# Issue 19：正式實作——「強制 FXL」書籍橫向雙頁排版修復（`Publication.Builder` 重建 `metadata.layout`）實作計劃

> **給執行者（agentic worker）的提示：** 建議使用 `superpowers:subagent-driven-development`（推薦）或 `superpowers:executing-plans` 逐工單執行本計劃。工單內的步驟以核取方塊（`- [ ]`）追蹤完成狀態。

**目標：** 把 Issue 18 Spike 已驗證 GO 的方向（`Publication.Builder` 重建 `Publication` 物件、強制 `metadata.layout = Layout.FIXED`）收斂為正式、可維護、進 `main` 的實作，修復 Issue 16「強制 FXL 後橫向雙頁模式退化成單頁」。架構決策依據見 `docs/adr/0016-fxl-metadata-override-via-publication-builder.md`。

**架構（2026-07-30 grilling 定案，見 `design.md`「Issue 19 Discovery」）：**
- **不做 Dart→Kotlin 旗標傳遞管線**。`EpubReaderView`（Dart widget）／`attachNavigator()`（Kotlin）只會在上游已決定「這本書用 FXL 引擎開」時才會建構/執行，`openedPublication.metadata.layout != Layout.FIXED` 這個 Kotlin 端運行時判斷式已完整表達「Readium 官方解析器不同意上游決定」，不需要額外旗標。
- 沿用 Issue 18 Spike 已驗證的**隔離架構**：class 欄位 `publication` 全程指向原始物件（保留完整服務給 `jumpToProgression()`／`buildTocPayloadSafely()`／`computeTotalCharacterCountInBackground()`），新增永久欄位 `effectivePublication` 只供 FXL 判斷檢查點與 `EpubNavigatorFactory` 使用。
- `epub_reader_view.dart:326` 的既有保護 bug 一併修復（防禦性修法，理論上修復後觸發條件不再出現，但仍需保留防護）。

**Tech Stack：** Kotlin（`EpubReaderView.kt`）、Dart（`epub_reader_view.dart`）、`flutter test`（Dart widget test）、真機人工驗證（`adb install`，`3CEF42ECD491687`）。

**分支：** `feature/epic-18-issue-19-fxl-metadata-override`（比照 Issue 15 `feature/epic-18-issue-15-force-fxl` 既有命名慣例）。

## Global Constraints

- 本次修改**直接進 `main`**（透過 feature branch + PR，非 throwaway Spike）。
- Kotlin 端改動全部集中在 `app/android/app/src/main/kotlin/cc/ugotit/elinkbook/EpubReaderView.kt`，不修改 `readium-kotlin-toolkit` 本身。
- `Publication.Builder`／`container` 存取需要 `@OptIn(org.readium.r2.shared.InternalReadiumApi::class)`（Issue 18 Spike 已驗證此標記存在，見 Readium `kotlin-toolkit` 3.3.0 原始碼）。
- 每次修改 Kotlin 原生程式碼後，Task 1 結尾與 Task 3 都需要完整重新建置＋安裝（`flutter build apk --debug` + `adb install -r`）驗證。
- Service Loss（進度條/頁數呈現異常）**不在本 Issue 範圍**，已另立 Issue 20 獨立排查；本 Issue 只需確保不引入超出 Issue 18 Spike 已知範圍的新退化。

---

## 檔案結構

- Modify: `app/android/app/src/main/kotlin/cc/ugotit/elinkbook/EpubReaderView.kt`（新增 `effectivePublication` 欄位＋`attachNavigator()` 內建構＋3 個 FXL 判斷檢查點改讀，見 Task 1）
- Modify: `app/lib/reader/epub_reader_view.dart:326`（`onLayoutResolved` 防禦性保護，見 Task 2）
- Modify: `app/test/reader/epub_reader_view_test.dart`（新增回歸測試，見 Task 2）

---

### Task 1：Kotlin 端核心修復——`Publication.Builder` 重建 `effectivePublication`

**Files:**
- Modify: `app/android/app/src/main/kotlin/cc/ugotit/elinkbook/EpubReaderView.kt:45-46,164,911-924,501,998,1199`

**Interfaces:**
- Consumes: Issue 18 Spike 已驗證的程式碼結構與真機證據
- Produces: `EpubReaderView.kt` 正式支援「強制 FXL 但 Readium 官方判定非 FXL」的書籍正確渲染雙頁

