#include "serial_ports.h"
#include <dbt.h>
#include <flutter/standard_method_codec.h>

namespace {
const GUID kComPort = {0x86e0d1e0, 0x8089, 0x11d0,
                       {0x9c, 0xe4, 0x08, 0x00, 0x3e, 0x30, 0x1f, 0x73}};
}  // namespace

SerialPorts::SerialPorts(HWND window, flutter::BinaryMessenger* messenger) {
  channel_ = std::make_unique<flutter::MethodChannel<flutter::EncodableValue>>(
      messenger, "clovecom/serial_ports", &flutter::StandardMethodCodec::GetInstance());
  DEV_BROADCAST_DEVICEINTERFACE_W filter = {};
  filter.dbcc_size = sizeof(filter);
  filter.dbcc_devicetype = DBT_DEVTYP_DEVICEINTERFACE;
  filter.dbcc_classguid = kComPort;
  notification_ = RegisterDeviceNotificationW(window, &filter, DEVICE_NOTIFY_WINDOW_HANDLE);
}
SerialPorts::~SerialPorts() {
  if (notification_) UnregisterDeviceNotification(notification_);
}
void SerialPorts::HandleMessage(UINT message, WPARAM wparam, LPARAM lparam) {
  if (message != WM_DEVICECHANGE) return;
  bool changed = wparam == DBT_DEVNODES_CHANGED;
  if ((wparam == DBT_DEVICEARRIVAL || wparam == DBT_DEVICEREMOVECOMPLETE) && lparam) {
    auto* header = reinterpret_cast<DEV_BROADCAST_HDR*>(lparam);
    if (header->dbch_devicetype == DBT_DEVTYP_DEVICEINTERFACE) {
      auto* device = reinterpret_cast<DEV_BROADCAST_DEVICEINTERFACE_W*>(lparam);
      changed = IsEqualGUID(device->dbcc_classguid, kComPort);
    }
  }
  // 事件仅提示重扫，不能据此直接增删候选项。
  if (changed) channel_->InvokeMethod("portsChanged", nullptr);
}
