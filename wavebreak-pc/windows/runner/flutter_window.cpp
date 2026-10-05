#include "flutter_window.h"
#include "utils.h"

#include <flutter/standard_method_codec.h>

#include <optional>
#include <string>
#include <vector>

#include "flutter/generated_plugin_registrant.h"

namespace {

std::wstring Utf8ToWide(const std::string& utf8) {
  if (utf8.empty()) return std::wstring();
  const int len = MultiByteToWideChar(CP_UTF8, 0, utf8.data(),
                                      static_cast<int>(utf8.size()), nullptr, 0);
  std::wstring wide(len, L'\0');
  MultiByteToWideChar(CP_UTF8, 0, utf8.data(), static_cast<int>(utf8.size()),
                      wide.data(), len);
  return wide;
}

bool MapBool(const flutter::EncodableMap& map, const char* key, bool fallback) {
  auto it = map.find(flutter::EncodableValue(key));
  if (it == map.end()) return fallback;
  const auto* v = std::get_if<bool>(&it->second);
  return v ? *v : fallback;
}

std::string MapString(const flutter::EncodableMap& map, const char* key) {
  auto it = map.find(flutter::EncodableValue(key));
  if (it == map.end()) return std::string();
  const auto* v = std::get_if<std::string>(&it->second);
  return v ? *v : std::string();
}

int MapInt(const flutter::EncodableMap& map, const char* key) {
  auto it = map.find(flutter::EncodableValue(key));
  if (it == map.end()) return 0;
  if (const auto* v = std::get_if<int32_t>(&it->second)) return *v;
  if (const auto* v = std::get_if<int64_t>(&it->second)) {
    return static_cast<int>(*v);
  }
  return 0;
}

std::vector<TrayMenuItem> ParseMenu(const flutter::EncodableList& list) {
  std::vector<TrayMenuItem> items;
  for (const auto& entry : list) {
    const auto* map = std::get_if<flutter::EncodableMap>(&entry);
    if (!map) continue;
    TrayMenuItem item;
    item.separator = MapBool(*map, "separator", false);
    item.label = Utf8ToWide(MapString(*map, "label"));
    item.id = MapInt(*map, "id");
    item.checked = MapBool(*map, "checked", false);
    item.enabled = MapBool(*map, "enabled", true);
    auto it = map->find(flutter::EncodableValue("children"));
    if (it != map->end()) {
      if (const auto* children = std::get_if<flutter::EncodableList>(&it->second)) {
        item.children = ParseMenu(*children);
      }
    }
    items.push_back(std::move(item));
  }
  return items;
}

}  // namespace

FlutterWindow::FlutterWindow(const flutter::DartProject& project)
    : project_(project) {}

FlutterWindow::~FlutterWindow() {}

bool FlutterWindow::OnCreate() {
  if (!Win32Window::OnCreate()) {
    return false;
  }

  RECT frame = GetClientArea();

  // The size here must match the window dimensions to avoid unnecessary surface
  // creation / destruction in the startup path.
  flutter_controller_ = std::make_unique<flutter::FlutterViewController>(
      frame.right - frame.left, frame.bottom - frame.top, project_);
  // Ensure that basic setup of the controller was successful.
  if (!flutter_controller_->engine() || !flutter_controller_->view()) {
    NativeLog(!flutter_controller_->engine() ? "Flutter engine failed to start"
                                             : "Flutter view failed to create");
    return false;
  }
  RegisterPlugins(flutter_controller_->engine());
  SetChildContent(flutter_controller_->view()->GetNativeWindow());

  // Tray icon: shown "not connected" from the start, then kept in step by
  // Dart over "wavebreak/tray":
  //   update {connected: bool, tooltip: String}
  //   showMenu [items] -> picked id (0 = dismissed); item = {label, id,
  //            checked, enabled, separator, children}
  //   quit     -> removes the icon and closes the window (Dart has
  //               already disconnected)
  // and told about a right click with "menuRequested".
  tray_.Create(GetHandle());
  tray_channel_ =
      std::make_unique<flutter::MethodChannel<flutter::EncodableValue>>(
          flutter_controller_->engine()->messenger(), "wavebreak/tray",
          &flutter::StandardMethodCodec::GetInstance());
  tray_.on_menu_requested = [this]() {
    if (tray_channel_) tray_channel_->InvokeMethod("menuRequested", nullptr);
  };
  tray_channel_->SetMethodCallHandler(
      [this](const flutter::MethodCall<flutter::EncodableValue>& call,
             std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>>
                 result) {
        const auto& method = call.method_name();
        if (method == "update") {
          bool connected = false;
          std::string tooltip;
          if (const auto* args =
                  std::get_if<flutter::EncodableMap>(call.arguments())) {
            connected = MapBool(*args, "connected", false);
            tooltip = MapString(*args, "tooltip");
          }
          tray_.Update(connected, Utf8ToWide(tooltip));
          result->Success();
        } else if (method == "showMenu") {
          std::vector<TrayMenuItem> items;
          if (const auto* list =
                  std::get_if<flutter::EncodableList>(call.arguments())) {
            items = ParseMenu(*list);
          }
          const int picked = tray_.ShowMenu(items);
          result->Success(flutter::EncodableValue(picked));
        } else if (method == "show") {
          HWND window = GetHandle();
          if (IsIconic(window)) ShowWindow(window, SW_RESTORE);
          ShowWindow(window, SW_SHOW);
          SetForegroundWindow(window);
          result->Success();
        } else if (method == "quit") {
          result->Success();
          tray_.Remove();
          PostMessage(GetHandle(), WM_CLOSE, 0, 0);
        } else {
          result->NotImplemented();
        }
      });

  flutter_controller_->engine()->SetNextFrameCallback([&]() {
    this->Show();
  });

  // Flutter can complete the first frame before the "show window" callback is
  // registered. The following call ensures a frame is pending to ensure the
  // window is shown. It is a no-op if the first frame hasn't completed yet.
  flutter_controller_->ForceRedraw();

  return true;
}

void FlutterWindow::OnDestroy() {
  tray_channel_ = nullptr;
  tray_.Remove();
  if (flutter_controller_) {
    flutter_controller_ = nullptr;
  }

  Win32Window::OnDestroy();
}

LRESULT
FlutterWindow::MessageHandler(HWND hwnd, UINT const message,
                              WPARAM const wparam,
                              LPARAM const lparam) noexcept {
  // Give Flutter, including plugins, an opportunity to handle window messages.
  if (flutter_controller_) {
    std::optional<LRESULT> result =
        flutter_controller_->HandleTopLevelWindowProc(hwnd, message, wparam,
                                                      lparam);
    if (result) {
      return *result;
    }
  }

  if (tray_.HandleMessage(hwnd, message, lparam)) {
    return 0;
  }

  switch (message) {
    case WM_FONTCHANGE:
      flutter_controller_->engine()->ReloadSystemFonts();
      break;
  }

  return Win32Window::MessageHandler(hwnd, message, wparam, lparam);
}
