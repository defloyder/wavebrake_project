#include "utils.h"

#include <flutter_windows.h>
#include <io.h>
#include <stdio.h>
#include <windows.h>

#include <iostream>

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
  // First, find the length of the string with a safe upper bound (CWE-126).
  // UNICODE_STRING_MAX_CHARS (32767) is the maximum length of a UNICODE_STRING.
  int input_length = static_cast<int>(wcsnlen(utf16_string, UNICODE_STRING_MAX_CHARS));
  // Now use that bounded length to determine the required buffer size.
  // When an explicit length is passed, WideCharToMultiByte does not include
  // the null terminator in its returned size.
  int target_length = ::WideCharToMultiByte(
      CP_UTF8, WC_ERR_INVALID_CHARS, utf16_string,
      input_length, nullptr, 0, nullptr, nullptr);
  std::string utf8_string;
  if (target_length == 0 || static_cast<size_t>(target_length) > utf8_string.max_size()) {
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

namespace {

std::wstring LogDirectory() {
  wchar_t buf[MAX_PATH];
  DWORD n = ::GetEnvironmentVariableW(L"LOCALAPPDATA", buf, MAX_PATH);
  if (n == 0 || n >= MAX_PATH) return L"";
  std::wstring dir = std::wstring(buf, n) + L"/WAVEBREAK";
  ::CreateDirectoryW(dir.c_str(), nullptr);
  dir += L"/logs";
  ::CreateDirectoryW(dir.c_str(), nullptr);
  return dir;
}

LONG WINAPI CrashFilter(EXCEPTION_POINTERS* info) {
  char line[160];
  snprintf(line, sizeof(line), "CRASH: exception 0x%08lX at %p",
           info && info->ExceptionRecord
               ? info->ExceptionRecord->ExceptionCode
               : 0UL,
           info && info->ExceptionRecord
               ? info->ExceptionRecord->ExceptionAddress
               : nullptr);
  NativeLog(line);
  return EXCEPTION_CONTINUE_SEARCH;
}

}  // namespace

void NativeLog(const std::string& line) {
  std::wstring dir = LogDirectory();
  if (dir.empty()) return;
  std::wstring path = dir + L"/native.log";
  FILE* f = nullptr;
  if (_wfopen_s(&f, path.c_str(), L"a") != 0 || !f) return;
  SYSTEMTIME t;
  ::GetLocalTime(&t);
  fprintf(f, "%04d-%02d-%02d %02d:%02d:%02d %s\n", t.wYear, t.wMonth, t.wDay,
          t.wHour, t.wMinute, t.wSecond, line.c_str());
  fclose(f);
}

void InstallCrashLogger() { ::SetUnhandledExceptionFilter(CrashFilter); }
