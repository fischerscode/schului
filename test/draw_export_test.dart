import 'dart:io';
import 'dart:convert';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import 'lesson_test_support.dart';

import 'package:schului/lessons/draw_targets.dart';

import 'package:schului/src/accessibility_node.dart';
import 'package:schului/src/node_selector.dart';

// Preserve the real exported types, names, hierarchy and bounds. IDs are local
// to this fixture; the lesson must continue to work with new runtime IDs.
List<AccessibilityNode> readExport() {
  final nodes = <AccessibilityNode>[];
  final parents = <int, String>{};
  final linePattern = RegExp(
    r'^( *)\[([^\]]*)\] (.*?)  (?:\(x=(-?\d+), y=(-?\d+), w=(\d+), h=(\d+)\)|\[nicht sichtbar\])$',
  );
  for (final line in File(
    'test/fixtures/draw_rectangle_tree.txt',
  ).readAsLinesSync()) {
    final match = linePattern.firstMatch(line);
    if (match == null) continue;
    final depth = match.group(1)!.length ~/ 2;
    final id = 'fixture-${nodes.length}';
    final name = match.group(3)!.trim();
    nodes.add(
      AccessibilityNode(
        id: id,
        parentId: parents[depth - 1] ?? '',
        type: match.group(2)!,
        name: name == '<ohne Namen>' ? '' : name,
        depth: depth,
        bounds: match.group(4) == null
            ? Rect.zero
            : Rect.fromLTWH(
                double.parse(match.group(4)!),
                double.parse(match.group(5)!),
                double.parse(match.group(6)!),
                double.parse(match.group(7)!),
              ),
        offscreen: match.group(4) == null,
      ),
    );
    parents[depth] = id;
    parents.removeWhere((level, _) => level > depth);
  }
  return nodes;
}

