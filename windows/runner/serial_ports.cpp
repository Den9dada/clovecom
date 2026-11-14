#include "serial_ports.h"
#include <dbt.h>
#include <setupapi.h>
#include <flutter/standard_method_codec.h>
#include <algorithm>
#include <map>
#include <stdexcept>
#include <string>
#include <vector>

namespace {
const GUID kComPort = {0x86e0d1e0, 0x8089, 0x11d0,
                       {0x9c, 0xe4, 0x08, 0x00, 0x3e, 0x30, 0x1f, 0x73}};
bool IsPort(const std::wstring& name) {
  return name.size() > 3 && name.substr(0, 3) == L"COM" &&
      std::all_of(name.begin() + 3, name.end(), [](wchar_t c) {
        return c >= L'0' && c <= L'9';
      });
}
std::string Utf8(const std::wstring& text) {
  if (text.empty()) return {};
  const int size = WideCharToMultiByte(CP_UTF8, 0, text.data(),
      static_cast<int>(text.size()), nullptr, 0, nullptr, nullptr);
  std::string result(size, '\0');
  WideCharToMultiByte(CP_UTF8, 0, text.data(), static_cast<int>(text.size()),
      result.data(), size, nullptr, nullptr);
  return result;
}
flutter::EncodableList EnumeratePorts() {
  std::map<std::wstring, std::wstring> ports;
  std::vector<wchar_t> buffer(65536);
  while (!QueryDosDeviceW(nullptr, buffer.data(), static_cast<DWORD>(buffer.size()))) {
    if (GetLastError() != ERROR_INSUFFICIENT_BUFFER || buffer.size() >= 1048576)
      throw std::runtime_error("QueryDosDeviceW failed");
    buffer.resize(buffer.size() * 2);
  }
  for (const wchar_t* item = buffer.data(); *item; item += wcslen(item) + 1) {
    if (IsPort(item)) ports[item] = item;
  }
  HDEVINFO devices = SetupDiGetClassDevsW(nullptr, nullptr, nullptr,
                                        DIGCF_PRESENT | DIGCF_ALLCLASSES);
  if (devices == INVALID_HANDLE_VALUE)
    throw std::runtime_error("SetupDiGetClassDevsW failed");
  SP_DEVINFO_DATA info = {};
  info.cbSize = sizeof(info);
  DWORD enumeration_error = ERROR_SUCCESS;
  for (DWORD index = 0;; ++index) {
    if (!SetupDiEnumDeviceInfo(devices, index, &info)) {
      enumeration_error = GetLastError();
      break;
    }
    HKEY key = SetupDiOpenDevRegKey(devices, &info, DICS_FLAG_GLOBAL, 0,
                                    DIREG_DEV, KEY_QUERY_VALUE);
    if (key == INVALID_HANDLE_VALUE) continue;
    wchar_t port[256] = {};
    DWORD bytes = sizeof(port), type = 0;
    const auto status = RegQueryValueExW(key, L"PortName", nullptr, &type,
                                       reinterpret_cast<BYTE*>(port), &bytes);
    RegCloseKey(key);
    port[255] = 0;
    if (status != ERROR_SUCCESS || type != REG_SZ || !IsPort(port)) continue;
    wchar_t description[2048] = {};
    if (SetupDiGetDeviceRegistryPropertyW(devices, &info, SPDRP_FRIENDLYNAME,
        nullptr, reinterpret_cast<BYTE*>(description), sizeof(description), nullptr)) {
      description[2047] = 0;
      ports[port] = description;
    } else if (ports.find(port) == ports.end()) {
      ports[port] = port;
    }
  }
  SetupDiDestroyDeviceInfoList(devices);
  if (enumeration_error != ERROR_NO_MORE_ITEMS)
    throw std::runtime_error("SetupDiEnumDeviceInfo failed");
  flutter::EncodableList result;
  for (const auto& entry : ports) {
    result.emplace_back(flutter::EncodableMap{
      {flutter::EncodableValue("port"), flutter::EncodableValue(Utf8(entry.first))},
      {flutter::EncodableValue("description"), flutter::EncodableValue(Utf8(entry.second))}});
  }
  return result;
}
}  // namespace

SerialPorts::SerialPorts(HWND window, flutter::BinaryMessenger* messenger) {
  channel_ = std::make_unique<flutter::MethodChannel<flutter::EncodableValue>>(
      messenger, "clovecom/serial_ports", &flutter::StandardMethodCodec::GetInstance());
  channel_->SetMethodCallHandler([](const auto& call, auto result) {
    if (call.method_name() != "listPorts") { result->NotImplemented(); return; }
    try { result->Success(flutter::EncodableValue(EnumeratePorts())); }
    catch (const std::exception& error) { result->Error("scan_failed", error.what()); }
  });
  DEV_BROADCAST_DEVICEINTERFACE_W filter = {};
  filter.dbcc_size = sizeof(filter);
  filter.dbcc_devicetype = DBT_DEVTYP_DEVICEINTERFACE;
  filter.dbcc_classguid = kComPort;
  notification_ = RegisterDeviceNotificationW(window, &filter, DEVICE_NOTIFY_WINDOW_HANDLE);
}
SerialPorts::~SerialPorts() {
  if (notification_) UnregisterDeviceNotification(notification_);
  channel_->SetMethodCallHandler(nullptr);
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
