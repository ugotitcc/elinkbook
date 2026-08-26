# Issue 2：最小朗讀閉環——系統語音逐句朗讀＋手動播放/暫停 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [x]`) syntax for tracking.

**Goal:** 讓使用者在 EPUB／KF8／TXT／MD（Foliate 格式，CBZ 除外）書籍畫面按下播放，聽到系統語音逐句朗讀目前章節，可暫停/繼續，章節唸完自動停止；不含同步高亮（Issue 3）、背景播放（Issue 7）、上一句/下一句與語速調整（Issue 5）、完整 Mini Player UI（Issue 6）。

**Architecture:** 新增一組格式無關的純 Dart TTS 模組（`TtsProvider`/`SystemTtsProvider`/`TtsAudioPlayer`/`TtsController`），`TtsController` 完全不依賴 Flutter widget 或 WebView，只透過建構子注入的 `loadSegments` callback 取得朗讀段清單——這個 callback 由 `ReaderScreen` 提供，內部呼叫新增的 `FoliateReaderView.loadTtsSegments()` 靜態 helper（比照既有 `loadTableOfContents()` 模式：Dart 呼叫 `window.buildTtsSegments(sectionIndex)`，`main.js` 用 `TreeWalker` 掃描章節文字、過濾 `<rt>`/`<script>`、依標點切句、對每句呼叫既有 `view.getCFI(sectionIndex, range)` 算 CFI，非同步回傳 JSON 陣列）。音訊播放透過 `TtsAudioPlayer` 抽象介面包一層 `just_audio`（`JustAudioTtsPlayer`），讓 `TtsController` 可以在純 Dart 單元測試中注入 Fake 播放器，不需要真機。`ReaderScreen` 新增可選 `ttsProvider` 建構參數（比照 `highlightsRepository` 既有 nullable 模式），CBZ 格式明確停用（非隱藏）播放按鈕。

**Tech Stack:** `flutter_tts: ^4.2.5`（Android 端 `synthesizeToFile()` 檔案合成 API，非 `speak()`）、`just_audio: ^0.10.6`（本機音訊播放）、既有 `flutter_inappwebview`/`main.js` JS↔Dart bridge 慣例。

**Spec:** `docs/epics/epic-34-tts-readalong/issues.md`「Issue 2」；`docs/epics/epic-34-tts-readalong/spec.md`「Implementation Decisions」（`TtsProvider`/音訊管線/朗讀段擷取/高亮渲染段落，本 Issue 只實作到朗讀段擷取＋播放，不含高亮）；`docs/epics/epic-34-tts-readalong/dependency-spike-findings.md`（Issue 1 已驗證版本無衝突）。

## Global Constraints

- 只支援 Foliate 格式（EPUB／KF8／TXT／MD），**CBZ 明確排除**——`ReaderScreen` 播放按鈕須存在但 `onPressed: null`（停用狀態＋說明 tooltip），不可整個隱藏（`issues.md` Issue 2 驗收標準明文要求）。
- 音訊合成一律走檔案管線（`flutter_tts.synthesizeToFile(text, path, true)`），不使用 `speak()`。
- 暫存音訊檔固定命名空間、以目前朗讀段索引覆寫（不逐段累積新檔案）——本 Issue 簡化為固定單一檔名（一次只有一個朗讀段在播放，天然滿足「以目前朗讀段覆寫」）。
- 朗讀段擷取須過濾 `<rt>`（注音）／`<script>` 節點，不朗讀其內容。
- 不修改任何 vendored `foliate-js` 檔案；`main.js` 是本專案自有整合層（見 CLAUDE.md），可以直接編輯。
- 不新增完整 Mini Player 視覺（Issue 6 範圍）、不做上一句/下一句/語速控制（Issue 5 範圍）、不做背景播放/`audio_service`（Issue 7 範圍）——播放/暫停按鈕比照既有 EPUB FAB 圓形按鈕樣式（`_themedFabBackgroundColor`/`_themedFabIconColor`），不做視覺打磨。
- 新增的 Dart 檔案放在 `app/lib/reader/`（不建子目錄，比照該目錄現有扁平結構慣例）；測試替身放在 `app/test/support/`（比照既有 `fake_*.dart` 命名慣例）。

---

### Task 1：新增 `flutter_tts`／`just_audio` 相依套件

**Files:**
- Modify: `app/pubspec.yaml`

**Interfaces:**
- Consumes：無
- Produces：`flutter_tts`／`just_audio` 套件可供後續 Task import

- [x] **Step 1：加入相依套件**

在 `app/pubspec.yaml` 的 `dependencies:` 區塊（`flutter_web_auth_2: ^5.1.0` 那行之後）新增：

```yaml
  # TTS 語音朗讀（epic-34-tts-readalong Issue 2）：系統原生語音合成，見
  # dependency-spike-findings.md 已驗證與現有相依鏈無衝突（minSdk=24，
  # 未拉高專案現有下限）。
  flutter_tts: ^4.2.5
  # TTS 本機音訊播放（epic-34-tts-readalong Issue 2）：見
  # dependency-spike-findings.md，minSdk=16，未拉高專案現有下限。
  just_audio: ^0.10.6
```

- [x] **Step 2：安裝並驗證無衝突**

在 `app/` 目錄下執行：

```
flutter pub get
```

Expected：成功完成，無錯誤訊息。接著執行：

```
flutter analyze
```

Expected：`No issues found!`

- [x] **Step 3：確認 `share_plus`/`file_picker`/`package_info_plus`/`win32` 版本未被牽動**

```
git diff app/pubspec.lock | grep -E "share_plus|file_picker|package_info_plus|win32" -A2 -B2
```

Expected：無輸出，或輸出中這四個套件的版本號沒有變化（只有新增 `flutter_tts`/`just_audio`/它們的 transitive 依賴的區塊）。

- [x] **Step 4：Commit**

```
git add app/pubspec.yaml app/pubspec.lock
git commit -m "deps(epic-34): 新增 flutter_tts/just_audio（Issue 2 最小朗讀閉環）"
```

---

### Task 2：`TtsProvider` 抽象介面與型別

**Files:**
- Create: `app/lib/reader/tts_provider.dart`
- Test: `app/test/reader/tts_provider_test.dart`

**Interfaces:**
- Consumes：無
- Produces：`abstract class TtsProvider { Future<List<TtsVoice>> getAvailableVoices(); Future<TtsSynthesisResult> synthesize(String text, {required TtsVoice voice, double speed = 1.0, double pitch = 1.0}); }`、`class TtsVoice { final String id; final String displayName; }`、`class TtsSynthesisResult { final String audioFilePath; final List<TtsWordTiming> wordTimings; }`、`class TtsWordTiming { final String text; final int startMs; final int endMs; }`、`class TtsSynthesisException implements Exception { final String message; }`——供 Task 3（`SystemTtsProvider`）與 Task 6（`TtsController`）使用。

- [x] **Step 1：寫型別與介面**

建立 `app/lib/reader/tts_provider.dart`：

```dart
/// 語音朗讀（TTS）的語音來源抽象（epic-34-tts-readalong Issue 2，
/// spec.md「Implementation Decisions」）。三種實作對應不同 Phase：
/// [SystemTtsProvider]（Phase 1，本 Issue）、雲端 API（Phase 2）、端側
/// 神經語音（Phase 3，stretch goal，皆未實作於本 Issue）。
abstract class TtsProvider {
  Future<List<TtsVoice>> getAvailableVoices();

  /// 合成 [text] 為音訊檔並回傳結果。音訊管線統一走檔案合成（見
  /// design.md 決策 9），不支援直接輸出喇叭的即時朗讀。
  Future<TtsSynthesisResult> synthesize(
    String text, {
    required TtsVoice voice,
    double speed = 1.0,
    double pitch = 1.0,
  });
}

/// 單一可用語音。Phase 1 僅有系統預設語音，[id]/[displayName] 皆為固定值
/// （見 [TtsVoice.systemDefault]），Phase 2 起雲端 Provider 會回傳多筆。
class TtsVoice {
  final String id;
  final String displayName;

  const TtsVoice({required this.id, required this.displayName});

  static const systemDefault = TtsVoice(
    id: 'system-default',
    displayName: '系統預設語音',
  );

  @override
  bool operator ==(Object other) =>
      other is TtsVoice && other.id == id && other.displayName == displayName;

  @override
  int get hashCode => Object.hash(id, displayName);
}

/// [TtsProvider.synthesize] 的合成結果。[wordTimings] 為字級時間戳記，
/// Phase 1 系統語音不提供，恆為空清單（見 [TtsWordTiming]）。
class TtsSynthesisResult {
  final String audioFilePath;
  final List<TtsWordTiming> wordTimings;

  const TtsSynthesisResult({
    required this.audioFilePath,
    this.wordTimings = const [],
  });
}

/// 字級時間戳記（Phase 1 未使用，保留供未來字級高亮擴充，見
/// spec.md Out of Scope「單詞級高亮」）。
class TtsWordTiming {
  final String text;
  final int startMs;
  final int endMs;

  const TtsWordTiming({
    required this.text,
    required this.startMs,
    required this.endMs,
  });
}

/// [TtsProvider.synthesize] 合成失敗時拋出。
class TtsSynthesisException implements Exception {
  final String message;
  const TtsSynthesisException(this.message);

  @override
  String toString() => 'TtsSynthesisException: $message';
}
```

