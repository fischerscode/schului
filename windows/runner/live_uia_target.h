#ifndef RUNNER_LIVE_UIA_TARGET_H_
#define RUNNER_LIVE_UIA_TARGET_H_
#include "desktop_session.h"
#include "live_node_path.h"
#include <UIAutomation.h>
#include <wrl/client.h>
#include <chrono>
#include <functional>
#include <limits>

namespace live_uia {
using flutter::EncodableMap;
using flutter::EncodableList;
using flutter::EncodableValue;
using Microsoft::WRL::ComPtr;
using Handle = ComPtr<IUIAutomationElement>;
inline std::wstring Wide(const std::string &text) {
  if (text.empty()) return {};
  const int count = MultiByteToWideChar(CP_UTF8, 0, text.data(), static_cast<int>(text.size()), nullptr, 0);
  std::wstring result(count, L'\0');
  MultiByteToWideChar(CP_UTF8, 0, text.data(), static_cast<int>(text.size()), result.data(), count);
  return result;
}
inline const EncodableValue *Entry(const EncodableMap &map, const char *key) {
  const auto found = map.find(EncodableValue(key));
  return found == map.end() ? nullptr : &found->second;
}
inline bool Parse(const EncodableValue &target, std::vector<live_path::Segment> *path,
                  bool *includes_client) {
  const auto *map = std::get_if<EncodableMap>(&target);
  if (!map) return false;
  const auto *selector_value = Entry(*map, "selector");
  const auto *selector = selector_value ? std::get_if<EncodableMap>(selector_value) : nullptr;
  if (!selector) return false;
  const auto *path_value = Entry(*selector, "path");
  const auto *entries = path_value ? std::get_if<EncodableList>(path_value) : nullptr;
  if (!entries || entries->empty() || entries->size() > 64) return false;
  const auto *client_value = Entry(*map, "includesUnnamedClient");
  const auto *client = client_value ? std::get_if<bool>(client_value) : nullptr;
  *includes_client = client && *client;
  for (const auto &value : *entries) {
    const auto *entry = std::get_if<EncodableMap>(&value);
    if (!entry) return false;
    const auto *type_value = Entry(*entry, "type");
    const auto *type = type_value ? std::get_if<std::string>(type_value) : nullptr;
    if (!type) return false;
    live_path::Segment segment{Wide(*type), std::nullopt, std::nullopt};
    if (const auto *name_value = Entry(*entry, "name")) {
      const auto *name = std::get_if<std::string>(name_value);
      if (!name) return false;
      segment.name = Wide(*name);
    }
    if (const auto *index_value = Entry(*entry, "index")) {
      int64_t index = -1;
      if (const auto *small_index = std::get_if<int32_t>(index_value)) index = *small_index;
      else if (const auto *large_index = std::get_if<int64_t>(index_value)) index = *large_index;
      if (index < 0 || index > std::numeric_limits<int>::max() ||
          !segment.name || !live_path::Normalize(*segment.name).empty()) return false;
      segment.index = static_cast<int>(index);
    }
    if (live_path::Normalize(segment.type) == L"dokument" && path->size() + 1 < entries->size())
      segment.name.reset();
    path->push_back(std::move(segment));
  }
  return true;
}

class Provider {
 public:
  Provider(IUIAutomationTreeWalker *walker, std::function<bool()> cancelled)
      : walker_(walker), cancelled_(std::move(cancelled)),
        deadline_(std::chrono::steady_clock::now() + std::chrono::seconds(2)) {}
  bool Cancelled() const {
    return cancelled_() || std::chrono::steady_clock::now() >= deadline_;
  }
  live_path::Metadata Read(const Handle &element) {
    const auto found = metadata_.find(element.Get());
    if (found != metadata_.end()) return found->second;
    BSTR name = nullptr, type = nullptr;
    const HRESULT name_status = element->get_CurrentName(&name);
    const HRESULT type_status = element->get_CurrentLocalizedControlType(&type);
    live_path::Metadata value{type ? type : L"", name ? name : L"",
        SUCCEEDED(name_status) && SUCCEEDED(type_status)};
    SysFreeString(name);
    SysFreeString(type);
    metadata_[element.Get()] = value;
    // Hold the handles for this query only, preventing pointer reuse in Read.
    handles_.push_back(element);
    return value;
  }
  std::optional<std::vector<Handle>> Children(const Handle &parent) {
    std::vector<Handle> children;
    Handle child;
    if (FAILED(walker_->GetFirstChildElement(parent.Get(), &child))) return std::nullopt;
    while (child) {
      if (Cancelled() || children.size() >= 3000) return std::nullopt;
      children.push_back(child);
      Handle next;
      if (FAILED(walker_->GetNextSiblingElement(child.Get(), &next))) return std::nullopt;
      child = std::move(next);
    }
    return children;
  }
 private:
  IUIAutomationTreeWalker *walker_;
  std::function<bool()> cancelled_;
  std::chrono::steady_clock::time_point deadline_;
  std::map<IUIAutomationElement *, live_path::Metadata> metadata_;
  std::vector<Handle> handles_;
};

inline std::optional<Handle> Resolve(IUIAutomation *automation, HWND draw,
    const EncodableValue &target, const std::function<bool()> &cancelled) {
  std::vector<live_path::Segment> path;
  bool includes_client = false;
  if (!Parse(target, &path, &includes_client) || cancelled() || !IsWindow(draw)) return std::nullopt;
  Handle root;
  ComPtr<IUIAutomationTreeWalker> walker;
  if (FAILED(automation->ElementFromHandle(draw, &root)) ||
      FAILED(automation->get_RawViewWalker(&walker))) return std::nullopt;
  Provider provider(walker.Get(), cancelled);
  const auto root_metadata = provider.Read(root);
  const auto children = provider.Children(root);
  if (!root_metadata.valid || !children) return std::nullopt;
  bool named_client = false;
  for (const auto &child : *children) {
    const auto metadata = provider.Read(child);
    if (!metadata.valid || provider.Cancelled()) return std::nullopt;
    if (live_path::TitleWrapper(metadata, root_metadata)) named_client = true;
  }
  std::vector<std::vector<live_path::Segment>> paths{path};
  if (includes_client && named_client && path.size() > 2) {
    auto variant = path;
    variant.erase(variant.begin() + 1);
    paths.push_back(std::move(variant));
  } else if (!includes_client && !named_client) {
    auto variant = path;
    variant.insert(variant.begin() + 1, live_path::Segment{L"", L"", 0});
    paths.push_back(std::move(variant));
  }
  for (const auto &candidate : paths) {
    auto result = live_path::Resolve(root, candidate, provider);
    if (result.failed || result.ambiguous || provider.Cancelled()) return std::nullopt;
    if (result.node) return result.node;
    auto legacy = candidate;
    for (auto &segment : legacy) if (segment.type.empty()) segment.type = L"Element";
    result = live_path::Resolve(root, legacy, provider);
    if (result.failed || result.ambiguous || provider.Cancelled()) return std::nullopt;
    if (result.node) return result.node;
  }
  return std::nullopt;
}
} // namespace live_uia
#endif
