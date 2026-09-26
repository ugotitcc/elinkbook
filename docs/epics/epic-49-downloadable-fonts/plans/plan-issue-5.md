# Issue 5：真機驗證 實作計畫（驗證手冊）

> **給執行者：** 這份計畫以人類操作為主。Task 1、Task 4 可以交給 agent（superpowers:executing-plans）；Task 2、Task 3 必須由人類在真機上操作。步驟使用核取方塊（`- [ ]`），完成一個就改成 `- [x]`。

**目標：** 在一般 Android 手機與電子紙閱讀器上，確認 epic-49 的可下載字型從「下載 → 閱讀器套用 → 刪除 → 退回書本字型」整條路徑在真機上正確，9 項驗收全部通過並記錄到 `epic.md`。

**架構：** 不改任何程式。準備兩種 APK 與一本專用的驗證書，依裝置分兩輪操作，最後把結果寫回文件。

```
Task 1 準備（agent）
  ├─ debug APK   ── 可用 chrome://inspect 連上 WebView（第 3、4、5、8、9 項）
  ├─ release APK ── 效能接近正式版（第 2 項電子紙閃爍、第 6 項翻頁）
  └─ 驗證書 epic-49-font-check.epub ── 書本 CSS 有宣告字型（第 9 項），第 2 章是長篇翻頁測試（第 6 項）
        │
        v
Task 2 一般手機（人類）：第 1、2、3、4、5、6、7、9 項
Task 3 電子紙閱讀器（人類）：第 2 項（閃爍）、第 6 項、第 8 項
        │
        v
Task 4 記錄結果、更新進度、發 PR（agent，依人類回報的結果）
```

**技術：** Flutter 建置（`flutter build apk`）、`adb`、桌面版 Chrome 的 `chrome://inspect`、7-Zip（產生驗證書）。

**規格：** `docs/epics/epic-49-downloadable-fonts/issues.md` Issue 5（9 項）、`spec.md`、`docs/adr/0035-downloadable-fonts-via-r2-worker.md`。第 8 項來自 `reviews/review-issue-4.md` M-2，第 9 項來自 `reviews/review-issue-6.md` M-2。

**分支：** 從最新的 `main` 建立 `epic-49/issue-5-device-qa`（只會提交文件）。

## 全域限制

- **不修改任何程式**。驗證中發現問題時，照實記錄並停在該項，由人類決定是否另開工單；不可以邊驗證邊修。
- 套件名稱：`cc.ugotit.elinkbook`。debug 與 release 都用 debug key 簽章（`app/android/app/build.gradle.kts` 的 `signingConfig = signingConfigs.getByName("debug")`），所以兩者可以用 `adb install -r` 互相覆蓋，**App 資料（書庫、已下載字型）會保留**。
- **不要 `adb uninstall`**，那會清掉裝置上的書庫。需要「字型未下載」的起點時，改在字型管理畫面把字型刪掉。
- 只有 **debug APK** 能用 `chrome://inspect` 連上 WebView（Android 對 debuggable App 會自動開啟 WebView 遠端除錯；本專案沒有另外呼叫 `setWebContentsDebuggingEnabled`）。release APK 連不上是正常的。
- 已下載字型的存放位置：`files/downloaded-fonts/v1/`（`getApplicationSupportDirectory()` 下的 `downloaded-fonts`）。只有 debug APK 可以用 `adb shell run-as cc.ugotit.elinkbook ls -la files/downloaded-fonts/v1` 查看。
- 字型大小（字型管理畫面應顯示的值，以 1024×1024 為 1 MB）：思源黑體 36,034,016 bytes → **34.4 MB**；思源宋體 59,898,316 bytes → **57.1 MB**。
- 字型家族名稱：思源黑體 `SourceHanSansTC`、思源宋體 `SourceHanSerifTC`。
- 下載服務：`https://elinkbook-fonts.huthief.workers.dev/v1/<檔名>`。下載閒置逾時 30 秒（兩個資料區塊之間超過 30 秒沒有資料就判定網路失敗），不是整個下載的時間上限。
- 所有 `adb` 指令在 Git Bash 執行；裝置不只一台時，每條指令都加 `-s <裝置序號>`（序號用 `adb devices` 查）。
- `adb` 不在 Git Bash 的 PATH 時（出現 `command not found`），先執行一次：`export PATH="$PATH:$(cygpath "$LOCALAPPDATA")/Android/Sdk/platform-tools"`。
- **Git Bash 會把 `/` 開頭的參數改寫成 Windows 路徑**（例如 `/sdcard/Download/` 變成 `C:/Program Files/Git/sdcard/Download/`）。所以裝置端路徑一律這樣寫（計畫審查 I-1）：
  - `adb push` 的目的地寫成 `//sdcard/Download/`（雙斜線不會被改寫，裝置端會視為 `/sdcard/Download/`）；來源的 `~/...` 照常寫，讓 Git Bash 轉成 Windows 路徑。
  - `adb shell` 後面帶裝置端絕對路徑時，整條指令前面加 `MSYS_NO_PATHCONV=1`（這類指令不含本機路徑，關掉改寫不會有副作用）。

