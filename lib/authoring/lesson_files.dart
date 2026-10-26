import 'dart:io';
import 'dart:convert';

import 'package:file_selector/file_selector.dart';

import 'lesson_document.dart';

const lessonType = XTypeGroup(
  label: 'schului-Lernumgebung',
  extensions: ['schului'],
);

Future<LessonDocument> readLessonFile(String path) async {
  final file = File(path);
  if (await file.length() > 4 * 1024 * 1024) {
    throw const FormatException('Die Lerndatei darf höchstens 4 MB groß sein.');
  }
  return LessonDocument.decode(await file.readAsString());
}

/// Write beside the destination so a failed write preserves the previous file.
Future<void> writeLessonFile(String path, LessonDocument document) async {
  final source = document.encode();
  if (utf8.encode(source).length > 4 * 1024 * 1024) {
    throw const FormatException('Die Lerndatei darf höchstens 4 MB groß sein.');
  }
  final staging = File('$path.${DateTime.now().microsecondsSinceEpoch}.tmp');
  try {
    await staging.writeAsString(source, flush: true);
    await staging.rename(path);
  } finally {
    if (await staging.exists()) await staging.delete();
  }
}

Future<void> launchLesson(
  LessonDocument document, {
  bool inspector = false,
}) async {
  final directory = await Directory.systemTemp.createTemp('schului-preview-');
  try {
    final file = File('${directory.path}/lesson.schului');
    await writeLessonFile(file.path, document);
    final process = await Process.start(Platform.resolvedExecutable, [
      '--lesson-file',
      file.path,
      if (inspector) '--inspector',
    ]);
    // Drain pipes and retain the immutable snapshot until all engines exit.
    final results = await Future.wait<Object?>([
      process.stdout.drain<void>(),
      process.stderr.drain<void>(),
      process.exitCode,
    ]);
    if (results.last != 0) {
      throw ProcessException(
        Platform.resolvedExecutable,
        const [],
        'Die Lernsitzung wurde mit Fehlercode ${results.last} beendet.',
      );
    }
  } finally {
    await directory.delete(recursive: true);
  }
}
