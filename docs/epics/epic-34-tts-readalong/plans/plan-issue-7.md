# Issue 7：背景播放與系統整合（`audio_service`）Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development（推薦）或 superpowers:executing-plans 逐工作項執行本計畫。步驟採用核取方塊（`- [ ]`）語法追蹤進度。

**Goal:** 讓朗讀（TTS）在 App 切到背景/鎖定螢幕後繼續播放，通知欄與鎖定畫面顯示播放控制，耳機線控/拔出正確反應，系統音訊焦點（來電/其他音樂 App）中斷時暫停/自動恢復符合政策，App 從背景恢復前景時畫面高亮重新同步。

**Architecture:** 新增三個獨立、可純 Dart 單元測試的協調層元件，全部只依賴既有 `TtsController`（Issue 2/4/5，`ChangeNotifier`）公開介面，不修改其既有播放邏輯本身：

1. **`TtsAudioFocusSource`／`TtsAudioFocusCoordinator`**（`tts_audio_focus_source.dart`／`tts_audio_focus_coordinator.dart`）：把 Android 系統音訊焦點事件／耳機拔出事件（透過 `audio_session` 套件）轉譯成 `TtsController.pause()`／`play()` 呼叫，決定「是否該在焦點恢復時自動恢復播放」（只有本協調器自己造成的暫停才自動恢復，使用者手動暫停不受影響）。
2. **`TtsAudioHandler`**（`tts_audio_handler.dart`）：`extends BaseAudioHandler`（`audio_service` 套件），是系統通知欄/鎖定畫面/耳機線控與 `TtsController` 之間的橋接——把 `TtsController.status` 變化轉譯成 `PlaybackState` 廣播（供系統顯示），把系統送來的 `play()`/`pause()`/`skipToNext()`/`skipToPrevious()` 呼叫轉發給 `TtsController` 對應方法。單一 App 層級長駐實例（`AudioService.init()` 全程式生命週期只能呼叫一次），透過 `attachController()`/`detachController()` 綁定/解綁「目前開啟的書」對應的 `TtsController`。
3. **`TtsController.resyncHighlight()`**（新方法，Issue 4 既有 `handleExternalPositionChange()` 旁）：App 從背景恢復前景時，`ReaderScreen` 既有的 `didChangeAppLifecycleState` 呼叫本方法，重新送出目前播放段落的高亮（`onHighlightSegment` 回呼），修正背景時 WebView 節流導致的高亮落後問題。**只重送高亮，不含「翻頁指令」**——安全視窗跟隨翻頁是 Issue 8（尚未實作）的範圍，本 Issue 不預先假設其存在。

三者皆透過 `ReaderScreen` 既有的可選（nullable）建構參數注入模式（比照 `ttsProvider`）接線，未提供時（例如所有既有測試）完全不影響現有行為。**測試分層依 `review-issues.md` Important #2**：狀態機正確性（暫停/恢復判斷邏輯）在純 Dart 層以 Fake 事件源徹底覆蓋（`TtsAudioFocusCoordinator`/`TtsAudioHandler` 各自的單元測試，不依賴真實系統廣播）；`ReaderScreen` 層測試因既有「`flutter_test` 環境下 `FoliateReaderView._controller` 恆為 `null`、`loadSegments()` 恆回傳空清單、`TtsController` 永遠不會真正進入 `playing`」誠實測試邊界（Issue 5 `plan-issue-5.md` 已確立），只能驗證接線本身不崩潰、依賴正確貫穿，無法在這層驗證「暫停真的發生」；真正的系統整合正確性（通知欄顯示、耳機線控、來電中斷、背景恢復高亮同步）留給真機手動驗收清單（見本計畫「測試策略總結」）。

**Tech Stack:** `audio_service: ^0.18.19`（背景前景服務、MediaSession、通知欄/鎖定畫面控制、耳機線控）＋ `audio_session: ^0.2.4`（Android 音訊焦點/耳機拔出事件的跨平台抽象，`audio_service` 的既有相依）。兩者版本已於 Issue 1 `dependency-spike-findings.md` 驗證與現有相依鏈（`flutter_inappwebview`／`pdfrx`／`sqflite`）無衝突，minSdk 分別為 19／未宣告獨立 minSdk，皆不拉高專案現有 `minSdk=24`。

**Spec:** `docs/epics/epic-34-tts-readalong/issues.md`「Issue 7」；`docs/epics/epic-34-tts-readalong/spec.md`「`TtsController`」Audio Focus 中斷處理段落、「`ReaderScreen` 整合」段落；`docs/epics/epic-34-tts-readalong/dependency-spike-findings.md`「targetSdk manifest 需求清單」（本計畫規劃階段查證發現此清單遺漏 `WAKE_LOCK` 權限，見 Task 1 說明）；`docs/epics/epic-34-tts-readalong/design.md`「App 背景/前景切換時的高亮同步落差」。

## Global Constraints

- **`AudioService.init()`全程式生命週期只能呼叫一次**（`audio_service` 套件原始碼 `assert(_cacheManager == null)` 強制）：必須在 `main()` 呼叫一次、建構單一長駐 `TtsAudioHandler`，不可在 `ReaderScreen` 每次開書時呼叫。
- **不修改 `TtsController` 既有播放邏輯**（`play()`/`pause()`/`nextSegment()`/`previousSegment()`/`setSpeed()`/`_playCurrentSegment()` 等既有方法簽章與行為皆不變）：本 Issue 新增的協調層一律透過呼叫這些既有公開方法達成效果，只新增一個全新方法 `resyncHighlight()`。
- **`MainActivity` 必須維持 `FragmentActivity` 家族**（`CLAUDE.md`「不要嘗試改回 `FlutterActivity`」）：`AudioServiceFragmentActivity`（`audio_service` 套件提供）本身即 `extends FlutterFragmentActivity`，改繼承它不違反此限制，資料夾匯入功能既有的 `registerForActivityResult` 不受影響。
- **CBZ 天然不受影響**：`TtsController`／`TtsAudioFocusCoordinator`／`TtsAudioHandler` 三者皆只在 `_ttsControllerOrNull` getter 首次被存取時才建構（Issue 6 審查修復後，CBZ 格式的 Mini Player 分支已改為完全不存取這個 getter，見 `reader_screen.dart:2226-2243`），本 Issue 不需要另外處理 CBZ 排除。
- **不涉及 Issue 8（E-Ink 安全視窗）範圍**：`resyncHighlight()` 只重送高亮，不觸發翻頁/捲動；design.md 原文提到的「翻頁指令」留給 Issue 8 完成後另行串接。
- **不涉及 Phase 2/3（雲端 API／端側神經語音）範圍**：`TtsAudioHandler` 的 `MediaItem` 只包含書名（`title`），不含封面圖（`artUri`）——避免引入額外的圖片載入/快取邏輯，非本 Issue 驗收標準要求。
- **新增檔案沿用既有扁平結構**（`app/lib/reader/`，比照 `tts_controller.dart`／`tts_audio_player.dart` 既有慣例，不建子目錄）；測試沿用既有慣例（`app/test/reader/<unit>_test.dart`，Fake 測試替身放 `app/test/support/`，比照 `fake_tts_audio_player.dart`／`fake_tts_provider.dart` 既有前例）。

---

### Task 1：Android 平台設定——套件相依性、`AndroidManifest.xml`、`MainActivity`

**Files:**
- Modify: `app/pubspec.yaml`
- Modify: `app/android/app/src/main/AndroidManifest.xml`
- Modify: `app/android/app/src/main/kotlin/cc/ugotit/elinkbook/MainActivity.kt`
- Modify: `docs/epics/epic-34-tts-readalong/dependency-spike-findings.md`

**規劃階段查證**：直接核對本機 pub cache 內 `audio_service-0.18.19`／`audio_session-0.2.4` 套件原始碼與官方 `README.md`「Android setup」段落（`C:\Users\huthief\AppData\Local\Pub\Cache\hosted\pub.dev\audio_service-0.18.19\README.md` 第 320-355 行），確認官方要求的 manifest 宣告清單與 `dependency-spike-findings.md`「targetSdk manifest 需求清單」（Issue 1 產出）逐項核對：`FOREGROUND_SERVICE`／`FOREGROUND_SERVICE_MEDIA_PLAYBACK`／`<service>`／`<receiver>`／`exported="true"` 五項完全吻合；但官方文件另外要求 **`android.permission.WAKE_LOCK`**（`dependency_spike-findings.md` 清單遺漏此項，Issue 1 spike 未涵蓋——本 Task 一併補上並在該文件加註記錄，不重新調查其餘四項）。`MainActivity` 部分核對 README「Custom Android activity」段落：本專案 `MainActivity` 是自訂 `FragmentActivity`（`.MainActivity`，非套件預設的 `AudioServiceActivity`），須改繼承套件提供的 `AudioServiceFragmentActivity`（`extends FlutterFragmentActivity`，內部把 `provideFlutterEngine()`/`getCachedEngineId()`/`shouldDestroyEngineWithHost()` 導向 `audio_service` 管理的共用 `FlutterEngine`，讓背景服務與 UI 共用同一個 Dart isolate，這樣 `TtsAudioHandler` 才能直接持有前景 `ReaderScreen` 建構出的同一個 `TtsController` 實例，不需要跨 isolate 通訊）——原始碼位置：`C:\Users\huthief\AppData\Local\Pub\Cache\hosted\pub.dev\audio_service-0.18.19\android\src\main\java\com\ryanheise\audioservice\AudioServiceFragmentActivity.java`。

- [x] **Step 1：`pubspec.yaml` 新增相依套件**

在 `app/pubspec.yaml` 找到既有：

```yaml
  # TTS 本機音訊播放（epic-34-tts-readalong Issue 2）：見
  # dependency-spike-findings.md，minSdk=16，未拉高專案現有下限。
  just_audio: ^0.10.6
```

緊接其後新增：

```yaml
  # TTS 背景播放與系統整合（epic-34-tts-readalong Issue 7）：前景服務、
  # 通知欄/鎖定畫面控制、耳機線控，見 dependency-spike-findings.md，
  # minSdk=19，未拉高專案現有下限。
  audio_service: ^0.18.19
  # TTS 音訊焦點中斷/耳機拔出事件（epic-34-tts-readalong Issue 7）：
  # audio_service 的既有相依，本專案額外顯式宣告以直接呼叫其 API
  # （AudioSession.instance／interruptionEventStream／
  # becomingNoisyEventStream），不依賴透過遞移相依隱式取用。
  audio_session: ^0.2.4
```

- [x] **Step 2：安裝相依套件**

```
flutter pub get
```

Expected：解析成功，無版本衝突（Issue 1 spike 已驗證過相容性，本次為正式加入 `pubspec.yaml` 後的覆核）。

- [x] **Step 3：`AndroidManifest.xml` 新增權限、Service、Receiver**

在 `app/android/app/src/main/AndroidManifest.xml` 第一行，`<manifest>` 根元素新增 `xmlns:tools` 命名空間（`tools:ignore="Instantiatable"` 屬性需要）：

```xml
<manifest xmlns:android="http://schemas.android.com/apk/res/android"
    xmlns:tools="http://schemas.android.com/tools">
```

