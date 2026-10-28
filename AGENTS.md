# schului

Build a Windows authoring tool for teachers to create units for arbitrary Windows
software, with an interactive learner runtime: side-by-side real application,
exact UIA paths, hover highlights, contextual help and inspector. All target
applications use the same configuration and path rules.

## Shared specifications

Read `ENGINEERING.md` and `profiles/flutter-dart.md` from the
`engineering_guidelines` repository before implementation. Read `DESIGN.md` and
relevant SVG examples from `schulzeug_design` before visual changes. Locate these
repositories among configured workspace folders or sibling checkouts; do not
assume a particular operating system, username or absolute checkout path. If they
are unavailable, report this and use this repository's documented conventions
and existing theme as the local baseline.
Create coherent local Conventional Commits after checks. Never push automatically.
Let Melos generate version sections in CHANGELOG.md. Do not duplicate routine
changes in a manual Unreleased section or add a file heading above the releases.

Use FVM for all Flutter/Dart commands. User-facing text is German; identifiers
and developer documentation are English. Keep learning content separate from
the Windows adapter. Use exact, full raw UIA paths for all applications. Never
select an arbitrary first window when multiple windows match the configured software.
