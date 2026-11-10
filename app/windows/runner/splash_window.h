#ifndef RUNNER_SPLASH_WINDOW_H_
#define RUNNER_SPLASH_WINDOW_H_

// 啟動小視窗（epic-66）：雙擊 exe 後、Flutter 第一個畫面出現前顯示 logo，
// 避免使用者面對一段空白或毫無反應的時間。
// 所有函式都必須在主執行緒（建立視窗的執行緒）呼叫。
namespace SplashWindow {

// 顯示啟動小視窗（置中、無邊框、不搶焦點）。已顯示時不重複建立。
void Show();

// 關閉啟動小視窗。尚未顯示或已關閉時不做事。
void Close();

}  // namespace SplashWindow

#endif  // RUNNER_SPLASH_WINDOW_H_
