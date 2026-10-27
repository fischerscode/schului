#include "desktop_session.h"
#include "session_layout.h"
#include "live_uia_target.h"
#include <UIAutomation.h>
#include <algorithm>
#include <chrono>
#include <filesystem>
#include <fstream>
#include <functional>
#include <sstream>
#include <wrl/client.h>

using flutter::EncodableList;
using flutter::EncodableMap;
using flutter::EncodableValue;
using Microsoft::WRL::ComPtr;
namespace {
std::string Utf8(const std::wstring &value) {
  if (value.empty())
    return {};
  int size = WideCharToMultiByte(CP_UTF8, 0, value.data(),
                                 static_cast<int>(value.size()), nullptr, 0,
                                 nullptr, nullptr);
  std::string result(size, '\0');
  WideCharToMultiByte(CP_UTF8, 0, value.data(), static_cast<int>(value.size()),
                      result.data(), size, nullptr, nullptr);
  return result;
}
std::string SingleLine(std::string text) {
  for (auto &character : text) {
    if (character == '\t' || character == '\n' || character == '\r')
      character = ' ';
  }
  return text;
}

std::string RuntimeId(IUIAutomationElement *element,
                      const std::string &fallback) {
  SAFEARRAY *ids = nullptr;
  if (FAILED(element->GetRuntimeId(&ids)) || !ids)
    return fallback;
  LONG lower = 0, upper = -1;
  std::ostringstream output;
  output << "runtime";
  if (SUCCEEDED(SafeArrayGetLBound(ids, 1, &lower)) &&
      SUCCEEDED(SafeArrayGetUBound(ids, 1, &upper))) {
    for (LONG i = lower; i <= upper; ++i) {
      LONG value = 0;
      if (FAILED(SafeArrayGetElement(ids, &i, &value))) {
        upper = -1;
        break;
      }
      output << ':' << value;
    }
  }
  SafeArrayDestroy(ids);
  return upper >= lower ? output.str() : fallback;
}

EncodableValue NodeValue(const AccessibilityNode &node) {
  return EncodableValue(EncodableMap{
      {EncodableValue("id"), EncodableValue(node.id)},
      {EncodableValue("parentId"), EncodableValue(node.parent_id)},
      {EncodableValue("name"), EncodableValue(node.name)},
      {EncodableValue("type"), EncodableValue(node.type)},
      {EncodableValue("depth"), EncodableValue(node.depth)},
      {EncodableValue("offscreen"), EncodableValue(node.offscreen)},
      {EncodableValue("left"),
       EncodableValue(static_cast<double>(node.rect.left))},
      {EncodableValue("top"),
       EncodableValue(static_cast<double>(node.rect.top))},
      {EncodableValue("width"),
       EncodableValue(static_cast<double>(node.rect.right - node.rect.left))},
      {EncodableValue("height"),
       EncodableValue(static_cast<double>(node.rect.bottom - node.rect.top))},
  });
}

std::string AccessibilityTree(IUIAutomation *automation,
                              IUIAutomationElement *root,
                              const std::atomic<bool> &stop,
                              std::vector<AccessibilityNode> *nodes,
                              HRESULT *status) {
  ComPtr<IUIAutomationTreeWalker> walker;
  *status = automation->get_RawViewWalker(&walker);
  if (FAILED(*status) || !walker)
    return {};
  std::ostringstream output;
  output << "Accessibility-Baum (UIA Raw View)\n"
         << "Einrueckung: zwei Leerzeichen pro Ebene. Positionen: "
            "Bildschirm-Pixel.\n\n";
  const auto deadline =
      std::chrono::steady_clock::now() + std::chrono::seconds(10);
  int visited = 0;
  bool truncated = false;
  std::function<void(IUIAutomationElement *, int, const std::string &,
                     const std::string &)>
      visit;
  visit = [&](IUIAutomationElement *element, int depth,
              const std::string &parent_id, const std::string &path) {
    if (stop || visited >= 3000 ||
        std::chrono::steady_clock::now() >= deadline) {
      truncated = true;
      return;
    }
    ++visited;
    BSTR raw_name = nullptr, raw_type = nullptr;
    element->get_CurrentName(&raw_name);
    element->get_CurrentLocalizedControlType(&raw_type);
    auto name = raw_name ? SingleLine(Utf8(raw_name)) : std::string();
    auto type = raw_type ? SingleLine(Utf8(raw_type)) : std::string();
    SysFreeString(raw_name);
    SysFreeString(raw_type);
    AccessibilityNode node;
    node.id = RuntimeId(element, "path:" + path + ':' + type + ':' + name);
    node.parent_id = parent_id;
    node.name = name;
    node.type = type;
    node.depth = depth;
    const bool has_rect =
        SUCCEEDED(element->get_CurrentBoundingRectangle(&node.rect));
    BOOL offscreen = FALSE;
    element->get_CurrentIsOffscreen(&offscreen);
    node.offscreen = offscreen != FALSE;
    nodes->push_back(node);
    output << std::string(depth * 2, ' ') << '['
           << type << "] "
           << (name.empty() ? "<ohne Namen>" : name);
    if (has_rect && node.rect.right > node.rect.left &&
        node.rect.bottom > node.rect.top) {
      output << "  (x=" << node.rect.left << ", y=" << node.rect.top
             << ", w=" << node.rect.right - node.rect.left
             << ", h=" << node.rect.bottom - node.rect.top << ')';
    }
    if (offscreen)
      output << "  [nicht sichtbar]";
    output << '\n';
    if (stop || std::chrono::steady_clock::now() >= deadline) {
      truncated = true;
      return;
    }
    ComPtr<IUIAutomationElement> child;
    if (FAILED(walker->GetFirstChildElement(element, &child))) {
      output << std::string((depth + 1) * 2, ' ')
             << "[Unterelemente nicht lesbar]\n";
      return;
    }
    if (child && depth >= 64) {
      output << std::string((depth + 1) * 2, ' ')
             << "[Maximale Baumtiefe erreicht]\n";
      truncated = true;
      return;
    }
    int child_index = 0;
    while (child && visited < 3000 && !stop) {
      visit(child.Get(), depth + 1, node.id,
            path + '/' + std::to_string(child_index++));
      if (stop || std::chrono::steady_clock::now() >= deadline)
        break;
      ComPtr<IUIAutomationElement> sibling;
      if (FAILED(walker->GetNextSiblingElement(child.Get(), &sibling))) {
        output << std::string((depth + 1) * 2, ' ')
               << "[Weitere Geschwister nicht lesbar]\n";
        return;
      }
      child = std::move(sibling);
    }
    if (child)
      truncated = true;
  };
  visit(root, 0, "", "0");
  if (truncated)
    output << "\n[Baum unvollstaendig: Abbruch oder Begrenzung auf 3000 "
              "Elemente / 64 Ebenen / Zeitlimit.]\n";
  return output.str();
}
std::filesystem::path ExecutableDirectory() {
  wchar_t buffer[32768]{};
  GetModuleFileNameW(nullptr, buffer, 32768);
  return std::filesystem::path(buffer).parent_path();
}
unsigned long long FileTimeValue(const FILETIME &value) {
  return (static_cast<unsigned long long>(value.dwHighDateTime) << 32) |
         value.dwLowDateTime;
}
DWORD Place(HWND window, const RECT &rect, HWND order) {
  if (!window)
    return ERROR_INVALID_WINDOW_HANDLE;
  RECT current{};
  GetWindowRect(window, &current);
  const bool topmost =
      (GetWindowLongPtr(window, GWL_EXSTYLE) & WS_EX_TOPMOST) != 0;
  const bool order_matches = !order || (order == HWND_TOPMOST && topmost) ||
                             (order == HWND_NOTOPMOST && !topmost);
  if (EqualRect(&current, &rect) && order_matches)
    return 0;
  const UINT flags = SWP_NOACTIVATE | (order ? 0 : SWP_NOZORDER);
  return SetWindowPos(window, order, rect.left, rect.top,
                      rect.right - rect.left, rect.bottom - rect.top, flags)
             ? 0
             : GetLastError();
}
} // namespace
DesktopSession &Session() {
  static DesktopSession session;
  return session;
}
DesktopSession::DesktopSession() {
  inspector_ = std::thread([this] { Inspect(); });
  hover_bounds_reader_ = std::thread([this] { InspectHoverBounds(); });
}
DesktopSession::~DesktopSession() {
  stop_ = true;
  hover_bounds_changed_.notify_all();
  if (inspector_.joinable())
    inspector_.join();
  if (hover_bounds_reader_.joinable())
    hover_bounds_reader_.join();
}
void DesktopSession::Register(const std::string &role, HWND hwnd) {
  if (role == "overlay")
    overlay_ = hwnd;
  else if (role == "hint")
    hint_ = hwnd;
  else if (role == "webPage")
    web_page_ = hwnd;
  else
    lesson_ = hwnd;
  SetWindowLongPtr(hwnd, GWL_STYLE, WS_POPUP | WS_CLIPCHILDREN);
  if (role == "webPage") {
    SetWindowLongPtr(hwnd, GWL_STYLE, WS_POPUP | WS_CLIPCHILDREN | WS_BORDER);
    SetWindowLongPtr(hwnd, GWLP_HWNDPARENT, reinterpret_cast<LONG_PTR>(lesson_));
  }
  // The lesson/inspector is a primary app window. Keep it reachable through
  // the taskbar and Alt+Tab, including while waiting for a target window.
  LONG_PTR ex = role == "lesson" ? WS_EX_APPWINDOW : WS_EX_TOOLWINDOW;
  if (role == "overlay") {
    ex |= WS_EX_LAYERED | WS_EX_TRANSPARENT | WS_EX_NOACTIVATE;
    SetWindowLongPtr(hwnd, GWL_EXSTYLE, ex);
    SetLayeredWindowAttributes(hwnd, RGB(1, 1, 1), inspector_mode_ ? 96 : 255,
                               LWA_COLORKEY | LWA_ALPHA);
  } else
    SetWindowLongPtr(hwnd, GWL_EXSTYLE, ex);
  SetWindowPos(hwnd, nullptr, 0, 0, 0, 0,
               SWP_NOMOVE | SWP_NOSIZE | SWP_NOZORDER | SWP_NOACTIVATE |
                   SWP_FRAMECHANGED);
  Tick();
}

