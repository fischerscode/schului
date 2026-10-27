import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:schului/authoring/lesson_document.dart';
import 'package:schului/authoring/lesson_files.dart';

import 'sample_lesson.dart';

void main() {
  test(
    'all authored content, help and exact UIA paths survive a file round trip',
    () async {
      final document = sampleDocument();
      final directory = await Directory.systemTemp.createTemp('schului-test-');
      addTearDown(() => directory.delete(recursive: true));
      final path = '${directory.path}/lesson.schului';
      await writeLessonFile(path, document);
      final loaded = await readLessonFile(path);
      expect(loaded.encode(), document.encode());
      expect(
        loaded.steps[1].links.first.target?.toJson(),
        document.steps[1].links.first.target?.toJson(),
      );
      // Replacing a file must work on Windows too.
      await writeLessonFile(path, LessonDocument.empty());
      expect((await readLessonFile(path)).title, 'Neue Lernumgebung');
      expect(await directory.list().length, 1);
    },
  );

  test('reject unsupported formats and malformed content instead of inventing a lesson', () {
    final valid = jsonDecode(sampleDocument().encode()) as Map<String, Object?>;
    for (final patch in <Map<String, Object?>>[
      {'version': 99},
      {'version': 1},
      {'application': 'unknown'},
      {'steps': []},
      {'title': ''},
      {
        'steps': [
          {
            'title': 'Test',
            'hint': '',
            'content': [
              {'type': 'unknown'},
            ],
          },
        ],
      },
      {
        'steps': [
          {
            'title': 'Test',
            'hint': '',
            'content': [
              {
                'type': 'activity',
                'label': 'Übung',
                'url': 'file:///C:/private',
              },
            ],
          },
        ],
      },
    ]) {
      expect(
        () => LessonDocument.decode(jsonEncode({...valid, ...patch})),
        throwsFormatException,
      );
    }
  });

  test('reject files beyond the supported size', () async {
    final directory = await Directory.systemTemp.createTemp('schului-test-');
    addTearDown(() => directory.delete(recursive: true));
    final file = File('${directory.path}/large.schului');
    await file.writeAsBytes(List.filled(4 * 1024 * 1024 + 1, 32));
    await expectLater(readLessonFile(file.path), throwsFormatException);
  });
}
