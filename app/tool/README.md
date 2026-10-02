# `app/tool/`

開發輔助腳本，不屬於 App 本身，不會被打包進 APK。

## `check_l10n_hardcoded_strings.js`

兩項檢查（`epic-45-interface-i18n` Issue 10，規則契約見該 Epic `spec.md` §9）：

1. **字串稽核**：掃描 `app/lib/**/*.dart`，找出「Widget 字串參數位置」上**含中文字元且未經
   `AppLocalizations` 包裝**的字串字面值（`Text('確定')`、`title: '設定'`、
   `tooltip:`／`label:`／`hintText:` 等），防止畫面遺漏在地化與日後新增畫面忘記包裝。
2. **測試端稽核**：掃描 `app/test/**/*.dart`，確認每個 `MaterialApp(`／`MaterialApp.router(`
   的最外層參數都帶 `locale`／`localizationsDelegates`／`supportedLocales`。缺 `locale:`
   時 flutter_test 預設為 en_US，日後若在該測試加中文斷言會靜默失敗；缺委派則會在
   `AppLocalizations.of(context)!` 觸發 Null check。優先改用 `pumpLocalizedWidget()`。
   刻意保留裸 `MaterialApp` 的測試（`eb_sheet_shell_test.dart` 驗證無 `AppLocalizations` 時的
   fallback）以「檔案＋數量」記在腳本的 `TEST_BARE_APP_ALLOW`，數量不符即報警。

### 何時該執行

- **新增或修改任何畫面字串（Widget 樹內的文字）的 Issue，提交前**跑一次。
- 目前**沒有接進 CI**（這個 repo 尚未設定任何 CI pipeline，與
  `check_foliate_es_compat.js` 現況一致）。之後若要接進 CI，直接把下面的執行
  指令包進 workflow 步驟即可。

### 執行方式

不需要 `npm install`，只用 Node.js 內建模組：

```bash
node app/tool/check_l10n_hardcoded_strings.js            # 兩項檢查都做
# 測試／驗收時可指定其他目錄（只給其中一個旗標時只做對應那項檢查）：
node app/tool/check_l10n_hardcoded_strings.js --lib-dir <目錄>
node app/tool/check_l10n_hardcoded_strings.js --test-dir <目錄>
```

- 結束碼 `0`：乾淨，並印出實際掃描的檔案數（`PASS：掃描 N 個檔案…`、`PASS：掃描 N 個測試檔…`）。
- 結束碼 `1`：至少一處違規，會印出 `lib/<檔案>:<行號>  <字串>` 或 `test/<檔案>:<行號>  缺少 locale…`。
- 結束碼 `2`：設定錯誤——`--lib-dir` 缺參數、目錄不存在，或目錄內沒有任何可掃描的
  `.dart` 檔。這**不代表乾淨**，避免掃錯目錄被誤當成通過。

單元測試：`node app/tool/test_check_l10n_hardcoded_strings.mjs`。

### 找到問題時怎麼修

1. 在 `app/lib/l10n/app_zh_TW.arb`（模板，含 `@` 描述）與 `app_zh_CN.arb`／
   `app_en.arb`／`app_zh.arb` 新增對應 key（四份 key 集合必須一致，由 `test/l10n/arb_consistency_test.dart` 守衛），執行
   `cd app && flutter gen-l10n`。
2. 該處改用 `AppLocalizations.of(context)!.<key>`，並補上 zh_CN／en 兩個
   locale 的 widget test。
3. 若確屬合法例外（不需翻譯的專有名詞、資料、刻意的 fallback），在該行或上一
   行加 `// l10n-ignore: <理由>`（**必須寫理由**，空標記無效）；整檔例外或專有
   名詞值則加進腳本的 `SKIP_FILES`／`ALLOWED_LITERAL_VALUES` 並註明理由。

### ARB 一致性守衛

ARB 本身的一致性（四份鍵集合與 `{placeholder}` 名稱一致、`app_zh.arb` 與
`app_zh_TW.arb` 逐字相同、`app_en.arb` 沒有漏翻）由
`app/test/l10n/arb_consistency_test.dart` 守衛，隨 `flutter test` 執行，不需另外跑腳本。
若 `en` 的值**刻意**與 zh_TW 相同或含中文（例如語言自稱），把鍵與理由加進該測試的
`_enAllowlist`；項目不再命中時測試會要求移除。

