// 在 x64 Developer PowerShell 中用 cl /O2 /std:c++17 /EHsc /utf-8 编译。
// 使用一对互连的测试串口，例如 benchmark_native_serial COM9 COM10 6。
#define NOMINMAX
#define WIN32_LEAN_AND_MEAN
#include <windows.h>

#include <algorithm>
#include <array>
#include <atomic>
#include <chrono>
#include <cstdint>
#include <cwchar>
#include <functional>
#include <iostream>
#include <string>
#include <thread>
#include <vector>

namespace {

using Clock = std::chrono::steady_clock;
using namespace std::chrono_literals;
using Payload = std::vector<std::uint8_t>;
using HundredNanoseconds = std::chrono::duration<LONGLONG, std::ratio<1, 10000000>>;

const std::array<Payload, 2> kDefaultPayloads = {{
    {'1', '2', '3', '4', '5', '6', '7', '8', '9', '0'},
    {'A', 'B', 'C', 'D', 'E', 'F', 'G', 'H', 'I', 'J'},
}};

class Handle {
 public:
  explicit Handle(HANDLE handle) : handle_(handle) {}
  ~Handle() {
    if (valid()) CloseHandle(handle_);
  }
  Handle(const Handle&) = delete;
  Handle& operator=(const Handle&) = delete;
  bool valid() const {
    return handle_ != nullptr && handle_ != INVALID_HANDLE_VALUE;
  }
  HANDLE get() const { return handle_; }

 private:
  HANDLE handle_;
};

bool Configure(HANDLE port, DWORD baud_rate) {
  DCB config = {};
  config.DCBlength = sizeof(config);
  if (!GetCommState(port, &config)) return false;
  config.BaudRate = baud_rate;
  config.ByteSize = 8;
  config.Parity = NOPARITY;
  config.StopBits = ONESTOPBIT;
  config.fBinary = TRUE;
  config.fParity = FALSE;
  config.fOutxCtsFlow = FALSE;
  config.fOutxDsrFlow = FALSE;
  config.fDsrSensitivity = FALSE;
  config.fDtrControl = DTR_CONTROL_DISABLE;
  config.fRtsControl = RTS_CONTROL_DISABLE;
  config.fOutX = FALSE;
  config.fInX = FALSE;
  config.fErrorChar = FALSE;
  config.fNull = FALSE;
  config.fAbortOnError = FALSE;
  // 已缓冲的数据立即返回。空缓冲时等首字节，20 ms 后正常返回空。
  COMMTIMEOUTS timeouts = {MAXDWORD, MAXDWORD, 20, 0, 0};
  return SetCommState(port, &config) && SetCommTimeouts(port, &timeouts) &&
         PurgeComm(port, PURGE_RXCLEAR | PURGE_TXCLEAR);
}

DWORD Complete(HANDLE port, OVERLAPPED& operation, DWORD& count) {
  if (GetOverlappedResultEx(port, &operation, &count, 500, FALSE)) {
    return ERROR_SUCCESS;
  }
  const DWORD error = GetLastError();
  if (error == WAIT_TIMEOUT || error == ERROR_IO_INCOMPLETE ||
      error == ERROR_SUCCESS) {
    // Win32 超时和取消请求都不是终结证明。释放缓冲区前等这笔 I/O 终结。
    CancelIoEx(port, &operation);
    static_cast<void>(GetOverlappedResult(port, &operation, &count, TRUE));
    return ERROR_TIMEOUT;
  }
  return error;
}

std::uint8_t RoundByte(std::uint64_t round, std::size_t offset) {
  return static_cast<std::uint8_t>(round >> (offset * 8));
}

struct WriteStats {
  std::vector<long long> gaps;
  std::vector<long long> start_delays;
  std::vector<long long> write_durations;
  std::uint64_t bytes = 0;
  std::uint64_t skipped = 0;
  std::uint64_t skipped_before_confirmation = 0;
  std::uint64_t cpu_microseconds = 0;
  unsigned int peak_inflight = 0;
  DWORD error = ERROR_SUCCESS;
};

class PendingWrites {
 public:
  PendingWrites(HANDLE port, const Payload& payload, WriteStats& stats)
      : port_(port), stats_(stats), slots_{WriteSlot(payload), WriteSlot(payload)} {}

