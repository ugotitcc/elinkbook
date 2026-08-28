# Epic 34 Issue 11 — 長段落缺乏終止標點時朗讀失敗 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 部分自製 EPUB（經文/善書類排版，整段/整章以全形空格「　」分隔語句、完全不使用「。！？」等標點）朗讀時完全無聲（原生端回報 `ERROR_OUTPUT -8`）的問題修好——三層防禦：(1) `main.js` 切句規則新增次要邊界（空白/換行），(2) Dart 端依 `getMaxSpeechInputLength()` 查得的引擎上限做最後一道硬性長度切分防線，(3) 單一段落合成/播放仍然失敗時跳過並接續下一段，不讓整個朗讀流程卡死。

**Architecture:** `main.js window.buildTtsSegments()` 的切句迴圈新增「次要邊界」判斷（找不到主要標點、且累積長度已達門檻時，遇到空白也切句），不改變既有「優先用標點」行為。`TtsProvider` 抽象介面新增 `getMaxInputLength()`，`SystemTtsProvider` 透過 `flutter_tts` 既有的 `getMaxSpeechInputLength` 屬性實作；`TtsController.play()` 在 `loadSegments()`／`lookupStartIndex()` 之後、寫入 `_segments` 之前，依這個上限把任何仍然過長的段落硬切成多個子段落（沿用同一個原始 CFI），並把 `lookupStartIndex` 算出的（切分前）索引正確換算到切分後清單的對應位置。`TtsController._playCurrentSegment()` 的失敗處理從「立即整個重設回 idle」改為迴圈跳過失敗段落、嘗試下一段，記錄診斷 log（比照 `SystemTtsProvider._log()` 既有的 `ReaderConsoleLog` 慣例），直到成功播放某一段或已無下一段可嘗試。

**Tech Stack:** Flutter/Dart（`TtsController`／`TtsProvider`／`SystemTtsProvider`）、`flutter_tts` 套件既有 `getMaxSpeechInputLength` API、`main.js`（本專案自有橋接腳本，非 vendored 檔案，可自由修改，見 ADR 0011／0013）、`flutter_test`（純 Dart 單元測試＋main.js 字串斷言 regression guard，比照既有慣例）。

**Spec：** `docs/epics/epic-34-tts-readalong/issues.md` Issue 11（第 317-341 行）。

## Global Constraints

- `main.js` 的變更**不得改變既有「優先用標點切句」行為**——次要邊界只在一段文字已經很長（達門檻）且遍尋不到主要標點時才生效，既有跨標籤句子測試樣本必須零回歸。
- `main.js` 是本專案自有橋接腳本（非 vendored `foliate-js` 原始碼），可自由修改，不受 ADR 0011「不修改 vendored 檔案」限制；但仍不得引入較新的 ES 內建方法（見 `app/tool/check_foliate_es_compat.js` 掃描範圍，本計畫用到的 API 皆為既有 `RegExp.test`/字串 `slice`/迴圈等基礎語法，不觸發風險)。
- `getMaxInputLength()` 為 `TtsProvider` 抽象介面新增方法，兩個既有實作者（`SystemTtsProvider`、測試用 `FakeTtsProvider`）皆須同步更新，否則 `flutter analyze` 會報缺少覆寫。
- 診斷 log 一律比照 `SystemTtsProvider._log()` 既有慣例，同時寫入 `debugPrint()` 與 `ReaderConsoleLog.add()`（`app/lib/reader/reader_console_log.dart`），訊息加上 `[TTS Diagnostic]` 前綴，讓真機除錯不必接電腦查看。
- **誠實測試邊界**（比照 `plan-issue-2.md` 既有慣例明文記載）：`flutter test` 環境下 `FoliateReaderView` 的 `_controller` 恆為 `null`，無法驗證 `main.js buildTtsSegments()` 對真實章節 DOM 的切句結果是否正確——本計畫的 main.js regression guard 測試只驗證原始碼字串結構（常數/判斷式存在），**不**驗證實際切句輸出；真正的正確性（用 `tmp/2023大狀元經典會考經訓彙整.epub` 真機驗證不再出現 `ERROR_OUTPUT -8`）留給 Task 4 完成後的真機手動驗證（見本計畫「測試策略總結」）。
- `flutter analyze`／`flutter test` 全數通過，既有跨標籤句子／`<rt>` 過濾測試（`app/test/reader/foliate_bridge_codec_test.dart` `parseTtsSegments` group）零回歸。

---

### Task 1：`main.js buildTtsSegments()` 新增次要切分邊界

**Files:**
- Modify: `app/android/app/src/main/assets/foliate/main.js:639-665`（`window.buildTtsSegments()` 內的切句迴圈）
- Test: `app/test/reader/foliate_reader_view_test.dart`（新增 regression guard group，緊接在既有「main.js 朗讀段反向查找 regression guard（epic-34-tts-readalong Issue 4）」group 之後、「main.js 安全視窗跟隨翻頁...（Issue 8）」group 之前，即第 1497-1499 行之間）

**Interfaces:**
- Consumes：無（本 Task 為 `main.js` 內部邏輯調整，不涉及 Dart↔JS 橋接契約變化——`window.buildTtsSegments()` 對外的呼叫簽章、`onTtsSegmentsReady` 回呼的 JSON 結構皆不變）。
- Produces：`buildTtsSegments()` 產生的 `segments` 陣列在「一段文字明顯過長且缺乏主要標點」時，會比修改前多切出幾個子段落——供 Task 3（Dart 端硬性長度上限防線）作為前置防禦，減少真的需要硬切的情況。

- [ ] **Step 1：寫失敗測試**

在 `app/test/reader/foliate_reader_view_test.dart` 第 1497 行（既有「main.js 朗讀段反向查找 regression guard」group 結尾 `});`）之後、第 1499 行（「main.js 安全視窗跟隨翻頁...」group）之前，新增：

