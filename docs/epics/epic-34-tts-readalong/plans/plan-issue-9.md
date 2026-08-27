# Issue 9：`ReaderScreen` 正式接線——真實 `SystemTtsProvider` 注入開書流程 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 讓使用者安裝正式建置的 APK、開啟 Foliate 格式書籍後，能看到並使用 Issue 2 已完成的朗讀播放/暫停按鈕——目前 `ReaderScreen` 雖然接受 `ttsProvider` 參數，但唯一的正式呼叫端 `library_screen.dart` 從未實際建構並傳入，導致功能合併後對使用者不可見、也無法真機驗證。

**Architecture:** 不新增任何型別或 UI，純粹補齊既有「App 級依賴逐層往下傳」的接線鏈：`main()` 建構一個真實 `SystemTtsProvider()` → 傳入 `ElinkBookApp` 建構參數 → `ElinkBookApp.build()` 塞進既有的 `LibraryReaderFeatureRepositories` bundle → `LibraryScreen` 開書時（`_openBook()`）與分類篩選自我遞迴（`_openGroupFilteredView()`）兩處轉送給 `ReaderScreen.ttsProvider`。整條路徑比照 `bookmarksRepository`/`highlightsRepository`/`notesRepository` 既有可選（nullable）參數模式，未提供時行為不變、零回歸。

**Tech Stack:** 沿用 Issue 2 已引入的 `flutter_tts`（`SystemTtsProvider` 內部依賴），本 Issue 不新增任何套件相依。

**Spec:** `docs/epics/epic-34-tts-readalong/issues.md`「Issue 9」；`docs/epics/epic-34-tts-readalong/reviews/review-issue-2-code.md`（發現本缺口的審查記錄）。

## Global Constraints

- **不新增任何 UI 視覺元件**——沿用 Issue 2 已完成的陽春播放/暫停按鈕，正式 Mini Player UI 是 Issue 6 範圍。
- **不重複實作 CBZ 排除邏輯**——`ReaderScreen` 內部已依格式判斷停用播放按鈕（Issue 2），本 Issue 只需確保正式呼叫端「一律」傳入同一個 `ttsProvider`，不依書籍格式做條件式判斷要不要傳。
- 沿用既有 nullable bundle 模式：`ttsProvider` 為 `null` 時功能不啟用，行為等同本 Issue 之前，零回歸。
- **已知但刻意不修的相鄰缺口**：`library_screen.dart` 第 618-623 行（`_openGroupFilteredView()` 自我遞迴）目前用「逐欄位轉送」而非整包轉送 `LibraryReaderFeatureRepositories`，且已經漏轉 `layoutPresetRepository`/`bookReaderPrefsRepository` 兩個既有欄位——這是 Issue 9 之前就存在、與 TTS 無關的既有缺口，本計畫比照該處既有的逐欄位風格加入 `ttsProvider` 一行，**不**順手把這兩個既有缺口一併修掉或改成整包轉送（範圍外變更，若要修請另開工單）。

---

### Task 1：`LibraryReaderFeatureRepositories` 新增 `ttsProvider` 欄位，`library_screen.dart` 兩處轉送

**Files:**
- Modify: `app/lib/screens/library_screen_dependencies.dart`
- Modify: `app/lib/screens/library_screen.dart:451-473`（`_openBook()`）
- Modify: `app/lib/screens/library_screen.dart:610-656`（`_openGroupFilteredView()`）
- Test: `app/test/screens/library_screen_test.dart`

**Interfaces:**
- Consumes：既有 `TtsProvider`（`app/lib/reader/tts_provider.dart`）、既有 `ReaderScreen.ttsProvider` 建構參數（Issue 2 已定義）、測試替身 `FakeTtsProvider`（`app/test/support/fake_tts_provider.dart`，Issue 2 已建立）
- Produces：`LibraryReaderFeatureRepositories.ttsProvider`（`TtsProvider?`）——供 Task 2 的 `main.dart` 呼叫端使用

- [x] **Step 1：寫失敗測試**

