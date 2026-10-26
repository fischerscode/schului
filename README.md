# schului

A Windows tool for teachers to create interactive learning environments.
German interface, Flutter/Dart, native Win32 and UI Automation integration.

## Product direction

Teachers compose learning steps and contextual help. Learners work in a real
application alongside an instruction panel. Hovering linked terms highlights
the corresponding application controls using semantic accessibility paths.
LibreOffice Draw is the first supported application adapter.

## Use

Start `build/windows/x64/runner/Release/schului.exe` to open the teacher editor.
It starts with an editable Draw lesson. Add, duplicate, reorder or delete steps;
click a text run to edit it or make it an interactive term. A linked term accepts
a preset or a JSON path copied from the Draw inspector. Paragraphs, bullet lists,
online activities and per-step hints are supported.

Use the eye to preview the instructions, the tree to discover Draw targets,
and play to launch the current lesson in Draw. The editor stays open. Each launch
uses a separate immutable snapshot; later edits apply to the next launch.
Save/open `.schului` files with the folder/save buttons or Ctrl+O/Ctrl+S.
New, open and window close ask about unsaved changes.

For learners, distribute the complete portable folder and a `.schului` file:

```powershell
.\schului.exe --lesson-file .\examples\erste-zeichnung.schului
```

Copying the EXE alone is insufficient: the adjacent DLLs and `data` directory
are required. `tools/package-windows.ps1` creates a portable ZIP with a sample
lesson and launch shortcuts. It does not install LibreOffice or publish anything.

## Development

```powershell
fvm use
fvm flutter pub get
fvm dart format lib test
fvm flutter analyze
fvm flutter test
fvm flutter build windows --release
fvm flutter run -d windows
fvm dart run melos run analyze
fvm dart run melos run test
.\tools\package-windows.ps1
```

Install Visual Studio's Desktop development with C++ workload and LibreOffice
for native builds and Draw sessions. WebView2 is needed for embedded activities.

## Architecture and format

- `lib/authoring`: teacher workspace, strict lesson codec, file dialogs and
  snapshot launch. Native window close is routed through unsaved-change handling.
- `lib/lessons`: typed content blocks and spans, shared instruction renderer,
  Draw example and verified exact target paths.
- `lib/src`: UIA selectors, inspector, embedded activity and Schulzeug theme.
- `windows/runner`: inherited application process detection, layout,
  click-through overlays and background UIA queries. Teacher mode uses a normal
  window and does not start Draw. Learner mode retains the 25/75 split.

`.schului` is UTF-8 JSON, format `schului.lesson`, version 1, application
`libreoffice.draw`; maximum file size 4 MB. Unknown versions, unknown content
types, malformed paths and non-HTTPS activities are rejected. It contains text,
hints and semantic paths, never persisted runtime IDs or screen coordinates.
Save writes a sibling staging file before replacing the destination. Future
format changes require explicit version handling and fixture tests.

FlatBuffers was considered for binary interchange. This first document format
uses inspectable text so teachers can exchange and diagnose selector data without
binary tooling. There is no relational query or migration need for Drift yet.
Neither generator nor database is introduced without a concrete use case.

## Verification and current limits

Flutter analysis, all 39 automated tests and a Windows release build pass. Tests
cover rich-content round trips, replacing files, invalid files, exact selector
resolution, editor operations, narrow layouts and doubled text size. The rendered
teacher workspace is inspected at `build/visual-review/teacher.png`.
Melos package discovery and its format script are also verified.

Native manual acceptance of this new teacher-to-Draw flow is still pending:
Computer Use launch approval timed out. The build does not establish working
transparency, click-through, native save dialogs or target geometry on a learner
machine. Test those with installed LibreOffice, and at 100/125/150% Windows DPI.
The inherited adapter primarily targets a single monitor and German LibreOffice
UIA names; other application adapters and arbitrary UI languages are not supported.
No installer, file association, progress tracking or automatic task assessment is
included. Embedded online activities require internet access and WebView2.

Some inherited lesson paths disagreed with the checked-in Inspector exports.
The new project restores the full sidebar/size/fill paths from those fixtures and
updates obsolete label assertions without weakening exact matching. The source
repository is unchanged; unrecognized LibreOffice layouts need fresh paths from
the inspector rather than a loose name fallback.

## Sources and conventions

- Runtime derived from `../schului-draw`, revision
  `212d4ae891f8d3f9ace1fe6098c3d03cd2a6d711`; MIT license retained.
- Engineering: `//wsl.localhost/Ubuntu/home/maximilian/dev/engineering_guidelines`,
  revision `e22679bdc13a68368e0be41df443d27530fb5bb3`.
- Design: `//wsl.localhost/Ubuntu/home/maximilian/dev/schulzeug_design`, revision
  `5e18fe67b88f17661d84ba5286aa0033ea6152d1`.

The source repositories remain independent and unchanged. See AGENTS.md for
the canonical specifications. Flutter is pinned in `.fvmrc`.
