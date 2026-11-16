# `app/tool/`

開發輔助腳本，不屬於 App 本身，不會被打包進 APK。

## 在這台 Windows 執行 Node 腳本

nvm 沒有安裝任何 Node 版本，`node` 會回 `No active Node.js version is configured`。pnpm 內建了 Node，改用它：

```powershell
# 1. 把 pnpm 的 Node 排到 PATH 最前面（只對目前這個 PowerShell 視窗有效）
$env:PATH = "$env:PNPM_HOME;$env:PATH"
node --version   # 應為 v24.15.0

# 2. 提交前的兩個檢查（在 app/）
cd app
node tool/check_l10n_hardcoded_strings.js
node tool/check_integration_keys.js

# 3. foliate_touch_harness（第一次要先裝 Chrome）
cd tool/foliate_touch_harness
npx puppeteer browsers install chrome
node run-all.mjs
```

- 步驟 1 不能省：`run-all.mjs` 會用 PATH 裡的 `node` 起子程序。
- 不要用 `pnpm exec`：測試台用 `package-lock.json`，pnpm 的依賴檢查會失敗。改用 `npx` 或 `node`。
- 在 Git Bash 裡 PATH 不同；目前這台機器的 Git Bash 內 `node` 也可直接使用（v26.13），診斷類腳本在哪個殼層跑都可以，需要 pnpm 內建 Node 的步驟（測試台、`run-all.mjs`）仍請用 PowerShell。

## `check_integration_keys.js`

找出 `app/integration_test/` 引用、但 `app/lib/` 已不存在的 `Key`。`integration_test/` 只能在真機執行，
平常的 `flutter test` 不會跑，介面改版後測試仍引用舊 key 也不會有人發現（epic-54 Issue 16／17）。

### 何時該執行

改了 `lib/` 內任何 `Key(...)`、或新增／修改 `integration_test/` 之後，提交前執行。

### 執行方式

```bash
cd app
node tool/check_integration_keys.js
node tool/test_check_integration_keys.mjs   # 守衛本身的單元測試
```

結束碼：0 乾淨；1 有過期 key；2 設定錯誤或掃到 0 個檔案（目錄指錯時不會被當成乾淨）。

### 比對規則

`Key('x')`（單、雙引號皆可）的 `x` 只要符合其一就算存在：等於 `lib/` 內某個不含 `$` 的字串字面值；
符合 `lib/` 內某個 `Key(…)` 參數的範本（`nav_zone_$index` 這類動態 key，第一個 `$` 之前至少 4 個固定字元）；
以 `keyPrefix: '…'` 加底線開頭；或是測試檔自己用 `key: Key('x')` 建立。掃描 `lib/` 時排除 `l10n/`。
範本只從 `Key(…)` 取，不從所有字串取：否則 `"$_temp0"` 這類字串會變成萬用正則，讓守衛永遠通過。

### 已知限制

只檢查字串字面值的 `Key`；測試端含 `$` 的 key（迴圈變數組成，例如 `Key('pdf_settings_$keySuffix')`）無法靜態解析，跳過；
`find.text(...)`、`find.byType(...)`、元件型別轉型（例如 `tester.widget<TextButton>`）不在範圍內，
這類過期仍須靠真機執行才看得到。

另外兩個會「漏報」的情況（Issue 17 程式審查 M-6，行為與上方比對規則一致，不是 bug，但要知道）：

- `lib/` 內**任何**不含 `$` 的字串字面值都算「存在」，不限於 `Key(…)` 的參數，也包含註解裡的引號字串。
  如果過期的 key 剛好等於 `lib/` 內某個無關字串（例如測試引用 `Key('client_id')`，而 `lib/` 有 `'client_id'` 這個字串），
  守衛會判為存在。這是刻意取捨：`Key` 常由變數、`keyPrefix`、`itemKey:` 等多種寫法組成，只比對 `Key(…)` 會大量誤報。
- 測試端比對是**逐行**進行：`Key(` 與字串分在兩行的寫法（`Key(\n  'x',\n)`）不會被檢查到。
  `dart format` 把 key 拆成多行時要留意。

## `check_l10n_hardcoded_strings.js`

三項檢查（`epic-45-interface-i18n` Issue 10，規則契約見該 Epic `spec.md` §9；第 3 項由 `epic-54` Issue 15 加入）：

1. **字串稽核**：掃描 `app/lib/**/*.dart`，找出「Widget 字串參數位置」上**含中文字元且未經
   `AppLocalizations` 包裝**的字串字面值（`Text('確定')`、`title: '設定'`、
   `tooltip:`／`label:`／`hintText:` 等），防止畫面遺漏在地化與日後新增畫面忘記包裝。