在 `app/test/screens/library_screen_test.dart` 頂部 import 區塊（`../support/fake_notes_repository.dart` 那一行附近）新增：

```dart
import '../support/fake_tts_provider.dart';
```

在既有測試「`LibraryScreen 點開一本書後，ReaderScreen 收到的 highlightsRepository／notesRepository 正確貫穿（Issue 6 缺口修正）`」（約第 2156-2194 行）之後，新增：

```dart
  testWidgets(
      'LibraryScreen 點開一本書後，ReaderScreen 收到的 ttsProvider 正確貫穿（Issue 9 缺口修正）',
      (tester) async {
    // 使用 .txt 格式讓 ReaderScreen 命中「不支援格式」分支（純 Dart 安全
    // 路徑，不觸發 AndroidView），比照本檔案既有的貫穿驗證測試手法——本
    // 測試只關心建構參數是否正確貫穿，與實際閱讀器渲染無關。
    final book = _testBook(
      id: '1',
      title: '紅樓夢',
      author: '曹雪芹',
      filePath: 'content://example/1.txt',
    );
    final ttsProvider = FakeTtsProvider();

    await tester.pumpWidget(
      MaterialApp(
        home: LibraryScreen(
          repository: FakeLibraryRepository(initialBooks: [book]),
          importService: FakeBookImportService(),
          prefsManager: prefsManager,
          readerFeatureRepositories: LibraryReaderFeatureRepositories(
            ttsProvider: ttsProvider,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('book_item_1')));
    await tester.pumpAndSettle();

    final readerScreen = tester.widget<ReaderScreen>(find.byType(ReaderScreen));
    expect(readerScreen.ttsProvider, same(ttsProvider),
        reason: 'LibraryScreen._openBook() 修正前，ttsProvider 從未貫穿給 '
            'ReaderScreen，一律為 null（見 issues.md Issue 9 背景）');
  });
```

**審查修訂（`reviews/review-plan-issue-9.md` Important）**：`_openGroupFilteredView()`（分類篩選自我遞迴路徑）的 `ttsProvider` 轉送先前沒有對稱測試涵蓋。在同一個既有測試「`LibraryScreen 透過分類篩選路徑（_openGroupFilteredView）開書後，ReaderScreen 收到的 syncCheckpointTrigger 與外層一致（epic-8-sync Issue 10）`」（約第 2994-3052 行）之後，新增：

```dart
  testWidgets(
      'LibraryScreen 透過分類篩選路徑（_openGroupFilteredView）開書後，'
      'ReaderScreen 收到的 ttsProvider 與外層一致（Issue 9 缺口修正）',
      (tester) async {
    final book = _testBook(
      id: '1',
      title: '紅樓夢',
      author: '曹雪芹',
      groupName: '奇幻',
      filePath: 'content://example/1.txt',
    );
    final ttsProvider = FakeTtsProvider();

    await tester.pumpWidget(
      MaterialApp(
        home: LibraryScreen(
          repository: FakeLibraryRepository(initialBooks: [book]),
          importService: FakeBookImportService(),
          prefsManager: prefsManager,
          readerFeatureRepositories: LibraryReaderFeatureRepositories(
            ttsProvider: ttsProvider,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('group_tile_奇幻')));
    await tester.pumpAndSettle();

    final filteredScreenFinder = _filteredLibraryScreenFinder('奇幻');
    final filteredScreen = tester.widget<LibraryScreen>(filteredScreenFinder);
    expect(filteredScreen.readerFeatureRepositories.ttsProvider,
        same(ttsProvider),
        reason: '_openGroupFilteredView() 未把 ttsProvider 貫穿給下一層 '
            'LibraryScreen');

    await tester.tap(find.descendant(
      of: filteredScreenFinder,
      matching: find.byKey(const Key('book_item_1')),
    ));
    await tester.pumpAndSettle();

    final readerScreen = tester.widget<ReaderScreen>(find.byType(ReaderScreen));
    expect(readerScreen.ttsProvider, same(ttsProvider),
        reason: '透過分類篩選路徑開書，ReaderScreen 收到的 ttsProvider 應與外層 '
            '一致');
  });
```

