#ifndef RUNNER_TRAY_ICON_H_
#define RUNNER_TRAY_ICON_H_

#include <windows.h>

#include <functional>
#include <string>
#include <vector>

// One entry of the tray icon's right-click menu. |id| > 0 is what
// ShowMenu() returns when it's picked; |children| makes it a submenu.
struct TrayMenuItem {
  std::wstring label;
  int id = 0;
  bool checked = false;
  bool enabled = true;
  bool separator = false;
  std::vector<TrayMenuItem> children;
};

// The app's icon in the notification area ("show hidden icons"), showing
// whether the VPN is up: the app icon with a green dot while connected,
// a dimmed grey one otherwise. The tooltip carries the state and the
// location. A left click brings the window back; a right click asks Dart
// (via |on_menu_requested|) for the menu — connect/disconnect, locations,
// open, quit — which Dart then shows through ShowMenu(). Driven over the
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

  // Shows |items| as a popup menu at the cursor; returns the picked id,
  // or 0 when the menu was dismissed.
  int ShowMenu(const std::vector<TrayMenuItem>& items);

  // Handles the icon's own messages and Explorer restarts. Returns true
  // when |message| was the tray's.
  bool HandleMessage(HWND window, UINT message, LPARAM lparam);

  std::function<void()> on_menu_requested;

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