2. **測試端稽核**：掃描 `app/test/**/*.dart`，確認每個 `MaterialApp(`／`MaterialApp.router(`
   的最外層參數都帶 `locale`／`localizationsDelegates`／`supportedLocales`。缺 `locale:`
   時 flutter_test 預設為 en_US，日後若在該測試加中文斷言會靜默失敗；缺委派則會在
   `AppLocalizations.of(context)!` 觸發 Null check。優先改用 `pumpLocalizedWidget()`。
   刻意保留裸 `MaterialApp` 的測試（`eb_sheet_shell_test.dart` 驗證無 `AppLocalizations` 時的
   fallback）以「檔案＋數量」記在腳本的 `TEST_BARE_APP_ALLOW`，數量不符即報警。
3. **integration 測試端稽核**：掃描 `app/integration_test/**/*.dart`，規則同第 2 項，但**沒有白名單**
   （integration 測試沒有刻意保留裸 `MaterialApp` 的案例）。integration 測試在真機上執行，缺
   `localizationsDelegates` 時 `AppLocalizations.of(context)!` 會 Null check 崩潰；這批測試曾因為
   這項檢查只涵蓋 `app/test/` 而長期無聲壞掉（`epic-54` Issue 15）。一律用
   `pumpLocalizedWidget(tester, home)`（`import '../test/support/pump_localized_widget.dart'`）。

### 何時該執行

- **新增或修改任何畫面字串（Widget 樹內的文字）的 Issue，提交前**跑一次。
- 目前**沒有接進 CI**（這個 repo 尚未設定任何 CI pipeline，與
  `check_foliate_es_compat.js` 現況一致）。之後若要接進 CI，直接把下面的執行
  指令包進 workflow 步驟即可。

### 執行方式

不需要 `npm install`，只用 Node.js 內建模組：

```bash
node app/tool/check_l10n_hardcoded_strings.js            # 三項檢查都做
# 測試／驗收時可指定其他目錄（只給其中一個旗標時只做對應那項檢查）：
node app/tool/check_l10n_hardcoded_strings.js --lib-dir <目錄>
node app/tool/check_l10n_hardcoded_strings.js --test-dir <目錄>
node app/tool/check_l10n_hardcoded_strings.js --integration-dir <目錄>
```

- 結束碼 `0`：乾淨，並印出實際掃描的檔案數（`PASS：掃描 N 個檔案…`、`PASS：掃描 N 個測試檔…`、`PASS：掃描 N 個 integration 測試檔…`）。
- 結束碼 `1`：至少一處違規，會印出 `lib/<檔案>:<行號>  <字串>`、`test/<檔案>:<行號>  缺少 locale…` 或 `integration_test/<檔案>:<行號>  缺少 locale…`。
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

## `check_loopback_reliability.js`

量測本機 loopback 連線可靠度。某些 Windows 機器的 `127.0.0.1` 上，帶 `Connection: close` 的 TCP 連線會被隨機重設
（`ECONNRESET` 或空回應），導致 `test/reader/local_book_server_test.dart` 隨機失敗（epic-66 Issue 11）。

### 何時該執行

`local_book_server_test.dart` 隨機出現 `Connection closed before full header was received`，或懷疑本機網路軟體干擾本機連線時。

### 執行方式

```bash
cd app
node tool/check_loopback_reliability.js              # 每列 100 次請求
node tool/check_loopback_reliability.js --count 50   # 指定次數
```

對 `127.0.0.1`、`127.0.0.2`、`::1`、第一個非內部的 IPv4 位址各啟動一個本機 HTTP 伺服器，每個位址跑兩種模式、每次新連線：
`close`（請求帶 `Connection: close`，由伺服器主動關閉）與 `keepalive`（請求帶 `Connection: keep-alive`，由客戶端關閉）。

結束碼：0 `127.0.0.1` 兩種模式都沒有失敗；1 `127.0.0.1` 有失敗。

### 怎麼看輸出

```text
127.0.0.1        close      ok=36  reset:ECONNRESET=14
127.0.0.1        keepalive  ok=50
127.0.0.2        close      ok=50
...
```

- 只有 `127.0.0.1` 的 `close` 列有失敗、其他列正常：本機有軟體干擾 `127.0.0.1` 上由伺服器主動關閉的連線。
  使用 keep-alive 的客戶端（例如瀏覽器）不一定受影響，是否影響 Windows 版開書要另外驗證。
- 每一列都有失敗：整個網路堆疊都不穩，先查網卡驅動與防火牆。
- 無法綁定（例如沒有 IPv6）只是該列略過，不算失敗。

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

## `build_release.js`

打包時自動配對簽章金鑰與 OAuth 設定檔，建置完再還原，不用手動 `cp`。

| 目標 | 金鑰（`android/key.properties` 來源） | OAuth（`config/cloud_oauth.json` 來源） | 指令 |
|---|---|---|---|
| `apk` | `key.properties.release` | `cloud_oauth.release.json` | `flutter build apk --release --split-per-abi`，再建一次 `flutter build apk --release`（共用版 `app-release.apk`） |
| `aab` | `key.properties.upload` | `cloud_oauth.release.json` | `flutter build appbundle --release` |
| `debug` | 不換 | `cloud_oauth.debug.json` | `flutter build apk --debug` |

