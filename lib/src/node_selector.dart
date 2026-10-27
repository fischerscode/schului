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

// LibreOffice repeats the mutable document title in its client wrapper.
bool _semantic(
  AccessibilityNode node,
  AccessibilityNode root,
  AccessibilityNode target,
) =>
    node == root ||
    node == target ||
    (node.name.trim().isNotEmpty && !_titleWrapper(node, root));

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

bool _titleWrapper(AccessibilityNode node, AccessibilityNode root) =>
    (_norm(node.type) == 'element' || _norm(node.type).isEmpty) &&
    node.name.trim().isNotEmpty &&
    _norm(node.name) == _norm(root.name);

/// Named segments use semantic identity; unnamed segments use sibling indices.
class NodeSelector {
  const NodeSelector(this.path, {this.legacyDraw = true});
  final List<PathSegment> path;
  final bool legacyDraw;
  factory NodeSelector.capture(
    AccessibilityNode node,
    List<AccessibilityNode> nodes, {
    bool legacyDraw = true,
  }) {
    final chain = _chain(node, {for (final n in nodes) n.id: n});
    return NodeSelector([
      for (final n in chain)
        if (!legacyDraw ||
            n == chain.first ||
            n == node ||
            !_titleWrapper(n, chain.first))
          PathSegment(
            n.type,
            (n == chain.first && (!legacyDraw || n != node)) ||
                    (legacyDraw && _norm(n.type) == 'dokument' && n != node)
                ? null
                : n.name,
            index: n.name.trim().isEmpty && (n != chain.first || n == node)
                ? _unnamedIndex(n, nodes)
                : null,
          ),
    ], legacyDraw: legacyDraw);
  }
  Map<String, Object> toJson() => {
    'version': 2,
    if (!legacyDraw) 'mode': 'exact',
    'path': path.map((s) => s.toJson()).toList(),
  };
  factory NodeSelector.fromJson(Object? raw) {
    if (raw is! Map ||
        (raw['version'] != 1 && raw['version'] != 2) ||
        raw['path'] is! List ||
        (raw['path'] as List).isEmpty ||
        (raw['path'] as List).length > 64) {
      throw const FormatException(
        'Erwartet: version 1 oder 2 und ein nicht leerer path.',
      );
    }
    if (raw.containsKey('mode') && raw['mode'] != 'exact') {
      throw const FormatException('Unbekannter Pfadmodus.');
    }
    final legacyDraw = raw['mode'] != 'exact';
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
          legacyDraw &&
                  _norm(entry['type'] as String) == 'dokument' &&
                  segments.length < (raw['path'] as List).length - 1
              ? null
              : entry['name'] as String?,
          index: entry['index'] as int?,
        ),
      );
    }
    return NodeSelector(segments, legacyDraw: legacyDraw);
  }

  NodeResolution resolve(
    List<AccessibilityNode> nodes, {
    bool allowFallback = true,
  }) {
    final byId = {for (final n in nodes) n.id: n};
    final candidates = nodes.where(path.last.matches).toList();
    final exact = <AccessibilityNode>[];
    for (final node in candidates) {
      final full = _chain(node, byId);
      final indexed = path.any((segment) => segment.index != null);
      final chain = full
          .where(
            (n) =>
                !legacyDraw ||
                (indexed
                    ? n == full.first ||
                          n == node ||
                          !_titleWrapper(n, full.first)
                    : _semantic(n, full.first, node)),
          )
          .toList();
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
    if (!allowFallback || !legacyDraw) {
      return const NodeResolution(
        null,
        'Pfad nicht vorhanden – keine Markierung.',
        0,
      );
    }

    // Keep the target type and name exact; relax only the ancestor context.
    // This avoids silently highlighting a different tool with a similar label.
    final fallbackPath = [
      for (var i = 0; i < path.length; i++)
        if (i == 0 || i == path.length - 1 || path[i].index == null) path[i],
    ];
    final ranked = <({AccessibilityNode node, double score})>[];
    for (final node in candidates) {
      if (fallbackPath.length == 1) continue;
      final ancestors = _chain(node, byId)..removeLast();
      var cursor = ancestors.length - 1;
      double matched = 0, total = 0;
      for (var i = fallbackPath.length - 2; i >= 0; i--) {
        final weight = (i + 1).toDouble();
        total += weight;
        for (var j = cursor; j >= 0; j--) {
          if (fallbackPath[i].matches(ancestors[j])) {
            matched += weight;
            cursor = j - 1;
            break;
          }
        }
      }
      ranked.add((node: node, score: 0.6 + 0.4 * matched / total));
    }
    ranked.sort((a, b) => b.score.compareTo(a.score));
    if (ranked.isEmpty) {
      return const NodeResolution(
        null,
        'Kein passender Knoten – keine Markierung.',
        0,
      );
    }
    final best = ranked.first;
    if (best.score < 0.7) {
      return NodeResolution(
        null,
        'Ersatzsuche: zu wenig passender Pfadkontext – keine Markierung.',
        best.score,
      );
    }
    if (ranked.length > 1 && best.score - ranked[1].score < 0.1) {
      return NodeResolution(
        null,
        'Ersatzsuche mehrdeutig – keine Markierung.',
        best.score,
        isAmbiguous: true,
      );
    }
    return NodeResolution(
      best.node,
      'Ersatzsuche: Pfad teilweise passend (${(best.score * 100).round()} % Bewertung)',
      best.score,
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

  /// Heuristic compatibility score, not a statistical probability.
  final double score;
  final bool isAmbiguous;
}
