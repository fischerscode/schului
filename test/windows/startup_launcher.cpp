// Regression launcher: exit before the real office window exists.
// Set SCHULUI_TEST_OFFICE to an installed soffice.exe before running.
#include <string>
#include <windows.h>
int WINAPI wWinMain(HINSTANCE, HINSTANCE, PWSTR args, int) {
  wchar_t executable[32768]{};
  if (!GetEnvironmentVariableW(L"SCHULUI_TEST_OFFICE", executable, 32768))
    return 2;
  std::wstring command = L"\"" + std::wstring(executable) + L"\" " + args;
  STARTUPINFOW startup{};
  startup.cb = sizeof(startup);
  PROCESS_INFORMATION process{};
  if (!CreateProcessW(executable, command.data(), nullptr, nullptr, FALSE, 0,
                      nullptr, nullptr, &startup, &process))
    return 3;
  CloseHandle(process.hThread);
  CloseHandle(process.hProcess);
  return 0;
}