```bash
cd app
node tool/build_release.js                 # 互動式選擇
node tool/build_release.js --target apk    # 直接指定
```

- 建置前先備份目前的 `key.properties` 與 `cloud_oauth.json`，結束後（成功、失敗、Ctrl+C）一律還原。
- 來源檔缺少時，在動任何檔案之前就中止。
- 結束碼 `0`：成功。`1`：取消。`2`：設定錯誤或建置失敗（檔案已還原）。
- 建完後印「打包資訊」：版本、**實際**簽章身分（`apksigner`／AAB 用 `keytool` 讀憑證，與該目標應有的身分比對）、OAuth Client ID 前綴、每個產物的大小與 SHA-256、下一步指令。簽章不符（例如 `apk` 目標卻簽成 debug 金鑰）以結束碼 `2` 結束，摘要仍會印出供檢查。
- 簽章身分判定邏輯在 `build_summary.js`（單元測試：`node tool/test_build_summary.mjs`）：憑證 DN 含 `CN=Android Debug` 為 debug 金鑰，其餘比對 `config/signing_fingerprints.json` 登錄的公開指紋；指紋留空時只警告「未登錄，無法驗證」，不當成失敗。
- `apksigner` 從 `android/local.properties` 的 `sdk.dir` 自動挑最新的 `build-tools`；找不到工具時標「簽章：未驗證」，不讓打包失敗。
- 它不做版本號、改檔名與 `SHA256SUMS.txt`；這些仍照 `docs/research/release_apk_sop.md`。
- 不經過這支腳本、直接 `flutter build apk --release` 且沒有 `key.properties` 時，Gradle 會直接失敗（避免打出 release＋debug 金鑰的組合）；只想自己量效能時設環境變數 `ORG_GRADLE_PROJECT_allowDebugSigning=true`。

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

## `foliate_legacy/`（舊版 WebView 降級工具）

把 `app/android/app/src/main/assets/foliate/` 的 JS 降級成 Chrome 83 看得懂的
語法，輸出到同目錄下的 `legacy/`。原始釘定檔案不動。

**背景**：iReader Ocean 4 Plus 的系統 WebView 是 Chrome 83，且廠商鎖死無法
升級。釘定的 foliate-js 使用私有方法（`#foo()`，Chrome 84 才支援），整份 JS
載入就失敗：開不了書、匯入沒有封面（封面與版面偵測用的探針是同一份 JS）。
`esCompatPolyfillJs` 只能補 API，補不了語法，所以另外產生降級副本。

**執行期怎麼選**：`foliate/index.html` 與 `android_epub_metadata.dart` 的
探針頁都看 `navigator.userAgent` 的 Chrome 主版號，低於 84 才載入
`legacy/`，其他裝置載入原始檔案，行為不變。

### 何時該執行

- **每次升級 `foliate/` 的釘定版本之後**，一定要重新產生。
- 修改 `foliate/` 下任何 `.js` 之後。
- 產生的 `legacy/` 要一併 commit（App 建置不需要 Node）。

### 執行方式

```powershell
$env:PATH = "$env:PNPM_HOME;$env:PATH"   # 見檔案開頭的 Node 說明
cd app\tool\foliate_legacy
pnpm install
pnpm build
```

- 用 esbuild，目標 `chrome83`。遇到無法降級的語法（例如頂層 `await`）會直接
  報錯，不會默默放過。
- `pnpm install` 可能提示 `Ignored build scripts: esbuild`，可忽略，不影響
  降級結果。
- 另外把 CSS 的 `:is(#header, #footer)`（Chrome 88+）改寫成等價選擇器。

### 已知限制

- 只處理語法，不處理執行期 API。缺少的 API 要補在 `esCompatPolyfillJs`，並
  用 `check_foliate_es_compat.js` 掃描（已納入 `replaceChildren`）。
- `paginator.js` 的 `@container` 與 CSS 巢狀寫法 Chrome 83 不支援，規則會被
  略過；目前實測直排與換字型正常，若之後發現欄數異常再回頭處理。
- 目前只在 Ocean 4 Plus（Chrome 83.0.4103.120）實測過。

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

## `test_column_pitch.mjs`

驗證 `column-pitch.js` 的欄間隔量測與補償純函式（`epic-54` Issue 34：舊 WebView 直排欄間隔與頁高不一致補償）。零 DOM 依賴，用 Node.js 內建 `node:assert/strict` 直接執行：`node app/tool/test_column_pitch.mjs`（結束碼 `0` 全數通過）。

## `detect_two_column_gap.py`

