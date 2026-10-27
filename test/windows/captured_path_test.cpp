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
    {{L"Fenster", L"Unbenannt 1 - LibreOffice Draw"}, {1}},
    {{L"", L"Unbenannt 1 - LibreOffice Draw"}, {2, 3, 4, 5}},
    {{L"", L""}, {}},
    {{L"Schaltfläche", L"Anderes Werkzeug"}, {}},
    {{L"", L""}, {6}},
    {{L"Symbolleiste", L""}, {}},
    {{L"Dokument", L"Unbenannt 1 - LibreOffice-Präsentation"}, {7}},
    {{L"", L"Rectangle"}, {}},
  }};
  const std::vector<int> chain{0, 1, 4, 6, 7};
  auto path = live_path::Capture(chain, provider);
  Require(path.has_value(), "Capture must resolve uniquely");
  Require(path->size() == 4, "Mutable client title wrapper must be omitted");
  Require(!path->front().name, "Root title must be omitted");
  Require((*path)[1].index == 1, "Index must count only unnamed siblings of the same type");
  Require(!(*path)[2].name, "Ancestor document title must be omitted");
  Require(live_path::Resolve(0, *path, provider).node == 7, "Captured path must round-trip");
  provider.nodes[0].metadata.name = L"Gespeichert - LibreOffice Draw";
  provider.nodes[1].metadata.name = provider.nodes[0].metadata.name;
  provider.nodes[6].metadata.name = L"Gespeichert - LibreOffice-Präsentation";
  Require(live_path::Resolve(0, *path, provider).node == 7, "Renaming must preserve identity");
  provider.nodes.push_back({{L"", L"Rectangle"}, {}});
  provider.nodes[6].children.push_back(8);
  Require(!live_path::Capture(chain, provider), "Ambiguous named targets must not be captured");
  provider.nodes[6].children = {7};
  provider.nodes[2].metadata.valid = false;
  Require(!live_path::Capture(chain, provider), "Unreadable siblings must not shift indices");
  provider.nodes[2].metadata.valid = true;
  provider.cancelled = true;
  Require(!live_path::Capture(chain, provider), "Cancelled capture must not produce a target");
  provider.cancelled = false;
  // In the other known layout, an unnamed client remains part of the path.
  provider.nodes[1].metadata.name.clear();
  path = live_path::Capture(chain, provider);
  Require(path && path->size() == 5 && (*path)[1].index == 0,
      "Unnamed client must remain explicitly indexed");
  Require(!live_path::Capture(std::vector<int>{}, provider), "Empty chain must be rejected");
  std::cout << "Captured path tests passed.\n";
}
