#ifndef RUNNER_CAPTURED_PATH_H_
#define RUNNER_CAPTURED_PATH_H_
#include "live_node_path.h"

namespace live_path {
// The caller supplies the raw root-to-target chain. Keep the same title-wrapper
// and unnamed-sibling rules as Resolve, then verify unique identity before use.
template <typename Handle, typename Provider>
std::optional<std::vector<Segment>> Capture(const std::vector<Handle> &chain,
                                           Provider &provider, bool draw_compatibility = true) {
  if (chain.empty() || chain.size() > 64) return std::nullopt;
  const auto root = provider.Read(chain.front());
  if (!root.valid) return std::nullopt;
  std::vector<Segment> path;
  for (size_t i = 0; i < chain.size(); ++i) {
    if (provider.Cancelled()) return std::nullopt;
    const auto value = provider.Read(chain[i]);
    if (!value.valid) return std::nullopt;
    if (draw_compatibility && i > 0 && i + 1 < chain.size() && TitleWrapper(value, root)) continue;
    Segment segment{value.type, value.name, std::nullopt};
    if (i == 0 || (draw_compatibility && Normalize(value.type) == L"dokument" && i + 1 < chain.size()))
      segment.name.reset();
    if (i > 0 && Normalize(value.name).empty()) {
      const auto siblings = provider.Children(chain[i - 1]);
      if (!siblings) return std::nullopt;
      int index = 0;
      bool found = false;
      for (const auto &sibling : *siblings) {
        if (provider.Cancelled()) return std::nullopt;
        const auto metadata = provider.Read(sibling);
        if (!metadata.valid) return std::nullopt;
        if (!Normalize(metadata.name).empty() ||
            Normalize(metadata.type) != Normalize(value.type)) continue;
        if (provider.Equal(sibling, chain[i])) { found = true; break; }
        ++index;
      }
      if (!found) return std::nullopt;
      segment.index = index;
    }
    path.push_back(std::move(segment));
  }
  const auto resolved = Resolve(chain.front(), path, provider, draw_compatibility);
  if (!resolved.node || resolved.failed || resolved.ambiguous ||
      provider.Cancelled() || !provider.Equal(*resolved.node, chain.back()))
    return std::nullopt;
  return path;
}
} // namespace live_path
#endif