偵測直排頁面是否出現「上下兩欄錯位」的大高度水平空白帶（`epic-54` Issue 34 真機 WAVE 176 像素空帶驗證工具）。內容區（略過頂部 100、底部 60、左 80、右 40 像素）內整列無墨（灰階 `< 128` 像素數為 0）的連續空帶超過 80 像素時判為 `BUG`（結束碼 `1`），正常判為 `ok`（結束碼 `0`）。用法：`python app/tool/detect_two_column_gap.py <png>...`。 全黑、全白或載入中的截圖判為 `INVALID`（結束碼 `1`）。**只適用單欄**：雙欄、自動欄數模式的兩個欄之間有設計內的欄間空白（WAVE 約 150 像素），會被誤判為 `BUG`。

## `make_test_mdx.py`

產生自製的 MDX／MDD 測試檔（MDict 格式 v2.0），供 epic-63 的字典單元測試使用
（`app/test/fixtures/mdx/`）。

**背景**：MDX 是二進位格式，沒有現成的公開測試檔可以直接放進版控，真實字典又
有授權問題。這支腳本用 Python 標準函式庫直接組出必要的區塊結構（檔頭、鍵區塊、
記錄區塊），**完全自寫、未複製任何第三方程式碼**，產出的檔案只含假內容。

### 產生的檔案

| kind | 檔案 | 用途 |
|------|------|------|
| `zlib` | `zlib.mdx` | 一般字典：zlib 壓縮、`KeyCaseSensitive=No` |
| `mdd` | `mdd.mdd` | 最小 MDD（圖片與 CSS 各一筆） |
| `images` | `images.mdx` / `images.mdd` | 成對的 MDX（pic 詞條）與 MDD（PNG 與 MP3 資源） |
| `fake-lzo` | `fake-lzo.mdx` | 記錄區塊標成 LZO（不支援的壓縮） |
| `truncated` | `truncated.mdx` | 整檔砍半，模擬下載中斷 |
| `cut-records` | `cut-records.mdx` | 只砍記錄區塊，檔頭與鍵區完整 |
| `html` | `html.mdx` | 詞條含 `entry://`、`bword://`、`#x`、`sound://`、`http://` 與 `<link href="ghychyz.css">`，標頭有 `StyleSheet` |
| `strip-key` | `strip-key.mdx` | `StripKey=Yes`，鍵含「一」等 CJK 字 |
| `case-sensitive` | `case-sensitive.mdx` | `KeyCaseSensitive=Yes`，只收小寫鍵 `apple` |
| `placeholder-title` | `placeholder-title.mdx` | `Title` 是預設佔位字串、`Description` 有內容 |
| `placeholder-title-empty` | `placeholder-title-empty.mdx` | 同上但 `Description` 為空（名稱應退回檔名） |
| `v1` | `v1.mdx` | MDict 1.2 版格式（4 位元組數字、鍵區標頭無 checksum、鍵區塊資訊不壓縮），測 `validateBlocks` 的 v1 路徑 |
| `strip-phrases` | `strip-phrases.mdx` | `StripKey=Yes`，鍵含空白與連字號的英文片語，檔內依「去空白標點、轉小寫」排序 |
| `multi-block` | `multi-block.mdx` | 區塊上限 512 位元組、約 300 筆、含跨區塊重複鍵（`dupkey` 60 筆），測跨塊路徑 |
| `encrypted-yes` | `encrypted-yes.mdx` | 標頭 `Encrypted="Yes"`（舊格式的記錄區塊加密） |
| `large` / `large-cjk` | （不進版控） | 合成大檔，供記憶體補測 |

### 執行方式

```bash
cd app

# 一般 fixture（輸出到 test/fixtures/mdx/）
python -X utf8 tool/make_test_mdx.py html test/fixtures/mdx/html.mdx
python -X utf8 tool/make_test_mdx.py mdd test/fixtures/mdx/mdd.mdd
python -X utf8 tool/make_test_mdx.py images test/fixtures/mdx/images.mdx

# 合成大檔（只放本機，例如 tmp/，不要加進版控）
python -X utf8 tool/make_test_mdx.py large-cjk tmp/large_cjk.mdx --entries 400000
```

改動格式細節（例如新增一種損壞情境）時，改這支腳本後**重新產生全部 fixture**，
不要手改二進位檔。

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

## `run_windows_smoke.ps1`

Windows 整合測試冒煙套件跑測腳本（`epic-66-windows-port` Issue 13）。

### 背景與設計
Windows 整合測試會啟動真實的 Windows 視窗與 WebView2 執行階段。為防止 2026-11-09 因多個測試並行導致記憶體耗盡遭系統終止的事故，本腳本實作四項硬性防護：
1. **單份互斥鎖**：透過 .NET 檔案獨佔鎖（`build/windows_smoke/.lock`），拒絕多個實例同時並行。
2. **開跑前殘留防護**：檢查系統中是否有殘留的 `elinkbook.exe`、`flutter_tester.exe`、`MSBuild.exe` 或 `dart`，若有則中止並列出，不擅自終止。
3. **記憶體熔斷**：執行每支測試前檢查可用實體記憶體，若低於門檻（預設 4096 MB）則等待 10 秒緩衝，仍不足即中止後續測試。
4. **行程樹逾時強制終止**：測試逾時（預設 420 秒）時調用 `taskkill /PID <PID> /T /F` 徹底清除子進程樹，並在每支測試結束後確認 `elinkbook.exe` 徹底退出。

