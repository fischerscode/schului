import 'dart:convert';
import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import 'lesson_test_support.dart';

import 'package:schului/lessons/draw_targets.dart';
import 'package:schului/src/accessibility_node.dart';
import 'package:schului/src/node_selector.dart';

List<AccessibilityNode> drawTree(String title, String prefix) => [
  AccessibilityNode(
    id: '${prefix}root',
    parentId: '',
    name: '$title – LibreOffice Draw',
    type: 'Fenster',
    depth: 0,
    bounds: const Rect.fromLTWH(0, 0, 1000, 800),
  ),
  for (var i = 0; i < 4; i++)
    AccessibilityNode(
      id: '${prefix}container$i',
      parentId: i == 0 ? '${prefix}root' : '${prefix}container${i - 1}',
      name: '',
      type: '',
      depth: i + 1,
      bounds: const Rect.fromLTWH(0, 0, 800, 700),
    ),
  AccessibilityNode(
    id: '${prefix}document',
    parentId: '${prefix}container3',
    name: '$title - LibreOffice-Präsentation',
    type: 'Dokument',
    depth: 5,
    bounds: const Rect.fromLTWH(0, 0, 800, 700),
  ),
  AccessibilityNode(
    id: '${prefix}rectangle',
    parentId: '${prefix}document',
    name: 'Rectangle ',
    type: '',
    depth: 6,
    bounds: const Rect.fromLTWH(100, 120, 200, 150),
  ),
];

void main() {
  test(
    'supplied JSON loads empty types and resolves after saving with new IDs',
    () {
      final selector = NodeSelector.fromJson(
        jsonDecode(
          File('test/fixtures/draw_rectangle_path.json').readAsStringSync(),
        ),
      );
      final original = drawTree('Unbenannt 1', 'old-');
      final saved = drawTree('Meine_Zeichnung', 'new-');
      expect(selector.resolve(original).node?.id, 'old-rectangle');
      expect(selector.path[5].name, isNull);
      expect(selector.resolve(saved).node?.id, 'new-rectangle');
      expect(selector.resolve(saved).description, 'Pfad gefunden');
      expect(DrawTargets.rectangleObject.resolve(saved)?.id, 'new-rectangle');
      expect(resolveAuthoredTarget('Objekt', 2, saved)?.id, 'new-rectangle');
      expect(resolveAuthoredTarget('Objekt', 1, saved)?.id, 'new-rectangle');
      final captured = NodeSelector.capture(original.last, original);
      expect(captured.path[5].name, isNull);
      expect(
        NodeSelector.fromJson(captured.toJson()).resolve(saved).node?.id,
        'new-rectangle',
      );
    },
  );

  test(
    'empty type is exact and duplicate rectangle paths remain ambiguous',
    () {
      final nodes = drawTree('Meine_Zeichnung', 'new-');
      expect(const PathSegment('', 'Rectangle').matches(nodes.last), isTrue);
      final other = AccessibilityNode(
        id: 'other',
        parentId: nodes.last.parentId,
        name: 'Rectangle',
        type: 'Element',
        depth: 6,
        bounds: nodes.last.bounds,
      );
      expect(const PathSegment('', 'Rectangle').matches(other), isFalse);
      final duplicate = AccessibilityNode(
        id: 'duplicate',
        parentId: nodes.last.parentId,
        name: 'Rectangle',
        type: '',
        depth: 6,
        bounds: nodes.last.bounds,
      );
      expect(
        DrawTargets.rectangleObject.resolve([...nodes, duplicate]),
        isNull,
      );
      expect(resolveAuthoredTarget('Objekt', 2, [...nodes, duplicate]), isNull);
    },
  );
}
