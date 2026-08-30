# Issue 9 程式審查報告

**Base:** `ef43c86181b0be3b0b6c5acc1a1734891e31e342` / **Head:** `5dcea30deb76c9522cc69c461aad82006e8495f2` / **審查日期：** 2026-08-27

## Strengths

- **完全依計畫執行、零走樣。** 逐一比對 `plans/plan-issue-9.md` 每個 Task 的程式碼片段與實際 diff（`library_screen_dependencies.dart`、`library_screen.dart` 兩處呼叫端、`main.dart`、`AndroidManifest.xml`），文字內容、行號位置、import 排序皆與計畫完全一致，沒有臨場加料或偷改範圍。
- **刻意不修的相鄰缺口確實維持原樣。** `_openGroupFilteredView()`（`app/lib/screens/library_screen.dart:614-618`）的 `LibraryReaderFeatureRepositories(...)` 逐欄位轉送區塊，本次只新增 `ttsProvider:` 一行，`layoutPresetRepository`／`bookReaderPrefsRepository` 兩個既有缺口確認未被順手修掉，符合 Global Constraints 明訂的範圍界線。
- **完全不新增 UI、不重複實作 CBZ 排除邏輯。** `git diff` 對 `app/lib/screens/reader_screen.dart`／`app/lib/reader/system_tts_provider.dart`／`app/lib/reader/tts_provider.dart` 三份檔案皆為空——本 Issue 純粹是接線，沒有動到 Issue 2 已完成的播放邏輯與格式判斷，達成計畫宣稱的「純接線、零回歸」。
- **測試對稱涵蓋兩條開書路徑。** `_openBook()`（一般開書）與 `_openGroupFilteredView()`（分類篩選自我遞迴）兩條路徑都各自補了一個 `same(ttsProvider)` 貫穿驗證測試，且後者連「傳到下一層 `LibraryScreen.readerFeatureRepositories.ttsProvider`」與「再傳到 `ReaderScreen`」兩段都分開斷言，測試邏輯紮實、非空洞的 mock-only 驗證。
- **AndroidManifest 改動精確對症。** 新增的 `TTS_SERVICE` `<intent>` 區塊巢狀在既有單一 `<queries>` 元素內、與 `PROCESS_TEXT` 並列，XML 結構合法（已用 `git show` 讀取 head 版本確認），且註解清楚交代「為何非做不可」與「不做的後果」，對照 `flutter_tts` 官方文件要求，屬於這次審查認為最有價值的一項修正。
- **文件誠實反映實際完成狀態。** `issues.md` 的四條驗收標準中，唯一需要人類介入才能驗證的「真機安裝後開啟…能看到並使用朗讀播放/暫停按鈕」正確保留未勾選；已完成的三條（接線、既有測試零回歸、`flutter analyze`／`flutter test` 全數通過）才打勾，沒有虛報。`epic.md` 開發記錄新增的一段也如實描述「待真機安裝 APK 驗證」，未誇大成「已完成」。

## Issues

### Critical (Must Fix)

無。

### Important (Should Fix)

無。

### Minor (Nice to Have)

- `docs/epics/epic-34-tts-readalong/plans/plan-issue-9.md` 全文把已完成的 Step 逐一從 `- [ ]` 改為 `- [x]`，純粹是計畫執行紀錄的勾選狀態更新，不影響程式行為，僅在此記錄以求審查記錄完整（無需任何行動）。

## Verification（本次審查實測，非僅靜態閱讀）

審查在唯讀 checkout 上不便直接跑建置/測試指令，因此另開一個獨立 `git worktree`（`git worktree add` 指向 head commit `5dcea30d`，未移動本次審查 checkout 的 HEAD）在其中執行：

- `flutter pub get`：成功。
- `flutter analyze`：`No issues found!`（81.8s）。
- `flutter test test/screens/library_screen_test.dart test/elinkbook_app_wiring_test.dart`：92 個測試全數通過，含 Issue 9 新增的 3 個貫穿驗證測試（`_openBook()` 路徑、`_openGroupFilteredView()` 路徑、`ElinkBookApp` 組裝路徑）。
- `flutter test`（全專案）：**1744 個測試全數通過**，與 `epic.md` 開發記錄宣稱的「1744 測試通過」精確吻合，零回歸。
- `AndroidManifest.xml` head 版本內容經 `git show` 讀取確認：新增的 `TTS_SERVICE` `<intent>` 正確巢狀於既有 `<queries>` 元素內，結構合法。

