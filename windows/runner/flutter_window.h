#ifndef RUNNER_FLUTTER_WINDOW_H_
#define RUNNER_FLUTTER_WINDOW_H_
#include "win32_window.h"
#include <flutter/dart_project.h>
#include <flutter/encodable_value.h>
#include <flutter/flutter_view_controller.h>
#include <flutter/method_channel.h>
#include <memory>
#include <string>
class FlutterWindow : public Win32Window {
public:
  explicit FlutterWindow(const flutter::DartProject &project,
                         std::string role = "lesson");
  virtual ~FlutterWindow();

protected:
  bool OnCreate() override;
  void OnDestroy() override;
  LRESULT MessageHandler(HWND window, UINT message, WPARAM wparam,
                         LPARAM lparam) noexcept override;

private:
  flutter::DartProject project_;
  std::string role_;
  std::unique_ptr<flutter::FlutterViewController> flutter_controller_;
  std::unique_ptr<flutter::MethodChannel<flutter::EncodableValue>> channel_;
};
#endif
