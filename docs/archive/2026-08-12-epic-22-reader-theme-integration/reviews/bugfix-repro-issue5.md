# Bugfix Repro：Issue 5 — 深色主題下點擊「進度/跳頁」按鈕，書籍內容區變成全黑不可辨識

日期：2026-08-06
回報來源：`epic-22-issue-2` 程式碼審查過程中，人類真機測試發現（`tmp/epic-22/review-issue-2-implementation.md` Part 2 第 3 項），並於後續確認為「真的全黑不可辨識」（非審查者原本猜測的「疊加後偏暗」）。

## 症狀

深色主題下，流式 EPUB 閱讀畫面點擊「進度/跳頁」浮動按鈕，彈出的 Bottom Sheet 背後，原本應該還看得到的書籍內容區完全變成黑色，不可辨識。

## Feedback loop

`flutter test` 無法觀察真機/WebView 實際渲染像素，但這個 bug 的機制本質是 Flutter 框架內建的 `ModalBarrier`（Bottom Sheet 背後的半透明遮罩）與 App 自己的背景色合成——這部分完全在 Flutter 框架控制範圍內，可以用 Flutter 引擎真正的 `Color.alphaBlend()`（與 `showModalBottomSheet` 內部合成邏輯同一套）建立確定性的驗證迴圈，不需要真機：寫一個暫時性 `flutter test`，分別計算「書本原始背景（近似白底）」與「`AppTheme.dark` 背景 `#121214`」各自疊上 Flutter 預設遮罩後的合成結果。驗證完畢後即刪除，未留下永久測試資產。

## 根因

`_openFoliateProgressSheet()`（`reader_screen.dart`，以及 `reader_screen.dart` 內另外 5 個 `showModalBottomSheet` 呼叫點：版面設定／PDF 設定／FXL 設定／目錄／筆記）皆未指定 `barrierColor`，全部使用 Flutter 框架預設值 `Colors.black54`（54% 不透明黑）——這個值完全沒有被 epic-22 的 Issue 1/2 改動過。

實測合成結果：
- **Issue 1 上線前**（書本原始背景，近似白底 `#FFFFFF`）：合成後 RGB ≈ `(117,117,117)`，清楚可辨識的中灰色。
- **Issue 1 上線後**（`AppTheme.dark` 背景 `#121214`）：合成後 RGB ≈ `(8,8,9)`。這個亮度在一般手機螢幕（尤其常見 OLED）正常環境光下，已經與純黑無法區分。

也就是說：這不是 WebView 合成或渲染的 bug——另外查證過 `flutter_inappwebview`（6.1.5）的 `useHybridComposition` 預設值就是 `true`，這正是專門設計來正確處理「PlatformView 上疊半透明 Flutter widget」情境、避免黑屏渲染異常的模式，排除了原生合成問題的可能性。真正原因是一個完全未被改動的既有 Flutter 預設遮罩值，疊加在 Issue 1 新增的深色主題背景上時，數學上必然合成出「肉眼判讀為全黑」的結果——是 Issue 1 讓書頁背景變深，才把這個原本無害的既有行為暴露成使用者可感知的問題。

## 決策（人類確認）

深色主題下大幅減弱/取消遮罩。選擇**完全取消**（`Colors.transparent`）而非挑一個介於中間的較弱透明度數值——因為背景起點本身已經接近 0，任何非零的黑色遮罩疊上去合成結果仍然逼近黑，無法用調整透明度數值解決根本問題；深色主題下書頁本身已經是深色、不刺眼，不像淺色主題需要額外遮罩把焦點拉到 Bottom Sheet 上。

修法範圍：一次修正全部 6 個 `showModalBottomSheet` 呼叫點（不只 Issue 5 報告的進度面板），因為 6 處是同一個根因、同一套修法，避免另外 5 個之後被使用者各自回報成 5 個重複 bug。

## 修法

新增共用私有方法 `_showThemedModalBottomSheet<T>({required WidgetBuilder builder, bool enableDrag = true})`（`app/lib/screens/reader_screen.dart`），內部呼叫 `showModalBottomSheet`，`barrierColor` 依 `Theme.of(context).brightness == Brightness.dark` 判斷：深色主題傳 `Colors.transparent`，其餘（淺色/羊皮紙/E-Ink，皆為 `Brightness.light`）傳 `null`（維持 Flutter 既有預設值 `Colors.black54` 不變）。全部 6 個原本直接呼叫 `showModalBottomSheet` 的地方改呼叫這個共用方法。

## 驗證過程中的插曲：測試斷言方式修正兩次

第一版測試直接找 `ModalBarrier` widget 斷言其 `color` 屬性等於 `Colors.transparent`，實測發現兩個問題：

1. `find.byType(ModalBarrier).last` 撿到的不保證是 Bottom Sheet 自己的遮罩——widget 樹裡同時存在其他語意用途、`color` 恆為 `null` 的 `ModalBarrier`，且兩者在深色/淺色主題下於樹中的相對順序不同，`.last` 因此不可靠。改用 `find.byWidgetPredicate` 精確篩選 `color != null` 的實例。
2. 套用修法後，斷言「找得到一個 `color == Colors.transparent` 的 `ModalBarrier`」持續失敗（`Bad state: No element`）。查證 Flutter 框架原始碼（`bottom_sheet.dart:1133`：`if (barrierColor.a != 0 && !offstage)`）確認：`barrierColor` 的 alpha 為 0 時，Flutter **根本不會建構**有顏色的 `ModalBarrier` widget（視為無遮罩效果的最佳化路徑）。正確斷言方式改為「找不到任何 `alpha > 0`（真的會遮蔽畫面）的 `ModalBarrier`」，而非嘗試找一個永遠不會被建構出來的 transparent 實例。

## 驗證結果

- `flutter test test/screens/reader_screen_test.dart`：133/133 通過（含本次新增的 3 個 Issue 5 回歸測試：深色主題進度面板遮罩消失、深色主題版面設定面板遮罩消失〔驗證共用 helper 確實套用到不只一個呼叫點〕、淺色主題遮罩維持既有預設值不變）。
- 全專案 `flutter test`：995/995 通過，`flutter analyze` 乾淨。
- `[DEBUG-i5br]`／`[DEBUG-i5bar]` 暫時性插樁與驗證腳本皆已於結案前完整移除，`git status` 確認僅 `reader_screen.dart`／`reader_screen_test.dart` 兩檔異動。

## 這次診斷帶出的架構觀察

`_openFoliateProgressSheet()` 這類「顯示模式相關的視覺瑕疵」，本質上跟 epic-22 Issue 1/2 是同一類問題的延伸——App 裡任何硬編碼、沒有跟著 `Theme.of(context)`走的視覺元素，都可能在深色主題全面推行後才第一次被真正壓力測試到。這次順帶查出的 Issue 3（FAB 顏色）、Issue 4（Toggle 對比）也是同一個模式。這類問題不容易靠 code review 提前抓到（本身沒有邏輯錯誤，純粹是「這個顏色沒考慮深色情境」），比較實際的預防方式是每次新主題大改動後，安排一輪針對「所有彈窗/浮動元件/互動控制項」的真機深色模式走查，而不是等使用者一個一個回報。
