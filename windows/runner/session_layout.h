#ifndef RUNNER_SESSION_LAYOUT_H_
#define RUNNER_SESSION_LAYOUT_H_
#include <windows.h>
#include <algorithm>

namespace session_layout {
enum class Visibility { waiting, visible, minimized, closed };
inline Visibility VisibilityFor(bool connected_once, bool exists,
                                bool minimized) {
  if (!exists)
    return connected_once ? Visibility::closed : Visibility::waiting;
  return minimized ? Visibility::minimized : Visibility::visible;
}
inline Visibility ApplyVisibility(HWND target, HWND lesson, HWND overlay,
                                  HWND hint, bool connected_once,
                                  bool &hidden_for_target) {
  const auto visibility = VisibilityFor(connected_once, IsWindow(target) != FALSE,
                                        target && IsIconic(target));
  if (visibility == Visibility::closed || visibility == Visibility::minimized) {
    if (lesson)
      ShowWindow(lesson, SW_HIDE);
    if (overlay)
      ShowWindow(overlay, SW_HIDE);
    if (hint)
      ShowWindow(hint, SW_HIDE);
    hidden_for_target = visibility == Visibility::minimized;
  } else if (hidden_for_target && visibility == Visibility::visible) {
    hidden_for_target = false;
    if (lesson)
      ShowWindow(lesson, SW_SHOWNOACTIVATE);
  }
  return visibility;
}
struct Bounds {
  RECT lesson;
  RECT target;
};
inline RECT CenteredActivity(const RECT &area, double scale) {
  const LONG width = std::max<LONG>(1, std::min<LONG>(static_cast<LONG>(1100 * scale), area.right - area.left - static_cast<LONG>(48 * scale)));
  const LONG height = std::max<LONG>(1, std::min<LONG>(static_cast<LONG>(760 * scale), area.bottom - area.top - static_cast<LONG>(48 * scale)));
  const LONG left = area.left + (area.right - area.left - width) / 2;
  const LONG top = area.top + (area.bottom - area.top - height) / 2;
  return {left, top, left + width, top + height};
}
inline Bounds SplitWorkArea(const RECT &area) {
  const LONG split = area.left + (area.right - area.left) / 4;
  return {{area.left, area.top, split, area.bottom},
          {split, area.top, area.right, area.bottom}};
}
} // namespace session_layout
#endif