### 已知限制

只偵測 spec §9 定義的「Widget 字串參數位置」。判定方式是找出字面值所在的
**參數運算式**（往回掃到同一層的 `,`／`;` 或尚未配對的 `(`／`[`／`{`），再看
這個參數是不是「文字參數」：

- `Text(`／`SelectableText(` 的第一個位置參數；
- 具名參數，名稱為 `label`／`title`／`subtitle`／`text`／`tooltip`／`message`／
  `content`／`hint`，或**以 `Label`／`Title`／`Text`／`Tooltip`／`Message`／
  `Hint`／`Subtitle` 結尾**（自訂 Widget 的 `deleteButtonLabel`、`hintText`、
  `semanticsLabel` 等都算；`labelStyle`／`contentPadding` 這類非文字參數不算）。

因此參數運算式內的**三元運算式與字串串接**（`tooltip: c ? '收藏' : '已收藏'`、
`Text('a' + '中')`、Dart 相鄰字串串接）都會被抓到；巢狀呼叫的引數
（`label: bar('中')`）、函式主體、相鄰的其他參數則不算。

**掃不到**：

- `record`／位置參數中的字串（例如 `(ColumnMode.single, 'single', icon, '單欄')`）。
- 參數運算式含 `??` 的 fallback（`label: x ?? '中文'`）——這是**刻意保留的逃逸口**，
  用於「無 `AppLocalizations` 時回退為固定字面值」的合法情境（例如
  `eb_sheet_shell.dart` 的「關閉」）；代價是硬編碼的 `?? '中文'` 也不會被抓。
- `assets/wifi_transfer/index.html`（電腦瀏覽器上的傳書網頁）不在掃描範圍；它的「無中文字面值」由 `test/wifi_transfer/wifi_transfer_page_test.dart` 守住。
- model 層字串與名稱不符合上述規則的參數。Issue 10 人工盤點時發現並已修正的例子：
  `Bookmark.defaultName()`、`TtsVoice` 的顯示名稱、OPDS 解析失敗的預設標題、`main.dart` 的
  通知頻道名稱——這類遺漏腳本仍抓不到，日後同類仍需靠 code review。
- 例外訊息、`assert`、`debugPrint` 等開發者診斷字串（設計上刻意不涵蓋，見
  `design.md`「Console Log／診斷內容翻譯」）。
- 字串插值 `${ … }` **內部**含註解（`/* ' */`、`// }`）時，掃描器的字串／註解狀態可能
  錯位；實務上不會這樣寫（`app/lib` 0 例），僅備忘。

這類遺漏仍需靠 code review 與人工盤點；本腳本只保證「最常見的 Widget 字串參數
位置」不會再漏。

## `bump_version.js`

建置要上傳到 Google Play 的 `.aab` 之前，用它更新版本號並記錄到版本對照表
（epic-52-play-release Issue 3）。它會顯示目前版本和 `store/google-play/release-log.md`
最後一筆，詢問 versionCode 要不要加 1、versionName 要不要改，再寫回
`app/pubspec.yaml`（只改 `version:` 那一行，保留原本的換行符號），並在對照表加一筆
「內部測試」紀錄。完整發布流程見 `docs/research/google_play_release_sop.md`。

### 何時該執行

- 每次要上傳新版本到 Google Play 之前（SOP 第 2.5、3 節）。

### 執行方式

```bash
cd app
node tool/bump_version.js          # 互動式
node tool/bump_version.js --yes    # 不詢問：versionCode 加 1、versionName 不變

# 測試／驗收時可指定其他檔案：
node tool/bump_version.js --pubspec <路徑> --log <路徑>
```

- 「加 1」的基準是 `pubspec.yaml` 和對照表裡**最大的** versionCode 中較大的那個。
  對照表最後一列不一定最大（例如把較舊的版本推到正式版），所以不能只看最後一列。