- [ ] **Step 1: 新增 `InternalReadiumApi` import**

找到（`EpubReaderView.kt:45`）：
```kotlin
import org.readium.r2.navigator.util.BaseActionModeCallback
import org.readium.r2.shared.publication.Layout
```
改為：
```kotlin
import org.readium.r2.navigator.util.BaseActionModeCallback
import org.readium.r2.shared.InternalReadiumApi
import org.readium.r2.shared.publication.Layout
```

- [ ] **Step 2: 新增永久欄位 `effectivePublication`**

找到 `private var publication: Publication? = null`（`EpubReaderView.kt:164` 附近），其後新增：
```kotlin
    // 修復 Issue 16：Readium 官方元件 EpubNavigatorFragment 會獨立重新讀取
    // Publication.metadata.layout 決定渲染模式，不受本專案 publication 欄位
    // 影響（見 docs/adr/0016-fxl-metadata-override-via-publication-builder.md）。
    // effectivePublication 是傳給 EpubNavigatorFactory／FXL 判斷檢查點使用的
    // 物件；publication 欄位維持指向原始物件，確保 jumpToProgression()／
    // buildTocPayloadSafely()／computeTotalCharacterCountInBackground() 等既有
    // 呼叫端維持使用完整服務。
    private var effectivePublication: Publication? = null
```

- [ ] **Step 3: `attachNavigator()` 內建構 `effectivePublication`**

找到（`EpubReaderView.kt:911-924`）：
```kotlin
        try {
            publication = openedPublication
            val navigatorFactory = EpubNavigatorFactory(publication = openedPublication)
```
改為：
```kotlin
        try {
            publication = openedPublication
            // 修復 Issue 16：Readium 官方解析器判定這本書不是 FXL 時（可能是
            // 書本 metadata 本身不規範，也可能是使用者透過「強制 FXL」（Issue 15）
            // 覆蓋了引擎分派決定，見 ADR 0016），用官方 Publication.Builder 重建
            // 一個 metadata.layout 強制為 FIXED 的物件，讓 EpubNavigatorFragment
            // 收到的 metadata 本身就是 FXL；沒有 mismatch 時原樣沿用，不重建
            // （避免對正常 FXL 書籍引入不必要的服務遺失風險，見 Issue 20）。
            @OptIn(InternalReadiumApi::class)
            val effective = if (openedPublication.metadata.layout != Layout.FIXED) {
                Publication.Builder(
                    manifest = openedPublication.manifest.copy(
                        metadata = openedPublication.manifest.metadata.copy(
                            layout = Layout.FIXED,
                        ),
                    ),
                    container = openedPublication.container,
                    servicesBuilder = Publication.ServicesBuilder(),
                ).build()
            } else {
                openedPublication
            }
            effectivePublication = effective
            val navigatorFactory = EpubNavigatorFactory(publication = effective)
```

- [ ] **Step 4: `:998` tap 熱區監聽器註冊判斷，改讀 `effective`**

找到：
```kotlin
            if (openedPublication.metadata.layout != Layout.FIXED) {
```
改為：
```kotlin
            // 修復後 effective.metadata.layout 恆為 Layout.FIXED（Step 3 已強制
            // 覆寫 mismatch 的情況），此條件理論上不再成立，原生端 tap 熱區監聽器
            // 不會再與 Dart 端 9 宮格 GestureDetector（epic-7-interaction Issue 5）
            // 同時作用（見 Issue 16 附帶發現的雙重輸入處理風險）；保留判斷式作為
            // 防禦層，不刪除。
            if (effective.metadata.layout != Layout.FIXED) {
```

- [ ] **Step 5: `applyFxlFitScale()`（`:501`）改讀 `effectivePublication`**

找到：
```kotlin
    private fun applyFxlFitScale() {
        val isFixedLayout = publication?.metadata?.layout == Layout.FIXED
```
改為：
```kotlin
    private fun applyFxlFitScale() {
        val isFixedLayout = effectivePublication?.metadata?.layout == Layout.FIXED
```

- [ ] **Step 6: `reportLayoutResolved()`（`:1199`）改讀 `effectivePublication`**

