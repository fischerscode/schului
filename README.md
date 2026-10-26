# schului

A Windows tool for teachers to create interactive learning environments.
German interface, Flutter/Dart, native Win32 and UI Automation integration.

## Product direction

Teachers compose learning steps and contextual help. Learners work in a real
application alongside an instruction panel. Hovering linked terms highlights
the corresponding application controls using semantic accessibility paths.
LibreOffice Draw is the first supported application adapter.

## Development

```powershell
fvm use
fvm flutter pub get
fvm dart format lib test
fvm flutter analyze
fvm flutter test
fvm flutter build windows --release
fvm flutter run -d windows
```

Install Visual Studio's Desktop development with C++ workload and LibreOffice
for native builds and Draw sessions. WebView2 is needed for embedded activities.

## Sources and conventions

- Runtime derived from `../schului-draw`, revision
  `212d4ae891f8d3f9ace1fe6098c3d03cd2a6d711`; MIT license retained.
- Engineering: `//wsl.localhost/Ubuntu/home/maximilian/dev/engineering_guidelines`,
  revision `e22679bdc13a68368e0be41df443d27530fb5bb3`.
- Design: `//wsl.localhost/Ubuntu/home/maximilian/dev/schulzeug_design`, revision
  `5e18fe67b88f17661d84ba5286aa0033ea6152d1`.

The source repositories remain independent and unchanged. See AGENTS.md for
the canonical specifications. Flutter is pinned in `.fvmrc`.
