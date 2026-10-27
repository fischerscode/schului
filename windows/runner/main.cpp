#include "desktop_session.h"
#include "flutter_window.h"
#include "utils.h"
#include <algorithm>
#include <flutter/dart_project.h>
#include <windows.h>
int APIENTRY wWinMain(_In_ HINSTANCE instance, _In_opt_ HINSTANCE previous,
                      _In_ wchar_t *command_line, _In_ int show_command) {
  (void)instance;
  (void)previous;
  (void)command_line;
  (void)show_command;
  if (!AttachConsole(ATTACH_PARENT_PROCESS) && IsDebuggerPresent())
    CreateAndAttachConsole();
  CoInitializeEx(nullptr, COINIT_APARTMENTTHREADED);
  auto args = GetCommandLineArguments();
  bool inspector =
      std::find(args.begin(), args.end(), "--inspector") != args.end();
  auto lesson_file = std::find(args.begin(), args.end(), "--lesson-file");
  const bool learner = inspector || lesson_file != args.end();
  flutter::DartProject project(L"data");
  auto arguments = [&](const std::string &role) {
    std::vector<std::string> values{role};
    if (lesson_file != args.end()) {
      values.push_back("--lesson-file");
      values.push_back(std::next(lesson_file) != args.end() ? *std::next(lesson_file) : "");
    }
    return values;
  };
  if (!learner) {
    project.set_dart_entrypoint_arguments({"teacher"});
    FlutterWindow editor(project, "teacher");
    if (!editor.Create(L"schului – Lernumgebung erstellen", {40, 40}, {1200, 820}))
      return EXIT_FAILURE;
    editor.SetQuitOnClose(true);
    MSG message{};
    while (GetMessage(&message, nullptr, 0, 0) > 0) {
      TranslateMessage(&message);
      DispatchMessage(&message);
    }
    editor.Destroy();
    CoUninitialize();
    return EXIT_SUCCESS;
  }
  project.set_dart_entrypoint_arguments(arguments(inspector ? "inspector" : "lesson"));
  flutter::DartProject overlay_project(L"data");
  overlay_project.set_dart_entrypoint_arguments(arguments("overlay"));
  flutter::DartProject hint_project(L"data");
  hint_project.set_dart_entrypoint_arguments(arguments("hint"));
  flutter::DartProject learning_app_project(L"data");
  learning_app_project.set_dart_entrypoint_arguments({"learningApp"});
  FlutterWindow lesson(project), overlay(overlay_project, "overlay"),
      hint(hint_project, "hint"), learning_app(learning_app_project, "learningApp");
  if (!lesson.Create(L"schului – Unterricht", {0, 0}, {400, 800}) ||
      !overlay.Create(L"SchulUI – Markierungen", {0, 0}, {800, 800}) ||
      !hint.Create(L"SchulUI – Hinweis", {0, 0}, {360, 210}) ||
      !learning_app.Create(L"LearningApps – Was hast du gelernt?", {0, 0}, {1100, 760}))
    return EXIT_FAILURE;
  lesson.SetQuitOnClose(true);
  MSG message{};
  while (GetMessage(&message, nullptr, 0, 0) > 0) {
    TranslateMessage(&message);
    DispatchMessage(&message);
  }
  Session().Restore();
  learning_app.Destroy();
  hint.Destroy();
  overlay.Destroy();
  lesson.Destroy();
  CoUninitialize();
  return EXIT_SUCCESS;
}
