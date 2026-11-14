#ifndef RUNNER_SERIAL_PORTS_H_
#define RUNNER_SERIAL_PORTS_H_
#include <windows.h>
#include <flutter/binary_messenger.h>
#include <flutter/method_channel.h>
#include <flutter/encodable_value.h>
#include <memory>

// 通道与系统通知跟随窗口生命周期。
class SerialPorts {
 public:
  SerialPorts(HWND window, flutter::BinaryMessenger* messenger);
  ~SerialPorts();
  void HandleMessage(UINT message, WPARAM wparam, LPARAM lparam);
 private:
  HDEVNOTIFY notification_ = nullptr;
  std::unique_ptr<flutter::MethodChannel<flutter::EncodableValue>> channel_;
};
#endif
