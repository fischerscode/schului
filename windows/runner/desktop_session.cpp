#include "desktop_session.h"
#include "session_layout.h"
#include "live_uia_target.h"
#include <UIAutomation.h>
#include <algorithm>
#include <chrono>
#include <cwctype>
#include <filesystem>
#include <fstream>
#include <functional>
#include <set>
#include <shellapi.h>
#include <shlwapi.h>
#include <sstream>
#include <tlhelp32.h>
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
struct ProcessDetails {
  std::wstring path;
  unsigned long long created = 0;
  DWORD error = 0;
};
ProcessDetails ReadProcess(DWORD pid) {
  ProcessDetails result;
  HANDLE process = OpenProcess(PROCESS_QUERY_LIMITED_INFORMATION, FALSE, pid);
  if (!process) {
    result.error = GetLastError();
    return result;
  }
  wchar_t path[32768]{};
  DWORD length = 32768;
  if (QueryFullProcessImageNameW(process, 0, path, &length))
    result.path = path;
  else
    result.error = GetLastError();
  FILETIME created{}, exited{}, kernel{}, user{};
  if (GetProcessTimes(process, &created, &exited, &kernel, &user))
    result.created = FileTimeValue(created);
  else
    result.error = GetLastError();
  CloseHandle(process);
  return result;
}
bool IsOfficeProcess(const ProcessDetails &process) {
  auto name = std::filesystem::path(process.path).filename().wstring();
  std::transform(name.begin(), name.end(), name.begin(),
                 [](wchar_t c) { return std::towlower(c); });
  return name == L"soffice.bin" || name == L"soffice.exe";
}
DWORD ReadPidFile(const std::filesystem::path &path) {
  if (path.empty())
    return 0;
  std::ifstream input(path);
  unsigned long long pid = 0;
  if (!(input >> pid) || !pid || pid > MAXDWORD)
    return 0;
  input >> std::ws;
  return input.eof() ? static_cast<DWORD>(pid) : 0;
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
  else if (role == "learningApp")
    learning_app_ = hwnd;
  else
    lesson_ = hwnd;
  SetWindowLongPtr(hwnd, GWL_STYLE, WS_POPUP | WS_CLIPCHILDREN);
  if (role == "learningApp") {
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
  draw_adapter_ = config->draw;
  return true;
}
EncodableValue DesktopSession::ApplicationWindows() { return EncodableValue(target_app::List(&application_)); }
bool DesktopSession::SelectApplicationWindow(int64_t handle) {
  const auto window = reinterpret_cast<HWND>(static_cast<intptr_t>(handle));
  auto candidate = target_app::Read(window);
  if (!candidate || !target_app::Matches(*candidate, application_) || captured_) return false;
  preferred_window_ = window;
  draw_ = nullptr;
  Tick();
  return true;
}
bool DesktopSession::StartApplication(std::string *error) {
  startup_error_.clear();
  if (IsWindow(draw_.load()) || FindDraw()) return true;
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
bool DesktopSession::Start(std::string *error) {
  if (!application_.draw) return StartApplication(error);
  startup_error_.clear();
  if (IsWindow(draw_.load()))
    return true;
  if (launched_pid_ && FindDraw())
    return true;
  if (launched_pid_) {
    HANDLE launcher = OpenProcess(SYNCHRONIZE, FALSE, launched_pid_);
    const bool running =
        launcher && WaitForSingleObject(launcher, 0) == WAIT_TIMEOUT;
    if (launcher)
      CloseHandle(launcher);
    if (running) {
      startup_error_ = *error = "Draw startet noch. Bitte kurz warten.";
      return false;
    }
    // A launcher may exit while its real office process is still starting.
    if (std::any_of(session_processes_.begin(), session_processes_.end(),
                    [](const auto &entry) {
                      return entry.second != 0 &&
                             ReadProcess(entry.first).created == entry.second;
                    })) {
      startup_error_ = *error = "Draw startet noch. Bitte kurz warten.";
      return false;
    }
    FILETIME now{};
    GetSystemTimeAsFileTime(&now);
    if (launch_time_ && FileTimeValue(now) - launch_time_ < 300000000ULL) {
      startup_error_ = *error = "Draw startet noch. Bitte kurz warten.";
      return false;
    }
    launched_pid_ = 0;
    captured_ = false;
  }
  const auto root = ExecutableDirectory();
  std::vector<std::filesystem::path> candidates = {
      root / L"LibreOfficePortable" / L"LibreOfficeDrawPortable.exe",
      root / L"LibreOfficePortable" / L"LibreOfficePortable.exe",
      L"C:\\Program Files\\LibreOffice\\program\\soffice.exe",
      L"C:\\Program Files (x86)\\LibreOffice\\program\\soffice.exe"};
  wchar_t custom[32768]{};
  if (GetEnvironmentVariableW(L"SCHULUI_DRAW_PATH", custom, 32768))
    candidates.insert(candidates.begin(), custom);
  std::filesystem::path executable;
  for (const auto &candidate : candidates)
    if (std::filesystem::is_regular_file(candidate)) {
      executable = candidate;
      break;
    }
  if (executable.empty()) {
    startup_error_ = *error =
        "LibreOffice nicht gefunden. SCHULUI_DRAW_PATH auf den "
        "Programmpfad setzen.";
    return false;
  }
  wchar_t temp[MAX_PATH]{};
  GetTempPathW(MAX_PATH, temp);
  FILETIME started{};
  GetSystemTimeAsFileTime(&started);
  launch_time_ = FileTimeValue(started);
  auto profile = std::filesystem::path(temp) /
                 (L"schului-profile-" + std::to_wstring(GetCurrentProcessId()) +
                  L"-" + std::to_wstring(launch_time_));
  pid_file_ = profile / L"draw.pid";
  launched_executable_ = executable;
  session_processes_.clear();
  connection_method_.clear();
  std::error_code filesystem_error;
  std::filesystem::create_directories(profile / L"user", filesystem_error);
  if (filesystem_error) {
    startup_error_ = *error =
        "Das temporäre Draw-Profil konnte nicht angelegt werden.";
    return false;
  }
  std::ofstream settings(profile / L"user" / L"registrymodifications.xcu");
  settings
      << R"(<?xml version="1.0" encoding="UTF-8"?><oor:items xmlns:oor="http://openoffice.org/2001/registry" xmlns:xs="http://www.w3.org/2001/XMLSchema"><item oor:path="/org.openoffice.Office.Common/Misc"><prop oor:name="FirstRun" oor:op="fuse"><value>false</value></prop><prop oor:name="ShowTipOfTheDay" oor:op="fuse"><value>false</value></prop></item><item oor:path="/org.openoffice.Setup/Office"><prop oor:name="MigrationCompleted" oor:op="fuse"><value>true</value></prop></item><item oor:path="/org.openoffice.Setup/Product"><prop oor:name="WhatsNew" oor:op="fuse"><value>false</value></prop><prop oor:name="WhatsNewDialog" oor:op="fuse"><value>false</value></prop></item><item oor:path="/org.openoffice.Office.Update/Update"><prop oor:name="Enabled" oor:op="fuse" oor:finalized="true"><value>false</value></prop></item><item oor:path="/org.openoffice.Office.Jobs/Jobs/org.openoffice.Office.Jobs:Job['UpdateCheck']/Arguments"><prop oor:name="AutoCheckEnabled" oor:type="xs:boolean" oor:op="fuse" oor:finalized="true"><value>false</value></prop><prop oor:name="AutoDownloadEnabled" oor:type="xs:boolean" oor:op="fuse" oor:finalized="true"><value>false</value></prop></item></oor:items>)";
  settings.close();
  if (!settings) {
    startup_error_ = *error =
        "Das Draw-Lernprofil konnte nicht vorbereitet werden.";
    return false;
  }
  wchar_t url[32768]{};
  DWORD url_length = 32768;
  if (FAILED(UrlCreateFromPathW(profile.c_str(), url, &url_length, 0))) {
    startup_error_ = *error =
        "Der Draw-Profilpfad konnte nicht erzeugt werden.";
    return false;
  }
  std::wstring command = L"\"" + executable.wstring() +
                         L"\" --draw \"-env:UserInstallation=" + url +
                         L"\" \"--pidfile=" + pid_file_.wstring() + L"\"";
  STARTUPINFOW startup{};
  startup.cb = sizeof(startup);
  PROCESS_INFORMATION process{};
  // Dedicated profile prevents taking over already-open pupil documents.
  if (!CreateProcessW(executable.c_str(), command.data(), nullptr, nullptr,
                      FALSE, 0, nullptr, executable.parent_path().c_str(),
                      &startup, &process)) {
    startup_error_ = *error =
        "LibreOffice konnte nicht gestartet werden (Windows-Fehler " +
        std::to_string(GetLastError()) + ").";
    return false;
  }
  launched_pid_ = process.dwProcessId;
  session_processes_[launched_pid_] = ReadProcess(launched_pid_).created;
  CloseHandle(process.hThread);
  CloseHandle(process.hProcess);
  return true;
}

HWND DesktopSession::FindDraw() {
  if (!application_.draw) {
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
  if (!launched_pid_)
    return nullptr;
  // Prefer the actual office PID, independent of launcher/updater ancestry.
  const DWORD office_pid = ReadPidFile(pid_file_);
  const auto office = office_pid ? ReadProcess(office_pid) : ProcessDetails{};
  const bool valid_pid = office.created >= launch_time_ &&
                         office.created != 0 && IsOfficeProcess(office);
  HANDLE snapshot = CreateToolhelp32Snapshot(TH32CS_SNAPPROCESS, 0);
  if (snapshot != INVALID_HANDLE_VALUE) {
    PROCESSENTRY32W entry{};
    entry.dwSize = sizeof(entry);
    std::vector<std::pair<DWORD, DWORD>> processes;
    if (Process32FirstW(snapshot, &entry))
      do {
        processes.emplace_back(entry.th32ProcessID, entry.th32ParentProcessID);
      } while (Process32NextW(snapshot, &entry));
    CloseHandle(snapshot);
    bool changed = true;
    while (changed) {
      changed = false;
      for (const auto &process : processes) {
        auto parent = session_processes_.find(process.second);
        if (parent == session_processes_.end())
          continue;
        // Retain exited parents, but do not follow reused PIDs.
        auto current_parent = ReadProcess(process.second);
        if (current_parent.created && current_parent.created != parent->second)
          continue;
        auto details = ReadProcess(process.first);
        if (!details.created || details.created < launch_time_ ||
            details.created < parent->second)
          continue;
        if (!session_processes_.count(process.first) ||
            session_processes_[process.first] != details.created) {
          session_processes_[process.first] = details.created;
          changed = true;
        }
      }
    }
  }
  struct Search {
    DesktopSession *session;
    DWORD office_pid;
    HWND authoritative = nullptr;
    std::vector<HWND> descendants;
  } search{this, valid_pid ? office_pid : 0, nullptr, {}};
  EnumWindows(
      [](HWND hwnd, LPARAM parameter) -> BOOL {
        auto *search = reinterpret_cast<Search *>(parameter);
        if (!IsWindowVisible(hwnd) || GetWindow(hwnd, GW_OWNER))
          return TRUE;
        wchar_t title[1024]{};
        GetWindowTextW(hwnd, title, 1024);
        if (std::wstring(title).find(L"LibreOffice Draw") == std::wstring::npos)
          return TRUE;
        DWORD pid = 0;
        GetWindowThreadProcessId(hwnd, &pid);
        if (pid == search->office_pid) {
          search->authoritative = hwnd;
          return FALSE;
        }
        auto known = search->session->session_processes_.find(pid);
        if (known != search->session->session_processes_.end()) {
          auto details = ReadProcess(pid);
          if (details.created == known->second && IsOfficeProcess(details))
            search->descendants.push_back(hwnd);
        }
        return TRUE;
      },
      reinterpret_cast<LPARAM>(&search));
  connection_method_ = search.authoritative             ? "pidfile"
                       : search.descendants.size() == 1 ? "tracked-process"
                                                        : "not-found";
  return search.authoritative             ? search.authoritative
         : search.descendants.size() == 1 ? search.descendants.front()
                                          : nullptr;
}

void DesktopSession::Tick() {
  if (!lesson_)
    return;
  MONITORINFO info{sizeof(MONITORINFO)};
  GetMonitorInfoW(MonitorFromWindow(lesson_, MONITOR_DEFAULTTOPRIMARY), &info);
  monitor_ = info.rcWork;
  const auto bounds = session_layout::SplitWorkArea(monitor_);
  const RECT left = bounds.lesson;
  draw_rect_ = bounds.draw;
  HWND draw = draw_.load();
  if (draw && !application_.draw) {
    const auto candidate = target_app::Read(draw);
    if (!candidate || !target_app::Matches(*candidate, application_)) { draw_ = nullptr; draw = nullptr; }
  }
  if (session_layout::ApplyVisibility(
          draw, lesson_, overlay_, hint_, draw_connected_once_,
          lesson_hidden_for_draw_) == session_layout::Visibility::closed) {
    active_ = false;
    if (learning_app_) ShowWindow(learning_app_, SW_HIDE);
    PostQuitMessage(0);
    return;
  }
  if (!IsWindow(draw)) {
    draw = FindDraw();
    draw_ = draw;
    if (draw && !captured_) {
      GetWindowPlacement(draw, &original_);
      captured_ = true;
      draw_connected_once_ = true;
      if (IsWindowEnabled(draw) && !IsIconic(draw)) {
        ShowWindow(draw, SW_RESTORE);
        placement_error_ = Place(draw, draw_rect_, nullptr);
      }
    }
  }
  if (session_layout::ApplyVisibility(
          draw, lesson_, overlay_, hint_, draw_connected_once_,
          lesson_hidden_for_draw_) == session_layout::Visibility::minimized) {
    active_ = false;
    if (learning_app_) ShowWindow(learning_app_, SW_HIDE);
    return;
  }
  HWND foreground = GetForegroundWindow();
  DWORD foreground_pid = 0, draw_pid = 0;
  GetWindowThreadProcessId(foreground, &foreground_pid);
  if (draw)
    GetWindowThreadProcessId(draw, &draw_pid);
  active_ = foreground == lesson_ || foreground == hint_ || foreground == learning_app_ ||
            (draw_pid && foreground_pid == draw_pid);
  Place(lesson_, left, active_ ? HWND_TOPMOST : HWND_NOTOPMOST);
  if (draw && active_ && IsWindowEnabled(draw)) {
    if (IsZoomed(draw))
      ShowWindow(draw, SW_RESTORE);
    RECT actual{};
    GetWindowRect(draw, &actual);
    if (!EqualRect(&actual, &draw_rect_))
      placement_error_ = Place(draw, draw_rect_, nullptr);
  }
  // Hide decorations over dialogs and unrelated applications.
  bool decorate =
      active_ && draw && IsWindowEnabled(draw) && IsWindowVisible(draw) && !learning_app_visible_;
  if (overlay_) {
    Place(overlay_, draw_rect_, decorate ? HWND_TOPMOST : HWND_NOTOPMOST);
    ShowWindow(overlay_, decorate ? SW_SHOWNOACTIVATE : SW_HIDE);
  }
  if (hint_) {
    const double scale = GetDpiForWindow(lesson_) / 96.0;
    const LONG w = static_cast<LONG>(360 * scale),
               h = static_cast<LONG>(210 * scale),
               margin = static_cast<LONG>(24 * scale);
    RECT rect{draw_rect_.right - w - margin, draw_rect_.bottom - h - margin,
              draw_rect_.right - margin, draw_rect_.bottom - margin};
    Place(hint_, rect, decorate ? HWND_TOPMOST : HWND_NOTOPMOST);
    ShowWindow(hint_, decorate && hint_visible_ ? SW_SHOWNOACTIVATE : SW_HIDE);
  }
  if (learning_app_) {
    const auto rect = session_layout::CenteredActivity(monitor_, GetDpiForWindow(lesson_) / 96.0);
    Place(learning_app_, rect, active_ ? HWND_TOPMOST : HWND_NOTOPMOST);
    ShowWindow(learning_app_, learning_app_visible_ ? SW_SHOWNOACTIVATE : SW_HIDE);
  }
}
void DesktopSession::SetLearningApp(const std::string &url) {
  {
    std::lock_guard<std::mutex> lock(mutex_);
    if (!url.empty()) learning_app_url_ = url;
    learning_app_visible_ = !url.empty();
    hover_target_ = EncodableValue();
    hover_geometry_ = EncodableValue();
    ++hover_generation_;
    hover_bounds_changed_.notify_all();
  }
  Tick();
  SetForegroundWindow(learning_app_visible_ ? learning_app_ : lesson_);
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
        const auto element = live_uia::Resolve(automation.Get(), draw_.load(), target, cancelled);
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
  if (learning_app_) ShowWindow(learning_app_, SW_HIDE);
  if (overlay_)
    ShowWindow(overlay_, SW_HIDE);
  if (hint_)
    ShowWindow(hint_, SW_HIDE);
  if (captured_ && IsWindow(draw_.load())) {
    const auto candidate = application_.draw ? std::optional<target_app::Window>{} : target_app::Read(draw_.load());
    if (application_.draw || (candidate && target_app::Matches(*candidate, application_))) SetWindowPlacement(draw_.load(), &original_);
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
      {EncodableValue("learningAppVisible"), EncodableValue(learning_app_visible_)},
      {EncodableValue("learningAppUrl"), EncodableValue(learning_app_url_)},
      {EncodableValue("hoverGeometry"), hover_geometry_},
      {EncodableValue("hoverGeneration"), EncodableValue(static_cast<int64_t>(hover_generation_.load()))},
      {EncodableValue("hoverGeometryGeneration"), EncodableValue(static_cast<int64_t>(hover_geometry_generation_))},
      {EncodableValue("connected"),
       EncodableValue(IsWindow(draw_.load()) != FALSE)},
      {EncodableValue("active"), EncodableValue(active_)},
      {EncodableValue("drawLeft"),
       EncodableValue(static_cast<double>(draw_rect_.left))},
      {EncodableValue("drawTop"),
       EncodableValue(static_cast<double>(draw_rect_.top))},
      {EncodableValue("targets"), EncodableValue(targets)},
      {EncodableValue("accessibilityReady"),
       EncodableValue(accessibility_ready_)},
      {EncodableValue("sidebarVisible"), EncodableValue(sidebar_visible_)}});
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
      bool ready = false, sidebar = false;
      HRESULT accessibility_status = automation_status;
      HWND draw = draw_.load();
      if (automation && IsWindow(draw)) {
        ComPtr<IUIAutomationElement> root;
        stage("element-from-handle");
        accessibility_status = automation->ElementFromHandle(draw, &root);
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
              CONTROLTYPEID type = 0;
              element->get_CurrentControlType(&type);
              if (draw_adapter_ && ((label == "Seitenleiste" && type == UIA_PaneControlTypeId) ||
                  (label == "Seitenleiste schließen" &&
                   type == UIA_ButtonControlTypeId)))
                sidebar = true;
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
        sidebar_visible_ = sidebar;
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
         << "pid_file=" << Utf8(pid_file_.wstring()) << '\n'
         << "office_pid=" << ReadPidFile(pid_file_) << '\n'
         << "connection_method=" << connection_method_ << '\n'
         << "connected=" << IsWindow(draw_.load()) << '\n'
         << "active=" << active_ << '\n'
         << "placement_error=" << placement_error_ << '\n'
         << "startup_error=" << startup_error_ << '\n';
  for (const auto &entry : session_processes_) {
    auto details = ReadProcess(entry.first);
    report << "tracked_pid=" << entry.first << " created=" << entry.second
           << " current_created=" << details.created
           << " error=" << details.error << " path=" << Utf8(details.path)
           << '\n';
  }
  struct Windows {
    std::ostringstream *report;
    std::map<DWORD, unsigned long long> *known;
  } windows{&report, &session_processes_};
  EnumWindows(
      [](HWND hwnd, LPARAM raw) -> BOOL {
        auto *data = reinterpret_cast<Windows *>(raw);
        wchar_t title[1024]{}, class_name[256]{};
        GetWindowTextW(hwnd, title, 1024);
        const std::wstring text = title;
        DWORD pid = 0;
        GetWindowThreadProcessId(hwnd, &pid);
        if (text.find(L"LibreOffice") == std::wstring::npos &&
            !data->known->count(pid))
          return TRUE;
        GetClassNameW(hwnd, class_name, 256);
        auto process = ReadProcess(pid);
        RECT rect{};
        GetWindowRect(hwnd, &rect);
        *data->report << "window=" << reinterpret_cast<uintptr_t>(hwnd)
                      << " pid=" << pid << " title=" << Utf8(text)
                      << " class=" << Utf8(class_name)
                      << " visible=" << IsWindowVisible(hwnd)
                      << " enabled=" << IsWindowEnabled(hwnd) << " owner="
                      << reinterpret_cast<uintptr_t>(GetWindow(hwnd, GW_OWNER))
                      << " process_error=" << process.error
                      << " path=" << Utf8(process.path) << " rect=" << rect.left
                      << ',' << rect.top << ',' << rect.right << ','
                      << rect.bottom << '\n';
        return TRUE;
      },
      reinterpret_cast<LPARAM>(&windows));
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

void DesktopSession::SmokeTest() {
  Export(nullptr);
  ExportConnection(nullptr);
  std::ofstream report(ExecutableDirectory() / L"smoke-test.txt");
  RECT lesson_rect{}, overlay_rect{}, hint_rect{}, draw_rect{};
  GetWindowRect(lesson_, &lesson_rect);
  GetWindowRect(overlay_, &overlay_rect);
  GetWindowRect(hint_, &hint_rect);
  if (IsWindow(draw_.load()))
    GetWindowRect(draw_.load(), &draw_rect);
  auto print_rect = [&](const char *name, const RECT &rect) {
    report << name << '=' << rect.left << ',' << rect.top << ',' << rect.right
           << ',' << rect.bottom << '\n';
  };
  print_rect("work_area", monitor_);
  print_rect("lesson", lesson_rect);
  print_rect("draw", draw_rect);
  print_rect("overlay", overlay_rect);
  print_rect("hint", hint_rect);
  report << "connection_method=" << connection_method_ << '\n';
  report << "connected=" << IsWindow(draw_.load()) << '\n'
         << "active=" << active_ << '\n';
  report << "overlay_visible=" << IsWindowVisible(overlay_) << '\n';
  report << "overlay_click_through="
         << ((GetWindowLongPtr(overlay_, GWL_EXSTYLE) & WS_EX_TRANSPARENT) != 0)
         << '\n';
  report << "hint_visible=" << IsWindowVisible(hint_) << '\n';
  std::lock_guard<std::mutex> lock(mutex_);
  report << "accessibility_ready=" << accessibility_ready_ << '\n'
         << "element_count=" << targets_.size() << '\n';
  std::set<std::string> node_ids;
  bool selection_exists = false;
  for (const auto &node : nodes_) {
    node_ids.insert(node.id);
    if (node.id == selected_node_id_)
      selection_exists = true;
  }
  BYTE alpha = 0;
  DWORD flags = 0;
  COLORREF key = 0;
  GetLayeredWindowAttributes(overlay_, &key, &alpha, &flags);
  report << "node_count=" << nodes_.size() << '\n'
         << "unique_node_ids=" << node_ids.size() << '\n'
         << "inspector_mode=" << inspector_mode_ << '\n'
         << "selected_node_exists=" << selection_exists << '\n'
         << "selected_node_id=" << selected_node_id_ << '\n'
         << "overlay_alpha=" << static_cast<int>(alpha) << '\n';
}