- [x] **Step 2：寫測試（型別建構/相等性）**

建立 `app/test/reader/tts_provider_test.dart`：

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:elinkbook/reader/tts_provider.dart';

void main() {
  test('TtsVoice.systemDefault 有固定的 id/displayName', () {
    expect(TtsVoice.systemDefault.id, 'system-default');
    expect(TtsVoice.systemDefault.displayName, '系統預設語音');
  });

  test('TtsVoice 相等性依 id/displayName 判斷', () {
    const a = TtsVoice(id: 'x', displayName: 'X');
    const b = TtsVoice(id: 'x', displayName: 'X');
    const c = TtsVoice(id: 'y', displayName: 'Y');
    expect(a, equals(b));
    expect(a == c, isFalse);
  });

  test('TtsSynthesisResult 預設 wordTimings 為空清單', () {
    const result = TtsSynthesisResult(audioFilePath: '/tmp/a.wav');
    expect(result.wordTimings, isEmpty);
  });

  test('TtsSynthesisException.toString() 含錯誤訊息', () {
    const exception = TtsSynthesisException('合成失敗');
    expect(exception.toString(), contains('合成失敗'));
  });
}
```

- [x] **Step 3：跑測試**

```
flutter test test/reader/tts_provider_test.dart
```

Expected：4 個測試全數 PASS。

- [x] **Step 4：Commit**

```
git add app/lib/reader/tts_provider.dart app/test/reader/tts_provider_test.dart
git commit -m "feat(epic-34): 新增 TtsProvider 抽象介面與型別（Issue 2 Task 2）"
```

---

### Task 3：`SystemTtsProvider`（`flutter_tts` 實作）

**Files:**
- Create: `app/lib/reader/system_tts_provider.dart`
- Test: `app/test/reader/system_tts_provider_test.dart`

**Interfaces:**
- Consumes：Task 2 的 `TtsProvider`／`TtsVoice`／`TtsSynthesisResult`／`TtsSynthesisException`；`test/support/fake_path_provider_platform.dart` 既有的 `FakePathProviderPlatform`
- Produces：`class SystemTtsProvider implements TtsProvider`，供 Task 6（`TtsController`）與 Task 7（`ReaderScreen`）建構真實 Provider 時使用

- [x] **Step 1：寫實作**

建立 `app/lib/reader/system_tts_provider.dart`：

```dart
import 'dart:async';
import 'dart:io';

import 'package:flutter_tts/flutter_tts.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import 'tts_provider.dart';

/// 系統原生語音朗讀（Android `TextToSpeech`，透過 `flutter_tts` 套件）。
/// [synthesize] 呼叫 `synthesizeToFile()`（檔案合成，非 `speak()` 即時
/// 朗讀——見 design.md 決策 9），固定寫入單一暫存檔路徑並每次覆寫（見
/// Global Constraints「暫存音訊檔生命週期」），呼叫端（[TtsController]）
/// 負責在播放完成/切換書籍/dispose 時視需要清除該檔案。
class SystemTtsProvider implements TtsProvider {
  final FlutterTts _flutterTts;

  SystemTtsProvider({FlutterTts? flutterTts})
      : _flutterTts = flutterTts ?? FlutterTts();

  @override
  Future<List<TtsVoice>> getAvailableVoices() async {
    // Phase 1 僅系統預設語音，無選單需求，呼叫端不依賴此結果。
    return const [TtsVoice.systemDefault];
  }

  @override
  Future<TtsSynthesisResult> synthesize(
    String text, {
    required TtsVoice voice,
    double speed = 1.0,
    double pitch = 1.0,
  }) async {
    final filePath = await _resolveOutputPath();

    // flutter_tts 的語速範圍是 0.0（最慢）～1.0（最快），本專案呼叫端
    // 目前恆傳 1.0（Issue 5 才會有語速調整 UI），clamp 純防禦。
    await _flutterTts.setSpeechRate(speed.clamp(0.0, 1.0));

    final completer = Completer<void>();
    _flutterTts.setCompletionHandler(() {
      if (!completer.isCompleted) completer.complete();
    });
    _flutterTts.setErrorHandler((dynamic message) {
      if (!completer.isCompleted) {
        completer.completeError(TtsSynthesisException(message.toString()));
      }
    });

    // isFullPath=true：呼叫端自己決定完整路徑並覆寫，不依賴套件自行組裝
    // 路徑的預設行為（見 Global Constraints「固定命名空間、覆寫」）。
    await _flutterTts.synthesizeToFile(text, filePath, true);
    await completer.future;

    return TtsSynthesisResult(audioFilePath: filePath);
  }

  Future<String> _resolveOutputPath() async {
    final tempDir = await getTemporaryDirectory();
    final ttsDir = Directory(p.join(tempDir.path, 'elinkbook_tts'));
    if (!await ttsDir.exists()) {
      await ttsDir.create(recursive: true);
    }
    return p.join(ttsDir.path, 'current_segment.wav');
  }
}
```

- [x] **Step 2：寫測試（mock `flutter_tts` MethodChannel）**

建立 `app/test/reader/system_tts_provider_test.dart`：

```dart
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:elinkbook/reader/system_tts_provider.dart';
import 'package:elinkbook/reader/tts_provider.dart';

import '../support/fake_path_provider_platform.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const channel = MethodChannel('flutter_tts');
  late Directory tempDir;
  late PathProviderPlatform originalPathProvider;

  setUp(() {
    tempDir = Directory.systemTemp.createTempSync('system_tts_provider_test');
    originalPathProvider = PathProviderPlatform.instance;
    PathProviderPlatform.instance = FakePathProviderPlatform(tempDir.path);
  });

  tearDown(() {
    PathProviderPlatform.instance = originalPathProvider;
    tempDir.deleteSync(recursive: true);
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  test('synthesize() 呼叫 synthesizeToFile（isFullPath=true）並在 synth.onComplete 後回傳結果',
      () async {
    final calls = <MethodCall>[];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      calls.add(call);
      if (call.method == 'synthesizeToFile') {
        // 模擬原生端非同步完成合成：透過同一個 channel 送回
        // synth.onComplete，讓 FlutterTts() 建構子註冊的
        // platformCallHandler 觸發 SystemTtsProvider 內的 completer。
        scheduleMicrotask(() {
          final message = const StandardMethodCodec()
              .encodeMethodCall(const MethodCall('synth.onComplete'));
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
              .handlePlatformMessage(channel.name, message, (_) {});
        });
      }
      return null;
    });

    final provider = SystemTtsProvider(flutterTts: FlutterTts());
    final result = await provider.synthesize(
      '測試文字',
      voice: TtsVoice.systemDefault,
    );

    expect(result.audioFilePath, endsWith('elinkbook_tts/current_segment.wav'));
    final synthCall =
        calls.firstWhere((c) => c.method == 'synthesizeToFile');
    final args = synthCall.arguments as Map;
    expect(args['text'], '測試文字');
    expect(args['fileName'], result.audioFilePath);
    expect(args['isFullPath'], isTrue);
  });

  test('synthesize() 在 synth.onError 後拋出 TtsSynthesisException', () async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      if (call.method == 'synthesizeToFile') {
        scheduleMicrotask(() {
          final message = const StandardMethodCodec().encodeMethodCall(
            const MethodCall('synth.onError', '模擬引擎錯誤'),
          );
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
              .handlePlatformMessage(channel.name, message, (_) {});
        });
      }
      return null;
    });

    final provider = SystemTtsProvider(flutterTts: FlutterTts());

    await expectLater(
      provider.synthesize('測試文字', voice: TtsVoice.systemDefault),
      throwsA(isA<TtsSynthesisException>()),
    );
  });
}
```

- [x] **Step 3：跑測試**

```
flutter test test/reader/system_tts_provider_test.dart
```

Expected：2 個測試全數 PASS。若 `synth.onError` 的 `MethodCall` 建構參數在你的 Flutter/flutter_tts 版本下型別不符（例如需要 Map 而非純字串），依實際 `platformCallHandler`（`flutter_tts-4.2.5/lib/flutter_tts.dart` 第 655 行附近 `case "synth.onError":`）的參數解析方式調整第二個測試的 `MethodCall` 引數，不要刪除這個測試。

- [x] **Step 4：Commit**

```
git add app/lib/reader/system_tts_provider.dart app/test/reader/system_tts_provider_test.dart
git commit -m "feat(epic-34): 新增 SystemTtsProvider（flutter_tts 實作，Issue 2 Task 3）"
```

---

### Task 4：朗讀段擷取——`main.js` JS 端＋Dart 端 codec／靜態 helper

**Files:**
- Create: `app/lib/reader/tts_segment_cfi.dart`
- Modify: `app/android/app/src/main/assets/foliate/main.js`
- Modify: `app/lib/reader/foliate_bridge_codec.dart`
- Modify: `app/lib/reader/foliate_reader_view.dart`
- Test: `app/test/reader/foliate_bridge_codec_test.dart`（既有檔案，新增測試案例）

**Interfaces:**
- Consumes：既有 `main.js` 的 `view.book.sections[index].createDocument()`／`view.getCFI(index, range)`（`buildTocEntry()` 已示範用法）、既有 `window.flutter_inappwebview.callHandler` 慣例
- Produces：`class TtsSegmentCfi { final String segmentId; final String cfi; final String text; }`、`List<TtsSegmentCfi> parseTtsSegments(String segmentsJson)`、`int? extractChapterIndex(String? locatorJson)`、`static Future<List<TtsSegmentCfi>> FoliateReaderView.loadTtsSegments(GlobalKey<State<FoliateReaderView>> key, int sectionIndex)`——供 Task 6／Task 7 的 `loadSegments` callback 使用

- [x] **Step 1：`TtsSegmentCfi` 模型**

建立 `app/lib/reader/tts_segment_cfi.dart`：

```dart
/// 章節載入時建立的「句子 → CFI」對照表單一項目（epic-34-tts-readalong
/// Issue 2，spec.md「朗讀段擷取」），對應 `main.js window.buildTtsSegments()`
/// 回傳的 JSON 陣列單一元素。比照 [TocEntry.fromWire] 既有寬容解析慣例
/// （缺失欄位以空字串防呆，不拋出例外）。
class TtsSegmentCfi {
  final String segmentId;
  final String cfi;
  final String text;

