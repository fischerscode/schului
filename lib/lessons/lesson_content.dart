import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

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
    this.title,
    this.notice,
    this.actions,
  });
  final ValueChanged<LessonLink?> onHover;
  final ValueChanged<int> onSection;
  final List<LessonStep> lessons;
  final ValueChanged<LessonActivity>? onActivity;
  final VoidCallback? onHint;
  final String? title;
  final Widget? notice, actions;
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
          section.localToGlobal(Offset.zero).dy <= origin + 16) {
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
                  onKeyEvent: (node, event) {
                    if (event is KeyDownEvent &&
                        (event.logicalKey == LogicalKeyboardKey.enter ||
                            event.logicalKey == LogicalKeyboardKey.space)) {
                      hovered = span;
                      widget.onHover(span);
                      return KeyEventResult.handled;
                    }
                    return KeyEventResult.ignored;
                  },
                  onFocusChange: (focused) {
                    if (focused) {
                      hovered = span;
                      widget.onHover(span);
                    } else if (identical(hovered, span)) {
                      hovered = null;
                      widget.onHover(null);
                    }
                  },
                  child: Builder(
                    builder: (context) {
                      final focus = Focus.of(context);
                      return Semantics(
                        button: true,
                        onTap: focus.requestFocus,
                        child: GestureDetector(
                          excludeFromSemantics: true,
                          onTap: focus.requestFocus,
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 2),
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(4),
                              border: Border.all(
                                width: 2,
                                color: focus.hasFocus
                                    ? Theme.of(context).colorScheme.primary
                                    : Colors.transparent,
                              ),
                            ),
                            child: Text(
                              span.text,
                              style: Theme.of(context).textTheme.bodyLarge
                                  ?.copyWith(
                                    fontWeight: FontWeight.w600,
                                    color: Theme.of(context)
                                        .colorScheme
                                        .primary,
                                    decoration: TextDecoration.underline,
                                    decorationColor: Theme.of(context)
                                        .colorScheme
                                        .primary,
                                  ),
                            ),
                          ),
                        ),
                      );
                    },
                  ),
                ),
              ).maybeTooltip(span.help),
            ),
          },
      ],
    ),
    style: Theme.of(context).textTheme.bodyLarge,
  );

  Widget block(LessonBlock block) => switch (block) {
    LessonActivity() => OutlinedButton.icon(
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
                Text('•  ', style: Theme.of(context).textTheme.bodyLarge),
                Expanded(child: paragraph(item)),
              ],
            ),
          ),
      ],
    ),
  };
  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Expanded(
        child: LayoutBuilder(
          builder: (context, constraints) => Scrollbar(
            controller: controller,
            child: SingleChildScrollView(
              key: viewport,
              controller: controller,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (widget.title case final title?) ...[
                    Padding(
                      padding: const EdgeInsets.fromLTRB(24, 20, 24, 16),
                      child: Semantics(
                        header: true,
                        child: Text(
                          title,
                          style: Theme.of(context).textTheme.titleLarge,
                        ),
                      ),
                    ),
                    const Divider(),
                  ],

                  for (var i = 0; i < widget.lessons.length; i++)
                    Container(
                      key: sectionKeys[i],
                      // Leave enough trailing room to align the final heading
                      // with the viewport when navigating to the last section.
                      constraints: i == widget.lessons.length - 1
                          ? BoxConstraints(minHeight: constraints.maxHeight)
                          : null,
                      decoration: BoxDecoration(
                        border: Border(
                          left: BorderSide(
                            width: 2,
                            color: i == current
                                ? Theme.of(context).colorScheme.primary
                                : Colors.transparent,
                          ),
                          bottom: BorderSide(
                            color: Theme.of(context).colorScheme.outlineVariant,
                          ),
                        ),
                      ),
                      padding: const EdgeInsets.fromLTRB(20, 20, 24, 16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Padding(
                                padding: const EdgeInsets.only(
                                  top: 2,
                                  right: 12,
                                ),
                                child: ExcludeSemantics(
                                  child: Text(
                                    '${i + 1}'.padLeft(2, '0'),
                                    style: Theme.of(context)
                                        .textTheme
                                        .labelMedium
                                        ?.copyWith(
                                          color: Theme.of(context)
                                              .colorScheme
                                              .onSurfaceVariant,
                                        ),
                                  ),
                                ),
                              ),
                              Expanded(
                                child: Semantics(
                                  header: true,
                                  child: Text(
                                    widget.lessons[i].title,
                                    style: Theme.of(context)
                                        .textTheme
                                        .titleMedium,
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 12),
                          for (final item in widget.lessons[i].content)
                            Padding(
                              padding: const EdgeInsets.only(bottom: 12),
                              child: block(item),
                            ),
                        ],
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
      if (widget.notice case final notice?)
        ConstrainedBox(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.sizeOf(context).height * .4,
          ),
          child: SingleChildScrollView(child: notice),
        ),
      Material(
        color: Theme.of(context).scaffoldBackgroundColor,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Divider(),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
              child: Row(
                children: [
                  IconButton(
                    onPressed: current > 0 ? () => go(current - 1) : null,
                    icon: const Icon(Icons.arrow_upward),
                    tooltip: 'Vorheriger Abschnitt',
                  ),
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Semantics(
                            label:
                                'Abschnitt ${current + 1} von ${widget.lessons.length}',
                            child: ExcludeSemantics(
                              child: Text(
                                '${current + 1} / ${widget.lessons.length}',
                                textAlign: TextAlign.center,
                                style: Theme.of(context).textTheme.labelLarge,
                              ),
                            ),
                          ),
                          const SizedBox(height: 6),
                          ExcludeSemantics(
                            child: LinearProgressIndicator(
                              value: (current + 1) / widget.lessons.length,
                              minHeight: 2,
                              borderRadius: BorderRadius.circular(2),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  IconButton.filled(
                    onPressed: current < widget.lessons.length - 1
                        ? () => go(current + 1)
                        : null,
                    icon: Icon(
                      Icons.arrow_downward,
                      color: current < widget.lessons.length - 1
                          ? Theme.of(context).colorScheme.onPrimary
                          : null,
                    ),
                    tooltip: 'Nächster Abschnitt',
                  ),
                  if (widget.onHint != null &&
                      widget.lessons[current].hint.trim().isNotEmpty)
                    IconButton(
                      onPressed: widget.onHint,
                      tooltip: 'Tipp anzeigen',
                      icon: const Icon(Icons.lightbulb_outline),
                    ),
                  ?widget.actions,
                ],
              ),
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
