#include "../../windows/runner/session_layout.h"
#include <cassert>
#include <iostream>
int main() {
  using namespace session_layout;
  assert(VisibilityFor(false, false, false) == Visibility::waiting);
  assert(VisibilityFor(false, true, false) == Visibility::visible);
  assert(VisibilityFor(true, true, true) == Visibility::minimized);
  assert(VisibilityFor(true, true, false) == Visibility::visible);
  assert(VisibilityFor(true, false, false) == Visibility::closed);
  // Taskbar at bottom; negative origin on a secondary screen.
  auto bottom = SplitWorkArea({-1920, 0, 0, 1040});
  assert(bottom.lesson.left == -1920 && bottom.lesson.right == -1440);
  assert(bottom.target.left == -1440 && bottom.target.right == 0);
  assert(bottom.lesson.bottom == 1040 && bottom.target.bottom == 1040);
  // Taskbar left / top and changed work area are respected on the next tick.
  auto offset = SplitWorkArea({80, 40, 1920, 1080});
  assert(offset.lesson.left == 80 && offset.lesson.top == 40);
  assert(offset.lesson.right == 540 && offset.target.left == 540);
  assert(offset.target.top == 40 && offset.target.bottom == 1080);
  // The activity is centered over the entire work area, including other monitors.
  auto activity = CenteredActivity({-1920, 40, 0, 1080}, 1.0);
  assert(activity.left == -1510 && activity.top == 180);
  assert(activity.right == -410 && activity.bottom == 940);
  auto compact = CenteredActivity({80, 40, 880, 640}, 1.5);
  assert(compact.left == 116 && compact.top == 76);
  assert(compact.right == 844 && compact.bottom == 604);
  // Real Win32 windows owned by this test, positioned outside the desktop.
  auto create = []() {
    HWND window = CreateWindowExW(
        WS_EX_TOOLWINDOW | WS_EX_NOACTIVATE, L"BUTTON",
        L"SchulUI lifecycle test", WS_OVERLAPPEDWINDOW, -30000, -30000, 100,
        100, nullptr, nullptr, GetModuleHandleW(nullptr), nullptr);
    assert(window);
    ShowWindow(window, SW_SHOWNOACTIVATE);
    return window;
  };
  HWND target = create(), lesson = create(), overlay = create(), hint = create();
  bool hidden = false;
  assert(ApplyVisibility(nullptr, lesson, overlay, hint, false, hidden) ==
         Visibility::waiting);
  assert(IsWindowVisible(lesson));
  ShowWindow(target, SW_SHOWMINNOACTIVE);
  assert(ApplyVisibility(target, lesson, overlay, hint, true, hidden) ==
         Visibility::minimized);
  assert(IsIconic(target)); // The application must not restore minimized target software.
  assert(!IsWindowVisible(lesson) && !IsWindowVisible(overlay) &&
         !IsWindowVisible(hint));
  assert(ApplyVisibility(target, lesson, overlay, hint, true, hidden) ==
         Visibility::minimized);
  ShowWindow(target, SW_RESTORE);
  assert(ApplyVisibility(target, lesson, overlay, hint, true, hidden) ==
         Visibility::visible);
  assert(IsWindowVisible(lesson));
  assert(!IsWindowVisible(overlay) &&
         !IsWindowVisible(
             hint)); // Normal Tick decides whether decorations are active.
  EnableWindow(target, FALSE); // A modal dialog leaves the main window alive.
  assert(ApplyVisibility(target, lesson, overlay, hint, true, hidden) ==
         Visibility::visible);
  EnableWindow(target, TRUE);
  DestroyWindow(target);
  assert(ApplyVisibility(target, lesson, overlay, hint, true, hidden) ==
         Visibility::closed);
  assert(!IsWindowVisible(lesson) && !IsWindowVisible(overlay) &&
         !IsWindowVisible(hint));
  DestroyWindow(lesson);
  DestroyWindow(overlay);
  DestroyWindow(hint);
  std::cout << "Session visibility and work-area layout checks passed.\n";
}
