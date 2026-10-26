import 'draw_target.dart';

class LessonStep {
  const LessonStep(this.title, this.content, this.hint);
  final String title, hint;
  final List<LessonBlock> content;

  Iterable<LessonLink> get links sync* {
    for (final block in content) {
      final paragraphs = switch (block) {
        LessonParagraph() => [block],
        LessonBulletList() => block.items,
        LessonActivity() => <LessonParagraph>[],
      };
      for (final paragraph in paragraphs) {
        yield* paragraph.spans.whereType<LessonLink>();
      }
    }
  }
}

sealed class LessonBlock {
  const LessonBlock();
}

class LessonParagraph extends LessonBlock {
  const LessonParagraph(this.spans);
  final List<LessonSpan> spans;
}

class LessonBulletList extends LessonBlock {
  const LessonBulletList(this.items);
  final List<LessonParagraph> items;
}

class LessonActivity extends LessonBlock {
  const LessonActivity(this.label, {required this.url});
  final String label, url;
}

sealed class LessonSpan {
  const LessonSpan(this.text);
  final String text;
}

class LessonText extends LessonSpan {
  const LessonText(super.text, {this.bold = false});
  final bool bold;
}

class LessonLink extends LessonSpan {
  const LessonLink(super.text, {this.target, this.help});
  final DrawTarget? target;
  final String? help;
}