找到既有的：

```xml
    <uses-permission android:name="android.permission.INTERNET"/>
```

緊接其後新增（`WAKE_LOCK`／`FOREGROUND_SERVICE`／`FOREGROUND_SERVICE_MEDIA_PLAYBACK`／`POST_NOTIFICATIONS` 四項，依 `dependency-spike-findings.md`「targetSdk manifest 需求清單」＋本 Task 規劃階段查證補上的 `WAKE_LOCK`）：

```xml
    <!-- epic-34-tts-readalong Issue 7：audio_service 背景播放前景服務所需
         權限（見 dependency-spike-findings.md「targetSdk manifest 需求
         清單」；WAKE_LOCK 為本 Issue 規劃階段查證官方 README 後補上，
         Issue 1 spike 原清單遺漏此項）。 -->
    <uses-permission android:name="android.permission.WAKE_LOCK"/>
    <uses-permission android:name="android.permission.FOREGROUND_SERVICE"/>
    <uses-permission android:name="android.permission.FOREGROUND_SERVICE_MEDIA_PLAYBACK"/>
    <uses-permission android:name="android.permission.POST_NOTIFICATIONS"/>
```

找到既有的（`<application>` 區塊內最後一個元素）：

```xml
        <provider
            android:name="androidx.core.content.FileProvider"
            android:authorities="${applicationId}.fileprovider"
            android:exported="false"
            android:grantUriPermissions="true">
            <meta-data
                android:name="android.support.FILE_PROVIDER_PATHS"
                android:resource="@xml/file_paths" />
        </provider>
    </application>
```

改為（在 `</application>` 前新增 `<service>`／`<receiver>`）：

```xml
        <provider
            android:name="androidx.core.content.FileProvider"
            android:authorities="${applicationId}.fileprovider"
            android:exported="false"
            android:grantUriPermissions="true">
            <meta-data
                android:name="android.support.FILE_PROVIDER_PATHS"
                android:resource="@xml/file_paths" />
        </provider>

        <!-- epic-34-tts-readalong Issue 7：audio_service 背景播放服務，
             宣告內容逐字核對自套件官方參考實作（見本計畫「規劃階段查證」）。
             exported="true" 是必要值，非疏漏——MediaButtonReceiver 需要
             接收系統層（藍牙/有線耳機線控）送進來的按鍵廣播，AudioService
             需要接收系統媒體瀏覽器查詢；兩者皆設為 false 會讓耳機線控與
             背景服務啟動整組失效。 -->
        <service
            android:name="com.ryanheise.audioservice.AudioService"
            android:foregroundServiceType="mediaPlayback"
            android:exported="true"
            tools:ignore="Instantiatable">
            <intent-filter>
                <action android:name="android.media.browse.MediaBrowserService" />
            </intent-filter>
        </service>

        <receiver
            android:name="com.ryanheise.audioservice.MediaButtonReceiver"
            android:exported="true"
            tools:ignore="Instantiatable">
            <intent-filter>
                <action android:name="android.intent.action.MEDIA_BUTTON" />
            </intent-filter>
        </receiver>
    </application>
```

- [x] **Step 4：`MainActivity.kt` 改繼承 `AudioServiceFragmentActivity`**

在 `app/android/app/src/main/kotlin/cc/ugotit/elinkbook/MainActivity.kt` 找到既有的 import：

```kotlin
import io.flutter.embedding.android.FlutterFragmentActivity
import io.flutter.embedding.engine.FlutterEngine
```

改為（移除不再直接使用的 `FlutterFragmentActivity` import，新增 `AudioServiceFragmentActivity` import——`AudioServiceFragmentActivity` 本身 `extends FlutterFragmentActivity`，不需要同時 import 兩者）：

```kotlin
import com.ryanheise.audioservice.AudioServiceFragmentActivity
import io.flutter.embedding.engine.FlutterEngine
```

找到既有的類別宣告：

```kotlin
class MainActivity : FlutterFragmentActivity() {
```

改為：

```kotlin
class MainActivity : AudioServiceFragmentActivity() {
```

其餘程式碼（`onCreate`／`dispatchKeyEvent`／`configureFlutterEngine`／`onDestroy` 等既有方法）完全不需要改動——`AudioServiceFragmentActivity` 只覆寫 `provideFlutterEngine()`/`getCachedEngineId()`/`shouldDestroyEngineWithHost()` 三個方法，本檔案原本就沒有覆寫過這三者，不會產生衝突。

- [x] **Step 5：`dependency-spike-findings.md` 補上遺漏權限的修正記錄**

在 `docs/epics/epic-34-tts-readalong/dependency-spike-findings.md` 找到既有的：

```
## targetSdk manifest 需求清單（供 Issue 7 落實）
```

緊接其後新增一段（保留原清單五項不動，只新增說明段落，理由同本文件開頭既有的「審查修訂」寫法慣例——記錄事後發現的落差，不回頭假裝原清單完整）：

```
**Issue 7 落實時的追加修正**：官方 `audio_service` 套件 README「Android setup」段落另要求 `android.permission.WAKE_LOCK`（前景服務保持 CPU 喚醒狀態所需），本清單原五項遺漏此項——Issue 1 spike 階段核對的是套件 `example/android/app/src/main/AndroidManifest.xml`（該檔案第 5 行確實含此權限，但撰寫本清單時漏抄）。Issue 7 落實時已直接依 README 正文重新核對並補上，見 `plans/plan-issue-7.md` Task 1「規劃階段查證」。
```

- [x] **Step 6：驗證建置**

```
flutter analyze
```

Expected：`No issues found!`（本 Task 純設定變更，無 Dart 邏輯異動，`flutter test` 基準線不受影響、不需要重跑）。

```
flutter build apk --debug
```

Expected：建置成功——這是本 Task 唯一能驗證的「正確性」層級：`AndroidManifest.xml` XML 語法正確、`MainActivity.kt` 繼承鏈可編譯、`audio_service`/`audio_session` 原生端 Gradle 相依可解析。實際背景播放/通知欄/耳機線控行為須留待真機驗收（見本計畫「測試策略總結」），本 Task 範圍不含。

- [x] **Step 7：Commit**

```bash
git add app/pubspec.yaml app/pubspec.lock app/android/app/src/main/AndroidManifest.xml app/android/app/src/main/kotlin/cc/ugotit/elinkbook/MainActivity.kt docs/epics/epic-34-tts-readalong/dependency-spike-findings.md
git commit -m "feat(epic-34): Android 平台設定——audio_service 依賴與 Manifest（Issue 7 Task 1）"
```

---

### Task 2：`TtsController.resyncHighlight()`（TDD）

**Files:**
- Modify: `app/lib/reader/tts_controller.dart`
- Test: `app/test/reader/tts_controller_test.dart`

**Interfaces:**
- Consumes：既有 `TtsController` 私有欄位 `_status`／`_segments`／`_currentIndex`／`_disposed`、既有建構參數 `onHighlightSegment`。
- Produces：`void resyncHighlight()`（公開方法，`TtsController` 新增），供 Task 6 `ReaderScreen` 呼叫。

- [ ] **Step 1：寫失敗測試**

在 `app/test/reader/tts_controller_test.dart` 找到既有的最後一個 `test(...)` 區塊結尾（檔案內搜尋最後一次出現的 `});`，緊接其後、`main()` 收尾 `}` 之前）新增：

```dart
  test('resyncHighlight() 於 idle 狀態（從未播放過）為 no-op，不呼叫 onHighlightSegment', () {
    TtsSegmentCfi? received;
    var callCount = 0;
    final controller = TtsController(
      provider: FakeTtsProvider(),
      player: FakeTtsAudioPlayer(),
      loadSegments: () async => segments,
      onHighlightSegment: (segment) {
        received = segment;
        callCount++;
      },
    );
    controller.resyncHighlight();
    expect(callCount, 0);
    expect(received, isNull);
  });

  test('resyncHighlight() 於 playing 狀態重新呼叫 onHighlightSegment，帶目前段落', () async {
    TtsSegmentCfi? received;
    var callCount = 0;
    final provider = FakeTtsProvider();
    final player = FakeTtsAudioPlayer();
    final controller = TtsController(
      provider: provider,
      player: player,
      loadSegments: () async => segments,
      onHighlightSegment: (segment) {
        received = segment;
        callCount++;
      },
    );
    await controller.play();
    final callCountAfterPlay = callCount;

    controller.resyncHighlight();

    expect(callCount, callCountAfterPlay + 1,
        reason: 'resyncHighlight() 應額外觸發一次 onHighlightSegment');
    expect(received, segments[0]);
  });

  test('resyncHighlight() 於 disposed 後為 no-op（不拋出例外）', () async {
    final controller = buildController();
    await controller.play();
    controller.dispose();

    expect(() => controller.resyncHighlight(), returnsNormally);
  });
```

- [ ] **Step 2：跑測試確認新增測試皆失敗**

```
flutter test test/reader/tts_controller_test.dart
```

Expected：FAIL——`resyncHighlight` 方法尚不存在，編譯期即報錯。

- [ ] **Step 3：實作 `resyncHighlight()`**

在 `app/lib/reader/tts_controller.dart` 找到既有 `handleExternalPositionChange()` 方法結尾（第 276 行 `}`）與其後的 `_segmentGeneration` 欄位文件註解（第 278 行起）之間，插入：

```dart

  /// App 從背景恢復前景時，主動重新送出目前播放位置對應的高亮（
  /// epic-34-tts-readalong Issue 7，spec.md「TtsController」Audio Focus
  /// 段落前的 User Story 28，對應 design.md「App 背景/前景切換時的高亮
  /// 同步落差」／`review-design.md` Important #3）。呼叫端（[ReaderScreen]）
  /// 在 `didChangeAppLifecycleState` 的 `AppLifecycleState.resumed` 分支
  /// 無條件呼叫本方法即可，不需要自行判斷「目前是否正在播放」——`idle`
  /// 狀態下為 no-op（沒有目前段落可以重新顯示），比照 [handleExternalPositionChange]
  /// 既有的「呼叫端無條件呼叫、內部自行判斷是否需要動作」設計慣例。
  ///
  /// **只重送「高亮」，不含 design.md 原文一併提到的「翻頁指令」**：安全
  /// 視窗跟隨翻頁機制是 Issue 8（尚未實作）的範圍，本方法目前只能重新
  /// 顯示高亮本身，不觸發任何捲動/翻頁；Issue 8 完成後若需要一併重新
  /// 觸發跟隨翻頁，屬於該 Issue 落地時的範圍，本方法不預先假設其存在。
  void resyncHighlight() {
    if (_disposed) return;
    if (_status == TtsPlaybackStatus.idle) return;
    onHighlightSegment?.call(_segments[_currentIndex]);
  }
```

