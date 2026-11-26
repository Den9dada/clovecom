#include "native_serial_loop.h"

#include <process.h>
#include <windows.h>

#include <algorithm>
#include <array>
#include <atomic>
#include <chrono>
#include <cstdint>
#include <cstring>
#include <memory>
#include <new>
#include <utility>

namespace {

using Clock = std::chrono::steady_clock;
using namespace std::chrono_literals;
using HundredNs = std::chrono::duration<LONGLONG, std::ratio<1, 10000000>>;
constexpr int kCapacity = 128;
// 只在经基准验证的最后 350 微秒内轮询。
constexpr auto kWakeLead = 350us;

class Handle {
 public:
  explicit Handle(HANDLE value) : value_(value) {}
  ~Handle() {
    if (value_) CloseHandle(value_);
  }
  Handle(const Handle&) = delete;
  Handle& operator=(const Handle&) = delete;
  HANDLE get() const { return value_; }
  bool valid() const { return value_ != nullptr; }

 private:
  HANDLE value_;
};

// 草稿仅在内容变化时分配，每轮写及回执共同持有该版本。
struct Draft {
  explicit Draft(unsigned int size)
      : length(size), bytes(new (std::nothrow) unsigned char[size]) {}

  std::atomic_uint references{1};
  const unsigned int length;
  const std::unique_ptr<unsigned char[]> bytes;
  unsigned long long version = 0;
};

struct ReleaseDraft {
  void operator()(Draft* draft) const {
    if (draft->references.fetch_sub(1, std::memory_order_acq_rel) == 1)
      delete draft;
  }
};

using DraftRef = std::unique_ptr<Draft, ReleaseDraft>;

struct Round {
  DraftRef draft;
  CloveSerialRound result{};
};

struct Loop {
  Loop(HANDLE owner, std::chrono::microseconds interval, DWORD timeout,
       bool immediate)
      : port(owner),
        period(interval),
        timeout_ms(timeout),
        next(Clock::now() + (immediate ? 0us : interval)) {}

  const HANDLE port;
  const std::chrono::microseconds period;
  const DWORD timeout_ms;
  Clock::time_point next;
  const Handle stop{CreateEventW(nullptr, TRUE, FALSE, nullptr)};
  const Handle cancel{CreateEventW(nullptr, TRUE, FALSE, nullptr)};
  const Handle changed{CreateEventW(nullptr, FALSE, FALSE, nullptr)};
  const Handle rounds_ready{CreateEventW(nullptr, FALSE, FALSE, nullptr)};
  const Handle completion{CreateEventW(nullptr, TRUE, FALSE, nullptr)};
  const Handle timer{CreateWaitableTimerExW(
      nullptr, nullptr, CREATE_WAITABLE_TIMER_HIGH_RESOLUTION,
      TIMER_MODIFY_STATE | SYNCHRONIZE)};
  HANDLE thread = nullptr;

  SRWLOCK lock = SRWLOCK_INIT;
  DraftRef draft;
  unsigned long long next_version = 0;
  std::array<Round, kCapacity> rounds;
  // 读出的回执仍持有草稿，直到下次读取，期间 Dart 可以同步复制。
  std::array<DraftRef, kCapacity> drained;
  int drained_count = 0;
  int head = 0, size = 0;
  CloveSerialLoopStatus status{};

  bool SetDraft(const unsigned char* bytes, unsigned int length) {
    DraftRef next_draft;
    if (length != 0) {
      next_draft.reset(new (std::nothrow) Draft(length));
      if (!next_draft || !next_draft->bytes) return false;
      std::memcpy(next_draft->bytes.get(), bytes, length);
    }
    AcquireSRWLockExclusive(&lock);
    if (next_draft) next_draft->version = ++next_version;
    draft = std::move(next_draft);
    ReleaseSRWLockExclusive(&lock);
    return true;
  }

  bool Prepare(Round* round = nullptr) {
    AcquireSRWLockShared(&lock);
    const bool ready = draft && size != kCapacity;
    if (ready && round) {
      draft->references.fetch_add(1, std::memory_order_relaxed);
      round->draft.reset(draft.get());
      round->result.length = draft->length;
      round->result.draft_version = draft->version;
      round->result.bytes = draft->bytes.get();
    }
    ReleaseSRWLockShared(&lock);
    return ready;
  }

  void Record(Round&& round, long long missed) {
    AcquireSRWLockExclusive(&lock);
    rounds[(head + size) % kCapacity] = std::move(round);
    ++size;
    // 每毫秒发送时合并两笔回执，减少跨线程唤醒。
    const bool notify = size == (period <= 2ms ? 2 : 1);
    status.skipped += missed;
    ReleaseSRWLockExclusive(&lock);
    if (notify && rounds_ready.valid()) SetEvent(rounds_ready.get());
  }

