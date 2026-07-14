#ifndef RUNNER_TYPE_MATE_OVERLAY_H_
#define RUNNER_TYPE_MATE_OVERLAY_H_

#include <windows.h>

#include <string>

class TypeMateOverlay {
 public:
  TypeMateOverlay();
  ~TypeMateOverlay();

  void Show(const std::wstring& state);
  void Hide();

 private:
  static LRESULT CALLBACK WindowProc(HWND hwnd, UINT message, WPARAM wparam,
                                     LPARAM lparam);
  LRESULT HandleMessage(HWND hwnd, UINT message, WPARAM wparam, LPARAM lparam);
  void RegisterWindowClass();
  void EnsureWindow();
  void Paint(HDC hdc);

  HWND hwnd_ = nullptr;
  std::wstring state_ = L"listening";
  int tick_ = 0;
};

#endif  // RUNNER_TYPE_MATE_OVERLAY_H_
