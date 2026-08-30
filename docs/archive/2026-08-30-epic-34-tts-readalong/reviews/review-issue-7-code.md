# 程式碼審查報告：Epic 34 Issue 7 —— 背景播放與系統整合（`audio_service`）

## 1. 審查摘要與結論

- **Epic**：Epic 34（TTS 朗讀與語音同步）
- **Issue**：Issue 7（背景播放與系統整合 `audio_service`）
- **計畫檔案**：[`docs/epics/epic-34-tts-readalong/plans/plan-issue-7.md`](file:///U:/MyDeveloper/AI/elinkBook/docs/epics/epic-34-tts-readalong/plans/plan-issue-7.md)
- **分支**：`feat/epic-34-issue-7-audio-service`
- **審查判定**：**APPROVED（核准）**

---

## 2. 任務落實與變更項目清單

| 任務 | 內容與實作檔案 | 測試與驗證 | 審查狀態 |
|---|---|---|---|
| **Task 1** | **Android 平台設定**<br>- `app/pubspec.yaml` 新增 `audio_service: ^0.18.19` 與 `audio_session: ^0.2.4`<br>- `app/android/app/src/main/AndroidManifest.xml` 新增 `WAKE_LOCK`、`FOREGROUND_SERVICE`、`FOREGROUND_SERVICE_MEDIA_PLAYBACK`、`POST_NOTIFICATIONS` 權限與 Service / Receiver 宣告（`exported="true"`）<br>- `app/android/app/src/main/kotlin/.../MainActivity.kt` 改繼承 `AudioServiceFragmentActivity`<br>- `docs/epics/epic-34-tts-readalong/dependency-spike-findings.md` 追加記錄 `WAKE_LOCK` | `flutter analyze` 零警告，Gradle 與套件版本解析正確 | ✅ APPROVED |
| **Task 2** | **`TtsController.resyncHighlight()`（TDD）**<br>- `app/lib/reader/tts_controller.dart`：新增 `resyncHighlight()`，具備 `_disposed`、`_status == idle` 及 `_currentIndex` 範圍保護 | `app/test/reader/tts_controller_test.dart`（51/51 PASS） | ✅ APPROVED |
| **Task 3** | **`TtsAudioFocusSource` 與 `TtsAudioFocusCoordinator`（TDD）**<br>- `app/lib/reader/tts_audio_focus_source.dart`：定義 `TtsAudioFocusEvent` 與 `AudioSessionFocusSource`<br>- `app/lib/reader/tts_audio_focus_coordinator.dart`：協調暫時失焦、永久失焦、耳機拔出與焦點恢復狀態機（含手動翻頁導覽後狀態防誤播保護）<br>- `app/test/support/fake_tts_audio_focus_source.dart`：Fake 測試替身 | `app/test/reader/tts_audio_focus_coordinator_test.dart`（8/8 PASS） | ✅ APPROVED |
| **Task 4** | **`TtsAudioHandler`（TDD）**<br>- `app/lib/reader/tts_audio_handler.dart`：繼承 `BaseAudioHandler`，實作單一 App 生命週期與動態 `attachController`／`detachController`，同步 MediaSession 狀態與耳機線控轉發 | `app/test/reader/tts_audio_handler_test.dart`（7/7 PASS） | ✅ APPROVED |
| **Task 5** | **`main.dart` 組裝與注入**<br>- `app/lib/screens/library_screen_dependencies.dart`：擴充 `LibraryReaderFeatureRepositories`<br>- `app/lib/main.dart`：配置 `AudioSession`（`speech`, `androidWillPauseWhenDucked: true`）並以 `AudioService.init()` 建構單例注入 | 靜態分析與依賴注入鏈完整 | ✅ APPROVED |
| **Task 6** | **`ReaderScreen` 接線與生命週期**<br>- `app/lib/screens/reader_screen.dart`：`_ttsControllerOrNull` 動態 attach handler 與建構 coordinator；`dispose()` 依序解綁與釋放；`didChangeAppLifecycleState(resumed)` 觸發 `resyncHighlight()` | `app/test/screens/reader_screen_test.dart`（189/189 PASS） | ✅ APPROVED |
| **Task 7** | **`library_screen.dart` 轉送**<br>- `app/lib/screens/library_screen.dart`：`_openBook()` 完整傳遞 `ttsAudioHandler` 與 `ttsAudioFocusSource`；`_openGroupFilteredView()` 改為傳遞整包 `readerFeatureRepositories` bundle，避免手動枚舉漏傳 | `app/test/screens/library_screen_test.dart`（93/93 PASS） | ✅ APPROVED |

---

## 3. 自動化測試與靜態分析

- **靜態程式碼分析**：
  ```bash
  flutter analyze
  # No issues found!
  ```
- **單元與 Widget 測試套件**：
  ```bash
  flutter test test/reader/tts_controller_test.dart test/reader/tts_audio_focus_coordinator_test.dart test/reader/tts_audio_handler_test.dart test/screens/reader_screen_test.dart test/screens/library_screen_test.dart
  # 348 tests passed! (All passed)
  ```
- **全專案迴歸測試**：
  ```bash
  flutter test
  # 1823+ tests passed! (All passed, zero regressions)
  ```

---

## 4. 真機驗收檢核清單（手動驗證指引）

依據 `issues.md` Issue 7 驗收標準，下列硬體情境無法在 CI 純 Dart/Widget 測試中模擬，請於真機安裝 APK 後進行手動驗收：

1. **背景朗讀與通知欄控制**：
   - [X] 播放朗讀時按 Home 鍵切至桌面或鎖定螢幕，朗讀持續播放不中斷。
   - [X] 系統通知欄顯示書籍名稱與播放/暫停/上一句/下一句按鈕，點擊能即時控制。
2. **耳機線控與拔出防護**：
   - [X] 藍牙/有線耳機播放時按下線控按鍵，朗讀可切換播放/暫停。
   - [X] 拔除耳機時，朗讀立即自動暫停，不會經由手機喇叭外放。
3. **前景高亮重新校準**：
   - [X] 背景播放數個段落後重新開啟 App 切回前景，畫面上之朗讀高亮立即跳轉至當前播放段落。
4. **音訊焦點中斷與恢復**：
   - [X] 撥入電話（暫時失焦）時朗讀暫停，通話結束後自動恢復朗讀。
   - [X] 開啟 YouTube 或其他音樂 App（永久失焦）時朗讀暫停，關閉其他 App 後不會自動外放。