  void Finish(DWORD error) {
    AcquireSRWLockExclusive(&lock);
    if (error) status.error = error;
    status.done = 1;
    ReleaseSRWLockExclusive(&lock);
    if (rounds_ready.valid()) SetEvent(rounds_ready.get());
  }

  void FailDraftUpdate() {
    AcquireSRWLockExclusive(&lock);
    if (!status.done) status.error = ERROR_NOT_ENOUGH_MEMORY;
    ReleaseSRWLockExclusive(&lock);
    SetEvent(stop.get());
  }
};

DWORD Probe(HANDLE port, OVERLAPPED& operation, DWORD& count) {
  if (GetOverlappedResult(port, &operation, &count, FALSE))
    return ERROR_SUCCESS;
  auto error = GetLastError();
  if (error == ERROR_SUCCESS) {
    // FALSE+0 仍查询同一笔写，绝不重新提交。
    if (GetOverlappedResultEx(port, &operation, &count, 0, FALSE))
      return ERROR_SUCCESS;
    error = GetLastError();
  }
  if (error == ERROR_SUCCESS || error == ERROR_INVALID_HANDLE ||
      error == ERROR_INVALID_PARAMETER)
    return ERROR_IO_INCOMPLETE;
  return error;
}

void Write(Loop& loop, CloveSerialRound& round) {
  const auto deadline =
      Clock::now() + std::chrono::milliseconds(loop.timeout_ms);
  OVERLAPPED operation = {};
  operation.hEvent = loop.completion.get();
  round.accepted = -1;
  if (!WriteFile(loop.port, round.bytes, round.length, nullptr, &operation)) {
    const DWORD error = GetLastError();
    if (error != ERROR_IO_PENDING && error != ERROR_SUCCESS) {
      round.error = error;
      return;
    }
  }

  DWORD count = 0;
  DWORD ending = ERROR_SUCCESS;
  const HANDLE signals[] = {loop.cancel.get(), loop.completion.get()};
  auto error = Probe(loop.port, operation, count);
  while (error == ERROR_IO_INCOMPLETE) {
    const auto remaining = deadline - Clock::now();
    if (ending == ERROR_SUCCESS) {
      const DWORD waited =
          remaining > 0ms
              ? WaitForMultipleObjects(
                    2, signals, FALSE,
                    static_cast<DWORD>(
                        std::chrono::ceil<std::chrono::milliseconds>(remaining)
                            .count()))
              : WAIT_TIMEOUT;
      if (waited != WAIT_OBJECT_0 + 1) {
        ending =
            waited == WAIT_OBJECT_0 ? ERROR_OPERATION_ABORTED : ERROR_TIMEOUT;
        CancelIoEx(loop.port, &operation);
      }
    } else {
      // 超时/取消后仍须等到原生终态，才能释放缓冲区并交还串口。
      WaitForSingleObject(loop.completion.get(), 1);
    }
    error = Probe(loop.port, operation, count);
    if (error == ERROR_IO_INCOMPLETE &&
        WaitForSingleObject(loop.completion.get(), 0) == WAIT_OBJECT_0)
      Sleep(1);
  }

  if (error == ERROR_SUCCESS && count <= round.length) {
    round.accepted = static_cast<int>(count);
  } else if (error == ERROR_SUCCESS) {
    error = ERROR_INVALID_DATA;
  }
  if (ending != ERROR_SUCCESS) {
    round.error = ending;
  } else if (error == ERROR_SUCCESS && Clock::now() >= deadline) {
    round.error = ERROR_TIMEOUT;
  } else {
    round.error = error;
  }
}

DWORD Run(Loop& loop) {
  const HANDLE setup[] = {loop.stop.get(), loop.changed.get()};
  const HANDLE timing[] = {loop.stop.get(), loop.timer.get()};
  while (WaitForSingleObject(loop.stop.get(), 0) != WAIT_OBJECT_0) {
    if (!loop.Prepare()) {
      const auto signal = WaitForMultipleObjects(2, setup, FALSE, INFINITE);
      if (signal == WAIT_OBJECT_0) return ERROR_SUCCESS;
      if (signal != WAIT_OBJECT_0 + 1) return GetLastError();
      continue;
    }

    auto now = Clock::now();
    const auto wake = loop.next - kWakeLead;
    while (now < wake) {
      LARGE_INTEGER due;
      due.QuadPart = -std::max<LONGLONG>(
          1, std::chrono::duration_cast<HundredNs>(wake - now).count());
      if (!SetWaitableTimer(loop.timer.get(), &due, 0, nullptr, nullptr, FALSE))
        return GetLastError();
      const auto signal = WaitForMultipleObjects(2, timing, FALSE, INFINITE);
      if (signal == WAIT_OBJECT_0) return ERROR_SUCCESS;
      if (signal != WAIT_OBJECT_0 + 1) return GetLastError();
      now = Clock::now();
    }
    while (now < loop.next) {
      YieldProcessor();
      now = Clock::now();
    }

    Round round;
    auto& result = round.result;
    if (WaitForSingleObject(loop.stop.get(), 0) == WAIT_OBJECT_0) break;
    if (!loop.Prepare(&round)) continue;
    const auto missed = (Clock::now() - loop.next) / loop.period;
    loop.next += (missed + 1) * loop.period;
    Write(loop, result);

    FILETIME stamp;
    GetSystemTimePreciseAsFileTime(&stamp);
    const auto ticks =
        (static_cast<std::uint64_t>(stamp.dwHighDateTime) << 32) |
        stamp.dwLowDateTime;
    result.timestamp_micros =
        static_cast<long long>(ticks / 10) - 11644473600000000LL;
    const bool failed = result.error ||
        result.accepted != static_cast<int>(result.length);
    loop.Record(std::move(round), missed);
    if (failed) break;
  }
  return ERROR_SUCCESS;
}

unsigned __stdcall ThreadMain(void* context) {
  auto& loop = *static_cast<Loop*>(context);
  loop.Finish(Run(loop));
  return 0;
}

}  // namespace

