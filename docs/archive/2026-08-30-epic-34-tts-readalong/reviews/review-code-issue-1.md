# Code Review：epic-34-tts-readalong Issue 1（套件相依性驗證 spike）

**審查範圍：** `git diff 0df92c66e4caaf231050e43a191785d1996d7c50..epic-34-issue-1`
**審查方式：** 未 checkout 此分支到目前工作樹；改用既有的 `.worktrees/epic-34-issue-1` 獨立工作副本重跑驗證指令（唯讀審查，未修改任何檔案）。
**審查日期：** 2026-08-26

---

## Strengths

1. **變更範圍完全乾淨，未踩 Global Constraints 任一條紅線。** `git diff --stat` 只有兩個檔案：新增 `dependency-spike-findings.md`（43 行）與 `plan-issue-1.md` 的 checkbox 更新（9 處 `- [ ]` → `- [x]`，純粹是 diff mark，內容一字未改）。`app/pubspec.yaml`／`app/pubspec.lock`／任何 Dart／Kotlin／`AndroidManifest.xml` 皆未變動，與計畫 Global Constraints 完全一致。
2. **Task 1 的 dry-run 機械式驗證完全準確、可重現。** 我在獨立 worktree 中實際重跑了三次 `flutter pub add --dry-run`（`audio_service just_audio`／`flutter_tts`／三者一起），逐行核對輸出：
   - 新增套件與版本號（`audio_service 0.18.19`／`just_audio 0.10.6`／`flutter_tts 4.2.5` 等 10 個套件）**完全吻合**文件記載。
   - `share_plus`（`11.1.0`）／`file_picker`（`11.0.3`，滿足 `^11.0.2`）／`package_info_plus`（`9.0.1`）／`win32`（`5.15.0`）三次試算皆**未變動**，`flutter_inappwebview_android` 的 patch override 也未受影響。
   - `Would change 9 dependencies.` → `Would change 1 dependency.` → `Would change 10 dependencies.`（9+1=10）三個數字**完全吻合**。
   - 每次 dry-run 後 `git status --short pubspec.yaml pubspec.lock` 皆無輸出，證實 `--dry-run` 確實沒有寫入檔案。
   這代表撰寫計畫時「已於撰寫本計畫前實際執行過一次驗證」的宣稱是真的，不是編造的 Expected 輸出。
3. **`flutter analyze` 基準線確實乾淨。** 我在同一 worktree 重跑 `flutter analyze`，輸出 `No issues found! (ran in 10.6s)`，與文件宣稱一致（`flutter test` 因未變動任何 Dart 程式碼、且測試套件耗時較長，未在審查中重跑，風險判斷為極低）。
4. **Checkbox 進度誠實反映實際完成情況。** 兩個 Task／9 個 Step 的 `- [x]` 逐一比對，沒有發現「勾了但實際沒做」的情況——連 Step 3（確認變更範圍只有新增檔案）都能從實際的 commit 結構（`a389769a` 只改 `dependency-spike-findings.md` 一個檔案）驗證屬實。
5. **文件路徑、日期格式、依賴版本表格式皆符合計畫模板規格**，`{DATE}` 正確替換為 `2026-08-26`（與環境目前日期一致，非估算/虛構日期）。

---

## Issues

### Critical (Must Fix)

（無）

### Important (Should Fix)