- 第一次上架（對照表沒有紀錄）時回答 `n`，保留 `1.0.0+1`。
- 結束碼 `0`：成功。`1`：輸入中斷，沒有修改任何檔案。`2`：設定錯誤（找不到檔案、
  路徑不是檔案、`version:` 格式錯誤、不認得的參數），沒有修改任何檔案；或是寫檔時
  發生未預期的錯誤，此時可能只更新了一個檔案，要用 `git status` 確認。
- 不在 git repo 裡或沒有安裝 git 時，commit 欄位填 `unknown` 並印出警告。

### 測試

```bash
node app/tool/test_bump_version.mjs
```

## `check_foliate_es_compat.js`

靜態掃描 `app/android/app/src/main/assets/foliate/`（`readest/foliate-js`
釘定版本，見 ADR 0011）是否使用了較新的 ES 內建方法（`Object.groupBy`／
`Array.prototype.at`／`Array.prototype.findLastIndex` 等），而
`app/lib/reader/foliate_native_bridge.dart` 的 `esCompatPolyfillJs`
還沒有對應的 polyfill。

**背景**：這份釘定的 vendor 程式碼在兩次真機 `/diagnose` 中都發現無條件呼叫
了較新的 ES 內建方法，較舊的 Android System WebView（例如 Chromium 91 的
Mobiscribe WAVE）不支援，導致開書失敗或整個卡在載入指示器（且部分裝置的
WebView 建置沒開遠端除錯，完全看不到例外訊息，非常難排查）。這支腳本讓
「升級釘定版本時上游引進了新的、目前完全沒設防的 ES 內建方法」這件事可以
提早在開發階段被發現，不必每次都等真機回報才後知後覺。

### 何時該執行

- **每次升級 `foliate/` 目錄下的釘定版本（bump commit）之後**，一定要跑一次。
- 平常開發不需要跑（純 Dart/Flutter 改動不會觸發這裡的邏輯）。
- 目前**沒有接進 CI**（這個 repo 尚未設定任何 CI pipeline）——純粹是一支
  可手動執行的獨立腳本，之後若要接進 CI，直接把下面的執行指令包進
  workflow 步驟即可。

### 執行方式

不需要 `npm install`，只用 Node.js 內建模組（`fs`／`path`）：

```bash
node app/tool/check_foliate_es_compat.js
```

- 結束碼 `0`：乾淨，目前找到的每個較新 API 用法都已有對應 polyfill 防護。
- 結束碼 `1`：找到至少一個尚未防護的用法，會印出檔案/行號與建議修法。

### 找到問題時怎麼修

1. 到 `app/lib/reader/foliate_native_bridge.dart` 的 `esCompatPolyfillJs`
   補上對應的 polyfill（僅在缺席時才定義，比照既有寫法，不覆蓋原生實作）。
2. 用 Node.js + `@xmldom/xmldom`（或視情況調整）對照未經修改的實際
   `epub.js`/`epubcfi.js`/`paginator.js` 驗證：缺席時真的會拋出例外、補上
   polyfill 後可修復（比照 epic-19 兩輪 `/diagnose` 紀錄的既有作法）。
3. 重新執行這支腳本確認乾淨。
4. 補上/更新 `app/test/reader/foliate_reader_view_test.dart` 裡驗證
   `initialUserScripts` 內容的既有測試，涵蓋新補上的 polyfill 名稱。

### 已知限制

純文字 regex 掃描，不是真的解析/執行 JavaScript，會有誤判空間（例如某個
變數剛好呼叫了 `.at(...)` 但其實跟 `Array.prototype.at`／
`String.prototype.at` 無關）。設計上寧可偶爾多提醒一次、也不要漏掉真正的
風險，故不追求零誤判；`RISKY_APIS` 清單本身也需要在發現新的較新 ES 內建
方法時手動擴充維護。

## `test_section_progress_density.mjs`

驗證 `progress.js` 的 `SectionProgress`（epic-26-architecture-hardening
Issue 11：已渲染 section 密度校正流式頁碼估算）純邏輯正確性——已知密度
換算、未知 section 最近鄰外插與 tie-break、清空快取退回統一常數、非線性
section 忽略共 5 項情境。`progress.js` 零 DOM 依賴，腳本用 Node.js 內建
`node:assert/strict` 直接執行，不需要任何測試框架。

### 何時該執行

