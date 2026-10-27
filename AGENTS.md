# schului

Build a Windows authoring tool for teachers to create units for arbitrary Windows
software, with an interactive learner runtime: side-by-side real application,
exact UIA paths, hover highlights, contextual help and inspector. All target
applications use the same configuration and path rules.

## Shared specifications

Read `//wsl.localhost/Ubuntu/home/maximilian/dev/engineering_guidelines/ENGINEERING.md`
and `profiles/flutter-dart.md` before implementation. Read
`//wsl.localhost/Ubuntu/home/maximilian/dev/schulzeug_design/DESIGN.md` and its
relevant SVG examples before visual changes. If unavailable, report this.
Create coherent local Conventional Commits after checks. Never push automatically.

Use FVM for all Flutter/Dart commands. User-facing text is German; identifiers
and developer documentation are English. Keep learning content separate from
the Windows adapter. Use exact, full raw UIA paths for all applications. Never
select an arbitrary first window when multiple windows match the configured software.
