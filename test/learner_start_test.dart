import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:schului/main.dart' as application;
import 'package:schului/authoring/teacher_view.dart';

import 'sample_lesson.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
    'a lesson file starts the student session without the teacher editor',
    (tester) async {
      late Directory directory;
      await tester.runAsync(() async {
        directory = await Directory.systemTemp.createTemp('schului-student-');
      });
      addTearDown(() => directory.delete(recursive: true));
      final file = File('${directory.path}/Unterricht mit Leerzeichen.schului');
      await tester.runAsync(
        () => file.writeAsString(sampleDocument().encode()),
      );
      Object? configuration;
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(application.bridge, (call) async {
            if (call.method == 'configureApplication') {
              configuration = call.arguments;
            }
            return call.method == 'state' ? {'connected': true} : null;
          });
      addTearDown(
        () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(application.bridge, null),
      );
      await tester.runAsync(
        () => application.main(['lesson', '--lesson-file', file.path]),
      );
      await tester.pumpAndSettle();
      expect(configuration, sampleApplication.toJson());
      expect(find.byType(application.SessionView), findsOneWidget);
      expect(find.byType(TeacherView), findsNothing);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'missing and malformed lesson files never fall back to the teacher editor',
    (tester) async {
      late Directory directory;
      await tester.runAsync(() async {
        directory = await Directory.systemTemp.createTemp('schului-student-');
      });
      addTearDown(() => directory.delete(recursive: true));
      final file = File('${directory.path}/invalid.schului');
      await tester.runAsync(() => file.writeAsString('invalid'));
      for (final arguments in [
        ['lesson', '--lesson-file'],
        ['lesson', '--lesson-file', '${directory.path}/missing.schului'],
        ['lesson', '--lesson-file', file.path],
      ]) {
        await tester.runAsync(() => application.main(arguments));
        await tester.pumpAndSettle();
        expect(find.byType(TeacherView), findsNothing);
        expect(
          find.textContaining('Lernumgebung kann nicht geöffnet werden'),
          findsOneWidget,
        );
        await tester.pumpWidget(const SizedBox());
      }
    },
  );
}
