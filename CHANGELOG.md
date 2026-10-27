# Changelog

## Unreleased

- Select arbitrary Windows target software from running windows or an executable.
  Store startup arguments and window filters in each unit, and capture generic
  UIA targets without Draw-specific path adaptations.
- Start with an unconfigured unit; retain Draw as an optional example and adapter.
- Write lesson format version 2 and continue reading version 1 Draw files.
  Older schului builds cannot read newly saved version 2 files.

- Select hover targets directly in an open Draw window; preview an outline,
  confirm with F8 and automatically insert a validated semantic path.
- Preserve existing targets on cancellation and report native picker errors.

## 0.1.0

- Preserve the Windows Draw learning runtime, hover targets, and inspector from
  schului-draw as the foundation for teacher-authored environments.
- Add a German teacher editor, portable versioned lesson files, learner preview,
  custom semantic targets, contextual hints and embedded HTTPS activities.
- Apply the shared Schulzeug theme and pin Flutter with FVM; expose Melos checks.
