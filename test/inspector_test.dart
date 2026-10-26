import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:schului/main.dart';
import 'package:schului/src/inspector_view.dart';

Map<String, dynamic> node(
  String id,
  String parent,
  String name,
  int depth, {
  bool offscreen = false,
}) => {
  'id': id,
  'parentId': parent,
  'name': name,
  'type': 'Schaltfläche',
  'depth': depth,
  'left': 120.0,
  'top': 90.0,
  'width': 60.0,
  'height': 40.0,
  'offscreen': offscreen,
};

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final rawNodes = [
    node('root', '', 'Draw', 0),
    node('toolbar', 'root', 'Zeichnung', 1),
    node('rectangle-1', 'toolbar', 'Rechteck', 2),
    node('rectangle-2', 'root', 'Rechteck', 1),
  ];

  test('tree collapse and search retain the correct ancestor chain', () {
    final nodes = rawNodes.map(AccessibilityNode.fromMap).toList();
    expect(visibleTreeNodes(nodes, {}, '').map((n) => n.id), ['root']);
    expect(visibleTreeNodes(nodes, {'root'}, '').map((n) => n.id), [
      'root',
      'toolbar',
      'rectangle-2',
    ]);
    expect(visibleTreeNodes(nodes, {}, 'Rechteck').map((n) => n.id), [
      'root',
      'toolbar',
      'rectangle-1',
      'rectangle-2',
    ]);
  });

  testWidgets(
    'selecting duplicate names sends the actual node ID and clearing removes it',
    (tester) async {
      tester.view.physicalSize = const Size(420, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      var snapshot = [
        ...rawNodes,
        node('unnamed-1', 'root', '', 1),
        node('unnamed-2', 'root', '', 1),
      ];
      final calls = <MethodCall>[];
      var selected = '';
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(bridge, (call) async {
            calls.add(call);
            if (call.method == 'selectNode') {
              selected = call.arguments as String;
            }
            if (call.method == 'state') {
              return {
                'nodes': snapshot,
                'connected': true,
                'selectedNodeId': selected,
                'selection': selected.isEmpty
                    ? null
                    : snapshot.where((n) => n['id'] == selected).firstOrNull,
              };
            }
            return null;
          });
      await tester.pumpWidget(const SchoolApp(role: 'inspector'));
      await tester.pump();
      expect(
        calls.any((c) => c.method == 'inspector' && c.arguments == true),
        isTrue,
      );
      expect(find.text('Noch kein Knoten ausgewählt.'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('node-unnamed-1')));
      await tester.pump();
      expect(selected, 'unnamed-1');
      await tester.pump(const Duration(milliseconds: 500));
      await tester.pump();
      expect(selected, 'unnamed-1');
      expect(find.text('Noch kein Knoten ausgewählt.'), findsNothing);
      expect(find.text('Pfad gefunden'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('node-rectangle-2')));
      await tester.pump();
      expect(selected, 'rectangle-2');
      snapshot = rawNodes
          .map(
            (n) => {
              ...n,
              'id': 'new-${n['id']}',
              'parentId': n['parentId'] == '' ? '' : 'new-${n['parentId']}',
            },
          )
          .toList();
      await tester.pump(const Duration(milliseconds: 500));
      await tester.pump();
      expect(selected, 'new-rectangle-2');
      snapshot = [];
      await tester.pump(const Duration(milliseconds: 500));
      await tester.pump();
      expect(selected, '');
      expect(find.text('Noch kein Knoten ausgewählt.'), findsNothing);
      snapshot = rawNodes;
      await tester.pump(const Duration(milliseconds: 500));
      await tester.pump();
      expect(selected, 'rectangle-2');
      await tester.tap(find.byTooltip('Markierung entfernen'));
      await tester.pump();
      expect(selected, '');
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'overlay converts screen pixels to local coordinates and hides offscreen nodes',
    (tester) async {
      tester.view.devicePixelRatio = 2;
      addTearDown(tester.view.resetDevicePixelRatio);
      final selection = node('selected', '', 'Rechteck', 0);
      final state = <String, dynamic>{
        'selection': selection,
        'drawLeft': 100.0,
        'drawTop': 50.0,
      };
      await tester.pumpWidget(
        MaterialApp(home: InspectorOverlay(state: state)),
      );
      final rect = tester.widget<Positioned>(
        find.byKey(const ValueKey('inspector-highlight')),
      );
      expect(rect.left, 10);
      expect(rect.top, 20);
      expect(rect.width, 30);
      expect(rect.height, 20);
      state['selection'] = {...selection, 'offscreen': true};
      await tester.pumpWidget(
        MaterialApp(home: InspectorOverlay(state: state)),
      );
      expect(find.byKey(const ValueKey('inspector-highlight')), findsNothing);
      state['selection'] = null;
      await tester.pumpWidget(
        MaterialApp(home: InspectorOverlay(state: state)),
      );
      expect(find.byKey(const ValueKey('inspector-highlight')), findsNothing);
    },
  );
}