void main() {
  test(
    'triangle highlights basic shapes and object highlights drawn rectangle',
    () {
      final nodes = readExport();
      final triangle = DrawTargets.triangleTool.resolve(nodes);
      final rectangle = DrawTargets.rectangleObject.resolve(nodes);
      expect(triangle?.name, 'Grundformen');
      expect(triangle?.type, 'Trennschaltfläche');
      expect(rectangle?.name, 'Rectangle');
      expect(rectangle?.bounds, const Rect.fromLTWH(1349, 533, 322, 311));
      expect(resolveAuthoredTarget('Dreieck', 5, nodes)?.id, triangle?.id);
      expect(resolveAuthoredTarget('Objekt', 2, nodes)?.id, rectangle?.id);
      expect(triangle?.id, isNot(rectangle?.id));
    },
  );
  test('supplied sidebar JSON paths select the same nodes as lesson hover', () {
    final exported = readExport();
    final live = [
      for (final node in exported)
        AccessibilityNode.fromMap({
          ...node.toMap(),
          'type': node.type == 'Element' ? '' : node.type,
          'name':
              node.name == exported.first.name && node.id != exported.first.id
              ? ''
              : node.name,
        }),
    ];
    final supplied = jsonDecode(
      File('test/fixtures/draw_sidebar_paths.json').readAsStringSync(),
    ) as Map;
    for (final pair in {
      'sidebar': 'Seitenleiste',
      'sidebarFillColor': 'Füllfarbe',
      'width': 'Breite',
      'height': 'Höhe',
    }.entries) {
      final expected = NodeSelector.fromJson(supplied[pair.key])
          .resolve(live, allowFallback: false);
      expect(expected.node, isNotNull, reason: pair.value);
      expect(expected.description, 'Pfad gefunden');
      expect(resolveAuthoredTarget(pair.value, 2, live)?.id, expected.node!.id);
    }
    expect(
      resolveAuthoredTarget('Seitenleiste', 2, live)?.bounds,
      const Rect.fromLTWH(2211, 159, 656, 1590),
    );
    expect(resolveAuthoredTarget('Füllfarbe', 2, live)?.type, 'Symbolleiste');
    final sidebarId = resolveAuthoredTarget('Seitenleiste', 2, live)!.id;
    expect(
      resolveAuthoredTarget('Seitenleiste', 2, [
        for (final node in live)
          if (node.id != sidebarId) node,
      ]),
      isNull,
    );
  });

  test(
    'all lesson targets resolve exact paths with actual empty provider types',
    () {
      final exported = readExport();
      for (final unnamedClient in [false, true]) {
        final nodes = [
          for (final node in exported)
            AccessibilityNode.fromMap({
              ...node.toMap(),
              'type': node.type == 'Element' ? '' : node.type,
              'name':
                  unnamedClient &&
                      node.name == exported.first.name &&
                      node.id != exported.first.id
                  ? ''
                  : node.name,
            }),
        ];
        for (final term in [
          'Arbeitsbereich',
          'linken Symbolleiste',
          'oberen Symbolleiste',
          'Rechteck',
          'Ellipse/Kreis',
          'Dreieck',
          'Linie',
          'Speichern',
          'Rückgängig',
          'Anordnen',
          'Seitenleiste',
          'Füllfarbe',
          'Breite',
          'Höhe',
          'Objekt',
        ]) {
          final expected = resolveAuthoredTarget(term, 1, exported);
          expect(expected, isNotNull, reason: term);
          expect(
            resolveAuthoredTarget(term, 1, nodes)?.id,
            expected?.id,
            reason: '$term / unnamedClient=$unnamedClient',
          );
        }
        expect(
          resolveAuthoredTarget('Objekt', 2, nodes)?.name.trim(),
          'Rectangle',
        );
      }
    },
  );

  test('missing control paths never fall back to matching names elsewhere', () {
    final nodes = readExport();
    final sidebar = resolveAuthoredTarget('Seitenleiste', 2, nodes)!;
    for (final term in ['Füllfarbe', 'Breite', 'Höhe']) {
      final target = resolveAuthoredTarget(term, 2, nodes)!;
      final decoy = AccessibilityNode(
        id: 'decoy',
        parentId: sidebar.id,
        name: target.name,
        type: target.type,
        depth: sidebar.depth + 1,
        bounds: target.bounds,
      );
      expect(resolveAuthoredTarget(term, 2, [...nodes, decoy])?.id, target.id);
      expect(
        resolveAuthoredTarget(term, 2, [
          for (final n in nodes)
            if (n.id != target.id) n,
          decoy,
        ]),
        isNull,
      );
    }
  });

  test(
    'actual Draw export resolves object, size fields and sidebar fill color',
    () {
      final nodes = readExport();
      expect(nodes.length, greaterThan(200));
      final rectangle = resolveAuthoredTarget('Objekt', 2, nodes);
      expect(rectangle?.name, 'Rectangle');
      expect(rectangle?.bounds, const Rect.fromLTWH(1349, 533, 322, 311));
      expect(resolveAuthoredTarget('Objekt', 1, nodes)?.id, rectangle?.id);
      expect(resolveAuthoredTarget('Rechteck', 1, nodes)?.type, 'Schaltfläche');
      expect(resolveAuthoredTarget('Rechteck', 5, nodes)?.type, 'Schaltfläche');
      for (final term in ['Breite', 'Höhe']) {
        final field = resolveAuthoredTarget(term, 2, nodes);
        expect(field?.type, 'Netz');
        expect(field?.name, term);
        expect(field?.bounds.left, 2366);
      }
      final fill = resolveAuthoredTarget('Füllfarbe', 2, nodes);
      expect(fill?.type, 'Symbolleiste');
      expect(fill?.bounds, const Rect.fromLTWH(2364, 354, 191, 43));
      final triangle = resolveAuthoredTarget('Dreieck', 5, nodes);
      expect(triangle?.name, 'Grundformen');
      expect(triangle?.type, 'Trennschaltfläche');
      expect(triangle?.bounds, const Rect.fromLTWH(735, 726, 79, 59));
    },
  );

  test('multiple or hidden drawn objects do not select a tool or the page', () {
    final nodes = readExport();
    final rectangle = nodes.singleWhere((n) => n.name == 'Rectangle');
    final duplicate = AccessibilityNode(
      id: 'second-rectangle',
      parentId: rectangle.parentId,
      name: 'Rectangle',
      type: rectangle.type,
      depth: rectangle.depth,
      bounds: rectangle.bounds,
    );
    expect(resolveAuthoredTarget('Objekt', 2, [...nodes, duplicate]), isNull);
    expect(resolveAuthoredTarget('Objekt', 1, [...nodes, duplicate]), isNull);
    final hidden = AccessibilityNode(
      id: rectangle.id,
      parentId: rectangle.parentId,
      name: rectangle.name,
      type: rectangle.type,
      depth: rectangle.depth,
      bounds: rectangle.bounds,
      offscreen: true,
    );
    final hiddenTree = [
      for (final n in nodes) n.id == rectangle.id ? hidden : n,
    ];
    expect(resolveAuthoredTarget('Objekt', 2, hiddenTree), isNull);
    expect(resolveAuthoredTarget('Objekt', 1, hiddenTree), isNull);
  });
}
