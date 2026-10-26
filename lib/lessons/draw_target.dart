import '../src/accessibility_node.dart';
import '../src/node_selector.dart';

/// A reusable Draw path attached directly to an authored lesson link.
class DrawTarget {
  const DrawTarget(this.selector, {this.includesUnnamedClient = false});
  final NodeSelector selector;
  final bool includesUnnamedClient;

  Map<String, Object> toJson() => {
    'selector': selector.toJson(),
    'includesUnnamedClient': includesUnnamedClient,
  };

  factory DrawTarget.fromJson(Map raw) => DrawTarget(
    NodeSelector.fromJson(raw['selector']),
    includesUnnamedClient: raw['includesUnnamedClient'] == true,
  );

  AccessibilityNode? resolve(
    List<AccessibilityNode> nodes, {
    bool requireVisible = true,
  }) {
    final hasNamedClient = nodes.any(
      (child) =>
          (child.type.isEmpty || child.type == 'Element') &&
          child.name.trim().isNotEmpty &&
          nodes.any(
            (parent) =>
                parent.id == child.parentId &&
                parent.type == 'Fenster' &&
                parent.name.trim() == child.name.trim(),
          ),
    );
    final paths = [
      selector.path,
      if (includesUnnamedClient && hasNamedClient)
        [selector.path.first, ...selector.path.skip(2)]
      else if (!includesUnnamedClient && !hasNamedClient)
        [
          selector.path.first,
          const PathSegment('', '', index: 0),
          ...selector.path.skip(1),
        ],
    ];
    // Historical text exports replaced empty provider types with Element.
    // Each variant is still an exact path, never a type wildcard or name search.
    for (final path in paths) {
      final resolutions = [
        NodeSelector(path).resolve(nodes, allowFallback: false),
        NodeSelector([
          for (final segment in path)
            PathSegment(
              segment.type.isEmpty ? 'Element' : segment.type,
              segment.name,
              index: segment.index,
            ),
        ]).resolve(nodes, allowFallback: false),
      ];
      if (resolutions.any((resolution) => resolution.isAmbiguous)) return null;
      final found = {
        for (final resolution in resolutions)
          if (resolution.node != null) resolution.node!.id: resolution.node!,
      };
      if (found.isEmpty) continue;
      if (found.length != 1) return null;
      // The supplied path is authoritative. Try the older client layout only
      // when it has no match, never against another shortened unnamed path.
      final node = found.values.single;
      return !requireVisible || node.canHighlight ? node : null;
    }
    return null;
  }
}