bool DesktopSession::ConfigureApplication(const EncodableValue &value) {
  auto config = target_app::Parse(value);
  if (!config || captured_ || launched_pid_) return false;
  application_ = *config;
  configured_ = true;
  return true;
}
EncodableValue DesktopSession::ApplicationWindows() { return EncodableValue(target_app::List(&application_)); }
bool DesktopSession::SelectApplicationWindow(int64_t handle) {
  const auto window = reinterpret_cast<HWND>(static_cast<intptr_t>(handle));
  auto candidate = target_app::Read(window);
  if (!candidate || !target_app::Matches(*candidate, application_) || captured_) return false;
  preferred_window_ = window;
  target_ = nullptr;
  Tick();
  return true;
}
bool DesktopSession::Start(std::string *error) {
  startup_error_.clear();
  if (!configured_) { startup_error_ = *error = "Zuerst Zielsoftware auswählen."; return false; }
  if (IsWindow(target_.load()) || FindTargetWindow()) return true;
  if (target_app::Windows(&application_).size() > 1) { *error = startup_error_; return false; }
  startup_error_.clear();
  FILETIME now{}; GetSystemTimeAsFileTime(&now);
  if (launched_pid_ && FileTimeValue(now) - launch_time_ < 300000000ULL) return true;
  std::error_code filesystem_error;
  if (!std::filesystem::is_regular_file(application_.executable, filesystem_error)) {
    startup_error_ = *error = "Zielsoftware nicht gefunden. Programmpfad in der Unterrichtseinheit anpassen oder Software zuerst öffnen.";
    return false;
  }
  auto command = target_app::Quote(application_.executable);
  for (const auto &argument : application_.arguments) command += L" " + target_app::Quote(argument);
  if (command.size() >= 32767) { startup_error_ = *error = "Startargumente sind zu lang."; return false; }
  STARTUPINFOW startup{}; startup.cb = sizeof(startup);
  PROCESS_INFORMATION process{};
  if (!CreateProcessW(application_.executable.c_str(), command.data(), nullptr, nullptr, FALSE, 0, nullptr,
      std::filesystem::path(application_.executable).parent_path().c_str(), &startup, &process)) {
    startup_error_ = *error = "Zielsoftware konnte nicht gestartet werden (Windows-Fehler " + std::to_string(GetLastError()) + ").";
    return false;
  }
  launched_pid_ = process.dwProcessId; launch_time_ = FileTimeValue(now);
  launched_executable_ = application_.executable;
  CloseHandle(process.hThread); CloseHandle(process.hProcess);
  return true;
}
HWND DesktopSession::FindTargetWindow() {
  if (!configured_) return nullptr;
    if (auto preferred = target_app::Read(preferred_window_); preferred && target_app::Matches(*preferred, application_)) { startup_error_.clear(); return preferred_window_; }
    auto windows = target_app::Windows(&application_);
    if (windows.size() == 1) { startup_error_.clear(); connection_method_ = "configured-application"; return windows.front().handle; }
    if (windows.size() > 1) startup_error_ = "Mehrere passende Fenster. Bitte Fenster auswählen.";
    else if (launched_pid_) {
      FILETIME now{}; GetSystemTimeAsFileTime(&now);
      if (FileTimeValue(now) - launch_time_ >= 300000000ULL) startup_error_ = "Kein passendes Fenster gefunden. Software öffnen und Fensterauswahl bzw. Programmeinstellungen prüfen.";
    }
    return nullptr;
}

