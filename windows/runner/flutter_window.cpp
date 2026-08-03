#include "flutter_window.h"

#include <flutter/method_channel.h>
#include <flutter/standard_method_codec.h>
#include <shellapi.h>

#include <optional>
#include <string>
#include <vector>

#include "flutter/generated_plugin_registrant.h"
#include "resource.h"

namespace {

constexpr UINT kTrayIconMessage = WM_APP + 1;
constexpr UINT kTrayIconId = 1;
constexpr UINT kTrayMenuOpenId = 0xA001;
constexpr UINT kTrayMenuQuitId = 0xA002;
// If Dart does not answer the quit request (engine hung or gone), force the
// process down after this timer fires.
constexpr UINT_PTR kQuitFallbackTimerId = 0xA003;

}  // namespace

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
          std::wstring overlay_message;
          const auto* arguments = std::get_if<flutter::EncodableMap>(call.arguments());
          if (arguments) {
            auto state_it = arguments->find(flutter::EncodableValue("state"));
            if (state_it != arguments->end()) {
              if (const auto* state_string =
                      std::get_if<std::string>(&state_it->second)) {
                state = std::wstring(state_string->begin(), state_string->end());
              }
            }
            auto message_it =
                arguments->find(flutter::EncodableValue("message"));
            if (message_it != arguments->end()) {
              if (const auto* message_string =
                      std::get_if<std::string>(&message_it->second)) {
                // Proper UTF-8 decode: failure copy may not stay ASCII.
                const int length = MultiByteToWideChar(
                    CP_UTF8, 0, message_string->c_str(), -1, nullptr, 0);
                if (length > 0) {
                  overlay_message.resize(length - 1);
                  MultiByteToWideChar(CP_UTF8, 0, message_string->c_str(), -1,
                                      overlay_message.data(), length);
                }
              }
            }
          }
          overlay_.Show(state, overlay_message);
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

  AddTrayIcon();

  return true;
}

void FlutterWindow::OnDestroy() {
  RemoveTrayIcon();
  overlay_.Hide();
  windows_channel_ = nullptr;
  if (flutter_controller_) {
    flutter_controller_ = nullptr;
  }

  Win32Window::OnDestroy();
}

void FlutterWindow::AddTrayIcon() {
  tray_window_ = GetHandle();
  NOTIFYICONDATA icon_data = {};
  icon_data.cbSize = sizeof(icon_data);
  icon_data.hWnd = tray_window_;
  icon_data.uID = kTrayIconId;
  icon_data.uFlags = NIF_ICON | NIF_MESSAGE | NIF_TIP;
  icon_data.uCallbackMessage = kTrayIconMessage;
  icon_data.hIcon = ::LoadIcon(::GetModuleHandle(nullptr),
                               MAKEINTRESOURCE(IDI_APP_ICON));
  wcscpy_s(icon_data.szTip, L"Type Mate");
  if (!::Shell_NotifyIcon(NIM_ADD, &icon_data)) {
    tray_window_ = nullptr;
  }
}

void FlutterWindow::RemoveTrayIcon() {
  if (tray_window_ == nullptr) {
    return;
  }
  NOTIFYICONDATA icon_data = {};
  icon_data.cbSize = sizeof(icon_data);
  icon_data.hWnd = tray_window_;
  icon_data.uID = kTrayIconId;
  ::Shell_NotifyIcon(NIM_DELETE, &icon_data);
  tray_window_ = nullptr;
}

void FlutterWindow::ShowMainWindow() {
  HWND handle = GetHandle();
  ::ShowWindow(handle, SW_SHOW);
  ::ShowWindow(handle, SW_RESTORE);
  ::SetForegroundWindow(handle);
}

void FlutterWindow::ShowTrayMenu() {
  HMENU menu = ::CreatePopupMenu();
  ::AppendMenu(menu, MF_STRING, kTrayMenuOpenId, L"Open Type Mate");
  ::AppendMenu(menu, MF_SEPARATOR, 0, nullptr);
  ::AppendMenu(menu, MF_STRING, kTrayMenuQuitId, L"Quit Type Mate");
  POINT cursor;
  ::GetCursorPos(&cursor);
  // Required so the menu closes when the user clicks elsewhere.
  ::SetForegroundWindow(GetHandle());
  ::TrackPopupMenu(menu, TPM_RIGHTBUTTON, cursor.x, cursor.y, 0, GetHandle(),
                   nullptr);
  ::DestroyMenu(menu);
}

void FlutterWindow::QuitFromTray() {
  RemoveTrayIcon();
  if (windows_channel_) {
    // Dart shuts the resident speech server down and exits the process.
    windows_channel_->InvokeMethod("quitRequested", nullptr);
    // Safety net: if Dart never answers, force the window down.
    ::SetTimer(GetHandle(), kQuitFallbackTimerId, 3000, nullptr);
    return;
  }
  SetQuitOnClose(true);
  Destroy();
}

LRESULT
FlutterWindow::MessageHandler(HWND hwnd, UINT const message,
                              WPARAM const wparam,
                              LPARAM const lparam) noexcept {
  switch (message) {
    case WM_CLOSE:
      // Hide to the system tray instead of quitting: dictation keeps
      // running in the background. Quit via the tray menu.
      ::ShowWindow(hwnd, SW_HIDE);
      return 0;
    case kTrayIconMessage:
      if (lparam == WM_LBUTTONUP || lparam == WM_LBUTTONDBLCLK) {
        ShowMainWindow();
      } else if (lparam == WM_RBUTTONUP) {
        ShowTrayMenu();
      }
      return 0;
    case WM_COMMAND:
      if (LOWORD(wparam) == kTrayMenuOpenId) {
        ShowMainWindow();
        return 0;
      }
      if (LOWORD(wparam) == kTrayMenuQuitId) {
        QuitFromTray();
        return 0;
      }
      break;
    case WM_TIMER:
      if (wparam == kQuitFallbackTimerId) {
        ::KillTimer(hwnd, kQuitFallbackTimerId);
        SetQuitOnClose(true);
        Destroy();
        return 0;
      }
      break;
  }

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