1. **`dependency-spike-findings.md` 第 5 項 manifest 建議（`exported="false"`）與 `audio_service` 官方參考實作矛盾，可能誤導 Issue 7。**
   - **檔案：** `docs/epics/epic-34-tts-readalong/dependency-spike-findings.md`，「targetSdk manifest 需求清單」第 5 點
   - **問題：** 文件寫「`audio_service` 新增的 Service／Receiver 元件同樣須明確標註（通常為 `exported="false"`，僅供 App 自身與系統 MediaSession 框架呼叫，不對外開放）」。我實際檢視了 pub cache 中 `audio_service-0.18.19` 套件自帶的官方範例 `example/android/app/src/main/AndroidManifest.xml`，其 `AudioService`（`<service>`，帶 `android.media.browse.MediaBrowserService` intent-filter）與 `MediaButtonReceiver`（`<receiver>`，帶 `android.intent.action.MEDIA_BUTTON` intent-filter）**都明確標註 `android:exported="true"`**，不是文件所寫的「通常為 false」。
   - **為什麼重要：** `MediaButtonReceiver` 必須是 `exported="true"` 才能接收系統層（藍牙/有線耳機線控、`ACTION_MEDIA_BUTTON` 廣播）送進來的按鍵事件——這正是 Issue 7 驗收標準明列的「耳機線控（藍牙/有線）對應播放/暫停」。若 Issue 7 實作者直接依本文件字面「通常為 false」設定，會讓耳機線控整組失效，且問題不會在 `flutter analyze`/`flutter test` 層被抓到（需要真機才會發現），對應到 Issue 7 本身「手動真機驗收清單」才會踩雷，屆時排查成本更高。
   - **溯源說明（非本 Issue 實作者的錯）：** 這段文字是逐字複製自 `plan-issue-1.md` Task 2 Step 1 的預寫模板（計畫作者在撰寫計畫階段就已經這樣寫），Issue 1 的實作者是依計畫指示原樣照抄，並未自行編造或誤判。這是**計畫本身（連帶其上游 Discovery/`design.md` 決策）的內容錯誤**，只是透過 Issue 1 的交付物被放大成「Issue 2／Issue 7 可直接引用、不需重新調查」的權威文件，建議在合併前修正這一點的措辭（例如改為「依 intent-filter 用途決定，`MediaButtonReceiver`／有 `MediaBrowserService` intent-filter 的 Service 通常需要 `exported="true"` 才能被系統廣播/瀏覽觸發，需在 Issue 7 實作時對照官方範例確認，不要預設為 false」）。

2. **`minSdk` 覆核聲稱「三者皆為 21」與實測結果不符，「本次為覆核，未發現矛盾」的敘述不準確。**
   - **檔案：** `docs/epics/epic-34-tts-readalong/dependency-spike-findings.md`，「minSdk 相容性」段落
   - **問題：** 文件寫「`flutter_tts`／`audio_service`／`sherpa_onnx`...三者 minSdk 皆為 21...（Discovery 階段...已查證，本次為覆核，未發現矛盾）」。我實際檢視了 pub cache 中已下載、且與文件版本表**完全相同版本**的套件原始碼：
     - `flutter_tts-4.2.5`／`android/build.gradle` 第 40 行：`minSdkVersion 24`（**不是 21**，且**恰好等於**、而非「低於」專案現有 `minSdk = 24`——文件寫「低於專案現有 minSdk = 24」在此套件上是錯的）。
     - `audio_service-0.18.19`／`android/build.gradle.kts` 第 47 行：`minSdk = 19`（不是 21）。
     - 順帶一提：`just_audio-0.10.6`／`android/build.gradle.kts` 第 47 行：`minSdk = 16`（此套件是本 Issue 三個 dry-run 對象之一，卻完全未出現在 minSdk 段落的討論範圍內）。
     - `sherpa_onnx`（Phase 3 用）未被本次 dry-run 下載，無法在本次審查中獨立核實其 minSdk 是否為 21。
   - **為什麼重要：** 最終**結論本身**（三者皆不會把專案 `minSdk=24` 往上拉）目前仍然成立（19、16、24 皆 ≤ 24），所以不會造成立即的建置失敗；但文件明確宣稱「本次為覆核，未發現矛盾」，而實際重新查證後三個可核實的數字全部與宣稱不符，這代表這一段實際上**沒有真的被覆核**，只是照抄了 Discovery 階段的舊數字。`flutter_tts` 是「等於」而非「低於」現有下限，這個差距是有意義的資訊（未來若 `flutter_tts` 升版把 minSdk 往上調一階，就會直接觸發專案下限被迫調高，而「低於」的措辭讓人誤以為還有安全餘裕）。
   - **溯源說明：** 同上一點，這段文字同樣逐字複製自 `plan-issue-1.md` 的預寫模板，且計畫的 Global Constraints 明確指示「不需重新調查更精確的數字」——Issue 1 實作者是依計畫指示行事，責任在計畫／Discovery 階段的原始查證，不在本次實作。建議修正為列出三者（含 `just_audio`）各自實測的 minSdk 具體數字，並把「低於」改為「flutter_tts 與專案現有下限持平、其餘兩者更寬鬆」等更精確的措辭。

