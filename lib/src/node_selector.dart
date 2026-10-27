import 'accessibility_node.dart';

String _norm(String value) =>
    value.trim().replaceAll(RegExp(r'\s+'), ' ').toLowerCase();

class PathSegment {
  const PathSegment(this.type, this.name, {this.index});
  final String type;
  final String? name;

  /// Zero-based position among unnamed siblings of the same element type.
  final int? index;
  bool matches(AccessibilityNode node) =>
      _norm(type) == _norm(node.type) &&
      (name == null || _norm(name!) == _norm(node.name));
  Map<String, Object?> toJson() => {
    'type': type,
    if (name != null) 'name': name,
    if (index != null) 'index': index,
  };
}

List<AccessibilityNode> _chain(
  AccessibilityNode node,
  Map<String, AccessibilityNode> byId,
) {
  final result = <AccessibilityNode>[];
  final visited = <String>{};
  AccessibilityNode? current = node;
  while (current != null && visited.add(current.id)) {
    result.add(current);
    current = byId[current.parentId];
  }
  return result.reversed.toList();
}

int _unnamedIndex(AccessibilityNode node, List<AccessibilityNode> nodes) =>
    nodes
        .where(
          (sibling) =>
              sibling.parentId == node.parentId &&
              sibling.name.trim().isEmpty &&
              _norm(sibling.type) == _norm(node.type),
        )
        .toList()
        .indexWhere((sibling) => sibling.id == node.id);

/// Named segments use semantic identity; unnamed segments use sibling indices.
class NodeSelector {
  const NodeSelector(this.path);
  final List<PathSegment> path;
  factory NodeSelector.capture(
    AccessibilityNode node,
    List<AccessibilityNode> nodes,
  ) {
    final chain = _chain(node, {for (final n in nodes) n.id: n});
    return NodeSelector([
      for (final n in chain)
        PathSegment(
          n.type,
          n == chain.first ? null : n.name,
          index: n != chain.first && n.name.trim().isEmpty
              ? _unnamedIndex(n, nodes)
              : null,
        ),
    ]);
  }
  Map<String, Object> toJson() => {
    'version': 2,
    'mode': 'exact',
    'path': path.map((s) => s.toJson()).toList(),
  };
  factory NodeSelector.fromJson(Object? raw) {
    if (raw is! Map ||
        raw['version'] != 2 ||
        raw['path'] is! List ||
        (raw['path'] as List).isEmpty ||
        (raw['path'] as List).length > 64) {
      throw const FormatException(
        'Erwartet: version 2 und ein nicht leerer path.',
      );
    }
    if (raw['mode'] != 'exact') {
      throw const FormatException('Unbekannter Pfadmodus.');
    }
    final segments = <PathSegment>[];
    for (final entry in raw['path'] as List) {
      if (entry is! Map ||
          entry['type'] is! String ||
          (entry.containsKey('name') && entry['name'] is! String) ||
          (entry.containsKey('index') &&
              (entry['index'] is! int ||
                  (entry['index'] as int) < 0 ||
                  entry['name'] is! String ||
                  (entry['name'] as String).trim().isNotEmpty))) {
        throw const FormatException(
          'type und optional name als Text; index nur für namenlose Knoten als ganze Zahl ab 0.',
        );
      }
      segments.add(
        PathSegment(
          entry['type'] as String,
          entry['name'] as String?,
          index: entry['index'] as int?,
        ),
      );
    }
    return NodeSelector(segments);
  }

  NodeResolution resolve(List<AccessibilityNode> nodes) {
    final byId = {for (final n in nodes) n.id: n};
    final candidates = nodes.where(path.last.matches).toList();
    final exact = <AccessibilityNode>[];
    for (final node in candidates) {
      final chain = _chain(node, byId);
      if (chain.length != path.length) continue;
      if (List.generate(
        path.length,
        (i) =>
            path[i].matches(chain[i]) &&
            (path[i].index == null ||
                path[i].index == _unnamedIndex(chain[i], nodes)),
      ).every((match) => match)) {
        exact.add(node);
      }
    }
    if (exact.length == 1) {
      return NodeResolution(exact.single, 'Pfad gefunden', 1);
    }
    if (exact.length > 1) {
      return NodeResolution(
        null,
        'Mehrdeutiger Pfad: ${exact.length} Treffer – keine Markierung.',
        0,
        isAmbiguous: true,
      );
    }
    return const NodeResolution(
      null,
      'Pfad nicht vorhanden – keine Markierung.',
      0,
    );
  }
}

class NodeResolution {
  const NodeResolution(
    this.node,
    this.description,
    this.score, {
    this.isAmbiguous = false,
  });
  final AccessibilityNode? node;
  final String description;

  /// One for a unique exact match, zero otherwise.
  final double score;
  final bool isAmbiguous;
}
