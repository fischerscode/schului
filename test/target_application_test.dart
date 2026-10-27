import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:schului/authoring/target_application.dart';
import 'package:schului/authoring/lesson_document.dart';
import 'package:schului/authoring/teacher_view.dart';
import 'package:schului/authoring/target_picker.dart';
import 'package:schului/src/node_selector.dart';
import 'package:schului/src/accessibility_node.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('version 2 stores arbitrary software and arguments without losing target identity', () {
    final app = WindowsApplication(
      name: 'Example Editor',
      executable: r'C:\Program Files\Editor\editor.exe',
      arguments: ['--new-window', 'a b.txt', ''],
      windowClass: 'EditorWindow',
      titleContains: 'Practice',
    );
    final document = LessonDocument(
      title: 'Text bearbeiten',
      steps: LessonDocument.empty().steps,
      application: app,
    );
    final loaded = LessonDocument.decode(document.encode());
    expect(loaded.application.toJson(), app.toJson());
    expect(jsonDecode(document.encode())['version'], 2);
    expect(LessonDocument.empty().application, isA<UnconfiguredApplication>());
    expect(
      () => WindowsApplication(name: 'Invalid', executable: 'relative.exe'),
      throwsFormatException,
    );
  });
  test('generic selectors preserve title-like wrappers and document names and never use fallback', () {
    AccessibilityNode node(
      String id,
      String parent,
      String type,
      String name,
      int depth,
    ) => AccessibilityNode(
      id: id,
      parentId: parent,
      type: type,
      name: name,
      depth: depth,
      bounds: const Rect.fromLTWH(1, 2, 30, 40),
    );
    final nodes = [
      node('r', '', 'Window', 'Example Editor', 0),
      node('w', 'r', '', 'Example Editor', 1),
      node('d', 'w', 'Dokument', 'Exercise', 2),
      node('b', 'd', 'Button', 'Save', 3),
    ];
    final captured = NodeSelector.capture(nodes.last, nodes);
    expect(captured.path.length, 4);
    expect(captured.path[1].name, 'Example Editor');
    final loaded = NodeSelector.fromJson(captured.toJson());
    expect(loaded.path[2].name, 'Exercise');
    expect(loaded.resolve(nodes).node?.id, 'b');
    final otherDocument = [...nodes]
      ..[2] = node('d', 'w', 'Dokument', 'Other exercise', 2);
    expect(loaded.resolve(otherDocument).node, isNull);
  });
  testWidgets(
    'teachers select any open application and keep it when editing content',
    (tester) async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
            targetPickerChannel,
            (_) async => [
              {
                'id': 41,
                'title': 'Example Editor',
                'executable': r'C:\Tools\editor.exe',
                'windowClass': 'EditorWindow',
              },
            ],
          );
      addTearDown(
        () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(targetPickerChannel, null),
      );
      await tester.pumpWidget(const MaterialApp(home: TeacherView()));
      await tester.tap(find.byTooltip('Zielsoftware'));
      await tester.pumpAndSettle();
      await tester.tap(find.byType(DropdownButtonFormField<int>));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Example Editor').last);
      await tester.pumpAndSettle();
      await tester.enterText(
        find.widgetWithText(TextField, 'Name'),
        'Mein Editor',
      );
      await tester.tap(find.text('Übernehmen'));
      await tester.pumpAndSettle();
      expect(find.text('Mein Editor'), findsOneWidget);
      await tester.enterText(
        find.widgetWithText(TextField, 'Schritttitel'),
        'Schreiben',
      );
      await tester.tap(find.byTooltip('Zielsoftware'));
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<TextField>(find.widgetWithText(TextField, 'Programmpfad'))
            .controller
            ?.text,
        r'C:\Tools\editor.exe',
      );
    },
  );
  test(
    'hover picker scopes capture to the selected generic application',
    () async {
      final app = WindowsApplication(
        name: 'Editor',
        executable: r'C:\Tools\editor.exe',
      );
      Object? arguments;
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(targetPickerChannel, (call) async {
            arguments = call.arguments;
            return null;
          });
      addTearDown(
        () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(targetPickerChannel, null),
      );
      await TargetPicker().pick(application: app, onCandidate: (_, _) {});
      expect(arguments, app.toJson());
    },
  );
}
