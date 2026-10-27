#ifndef RUNNER_APPLICATION_CONFIG_H_
#define RUNNER_APPLICATION_CONFIG_H_
#include <windows.h>
#include <flutter/encodable_value.h>
#include <filesystem>
#include "live_node_path.h"

namespace target_app {
using flutter::EncodableValue;
using flutter::EncodableMap;
using flutter::EncodableList;
struct Config {
  bool draw = true;
  std::wstring name = L"LibreOffice Draw", executable, window_class, title_contains;
  std::vector<std::wstring> arguments;
};
inline std::wstring Wide(const std::string &text) {
  if (text.empty()) return {};
  int count = MultiByteToWideChar(CP_UTF8, 0, text.data(), static_cast<int>(text.size()), nullptr, 0);
  std::wstring result(count, L'\0');
  MultiByteToWideChar(CP_UTF8, 0, text.data(), static_cast<int>(text.size()), result.data(), count);
  return result;
}
inline std::string Utf8(const std::wstring &text) {
  if (text.empty()) return {};
  int count = WideCharToMultiByte(CP_UTF8, 0, text.data(), static_cast<int>(text.size()), nullptr, 0, nullptr, nullptr);
  std::string result(count, '\0');
  WideCharToMultiByte(CP_UTF8, 0, text.data(), static_cast<int>(text.size()), result.data(), count, nullptr, nullptr);
  return result;
}
inline std::optional<std::wstring> Text(const EncodableMap &map, const char *key, bool empty = false) {
  auto it = map.find(EncodableValue(key));
  if (it == map.end()) return std::nullopt;
  auto value = std::get_if<std::string>(&it->second);
  if (!value || value->size() > 32768 || value->find('\0') != std::string::npos || (!empty && value->empty())) return std::nullopt;
  return Wide(*value);
}
inline std::optional<Config> Parse(const EncodableValue &raw) {
  const auto *map = std::get_if<EncodableMap>(&raw);
  if (!map) return std::nullopt;
  auto kind = Text(*map, "kind");
  if (kind == L"libreoffice.draw") return Config{};
  if (kind != L"windows") return std::nullopt;
  auto name = Text(*map, "name"), executable = Text(*map, "executable");
  auto cls = Text(*map, "windowClass", true), title = Text(*map, "titleContains", true);
  auto args = map->find(EncodableValue("arguments"));
  const auto *list = args == map->end() ? nullptr : std::get_if<EncodableList>(&args->second);
  if (!name || !executable || !cls || !title || !list || list->size() > 100 || !std::filesystem::path(*executable).is_absolute()) return std::nullopt;
  Config result;
  result.draw = false; result.name = *name; result.executable = *executable;
  result.window_class = *cls; result.title_contains = *title;
  for (const auto &entry : *list) {
    const auto *value = std::get_if<std::string>(&entry);
    if (!value || value->size() > 32768 || value->find('\0') != std::string::npos) return std::nullopt;
    result.arguments.push_back(Wide(*value));
  }
  return result;
}
inline std::wstring Quote(const std::wstring &argument) {
  std::wstring result = L"\"";
  size_t slashes = 0;
  for (wchar_t c : argument) {
    if (c == L'\\') { ++slashes; continue; }
    result.append(c == L'"' ? slashes * 2 + 1 : slashes, L'\\');
    result.push_back(c); slashes = 0;
  }
  result.append(slashes * 2, L'\\');
  return result + L"\"";
}
struct Window {
  HWND handle;
  std::wstring executable, title, window_class;
};
inline std::optional<Window> Read(HWND window) {
  if (!IsWindowVisible(window) || GetWindow(window, GW_OWNER) || (GetWindowLongPtr(window, GWL_EXSTYLE) & WS_EX_TOOLWINDOW)) return std::nullopt;
  DWORD pid = 0; GetWindowThreadProcessId(window, &pid);
  if (pid == GetCurrentProcessId()) return std::nullopt;
  wchar_t title[2048]{}, cls[512]{}, executable[32768]{};
  if (!GetWindowTextW(window, title, 2048)) return std::nullopt;
  GetClassNameW(window, cls, 512);
  HANDLE process = OpenProcess(PROCESS_QUERY_LIMITED_INFORMATION, FALSE, pid);
  if (!process) return std::nullopt;
  DWORD length = 32768;
  bool valid = QueryFullProcessImageNameW(process, 0, executable, &length) != FALSE;
  CloseHandle(process);
  if (!valid) return std::nullopt;
  return Window{window, executable, title, cls};
}
inline bool SameExecutable(const std::wstring &left, const std::wstring &right) {
  const auto a = std::filesystem::path(left).lexically_normal().make_preferred().wstring();
  const auto b = std::filesystem::path(right).lexically_normal().make_preferred().wstring();
  return CompareStringOrdinal(a.c_str(), -1, b.c_str(), -1, TRUE) == CSTR_EQUAL;
}
inline bool Matches(const Window &window, const Config &config) {
  if (config.draw) return live_path::Normalize(std::filesystem::path(window.executable).filename().wstring()) == L"soffice.bin" && window.title.find(L"LibreOffice Draw") != std::wstring::npos;
  return SameExecutable(window.executable, config.executable) &&
    (config.window_class.empty() || window.window_class == config.window_class) &&
    (config.title_contains.empty() || live_path::Normalize(window.title).find(live_path::Normalize(config.title_contains)) != std::wstring::npos);
}
inline std::vector<Window> Windows(const Config *filter = nullptr) {
  struct Search { const Config *filter; std::vector<Window> windows; } search{filter, {}};
  EnumWindows([](HWND handle, LPARAM data) -> BOOL {
    auto *search = reinterpret_cast<Search *>(data);
    auto window = Read(handle);
    if (window && (!search->filter || Matches(*window, *search->filter))) search->windows.push_back(*window);
    return TRUE;
  }, reinterpret_cast<LPARAM>(&search));
  return search.windows;
}
inline EncodableList List(const Config *filter = nullptr) {
  EncodableList result;
  for (const auto &window : Windows(filter)) result.emplace_back(EncodableMap{
    {EncodableValue("id"), EncodableValue(static_cast<int64_t>(reinterpret_cast<intptr_t>(window.handle)))},
    {EncodableValue("title"), EncodableValue(Utf8(window.title))},
    {EncodableValue("executable"), EncodableValue(Utf8(window.executable))},
    {EncodableValue("windowClass"), EncodableValue(Utf8(window.window_class))}});
  return result;
}
}
#endif
