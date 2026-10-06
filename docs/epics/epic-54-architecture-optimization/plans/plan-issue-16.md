# Issue 16：integration 測試真機載入轉圈與未完成的真機驗證 實作計畫

> **給執行者：** 必要子技能：使用 `superpowers:subagent-driven-development`（建議）或 `superpowers:executing-plans` 逐 Task 執行本計畫。步驟使用 checkbox（`- [ ]`）語法追蹤進度；每完成一個 Step 就把它改為 `- [x]`。

**Goal：** 查出 `integration_test/` 在真機上「閱讀器載入指示器不消失」的根因並修掉，讓 Issue 15 沒跑完的 27 個檔案能在真機執行，並把所有失敗依固定分類表記錄。

**Architecture：** 這是「先診斷、後修復」的計畫。根因現在未知，所以 Task 2 用三個可證偽的實驗縮小範圍，Task 3 依實驗結果走對應分支。只有分支 H1（等待時間太短）在本計畫給出完整程式碼；H2／H3 觸及 `lib/`，須在 Task 2 結束時回報使用者，補寫計畫附錄並經審查後才動手。Task 1 先解決 `BooksPad` 安裝太慢的前置問題，否則後面都做不了。

**Tech Stack：** Flutter／Dart、`integration_test`、`flutter_inappwebview`、`adb`、Node／Bash（一次性腳本）。指令一律在 `app/` 目錄下執行。

**Spec：** 沒有獨立 `spec.md`。缺陷描述見 `docs/epics/epic-54-architecture-optimization/issues.md` Issue 16；前因與已知事實見 `epic.md`「Issue 15 真機驗證結果」；分類表與 base 對照規則沿用 `plans/plan-issue-15.md` Task 4。

## Global Constraints

- **語言**：所有文件、註解、測試名稱一律正體中文（zh-TW），禁止簡體中文；程式碼命名維持英文慣例。
- **不放寬測試**：不得為了通過而改斷言、加 `skip`、或刪測試。**例外只有一個**：H1 分支允許把「等待載入的逾時秒數」調大，且必須有 Task 2 的實驗數據支持。
- **不改 `OpenBookFlow` 的正式逾時（30 秒）**與任何 `lib/` 行為，除非 Task 2 證明根因在 `lib/`，且已補計畫附錄並經使用者同意。
- **base 對照規則**：判定「既存」前，必須在 base `bdff826c`、同一台裝置、同一個檔案重現。不得以推測定案。
- **真機安全**：第一次執行 `flutter test`／`flutter drive` 前，必須先向使用者確認裝置，以及是否接受 Flutter 在簽章不符時解除安裝並清除該裝置上的 `cc.ugotit.elinkbook`。不得自行換裝置。目前已知裝置是 `BooksPad`（序號 `B78CW2508006423`），但仍須確認。
- **測試範圍**（CLAUDE.md）：單一 Task 只跑異動觸及的測試。完整 `flutter test`（無參數）只在最後一個 Task 跑一次（約 6 分鐘，`run_in_background`，必須在 `app/` 下）。
- **提交前**：`flutter analyze` 必須是 "No issues found!"，並執行 `node tool/check_l10n_hardcoded_strings.js`。
- **Windows 環境**：用 Bash 工具（Git Bash）。`python` 不可用。多數原始檔是 CRLF，Edit 的定位字串不要含換行。一次性腳本放 worktree 根目錄 `.scratch/`（untracked）。提交一律用明確路徑 `git add`，不用 `git add -A`。Bash heredoc 遇到含反引號與引號的長內容會失敗，腳本改用 Write 工具建檔。
- **Commit 結尾**必須帶 `Co-Authored-By: Claude Sonnet 5.5 <noreply@anthropic.com>`。
- **流程**：計畫先審查再動手。程式審查先出報告（存 `reviews/`，gitignore），審查者不直接改程式。審查摘要放進 `epic.md`。

## 已知事實（動手前先讀，不要重新推導）

- 載入指示器 `Key('reader_loading_indicator')` 由 `ReaderScreen` 在 `_openBookFlow.isLoading` 時顯示（`lib/screens/reader_screen.dart` 約第 2970 行）。
- 它只在 `onPageRendered` 觸發 `OpenBookFlow.onRendered()` 時消失（`reader_screen.dart` 的 `_handlePageRendered`，來源是 `FoliateReaderView` 的 JS handler `FoliateBridgeHandlers.onPageRendered`）。
- 正式 App 的 `OpenBookFlow` 逾時是 30 秒（`open_book_flow.dart` 第 149 行），逾時會轉成 `OpenBookFailed` 並顯示 `reader_error_text`。**測試的等待上限只有 10 秒**（例如 `epub_toc_test.dart` 第 29 行）。所以「測試等了 10 秒、App 還在載入中」與「載入真的卡死」現在無法區分。這是 H1 的由來。
- 同一個分支的一般 debug APK，在 `BooksPad`（WebView 91）與 `ViWoods Reader Air`（WebView 153）都能正常開書。
- `epub_toc_test` 已在 base `bdff826c` 同機對照確認為既存，不是 Issue 11 回歸。
- 22 個 `integration_test/` 檔案各自內嵌一份載入等待邏輯（含 `reader_loading_indicator`），沒有共用 helper。
- `integration_test/flutter_test_config.dart` 把 `framePolicy` 設為 `fullyLive`，原因見該檔案註解（Issue 9）。
- Issue 15 的執行方式：每檔 `flutter build apk --debug --target=integration_test/<檔>.dart`，使用者用 MTP 手動安裝，再 `flutter drive --use-application-binary`。腳本在 `.scratch/run_drive.sh`、`.scratch/adbshim/`、`app/test_driver/integration_test.dart`，都是 untracked。這些檔案在主工作區的 `.scratch/`，新 worktree 要複製過去。

## 假設表（Task 2 逐一證偽）