void DesktopSession::Tick() {
  if (!lesson_)
    return;
  MONITORINFO info{sizeof(MONITORINFO)};
  GetMonitorInfoW(MonitorFromWindow(lesson_, MONITOR_DEFAULTTOPRIMARY), &info);
  monitor_ = info.rcWork;
  const auto bounds = session_layout::SplitWorkArea(monitor_);
  const RECT left = bounds.lesson;
  target_rect_ = bounds.target;
  HWND target = target_.load();
  if (target) {
    const auto candidate = target_app::Read(target);
    if (!candidate || !target_app::Matches(*candidate, application_)) { target_ = nullptr; target = nullptr; }
  }
  if (session_layout::ApplyVisibility(
          target, lesson_, overlay_, hint_, target_connected_once_,
          lesson_hidden_for_target_) == session_layout::Visibility::closed) {
    active_ = false;
    if (web_page_) ShowWindow(web_page_, SW_HIDE);
    PostQuitMessage(0);
    return;
  }
  if (!IsWindow(target)) {
    target = FindTargetWindow();
    target_ = target;
    if (target && !captured_) {
      GetWindowPlacement(target, &original_);
      captured_ = true;
      target_connected_once_ = true;
      if (IsWindowEnabled(target) && !IsIconic(target)) {
        ShowWindow(target, SW_RESTORE);
        placement_error_ = Place(target, target_rect_, nullptr);
      }
    }
  }
  if (session_layout::ApplyVisibility(
          target, lesson_, overlay_, hint_, target_connected_once_,
          lesson_hidden_for_target_) == session_layout::Visibility::minimized) {
    active_ = false;
    if (web_page_) ShowWindow(web_page_, SW_HIDE);
    return;
  }
  HWND foreground = GetForegroundWindow();
  DWORD foreground_pid = 0, target_pid = 0;
  GetWindowThreadProcessId(foreground, &foreground_pid);
  if (target)
    GetWindowThreadProcessId(target, &target_pid);
  active_ = foreground == lesson_ || foreground == hint_ || foreground == web_page_ ||
            (target_pid && foreground_pid == target_pid);
  Place(lesson_, left, active_ ? HWND_TOPMOST : HWND_NOTOPMOST);
  if (target && active_ && IsWindowEnabled(target)) {
    if (IsZoomed(target))
      ShowWindow(target, SW_RESTORE);
    RECT actual{};
    GetWindowRect(target, &actual);
    if (!EqualRect(&actual, &target_rect_))
      placement_error_ = Place(target, target_rect_, nullptr);
  }
  // Hide decorations over dialogs and unrelated applications.
  bool decorate =
      active_ && target && IsWindowEnabled(target) && IsWindowVisible(target) && !web_page_visible_;
  if (overlay_) {
    Place(overlay_, target_rect_, decorate ? HWND_TOPMOST : HWND_NOTOPMOST);
    ShowWindow(overlay_, decorate ? SW_SHOWNOACTIVATE : SW_HIDE);
  }
  if (hint_) {
    const double scale = GetDpiForWindow(lesson_) / 96.0;
    const LONG w = static_cast<LONG>(360 * scale),
               h = static_cast<LONG>(210 * scale),
               margin = static_cast<LONG>(24 * scale);
    RECT rect{target_rect_.right - w - margin, target_rect_.bottom - h - margin,
              target_rect_.right - margin, target_rect_.bottom - margin};
    Place(hint_, rect, decorate ? HWND_TOPMOST : HWND_NOTOPMOST);
    ShowWindow(hint_, decorate && hint_visible_ ? SW_SHOWNOACTIVATE : SW_HIDE);
  }
  if (web_page_) {
    const auto rect = session_layout::CenteredActivity(monitor_, GetDpiForWindow(lesson_) / 96.0);
    Place(web_page_, rect, active_ ? HWND_TOPMOST : HWND_NOTOPMOST);
    ShowWindow(web_page_, web_page_visible_ ? SW_SHOWNOACTIVATE : SW_HIDE);
  }
}
void DesktopSession::SetWebPage(const std::string &url, const std::string &title,
                               const std::string &instructions) {
  {
    std::lock_guard<std::mutex> lock(mutex_);
    if (!url.empty()) {
      web_page_url_ = url;
      web_page_title_ = title;
      web_page_instructions_ = instructions;
    }
    web_page_visible_ = !url.empty();
    hover_target_ = EncodableValue();
    hover_geometry_ = EncodableValue();
    ++hover_generation_;
    hover_bounds_changed_.notify_all();
  }
  if (!url.empty() && web_page_) SetWindowTextW(web_page_, target_app::Wide(title).c_str());
  Tick();
  SetForegroundWindow(web_page_visible_ ? web_page_ : lesson_);
}
void DesktopSession::SetStep(int value) {
  step_ = std::max(value, 0);
  hint_visible_ = false;
  Tick();
}
void DesktopSession::SetHover(const EncodableValue &target) {
  std::lock_guard<std::mutex> lock(mutex_);
  hover_target_ = target;
  hover_geometry_ = EncodableValue();
  ++hover_generation_;
  hover_bounds_changed_.notify_all();
}

