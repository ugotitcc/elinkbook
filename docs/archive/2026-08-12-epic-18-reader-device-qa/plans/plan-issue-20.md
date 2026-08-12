# Issue 20：FXL 書籍新增進度條／頁尾 FAB（比照流式 EPUB）實作計劃

> **給執行者（agentic worker）的提示：** 建議使用 `superpowers:subagent-driven-development`（推薦）或 `superpowers:executing-plans` 逐工單執行本計劃。工單內的步驟以核取方塊（`- [ ]`）追蹤完成狀態。

**目標：** 修復 Issue 20 已確認的根因——FXL（`EpubReaderView`／Readium）浮動按鈕群組從未接上對應流式 EPUB `reader_foliate_progress_button`「跳頁」按鈕的功能，補齊 FAB＋Bottom Sheet＋常駐進度文字（受 `showFooter` 設定控制），頁碼資料來源改用 `readingOrder` 索引（不依賴字元估算或 `positions()`／`servicesBuilder`）。

**架構（2026-07-30 grilling 定案，見 `design.md`「Issue 20／21 修復方向 Discovery」）：**
- Kotlin 端 `onLocatorChanged` payload 新增 `pageIndex`／`totalPages` 兩個欄位：`totalPages` 直接取 `publication.readingOrder.size`（`readingOrder` 是 `Manifest` 基本屬性，不經過 `positions()`／`servicesBuilder`，`publication`〔原始物件〕即有完整資料，不需要 `effectivePublication`）；`pageIndex` 用目前 `Locator.href` 對照 `readingOrder` 索引位置取得。
- `EpubPositionInfo.pageIndex`／`totalPages` 這兩個欄位已存在（epic-17-epub-render-migration Issue 6 為流式 EPUB 新增），本次只是讓 `EpubReaderView`（FXL）也開始填入，是既有型別的加法性延伸，不需新型別。
- Dart 端 UI 完全比照流式 EPUB 既有的 `reader_foliate_progress_button`／`_buildFoliateProgressText()`／`_openFoliateProgressSheet()`／`_buildFoliateEpubFooter()` 四件套，各自新增 FXL 對應版本（`reader_fixed_layout_progress_button` 等），不共用/不重構既有流式版本（兩者 gating 條件本來就不同：`_isFixedLayout` vs `_dispatchedIsFixedLayout == false`，比照本檔案現有兩組平行維護的既有慣例）。
- 不需要新的 Dart→Kotlin 旗標傳遞管線。

**Tech Stack：** Kotlin（`EpubReaderView.kt`）、Dart（`epub_reader_view.dart`／`reader_screen.dart`）、`flutter test`（Dart widget test）、真機人工驗證（`adb install`，`3CEF42ECD491687`）。

**分支：** `feature/epic-18-issue-20-fxl-progress-footer`

## Global Constraints

- 本次修改直接進 `main`（透過 feature branch + PR）。
- 不處理 Issue 21（封面獨立顯示／頁碼配對）與 Issue 22（TOC 按鈕缺失）範圍。
- 舊有 `_buildEpubFooter()`（`reader_screen.dart:1792-1818`，字元估算、`!_isFixedLayout` 死碼）**不在本次刪除範圍**——已於 Issue 20 描述記錄為已知死碼，若要清理留待未來單獨處理，避免本次修改範圍混雜「新增功能」與「清理既有死碼」兩種性質不同的變更。
- 新按鈕 `reader_fixed_layout_progress_button` 置於 FXL 浮動按鈕群組下一個可用欄位（`top:184, right:16`，緊接現有 `reader_fixed_layout_notes_button` 的 `top:72` 與 `reader_fixed_layout_bookmark_toggle_button` 的 `top:128` 之後）。

---

## 檔案結構