| 編號 | 假設 | 證偽實驗 | 若成立 |
|---|---|---|---|
| H1 | 測試只等 10 秒，但 debug APK 在這台裝置上冷啟動 WebView ＋ 載入 foliate-js 需要更久 | 實驗 A：同一檔案等待上限改 90 秒，記錄指示器消失的秒數，**並確認消失後畫面是正常內容、不是 `reader_error_text`**（App 自己 30 秒逾時也會讓指示器消失） | Task 3 走 H1 |
| H2 | WebView 內的 JS 出錯（ES 相容、素材路徑、未處理的 Promise），`onPageRendered` 永遠不會觸發 | 實驗 B：擷取 `adb logcat` 的 `chromium`／`flutter` 行，找 `Uncaught`、`ReferenceError`、`TypeError` | 回報使用者，補計畫附錄 |
| H3 | 測試的幀驅動方式（`fullyLive` 加 `tester.pump` 迴圈）讓 `InAppWebView` 沒有被掛載或沒有拿到尺寸 | 實驗 C：逾時時印出 `InAppWebView` 是否存在、**實際尺寸**（0x0 也算成立）、以及 `reader_error_text` 數量 | 回報使用者，補計畫附錄 |

## Review Focus

最可能咬到使用者的情況，每條都有對應 Task：

1. **把逾時調大後，真正卡死的測試被掩蓋成「慢」。** → Task 2 實驗 A 同時記錄「載入指示器消失的實際秒數」，且指示器消失後必須沒有 `reader_error_text` 才算 H1 成立。App 自己的 30 秒逾時（`OpenBookFailed`）也會讓指示器消失，若只看指示器，開書失敗會被誤判成「只是慢」。90 秒仍不消失，或消失但出現 `reader_error_text`，H1 都不成立，不得進 Task 3。
2. **調大逾時後，原本通過的測試變慢到整體跑不完。** → Task 3：只調 `_pumpUntilLoaded` 的上限，通過時不會多等（迴圈在指示器消失就結束）。
3. **22 個檔案的載入等待寫法不一，codemod 無聲略過。** 實際有三種：獨立 helper（約 15 檔）、`_pumpUntil(…, timeout:)`／`_loadingIndicatorGone`、直接寫在 `testWidgets` 內的迴圈；現有秒數也有 10／15／20，另有 `pumpAndSettle(seconds: 3)`。 → Task 3：codemod 先 dry-run 列出每一處命中，**任何檔案命中 0 處就輸出警告**，逐檔人工確認後才寫入。
4. **真機掉線或安裝失敗造成假失敗，被誤記成測試失敗。** → Task 4：每個檔案結果必須附 `+N -M` 計數或 `exit` 碼；出現 `device … not found`、`log reader stopped`、`INSTALL_FAILED` 記為環境失敗並重跑。
5. **分類時把 D 類（斷言與 locale 不符）自己改掉。** → Task 4：D 類只記錄、不改，交使用者決定。

## File Structure

| 檔案 | 動作 | 責任 |
|---|---|---|
| `.scratch/`（worktree 根目錄，不進版控） | 新增／複製 | 安裝加速腳本、`run_drive.sh`、`adbshim/`、實驗 log |
| `app/integration_test/*.dart`（22 個含 `reader_loading_indicator` 的檔案） | 修改（僅 H1） | 載入等待上限 10 秒 → 依實驗數據定案的秒數 |
| `app/test/support/pump_until_reader_loaded.dart` | **不建立** | 見 Task 3 說明：只調數字，不抽共用 helper（避免超出範圍） |
| `docs/epics/epic-54-architecture-optimization/{epic.md,issues.md}`、`docs/epics.md` | 修改 | 診斷結果、分類表、狀態 |

---

### Task 0：提交計畫、建立 worktree、確認裝置

**Files：**
- Commit：本計畫檔（在 `main`，純文件）
- 建立 worktree：`.worktrees/epic-54-issue-16-integration-device`

- [ ] **Step 1：提交計畫（在 `main`）**

```bash
git add docs/epics/epic-54-architecture-optimization/plans/plan-issue-16.md
git commit -m "docs(epic-54): Issue 16 實作計畫

Co-Authored-By: Claude Sonnet 5.5 <noreply@anthropic.com>"
```

- [ ] **Step 2：建立 worktree，複製真機工具**

```bash
git worktree add .worktrees/epic-54-issue-16-integration-device -b epic-54/issue-16-integration-device
mkdir -p .worktrees/epic-54-issue-16-integration-device/.scratch/it_results .worktrees/epic-54-issue-16-integration-device/.scratch/apks
cp -r .scratch/adbshim .scratch/sdkfake .scratch/run_drive.sh .worktrees/epic-54-issue-16-integration-device/.scratch/
mkdir -p .worktrees/epic-54-issue-16-integration-device/app/test_driver
cp app/test_driver/integration_test.dart .worktrees/epic-54-issue-16-integration-device/app/test_driver/
cd .worktrees/epic-54-issue-16-integration-device/app && flutter pub get
```

`test_driver/` 在 worktree 內是 untracked，**不要提交**。

- [ ] **Step 3：向使用者確認裝置（必做）**

問使用者：目標裝置序號（預設 `B78CW2508006423`，`BooksPad`）、是否接受清除該裝置上既有的 `cc.ugotit.elinkbook`。**得到明確回答前，不得執行任何 `flutter test`／`flutter drive`／`adb install`。** 然後確認連線穩定：

```bash
adb devices -l   # PATH 找不到 adb 時，改用 "$LOCALAPPDATA/Android/Sdk/platform-tools/adb.exe"
```

序號後面必須是 `device`。

---

### Task 1：解決 `BooksPad` 安裝太慢（前置）

**目標：** 找出一個能讓測試 APK 在 5 分鐘內裝好、不用人工 MTP 的做法。這個 Task 不改任何程式。