```dart
  group(
      'main.js 朗讀段長段落次要邊界切分 regression guard '
      '（epic-34-tts-readalong Issue 11）', () {
    late String mainJsSource;

    setUpAll(() {
      mainJsSource = File('android/app/src/main/assets/foliate/main.js')
          .readAsStringSync();
    });

    test('buildTtsSegments 定義次要邊界門檻常數與空白字元判斷', () {
      expect(
        mainJsSource
            .contains('const TTS_SECONDARY_BOUNDARY_MIN_LENGTH = 200'),
        isTrue,
        reason: 'main.js 內找不到 TTS_SECONDARY_BOUNDARY_MIN_LENGTH——長'
            '段落缺乏標點時的次要邊界防線缺失，完全不使用標點的長段落'
            '（例如經文/善書類排版整段以「　」分隔語句）會被切成單一超長'
            '段落，超出 Android TextToSpeech 單次合成輸入長度上限'
            '（ERROR_OUTPUT -8）。',
      );
      expect(
        mainJsSource.contains('const secondaryBoundary = /\\s/'),
        isTrue,
        reason: 'JS 的 \\s 已涵蓋全形空格 U+3000（Unicode Space_Separator '
            '類別），不需要另外處理全形/半形空白的差異。',
      );
    });

    test('切分判斷式優先採用主要標點，次要邊界只在累積長度達門檻且無主要標點時才生效',
        () {
      expect(
        mainJsSource
            .contains('const isPrimaryBoundary = terminators.test(fullText[i])'),
        isTrue,
      );
      expect(
        mainJsSource.contains('!isPrimaryBoundary &&'),
        isTrue,
        reason: '次要邊界判斷式必須以「非主要標點」為第一個條件，確保只要'
            '遇到主要標點就一律優先切句，不受次要邊界邏輯影響。',
      );
      expect(
        mainJsSource
            .contains('(i - start) >= TTS_SECONDARY_BOUNDARY_MIN_LENGTH &&'),
        isTrue,
        reason: '次要邊界必須同時滿足「累積長度已達門檻」才生效，否則會'
            '提早在一般正常長度的句子中間就用空白切句，改變既有「優先用'
            '標點切句」的行為，跨標籤句子等既有測試樣本會被破壞。',
      );
      expect(
        mainJsSource
            .contains('if (isPrimaryBoundary || isSecondaryBoundary || isLast) {'),
        isTrue,
        reason: '切句判斷式必須同時涵蓋主要標點／次要邊界／章節結尾三種'
            '情況，缺一即會改變既有行為或無法處理長段落。',
      );
    });
  });
```

- [ ] **Step 2：執行測試確認失敗**

Run: `flutter test test/reader/foliate_reader_view_test.dart --plain-name "main.js 朗讀段長段落次要邊界切分 regression guard"`（於 `app/` 目錄下執行）

Expected: FAIL——`main.js` 內尚未有 `TTS_SECONDARY_BOUNDARY_MIN_LENGTH` 等字串，兩個 `test` 皆失敗。

- [ ] **Step 3：寫最小實作**

修改 `app/android/app/src/main/assets/foliate/main.js` 第 639-645 行，原本：

```js
    const terminators = /[。！？；.!?;]/
    const segments = []
    let start = 0
    let segmentIndex = 0
    for (let i = 0; i < fullText.length; i++) {
      const isLast = i === fullText.length - 1
      if (terminators.test(fullText[i]) || isLast) {
```

改為：

```js
    const terminators = /[。！？；.!?;]/
    // 次要切分邊界（epic-34-tts-readalong Issue 11，issues.md「來源」
    // 欄位真機重現紀錄：部分自製 EPUB 整段/整章以全形空格「　」分隔
    // 語句、完全不使用「。！？」等標點，導致單一朗讀段長達近 2 萬字，
    // 超出 Android TextToSpeech 單次合成輸入長度上限，回報
    // ERROR_OUTPUT -8）。找不到主要標點、且目前累積片段長度已達
    // TTS_SECONDARY_BOUNDARY_MIN_LENGTH 時，遇到空白字元（JS \s 已
    // 涵蓋全形空格 U+3000／半形空白／換行，不需要另外處理）也視為可
    // 切分點。門檻刻意設得比一般正常句子長（既有跨標籤句子測試樣本
    // 遠低於此門檻），確保「優先用標點切句」這個既有行為不受影響——
    // 只有真的很長、又缺乏標點時才會退而求其次觸發次要邊界。
    const TTS_SECONDARY_BOUNDARY_MIN_LENGTH = 200
    const secondaryBoundary = /\s/
    const segments = []
    let start = 0
    let segmentIndex = 0
    for (let i = 0; i < fullText.length; i++) {
      const isLast = i === fullText.length - 1
      const isPrimaryBoundary = terminators.test(fullText[i])
      const isSecondaryBoundary = !isPrimaryBoundary &&
        (i - start) >= TTS_SECONDARY_BOUNDARY_MIN_LENGTH &&
        secondaryBoundary.test(fullText[i])
      if (isPrimaryBoundary || isSecondaryBoundary || isLast) {
```

迴圈其餘部分（`rangeStart` 空白跳過、`trimmed`、CFI 計算、`segments.push`、`start = i + 1`）完全不動。

- [ ] **Step 4：執行測試確認通過**

Run: `flutter test test/reader/foliate_reader_view_test.dart --plain-name "main.js 朗讀段長段落次要邊界切分 regression guard"`（於 `app/` 目錄下執行）

Expected: PASS

- [ ] **Step 5：執行 ES 相容性掃描（比照 Issue 2 Task 4 既有慣例）**

Run（於 `app/` 目錄下）：
```bash
node tool/check_foliate_es_compat.js
```

Expected：結束碼 `0`（乾淨）。本 Task 新增的程式碼只用了 `RegExp.test`／字串索引／算術比較／迴圈等基礎語法，不含任何較新的 ES 內建方法，理論上不會觸發掃描。

