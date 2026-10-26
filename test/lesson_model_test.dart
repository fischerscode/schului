import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:schului/lessons/draw_lesson.dart';
import 'package:schului/lessons/draw_target.dart';
import 'package:schului/lessons/draw_targets.dart';
import 'package:schului/lessons/lesson_content.dart';

void main() {
  test('tool and object links retain their authored paths', () {
    final tool = steps[1].links.singleWhere((link) => link.text == 'Rechteck');
    final object = steps[2].links.singleWhere((link) => link.text == 'Objekt');
    expect(tool.target, same(DrawTargets.rectangleTool));
    expect(object.target, same(DrawTargets.rectangleObject));
    for (final link in [tool, object]) {
      expect(
        DrawTarget.fromJson(link.target!.toJson()).toJson(),
        link.target!.toJson(),
      );
    }
  });

  testWidgets(
    'markup stays literal, bold stays plain, and arbitrary link text carries its target',
    (tester) async {
      const link = LessonLink(
        'Frei benannt',
        target: DrawTargets.width,
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
      expect(events.single!.target, same(DrawTargets.width));
      await mouse.moveTo(Offset.zero);
      await tester.pump();
      expect(events.last, isNull);
      await mouse.removePointer();
      await tester.pumpWidget(const SizedBox());
    },
  );
}
