# 文件審查報告：plan-issue-2.md (Issue 2 實作計劃)

本報告針對 `plan-issue-2.md` 計劃文件進行文件審查，評估其可行性、強健性、以及是否契合專案的 PRD 與 ADR 規格。

- **審查對象**：[plan-issue-2.md](file:///U:/MyDeveloper/AI/elinkBook/docs/epics/epic-0-skeleton/plans/plan-issue-2.md)
- **報告路徑**：`docs/epics/epic-0-skeleton/reviews/review-plan-issue-2.md`
- **最新狀態**：已修正。Important #1（副檔名大小寫）與 #2（返回機制）皆已採納並更新至 `plan-issue-2.md`；#2 的實作方式與本報告建議不同（改用 Flutter `AppBar` 預設的自動返回鍵，而非手動 `IconButton`+`pop()`），理由見 `plan-issue-2.md` 的「文件審查回應紀錄」。Minor 的 `trim()` 建議未採納（YAGNI，無具體使用情境佐證）。

---

## 審查結論

### 1. 優點 (Strengths)
- **TDD 流程設計完善**：Task 1 與 Task 2 皆完整採用先寫失敗測試、再實作、後驗證的 TDD 模式，能有效保證程式碼品質。
- **測試不依賴模擬器**：將格式偵測設計為不依賴 Flutter widget 的純 Dart 函式，且 Widget 測試皆為本機測試，不需要啟動真實模擬器，這能大幅縮短開發與 CI 運行的時間。
- **無狀態與擴充點清晰**：`ReaderScreen` 的定位非常明確（僅作為分派的 thin widget），為下一階段（Issue 5）引入真正原生渲染視圖提供了乾淨的接縫 (seam)。

### 2. 發現的問題 (Issues)

#### Critical (Must Fix)
- 無

#### Important (Should Fix)
1. **副檔名大小寫不敏感支援缺失**：
   - **位置**：Task 1 Step 1 測試與 Task 1 Step 3 實作。
   - **問題**：現有設計直接使用 `path.endsWith('.epub')` 與 `path.endsWith('.pdf')`。這會導致大寫副檔名（例如 `book.EPUB`、`book.PDF` 或 `book.Pdf`）被判定為 `BookFormat.unknown`。
   - **影響**：在實際使用中，很多書籍副檔名可能為大寫，這會導致格式偵測失敗而無法閱讀。
   - **建議修正**：測試應加入大寫副檔名的案例；實作中應先將路徑轉為小寫再行判斷（如 `path.toLowerCase().endsWith(...)`）。

2. **ReaderScreen 缺乏返回導航機制**：
   - **位置**：Task 2 Step 3 實作（`ReaderScreen` widget 結構）。
   - **問題**：`ReaderScreen` 實作僅有一個 `body: Center(...)` 的 `Scaffold`，沒有 `AppBar` 或任何返回按鈕。
   - **影響**：使用者在點開書籍後，畫面會被「卡死」在該閱讀畫面中，無法返回書架（`LibraryScreen`）。雖然這僅是 Issue 2 的佔位畫面，但隨著後續 Issue 6 的導航串接，缺乏返回機制會導致基本操作流中斷。
   - **建議修正**：`ReaderScreen` 的 Scaffold 應包含 `AppBar`，且至少包含一個返回按鈕（或使用 `AppBar` 預設的領航返回按鈕），調用 `Navigator.of(context).pop()` 以提供返回功能。

#### Minor (Nice to Have)
1. **路徑尾端多餘空白的防禦性處理**：
   - **位置**：Task 1 Step 3 (`detectBookFormat`)。
   - **問題**：如果路徑字串尾端不小心包含多餘空白（如 `'sample.epub '`），目前的 `endsWith` 會失效。
   - **建議修正**：在進行偵測前，可使用 `path.trim()` 先去除字串首尾空白。

---

## 修改建議與修正方案 (Proposed Fixes)

### 建議修正 1：測試大寫副檔名與小寫化實作

在 `app/test/reader/book_format_test.dart` 中，新增大小寫不敏感測試：
```dart
test('大寫副檔名判定成功', () {
  expect(detectBookFormat('book.EPUB'), BookFormat.epub);
  expect(detectBookFormat('book.PDF'), BookFormat.pdf);
});
```

並在 `app/lib/reader/book_format.dart` 的 `detectBookFormat` 實作中進行轉換：
```dart
BookFormat detectBookFormat(String path) {
  final cleanPath = path.trim().toLowerCase();
  if (cleanPath.endsWith('.epub')) return BookFormat.epub;
  if (cleanPath.endsWith('.pdf')) return BookFormat.pdf;
  return BookFormat.unknown;
}
```

### 建議修正 2：在 ReaderScreen 新增返回按鈕

將 `ReaderScreen` 的 UI 修改為具備返回功能的外殼：
```dart
@override
Widget build(BuildContext context) {
  final format = detectBookFormat(filePath);
  return Scaffold(
    appBar: AppBar(
      title: const Text('閱讀器佔位外殼'),
      leading: IconButton(
        icon: const Icon(Icons.arrow_back),
        onPressed: () => Navigator.of(context).pop(),
      ),
    ),
    body: Center(
      child: Text(_placeholderLabel(format)),
    ),
  );
}
```

---

## 最終評估 (Assessment)

**Ready to implement: With fixes**

**評估說明**：
這份實作計劃整體架構與 TDD 設計極佳。只要在計畫中補上「大小寫不敏感的副檔名偵測」與「ReaderScreen 的返回導航機制」，該計劃就非常完備，隨時可以安全交付給 Agent 進行實作。