- [ ] **Step 6：執行本檔案完整測試，確認零回歸**

Run: `flutter test test/reader/foliate_reader_view_test.dart`（於 `app/` 目錄下執行）

Expected: 全數 PASS。

- [ ] **Step 7：Commit**

```bash
git add app/android/app/src/main/assets/foliate/main.js app/test/reader/foliate_reader_view_test.dart
git commit -m "feat(epic-34): Issue 11 main.js 長段落次要邊界切分（空白/換行）"
```

---

### Task 2：`TtsProvider.getMaxInputLength()` 介面新增與 `SystemTtsProvider` 實作

**Files:**
- Modify: `app/lib/reader/tts_provider.dart:5-16`（`TtsProvider` 抽象介面新增方法）
- Modify: `app/lib/reader/system_tts_provider.dart:22-26`（`SystemTtsProvider` 新增實作，緊接在 `getAvailableVoices()` 之後）
- Modify: `app/test/support/fake_tts_provider.dart`（新增對應欄位與實作，供既有／新測試使用）
- Test: `app/test/reader/system_tts_provider_test.dart`（新增測試，緊接在既有最後一則測試之後，第 207 行結尾 `}` 之前）

**Interfaces:**
- Consumes：`flutter_tts` 套件既有 `Future<int?> get getMaxSpeechInputLength`（`FlutterTts` 類別既有屬性，`SystemTtsProvider._flutterTts` 已持有實例）。
- Produces：`Future<int?> TtsProvider.getMaxInputLength()`——`null` 代表引擎未回報或不支援查詢此限制。供 Task 3 的 `TtsController.play()` 呼叫。`FakeTtsProvider` 新增可寫入的 `int? maxInputLength`（預設 `null`，供測試設定回傳值）。

- [ ] **Step 1：寫失敗測試**

在 `app/test/reader/system_tts_provider_test.dart` 第 207 行（檔案結尾 `}` 之前，緊接在最後一個既有 `test(...)` 的結尾 `});` 之後）新增：

```dart
  test('getMaxInputLength() 回傳 getMaxSpeechInputLength 平台呼叫結果', () async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      if (call.method == 'getMaxSpeechInputLength') {
        return 4000;
      }
      return null;
    });

    final provider = SystemTtsProvider(flutterTts: FlutterTts());
    final result = await provider.getMaxInputLength();

    expect(result, 4000);
  });

  test('getMaxInputLength() 於平台呼叫拋出例外時回傳 null（不拋出例外）', () async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      if (call.method == 'getMaxSpeechInputLength') {
        throw PlatformException(code: 'error', message: '模擬平台呼叫失敗');
      }
      return null;
    });

    final provider = SystemTtsProvider(flutterTts: FlutterTts());
    final result = await provider.getMaxInputLength();

    expect(result, isNull);
  });
```

- [ ] **Step 2：執行測試確認失敗**

Run: `flutter test test/reader/system_tts_provider_test.dart --plain-name "getMaxInputLength"`（於 `app/` 目錄下執行）

Expected: FAIL——編譯錯誤（`SystemTtsProvider` 尚未有 `getMaxInputLength` 方法，`TtsProvider` 介面也還沒有）。

- [ ] **Step 3：寫最小實作**

修改 `app/lib/reader/tts_provider.dart`，在 `getAvailableVoices()` 宣告之後新增：

```dart
abstract class TtsProvider {
  Future<List<TtsVoice>> getAvailableVoices();

  /// 目前引擎單次合成文字長度上限（epic-34-tts-readalong Issue 11）。
  /// `null` 代表引擎未回報或不支援查詢此限制——呼叫端此時不套用硬性
  /// 長度上限防線，僅依賴 main.js buildTtsSegments() 既有的標點/次要
  /// 邊界切句規則（見 Task 1）。Phase 1 僅 SystemTtsProvider 有意義的
  /// 實作（透過 flutter_tts getMaxSpeechInputLength，Android 專屬
  /// API）；Phase 2/3 的雲端/端側神經語音 Provider 若無對應概念，可
  /// 直接回傳 null。
  Future<int?> getMaxInputLength();

  /// 合成 [text] 為音訊檔並回傳結果。音訊管線統一走檔案合成（見
  /// design.md 決策 9），不支援直接輸出喇叭的即時朗讀。
  Future<TtsSynthesisResult> synthesize(
    String text, {
    required TtsVoice voice,
    double speed = 1.0,
    double pitch = 1.0,
  });
}
```

修改 `app/lib/reader/system_tts_provider.dart`，在 `getAvailableVoices()` 方法（第 22-26 行）之後、`_log()` 方法之前新增：

```dart
  /// 查詢目前引擎單次合成文字長度上限（epic-34-tts-readalong Issue 11）。
  /// 呼叫失敗（例如平台方法未實作、逾時）時回傳 `null` 而非拋出例外——
  /// 呼叫端（`TtsController`）把 `null` 視為「未知上限，不套用硬性長度
  /// 上限防線」，比照本類別其餘防禦性查詢（`getEngines`/`getDefaultEngine`）
  /// 既有的容錯風格。
  @override
  Future<int?> getMaxInputLength() async {
    try {
      return await _flutterTts.getMaxSpeechInputLength;
    } catch (e) {
      _log('Failed to query getMaxSpeechInputLength: $e');
      return null;
    }
  }
```

修改 `app/test/support/fake_tts_provider.dart`，在 `nextSynthesizeCompleter` 欄位宣告之後新增：

```dart
  /// 測試設定後，[getMaxInputLength] 回傳這個值（預設 `null`，代表未
  /// 設定任何上限，等同引擎未回報——既有測試不需要修改即可維持原行為，
  /// 因為 [TtsController] 在 `null` 時不套用硬性長度上限防線，見
  /// epic-34-tts-readalong Issue 11）。
  int? maxInputLength;

  @override
  Future<int?> getMaxInputLength() async => maxInputLength;
```

