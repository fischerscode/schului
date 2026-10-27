#ifndef RUNNER_DESKTOP_SESSION_H_
#define RUNNER_DESKTOP_SESSION_H_
#include <atomic>
#include <filesystem>
#include <flutter/encodable_value.h>
#include <map>
#include <mutex>
#include <string>
#include <thread>
#include <vector>
#include <windows.h>
#include <condition_variable>
#include <cstdint>
#include "application_config.h"

struct AccessibleTarget {
  std::string name;
  RECT rect;
};
struct AccessibilityNode {
  std::string id, parent_id, name, type;
  RECT rect{};
  int depth = 0;
  bool offscreen = false;
};
class DesktopSession {
public:
  DesktopSession();
  ~DesktopSession();
  void Register(const std::string &role, HWND hwnd);
  void Tick();
  bool Start(std::string *error);
  bool ConfigureApplication(const flutter::EncodableValue &value);
  flutter::EncodableValue ApplicationWindows();
  bool SelectApplicationWindow(int64_t handle);
  void SetStep(int value);
  void SetHover(const flutter::EncodableValue &target);
  void SetHint(bool value);
  void SetLearningApp(const std::string &url);
  void SetInspector(bool enabled);
  bool SelectNode(const std::string &id);
  void Restore();
  bool Export(std::string *path);
  flutter::EncodableValue State(bool include_nodes = true);
  bool ExportConnection(std::string *path);

private:
  void Inspect();
  void InspectHoverBounds();
  HWND FindTargetWindow();
  target_app::Config application_;
  bool configured_ = false;
  HWND preferred_window_ = nullptr;
  HWND lesson_ = nullptr, overlay_ = nullptr, hint_ = nullptr, learning_app_ = nullptr;
  bool learning_app_visible_ = false;
  std::string learning_app_url_;
  std::atomic<HWND> target_{nullptr};
  DWORD launched_pid_ = 0;
  std::filesystem::path launched_executable_;
  unsigned long long launch_time_ = 0;
  std::string connection_method_, startup_error_;
  DWORD placement_error_ = 0;
  HRESULT accessibility_error_ = S_OK;
  std::string inspection_stage_ = "initializing";
  WINDOWPLACEMENT original_{sizeof(WINDOWPLACEMENT)};
  bool captured_ = false, hint_visible_ = false, active_ = false;
  int step_ = 0;
  flutter::EncodableValue hover_target_;
  flutter::EncodableValue hover_geometry_;
  std::atomic<uint64_t> hover_generation_{0};
  uint64_t hover_geometry_generation_ = 0;
  std::condition_variable hover_bounds_changed_;
  std::thread hover_bounds_reader_;
  bool inspector_mode_ = false;
  bool target_connected_once_ = false, lesson_hidden_for_target_ = false;
  std::string selected_node_id_;
  RECT monitor_{}, target_rect_{};
  std::atomic<bool> stop_{false};
  std::thread inspector_;
  std::mutex mutex_;
  std::vector<AccessibleTarget> targets_;
  std::string tree_snapshot_;
  std::vector<AccessibilityNode> nodes_;
  bool accessibility_ready_ = false;
};
DesktopSession &Session();
#endif