找到：
```kotlin
    private fun reportLayoutResolved() {
        val isFixedLayout = publication?.metadata?.layout == Layout.FIXED
```
改為：
```kotlin
    private fun reportLayoutResolved() {
        val isFixedLayout = effectivePublication?.metadata?.layout == Layout.FIXED
```

- [ ] **Step 7: 確認變更範圍並建置**

```bash
cd app
git diff android/app/src/main/kotlin/cc/ugotit/elinkbook/EpubReaderView.kt
flutter build apk --debug
```
確認變更範圍僅限 Step 1-6 共 6 處區塊，且建置成功無編譯錯誤。

---

### Task 2：Dart 端防禦性修法——`epub_reader_view.dart:326` 保護 `_isFixedLayout`

**Files:**
- Modify: `app/lib/reader/epub_reader_view.dart:318-328`
- Modify: `app/test/reader/epub_reader_view_test.dart`（新增回歸測試）

**Interfaces:**
- Consumes: Task 1 已完成（理論上此防護的觸發條件不再出現，但仍需驗證）
- Produces: `_isFixedLayout` 一旦變為 `true` 不再被後續 `false` 回報覆蓋

- [ ] **Step 1: 修改 `onLayoutResolved` 處理邏輯（單調鎖存，比照 Issue 15 `commit 97878c4` 對 `ReaderScreen._isFixedLayout` 的既有保護精神）**

找到（`epub_reader_view.dart:318-327`）：
```dart
      case 'onLayoutResolved':
        final args = call.arguments as Map<Object?, Object?>;
        final info = EpubLayoutInfo(
          isFixedLayout: args['isFixedLayout'] as bool,
          writingMode: (args['writingMode'] as String) == 'vertical'
              ? WritingMode.vertical
              : WritingMode.horizontal,
        );
        setState(() => _isFixedLayout = info.isFixedLayout);
        widget.onLayoutResolved?.call(info);
        break;
```
改為：
```dart
      case 'onLayoutResolved':
        final args = call.arguments as Map<Object?, Object?>;
        final info = EpubLayoutInfo(
          isFixedLayout: args['isFixedLayout'] as bool,
          writingMode: (args['writingMode'] as String) == 'vertical'
              ? WritingMode.vertical
              : WritingMode.horizontal,
        );
        // Issue 19：EpubReaderView 這個 widget 本身只會在上游已決定「這本書用
        // FXL 引擎開」時才會被建構（見 docs/adr/0016-...）。修復 Issue 16 後
        // native 端理論上不會再回報 isFixedLayout: false，但保留防禦層：一旦
        // _isFixedLayout 變為 true，不再讓後續的 false 覆蓋掉，避免 FXL 專屬
        // 9 宮格熱區疊加層（見下方 build()）無預警消失。
        if (info.isFixedLayout) {
          setState(() => _isFixedLayout = true);
        }
        widget.onLayoutResolved?.call(info);
        break;
```

- [ ] **Step 2: 新增回歸測試**

於 `app/test/reader/epub_reader_view_test.dart` 新增測試（比照既有「FXL 9 宮格熱區」測試的 pump 設置模式，見同檔 `:279-343`），流程：
1. `pumpWidget` 建構 `EpubReaderView`。
2. 模擬原生端回報 `onLayoutResolved` with `isFixedLayout: true` → 斷言 9 宮格熱區 Key 皆存在。
3. 再次模擬原生端回報 `onLayoutResolved` with `isFixedLayout: false`（模擬修復前會發生、修復後屬邊界情況的 native 回報）→ 斷言 9 宮格熱區 Key **仍然**皆存在（未被移除）。

測試名稱建議：`'FXL 9 宮格熱區：isFixedLayout 一旦變為 true，後續 native 回報 false 不會覆蓋（Issue 19 防禦性修法回歸測試）'`。

- [ ] **Step 3: 執行測試**

```bash
cd app
flutter test test/reader/epub_reader_view_test.dart
flutter analyze
```
預期：新測試通過，`flutter analyze` 顯示 `No issues found!`。

---

### Task 3：真機驗證、完整測試、文件更新、送出 PR

**Files:**
- Modify: `docs/epics/epic-18-reader-device-qa/design.md`、`docs/epics/epic-18-reader-device-qa/issues.md`、`docs/epics.md`、本計畫檔

**Interfaces:**
- Consumes: Task 1／2 已完成
- Produces: 合併回 `main` 的正式修復，Issue 16/19 狀態更新