**計畫審查的實測數據（`BooksPad`，Android 12，ABI `armeabi-v7a`）：** USB 約 116～250 KB/s；56.3 MB 的 release APK 用 `adb install --no-streaming` 共 534 秒（推送 472 秒、`pm install` 62 秒），可靠但不會變快。`/data` 剩 40 GB，空間夠。Wi-Fi 目前關閉。結論：

- **縮小 APK 是最立即的手段。** 目前 debug APK 約 228 MB（含全部 ABI），改成只打包 `armeabi-v7a` 後體積約降為 1/4（審查以 release APK 估 56 MB，debug 實際大小以 build 結果為準）。USB 下單檔仍要約 8～9 分鐘，27 檔約 4 小時，只是勉強可行。
- **Wi-Fi 無線 adb 才是真正的解法。** 速度通常是 MB/s 等級，需要使用者先在 `BooksPad` 開啟 Wi-Fi。
- `--incremental` **不採用**：它要求 APK 同目錄有 v4 簽章檔（`.apk.idsig`），Flutter 的 debug APK 沒有，會被 adb 直接拒絕。

**Files：** 只在 `.scratch/` 內寫腳本與記錄。

- [ ] **Step 1：量測現況傳輸速度**

```bash
ADB=adb   # 本機 PATH 已有 adb（which adb 可確認）；找不到時才改用完整路徑 "$LOCALAPPDATA/Android/Sdk/platform-tools/adb.exe"
dd if=/dev/zero of=.scratch/zero_20m.bin bs=1M count=20 2>/dev/null
time "$ADB" -s B78CW2508006423 push .scratch/zero_20m.bin /data/local/tmp/zero_20m.bin
"$ADB" -s B78CW2508006423 shell rm /data/local/tmp/zero_20m.bin
```

記錄秒數，算出 MB/s。預期約 0.1～0.25 MB/s（審查實測 20 MB 約需 40 秒以上）。

- [ ] **Step 2：依序試三個做法，每個只量一次**

1. **只打包單一 ABI ＋ `--no-streaming`（不需使用者操作，先做）：**

```bash
cd app
ADB=adb
"$ADB" -s B78CW2508006423 shell getprop ro.product.cpu.abi   # 預期 armeabi-v7a
flutter build apk --debug --target-platform android-arm --target=integration_test/epub_toc_test.dart
ls -l build/app/outputs/flutter-apk/app-debug.apk
time "$ADB" -s B78CW2508006423 install --no-streaming -r -t build/app/outputs/flutter-apk/app-debug.apk
```

   記錄 APK 大小與總秒數。
2. **無線 adb**：請使用者先在 `BooksPad` 開啟 Wi-Fi 並連上與主機相同的區域網路，再執行：

```bash
"$ADB" -s B78CW2508006423 tcpip 5555
"$ADB" -s B78CW2508006423 shell ip -f inet addr show wlan0
"$ADB" connect <上一行的 IP>:5555
```

   拔掉 USB 線，對新的 `<IP>:5555` 序號重跑 Step 1，再重做做法 1 的 `install`。
3. **換 USB 線與孔位**（使用者操作）：換一條線、直接插主機後方 USB 孔（不經 hub），重跑 Step 1。

- [ ] **Step 3：選定做法並寫成腳本**

選速度最快且不需人工的做法。若三個都不行，在 `epic.md` 記錄量測數字，並**停止回報使用者**：此時 Task 4 只能沿用 Issue 15 的 MTP 手動安裝，工時約 27 檔 × 5 分鐘，請使用者決定要不要做。

若有可行做法，把它與 `flutter drive` 串成 `.scratch/run_drive.sh` 的新版本。`flutter test` 自動安裝時會打包全部 ABI，無法套用 `--target-platform`，所以做法 1 的流程是：`flutter build apk --debug --target-platform android-arm --target=integration_test/<檔>.dart` → `adb install --no-streaming -r -t` → `flutter drive --use-application-binary`（沿用 Issue 15 的 `adbshim` 吞掉 `install`）。只有做法 2（Wi-Fi）速度夠快時，才改回直接用 `flutter test`。用 `epub_toc_test` 驗證：

```bash
cd .worktrees/epic-54-issue-16-integration-device/app
flutter test integration_test/epub_toc_test.dart -d <device-id> 2>&1 | tail -n 15
```

預期：能自動安裝並執行到測試本體（結果仍可能是逾時失敗，這是 Task 2 要查的）。

- [ ] **Step 4：記錄**

在 `.scratch/it_results/transport.txt` 寫下三個做法的速度與選定結果。此檔不進版控，結論稍後寫進 `epic.md`。

---

### Task 2：診斷根因（三個實驗，不改 `lib/`）

**Files：** 只暫時改 `app/integration_test/epub_toc_test.dart`（實驗用，**Task 2 結束時 `git checkout` 還原**）。

**Interfaces：**
- Produces：一份寫進 `.scratch/it_results/diagnosis.txt` 的結論，格式為 `H1 成立／不成立`、`H2 成立／不成立`、`H3 成立／不成立`，各附證據一行。Task 3 依此分支。

- [ ] **Step 1：實驗 A——把等待上限放寬並記錄實際耗時**

只改 `epub_toc_test.dart` 的 `_pumpUntilLoaded`（第 28～35 行附近，內容與 `fxl_bookmarks_test.dart` 相同結構）。把 deadline 改成 90 秒，並在指示器消失時印出耗時：