- [ ] **Step 4：執行測試確認通過**

Run: `flutter test test/reader/system_tts_provider_test.dart --plain-name "getMaxInputLength"`（於 `app/` 目錄下執行）

Expected: PASS

- [ ] **Step 5：執行本檔案完整測試與 `flutter analyze`，確認零回歸**

Run（於 `app/` 目錄下）：
```bash
flutter test test/reader/system_tts_provider_test.dart
flutter analyze
```

Expected: 測試全數 PASS；`flutter analyze` 顯示 `No issues found!`（確認 `FakeTtsProvider`／`SystemTtsProvider` 兩個既有實作者皆已補上新方法，沒有「缺少覆寫」的編譯錯誤——`TtsController` 尚未呼叫 `getMaxInputLength()`，Task 3 才會接上，故本 Task 完成後這個方法暫時尚無呼叫端，`flutter analyze` 不會因此報 unused 警告，因為它是 public 介面方法）。

- [ ] **Step 6：Commit**

```bash
git add app/lib/reader/tts_provider.dart app/lib/reader/system_tts_provider.dart app/test/support/fake_tts_provider.dart app/test/reader/system_tts_provider_test.dart
git commit -m "feat(epic-34): Issue 11 TtsProvider 新增 getMaxInputLength()"
```

---

### Task 3：`TtsController` 硬性長度上限切分（消費 Task 2 的 `getMaxInputLength()`）

**Files:**
- Modify: `app/lib/reader/tts_controller.dart`（`play()` 方法內 idle 分支＋新增私有頂層函式）
- Test: `app/test/reader/tts_controller_test.dart`（新增測試，插入位置見下方 Step 1）

**Interfaces:**
- Consumes：`TtsProvider.getMaxInputLength()`（Task 2 產物，`Future<int?>`）。
- Produces：`TtsController.play()` 內部行為變化——`_segments`／`_currentIndex` 在寫入前會先經過硬性長度上限切分；不新增任何 public 方法或欄位。

- [ ] **Step 1：寫失敗測試**

在 `app/test/reader/tts_controller_test.dart` 第 986 行（既有最後一則測試 `resyncHighlight() 於 disposed 後為 no-op` 的結尾 `});`）之後、第 987 行（`main()` 結尾 `}`）之前，新增：

```dart
  group('硬性長度上限切分（epic-34-tts-readalong Issue 11）', () {
    test('provider.getMaxInputLength() 回傳 null 時不切分，既有行為不變',
        () async {
      final controller = buildController();
      provider.maxInputLength = null;

      await controller.play();

      expect(controller.segments.length, segments.length);
      expect(provider.synthesizedTexts, ['第一句。']);
    });

    test('段落文字長度超過上限時硬切為多個子段落，各自依序合成', () async {
      final longText = List.generate(25, (i) => '字').join();
      final controller = buildController(segs: [
        TtsSegmentCfi(
          segmentId: '0',
          cfi: 'epubcfi(/6/4!/1:0)',
          text: longText,
        ),
      ]);
      provider.maxInputLength = 10;

      await controller.play();

      // 25 字、上限 10 字，應切成 3 段（10+10+5）。
      expect(controller.segments.length, 3);
      expect(controller.segments[0].text.length, 10);
      expect(controller.segments[1].text.length, 10);
      expect(controller.segments[2].text.length, 5);
      // 子段落沿用原始 CFI（精確子範圍 CFI 需回到 JS 端重新計算，
      // 超出本硬性防線的職責範圍）。
      expect(controller.segments[0].cfi, 'epubcfi(/6/4!/1:0)');
      expect(controller.segments[1].cfi, 'epubcfi(/6/4!/1:0)');
      expect(controller.segments[2].cfi, 'epubcfi(/6/4!/1:0)');
      expect(provider.synthesizedTexts.first.length, 10);
      expect(controller.currentIndex, 0);
    });

    test(
        'lookupStartIndex 回傳的（切分前）索引，在切分後正確換算到對應'
        '子段落的起始位置', () async {
      final longText = List.generate(25, (i) => '字').join();
      final loaded = [
        const TtsSegmentCfi(
          segmentId: '0',
          cfi: 'epubcfi(/6/4!/1:0)',
          text: '短句。', // 3 字，不切分
        ),
        TtsSegmentCfi(
          segmentId: '1',
          cfi: 'epubcfi(/6/4!/2:0)',
          text: longText, // 25 字，上限 10 字時切成 3 段
        ),
        const TtsSegmentCfi(
          segmentId: '2',
          cfi: 'epubcfi(/6/4!/3:0)',
          text: '最後。', // 3 字，不切分
        ),
      ];
      provider = FakeTtsProvider();
      player = FakeTtsAudioPlayer();
      provider.maxInputLength = 10;
      final controller = TtsController(
        provider: provider,
        player: player,
        loadSegments: () async => loaded,
        lookupStartIndex: (segs) async => 2, // 指向切分前的第三個原始段落
      );

      await controller.play();

      // 切分後清單：[短句, 長句子段1, 長句子段2, 長句子段3, 最後]，
      // 原始索引 2（「最後。」）換算後應是切分後索引 4。
      expect(controller.segments.length, 5);
      expect(controller.currentIndex, 4);
      expect(provider.synthesizedTexts, ['最後。']);
    });
  });
```

- [ ] **Step 2：執行測試確認失敗**

Run: `flutter test test/reader/tts_controller_test.dart --plain-name "硬性長度上限切分"`（於 `app/` 目錄下執行）

Expected: FAIL——`provider.maxInputLength` 尚未存在於 `FakeTtsProvider`（此屬 Task 2 產物，若 Task 2 已先完成則此屬性已存在，這裡改為在 `play()` 未套用切分邏輯，`controller.segments.length` 斷言失敗）。

- [ ] **Step 3：寫最小實作**

修改 `app/lib/reader/tts_controller.dart` 的 `play()` 方法（idle 分支），原本：

