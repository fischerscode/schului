#ifndef RUNNER_LIVE_NODE_PATH_H_
#define RUNNER_LIVE_NODE_PATH_H_
#include <cwctype>
#include <map>
#include <optional>
#include <string>
#include <vector>

namespace live_path {
inline std::wstring Normalize(const std::wstring &value) {
  std::wstring result;
  bool space = false;
  for (wchar_t ch : value) {
    if (std::iswspace(ch)) { space = !result.empty(); continue; }
    if (space) result.push_back(L' ');
    result.push_back(static_cast<wchar_t>(std::towlower(ch)));
    space = false;
  }
  return result;
}
struct Segment {
  std::wstring type;
  std::optional<std::wstring> name;
  std::optional<int> index;
};
struct Metadata {
  std::wstring type, name;
  bool valid = true;
};
inline bool Matches(const Segment &segment, const Metadata &node) {
  return Normalize(segment.type) == Normalize(node.type) &&
      (!segment.name || Normalize(*segment.name) == Normalize(node.name));
}
inline bool TitleWrapper(const Metadata &node, const Metadata &root) {
  const auto type = Normalize(node.type);
  return (type.empty() || type == L"element") &&
      !Normalize(node.name).empty() && Normalize(node.name) == Normalize(root.name);
}
template <typename Handle> struct Result {
  std::optional<Handle> node;
  bool ambiguous = false, failed = false;
};

// Provider reads the live siblings at each path segment, not a saved tree.
// Unreadable siblings invalidate indexed selection rather than shifting indices.
template <typename Handle, typename Provider>
Result<Handle> Resolve(const Handle &root, const std::vector<Segment> &path,
                       Provider &provider, bool draw_compatibility = true) {
  Result<Handle> result;
  if (path.empty() || path.size() > 64 || provider.Cancelled()) return result;
  const auto root_metadata = provider.Read(root);
  if (!root_metadata.valid) { result.failed = true; return result; }
  if (!Matches(path.front(), root_metadata)) return result;
  if (path.size() == 1) { result.node = root; return result; }
  std::vector<Handle> matches;
  int visited = 0;
  const auto walk = [&](const auto &self, const Handle &parent, size_t index,
                        int depth) -> void {
    if (result.failed || provider.Cancelled()) return;
    if (depth > 64) { result.failed = true; return; }
    const auto children = provider.Children(parent);
    if (!children) { result.failed = true; return; }
    std::map<std::wstring, int> unnamed_indices;
    for (const auto &child : *children) {
      if (provider.Cancelled()) return;
      if (++visited > 3000) { result.failed = true; return; }
      const auto metadata = provider.Read(child);
      if (!metadata.valid) { result.failed = true; return; }
      const auto type = Normalize(metadata.type);
      const bool unnamed = Normalize(metadata.name).empty();
      const int sibling_index = unnamed ? unnamed_indices[type]++ : -1;
      if (draw_compatibility && TitleWrapper(metadata, root_metadata)) {
        self(self, child, index, depth + 1);
        continue;
      }
      const auto &segment = path[index];
      if (!Matches(segment, metadata) ||
          (segment.index && *segment.index != sibling_index)) continue;
      if (index + 1 == path.size()) matches.push_back(child);
      else self(self, child, index + 1, depth + 1);
    }
  };
  walk(walk, root, 1, 1);
  if (provider.Cancelled() || result.failed) return result;
  if (matches.size() == 1) result.node = matches.front();
  else result.ambiguous = matches.size() > 1;
  return result;
}
} // namespace live_path
#endif
