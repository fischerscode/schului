import 'package:flutter/widgets.dart';

class AccessibilityNode {
  const AccessibilityNode({
    required this.id,
    required this.parentId,
    required this.name,
    required this.type,
    required this.depth,
    required this.bounds,
    this.offscreen = false,
  });
  factory AccessibilityNode.fromMap(Map<String, dynamic> value) =>
      AccessibilityNode(
        id: value['id'] as String,
        parentId: value['parentId'] as String? ?? '',
        name: value['name'] as String? ?? '',
        type: value['type'] as String? ?? '',
        depth: value['depth'] as int? ?? 0,
        offscreen: value['offscreen'] == true,
        bounds: Rect.fromLTWH(
          (value['left'] as num? ?? 0).toDouble(),
          (value['top'] as num? ?? 0).toDouble(),
          (value['width'] as num? ?? 0).toDouble(),
          (value['height'] as num? ?? 0).toDouble(),
        ),
      );
  Map<String, dynamic> toMap() => {
    'id': id,
    'parentId': parentId,
    'name': name,
    'type': type,
    'depth': depth,
    'offscreen': offscreen,
    'left': bounds.left,
    'top': bounds.top,
    'width': bounds.width,
    'height': bounds.height,
  };
  final String id, parentId, name, type;
  final int depth;
  final Rect bounds;
  final bool offscreen;
  String get label => name.isEmpty ? '<ohne Namen>' : name;
  bool get canHighlight => !offscreen && bounds.width > 0 && bounds.height > 0;
}
