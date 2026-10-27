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
    n('r', '', 'Editor', type: 'window'),
    n('p0', 'r', '', type: 'pane'),
    n('p1', 'r', '', type: 'pane'),
    n('b', 'p1', 'Save'),
  ];
  final selector = NodeSelector.capture(original.last, original);
  test('exact capture round trips with new runtime IDs and root caption', () {
    final nodes = [
      n('new', '', 'Other title', type: 'window'),
      n('a', 'new', '', type: 'pane'),
      n('b2', 'new', '', type: 'pane'),
      n('target', 'b2', 'Save'),
    ];
    final loaded = NodeSelector.fromJson(selector.toJson());
    expect(loaded.path[1].index, 1);
    expect(loaded.resolve(nodes).node?.id, 'target');
  });
  test('same names in another branch do not change target identity', () {
    expect(
      selector.resolve([...original, n('other', 'p0', 'Save')]).node?.id,
      'b',
    );
  });
  test(
    'duplicate targets are ambiguous and missing ancestors never fall back',
    () {
      expect(
        selector.resolve([
          ...original,
          n('duplicate', 'p1', 'Save'),
        ]).isAmbiguous,
        isTrue,
      );
      expect(
        selector.resolve([original.first, n('moved', 'r', 'Save')]).node,
        isNull,
      );
      expect(selector.resolve([]).node, isNull);
    },
  );
  test('malformed and unsupported path formats are rejected', () {
    for (final raw in [
      {
        'version': 1,
        'mode': 'exact',
        'path': [
          {'type': 'button'},
        ],
      },
      {
        'version': 2,
        'path': [
          {'type': 'button'},
        ],
      },
      {
        'version': 2,
        'mode': 'other',
        'path': [
          {'type': 'button'},
        ],
      },
      {'version': 2, 'mode': 'exact', 'path': []},
      {
        'version': 2,
        'mode': 'exact',
        'path': [
          {'type': 'button', 'name': 'Save', 'index': 0},
        ],
      },
      {
        'version': 2,
        'mode': 'exact',
        'path': [
          {'type': 'pane', 'name': '', 'index': -1},
        ],
      },
      {
        'version': 2,
        'mode': 'exact',
        'path': [
          {'type': 'pane', 'name': '', 'index': 0.5},
        ],
      },
    ]) {
      expect(() => NodeSelector.fromJson(raw), throwsFormatException);
    }
  });
}