- 每次修改 `progress.js` 的 `SectionProgress` 之後。
- 升級 `foliate/` 目錄下的釘定版本（bump commit）之後，若上游改動了
  `progress.js` 的既有邏輯，用這支腳本確認密度校正邏輯與新版上游程式碼
  仍相容。

### 執行方式

```bash
node app/tool/test_section_progress_density.mjs
```

- 結束碼 `0`：5 項情境全數通過。
- 非 `0`：斷言失敗或拋出例外，會印出對應的錯誤訊息與堆疊。

## `test_tts_safe_window.mjs`

驗證 `tts-safe-window.js` 的 `resolveTtsSafeWindowDirection()`（epic-26-architecture-hardening
Issue 12：TTS 安全視窗判斷邏輯純函式化）——橫排/直排各自的軟門檻/硬邊界
邊界值、needNext 與 needPrev 同時成立時的優先順序、必要輸入缺席共 13
項情境。
`tts-safe-window.js` 零 DOM 依賴，腳本用 Node.js 內建 `node:assert/strict`
直接執行，不需要任何測試框架。

### 何時該執行

- 每次修改 `tts-safe-window.js` 之後。
- 升級 `foliate/` 目錄下的釘定版本（bump commit）之後，若上游改動了
  `draw-annotation` 事件（`view.js`／`overlayer.js`）相關機制，確認安全
  視窗判斷邏輯仍與新版上游行為相容。

### 執行方式

```bash
node app/tool/test_tts_safe_window.mjs
```

- 結束碼 `0`：13 項情境全數通過。
- 非 `0`：斷言失敗或拋出例外，會印出對應的錯誤訊息與堆疊。

## `filter_antigravity_log.py` / `filter_antigravity_log.ps1`

過濾 Antigravity CLI 日誌噪音（`C:\Users\huthief\.gemini\antigravity-cli\log\cli-*.log`）。

**背景**：Antigravity 1.1.27 在 Windows 上有兩類高頻噪音會蓋掉真正錯誤：
1. `grep_handler.go:518` — Windows `C:/U:/` 路徑冒號被 `strings.Split(":")` 誤解析，
   每個內容搜尋結果都噴 `strconv.Atoi: invalid syntax`（實測佔真 E 的 91%，單次 burst 可達 284 行）
2. `ERROR: logging before google.Init: I...` — glog 在 `google.Init()` 前統一打 `ERROR:` 前綴，
   實際等級是 `I`（INFO），被視覺誤判為錯誤（實測 495 行）

此腳本僅做**顯示層過濾**，不修改原始 log 檔。上游修復前用於日常查 log 降噪。

### 執行方式

```bash
# 過濾最新一份 log（預設行為），過濾後內容走 stdout，統計走 stderr
python app/tool/filter_antigravity_log.py
python app/tool/filter_antigravity_log.py --stats          # 只看統計
python app/tool/filter_antigravity_log.py --aggressive     # 額外過濾 CORTEX/empty component 次要噪音
python app/tool/filter_antigravity_log.py --follow         # 即時 tail（每 2 秒刷新）

# 指定檔案 / 輸出到檔案
python app/tool/filter_antigravity_log.py -f C:/Users/huthief/.gemini/antigravity-cli/log/cli-20260907_135357.log
python app/tool/filter_antigravity_log.py -f cli-20260907_135357.log -o filtered.log

# PowerShell 包裝器（同參數）
powershell -ExecutionPolicy Bypass -File app/tool/filter_antigravity_log.ps1
powershell -ExecutionPolicy Bypass -File app/tool/filter_antigravity_log.ps1 -Stats
powershell -ExecutionPolicy Bypass -File app/tool/filter_antigravity_log.ps1 -Follow
```

### 過濾規則

| 規則 | 匹配 | 預設 |
|------|------|------|
| `grep_handler.go:518` | `grep_handler.go:518.*Error parsing grep result` | 丟棄 |
| Fake ERROR/INFO | `logging before google.Init: I\d{4}` | 丟棄 |
| `CORTEX_MEMORY_TRIGGER_UNSPECIFIED` / `empty component` | 僅 `--aggressive` | 保留 |

保留所有真 `E`/`W`（如 `token source`、`quota` 等需關注錯誤）。
