#ifndef RUNNER_TRAY_ICON_H_
#define RUNNER_TRAY_ICON_H_

#include <windows.h>

#include <string>

// The app's icon in the notification area ("show hidden icons"), showing
// whether the VPN is up: the app icon with a green dot while connected,
// a dimmed grey one otherwise. The tooltip carries the state and the
// location. Clicking it brings the window back. Driven from Dart over the
// "wavebreak/tray" method channel (see flutter_window.cpp).
//
// Plain Win32 (Shell_NotifyIcon) rather than a plugin: no new dependency,
// and the state icons are derived from the app icon at runtime, so there
// are no extra image files to keep in sync with it.
class TrayIcon {
 public:
  // The window message the icon reports mouse events with.
  static constexpr UINT kCallbackMessage = WM_APP + 1;

  TrayIcon() = default;
  ~TrayIcon();

  void Create(HWND window);
  void Update(bool connected, const std::wstring& tooltip);
  void Remove();

  // Handles the icon's own messages and Explorer restarts. Returns true
  // when |message| was the tray's.
  bool HandleMessage(HWND window, UINT message, LPARAM lparam);

 private:
  void Apply(DWORD action);

  HWND window_ = nullptr;
  bool added_ = false;
  bool connected_ = false;
  std::wstring tooltip_ = L"WAVEBREAK";
  HICON connected_icon_ = nullptr;
  HICON idle_icon_ = nullptr;
  UINT taskbar_created_ = 0;
};

#endif  // RUNNER_TRAY_ICON_H_
