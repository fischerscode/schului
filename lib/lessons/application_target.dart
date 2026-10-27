import '../src/accessibility_node.dart';
import '../src/node_selector.dart';

/// An exact application path attached to an authored lesson link.
class ApplicationTarget {
  const ApplicationTarget(this.selector);
  final NodeSelector selector;
  Map<String, Object> toJson() => {'selector': selector.toJson()};
  factory ApplicationTarget.fromJson(Map raw) =>
      ApplicationTarget(NodeSelector.fromJson(raw['selector']));
  AccessibilityNode? resolve(
    List<AccessibilityNode> nodes, {
    bool requireVisible = true,
  }) {
    final node = selector.resolve(nodes).node;
    return node != null && (!requireVisible || node.canHighlight) ? node : null;
  }
}