### 執行方式

```powershell
cd app

# 依預設套件清單 (integration_test/windows_smoke_suite.txt) 依序跑測
powershell -ExecutionPolicy Bypass -File tool/run_windows_smoke.ps1

# 自訂參數
powershell -ExecutionPolicy Bypass -File tool/run_windows_smoke.ps1 -Suite integration_test/windows_smoke_suite.txt -TimeoutSec 300 -MinFreeMB 4096
```

結束碼：0 全數通過；非 0 代表有失敗、逾時或中斷。詳細日誌保存在 `build/windows_smoke/<測試名稱>.log`。

## `package_windows_zip.ps1`

Windows 免安裝 zip 打包腳本（`epic-66-windows-port` Issue 14）。

### 背景與設計
將 Windows Release 版打成免安裝 zip，解壓到任何位置雙擊 `elinkbook.exe` 即可使用：
1. **重新建置**：在 `app/` 執行 `flutter build windows --release`（支援 `-SkipBuild` 沿用現有 Release 輸出）。
2. **暫存組裝**：將 `build/windows/x64/runner/Release` 組裝至 `build/windows_zip/stage/elinkbook/`，排除 `.pdb`、`.lib`、`.exp`、`.ilk` 等除錯與建置暫存檔。
3. **隨附 VC 執行階段**：自動以 `vswhere` 定位 Visual Studio 安裝路徑，由 `Microsoft.VCRedistVersion.default.txt` 取得版本，複製 `msvcp140.dll`、`vcruntime140.dll`、`vcruntime140_1.dll` 到程式根目錄（app-local 部署）。
4. **README 範本**：自動隨附 `app/windows/packaging/README.txt`。
5. **bsdtar 壓縮與路徑防護**：使用 Windows 內建 `tar.exe` 壓縮，確保 zip 內部路徑分隔符皆為正斜線 `/`（避開 PowerShell 5.1 `Compress-Archive` 反斜線缺陷）。
6. **清單驗證與安全寫入**：先壓至 `.tmp.zip`，驗證清單必備檔案存在、不含反斜線且不含 `.pdb`，全部通過後才更名為正式 zip，並以純檔名基底寫出同名 `.sha256`。

### 執行方式

```powershell
cd app

# 完整流程：重新建置並打包
powershell -ExecutionPolicy Bypass -File tool/package_windows_zip.ps1

# 沿用現有 Release 建置（跳過建置步驟）
powershell -ExecutionPolicy Bypass -File tool/package_windows_zip.ps1 -SkipBuild

# 自訂輸出目錄
powershell -ExecutionPolicy Bypass -File tool/package_windows_zip.ps1 -SkipBuild -OutDir C:\path\to\output
```

結束碼：0 成功；非 0 代表建置失敗、缺少檔案或清單驗證不符。

補充：
- 每次執行開頭會先刪除輸出目錄中同名的舊正式 zip、`.sha256` 與暫存 zip，所以任何一步失敗都不會留下看似成功的舊產物。
- 暫存目錄不得含內建字型：依賴檢查（含 `-CheckOnly`）會在 `data\flutter_assets\assets\` 下發現字型檔就失敗。成因是 `build\flutter_assets` 會殘留已從 `pubspec.yaml` 移除的舊資源（Flutter 不會刪，CMake 安裝步驟卻整個目錄複製）；完整建置前腳本會先清掉該目錄，由 Flutter 依目前的 `pubspec.yaml` 重新產生。使用 `-SkipBuild` 沿用舊輸出而被擋下來時，手動刪除 `app\build\flutter_assets` 後重新建置。
- 暫存目錄不得含測試用資源：`pubspec.yaml` 為了整合測試把 `test/fixtures/` 宣告成 asset，會被整個帶進 `data\flutter_assets\test`（約 36 MB，其中 `sample.ttf` 就占 35 MB）；`lib/` 沒有任何地方在執行期讀它。組裝暫存目錄時腳本會移除該資料夾，依賴檢查（含 `-CheckOnly`）發現它存在就失敗。
- 暫存組裝時排除 `dartjni.dll`（`jni` 為 `path_provider_android` 的遞移相依，`lib/` 沒有任何引用，且該 DLL 依賴不存在的 `jvm.dll`）；理由與限制見 `docs/epics/epic-66-windows-port/epic.md` 決策 30。

### 單獨做依賴靜態檢查：`-CheckOnly`

```powershell
# 檢查任一目錄（例如暫存目錄 build/windows_zip/stage/elinkbook）
powershell -ExecutionPolicy Bypass -File tool/package_windows_zip.ps1 -CheckOnly build/windows_zip/stage/elinkbook
```

以 `dumpbin /dependents` 檢查目錄內每個 `.exe`／`.dll`：`msvcp140.dll`、`vcruntime140.dll`、`vcruntime140_1.dll` 必須實體存在於目錄根（即使 System32 有也不算）；其他非系統依賴必須在目錄內。結束碼 0 通過、1 失敗並列出「檔案 → 缺少的依賴」。這只證明「檔案依賴齊全」，不證明乾淨機器能開。

## `verify_windows_zip.ps1`

Windows 免安裝 zip 的本機驗證腳本（`epic-66-windows-port` Issue 14）。

```powershell
cd app
powershell -ExecutionPolicy Bypass -File tool/verify_windows_zip.ps1 -Zip build/windows_zip/elinkbook-<版本>-windows-x64.zip