## 審查重點（Review Focus）

這份計畫沒有自動化測試，以下是真機驗證時最容易誤判的五種情況，對應的檢查已寫進負責的步驟：

1. **DevTools 看到的是外層頁面，不是書本內容**：foliate-js 把章節放在 `<iframe>` 裡，直接在外層選元素，看到的字型和書本無關。→ Task 2 Step 5 明確要求展開 iframe 的 `#document` 再選 `<p>`。
2. **Network 面板看不到字型請求**：字型在接上 DevTools 之前就已經載入完了。→ Task 3 Step 4 規定先接上 DevTools，再到閱讀設定選字型，讓請求在觀察期間發生。
3. **以為是「未下載」，其實裝置上已經有字型檔**：之前測試留下的檔案會讓第 1 項誤判。→ Task 2 Step 2 先用 `run-as` 列出存放目錄，確認是空的。
4. **把 debug 版的卡頓誤判成字型問題**：debug APK 本來就比較慢。→ 第 2 項電子紙閃爍與第 6 項翻頁一律用 release APK（Task 2 Step 11、Task 3 Step 2）。
5. **裝置 WebView 連不上 DevTools**（即使是 debug APK）：部分電子紙裝置的系統 WebView 有限制。→ Task 3 Step 4 提供退路：改用肉眼比對截圖，並在結果註明「無法連上 DevTools」。

---

## 檔案結構

| 檔案 | 動作 | 責任 |
|---|---|---|
| `~/elinkbook-qa/epic-49-font-check/`（不進版控） | 建立 | 驗證書的原始檔 |
| `~/elinkbook-qa/epic-49-font-check.epub`（不進版控） | 建立 | 第 6、9 項用的驗證書 |
| `docs/epics/epic-49-downloadable-fonts/epic.md` | 修改 | 驗證結果記錄（Task 4） |
| `docs/epics/epic-49-downloadable-fonts/issues.md` | 修改 | Issue 5 狀態（Task 4） |
| `docs/epics.md` | 修改 | epic-49 備註（Task 4） |
| `docs/epics/epic-49-downloadable-fonts/plans/plan-issue-5.md` | 修改 | 勾選步驟 |

---

### Task 1：準備 APK 與驗證書（agent 可執行）

**Files:**
- Create: `~/elinkbook-qa/epic-49-font-check/` 下的 7 個檔案（`mimetype`、`META-INF/container.xml`、`OEBPS/` 下 5 個）、`~/elinkbook-qa/epic-49-font-check.epub`

**Interfaces:**
- Produces：`app/build/app/outputs/flutter-apk/app-debug.apk`、`app/build/app/outputs/flutter-apk/app-release.apk`、`~/elinkbook-qa/epic-49-font-check.epub`，Task 2、3 使用。

