#ifndef RUNNER_TYPE_MATE_OVERLAY_H_
#define RUNNER_TYPE_MATE_OVERLAY_H_

#include <windows.h>

#include <string>

class TypeMateOverlay {
 public:
  TypeMateOverlay();
  ~TypeMateOverlay();

  void Show(const std::wstring& state, const std::wstring& message = L"");
  void Hide();

 private:
  static LRESULT CALLBACK WindowProc(HWND hwnd, UINT message, WPARAM wparam,
                                     LPARAM lparam);
  LRESULT HandleMessage(HWND hwnd, UINT message, WPARAM wparam, LPARAM lparam);
  void RegisterWindowClass();
  void EnsureWindow();
  void Paint(HDC hdc);
  void MeasureErrorMessage();
  bool IsError() const { return state_ == L"error"; }
  int Width() const;
  int Height() const;

  HWND hwnd_ = nullptr;
  std::wstring state_ = L"listening";
  std::wstring message_;
  int error_text_width_ = 0;
  int error_text_height_ = 0;
  int tick_ = 0;
};

#endif  // RUNNER_TYPE_MATE_OVERLAY_H_
