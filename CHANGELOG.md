# Changelog

## Unreleased

- Redesign learner reading with compact numbered sections, a shared navigation
  and reading-position bar, contextual tips and direct connection recovery.
  Preserve continuous scrolling, exact hover targets and the application split.
- Show the actual app version/build, GitHub link and offline imprint/privacy
  information in the shared teacher and learner About dialog.
- Add GitHub Actions checks for formatting, analysis, Flutter/native tests and
  Windows builds; attach portable ZIPs and SHA-256 checksums to published releases.
- Show arbitrary HTTPS pages with teacher-authored button labels, window titles
  and optional instructions. Replace provider-specific URL window text with
  neutral loading/error messages; preserve existing URL blocks with defaults.
- Export student packages from the teacher editor, including the current lesson,
  relative BAT launcher, application runtime and license in a new portable folder.
- Remove inspector and diagnostic exports from the learner menu; retain authoring
  tools in the teacher editor. Include start-lernen.bat for direct lesson launch.
- Use one software-independent authoring and learner workflow for all Windows
  applications: select executable/window, capture exact UIA targets, save and run.
- Remove application-specific templates, path presets, launchers and fallback
  matching. Preserve full raw paths, document names and unnamed sibling indices.
- **Breaking:** remove the former Draw adapter and version 1 reader. Only version
  2 units with Windows/unconfigured application settings and version 2 exact
  selectors are supported. Recreate older units and capture their targets again.
  Existing general-purpose version 2 units remain readable.
- Keep learner/inspector windows available in the taskbar and window switcher.
- Preserve existing targets on picker cancellation and report native picker errors.

## 0.1.0

- Preserve the Windows Draw learning runtime, hover targets, and inspector from
  schului-draw as the foundation for teacher-authored environments.
- Add a German teacher editor, portable versioned lesson files, learner preview,
  custom semantic targets, contextual hints and embedded HTTPS activities.
- Apply the shared Schulzeug theme and pin Flutter with FVM; expose Melos checks.