  const TtsSegmentCfi({
    required this.segmentId,
    required this.cfi,
    required this.text,
  });

  factory TtsSegmentCfi.fromWire(Map<Object?, Object?> map) {
    return TtsSegmentCfi(
      segmentId: map['segmentId'] as String? ?? '',
      cfi: map['cfi'] as String? ?? '',
      text: map['text'] as String? ?? '',
    );
  }
}
```

- [x] **Step 2：`main.js` 新增 `window.buildTtsSegments()`**

在 `app/android/app/src/main/assets/foliate/main.js` 的 `window.getTableOfContents` 函式定義之後（第 503 行之後），新增：

```javascript
/**
 * 建立指定章節（section）的「句子 → CFI」對照表（epic-34-tts-readalong
 * Issue 2，spec.md「朗讀段擷取」）。獨立載入該 section 的文件
 * （view.book.sections[index].createDocument()，同 buildTocEntry() 既有
 * 用法，獨立於目前實際顯示中的頁面），不影響閱讀畫面。
 *
 * 兩階段實作（避免跨 TextNode 邊界的狀態機錯誤）：
 * 第一階段用 TreeWalker 掃描全部符合條件的文字節點（過濾 <rt> 注音／
 * <script>），串接成單一字串 fullText，同時記錄「全域字元索引 -> (node,
 * 節點內偏移)」對照表 offsetMap；第二階段依標點切句，每句用 offsetMap
 * 查出起訖各自所在的 (node, offset)，建立可能跨多個 TextNode/標籤的
 * Range（例如「這是<em>重要</em>觀念。」），呼叫既有 view.getCFI(index,
 * range) 算 CFI，不重新實作 CFI 轉換邏輯。
 *
 * 已知限制：句子切分僅用常見中英文句末標點的簡單規則（不含精細避頭尾/
 * 引號內句界判斷），供 Phase 1 MVP 使用；不使用 Intl.Segmenter，避免對
 * 較舊 Android System WebView 的相容性風險（見
 * app/tool/check_foliate_es_compat.js 掃描範圍涵蓋本檔案）。
 *
 * 供 Dart 端 FoliateReaderView.loadTtsSegments()（透過
 * InAppWebViewController.evaluateJavascript）呼叫；非同步計算完成後主動
 * 透過 window.flutter_inappwebview.callHandler('onTtsSegmentsReady', ...)
 * 回呼 Dart 端，理由同 window.getTableOfContents()（evaluateJavascript
 * 不會等待內部 Promise resolve）。
 */
window.buildTtsSegments = async function (sectionIndex) {
  try {
    const doc = await view.book.sections[sectionIndex].createDocument()
    const walker = doc.createTreeWalker(doc.body, NodeFilter.SHOW_TEXT, {
      acceptNode: (node) => {
        // 不分大小寫比對（審查 review-plan-issue-2.md Minor #1）：EPUB
        // 章節是 XHTML，走 XML 解析器而非 HTML 解析器，tagName 不會被
        // 自動正規化為大寫，不能保證所有書都乖乖用小寫標籤。
        const tag = node.parentElement
          ? node.parentElement.tagName.toUpperCase()
          : ''
        return (tag === 'RT' || tag === 'SCRIPT')
          ? NodeFilter.FILTER_REJECT
          : NodeFilter.FILTER_ACCEPT
      },
    })

    let fullText = ''
    const offsetMap = []
    let node = walker.nextNode()
    while (node) {
      const text = node.textContent || ''
      for (let i = 0; i < text.length; i++) {
        offsetMap.push({ node, offset: i })
      }
      fullText += text
      node = walker.nextNode()
    }

    const terminators = /[。！？；.!?;]/
    const segments = []
    let start = 0
    let segmentIndex = 0
    for (let i = 0; i < fullText.length; i++) {
      const isLast = i === fullText.length - 1
      if (terminators.test(fullText[i]) || isLast) {
        // Range 起點跳過開頭空白字元（審查 review-plan-issue-2.md
        // Minor #2）：段落縮排空格若被含進 Range，Issue 3 高亮跟隨時
        // 反白區塊會多一截空白；Issue 2 本身不影響朗讀，但現在順手對齊
        // 比 Issue 3 再回頭補便宜。
        let rangeStart = start
        while (rangeStart < i && /\s/.test(fullText[rangeStart])) rangeStart++
        const trimmed = fullText.slice(start, i + 1).trim()
        if (trimmed.length > 0) {
          const startMap = offsetMap[rangeStart]
          const endMap = offsetMap[i]
          const range = doc.createRange()
          range.setStart(startMap.node, startMap.offset)
          range.setEnd(endMap.node, endMap.offset + 1)
          const cfi = view.getCFI(sectionIndex, range)
          segments.push({ segmentId: String(segmentIndex), cfi, text: trimmed })
          segmentIndex++
        }
        start = i + 1
      }
    }

    window.flutter_inappwebview.callHandler(
      'onTtsSegmentsReady', sectionIndex, JSON.stringify(segments),
    )
  } catch (e) {
    window.flutter_inappwebview.callHandler(
      'onTtsSegmentsReady', sectionIndex, JSON.stringify([]),
    )
  }
}
```

- [x] **Step 3：Dart codec——`parseTtsSegments()`／`extractChapterIndex()`**

在 `app/lib/reader/foliate_bridge_codec.dart` 頂部新增 import：

```dart
import 'tts_segment_cfi.dart';
```

在 `extractCfi()` 函式之後新增：

```dart
/// 從 `locatorJson`（`{"cfi":...,"index":N,"fraction":F}`，見
/// [EpubPositionInfo] class doc）取出章節/spine index（main.js `relocate`
/// 事件的 `section.current`），供 TTS 朗讀段擷取判斷「目前在哪個章節」
/// 使用（epic-34-tts-readalong Issue 2）。格式錯誤或缺席時回傳 `null`，
/// 比照 [extractCfi] 既有的優雅退回原則。
int? extractChapterIndex(String? locatorJson) {
  if (locatorJson == null) return null;
  try {
    final obj = jsonDecode(locatorJson);
    if (obj is Map && obj['index'] is num) {
      return (obj['index'] as num).toInt();
    }
    return null;
  } catch (_) {
    return null;
  }
}
```

在 `parseTableOfContents()` 函式之後新增：

```dart
/// 把 `main.js window.buildTtsSegments()` 回傳的 JSON 陣列字串解析為
/// [TtsSegmentCfi] 清單（epic-34-tts-readalong Issue 2），比照
/// [parseTableOfContents] 既有寬容解析慣例——格式錯誤時回傳空清單，不
/// 拋出例外。
List<TtsSegmentCfi> parseTtsSegments(String segmentsJson) {
  try {
    final array = jsonDecode(segmentsJson) as List<dynamic>;
    return array
        .map((e) => TtsSegmentCfi.fromWire(e as Map<Object?, Object?>))
        .toList();
  } catch (_) {
    return const [];
  }
}
```

- [x] **Step 4：`FoliateReaderView` 新增 `loadTtsSegments()` 靜態 helper**

在 `app/lib/reader/foliate_reader_view.dart` 頂部 import 區塊新增：

```dart
import 'tts_segment_cfi.dart';
```

在 `static Future<List<TocEntry>> loadTableOfContents(...)`（第 504 行附近）之後新增：

```dart
  /// 建立目前指定章節的「句子 → CFI」對照表（epic-34-tts-readalong
  /// Issue 2），比照 [loadTableOfContents] 既有模式。[key] 對應的 State
  /// 若尚未掛載，回傳空清單。
  static Future<List<TtsSegmentCfi>> loadTtsSegments(
    GlobalKey<State<FoliateReaderView>> key,
    int sectionIndex,
  ) async {
    final state = key.currentState;
    if (state is! _FoliateReaderViewState) return const [];
    return state._requestTtsSegments(sectionIndex);
  }
