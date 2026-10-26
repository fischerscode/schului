import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:schului/main.dart';

import 'lesson_test_support.dart';

import 'package:schului/lessons/draw_targets.dart';
import 'package:schului/src/accessibility_node.dart';

Map<String, Object> node(String id, String parent, String type, String name) =>
    {
      'id': id,
      'parentId': parent,
      'type': type,
      'name': name,
      'depth': 0,
      'left': 120.0,
      'top': 90.0,
      'width': 60.0,
      'height': 40.0,
    };
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final tree = [
    node('r', '', 'Fenster', 'Dokument 2 – LibreOffice Draw'),
    node('client', 'r', 'Element', 'Dokument 2 – LibreOffice Draw'),
    node('central', 'client', 'Element', ''),
    node('canvas', 'central', 'Element', ''),
    node('pages', 'central', 'Element', ''),
    node('sidebar-container', 'central', 'Element', ''),
    node('standard-container', 'client', 'Element', ''),
    node('drawing-container', 'client', 'Element', ''),
    node('toolbar', 'drawing-container', 'Symbolleiste', 'Zeichnung'),
    node('rectangle', 'toolbar', 'Schaltfläche', 'Rechteck'),
    node('ellipse', 'toolbar', 'Schaltfläche', 'Ellipse'),
    node('sidebar', 'sidebar-container', 'Element', 'Eigenschaften'),
    node('close', 'sidebar', 'Schaltfläche', 'Seitenleiste schließen'),
    node('other', 'client', 'Symbolleiste', 'Andere'),
    node('duplicate', 'other', 'Schaltfläche', 'Rechteck'),
  ];
  test('lesson paths resolve Draw tools despite mutable client title and duplicates', () {
    final nodes = tree.map((raw) => AccessibilityNode.fromMap(raw)).toList();
    for (final pair in [
      ('Rechteck', 'rectangle'),
      ('Ellipse/Kreis', 'ellipse'),
      ('Seitenleiste', 'sidebar-container'),
    ]) {
      expect(resolveAuthoredTarget(pair.$1, 1, nodes)?.id, pair.$2);
    }
  });
  testWidgets(
    'lesson overlay draws only the path target and removes ambiguous highlights',
    (tester) async {
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetDevicePixelRatio);
      var nodes = tree;
      var term = 'Rechteck';
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(bridge, (call) async {
            if (call.method == 'state') {
              return {
                'step': 1,
                'hoverTarget': term.isEmpty
                    ? null
                    : nodes.where((n) => n['id'] == 'ambiguous').isNotEmpty
                    ? null
                    : DrawTargets.rectangleTool.toJson(),
                'nodes': nodes,
                'hoverGeneration': 1,
                'hoverGeometryGeneration': 1,
                'hoverGeometry': nodes.firstWhere(
                  (node) => node['id'] == 'rectangle',
                ),
                'drawLeft': 100.0,
                'drawTop': 50.0,
              };
            }
            return null;
          });
      await tester.pumpWidget(const SchoolApp(role: 'overlay'));
      await tester.pump();
      expect(find.byType(Positioned), findsOneWidget);
      final box = tester.widget<Positioned>(find.byType(Positioned));
      expect(box.left, 16);
      expect(box.top, 36);
      term = '';
      await tester.pump(const Duration(milliseconds: 100));
      await tester.pump();
      expect(find.byType(Positioned), findsNothing);
      term = 'Rechteck';
      nodes = [
        ...tree,
        node('ambiguous', 'toolbar', 'Schaltfläche', 'Rechteck'),
      ];
      await tester.pump(const Duration(milliseconds: 500));
      await tester.pump();
      expect(find.byType(Positioned), findsNothing);
      await tester.pumpWidget(const SizedBox());
    },
  );
}
