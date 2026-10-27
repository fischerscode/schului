#include "target_picker.h"
#include "captured_path.h"
#include "live_uia_target.h"
#include <algorithm>
#include <filesystem>
#include <flutter/standard_method_codec.h>

namespace {
using flutter::EncodableValue;
using flutter::EncodableMap;
using flutter::EncodableList;
using Microsoft::WRL::ComPtr;

std::string Utf8(const std::wstring &value) {
  if (value.empty()) return {};
  const int count = WideCharToMultiByte(CP_UTF8, 0, value.data(),
      static_cast<int>(value.size()), nullptr, 0, nullptr, nullptr);
  std::string result(count, '\0');
  WideCharToMultiByte(CP_UTF8, 0, value.data(), static_cast<int>(value.size()),
      result.data(), count, nullptr, nullptr);
  return result;
}

class CaptureProvider : public live_uia::Provider {
 public:
  CaptureProvider(IUIAutomation *automation, IUIAutomationTreeWalker *walker,
                  std::function<bool()> cancelled)
      : live_uia::Provider(walker, std::move(cancelled)), automation_(automation) {}
  bool Equal(const live_uia::Handle &left, const live_uia::Handle &right) {
    BOOL equal = FALSE;
    return SUCCEEDED(automation_->CompareElements(left.Get(), right.Get(), &equal)) && equal;
  }
 private:
  IUIAutomation *automation_;
};

LRESULT CALLBACK OutlineProc(HWND window, UINT message, WPARAM wparam, LPARAM lparam) {
  if (message == WM_NCHITTEST) return HTTRANSPARENT;
  if (message == WM_MOUSEACTIVATE) return MA_NOACTIVATE;
  if (message == WM_PAINT) {
    PAINTSTRUCT paint{};
    HDC dc = BeginPaint(window, &paint);
    RECT area{};
    GetClientRect(window, &area);
    HBRUSH brush = CreateSolidBrush(RGB(0, 122, 255));
    FillRect(dc, &area, brush);
    DeleteObject(brush);
    EndPaint(window, &paint);
    return 0;
  }
  return DefWindowProc(window, message, wparam, lparam);
}
} // namespace

TargetPicker::TargetPicker(HWND owner, flutter::BinaryMessenger *messenger)
    : owner_(owner), channel_(messenger, "schului/target-picker",
                             &flutter::StandardMethodCodec::GetInstance()) {
  channel_.SetMethodCallHandler([this](const auto &call, auto result) {
    if (call.method_name() == "begin") Start(call.arguments(), std::move(result));
    else if (call.method_name() == "windows") result->Success(EncodableValue(target_app::List()));
    else if (call.method_name() == "cancel") { Cancel(); result->Success(); }
    else result->NotImplemented();
  });
}

TargetPicker::~TargetPicker() {
  channel_.SetMethodCallHandler(nullptr);
  Cancel();
  if (overlay_) DestroyWindow(overlay_);
}

void TargetPicker::Start(const EncodableValue *application, std::unique_ptr<flutter::MethodResult<EncodableValue>> result) {
  if (result_) { result->Error("busy", "Eine Zielauswahl ist bereits aktiv."); return; }
  auto config = application ? target_app::Parse(*application) : std::optional<target_app::Config>(target_app::Config{});
  if (!config) { result->Error("application", "Zuerst Zielsoftware auswählen."); return; }
  application_ = *config;
  POINT cursor{};
  if (!GetCursorPos(&cursor)) {
    result->Error("desktop", "Die Mausposition ist nicht verfügbar. Zielauswahl auf dem entsperrten Windows-Desktop starten.");
    return;
  }
  if (!RegisterHotKey(owner_, kConfirm, MOD_NOREPEAT, VK_F8)) {
    result->Error("hotkey", "F8 ist bereits belegt. Die Zielauswahl konnte nicht gestartet werden.");
    return;
  }
  if (!RegisterHotKey(owner_, kCancel, MOD_NOREPEAT, VK_ESCAPE)) {
    UnregisterHotKey(owner_, kConfirm);
    result->Error("hotkey", "Esc ist bereits belegt. Die Zielauswahl konnte nicht gestartet werden.");
    return;
  }
  result_ = std::move(result);
  { std::lock_guard<std::mutex> lock(mutex_); confirmation_.reset(); update_.reset(); }
  ++generation_;
  stop_ = false;
  worker_ = std::thread([this] { ReadCursor(); });
}