  ~PendingWrites() {
    // 任一提前退出路径都等待已提交请求终结，再释放缓冲区。
    for (auto& slot : slots_) {
      if (!slot.pending) continue;
      CancelIoEx(port_, &slot.operation);
      DWORD count = 0;
      GetOverlappedResult(port_, &slot.operation, &count, TRUE);
    }
  }

  bool valid() const {
    return slots_[0].event.valid() && slots_[1].event.valid();
  }

  unsigned int size() const { return size_; }

  bool front_ready() const {
    const auto& slot = slots_[head_];
    return size_ != 0 &&
           (slot.completed_inline ||
            WaitForSingleObject(slot.event.get(), 0) == WAIT_OBJECT_0);
  }

  bool Start(Clock::time_point started) {
    auto& slot = slots_[(head_ + size_) % slots_.size()];
    if (slot.bytes.size() >= 4) {
      for (std::size_t offset = 0; offset < 4; ++offset)
        slot.bytes[offset] = RoundByte(round_, offset);
    }
    slot.operation = {};
    slot.operation.hEvent = slot.event.get();
    slot.started = started;
    slot.completed_inline = WriteFile(port_, slot.bytes.data(),
                                      static_cast<DWORD>(slot.bytes.size()),
                                      nullptr, &slot.operation) != FALSE;
    if (!slot.completed_inline) {
      const auto error = GetLastError();
      if (error != ERROR_IO_PENDING && error != ERROR_SUCCESS) {
        stats_.error = error;
        return false;
      }
    }
    slot.pending = true;
    ++round_;
    ++size_;
    stats_.peak_inflight = std::max(stats_.peak_inflight, size_);
    return true;
  }

  bool FinishFront(Clock::time_point& confirmed) {
    auto& slot = slots_[head_];
    DWORD count = 0;
    stats_.error = Complete(port_, slot.operation, count);
    slot.pending = false;
    head_ = (head_ + 1) % slots_.size();
    --size_;
    if (stats_.error != ERROR_SUCCESS) return false;
    confirmed = Clock::now();
    stats_.write_durations.push_back(
        std::chrono::duration_cast<std::chrono::microseconds>(
            confirmed - slot.started).count());
    stats_.bytes += count;
    if (count != slot.bytes.size()) stats_.error = ERROR_WRITE_FAULT;
    return stats_.error == ERROR_SUCCESS;
  }

 private:
  struct WriteSlot {
    explicit WriteSlot(const Payload& payload) : bytes(payload) {}

    Handle event{CreateEventW(nullptr, TRUE, FALSE, nullptr)};
    Payload bytes;
    OVERLAPPED operation{};
    Clock::time_point started;
    bool pending = false;
    bool completed_inline = false;
  };

