#ifndef RUNNER_TARGET_PICKER_H_
#define RUNNER_TARGET_PICKER_H_
#include <windows.h>
#include <flutter/method_channel.h>
#include <flutter/encodable_value.h>
#include <atomic>
#include <condition_variable>
#include <mutex>
#include <optional>
#include <thread>

class TargetPicker {
 public:
  static constexpr UINT kUpdate = WM_APP + 71;
  static constexpr int kConfirm = 71, kCancel = 72;
  TargetPicker(HWND owner, flutter::BinaryMessenger *messenger);
  ~TargetPicker();
  bool HandleMessage(UINT message, WPARAM wparam);
  void Cancel();

 private:
  struct Update {
    flutter::EncodableValue target;
    std::string label, error;
    RECT bounds{};
    POINT point{};
    bool confirmed = false;
    uint64_t generation = 0;
  };
  void Start(std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result);
  void ReadCursor();
  void Apply();
  void ShowBounds(const RECT &bounds);
  void Finish(const flutter::EncodableValue &value);
  HWND owner_, overlay_ = nullptr;
  flutter::MethodChannel<flutter::EncodableValue> channel_;
  std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result_;
  std::atomic<bool> stop_{true};
  std::atomic<uint64_t> generation_{0};
  std::mutex mutex_;
  std::condition_variable changed_;
  std::optional<POINT> confirmation_;
  std::optional<Update> update_;
  std::thread worker_;
};
#endif