```dart
      final startIndex =
          lookupStartIndex == null ? 0 : await lookupStartIndex!(loaded);
      if (_disposed || generation != _playGeneration) return;
      // _segments／_currentIndex 一起賦值、放在兩個 await 之後、確認世代
      // 仍有效才寫入——避免中途被中止的呼叫留下「_segments 已覆寫、但
      // 從未真正開始播放」的孤兒狀態（同一個 review Important #1／#2 的
      // 修法延伸）。
      _segments = loaded;
      _currentIndex =
          (startIndex >= 0 && startIndex < _segments.length) ? startIndex : 0;
```

改為：

```dart
      final startIndex =
          lookupStartIndex == null ? 0 : await lookupStartIndex!(loaded);
      if (_disposed || generation != _playGeneration) return;
      // 硬性長度上限防線（epic-34-tts-readalong Issue 11）：main.js
      // buildTtsSegments() 已有標點/次要邊界切句規則（見 issues.md Issue
      // 11 設計要點第 1 點），但無法涵蓋所有極端排版，這裡是最後一道
      // 防線——依引擎回報的實際上限，把任何仍然過長的段落硬切成多個
      // 子段落再個別合成。maxInputLength 為 null（引擎未回報上限）時
      // _capSegmentsToMaxLength 直接原樣回傳，不套用任何切分。
      final maxInputLength = await provider.getMaxInputLength();
      if (_disposed || generation != _playGeneration) return;
      final capped = _capSegmentsToMaxLength(loaded, maxInputLength);
      // _segments／_currentIndex 一起賦值、放在所有 await 之後、確認世代
      // 仍有效才寫入——避免中途被中止的呼叫留下「_segments 已覆寫、但
      // 從未真正開始播放」的孤兒狀態（同一個 review Important #1／#2 的
      // 修法延伸）。
      _segments = capped.segments;
      final clampedStartIndex =
          (startIndex >= 0 && startIndex < loaded.length) ? startIndex : 0;
      _currentIndex = capped.startOffsets[clampedStartIndex];
```

在 `TtsController` 類別定義之後（檔案結尾 `}` 之前，`class TtsController extends ChangeNotifier { ... }` 結束後）新增一個私有頂層函式：

```dart
/// 把 [original] 清單中任何 `text.length` 超過 [maxLength] 的段落，依
/// 字數硬切為多個子段落（沿用同一個原始 CFI——精確的子範圍 CFI 需要
/// 回到 JS 端重新計算，超出本硬性防線的職責範圍；子段落只共用同一個
/// 原始 CFI，高亮在這極端情境下會維持指向整個原段落，不影響「朗讀能
/// 正常繼續進行」這個核心目標，見 epic-34-tts-readalong Issue 11）。
/// [maxLength] 為 `null` 或 `<= 0`（引擎未回報上限）時原樣回傳，不套用
/// 任何切分。回傳值的 `startOffsets[i]` 是 [original] 第 `i` 個段落
/// （切分前）對應到切分後清單中「第一個子段落」的索引，供 `play()` 把
/// `lookupStartIndex` 算出的（切分前）索引正確換算到切分後的位置。
({List<TtsSegmentCfi> segments, List<int> startOffsets}) _capSegmentsToMaxLength(
  List<TtsSegmentCfi> original,
  int? maxLength,
) {
  if (maxLength == null || maxLength <= 0) {
    return (
      segments: original,
      startOffsets: List<int>.generate(original.length, (i) => i),
    );
  }
  final result = <TtsSegmentCfi>[];
  final startOffsets = <int>[];
  for (final segment in original) {
    startOffsets.add(result.length);
    final text = segment.text;
    if (text.length <= maxLength) {
      result.add(segment);
      continue;
    }
    var chunkIndex = 0;
    for (var start = 0; start < text.length; start += maxLength) {
      final end =
          (start + maxLength < text.length) ? start + maxLength : text.length;
      result.add(TtsSegmentCfi(
        segmentId: '${segment.segmentId}_$chunkIndex',
        cfi: segment.cfi,
        text: text.substring(start, end),
      ));
      chunkIndex++;
    }
  }
  return (segments: result, startOffsets: startOffsets);
}
```

- [ ] **Step 4：執行測試確認通過**

Run: `flutter test test/reader/tts_controller_test.dart --plain-name "硬性長度上限切分"`（於 `app/` 目錄下執行）

Expected: PASS

- [ ] **Step 5：執行本檔案完整測試，確認零回歸**

Run: `flutter test test/reader/tts_controller_test.dart`（於 `app/` 目錄下執行）

Expected: 全數 PASS——`FakeTtsProvider.maxInputLength` 預設 `null`，所有既有測試（未主動設定這個欄位）不套用任何切分，行為與修改前完全一致。

- [ ] **Step 6：Commit**

```bash
git add app/lib/reader/tts_controller.dart app/test/reader/tts_controller_test.dart
git commit -m "feat(epic-34): Issue 11 TtsController 硬性長度上限切分防線"
```

---

### Task 4：`TtsController._playCurrentSegment()` 失敗時跳過並接續下一段

**Files:**
- Modify: `app/lib/reader/tts_controller.dart`（`import` 新增＋ `_playCurrentSegment()` 方法重寫）
- Test: `app/test/reader/tts_controller_test.dart`（修改 2 則既有測試＋新增 3 則測試，見下方 Step 1）

**Interfaces:**
- Consumes：無新介面（沿用既有 `provider`／`player`／`_segments`／`_currentIndex`／`_segmentGeneration`）。
- Produces：`_playCurrentSegment()` 對外可觀察行為變化——單一段落合成/播放失敗時，會自動嘗試下一段（若有），而非立即整個重設回 `idle`；失敗時寫入 `ReaderConsoleLog` 診斷紀錄。

