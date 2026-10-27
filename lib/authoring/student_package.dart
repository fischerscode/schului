import 'dart:io';

import 'lesson_document.dart';
import 'lesson_files.dart';
import 'target_application.dart';

/// Fixed, relative filenames keep lesson titles and machine paths out of CMD.
const studentLauncher =
    '@echo off\r\n'
    'setlocal\r\n'
    'start "" /D "%~dp0" "%~dp0schului.exe" '
    '--lesson-file "%~dp0unterricht.schului"\r\n';

/// Publish a complete folder only after every file has been copied successfully.
Future<Directory> exportStudentPackage({
  required LessonDocument document,
  required Directory destinationParent,
  required File runtimeExecutable,
  required String licenseText,
}) async {
  if (document.application is! WindowsApplication) {
    throw const FormatException('Zuerst eine Zielsoftware auswählen.');
  }
  // Validate the same content that the student runtime will load.
  LessonDocument.decode(document.encode());
  final runtime = runtimeExecutable.parent;
  final data = Directory('${runtime.path}/data');
  if (!await runtimeExecutable.exists() ||
      !await File('${runtime.path}/flutter_windows.dll').exists() ||
      !await File('${data.path}/icudtl.dat').exists() ||
      !await Directory('${data.path}/flutter_assets').exists()) {
    throw const FormatException(
      'Das Schülerpaket im vollständigen Windows-Programm exportieren.',
    );
  }
  final parentPath = await destinationParent.resolveSymbolicLinks();
  final dataPath = await data.resolveSymbolicLinks();
  final parentKey = parentPath.replaceAll('\\', '/').toLowerCase();
  final dataKey = dataPath.replaceAll('\\', '/').toLowerCase();
  if (parentKey == dataKey || parentKey.startsWith('$dataKey/')) {
    throw const FormatException(
      'Einen Zielordner außerhalb der Programmdaten auswählen.',
    );
  }
  final parent = Directory(parentPath);
  final staging = await parent.createTemp('.schului-export-');
  try {
    await writeLessonFile('${staging.path}/unterricht.schului', document);
    await runtimeExecutable.copy('${staging.path}/schului.exe');
    await for (final entry in runtime.list(followLinks: false)) {
      final name = entry.uri.pathSegments.last;
      if (name.toLowerCase().endsWith('.dll') || name == 'native_assets.json') {
        if (entry is! File) {
          throw const FormatException(
            'Programmdateien müssen reguläre Dateien sein.',
          );
        }
        await entry.copy('${staging.path}/$name');
      }
    }
    await _copyDirectory(data, Directory('${staging.path}/data'));
    await File('${staging.path}/start-lernen.bat')
        .writeAsString(studentLauncher, flush: true);
    await File('${staging.path}/LICENSE')
        .writeAsString(licenseText, flush: true);
    await File('${staging.path}/START-HIER.txt').writeAsString(
      'Mit start-lernen.bat beginnt der Unterricht.\r\n'
      'Den gesamten Ordner zusammenlassen.\r\n'
      'Die Zielsoftware muss auf diesem Rechner verfügbar sein.\r\n',
      flush: true,
    );
    final name = _folderName(document.title);
    var destination = '${parent.path}/$name';
    var number = 2;
    while (await FileSystemEntity.type(destination, followLinks: false) !=
        FileSystemEntityType.notFound) {
      destination = '${parent.path}/$name-${number++}';
    }
    return await staging.rename(destination);
  } finally {
    if (await staging.exists()) await staging.delete(recursive: true);
  }
}

String _folderName(String title) {
  final name = title.replaceAll(RegExp(r'[^a-zA-Z0-9äöüÄÖÜß_-]+'), '-');
  final shortened = name.substring(0, name.length.clamp(0, 60));
  return '${shortened.isEmpty ? 'Unterricht' : shortened}-Schuelerpaket';
}

Future<void> _copyDirectory(Directory source, Directory destination) async {
  await destination.create();
  await for (final entry in source.list(followLinks: false)) {
    final segments = entry.uri.pathSegments.where(
      (segment) => segment.isNotEmpty,
    );
    final path = '${destination.path}/${segments.last}';
    if (entry is File) {
      await entry.copy(path);
    } else if (entry is Directory) {
      await _copyDirectory(entry, Directory(path));
    } else {
      throw const FormatException(
        'Die Programmdaten enthalten eine nicht unterstützte Dateiverknüpfung.',
      );
    }
  }
}