- Modify: `app/android/app/src/main/kotlin/cc/ugotit/elinkbook/EpubReaderView.kt:991-1001`（`onLocatorChanged` payload 新增 `pageIndex`／`totalPages`，見 Task 1）
- Modify: `app/lib/reader/epub_reader_view.dart:336-342`（解析新欄位，見 Task 2）
- Modify: `app/lib/reader/epub_position_info.dart`（更新文件註解，見 Task 2）
- Modify: `app/lib/screens/reader_screen.dart`（新增 FXL 進度 FAB／常駐文字／Bottom Sheet／頁尾建構函式，見 Task 3）
- Modify: `app/test/reader/epub_reader_view_test.dart`（新增 payload 解析測試，見 Task 2）
- Modify: `app/test/screens/reader_screen_test.dart`（新增 UI 測試，見 Task 4）

---

### Task 1：Kotlin 端——`onLocatorChanged` 新增 `pageIndex`／`totalPages`（`readingOrder` 索引）

**Files:**
- Modify: `app/android/app/src/main/kotlin/cc/ugotit/elinkbook/EpubReaderView.kt:991-1001`

**Interfaces:**
- Consumes: 無（`publication.readingOrder` 已是既有可用屬性，見 `:1103` 既有使用範例）
- Produces: `onLocatorChanged` method channel payload 新增 `pageIndex`（`Int?`）／`totalPages`（`Int?`）兩個欄位

- [ ] **Step 1: 計算並回傳 `pageIndex`／`totalPages`**

找到：
```kotlin
            navigatorFragment?.currentLocator
                ?.onEach { locator ->
                    channel.invokeMethod(
                        "onLocatorChanged",
                        mapOf(
                            "locatorJson" to locator.toJSON().toString(),
                            "progression" to locator.locations.totalProgression,
                        ),
                    )
                }
                ?.launchIn(scope)
```
改為：
```kotlin
            navigatorFragment?.currentLocator
                ?.onEach { locator ->
                    // Issue 20：FXL 頁碼改用 readingOrder 索引，不依賴 positions()／
                    // servicesBuilder 服務層（見 docs/epics/epic-18-reader-device-qa/
                    // design.md「Issue 20／21 修復方向 Discovery」）。readingOrder 是
                    // Manifest 基本屬性，publication（原始物件，非 effectivePublication）
                    // 即有完整資料。
                    val readingOrder = publication?.readingOrder
                    val pageIndex = readingOrder
                        ?.indexOfFirst { it.href == locator.href }
                        ?.takeIf { it >= 0 }
                    val totalPages = readingOrder?.size
                    channel.invokeMethod(
                        "onLocatorChanged",
                        mapOf(
                            "locatorJson" to locator.toJSON().toString(),
                            "progression" to locator.locations.totalProgression,
                            "pageIndex" to pageIndex,
                            "totalPages" to totalPages,
                        ),
                    )
                }
                ?.launchIn(scope)
```

- [ ] **Step 2: 建置確認無編譯錯誤**

```bash
cd app
flutter build apk --debug
```

---

### Task 2：Dart 端——解析新欄位，更新文件註解，新增測試

**Files:**
- Modify: `app/lib/reader/epub_reader_view.dart:336-342`
- Modify: `app/lib/reader/epub_position_info.dart`
- Modify: `app/test/reader/epub_reader_view_test.dart`

**Interfaces:**
- Consumes: Task 1 已完成（Kotlin 端開始送出 `pageIndex`／`totalPages`）
- Produces: `EpubReaderView.onLocatorChanged` 回呼的 `EpubPositionInfo` 正確帶有 `pageIndex`／`totalPages`

- [ ] **Step 1: `epub_reader_view.dart` 解析新欄位**

找到（`:336-342`）：
```dart
      case 'onLocatorChanged':
        final args = call.arguments as Map<Object?, Object?>;
        widget.onLocatorChanged?.call(EpubPositionInfo(
          locatorJson: args['locatorJson'] as String,
          progression: (args['progression'] as num?)?.toDouble(),
        ));
        break;
```
改為：
```dart
      case 'onLocatorChanged':
        final args = call.arguments as Map<Object?, Object?>;
        widget.onLocatorChanged?.call(EpubPositionInfo(
          locatorJson: args['locatorJson'] as String,
          progression: (args['progression'] as num?)?.toDouble(),
          pageIndex: args['pageIndex'] as int?,
          totalPages: args['totalPages'] as int?,
        ));
        break;
```