- [x] **Step 2：跑測試確認失敗**

```
flutter test test/screens/library_screen_test.dart --plain-name "ttsProvider"
```

Expected：編譯失敗（`LibraryReaderFeatureRepositories` 沒有名為 `ttsProvider` 的具名參數），或相關 `same(ttsProvider)` 斷言因實際值為 `null` 而失敗（視 Dart 分析器是否先擋在編譯階段而定，兩者皆代表測試正確反映目前缺口）；篩選出的兩個新測試（`_openBook()` 路徑與 `_openGroupFilteredView()` 路徑）皆應失敗。

- [x] **Step 3：實作最小改動**

`app/lib/screens/library_screen_dependencies.dart`：在檔案頂部 import 區塊新增（依現有字母序排在 `notes_repository.dart` 之後）：

```dart
import '../reader/notes_repository.dart';
import '../reader/tts_provider.dart';
```

（其餘既有 import 不動；現行檔案字母序為 `layout_preset_repository.dart` 在前、`notes_repository.dart` 在後，`tts_provider.dart` 接續插在 `notes_repository.dart` 之後、`remote/opds_client.dart` 之前即可，如上方程式碼片段所示。）

在 `LibraryReaderFeatureRepositories` 類別新增欄位與建構參數：

```dart
@immutable
class LibraryReaderFeatureRepositories {
  final BookmarksRepository? bookmarksRepository;
  final HighlightsRepository? highlightsRepository;
  final NotesRepository? notesRepository;
  final CustomFontsRepository? customFontsRepository;
  final LayoutPresetRepository? layoutPresetRepository;
  final BookReaderPrefsRepository? bookReaderPrefsRepository;
  final TtsProvider? ttsProvider;

  const LibraryReaderFeatureRepositories({
    this.bookmarksRepository,
    this.highlightsRepository,
    this.notesRepository,
    this.customFontsRepository,
    this.layoutPresetRepository,
    this.bookReaderPrefsRepository,
    this.ttsProvider,
  });
}
```

`app/lib/screens/library_screen.dart` 的 `_openBook()`（約第 451-473 行），在 `syncCheckpointTrigger:` 那一行之後新增一行：

```dart
              syncCheckpointTrigger: widget.syncDependencies.syncCheckpointTrigger,
              ttsProvider: widget.readerFeatureRepositories.ttsProvider,
            ),
```

`app/lib/screens/library_screen.dart` 的 `_openGroupFilteredView()`（約第 618-623 行），在既有逐欄位轉送區塊新增一行（比照該處既有風格，不改成整包轉送，理由見 Global Constraints）：

```dart
              readerFeatureRepositories: LibraryReaderFeatureRepositories(
                bookmarksRepository: widget.readerFeatureRepositories.bookmarksRepository,
                highlightsRepository: widget.readerFeatureRepositories.highlightsRepository,
                notesRepository: widget.readerFeatureRepositories.notesRepository,
                customFontsRepository: widget.readerFeatureRepositories.customFontsRepository,
                ttsProvider: widget.readerFeatureRepositories.ttsProvider,
              ),
```

- [x] **Step 4：跑測試確認通過**

```
flutter test test/screens/library_screen_test.dart
```

Expected：全數 PASS（含新增測試與既有測試零回歸）。

- [x] **Step 5：Commit**

```
git add app/lib/screens/library_screen_dependencies.dart app/lib/screens/library_screen.dart app/test/screens/library_screen_test.dart
git commit -m "feat(epic-34): LibraryReaderFeatureRepositories 新增 ttsProvider 並貫穿 ReaderScreen（Issue 9 Task 1）"
```

---

### Task 2：`main.dart` 建構真實 `SystemTtsProvider` 並貫穿至 `ElinkBookApp`

**Files:**
- Modify: `app/lib/main.dart`
- Test: `app/test/elinkbook_app_wiring_test.dart`

