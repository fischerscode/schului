# schului

Create interactive teaching units for Windows software. Teachers compose steps,
contextual help and hover targets; learners work in the real target application
beside the instruction panel. The interface is German, built with Flutter/Dart,
Win32 and Windows UI Automation (UIA).

## Teacher workflow

Start `build/windows/x64/runner/Release/schului.exe`. A new unit has no software
selected. Use **Zielsoftware** (gear or the name in the footer):

1. Select a running application's window, or browse to its executable.
2. Set a readable name. Under **Start und Fenster**, optionally enter arguments
   (one argument per line), a window class and a title substring.
3. Add and edit learning steps, paragraphs, lists, online activities and hints.
4. To link a term, click its text, enable **Interaktiver Begriff**, choose
   **Ziel in Anwendung auswählen**, point at the target and press F8. Esc cancels.
5. Save a `.schului` file and test it with the play button.

The picker previews a blue click-through outline. F8 captures the position at
that key press and inserts the path after confirming unique identity. It does
not click the application. The selected software must already be open to capture
its targets. The inspector and manual JSON entry remain available.

Switching to different software asks before removing old target links; text and
hints survive. Changing configuration for the same executable keeps the links.
New/open/close handle unsaved changes. Ctrl+N/O/S provide standard file shortcuts.
The eye previews instructions. Each play/inspector launch uses an immutable
snapshot, so later edits affect the next session.

Draw is an optional example under **Vorlagen**, with a separate compatibility
adapter for its isolated profile and historical selectors. It is not required
for a generic unit. Draw-specific target presets appear only in that mode.

## Learner runtime

```powershell
.\schului.exe --lesson-file .\my-unit.schului
```

The runtime reuses a uniquely matching open window or starts the configured
executable with separately quoted arguments, without a command shell. Matching
uses the full executable path and optional class/title filters, not a global
window-title guess. If multiple windows match, use **Fenster auswählen**; the
runtime does not arbitrarily choose the first. Minimize/restore and the 25/75
instruction/application split retain the original Draw runtime behavior.
Closing the session restores window geometry and leaves the target app open.

Program locations can differ across computers: update the unit's executable
path in the editor on the destination machine. Applications requiring a launcher,
Store activation or special startup can be opened manually first; select the
actual application window when authoring. The runtime launches ordinary executable
files directly and does not install target software.

## Portable package

Run `tools/package-windows.ps1` to build a ZIP. `-SkipBuild` packages an existing
release. Keep the whole extracted folder, including DLLs and `data`; the EXE alone
is insufficient. `schului.exe` opens the general editor. The included
`start-beispiel.cmd` and `start-inspector.cmd` demonstrate the optional Draw adapter.
Embedded HTTPS activities require internet access and Edge WebView2.

## Development and verification

```powershell
fvm use
fvm flutter pub get
fvm dart run melos run format
fvm dart run melos run analyze
fvm dart run melos run test
fvm flutter build windows --release
fvm flutter run -d windows
.\tools\package-windows.ps1
```

Visual Studio's Desktop development with C++ workload is needed for native builds.
Flutter is pinned in `.fvmrc`; application dependencies are locked. Melos provides
repeatable checks and private-package versioning without an aggregate changelog.

Flutter analysis, 48 tests, the Melos format check and the Windows release build
pass. Tests cover software selection, settings retention during edits, file
migration, generic exact paths, Draw regressions, picker insertion/cancellation,
invalid input, narrow layouts and doubled text. Rendered views are inspected at
`build/visual-review/teacher.png` and `target-picker.png`.

Two native regression tests cover exact capture, duplicate/unnamed elements,
software/window matching, significant path spaces and Windows argument quoting:

```powershell
$nativeCmake = (Select-String -Path build/windows/x64/CMakeCache.txt -Pattern '^CMAKE_COMMAND:INTERNAL=').Line.Split('=', 2)[1]
& $nativeCmake --build build/windows/x64 --config Release --target captured_path_test application_config_test
.\build\windows\x64\tests\Release\captured_path_test.exe
.\build\windows\x64\tests\Release\application_config_test.exe
```