```dart
Future<void> _pumpUntilLoaded(WidgetTester tester) async {
  final stopwatch = Stopwatch()..start();
  final deadline = DateTime.now().add(const Duration(seconds: 90));
  while (find.byKey(const Key('reader_loading_indicator')).evaluate().isNotEmpty) {
    if (DateTime.now().isAfter(deadline)) {
      // ignore: avoid_print
      print('[診斷A] 90 秒後載入指示器仍在');
      fail('等待逾時：載入指示器未消失');
    }
    await tester.pump(const Duration(milliseconds: 50));
  }
  // ignore: avoid_print
  print('[診斷A] 載入指示器在 ${stopwatch.elapsedMilliseconds} ms 後消失');
  // 指示器消失有兩種原因：真的載入完成，或 App 自己 30 秒逾時轉成 OpenBookFailed。
  // 後者不是「慢」，必須明確分開，否則會誤判 H1。
  if (find.byKey(const Key('reader_error_text')).evaluate().isNotEmpty) {
    // ignore: avoid_print
    print('[診斷A] 指示器消失但出現 reader_error_text（開書失敗，非 H1）');
    fail('開書失敗：出現 reader_error_text');
  }
  await tester.pump(const Duration(seconds: 1));
}
```

執行並存 log（用 Task 1 選定的安裝方式；以下以 `flutter test` 示意）：

```bash
flutter test integration_test/epub_toc_test.dart -d <device-id> > ../.scratch/it_results/diag_A.log 2>&1
grep -n "診斷A\|reader_error_text\|All tests passed\|Some tests failed" ../.scratch/it_results/diag_A.log
```

判讀：
- 出現 `在 N ms 後消失`、**沒有**出現 `reader_error_text`，且測試往後的步驟繼續執行（或整檔通過），且 N > 10000：**H1 成立**（記錄 N）。
- 出現 `指示器消失但出現 reader_error_text`：**H1 不成立**。這是開書失敗。若 N 約 30000，是 `OpenBookFlow` 的 30 秒逾時，代表 `onPageRendered` 從未觸發，根因在 H2／H3 或其他地方，繼續實驗 B、C。
- 出現 `90 秒後載入指示器仍在`：**H1 不成立**，繼續實驗 B。
- 出現 `在 N ms 後消失`且 N ≤ 10000：結果與 Issue 15 矛盾，先重跑一次確認；仍矛盾就停止回報使用者。

- [ ] **Step 2：實驗 B——擷取 WebView 與 Flutter 的 log**

在一個終端機先清 log 並開始擷取，再於另一個執行實驗 A 的指令（若 A 已成立，仍要做，用來排除 H2 同時存在）：

```bash
ADB=adb
"$ADB" -s <device-id> logcat -c
# Tag 要含 Console／cr_WebView：WebView 的 JS console.error 與未捕捉例外常用這些 Tag，
# 結尾的 *:S 會靜音其他所有 Tag，漏掉就看不到 JS 錯誤。
"$ADB" -s <device-id> logcat -v time chromium:V Console:V cr_WebView:V flutter:V InAppWebView:V *:S > ../.scratch/it_results/diag_B_logcat.log &
LOGCAT_PID=$!
flutter test integration_test/epub_toc_test.dart -d <device-id> > ../.scratch/it_results/diag_B.log 2>&1
# Git Bash 對 Windows 原生程序用 kill 常殺不掉，改用 taskkill
kill $LOGCAT_PID 2>/dev/null || taskkill //F //PID $LOGCAT_PID 2>/dev/null
grep -n "Uncaught\|ReferenceError\|TypeError\|SyntaxError\|net::ERR\|Failed to load" ../.scratch/it_results/diag_B_logcat.log | head -n 20
```

判讀：
- 有 `Uncaught`／`ReferenceError`／`TypeError`／`net::ERR`：**H2 成立**，記錄前三行。
- 完全沒有：H2 不成立。

- [ ] **Step 3：實驗 C——確認 WebView 有沒有被掛載**

在 `epub_toc_test.dart` 的 `_pumpUntilLoaded` 迴圈外、`pumpLocalizedWidget` 之後，臨時加一段（只印資訊，不改斷言）。先在檔案頂端加 `import 'package:flutter_inappwebview/flutter_inappwebview.dart';`，然後在 `_pumpUntilLoaded` 開頭：

```dart
  // ignore: avoid_print
  print('[診斷C] 開始等待時 InAppWebView 數量=${find.byType(InAppWebView).evaluate().length}');
```

並在 deadline 失敗分支前，以及上面實驗 A 的 `reader_error_text` 失敗分支前，各印一次（WebView 掛載了但寬或高為 0，Chromium 不會排版，也算 H3）：

```dart
      final webViewFinder = find.byType(InAppWebView);
      // ignore: avoid_print
      print('[診斷C] InAppWebView 數量=${webViewFinder.evaluate().length}，'
          '尺寸=${webViewFinder.evaluate().isNotEmpty ? tester.getSize(webViewFinder.first) : "無"}，'
          '錯誤文字=${find.byKey(const Key('reader_error_text')).evaluate().length}');
```

判讀：
- `InAppWebView 數量=0`，或尺寸的寬或高為 0：**H3 成立**。
- 數量為 1 且尺寸正常（例如接近螢幕大小）：H3 不成立。

- [ ] **Step 4：還原實驗用修改並寫結論**

```bash
git checkout app/integration_test/epub_toc_test.dart
```

在 `.scratch/it_results/diagnosis.txt` 寫下 H1／H2／H3 各自「成立／不成立」與證據。

**決策閘門：**
- 只有 H1 成立 → 進 Task 3。
- H2 或 H3 成立（含與 H1 同時成立）→ **停止，向使用者回報證據**，補計畫附錄（`lib/` 或測試基礎設施的修法）並經審查後才動手。
- 三個都不成立 → **停止回報使用者**，附上三份 log 路徑。不得猜測。

---

### Task 3：修復（僅 H1 分支）

**前置：** Task 2 結論為「只有 H1 成立」，也就是指示器消失後**沒有** `reader_error_text`（見實驗 A 判讀）。實驗 A 記錄到的最長耗時記為 `N` 秒。