**Interfaces:**
- Consumes：Task 1 的 `LibraryReaderFeatureRepositories.ttsProvider`；既有 `SystemTtsProvider`（`app/lib/reader/system_tts_provider.dart`，Issue 2 已定義，預設建構子 `SystemTtsProvider()` 內部自行建立 `FlutterTts()`，不需外部傳入）
- Produces：`ElinkBookApp.ttsProvider`（`TtsProvider?` 建構參數）——本 Issue 最後一棒，之後無其他 Task 依賴它

- [x] **Step 1：寫失敗測試**

`app/test/elinkbook_app_wiring_test.dart` 頂部 import 區塊新增：

```dart
import 'support/fake_tts_provider.dart';
```

在既有測試「`ElinkBookApp 組裝出的 LibraryScreen，每個 bundle 欄位與獨立參數皆與傳入值同一實例`」內：宣告區塊（約第 68-91 行）新增一行：

```dart
    final ttsProvider = FakeTtsProvider();
```

`ElinkBookApp(...)` 建構區塊（約第 94-119 行）新增一行：

```dart
        thumbnailCache: thumbnailCache,
        isMobileDataConnection: isMobileDataConnection,
        ttsProvider: ttsProvider,
        initialTheme: AppTheme.dark,
```

斷言區塊（`readerFeatureRepositories.bookReaderPrefsRepository` 那組斷言之後，約第 141 行之後）新增：

```dart
    expect(libraryScreen.readerFeatureRepositories.ttsProvider,
        same(ttsProvider));
```

- [x] **Step 2：跑測試確認失敗**

```
flutter test test/elinkbook_app_wiring_test.dart
```

Expected：編譯失敗（`ElinkBookApp` 建構子沒有名為 `ttsProvider` 的具名參數）。

- [x] **Step 3：實作最小改動**

`app/lib/main.dart` 頂部 import 區塊新增（現行字母序中 `reader/reading_position_repository.dart` 是 `reader/` 底下最後一個 import，接續插在其後、`remote/opds_client.dart` 之前）：

```dart
import 'reader/reading_position_repository.dart';
import 'reader/system_tts_provider.dart';
import 'reader/tts_provider.dart';
```

（`reading_position_repository.dart` 該行已存在，僅新增後兩行。）

`main()` 函式內，在既有 `layoutPresetRepository` 等 repository 建構區塊（約第 82-86 行）之後新增一行：

```dart
  final layoutPresetRepository = LayoutPresetRepository(repository.database);
  // epic-34-tts-readalong Issue 9：SystemTtsProvider 預設建構子內部會自行
  // 建立 FlutterTts()，App 層級不需要另外管理其生命週期或提供假物件。
  final ttsProvider = SystemTtsProvider();
```

`runApp(ElinkBookApp(...))` 呼叫區塊（約第 141-170 行），在 `bookReaderPrefsRepository: prefsRepository,` 之後新增一行：

```dart
      bookReaderPrefsRepository: prefsRepository,
      ttsProvider: ttsProvider,
```

`ElinkBookApp` 類別的欄位宣告（約第 179-184 行）新增一行：

```dart
  final BookReaderPrefsRepository? bookReaderPrefsRepository;
  final TtsProvider? ttsProvider;
```

`ElinkBookApp` 建構子（約第 203-231 行）新增一行：

```dart
    this.bookReaderPrefsRepository,
    this.ttsProvider,
```

`_ElinkBookAppState.build()` 內的 `LibraryReaderFeatureRepositories(...)` 區塊（約第 292-299 行）新增一行：

```dart
        readerFeatureRepositories: LibraryReaderFeatureRepositories(
          bookmarksRepository: widget.bookmarksRepository,
          highlightsRepository: widget.highlightsRepository,
          notesRepository: widget.notesRepository,
          customFontsRepository: widget.customFontsRepository,
          layoutPresetRepository: widget.layoutPresetRepository,
          bookReaderPrefsRepository: widget.bookReaderPrefsRepository,
          ttsProvider: widget.ttsProvider,
        ),
```

- [x] **Step 4：跑測試確認通過**

