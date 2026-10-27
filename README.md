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
click a text run to edit it or make it an interactive term. Choose **Ziel in Draw
auswählen**, point at an element in an already open Draw window and press F8.
The editor inserts the captured path automatically; Esc cancels without changing
the previous path. A blue, click-through outline previews a uniquely resolved
element. F8 captures the position at the key press, rather than the last preview.
This does not click or activate the target. Presets and JSON paths from the
inspector remain available. Paragraphs, bullet lists,
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
- `windows/runner/target_picker.*`: temporary F8/Esc hotkeys, a separate MTA UIA
  worker and a non-activating outline. Only visible main windows belonging to
  `soffice.bin` and titled LibreOffice Draw are accepted. The raw ancestor chain
  is captured with title-wrapper and unnamed-sibling rules matching the runtime,
  then resolved again to verify that it uniquely identifies the hit element.
  COM objects remain on that worker; only content/geometry crosses to the UI.
  Queries use bounded traversal and UIA timeouts where supported. Provider calls
  cannot be assumed to obey a guaranteed total timeout.

The picker uses Microsoft's [ElementFromPoint API](https://learn.microsoft.com/en-us/windows/win32/api/uiautomationclient/nf-uiautomationclient-iuiautomation-elementfrompoint),
[UIA threading guidance](https://github.com/MicrosoftDocs/win32/blob/docs/desktop-src/WinAuto/uiauto-threading.md),
and [layered window behavior](https://learn.microsoft.com/en-us/windows/win32/winmsg/window-features).

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

Flutter analysis, the 43 automated tests and a Windows release build pass. Tests
cover rich-content round trips, replacing files, invalid files, exact selector
resolution, editor operations, narrow layouts and doubled text size. The rendered
teacher workspace is inspected at `build/visual-review/teacher.png`.
Melos package discovery and its format script are also verified. The new dialog
is rendered at `build/visual-review/target-picker.png`. Picker tests cover
insertion, cancellation, malformed native paths and visible platform errors.

The pure native capture regression test also passes (duplicate names, unnamed
sibling indices, title changes, unreadable siblings, cancellation, and both client
wrapper layouts). After configuring a Flutter Windows build, run it with:

```powershell
$nativeCmake = (Select-String -Path build/windows/x64/CMakeCache.txt -Pattern '^CMAKE_COMMAND:INTERNAL=').Line.Split('=', 2)[1]
& $nativeCmake --build build/windows/x64 --config Release --target captured_path_test
.\build\windows\x64\tests\Release\captured_path_test.exe
```

Native manual acceptance of this new teacher-to-Draw flow is still pending:
The first Computer Use launch approval timed out; the subsequent picker check
failed with `GetCursorPos: access denied`. The build does not establish working
transparency, click-through, native save dialogs or target geometry on a learner
machine. Test those with installed LibreOffice, and at 100/125/150% Windows DPI.
The inherited adapter primarily targets a single monitor and German LibreOffice
UIA names; other application adapters and arbitrary UI languages are not supported.
The new picker requires an unlocked interactive desktop and already open Draw.
Popup menus/dialogs outside the main Draw window are not accepted. In live
acceptance, verify F8, Esc, repeated selection, an ambiguous target, window close,
and preservation of unsaved lesson changes. An already occupied hotkey produces
a visible error instead of starting a picker that cannot be confirmed/cancelled.
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
