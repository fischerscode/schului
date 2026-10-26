import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:schului/src/accessibility_node.dart';
import 'package:schului/src/node_selector.dart';

AccessibilityNode n(
  String id,
  String parent,
  String name, {
  String type = 'button',
}) => AccessibilityNode(
  id: id,
  parentId: parent,
  name: name,
  type: type,
  depth: 0,
  bounds: const Rect.fromLTWH(0, 0, 10, 10),
);
void main() {
  final original = [
    n('r', '', 'Dokument 1', type: 'window'),
    n('w', 'r', '', type: 'pane'),
    n('t', 'w', 'Zeichnung', type: 'toolbar'),
    n('b', 't', 'Rechteck'),
  ];
  final selector = NodeSelector.capture(original.last, original);
  test('JSON roundtrip resolves new IDs, document title and reordered unnamed wrappers', () {
    final restored = NodeSelector.fromJson(selector.toJson());
    final nodes = [
      n('new', '', 'Dokument 2', type: 'window'),
      n('other', 'new', '', type: 'pane'),
      n('toolbar', 'other', 'Zeichnung', type: 'toolbar'),
      n('extra', 'toolbar', '', type: 'pane'),
      n('target', 'extra', 'Rechteck'),
    ];
    expect(restored.resolve(nodes).node?.id, 'target');
    expect(
      restored.resolve(nodes.reversed.toList()).description,
      contains('Ersatzsuche'),
    );
  });
  test('duplicate target names are distinguished by ancestor path', () {
    final nodes = [
      ...original,
      n('other', 'r', 'Andere', type: 'toolbar'),
      n('duplicate', 'other', 'Rechteck'),
    ];
    expect(selector.resolve(nodes).node?.id, 'b');
  });
  test('missing ancestor uses fallback and reconnects with new runtime ID', () {
    final nodes = [
      n('new', '', 'Draw', type: 'window'),
      n('newtarget', 'new', 'Rechteck'),
    ];
    final result = selector.resolve(nodes);
    expect(result.node?.id, 'newtarget');
    expect(result.description, contains('Ersatzsuche'));
  });
  test('ambiguous exact path and fallback never pick traversal order', () {
    expect(
      selector.resolve([...original, n('second', 't', 'Rechteck')]).node,
      isNull,
    );
    final nodes = [
      n('new', '', 'Draw', type: 'window'),
      n('a', 'new', 'Rechteck'),
      n('b', 'new', 'Rechteck'),
    ];
    expect(selector.resolve(nodes).node, isNull);
    expect(selector.resolve(nodes.reversed.toList()).node, isNull);
  });
  test('wrong type, missing target and malformed selectors fail safely', () {
    expect(
      selector.resolve([
        n('r', '', 'Draw', type: 'window'),
        n('b', 'r', 'Rechteck', type: 'menu'),
      ]).node,
      isNull,
    );
    expect(selector.resolve([]).node, isNull);
    expect(
      () => NodeSelector.fromJson({'version': 1, 'path': []}),
      throwsFormatException,
    );
    expect(
      () => NodeSelector.fromJson({
        'version': 1,
        'path': [
          {'type': 4},
        ],
      }),
      throwsFormatException,
    );
  });
  test('unnamed identical targets resolve their default sibling index', () {
    final nodes = [
      n('r', '', 'Draw', type: 'window'),
      n('a', 'r', '', type: 'pane'),
      n('b', 'r', '', type: 'pane'),
    ];
    final selector = NodeSelector.capture(nodes[1], nodes);
    expect(selector.path.last.index, 0);
    expect(selector.resolve(nodes).node?.id, 'a');
    expect(NodeSelector.capture(nodes[2], nodes).resolve(nodes).node?.id, 'b');
  });
  test('fallback ranks ordered ancestor context and rejects weak context', () {
    final saved = [
      n('r', '', 'Draw', type: 'window'),
      n('p', 'r', 'Arbeitsbereich', type: 'pane'),
      n('t', 'p', 'Zeichnung', type: 'toolbar'),
      n('b', 't', 'Rechteck'),
    ];
    final query = NodeSelector.capture(saved.last, saved);
    final changed = [
      n('r2', '', 'Neues Dokument', type: 'window'),
      n('t2', 'r2', 'Zeichnung', type: 'toolbar'),
      n('b2', 't2', 'Rechteck'),
      n('other', 'r2', 'Andere', type: 'toolbar'),
      n('b3', 'other', 'Rechteck'),
    ];
    expect(query.resolve(changed).node?.id, 'b2');
    expect(query.resolve(changed.reversed.toList()).node?.id, 'b2');
    expect(
      query.resolve([changed.first, n('weak', 'r2', 'Rechteck')]).node,
      isNull,
    );
    final inserted = [
      ...saved.where((node) => node.id != 'b'),
      n('extra', 't', 'Neue Gruppe', type: 'pane'),
      n('new', 'extra', 'Rechteck'),
    ];
    final result = query.resolve(inserted);
    expect(result.node?.id, 'new');
    expect(result.description, contains('Ersatzsuche'));
  });
  test(
    'indexed path wins before fallback and only missing index invokes fallback',
    () {
      final nodes = [
        n('r', '', 'Draw', type: 'window'),
        n('named', 'r', 'Named', type: 'pane'),
        n('a', 'r', '', type: 'pane'),
        n('different', 'r', '', type: 'toolbar'),
        n('b', 'r', '', type: 'pane'),
      ];
      final saved = NodeSelector.fromJson(
        NodeSelector.capture(nodes.last, nodes).toJson(),
      );
      expect(saved.path.last.index, 1);
      final exact = saved.resolve(nodes);
      expect(exact.node?.id, 'b');
      expect(exact.description, 'Pfad gefunden');
      // A valid index is authoritative even when equal unnamed siblings swap.
      expect(saved.resolve([nodes.first, nodes.last, nodes[2]]).node?.id, 'a');
      final missingIndex = saved.resolve([nodes.first, nodes.last]);
      expect(missingIndex.node?.id, 'b');
      expect(missingIndex.description, contains('Ersatzsuche'));
    },
  );
  test('unnamed ancestor indices separate identical named targets', () {
    final nodes = [
      n('r', '', 'Draw', type: 'window'),
      n('a', 'r', '', type: 'pane'),
      n('one', 'a', 'Rechteck'),
      n('b', 'r', '', type: 'pane'),
      n('two', 'b', 'Rechteck'),
    ];
    final saved = NodeSelector.fromJson(
      NodeSelector.capture(nodes.last, nodes).toJson(),
    );
    expect(saved.path[1].index, 1);
    final changedIds = [
      n('new', '', 'Other title', type: 'window'),
      n('first', 'new', '', type: 'pane'),
      n('wrong', 'first', 'Rechteck'),
      n('second', 'new', '', type: 'pane'),
      n('right', 'second', 'Rechteck'),
    ];
    expect(saved.resolve(changedIds).node?.id, 'right');
  });
  test(
    'legacy semantic paths remain supported; invalid indices are rejected',
    () {
      final legacy = NodeSelector.fromJson({
        'version': 1,
        'path': [
          {'type': 'window'},
          {'type': 'toolbar', 'name': 'Zeichnung'},
          {'type': 'button', 'name': 'Rechteck'},
        ],
      });
      expect(legacy.resolve(original).node?.id, 'b');
      for (final value in [-1, 1.5, '1']) {
        expect(
          () => NodeSelector.fromJson({
            'version': 2,
            'path': [
              {'type': 'pane', 'name': '', 'index': value},
            ],
          }),
          throwsFormatException,
        );
      }
    },
  );
}