**審查 `review-plan-issue-7.md` 4.1（`_currentIndex` 邊界檢查）不採納**：`_status != idle` 時 `_currentIndex` 恆為 `_segments` 的合法索引，這個不變量是結構性成立的——`play()` 的 `idle` 分支內，`_segments`／`_currentIndex` 賦值與 `_status` 變成非 `idle`（`_playCurrentSegment()` 內）之間沒有任何 `await` 造成的執行權讓渡（Dart 單執行緒，同步程式碼區塊不會被其他呼叫插入），不存在「狀態非 idle 但索引無效」的可達路徑；本類別既有的 `_playCurrentSegment()`（第 296 行）本身就是 `_segments[_currentIndex]` 直接存取、無邊界檢查，是同一個不變量的既有先例。加上邊界檢查不會讓程式更正確，只會讓 `resyncHighlight()` 跟同類別內這個既有先例的寫法不一致，屬於 `CLAUDE.md`「不要為不可能發生的情境新增驗證」明確排除的情況，故維持上方程式碼原樣，不加此檢查。

- [ ] **Step 4：跑測試確認全數通過**

```
flutter test test/reader/tts_controller_test.dart
```

Expected：全數 PASS（含既有測試零回歸＋新增 3 個測試）。

```
flutter analyze
```

Expected：`No issues found!`

- [ ] **Step 5：Commit**

```bash
git add app/lib/reader/tts_controller.dart app/test/reader/tts_controller_test.dart
git commit -m "feat(epic-34): TtsController 新增 resyncHighlight()（Issue 7 Task 2）"
```

---

### Task 3：`TtsAudioFocusSource`／`TtsAudioFocusCoordinator`（TDD）

**Files:**
- Create: `app/lib/reader/tts_audio_focus_source.dart`
- Create: `app/lib/reader/tts_audio_focus_coordinator.dart`
- Create: `app/test/support/fake_tts_audio_focus_source.dart`
- Test: `app/test/reader/tts_audio_focus_coordinator_test.dart`

**規劃階段查證**：直接核對本機 pub cache `audio_session-0.2.4` 原始碼（`C:\Users\huthief\AppData\Local\Pub\Cache\hosted\pub.dev\audio_session-0.2.4\lib\src\core.dart`／`android.dart`）確認事件對應規則：`AudioSession.interruptionEventStream` 送出 `AudioInterruptionEvent(begin, type)`，Android 端原生 `AudioManager` 焦點變化的對應規則（`core.dart` 第 254-286 行）為——`AndroidAudioFocus.loss`（永久失焦）→ `AudioInterruptionEvent(true, AudioInterruptionType.unknown)`；`AndroidAudioFocus.lossTransient`（暫時失焦）→ `AudioInterruptionEvent(true, AudioInterruptionType.pause)`；`AndroidAudioFocus.lossTransientCanDuck`（可降低音量的暫時失焦）在 `androidWillPauseWhenDucked: true` 設定下同樣映射為 `AudioInterruptionEvent(true, AudioInterruptionType.pause)`（本 Issue 對語音朗讀內容採用此設定——降低音量的人聲朗讀無法辨識，等同必須暫停，不採用「降低音量繼續播放」的 duck 語意）；`AndroidAudioFocus.gain`（焦點恢復）→ `AudioInterruptionEvent(false, ...)`。`AudioSession.becomingNoisyEventStream`（耳機拔出／輸出裝置變化）為獨立的 `Stream<void>`。

**Interfaces:**
- Consumes：`TtsController`（Issue 2/4/5，`play()`／`pause()`／`status` getter）。
- Produces：
  - `enum TtsAudioFocusEvent { transientLoss, permanentLoss, focusGained, becomingNoisy }`
  - `abstract class TtsAudioFocusSource { Stream<TtsAudioFocusEvent> get events; void dispose(); }`
  - `class AudioSessionFocusSource implements TtsAudioFocusSource`（建構參數 `AudioSession session`，`audio_session` 套件型別）
  - `class TtsAudioFocusCoordinator`（建構參數 `source`／`controller` 皆必要；`void dispose()`）

供 Task 6 `ReaderScreen` 使用；`FakeTtsAudioFocusSource` 供本 Task 與 Task 6 測試共用。

- [ ] **Step 1：寫失敗測試——先建立 Fake 測試替身**

建立 `app/test/support/fake_tts_audio_focus_source.dart`：

```dart
import 'dart:async';

import 'package:elinkbook/reader/tts_audio_focus_source.dart';

/// 測試用 Fake，比照 [FakeTtsAudioPlayer] 模式。[emit] 讓測試主動送出
/// 合成的焦點事件，不依賴真實系統廣播（epic-34-tts-readalong Issue 7，
/// 審查 `review-issues.md` Important #2「測試分流」自動化層）。
class FakeTtsAudioFocusSource implements TtsAudioFocusSource {
  final StreamController<TtsAudioFocusEvent> _controller =
      StreamController<TtsAudioFocusEvent>.broadcast();
  bool disposed = false;

  @override
  Stream<TtsAudioFocusEvent> get events => _controller.stream;

  void emit(TtsAudioFocusEvent event) => _controller.add(event);

  @override
  void dispose() {
    disposed = true;
    _controller.close();
  }
}
```

- [ ] **Step 2：寫失敗測試——`TtsAudioFocusCoordinator` 狀態機**

建立 `app/test/reader/tts_audio_focus_coordinator_test.dart`：

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:elinkbook/reader/tts_audio_focus_coordinator.dart';
import 'package:elinkbook/reader/tts_audio_focus_source.dart';
import 'package:elinkbook/reader/tts_controller.dart';
import 'package:elinkbook/reader/tts_segment_cfi.dart';

import '../support/fake_tts_audio_focus_source.dart';
import '../support/fake_tts_audio_player.dart';
import '../support/fake_tts_provider.dart';

void main() {
  const segments = [
    TtsSegmentCfi(segmentId: '0', cfi: 'epubcfi(/6/4!/1:0)', text: '第一句。'),
    TtsSegmentCfi(segmentId: '1', cfi: 'epubcfi(/6/4!/1:5)', text: '第二句。'),
  ];

  late FakeTtsAudioFocusSource source;
  late TtsController controller;
  late FakeTtsAudioPlayer player;

  TtsAudioFocusCoordinator buildCoordinator() {
    source = FakeTtsAudioFocusSource();
    player = FakeTtsAudioPlayer();
    controller = TtsController(
      provider: FakeTtsProvider(),
      player: player,
      loadSegments: () async => segments,
    );
    return TtsAudioFocusCoordinator(source: source, controller: controller);
  }

  test('暫時失焦（transientLoss）時，播放中的 controller 會被暫停', () async {
    buildCoordinator();
    await controller.play();
    expect(controller.status, TtsPlaybackStatus.playing);

    source.emit(TtsAudioFocusEvent.transientLoss);

    expect(controller.status, TtsPlaybackStatus.paused);
  });

  test('暫時失焦後焦點恢復（focusGained），因暫停係本協調器造成，自動恢復播放', () async {
    buildCoordinator();
    await controller.play();

    source.emit(TtsAudioFocusEvent.transientLoss);
    expect(controller.status, TtsPlaybackStatus.paused);

    source.emit(TtsAudioFocusEvent.focusGained);

    expect(controller.status, TtsPlaybackStatus.playing);
    expect(player.callLog.last, 'play');
  });

  test('使用者手動暫停後才發生焦點恢復事件，不會被誤觸自動播放', () async {
    buildCoordinator();
    await controller.play();
    controller.pause(); // 使用者手動暫停，非本協調器造成
    expect(controller.status, TtsPlaybackStatus.paused);

    source.emit(TtsAudioFocusEvent.focusGained);

    expect(controller.status, TtsPlaybackStatus.paused,
        reason: '使用者手動暫停不應被焦點恢復事件自動喚醒播放');
  });

  test('暫時失焦期間使用者手動翻頁（狀態被重設為 idle），焦點恢復後不會自動開始播放新內容'
      '（審查 review-plan-issue-7.md 4.2）', () async {
    buildCoordinator();
    await controller.play();

    source.emit(TtsAudioFocusEvent.transientLoss);
    expect(controller.status, TtsPlaybackStatus.paused);

    // 使用者在失焦期間手動翻頁/跳章，ReaderScreen 的 onLocatorChanged 會
    // 呼叫本方法，把狀態完全重設為 idle（見 TtsController 既有文件：
    // 手動導覽視為「舊朗讀段清單已不適用」，不是「暫停中待恢復」）。
    controller.handleExternalPositionChange();
    expect(controller.status, TtsPlaybackStatus.idle);
    final callLogLengthBeforeFocusGained = player.callLog.length;

    source.emit(TtsAudioFocusEvent.focusGained);

    expect(controller.status, TtsPlaybackStatus.idle,
        reason: '狀態已因手動導覽變成 idle，不應被焦點恢復事件誤觸自動播放'
            '（那會變成沒被要求就從新頁面開始朗讀）');
    expect(player.callLog.length, callLogLengthBeforeFocusGained,
        reason: 'player 不應在使用者未主動按下播放鍵的情況下收到任何新呼叫'
            '（idle 狀態下 controller.play() 會走 loadSegments()/'
            'lookupStartIndex() 全新流程，不該被觸發）');
  });

  test('永久失焦（permanentLoss）時暫停，且焦點恢復後不自動恢復播放', () async {
    buildCoordinator();
    await controller.play();

    source.emit(TtsAudioFocusEvent.permanentLoss);
    expect(controller.status, TtsPlaybackStatus.paused);

    source.emit(TtsAudioFocusEvent.focusGained);

    expect(controller.status, TtsPlaybackStatus.paused,
        reason: '永久失焦造成的暫停，等同使用者手動暫停，不應自動恢復');
  });

  test('耳機拔出（becomingNoisy）時暫停，且不會自動恢復播放', () async {
    buildCoordinator();
    await controller.play();

    source.emit(TtsAudioFocusEvent.becomingNoisy);
    expect(controller.status, TtsPlaybackStatus.paused);

    source.emit(TtsAudioFocusEvent.focusGained);

    expect(controller.status, TtsPlaybackStatus.paused,
        reason: '耳機拔出的暫停不應自動恢復，避免拔出耳機後突然透過喇叭外放');
  });

  test('尚未開始播放（idle）時發生暫時失焦事件，不會產生任何動作', () async {
    buildCoordinator();
    expect(controller.status, TtsPlaybackStatus.idle);

    source.emit(TtsAudioFocusEvent.transientLoss);

    expect(controller.status, TtsPlaybackStatus.idle);
    expect(player.callLog, isEmpty);
  });

  test('dispose() 後不再回應事件', () async {
    final coordinator = buildCoordinator();
    await controller.play();
    coordinator.dispose();

    source.emit(TtsAudioFocusEvent.transientLoss);
    await Future<void>.delayed(Duration.zero);

    expect(controller.status, TtsPlaybackStatus.playing,
        reason: 'dispose() 後协調器不應再訂閱事件、不應再操作 controller');
  });
}
```

- [ ] **Step 3：跑測試確認全數失敗**

```
flutter test test/reader/tts_audio_focus_coordinator_test.dart
```

Expected：FAIL——`package:elinkbook/reader/tts_audio_focus_source.dart`／`tts_audio_focus_coordinator.dart` 尚不存在，編譯期即報錯。

- [ ] **Step 4：實作 `TtsAudioFocusSource`／`AudioSessionFocusSource`**

建立 `app/lib/reader/tts_audio_focus_source.dart`：

```dart
import 'package:audio_session/audio_session.dart';

