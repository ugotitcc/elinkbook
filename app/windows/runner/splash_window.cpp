#include "splash_window.h"

#include <windows.h>

#include "resource.h"

namespace {

// 視窗類別名稱：驗證腳本以此名稱偵測啟動小視窗，改名需同步修改腳本
constexpr wchar_t kSplashClassName[] = L"ELINKBOOK_SPLASH";

// 啟動小視窗的邏輯邊長（96 DPI 下的像素），實際尺寸依系統 DPI 縮放
constexpr int kSplashLogicalSize = 400;

// 保險：即使 Flutter 因故一直沒有第一個畫面，也不讓小視窗永遠留著
constexpr UINT_PTR kSafetyTimerId = 1;
constexpr UINT kSafetyTimeoutMs = 30000;

HWND g_splash = nullptr;
HBITMAP g_bitmap = nullptr;

LRESULT CALLBACK SplashProc(HWND hwnd, UINT message, WPARAM wparam,
                            LPARAM lparam) {
  switch (message) {
    case WM_ERASEBKGND:
      return 1;  // 由 WM_PAINT 整面繪製，避免閃爍
    case WM_PAINT: {
      PAINTSTRUCT ps;
      HDC hdc = BeginPaint(hwnd, &ps);
      if (g_bitmap) {
        RECT client;
        GetClientRect(hwnd, &client);
        BITMAP bm{};
        GetObject(g_bitmap, sizeof(bm), &bm);
        HDC mem = CreateCompatibleDC(hdc);
        HGDIOBJ old = SelectObject(mem, g_bitmap);
        SetStretchBltMode(hdc, HALFTONE);
        SetBrushOrgEx(hdc, 0, 0, nullptr);
        StretchBlt(hdc, 0, 0, client.right - client.left,
                   client.bottom - client.top, mem, 0, 0, bm.bmWidth,
                   bm.bmHeight, SRCCOPY);
        SelectObject(mem, old);
        DeleteDC(mem);
      }
      EndPaint(hwnd, &ps);
      return 0;
    }
    case WM_TIMER:
      if (wparam == kSafetyTimerId) {
        SplashWindow::Close();
      }
      return 0;
    case WM_NCHITTEST:
      return HTCAPTION;  // 允許使用者拖曳（Flutter 視窗載入較久時可移開）
  }
  return DefWindowProc(hwnd, message, wparam, lparam);
}

}  // namespace

namespace SplashWindow {

void Show() {
  if (g_splash) {
    return;
  }
  HINSTANCE instance = GetModuleHandle(nullptr);

  g_bitmap = static_cast<HBITMAP>(
      LoadImage(instance, MAKEINTRESOURCE(IDB_SPLASH), IMAGE_BITMAP, 0, 0,
                LR_CREATEDIBSECTION));
  if (!g_bitmap) {
    return;  // 圖載入失敗就不顯示，不影響主程式啟動
  }

  WNDCLASS wc{};
  wc.lpfnWndProc = SplashProc;
  wc.hInstance = instance;
  wc.hCursor = LoadCursor(nullptr, IDC_ARROW);
  wc.hIcon = LoadIcon(instance, MAKEINTRESOURCE(IDI_APP_ICON));
  wc.lpszClassName = kSplashClassName;
  RegisterClass(&wc);

  const UINT dpi = GetDpiForSystem();
  const int size = MulDiv(kSplashLogicalSize, static_cast<int>(dpi), 96);
  const int x = (GetSystemMetrics(SM_CXSCREEN) - size) / 2;
  const int y = (GetSystemMetrics(SM_CYSCREEN) - size) / 2;

  // WS_EX_TOOLWINDOW：不在工作列另外佔一個按鈕，主視窗出現後才有工作列項目
  g_splash = CreateWindowEx(WS_EX_TOOLWINDOW, kSplashClassName, L"elinkbook",
                            WS_POPUP, x, y, size, size, nullptr, nullptr,
                            instance, nullptr);
  if (!g_splash) {
    DeleteObject(g_bitmap);
    g_bitmap = nullptr;
    return;
  }
  SetTimer(g_splash, kSafetyTimerId, kSafetyTimeoutMs, nullptr);
  ShowWindow(g_splash, SW_SHOWNOACTIVATE);
  UpdateWindow(g_splash);  // 同步繪製：之後 Flutter 引擎啟動會佔住主執行緒一段時間
}

void Close() {
  if (g_splash) {
    KillTimer(g_splash, kSafetyTimerId);
    DestroyWindow(g_splash);
    g_splash = nullptr;
  }
  if (g_bitmap) {
    DeleteObject(g_bitmap);
    g_bitmap = nullptr;
  }
}

}  // namespace SplashWindow