- [ ] **Step 2: 更新 `epub_position_info.dart` 文件註解**

找到「`[EpubReaderView]（Readium）永遠不填這兩個欄位，維持既有行為不受影響。」這句過時說明（Issue 20 之前的既有行為），改為說明 Issue 20 起 `EpubReaderView` 也會填入這兩個欄位（依 `readingOrder` 索引計算，非估算值），移除「永遠不填」的錯誤敘述。

- [ ] **Step 3: 新增 payload 解析測試**

於 `app/test/reader/epub_reader_view_test.dart` 新增測試，模擬原生端 `onLocatorChanged` 回報含 `pageIndex`／`totalPages` 的 payload，斷言 `onLocatorChanged` 回呼收到的 `EpubPositionInfo` 正確帶有這兩個欄位（比照既有 `onLocatorChanged` 相關測試的 mock 設置模式）。

- [ ] **Step 4: 執行測試**

```bash
cd app
flutter test test/reader/epub_reader_view_test.dart
flutter analyze
```

---

### Task 3：`reader_screen.dart`——新增 FXL 進度 FAB／常駐文字／Bottom Sheet

**Files:**
- Modify: `app/lib/screens/reader_screen.dart:1533-1552`（新增 FAB 按鈕，緊接既有 `reader_fixed_layout_notes_button` 區塊）
- Modify: `app/lib/screens/reader_screen.dart:1682-1711`（新增常駐進度文字，緊接既有流式 EPUB 進度文字區塊之前，比照其結構）
- Modify: `app/lib/screens/reader_screen.dart`（新增 `_buildFixedLayoutProgressText()`／`_openFixedLayoutProgressSheet()`／`_buildFixedLayoutEpubFooter()` 三個方法，緊接既有 `_buildFoliateProgressText()`／`_openFoliateProgressSheet()`／`_buildFoliateEpubFooter()` 之後）

**Interfaces:**
- Consumes: Task 1／2 已完成（`_epubPositionInfo.pageIndex`／`totalPages` 對 FXL 書籍不再是 `null`）
- Produces: FXL 書籍可透過 FAB 開啟跳頁 Bottom Sheet；`showFooter` 設定控制常駐進度文字顯示

- [ ] **Step 1: 新增 FAB 按鈕**

找到既有 `reader_fixed_layout_notes_button` 區塊結尾（`reader_screen.dart:1533-1552`），其後新增：
```dart
            if (_isFixedLayout && _chromeVisible)
              Positioned(
                top: 184,
                right: 16,
                child: ClipOval(
                  child: Container(
                    color: Colors.black54,
                    child: IconButton(
                      key: const Key('reader_fixed_layout_progress_button'),
                      icon: const Icon(Icons.swap_vert, color: Colors.white),
                      tooltip: '跳頁',
                      onPressed: _openFixedLayoutProgressSheet,
                    ),
                  ),
                ),
              ),
```
（比照 `reader_foliate_progress_button` 的簡化決策，不額外等待 `_epubPositionInfo` 才顯示按鈕本身——見既有 `_openFoliateProgressSheet()` 文件註解。）

- [ ] **Step 2: 新增常駐進度文字**

找到既有流式 EPUB 進度文字區塊（`reader_screen.dart:1693-1711`）之前，新增對稱的 FXL 版本：
```dart
            if (_isFixedLayout &&
                (_resolved?.showFooter ?? true) &&
                (_epubPositionInfo?.totalPages ?? 0) > 0)
              (_resolved?.writingMode == WritingMode.vertical)
                  ? Positioned(
                      left: 16,
                      bottom: 16,
                      child: RotatedBox(
                        quarterTurns: 1,
                        child: _buildFixedLayoutProgressText(),
                      ),
                    )
                  : Positioned(
                      left: 0,
                      right: 0,
                      bottom: 16,
                      child: Center(child: _buildFixedLayoutProgressText()),
                    ),