**Files：**
- Modify：`app/integration_test/*.dart` 中含 `reader_loading_indicator` 的 22 個檔案，僅改載入等待的上限。
- Create（不進版控）：`.scratch/codemod_loading_timeout.js`

**Interfaces：**
- Produces：每個檔案「載入指示器附近」的等待上限，凡是原本在 10 秒以上、但小於 `T` 的，一律調成 `T` 秒（只升不降）。**不抽共用常數**：每個檔案的等待寫法各自內嵌，這個 Issue 只調數字，不改結構。

- [ ] **Step 1：定案秒數**

秒數 = `max(30, ceil(N × 2 / 1000))`。理由：不低於正式 App 的 30 秒逾時（`OpenBookFlow` 預設），且對最慢實測值留 2 倍餘裕。把定案值記為 `T`，寫進 commit 訊息與 `epic.md`。

- [ ] **Step 2：先看 22 個檔案的載入等待長什麼樣**

計畫審查已盤點：22 個檔案的寫法**不一致**，不能只靠一條正則。

| 寫法 | 檔案 | 現有秒數 |
|---|---|---|
| 獨立 `Future<void> _pumpUntilLoaded(…)` 等 helper | 約 15 檔（如 `epub_toc_test`、`fxl_bookmarks_test`、`foliate_cbz_test`） | 10、15、20 |
| `_pumpUntil(tester, _loadingIndicatorGone, timeout: const Duration(seconds: N))` | `reader_screen_test`、`orientation_repagination_test`、`library_screen_test` | 10 |
| 直接寫在 `testWidgets` 內的 `while` 迴圈 | `reader_footer_test`、`reader_header_footer_toggle_test`、`foliate_single_column_test` | 10、15 |
| `pumpAndSettle(const Duration(seconds: 3))` | `custom_font_rendering_test` | 3 |

執行下面指令確認盤點仍然正確。若出現這四種以外的寫法，**停止**並回報：

```bash
grep -n -B4 -A4 "reader_loading_indicator\|_loadingIndicatorGone" integration_test/*.dart | grep "seconds:" | head -n 80
```

- [ ] **Step 3：寫 codemod（預設只列清單，加 `--apply` 才寫檔）**

做法：找出每個含 `reader_loading_indicator` 或 `_loadingIndicatorGone` 的行，只看它前後 4 行內的 `Duration(seconds: N)`；N 在 10 以上且小於 `T` 才改成 `T`。不碰 N < 10（例如 `seconds: 1`、`seconds: 2`）、也不碰 N ≥ `T`。這樣三種寫法都涵蓋，而且不會改到同檔其他不相干的等待。

用 Write 工具建立 `.scratch/codemod_loading_timeout.js`：

```js
// 用法：node ../.scratch/codemod_loading_timeout.js [--apply] <T秒> <檔案...>
// 不加 --apply：只印出每一處命中（dry-run）。加了才寫檔。
const fs = require('fs');
const args = process.argv.slice(2);
const apply = args.includes('--apply');
const rest = args.filter((a) => a !== '--apply');
const T = Number(rest[0]);
const files = rest.slice(1);
if (!Number.isFinite(T) || T < 30 || files.length === 0) {
  console.error('用法：node codemod_loading_timeout.js [--apply] <T（>=30）> <檔案...>');
  process.exit(2);
}
const TRIGGER = /reader_loading_indicator|_loadingIndicatorGone/;
const WINDOW = 4;
const zero = [];
let total = 0;
for (const f of files) {
  const lines = fs.readFileSync(f, 'utf8').split('\n'); // 保留行尾 \r，CRLF 檔不被破壞
  const hitLines = new Set();
  lines.forEach((line, t) => {
    if (!TRIGGER.test(line)) return;
    const from = Math.max(0, t - WINDOW);
    const to = Math.min(lines.length - 1, t + WINDOW);
    for (let i = from; i <= to; i++) {
      for (const m of lines[i].matchAll(/Duration\(seconds:\s*(\d+)\)/g)) {
        const n = Number(m[1]);
        if (n >= 10 && n < T) hitLines.add(i);
      }
    }
  });
  if (hitLines.size === 0) { zero.push(f); continue; }
  for (const i of [...hitLines].sort((a, b) => a - b)) {
    console.log(`${f}:${i + 1}: ${lines[i].trim()}`);
    if (apply) {
      lines[i] = lines[i].replace(/Duration\(seconds:\s*(\d+)\)/g, (s, d) => {
        const n = Number(d);
        return n >= 10 && n < T ? `Duration(seconds: ${T})` : s;
      });
    }
  }
  total += hitLines.size;
  if (apply) fs.writeFileSync(f, lines.join('\n'));
}
console.log(`${apply ? '已改' : '將改'} ${total} 行；命中 0 處的檔案（必須人工處理）：${zero.length ? zero.join(', ') : '無'}`);
```

- [ ] **Step 4：先 dry-run，並在三種寫法各一個檔案上試套用**

```bash
# 1. 全部 22 個檔案 dry-run，逐行確認命中的是載入等待、不是別的
node ../.scratch/codemod_loading_timeout.js <T> $(grep -l "reader_loading_indicator" integration_test/*.dart)
# 2. 三種寫法各挑一個真的套用並審 diff
node ../.scratch/codemod_loading_timeout.js --apply <T> integration_test/epub_toc_test.dart integration_test/reader_screen_test.dart integration_test/reader_footer_test.dart
git diff integration_test/epub_toc_test.dart integration_test/reader_screen_test.dart integration_test/reader_footer_test.dart
```

預期：
- `epub_toc_test` 只有載入等待那一處改變；同檔其他 `seconds: 10`（例如 TOC 渲染、章節跳轉）若不在載入指示器 4 行範圍內，**不變**。
- `reader_screen_test` 有 20 處 `seconds: 10`，只有緊貼 `_loadingIndicatorGone` 的才改，其餘不變。
- `reader_footer_test` 是直接寫在 `testWidgets` 內的迴圈，確認有命中。
- 若 diff 出現不是載入等待的行被改，調整 `WINDOW` 或改成逐檔人工處理，`git checkout` 還原後再試。