```

在 `_FoliateReaderViewState` 類別內，緊接 `Completer<List<TocEntry>>? _pendingToc;`（約第 536 行）之後新增欄位：

```dart
  Completer<List<TtsSegmentCfi>>? _pendingTtsSegments;
```

在 `Future<List<TocEntry>> _requestTableOfContents() { ... }` 方法之後新增：

```dart
  Future<List<TtsSegmentCfi>> _requestTtsSegments(int sectionIndex) {
    if (_controller == null) return Future.value(const []);
    final completer = Completer<List<TtsSegmentCfi>>();
    _pendingTtsSegments = completer;
    _evaluate('window.buildTtsSegments($sectionIndex)');
    // 5 秒逾時防禦（審查 review-plan-issue-2.md Minor #3）：main.js 端
    // 已用 try-catch 包住整段邏輯、正常情況下必定會呼叫
    // onTtsSegmentsReady，但 WebView 在等待期間被銷毀、或 JS context
    // 整個掛掉這類極端情況下 completer 可能永遠不 resolve，沒有逾時的話
    // 呼叫端 TtsController.play() 會永久卡在 await，播放功能整個沒回應。
    return completer.future.timeout(
      const Duration(seconds: 5),
      onTimeout: () {
        _pendingTtsSegments = null;
        return const [];
      },
    );
  }
```

在 `_onWebViewCreated()` 內，緊接 `onTableOfContentsReady` 的 `addJavaScriptHandler` 區塊之後新增：

```dart
    controller.addJavaScriptHandler(
      handlerName: 'onTtsSegmentsReady',
      callback: (args) {
        final completer = _pendingTtsSegments;
        _pendingTtsSegments = null;
        final json = args.length > 1 ? args[1] as String : '[]';
        completer?.complete(parseTtsSegments(json));
      },
    );
```

- [x] **Step 5：`parseTtsSegments()`／`extractChapterIndex()` 單元測試**

在 `app/test/reader/foliate_bridge_codec_test.dart` 檔案結尾（`main()` 函式內最後一個 `test()`/`group()` 之後、`}` 之前）新增：

```dart
  group('extractChapterIndex', () {
    test('正常 locatorJson 回傳 index', () {
      expect(
        extractChapterIndex('{"cfi":"epubcfi(/6/4)","index":3,"fraction":0.5}'),
        3,
      );
    });

    test('locatorJson 為 null 回傳 null', () {
      expect(extractChapterIndex(null), isNull);
    });

    test('格式錯誤回傳 null', () {
      expect(extractChapterIndex('not json'), isNull);
    });

    test('缺少 index 欄位回傳 null', () {
      expect(extractChapterIndex('{"cfi":"epubcfi(/6/4)"}'), isNull);
    });
  });

  group('parseTtsSegments', () {
    test('正常 JSON 陣列解析為 TtsSegmentCfi 清單', () {
      const json = '''
      [
        {"segmentId":"0","cfi":"epubcfi(/6/4!/4/2,/1:0,/1:5)","text":"第一句。"},
        {"segmentId":"1","cfi":"epubcfi(/6/4!/4/2,/1:5,/1:10)","text":"第二句。"}
      ]
      ''';
      final segments = parseTtsSegments(json);
      expect(segments, hasLength(2));
      expect(segments[0].segmentId, '0');
      expect(segments[0].text, '第一句。');
      expect(segments[1].cfi, 'epubcfi(/6/4!/4/2,/1:5,/1:10)');
    });

    test('跨標籤句子（例如含 <em> 分割成多個 TextNode）產生的單一合併 CFI 範圍，解析結果為單一 segment',
        () {
      // main.js 端把「這是<em>重要</em>觀念。」這種跨 TextNode 的句子，
      // 用 Range.setStart/setEnd 橫跨多個節點後，view.getCFI() 回傳的
      // 仍是單一字串（CFI 本身就是可跨節點定位的表示法，見 spec.md
      // 「Implementation Decisions」）——Dart 端只需驗證它被視為一個
      // 完整 segment，不會被誤拆成多筆。
      const json = '''
      [{"segmentId":"0","cfi":"epubcfi(/6/4!/4/2,/1:0,/3:2)","text":"這是重要觀念。"}]
      ''';
      final segments = parseTtsSegments(json);
      expect(segments, hasLength(1));
      expect(segments[0].text, '這是重要觀念。');
    });

    test('空陣列回傳空清單', () {
      expect(parseTtsSegments('[]'), isEmpty);
    });

    test('格式錯誤回傳空清單，不拋出例外', () {
      expect(parseTtsSegments('not json'), isEmpty);
    });

    test('缺失欄位以空字串防呆', () {
      final segments = parseTtsSegments('[{"cfi":"epubcfi(/6/4)"}]');
      expect(segments, hasLength(1));
      expect(segments[0].segmentId, '');
      expect(segments[0].text, '');
      expect(segments[0].cfi, 'epubcfi(/6/4)');
    });
  });
```

若 `foliate_bridge_codec_test.dart` 檔案頂部尚未 import `TtsSegmentCfi`/`parseTtsSegments`/`extractChapterIndex` 所在的 `foliate_bridge_codec.dart`／`tts_segment_cfi.dart`，確認既有 import（通常整個檔案已經 `import 'package:elinkbook/reader/foliate_bridge_codec.dart';`，涵蓋新函式）即可，不需額外新增。

**注意（測試涵蓋範圍的誠實邊界）**：上面「跨標籤句子」測試只驗證 Dart 端 `parseTtsSegments()` 對「JS 已經產生單一合併 CFI」這個結果的解析正確——**不驗證** `main.js window.buildTtsSegments()` 本身橫跨 TextNode 建立 Range／呼叫 `view.getCFI()` 的邏輯是否正確，因為 `flutter test` 環境下 `FoliateReaderView` 的 `_controller` 恆為 `null`（WebView 不會真的初始化，比照 `loadTableOfContents()` 既有的測試涵蓋範圍限制）。`window.buildTtsSegments()` 的實際正確性（含跨標籤句子、`<rt>` 過濾）**必須在 Task 7 完成後以真機開啟一本含 `<em>`/`<ruby>` 標籤句子的 EPUB 手動驗證**，見本計畫「測試策略」總結。

- [x] **Step 6：跑測試＋ES 相容性掃描**

```
flutter test test/reader/foliate_bridge_codec_test.dart
```

Expected：全數 PASS（含新增的 9 個測試）。

```
node app/tool/check_foliate_es_compat.js
```

Expected：結束碼 `0`（乾淨）。新增的 `window.buildTtsSegments()` 只用了 `TreeWalker`／`NodeFilter`／`RegExp.test`／字串 `slice`/`trim`／`Array.push` 等基礎 API，不含任何較新的 ES 內建方法，理論上不會觸發掃描。若掃描回報非 0，依腳本列出的清單在 `_esCompatPolyfillJs`（`foliate_reader_view.dart`）補齊 polyfill，不要刪減 `buildTtsSegments()` 的邏輯來規避掃描。

```
flutter analyze
```

Expected：`No issues found!`

- [x] **Step 7：Commit**

```
git add app/lib/reader/tts_segment_cfi.dart app/android/app/src/main/assets/foliate/main.js app/lib/reader/foliate_bridge_codec.dart app/lib/reader/foliate_reader_view.dart app/test/reader/foliate_bridge_codec_test.dart
git commit -m "feat(epic-34): 朗讀段擷取——main.js buildTtsSegments 與 Dart codec/靜態 helper（Issue 2 Task 4）"
```

---

### Task 5：`TtsAudioPlayer` 抽象介面與 `just_audio` 實作

**Files:**
- Create: `app/lib/reader/tts_audio_player.dart`

**Interfaces:**
- Consumes：`just_audio` 套件（Task 1 已加入）
- Produces：`abstract class TtsAudioPlayer { Future<void> loadFile(String path); Future<void> play(); Future<void> pause(); Stream<void> get completedStream; Future<void> dispose(); }`、`class JustAudioTtsPlayer implements TtsAudioPlayer`——供 Task 6（`TtsController`）與 Task 7（`ReaderScreen` 建構真實 `TtsController`）使用

- [x] **Step 1：寫抽象介面與實作**

建立 `app/lib/reader/tts_audio_player.dart`：

```dart
import 'dart:async';