void TargetPicker::Finish(const EncodableValue &value) {
  stop_ = true;
  ++generation_;
  changed_.notify_all();
  UnregisterHotKey(owner_, kConfirm);
  UnregisterHotKey(owner_, kCancel);
  if (overlay_) ShowWindow(overlay_, SW_HIDE);
  if (worker_.joinable()) worker_.join();
  if (result_) { result_->Success(value); result_.reset(); SetForegroundWindow(owner_); }
}

void TargetPicker::Cancel() { Finish(EncodableValue()); }

bool TargetPicker::HandleMessage(UINT message, WPARAM wparam) {
  if (message == kUpdate) { Apply(); return true; }
  if (message != WM_HOTKEY || !result_) return false;
  if (wparam == kCancel) { Cancel(); return true; }
  if (wparam != kConfirm) return false;
  POINT point{};
  if (GetCursorPos(&point)) {
    std::lock_guard<std::mutex> lock(mutex_);
    confirmation_ = point;
    ++generation_;
    changed_.notify_all();
  }
  return true;
}

void TargetPicker::ShowBounds(const RECT &bounds) {
  if (bounds.right <= bounds.left || bounds.bottom <= bounds.top) {
    if (overlay_) ShowWindow(overlay_, SW_HIDE);
    return;
  }
  if (!overlay_) {
    WNDCLASSW cls{};
    cls.lpfnWndProc = OutlineProc;
    cls.hInstance = GetModuleHandle(nullptr);
    cls.lpszClassName = L"SchuluiTargetOutline";
    RegisterClassW(&cls);
    overlay_ = CreateWindowExW(WS_EX_LAYERED | WS_EX_TRANSPARENT | WS_EX_NOACTIVATE |
        WS_EX_TOOLWINDOW | WS_EX_TOPMOST, cls.lpszClassName, L"", WS_POPUP,
        0, 0, 0, 0, nullptr, nullptr, cls.hInstance, nullptr);
    if (!overlay_) return;
    SetLayeredWindowAttributes(overlay_, 0, 255, LWA_ALPHA);
  }
  const int width = bounds.right - bounds.left + 6;
  const int height = bounds.bottom - bounds.top + 6;
  HRGN ring = CreateRectRgn(0, 0, width, height);
  HRGN inner = CreateRectRgn(3, 3, width - 3, height - 3);
  CombineRgn(ring, ring, inner, RGN_DIFF);
  DeleteObject(inner);
  if (!SetWindowRgn(overlay_, ring, FALSE)) DeleteObject(ring);
  SetWindowPos(overlay_, HWND_TOPMOST, bounds.left - 3, bounds.top - 3, width, height,
      SWP_NOACTIVATE | SWP_SHOWWINDOW);
  InvalidateRect(overlay_, nullptr, TRUE);
}

void TargetPicker::Apply() {
  std::optional<Update> update;
  { std::lock_guard<std::mutex> lock(mutex_); update.swap(update_); }
  if (!result_ || !update || update->generation != generation_.load()) return;
  if (update->confirmed && !update->target.IsNull()) {
    Finish(update->target);
    return;
  }
  POINT current{};
  if (!update->confirmed && GetCursorPos(&current) &&
      (current.x != update->point.x || current.y != update->point.y)) {
    if (overlay_) ShowWindow(overlay_, SW_HIDE);
    return;
  }
  ShowBounds(update->bounds);
  channel_.InvokeMethod("candidate", std::make_unique<EncodableValue>(EncodableMap{
    {EncodableValue("label"), EncodableValue(update->label)},
    {EncodableValue("error"), EncodableValue(update->error)},
  }));
}