# 可選：-WorkDir 指定解壓位置（預設 $env:TEMP）、-KeepAppData 保留測試產生的使用者資料夾
```

流程：解壓到 `<WorkDir>\含 空格 與 中文\`、以 `icacls` 對目前使用者 SID 拒絕寫入／建立子資料夾／刪除子項、用 `Start-Process -WorkingDirectory` 啟動、輪詢等主視窗、再確認行程存活 20 秒、確認使用者資料夾 `%APPDATA%\cc.ugotit\elinkbook` 有當次啟動的寫入、結束行程樹並確認 `msedgewebview2.exe` 子行程消失、移除 deny ACL、比對解壓資料夾執行前後的檔案與資料夾清單必須完全相同。每項輸出一行 `[通過]／[失敗] 名稱 :: 說明`，結束碼 0 全數通過。

注意：
- 會實際啟動 `elinkbook.exe`；開跑前會檢查殘留行程與可用記憶體（只檢查不終止）。執行期間不要同時跑 Windows 整合測試或建置。
- `-WorkDir\含 空格 與 中文` 若已存在且含非本腳本產生的內容，腳本拒絕刪除並以非 0 結束。
- 本機驗證**抓不到缺 VC 執行階段 DLL 的問題**（這台機器的 System32 有這些 DLL），那一關由 `package_windows_zip.ps1 -CheckOnly` 負責；兩者都不證明乾淨機器、Windows 10 1809 能開。

## `package_windows_installer.ps1`

Windows 安裝程式（Inno Setup）打包腳本（`epic-66-windows-port` Issue 27，決策見 [ADR 0043](../../docs/adr/0043-windows-installer-inno-setup-unsigned-per-user.md)）。

需要先安裝 Inno Setup 6：`winget install --id JRSoftware.InnoSetup -e`（腳本會找 `%LOCALAPPDATA%\Programs\Inno Setup 6`、`Program Files` 與 `PATH`）。

```powershell
cd app
# 完整流程：呼叫 package_windows_zip.ps1 重新建置並組裝暫存目錄，再編譯安裝程式
powershell -ExecutionPolicy Bypass -File tool/package_windows_installer.ps1

# 沿用現有 Release 建置
powershell -ExecutionPolicy Bypass -File tool/package_windows_installer.ps1 -SkipBuild

# 直接指定暫存目錄（不呼叫 zip 腳本；供變異驗證與除錯）、指定版本（格式同 pubspec 的 version:）
powershell -ExecutionPolicy Bypass -File tool/package_windows_installer.ps1 -StageDir <目錄> -Version 1.0.9+1 -OutDir <輸出目錄>
```

輸出 `build/windows_installer/elinkbook-<版本把 + 換成 -b>-windows-x64-setup.exe` 與 `<同檔名>.sha256`（格式同 zip 的 `.sha256`）。結束碼 0 成功；找不到 Inno Setup、依賴複檢失敗、編譯失敗都以非 0 結束，且開頭會先清掉同名舊產物，不會留下看似成功的舊檔。

設計重點：
- 安裝程式腳本是 `windows/packaging/elinkbook.iss`；介面語言用同目錄的 `ChineseTraditional.isl`（取自 Inno Setup 官方儲存庫 main，Inno Setup 6.7.3 的安裝目錄沒有附，內容未修改，授權為 Inno Setup License）。
- 內容與 zip 版同源：直接使用 zip 腳本組好的暫存目錄 `build/windows_zip/stage/elinkbook`，並永遠先對它跑 `package_windows_zip.ps1 -CheckOnly`（三個 VC DLL 必須實體存在），腳本會印出所用暫存目錄與 `elinkbook.exe` 的檔案版本，避免誤用過期的暫存目錄。
- 固定 `AppId`（見 `.iss` 註解）發佈後不可更改；`AppIdOverride` 只給變異驗證用。
- 不簽章、不上傳、不建 CI。

## `verify_windows_installer.ps1`

Windows 安裝程式的本機驗證腳本（`epic-66-windows-port` Issue 27）。

```powershell
cd app
powershell -ExecutionPolicy Bypass -File tool/verify_windows_installer.ps1 `
  -Setup build/windows_installer/elinkbook-<版本>-windows-x64-setup.exe `
  -OlderSetup <較舊版本的 setup.exe>