- [x] **Step 1：建立分支並建置兩種 APK**

在 repo 根目錄：
```bash
git switch main && git pull --ff-only origin main
git switch -c epic-49/issue-5-device-qa
cd app
flutter build apk --debug
flutter build apk --release
ls -la build/app/outputs/flutter-apk/app-debug.apk build/app/outputs/flutter-apk/app-release.apk
```
預期：兩個 APK 都存在。不需要帶 `--dart-define-from-file=config/cloud_oauth.json`（本 Issue 不測雲端登入）。

- [x] **Step 2：寫驗證書的原始檔**

這本書的用途：書本 CSS 讓中文段落用 `serif`、英文段落用 `monospace`。在 DevTools 的 Rendered Fonts 裡，三種狀態看得出差別：

| 狀態 | 英文等寬段落的 Rendered Fonts |
|---|---|
| 使用書本字型（正確） | 等寬字型，例如 `Cutive Mono`、`Droid Sans Mono` |
| 選了思源宋體 | `SourceHanSerifTC` |
| 系統預設字型蓋掉書本字型（Issue 6 修掉的錯誤） | 一般無襯線字型，例如 `Roboto` |

```bash
Q=~/elinkbook-qa/epic-49-font-check
mkdir -p "$Q/META-INF" "$Q/OEBPS"
printf 'application/epub+zip' > "$Q/mimetype"

cat > "$Q/META-INF/container.xml" <<'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<container version="1.0" xmlns="urn:oasis:names:tc:opendocument:xmlns:container">
  <rootfiles>
    <rootfile full-path="OEBPS/content.opf" media-type="application/oebps-package+xml"/>
  </rootfiles>
</container>
EOF

cat > "$Q/OEBPS/content.opf" <<'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<package xmlns="http://www.idpf.org/2007/opf" version="3.0" unique-identifier="bookid" xml:lang="zh-Hant">
  <metadata xmlns:dc="http://purl.org/dc/elements/1.1/">
    <dc:identifier id="bookid">urn:uuid:5e6f4a49-0e49-4c49-9a49-e49f0f0c4ec9</dc:identifier>
    <dc:title>epic-49 字型驗證書</dc:title>
    <dc:language>zh-Hant</dc:language>
    <meta property="dcterms:modified">2026-09-26T00:00:00Z</meta>
  </metadata>
  <manifest>
    <item id="nav" href="nav.xhtml" media-type="application/xhtml+xml" properties="nav"/>
    <item id="ch1" href="chapter1.xhtml" media-type="application/xhtml+xml"/>
    <item id="ch2" href="chapter2.xhtml" media-type="application/xhtml+xml"/>
    <item id="css" href="style.css" media-type="text/css"/>
  </manifest>
  <spine>
    <itemref idref="ch1"/>
    <itemref idref="ch2"/>
  </spine>
</package>
EOF

cat > "$Q/OEBPS/nav.xhtml" <<'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<html xmlns="http://www.w3.org/1999/xhtml" xmlns:epub="http://www.idpf.org/2007/ops" xml:lang="zh-Hant">
<head><title>目錄</title></head>
<body>
  <nav epub:type="toc"><ol><li><a href="chapter1.xhtml">字型驗證</a></li><li><a href="chapter2.xhtml">翻頁測試</a></li></ol></nav>
</body>
</html>
EOF

cat > "$Q/OEBPS/style.css" <<'EOF'
body { font-family: serif; }
p.mono { font-family: monospace; }
EOF

cat > "$Q/OEBPS/chapter1.xhtml" <<'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<html xmlns="http://www.w3.org/1999/xhtml" xml:lang="zh-Hant">
<head><title>字型驗證</title><link rel="stylesheet" type="text/css" href="style.css"/></head>
<body>
  <h1>字型驗證</h1>
  <p>這一段是中文內文，書本 CSS 宣告為 serif。選擇思源宋體時應顯示為思源宋體；改回「使用書本字型」後應回到裝置的襯線字型。</p>
  <p class="mono">The quick brown fox jumps over the lazy dog. 0123456789 — this paragraph is declared as monospace by the book CSS.</p>
  <p>第三段：旋轉螢幕、翻頁後再檢查一次，字型不應改變。</p>
</body>
</html>
EOF

# 第 2 章：翻頁測試用的長章節（計畫審查 I-2）。80 段、每段約 440 字，
# 共約 3.5 萬字，手機與電子紙都遠超過 30 頁。
S='翻頁測試的內文，用來觀察連續翻頁時字型是否穩定、有沒有因為字型載入而卡頓或多出一次刷新。'
{
  printf '%s\n' '<?xml version="1.0" encoding="UTF-8"?>'
  printf '%s\n' '<html xmlns="http://www.w3.org/1999/xhtml" xml:lang="zh-Hant">'
  printf '%s\n' '<head><title>翻頁測試</title><link rel="stylesheet" type="text/css" href="style.css"/></head>'
  printf '%s\n' '<body>' '  <h1>翻頁測試</h1>'
  for i in $(seq 1 80); do
    printf '  <p>第 %d 段。%s%s%s%s%s%s%s%s%s%s</p>\n' "$i" "$S" "$S" "$S" "$S" "$S" "$S" "$S" "$S" "$S" "$S"
  done
  printf '%s\n' '</body>' '</html>'
} > "$Q/OEBPS/chapter2.xhtml"
grep -c '<p>' "$Q/OEBPS/chapter2.xhtml"
ls -R "$Q"
```
預期：`grep -c` 輸出 `80`；列出 `mimetype`、`META-INF/container.xml`、`OEBPS/` 下 5 個檔案（`content.opf`、`nav.xhtml`、`style.css`、`chapter1.xhtml`、`chapter2.xhtml`）。

