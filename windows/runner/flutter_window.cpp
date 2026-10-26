#include "flutter_window.h"
#include "desktop_session.h"
#include "flutter/generated_plugin_registrant.h"
#include <flutter/standard_method_codec.h>
#include <optional>
FlutterWindow::FlutterWindow(const flutter::DartProject &project,
                             std::string role)
    : project_(project), role_(std::move(role)) {}
FlutterWindow::~FlutterWindow() { Destroy(); }
bool FlutterWindow::OnCreate() {
  if (!Win32Window::OnCreate())
    return false;
  if (role_ != "teacher") Session().Register(role_, GetHandle());
  RECT frame = GetClientArea();
  flutter_controller_ = std::make_unique<flutter::FlutterViewController>(
      frame.right, frame.bottom, project_);
  if (!flutter_controller_->engine() || !flutter_controller_->view())
    return false;
  RegisterPlugins(flutter_controller_->engine());
  SetChildContent(flutter_controller_->view()->GetNativeWindow());
  channel_ = std::make_unique<flutter::MethodChannel<flutter::EncodableValue>>(
      flutter_controller_->engine()->messenger(), "schului/windows",
      &flutter::StandardMethodCodec::GetInstance());
  channel_->SetMethodCallHandler([this](const auto &call, auto result) {
    const auto &method = call.method_name();
    if (role_ == "teacher") {
      if (method == "closeEditor") {
        result->Success();
        PostQuitMessage(0);
      } else {
        result->NotImplemented();
      }
      return;
    }
    if (method == "state") {
      result->Success(Session().State(role_ != "overlay" && role_ != "learningApp"));
      return;
    }
    if (method == "start") {
      std::string error;
      if (!Session().Start(&error)) {
        result->Error("draw_start", error);
        return;
      }
    } else if (method == "step") {
      const auto *value =
          call.arguments() ? std::get_if<int32_t>(call.arguments()) : nullptr;
      if (!value) {
        result->Error("invalid_argument", "Schritt muss eine Zahl sein.");
        return;
      }
      Session().SetStep(*value);
    } else if (method == "hover") {
      if (call.arguments() && !call.arguments()->IsNull() &&
          !std::holds_alternative<flutter::EncodableMap>(*call.arguments())) {
        result->Error("invalid_argument", "Hover erwartet einen Zielpfad oder null.");
        return;
      }
      Session().SetHover(call.arguments() ? *call.arguments() : flutter::EncodableValue());
    } else if (method == "hint") {
      const auto *value =
          call.arguments() ? std::get_if<bool>(call.arguments()) : nullptr;
      if (!value) {
        result->Error("invalid_argument", "Hinweis muss true oder false sein.");
        return;
      }
      Session().SetHint(*value);
    } else if (method == "learningApp") {
      const auto *url = call.arguments() ? std::get_if<std::string>(call.arguments()) : nullptr;
      if (call.arguments() && !call.arguments()->IsNull() && !url) {
        result->Error("invalid_argument", "LearningApp erwartet eine URL oder null.");
        return;
      }
      Session().SetLearningApp(url ? *url : "");
    } else if (method == "inspector") {
      const auto *value =
          call.arguments() ? std::get_if<bool>(call.arguments()) : nullptr;
      if (!value) {
        result->Error("invalid_argument",
                      "Inspector-Modus muss true oder false sein.");
        return;
      }
      Session().SetInspector(*value);
    } else if (method == "selectNode") {
      const auto *value = call.arguments()
                              ? std::get_if<std::string>(call.arguments())
                              : nullptr;
      if (!value) {
        result->Error("invalid_argument",
                      "Knoten-ID muss eine Zeichenkette sein.");
        return;
      }
      if (!Session().SelectNode(*value)) {
        result->Error(
            "node_missing",
            "Der Knoten ist nicht mehr vorhanden. Bitte erneut auswählen.");
        return;
      }
    } else if (method == "connectionDiagnostics") {
      std::string path;
      if (!Session().ExportConnection(&path)) {
        result->Error(
            "export",
            "Die Verbindungsdiagnose konnte nicht gespeichert werden.");
        return;
      }
      result->Success(flutter::EncodableValue(path));
      return;
    } else if (method == "diagnostics") {
      std::string path;
      if (!Session().Export(&path)) {
        result->Error("export", "Kein Accessibility-Baum verfügbar oder "
                                "Exportordner nicht beschreibbar.");
        return;
      }
      result->Success(flutter::EncodableValue(path));
      return;
    } else if (method == "exit") {
      Session().Restore();
      PostQuitMessage(0);
    } else {
      result->NotImplemented();
      return;
    }
    result->Success();
  });
  if (role_ == "lesson") {
    SetTimer(GetHandle(), 1, 400, nullptr);
    RegisterHotKey(GetHandle(), 1, MOD_CONTROL | MOD_SHIFT | MOD_NOREPEAT,
                   VK_F12);
    flutter_controller_->engine()->SetNextFrameCallback([this]() {
      Show();
      SetForegroundWindow(GetHandle());
      std::string error;
      Session().Start(&error);
    });
  }
  if (role_ == "teacher") {
    flutter_controller_->engine()->SetNextFrameCallback([this]() { Show(); });
  }
  flutter_controller_->ForceRedraw();
  return true;
}
void FlutterWindow::OnDestroy() {
  if (GetHandle()) {
    KillTimer(GetHandle(), 1);
    UnregisterHotKey(GetHandle(), 1);
  }
  channel_.reset();
  flutter_controller_.reset();
  Win32Window::OnDestroy();
}
LRESULT FlutterWindow::MessageHandler(HWND hwnd, UINT message, WPARAM wparam,
                                      LPARAM lparam) noexcept {
  if (message == WM_CLOSE && role_ == "teacher" && channel_) {
    channel_->InvokeMethod("requestClose", nullptr);
    return 0;
  }
  if (message == WM_TIMER && role_ == "lesson") {
    Session().Tick();
    return 0;
  }
  if (message == WM_HOTKEY || (message == WM_CLOSE && role_ == "lesson")) {
    Session().Restore();
    PostQuitMessage(0);
    return 0;
  }
  if (role_ == "hint" && message == WM_CLOSE) {
    Session().SetHint(false);
    return 0;
  }
  if (role_ == "learningApp" && message == WM_CLOSE) {
    Session().SetLearningApp("");
    return 0;
  }
  if (role_ == "overlay" && message == WM_MOUSEACTIVATE)
    return MA_NOACTIVATE;
  if (flutter_controller_) {
    auto result = flutter_controller_->HandleTopLevelWindowProc(hwnd, message,
                                                                wparam, lparam);
    if (result)
      return *result;
    if (message == WM_FONTCHANGE)
      flutter_controller_->engine()->ReloadSystemFonts();
  }
  return Win32Window::MessageHandler(hwnd, message, wparam, lparam);
}