/// 音訊焦點事件（epic-34-tts-readalong Issue 7，spec.md「Audio Focus
/// 中斷處理」）。跨平台抽象——不直接暴露 Android
/// `AudioManager.OnAudioFocusChangeListener` 或 `audio_session` 套件的
/// [AudioInterruptionEvent] 型別，讓 [TtsAudioFocusCoordinator] 可用
/// Fake 事件源做純 Dart 單元測試（審查 `review-issues.md` Important #2
/// 「測試分流」自動化層）。
enum TtsAudioFocusEvent {
  /// 暫時失去焦點（Android `AUDIOFOCUS_LOSS_TRANSIENT`，例如來電、導航
  /// 語音、系統通知音）：應暫停播放，焦點恢復時自動恢復。
  transientLoss,

  /// 永久失去焦點（Android `AUDIOFOCUS_LOSS`，例如使用者開啟其他音樂/
  /// Podcast App）：應暫停播放，且不自動恢復。
  permanentLoss,

  /// 焦點恢復（Android `AUDIOFOCUS_GAIN`）。
  focusGained,

  /// 耳機/藍牙裝置拔出（`AudioSession.becomingNoisyEventStream`）：應
  /// 暫停播放，且不自動恢復（避免拔出耳機後突然透過喇叭外放）。
  becomingNoisy,
}

/// [TtsAudioFocusEvent] 事件來源抽象。存在的唯一理由同
/// [TtsAudioPlayer]（`tts_audio_player.dart`）——讓
/// [TtsAudioFocusCoordinator] 可在純 Dart 單元測試中注入 Fake 實作，
/// `audio_session` 依賴平台 channel，`flutter test` 環境下無法產生真實
/// 系統廣播。
abstract class TtsAudioFocusSource {
  Stream<TtsAudioFocusEvent> get events;

  void dispose();
}

/// [TtsAudioFocusSource] 的正式實作，包一層 `audio_session` 的
/// [AudioSession]。事件對應規則見 `plans/plan-issue-7.md` Task 3「規劃
/// 階段查證」：Android `AudioManager` 的
/// `loss`/`lossTransient`/`lossTransientCanDuck`/`gain` 四種焦點變化，
/// 經 `audio_session` 轉譯為 [AudioInterruptionEvent]（`begin`＋`type`
/// 兩個欄位），本類別再把這組二維組合收斂為 [TtsAudioFocusEvent] 這個
/// 一維列舉，供 [TtsAudioFocusCoordinator] 使用。
///
/// 合併後的事件流在**建構子內一次性**訂閱底層 `AudioSession` 的兩條
/// 串流並存成欄位（而非每次讀取 [events] 這個 getter 時才即時訂閱）——
/// 避免 [events] 被存取超過一次時（目前呼叫端 [TtsAudioFocusCoordinator]
/// 只會存取一次，但介面本身不應假設呼叫端只存取一次）產生重複訂閱，讓
/// [dispose] 能明確對應到唯一一組訂閱、確實可以取消。
class AudioSessionFocusSource implements TtsAudioFocusSource {
  final StreamController<TtsAudioFocusEvent> _controller =
      StreamController<TtsAudioFocusEvent>.broadcast();
  late final StreamSubscription<AudioInterruptionEvent> _interruptionSub;
  late final StreamSubscription<void> _noisySub;

  AudioSessionFocusSource(AudioSession session) {
    _interruptionSub = session.interruptionEventStream.listen((event) {
      if (!event.begin) {
        _controller.add(TtsAudioFocusEvent.focusGained);
        return;
      }
      // AudioInterruptionType.unknown 對應 Android AUDIOFOCUS_LOSS
      // （永久失焦）；pause／duck（本專案設定 androidWillPauseWhenDucked:
      // true 後，duck 事件不會發生，一律以 pause 型別送達）皆對應
      // AUDIOFOCUS_LOSS_TRANSIENT（暫時失焦）。
      _controller.add(event.type == AudioInterruptionType.unknown
          ? TtsAudioFocusEvent.permanentLoss
          : TtsAudioFocusEvent.transientLoss);
    });
    _noisySub = session.becomingNoisyEventStream.listen(
      (_) => _controller.add(TtsAudioFocusEvent.becomingNoisy),
    );
  }

  @override
  Stream<TtsAudioFocusEvent> get events => _controller.stream;

  @override
  void dispose() {
    // AudioSession 本身為 main.dart 建構、App 全生命週期共用的單例，本
    // 類別不擁有其生命週期、不關閉它；只取消自己對它的兩條訂閱。
    // main.dart 目前不會呼叫本方法（App 行程存續期間持續有效，比照既有
    // syncEngine/repository 等 main.dart 層級單例從不顯式 dispose 的
    // 既有慣例），但方法本身要能正確運作，供未來需要時或測試使用。
    _interruptionSub.cancel();
    _noisySub.cancel();
    _controller.close();
  }
}
```

`app/lib/reader/tts_audio_focus_source.dart` 頂端補上 `import 'dart:async';`（`StreamController`／`StreamSubscription` 需要）。

- [ ] **Step 5：實作 `TtsAudioFocusCoordinator`**

建立 `app/lib/reader/tts_audio_focus_coordinator.dart`：

```dart
import 'dart:async';

import 'tts_audio_focus_source.dart';
import 'tts_controller.dart';

/// 把 [TtsAudioFocusSource] 送出的系統音訊焦點/耳機事件，轉譯成
/// [TtsController.pause]／[TtsController.play] 呼叫（epic-34-tts-readalong
/// Issue 7，spec.md「Audio Focus 中斷處理」契約）。純 Dart、不依賴
/// Flutter widget 樹，呼叫端（[ReaderScreen]）於 [TtsController] 建構
/// 完成後一併建構本類別，比照 [TtsController] 本身「純 Dart 協調者」的
/// 既有設計慣例（不知道 `ReaderScreen`／WebView 存在）。
///
/// **只有本協調器自己造成的暫停才會在焦點恢復時自動播放**——
/// [_pausedByFocus] 只在「暫時失焦發生時，[controller] 原本正在播放」
/// 這個條件下才被設為 `true`；使用者手動呼叫 [TtsController.pause]、或
/// 永久失焦、或耳機拔出造成的暫停，皆不會設定此旗標，焦點恢復事件對它們
/// 是無操作。
///
/// **焦點恢復時額外核對 `controller.status` 仍為 `paused`**（審查
/// `review-plan-issue-7.md` 4.2 採納）：暫時失焦期間（例如來電中），
/// 使用者可能手動翻頁/跳章，觸發 [TtsController.handleExternalPositionChange]
/// 把狀態重設為 `idle`（見該方法文件：手動導覽一律視為「舊的朗讀段清單
/// 已不適用，完全重設」，不是「暫停中，等待從原位置恢復」）——這個過程
/// 完全不經過本協調器，[_pausedByFocus] 不會被連動清除。若此時只憑
/// [_pausedByFocus] 就呼叫 [TtsController.play]，會在使用者沒有主動按
/// 播放鍵的情況下，從使用者剛剛翻到的新頁面自動開始朗讀——這不是「恢復
/// 被系統打斷的播放」，而是背著使用者開始一次全新的播放，超出「自動恢復」
/// 這句契約的原意。只有 `controller.status` 在焦點恢復當下仍確實是
/// [TtsPlaybackStatus.paused]（代表狀態機從失焦以來沒有被其他事件改
/// 變過）才呼叫 [TtsController.play]。
class TtsAudioFocusCoordinator {
  final TtsAudioFocusSource source;
  final TtsController controller;

  StreamSubscription<TtsAudioFocusEvent>? _sub;
  bool _pausedByFocus = false;

  TtsAudioFocusCoordinator({required this.source, required this.controller}) {
    _sub = source.events.listen(_handleEvent);
  }

  void _handleEvent(TtsAudioFocusEvent event) {
    switch (event) {
      case TtsAudioFocusEvent.transientLoss:
        if (controller.status == TtsPlaybackStatus.playing) {
          _pausedByFocus = true;
          controller.pause();
        }
        break;
      case TtsAudioFocusEvent.permanentLoss:
      case TtsAudioFocusEvent.becomingNoisy:
        _pausedByFocus = false;
        controller.pause();
        break;
      case TtsAudioFocusEvent.focusGained:
        if (_pausedByFocus) {
          _pausedByFocus = false;
          if (controller.status == TtsPlaybackStatus.paused) {
            controller.play();
          }
        }
        break;
    }
  }

  void dispose() {
    _sub?.cancel();
    _sub = null;
  }
}
```

- [ ] **Step 6：跑測試確認全數通過**

```
flutter test test/reader/tts_audio_focus_coordinator_test.dart
```

Expected：全數 PASS（8 個測試，含審查 4.2 採納後新增的「暫時失焦期間使用者手動翻頁」情境）。

```
flutter analyze
```

Expected：`No issues found!`

- [ ] **Step 7：Commit**

```bash
git add app/lib/reader/tts_audio_focus_source.dart app/lib/reader/tts_audio_focus_coordinator.dart app/test/support/fake_tts_audio_focus_source.dart app/test/reader/tts_audio_focus_coordinator_test.dart
git commit -m "feat(epic-34): 新增 TtsAudioFocusSource／TtsAudioFocusCoordinator（Issue 7 Task 3）"
```

---

### Task 4：`TtsAudioHandler`（TDD）

**Files:**
- Create: `app/lib/reader/tts_audio_handler.dart`
- Test: `app/test/reader/tts_audio_handler_test.dart`

**規劃階段查證**：直接核對本機 pub cache `audio_service-0.18.19` 原始碼（`C:\Users\huthief\AppData\Local\Pub\Cache\hosted\pub.dev\audio_service-0.18.19\lib\audio_service.dart`）確認 `BaseAudioHandler` 是純 Dart 類別（內部欄位皆為 `rxdart` 的 `BehaviorSubject`，建構子 `BaseAudioHandler() : super._()` 不觸發任何平台 channel 呼叫），故本類別可在 `flutter test` 環境下直接建構/測試，不需要呼叫 `AudioService.init()`（該方法才會觸發平台 channel `configure()` 呼叫，且全程式生命週期只能呼叫一次，見 Global Constraints）。`BaseAudioHandler.click()` 預設實作（第 3089-3105 行）已經把單次媒體按鍵點擊依 `playbackState.playing` 分派成 `play()`/`pause()`，本類別不需要另外覆寫 `click()`。

**Interfaces:**
- Consumes：`TtsController`（`status`／`speed` getter、`play()`／`pause()`／`nextSegment()`／`previousSegment()`，`ChangeNotifier.addListener`/`removeListener`）。
- Produces：`class TtsAudioHandler extends BaseAudioHandler`，公開方法 `void attachController(TtsController controller, {required String bookTitle})`／`void detachController()`，供 Task 6 `ReaderScreen` 使用；`main.dart`（Task 5）以 `AudioService.init(builder: () => TtsAudioHandler(), ...)` 建構單一實例。

- [ ] **Step 1：寫失敗測試**

建立 `app/test/reader/tts_audio_handler_test.dart`：

```dart
import 'package:audio_service/audio_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:elinkbook/reader/tts_audio_handler.dart';
import 'package:elinkbook/reader/tts_controller.dart';
import 'package:elinkbook/reader/tts_segment_cfi.dart';

