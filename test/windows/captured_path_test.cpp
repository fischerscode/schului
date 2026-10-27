#include "../../windows/runner/captured_path.h"
#include <iostream>
#include <stdexcept>

struct Node { live_path::Metadata metadata; std::vector<int> children; };
struct Provider {
  std::vector<Node> nodes;
  bool cancelled = false;
  bool Cancelled() const { return cancelled; }
  live_path::Metadata Read(int id) { return nodes.at(id).metadata; }
  std::optional<std::vector<int>> Children(int id) { return nodes.at(id).children; }
  bool Equal(int left, int right) { return left == right; }
};
void Require(bool value, const char *message) {
  if (!value) throw std::runtime_error(message);
}
int main() {
  Provider provider{{
    {{L"Window", L"Editor"}, {1}},
    {{L"", L"Editor"}, {2, 3, 4, 5}},
    {{L"", L""}, {}},
    {{L"Button", L"Open"}, {}},
    {{L"", L""}, {6}},
    {{L"Toolbar", L""}, {}},
    {{L"Document", L"Exercise"}, {7}},
    {{L"Button", L"Save"}, {}},
  }};
  const std::vector<int> chain{0, 1, 4, 6, 7};
  auto path = live_path::Capture(chain, provider);
  Require(path && path->size() == 5, "Full raw hierarchy must be preserved");
  Require(!path->front().name, "Only the root caption must be omitted");
  Require((*path)[1].name == L"Editor", "Title-like ancestor must remain");
  Require((*path)[2].index == 1, "Index counts unnamed siblings of the same type");
  Require((*path)[3].name == L"Exercise", "Document names must remain");
  Require(live_path::Resolve(0, *path, provider).node == 7, "Path must round trip");
  provider.nodes[0].metadata.name = L"Changed caption";
  Require(live_path::Resolve(0, *path, provider).node == 7, "Root caption may change");
  provider.nodes[6].metadata.name = L"Another exercise";
  Require(!live_path::Resolve(0, *path, provider).node, "Document names are significant");
  provider.nodes[6].metadata.name = L"Exercise";
  provider.nodes.push_back({{L"Button", L"Save"}, {}});
  provider.nodes[6].children.push_back(8);
  Require(!live_path::Capture(chain, provider), "Duplicate named targets must be rejected");
  provider.nodes[6].children = {7};
  provider.nodes[2].metadata.valid = false;
  Require(!live_path::Capture(chain, provider), "Unreadable siblings must not shift indices");
  provider.nodes[2].metadata.valid = true;
  provider.cancelled = true;
  Require(!live_path::Capture(chain, provider), "Cancelled captures must be rejected");
  provider.cancelled = false;
  provider.nodes[1].metadata.name.clear();
  path = live_path::Capture(chain, provider);
  Require(path && (*path)[1].index == 0, "Unnamed ancestors must be indexed");
  Require(!live_path::Capture(std::vector<int>{}, provider), "Empty chains must be rejected");
  std::cout << "Captured path tests passed.\n";
}
