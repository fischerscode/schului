import 'package:flutter/material.dart';

import 'lesson_model.dart';
import '../src/windows_bridge.dart';

class LessonContent extends StatefulWidget {
  const LessonContent({
    super.key,
    required this.onHover,
    required this.onSection,
    required this.lessons,
    this.onActivity,
    this.onHint,
  });
  final ValueChanged<LessonLink?> onHover;
  final ValueChanged<int> onSection;
  final List<LessonStep> lessons;
  final ValueChanged<LessonActivity>? onActivity;
  final VoidCallback? onHint;
  @override
  State<LessonContent> createState() => _LessonContentState();
}

class _LessonContentState extends State<LessonContent> {
  final controller = ScrollController();
  final viewport = GlobalKey();
  late final sectionKeys = List.generate(
    widget.lessons.length,
    (_) => GlobalKey(),
  );
  int current = 0;
  LessonLink? hovered;
  @override
  void initState() {
    super.initState();
    controller.addListener(updateSection);
  }

  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

  void updateSection() {
    final box = viewport.currentContext?.findRenderObject() as RenderBox?;
    if (box == null) return;
    final origin = box.localToGlobal(Offset.zero).dy;
    var next = 0;
    for (var i = 0; i < sectionKeys.length; i++) {
      final section =
          sectionKeys[i].currentContext?.findRenderObject() as RenderBox?;
      if (section != null &&
          section.localToGlobal(Offset.zero).dy <=
              origin + box.size.height * .4) {
        next = i;
      }
    }
    if (next != current) {
      setState(() => current = next);
      widget.onSection(next);
    }
    if (hovered != null) {
      hovered = null;
      widget.onHover(null);
    }
  }

  void go(int index) => Scrollable.ensureVisible(
    sectionKeys[index].currentContext!,
    duration: MediaQuery.disableAnimationsOf(context)
        ? Duration.zero
        : const Duration(milliseconds: 180),
    curve: Curves.easeInOut,
  );

  Widget paragraph(LessonParagraph paragraph) => Text.rich(
    TextSpan(
      children: [
        for (final span in paragraph.spans)
          switch (span) {
            LessonText() => TextSpan(
              text: span.text,
              style: span.bold
                  ? const TextStyle(fontWeight: FontWeight.bold)
                  : null,
            ),
            LessonLink() => WidgetSpan(
              alignment: PlaceholderAlignment.baseline,
              baseline: TextBaseline.alphabetic,
              child: MouseRegion(
                cursor: SystemMouseCursors.help,
                onEnter: (_) {
                  hovered = span;
                  widget.onHover(span);
                },
                onExit: (_) {
                  if (identical(hovered, span)) {
                    hovered = null;
                    widget.onHover(null);
                  }
                },
                child: Focus(
                  onFocusChange: (focused) {
                    if (focused) {
                      hovered = span;
                      widget.onHover(span);
                    } else if (identical(hovered, span)) {
                      hovered = null;
                      widget.onHover(null);
                    }
                  },
                  child: Text(
                    span.text,
                    style: const TextStyle(
                      fontSize: 18,
                      height: 1.5,
                      fontWeight: FontWeight.w700,
                      color: Color(0xFF1D4ED8),
                      decoration: TextDecoration.underline,
                      decorationColor: Color(0xFF93B4F4),
                    ),
                  ),
                ),
              ).maybeTooltip(span.help),
            ),
          },
      ],
    ),
    style: const TextStyle(fontSize: 18, height: 1.5, color: Color(0xFF25324A)),
  );

  Widget block(LessonBlock block) => switch (block) {
    LessonActivity() => FilledButton.icon(
      onPressed: () async {
        widget.onHover(null);
        if (widget.onActivity case final action?) {
          action(block);
          return;
        }
        try {
          await bridge.invokeMethod<void>('webPage', block.toWebPageRequest());
        } catch (_) {
          if (!mounted) return;
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text(
                'Die Webseite konnte nicht geöffnet werden. Bitte starte SchulUI vollständig neu.',
              ),
            ),
          );
        }
      },
      icon: const Icon(Icons.open_in_new),
      label: Text(block.label),
    ),
    LessonParagraph() => paragraph(block),
    LessonBulletList() => Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final item in block.items)
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('•  ', style: TextStyle(fontSize: 18, height: 1.5)),
                Expanded(child: paragraph(item)),
              ],
            ),
          ),
      ],
    ),
  };
  @override
  Widget build(BuildContext context) => Column(
    children: [
      Expanded(
        child: LayoutBuilder(
          builder: (context, constraints) => Scrollbar(
            controller: controller,
            thumbVisibility: true,
            child: SingleChildScrollView(
              key: viewport,
              controller: controller,
              child: Column(
                children: [
                  for (var i = 0; i < widget.lessons.length; i++)
                    Container(
                      key: sectionKeys[i],
                      decoration: const BoxDecoration(
                        border: Border(
                          bottom: BorderSide(color: Color(0xFFDCE4F2)),
                        ),
                      ),
                      padding: const EdgeInsets.fromLTRB(24, 24, 28, 24),
                      child: ConstrainedBox(
                        constraints: BoxConstraints(
                          minHeight: (constraints.maxHeight - 48).clamp(
                            0,
                            double.infinity,
                          ),
                        ),
                        child: IntrinsicHeight(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              Text(
                                widget.lessons[i].title,
                                style: Theme.of(context).textTheme.headlineSmall
                                    ?.copyWith(fontWeight: FontWeight.w800),
                              ),
                              const SizedBox(height: 24),
                              Expanded(
                                child: Center(
                                  child: Column(
                                    mainAxisSize: MainAxisSize.min,
                                    crossAxisAlignment:
                                        CrossAxisAlignment.stretch,
                                    children: [
                                      for (final item
                                          in widget.lessons[i].content)
                                        Padding(
                                          padding: const EdgeInsets.only(
                                            bottom: 16,
                                          ),
                                          child: block(item),
                                        ),
                                    ],
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
        child: Row(
          children: [
            if (widget.onHint != null)
              IconButton(
                onPressed: widget.onHint,
                tooltip: 'Tipp anzeigen',
                icon: const Icon(Icons.lightbulb_outline),
              ),
            IconButton(
              onPressed: current > 0 ? () => go(current - 1) : null,
              icon: const Icon(Icons.arrow_upward),
              tooltip: 'Vorheriger Abschnitt',
            ),
            Expanded(
              child: Text(
                'Abschnitt ${current + 1} von ${widget.lessons.length}',
                textAlign: TextAlign.center,
              ),
            ),
            IconButton(
              onPressed: current < widget.lessons.length - 1
                  ? () => go(current + 1)
                  : null,
              icon: const Icon(Icons.arrow_downward),
              tooltip: 'Nächster Abschnitt',
            ),
          ],
        ),
      ),
    ],
  );
}

extension on Widget {
  Widget maybeTooltip(String? hint) {
    if (hint == null) {
      return this;
    } else {
      return Tooltip(message: hint, child: this);
    }
  }
}
