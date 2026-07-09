# Issue 7：字型粗細（fontWeight）設定無視覺效果 — 實作計劃

**Goal:** 修正 fontWeight 滑桿調整無視覺效果的問題

**根因分析：**
Dart 端 `ReaderSettingsSheet` 將 UI 顯示值（300-900）除以 400 轉為倍率（0.75-2.25），但 Readium 的 `EpubPreferences.fontWeight` 期望的是 CSS 原始值（300-900），不是倍率。導致送出的值範圍錯誤（0.75-2.25 vs 300-900），Readium 無法正確套用。

---

### Task 1: 修正 Dart 端 fontWeight 值轉換

**Files:**
- Modify: `app/lib/screens/reader_settings_sheet.dart`

**Description:**
移除 `_fontWeightMultiplier` 的除以 400 轉換，直接使用 CSS 原始值（300-900）。

- [ ] **Step 1: 修改 `_notifyChanged()` 中的 fontWeight 計算**

```dart
// Before (line 115):
fontWeight: _fontWeightMultiplier,

// After:
fontWeight: _fontWeightMultiplier * 400, // 直接送出 CSS 300-900 原始值
```

- [ ] **Step 2: 修改初始化邏輯，確保從持久化載入時正確轉換**

```dart
// initState() 和 didUpdateWidget() 中：
// Before:
_fontWeightMultiplier = widget.prefs.fontWeight ?? _defaultFontWeightMultiplier;

// After:
_fontWeightMultiplier = widget.prefs.fontWeight != null
    ? widget.prefs.fontWeight! / 400  // 從 CSS 值轉回倍率供 UI 顯示
    : _defaultFontWeightMultiplier;
```

- [ ] **Step 3: 更新預設值註解**

```dart
// Before:
static const _defaultFontWeightMultiplier = 1.0; // UI 顯示 400

// After:
static const _defaultFontWeightMultiplier = 1.0; // 倍率，UI 顯示 400（1.0 × 400）
```

---

### Task 2: 驗證 Kotlin 端接收正確

**Files:**
- Verify: `app/android/app/src/main/kotlin/cc/ugotit/elinkbook/EpubReaderView.kt`

**Description:**
確認 `buildPreferencesFromMap()` 正確接收 fontWeight 並傳給 `EpubPreferences`。

- [ ] **Step 1: 確認 Kotlin 端代碼（已正確，無需修改）**

```kotlin
// Line 157 - 已正確：
fontWeight = (map["fontWeight"] as? Number)?.toDouble(),
```

**驗證方式：** 真機測試拖動滑桿 300→900，觀察文字粗細變化

---

### Task 3: 建立單元測試

**Files:**
- Create: `app/test/screens/reader_settings_sheet_test.dart`

**Description:**
驗證 fontWeight 值在 UI 顯示與持久化儲存之間的正確轉換。

- [ ] **Step 1: 測試 fontWeight 值轉換**

```dart
testWidgets('fontWeight 滑桿調整應送出 CSS 原始值（300-900）', (tester) async {
  final prefs = BookReaderPrefs.empty;
  BookReaderPrefs? capturedPrefs;
  
  await tester.pumpWidget(MaterialApp(
    home: ReaderSettingsSheet(
      prefs: prefs,
      onChanged: (p) => capturedPrefs = p,
    ),
  ));
  
  // 拖動字重滑桿到 700
  final slider = find.byKey(const Key('reader_settings_font_weight_slider'));
  await tester.drag(slider, Offset(100, 0)); // 向右拖動
  
  expect(capturedPrefs?.fontWeight, equals(700.0));
});
```

---

### 驗收標準
- 拖動字重滑桿 300→900，思源黑體/宋體呈現 Variable Font 多級漸進變化
- 其餘 3 款字型呈現模擬粗體效果（Faux Bold）
- `flutter test` 通過、`flutter analyze` 乾淨
