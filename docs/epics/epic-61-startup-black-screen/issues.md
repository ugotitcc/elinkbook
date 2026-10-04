# Epic 61 — 啟動黑屏後續：工單清單 (Issues)

2 個 Issue。F2（找觸發條件）是調查，不是工作項目，留在 `epic.md` 的「後續項目」表，不開 Issue。

```
Issue 1（F3 降級提示）   獨立，範圍小
Issue 2（F1 不阻塞啟動） 獨立，範圍大；建議在 Issue 1 之後做
```

兩者互不依賴。建議先做 Issue 1：範圍小，且 Issue 2 改完後 handler 會晚到，降級提示的觸發點需要一起對齊。

---

## Issue 1：降級後讓使用者知道（F3）

**Status:** 實作與真機驗證完成，待程式審查與 PR

**依賴：** 無。

**背景：** `initTtsAudioHandlerSafely` 失敗回傳 null 時，只有 `debugPrint`。使用者看不到任何說明，只會發現沒有媒體通知、鎖屏控制。朗讀本身仍可用（見 `epic.md` 程式審查 M-1）。

**What to build：**
- 降級時（handler 為 null）進入 App 後顯示一次性提示，文字說明「朗讀仍可使用，但本次沒有媒體通知與鎖屏控制」。
- 提示形式、顯示位置、顯示次數（2026-10-05 人類決定）：進入閱讀器時顯示 SnackBar，每次啟動 App 只顯示一次。
- 新增 4 個 arb 字串（比照現有 4 種語系），不可硬編碼中文。

**測試要求：**
- widget 測試：handler 為 null 時顯示提示；handler 非 null 時不顯示。
- 若有「只顯示一次」規則，測試重複進入不重複顯示。
- `flutter analyze` 乾淨；`node tool/check_l10n_hardcoded_strings.js` 通過。

**驗收標準：** 用暫時故障 manifest（`AudioServiceBROKEN`，做完還原）在電子紙重現降級，畫面出現提示；正常版不出現。

**Blocked by：** 無。

---

## Issue 2：AudioService 初始化不阻塞啟動（F1）

**Status:** todo

**依賴：** 無（建議在 Issue 1 之後）。

**背景：** 綁定逾時時，`AudioService.init` 要等約 10 秒才丟例外，降級後 App 仍黑屏約 10 秒（逾時秒數為推測，未實測）。

**What to build：**
- 先量測：做出可控的「綁定逾時」（不是立即失敗的故障 manifest），量出實際黑屏秒數，記錄在 `epic.md`。
- `main()` 不再 `await` `AudioService.init`，`runApp` 先執行。handler 完成後再注入。
- handler 目前以建構子參數傳給 `LibraryScreen`、`ReaderScreen`（`main.dart`、`library_screen_dependencies.dart`、`reader_screen.dart`）。需改為可晚到注入。作法（例如 `ValueNotifier<TtsAudioHandler?>`）在寫 `plans/plan-issue-2.md` 時決定，並送審查，審查前不寫程式。
- 保留 `AudioService.init` 全程式只呼叫一次、失敗不可重試的限制。
- 閱讀中途 handler 才到：`ReaderScreen` 已建立的 `TtsController` 須能事後 `attachController`。

**測試要求：**
- 單元測試：init 延遲完成時，`runApp` 路徑不被阻擋；晚到的 handler 會被注入。
- widget 測試：handler 由 null 變成非 null 後，`ReaderScreen` 會 attach；失敗維持 null 時行為與現況相同。
- 既有 `elinkbook_app_wiring_test`、`tts_audio_handler_startup_test` 不改而通過。

**驗收標準：** 可控逾時情境下，電子紙冷啟動在 2 秒內進入書架（數值於量測後修正）；正常情境下媒體通知、鎖屏控制照常；全套 `flutter test` 通過。

**Blocked by：** 無。
