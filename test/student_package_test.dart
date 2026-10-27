import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:schului/authoring/lesson_document.dart';
import 'package:schului/authoring/lesson_files.dart';
import 'package:schului/authoring/student_package.dart';
import 'package:schului/lessons/lesson_model.dart';

import 'sample_lesson.dart';

void main() {
  late Directory root, runtime, destination;
  late File executable;
  setUp(() async {
    root = await Directory.systemTemp.createTemp('schului-export-test-');
    runtime = await Directory('${root.path}/runtime').create();
    destination = await Directory('${root.path}/Schüler Pakete').create();
    executable = await File('${runtime.path}/schului.exe')
        .writeAsBytes([1, 2, 3]);
    for (final path in [
      'flutter_windows.dll',
      'plugin.dll',
      'data/icudtl.dat',
      'data/flutter_assets/nested/asset.bin',
    ]) {
      final file = File('${runtime.path}/$path');
      await file.parent.create(recursive: true);
      await file.writeAsBytes([4, 5, 6]);
    }
    await File('${runtime.path}/native_assets.json').writeAsString('{}');
    await File('${runtime.path}/private.schului').writeAsString('private');
    await File('${runtime.path}/connection-diagnostics.txt')
        .writeAsString('private');
    await File('${runtime.path}/schului.pdb').writeAsString('debug symbols');
  });
  tearDown(() => root.delete(recursive: true));

  Future<Directory> export({LessonDocument? document, Directory? parent}) =>
      exportStudentPackage(
        document: document ?? sampleDocument(),
        destinationParent: parent ?? destination,
        runtimeExecutable: executable,
        licenseText: 'Test license',
      );

  test('exports a movable runtime with the exact lesson and a relative student launcher', () async {
    final package = await export();
    expect(
      (await readLessonFile('${package.path}/unterricht.schului')).encode(),
      sampleDocument().encode(),
    );
    expect(await File('${package.path}/schului.exe').readAsBytes(), [1, 2, 3]);
    expect(await File('${package.path}/plugin.dll').readAsBytes(), [4, 5, 6]);
    expect(
      await File('${package.path}/data/flutter_assets/nested/asset.bin')
          .readAsBytes(),
      [4, 5, 6],
    );
    expect(
      await File('${package.path}/LICENSE').readAsString(),
      'Test license',
    );
    expect(await File('${package.path}/private.schului').exists(), isFalse);
    expect(
      await File('${package.path}/connection-diagnostics.txt').exists(),
      isFalse,
    );
    expect(await File('${package.path}/schului.pdb').exists(), isFalse);
    final moved = await package.rename('${destination.path}/Anderer Ordner');
    final bat = await File('${moved.path}/start-lernen.bat').readAsString();
    expect(
      bat,
      contains('"%~dp0schului.exe" --lesson-file "%~dp0unterricht.schului"'),
    );
    expect(bat, isNot(contains(runtime.path)));
    expect(bat, isNot(contains(sampleDocument().title)));
    expect(
      (await readLessonFile('${moved.path}/unterricht.schului'))
          .steps[1]
          .links
          .first
          .target
          ?.toJson(),
      saveTarget.toJson(),
    );
    expect(await destination.list().length, 1);
  });

  test('repeated exports preserve the earlier package and unrelated destination files', () async {
    final first = await export();
    await File('${first.path}/marker.txt').writeAsString('keep');
    final second = await export();
    expect(first.path, isNot(second.path));
    expect(await File('${first.path}/marker.txt').readAsString(), 'keep');
    expect(await destination.list().length, 2);
  });

  test('rejects an unconfigured lesson and incomplete runtime before creating output', () async {
    await expectLater(
      export(document: LessonDocument.empty()),
      throwsFormatException,
    );
    await File('${runtime.path}/flutter_windows.dll').delete();
    await expectLater(export(), throwsFormatException);
    expect(await destination.list().length, 0);
  });

  test(
    'a failed lesson write removes partial output and preserves existing files',
    () async {
      final marker = await File('${destination.path}/keep.txt')
          .writeAsString('keep');
      final tooLarge = LessonDocument(
        title: 'Zu groß',
        application: sampleApplication,
        steps: [
          LessonStep('Schritt', [
            LessonParagraph(List.generate(60, (_) => LessonText('x' * 80000))),
          ], ''),
        ],
      );
      await expectLater(export(document: tooLarge), throwsFormatException);
      expect(await marker.readAsString(), 'keep');
      expect(await destination.list().length, 1);
    },
  );

  test(
    'refuses destinations within source assets to prevent recursive self-copy',
    () async {
      await expectLater(
        export(parent: Directory('${runtime.path}/data/flutter_assets')),
        throwsFormatException,
      );
      expect(await destination.list().length, 0);
    },
  );

  test('command punctuation and reserved device names cannot become launcher commands or invalid folder names', () async {
    for (final title in ['CON', '..\\..\\A & echo attack %TEMP%!', 'NUL']) {
      final package = await export(
        document: LessonDocument(
          title: title,
          application: sampleApplication,
          steps: sampleSteps,
        ),
      );
      expect(
        await File('${package.path}/start-lernen.bat').readAsString(),
        studentLauncher,
      );
      expect(
        (await readLessonFile('${package.path}/unterricht.schului')).title,
        title,
      );
      expect(
        await package.parent.resolveSymbolicLinks(),
        await destination.resolveSymbolicLinks(),
      );
    }
  });
}
