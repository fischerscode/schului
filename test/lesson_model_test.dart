import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:schului/lessons/lesson_content.dart';

import 'sample_lesson.dart';

import 'package:schului/lessons/application_target.dart';
import 'package:schului/lessons/lesson_model.dart';

void main() {
  test('tool and object links retain their authored paths', () {
    final tool = sampleSteps[1].links.singleWhere(
      (link) => link.text == 'Speichern',
    );
    final object = sampleSteps[1].links.singleWhere(
      (link) => link.text == 'Öffnen',
    );
    expect(tool.target, same(saveTarget));
    expect(object.target, same(openTarget));
    for (final link in [tool, object]) {
      expect(
        ApplicationTarget.fromJson(link.target!.toJson()).toJson(),
        link.target!.toJson(),
      );
    }
  });

  testWidgets(
    'markup stays literal, bold stays plain, and arbitrary link text carries its target',
    (tester) async {
      const link = LessonLink(
        'Frei benannt',
        target: saveTarget,
        help: 'Mein Hilfetext',
      );
      final events = <LessonLink?>[];
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: LessonContent(
              lessons: const [
                LessonStep('Ein Abschnitt', [
                  LessonParagraph([LessonText('**bleibt Text**')]),
                  LessonParagraph([LessonText('Nur fett', bold: true)]),
                  LessonParagraph([link]),
                  LessonBulletList([
                    LessonParagraph([LessonText('Ein Listenpunkt')]),
                  ]),
                ], ''),
              ],
              onHover: events.add,
              onSection: (_) {},
            ),
          ),
        ),
      );
      expect(find.text('**bleibt Text**'), findsOneWidget);
      expect(find.text('Ein Listenpunkt'), findsOneWidget);
      final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
      await mouse.addPointer(location: Offset.zero);
      await mouse.moveTo(tester.getCenter(find.text('Nur fett')));
      await tester.pump();
      expect(events, isEmpty);
      await mouse.moveTo(tester.getCenter(find.text('Frei benannt')));
      await tester.pump();
      expect(events.single, same(link));
      expect(events.single!.target, same(saveTarget));
      await mouse.moveTo(Offset.zero);
      await tester.pump();
      expect(events.last, isNull);
      await mouse.removePointer();
      await tester.pumpWidget(const SizedBox());
    },
  );
}