- [x] **Step 3：打包成 EPUB**

EPUB 規定 `mimetype` 必須是壓縮檔的第一個項目而且不壓縮，所以分兩次加入：
```bash
Q=~/elinkbook-qa/epic-49-font-check
OUT=~/elinkbook-qa/epic-49-font-check.epub
rm -f "$OUT"
cd "$Q"
"/c/Program Files/7-Zip/7z.exe" a -tzip -mx0 "$OUT" mimetype
"/c/Program Files/7-Zip/7z.exe" a -tzip -mx9 "$OUT" META-INF OEBPS
"/c/Program Files/7-Zip/7z.exe" l "$OUT"
```
預期：清單第一個項目是 `mimetype`，其後是 `META-INF/container.xml` 與 `OEBPS/` 下 5 個檔案。

最後回到 repo 根目錄，後面的 Task 都假設從那裡執行（計畫審查 M-1）：
```bash
cd /c/Users/fycdc/AI/elinkBook
```

- [x] **Step 4：告訴人類準備好了**

回報三個檔案的完整路徑（兩個 APK、一本 EPUB），並提醒人類：Task 2 需要一台一般 Android 手機、Task 3 需要一台電子紙閱讀器，兩台都要開啟「開發人員選項 → USB 偵錯」，電腦要裝桌面版 Chrome。

---

### Task 2：一般 Android 手機（人類操作）

**Interfaces:**
- Consumes：Task 1 的 `app-debug.apk`、`app-release.apk`、`epic-49-font-check.epub`。
- Produces：第 1、2、3、4、5、6、7、9 項的結果（通過／失敗＋觀察到的現象），交給 Task 4。

以下指令在 repo 根目錄的 Git Bash 執行，`<id>` 換成 `adb devices` 顯示的手機序號。

- [x] **Step 1：記錄裝置資訊並安裝 debug APK**