- [ ] **Step 5：套用到全部 22 個檔案並確認**

```bash
node ../.scratch/codemod_loading_timeout.js --apply <T> $(grep -l "reader_loading_indicator" integration_test/*.dart)
flutter analyze
node tool/check_l10n_hardcoded_strings.js
git diff --stat | tail -n 1
```

預期：`flutter analyze` 是 "No issues found!"；檢查腳本全 PASS。以 `T=60` dry-run 預演過：22 檔中 21 檔命中、共 28 行；其中 `reader_screen_test`（3 行）、`library_screen_test`（3 行）、`reader_header_footer_toggle_test`（4 行）命中較多，**必須逐行確認都是載入等待**，不是相鄰的其他等待。「命中 0 處的檔案」清單預期是 `custom_font_rendering_test`（它用 `pumpAndSettle(const Duration(seconds: 3))`，不是等指示器消失）。清單裡每個檔案都要**人工讀過**：判斷它的載入等待是否真的需要調整，把結論與理由寫進 commit 訊息。不得因為腳本沒報錯就當作已處理。

- [ ] **Step 6：用被卡住的 5 個檔案驗證**

```bash
for t in fxl_bookmarks_test epub_toc_test reading_position_test foliate_cbz_test reader_screen_test; do
  flutter test integration_test/$t.dart -d <device-id> > ../.scratch/it_results/fix_$t.log 2>&1
  echo "$t exit=$?" >> ../.scratch/it_results/fix_summary.txt
done
cat ../.scratch/it_results/fix_summary.txt
```

預期：`fxl_bookmarks_test`、`epub_toc_test`、`foliate_cbz_test` 不再出現 `等待逾時：載入指示器未消失`。若仍出現，**H1 的結論有誤**，還原修改並回 Task 2 重新診斷。`reading_position_test` 與 `reader_screen_test` 可能因其他原因仍失敗，這是 Task 4 的分類範圍。

- [ ] **Step 7：Commit**

```bash
git add app/integration_test/
git commit -m "test(epic-54): integration 載入等待上限由 10 秒調為 <T> 秒（Issue 16）

真機實測載入指示器約 <N> ms 後才消失，原本 10 秒的等待上限在慢速裝置上
必然逾時。只調等待上限，不改斷言。

Co-Authored-By: Claude Sonnet 5.5 <noreply@anthropic.com>"
```

---

### Task 4：補完其餘 27 個檔案的真機驗證與分類

**前置：** Task 1 已有可自動安裝的做法（否則照 Task 1 Step 3 的停止規則，先請使用者決定）。Task 3 已完成，或 Task 2 結論允許繼續。

**Files：** 僅在判定為 C 類時修改 `lib/` 或測試；其餘只更新文件。

- [ ] **Step 1：建立逐檔執行腳本**

用 Write 工具建立 `.scratch/run_integration.sh`：

```bash
#!/usr/bin/env bash
# 用法：bash ../.scratch/run_integration.sh <device-id>   （在 app/ 目錄下執行）
DEVICE="$1"
OUT=../.scratch/it_results
mkdir -p "$OUT"
: > "$OUT/summary.txt"
# 已在 Issue 15 驗證過的 5 個檔案與人工驗收檔不重跑
SKIP="manual_import_acceptance_test fxl_bookmarks_test epub_toc_test reading_position_test foliate_cbz_test reader_screen_test"
for f in $(grep -l "pumpLocalizedWidget" integration_test/*.dart | sort); do
  name=$(basename "$f" .dart)
  case " $SKIP " in *" $name "*) continue ;; esac
  echo "=== $name ===" >> "$OUT/summary.txt"
  flutter test "$f" -d "$DEVICE" > "$OUT/$name.log" 2>&1
  rc=$?
  echo "exit=$rc" >> "$OUT/summary.txt"
  # 裝置斷線時快速中斷：連續 2 個檔案都出現 device not found，剩下的檔案只會逐一逾時，白白浪費時間
  if grep -q "device .* not found\|no devices/emulators found" "$OUT/$name.log"; then
    miss=$((miss + 1))
  else
    miss=0
  fi
  if [ "$miss" -ge 2 ]; then
    echo "ABORT：連續 2 個檔案找不到裝置，中止。請確認 adb devices -l 後重跑剩餘檔案" >> "$OUT/summary.txt"
    exit 3
  fi
  grep -E "All tests passed|Some tests failed|\+[0-9]+ -[0-9]+|Build failed|not found|log reader stopped|INSTALL_FAILED" "$OUT/$name.log" | tail -n 3 | cut -c1-160 >> "$OUT/summary.txt"
done
echo DONE >> "$OUT/summary.txt"
```

若 Task 1 選的做法需要 `flutter drive`，把 `flutter test "$f" -d "$DEVICE"` 換成 `bash ../.scratch/run_drive.sh "$name" "$DEVICE"`（並先 build 該檔的 APK）。

預期要跑 27 個檔案：含 `pumpLocalizedWidget` 的檔案共 33 個，扣掉 `SKIP` 清單的 6 個（1 個人工驗收檔 `manual_import_acceptance_test` ＋ 5 個已驗證檔），`33 - 6 = 27`。用下面指令確認數字：

```bash
grep -l "pumpLocalizedWidget" integration_test/*.dart | wc -l   # 預期 33
```

- [ ] **Step 2：背景執行（預估 1 小時以上；手機保持接線、螢幕亮著）**

```bash
bash ../.scratch/run_integration.sh <device-id>
```

用 `run_in_background` 執行，等完成通知，不要輪詢。

- [ ] **Step 3：排除環境失敗**