```
flutter test test/elinkbook_app_wiring_test.dart
```

Expected：全數 PASS。

- [x] **Step 5：Commit**

```
git add app/lib/main.dart app/test/elinkbook_app_wiring_test.dart
git commit -m "feat(epic-34): main.dart 建構真實 SystemTtsProvider 並貫穿至 ElinkBookApp（Issue 9 Task 2）"
```

---

### Task 3：`AndroidManifest.xml` 補上 `flutter_tts` 所需的 `TTS_SERVICE` 套件可見性宣告

**Files:**
- Modify: `app/android/app/src/main/AndroidManifest.xml`

**Interfaces:**
- Consumes：無
- Produces：無（純 Android 平台設定，Dart 層無介面變化）

**背景（審查 `reviews/review-plan-issue-9.md` Critical，執行前必讀）：** `flutter_tts` 套件官方文件明載：「Apps targeting Android 11 that use text-to-speech should declare `TextToSpeech.Engine.INTENT_ACTION_TTS_SERVICE` in the `queries` elements of their manifest」。本專案 `targetSdk` 已解析為 36（遠高於 Android 11 的套件可見性限制門檻），`AndroidManifest.xml` 目前的 `<queries>` 區塊（第 66-71 行）只宣告了 `PROCESS_TEXT`，沒有 `TTS_SERVICE`。若不補上，`TextToSpeech` 綁定語音引擎的隱式 Intent 查詢會被系統擋下——播放按鈕本身會正常顯示（顯示與否只看 `ttsProvider != null`，與這項設定無關），但實際按下播放極可能靜默失敗或拋出例外，直接牴觸 Issue 9「真機能看到並使用朗讀」的核心目標。Task 1／Task 2 的 Dart 接線即使全部正確，沒有這個宣告，真機驗收清單第 3 點仍會失敗。

- [x] **Step 1：修改 manifest**

`app/android/app/src/main/AndroidManifest.xml` 現有 `<queries>` 區塊（第 66-71 行）：

```xml
    <queries>
        <intent>
            <action android:name="android.intent.action.PROCESS_TEXT"/>
            <data android:mimeType="text/plain"/>
        </intent>
    </queries>
```

改為：

```xml
    <!-- epic-34-tts-readalong Issue 9：flutter_tts 官方文件要求 targeting
         Android 11+ 的 App 須在 queries 宣告 TTS_SERVICE，否則
         TextToSpeech 綁定語音引擎的隱式 Intent 查詢會被套件可見性限制擋下，
         SystemTtsProvider.synthesize() 在真機上會靜默失敗。 -->
    <queries>
        <intent>
            <action android:name="android.intent.action.PROCESS_TEXT"/>
            <data android:mimeType="text/plain"/>
        </intent>
        <intent>
            <action android:name="android.intent.action.TTS_SERVICE"/>
        </intent>
    </queries>
```

- [x] **Step 2：確認 manifest 仍是合法 XML、建置成功**

```
flutter build apk --debug
```

Expected：建置成功（`flutter analyze`／`flutter test` 不涵蓋 Android manifest 內容，本步驟是本檔案唯一的自動化防呆——XML 語法錯誤或標籤未正確關閉會在此直接建置失敗）。

- [x] **Step 3：Commit**

```
git add app/android/app/src/main/AndroidManifest.xml
git commit -m "fix(epic-34): AndroidManifest.xml 補上 TTS_SERVICE queries 宣告（Issue 9 Task 3，審查 Critical）"
```

---

### Task 4：全量驗證、更新 Issue 追蹤文件、真機驗收清單

**Files:**
- Modify: `docs/epics/epic-34-tts-readalong/issues.md`（Issue 9 驗收標準勾選）
- Modify: `docs/epics/epic-34-tts-readalong/epic.md`（開發記錄）
- Modify: `docs/epics.md`（全域看板備註）

**Interfaces:**
- Consumes：Task 1／Task 2 完成的接線、Task 3 補上的 manifest 宣告
- Produces：無（本 Task 為收尾與文件更新，不產出程式介面）