**⚠️ 這個 Task 會讓 2 則既有測試斷言不再成立，須同步修改（非本 Task 的迴歸，是刻意的行為變更，見下方說明）**：`tts_controller_test.dart` 目前有 2 則測試用「唯一一次呼叫 `play()`、`provider.nextSynthesizeError` 設在唯一/第一段」的方式驗證「合成失敗立即重設回 idle」，且測試固定使用模組層級 2 段的 `segments` 常數。`FakeTtsProvider.nextSynthesizeError` 是**一次性**（拋出後自動清空，見 `fake_tts_provider.dart` 第 11-13 行既有註解），修改後的行為是「第一段失敗被跳過、嘗試第二段時 `nextSynthesizeError` 已經清空、第二段合成成功」——這正是本 Task 要做到的效果，但會讓這兩則測試原本斷言的「重設回 idle」不再成立。修法是把這兩則測試改用**只有一段**的清單（此時跳過後已無下一段可嘗試，才會真的重設回 idle，測試意圖不變、只是情境更精確），並新增測試涵蓋「還有下一段可跳過」的新行為。

- [ ] **Step 1：寫失敗測試（修改 2 則既有測試＋新增 3 則測試）**

修改 `app/test/reader/tts_controller_test.dart` 第 145-157 行，原本：

```dart
  test('play() 時 synthesize() 拋出例外，重設回 idle 而非卡在 playing（審查 Important #1）',
      () async {
    final controller = buildController();
    provider.nextSynthesizeError = const TtsSynthesisException('模擬引擎失敗');

    await controller.play();

    expect(controller.status, TtsPlaybackStatus.idle);
    expect(controller.currentIndex, -1);
    expect(controller.segments, isEmpty);
    // player.loadFile()/play() 不應該被呼叫——合成本身就失敗了。
    expect(player.callLog, isEmpty);
  });
```

改為：

```dart
  test(
      'play() 時唯一段落 synthesize() 拋出例外、已無下一段可嘗試，重設回 idle '
      '而非卡在 playing（審查 review-issue-2-code.md Important #1；'
      'epic-34-tts-readalong Issue 11 起僅適用於「無下一段可跳過」情境，'
      '見下一則測試）', () async {
    final controller = buildController(segs: const [
      TtsSegmentCfi(segmentId: '0', cfi: 'epubcfi(/6/4!/1:0)', text: '第一句。'),
    ]);
    provider.nextSynthesizeError = const TtsSynthesisException('模擬引擎失敗');

    await controller.play();

    expect(controller.status, TtsPlaybackStatus.idle);
    expect(controller.currentIndex, -1);
    expect(controller.segments, isEmpty);
    // player.loadFile()/play() 不應該被呼叫——合成本身就失敗了，且已無
    // 下一段可嘗試。
    expect(player.callLog, isEmpty);
  });

  test(
      'play() 時第一段 synthesize() 拋出例外，自動跳過並成功合成播放下一段'
      '（epic-34-tts-readalong Issue 11：單一段落失敗不得讓整個朗讀流程'
      '卡死）', () async {
    final controller = buildController(); // 預設兩段
    provider.nextSynthesizeError = const TtsSynthesisException('模擬引擎失敗');

    await controller.play();

    expect(controller.status, TtsPlaybackStatus.playing);
    expect(controller.currentIndex, 1);
    // 第一段合成失敗（被跳過，未呼叫 loadFile/play）、第二段合成成功
    // 並播放。
    expect(provider.synthesizedTexts, ['第一句。', '第二句。']);
    expect(player.callLog, ['loadFile', 'play']);
  });

  test(
      'play() 段落合成失敗被跳過時，寫入 ReaderConsoleLog 診斷紀錄'
      '（epic-34-tts-readalong Issue 11）', () async {
    ReaderConsoleLog.clear();
    final controller = buildController();
    provider.nextSynthesizeError = const TtsSynthesisException('模擬引擎失敗');

    await controller.play();

    expect(
      ReaderConsoleLog.entries.value.any((entry) =>
          entry.contains('[TTS Diagnostic]') &&
          entry.contains('跳過並嘗試下一段')),
      isTrue,
    );
  });
```

修改 `app/test/reader/tts_controller_test.dart` 第 339-354 行，原本：

```dart
  test('play() 合成失敗重設回 idle 時，onHighlightSegment 最後收到 null', () async {
    final highlighted = <TtsSegmentCfi?>[];
    provider = FakeTtsProvider();
    player = FakeTtsAudioPlayer();
    provider.nextSynthesizeError = const TtsSynthesisException('模擬引擎失敗');
    final controller = TtsController(
      provider: provider,
      player: player,
      loadSegments: () async => segments,
      onHighlightSegment: highlighted.add,
    );

    await controller.play();

    expect(highlighted, [segments[0], null]);
  });
```

改為：

```dart
  test(
      'play() 唯一段落合成失敗、已無下一段可嘗試，重設回 idle 時 '
      'onHighlightSegment 最後收到 null（epic-34-tts-readalong Issue 11 '
      '起僅適用於「無下一段可跳過」情境，見上方「自動跳過並成功合成'
      '播放下一段」測試）', () async {
    final highlighted = <TtsSegmentCfi?>[];
    provider = FakeTtsProvider();
    player = FakeTtsAudioPlayer();
    provider.nextSynthesizeError = const TtsSynthesisException('模擬引擎失敗');
    const singleSegment = [
      TtsSegmentCfi(segmentId: '0', cfi: 'epubcfi(/6/4!/1:0)', text: '第一句。'),
    ];
    final controller = TtsController(
      provider: provider,
      player: player,
      loadSegments: () async => singleSegment,
      onHighlightSegment: highlighted.add,
    );

    await controller.play();

    expect(highlighted, [singleSegment[0], null]);
  });
```

在檔案頂部的 `import` 區塊新增（第 7 行 `import 'package:elinkbook/reader/tts_segment_cfi.dart';` 之後）：

```dart
import 'package:elinkbook/reader/reader_console_log.dart';
```

- [ ] **Step 2：執行測試確認失敗**