```bash
adb devices
adb -s <id> shell getprop ro.product.model
adb -s <id> shell getprop ro.build.version.release
adb -s <id> shell dumpsys webviewupdate | grep -i "current webview package"
adb -s <id> install -r app/build/app/outputs/flutter-apk/app-debug.apk
adb -s <id> push ~/elinkbook-qa/epic-49-font-check.epub //sdcard/Download/
```
記下：型號、Android 版本、WebView 版本。`dumpsys webviewupdate` 會直接列出系統目前使用的 WebView 套件與版本，不必猜套件名稱（計畫審查 M-3）；如果這行沒有輸出，改看完整的 `adb -s <id> shell dumpsys webviewupdate`。

- [x] **Step 2：確認起點是「未下載」（第 1 項前置）**

```bash
adb -s <id> shell run-as cc.ugotit.elinkbook ls -la files/downloaded-fonts/v1
```
預期：目錄是空的，或回報「No such file or directory」。如果看到 `.ttf` 檔，先開 App → 設定 → 字型管理，把已下載的字型刪掉，再跑一次確認。

- [x] **Step 3：第 1 項——字型管理畫面**

開 App → 設定 → 字型管理。

預期：思源黑體顯示「未下載」與 **34.4 MB**；思源宋體顯示「未下載」與 **57.1 MB**；兩列都有「下載」按鈕。

- [x] **Step 4：第 2 項——下載、取消、完成**

1. 按思源宋體的「下載」，看進度百分比有持續增加；在 30% 左右按「取消下載」。預期：回到「未下載」，而且沒有錯誤訊息。
2. 用 Step 2 的 `run-as` 指令確認目錄裡沒有 `SourceHanSerifTC-VF.ttf`，也沒有殘留的 `.part` 檔。
3. 再按一次「下載」並等它完成。預期：進度走到 100%，變成「已下載」，出現「刪除」按鈕；`run-as` 列出 `SourceHanSerifTC-VF.ttf`，大小 59898316。
4. 下載期間觀察其他列的「下載」按鈕是停用的（一次只能下載一款）。

- [x] **Step 5：第 3 項——閱讀器套用思源宋體（橫排）**

1. 回書庫，用書庫的匯入功能從「下載」資料夾選 `epic-49-font-check.epub`，開啟這本書。
2. 開閱讀設定 → 字型選單。預期：內建字型只列出「思源宋體」（思源黑體還沒下載，不應出現）；另外有「使用書本字型」，以及裝置上原本就有的自訂字型（如果有的話）。選單下方**不**顯示「到『字型管理』下載更多字型」提示。
3. 選「思源宋體」，關閉設定。
4. 電腦開 Chrome，網址列輸入 `chrome://inspect/#devices`，在手機底下找到 `cc.ugotit.elinkbook`、網址為 `https://appassets.androidplatform.net/...` 的項目，按「inspect」。
5. 在 DevTools 的 Elements 面板，展開 `<iframe>` 底下的 `#document`，選取第一個中文 `<p>`。
6. 切到 Computed 分頁，捲到最下面的「Rendered Fonts」。預期：顯示 `SourceHanSerifTC`，不是 `Noto Serif CJK`／`Noto Sans CJK`。
7. 再選英文等寬的 `<p class="mono">`，預期同樣是 `SourceHanSerifTC`（閱讀器覆蓋了書本的 `monospace`）。

- [x] **Step 6：第 3 項——直排**

閱讀設定把排版方向切成直排，重做 Step 5 的第 5～6 小步。預期：仍是 `SourceHanSerifTC`，直排標點方向正常。檢查完切回橫排。

- [x] **Step 7：第 9 項——改回「使用書本字型」**

1. DevTools 保持連線。閱讀設定 → 字型選單改選「使用書本字型」。
2. 選取 `<p class="mono">`，看 Rendered Fonts。預期：變成等寬字型（例如 `Cutive Mono`、`Droid Sans Mono`），**不是** `SourceHanSerifTC`，也不是 `Roboto` 這類一般無襯線字型。
3. 選取中文 `<p>`。預期：不再是 `SourceHanSerifTC`。
4. 在 Styles 分頁確認沒有任何 `font-family: 'SourceHanSerifTC' !important` 規則。
5. 旋轉手機一次（螢幕方向沒有鎖定時），再重做第 2 小步。預期：仍是等寬字型。
6. 做完把字型改回「思源宋體」。

