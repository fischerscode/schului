import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:schului/src/accessibility_node.dart';

import 'sample_lesson.dart';

void main() {
  test('only a unique, visible exact target can be highlighted', () {
    final nodes = sampleTree();
    expect(saveTarget.resolve(nodes)?.id, 'save');
    final hidden = AccessibilityNode(
      id: 'save',
      parentId: 'root',
      type: 'Button',
      name: 'Save',
      depth: 1,
      bounds: const Rect.fromLTWH(1, 2, 30, 40),
      offscreen: true,
    );
    expect(saveTarget.resolve([nodes.first, hidden]), isNull);
    expect(
      saveTarget.resolve([nodes.first, hidden], requireVisible: false)?.id,
      'save',
    );
    final duplicate = AccessibilityNode(
      id: 'duplicate',
      parentId: 'root',
      type: 'Button',
      name: 'Save',
      depth: 1,
      bounds: const Rect.fromLTWH(1, 2, 30, 40),
    );
    expect(saveTarget.resolve([...nodes, duplicate]), isNull);
    expect(saveTarget.resolve([nodes.first]), isNull);
  });
}
