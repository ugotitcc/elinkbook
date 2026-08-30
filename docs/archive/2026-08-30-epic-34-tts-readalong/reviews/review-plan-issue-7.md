# Epic 34 Issue 7 實作計畫審查報告 (Plan Review Report)

**審查對象：** [`docs/epics/epic-34-tts-readalong/plans/plan-issue-7.md`](file:///U:/MyDeveloper/AI/elinkBook/docs/epics/epic-34-tts-readalong/plans/plan-issue-7.md)  
**對應工單：** `docs/epics/epic-34-tts-readalong/issues.md` Issue 7（背景播放與系統整合 `audio_service`）  
**診斷依據：**
- [`docs/epics/epic-34-tts-readalong/issues.md`](file:///U:/MyDeveloper/AI/elinkBook/docs/epics/epic-34-tts-readalong/issues.md)（Issue 7 需求與驗收標準）
- [`docs/epics/epic-34-tts-readalong/spec.md`](file:///U:/MyDeveloper/AI/elinkBook/docs/epics/epic-34-tts-readalong/spec.md)（`TtsController`、Audio Focus 中斷處理與 `audio_service` 整合）
- [`docs/epics/epic-34-tts-readalong/design.md`](file:///U:/MyDeveloper/AI/elinkBook/docs/epics/epic-34-tts-readalong/design.md)（背景播放與前景切換高亮同步）
- [`docs/epics/epic-34-tts-readalong/dependency-spike-findings.md`](file:///U:/MyDeveloper/AI/elinkBook/docs/epics/epic-34-tts-readalong/dependency-spike-findings.md)（`audio_service`／`audio_session` 相依與 Manifest 規範）
- [`app/lib/reader/tts_controller.dart`](file:///U:/MyDeveloper/AI/elinkBook/app/lib/reader/tts_controller.dart)（既有 TTS 狀態機實作）
- [`app/lib/screens/reader_screen.dart`](file:///U:/MyDeveloper/AI/elinkBook/app/lib/screens/reader_screen.dart)（既有開書與生命週期控制）
- [`app/lib/screens/library_screen.dart`](file:///U:/MyDeveloper/AI/elinkBook/app/lib/screens/library_screen.dart) 及 [`library_screen_dependencies.dart`](file:///U:/MyDeveloper/AI/elinkBook/app/lib/screens/library_screen_dependencies.dart)（依賴注入架構）
- [`app/android/app/src/main/kotlin/cc/ugotit/elinkbook/MainActivity.kt`](file:///U:/MyDeveloper/AI/elinkBook/app/android/app/src/main/kotlin/cc/ugotit/elinkbook/MainActivity.kt) 與 [`AndroidManifest.xml`](file:///U:/MyDeveloper/AI/elinkBook/app/android/app/src/main/AndroidManifest.xml)（Android 原生層設定）  
**審查日期：** 2026-08-28  
**審查結果：** **Approved（正式核准，建議納入防禦性細節後執行）**

---

## 1. 審查總結（Executive Summary）

本實作計畫涵蓋了系統層級整合、生命週期管理、音訊焦點協調與背景高亮重新同步等複雜領域，整體設計結構嚴謹、分層清晰，完全符合規格書與工單目標：

1. **職責分離與低侵入式協調層**：
   - 完整保留既有 [`TtsController`](file:///U:/MyDeveloper/AI/elinkBook/app/lib/reader/tts_controller.dart) 的播放與合成核心邏輯，僅新增純粹的 `resyncHighlight()` 公開方法。
   - 將「系統音訊焦點／耳機拔出」與「系統通知欄／鎖定畫面／MediaSession」分別封裝於獨立的 [`TtsAudioFocusCoordinator`](file:///U:/MyDeveloper/AI/elinkBook/app/lib/reader/tts_audio_focus_coordinator.dart) 與 [`TtsAudioHandler`](file:///U:/MyDeveloper/AI/elinkBook/app/lib/reader/tts_audio_handler.dart)，完全透過 `TtsController` 公開介面操作。
2. **生命週期與架構約束嚴密**：
   - 嚴格遵守 `AudioService.init()` 在 App 全生命週期僅能呼叫一次的限制，於 `main.dart` 建立單一實例，並於 [`ReaderScreen`](file:///U:/MyDeveloper/AI/elinkBook/app/lib/screens/reader_screen.dart) 開書/離開時透過 `attachController()`／`detachController()` 動態綁定/解綁目前書籍對應的控制器。
   - [`MainActivity.kt`](file:///U:/MyDeveloper/AI/elinkBook/app/android/app/src/main/kotlin/cc/ugotit/elinkbook/MainActivity.kt) 採用 `AudioServiceFragmentActivity`，維持了專案關鍵約束（`FragmentActivity` 家族以支援 SAF 資料夾選取 `registerForActivityResult`）。
   - 明確劃分邊界：`resyncHighlight()` 只負責重發高亮，嚴格排除尚未實作的 Issue 8 安全視窗翻頁邏輯。
3. **誠實測試邊界與雙層驗證策略**：
   - 依據 `review-issues.md` Important #2 建議，狀態機的深層邏輯（焦點暫時失焦/永久失焦/恢復、耳機拔出、手動暫停防誤觸）全部在純 Dart 單元測試層透過 `FakeTtsAudioFocusSource` 進行 100% 覆蓋。
   - 承認 `flutter_test` 環境下 WebView 限制，在 Widget Test 層著重接線無崩潰與依賴貫穿驗證，並提供完整的 7 項真機手動驗收清單。

---

## 2. 審查檢核清單（Review Checklist）

| 檢核維度 | 評估項目 | 狀態 | 備註與技術確認 |
|---|---|:---:|---|
| **規格符合度** | Issue 7 驗收標準覆蓋 | **✅ 完整** | 背景播放、通知欄/鎖定畫面、耳機拔出/線控、焦點中斷與恢復、前景高亮重同步全數涵蓋。 |
| **原生層相容** | `MainActivity` 繼承鏈 | **✅ 良好** | 改為 `AudioServiceFragmentActivity`（`extends FlutterFragmentActivity`），相容 SAF 檔案選擇。 |
| **原生層權限** | Android Manifest 完整性 | **✅ 良好** | 包含 `FOREGROUND_SERVICE`、`FOREGROUND_SERVICE_MEDIA_PLAYBACK`、`POST_NOTIFICATIONS` 與查證補上的 `WAKE_LOCK`；`<service>` 與 `<receiver>` 正確宣告。 |
| **單例生命週期** | `AudioService.init` 唯一性 | **✅ 良好** | 在 `main.dart` 單次初始化，`ReaderScreen` 僅透過 `attachController`／`detachController` 轉接。 |
| **焦點恢復防護** | 使用者手動暫停防誤觸 | **✅ 良好** | `_pausedByFocus` 旗標嚴格限定僅在「暫時失焦時原本處於 playing」才置為 true，手動暫停與永久失焦不觸發自動恢復。 |
| **跨 Issue 邊界** | Issue 8 責任隔離 | **✅ 良好** | `resyncHighlight()` 僅重送目前 segment 高亮，不觸發翻頁與捲動指令。 |
| **依賴注入貫穿** | `LibraryScreen` 到 `ReaderScreen` | **✅ 完整** | `LibraryReaderFeatureRepositories` 納入新欄位，一般開書與分類篩選路徑皆有測試驗證轉送。 |
| **測試品質與分層** | TDD 與 Fake 替身 | **✅ 完整** | 提供 `FakeTtsAudioFocusSource`，涵蓋各事件轉換與邊界測試。 |
| **向後相容性** | 既有測試與 CBZ 格式 | **✅ 零回歸** | 新參數皆為 nullable，CBZ 模式不觸碰 `_ttsControllerOrNull`。 |

---

## 3. 核心設計亮點（Strengths to Preserve）

1. **焦點狀態機的防誤觸設計（Focus Restoration Guard）**：
   [`TtsAudioFocusCoordinator`](file:///U:/MyDeveloper/AI/elinkBook/app/lib/reader/tts_audio_focus_coordinator.dart) 中設計了 `_pausedByFocus` 旗標。只有因 `TtsAudioFocusEvent.transientLoss` 被迫暫停的播放，才會在收到 `TtsAudioFocusEvent.focusGained` 時自動重啟；使用者手動暫停、永久失焦或耳機拔出皆不會被後續的焦點恢復事件意外喚醒。
2. **前景服務生命週期與資源解耦（Clean Attachment/Detachment）**：
   [`TtsAudioHandler`](file:///U:/MyDeveloper/AI/elinkBook/app/lib/reader/tts_audio_handler.dart) 將全域唯一的 `AudioService` 與單書生命週期的 `TtsController` 解耦。開書與換書時呼叫 `attachController` 自動清理舊監聽並綁定新書名與狀態；關閉閱讀器時 `detachController` 立即重置 `MediaItem` 與 `PlaybackState`，避免記憶體洩漏與過期廣播。
3. **無縫的前景高亮校正（Graceful Resynchronization）**：
   在 [`ReaderScreen`](file:///U:/MyDeveloper/AI/elinkBook/app/lib/screens/reader_screen.dart) 的 `didChangeAppLifecycleState` 捕捉 `AppLifecycleState.resumed`，無條件呼叫 `_ttsController?.resyncHighlight()`，優雅解決背景播放時 WebView JS 計時器遭系統節流導致的高亮滯後問題。

---

## 4. 實作細節建議與觀察（Actionable Recommendations & Observations）

以下項目為非阻塞性技術建議，建議在實作各 Task 時一併納入以強化邊界防禦：

### 4.1. Task 2：`TtsController.resyncHighlight()` 的陣列索引防呆（Defensive Bounds Check）
- **現狀**：計畫中的實作：
  ```dart
  void resyncHighlight() {
    if (_disposed) return;
    if (_status == TtsPlaybackStatus.idle) return;
    onHighlightSegment?.call(_segments[_currentIndex]);
  }
  ```
- **建議**：雖然在非 `idle` 狀態下 `_currentIndex` 理論上有效，但考慮到非同步載入或異常重置的極端邊界，建議加上安全的邊界判斷：
  ```dart
  void resyncHighlight() {
    if (_disposed) return;
    if (_status == TtsPlaybackStatus.idle) return;
    if (_currentIndex < 0 || _currentIndex >= _segments.length) return;
    onHighlightSegment?.call(_segments[_currentIndex]);
  }
  ```
  可徹底杜絕 `RangeError (IndexOutOfBounds)` 風險。

### 4.2. Task 3：`TtsAudioFocusCoordinator` 焦點恢復時的狀態守衛
- **現狀**：`TtsAudioFocusEvent.focusGained` 分支為：
  ```dart
  case TtsAudioFocusEvent.focusGained:
    if (_pausedByFocus) {
      _pausedByFocus = false;
      controller.play();
    }
    break;
  ```
- **建議**：若使用者在暫時失焦期間（例如來電中）手動進行了翻頁或跳章（觸發了 `handleExternalPositionChange()` 將狀態重設為 `idle`），雖然 `_pausedByFocus` 仍為 `true`，但此時不宜直接呼叫 `controller.play()` 播放新章節。建議將條件收斂為：
  ```dart
  case TtsAudioFocusEvent.focusGained:
    if (_pausedByFocus) {
      _pausedByFocus = false;
      if (controller.status == TtsPlaybackStatus.paused) {
        controller.play();
      }
    }
    break;
  ```

### 4.3. Task 7：`_openGroupFilteredView` 的 Repository 轉送一致性
- **現狀**：Task 7 在 `library_screen.dart` 的 `_openGroupFilteredView()` 重新構建 `LibraryReaderFeatureRepositories` 並傳入 `ttsAudioHandler` 與 `ttsAudioFocusSource`。
- **觀察**：既有程式碼在該處手動列舉欄位時漏掉了 `layoutPresetRepository` 與 `bookReaderPrefsRepository`。在本次修改時，若直接傳入 `readerFeatureRepositories: widget.readerFeatureRepositories`，既可簡化程式碼，也能自然避免未來新增欄位時漏轉發的問題。

---

## 5. 審查結論（Final Verdict）

- [x] **實作計畫審查正式通過（Approved）**
- **後續步驟：** 可使用 `superpowers:subagent-driven-development` 或 `superpowers:executing-plans` 依據 [`plan-issue-7.md`](file:///U:/MyDeveloper/AI/elinkBook/docs/epics/epic-34-tts-readalong/plans/plan-issue-7.md) 啟動 Task 1 至 Task 7 的實作與測試驗證。
