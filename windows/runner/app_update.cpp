#include "app_update.h"

#include <appmodel.h>
#include <flutter/standard_method_codec.h>
#include <shellapi.h>

#include <regex>
#include <string>
#include <vector>

namespace {
std::string Utf8(const wchar_t* value) {
  if (value == nullptr || *value == L'\0') return {};
  const int count = WideCharToMultiByte(CP_UTF8, 0, value, -1, nullptr, 0,
                                        nullptr, nullptr);
  if (count <= 0) return {};
  std::string text(count, '\0');
  WideCharToMultiByte(CP_UTF8, 0, value, -1, text.data(), count, nullptr,
                      nullptr);
  text.resize(count - 1);
  return text;
}

std::wstring Wide(const std::string& value) {
  const int count = MultiByteToWideChar(CP_UTF8, MB_ERR_INVALID_CHARS,
                                        value.data(),
                                        static_cast<int>(value.size()), nullptr,
                                        0);
  if (count <= 0) return {};
  std::wstring text(count, L'\0');
  MultiByteToWideChar(CP_UTF8, MB_ERR_INVALID_CHARS, value.data(),
                      static_cast<int>(value.size()), text.data(), count);
  return text;
}
}  // namespace

std::unique_ptr<flutter::MethodChannel<flutter::EncodableValue>>
CreateAppUpdateChannel(flutter::BinaryMessenger* messenger, HWND window) {
  auto channel =
      std::make_unique<flutter::MethodChannel<flutter::EncodableValue>>(
          messenger, "clovecom/app_update",
          &flutter::StandardMethodCodec::GetInstance());
  channel->SetMethodCallHandler([window](const auto& call, auto result) {
    if (call.method_name() == "getInfo") {
      UINT32 size = 0;
      const LONG status = GetCurrentPackageId(&size, nullptr);
      if (status != APPMODEL_ERROR_NO_PACKAGE &&
          status != ERROR_INSUFFICIENT_BUFFER) {
        result->Error("version_failed", "无法读取 Windows 包身份。");
        return;
      }
      const bool packaged = status == ERROR_INSUFFICIENT_BUFFER;
      std::string version = std::to_string(FLUTTER_VERSION_MAJOR) + "." +
                            std::to_string(FLUTTER_VERSION_MINOR) + "." +
                            std::to_string(FLUTTER_VERSION_PATCH) + "." +
                            std::to_string(FLUTTER_VERSION_BUILD);
      flutter::EncodableMap info{
          {flutter::EncodableValue("packaged"),
           flutter::EncodableValue(packaged)},
          {flutter::EncodableValue("name"),
           flutter::EncodableValue("CloveCOM.Desktop")}};
      if (packaged) {
        std::vector<BYTE> buffer(size);
        if (GetCurrentPackageId(&size, buffer.data()) != ERROR_SUCCESS) {
          result->Error("version_failed", "无法读取已安装版本。");
          return;
        }
        const auto* id = reinterpret_cast<const PACKAGE_ID*>(buffer.data());
        version = std::to_string(id->version.Major) + "." +
                  std::to_string(id->version.Minor) + "." +
                  std::to_string(id->version.Build) + "." +
                  std::to_string(id->version.Revision);
        info[flutter::EncodableValue("name")] =
            flutter::EncodableValue(Utf8(id->name));
        info[flutter::EncodableValue("publisher")] =
            flutter::EncodableValue(Utf8(id->publisher));
      }
      info[flutter::EncodableValue("version")] =
          flutter::EncodableValue(version);
      result->Success(flutter::EncodableValue(info));
      return;
    }

    std::wstring target;
    std::wstring parameters;
    if (call.method_name() == "openReleasePage") {
      target = L"https://github.com/Den9dada/clovecom/releases/latest";
    } else if (call.method_name() == "openInstaller") {
      const auto* path = call.arguments() == nullptr
                             ? nullptr
                             : std::get_if<std::string>(call.arguments());
      if (path == nullptr) {
        result->Error("invalid_path", "缺少安装清单路径。");
        return;
      }
      target = Wide(*path);
      const std::wstring suffix = L"\\CloveCOM.appinstaller";
      // Dart 写入的临时清单使用正斜杠，Windows Shell 两种分隔符均支持。
      for (auto& character : target) {
        if (character == L'/') character = L'\\';
      }
      if (target.size() <= suffix.size() ||
          target.compare(target.size() - suffix.size(), suffix.size(),
                         suffix) != 0 ||
          GetFileAttributesW(target.c_str()) == INVALID_FILE_ATTRIBUTES) {
        result->Error("invalid_path", "安装清单文件不可用。");
        return;
      }
    } else if (call.method_name() == "runSetup") {
      const auto* path = call.arguments() == nullptr
                             ? nullptr
                             : std::get_if<std::string>(call.arguments());
      if (path == nullptr) {
        result->Error("invalid_path", "缺少更新安装包路径。");
        return;
      }
      target = Wide(*path);
      for (auto& character : target) {
        if (character == L'/') character = L'\\';
      }
      const std::wregex suffix(
          L"\\\\CloveCOM-[0-9]+\\.[0-9]+\\.[0-9]+\\.[0-9]+-windows-x64-setup\\.exe$");
      const DWORD attributes = GetFileAttributesW(target.c_str());
      if (!std::regex_search(target, suffix) ||
          target.find(L"\\clovecom-update-") == std::wstring::npos ||
          attributes == INVALID_FILE_ATTRIBUTES ||
          (attributes & FILE_ATTRIBUTE_DIRECTORY) != 0) {
        result->Error("invalid_path", "更新安装包不可用。");
        return;
      }
      std::vector<wchar_t> executable(32768);
      const DWORD length = GetModuleFileNameW(
          nullptr, executable.data(), static_cast<DWORD>(executable.size()));
      if (length == 0 || length >= executable.size()) {
        result->Error("path_failed", "无法确定当前应用目录。");
        return;
      }
      const std::wstring current(executable.data(), length);
      const auto separator = current.find_last_of(L"\\");
      const std::wstring directory = current.substr(0, separator);
      // 自解压单 EXE 的工作目录会在退出时删除，不能在该目录覆盖更新。
      wchar_t temporary[MAX_PATH + 1] = {};
      GetTempPathW(MAX_PATH, temporary);
      const std::wstring temp(temporary);
      if (!temp.empty() && directory.size() >= temp.size() &&
          _wcsnicmp(directory.c_str(), temp.c_str(), temp.size()) == 0) {
        result->Error(
            "temporary_app",
            "当前为临时目录运行的便携版，请先下载安装版后使用重启更新。");
        return;
      }
      // /D 必须置于最后且不加引号，以保留含空格和中文的原目录。
      parameters = L"/S /INPLACE /RESTART /UPDATEPID=" +
                   std::to_wstring(GetCurrentProcessId()) + L" /D=" +
                   directory;
    } else {
      result->NotImplemented();
      return;
    }
    const auto status = reinterpret_cast<INT_PTR>(ShellExecuteW(
        window, L"open", target.c_str(),
        parameters.empty() ? nullptr : parameters.c_str(), nullptr,
        call.method_name() == "runSetup" ? SW_HIDE : SW_SHOWNORMAL));
    if (status <= 32) {
      result->Error("open_failed", "无法打开系统安装器或浏览器。",
                    flutter::EncodableValue(static_cast<int>(status)));
      return;
    }
    result->Success();
  });
  return channel;
}