審查完畢後已用 `git worktree remove` 清除該暫存 worktree，未對本次審查所在的原始 checkout 做任何異動。

## Recommendations

- 無架構或流程面的必要建議；本 Issue 範圍極小、執行乾淨，唯一剩餘動作是計畫本身已明訂的真機安裝驗證（不在本次程式審查範圍內）。

## Assessment

**Ready to merge？** Yes

**Reasoning：** 實作與計畫逐字對齊、`flutter analyze`／全專案 `flutter test`（1744 項）皆通過、AndroidManifest 改動經確認為合法且對症的 XML、範圍界線（不新增 UI、不重複 CBZ 邏輯、不順手修鄰近缺口）全數遵守，文件對「待真機驗證」的狀態誠實揭露，沒有發現任何 Critical 或 Important 問題。

---

## 追加審查：664c550f（真機無聲問題防禦修正）

**Base:** `5dcea30deb76c9522cc69c461aad82006e8495f2` / **Head:** `664c550f0e9d2e7ed58b387b2ff64680dfe5df2b` / **審查日期：** 2026-08-27

**背景說明**：本段審查針對前次審查（上方，Base `ef43c861`／Head `5dcea30d`）之後追加的一個小 commit，**不在原計畫 `plans/plan-issue-9.md` 任何 Task 範圍內**，是使用者在真機測試過程中額外補上的防禦性修正，只動了兩個檔案（`system_tts_provider.dart` +14/-0、`system_tts_provider_test.dart` +5/-1）。

**額外揭露**：審查當下該分支所在 worktree（`.worktrees/epic-34-issue-9`）HEAD 已推進到 `5d531113`（比審查對象 `664c550f` 多一個 commit），對 `synthesize()` 做了更大幅改寫（加入引擎預檢、語言設定、5 秒逾時），並移除了 `664c550f` 新增的「可用引擎列表」錯誤訊息內容。審查者已另外用 `git show 664c550f:app/lib/reader/system_tts_provider.dart` 取出該 commit 當下的精確內容逐行審查，確保審查對象正確，不受後續 commit 干擾。`5d531113` 額外引入 3 個 `avoid_print`（`system_tts_provider.dart:39/41/58`）analyzer info，不符合專案「提交前必須乾淨」規範，但這是 `5d531113` 的問題，不屬於本段審查對象 `664c550f`。

### Strengths

1. 防禦邏輯放置時機正確：在 `await completer.future;`（等待原生端 TTS 完成回呼）之後才做檔案存在性/大小檢查，語意上正確對應「引擎回報完成但實際沒寫出可用音檔」這個真機無聲的根因。
2. 短路判斷順序正確：`!await file.exists() || await file.length() == 0`——先判斷存在性，短路後才呼叫 `file.length()`，不會對不存在的檔案呼叫 `length()` 造成例外。
3. 沿用既有例外型別：直接丟出 Issue 2 既有定義的 `TtsSynthesisException`（`app/lib/reader/tts_provider.dart:66`），沒有發明新例外類別或改變 `synthesize()` 對外契約，呼叫端錯誤處理路徑不需改動。
4. 診斷資訊 best-effort、不搶主要錯誤：`getEngines` 呼叫包在獨立 `try/catch`，失敗時忽略讓 `engines` 維持 `const []`，不會讓「取得引擎列表失敗」蓋掉更重要的「檔案為空」原始錯誤。
5. 錯誤訊息內容恰當：正體中文、可操作（提示去系統設定安裝/啟用中文 TTS 引擎），只帶出公開的 TTS 引擎套件識別字串（如 `com.google.android.tts`），不涉及隱私或敏感資訊。
6. 測試同步更新避免假陽性：mock handler 對 `synthesizeToFile` 新增 `File(filePath).writeAsStringSync('dummy wave content');`，讓兩個既有測試在新增檢查後仍反映「合成成功且檔案有內容」的正確情境，顯示作者確實理解新檢查對既有 fixture 的影響並主動修正。
7. 範圍嚴格限縮：只觸及 `system_tts_provider.dart` 與其單元測試，沒碰 UI、沒碰格式判斷分派邏輯，完全落在 Issue 9 原計畫 Global Constraints「不新增任何 UI 視覺元件」允許範圍內，也沒有連帶去修已知排除在外的 `_openGroupFilteredView()` 缺口，無範圍蔓延疑慮。