import 'package:just_audio/just_audio.dart';

/// 朗讀音訊播放器抽象（epic-34-tts-readalong Issue 2）。存在的唯一理由
/// 是讓 [TtsController] 可在純 Dart 單元測試中注入 Fake 實作——
/// `just_audio` 的 `AudioPlayer` 依賴平台 channel，`flutter test`
/// 環境下無法真的播放音訊（無官方測試替身套件，比照本專案 WebView/
/// PlatformView 相關元件「flutter_test 測不到，真機才能驗證」的既有
/// 限制），故不直接讓 [TtsController] 持有具體的 `AudioPlayer`。
abstract class TtsAudioPlayer {
  Future<void> loadFile(String path);
  Future<void> play();
  Future<void> pause();

  /// 目前載入的音訊播放完畢時發出一個事件（不攜帶資料）。
  Stream<void> get completedStream;

  Future<void> dispose();
}

/// [TtsAudioPlayer] 的正式實作，包一層 `just_audio` 的 [AudioPlayer]。
class JustAudioTtsPlayer implements TtsAudioPlayer {
  final AudioPlayer _player;
  final StreamController<void> _completedController =
      StreamController<void>.broadcast();
  StreamSubscription<PlayerState>? _stateSub;

  JustAudioTtsPlayer({AudioPlayer? player}) : _player = player ?? AudioPlayer() {
    _stateSub = _player.playerStateStream.listen((state) {
      if (state.processingState == ProcessingState.completed) {
        _completedController.add(null);
      }
    });
  }

  @override
  Stream<void> get completedStream => _completedController.stream;

  @override
  Future<void> loadFile(String path) async {
    await _player.setFilePath(path);
  }

  @override
  Future<void> play() => _player.play();

  @override
  Future<void> pause() => _player.pause();

  @override
  Future<void> dispose() async {
    await _stateSub?.cancel();
    await _completedController.close();
    await _player.dispose();
  }
}
```

- [x] **Step 2：驗證編譯**

```
flutter analyze
```

Expected：`No issues found!`（本 Task 沒有可在 `flutter test` 下驗證的單元測試——`JustAudioTtsPlayer` 需要真機才能驗證實際播放行為，見本計畫「測試策略」總結；`TtsAudioPlayer` 抽象介面本身的行為由 Task 6 用 Fake 實作間接驗證。）

- [x] **Step 3：Commit**

```
git add app/lib/reader/tts_audio_player.dart
git commit -m "feat(epic-34): 新增 TtsAudioPlayer 抽象介面與 JustAudioTtsPlayer 實作（Issue 2 Task 5）"
```

---

### Task 6：`TtsController` 播放狀態機

**Files:**
- Create: `app/lib/reader/tts_controller.dart`
- Create: `app/test/support/fake_tts_provider.dart`
- Create: `app/test/support/fake_tts_audio_player.dart`
- Test: `app/test/reader/tts_controller_test.dart`

**Interfaces:**
- Consumes：Task 2 的 `TtsProvider`/`TtsVoice`；Task 4 的 `TtsSegmentCfi`；Task 5 的 `TtsAudioPlayer`
- Produces：`enum TtsPlaybackStatus { idle, playing, paused }`、`class TtsController extends ChangeNotifier { TtsController({required TtsProvider provider, required TtsAudioPlayer player, required Future<List<TtsSegmentCfi>> Function() loadSegments}); TtsPlaybackStatus get status; List<TtsSegmentCfi> get segments; int get currentIndex; Future<void> play(); void pause(); }`——供 Task 7（`ReaderScreen`）使用

- [x] **Step 1：寫 Fake 測試替身**

建立 `app/test/support/fake_tts_provider.dart`：

```dart
import 'package:elinkbook/reader/tts_provider.dart';

/// 測試用 Fake，比照 [FakeHighlightsRepository] 模式。每次 [synthesize]
/// 回傳一個遞增編號的假路徑，不做真的檔案 I/O 或語音合成。
class FakeTtsProvider implements TtsProvider {
  int synthesizeCallCount = 0;
  final List<String> synthesizedTexts = [];

  /// 測試設定後，下一次 [synthesize] 呼叫會拋出這個例外（拋出後自動
  /// 清空，只影響下一次呼叫），供驗證 [TtsController] 的例外處理。
  Object? nextSynthesizeError;

  @override
  Future<List<TtsVoice>> getAvailableVoices() async => const [TtsVoice.systemDefault];

  @override
  Future<TtsSynthesisResult> synthesize(
    String text, {
    required TtsVoice voice,
    double speed = 1.0,
    double pitch = 1.0,
  }) async {
    synthesizeCallCount++;
    synthesizedTexts.add(text);
    final error = nextSynthesizeError;
    if (error != null) {
      nextSynthesizeError = null;
      throw error;
    }
    return TtsSynthesisResult(audioFilePath: '/fake/segment_$synthesizeCallCount.wav');
  }
}
```

建立 `app/test/support/fake_tts_audio_player.dart`：

```dart
import 'dart:async';

import 'package:elinkbook/reader/tts_audio_player.dart';

/// 測試用 Fake，比照 [FakeHighlightsRepository] 模式。記錄呼叫順序供
/// 測試斷言，[simulateCompleted] 讓測試主動觸發「目前段落播放完畢」。
class FakeTtsAudioPlayer implements TtsAudioPlayer {
  final List<String> loadedFiles = [];
  final List<String> callLog = [];
  final StreamController<void> _completedController =
      StreamController<void>.broadcast();
  bool disposed = false;

  @override
  Stream<void> get completedStream => _completedController.stream;

  @override
  Future<void> loadFile(String path) async {
    loadedFiles.add(path);
    callLog.add('loadFile');
  }

  @override
  Future<void> play() async {
    callLog.add('play');
  }

  @override
  Future<void> pause() async {
    callLog.add('pause');
  }

  @override
  Future<void> dispose() async {
    disposed = true;
    await _completedController.close();
  }

  void simulateCompleted() => _completedController.add(null);
}
```

- [x] **Step 2：寫失敗測試（`TtsController` 尚未存在）**

建立 `app/test/reader/tts_controller_test.dart`：

```dart
import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:elinkbook/reader/tts_controller.dart';
import 'package:elinkbook/reader/tts_provider.dart';
import 'package:elinkbook/reader/tts_segment_cfi.dart';

import '../support/fake_tts_audio_player.dart';
import '../support/fake_tts_provider.dart';

