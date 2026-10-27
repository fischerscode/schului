# schului

Build a Windows authoring tool for teachers to create units for arbitrary Windows
software, with an interactive learner runtime. Preserve schului-draw's
side-by-side real application, semantic UIA paths, hover highlights, contextual
help and inspector. Draw is an optional compatibility adapter and example, never
an implicit requirement for a new unit.

## Shared specifications

Read `//wsl.localhost/Ubuntu/home/maximilian/dev/engineering_guidelines/ENGINEERING.md`
and `profiles/flutter-dart.md` before implementation. Read
`//wsl.localhost/Ubuntu/home/maximilian/dev/schulzeug_design/DESIGN.md` and its
relevant SVG examples before visual changes. If unavailable, report this.
Create coherent local Conventional Commits after checks. Never push automatically.

Use FVM for all Flutter/Dart commands. User-facing text is German; identifiers
and developer documentation are English. Keep learning content separate from
the Windows adapter. Use exact, full paths for general applications; keep Draw's
historical path adaptations confined to its compatibility mode. Never select an
arbitrary first window when multiple windows match the configured software.