### Minor (Nice to Have)

1. **`minSdk` 段落漏列 `just_audio` 的 minSdk。** 本 Issue 的 Task 1 dry-run 明明包含 `just_audio`（Step 2/4），但「minSdk 相容性」段落只討論 `flutter_tts`／`audio_service`／`sherpa_onnx`，對同樣是本次驗證對象的 `just_audio` 隻字未提。建議一併補上（實測為 `minSdk = 16`，見上）。
2. **版本表建議加一欄「minSdk」**，讓 Issue 7 不需要另外去 pub cache 翻各套件的 `build.gradle`，可直接在同一份文件內看到完整資訊，減少未來還要另開工單覆核的機率。

---

## Recommendations

1. 在合併前（或合併後、Issue 7 開工前皆可，因為本 Issue 是文件交付物、不影響 Issue 2 加套件的動作），修正 `dependency-spike-findings.md` 的兩處 Important 問題：`exported` 建議值、`minSdk` 具體數字與「低於」措辭。這兩處錯誤都可回溯到 `plan-issue-1.md` 的預寫模板，若之後同一 Epic 還有類似「先寫好模板再照抄」的 Issue，建議在計畫撰寫階段對這類外部套件的技術細節（manifest 屬性、minSdk）也採取「附上查證來源連結或指令」的方式，而不是直接斷言數字/預設值，降低以訛傳訛的風險。
2. Issue 7 實際落實 manifest 宣告時，應直接對照 `audio_service` 套件自帶的 `example/android/app/src/main/AndroidManifest.xml`（本次審查已確認其存在且內容具參考價值），而不是只依賴本文件的文字敘述。
3. 這兩處錯誗不影響 Issue 1 本身的驗收標準達成（見下方逐條核對），不構成阻擋合併的理由，但建議明確追蹤（例如在 Issue 7 的計畫撰寫時重新核對一次 manifest exported 值），避免真的被字面照抄進 Kotlin/Manifest 程式碼。

### 驗收標準逐條核對（`issues.md` Issue 1）

- [x] `flutter pub add --dry-run` 確認無相依衝突——已透過獨立重跑驗證，三次 dry-run 皆無衝突，`share_plus`/`file_picker`/`package_info_plus`/`win32` 版本不變。
- [~] targetSdk manifest 宣告清單已文件化——**清單存在且大部分正確**（foregroundServiceType／兩個 FOREGROUND_SERVICE 權限／POST_NOTIFICATIONS／MainActivity 現況描述皆正確），但第 5 點 `exported` 建議值有誤（見 Important #1），嚴格來說「文件化」的動作完成了，但內容有一處需要修正才能真正達到「供後續 Issue 引用、不需重新調查」的效果。
- [x] `flutter analyze`／`flutter test` 基準線無回歸——`flutter analyze` 已重跑確認 `No issues found!`；`flutter test` 因未變動任何 Dart 程式碼、審查時間成本考量未重跑，風險評估為極低（無程式碼變更）。

---

## Assessment

**Ready to merge?** With fixes

**Reasoning：** Task 1 的機械式 dry-run 驗證工作完全準確、可重現，Global Constraints 零踩線，checkbox 進度誠實，是一次執行得很紮實的 spike。但交付物（`dependency-spike-findings.md`）中有兩處內容錯誤——`exported="false"` 建議與官方參考實作相反、`minSdk` 具體數字與實測不符——而這份文件的存在目的正是讓 Issue 2／Issue 7「直接引用、不需重新調查」，其中 `exported` 這一點若被字面照抄進 Issue 7 的 Kotlin/Manifest，有實際造成耳機線控功能失效的風險。建議在 Issue 7 開工前修正這兩處（責任可歸於計畫模板本身的預寫內容，而非本次實作的執行品質），修正後即可視為完全達標。
