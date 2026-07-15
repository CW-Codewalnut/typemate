#include "flutter_window.h"

#include <flutter/method_channel.h>
#include <flutter/standard_method_codec.h>
#include <optional>
#include <string>
#include <vector>

#include "flutter/generated_plugin_registrant.h"

namespace {

// Types text into the focused field of whichever window has keyboard focus,
// using SendInput unicode events. Unlike clipboard-paste insertion, this
// leaves the user's clipboard untouched and works for any script whisper can
// produce (Latin, Devanagari, CJK, ...).
bool InsertTextIntoFocusedField(const std::string& utf8_text) {
  if (utf8_text.empty()) {
    return true;
  }

  int wide_length = ::MultiByteToWideChar(
      CP_UTF8, 0, utf8_text.data(), static_cast<int>(utf8_text.size()),
      nullptr, 0);
  if (wide_length <= 0) {
    return false;
  }
  std::wstring wide_text(wide_length, L'\0');
  ::MultiByteToWideChar(CP_UTF8, 0, utf8_text.data(),
                        static_cast<int>(utf8_text.size()), wide_text.data(),
                        wide_length);

  std::vector<INPUT> inputs;
  inputs.reserve(wide_text.size() * 2);
  for (wchar_t unit : wide_text) {
    // Edit controls expect carriage return for line breaks.
    if (unit == L'\n') {
      unit = L'\r';
    }
    INPUT key_down = {};
    key_down.type = INPUT_KEYBOARD;
    key_down.ki.wScan = unit;
    key_down.ki.dwFlags = KEYEVENTF_UNICODE;
    INPUT key_up = key_down;
    key_up.ki.dwFlags |= KEYEVENTF_KEYUP;
    inputs.push_back(key_down);
    inputs.push_back(key_up);
  }

  UINT sent = ::SendInput(static_cast<UINT>(inputs.size()), inputs.data(),
                          sizeof(INPUT));
  return sent == inputs.size();
}

}  // namespace

FlutterWindow::FlutterWindow(const flutter::DartProject& project)
    : project_(project) {}

FlutterWindow::~FlutterWindow() {}

bool FlutterWindow::OnCreate() {
  if (!Win32Window::OnCreate()) {
    return false;
  }

  RECT frame = GetClientArea();

  // The size here must match the window dimensions to avoid unnecessary surface
  // creation / destruction in the startup path.
  flutter_controller_ = std::make_unique<flutter::FlutterViewController>(
      frame.right - frame.left, frame.bottom - frame.top, project_);
  // Ensure that basic setup of the controller was successful.
  if (!flutter_controller_->engine() || !flutter_controller_->view()) {
    return false;
  }
  RegisterPlugins(flutter_controller_->engine());

  windows_channel_ =
      std::make_unique<flutter::MethodChannel<flutter::EncodableValue>>(
      flutter_controller_->engine()->messenger(), "typemate/windows",
      &flutter::StandardMethodCodec::GetInstance());
  windows_channel_->SetMethodCallHandler(
      [this](const flutter::MethodCall<flutter::EncodableValue>& call,
             std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>>
                 result) {
        if (call.method_name() == "showOverlay") {
          std::wstring state = L"listening";
          const auto* arguments = std::get_if<flutter::EncodableMap>(call.arguments());
          if (arguments) {
            auto state_it = arguments->find(flutter::EncodableValue("state"));
            if (state_it != arguments->end()) {
              if (const auto* state_string =
                      std::get_if<std::string>(&state_it->second)) {
                state = std::wstring(state_string->begin(), state_string->end());
              }
            }
          }
          overlay_.Show(state);
          result->Success();
          return;
        }
        if (call.method_name() == "hideOverlay") {
          overlay_.Hide();
          result->Success();
          return;
        }
        if (call.method_name() == "insertText") {
          std::string text;
          const auto* arguments =
              std::get_if<flutter::EncodableMap>(call.arguments());
          if (arguments) {
            auto text_it = arguments->find(flutter::EncodableValue("text"));
            if (text_it != arguments->end()) {
              if (const auto* text_string =
                      std::get_if<std::string>(&text_it->second)) {
                text = *text_string;
              }
            }
          }
          if (InsertTextIntoFocusedField(text)) {
            result->Success();
          } else {
            result->Error("insert_failed",
                          "SendInput could not deliver the transcript to the "
                          "focused field.");
          }
          return;
        }
        result->NotImplemented();
      });

  SetChildContent(flutter_controller_->view()->GetNativeWindow());

  flutter_controller_->engine()->SetNextFrameCallback([&]() {
    this->Show();
  });

  // Flutter can complete the first frame before the "show window" callback is
  // registered. The following call ensures a frame is pending to ensure the
  // window is shown. It is a no-op if the first frame hasn't completed yet.
  flutter_controller_->ForceRedraw();

  return true;
}

void FlutterWindow::OnDestroy() {
  overlay_.Hide();
  windows_channel_ = nullptr;
  if (flutter_controller_) {
    flutter_controller_ = nullptr;
  }

  Win32Window::OnDestroy();
}

LRESULT
FlutterWindow::MessageHandler(HWND hwnd, UINT const message,
                              WPARAM const wparam,
                              LPARAM const lparam) noexcept {
  // Give Flutter, including plugins, an opportunity to handle window messages.
  if (flutter_controller_) {
    std::optional<LRESULT> result =
        flutter_controller_->HandleTopLevelWindowProc(hwnd, message, wparam,
                                                      lparam);
    if (result) {
      return *result;
    }
  }

  switch (message) {
    case WM_FONTCHANGE:
      flutter_controller_->engine()->ReloadSystemFonts();
      break;
  }

  return Win32Window::MessageHandler(hwnd, message, wparam, lparam);
}