```bash
grep -l "not found\|log reader stopped\|INSTALL_FAILED\|Unable to start the app" ../.scratch/it_results/*.log
```

列出的檔案是環境失敗，**不分類**。確認 `adb devices -l` 穩定後單獨重跑，直到沒有為止。

- [ ] **Step 4：對每個失敗分類**

對 `summary.txt` 中 `exit` 非 0 的檔案，讀 `.log` 的第一個例外（`grep -n "EXCEPTION CAUGHT\|Expected\|Actual\|The following"`），依下表記錄「檔案、測試名、例外摘要」：

| 類別 | 判斷 | 處理 |
|---|---|---|
| A. 仍是多語系 null check | 例外是 `AppLocalizations.of(context)!`／`Null check` | Issue 15 沒修乾淨，回報使用者 |
| B. 既存、與 Issue 11 無關 | 例外與依賴組、`AppLocalizations` 無關，且**base 上同機同樣失敗** | 不修，記進 `epic.md`，建議另立工單 |
| C. Issue 11 回歸 | 例外與 `ReaderFeatureDependencies`、`StateError('ReaderFeatureDependencies 缺少 …')` 相關，**且 base 上通過** | 本 Issue 修：先寫能重現的失敗測試（單元測試優先），再修 `lib/` |
| D. 斷言與介面不符 | 失敗的 `find.text('…')` 與現行介面文字不符。包含兩種：(1) 多語系文字不符（斷言英文、介面是正體中文）；(2) **過期斷言**：介面改版後，測試沒跟著改。例：`reading_position_test` 第 88 行與 `reader_footer_test` 第 73 行找 `進度 67% ｜ 第 4/6 頁`，但 `lib/screens/reader_footer.dart` 的頁尾現在只顯示 `${currentPage}/${totalPages}`（即 `4/6`），`lib/` 內已沒有那個字串 | 不自行改文字。記錄檔案、斷言、現行介面文字、以及你查到的改版來源，交使用者決定要不要在本 Issue 修 |
| E. 通過 | `All tests passed!` | 無 |

**base 對照步驟**（判 B 或 C 前必做，同一台裝置）：

```bash
# 1. 主 repo 根目錄建立 base worktree
git worktree add .worktrees/base-bdff826c bdff826c
# 2. 取依賴，並用 Issue 15 的 codemod 補多語系（腳本在 Issue 15 worktree 的 .scratch/ 或主工作區 .scratch/）
( cd .worktrees/base-bdff826c/app && flutter pub get && node ../../../.scratch/codemod_integration_l10n.js integration_test/<目標檔>.dart )
# 3. 若 Task 3 有調整等待上限，對 base 同樣套用，確保對照條件一致
( cd .worktrees/base-bdff826c/app && node ../../epic-54-issue-16-integration-device/.scratch/codemod_loading_timeout.js <T> integration_test/<目標檔>.dart )
# 4. 同機執行並存 log
( cd .worktrees/base-bdff826c/app && flutter test integration_test/<目標檔>.dart -d <device-id> > ../../epic-54-issue-16-integration-device/.scratch/it_results/base_<目標檔>.log 2>&1 )
# 5. 記錄後清理
git worktree remove --force .worktrees/base-bdff826c
```

第 2 步的 codemod 路徑以實際存在位置為準；找不到就先 `ls .scratch/`、`ls .worktrees/*/.scratch/` 確認。

- [ ] **Step 5：補驗 Issue 15 留下的 5 個檔案**

這 5 個已在 Task 3 Step 6 跑過。對仍失敗的，分類方式同 Step 4：
- `epub_toc_test`：已確認 B（Issue 15），只需確認調整等待上限後結果。
- `fxl_bookmarks_test`、`foliate_cbz_test`：對 base 逐檔對照（Issue 15 尚未做）。
- `reading_position_test` PDF 案例：找不到文字 `進度 67% ｜ 第 4/6 頁`。計畫審查已查到：頁尾現在顯示 `4/6`（`lib/screens/reader_footer.dart` 第 120 行，`Key('reader_footer_progress_text')`），`lib/` 內已沒有 `進度 67% ｜ 第 4/6 頁`，`reader_footer_test` 第 73 行有同樣的斷言。所以這很可能是 **D 類（過期斷言）**。仍須確認：用真機畫面或 `reader_footer_progress_text` 的實際文字證明「跳頁其實成功了、只是文字不同」，再歸 D；若實際頁碼也不是 4，才是 B／C。D 類只記錄，交使用者決定。
- `reader_screen_test`：`等待逾時（10 秒）：條件未成立`（渲染非空白內容），第 139、203、231 行的 `timeout: const Duration(seconds: 10)` 是否也需依 Task 2 結果調整，由實驗 A 的數據決定；不得憑感覺改。

- [ ] **Step 6：記錄結果**

在 `epic.md` 新增「Issue 16 真機驗證結果」段落：裝置、日期、診斷結論（H1／H2／H3）、安裝做法與速度、32 個檔案各自的 `+N -M`、分類表（檔案、測試名、類別、例外摘要、base 對照結果）、B 類清單（建議另立工單）、D 類清單（待使用者決定）。C 類另列修復 commit。

---

### Task 5：收尾

**Files：** `docs/epics/epic-54-architecture-optimization/{epic.md,issues.md}`、`docs/epics.md`

- [ ] **Step 1：完整 `flutter test`（只在這裡跑一次）**

```bash
cd .worktrees/epic-54-issue-16-integration-device/app
flutter test > ../.scratch/it_results/full_test.log 2>&1
```

用 `run_in_background`，約 6 分鐘。預期：只有既存的 `pdf_reader_view_filters_test`（bold overlay 多頁案例）失敗（Issue 15 已在乾淨 `main` 確認）。出現其他失敗就是本 Issue 造成，必須查。

- [ ] **Step 2：`flutter analyze` 與檢查腳本**