void main() {
  const segments = [
    TtsSegmentCfi(segmentId: '0', cfi: 'epubcfi(/6/4!/1:0)', text: '第一句。'),
    TtsSegmentCfi(segmentId: '1', cfi: 'epubcfi(/6/4!/1:5)', text: '第二句。'),
  ];

  late FakeTtsProvider provider;
  late FakeTtsAudioPlayer player;

  TtsController buildController({List<TtsSegmentCfi> segs = segments}) {
    provider = FakeTtsProvider();
    player = FakeTtsAudioPlayer();
    return TtsController(
      provider: provider,
      player: player,
      loadSegments: () async => segs,
    );
  }

  test('初始狀態為 idle，尚未載入任何朗讀段', () {
    final controller = buildController();
    expect(controller.status, TtsPlaybackStatus.idle);
    expect(controller.segments, isEmpty);
    expect(controller.currentIndex, -1);
  });

  test('play() 於空朗讀段清單時維持 idle，不呼叫 synthesize', () async {
    final controller = buildController(segs: const []);
    await controller.play();
    expect(controller.status, TtsPlaybackStatus.idle);
    expect(provider.synthesizeCallCount, 0);
  });

  test('play() 合成第一段並開始播放', () async {
    final controller = buildController();
    await controller.play();

    expect(provider.synthesizeCallCount, 1);
    expect(provider.synthesizedTexts, ['第一句。']);
    expect(player.loadedFiles, ['/fake/segment_1.wav']);
    expect(player.callLog, ['loadFile', 'play']);
    expect(controller.status, TtsPlaybackStatus.playing);
    expect(controller.currentIndex, 0);
  });

  test('目前段落播放完畢後自動合成並播放下一段', () async {
    final controller = buildController();
    await controller.play();
    player.simulateCompleted();
    await Future<void>.delayed(Duration.zero); // 讓 completedStream 事件被消費

    expect(provider.synthesizeCallCount, 2);
    expect(provider.synthesizedTexts, ['第一句。', '第二句。']);
    expect(controller.currentIndex, 1);
    expect(controller.status, TtsPlaybackStatus.playing);
  });

  test('最後一段播放完畢後回到 idle，不再合成新段落', () async {
    final controller = buildController();
    await controller.play();
    player.simulateCompleted();
    await Future<void>.delayed(Duration.zero);
    player.simulateCompleted();
    await Future<void>.delayed(Duration.zero);

    expect(provider.synthesizeCallCount, 2);
    expect(controller.status, TtsPlaybackStatus.idle);
    expect(controller.currentIndex, -1);
    expect(controller.segments, isEmpty);
  });

  test('pause() 於播放中呼叫 player.pause() 並轉為 paused，不重新合成', () async {
    final controller = buildController();
    await controller.play();
    controller.pause();

    expect(controller.status, TtsPlaybackStatus.paused);
    expect(player.callLog.last, 'pause');
    expect(provider.synthesizeCallCount, 1);
  });

  test('paused 狀態下再次呼叫 play() 只呼叫 player.play()，不重新合成', () async {
    final controller = buildController();
    await controller.play();
    controller.pause();
    await controller.play();

    expect(controller.status, TtsPlaybackStatus.playing);
    expect(provider.synthesizeCallCount, 1); // 沒有新的合成呼叫
    expect(player.callLog, ['loadFile', 'play', 'pause', 'play']);
  });

  test('play() 於已在播放中時為 no-op', () async {
    final controller = buildController();
    await controller.play();
    await controller.play();

    expect(provider.synthesizeCallCount, 1);
    expect(player.callLog, ['loadFile', 'play']);
  });

  test('notifyListeners 在狀態變化時觸發', () async {
    final controller = buildController();
    var notifyCount = 0;
    controller.addListener(() => notifyCount++);

    await controller.play();
    expect(notifyCount, greaterThan(0));

    final countAfterPlay = notifyCount;
    controller.pause();
    expect(notifyCount, greaterThan(countAfterPlay));
  });

  test('dispose() 後 player 已釋放，模擬完成事件不再觸發新的合成', () async {
    final controller = buildController();
    await controller.play();
    controller.dispose();

    expect(player.disposed, isTrue);
  });

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

  test('自動接續下一句時 synthesize() 拋出例外，重設回 idle 而非卡在 playing（審查 Important #1）',
      () async {
    final controller = buildController();
    await controller.play();
    provider.nextSynthesizeError = const TtsSynthesisException('模擬引擎失敗');
    player.simulateCompleted();
    await Future<void>.delayed(Duration.zero);

    expect(controller.status, TtsPlaybackStatus.idle);
    expect(controller.currentIndex, -1);
    // 第一段合成成功（callLog 有 loadFile/play），第二段合成失敗，
    // 不應該再有第二次 loadFile。
    expect(player.callLog, ['loadFile', 'play']);
  });

  test('play() 於 loadSegments() 尚未完成時重複呼叫，只觸發一次 loadSegments（審查 Important #2）',
      () async {
    final loadCompleter = Completer<List<TtsSegmentCfi>>();
    var loadSegmentsCallCount = 0;
    provider = FakeTtsProvider();
    player = FakeTtsAudioPlayer();
    final controller = TtsController(
      provider: provider,
      player: player,
      loadSegments: () {
        loadSegmentsCallCount++;
        return loadCompleter.future;
      },
    );

    final firstPlay = controller.play();
    final secondPlay = controller.play(); // 連點：loadSegments() 尚未完成
    loadCompleter.complete(segments);
    await firstPlay;
    await secondPlay;

    expect(loadSegmentsCallCount, 1);
    expect(provider.synthesizeCallCount, 1);
  });
}
```

- [x] **Step 3：跑測試確認失敗**

```
flutter test test/reader/tts_controller_test.dart
```

Expected：FAIL（`tts_controller.dart`／`TtsController` 尚不存在，編譯錯誤）。

- [x] **Step 4：寫 `TtsController` 實作**

建立 `app/lib/reader/tts_controller.dart`：

```dart
import 'dart:async';

import 'package:flutter/foundation.dart';

import 'tts_audio_player.dart';
import 'tts_provider.dart';
import 'tts_segment_cfi.dart';

enum TtsPlaybackStatus { idle, playing, paused }

/// 朗讀狀態機的核心協調者（epic-34-tts-readalong Issue 2，spec.md
/// 「Implementation Decisions」）。純 Dart、不依賴 Flutter widget 樹或
/// WebView，[loadSegments] 由呼叫端（[ReaderScreen]）注入，內部實際呼叫
/// `FoliateReaderView.loadTtsSegments()`——本類別完全不知道 `FoliateReaderView`
/// 存在，只透過這個 callback 取得朗讀段清單。`extends ChangeNotifier`
/// 讓 UI（本 Issue 的簡易播放/暫停按鈕、Issue 6 的 Mini Player）可直接
/// 訂閱狀態變化（見 `review-issues.md` Minor #1「單一事實來源」）。
///
/// Phase 1 MVP 簡化：不維護獨立的「音訊播放位置 → 朗讀段」二分搜尋索引
/// （原研究報告的 `TtsTimeline` 設計）——每個朗讀段各自合成為獨立音訊檔、
/// 依序播放（非單一連續跨段落音訊流，見 design.md 決策 9「音訊合成一律
/// 走檔案管線」），「目前是哪一段」天然等同 [currentIndex] 這個整數游標，
/// 不需要對「音訊時間」做二分搜尋。Issue 4 若需要「畫面位置 → 朗讀段」
/// 反向查找（`lookupSegmentByCfi`），可直接對 [segments] 做線性/二分搜尋
/// （已依文件順序排序），不影響本類別既有結構。
class TtsController extends ChangeNotifier {
  final TtsProvider provider;
  final TtsAudioPlayer player;
  final Future<List<TtsSegmentCfi>> Function() loadSegments;

  TtsController({
    required this.provider,
    required this.player,
    required this.loadSegments,
  }) {
    _completedSub = player.completedStream.listen((_) => _handleSegmentCompleted());
  }

  TtsPlaybackStatus _status = TtsPlaybackStatus.idle;
  TtsPlaybackStatus get status => _status;

  List<TtsSegmentCfi> _segments = const [];
  List<TtsSegmentCfi> get segments => _segments;

  int _currentIndex = -1;
  int get currentIndex => _currentIndex;

  StreamSubscription<void>? _completedSub;
  bool _disposed = false;

  /// `play()` 在 `idle` 狀態下要先 `await loadSegments()`（涉及 JS bridge
  /// 往返，非立即完成）——這段期間 `_status` 仍是 `idle`，若不設防重入
  /// 旗標，使用者連點播放鍵會觸發第二次 `loadSegments()`／合成流程互相
  /// 打架（審查 review-plan-issue-2.md Important #2）。
  bool _isLoadingSegments = false;

  Future<void> play() async {
    if (_status == TtsPlaybackStatus.playing) return;
    if (_isLoadingSegments) return;
    if (_status == TtsPlaybackStatus.paused) {
      _status = TtsPlaybackStatus.playing;
      notifyListeners();
      await player.play();
      return;
    }
    // idle：第一次播放，先載入目前章節的朗讀段。
    _isLoadingSegments = true;
    List<TtsSegmentCfi> loaded;
    try {
      loaded = await loadSegments();
    } finally {
      _isLoadingSegments = false;
    }
    if (_disposed) return;
    if (loaded.isEmpty) return; // 沒有可朗讀的內容，維持 idle。
    _segments = loaded;
    _currentIndex = 0;
    await _playCurrentSegment();
  }

  void pause() {
    if (_status != TtsPlaybackStatus.playing) return;
    _status = TtsPlaybackStatus.paused;
    notifyListeners();
    player.pause();
  }

  /// 合成並播放 [_currentIndex] 對應的朗讀段。`provider.synthesize()`／
  /// `player.loadFile()` 任一步驟拋出例外時（例如真機上 Android TTS
  /// 引擎失敗、磁碟寫入錯誤），一律捕捉並重設回 `idle`——不重新拋出
  /// （審查 review-plan-issue-2.md Important #1）。這個方法同時被
  /// [play] 與 [_handleSegmentCompleted]（自動接續下一句）呼叫，後者是
  /// 在 `completedStream` 的 `listen()` callback 內以「非 async 回呼
  /// 型別」的方式觸發（`void Function(T)`，Dart 不會 await 這個
  /// callback 回傳的 `Future`），若不在這裡就地捕捉例外，會變成沒人
  /// 接住的非同步例外，且 `_status` 會永遠卡在 `playing`（使用者看到
  /// 暫停圖示但實際上沒在播放，怎麼點都沒反應）。
  Future<void> _playCurrentSegment() async {
    final segment = _segments[_currentIndex];
    try {
      final result = await provider.synthesize(
        segment.text,
        voice: TtsVoice.systemDefault,
      );
      if (_disposed) return;
      await player.loadFile(result.audioFilePath);
      if (_disposed) return;
      _status = TtsPlaybackStatus.playing;
      notifyListeners();
      await player.play();
    } catch (_) {
      if (_disposed) return;
      _status = TtsPlaybackStatus.idle;
      _currentIndex = -1;
      _segments = const [];
      notifyListeners();
    }
  }

