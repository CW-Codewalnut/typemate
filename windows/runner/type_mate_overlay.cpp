#include "type_mate_overlay.h"

#include <algorithm>
#include <cmath>

namespace {
constexpr wchar_t kOverlayWindowClass[] = L"TypeMateNativeOverlayWindow";
constexpr int kOverlayWidth = 210;
constexpr int kOverlayHeight = 58;
constexpr int kTimerId = 1;
constexpr int kTimerMs = 70;

COLORREF Rgb(int red, int green, int blue) { return RGB(red, green, blue); }
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

void TypeMateOverlay::EnsureWindow() {
  if (hwnd_) {
    return;
  }

  const RECT work_area = [] {
    RECT rect = {};
    SystemParametersInfo(SPI_GETWORKAREA, 0, &rect, 0);
    return rect;
  }();
  const int left = work_area.left +
                   ((work_area.right - work_area.left - kOverlayWidth) / 2);
  const int top = work_area.bottom - kOverlayHeight - 28;

  hwnd_ = CreateWindowEx(
      WS_EX_TOPMOST | WS_EX_TOOLWINDOW | WS_EX_NOACTIVATE, kOverlayWindowClass,
      L"TypeMate", WS_POPUP, left, top, kOverlayWidth, kOverlayHeight, nullptr,
      nullptr, GetModuleHandle(nullptr), this);
  if (hwnd_) {
    HRGN rounded_region = CreateRoundRectRgn(0, 0, kOverlayWidth + 1,
                                            kOverlayHeight + 1, 58, 58);
    SetWindowRgn(hwnd_, rounded_region, TRUE);
  }
}

void TypeMateOverlay::Show(const std::wstring& state) {
  state_ = state.empty() ? L"listening" : state;
  EnsureWindow();
  if (!hwnd_) {
    return;
  }

  SetWindowPos(hwnd_, HWND_TOPMOST, 0, 0, 0, 0,
               SWP_NOMOVE | SWP_NOSIZE | SWP_NOACTIVATE | SWP_SHOWWINDOW);
  SetTimer(hwnd_, kTimerId, kTimerMs, nullptr);
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
  RECT rect = {0, 0, kOverlayWidth, kOverlayHeight};
  HBRUSH background = CreateSolidBrush(Rgb(31, 34, 48));
  HPEN background_pen = CreatePen(PS_SOLID, 1, Rgb(31, 34, 48));
  HGDIOBJ previous_brush = SelectObject(hdc, background);
  HGDIOBJ previous_pen = SelectObject(hdc, background_pen);
  RoundRect(hdc, rect.left, rect.top, rect.right, rect.bottom, 58, 58);
  SelectObject(hdc, previous_pen);
  SelectObject(hdc, previous_brush);
  DeleteObject(background_pen);
  DeleteObject(background);

  SetBkMode(hdc, TRANSPARENT);
  SetTextColor(hdc, Rgb(255, 255, 255));
  HFONT font = CreateFont(14, 0, 0, 0, FW_BOLD, FALSE, FALSE, FALSE,
                          DEFAULT_CHARSET, OUT_DEFAULT_PRECIS,
                          CLIP_DEFAULT_PRECIS, CLEARTYPE_QUALITY,
                          DEFAULT_PITCH | FF_SWISS, L"Segoe UI");
  HFONT previous_font = static_cast<HFONT>(SelectObject(hdc, font));
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
