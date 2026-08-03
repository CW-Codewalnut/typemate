#include "type_mate_overlay.h"

#include <algorithm>
#include <cmath>

namespace {
constexpr wchar_t kOverlayWindowClass[] = L"TypeMateNativeOverlayWindow";
constexpr int kOverlayWidth = 210;
constexpr int kOverlayHeight = 58;
// The error toast is a capsule sized to its sentence: text wraps at this
// width, and padding completes the pill.
constexpr int kErrorMaxTextWidth = 360;
constexpr int kErrorPadX = 24;
constexpr int kErrorPadY = 13;
constexpr int kErrorMinHeight = 44;
constexpr int kTimerId = 1;
constexpr int kTimerMs = 70;
// Auto-hide for the error toast; every other state is hidden by the app.
constexpr int kHideTimerId = 2;
constexpr int kErrorAutoHideMs = 4500;

COLORREF Rgb(int red, int green, int blue) { return RGB(red, green, blue); }

HFONT CreateOverlayFont() {
  return CreateFont(14, 0, 0, 0, FW_BOLD, FALSE, FALSE, FALSE,
                    DEFAULT_CHARSET, OUT_DEFAULT_PRECIS, CLIP_DEFAULT_PRECIS,
                    CLEARTYPE_QUALITY, DEFAULT_PITCH | FF_SWISS, L"Segoe UI");
}
}  // namespace

TypeMateOverlay::TypeMateOverlay() { RegisterWindowClass(); }

TypeMateOverlay::~TypeMateOverlay() { Hide(); }

void TypeMateOverlay::RegisterWindowClass() {
  static bool registered = false;
  if (registered) {
    return;
  }

  WNDCLASS window_class = {};
  window_class.lpfnWndProc = TypeMateOverlay::WindowProc;
  window_class.hInstance = GetModuleHandle(nullptr);
  window_class.lpszClassName = kOverlayWindowClass;
  window_class.hCursor = LoadCursor(nullptr, IDC_ARROW);
  window_class.hbrBackground = CreateSolidBrush(Rgb(31, 34, 48));
  RegisterClass(&window_class);
  registered = true;
}

int TypeMateOverlay::Width() const {
  return IsError() ? error_text_width_ + 2 * kErrorPadX : kOverlayWidth;
}

int TypeMateOverlay::Height() const {
  if (!IsError()) {
    return kOverlayHeight;
  }
  const int fitted = error_text_height_ + 2 * kErrorPadY;
  return fitted < kErrorMinHeight ? kErrorMinHeight : fitted;
}

/// Sizes the error capsule to its sentence: wrap at the max text width,
/// then pad. Measured with the same font Paint() draws with.
void TypeMateOverlay::MeasureErrorMessage() {
  HDC hdc = GetDC(nullptr);
  HFONT font = CreateOverlayFont();
  HGDIOBJ previous_font = SelectObject(hdc, font);
  RECT rect = {0, 0, kErrorMaxTextWidth, 0};
  DrawText(hdc, message_.c_str(), -1, &rect,
           DT_CALCRECT | DT_CENTER | DT_WORDBREAK | DT_NOPREFIX);
  error_text_width_ = rect.right - rect.left;
  error_text_height_ = rect.bottom - rect.top;
  SelectObject(hdc, previous_font);
  DeleteObject(font);
  ReleaseDC(nullptr, hdc);
}

void TypeMateOverlay::EnsureWindow() {
  if (hwnd_) {
    return;
  }

  const RECT work_area = [] {
    RECT rect = {};
    SystemParametersInfo(SPI_GETWORKAREA, 0, &rect, 0);
    return rect;
  }();
  const int left =
      work_area.left + ((work_area.right - work_area.left - Width()) / 2);
  const int top = work_area.bottom - Height() - 28;

  hwnd_ = CreateWindowEx(
      WS_EX_TOPMOST | WS_EX_TOOLWINDOW | WS_EX_NOACTIVATE, kOverlayWindowClass,
      L"TypeMate", WS_POPUP, left, top, Width(), Height(), nullptr,
      nullptr, GetModuleHandle(nullptr), this);
  if (hwnd_) {
    // Ellipse = full height: a capsule for any window size.
    HRGN rounded_region = CreateRoundRectRgn(0, 0, Width() + 1, Height() + 1,
                                             Height(), Height());
    SetWindowRgn(hwnd_, rounded_region, TRUE);
  }
}

// The start chime is not played here: dictation sounds are Dart-side
// (lib/src/core/platform/dictation_sounds.dart), one implementation for
// every desktop.
void TypeMateOverlay::Show(const std::wstring& state,
                           const std::wstring& message) {
  const bool was_error = IsError();
  state_ = state.empty() ? L"listening" : state;
  message_ = message;
  if (IsError()) {
    MeasureErrorMessage();
  }
  // The error toast's window is sized to its message, so entering (or
  // leaving) the error state recreates the window; the listening and
  // transcribing states share one fixed-size window with no flicker.
  if (hwnd_ && (IsError() || was_error)) {
    Hide();
  }
  EnsureWindow();
  if (!hwnd_) {
    return;
  }

  SetWindowPos(hwnd_, HWND_TOPMOST, 0, 0, 0, 0,
               SWP_NOMOVE | SWP_NOSIZE | SWP_NOACTIVATE | SWP_SHOWWINDOW);
  if (IsError()) {
    // No bar animation to drive; just an auto-hide so the toast never
    // needs a hide call from the app.
    KillTimer(hwnd_, kTimerId);
    SetTimer(hwnd_, kHideTimerId, kErrorAutoHideMs, nullptr);
  } else {
    KillTimer(hwnd_, kHideTimerId);
    SetTimer(hwnd_, kTimerId, kTimerMs, nullptr);
  }
  InvalidateRect(hwnd_, nullptr, TRUE);
}