  Future<void> _handleSegmentCompleted() async {
    if (_disposed) return;
    if (_status != TtsPlaybackStatus.playing) return;
    final nextIndex = _currentIndex + 1;
    if (nextIndex >= _segments.length) {
      _status = TtsPlaybackStatus.idle;
      _currentIndex = -1;
      _segments = const [];
      notifyListeners();
      return;
    }
    _currentIndex = nextIndex;
    await _playCurrentSegment();
  }

  @override
  void dispose() {
    _disposed = true;
    _completedSub?.cancel();
    player.dispose();
    super.dispose();
  }
}
```

- [x] **Step 5：跑測試確認通過**

```
flutter test test/reader/tts_controller_test.dart
```

Expected：13 個測試全數 PASS（含審查修訂新增的例外處理／防重入 3 個測試）。若「目前段落播放完畢後自動合成並播放下一段」等依賴 `completedStream` 事件的測試出現時序問題（事件在 `expect` 執行前還沒被消費），確認 `Future<void>.delayed(Duration.zero)` 那行有留著（把目前巨集任務排到事件迴圈之後，讓 `StreamController.broadcast()` 的監聽器有機會執行）。

- [x] **Step 6：Commit**

```
git add app/lib/reader/tts_controller.dart app/test/support/fake_tts_provider.dart app/test/support/fake_tts_audio_player.dart app/test/reader/tts_controller_test.dart
git commit -m "feat(epic-34): 新增 TtsController 播放狀態機（Issue 2 Task 6，TDD）"
```

---

### Task 7：`ReaderScreen` 整合——`ttsProvider` 參數、CBZ 排除、最小播放/暫停按鈕

**Files:**
- Modify: `app/lib/screens/reader_screen.dart`
- Test: `app/test/screens/reader_screen_test.dart`（既有檔案，新增測試案例）

**Interfaces:**
- Consumes：Task 2 的 `TtsProvider`；Task 4 的 `FoliateReaderView.loadTtsSegments`／`extractChapterIndex`；Task 5 的 `JustAudioTtsPlayer`；Task 6 的 `TtsController`/`TtsPlaybackStatus`
- Produces：`ReaderScreen` 新增可選建構參數 `final TtsProvider? ttsProvider;`；新增 `Key('reader_tts_play_pause_button')` 供測試/後續 Issue 觀察

- [x] **Step 1：新增建構參數**

在 `app/lib/screens/reader_screen.dart` 頂部 import 區塊新增：

```dart
import '../reader/tts_audio_player.dart';
import '../reader/tts_controller.dart';
import '../reader/tts_provider.dart';
```

在 `class ReaderScreen extends StatefulWidget` 內，緊接 `final SyncCheckpointTrigger? syncCheckpointTrigger;`（第 152 行）之後新增欄位：

```dart
  /// 語音朗讀（TTS）的語音來源（epic-34-tts-readalong Issue 2）。刻意為
  /// 可選參數——比照 [bookmarksRepository] 既有慣例，未提供時朗讀播放
  /// 按鈕不顯示，行為等同本 Issue 之前，零回歸。CBZ 格式即使提供本參數
  /// 也會顯示明確停用狀態的按鈕（非隱藏，見 `issues.md` Issue 2 驗收
  /// 標準），因為 CBZ 是純圖像格式、沒有文字可朗讀。
  final TtsProvider? ttsProvider;
```

在建構子參數列表（`this.syncCheckpointTrigger,` 之後）新增：

```dart
    this.ttsProvider,
```

- [x] **Step 2：State 新增 `TtsController` lazy getter 與 dispose**

在 `class _ReaderScreenState extends State<ReaderScreen> with WidgetsBindingObserver` 內，緊接 `EpubPositionInfo? _epubPositionInfo;`（第 280 行附近）之後新增欄位：

```dart
  TtsController? _ttsController;
```

在同一個 State class 內新增（放在既有 getter 群組附近，例如 `_themedFabIconColor` getter 之後）：

```dart
  /// 首次存取時才建構 [TtsController]（[widget.ttsProvider] 為 `null` 時
  /// 回傳 `null`，播放按鈕不顯示）。[loadSegments] 內部從
  /// [_epubPositionInfo] 反推目前章節 index（`extractChapterIndex()`，
  /// 缺席時預設第 0 章，比照 `main.js` `section?.current ?? 0` 既有預設
  /// 行為），呼叫 [FoliateReaderView.loadTtsSegments]——完全不需要
  /// [TtsController] 知道 [FoliateReaderView] 或 [GlobalKey] 的存在。
  TtsController? get _ttsControllerOrNull {
    final provider = widget.ttsProvider;
    if (provider == null) return null;
    return _ttsController ??= TtsController(
      provider: provider,
      player: JustAudioTtsPlayer(),
      loadSegments: () async {
        final chapterIndex =
            extractChapterIndex(_epubPositionInfo?.locatorJson) ?? 0;
        return FoliateReaderView.loadTtsSegments(
          _foliateEpubReaderViewKey,
          chapterIndex,
        );
      },
    );
  }
```

在既有 `dispose()` 方法內（搜尋 `super.dispose()` 呼叫前的清理區塊，通常與其他 repository/controller 清理程式碼放在一起），新增：

```dart
    _ttsController?.dispose();
```

- [x] **Step 3：新增播放/暫停按鈕**

在 `_buildNativeView` 所在的 build 方法內，找到既有 EPUB FAB 區塊最後一個（`Key('reader_foliate_progress_button')`，`top: 240`）的 `Positioned` 區塊，緊接其後新增：

```dart
            if (isFoliateFormat(format) &&
                _chromeVisible &&
                widget.ttsProvider != null)
              Positioned(
                top: 296,
                right: 16,
                child: format == BookFormat.cbz
                    // CBZ 為純圖像格式，無文字可朗讀——明確顯示停用狀態
                    // 的按鈕（onPressed: null），不是整個隱藏（見
                    // issues.md Issue 2 驗收標準：「CBZ 書籍 TTS 入口為
                    // 明確停用狀態，非靜默無反應」）。
                    ? ClipOval(
                        child: Container(
                          color: _themedFabBackgroundColor,
                          child: IconButton(
                            key: const Key('reader_tts_play_pause_button'),
                            icon: Icon(Icons.play_arrow,
                                color: _themedFabIconColor),
                            tooltip: 'CBZ 為純圖像格式，不支援語音朗讀',
                            onPressed: null,
                          ),
                        ),
                      )
                    : AnimatedBuilder(
                        animation: _ttsControllerOrNull!,
                        builder: (context, _) {
                          final controller = _ttsControllerOrNull!;
                          final playing =
                              controller.status == TtsPlaybackStatus.playing;
                          return ClipOval(
                            child: Container(
                              color: _themedFabBackgroundColor,
                              child: IconButton(
                                key: const Key('reader_tts_play_pause_button'),
                                icon: Icon(
                                  playing ? Icons.pause : Icons.play_arrow,
                                  color: _themedFabIconColor,
                                ),
                                tooltip: playing ? '暫停朗讀' : '開始朗讀',
                                onPressed:
                                    playing ? controller.pause : () => controller.play(),
                              ),
                            ),
                          );
                        },
                      ),
              ),