# 可選：-WorkDir（預設 $env:TEMP）、-ExpectedStageDir（預設 build/windows_zip/stage/elinkbook）
```

**會實際啟動 `elinkbook.exe`，寫入這台機器上真實的 `%APPDATA%\cc.ugotit\elinkbook`。執行前先備份該資料夾**（`robocopy <來源> <備份> /MIR`，結束碼 0～7 皆為成功）。腳本任何一步都不會刪除該資料夾。需用一般權限（非系統管理員）的終端機執行，否則無法驗證「不需要管理員」。

流程與檢查項（每項輸出一行 `[通過]／[失敗] 名稱 :: 說明`，結束碼 0＝全部通過，目前共 29 項）：
1. 靜默安裝到 `<WorkDir>\含 空格 與 中文 installer-verify\app`：不需管理員、HKCU 有 `{GUID}_is1` 登錄項（單花括號，驗證 `.iss` 的花括號跳脫）、HKLM 沒有。預期 AppId 在腳本內獨立釘住，`.iss` 被改動時腳本開頭就失敗。
2. 安裝內容：必備檔齊全（含三個 VC DLL、`data\foliate\main.js`）、沒有 `.pdb`／`.lib`／`.exp`／`.ilk`、沒有打包字型與 `data\flutter_assets\test`，且與暫存目錄逐檔（路徑加 SHA256）一致，只允許多出解除安裝程式自己的檔案。
3. 開始功能表項目、桌面捷徑（預設存在）指向安裝的 `elinkbook.exe`。
4. 啟動出現主視窗、行程存活 20 秒。
5. 覆蓋升級：先裝舊版並保持執行，再靜默安裝新版——舊行程被關閉、全機只有一個 elinkBook 解除安裝項與一個 `unins*.exe`、版本更新、`elinkbook.exe` 與 `README.txt` 已被新版取代。
6. 資料保護：升級前後、兩次靜默解除安裝前後，`%APPDATA%\cc.ugotit\elinkbook` 內「原本存在的檔案」不得消失（WebView2 的 `lockfile` 只在 App 執行期間存在，不納入比對）。書庫在「文件」資料夾，安裝程式不會動它，不在比對範圍。
7. 靜默解除安裝：Inno 的解除安裝程式會複製自己到 `%TEMP%` 再啟動並讓原行程結束，所以腳本以輪詢（每 0.5 秒、最長 30 秒）等程式檔、登錄項與解除安裝行程本身都結束，不能只等行程結束；刻意不帶 `/SUPPRESSMSGBOXES`，讓 `.iss` 的 `UninstallSilent` 判斷成為唯一擋住詢問框的防線，防線失效時詢問框卡住、輪詢逾時就會失敗。
8. `/TASKS="!desktopicon"`：桌面捷徑不存在、開始功能表存在。
9. 結束時沒有殘留行程與安裝。
10. App 執行中解除安裝必須被拒絕（程式檔與登錄項仍在）。

開跑前會拒絕：這台機器已有任何 elinkBook 解除安裝項、或已存在同名的開始功能表／桌面捷徑（驗證會覆寫並刪除它們）。

**產生「較舊版本」setup.exe 的做法**：複製暫存目錄、改掉 `README.txt` 內容並在 `elinkbook.exe` 尾端加一個 0x00 位元組（讓新舊內容有差別，才能證明被取代），再用 `package_windows_installer.ps1 -StageDir <複本> -Version 1.0.9+1 -OutDir <輸出目錄>` 編譯。

**驗證檢查本身有效（負向驗證）**：`-DataDir <假資料夾> -SimulateDataLoss` 會在比對前人為刪掉假資料夾內一個檔案，預期 6a 失敗、其餘通過。這兩個參數只給這種用途，不要對真實資料夾使用 `-SimulateDataLoss`（會刪檔）。

這只證明「這台機器上安裝、升級、解除安裝的行為」；乾淨機器（缺 VC 執行階段與 WebView2）、Windows 10 1809、SmartScreen 實際行為皆**未驗證**。

## `verify_windows_uninstall_data.ps1`

驗證安裝程式「解除安裝是否刪除資料」的本機腳本（`epic-66-windows-port` Issue 27）。

```powershell
cd app
powershell -ExecutionPolicy Bypass -File tool/verify_windows_uninstall_data.ps1
# 可選：-StageDir（預設 build/windows_zip/stage/elinkbook）、-WorkDir（預設 $env:TEMP）
```

**不會碰真實的 `%APPDATA%` 與「文件」資料夾。** 腳本用 `elinkbook.iss` 的 `AppDataRootOverride`、`DocsRootOverride` 兩個 `/D` 定義編一個測試用安裝程式，把兩個資料根目錄指到 `<WorkDir>\含 空格 與 中文 uninstall-data-verify\` 下的假資料夾；出貨版不帶這兩個定義，使用真實路徑。

流程（共 10 項檢查，每項輸出一行 `[通過]／[失敗] 名稱 :: 說明`，結束碼 0＝全部通過）：
1. 安裝測試用安裝程式，在假資料夾的 `fake-docs\elinkbook-data\` 下放入 App 會建立的項目（`library.db`、`dictionary.db` 各含 `-wal`／`-shm`／`-journal`、`covers`、`imported_books`、`cloud_import_books`、`remote_books`、`wifi_transfer_uploads`、`update_staging`）及假的 `%APPDATA%\cc.ugotit\elinkbook` 資料夾；並在假「文件」**根目錄**放入模擬舊版遺留與使用者同名資料的「誘餌」（`covers\a.bin`、`imported_books\b.bin`、`library.db`、`dictionary.db`、`六祖壇經\x.txt`、`desktop.ini`、`my-library.db`、`library.db.bak`、`covers-backup\a.jpg`、`notes.txt`、`Zoom\z.txt`，以及 `cc.ugotit\other\keep.txt`）。
2. 以 UI Automation 對解除安裝程式的訊息框逐一回應（「確定要移除」按「是」、我們的資料詢問框按指定的答案、結尾訊息按「確定」）。
3. **情境一（選「否」）**：確認詢問框出現、「否」鈕取得鍵盤焦點（預設按鈕為「否」）、程式已移除，且所有資料與誘餌原封不動。
4. **情境二（選「是」）**：`fake-docs\elinkbook-data` 與假 `%APPDATA%\cc.ugotit\elinkbook` 兩個資料夾全數消失，根目錄的舊項目誘餌與其他檔案原封不動。

這只驗證「解除安裝刪除範圍與預設按鈕」；出貨版的真實路徑（`{userdocs}`、`{userappdata}`）沒有實跑。

## `generate_windows_icons.ps1`

由 `assets/appicon_v2.jpg` 產生 Windows 版圖示與啟動小視窗圖（`epic-66-windows-port`），只用 .NET `System.Drawing`，不需安裝其他工具。

```powershell
cd app
powershell -ExecutionPolicy Bypass -File tool/generate_windows_icons.ps1
```

輸出（直接覆寫，需一併提交）：
- `windows/runner/resources/app_icon.ico`：16／24／32／48／64／128 為 DIB 項、256 為 PNG 項；由 `Runner.rc` 內嵌，用於 exe、檔案總管、工作列、視窗標題列。
- `windows/runner/resources/splash.bmp`：400x400 的 24 位元 BMP；由 `Runner.rc` 以 `IDB_SPLASH` 內嵌，供 `windows/runner/splash_window.cpp` 的啟動小視窗使用。

換圖後要重新建置（`flutter build windows --release`）；本次實測增量建置會重新連結新圖示，若日後發現 exe 沒更新，再改為刪除 `build/windows/x64/runner` 後重建。

**啟動小視窗（`splash_window.cpp`）**：`wWinMain` 一開始就顯示（類別 `ELINKBOOK_SPLASH`、約 80～200 ms 內出現），Flutter 第一個畫面出現時（`FlutterWindow` 的 `SetNextFrameCallback`）關閉；另有 30 秒保險計時器。`verify_windows_zip.ps1` 以視窗類別區分小視窗（`ELINKBOOK_SPLASH`）與主視窗（`FLUTTER_RUNNER_WIN32_WINDOW`），不再使用 `MainWindowHandle`（它會先回傳小視窗，讓「主視窗偵測」失去意義）。

## `generate_android_splash.ps1`

由 `assets/appicon_v2.jpg` 產生 Android 啟動畫面圖 `android/app/src/main/res/drawable-xxxhdpi/splash_icon.png`（1152x1152，即 288dp @ 4x），並印出建議底色（目前 `#F9F9F4`，寫在 `res/values/colors.xml`）。只用 .NET `System.Drawing`。

```powershell
cd app
powershell -ExecutionPolicy Bypass -File tool/generate_android_splash.ps1
```

背景：Android 12+ 的系統 SplashScreen 若沒指定專用圖示，只會拿舊式 `ic_launcher` 縮進圓形範圍，圖示很小（模擬器量測約佔螢幕寬度 19%）。現在 `values-v31`／`values-night-v31` 的 `LaunchTheme` 指定 `windowSplashScreenAnimatedIcon`／`windowSplashScreenBackground`；系統對沒有 icon background 的圖示只顯示 288dp 畫布中央直徑 192dp 的圓，所以腳本把插畫縮放到剛好放進這個圓（約 45%，已接近上限 47%）。`values-night-v31` 另設淺色狀態列／導覽列，否則深色模式白字疊在紙張底色上看不見。Android 11 以下改由 `drawable/launch_background.xml` 置中顯示同一張圖（未實測）。

換圖或調整版面後要重新建置並在 Android 12+ 裝置或模擬器實測；這台 BooksPad（Android 12）的 ROM 不顯示系統啟動畫面，不能用來驗證。