```
（刻意不加 `_chromeVisible` 判斷，完全比照既有流式 EPUB 版本的既有行為——沉浸模式下仍常駐顯示。）

- [ ] **Step 3: 新增三個對應方法**

緊接既有 `_buildFoliateEpubFooter()` 之後，新增：
```dart
  /// FXL 進度純顯示（Issue 20，比照 _buildFoliateProgressText()）：pageIndex／
  /// totalPages 皆為 0-indexed 頁碼（Issue 20 起由 EpubReaderView.kt 依
  /// readingOrder 索引回報，非估算值），+1 換算為人類慣用的 1-indexed。
  Widget _buildFixedLayoutProgressText() {
    final info = _epubPositionInfo!;
    final totalPages = info.totalPages!;
    final currentPage = ((info.pageIndex ?? 0) + 1).clamp(1, totalPages);
    return Container(
      key: const Key('reader_fixed_layout_progress_text'),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: Colors.black54,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(
        '$currentPage/$totalPages',
        style: const TextStyle(color: Colors.white, fontSize: 12),
      ),
    );
  }

  /// FXL「跳頁」浮動按鈕開啟的 Bottom Sheet（Issue 20，比照
  /// _openFoliateProgressSheet()）：_epubPositionInfo 為 null 時顯示空白
  /// Sheet，比照既有簡化決策。
  void _openFixedLayoutProgressSheet() {
    final positionInfo = _epubPositionInfo;
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (_) => SafeArea(
        child: positionInfo == null
            ? const SizedBox.shrink()
            : _buildFixedLayoutEpubFooter(positionInfo),
      ),
    );
  }

  /// FXL 頁尾（Issue 20，比照 _buildFoliateEpubFooter()）：pageIndex／
  /// totalPages 來源見 _buildFixedLayoutProgressText() 說明。onPageChanged
  /// 透過既有 EpubReaderView.jumpToProgression 換算目標頁對應的全書進度
  /// 比例（近似值，非精確反解頁碼，與 _buildFoliateEpubFooter 的既有作法
  /// 相同）。
  Widget _buildFixedLayoutEpubFooter(EpubPositionInfo info) {
    final totalPages = info.totalPages ?? 0;
    if (totalPages <= 0) return const SizedBox.shrink();
    final currentPage = ((info.pageIndex ?? 0) + 1).clamp(1, totalPages);
    return ReaderFooter(
      currentPage: currentPage,
      totalPages: totalPages,
      onPageChanged: (page1Indexed) {
        final progression =
            totalPages > 0 ? (page1Indexed - 1) / totalPages : 0.0;
        EpubReaderView.jumpToProgression(_epubReaderViewKey, progression);
      },
    );
  }