Run（`--name` 支援正規表示式，於 `app/` 目錄下執行）：
```bash
flutter test test/reader/tts_controller_test.dart --name "自動跳過並成功合成播放下一段|ReaderConsoleLog 診斷紀錄"
```

Expected: FAIL——目前 `_playCurrentSegment()` 一失敗就整個重設回 idle，不會嘗試下一段，也不會寫入 `ReaderConsoleLog`。（原本 145/339 行的兩則測試因為已改成單一段落情境，此時仍然 PASS，不受影響。）

- [ ] **Step 3：寫最小實作**

在 `app/lib/reader/tts_controller.dart` 頂部 `import` 區塊新增：

```dart
import 'reader_console_log.dart';
```

修改 `_playCurrentSegment()` 方法，原本：

```dart
  Future<void> _playCurrentSegment() async {
    final segment = _segments[_currentIndex];
    final generation = ++_segmentGeneration;
    try {
      _status = TtsPlaybackStatus.playing;
      onHighlightSegment?.call(segment);
      notifyListeners();
      final result = await provider.synthesize(
        segment.text,
        voice: TtsVoice.systemDefault,
        speed: _speed,
      );
      if (_disposed || generation != _segmentGeneration) return;
      await player.loadFile(result.audioFilePath);
      // 重要修復（review-issue-2-code.md Important #1）：若在 synthesize/loadFile
      // 非同步期間使用者按下了暫停鍵（_status 變更為 paused），檔案載入完成後
      // 不得再呼叫 player.play()，應維持在 paused 狀態，等待使用者下次主動按下播放鍵。
      if (_disposed || generation != _segmentGeneration) return;
      if (_status != TtsPlaybackStatus.playing) return;
      await player.play();
    } catch (_) {
      if (_disposed || generation != _segmentGeneration) return;
      _suppressExpiryTimer?.cancel();
      _suppressNextPositionChange = false;
      _status = TtsPlaybackStatus.idle;
      _currentIndex = -1;
      _segments = const [];
      onHighlightSegment?.call(null);
      notifyListeners();
    }
  }
```

改為：

```dart
  Future<void> _playCurrentSegment() async {
    final generation = ++_segmentGeneration;
    // epic-34-tts-readalong Issue 11：單一段落合成/播放失敗時不得讓整個
    // 朗讀流程卡死或靜默無反應（例如遇到超出 TTS 引擎輸入長度上限、或
    // 原生端回報 ERROR_OUTPUT 的段落）——改為迴圈跳過失敗段落並嘗試
    // 下一段，直到成功播放某一段，或已無下一段可嘗試（視同章節自然
    // 播放完畢，走既有「重設回 idle」路徑）。
    while (true) {
      if (_disposed || generation != _segmentGeneration) return;
      if (_currentIndex < 0 || _currentIndex >= _segments.length) {
        // 已跳過所有剩餘段落（或呼叫當下本來就已經沒有下一段）：視同
        // 播放自然結束，重設回 idle（比照既有 _handleSegmentCompleted()
        // 章節結尾分支）。
        _suppressExpiryTimer?.cancel();
        _suppressNextPositionChange = false;
        _status = TtsPlaybackStatus.idle;
        _currentIndex = -1;
        _segments = const [];
        onHighlightSegment?.call(null);
        notifyListeners();
        return;
      }
      final segment = _segments[_currentIndex];
      try {
        _status = TtsPlaybackStatus.playing;
        onHighlightSegment?.call(segment);
        notifyListeners();
        final result = await provider.synthesize(
          segment.text,
          voice: TtsVoice.systemDefault,
          speed: _speed,
        );
        if (_disposed || generation != _segmentGeneration) return;
        await player.loadFile(result.audioFilePath);
        // 重要修復（review-issue-2-code.md Important #1）：若在 synthesize/loadFile
        // 非同步期間使用者按下了暫停鍵（_status 變更為 paused），檔案載入完成後
        // 不得再呼叫 player.play()，應維持在 paused 狀態，等待使用者下次主動按下播放鍵。
        if (_disposed || generation != _segmentGeneration) return;
        if (_status != TtsPlaybackStatus.playing) return;
        await player.play();
        return;
      } catch (e) {
        if (_disposed || generation != _segmentGeneration) return;
        final message = '[TTS Diagnostic] 段落索引 $_currentIndex 合成/播放'
            '失敗，跳過並嘗試下一段：$e';
        debugPrint(message);
        ReaderConsoleLog.add(message);
        _currentIndex++;
      }
    }
  }
```

- [ ] **Step 4：執行測試確認通過**

Run: `flutter test test/reader/tts_controller_test.dart`（於 `app/` 目錄下執行）

Expected: 全數 PASS（含 Step 1 修改的 2 則既有測試＋新增的 3 則測試）。

- [ ] **Step 5：執行 `flutter analyze` 與全專案 `flutter test`**

Run（於 `app/` 目錄下）：
```bash
flutter analyze
flutter test
```

Expected: `flutter analyze` 顯示 `No issues found!`；`flutter test` 全數通過（本計畫為 Issue 11 最後一個 Task，依 `CLAUDE.md`「測試執行範圍」慣例，計畫最後一個 Task 完成時須跑一次完整 `flutter test`）。特別留意 `app/test/reader/foliate_bridge_codec_test.dart` `parseTtsSegments` group（既有跨標籤句子／`<rt>` 過濾相關測試）零回歸。

- [ ] **Step 6：Commit**

```bash
git add app/lib/reader/tts_controller.dart app/test/reader/tts_controller_test.dart
git commit -m "feat(epic-34): Issue 11 TtsController 段落合成失敗改為跳過並接續下一段"
```

---

## 測試策略總結