  HANDLE port_;
  WriteStats& stats_;
  std::array<WriteSlot, 2> slots_;
  std::size_t head_ = 0;
  unsigned int size_ = 0;
  std::uint64_t round_ = 0;
};

void WriteLoop(HANDLE port, const Payload& payload, Clock::time_point begin,
               Clock::time_point end, bool periodic,
               std::chrono::microseconds advance, bool above_normal,
               unsigned int max_inflight, WriteStats& stats) {
  if (above_normal &&
      !SetThreadPriority(GetCurrentThread(), THREAD_PRIORITY_ABOVE_NORMAL)) {
    stats.error = GetLastError();
    return;
  }
  Handle timer(CreateWaitableTimerExW(nullptr, nullptr,
                                      CREATE_WAITABLE_TIMER_HIGH_RESOLUTION,
                                      TIMER_MODIFY_STATE | SYNCHRONIZE));
  PendingWrites pending(port, payload, stats);
  if (!timer.valid() || !pending.valid()) {
    stats.error = ERROR_INVALID_HANDLE;
    return;
  }

  constexpr auto period = 1ms;
  const auto arm = [&](Clock::duration remaining, LONG period_ms) {
    LARGE_INTEGER due;
    due.QuadPart = -std::max<LONGLONG>(
        1, std::chrono::duration_cast<HundredNanoseconds>(remaining).count());
    if (SetWaitableTimer(timer.get(), &due, period_ms, nullptr, nullptr,
                         FALSE)) {
      return true;
    }
    stats.error = GetLastError();
    return false;
  };
  const auto wait = [&]() {
    if (WaitForSingleObject(timer.get(), INFINITE) == WAIT_OBJECT_0) return true;
    stats.error = ERROR_INVALID_HANDLE;
    return false;
  };
  if (periodic && !arm(begin - Clock::now(), 1)) return;
  Clock::time_point previous;
  Clock::time_point confirmed;
  for (auto next = begin; next < end;) {
    while (pending.size() == max_inflight || pending.front_ready()) {
      if (!pending.FinishFront(confirmed)) return;
    }
    // 同一个线程等待并提交写入。按绝对节拍安排，延误时跳过过期轮次。
    auto now = Clock::now();
    if (periodic) {
      if (!wait()) return;
      now = Clock::now();
      if (now < next) continue;
    } else {
      const auto wake = next - advance;
      while (now < wake) {
        if (!arm(wake - now, 0) || !wait()) return;
        now = Clock::now();
      }
      // 可选的提前唤醒实验。最多在配置的提前量内短暂轮询。
      while (now < next) {
        YieldProcessor();
        now = Clock::now();
      }
    }
    const auto missed = (std::min(now, end) - next) / period;
    stats.skipped += missed;
    // 区分上一笔写入确认前已过期的节拍与确认后才过期的节拍。
    if (confirmed > next) {
      stats.skipped_before_confirmation +=
          std::min(missed, std::chrono::ceil<std::chrono::milliseconds>(
                               confirmed - next).count());
    }
    if (now >= end) break;
    stats.start_delays.push_back(
        std::chrono::duration_cast<std::chrono::microseconds>(
            now - next - missed * period).count());
    next += (1 + missed) * period;
    if (previous != Clock::time_point()) {
      stats.gaps.push_back(
          std::chrono::duration_cast<std::chrono::microseconds>(now - previous)
              .count());
    }
    previous = now;

    while (pending.front_ready()) {
      if (!pending.FinishFront(confirmed)) return;
    }
    if (!pending.Start(now)) return;
  }
  while (pending.size() != 0) {
    if (!pending.FinishFront(confirmed)) return;
  }
  FILETIME created, exited, kernel, user;
  if (GetThreadTimes(GetCurrentThread(), &created, &exited, &kernel, &user)) {
    const auto ticks = [](FILETIME time) {
      return (static_cast<std::uint64_t>(time.dwHighDateTime) << 32) |
             time.dwLowDateTime;
    };
    stats.cpu_microseconds = (ticks(kernel) + ticks(user)) / 10;
  }
}

struct ReadStats {
  std::uint64_t bytes = 0;
  std::uint64_t wrong = 0;
  DWORD error = ERROR_SUCCESS;
};

void ReadLoop(HANDLE port, const Payload& expected,
              const std::atomic<bool>& writers_done, ReadStats& stats) {
  Handle complete(CreateEventW(nullptr, TRUE, FALSE, nullptr));
  if (!complete.valid()) {
    stats.error = GetLastError();
    return;
  }
  std::array<std::uint8_t, 16 * 1024> buffer;
  for (;;) {
    OVERLAPPED operation = {};
    operation.hEvent = complete.get();
    DWORD count = 0;
    if (!ReadFile(port, buffer.data(), static_cast<DWORD>(buffer.size()),
                  nullptr, &operation)) {
      const DWORD error = GetLastError();
      if (error != ERROR_IO_PENDING && error != ERROR_SUCCESS) {
        stats.error = error;
        return;
      }
    }
    stats.error = Complete(port, operation, count);
    if (stats.error != ERROR_SUCCESS) return;
    for (DWORD i = 0; i < count; ++i) {
      const auto offset = stats.bytes % expected.size();
      const auto value = expected.size() >= 4 && offset < 4
                             ? RoundByte(stats.bytes / expected.size(), offset)
                             : expected[offset];
      if (buffer[i] != value) ++stats.wrong;
      ++stats.bytes;
    }
    if (count == 0 && writers_done.load()) return;
  }
}

void PrintPercentiles(std::vector<long long>& samples) {
  if (samples.empty()) {
    std::cout << "-";
    return;
  }
  std::sort(samples.begin(), samples.end());
  for (const std::size_t rank : {50, 95, 99}) {
    if (rank != 50) std::cout << '/';
    std::cout << samples[(samples.size() * rank + 99) / 100 - 1];
  }
}

}  // namespace