Live desktop acceptance is still pending: Computer Use previously failed with
`GetCursorPos: access denied`. Compilation and rendered widgets do not verify
native click-through, screen geometry, native dialogs or compatibility with every
application. Test the teacher-to-learner flow on actual school PCs, including
100/125/150% DPI, F8/Esc, multiple windows and unsaved work.

## Application compatibility

Units can target arbitrary Windows applications; individual hover marks require
usable UIA elements. Custom canvases, games, remote desktops and inaccessible
controls may expose no unique element at the desired granularity. Keep instructions
and hints usable when a target cannot be identified; no coordinates or image-based
guessing are substituted. The picker reports missing/ambiguous paths.

The runtime currently attaches a top-level main window. Separate owned popup
windows and dialog-only workflows are not captured. UI language, version or
control-name changes may require recapturing targets. Elevated/protected apps can
prevent accessibility access. The original session layout primarily targets a
single monitor. There is no installer, file association, progress tracking or
automatic assessment yet.

## Data and architecture

`.schului` is UTF-8 JSON (`schului.lesson`), maximum 4 MB. New writes use **version
2** with a typed application configuration: unconfigured draft, generic Windows
software or the Draw compatibility adapter. Version 1 Draw files remain readable
and migrate on save; older schului releases cannot read new version 2 files.
Executable arguments are a list, never an embedded shell command. Window handles,
process IDs and screen coordinates are not persisted.

Generic selectors store `mode: exact`, the full raw ancestor chain, element names,
types and unnamed-sibling indices. Only the root's mutable caption is omitted.
They do not use Draw's title-wrapper removal, document-name removal, client-layout
variants or loose fallback. Historic Draw selectors retain their explicit
compatibility behavior. `ApplicationTarget` is the general domain type;
`DrawTarget` remains a compatibility alias for existing lesson code.

- `lib/authoring`: editor, software settings, versioned codec, file dialogs and
  immutable snapshot launch.
- `lib/lessons`: typed content, shared renderer, general targets and Draw example.
- `lib/src`: selectors, inspector, embedded activity and Schulzeug theme.
- `windows/runner/application_config.h`: executable/window identity and argument
  quoting shared by runtime and picker.
- `windows/runner/target_picker.*`: temporary hotkeys, outline and separate MTA UIA
  worker. Capture is resolved again to verify identity before insertion.
- `windows/runner/desktop_session.*`: application connection, window layout and
  diagnostics, with the legacy Draw startup branch kept separately.

COM objects stay on their worker. Traversal and supported UIA timeouts bound work;
foreign providers cannot be assumed to obey a guaranteed total timeout. Relevant
Microsoft documentation: [ElementFromPoint](https://learn.microsoft.com/en-us/windows/win32/api/uiautomationclient/nf-uiautomationclient-iuiautomation-elementfrompoint),
[UIA threading](https://github.com/MicrosoftDocs/win32/blob/docs/desktop-src/WinAuto/uiauto-threading.md),
[layered windows](https://learn.microsoft.com/en-us/windows/win32/winmsg/window-features).

Files are written to a sibling staging file before replacement. Unsupported
versions and malformed content are rejected. Inspectable JSON fits this initial
interchange workflow; FlatBuffers and Drift are not introduced without a binary
or relational persistence requirement.

## Sources and conventions

- Runtime derived from `../schului-draw`, revision
  `212d4ae891f8d3f9ace1fe6098c3d03cd2a6d711`; MIT license retained.
- Engineering: `//wsl.localhost/Ubuntu/home/maximilian/dev/engineering_guidelines`,
  revision `e22679bdc13a68368e0be41df443d27530fb5bb3`.
- Design: `//wsl.localhost/Ubuntu/home/maximilian/dev/schulzeug_design`, revision
  `5e18fe67b88f17661d84ba5286aa0033ea6152d1`.

These source repositories remain independent and unchanged. See AGENTS.md for
the canonical specifications and package CHANGELOG.md for format compatibility.