void TargetPicker::ReadCursor() {
  const HRESULT com = CoInitializeEx(nullptr, COINIT_MULTITHREADED);
  if (SUCCEEDED(com)) {
    {
      ComPtr<IUIAutomation> automation;
      HRESULT status = CoCreateInstance(CLSID_CUIAutomation8, nullptr, CLSCTX_INPROC_SERVER,
          IID_PPV_ARGS(&automation));
      if (FAILED(status)) CoCreateInstance(CLSID_CUIAutomation, nullptr, CLSCTX_INPROC_SERVER,
          IID_PPV_ARGS(&automation));
      ComPtr<IUIAutomation2> bounded;
      if (automation && SUCCEEDED(automation.As(&bounded))) {
        bounded->put_ConnectionTimeout(2000);
        bounded->put_TransactionTimeout(2000);
      }
      while (!stop_) {
        Update update;
        POINT point{};
        {
          std::lock_guard<std::mutex> lock(mutex_);
          update.generation = generation_.load();
          update.confirmed = confirmation_.has_value();
          if (confirmation_) { point = *confirmation_; confirmation_.reset(); }
          else GetCursorPos(&point);
          update.point = point;
        }
        const auto cancelled = [this, version = update.generation] {
          return stop_ || version != generation_.load();
        };
        const HWND window = GetAncestor(WindowFromPoint(point), GA_ROOT);
        if (!automation) update.error = "Windows Accessibility ist nicht verfügbar.";
        else if (auto candidate = target_app::Read(window); !candidate || !target_app::Matches(*candidate, application_)) update.error = "Über ein Element der gewählten Zielsoftware zeigen.";
        else {
          live_uia::Handle root, element;
          ComPtr<IUIAutomationTreeWalker> walker;
          if (SUCCEEDED(automation->ElementFromHandle(window, &root)) &&
              SUCCEEDED(automation->ElementFromPoint(point, &element)) &&
              SUCCEEDED(automation->get_RawViewWalker(&walker)) && root && element) {
            CaptureProvider provider(automation.Get(), walker.Get(), cancelled);
            std::vector<live_uia::Handle> chain{element};
            while (!provider.Cancelled() && chain.size() < 64 && !provider.Equal(chain.back(), root)) {
              live_uia::Handle parent;
              if (FAILED(walker->GetParentElement(chain.back().Get(), &parent)) || !parent) break;
              chain.push_back(parent);
            }
            if (provider.Equal(chain.back(), root)) {
              std::reverse(chain.begin(), chain.end());
              const auto path = live_path::Capture(chain, provider, application_.draw);
              BOOL offscreen = TRUE;
              RECT bounds{};
              if (path && SUCCEEDED(element->get_CurrentBoundingRectangle(&bounds)) &&
                  SUCCEEDED(element->get_CurrentIsOffscreen(&offscreen)) && !offscreen &&
                  bounds.right > bounds.left && bounds.bottom > bounds.top &&
                  PtInRect(&bounds, point) && !provider.Cancelled()) {
                EncodableList segments;
                for (const auto &segment : *path) {
                  EncodableMap entry{{EncodableValue("type"), EncodableValue(Utf8(segment.type))}};
                  if (segment.name) entry[EncodableValue("name")] = EncodableValue(Utf8(*segment.name));
                  if (segment.index) entry[EncodableValue("index")] = EncodableValue(*segment.index);
                  segments.emplace_back(entry);
                }
                // Capture omits named title wrappers, but retains an unnamed client.
                const bool includes_client = chain.size() > 1 &&
                    live_path::Normalize(provider.Read(chain[1]).name).empty() &&
                    (provider.Read(chain[1]).type.empty() || live_path::Normalize(provider.Read(chain[1]).type) == L"element");
                EncodableMap selector{
                    {EncodableValue("version"), EncodableValue(2)},
                    {EncodableValue("path"), EncodableValue(segments)}};
                if (!application_.draw) selector[EncodableValue("mode")] = EncodableValue("exact");
                update.target = EncodableValue(EncodableMap{
                  {EncodableValue("selector"), EncodableValue(selector)},
                  {EncodableValue("includesUnnamedClient"), EncodableValue(includes_client)}});
                const auto metadata = provider.Read(element);
                update.label = Utf8(metadata.name.empty() ? metadata.type : metadata.name);
                update.bounds = bounds;
              }
            }
          }
          if (update.target.IsNull()) update.error = "Kein eindeutiger Zielpfad. Anderes Element wählen oder Inspector verwenden.";
        }
        {
          std::unique_lock<std::mutex> lock(mutex_);
          if (!cancelled()) {
            // Do not overwrite a pending confirmed update with a later preview.
            if (!update_ || !update_->confirmed) update_ = std::move(update);
            PostMessage(owner_, kUpdate, 0, 0);
          }
          changed_.wait_for(lock, std::chrono::milliseconds(200), [&] { return cancelled(); });
        }
      }
    }
    CoUninitialize();
  } else {
    std::lock_guard<std::mutex> lock(mutex_);
    Update update;
    update.generation = generation_.load();
    update.error = "Windows Accessibility konnte nicht gestartet werden.";
    update_ = std::move(update);
    PostMessage(owner_, kUpdate, 0, 0);
  }
}