- [x] **Step 8：第 4 項——飛航模式**

1. 退出閱讀器，把 App 從多工畫面滑掉。
2. 手機開飛航模式（Wi-Fi 也關掉）。
3. 重開 App、開同一本書。預期：開書正常，畫面字型和 Step 5 一樣是思源宋體（可以用 DevTools 再確認一次 Rendered Fonts）。
4. 關閉飛航模式。

- [x] **Step 9：第 5 項——刪除後退回書本字型、重新下載後恢復**

1. 退出閱讀器 → 設定 → 字型管理 → 刪除思源宋體。預期：確認對話框內文是「刪除後可以隨時重新下載。使用這款字型的書會暫時改用書本或系統字型，重新下載後自動恢復。」確認後變回「未下載」。
2. 開同一本書 → 閱讀設定。預期：字型選單顯示「使用書本字型」，選單下方出現「到『字型管理』下載更多字型」提示。
3. 用 DevTools 看 `<p class="mono">` 的 Rendered Fonts。預期：是等寬字型（書本字型），不是系統預設的無襯線字型（Issue 6 的修正）。
4. 退出 → 字型管理 → 重新下載思源宋體。
5. 再開同一本書。預期：字型選單自動顯示「思源宋體」，Rendered Fonts 是 `SourceHanSerifTC`，**不需要**重新選字型。

- [x] **Step 10：第 7 項——下載中途滑掉 App**

issues.md 第 7 項寫的是思源宋體，這裡刻意改用思源黑體：思源宋體在 Step 9 已經下載完成，改用思源黑體就不必先刪除，而且能順便驗證目錄裡的另一款字型（計畫審查 M-5）。

1. 字型管理 → 下載思源黑體，進度到 30～60% 時，從多工畫面把 App 滑掉。
2. 重開 App → 字型管理。預期：思源黑體顯示「未下載」。
3. `run-as` 列出目錄，預期：沒有 `SourceHanSansTC-VF.ttf`，也沒有 `SourceHanSansTC-VF.ttf.part`（App 啟動時的 `prepare()` 會清掉）。
4. 再下載一次思源黑體。預期：能正常完成，變成「已下載」。

- [x] **Step 11：第 6 項——翻頁效能（release APK）**

1. 安裝 release APK（資料保留）：
   ```bash
   adb -s <id> install -r app/build/app/outputs/flutter-apk/app-release.apk
   ```
2. 開驗證書，用目錄跳到第 2 章「翻頁測試」（約 3.5 萬字，遠超過 30 頁；計畫審查 I-2），字型選思源宋體。書庫裡如果有其他長篇書，也可以額外再試一本。
3. 從第 2 章開頭連續翻 30 頁以上，橫排、直排各一次。預期：翻頁速度和選「使用書本字型」時沒有明顯差別，不會出現某幾頁先顯示系統字型再跳成思源宋體的閃動。
4. 記下主觀感受（順暢／偶爾卡頓／明顯卡頓）與卡頓發生的位置。

- [x] **Step 12：整理手機結果**

把第 1、2、3、4、5、6、7、9 項逐項寫成「通過／失敗＋一句觀察」，連同 Step 1 的裝置資訊交給 Task 4。任何一項失敗時，附上截圖或 DevTools 畫面，並寫下重現步驟。

---

### Task 3：電子紙閱讀器（人類操作）

**Interfaces:**
- Consumes：Task 1 的兩個 APK 與驗證書。
- Produces：第 2 項（電子紙部分）、第 6 項、第 8 項的結果，交給 Task 4。

- [x] **Step 1：記錄裝置資訊**