void DesktopSession::InspectHoverBounds() {
  // This thread owns all its UIA objects. No COM calls/releases occur while
  // holding mutex_, and no element references are shared with the tree scanner.
  CoInitializeEx(nullptr, COINIT_MULTITHREADED);
  {
    ComPtr<IUIAutomation> automation;
    HRESULT status = CoCreateInstance(CLSID_CUIAutomation8, nullptr,
        CLSCTX_INPROC_SERVER, IID_PPV_ARGS(&automation));
    if (FAILED(status)) CoCreateInstance(CLSID_CUIAutomation, nullptr,
        CLSCTX_INPROC_SERVER, IID_PPV_ARGS(&automation));
    ComPtr<IUIAutomation2> bounded;
    if (automation && SUCCEEDED(automation.As(&bounded))) {
      bounded->put_ConnectionTimeout(2000);
      bounded->put_TransactionTimeout(2000);
    }
    while (!stop_) {
      EncodableValue target;
      uint64_t generation = 0;
      {
        std::unique_lock<std::mutex> lock(mutex_);
        hover_bounds_changed_.wait(lock, [this] {
          return stop_ || (!hover_target_.IsNull() && !inspector_mode_);
        });
        if (stop_) break;
        target = hover_target_;
        generation = hover_generation_.load();
      }
      EncodableValue geometry;
      const auto cancelled = [this, generation] {
        return stop_ || hover_generation_.load() != generation;
      };
      if (automation) {
        // Resolve the complete path afresh, including newly created objects.
        const auto element = live_uia::Resolve(automation.Get(), target_.load(), target, cancelled);
        if (element && !cancelled()) {
          RECT rect{};
          BOOL offscreen = TRUE;
          if (SUCCEEDED((*element)->get_CurrentBoundingRectangle(&rect)) &&
              SUCCEEDED((*element)->get_CurrentIsOffscreen(&offscreen))) {
            const auto metadata = live_uia::Provider(nullptr, cancelled).Read(*element);
            AccessibilityNode node;
            node.id = RuntimeId(element->Get(), "hover-path");
            node.name = Utf8(metadata.name);
            node.type = Utf8(metadata.type);
            node.rect = rect;
            node.offscreen = offscreen != FALSE;
            if (metadata.valid) geometry = NodeValue(node);
          }
        }
      }
      {
        std::unique_lock<std::mutex> lock(mutex_);
        if (!cancelled() && !hover_target_.IsNull() && !inspector_mode_) {
          hover_geometry_ = std::move(geometry);
          hover_geometry_generation_ = generation;
        }
        // Continue checking while hovered; a missing object needs no re-entry.
        hover_bounds_changed_.wait_for(lock, std::chrono::milliseconds(200),
            [&] { return cancelled(); });
      }
    }
  }
  CoUninitialize();
}
void DesktopSession::SetHint(bool value) {
  hint_visible_ = value;
  Tick();
}
void DesktopSession::SetInspector(bool enabled) {
  {
    std::lock_guard<std::mutex> lock(mutex_);
    inspector_mode_ = enabled;
    if (enabled) {
      hover_target_ = EncodableValue();
      hover_geometry_ = EncodableValue();
      ++hover_generation_;
    }
    hover_bounds_changed_.notify_all();
  }
  hint_visible_ = false;
  if (overlay_)
    SetLayeredWindowAttributes(overlay_, RGB(1, 1, 1), enabled ? 96 : 255,
                               LWA_COLORKEY | LWA_ALPHA);
  Tick();
}
bool DesktopSession::SelectNode(const std::string &id) {
  std::lock_guard<std::mutex> lock(mutex_);
  if (!id.empty() &&
      std::none_of(nodes_.begin(), nodes_.end(),
                   [&](const auto &node) { return node.id == id; }))
    return false;
  selected_node_id_ = id;
  return true;
}
void DesktopSession::Restore() {
  if (web_page_) ShowWindow(web_page_, SW_HIDE);
  if (overlay_)
    ShowWindow(overlay_, SW_HIDE);
  if (hint_)
    ShowWindow(hint_, SW_HIDE);
  if (captured_ && IsWindow(target_.load())) {
    const auto candidate = target_app::Read(target_.load());
    if (candidate && target_app::Matches(*candidate, application_)) SetWindowPlacement(target_.load(), &original_);
  }
}
EncodableValue DesktopSession::State(bool include_nodes) {
  std::lock_guard<std::mutex> lock(mutex_);
  EncodableList targets;
  EncodableList nodes;
  EncodableValue selection;
  for (const auto &node : nodes_) {
    if (include_nodes && inspector_mode_) nodes.push_back(NodeValue(node));
    if (inspector_mode_ && node.id == selected_node_id_)
      selection = NodeValue(node);
  }
  // Only unique semantic names are marked; ambiguous matches remain textual.
  for (const auto &target : targets_) {

    if (std::count_if(targets_.begin(), targets_.end(), [&](const auto &other) {
          return other.name == target.name;
        }) != 1)
      continue;
    targets.emplace_back(EncodableMap{
        {EncodableValue("name"), EncodableValue(target.name)},
        {EncodableValue("left"),
         EncodableValue(static_cast<double>(target.rect.left))},
        {EncodableValue("top"),
         EncodableValue(static_cast<double>(target.rect.top))},
        {EncodableValue("width"), EncodableValue(static_cast<double>(
                                      target.rect.right - target.rect.left))},
        {EncodableValue("height"),
         EncodableValue(
             static_cast<double>(target.rect.bottom - target.rect.top))}});
  }
  return EncodableValue(EncodableMap{
      {EncodableValue("startupError"), EncodableValue(startup_error_)},
      {EncodableValue("connectionMethod"), EncodableValue(connection_method_)},
      {EncodableValue("placementError"),
       EncodableValue(static_cast<int32_t>(placement_error_))},
      {EncodableValue("inspectorMode"), EncodableValue(inspector_mode_)},
      {EncodableValue("nodes"), EncodableValue(nodes)},
      {EncodableValue("selectedNodeId"), EncodableValue(selected_node_id_)},
      {EncodableValue("selection"), selection},
      {EncodableValue("step"), EncodableValue(step_)},
      {EncodableValue("hoverTarget"), hover_target_},
      {EncodableValue("webPageVisible"), EncodableValue(web_page_visible_)},
      {EncodableValue("webPageUrl"), EncodableValue(web_page_url_)},
      {EncodableValue("webPageTitle"), EncodableValue(web_page_title_)},
      {EncodableValue("webPageInstructions"), EncodableValue(web_page_instructions_)},
      {EncodableValue("hoverGeometry"), hover_geometry_},
      {EncodableValue("hoverGeneration"), EncodableValue(static_cast<int64_t>(hover_generation_.load()))},
      {EncodableValue("hoverGeometryGeneration"), EncodableValue(static_cast<int64_t>(hover_geometry_generation_))},
      {EncodableValue("connected"),
       EncodableValue(IsWindow(target_.load()) != FALSE)},
      {EncodableValue("active"), EncodableValue(active_)},
      {EncodableValue("targetLeft"),
       EncodableValue(static_cast<double>(target_rect_.left))},
      {EncodableValue("targetTop"),
       EncodableValue(static_cast<double>(target_rect_.top))},
      {EncodableValue("targets"), EncodableValue(targets)},
      {EncodableValue("accessibilityReady"),
       EncodableValue(accessibility_ready_)}});
}

