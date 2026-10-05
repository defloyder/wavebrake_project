#include <flutter/dart_project.h>
#include <flutter/flutter_view_controller.h>
#include <windows.h>
#include <tlhelp32.h>

#include <string>

#include "flutter_window.h"
#include "utils.h"

namespace {

// Full path of the image behind [process], or empty.
std::wstring ImagePath(HANDLE process) {
  wchar_t image[MAX_PATH];
  DWORD size = MAX_PATH;
  if (!::QueryFullProcessImageNameW(process, 0, image, &size)) return L"";
  return std::wstring(image, size);
}

// This app's own exe.
std::wstring SelfPath() {
  wchar_t buf[MAX_PATH];
  DWORD n = ::GetModuleFileNameW(nullptr, buf, MAX_PATH);
  return (n == 0 || n == MAX_PATH) ? L"" : std::wstring(buf, n);
}

// The sing-box.exe that ships next to this exe (the one WindowsVpnAdapter
// launches).
std::wstring OwnSingBoxPath(const std::wstring& self) {
  size_t slash = self.find_last_of(L"\\/");
  return slash == std::wstring::npos ? L""
                                     : self.substr(0, slash + 1) + L"sing-box.exe";
}

// Whether [pid] is a running copy of this app (the parent of a sing-box
// that is still in use).
bool IsRunningWavebreak(DWORD pid, const std::wstring& self) {
  HANDLE parent = ::OpenProcess(PROCESS_QUERY_LIMITED_INFORMATION, FALSE, pid);
  if (!parent) return false;
  bool same = _wcsicmp(ImagePath(parent).c_str(), self.c_str()) == 0;
  ::CloseHandle(parent);
  return same;
}

// Stops WAVEBREAK's own sing-box.exe (matched by full path, so another
// app's sing-box — Happ and the like — is never touched). Closing the
// window used to leave sing-box running, still holding the TUN adapter and
// routes, so other VPN apps couldn't connect afterwards.
//   onlyChildren = true  — on exit: this process's own children.
//   onlyChildren = false — on start: leftovers whose WAVEBREAK parent is
//                          gone (a crash or an ended task), but not the one
//                          another running WAVEBREAK window is using.
void StopOwnSingBox(bool onlyChildren) {
  const std::wstring self = SelfPath();
  const std::wstring own = OwnSingBoxPath(self);
  if (own.empty()) return;
  HANDLE snap = ::CreateToolhelp32Snapshot(TH32CS_SNAPPROCESS, 0);
  if (snap == INVALID_HANDLE_VALUE) return;
  const DWORD me = ::GetCurrentProcessId();
  PROCESSENTRY32W entry{};
  entry.dwSize = sizeof(entry);
  for (BOOL ok = ::Process32FirstW(snap, &entry); ok;
       ok = ::Process32NextW(snap, &entry)) {
    if (_wcsicmp(entry.szExeFile, L"sing-box.exe") != 0) continue;
    const bool child = entry.th32ParentProcessID == me;
    if (onlyChildren ? !child
                     : IsRunningWavebreak(entry.th32ParentProcessID, self)) {
      continue;
    }
    HANDLE proc = ::OpenProcess(
        PROCESS_TERMINATE | PROCESS_QUERY_LIMITED_INFORMATION | SYNCHRONIZE,
        FALSE, entry.th32ProcessID);
    if (!proc) continue;
    if (_wcsicmp(ImagePath(proc).c_str(), own.c_str()) == 0) {
      ::TerminateProcess(proc, 0);
      ::WaitForSingleObject(proc, 3000);
    }
    ::CloseHandle(proc);
  }
  ::CloseHandle(snap);
}

}  // namespace

int APIENTRY wWinMain(_In_ HINSTANCE instance, _In_opt_ HINSTANCE prev,
                      _In_ wchar_t *command_line, _In_ int show_command) {
  // Attach to console when present (e.g., 'flutter run') or create a
  // new console when running with a debugger.
  if (!::AttachConsole(ATTACH_PARENT_PROCESS) && ::IsDebuggerPresent()) {
    CreateAndAttachConsole();
  }
  InstallCrashLogger();
  NativeLog("runner start");

  // A sing-box left behind by a crashed or killed WAVEBREAK still holds
  // the TUN adapter: stop it before this run tries to connect.
  StopOwnSingBox(/*onlyChildren=*/false);

  // Initialize COM, so that it is available for use in the library and/or
  // plugins.
  ::CoInitializeEx(nullptr, COINIT_APARTMENTTHREADED);

  flutter::DartProject project(L"data");

  std::vector<std::string> command_line_arguments =
      GetCommandLineArguments();

  project.set_dart_entrypoint_arguments(std::move(command_line_arguments));

  FlutterWindow window(project);
  Win32Window::Point origin(80, 40);
  Win32Window::Size size(1200, 800);
  if (!window.Create(L"WAVEBREAK", origin, size)) {
    NativeLog("window or Flutter engine could not be created");
    ::MessageBoxW(nullptr,
                  L"WAVEBREAK could not start (graphics / Flutter engine).\n"
                  L"Log: %LOCALAPPDATA%\\WAVEBREAK\\logs\\native.log",
                  L"WAVEBREAK", MB_OK | MB_ICONERROR);
    return EXIT_FAILURE;
  }
  NativeLog("window created");
  window.SetQuitOnClose(true);

  ::MSG msg;
  while (::GetMessage(&msg, nullptr, 0, 0)) {
    ::TranslateMessage(&msg);
    ::DispatchMessage(&msg);
  }

  // The window is closed: take the tunnel down with the app.
  StopOwnSingBox(/*onlyChildren=*/true);

  ::CoUninitialize();
  return EXIT_SUCCESS;
}
