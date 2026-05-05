#include "utils.h"

#include <flutter_windows.h>
#include <io.h>
#include <stdio.h>
#include <windows.h>

#include <fstream>
#include <iostream>
#include <sstream>

namespace {

std::wstring GetStartupLogPath() {
  wchar_t temp_path[MAX_PATH];
  DWORD temp_length = ::GetTempPathW(MAX_PATH, temp_path);
  if (temp_length > 0 && temp_length < MAX_PATH) {
    return std::wstring(temp_path) + L"clovecom_startup_error.log";
  }
  return L"clovecom_startup_error.log";
}

bool PathExists(const wchar_t* path) {
  return ::GetFileAttributesW(path) != INVALID_FILE_ATTRIBUTES;
}

}  // namespace

void CreateAndAttachConsole() {
  if (::AllocConsole()) {
    FILE *unused;
    if (freopen_s(&unused, "CONOUT$", "w", stdout)) {
      _dup2(_fileno(stdout), 1);
    }
    if (freopen_s(&unused, "CONOUT$", "w", stderr)) {
      _dup2(_fileno(stdout), 2);
    }
    std::ios::sync_with_stdio();
    FlutterDesktopResyncOutputStreams();
  }
}

void LogStartupEvent(const wchar_t* message) {
  std::wofstream log_file(GetStartupLogPath(), std::ios::app);
  if (!log_file.is_open()) {
    return;
  }

  SYSTEMTIME now;
  ::GetLocalTime(&now);
  log_file << L"[" << now.wYear << L"-" << now.wMonth << L"-" << now.wDay
           << L" " << now.wHour << L":" << now.wMinute << L":" << now.wSecond
           << L"] " << (message == nullptr ? L"(null)" : message) << L"\n";
}

void SetCurrentDirectoryToExecutablePath() {
  wchar_t executable_path[MAX_PATH];
  DWORD length = ::GetModuleFileNameW(nullptr, executable_path, MAX_PATH);
  if (length == 0 || length == MAX_PATH) {
    return;
  }

  wchar_t* last_separator = wcsrchr(executable_path, L'\\');
  if (last_separator == nullptr) {
    return;
  }

  *last_separator = L'\0';
  ::SetCurrentDirectoryW(executable_path);
}

bool ValidateFlutterRuntimeFiles() {
  const wchar_t* required_paths[] = {
      L"flutter_windows.dll",
      L"data",
      L"data\\icudtl.dat",
      L"data\\flutter_assets",
  };

  std::wstringstream missing;
  for (const wchar_t* path : required_paths) {
    if (!PathExists(path)) {
      missing << L" - " << path << L"\r\n";
    }
  }

  if (!PathExists(L"data\\app.so") &&
      !PathExists(L"data\\flutter_assets\\kernel_blob.bin")) {
    missing << L" - data\\app.so or data\\flutter_assets\\kernel_blob.bin"
            << L"\r\n";
  }

  std::wstring missing_text = missing.str();
  if (missing_text.empty()) {
    LogStartupEvent(L"Flutter runtime files are visible");
    return true;
  }

  std::wstring log_path = GetStartupLogPath();

  std::wofstream log_file(log_path, std::ios::app);
  if (log_file.is_open()) {
    wchar_t current_directory[MAX_PATH];
    DWORD current_length = ::GetCurrentDirectoryW(MAX_PATH, current_directory);
    log_file << L"CloveCom startup failed because required Flutter runtime "
                L"files were not visible.\n";
    if (current_length > 0 && current_length < MAX_PATH) {
      log_file << L"Current directory: " << current_directory << L"\n";
    }
    log_file << L"Missing files:\n" << missing_text;
  }

  std::wstring message =
      L"CloveCom cannot start because required runtime files are missing or "
      L"not visible to the packed executable.\r\n\r\n"
      L"Missing:\r\n" +
      missing_text + L"\r\nDiagnostic log:\r\n" + log_path;

  ::MessageBoxW(nullptr, message.c_str(), L"CloveCom startup error",
                MB_OK | MB_ICONERROR);
  return false;
}

std::vector<std::string> GetCommandLineArguments() {
  // Convert the UTF-16 command line arguments to UTF-8 for the Engine to use.
  int argc;
  wchar_t** argv = ::CommandLineToArgvW(::GetCommandLineW(), &argc);
  if (argv == nullptr) {
    return std::vector<std::string>();
  }

  std::vector<std::string> command_line_arguments;

  // Skip the first argument as it's the binary name.
  for (int i = 1; i < argc; i++) {
    command_line_arguments.push_back(Utf8FromUtf16(argv[i]));
  }

  ::LocalFree(argv);

  return command_line_arguments;
}

std::string Utf8FromUtf16(const wchar_t* utf16_string) {
  if (utf16_string == nullptr) {
    return std::string();
  }
  unsigned int target_length = ::WideCharToMultiByte(
      CP_UTF8, WC_ERR_INVALID_CHARS, utf16_string,
      -1, nullptr, 0, nullptr, nullptr)
    -1; // remove the trailing null character
  int input_length = (int)wcslen(utf16_string);
  std::string utf8_string;
  if (target_length == 0 || target_length > utf8_string.max_size()) {
    return utf8_string;
  }
  utf8_string.resize(target_length);
  int converted_length = ::WideCharToMultiByte(
      CP_UTF8, WC_ERR_INVALID_CHARS, utf16_string,
      input_length, utf8_string.data(), target_length, nullptr, nullptr);
  if (converted_length == 0) {
    return std::string();
  }
  return utf8_string;
}
