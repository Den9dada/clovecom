#ifndef CLOVECOM_NATIVE_SERIAL_LOOP_H
#define CLOVECOM_NATIVE_SERIAL_LOOP_H

#ifdef _WIN32
#define CLOVECOM_SERIAL_EXPORT __declspec(dllexport)
#else
#define CLOVECOM_SERIAL_EXPORT
#endif

#ifdef __cplusplus
extern "C" {
#endif

#define CLOVESERIAL_LOOP_MAX_PAYLOAD 4096

typedef struct CloveSerialRound {
  long long timestamp_micros;
  unsigned int length;
  int accepted;
  unsigned int error;
  unsigned long long draft_version;
  const unsigned char* bytes;
} CloveSerialRound;

typedef struct CloveSerialLoopStatus {
  long long skipped;
  unsigned int error;
  int done;
} CloveSerialLoopStatus;

CLOVECOM_SERIAL_EXPORT void* CloveSerialLoopStartTimed(
    void* port, const unsigned char* bytes, unsigned int length,
    unsigned int period_us, unsigned int timeout_ms, int immediate);
CLOVECOM_SERIAL_EXPORT void CloveSerialLoopUpdate(void* context,
                                                  const unsigned char* bytes,
                                                  unsigned int length);
// 事件句柄由循环持有，释放循环前须先撤销等待。
CLOVECOM_SERIAL_EXPORT void* CloveSerialLoopRoundsReady(void* context);
// 回执负载只借给调用方，直到同一个循环下一次读取回执或释放。
CLOVECOM_SERIAL_EXPORT int CloveSerialLoopDrainShared(
    void* context, CloveSerialRound* rounds, int limit,
    CloveSerialLoopStatus* status);
CLOVECOM_SERIAL_EXPORT void CloveSerialLoopStop(void* context,
                                                int cancel_in_flight);
CLOVECOM_SERIAL_EXPORT void CloveSerialLoopRelease(void* context);

#ifdef __cplusplus
}
#endif
#endif