- [x] **Step 1：全專案分析與測試**

```
flutter analyze
flutter test
```

Expected：`flutter analyze` 顯示 `No issues found!`；`flutter test` 全數 PASS，較 Issue 2 合併時的基準線多 3 個測試（Task 1 新增 2 個：`_openBook()`／`_openGroupFilteredView()` 兩條路徑；Task 2 新增 1 個），零回歸。

- [x] **Step 2：更新 `issues.md` Issue 9 驗收標準勾選狀態**

將 Issue 9 的四條驗收標準（`library_screen.dart` 接線完成、真機可見播放鈕、既有測試零回歸、`flutter analyze`／`flutter test` 全數通過）依實際完成狀況打勾；**真機驗證那一條保留未勾選**，待人類實際安裝 APK 驗證後再手動勾選（本計畫的自動化步驟無法驗證真機行為）。

- [x] **Step 3：補一筆 `epic.md` 開發記錄**

依既有風格（單一長段落，日期前綴）在 `## 開發記錄` 段落末尾接續新增一句，說明 Issue 9 已完成接線、通過 `flutter analyze`／`flutter test`、待真機驗證播放鈕可見性。

- [x] **Step 4：更新 `docs/epics.md` 全域看板備註**

將 epic-34 這一列備註改為簡潔摘要，例如「Issue 9 已完成接線，待真機驗證」。

- [x] **Step 5：Commit**

```
git add docs/epics/epic-34-tts-readalong/issues.md docs/epics/epic-34-tts-readalong/epic.md docs/epics.md
git commit -m "docs(epic-34): 更新 Issue 9 驗收標準與看板備註（接線完成，待真機驗證）"
```

---

## 真機驗收清單（Self-Review 用，非額外自動化步驟）

比照 Issue 2「測試策略總結」既有慣例，以下項目無法自動化，須人類合併前手動驗證一次：

1. 重新建置並安裝 APK（`flutter build apk --debug` 或既有簽章流程）。
2. 開啟一本 EPUB／KF8／TXT／MD 格式書籍，確認畫面上出現朗讀播放/暫停按鈕（Issue 2 既有陽春樣式）。
3. 按下播放，確認能聽到系統語音逐句朗讀；按暫停/繼續確認狀態切換正確；章節唸完確認自動停止——這一步同時驗證 Task 3 的 `TTS_SERVICE` manifest 宣告是否生效（若漏做 Task 3，播放鍵會顯示正常但按下去極可能靜默失敗）。
4. 開啟一本 CBZ 書籍，確認朗讀按鈕存在但為明確停用狀態（非隱藏），符合 Issue 2 既有驗收標準。

## Self-Review 檢查結果

- **Spec coverage**：`issues.md` Issue 9 四條驗收標準逐條對應：Task 1／2 完成接線（第 1 條）、Task 3 補上真機播放實際可用所需的 manifest 宣告＋真機驗收清單涵蓋可見性與可用性（第 2 條）、Task 1／2 皆附既有測試零回歸驗證（第 3 條）、Task 4 涵蓋 `flutter analyze`／`flutter test`（第 4 條）。無缺口。
- **Placeholder scan**：全文搜尋未發現「TBD」/「之後補」等空話；所有程式碼步驟皆有完整程式碼區塊與確切行號。
- **Type consistency**：`TtsProvider`／`SystemTtsProvider`（Issue 2 既有定義）在 Task 1（`LibraryReaderFeatureRepositories.ttsProvider`）、Task 2（`ElinkBookApp.ttsProvider`）呼叫端型別一致；`FakeTtsProvider`（Issue 2 既有測試替身）在 Task 1／Task 2 測試中匯入路徑與建構方式一致（皆為無參數建構子 `FakeTtsProvider()`）。
- **已知範圍外事項**（已於 Global Constraints 明列，不在本計畫修復範圍）：`_openGroupFilteredView()` 既有的 `layoutPresetRepository`/`bookReaderPrefsRepository` 漏轉發缺口。
