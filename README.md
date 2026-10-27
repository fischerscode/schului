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

Use **Schülerpaket exportieren** (archive icon) to create a complete student
folder. Select its parent directory; schului creates a new folder named after
the unit with `unterricht.schului`, `start-lernen.bat`, the schului runtime and
its required DLLs/data. Repeated exports create numbered folders. The export
uses the current editor content, including unsaved edits, without changing the
original file or its save status. Canceling leaves the editor unchanged.

Distribute the whole exported folder and assign `start-lernen.bat` as the student
launch path. The target software itself is not included; its configured path
must exist on the student PCs. The export copies the running schului build,
so use a release build for distribution.

The picker previews a blue click-through outline. F8 captures the position at
that key press and inserts the path after confirming unique identity. It does
not click the application. The selected software must already be open to capture
its targets. The inspector and manual JSON entry remain available.

Switching to different software asks before removing old target links; text and
hints survive. Changing configuration for the same executable keeps the links.
New/open/close handle unsaved changes. Ctrl+N/O/S provide standard file shortcuts.
The eye previews instructions. Each play/inspector launch uses an immutable
snapshot, so later edits affect the next session.

## Learner runtime

```powershell
.\schului.exe --lesson-file .\my-unit.schului
```

This opens the student session directly, with no teacher editor or route to it
in the learner menu. Missing or invalid lesson files show an error instead of
opening the editor. Starting `schului.exe` without arguments opens the teacher
editor; assign the student launcher below in classroom management software.

Save the finished unit as `unterricht.schului` beside `schului.exe` and distribute
the complete application folder. Point the students' launch path at the included
`start-lernen.bat`; no arguments are needed. To select a different unit, pass its
path as the first argument to the batch file, or use `--lesson-file` directly:

```bat
@echo off
start "" "C:\Schule\schului\schului.exe" --lesson-file "C:\Unterricht\Text bearbeiten.schului"
```

Use quotes around paths containing spaces. Learner menus offer reconnect, exit
and application information. The teacher editor provides **Ziele erkunden** for
inspection and diagnostics.

The runtime reuses a uniquely matching open window or starts the configured
executable with separately quoted arguments, without a command shell. Matching
uses the full executable path and optional class/title filters, not a global
window-title guess. If multiple windows match, use **Fenster auswählen**; the
runtime does not arbitrarily choose the first. Instructions use 25% of the
work area and the target application uses 75%; minimizing the target hides the
lesson and restoring it brings the lesson back.
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
`start-inspector.cmd path-to-unit.schului` opens the inspector for that unit.
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

Automated checks cover software selection, settings retention during edits, file
round trips, exact paths, picker insertion/cancellation, invalid input, narrow
layouts and doubled text. Rendered views are inspected at
`build/visual-review/teacher.png`, `target-picker.png` and `application-settings.png`.

Two native regression tests cover exact capture, duplicate/unnamed elements,
software/window matching, significant path spaces and Windows argument quoting:

```powershell
$nativeCmake = (Select-String -Path build/windows/x64/CMakeCache.txt -Pattern '^CMAKE_COMMAND:INTERNAL=').Line.Split('=', 2)[1]
& $nativeCmake --build build/windows/x64 --config Release --target captured_path_test application_config_test
.\build\windows\x64\tests\Release\captured_path_test.exe
.\build\windows\x64\tests\Release\application_config_test.exe
```

Live Notepad authoring was exercised on 2026-10-27 with Windows Notepad
11.2607.14.0: create a unit, select the running Notepad window, capture its actual
File menu by mouse/F8, insert the exact UIA path, save through the native dialog,
restart the teacher editor and reopen the saved unit. These steps passed.
The picker visibly outlined the File menu without opening it. The saved file is
`build/notepad-e2e.schului` (machine-specific test data, excluded from Git).

The test exposed the learner window's tool-window style; it now uses a primary
app-window style and is discoverable while waiting for window selection. After
desktop access was restored, the remaining end-to-end steps also passed:

- The runtime reported two matching Notepad windows and offered explicit selection.
- Selecting the blank test window connected that exact window and displayed the
  instruction/application layout, without selecting the pre-existing user document.
- Hovering the authored "Datei" term produced a yellow outline around Notepad's
  actual File menu. Moving away removed the outline.

This completes the requested authoring/capture/save/reload/runtime-hover flow
with an already open Notepad window. Cold-starting the packaged Notepad executable,
other apps, other DPI settings and lifecycle cases are separate checks.
Computer Use temporarily lost desktop access (`GetCursorPos: access denied`),
requiring the user to activate the desktop before continuation. Normal key
presses worked in Flutter fields, while automated text injection/Ctrl+A did not;
native file-dialog text input did work. This is an automation observation, not a
verified diagnosis of physical-keyboard behavior.

Compilation and rendered widgets alone do not establish native click-through,
geometry or compatibility with every app. Repeat on school PCs, including
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

`.schului` is UTF-8 JSON (`schului.lesson`), maximum 4 MB. Files use **version
2** with a typed application configuration: unconfigured draft or Windows software.
Only version 2 files and version 2 exact selectors are supported. Older files
and application-specific configurations are rejected; create a new unit and
recapture its targets. Existing general-purpose version 2 units remain readable.
Executable arguments are a list, never an embedded shell command. Window handles,
process IDs and screen coordinates are not persisted.

Generic selectors store `mode: exact`, the full raw ancestor chain, element names,
types and unnamed-sibling indices. Only the root's mutable caption is omitted.
Paths must resolve uniquely; missing ancestors or duplicate targets produce no
highlight. `ApplicationTarget` is the shared domain type.

- `lib/authoring`: editor, software settings, versioned codec, file dialogs and
  immutable snapshot launch.
- `lib/lessons`: typed content, shared renderer, application-independent targets.
- `lib/src`: selectors, inspector, embedded activity and Schulzeug theme.
- `windows/runner/application_config.h`: executable/window identity and argument
  quoting shared by runtime and picker.
- `windows/runner/target_picker.*`: temporary hotkeys, outline and separate MTA UIA
  worker. Capture is resolved again to verify identity before insertion.
- `windows/runner/desktop_session.*`: application connection, window layout and
  diagnostics, using the configured executable and window filters.

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

- Engineering: `//wsl.localhost/Ubuntu/home/maximilian/dev/engineering_guidelines`,
  revision `e22679bdc13a68368e0be41df443d27530fb5bb3`.
- Design: `//wsl.localhost/Ubuntu/home/maximilian/dev/schulzeug_design`, revision
  `5e18fe67b88f17661d84ba5286aa0033ea6152d1`.

These source repositories remain independent and unchanged. See AGENTS.md for
the canonical specifications and package CHANGELOG.md for format compatibility.
