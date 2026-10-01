#include "tray_icon.h"

#include <shellapi.h>

#include <algorithm>
#include <cmath>
#include <vector>

#include "resource.h"

namespace {

constexpr UINT kTrayId = 1;

// Builds a variant of the app icon at the small-icon size: |connected|
// adds a green status dot in the bottom-right corner, otherwise the icon
// is turned grey and dimmed. Returns nullptr if anything fails (the
// caller then falls back to the plain app icon).
HICON MakeStateIcon(bool connected) {
  const int size = GetSystemMetrics(SM_CXSMICON);
  HICON base = static_cast<HICON>(
      LoadImage(GetModuleHandle(nullptr), MAKEINTRESOURCE(IDI_APP_ICON),
                IMAGE_ICON, size, size, LR_DEFAULTCOLOR));
  if (!base) return nullptr;

  BITMAPINFO bmi = {};
  bmi.bmiHeader.biSize = sizeof(BITMAPINFOHEADER);
  bmi.bmiHeader.biWidth = size;
  bmi.bmiHeader.biHeight = -size;  // top-down
  bmi.bmiHeader.biPlanes = 1;
  bmi.bmiHeader.biBitCount = 32;
  bmi.bmiHeader.biCompression = BI_RGB;

  // Render the icon onto a transparent 32-bit surface: this gives straight
  // BGRA pixels whether the .ico entry is 32-bit or an older masked one.
  void* bits = nullptr;
  HDC screen = GetDC(nullptr);
  HDC dc = CreateCompatibleDC(screen);
  HBITMAP color = CreateDIBSection(screen, &bmi, DIB_RGB_COLORS, &bits,
                                   nullptr, 0);
  ReleaseDC(nullptr, screen);
  if (!dc || !color || !bits) {
    if (color) DeleteObject(color);
    if (dc) DeleteDC(dc);
    DestroyIcon(base);
    return nullptr;
  }
  HGDIOBJ old = SelectObject(dc, color);
  auto* px = static_cast<BYTE*>(bits);
  std::fill(px, px + size * size * 4, static_cast<BYTE>(0));
  DrawIconEx(dc, 0, 0, base, size, size, 0, nullptr, DI_NORMAL);
  SelectObject(dc, old);
  DeleteDC(dc);
  DestroyIcon(base);
  GdiFlush();

  if (connected) {
    // Green dot (#22C55E) with a dark rim, antialiased by coverage.
    const double r = size * 0.24;
    const double cx = size - r - 0.5;
    const double cy = size - r - 0.5;
    for (int y = 0; y < size; ++y) {
      for (int x = 0; x < size; ++x) {
        const double d = std::hypot(x + 0.5 - cx, y + 0.5 - cy);
        const double outer = std::clamp(r + 0.5 - d, 0.0, 1.0);
        if (outer <= 0) continue;
        const double inner = std::clamp(r - 0.7 - d, 0.0, 1.0);
        BYTE* p = px + (y * size + x) * 4;  // B, G, R, A
        // Rim colour, then the green fill over it.
        const double rim[3] = {0x1E, 0x29, 0x0F};
        const double fill[3] = {0x5E, 0xC5, 0x22};
        for (int c = 0; c < 3; ++c) {
          const double dot = rim[c] * (1 - inner) + fill[c] * inner;
          p[c] = static_cast<BYTE>(p[c] * (1 - outer) + dot * outer);
        }
        p[3] = static_cast<BYTE>(
            std::max<double>(p[3], 255.0 * outer));
      }
    }
  } else {
    for (int i = 0; i < size * size; ++i) {
      BYTE* p = px + i * 4;
      const BYTE g =
          static_cast<BYTE>((p[2] * 30 + p[1] * 59 + p[0] * 11) / 100);
      p[0] = p[1] = p[2] = g;
      p[3] = static_cast<BYTE>(p[3] * 0.6);
    }
  }

  std::vector<BYTE> mask_bits(((size + 15) / 16) * 2 * size, 0);
  HBITMAP mask = CreateBitmap(size, size, 1, 1, mask_bits.data());
  ICONINFO info = {};
  info.fIcon = TRUE;
  info.hbmColor = color;
  info.hbmMask = mask;
  HICON icon = CreateIconIndirect(&info);
  DeleteObject(mask);
  DeleteObject(color);
  return icon;
}

}  // namespace

TrayIcon::~TrayIcon() {
  Remove();
  if (connected_icon_) DestroyIcon(connected_icon_);
  if (idle_icon_) DestroyIcon(idle_icon_);
}

void TrayIcon::Create(HWND window) {
  window_ = window;
  taskbar_created_ = RegisterWindowMessage(L"TaskbarCreated");
  connected_icon_ = MakeStateIcon(true);
  idle_icon_ = MakeStateIcon(false);
  Apply(NIM_ADD);
}

void TrayIcon::Update(bool connected, const std::wstring& tooltip) {
  connected_ = connected;
  tooltip_ = tooltip.empty() ? L"WAVEBREAK" : tooltip;
  Apply(added_ ? NIM_MODIFY : NIM_ADD);
}

void TrayIcon::Remove() {
  if (!added_) return;
  NOTIFYICONDATA nid = {};
  nid.cbSize = sizeof(nid);
  nid.hWnd = window_;
  nid.uID = kTrayId;
  Shell_NotifyIcon(NIM_DELETE, &nid);
  added_ = false;
}

void TrayIcon::Apply(DWORD action) {
  if (!window_) return;
  NOTIFYICONDATA nid = {};
  nid.cbSize = sizeof(nid);
  nid.hWnd = window_;
  nid.uID = kTrayId;
  nid.uFlags = NIF_ICON | NIF_TIP | NIF_MESSAGE;
  nid.uCallbackMessage = kCallbackMessage;
  nid.hIcon = connected_ ? connected_icon_ : idle_icon_;
  if (!nid.hIcon) {
    nid.hIcon = LoadIcon(GetModuleHandle(nullptr),
                         MAKEINTRESOURCE(IDI_APP_ICON));
  }
  wcsncpy_s(nid.szTip, tooltip_.c_str(), _TRUNCATE);
  if (Shell_NotifyIcon(action, &nid)) {
    added_ = true;
  } else if (action == NIM_MODIFY) {
    // The icon is gone (Explorer restarted before we noticed): re-add.
    added_ = Shell_NotifyIcon(NIM_ADD, &nid) != FALSE;
  }
}

bool TrayIcon::HandleMessage(HWND window, UINT message, LPARAM lparam) {
  if (taskbar_created_ != 0 && message == taskbar_created_) {
    // Explorer restarted and lost every tray icon — add ours back.
    added_ = false;
    Apply(NIM_ADD);
    return true;
  }
  if (message != kCallbackMessage) return false;
  switch (LOWORD(lparam)) {
    case WM_LBUTTONUP:
    case WM_LBUTTONDBLCLK:
    case WM_RBUTTONUP:
      if (IsIconic(window)) ShowWindow(window, SW_RESTORE);
      ShowWindow(window, SW_SHOW);
      SetForegroundWindow(window);
      break;
  }
  return true;
}