import '../support/fake_tts_audio_player.dart';
import '../support/fake_tts_provider.dart';

void main() {
  const segments = [
    TtsSegmentCfi(segmentId: '0', cfi: 'epubcfi(/6/4!/1:0)', text: '第一句。'),
    TtsSegmentCfi(segmentId: '1', cfi: 'epubcfi(/6/4!/1:5)', text: '第二句。'),
  ];

  late TtsController controller;
  late FakeTtsAudioPlayer player;

  TtsController buildRealController() {
    player = FakeTtsAudioPlayer();
    return TtsController(
      provider: FakeTtsProvider(),
      player: player,
      loadSegments: () async => segments,
    );
  }

  test('尚未 attachController 時，playbackState 維持初始 idle 狀態', () {
    final handler = TtsAudioHandler();
    expect(handler.playbackState.value.processingState, AudioProcessingState.idle);
    expect(handler.playbackState.value.playing, isFalse);
  });

  test('attachController 後，mediaItem 帶入書名，playbackState 反映 idle', () {
    final handler = TtsAudioHandler();
    controller = buildRealController();

    handler.attachController(controller, bookTitle: '紅樓夢');

    expect(handler.mediaItem.value?.title, '紅樓夢');
    expect(handler.playbackState.value.playing, isFalse);
    expect(handler.playbackState.value.processingState, AudioProcessingState.idle);
  });

  test('controller 開始播放後，playbackState.playing 同步變為 true', () async {
    final handler = TtsAudioHandler();
    controller = buildRealController();
    handler.attachController(controller, bookTitle: '紅樓夢');

    await controller.play();

    expect(handler.playbackState.value.playing, isTrue);
    expect(handler.playbackState.value.processingState, AudioProcessingState.ready);
  });

  test('handler.play()／pause() 轉發給目前綁定的 controller', () async {
    final handler = TtsAudioHandler();
    controller = buildRealController();
    handler.attachController(controller, bookTitle: '紅樓夢');

    await controller.play();
    await handler.pause();
    expect(controller.status, TtsPlaybackStatus.paused);

    await handler.play();
    expect(controller.status, TtsPlaybackStatus.playing);
  });

  test('handler.skipToNext()／skipToPrevious() 轉發給目前綁定的 controller', () async {
    final handler = TtsAudioHandler();
    controller = buildRealController();
    handler.attachController(controller, bookTitle: '紅樓夢');
    await controller.play();
    expect(controller.currentIndex, 0);

    await handler.skipToNext();
    expect(controller.currentIndex, 1);

    await handler.skipToPrevious();
    expect(controller.currentIndex, 0);
  });

  test('detachController 後，handler.play() 不再影響先前綁定的 controller', () async {
    final handler = TtsAudioHandler();
    controller = buildRealController();
    handler.attachController(controller, bookTitle: '紅樓夢');
    handler.detachController();

    await handler.play();

    expect(controller.status, TtsPlaybackStatus.idle,
        reason: 'detach 後 handler 不應再持有對舊 controller 的參照');
    expect(handler.playbackState.value.processingState, AudioProcessingState.idle);
  });

  test('attachController 兩次（換書），第二次會先解綁第一個 controller 的監聽', () async {
    final handler = TtsAudioHandler();
    final firstController = buildRealController();
    handler.attachController(firstController, bookTitle: '第一本書');

    final secondPlayer = FakeTtsAudioPlayer();
    final secondController = TtsController(
      provider: FakeTtsProvider(),
      player: secondPlayer,
      loadSegments: () async => segments,
    );
    handler.attachController(secondController, bookTitle: '第二本書');

    await firstController.play(); // 舊 controller 狀態變化不應再影響 handler
    expect(handler.mediaItem.value?.title, '第二本書');
    expect(handler.playbackState.value.playing, isFalse);
  });
}
```

- [ ] **Step 2：跑測試確認全數失敗**

```
flutter test test/reader/tts_audio_handler_test.dart
```

Expected：FAIL——`package:elinkbook/reader/tts_audio_handler.dart` 尚不存在，編譯期即報錯。

- [ ] **Step 3：實作 `TtsAudioHandler`**

建立 `app/lib/reader/tts_audio_handler.dart`：

```dart
import 'package:audio_service/audio_service.dart';
import 'package:flutter/foundation.dart';

import 'tts_controller.dart';

/// 系統通知欄/鎖定畫面/耳機線控與 [TtsController] 之間的橋接
/// （epic-34-tts-readalong Issue 7，spec.md「Android 平台整合
/// （`audio_service`）」）。`main.dart` 以 `AudioService.init(builder: () =>
/// TtsAudioHandler())` 建構**單一 App 生命週期長駐實例**（`audio_service`
/// 套件限制 `AudioService.init()` 全程式只能呼叫一次），透過
/// [attachController]／[detachController] 綁定/解綁「目前開啟的書」對應
/// 的 [TtsController]——[ReaderScreen] 每次開書都會建構一個新的
/// [TtsController]，但只有一個 [TtsAudioHandler]。
///
/// 只轉發播放/暫停/上一句/下一句（[play]／[pause]／[skipToNext]／
/// [skipToPrevious]），[BaseAudioHandler.click] 的預設實作已依
/// `playbackState.playing` 把單次媒體按鍵點擊（藍牙/有線耳機線控最常見
/// 的形式）分派成 [play]／[pause]，本類別不需要另外覆寫。
class TtsAudioHandler extends BaseAudioHandler {
  TtsController? _controller;
  VoidCallback? _statusListener;

  void attachController(TtsController controller, {required String bookTitle}) {
    detachController();
    _controller = controller;
    mediaItem.add(MediaItem(id: 'elinkbook-tts', title: bookTitle));
    _statusListener = _syncPlaybackState;
    controller.addListener(_statusListener!);
    _syncPlaybackState();
  }

  void detachController() {
    final controller = _controller;
    final listener = _statusListener;
    if (controller != null && listener != null) {
      controller.removeListener(listener);
    }
    _controller = null;
    _statusListener = null;
    mediaItem.add(null);
    playbackState.add(PlaybackState());
  }

  void _syncPlaybackState() {
    final controller = _controller;
    if (controller == null) return;
    final playing = controller.status == TtsPlaybackStatus.playing;
    playbackState.add(PlaybackState(
      controls: playing
          ? const [
              MediaControl.skipToPrevious,
              MediaControl.pause,
              MediaControl.skipToNext,
            ]
          : const [
              MediaControl.skipToPrevious,
              MediaControl.play,
              MediaControl.skipToNext,
            ],
      androidCompactActionIndices: const [0, 1, 2],
      playing: playing,
      processingState: controller.status == TtsPlaybackStatus.idle
          ? AudioProcessingState.idle
          : AudioProcessingState.ready,
      speed: controller.speed,
    ));
  }

  @override
  Future<void> play() async => _controller?.play();

  @override
  Future<void> pause() async => _controller?.pause();

  @override
  Future<void> skipToNext() async => _controller?.nextSegment();

  @override
  Future<void> skipToPrevious() async => _controller?.previousSegment();

  @override
  Future<void> stop() async {
    _controller?.pause();
    await super.stop();
  }
}
```

- [ ] **Step 4：跑測試確認全數通過**

```
flutter test test/reader/tts_audio_handler_test.dart
```

Expected：全數 PASS（7 個測試）。

```
flutter analyze
```

Expected：`No issues found!`

- [ ] **Step 5：Commit**

```bash
git add app/lib/reader/tts_audio_handler.dart app/test/reader/tts_audio_handler_test.dart
git commit -m "feat(epic-34): 新增 TtsAudioHandler（Issue 7 Task 4）"
```

---

### Task 5：`main.dart` 組裝與注入

**Files:**
- Modify: `app/lib/main.dart`
- Modify: `app/lib/screens/library_screen_dependencies.dart`

**Interfaces:**
- Consumes：Task 3 `AudioSessionFocusSource`／`TtsAudioFocusSource`、Task 4 `TtsAudioHandler`。
- Produces：`ElinkBookApp` 新增建構參數 `ttsAudioHandler`／`ttsAudioFocusSource`；`LibraryReaderFeatureRepositories` 新增同名兩個欄位。

- [ ] **Step 1：`library_screen_dependencies.dart` 新增兩個欄位**

在 `app/lib/screens/library_screen_dependencies.dart` 檔案頂端 import 區塊，找到既有的：

```dart
import '../reader/tts_provider.dart';
```

緊接其後新增：

```dart
import '../reader/tts_audio_focus_source.dart';
import '../reader/tts_audio_handler.dart';
```

找到 `LibraryReaderFeatureRepositories` 類別內既有的：

```dart
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
```

改為：

```dart
  final TtsProvider? ttsProvider;
  final TtsAudioHandler? ttsAudioHandler;
  final TtsAudioFocusSource? ttsAudioFocusSource;

  const LibraryReaderFeatureRepositories({
    this.bookmarksRepository,
    this.highlightsRepository,
    this.notesRepository,
    this.customFontsRepository,
    this.layoutPresetRepository,
    this.bookReaderPrefsRepository,
    this.ttsProvider,
    this.ttsAudioHandler,
    this.ttsAudioFocusSource,
  });
```

- [ ] **Step 2：`main.dart` 建構 `AudioSession`／`TtsAudioHandler`**

在 `app/lib/main.dart` 頂端 import 區塊，找到既有的：

```dart
import 'reader/system_tts_provider.dart';
import 'reader/tts_provider.dart';
```

改為：

```dart
import 'reader/system_tts_provider.dart';
import 'reader/tts_audio_focus_source.dart';
import 'reader/tts_audio_handler.dart';
import 'reader/tts_provider.dart';
```

再新增 `package:audio_service/audio_service.dart` 與 `package:audio_session/audio_session.dart` 兩個第三方 import（放在既有 `package:pdfrx/pdfrx.dart` 之後、本地 import 之前，比照既有 import 排序慣例）：

```dart
import 'package:audio_service/audio_service.dart';
import 'package:audio_session/audio_session.dart';
```

在 `main()` 函式內找到既有的：

```dart
  // epic-34-tts-readalong Issue 9：SystemTtsProvider 預設建構子內部會自行
  // 建立 FlutterTts()，App 層級不需要另外管理其生命週期或提供假物件。
  final ttsProvider = SystemTtsProvider();