### Issues

#### Critical (Must Fix)

無。

#### Important (Should Fix)

- **缺少「檔案不存在/大小為 0 時應拋出例外」的直接測試案例**。File: `app/test/reader/system_tts_provider_test.dart`（`664c550f` 版本第 38-42 行附近）。這次修改只調整既有兩個測試的 mock 行為（新增 dummy content 寫入），確保新檢查不會誤傷既有測試，但沒有新增測試直接驗證新邏輯本身——例如模擬 `synthesizeToFile` 送出 `synth.onComplete` 但刻意不寫入任何檔案內容，斷言 `provider.synthesize(...)` 會 `throwsA(isA<TtsSynthesisException>())`。這代表這段防禦邏輯目前沒有自動化回歸保護，若日後有人不慎改壞這個 `if` 條件（例如打錯成 `&&`），現有測試套件抓不到。建議補一個測試：
  ```dart
  test('synthesize() 在合成檔案不存在或大小為 0 時拋出 TtsSynthesisException', () async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      if (call.method == 'synthesizeToFile') {
        // 刻意不寫入任何檔案內容，模擬引擎回報完成但檔案為空/不存在。
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
    await expectLater(
      provider.synthesize('測試文字', voice: TtsVoice.systemDefault),
      throwsA(isA<TtsSynthesisException>()),
    );
  });
  ```
  （此範例對應 `664c550f` 當下程式碼；若照目前 worktree 實際 HEAD `5d531113`，mock handler 還需回應 `getEngines`/`getDefaultEngine`/`setLanguage`/`setSpeechRate`，否則會卡在其他更前面新增的步驟。）

#### Minor (Nice to Have)

- `getEngines` 回傳型別與宣告型別不完全對齊。File: `app/lib/reader/system_tts_provider.dart`（`664c550f` 版本，新增區塊內）。`flutter_tts` 套件的 `getEngines` 是 `Future<dynamic> get getEngines`（見 `flutter_tts-4.2.5/lib/flutter_tts.dart:498`），可能回傳 `null`；程式碼 `List<dynamic> engines = const []; ... engines = await _flutterTts.getEngines;` 若真收到 `null`，賦值時會觸發執行期隱式向下轉型例外，不過整段包在 `try/catch` 內會被吞掉、`engines` 維持 `const []`，最終行為仍正確，只是屬於「意外被 catch-all 接住」而非「明確處理」。不影響本次合併判斷；範圍外的後續 commit `5d531113` 已改用 `?? const []` 明確處理，可視為對此觀察的佐證。
- `file.length()` 的 IO 例外未被統一轉型。同一區塊。若檔案在檢查當下因極端情況（例如原生端行程仍持有寫入鎖）拋出 `FileSystemException`，會以原始例外型態往外傳，不會被轉換成呼叫端已知的 `TtsSynthesisException`。機率極低、非阻擋等級。

### Recommendations

- 補上 Important 提到的「檔案為空/不存在時拋出例外」測試案例，讓這段防禦邏輯有實際回歸保護。
- 提醒作者：worktree 已經推進到 `5d531113`，該 commit 引入 3 個 `avoid_print` info 級 analyzer 問題，不符合專案「提交前必須乾淨（No issues found!）」規範，且移除了本次審查對象新增的「可用引擎列表」錯誤訊息內容，建議一併排入下一輪審查範圍或請作者確認是刻意精簡還是遺漏。

### Assessment

**Ready to merge?** With fixes

**Reasoning:** 新增的防禦邏輯本身正確、時機恰當、範圍嚴格限縮於 Issue 9 計畫允許的防禦性修正，不違反任何 Global Constraints；主要缺口是新邏輯沒有直接對應的新測試驗證（Important，非阻擋程式正確性，但屬可快速補齊的測試覆蓋缺口），建議補測試後即可合併。
