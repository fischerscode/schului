#ifndef RUNNER_CAPTURED_PATH_H_
#define RUNNER_CAPTURED_PATH_H_
#include "live_node_path.h"

namespace live_path {
// Capture the full raw hierarchy and verify unique identity before use.
template <typename Handle, typename Provider>
std::optional<std::vector<Segment>> Capture(const std::vector<Handle> &chain,
                                           Provider &provider) {
  if (chain.empty() || chain.size() > 64) return std::nullopt;
  const auto root = provider.Read(chain.front());
  if (!root.valid) return std::nullopt;
  std::vector<Segment> path;
  for (size_t i = 0; i < chain.size(); ++i) {
    if (provider.Cancelled()) return std::nullopt;
    const auto value = provider.Read(chain[i]);
    if (!value.valid) return std::nullopt;
    Segment segment{value.type, value.name, std::nullopt};
    if (i == 0)
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
  const auto resolved = Resolve(chain.front(), path, provider);
  if (!resolved.node || resolved.failed || resolved.ambiguous ||
      provider.Cancelled() || !provider.Equal(*resolved.node, chain.back()))
    return std::nullopt;
  return path;
}
} // namespace live_path
#endif