void TypeMateOverlay::Hide() {
  if (!hwnd_) {
    return;
  }

  KillTimer(hwnd_, kTimerId);
  DestroyWindow(hwnd_);
  hwnd_ = nullptr;
}

LRESULT CALLBACK TypeMateOverlay::WindowProc(HWND hwnd, UINT message,
                                             WPARAM wparam, LPARAM lparam) {
  TypeMateOverlay* overlay = nullptr;
  if (message == WM_NCCREATE) {
    const auto create_struct = reinterpret_cast<CREATESTRUCT*>(lparam);
    overlay = static_cast<TypeMateOverlay*>(create_struct->lpCreateParams);
    SetWindowLongPtr(hwnd, GWLP_USERDATA,
                     reinterpret_cast<LONG_PTR>(overlay));
  } else {
    overlay = reinterpret_cast<TypeMateOverlay*>(
        GetWindowLongPtr(hwnd, GWLP_USERDATA));
  }

  if (overlay) {
    return overlay->HandleMessage(hwnd, message, wparam, lparam);
  }
  return DefWindowProc(hwnd, message, wparam, lparam);
}

LRESULT TypeMateOverlay::HandleMessage(HWND hwnd, UINT message, WPARAM wparam,
                                       LPARAM lparam) {
  switch (message) {
    case WM_TIMER:
      if (wparam == kHideTimerId) {
        // The error toast dismisses itself; a newer non-error overlay owns
        // the animation timer instead and must not be torn down.
        if (IsError()) {
          Hide();
        }
        return 0;
      }
      tick_ += 1;
      InvalidateRect(hwnd, nullptr, TRUE);
      return 0;
    case WM_PAINT: {
      PAINTSTRUCT paint = {};
      HDC hdc = BeginPaint(hwnd, &paint);
      Paint(hdc);
      EndPaint(hwnd, &paint);
      return 0;
    }
    case WM_DESTROY:
      KillTimer(hwnd, kTimerId);
      if (hwnd_ == hwnd) {
        hwnd_ = nullptr;
      }
      return 0;
  }
  return DefWindowProc(hwnd, message, wparam, lparam);
}

void TypeMateOverlay::Paint(HDC hdc) {
  // The error toast is a red pill with the failure sentence; everything
  // else is the dark pill with the animated bars.
  const COLORREF fill = IsError() ? Rgb(96, 28, 34) : Rgb(31, 34, 48);
  RECT rect = {0, 0, Width(), Height()};
  HBRUSH background = CreateSolidBrush(fill);
  HPEN background_pen = CreatePen(PS_SOLID, 1, fill);
  HGDIOBJ previous_brush = SelectObject(hdc, background);
  HGDIOBJ previous_pen = SelectObject(hdc, background_pen);
  RoundRect(hdc, rect.left, rect.top, rect.right, rect.bottom, Height(),
            Height());
  SelectObject(hdc, previous_pen);
  SelectObject(hdc, previous_brush);
  DeleteObject(background_pen);
  DeleteObject(background);

  SetBkMode(hdc, TRANSPARENT);
  SetTextColor(hdc, Rgb(255, 255, 255));
  HFONT font = CreateOverlayFont();
  HFONT previous_font = static_cast<HFONT>(SelectObject(hdc, font));
  if (IsError()) {
    // Centered both ways: the window was sized from this same measured
    // text, so the rect just re-centers the measured block.
    const int top = (Height() - error_text_height_) / 2;
    RECT text_rect = {kErrorPadX, top, Width() - kErrorPadX,
                      top + error_text_height_};
    DrawText(hdc, message_.c_str(), -1, &text_rect,
             DT_CENTER | DT_WORDBREAK | DT_NOPREFIX);
    SelectObject(hdc, previous_font);
    DeleteObject(font);
    return;
  }
  RECT text_rect = {8, 7, kOverlayWidth - 8, 29};
  const wchar_t* label = state_ == L"transcribing" ? L"Transcribing locally..."
                                                   : L"TypeMate is listening...";
  DrawText(hdc, label, -1, &text_rect, DT_CENTER | DT_VCENTER | DT_SINGLELINE);
  SelectObject(hdc, previous_font);
  DeleteObject(font);

  HBRUSH bar_brush = CreateSolidBrush(Rgb(122, 139, 255));
  HPEN bar_pen = CreatePen(PS_SOLID, 1, Rgb(122, 139, 255));
  previous_brush = SelectObject(hdc, bar_brush);
  previous_pen = SelectObject(hdc, bar_pen);
  constexpr int bar_count = 7;
  constexpr int bar_width = 5;
  constexpr int gap = 6;
  constexpr int min_height = 5;
  constexpr int max_height = 18;
  const int total_width = (bar_count * bar_width) + ((bar_count - 1) * gap);
  const int start_x = (kOverlayWidth - total_width) / 2;
  const int center_y = 42;

  for (int i = 0; i < bar_count; i++) {
    const double phase = (tick_ + (i * 2)) * 0.55;
    const int height = static_cast<int>(
        min_height + ((std::sin(phase) + 1.0) / 2.0) *
                         (max_height - min_height));
    const int left = start_x + (i * (bar_width + gap));
    const int top = center_y - (height / 2);
    RoundRect(hdc, left, top, left + bar_width, top + height, bar_width,
              bar_width);
  }
  SelectObject(hdc, previous_pen);
  SelectObject(hdc, previous_brush);
  DeleteObject(bar_pen);
  DeleteObject(bar_brush);
}