int wmain(int argc, wchar_t** argv) {
  SetConsoleOutputCP(CP_UTF8);
  wchar_t* end_of_number = nullptr;
  const bool periodic = argc == 5 && std::wcscmp(argv[4], L"--periodic") == 0;
  const bool advance_requested =
      argc == 6 && std::wcscmp(argv[4], L"--advance-us") == 0;
  wchar_t priority[2] = {};
  const bool above_normal =
      GetEnvironmentVariableW(L"CLOVECOM_BENCH_ABOVE_NORMAL", priority, 2) == 1 &&
      priority[0] == L'1';
  wchar_t* end_of_advance = nullptr;
  const long advance =
      advance_requested ? std::wcstol(argv[5], &end_of_advance, 10) : 0;
  const long seconds = argc == 4 || periodic || advance_requested
                           ? std::wcstol(argv[3], &end_of_number, 10)
                           : 0;
  if (seconds < 1 || seconds > 600 || end_of_number == argv[3] ||
      *end_of_number != L'\0' || _wcsicmp(argv[1], argv[2]) == 0 ||
      (advance_requested && (end_of_advance == argv[5] ||
                             *end_of_advance != L'\0' ||
                             advance < 1 || advance > 900))) {
    std::cerr << "用法：benchmark_native_serial COM9 COM10 6 "
                 "[--periodic | --advance-us 350]\n";
    return 2;
  }
  const auto read_number = [](const wchar_t* key, unsigned long fallback,
                              unsigned long maximum) -> unsigned long {
    wchar_t value[16] = {};
    const DWORD length = GetEnvironmentVariableW(key, value, 16);
    if (length == 0) return fallback;
    if (length >= 16 || value[0] < L'0' || value[0] > L'9') return 0;
    wchar_t* end = nullptr;
    const auto number = std::wcstoul(value, &end, 10);
    return *end == L'\0' && number <= maximum ? number : 0;
  };
  const auto baud_rate = read_number(L"CLOVECOM_BENCH_BAUD", CBR_115200, 10000000);
  const auto payload_bytes = read_number(L"CLOVECOM_BENCH_PAYLOAD_BYTES", 10, 4096);
  const auto max_inflight = read_number(L"CLOVECOM_BENCH_INFLIGHT", 1, 2);
  if (baud_rate == 0 || payload_bytes == 0 || max_inflight == 0) {
    std::cerr << "基准波特率、载荷大小或在途上限无效\n";
    return 2;
  }
  auto payloads = kDefaultPayloads;
  if (payload_bytes != 10) {
    for (std::size_t direction = 0; direction < payloads.size(); ++direction) {
      auto& payload = payloads[direction];
      payload.resize(payload_bytes);
      for (std::size_t offset = 0; offset < payload.size(); ++offset) {
        payload[offset] = static_cast<std::uint8_t>(
            (offset * 131 + direction * 97 + offset / 256) & 0xff);
      }
    }
  }
  std::cout << baud_rate << " 波特，每轮 " << payload_bytes
            << " 字节，在途上限 " << max_inflight << '\n';
  const auto open = [](const wchar_t* name) {
    const auto path = std::wstring(L"\\\\.\\") + name;
    return CreateFileW(path.c_str(), GENERIC_READ | GENERIC_WRITE, 0, nullptr,
                       OPEN_EXISTING, FILE_FLAG_OVERLAPPED, nullptr);
  };
  Handle first(open(argv[1]));
  if (!first.valid() || !Configure(first.get(), baud_rate)) {
    std::cerr << "打开或配置第一个测试端口失败：" << GetLastError() << '\n';
    return 1;
  }
  Handle second(open(argv[2]));
  if (!second.valid() || !Configure(second.get(), baud_rate)) {
    std::cerr << "打开或配置第二个测试端口失败：" << GetLastError() << '\n';
    return 1;
  }
  std::array<HANDLE, 2> ports = {first.get(), second.get()};
  std::array<ReadStats, 2> input;
  std::array<WriteStats, 2> output;
  std::array<std::thread, 2> readers, writers;
  std::atomic<bool> writers_done = false;
  const auto begin = Clock::now() + 250ms;
  // 可选地错开第二个发送线程，用相同的测量时长比较双向争用。
  wchar_t stagger_env[2] = {};
  const bool stagger =
      GetEnvironmentVariableW(L"CLOVECOM_BENCH_STAGGER", stagger_env, 2) == 1 &&
      stagger_env[0] == L'1';
  for (std::size_t i = 0; i < ports.size(); ++i) {
    const auto slots = static_cast<std::size_t>(seconds) * 1000;
    output[i].start_delays.reserve(slots);
    output[i].gaps.reserve(slots);
    output[i].write_durations.reserve(slots);
    readers[i] = std::thread(ReadLoop, ports[i], std::cref(payloads[1 - i]),
                             std::cref(writers_done), std::ref(input[i]));
    const auto start = begin + (i == 1 && stagger ? 500us : 0us);
    writers[i] = std::thread(WriteLoop, ports[i], std::cref(payloads[i]), start,
                             start + std::chrono::seconds(seconds), periodic,
                             std::chrono::microseconds(advance),
                             above_normal, static_cast<unsigned int>(max_inflight),
                             std::ref(output[i]));
  }
  for (auto& thread : writers) thread.join();
  writers_done.store(true);
  for (auto& thread : readers) thread.join();

  bool matched = true;
  for (std::size_t i = 0; i < ports.size(); ++i) {
    const auto& rx = input[1 - i];
    auto& tx = output[i];
    std::cout << 'P' << i + 1 << ' '
              << static_cast<double>(tx.bytes) / payloads[i].size() / seconds
              << " 轮/秒，漏拍 " << tx.skipped
              << "（写入确认前 " << tx.skipped_before_confirmation
              << "，其余 " << tx.skipped - tx.skipped_before_confirmation
              << "），发起间隔 P50/P95/P99 ";
    PrintPercentiles(tx.gaps);
    std::cout << " us，相对节拍的发起延迟 P50/P95/P99 ";
    PrintPercentiles(tx.start_delays);
    std::cout << " us，写入至观察到确认 P50/P95/P99 ";
    PrintPercentiles(tx.write_durations);
    std::cout << " us，最大在途 " << tx.peak_inflight << "，发送线程 CPU "
              << static_cast<double>(tx.cpu_microseconds) / seconds / 10000
              << "%，确认 " << tx.bytes << " 字节，对端收到 " << rx.bytes
              << " 字节，内容错位 " << rx.wrong << "，写错误 " << tx.error
              << "，读错误 " << rx.error << '\n';
    matched &= tx.error == ERROR_SUCCESS && rx.error == ERROR_SUCCESS &&
               tx.bytes != 0 && tx.bytes == rx.bytes && rx.wrong == 0 &&
               tx.bytes / payloads[i].size() + tx.skipped ==
                   static_cast<std::uint64_t>(seconds) * 1000;
  }
  return matched ? 0 : 1;
}