```bash
flutter analyze
node tool/check_l10n_hardcoded_strings.js
```

預期：No issues found!；三行 PASS。

- [ ] **Step 3：更新文件**

- `issues.md` Issue 16 狀態改為「🟢 實作完成，待程式審查」（含 PR 後再改為已合併）。
- `docs/epics.md` 備註只寫「Issue 16 已完成」，不寫歷程。
- 若 H1 以外的根因讓 Task 3 停下，狀態改為「🟡 診斷完成，待計畫附錄」並寫明卡在哪。

- [ ] **Step 4：Commit 文件並請求程式審查**

```bash
git add docs/epics/epic-54-architecture-optimization/epic.md docs/epics/epic-54-architecture-optimization/issues.md docs/epics.md
git commit -m "docs(epic-54): Issue 16 真機驗證結果與狀態同步

Co-Authored-By: Claude Sonnet 5.5 <noreply@anthropic.com>"
```

程式審查報告存 `docs/epics/epic-54-architecture-optimization/reviews/review-issue-16.md`（gitignore，不進版控）。審查者先出報告，不直接改程式。

---

## 自我審查

**Spec 對照（Issue 16 工單文字）：**
- 載入指示器不消失的根因 → Task 2（診斷）、Task 3（H1 修復；H2／H3 設停止閘門）。
- 其餘 27 個檔案真機驗證 → Task 4 Step 1～3。
- 4 個未對照 base 的檔案分類 → Task 4 Step 4～5。
- `reading_position_test` PDF 案例、`reader_screen_test` 根因 → Task 4 Step 5。
- 前置：`BooksPad` adb 傳輸過慢 → Task 1。

**已知缺口（刻意保留，不是佔位符）：** 根因現在未知，所以 H2／H3 的修法不在本計畫內。Task 2 的決策閘門要求先回報使用者再補附錄。這比寫一個猜測的修法安全。

**佔位符掃描：** `<T>`、`<N>`、`<device-id>`、`<目標檔>` 是執行時才知道的實測值或使用者回答，每處都有對應的取得步驟（Task 3 Step 1、Task 0 Step 3、Task 4 Step 4）。

**型別一致性：** 本計畫沒有新增 Dart 型別或函式。codemod 只改 `Duration(seconds: 10)` 字面值。

## 修訂紀錄

**2026-10-06 依 `reviews/review-plan-issue-16.md` 修訂**（Critical 2、Important 4、Minor 4 全數採納，皆已對照程式碼查證屬實）：

- C-1：實驗 A 增加 `reader_error_text` 檢查，判讀改為「指示器消失且無錯誤文字」才算 H1；Review Focus 第 1 點同步。
- C-2：Task 3 codemod 改為「依載入指示器前後 4 行、只升不降、預設 dry-run」；Step 2 補四種寫法盤點表；以 `T=60` 預演 21/22 檔命中。
- I-1：Task 1 移除 `--incremental`（缺 v4 簽章），改為 `--target-platform android-arm` ＋ `--no-streaming` 為做法 1，Wi-Fi 無線 adb 為做法 2。
- I-2：實驗 C 加印 `InAppWebView` 尺寸，0x0 也算 H3。
- I-3：logcat 加 `Console:V cr_WebView:V`。
- I-4：D 類擴充為「斷言與介面不符」，含過期斷言；`reading_position_test` PDF 案例預判為 D，但須先證明跳頁成功。
- M-1：改用 `kill … || taskkill //F //PID`。M-2：更正為 33 − 6 = 27。M-3：批次腳本連續 2 次找不到裝置即中止。M-4：改用 PATH 上的 `adb`。

**未採納：** 無。審查的 debug APK 大小估算（約 56 MB）取自 release APK，計畫已註明 debug 實際大小以 build 結果為準。

## 附錄 A：Task 2 診斷結論與修復（2026-10-06）

**診斷（`BooksPad`，`epub_toc_test`，詳見 `.scratch/it_results/diagnosis.txt`）：** H1、H2 不成立，H3 成立。根因是新的 H4：`ReaderFeatureDependencies` 預設的 `FakeDownloadableFontStore.directory` 是不存在的 `/fake/downloaded-fonts`，`ReaderScreen` 把它傳給 `FoliateReaderView.downloadedFontsDirectory`，Android 原生的 `WebViewAssetLoader.InternalStoragePathHandler` 在 WebView 建立時拒絕不存在的目錄並丟 `PlatformException`，`InAppWebView` 從未掛載，30 秒後 `OpenBookFlow` 逾時。base `bdff826c` 的 `downloadableFontStore` 可為 null，integration 測試不傳，不會建立該 handler。

**決策（使用者選擇做法 1：只改測試端，不動 `lib/`）：**

- `FakeDownloadableFontStore` 新增選用建構參數 `directory`，預設值維持 `/fake/downloaded-fonts`（單元測試行為不變）。
- `fakeReaderFeatureDependencies` 與 `completeLegacyReaderFeatures` 的預設 store：在 Android 上（`Platform.isAndroid`，即真機 integration 測試）改傳一個**真實存在的暫存目錄**（`Directory.systemTemp.createTempSync`，即 App 快取目錄，在 `InternalStoragePathHandler` 允許範圍內）；其他平台（`flutter test` 於桌面主機）維持原值。
- 與先前提議的差異：原本想逐檔改 21 個 integration 檔案，改為只改工廠的預設值，異動檔案從 21 個降為 3 個，且不會有 codemod 誤改。

**Task 3（調整等待上限）取消：** H1 不成立，不需要調 10 秒。

**驗證：** 重新建置安裝，不加任何診斷，直接跑 `epub_toc_test`，預期不再 `等待逾時：載入指示器未消失`。H4 修好之後，base 上同一檔案「同樣逾時」的原因仍未查明，Task 4 對照時需另行確認，不得沿用 Issue 15 的 B 類結論。