- [ ] **Step 1: 建置並安裝至真機**

```bash
cd app
flutter build apk --debug
adb -s 3CEF42ECD491687 install -r build/app/outputs/flutter-apk/app-debug.apk
```

- [ ] **Step 2: 真機驗證雙頁排版修復**

沿用 Issue 15/17/18 已知會被誤判為流式的漫畫 EPUB（已套用「強制 FXL」）。開書、裝置轉橫向、雙頁模式設為「永遠雙頁」，觀察畫面。

預期：畫面顯示兩頁並排，翻頁行為為 spread 切換（比照 Issue 18 Spike 已驗證的結果）。

- [ ] **Step 3: 真機複驗 Issue 18 Spike 已驗證的 4 項服務項目（確認正式實作未引入超出 Issue 20 已知範圍的新退化）**

1. 頁面基本渲染（文字/圖片正常，無空白頁）
2. Slider 進度跳轉測試（25%／50%／75%）
3. `onLocatorChanged` 進度回報觀察（`adb logcat` 過濾，確認有回報，即使數值異常也屬 Issue 20 已知範圍）
4. 目錄（TOC）點擊跳轉

- [ ] **Step 4: 附帶驗證——tap 熱區是否仍有雙重處理**

點擊畫面左右兩側觀察換頁行為是否有雙重觸發或不一致現象，記錄結果（預期：Task 1 Step 4 的判斷式修復後不應再出現雙重觸發）。

- [ ] **Step 5: 一般（非強制 FXL）EPUB 書籍回歸驗證**

開啟至少一本原生判定就是 FXL（非強制覆蓋）的書籍，確認雙頁排版、翻頁、進度條、TOC 皆維持既有正常行為（驗證 Step 3「mismatch 時不重建」的分支未被誤觸發、未引入回歸）。

- [ ] **Step 6: 全套 `flutter test` 與 `flutter analyze`**

```bash
cd app
flutter test
flutter analyze
```
預期：全數通過、`No issues found!`。

- [ ] **Step 7: 依結果更新 `design.md`「Issue 19 Discovery」段落**

補上真機驗證結果摘要（Step 2-5 觀察結果）。

- [ ] **Step 8: 依結果更新 `issues.md` Issue 19／16 狀態**

Issue 19 `Status` 更新為完成，摘要真機驗證結果；Issue 16 `Status` 更新為「已由 Issue 19 完整修復並合併」。

- [ ] **Step 9: 更新 `docs/epics.md` epic-18 列摘要**

- [ ] **Step 10: Commit（於 feature branch）**

```bash
git add app/android/app/src/main/kotlin/cc/ugotit/elinkbook/EpubReaderView.kt \
        app/lib/reader/epub_reader_view.dart \
        app/test/reader/epub_reader_view_test.dart \
        docs/epics/epic-18-reader-device-qa/design.md \
        docs/epics/epic-18-reader-device-qa/issues.md \
        docs/epics.md \
        docs/epics/epic-18-reader-device-qa/plans/plan-issue-19.md
git commit -m "fix(epic-18): Issue 19 強制 FXL 書籍橫向雙頁排版修復——重建 Publication 物件覆寫 metadata.layout"
```

- [ ] **Step 11: 送出 code review（`superpowers:requesting-code-review`），依審查結果修正後開 PR**

---

## 相關佐證

- `docs/adr/0016-fxl-metadata-override-via-publication-builder.md`
- `docs/epics/epic-18-reader-device-qa/design.md`「Issue 16／17 修復方向 Discovery」「Issue 18 Spike 結論」「Issue 19 Discovery」
- `docs/epics/epic-18-reader-device-qa/issues.md` Issue 15／16／17／18／19／20
- `docs/epics/epic-18-reader-device-qa/reviews/spike-issue18-publication-builder-override.md`（本計畫 Task 1 沿用的已驗證程式碼結構）
- `app/lib/screens/reader_screen.dart:291-309`（`commit 97878c4` 既有保護模式參考）
- `app/android/app/src/main/kotlin/cc/ugotit/elinkbook/EpubReaderView.kt:45,164,501,911-924,998,1199`
- `app/lib/reader/epub_reader_view.dart:318-328`
- `app/test/reader/epub_reader_view_test.dart:279-343`（既有測試模式參考）