```

- [ ] **Step 4: `flutter analyze` 確認無警告**

```bash
cd app
flutter analyze
```

---

### Task 4：Widget 測試

**Files:**
- Modify: `app/test/screens/reader_screen_test.dart`

**Interfaces:**
- Consumes: Task 3 已完成
- Produces: 新 UI 的自動化測試覆蓋

- [ ] **Step 1: 新增測試——按鈕存在且可點擊**

比照既有 `reader_fixed_layout_notes_button`／`reader_fixed_layout_bookmark_toggle_button` 測試模式（`app/test/screens/reader_screen_test.dart:2150-2490` 一帶），新增：FXL 書籍、`_chromeVisible` 為 `true` 時，`Key('reader_fixed_layout_progress_button')` 存在；點擊後開啟 Bottom Sheet，內含 `ReaderFooter`。

- [ ] **Step 2: 新增測試——常駐進度文字受 `showFooter` 控制**

模擬 `onLocatorChanged` 回報含 `pageIndex`／`totalPages` 的 `EpubPositionInfo`，斷言 `showFooter: true` 時 `Key('reader_fixed_layout_progress_text')` 顯示正確頁碼文字（`"$currentPage/$totalPages"`）；`showFooter: false` 時不顯示。

- [ ] **Step 3: 新增測試——直排時使用 `RotatedBox`**

比照既有流式 EPUB「直排時進度以 RotatedBox 顯示於左下角」測試（`reader_screen_test.dart` 內既有同名模式），驗證 FXL 直排時常駐進度文字同樣正確旋轉。

- [ ] **Step 4: 執行測試**

```bash
cd app
flutter test test/screens/reader_screen_test.dart
flutter analyze
```

---

### Task 5：真機驗證、文件更新、送出 PR

**Files:**
- Modify: `docs/epics/epic-18-reader-device-qa/design.md`、`docs/epics/epic-18-reader-device-qa/issues.md`、`docs/epics.md`、本計畫檔

**Interfaces:**
- Consumes: Task 1-4 已完成
- Produces: 合併回 `main` 的正式修復

- [ ] **Step 1: 建置並安裝至真機**

```bash
cd app
flutter build apk --debug
adb -s 3CEF42ECD491687 install -r build/app/outputs/flutter-apk/app-debug.apk
```

- [ ] **Step 2: 真機驗證——強制 FXL 漫畫 EPUB**

沿用已知會被誤判為流式、已套用「強制 FXL」的漫畫 EPUB。開書，確認：
1. FXL 浮動按鈕群組出現「跳頁」按鈕，點擊開啟 Bottom Sheet，內容顯示正確目前頁／總頁數（對照書本實際頁數，非估算值）。
2. 拖曳 Slider／輸入頁碼可正確跳頁。
3. 開啟閱讀設定「頁尾」開關，常駐進度文字正確顯示/隱藏。
4. 直排模式下常駐進度文字正確旋轉顯示於左下角。

- [ ] **Step 3: 真機驗證——一般原生判定 FXL 書籍回歸**

開啟至少一本原生判定就是 FXL（非強制覆蓋）的書籍，重複 Step 2 驗證項目，確認行為一致。

- [ ] **Step 4: 全套測試**

```bash
cd app
flutter test
flutter analyze
```

- [ ] **Step 5: 依結果更新 `design.md`「Issue 20／21 修復方向 Discovery」段落**

- [ ] **Step 6: 依結果更新 `issues.md` Issue 20 狀態**

- [ ] **Step 7: 更新 `docs/epics.md` epic-18 列摘要**

- [ ] **Step 8: Commit（於 feature branch）**

```bash
git add app/android/app/src/main/kotlin/cc/ugotit/elinkbook/EpubReaderView.kt \
        app/lib/reader/epub_reader_view.dart \
        app/lib/reader/epub_position_info.dart \
        app/lib/screens/reader_screen.dart \
        app/test/reader/epub_reader_view_test.dart \
        app/test/screens/reader_screen_test.dart \
        docs/epics/epic-18-reader-device-qa/design.md \
        docs/epics/epic-18-reader-device-qa/issues.md \
        docs/epics.md \
        docs/epics/epic-18-reader-device-qa/plans/plan-issue-20.md
git commit -m "feat(epic-18): Issue 20 FXL 新增進度條/頁尾 FAB，頁碼改用 readingOrder 索引"
```

- [ ] **Step 9: 送出 code review（`superpowers:requesting-code-review`），依審查結果修正後開 PR**

---

## 相關佐證

- `docs/epics/epic-18-reader-device-qa/design.md`「Issue 20／21 修復方向 Discovery」
- `docs/epics/epic-18-reader-device-qa/issues.md` Issue 20
- `app/lib/screens/reader_screen.dart:1533-1552,1666-1711,1854-1919`（流式 EPUB／FXL 既有按鈕群組與 `_buildFoliate*` 系列既有實作，本計劃比照對象）
- `app/lib/reader/epub_position_info.dart`（`pageIndex`／`totalPages` 既有型別定義）
- `app/android/app/src/main/kotlin/cc/ugotit/elinkbook/EpubReaderView.kt:991-1001,1103`（`onLocatorChanged` 既有實作、`readingOrder` 既有使用範例）
- `app/test/screens/reader_screen_test.dart:2150-2490`（既有 FXL 按鈕測試模式參考）
