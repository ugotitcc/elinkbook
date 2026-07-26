# Issue 8 Spike 報告：`flutter_inappwebview` 選取手勢與 ES Module 載入驗證

- **驗證日期**：2026-07-26
- **測試裝置**：`3CEF42ECD491687` (Android 15, API 35)
- **套件版本**：`flutter_inappwebview` 6.1.5 (`pubspec.lock`)
- **結論**：**GO ✅**

---

## 1. Task 1：選取手勢驗證（長按選字＋拖曳控點）

### 1.1 執行方式
1. 建立 Throwaway Integration Test Harness (`integration_test/_spike_inappwebview_selection.dart`)。
2. 於真機 `3CEF42ECD491687` 啟動測試，等待 `SPIKE-READY`。
3. 透過 `adb shell input touchscreen swipe` 對準畫面文字進行：
   - 模擬長按建立初始選取 (`swipe 300 500 300 500 800`)
   - 模擬拖曳選取控點調整選取範圍 (`swipe 300 500 700 700 600`)
   - 模擬二次拖曳位移 (`swipe 700 700 400 400 600`)

### 1.2 實測紀錄與 Log 證據
測試完全執行完畢，`selectionLog` 取得 3 筆隨拖曳動態變化的選取內容記錄：

```text
I/flutter ( 9700): SPIKE selectionLog: [
  CHANGED: 段文字刻意夠長，確保長按後有足夠的內容可供拖曳測試選取範圍是否確實隨手指移動而擴大或縮小，這是本次驗驗證唯一關心,
  CHANGED: 文字刻意夠長，確保長按後有足夠的內容可供拖曳測試選取範圍是否確實隨手指移動而擴大或縮小，這是本次驗證唯一關心的問題,
  CHANGED: 在真實情境中，使用者會在流式 EPUB 內容區塊長按選取一段文字，接著拖曳選取控點調整範圍，最後放開手指觸發劃線工具列。這段文字刻意夠長，確保長按後有足夠的內容可供拖曳測試選取範圍是否確實隨手指移動而擴大或縮小，這是本次驗證唯一關心的問題。
]
00:59 +1: All tests passed!
```

### 1.3 觀察結論
- `flutter_inappwebview` 的原生觸控事件轉發機制成功還原了 Android 上的「長按選字 -> 顯示控點 -> 拖曳控點」連續手勢。
- DOM `selectionchange` 事件隨控點位移即時觸發，選取文字字串長度與內容即時更新。
- 解決了原生 Flutter `AndroidView` 包裹官方 `android.webkit.WebView` 時控點拖曳無法轉發並中斷選取的問題（ADR 0013）。

---

## 2. Task 2：ES Module 資源載入驗證 (`shouldInterceptRequest`)

### 2.1 執行方式
1. 建立 Throwaway Integration Test Harness (`integration_test/_spike_inappwebview_esmodule.dart`)。
2. 透過 `shouldInterceptRequest` 攔截 `https://appassets.androidplatform.net/` 的多檔案 ES module `import` 鏈結 (`index.html` -> `module_test.js` -> `module_dep.js`)。
3. 對 `.js` 檔強制覆寫 MIME 為 `text/javascript`。

### 2.2 實測紀錄與 Log 證據
```text
I/flutter: SPIKE moduleLoadResult: module-ok
00:08 +1: All tests passed!
```

### 2.3 觀察結論
- `shouldInterceptRequest` 成功攔截並正確服務多檔案 ES module 依賴。
- 證實在 Dart 端進行 `.js` MIME 覆寫可完全避免 `"Expected a JavaScript-or-Wasm module script"` 錯誤與 CORS 限制。

---

## 3. 綜合決策判定：GO ✅

| 判定條件 (`plan-issue-8.md`) | 實測證據 | 結果 |
|---|---|---|
| Task 1：選取控點可拖曳且 `selectionLog` 包含隨拖曳變化的 `CHANGED` 記錄 | `SPIKE selectionLog` 印出 3 筆隨拖曳動態變化的 `CHANGED` 文字紀錄 | ✅ 通過 |
| Task 2：ES module 載入 `moduleLoadResult == 'module-ok'` | `SPIKE moduleLoadResult: module-ok` | ✅ 通過 |

兩項 AND 條件皆取得實測數據支援，確定採用 `flutter_inappwebview` 取代現行原生 `AndroidView`/`WebView` 嵌入架構（進入 Issue 10）。