**自動化層（本計畫 4 個 Task 已涵蓋）：**
- `main.js` 次要邊界切分邏輯：字串結構 regression guard（Task 1）——**不**驗證實際切句輸出是否正確（誠實邊界，見 Global Constraints）。
- `TtsProvider.getMaxInputLength()`／`SystemTtsProvider` 實作：平台方法呼叫成功/失敗兩種情境（Task 2）。
- `TtsController` 硬性長度上限切分：無上限不切分、超過上限正確硬切、`lookupStartIndex` 索引正確換算三種情境（Task 3）。
- `TtsController` 段落失敗跳過並接續：唯一段落失敗重設 idle、還有下一段時跳過並成功播放、診斷 log 正確寫入三種情境（Task 4）。
- 既有跨標籤句子／`<rt>` 過濾測試（`foliate_bridge_codec_test.dart` `parseTtsSegments` group）：零回歸（本計畫未觸碰 `<rt>`/`<script>` 過濾邏輯或 JSON wire 格式，僅風險評估後跑一次確認）。

**手動真機驗收清單（`app/integration_test/` 與 `flutter test` 皆涵蓋不到的部分，合併前須人工執行）：**
- 安裝含本計畫修改的 APK，開啟 `tmp/2023大狀元經典會考經訓彙整.epub`（已確認存在於儲存庫 `tmp/` 目錄，`issues.md` Issue 11「來源」欄位已用此書實際重現過原始問題），按下播放，確認：
  - 不再出現 `ERROR_OUTPUT (-8)`／完全無聲的情況。
  - 該書先前重現過「單章 17,908 字」與「單章 23,890 字」兩個問題章節皆可正常聽到朗讀內容（不要求逐字校對语音品質，只要求「有聲音、且能持續播放到章節結尾或使用者主動停止」）。
- 一般正常排版（有標點）的既有測試書籍（EPUB／TXT／MD 各挑一本），確認朗讀行為與切句斷點未受影響（Task 1 的次要邊界不應該在正常書籍上被觸發）。

---

## Self-Review（撰寫計畫後自我檢查）

**1. Spec 覆蓋度**（對照 `issues.md` Issue 11 四條驗收標準）：
- 「真機測試 `tmp/2023大狀元經典會考經訓彙整.epub`（或等效無標點長段落樣本）可正常朗讀，不再出現 `ERROR_OUTPUT (-8)`」→ Task 1（次要邊界，大幅減少觸發硬切的機會）＋ Task 3（硬性防線）＋ Task 4（單段失敗不卡死整章）三層防禦共同作用，真機驗證步驟見「測試策略總結」。
- 「既有跨標籤句子／`<rt>` 過濾測試零回歸」→ Global Constraints 明確要求，Task 1/4 皆未觸碰 `<rt>`/`<script>` 過濾邏輯或 JSON wire 格式，Task 4 Step 5 明確列為確認項目。
- 「單一段落合成失敗時能跳過並接續下一段，不卡死整個朗讀流程」→ Task 4。
- 「`flutter analyze`／`flutter test` 全數通過」→ 每個 Task 皆有對應驗證步驟，Task 4 Step 5 額外跑一次全專案完整測試。
四條皆有對應任務，無缺口。

**2. Placeholder 掃描：** 全文無「TBD」/「稍後補上」/「加上適當的錯誤處理」等字樣，所有程式碼區塊皆為可直接套用的完整內容。

**3. 型別/命名一致性：** `getMaxInputLength()`（`TtsProvider`／`SystemTtsProvider`／`FakeTtsProvider` 三處簽章一致，皆為 `Future<int?> getMaxInputLength()`）、`_capSegmentsToMaxLength()`（Task 3 定義與 Task 3 Step 3 套用點一致）、`TTS_SECONDARY_BOUNDARY_MIN_LENGTH`／`secondaryBoundary`（Task 1 main.js 定義與測試斷言字串一致）全文檢查皆一致，無命名分裂。Task 3 的 record 型別 `({List<TtsSegmentCfi> segments, List<int> startOffsets})` 在定義處與 `play()` 消費處（`capped.segments`／`capped.startOffsets[...]`）欄位名稱一致。

---

## 計畫修訂記錄（2026-08-29，依 `/superpowers:requesting-code-review`）

程式審查（`reviews/review-issue-11-code.md`，本機檔案不進版控）結論 With fixes（0 Critical／1 Important／2 Minor）。已依審查結果修訂：

- **Important #1（`main.js` 未涵蓋 issues.md 設計要點提到的「换行/段落邊界（對應 `<br>`／區塊層級標籤邊界）」）**：確認為刻意取捨，非遺漏。原因：`fullText` 組裝時單純串接各文字節點 `textContent`，不同區塊層級標籤（例如相鄰 `<p>`）之間若彼此緊鄰且內部文字無空白字元，不會產生 `secondaryBoundary` 可偵測的訊號；正確處理需要在 TreeWalker 掃描時額外比對父元素變化並插入合成邊界字元，同時避免污染 `offsetMap`／CFI range 計算，複雜度不小。已在 `main.js` `TTS_SECONDARY_BOUNDARY_MIN_LENGTH` 常數上方補上決策說明（見程式碼），並記錄於此——`TtsController` 的硬性長度上限切分（Task 3）＋段落失敗跳過並接續（Task 4）兩層防線仍保證「不會整章念不出來」這個核心驗收標準成立，即使某本書恰好完全落在本層偵測不到的情境。若之後真機回報此路徑仍有問題，再依實際案例另立工單處理。
- **Minor #1（`_capSegmentsToMaxLength()` 索引換算「指向被切分段落自身」情境缺乏直接測試）**：已採納，於 `tts_controller_test.dart`「硬性長度上限切分」group 新增第四則測試（`lookupStartIndex: (segs) async => 1`，斷言 `controller.currentIndex == 1`），驗證索引恰好指向被切分段落本身時正確換算到該段落的第一個子段落。
- **Minor #2（`getMaxInputLength()` 每次播放皆重新查詢，未快取）**：審查報告本身已標註「非必要修復」，不採納，保持現況（單次 method channel 呼叫延遲可忽略）。
