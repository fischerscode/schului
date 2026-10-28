## 0.2.0+2

> Note: This release has breaking changes.

 - **REFACTOR**(learner): simplify inactive task headings.
 - **FIX**(learner): soften inactive task typography.
 - **FIX**(windows): expose the lesson as a primary application window.
 - **FEAT**(branding): add the SchulUI application icon.
 - **FEAT**(learner): focus and center the active task.
 - **FEAT**(learner): streamline lesson reading and navigation.
 - **FEAT**(about): add version, repository and offline legal information.
 - **FEAT**(web): support custom titles and instructions for arbitrary pages.
 - **FEAT**(authoring): export portable student lesson packages.
 - **FEAT**(learner): streamline session actions and provide a student launcher.
 - **FEAT**(authoring): capture Draw hover targets from the mouse pointer.
 - **FEAT**(authoring): create Windows lesson editor with Draw runtime.
 - **DOCS**: describe the software-independent teaching workflow.
 - **DOCS**(test): record successful native Notepad authoring workflow.
 - **DOCS**: explain software-independent authoring and format migration.
 - **BREAKING** **REFACTOR**(application): remove application-specific adapters.
 - **BREAKING** **FEAT**(application): support teaching units for arbitrary Windows software.

# Changelog

## Unreleased

- Replace the Flutter placeholder with an original SchulUI app icon, including
  Windows icon sizes from 16 through 256 px and an editable SVG source.
- Use smaller, regular-weight inactive task titles so active instructions
  remain visually dominant.
- Show only titles for inactive learner tasks; remove section numbers and the
  redundant active-task label.

- Focus the learner view on one active task with more padding and muted previews;
  switch explicitly by click, keyboard or navigation, centering fitting tasks
  while aligning long tasks at the top. Keep the session menu beside the title.
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
