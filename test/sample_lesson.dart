import 'package:flutter/painting.dart';
import 'package:schului/authoring/lesson_document.dart';
import 'package:schului/authoring/target_application.dart';
import 'package:schului/lessons/application_target.dart';
import 'package:schului/lessons/lesson_model.dart';
import 'package:schului/src/accessibility_node.dart';
import 'package:schului/src/node_selector.dart';

final sampleApplication = WindowsApplication(
  name: 'Beispiel-Editor',
  executable: r'C:\Tools\editor.exe',
);
const saveTarget = ApplicationTarget(
  NodeSelector([PathSegment('Window', null), PathSegment('Button', 'Save')]),
);
const openTarget = ApplicationTarget(
  NodeSelector([PathSegment('Window', null), PathSegment('Button', 'Open')]),
);
const sampleSteps = [
  LessonStep('Willkommen', [
    LessonParagraph([LessonText('Lerne den Editor kennen.')]),
  ], 'Ein Tipp'),
  LessonStep('Dein erster Text', [
    LessonParagraph([
      LessonText('Nutze '),
      LessonLink('Speichern', target: saveTarget, help: 'Datei sichern'),
      LessonText(' oder '),
      LessonLink('Öffnen', target: openTarget),
    ]),
  ], 'Ein weiterer Tipp'),
  LessonStep('Bearbeiten', [
    LessonBulletList([
      LessonParagraph([LessonText('Text eingeben', bold: true)]),
    ]),
  ], ''),
  LessonStep('Prüfen', [
    LessonParagraph([LessonText('Lies deinen Text.')]),
  ], ''),
  LessonStep('Üben', [
    LessonActivity('Lückentext öffnen', url: 'https://example.org/exercise'),
  ], ''),
  LessonStep('Vergleichen', [
    LessonParagraph([LessonText('Vergleiche dein Ergebnis.')]),
  ], ''),
  LessonStep('Abschluss', [
    LessonParagraph([LessonText('Fertig!')]),
  ], ''),
];
LessonDocument sampleDocument() => LessonDocument(
  title: 'Text bearbeiten',
  application: sampleApplication,
  steps: sampleSteps,
);
List<AccessibilityNode> sampleTree() => [
  AccessibilityNode(
    id: 'root',
    parentId: '',
    type: 'Window',
    name: 'Editor',
    depth: 0,
    bounds: const Rect.fromLTWH(100, 50, 900, 700),
  ),
  AccessibilityNode(
    id: 'save',
    parentId: 'root',
    type: 'Button',
    name: 'Save',
    depth: 1,
    bounds: const Rect.fromLTWH(450, 300, 130, 90),
  ),
];
