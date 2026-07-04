# Code Review 報告：Issue 5 程式碼審查 (Worktree 複審)

本報告針對分支 `worktree-epic-0-issue-5-reader-screen-integration` 中的程式碼進行審查。審查依據為專案系統設計文件（SDD），即 [spec.md](../../spec.md) 與 [design.md](../../design.md)。

---

## 評估摘要 (Assessment Summary)

* **評估結論：** **核准通過，建議合併 (Approved / Ready to Merge)**
* **總體評價：** 本次程式碼實作非常優異，完全實現了 `plan-issue-5.md` 中規定的分派與渲染功能。不僅徹底解決了先前計劃審查中提到的原生資源釋放問題（Important #1），更在細節處展現了極佳的防禦性程式設計思維與測試嚴謹度。

---

## 優點與良好實作 (Strengths)

1. **徹底解決原生視圖資源佔用問題 (Important #1 已解決)：**
   - 在 [reader_screen.dart](../../../app/lib/screens/reader_screen.dart) 的 `_buildBody` 實作中，當狀態變更為 `_RenderState.error` 時，程式碼直接 return 錯誤文字元件（Early Return）。
   - 此寫法成功將 `AndroidView`（`EpubReaderView` / `PdfReaderView`）從 widget tree 中完全移除，從而自動觸發原生 `PlatformView` 的 `dispose()`，確保 Android 端的資源（如 WebView、PdfRenderer）能夠徹底被清理，不再滯留於畫面上層或背景中。

2. **防禦性非同步狀態更新：**
   - 在 MethodChannel 的 async callback 實作中（`_handlePageRendered` 和 `_handleError`），均加入了 `if (!mounted) return;` 檢查。
   - 由於這些 callback 是由 native 層非同步呼叫，加上 `mounted` 守衛可有效防止 Flutter widget 已被 pop/dispose 但仍調用 `setState` 的執行階段異常，提升了程式碼的健壯性。

3. **高嚴謹度的整合測試設計：**
   - 在 [reader_screen_test.dart](../../../app/integration_test/reader_screen_test.dart) 中，在呼叫 `_pumpUntil` 等待載入指示器消失之前，顯式加入了：
     `expect(find.byKey(const Key('reader_loading_indicator')), findsOneWidget);`
   - 此斷言可確保載入指示器在一開始確實被渲染出來。這能有效防止因為 Key 拼寫錯誤或元件未生成，導致 `_loadingIndicatorGone()` 一開始就回傳 `true`，從而產生測試在載入成功前即 silent pass（虛假綠燈）的漏洞。

4. **100% 綠燈的環境指標：**
   - 實地於 worktree 中執行 `flutter analyze` 靜態分析為 `No issues found!`（完全無警告）。
   - 執行 `flutter test` 所有 10 項單元與元件測試均全數通過。

---

## 審查發現與改善建議 (Findings & Recommendations)

本階段程式碼實作中未發現任何 **Critical (嚴重)** 或 **Important (重要)** 級別的問題，僅有一項 Minor (輕微) 優化建議：

### Critical (嚴重問題)
- **無。**

### Important (重要建議)
- **無。**

### Minor (輕微建議)

#### 1. `BookFormat.unknown` 冗餘分支之程式碼註解
* **說明位置：**
  [reader_screen.dart L98-100](../../../app/lib/screens/reader_screen.dart#L98-100)
  ```dart
  case BookFormat.unknown:
    return const SizedBox.shrink();
  ```
* **問題說明：**
  此分支在 `_buildBody` 的 L57 處已被 `format == BookFormat.unknown` 條件提早過濾並攔截（直接回傳不支援格式的文字）。因此，此處在 `_buildNativeView` 中的 `unknown` 分支實質上是 unreachable branch。
* **改善建議：**
  雖然為了 Dart 窮舉性 (exhaustiveness) 必須宣告此 case，但為了提升可讀性，建議在該分支內加上簡短註解說明：`// 已於 _buildBody 攔截，此處僅作窮舉處理`，避免未來維護的工程師產生困惑。