```

緊接其後新增：

```dart
  // epic-34-tts-readalong Issue 7：AudioSession 設定一次即為 App 全程式
  // 共用（audio_session 套件內部本身即單例，見該套件 AudioSession.instance
  // 文件），朗讀內容一律視為 speech（語音），並要求「降低音量」型的暫時
  // 失焦（AUDIOFOCUS_LOSS_TRANSIENT_CAN_DUCK）也一律當成需要暫停處理
  // （androidWillPauseWhenDucked: true）——降低音量的人聲朗讀無法辨識，
  // 與音樂/Podcast 那種可以被降低音量、繼續播放的內容性質不同。
  final ttsAudioSession = await AudioSession.instance;
  await ttsAudioSession.configure(const AudioSessionConfiguration(
    androidAudioAttributes: AndroidAudioAttributes(
      contentType: AndroidAudioContentType.speech,
      usage: AndroidAudioUsage.media,
    ),
    androidAudioFocusGainType: AndroidAudioFocusGainType.gain,
    androidWillPauseWhenDucked: true,
  ));
  final ttsAudioFocusSource = AudioSessionFocusSource(ttsAudioSession);
  // AudioService.init() 全程式生命週期只能呼叫一次（見
  // plans/plan-issue-7.md Global Constraints），建構出的單一 handler
  // 由 ReaderScreen 於每次開書時呼叫 attachController()／
  // detachController() 綁定/解綁目前的 TtsController。
  final ttsAudioHandler = await AudioService.init(
    builder: () => TtsAudioHandler(),
    config: const AudioServiceConfig(
      androidNotificationChannelId: 'cc.ugotit.elinkbook.tts_channel',
      androidNotificationChannelName: '朗讀播放中',
      // Android 12 起背景重啟前景服務有限制（見 audio_service 官方
      // README「Android setup」段落說明），保持 false（暫停時服務維持
      // 前景狀態，不釋放通知），避免使用者暫停朗讀後、App 進一步被系統
      // 節流時無法重新啟動前景服務。
      androidStopForegroundOnPause: false,
    ),
  );
```

在 `runApp(ElinkBookApp(...))` 呼叫中找到既有的：

```dart
      ttsProvider: ttsProvider,
```

緊接其後新增：

```dart
      ttsAudioHandler: ttsAudioHandler,
      ttsAudioFocusSource: ttsAudioFocusSource,
```

在 `class ElinkBookApp` 找到既有的：

```dart
  final TtsProvider? ttsProvider;
```

緊接其後新增：

```dart
  final TtsAudioHandler? ttsAudioHandler;
  final TtsAudioFocusSource? ttsAudioFocusSource;
```

在 `ElinkBookApp` 建構子找到既有的：

```dart
    this.ttsProvider,
```

緊接其後新增：

```dart
    this.ttsAudioHandler,
    this.ttsAudioFocusSource,
```

在 `_ElinkBookAppState.build()` 內找到既有的：

```dart
          ttsProvider: widget.ttsProvider,
```

緊接其後新增：

```dart
          ttsAudioHandler: widget.ttsAudioHandler,
          ttsAudioFocusSource: widget.ttsAudioFocusSource,
