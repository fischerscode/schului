import 'dart:convert';

import '../lessons/lesson_model.dart';
import '../lessons/application_target.dart';
import 'target_application.dart';

/// Versioned, portable lesson content. Runtime IDs and coordinates are excluded.
class LessonDocument {
  LessonDocument({
    required this.title,
    required List<LessonStep> steps,
    this.application = const UnconfiguredApplication(),
  }) : steps = List.unmodifiable(steps) {
    if (title.trim().isEmpty || steps.isEmpty || steps.length > 200) {
      throw const FormatException('Titel und 1 bis 200 Schritte erforderlich.');
    }
  }

  final String title;
  final TargetApplication application;
  final List<LessonStep> steps;

  factory LessonDocument.empty() => LessonDocument(
    title: 'Neue Lernumgebung',
    application: const UnconfiguredApplication(),
    steps: [
      const LessonStep('Erster Schritt', [
        LessonParagraph([LessonText('Dein Arbeitsauftrag.')]),
      ], ''),
    ],
  );

  String encode() => const JsonEncoder.withIndent('  ').convert({
    'format': 'schului.lesson',
    'version': 2,
    'application': application.toJson(),
    'title': title,
    'steps': [
      for (final step in steps)
        {
          'title': step.title,
          'hint': step.hint,
          'content': [
            for (final block in step.content)
              switch (block) {
                LessonParagraph() => {
                  'type': 'paragraph',
                  'spans': _encodeSpans(block),
                },
                LessonBulletList() => {
                  'type': 'bullets',
                  'items': [for (final item in block.items) _encodeSpans(item)],
                },
                LessonActivity() => {
                  'type': 'activity',
                  'label': block.label,
                  'url': block.url,
                },
              },
          ],
        },
    ],
  });

  static List<Map<String, Object?>> _encodeSpans(LessonParagraph paragraph) => [
    for (final span in paragraph.spans)
      switch (span) {
        LessonText() => {'type': 'text', 'text': span.text, 'bold': span.bold},
        LessonLink() => {
          'type': 'link',
          'text': span.text,
          'help': span.help,
          'target': span.target?.toJson(),
        },
      },
  ];

  factory LessonDocument.decode(String source) {
    final Object? raw = jsonDecode(source);
    if (raw is! Map<String, Object?> ||
        raw['format'] != 'schului.lesson' ||
        raw['version'] != 2) {
      throw const FormatException(
        'Keine unterstützte schului-Lerndatei (Version 2).',
      );
    }
    final application = TargetApplication.fromJson(raw['application']);
    final result = <LessonStep>[];
    for (final entry in _list(raw['steps'])) {
      final step = _map(entry);
      final content = <LessonBlock>[];
      for (final entry in _list(step['content'])) {
        final block = _map(entry);
        content.add(switch (_text(block['type'])) {
          'paragraph' => _paragraph(block['spans']),
          'bullets' => LessonBulletList([
            for (final item in _list(block['items'])) _paragraph(item),
          ]),
          'activity' => LessonActivity(
            _text(block['label']),
            url: validateActivityUrl(_text(block['url'])),
          ),
          _ => throw const FormatException('Unbekannter Inhaltsbaustein.'),
        });
      }
      if (content.isEmpty) {
        throw const FormatException('Ein Schritt braucht Inhalt.');
      }
      result.add(
        LessonStep(
          _text(step['title']),
          List.unmodifiable(content),
          _text(step['hint'], allowEmpty: true),
        ),
      );
    }
    return LessonDocument(
      title: _text(raw['title']),
      steps: result,
      application: application,
    );
  }

  static LessonParagraph _paragraph(Object? raw) {
    final spans = <LessonSpan>[];
    for (final entry in _list(raw)) {
      final span = _map(entry);
      final text = _text(span['text'], allowEmpty: true);
      switch (span['type']) {
        case 'text':
          if (span['bold'] is! bool) {
            throw const FormatException('Ungültige Textformatierung.');
          }
          spans.add(LessonText(text, bold: span['bold'] == true));
        case 'link':
          final help = span['help'];
          if (help != null && help is! String) {
            throw const FormatException('Ungültiger Hilfetext.');
          }
          final target = span['target'];
          spans.add(
            LessonLink(
              text,
              help: help as String?,
              target: target == null
                  ? null
                  : ApplicationTarget.fromJson(_map(target)),
            ),
          );
        default:
          throw const FormatException('Unbekannter Textbaustein.');
      }
    }
    if (spans.isEmpty) {
      throw const FormatException('Ein Absatz braucht Textbausteine.');
    }
    return LessonParagraph(List.unmodifiable(spans));
  }

  static Map<String, Object?> _map(Object? raw) {
    if (raw is! Map<String, Object?>) {
      throw const FormatException('Objekt erwartet.');
    }
    return raw;
  }

  static List<Object?> _list(Object? raw) {
    if (raw is! List<Object?> || raw.length > 1000) {
      throw const FormatException(
        'Liste mit höchstens 1000 Einträgen erwartet.',
      );
    }
    return raw;
  }

  static String _text(Object? raw, {bool allowEmpty = false}) {
    if (raw is! String ||
        raw.length > 100000 ||
        (!allowEmpty && raw.trim().isEmpty)) {
      throw const FormatException('Gültiger Text erforderlich.');
    }
    return raw;
  }
}

String validateActivityUrl(String source) {
  final uri = Uri.tryParse(source);
  if (uri == null ||
      uri.scheme != 'https' ||
      uri.host.isEmpty ||
      uri.userInfo.isNotEmpty) {
    throw const FormatException('Eine vollständige HTTPS-Adresse eingeben.');
  }
  return source;
}