void* CloveSerialLoopStartTimed(void* port, const unsigned char* bytes,
                                unsigned int length, unsigned int period_us,
                                unsigned int timeout_ms, int immediate) {
  if (!port || length > CLOVESERIAL_LOOP_MAX_PAYLOAD || period_us < 1000 ||
      period_us > 20000)
    return nullptr;
  auto* loop = new (std::nothrow) Loop(
      port, std::chrono::microseconds(period_us), timeout_ms, immediate != 0);
  if (!loop) return nullptr;
  if (loop->stop.valid() && loop->cancel.valid() && loop->changed.valid() &&
      loop->completion.valid() && loop->timer.valid() &&
      loop->SetDraft(bytes, length)) {
    loop->thread = reinterpret_cast<HANDLE>(
        _beginthreadex(nullptr, 0, ThreadMain, loop, 0, nullptr));
    if (loop->thread) return loop;
  }
  delete loop;
  return nullptr;
}

void CloveSerialLoopUpdate(void* context, const unsigned char* bytes,
                           unsigned int length) {
  auto& loop = *static_cast<Loop*>(context);
  if (length > CLOVESERIAL_LOOP_MAX_PAYLOAD) return;
  if (loop.SetDraft(bytes, length)) {
    SetEvent(loop.changed.get());
  } else {
    loop.FailDraftUpdate();
  }
}

void* CloveSerialLoopRoundsReady(void* context) {
  return static_cast<Loop*>(context)->rounds_ready.get();
}

int CloveSerialLoopDrainShared(void* context, CloveSerialRound* rounds,
                               int limit, CloveSerialLoopStatus* status) {
  auto& loop = *static_cast<Loop*>(context);
  AcquireSRWLockExclusive(&loop.lock);
  const int count = std::min(loop.size, limit);
  const bool resume = loop.size == kCapacity && count > 0;
  for (int index = 0; index < count; ++index) {
    auto& round = loop.rounds[(loop.head + index) % kCapacity];
    loop.drained[index] = std::move(round.draft);
    rounds[index] = round.result;
  }
  for (int index = count; index < loop.drained_count; ++index)
    loop.drained[index].reset();
  loop.drained_count = count;
  loop.head = (loop.head + count) % kCapacity;
  loop.size -= count;
  *status = loop.status;
  ReleaseSRWLockExclusive(&loop.lock);
  // 只有满队列会让写线程等回执消费；正常批次无需发出内核事件。
  if (resume) SetEvent(loop.changed.get());
  return count;
}

void CloveSerialLoopStop(void* context, int cancel_in_flight) {
  auto& loop = *static_cast<Loop*>(context);
  SetEvent(loop.stop.get());
  if (cancel_in_flight) SetEvent(loop.cancel.get());
}

void CloveSerialLoopRelease(void* context) {
  auto* loop = static_cast<Loop*>(context);
  WaitForSingleObject(loop->thread, INFINITE);
  CloseHandle(loop->thread);
  delete loop;
}