```

- [ ] **Step 3：驗證**

```
flutter analyze
```

Expected：`No issues found!`（本 Task 純組裝接線，`LibraryReaderFeatureRepositories`／`ReaderScreen` 新增欄位尚未在 Task 6 前完全接上前，`ReaderScreen` 建構子還沒有這兩個參數——**此步驟須等 Task 6 完成後才會真正編譯成功**，若依序執行到本 Task 立即跑 `flutter analyze` 預期會因 `ReaderScreen(... ttsAudioHandler: ...)` 尚未定義該具名參數而報錯；建議 Task 5／Task 6 視為同一次可驗證的整體，Task 5 先完成、Task 6 完成後再一併跑本驗證步驟）。

- [ ] **Step 4：Commit**（與 Task 6 合併提交，見 Task 6 Step 5）

本 Task 暫不獨立 commit——`main.dart` 傳入 `ttsAudioHandler`/`ttsAudioFocusSource` 給 `ElinkBookApp`／`LibraryScreen` 后，最終仍要靠 Task 6 `ReaderScreen` 實際定義這兩個具名參數才能編譯成功；為了維持「每個 commit 皆可獨立編譯/測試」的既有慣例（比照本檔案其餘 Task 每步驟結尾皆驗證 `flutter analyze` 乾淨），Task 5 與 Task 6 的變更**一併於 Task 6 Step 5 提交同一個 commit**，訊息涵蓋兩者。

---

### Task 6：`ReaderScreen` 接線

**Files:**
- Modify: `app/lib/screens/reader_screen.dart`
- Test: `app/test/screens/reader_screen_test.dart`

**Interfaces:**
- Consumes：Task 3 `TtsAudioFocusSource`／`TtsAudioFocusCoordinator`、Task 4 `TtsAudioHandler`、Task 2 `TtsController.resyncHighlight()`。
- Produces：`ReaderScreen` 新增可選建構參數 `ttsAudioHandler`（`TtsAudioHandler?`）／`ttsAudioFocusSource`（`TtsAudioFocusSource?`）。

- [ ] **Step 1：寫失敗測試**

在 `app/test/screens/reader_screen_test.dart` 找到既有「Mini Player 與既有底部元件顯示連動（epic-34-tts-readalong Issue 6）」`group` 結尾（該 group 的收尾 `});`），緊接其後新增一個新的 group：

```dart
  group('背景播放與系統整合（epic-34-tts-readalong Issue 7）', () {
    testWidgets(
        '提供 ttsAudioHandler／ttsAudioFocusSource 時，開書/播放/離開畫面'
        '皆不崩潰（誠實測試邊界：flutter_test 環境下 loadSegments() 恆'
        '回傳空清單，TtsController 永遠不會真正進入 playing，這裡驗證的'
        '是接線本身的結構性保證，深層狀態機正確性由'
        'tts_audio_focus_coordinator_test.dart／tts_audio_handler_test.dart'
        '（純 Dart）完整涵蓋，見 plan-issue-7.md「測試分層」）',
        (tester) async {
      final ttsProvider = FakeTtsProvider();
      final ttsAudioHandler = TtsAudioHandler();
      final ttsAudioFocusSource = FakeTtsAudioFocusSource();

      await tester.pumpWidget(
        MaterialApp(
          home: ReaderScreen(
            filePath: 'test/fixtures/sample.epub',
            bookId: 'b_tts7_wiring',
            prefsManager: prefsManager,
            isFixedLayout: false,
            ttsProvider: ttsProvider,
            ttsAudioHandler: ttsAudioHandler,
            ttsAudioFocusSource: ttsAudioFocusSource,
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
      await tester.tap(buttonFinder);
      await tester.pump();
      expect(tester.takeException(), isNull);

      // TtsAudioHandler 應已綁定書名（attachController 已被呼叫）。
      expect(ttsAudioHandler.mediaItem.value?.title, '未知書籍');

      // 焦點事件送達不應造成崩潰（idle 狀態下為 no-op）。
      ttsAudioFocusSource.emit(TtsAudioFocusEvent.transientLoss);
      await tester.pump();
      expect(tester.takeException(), isNull);

      // App 從背景恢復前景時，resyncHighlight() 接線不應崩潰。
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pump();
      expect(tester.takeException(), isNull);

      final navigatorState = tester.state<NavigatorState>(find.byType(Navigator));
      navigatorState.maybePop();
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(ttsAudioHandler.mediaItem.value, isNull,
          reason: '離開畫面（dispose）應呼叫 detachController()');
    });

    testWidgets('未提供 ttsAudioHandler／ttsAudioFocusSource 時，既有播放/暫停行為零回歸',
        (tester) async {
      final ttsProvider = FakeTtsProvider();

      await tester.pumpWidget(
        MaterialApp(
          home: ReaderScreen(
            filePath: 'test/fixtures/sample.epub',
            bookId: 'b_tts7_no_wiring',
            prefsManager: prefsManager,
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
      await tester.tap(buttonFinder);
      await tester.pump();
      expect(tester.takeException(), isNull);

      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pump();
      expect(tester.takeException(), isNull);
    });
  });
```

在該檔案頂端 import 區塊新增（找到既有 `import 'package:elinkbook/reader/tts_controller.dart';` 等既有 TTS import 群，緊接其後新增）：

```dart
import 'package:elinkbook/reader/tts_audio_focus_source.dart';
import 'package:elinkbook/reader/tts_audio_handler.dart';

import '../support/fake_tts_audio_focus_source.dart';
```

- [ ] **Step 2：跑測試確認新測試失敗**

```
flutter test test/screens/reader_screen_test.dart
```

Expected：FAIL（編譯錯誤）——`ReaderScreen` 尚未定義 `ttsAudioHandler`／`ttsAudioFocusSource` 具名參數。

- [ ] **Step 3：`ReaderScreen` 新增建構參數與欄位**

在 `app/lib/screens/reader_screen.dart` 頂端 import 區塊找到既有的：

```dart
import '../reader/tts_audio_player.dart';
import '../reader/tts_controller.dart';
import '../reader/tts_provider.dart';
```

改為：

```dart
import '../reader/tts_audio_focus_coordinator.dart';
import '../reader/tts_audio_focus_source.dart';
import '../reader/tts_audio_handler.dart';
import '../reader/tts_audio_player.dart';
import '../reader/tts_controller.dart';
import '../reader/tts_provider.dart';
```

找到既有的：

```dart
  final TtsProvider? ttsProvider;

  const ReaderScreen({
```

改為：

```dart
  final TtsProvider? ttsProvider;

  /// 系統通知欄/鎖定畫面/耳機線控整合（epic-34-tts-readalong Issue 7）。
  /// 刻意為可選參數——比照 [ttsProvider] 既有慣例，未提供時（例如本檔案
  /// 絕大多數既有測試）背景播放系統整合完全不啟用，Mini Player 播放/
  /// 暫停等既有功能不受影響。`main.dart` 建構的單一 App 生命週期長駐
  /// 實例（`AudioService.init()` 全程式只能呼叫一次），由本畫面於開書
  /// 時呼叫 `attachController()`、離開時呼叫 `detachController()`。
  final TtsAudioHandler? ttsAudioHandler;

  /// 系統音訊焦點中斷/耳機拔出事件來源（epic-34-tts-readalong Issue 7）。
  /// 刻意為可選參數，理由同 [ttsAudioHandler]。`main.dart` 建構的單一
  /// App 生命週期共用實例（`AudioSession` 本身即單例）。
  final TtsAudioFocusSource? ttsAudioFocusSource;

  const ReaderScreen({
```

找到既有建構子內的：

```dart
    this.ttsProvider,
  });
```

改為：

```dart
    this.ttsProvider,
    this.ttsAudioHandler,
    this.ttsAudioFocusSource,
  });
```

- [ ] **Step 4：接線——`_ttsControllerOrNull` getter、`dispose()`、`didChangeAppLifecycleState`**

在 `app/lib/screens/reader_screen.dart` 找到既有的：

```dart
  TtsController? _ttsController;
```

緊接其後新增：

```dart
  /// 目前開啟的書對應的音訊焦點協調器（epic-34-tts-readalong Issue 7）。
  /// 與 [_ttsController] 同一時機建構/銷毀，見 [_ttsControllerOrNull]／
  /// [dispose]。
  TtsAudioFocusCoordinator? _ttsAudioFocusCoordinator;
```

找到既有的 `_ttsControllerOrNull` getter（完整內容）：

```dart
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
      // 朗讀同步高亮（epic-34-tts-readalong Issue 3，ADR 0026）：只呼叫
      // 既有 Overlayer 管線，不引用 highlightsRepository/notesRepository。
      // vertical 旗標讀取 _resolved（目前實際生效的排版方向，含使用者
      // 手動切換的結果，非僅書本 CSS 宣告的 _autoDetectedWritingMode），
      // 比照本檔案既有頁首/頁尾直排判斷寫法（_resolved?.writingMode ==
      // WritingMode.vertical）。
      onHighlightSegment: (segment) {
        if (segment == null) {
          FoliateReaderView.clearTtsHighlight(_foliateEpubReaderViewKey);
        } else {
          FoliateReaderView.showTtsHighlight(
            _foliateEpubReaderViewKey,
            segment.cfi,
            vertical: _resolved?.writingMode == WritingMode.vertical,
          );
        }
      },
      // 反向查找起始段落（epic-34-tts-readalong Issue 4，2026-08-27
      // Issue 3 真機驗收追加範圍）：從 _epubPositionInfo 讀取畫面目前可視
      // 位置的 cfi（與 loadSegments 內的 extractChapterIndex 同一份
      // _epubPositionInfo，同一次 play() 呼叫序列內不會中途改變），找不到
      // （例如尚未收到任何 onLocatorChanged 事件）時回傳 0，交由
      // TtsController 既有的「從第 0 段開始」向後相容行為處理。
      lookupStartIndex: (segs) async {
        final visibleCfi = extractCfi(_epubPositionInfo?.locatorJson);
        if (visibleCfi == null) return 0;
        return FoliateReaderView.lookupSegmentByCfi(
          _foliateEpubReaderViewKey,
          visibleCfi,
          segs.map((s) => s.cfi).toList(),
        );
      },
    );
  }
```

改為（`??=` 單行 lazy 建構改成 `if` 守衛式寫法，讓建構完成後可以緊接著執行 attach 副作用，只在首次建構時執行一次）：

```dart
  TtsController? get _ttsControllerOrNull {
    final provider = widget.ttsProvider;
    if (provider == null) return null;
    if (_ttsController != null) return _ttsController;
    final controller = TtsController(
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
      // 朗讀同步高亮（epic-34-tts-readalong Issue 3，ADR 0026）：只呼叫
      // 既有 Overlayer 管線，不引用 highlightsRepository/notesRepository。
      // vertical 旗標讀取 _resolved（目前實際生效的排版方向，含使用者
      // 手動切換的結果，非僅書本 CSS 宣告的 _autoDetectedWritingMode），
      // 比照本檔案既有頁首/頁尾直排判斷寫法（_resolved?.writingMode ==
      // WritingMode.vertical）。
      onHighlightSegment: (segment) {
        if (segment == null) {
          FoliateReaderView.clearTtsHighlight(_foliateEpubReaderViewKey);
        } else {
          FoliateReaderView.showTtsHighlight(
            _foliateEpubReaderViewKey,
            segment.cfi,
            vertical: _resolved?.writingMode == WritingMode.vertical,
          );
        }
      },
      // 反向查找起始段落（epic-34-tts-readalong Issue 4，2026-08-27
      // Issue 3 真機驗收追加範圍）：從 _epubPositionInfo 讀取畫面目前可視
      // 位置的 cfi（與 loadSegments 內的 extractChapterIndex 同一份
      // _epubPositionInfo，同一次 play() 呼叫序列內不會中途改變），找不到
      // （例如尚未收到任何 onLocatorChanged 事件）時回傳 0，交由
      // TtsController 既有的「從第 0 段開始」向後相容行為處理。
      lookupStartIndex: (segs) async {
        final visibleCfi = extractCfi(_epubPositionInfo?.locatorJson);
        if (visibleCfi == null) return 0;
        return FoliateReaderView.lookupSegmentByCfi(
          _foliateEpubReaderViewKey,
          visibleCfi,
          segs.map((s) => s.cfi).toList(),
        );
      },
    );
    _ttsController = controller;
    // 背景播放系統整合（epic-34-tts-readalong Issue 7）：與 controller
    // 本身同一時機建構/綁定，只在首次存取本 getter（即本次開書第一次
    // 需要 TtsController）時執行一次，比照上方 controller 建構本身的
    // lazy 語意。兩者皆為可選（nullable），未提供時完全不啟用。
    widget.ttsAudioHandler?.attachController(controller, bookTitle: widget.bookTitle);
    final focusSource = widget.ttsAudioFocusSource;
    if (focusSource != null) {
      _ttsAudioFocusCoordinator =
          TtsAudioFocusCoordinator(source: focusSource, controller: controller);
    }
    return controller;
  }
```

找到既有 `dispose()` 內的：

```dart
    _pdfSearchStateNotifier.dispose();
    _ttsController?.dispose();
```

改為：

```dart
    _pdfSearchStateNotifier.dispose();
    _ttsAudioFocusCoordinator?.dispose();
    widget.ttsAudioHandler?.detachController();
    _ttsController?.dispose();
```

找到既有 `didChangeAppLifecycleState` 的 `resumed` 分支：

```dart
    } else if (state == AppLifecycleState.resumed) {
      // App 從背景恢復時，Android 系統列可能已被 OS 自動重新顯示，
      // _lastAppliedFullscreen 等值節流防護會誤判不需重套用，故強制清空
      // 快取後無條件重新呼叫一次（epic-19 Issue 1 review Critical 2）。
      _lastAppliedFullscreen = null;
      _applySystemUiMode();
    }
```

改為（新增一行，其餘不動）：

```dart
    } else if (state == AppLifecycleState.resumed) {
      // App 從背景恢復時，Android 系統列可能已被 OS 自動重新顯示，
      // _lastAppliedFullscreen 等值節流防護會誤判不需重套用，故強制清空
      // 快取後無條件重新呼叫一次（epic-19 Issue 1 review Critical 2）。
      _lastAppliedFullscreen = null;
      _applySystemUiMode();
      // 背景時 WebView 的 JS 執行/計時器可能被系統節流，但 audio_service
      // 前景服務讓音訊照常播放，導致畫面高亮落後於實際播放進度
      // （epic-34-tts-readalong Issue 7，design.md「App 背景/前景切換時的
      // 高亮同步落差」）。直接用既有的 nullable _ttsController 欄位（不用
      // _ttsControllerOrNull getter，比照 onLocatorChanged 既有呼叫端的
      // 既定寫法）——尚未曾建構過 TtsController 時呼叫本方法是 no-op。
      _ttsController?.resyncHighlight();
    }
```

- [ ] **Step 5：跑測試確認全數通過、零回歸；Commit（含 Task 5）**

```
flutter test test/screens/reader_screen_test.dart
```

Expected：全數 PASS——含 Task 5／Task 6 一併生效後新增的 2 個 Issue 7 測試，以及 Issue 2/3/4/5/6 既有全部 TTS 相關測試皆維持原樣通過，零回歸。

```
flutter test
```

Expected：全專案測試全數通過，零回歸。

```
flutter analyze
```

Expected：`No issues found!`

```bash
git add app/lib/main.dart app/lib/screens/library_screen_dependencies.dart app/lib/screens/reader_screen.dart app/test/screens/reader_screen_test.dart
git commit -m "feat(epic-34): main.dart 組裝與 ReaderScreen 接線——AudioHandler／AudioFocus（Issue 7 Task 5-6）"
```

---

### Task 7：`library_screen.dart` 轉送

**Files:**
- Modify: `app/lib/screens/library_screen.dart`
- Test: `app/test/screens/library_screen_test.dart`

**Interfaces:**
- Consumes：Task 5 `LibraryReaderFeatureRepositories.ttsAudioHandler`／`.ttsAudioFocusSource`、Task 6 `ReaderScreen.ttsAudioHandler`／`.ttsAudioFocusSource`。

- [ ] **Step 1：寫失敗測試**

在 `app/test/screens/library_screen_test.dart` 找到既有「`LibraryScreen` 點開一本書後，`ReaderScreen` 收到的 `ttsProvider` 正確貫穿（Issue 9 缺口修正）」測試結尾（第 2232 行 `});`），緊接其後新增：

```dart
  testWidgets(
      'LibraryScreen 點開一本書後，ReaderScreen 收到的 ttsAudioHandler／'
      'ttsAudioFocusSource 正確貫穿（epic-34-tts-readalong Issue 7）',
      (tester) async {
    final book = _testBook(
      id: '1',
      title: '紅樓夢',
      author: '曹雪芹',
      filePath: 'content://example/1.txt',
    );
    final ttsAudioHandler = TtsAudioHandler();
    final ttsAudioFocusSource = FakeTtsAudioFocusSource();

    await tester.pumpWidget(
      MaterialApp(
        home: LibraryScreen(
          repository: FakeLibraryRepository(initialBooks: [book]),
          importService: FakeBookImportService(),
          prefsManager: prefsManager,
          readerFeatureRepositories: LibraryReaderFeatureRepositories(
            ttsAudioHandler: ttsAudioHandler,
            ttsAudioFocusSource: ttsAudioFocusSource,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('book_item_1')));
    await tester.pumpAndSettle();

    final readerScreen = tester.widget<ReaderScreen>(find.byType(ReaderScreen));
    expect(readerScreen.ttsAudioHandler, same(ttsAudioHandler));
    expect(readerScreen.ttsAudioFocusSource, same(ttsAudioFocusSource));
  });
```

在 `app/test/screens/library_screen_test.dart` 找到既有「透過分類篩選路徑開書，`ReaderScreen` 收到的 `ttsProvider` 應與外層一致」測試結尾，緊接其後新增（比照上方測試，改走 `_openGroupFilteredView` 路徑）：

```dart
  testWidgets(
      '透過分類篩選路徑開書，ReaderScreen 收到的 ttsAudioHandler／'
      'ttsAudioFocusSource 應與外層一致（epic-34-tts-readalong Issue 7）；'
      '順帶驗證改為整包轉送後，先前遺漏的 layoutPresetRepository／'
      'bookReaderPrefsRepository 也一併正確貫穿（審查 review-plan-issue-7.md '
      '4.3 採納，修復既有缺口，非本 Issue 造成，見 Task 7 Step 3「理由」）',
      (tester) async {
    final book = _testBook(
      id: '1',
      title: '紅樓夢',
      author: '曹雪芹',
      filePath: 'content://example/1.txt',
      groupName: '小說',
    );
    final ttsAudioHandler = TtsAudioHandler();
    final ttsAudioFocusSource = FakeTtsAudioFocusSource();
    final layoutPresetRepository =
        LayoutPresetRepository(libraryRepository.database);

    await tester.pumpWidget(
      MaterialApp(
        home: LibraryScreen(
          repository: FakeLibraryRepository(initialBooks: [book]),
          importService: FakeBookImportService(),
          prefsManager: prefsManager,
          readerFeatureRepositories: LibraryReaderFeatureRepositories(
            ttsAudioHandler: ttsAudioHandler,
            ttsAudioFocusSource: ttsAudioFocusSource,
            layoutPresetRepository: layoutPresetRepository,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('小說'));
    await tester.pumpAndSettle();

    final filteredScreen = tester.widget<LibraryScreen>(find.byType(LibraryScreen).last);
    expect(filteredScreen.readerFeatureRepositories.ttsAudioHandler,
        same(ttsAudioHandler));
    expect(filteredScreen.readerFeatureRepositories.ttsAudioFocusSource,
        same(ttsAudioFocusSource));
    expect(filteredScreen.readerFeatureRepositories.layoutPresetRepository,
        same(layoutPresetRepository),
        reason: '改為整包轉送（Step 3）前，_openGroupFilteredView() 手動列舉'
            '欄位時遺漏了 layoutPresetRepository，此處鎖定該既有缺口已修復。');

    await tester.tap(find.byKey(const Key('book_item_1')));
    await tester.pumpAndSettle();

    final readerScreen = tester.widget<ReaderScreen>(find.byType(ReaderScreen));
    expect(readerScreen.ttsAudioHandler, same(ttsAudioHandler));
    expect(readerScreen.ttsAudioFocusSource, same(ttsAudioFocusSource));
  });
```

**注意**：上方兩個測試須先比照 `library_screen_test.dart` 檔案內既有「透過分類篩選路徑開書」測試的實際互動手法（點擊分類名稱進入篩選頁、`find.byKey('book_item_1')` 尋找書籍項目等）核對一致——若既有測試的實際互動步驟與本計畫描述有出入（例如分類進入方式、書籍項目 Key 命名），以檔案內實際存在的既有寫法為準，本計畫只保證欄位轉送邏輯本身的斷言正確。`libraryRepository`／`LayoutPresetRepository` 建構方式比照本檔案既有「`LibraryScreen` 點開一本書後，`ReaderScreen` 收到的 `layoutPresetRepository`／`bookReaderPrefsRepository` 正確貫穿」測試（第 2952-2989 行）既有寫法。在檔案頂端 import 區塊新增：

```dart
import 'package:elinkbook/reader/tts_audio_handler.dart';

import '../support/fake_tts_audio_focus_source.dart';
```

- [ ] **Step 2：跑測試確認新測試失敗**

```
flutter test test/screens/library_screen_test.dart
```

Expected：FAIL（編譯錯誤或欄位不存在）——`_openBook()`／`_openGroupFilteredView()` 尚未轉送這兩個新欄位。

- [ ] **Step 3：`library_screen.dart` 轉送兩個新欄位**

在 `app/lib/screens/library_screen.dart` 找到 `_openBook()` 內既有的：

```dart
              ttsProvider: widget.readerFeatureRepositories.ttsProvider,
```

改為：

```dart
              ttsProvider: widget.readerFeatureRepositories.ttsProvider,
              ttsAudioHandler: widget.readerFeatureRepositories.ttsAudioHandler,
              ttsAudioFocusSource: widget.readerFeatureRepositories.ttsAudioFocusSource,
```

在 `_openGroupFilteredView()` 內找到既有的：

```dart
              readerFeatureRepositories: LibraryReaderFeatureRepositories(
                bookmarksRepository: widget.readerFeatureRepositories.bookmarksRepository,
                highlightsRepository: widget.readerFeatureRepositories.highlightsRepository,
                notesRepository: widget.readerFeatureRepositories.notesRepository,
                customFontsRepository: widget.readerFeatureRepositories.customFontsRepository,
                ttsProvider: widget.readerFeatureRepositories.ttsProvider,
              ),
```

**改為整包轉送，不再逐欄位列舉**（審查 `review-plan-issue-7.md` 4.3 採納）：

```dart
              readerFeatureRepositories: widget.readerFeatureRepositories,
```

**理由**：上方既有的逐欄位列舉方式，本來就已經遺漏 `layoutPresetRepository`／`bookReaderPrefsRepository` 兩個既有欄位（`LibraryReaderFeatureRepositories` 目前共 7 個欄位，這裡只列了 5 個）——這不是本 Issue 造成的問題，但如果本 Task 只是比照既有方式再手動加兩行（`ttsAudioHandler`／`ttsAudioFocusSource`），會讓「逐欄位列舉、忘了轉某個欄位」這個既有的錯誤模式繼續重演，且本 Task 新增的兩個欄位本身也會立刻曝露在同一種風險下。本專案已有明確先例：`library_screen.dart` 的 `syncDependencies: widget.syncDependencies,`（`epic-8-sync` Issue 10，該處註解原文：「先前遺漏這三個同步相關欄位……本次改為整包轉送 `syncDependencies` bundle，結構上不會再重演『轉 A 忘轉 B』的部分欄位漏轉發」）——`LibraryReaderFeatureRepositories` 沒有像 `LibraryCloudAccountDependencies`／`LibraryRemoteLibraryDependencies` 那樣在 `library_screen_dependencies.dart` 留下「刻意不含某欄位」的排除說明（比對後兩者的文件註解可知那是特意排除、有明確理由），代表這裡的欄位缺漏是單純疏漏，不是設計上的邊界，改整包轉送同時修好這個既有缺口與本 Task 新增欄位的風險，範圍內的改動就在同一行程式碼上，不是另外去動其他無關程式碼。

- [ ] **Step 4：跑測試確認全數通過、零回歸**

```
flutter test test/screens/library_screen_test.dart
```

Expected：全數 PASS——含新增的 2 個 Issue 7 測試，既有 Issue 9 `ttsProvider` 轉送測試與其餘測試維持原樣通過，零回歸。

```
flutter test
```

Expected：全專案測試全數通過，零回歸。

```
flutter analyze
```

Expected：`No issues found!`

- [ ] **Step 5：Commit**

```bash
git add app/lib/screens/library_screen.dart app/test/screens/library_screen_test.dart
git commit -m "feat(epic-34): library_screen.dart 轉送 ttsAudioHandler／ttsAudioFocusSource（Issue 7 Task 7）"
```

---

## 測試策略總結（Self-Review 用，非額外步驟）

- **`TtsController.resyncHighlight()` 純 Dart 單元測試**（Task 2）：idle no-op、playing/paused 狀態重新觸發 `onHighlightSegment`、disposed 後安全無例外，三種情境完整涵蓋。
- **`TtsAudioFocusCoordinator` 純 Dart 單元測試**（Task 3）：這是本 Issue 最扎實的測試層，也是 `review-issues.md` Important #2「測試分流」自動化層的實際落點——不透過 `ReaderScreen`／WebView，直接以真實 `TtsController`＋Fake `TtsProvider`/`TtsAudioPlayer` 讓狀態機能真正進入 `playing`，再用 `FakeTtsAudioFocusSource` 送出合成的暫時失焦/永久失焦/焦點恢復/耳機拔出事件，逐一驗證暫停/自動恢復的判斷邏輯（含「使用者手動暫停後焦點恢復不應被誤觸自動播放」這個關鍵邊界情況）。
- **`TtsAudioHandler` 純 Dart 單元測試**（Task 4）：`attachController`/`detachController` 生命週期、`playbackState`/`mediaItem` 隨 `TtsController` 狀態變化正確同步、`play()`/`pause()`/`skipToNext()`/`skipToPrevious()` 正確轉發、換書時正確解綁前一本書的監聽，皆為可獨立驗證的真實行為（`BaseAudioHandler` 是純 Dart 類別，不需要平台 channel 即可測試，見 Task 4「規劃階段查證」）。
- **`ReaderScreen`／`LibraryScreen` widget test**（Task 6／Task 7）：受限於既有「`flutter_test` 環境下 `loadSegments()` 恆回傳空清單，`TtsController` 永遠不會真正進入 `playing`」誠實測試邊界（Issue 5 已確立），這兩層測試只能驗證**接線本身不崩潰、依賴正確貫穿**（`ttsAudioHandler`/`ttsAudioFocusSource` 是否真的傳到底、`attachController`/`detachController` 是否真的被呼叫），無法在這層驗證「暫停/恢復真的發生」——這部分的深層正確性已由 Task 3/4 的純 Dart 測試完整涵蓋，兩層測試合起來構成完整覆蓋，不是缺口。
- **零回歸驗證**：Issue 2/3/4/5/6 在 `reader_screen_test.dart`／`library_screen_test.dart` 累積的所有 TTS 相關測試完全不修改，直接依賴 Task 2/6/7 保留既有方法簽章、既有欄位語意來維持通過。
- **無法自動化、須真機手動驗證的部分**（比照既有 Issue「測試策略總結」慣例，合併前建議至少手動跑一次，對應 `issues.md` Issue 7 驗收標準四項）：
  1. 播放朗讀後把 App 切到背景/鎖定螢幕，確認音訊繼續播放、通知欄與鎖定畫面顯示朗讀狀態＋播放/暫停控制，點擊控制項確實生效。
  2. 實體藍牙耳機連線中途拔除／有線耳機拔出，確認朗讀自動暫停。
  3. 實體電話撥入（暫時失焦），確認朗讀自動暫停；通話結束後確認朗讀自動恢復（且不是使用者手動暫停被誤觸自動恢復——若測試前先手動暫停朗讀再撥入電話，通話結束後應維持暫停狀態）。
  4. 切換至 YouTube／其他音樂 App 播放（永久失焦），確認朗讀暫停且不自動恢復。
  5. 耳機線控（藍牙/有線）單擊，確認觸發播放/暫停切換（`BaseAudioHandler.click()` 既有預設實作）。
  6. App 背景一段時間後前景恢復（`AppLifecycleState.resumed`），確認畫面高亮正確重新同步至目前實際播放進度，不是停留在背景前的舊位置（不含跨頁翻頁跟隨，該部分留給 Issue 8）。
  7. 確認 `flutter build apk --debug`／`--release` 皆能成功產出 APK（Task 1 已於開發階段驗證 debug 建置，正式合併前建議再次確認 release 建置，因 R8/ProGuard 縮減規則可能影響 `audio_service` 的通知圖示資源，見官方 README「shrinking」段落）。

---

## Self-Review 檢查結果

- **Spec coverage**：`issues.md` Issue 7「設計要點」四項（`audio_service` 整合與 manifest 宣告、通知欄/鎖定畫面/耳機線控、前景恢復重新同步、Audio Focus 中斷處理）逐條對應 Task 1（Manifest）、Task 4（`TtsAudioHandler`）、Task 2（`resyncHighlight`）、Task 3（`TtsAudioFocusCoordinator`）；驗收標準四項（背景播放/通知欄、耳機線控/拔出、前景恢復高亮同步、Audio Focus 行為）皆對應到「測試策略總結」的自動化測試＋真機驗收清單雙層覆蓋。無缺口。
- **Placeholder scan**：全文搜尋未發現「TBD」/「之後補」/「處理錯誤」等空話；Task 5 Step 3 明確說明「`flutter analyze` 須等 Task 6 完成後才會真正編譯成功」這個跨 Task 依賴，不是遺漏而是刻意標註的執行順序提醒。
- **Type consistency**：`TtsAudioFocusEvent`（Task 3 定義：`transientLoss`/`permanentLoss`/`focusGained`/`becomingNoisy`）在 `TtsAudioFocusSource`/`AudioSessionFocusSource`/`TtsAudioFocusCoordinator`（Task 3）與其單元測試（Task 3 Step 2）用字一致；`TtsAudioHandler.attachController(TtsController, {required String bookTitle})`／`detachController()` 簽章在 Task 4 定義與 Task 6 `ReaderScreen` 呼叫端（`widget.ttsAudioHandler?.attachController(controller, bookTitle: widget.bookTitle)`）、Task 7 `library_screen.dart` 轉送欄位名稱（`ttsAudioHandler`）三處一致；`TtsController.resyncHighlight()`（Task 2 定義，無參數、`void` 回傳）與 Task 6 呼叫端 `_ttsController?.resyncHighlight()` 一致。
