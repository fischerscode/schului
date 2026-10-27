import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:schului/authoring/span_dialog.dart';
import 'package:schului/authoring/target_picker.dart';
import 'package:schului/lessons/draw_targets.dart';
import 'package:schului/lessons/lesson_model.dart';
import 'package:schului/src/schulzeug_theme.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
    'hover selection inserts the confirmed native path into the authored link',
    (tester) async {
      final completion = Completer<Object?>();
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
            targetPickerChannel,
            (call) async => call.method == 'begin' ? completion.future : null,
          );
      addTearDown(
        () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(targetPickerChannel, null),
      );
      LessonSpan? saved;
      await tester.pumpWidget(
        MaterialApp(
          theme: schulzeugTheme(),
          home: Builder(
            builder: (context) => Scaffold(
              body: TextButton(
                onPressed: () async {
                  saved = await editSpan(
                    context,
                    const LessonLink('Mein Werkzeug'),
                  );
                },
                child: const Text('Bearbeiten'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Bearbeiten'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Ziel in Anwendung auswählen'));
      await tester.pumpAndSettle();
      expect(
        find.text(
          'Über ein Ziel in der Anwendung zeigen. F8 übernimmt, Esc bricht ab.',
        ),
        findsOneWidget,
      );
      expect(
        tester
            .widget<FilledButton>(
              find.widgetWithText(FilledButton, 'Übernehmen'),
            )
            .onPressed,
        isNull,
      );
      completion.complete(DrawTargets.ellipseTool.toJson());
      await tester.pumpAndSettle();
      final pathField = tester.widget<TextField>(
        find.widgetWithText(TextField, 'Zielpfad (JSON, optional)'),
      );
      expect(
        jsonDecode(pathField.controller?.text ?? ''),
        DrawTargets.ellipseTool.toJson(),
      );
      await tester.tap(find.text('Übernehmen'));
      await tester.pumpAndSettle();
      expect(saved, isA<LessonLink>());
      if (saved case LessonLink(:final target)) {
        expect(target?.toJson(), DrawTargets.ellipseTool.toJson());
      }
    },
  );

  testWidgets('cancelling hover selection preserves the previous path', (
    tester,
  ) async {
    final completion = Completer<Object?>();
    final calls = <String>[];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(targetPickerChannel, (call) async {
          calls.add(call.method);
          if (call.method == 'begin') return completion.future;
          if (call.method == 'cancel') completion.complete(null);
          return null;
        });
    addTearDown(
      () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(targetPickerChannel, null),
    );
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () => editSpan(
                context,
                const LessonLink('Rechteck', target: DrawTargets.rectangleTool),
              ),
              child: const Text('Bearbeiten'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Bearbeiten'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Ziel in Anwendung auswählen'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Zielauswahl abbrechen'));
    await tester.pumpAndSettle();
    final field = tester.widget<TextField>(
      find.widgetWithText(TextField, 'Zielpfad (JSON, optional)'),
    );
    expect(
      jsonDecode(field.controller?.text ?? ''),
      DrawTargets.rectangleTool.toJson(),
    );
    expect(calls, ['begin', 'cancel']);
  });

  test('malformed native target does not become lesson content', () async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          targetPickerChannel,
          (_) async => {
            'includesUnnamedClient': false,
            'selector': {'version': 2, 'path': []},
          },
        );
    addTearDown(
      () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(targetPickerChannel, null),
    );
    await expectLater(
      TargetPicker().pick(onCandidate: (_, _) {}),
      throwsFormatException,
    );
  });

  testWidgets('native picker failures remain visible and allow retry', (
    tester,
  ) async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          targetPickerChannel,
          (_) async => throw PlatformException(
            code: 'desktop',
            message: 'Mausposition nicht verfügbar.',
          ),
        );
    addTearDown(
      () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(targetPickerChannel, null),
    );
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () => editSpan(
                context,
                const LessonLink('Rechteck', target: DrawTargets.rectangleTool),
              ),
              child: const Text('Bearbeiten'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Bearbeiten'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Ziel in Anwendung auswählen'));
    await tester.pumpAndSettle();
    expect(find.text('Mausposition nicht verfügbar.'), findsOneWidget);
    expect(find.text('Ziel in Anwendung auswählen'), findsOneWidget);
    final field = tester.widget<TextField>(
      find.widgetWithText(TextField, 'Zielpfad (JSON, optional)'),
    );
    expect(
      jsonDecode(field.controller?.text ?? ''),
      DrawTargets.rectangleTool.toJson(),
    );
  });
}