void DesktopSession::Inspect() {
  CoInitializeEx(nullptr, COINIT_MULTITHREADED);
  {
    ComPtr<IUIAutomation> automation;
    HRESULT automation_status =
        CoCreateInstance(CLSID_CUIAutomation8, nullptr, CLSCTX_INPROC_SERVER,
                         IID_PPV_ARGS(&automation));
    if (FAILED(automation_status))
      automation_status =
          CoCreateInstance(CLSID_CUIAutomation, nullptr, CLSCTX_INPROC_SERVER,
                           IID_PPV_ARGS(&automation));
    ComPtr<IUIAutomation2> bounded_automation;
    if (automation && SUCCEEDED(automation.As(&bounded_automation))) {
      bounded_automation->put_ConnectionTimeout(2000);
      bounded_automation->put_TransactionTimeout(2000);
    }
    auto stage = [&](const std::string &value) {
      std::lock_guard<std::mutex> lock(mutex_);
      inspection_stage_ = value;
    };
    while (!stop_) {
      stage("waiting-for-window");
      std::vector<AccessibleTarget> targets;
      std::string tree;
      std::vector<AccessibilityNode> nodes;
      bool ready = false;
      HRESULT accessibility_status = automation_status;
      HWND target = target_.load();
      if (automation && IsWindow(target)) {
        ComPtr<IUIAutomationElement> root;
        stage("element-from-handle");
        accessibility_status = automation->ElementFromHandle(target, &root);
        if (SUCCEEDED(accessibility_status)) {
          stage("raw-tree");
          tree = AccessibilityTree(automation.Get(), root.Get(), stop_, &nodes,
                                   &accessibility_status);
          if (stop_)
            break;
          ComPtr<IUIAutomationCondition> condition;
          automation->CreateTrueCondition(&condition);
          ComPtr<IUIAutomationElementArray> elements;
          stage("find-descendants");
          const HRESULT find_status =
              root->FindAll(TreeScope_Descendants, condition.Get(), &elements);
          if (FAILED(find_status))
            accessibility_status = find_status;
          if (SUCCEEDED(find_status)) {
            int count = 0;
            elements->get_Length(&count);
            ready = count > 5;
            const auto deadline =
                std::chrono::steady_clock::now() + std::chrono::seconds(10);
            for (int i = 0; i < std::min(count, 3000) && !stop_ &&
                            std::chrono::steady_clock::now() < deadline;
                 ++i) {
              ComPtr<IUIAutomationElement> element;
              elements->GetElement(i, &element);
              if (!element)
                continue;
              BOOL offscreen = TRUE;
              element->get_CurrentIsOffscreen(&offscreen);
              if (offscreen)
                continue;
              BSTR name = nullptr;
              if (FAILED(element->get_CurrentName(&name)) || !name)
                continue;
              std::string label = Utf8(name);
              SysFreeString(name);
              RECT rect{};
              element->get_CurrentBoundingRectangle(&rect);
              if (label.empty() || rect.right <= rect.left ||
                  rect.bottom <= rect.top)
                continue;
              targets.push_back({label, rect});
            }
          }
        }
      }
      {
        std::lock_guard<std::mutex> lock(mutex_);
        targets_ = std::move(targets);
        tree_snapshot_ = std::move(tree);
        nodes_ = std::move(nodes);
        inspection_stage_ = "snapshot-ready";
        accessibility_error_ = accessibility_status;
        accessibility_ready_ = ready;
      }
      for (int i = 0; i < 10 && !stop_; ++i)
        std::this_thread::sleep_for(std::chrono::milliseconds(100));
    }
  }
  CoUninitialize();
}
bool DesktopSession::Export(std::string *path) {
  std::string tree;
  {
    std::lock_guard<std::mutex> lock(mutex_);
    tree = tree_snapshot_;
  }
  if (tree.empty())
    return false;
  auto destination = ExecutableDirectory() / L"accessibility-tree.txt";
  std::ofstream output(destination, std::ios::binary);
  if (!output)
    return false;
  // UTF-8 BOM makes names and control types readable in Windows text editors.
  output << "\xEF\xBB\xBF" << tree;
  output.close();
  if (path)
    *path = Utf8(destination.wstring());
  return !output.fail();
}
bool DesktopSession::ExportConnection(std::string *path) {
  std::ostringstream report;
  report << "Schului Verbindungsdiagnose\n"
         << "launcher_pid=" << launched_pid_ << '\n'
         << "executable=" << Utf8(launched_executable_.wstring()) << '\n'
         << "connection_method=" << connection_method_ << '\n'
         << "connected=" << IsWindow(target_.load()) << '\n'
         << "active=" << active_ << '\n'
         << "placement_error=" << placement_error_ << '\n'
         << "startup_error=" << startup_error_ << '\n';
  for (const auto &window : target_app::Windows(&application_)) {
    DWORD pid = 0;
    GetWindowThreadProcessId(window.handle, &pid);
    RECT rect{};
    GetWindowRect(window.handle, &rect);
    report << "window=" << reinterpret_cast<uintptr_t>(window.handle)
           << " pid=" << pid << " title=" << Utf8(window.title)
           << " class=" << Utf8(window.window_class)
           << " path=" << Utf8(window.executable) << " rect=" << rect.left
           << ',' << rect.top << ',' << rect.right << ',' << rect.bottom << '\n';
  }
  {
    std::lock_guard<std::mutex> lock(mutex_);
    report << "inspection_stage=" << inspection_stage_ << '\n';
    report << "accessibility_hresult=" << std::hex
           << static_cast<unsigned long>(accessibility_error_) << std::dec
           << '\n'
           << "accessibility_ready=" << accessibility_ready_
           << " nodes=" << nodes_.size() << '\n';
  }
  wchar_t temp[MAX_PATH]{};
  GetTempPathW(MAX_PATH, temp);
  const std::vector<std::filesystem::path> destinations = {
      ExecutableDirectory() / L"connection-diagnostics.txt",
      std::filesystem::path(temp) /
          (L"schului-connection-" + std::to_wstring(GetCurrentProcessId()) +
           L".txt")};
  for (const auto &destination : destinations) {
    std::ofstream output(destination, std::ios::binary);
    if (!output)
      continue;
    output << "\xEF\xBB\xBF" << report.str();
    output.close();
    if (!output.fail()) {
      if (path)
        *path = Utf8(destination.wstring());
      return true;
    }
  }
  return false;
}