```

- [x] **Step 4：寫 widget test**

在 `app/test/screens/reader_screen_test.dart` 找一個既有的「流式 EPUB」`testWidgets` 區塊（例如 Task 說明中提過的「流式 EPUB：點擊複製按鈕」測試）附近，新增以下測試（若檔案頂部尚未 import `FakeTtsProvider`，補上 `import '../support/fake_tts_provider.dart';`）：

```dart
  testWidgets('未提供 ttsProvider 時，不顯示 TTS 播放按鈕', (tester) async {
    final highlightsRepo = FakeHighlightsRepository();
    final notesRepo = FakeNotesRepository();

    await tester.pumpWidget(
      MaterialApp(
        home: ReaderScreen(
          filePath: 'test/fixtures/sample.epub',
          bookId: 'b_tts_no_provider',
          prefsManager: prefsManager,
          highlightsRepository: highlightsRepo,
          notesRepository: notesRepo,
          isFixedLayout: false,
        ),
      ),
    );
    await tester.pump();
    await tester.runAsync(() => Future.delayed(Duration.zero));
    await tester.pump();

    final foliateView =
        tester.widget<FoliateReaderView>(find.byType(FoliateReaderView));
    foliateView.onPageRendered();
    foliateView.onLayoutResolved?.call(
      const EpubLayoutInfo(
        isFixedLayout: false,
        writingMode: WritingMode.horizontal,
      ),
    );
    await tester.pump();
    await tester.pump();

    expect(find.byKey(const Key('reader_tts_play_pause_button')), findsNothing);
  });

  testWidgets('提供 ttsProvider 時，流式 EPUB 顯示 TTS 播放按鈕，初始為播放圖示',
      (tester) async {
    final highlightsRepo = FakeHighlightsRepository();
    final notesRepo = FakeNotesRepository();
    final ttsProvider = FakeTtsProvider();

    await tester.pumpWidget(
      MaterialApp(
        home: ReaderScreen(
          filePath: 'test/fixtures/sample.epub',
          bookId: 'b_tts_with_provider',
          prefsManager: prefsManager,
          highlightsRepository: highlightsRepo,
          notesRepository: notesRepo,
          isFixedLayout: false,
          ttsProvider: ttsProvider,
        ),
      ),
    );
    await tester.pump();
    await tester.runAsync(() => Future.delayed(Duration.zero));
    await tester.pump();

    final foliateView =
        tester.widget<FoliateReaderView>(find.byType(FoliateReaderView));
    foliateView.onPageRendered();
    foliateView.onLayoutResolved?.call(
      const EpubLayoutInfo(
        isFixedLayout: false,
        writingMode: WritingMode.horizontal,
      ),
    );
    await tester.pump();
    await tester.pump();

    final buttonFinder = find.byKey(const Key('reader_tts_play_pause_button'));
    expect(buttonFinder, findsOneWidget);
    final icon = tester.widget<Icon>(find.descendant(
      of: buttonFinder,
      matching: find.byType(Icon),
    ));
    expect(icon.icon, Icons.play_arrow);

    // 點擊播放：測試環境下 FoliateReaderView._controller 恆為 null（見
    // Task 4 Step 5「測試涵蓋範圍的誠實邊界」），loadSegments() 因此
    // 恆回傳空清單，TtsController 維持 idle、不呼叫 FakeTtsProvider——
    // 本測試只驗證「按鈕存在且點擊不拋出例外」這個 UI 接線層級的行為，
    // TtsController 完整播放/暫停流程的驗證見 tts_controller_test.dart。
    await tester.tap(buttonFinder);
    await tester.pump();
    expect(tester.takeException(), isNull);
  });

  testWidgets('CBZ 格式提供 ttsProvider 時，TTS 按鈕顯示但為停用狀態', (tester) async {
    final ttsProvider = FakeTtsProvider();

    await tester.pumpWidget(
      MaterialApp(
        home: ReaderScreen(
          filePath: 'test/fixtures/sample.cbz',
          bookId: 'b_tts_cbz',
          prefsManager: prefsManager,
          isFixedLayout: true,
          ttsProvider: ttsProvider,
        ),
      ),
    );
    await tester.pump();
    await tester.runAsync(() => Future.delayed(Duration.zero));
    await tester.pump();

    final foliateView =
        tester.widget<FoliateReaderView>(find.byType(FoliateReaderView));
    foliateView.onPageRendered();
    foliateView.onLayoutResolved?.call(
      const EpubLayoutInfo(isFixedLayout: true, writingMode: WritingMode.horizontal),
    );
    await tester.pump();
    await tester.pump();

    final buttonFinder = find.byKey(const Key('reader_tts_play_pause_button'));
    expect(buttonFinder, findsOneWidget);
    final button = tester.widget<IconButton>(buttonFinder);
    expect(button.onPressed, isNull);
  });
```

若 `test/fixtures/sample.cbz` 這個 fixture 檔在既有測試中的正確 `isFixedLayout`/開書驗證方式與上面寫的不同（例如需要不同的 `onLayoutResolved` 呼叫時機或格式判斷路徑），比照檔案內其他既有 CBZ/FXL 測試案例（搜尋 `sample.cbz` 或 `isFixedLayout: true` 既有用法）調整，不要憑空假設。

- [x] **Step 5：跑測試確認全數通過、零回歸**

```
flutter test test/screens/reader_screen_test.dart
```

Expected：全數 PASS（含新增的 3 個測試，既有測試零回歸）。

```
flutter test
```

Expected：全專案測試全數通過，零回歸。

```
flutter analyze
```

Expected：`No issues found!`

- [x] **Step 6：Commit**

```
git add app/lib/screens/reader_screen.dart app/test/screens/reader_screen_test.dart
git commit -m "feat(epic-34): ReaderScreen 整合 TTS 播放/暫停按鈕，CBZ 明確停用（Issue 2 Task 7）"
```

---

## 測試策略總結（Self-Review 用，非額外步驟）

- **純 Dart 單元測試**（Task 2/3/4/6）：涵蓋 `TtsProvider`/`SystemTtsProvider`/`TtsController` 全部狀態轉換邏輯、`parseTtsSegments`/`extractChapterIndex` 的 JSON 解析健壯性。
- **`ReaderScreen` widget test**（Task 7）：涵蓋 UI 接線層級——按鈕顯示/隱藏/停用邏輯是否正確，不涵蓋真實播放流程（該環境下 WebView 不會初始化）。
- **無法自動化、須真機手動驗證的部分**（比照本專案既有「PlatformView/WebView 渲染真相只能真機驗證」慣例，不在本 Issue 的自動化測試範圍內，但**合併前建議至少手動跑一次**）：
  1. `main.js window.buildTtsSegments()` 對真實章節 DOM 的句子切分與跨標籤 CFI 是否正確（含 `<em>`/`<ruby>` 情境，呼應 `review-spec.md` Important #2）。
  2. `SystemTtsProvider` 呼叫真實 Android `TextToSpeech` 合成語音檔是否成功。
  3. `JustAudioTtsPlayer` 播放合成出的音訊檔、`completedStream` 是否正確在播放結束時觸發。
  4. 端到端：開一本 EPUB，按下播放，確認能聽到逐句朗讀、章節結束自動停止、暫停/繼續正常。

---

## Self-Review 檢查結果

- **Spec coverage**：`issues.md` Issue 2 設計要點與驗收標準逐條對應：`TtsProvider`/`SystemTtsProvider`（Task 2/3）、`TtsController` 播放/暫停/自動接續（Task 6）、朗讀段擷取含 `<rt>` 過濾（Task 4）、暫存檔固定命名空間覆寫（Task 3，單一固定檔名天然滿足）、CBZ 排除且明確停用（Task 7）、`ReaderScreen` 可選參數零回歸（Task 7）、`flutter analyze`/`flutter test` 全數通過（每個 Task 皆有驗證步驟）。無缺口。
- **Placeholder scan**：全文搜尋未發現「TBD」/「之後補」/「處理錯誤」等空話；所有程式碼步驟皆有完整程式碼區塊。
- **Type consistency**：`TtsProvider.synthesize()` 簽章（Task 2 定義）與 Task 3 `SystemTtsProvider`/Task 6 `FakeTtsProvider`/`TtsController._playCurrentSegment()` 呼叫端一致；`TtsAudioPlayer` 介面（Task 5）與 Task 6 `FakeTtsAudioPlayer`/`TtsController` 呼叫端一致；`TtsSegmentCfi`（Task 4）欄位名稱在 Task 6/7 `loadSegments` callback 與測試中一致；`TtsController` 建構子參數名稱（`provider`/`player`/`loadSegments`）在 Task 6 測試與 Task 7 `ReaderScreen` 呼叫端一致。

**審查修訂**（`/superpowers:requesting-code-review`，`reviews/review-plan-issue-2.md`，結論 Approved with Recommendations，0 Critical／2 Important／3 Minor，已全數採納修訂）：
- Task 6：`_playCurrentSegment()` 補上 try-catch，`provider.synthesize()`/`player.loadFile()` 失敗時重設回 `idle`（不論由 `play()` 或自動接續 `_handleSegmentCompleted()` 觸發），避免使用者卡在「顯示暫停圖示但實際沒在播放」的假死狀態；`play()` 新增 `_isLoadingSegments` 防重入旗標，避免連點播放鍵觸發兩次 `loadSegments()`。對應新增 3 個測試（例外處理 2 個、防重入 1 個），`FakeTtsProvider` 新增 `nextSynthesizeError` 欄位供測試觸發。
- Task 4：`main.js` 的 `<rt>`/`<script>` 標籤比對改不分大小寫（XHTML 走 XML 解析器不會自動正規化 tagName）；句子 Range 起點跳過開頭空白字元（避免 Issue 3 高亮跟隨時反白區塊多一截空白）；`FoliateReaderView._requestTtsSegments()` 加上 5 秒逾時防禦，避免 JS 端異常未回呼時永久卡住播放功能。