照 Task 2 Step 1 的前 4 條指令（`adb devices`、兩條 `getprop`、`dumpsys webviewupdate`）記下型號、Android 版本、WebView 版本。比較兩台裝置：**Android 版本或 WebView 版本較舊的那台，負責第 8 項**。如果手機比較舊，第 8 項改在手機上做（debug APK），做法同本 Task Step 4。

- [x] **Step 2：第 2 項電子紙部分——下載時的畫面（release APK）**

1. 安裝 release APK 並推送驗證書：
   ```bash
   adb -s <id> install -r app/build/app/outputs/flutter-apk/app-release.apk
   adb -s <id> push ~/elinkbook-qa/epic-49-font-check.epub //sdcard/Download/
   ```
   再用書庫的匯入功能匯入驗證書（Step 3、Step 4 會用到）。
2. 字型管理 → 如果思源宋體已下載，先刪除 → 按「下載」。
3. 觀察整個下載過程。預期：進度數字更新時沒有整頁閃爍、沒有殘影堆積，其他操作（捲動清單、返回）不會卡住。進度最多更新 101 次（0～100%，只在數字變大時更新）。
4. 下載完成後變成「已下載」。

- [x] **Step 3：第 6 項——翻頁效能（release APK）**

照 Task 2 Step 11 的第 2～4 小步，在電子紙上做一次。額外觀察：翻頁時有沒有因為字型載入多出一次刷新。

- [x] **Step 4：第 8 項——最舊裝置的字型請求與 Content-Type（debug APK）**

在 Step 1 判定為「較舊」的那台裝置上做。

1. 安裝 debug APK：
   ```bash
   adb -s <id> install -r app/build/app/outputs/flutter-apk/app-debug.apk
   ```
2. 開驗證書，閱讀設定先選「使用書本字型」。
3. 電腦 `chrome://inspect/#devices` → inspect 這個 WebView → 切到 Network 面板，勾選「Disable cache」，篩選欄輸入 `downloaded-fonts`。
4. **這時才**到閱讀設定改選「思源宋體」。預期：Network 出現 `SourceHanSerifTC-VF.ttf` 的請求，Status 是 **200**。
5. 點這個請求 → Headers → Response Headers，記下 `Content-Type` 的實際值（預期可能是 `font/ttf`、`application/x-font-ttf` 或其他，**照實記錄即可，值本身不算失敗**）。
6. 照 Task 2 Step 5 第 5～6 小步確認 Rendered Fonts 是 `SourceHanSerifTC`。**字型有套用才算通過**。
7. 如果 Network 沒有出現請求：關閉書、重新開書並立刻 inspect，再做一次第 4 小步。

**連不上 DevTools 時的退路**（`chrome://inspect` 裡找不到這個 WebView）：
- 在結果註明「此裝置無法連上 DevTools」。
- 改用肉眼比對：同一頁分別選「使用書本字型」和「思源宋體」各截一張圖，英文等寬段落的字形應該明顯不同（等寬 vs. 思源宋體的比例字寬）。字形有變就算「字型有套用」；Content-Type 記為「無法取得」。

- [x] **Step 5：整理電子紙結果**

把第 2 項（電子紙部分）、第 6 項、第 8 項寫成「通過／失敗＋一句觀察」，第 8 項附上 Content-Type 實際值，連同裝置資訊交給 Task 4。

---

### Task 4：記錄結果與更新進度（agent 可執行，依人類回報）

**Files:**
- Modify: `docs/epics/epic-49-downloadable-fonts/epic.md`
- Modify: `docs/epics/epic-49-downloadable-fonts/issues.md`
- Modify: `docs/epics.md`
- Modify: `docs/epics/epic-49-downloadable-fonts/plans/plan-issue-5.md`

**Interfaces:**
- Consumes：Task 2 Step 12、Task 3 Step 5 的結果與裝置資訊。

本 Task 的指令都在 repo 根目錄執行；開始前先 `cd /c/Users/fycdc/AI/elinkBook`，並用 `git branch --show-current` 確認在 `epic-49/issue-5-device-qa`（計畫審查 M-1）。

