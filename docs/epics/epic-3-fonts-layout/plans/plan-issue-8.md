# Issue 8：閱讀器底部被狀態列/導航列遮蔽 — 實作計劃

**Goal:** 修正閱讀器畫面底部被 Android 狀態列或導航行動列遮蔽的問題

**根因分析：**
`ReaderScreen.build()` 回傳 `Scaffold`，其 `body` 直接放入 `Stack` 包含原生 `PlatformView`，但未處理系統 UI insets（`MediaQuery.viewPadding.bottom`）。導致 PlatformView 佔滿全高，底部內容被系統 UI 遮蔽。

---

### Task 1: 在 ReaderScreen 加入 SafeArea 處理

**Files:**
- Modify: `app/lib/screens/reader_screen.dart`

**Description:**
在 `_buildBody()` 回傳的 `Stack` 外層包裝 `SafeArea`，讓原生視圖避開系統 UI 佔用區域。

- [ ] **Step 1: 修改 `_buildBody()` 方法**

```dart
// Before (lines 252-261):
return Stack(
  children: [
    _buildNativeView(format),
    if (_state == _RenderState.loading)
      const Center(
        key: Key('reader_loading_indicator'),
        child: CircularProgressIndicator(),
      ),
  ],
);

// After:
return SafeArea(
  child: Stack(
    children: [
      _buildNativeView(format),
      if (_state == _RenderState.loading)
        const Center(
          key: Key('reader_loading_indicator'),
          child: CircularProgressIndicator(),
        ),
    ],
  ),
);
```

**備註：**
- `SafeArea` 會自動讀取 `MediaQuery.viewPadding` 並加入適當 padding
- AppBar 已由 `Scaffold` 處理，只需處理 body 區域
- 直排/橫排模式下，`SafeArea` 會依方向自動調整

---

### Task 2: 確認 EpubReaderView/PdfReaderView 高度計算

**Files:**
- Verify: `app/lib/reader/epub_reader_view.dart`
- Verify: `app/lib/reader/pdf_reader_view.dart`

**Description:**
確認原生視圖的 `AndroidView` 會正確適應 `SafeArea` 提供的約束。

- [ ] **Step 1: 確認 AndroidView 使用 `hitTestBehavior: HitTestBehavior.translucent`**

```dart
// epub_reader_view.dart 和 pdf_reader_view.dart 的 build() 方法：
return AndroidView(
  viewType: 'cc.ugotit.elinkbook/epub_reader_view', // 或 pdf_reader_view
  onPlatformViewCreated: _onPlatformViewCreated,
  hitTestBehavior: HitTestBehavior.translucent, // 確保正確接收手勢
);
```

---

### Task 3: 建立整合測試

**Files:**
- Create: `app/integration_test/reader_insets_test.dart`

**Description:**
驗證在不同螢幕尺寸下，閱讀器內容不被系統 UI 遮蔽。

- [ ] **Step 1: 測試 SafeArea 正確套用**

```dart
testWidgets('閱讀器內容不被系統 UI 遮蔽', (tester) async {
  // 設定模擬的 viewPadding（模擬狀態列和導航列）
  tester.binding.window.viewPaddingTestValue = const FakeViewPadding(
    top: 24, // 狀態列高度
    bottom: 48, // 導航列高度
  );
  
  // 載入閱讀器
  await tester.pumpWidget(MaterialApp(
    home: ReaderScreen(
      filePath: samplePath,
      bookId: 'test_book',
      prefsRepository: prefsRepository,
    ),
  ));
  
  // 確認內容區域有適當的 padding
  final safeArea = find.byType(SafeArea);
  expect(safeArea, findsOneWidget);
  
  // 恢復
  tester.binding.window.clearViewPaddingTestValue();
});
```

---

### 驗收標準
- 書籍內容完整顯示，不被系統 UI 遮蔽
- 直排/橫排模式下皆正常
- `flutter test` 通過、`flutter analyze` 乾淨
