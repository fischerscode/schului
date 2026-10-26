#include "../../windows/runner/live_node_path.h"
#include <cassert>
#include <iostream>

struct Node {
  live_path::Metadata metadata;
  std::vector<int> children;
};
struct Provider {
  std::vector<Node> nodes;
  bool cancelled = false;
  bool Cancelled() const { return cancelled; }
  live_path::Metadata Read(int id) { return nodes.at(id).metadata; }
  std::optional<std::vector<int>> Children(int id) { return nodes.at(id).children; }
};
int main() {
  Provider provider{{
    {{L"Fenster", L"Unbenannt 1 - LibreOffice Draw"}, {1}},
    {{L"", L""}, {2}},
    {{L"", L""}, {3}},
    {{L"", L""}, {4}},
    {{L"", L""}, {5}},
    {{L"Dokument", L"Unbenannt 1 - LibreOffice-Präsentation"}, {}},
    {{L"", L"Rectangle "}, {}},
    {{L"", L"Rectangle"}, {}},
  }};
  const std::vector<live_path::Segment> path{
    {L"Fenster", std::nullopt, std::nullopt},
    {L"", L"", 0}, {L"", L"", 0}, {L"", L"", 0}, {L"", L"", 0},
    {L"Dokument", std::nullopt, std::nullopt},
    {L"", L"Rectangle ", std::nullopt},
  };
  // The next lookup discovers a newly drawn object without a full-tree scan
  // or changing the hovered path. The same provider reads its live children.
  assert(!live_path::Resolve(0, path, provider).node);
  provider.nodes[5].children = {6};
  assert(live_path::Resolve(0, path, provider).node == 6);
  provider.nodes[0].metadata.name = L"Meine_Zeichnung - LibreOffice Draw";
  provider.nodes[5].metadata.name = L"Meine_Zeichnung - LibreOffice-Präsentation";
  assert(live_path::Resolve(0, path, provider).node == 6);
  provider.nodes[5].children.push_back(7);
  assert(live_path::Resolve(0, path, provider).ambiguous);
  provider.nodes[5].children = {6};
  provider.nodes[6].metadata.type = L"Element";
  assert(!live_path::Resolve(0, path, provider).node);
  provider.nodes[6].metadata.type = L"";
  provider.nodes[7].metadata.valid = false;
  provider.nodes[5].children.push_back(7);
  assert(live_path::Resolve(0, path, provider).failed);
  provider.nodes[5].children = {6};
  provider.cancelled = true;
  assert(!live_path::Resolve(0, path, provider).node);
  provider.cancelled = false;
  // Skip only the mutable title wrapper, preserving unnamed sibling indices.
  provider.nodes.push_back({{L"", provider.nodes[0].metadata.name}, {1}});
  provider.nodes[0].children = {8};
  assert(live_path::Resolve(0, path, provider).node == 6);
  std::cout << "Live path lookup tests passed.\n";
}
