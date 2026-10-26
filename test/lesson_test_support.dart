import 'package:schului/lessons/draw_lesson.dart';
import 'package:schului/src/accessibility_node.dart';

// Tests inspect the authored links; production never looks targets up by text.
AccessibilityNode? resolveAuthoredTarget(
  String label,
  int section,
  List<AccessibilityNode> nodes,
) {
  final links = [
    ...steps[section].links,
    ...steps.expand((step) => step.links),
  ];
  return links.firstWhere((link) => link.text == label).target?.resolve(nodes);
}
