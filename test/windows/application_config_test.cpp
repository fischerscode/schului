#include "../../windows/runner/application_config.h"
#include <shellapi.h>
#include <stdexcept>
#include <iostream>

void Require(bool condition, const char *message) { if (!condition) throw std::runtime_error(message); }
int main() {
  target_app::Config app;
  app.draw = false; app.executable = L"C:\\Tools\\Example App\\app.exe";
  target_app::Window window{nullptr, L"c:/tools/example app/app.EXE", L"Document 1 - Editor", L"EditorWindow"};
  Require(target_app::Matches(window, app), "Generic software must match by full executable path");
  app.window_class = L"EditorWindow"; app.title_contains = L"document";
  Require(target_app::Matches(window, app), "Class and title filter must match");
  app.title_contains = L"other";
  Require(!target_app::Matches(window, app), "Other documents must not be attached");
  app.title_contains.clear(); app.window_class = L"OtherWindow";
  Require(!target_app::Matches(window, app), "Window class must constrain selection");
  Require(!target_app::SameExecutable(L"C:\\A  B\\app.exe", L"C:\\A B\\app.exe"), "Path spaces must remain significant");
  const std::vector<std::wstring> args{L"program.exe", L"", L"two words", L"C:\\path with space\\", L"literal\"quote", L"trailing\\"};
  std::wstring command;
  for (const auto &arg : args) command += (command.empty() ? L"" : L" ") + target_app::Quote(arg);
  int count = 0;
  auto parsed = CommandLineToArgvW(command.c_str(), &count);
  Require(parsed && count == static_cast<int>(args.size()), "Argument count must survive Windows quoting");
  for (int i = 0; i < count; ++i) Require(args[i] == parsed[i], "Argument boundaries must survive quoting");
  LocalFree(parsed);
  std::cout << "Application configuration tests passed.\n";
}