- [x] **Step 1：寫入 `epic.md`**

在「開發記錄」最後新增一段，格式如下，角括號內照人類回報的內容填寫，不可自行推測：

```markdown
**<YYYY-MM-DD> Issue 5 真機驗證**（分支 `epic-49/issue-5-device-qa`）

| 裝置 | 型號 | Android | WebView |
|---|---|---|---|
| 一般手機 | <型號> | <版本> | <版本> |
| 電子紙閱讀器 | <型號> | <版本> | <版本> |

| # | 項目 | 裝置 | 結果 | 觀察 |
|---|---|---|---|---|
| 1 | 字型管理列出未下載與大小 | 手機 | <通過／失敗> | <一句話> |
| 2 | 下載進度、取消、完成 | 手機 | <通過／失敗> | <一句話> |
| 2 | 電子紙下載時無明顯閃爍或卡頓 | 電子紙 | <通過／失敗> | <一句話> |
| 3 | 閱讀器套用思源宋體（橫排／直排） | 手機 | <通過／失敗> | <Rendered Fonts 結果> |
| 4 | 飛航模式重新開書字型正確 | 手機 | <通過／失敗> | <一句話> |
| 5 | 刪除後退回書本字型、重新下載後恢復 | 手機 | <通過／失敗> | <一句話> |
| 6 | 翻頁無明顯卡頓（橫排／直排） | 手機 | <通過／失敗> | <主觀感受> |
| 6 | 翻頁無明顯卡頓、無額外刷新 | 電子紙 | <通過／失敗> | <主觀感受> |
| 7 | 下載中途滑掉 App 後為未下載、可重新下載 | 手機 | <通過／失敗> | <一句話> |
| 8 | 最舊裝置字型請求 200、字型有套用 | <裝置> | <通過／失敗> | Content-Type：<實際值或「無法取得」> |
| 9 | 改回使用書本字型後立即回到書本字型、旋轉後仍正確 | 手機 | <通過／失敗> | <Rendered Fonts 結果> |
```

- [x] **Step 2：依結果更新狀態**

**9 項全部通過時：**
1. `issues.md` 的 Issue 5：`**Status:** ready-for-human` 改成 `**Status:** completed`。
2. `docs/epics.md` epic-49 那一列的備註改成：`全數完成，待歸檔`。
3. `epic.md` 在表格下方加一句：「9 項全部通過，epic-49 全部工單完成，待人類指定歸檔。」

**有任何一項失敗時：**
1. Issue 5 狀態維持 `ready-for-human`，不改 `docs/epics.md`。
2. `epic.md` 在表格下方列出失敗的項目、現象與重現步驟。
3. 回報人類，由人類決定要在 `issues.md` 新增哪個修正工單（不可自行新增）。

- [x] **Step 3：勾選本計畫已完成的步驟並提交**

```bash
git add docs/epics.md docs/epics/epic-49-downloadable-fonts/epic.md docs/epics/epic-49-downloadable-fonts/issues.md docs/epics/epic-49-downloadable-fonts/plans/plan-issue-5.md
git commit -m "docs(epic-49): 記錄 Issue 5 真機驗證結果"
```
commit 訊息結尾加上 `Co-Authored-By` 署名行（依當次工作階段的 system reminder）。之後依人類指示推送並發 PR。

- [ ] **Step 4（可選）：清理測試物料**（計畫審查 M-2）

由人類決定是否執行。裝置端每台各跑一次：
```bash
MSYS_NO_PATHCONV=1 adb -s <id> shell rm -f /sdcard/Download/epic-49-font-check.epub
```
書庫裡匯入的「epic-49 字型驗證書」要在 App 內手動移除（這裡沒有對應的 `adb` 指令）；已下載的字型可以保留。本機暫存：
```bash
rm -rf ~/elinkbook-qa
```
