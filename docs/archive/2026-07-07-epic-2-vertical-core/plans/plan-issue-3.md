# Issue 3 實作計劃：FR-32 避頭尾符合度驗證（CNS 11643）與直排分頁文字裁切問題調查

> **給執行的 Agent：** 建議使用 superpowers:subagent-driven-development（推薦）或 superpowers:executing-plans 逐任務執行本計劃。步驟採用核取方塊（`- [ ]`）語法追蹤進度。

**目標：** 完成 `issues.md` Issue 3 的驗收要求——在真機上對直排 CJK EPUB 進行 FR-32 標點轉向/避頭尾人工視覺比對並產出書面驗證紀錄；同時系統化重現、根因調查使用者實機測試回報的「EPUB3 在手機/平板直立、採用直排閱讀時，畫面上下會切到部份文字」問題，並依調查結論決定是否需要建立後續 issue 追蹤修復。本 issue 依 `issues.md` 定義為**驗證/研究性質**工單，預設不假設一定要異動 production 程式碼。

**架構：** 現有 `app/test/fixtures/sample.epub` 內容僅一段短句（見下方 Task 1 Step 1 的具體證據），不足以在真機上呈現跨「頁」（直排分頁下的欄位邊界）的畫面，因此本 issue 第一步須先補一份內容足夠長、標點符號種類齊全的直排 CJK fixture。接著分別對 FR-32（標點/避頭尾）與新發現的文字裁切問題進行真機視覺驗證；文字裁切問題另外透過解壓 `readium-navigator:3.3.0` AAR 內建的 `cjk-vertical` ReadiumCSS 常數，與 Readium 官方倉庫的已知 issue 交叉比對根因，並用 `EpubPreferences` 既有欄位（`scroll`/`lineHeight`/`pageMargins`）做暫時性、驗證後即還原的診斷實驗（不永久修改 production 程式碼）。最終產出一份版本控制的驗證紀錄 `docs/epics/epic-2-vertical-core/qa-issue-3-writing-mode-verification.md`，並依結論決定是否在 `issues.md` 新增 Issue 4。

**技術棧：** Readium `readium-navigator`/`readium-css` 3.3.0（`cjk-vertical` ReadiumCSS、CSS 多欄分頁機制、`EpubPreferences`）、Android WebView（系統元件，版本因裝置而異，可透過既有 `elinkbook/app_info`.`getSystemWebViewVersion` method channel 查詢）、`flutter build apk --debug` + 真機/模擬器、`adb`（螢幕截圖）、Python 3（一次性產生新的長篇 CJK 直排 fixture，不是專案相依套件）、`javap`（JDK 內建，反編譯 AAR `.class` 確認 API 欄位）。

## ⚠️ 執行前環境確認事項

本 issue **全程須在真實 Android 裝置或模擬器上執行視覺驗證**——執行前請先在 `app/` 目錄下確認 `flutter devices` 能列出至少一個 Android 裝置/模擬器。若條件允許，建議準備至少兩種不同螢幕比例的裝置/模擬器（例如一支手機＋一台平板，或至少兩種不同解析度的手機模擬器），因為使用者回報的症狀特別指出「手機/平板直立時」，需要排除單一裝置的個案因素。

## 全域限制條件

- 本 issue **預設不修改** production 程式碼（`EpubReaderView.kt`、`app/lib/reader/epub_reader_view.dart`、`app/lib/screens/reader_screen.dart`）。Task 5 的診斷實驗屬暫時性程式碼變動，驗證完成後**必須**在同一個 Task 內以 `git checkout --` 還原、確認 `git status` 乾淨，不得遺留未還原的變更；只有在 Task 6 依證據明確決定「本 issue 內直接採用某個最小修復」時才允許例外（見 Task 6 的決策分支說明）。
- 驗證紀錄與所有新增文件一律使用正體中文撰寫。
- 驗證紀錄存放路徑固定為 `docs/epics/epic-2-vertical-core/qa-issue-3-writing-mode-verification.md`——**不**放在 `reviews/` 目錄：`reviews/` 依專案慣例僅用於審查報告且已加入 `.gitignore`（不進版控），而本檔案是 `issues.md` Issue 3 本身要求產出、需要進版控供後續複查的驗收交付物。
- 若 Task 6 判定需要新增後續 issue，一律以新增區塊的方式附加於 `docs/epics/epic-2-vertical-core/issues.md` 現有 Issue 3 區塊之後，**不得**刪改 Issue 1/2 既有內容。
- 新增的 fixture 檔名須為 `sample_long_vertical.epub`，並依既有慣例登記進 `app/pubspec.yaml` 的 `assets` 清單。
- `flutter analyze` 全程必須維持 `No issues found!`（若 Task 5 的暫時性程式碼變動導致分析出現問題，還原後應自動恢復乾淨）。
- Task 2/3/5 每一次 `adb pull` 取得的截圖，`git add` 前先執行 `ls -la <檔名>`（或 `Get-Item <檔名> | Select-Object Length`）確認檔案大小；由於 `sample_long_vertical.epub` 內容以純文字為主（背景近乎全白、無複雜圖片），PNG 無損壓縮後單張預期在數百 KB 內，若任一張超過 1MB，先用系統內建工具（Windows「相片」應用程式或小畫家）裁切至只保留裁切現象發生的局部區域再提交，避免將整張未裁切的高解析度截圖不必要地存入 git 歷史。

---

### Task 1：建立可重現跨頁邊界的直排 CJK 測試 fixture（`sample_long_vertical.epub`）

**Files:**
- Create: `app/test/fixtures/sample_long_vertical.epub`
- Modify: `app/pubspec.yaml`

**Interfaces:**
- Consumes: 無（獨立於 Issue 1/2 已建立的型別）
- Produces: `test/fixtures/sample_long_vertical.epub`——內容足夠長、`dc:language=zh-TW`、`<html lang="zh-TW">`、涵蓋常見 CNS 11643 避頭尾標點種類的直排 CJK EPUB，供 Task 2、3、5 共用。

- [ ] **Step 1：確認既有 fixture 內容過短，無法重現跨頁邊界**

Run（於 `app/` 目錄下，利用 Python 避開 Windows pwsh 無 unzip 的相容性問題）：
```bash
python -c "import zipfile; print(zipfile.ZipFile('test/fixtures/sample.epub').read('OEBPS/chapter1.xhtml').decode('utf-8'))"
```
Expected：輸出僅一個標題（`第一章`）與一段約 30 字的短句（「這是 elinkBook 用於 integration_test 的範例 EPUB 內容。」）。這樣的內容量在任何螢幕尺寸下都只會佔用直排分頁的第 1 欄局部空間，不會產生第 2 欄，因此無法用來觀察「欄位邊界文字被裁切」的現象——這正是需要新建 `sample_long_vertical.epub` 的原因。

- [ ] **Step 2：撰寫並執行 fixture 產生腳本**

在 `app/test/fixtures/` 目錄下建立暫時腳本 `_build_long_vertical_fixture.py`（本步驟結束後會刪除，不會提交進版控）：

```python
import zipfile

CONTAINER_XML = """<?xml version="1.0" encoding="UTF-8"?>
<container version="1.0" xmlns="urn:oasis:names:tc:opendocument:xmlns:container">
  <rootfiles>
    <rootfile full-path="OEBPS/content.opf" media-type="application/oebps-package+xml"/>
  </rootfiles>
</container>
"""

OPF = """<?xml version="1.0" encoding="UTF-8"?>
<package xmlns="http://www.idpf.org/2007/opf" version="3.0" unique-identifier="pub-id">
  <metadata xmlns:dc="http://purl.org/dc/elements/1.1/">
    <dc:identifier id="pub-id">urn:uuid:00000000-0000-0000-0000-000000000004</dc:identifier>
    <dc:title>elinkBook 直排長篇範例 EPUB</dc:title>
    <dc:language>zh-TW</dc:language>
    <meta property="dcterms:modified">2026-01-01T00:00:00Z</meta>
  </metadata>
  <manifest>
    <item id="nav" href="nav.xhtml" media-type="application/xhtml+xml" properties="nav"/>
    <item id="chapter1" href="chapter1.xhtml" media-type="application/xhtml+xml"/>
  </manifest>
  <spine>
    <itemref idref="chapter1"/>
  </spine>
</package>
"""

NAV = """<?xml version="1.0" encoding="UTF-8"?>
<html xmlns="http://www.w3.org/1999/xhtml" xmlns:epub="http://www.idpf.org/2007/ops">
<head><title>目錄</title></head>
<body>
  <nav epub:type="toc">
    <ol>
      <li><a href="chapter1.xhtml">第一章</a></li>
    </ol>
  </nav>
</body>
</html>
"""

# 10 種句型，涵蓋 CNS 11643 常見避頭尾標點：句號/逗號、問號/驚嘆號、
# 頓號、括號、書名號、破折號、刪節號、冒號分號。每種句型重複 6 次、
# 依序編號組成 60 段落，確保內容量（約 3000+ 字）足以在一般手機直排
# 版面下跨越多個欄位（頁）邊界。
TEMPLATES = [
    "「這是第{n}段話，包含逗號與句號。」",
    "『他在第{n}段問道：你今天過得好嗎？』",
    "這是第{n}段的驚嘆句！這裡還有一個驚嘆號。",
    "（這是第{n}段括號內的補充說明）然後接續正文繼續書寫。",
    "第{n}段列出幾樣水果：蘋果、香蕉、橘子，還有葡萄。",
    "——這是第{n}段以破折號開頭的句子，用來表示語氣的轉折。",
    "他在第{n}段說……然後就沉默了，留下一段省略號。",
    "《紅樓夢》是第{n}段提到的經典小說；《西遊記》也是。",
    "「你聽到了嗎？」她在第{n}段輕聲問道，語氣中帶著一絲不安。",
    "第{n}段列舉：一、二、三；甲、乙、丙——這些都是常見的列舉符號。",
]

paragraphs = []
for i in range(1, 61):
    template = TEMPLATES[(i - 1) % len(TEMPLATES)]
    paragraphs.append("  <p>{}</p>".format(template.format(n=i)))

CHAPTER1 = """<?xml version="1.0" encoding="UTF-8"?>
<html xmlns="http://www.w3.org/1999/xhtml" lang="zh-TW" xml:lang="zh-TW">
<head><title>第一章</title></head>
<body>
  <h1>第一章：直排長篇範例</h1>
{paragraphs}
</body>
</html>
""".format(paragraphs="\n".join(paragraphs))


def build_epub(path, opf, nav, chapter1):
    with zipfile.ZipFile(path, "w") as zf:
        zf.writestr("mimetype", "application/epub+zip", compress_type=zipfile.ZIP_STORED)
        zf.writestr("META-INF/container.xml", CONTAINER_XML, compress_type=zipfile.ZIP_DEFLATED)
        zf.writestr("OEBPS/content.opf", opf, compress_type=zipfile.ZIP_DEFLATED)
        zf.writestr("OEBPS/nav.xhtml", nav, compress_type=zipfile.ZIP_DEFLATED)
        zf.writestr("OEBPS/chapter1.xhtml", chapter1, compress_type=zipfile.ZIP_DEFLATED)


build_epub("sample_long_vertical.epub", OPF, NAV, CHAPTER1)
print("done")

# 驗證新產生的 epub 檔案
try:
    zf = zipfile.ZipFile('sample_long_vertical.epub')
    print([(i.filename, i.compress_type) for i in zf.infolist()])
    print(len(zf.read('OEBPS/chapter1.xhtml')), 'bytes in chapter1.xhtml')
except Exception as e:
    print("Verification failed:", e)
```

Run（於 `app/test/fixtures/` 目錄下，利用 Python 腳本自帶的驗證輸出，並使用 Windows / Unix 皆支援 rm 語法刪除暫存腳本）：
```bash
python _build_long_vertical_fixture.py
rm _build_long_vertical_fixture.py
```
Expected：印出 `done`；第二個指令印出 5 個項目（`mimetype` 的 `compress_type` 為 `0`／`ZIP_STORED` 且為第一個項目，其餘為 `8`／`ZIP_DEFLATED`），且 `chapter1.xhtml` 位元組數應遠大於 `sample.epub` 的同名檔案（預期 3000 bytes 以上）；`_build_long_vertical_fixture.py` 已刪除，不會被提交進版控。

- [ ] **Step 3：在 `pubspec.yaml` 註冊新 asset**

開啟 `app/pubspec.yaml`，把：

```yaml
  assets:
    - test/fixtures/sample.pdf
    - test/fixtures/sample.epub
    - test/fixtures/sample_horizontal.epub
    - test/fixtures/sample_fixed_layout.epub
```

改為：

```yaml
  assets:
    - test/fixtures/sample.pdf
    - test/fixtures/sample.epub
    - test/fixtures/sample_horizontal.epub
    - test/fixtures/sample_fixed_layout.epub
    - test/fixtures/sample_long_vertical.epub
```

- [ ] **Step 4：確認 asset 註冊無誤**

Run（於 `app/` 目錄下）：
```bash
flutter pub get
```
Expected：成功執行，無錯誤訊息。

- [ ] **Step 5：Commit**

Run（返回專案根目錄執行 Git 指令）：
```bash
cd ../..
git add app/test/fixtures/sample_long_vertical.epub app/pubspec.yaml
git commit -m "Add long-form vertical CJK EPUB fixture for FR-32 and pagination QA"
cd app
```

---

### Task 2：FR-32 標點轉向與避頭尾人工視覺比對（真機）

**Files:**
- Create: `docs/epics/epic-2-vertical-core/qa-issue-3-writing-mode-verification.md`

**Interfaces:**
- Consumes: Task 1 的 `sample_long_vertical.epub`
- Produces: 驗證紀錄文件的「FR-32 標點與避頭尾」章節，供 Task 6 彙整最終結論時引用。

- [ ] **Step 1：建立驗證紀錄文件骨架**

建立 `docs/epics/epic-2-vertical-core/qa-issue-3-writing-mode-verification.md`：

```markdown
# Issue 3 驗證紀錄：FR-32 避頭尾符合度與直排分頁文字裁切問題

依 `docs/epics/epic-2-vertical-core/issues.md` Issue 3 與 `docs/epics/epic-2-vertical-core/plans/plan-issue-3.md` 產出。

## 測試環境

| 項目 | 值 |
| --- | --- |
| 裝置/模擬器型號 | （執行時填入 `adb shell getprop ro.product.model` 的輸出） |
| Android 版本 | （執行時填入 `adb shell getprop ro.build.version.release` 的輸出） |
| 螢幕解析度 | （執行時填入 `adb shell wm size` 的輸出） |
| 螢幕密度 | （執行時填入 `adb shell wm density` 的輸出） |
| 系統 WebView 版本 | （執行時透過 App 內既有 `elinkbook/app_info`.`getSystemWebViewVersion` 或 `adb shell "dumpsys package com.google.android.webview | grep versionName"` 取得後填入） |
| App 建置方式 | `flutter build apk --debug`（本機組建，未簽章 release） |

## 一、FR-32 標點轉向與避頭尾比對

**方法：** 於 `flutter run`（或安裝 debug APK 後）於裝置上開啟 `sample_long_vertical.epub`，切換為直排模式，逐頁瀏覽全書 60 段內容，對照下表的 CNS 11643 常見避頭尾字元類別，記錄實際渲染結果。

| 類別 | 代表字元 | 規則 | 觀察結果（符合／不符合＋說明） |
| --- | --- | --- | --- |
| 收尾類標點不可置於行首 | 」』）］｝、。，；：？！ | 不可出現在下一欄（頁）的最上方 | |
| 起頭類標點不可置於行尾 | 「『（〔［｛《〈 | 不可出現在欄（頁）的最下方 | |
| 破折號 | —— | 應連續轉向為縱向、不可斷開 | |
| 刪節號 | …… | 應連續轉向為縱向、不可斷開 | |
| 書名號 | 《》 | 應正確轉向並置中 | |
| 一般標點置中 | 、。，；：？！ | 直排時應置中對齊字身，而非貼齊某一側 | |

## 二、結論

（符合 CNS 11643 ／發現以下落差：……——由 Task 6 彙整填入最終結論）
```

- [ ] **Step 2：安裝 debug APK 並於真機上開啟 fixture 進行比對**

Run（於 `app/` 目錄下；`<device-id>` 替換為 `flutter devices` 列出的實際裝置 ID）：
```bash
flutter build apk --debug
flutter install -d <device-id>
```
在裝置上手動開啟 App、進入書架、開啟 `sample_long_vertical.epub`（需先透過既有匯入流程或範例書架項目載入本檔案；若目前 `LibraryScreen` 範例清單未涵蓋本檔案，暫時透過 `adb push` 將檔案放到裝置可存取路徑，再以既有的「本機檔案匯入」流程開啟——不需為此新增任何 production 程式碼）：
```bash
adb -s <device-id> push test/fixtures/sample_long_vertical.epub /sdcard/Download/sample_long_vertical.epub
```
開啟後按下 AppBar 的橫直排切換按鈕（`reader_writing_mode_toggle`）切換為直排，逐頁翻閱，依 Step 1 建立的表格逐一比對並記錄結果；對每一類別若有疑似落差，執行：
```bash
adb -s <device-id> shell screencap -p /sdcard/qa-issue-3-fr32-<類別編號>.png
adb -s <device-id> pull /sdcard/qa-issue-3-fr32-<類別編號>.png docs/epics/epic-2-vertical-core/
```
把截圖存放於 `docs/epics/epic-2-vertical-core/`（與驗證紀錄同目錄，檔名前綴 `qa-issue-3-fr32-`），並在驗證紀錄表格的「觀察結果」欄位中註明對應截圖檔名。

Expected：完成表格所有列的填寫；若六類皆符合預期（收尾類不出現在行首、起頭類不出現在行尾、破折號/刪節號/書名號正確轉向、標點置中），在「結論」段落記錄「符合 CNS 11643」；否則記錄具體差異字元與截圖佐證。

---

### Task 3：系統化重現「直排模式下文字上下被裁切」問題

**Files:**
- Modify: `docs/epics/epic-2-vertical-core/qa-issue-3-writing-mode-verification.md`

**Interfaces:**
- Consumes: Task 1 的 `sample_long_vertical.epub`；既有 `sample.epub`
- Produces: 驗證紀錄文件新增「三、文字裁切問題重現」章節，含明確的重現條件矩陣，供 Task 4 根因調查使用。

- [ ] **Step 1：於驗證紀錄新增重現記錄章節骨架**

在 `docs/epics/epic-2-vertical-core/qa-issue-3-writing-mode-verification.md` 的「二、結論」段落之前插入：

```markdown
## 三、文字裁切問題重現

**回報症狀：** 實機測試中，EPUB3 在手機/平板呈直立（portrait）狀態、採用直排（vertical-RL）閱讀模式時，畫面上下邊緣會出現部份文字被裁切的現象。

**重現條件矩陣：**

| # | 裝置 | 螢幕方向 | 書籍 | 字型大小 | 是否出現裁切 | 裁切位置（畫面上緣／下緣／兩者皆有） | 截圖檔名 |
| --- | --- | --- | --- | --- | --- | --- | --- |
| 1 | | 直立 (portrait) | sample_long_vertical.epub | 預設 (100%) | | | |
| 2 | | 直立 (portrait) | sample_long_vertical.epub | 放大 (150%) | | | |
| 3 | | 直立 (portrait) | sample_long_vertical.epub | 縮小 (80%) | | | |
| 4 | | 橫向 (landscape) | sample_long_vertical.epub | 預設 (100%) | | | |
| 5 | | 直立 (portrait) | sample.epub（短內容） | 預設 (100%) | | | |
| 6 | | 直立 (portrait，第二支裝置/模擬器若有) | sample_long_vertical.epub | 預設 (100%) | | | |

**每一列的判別重點：** 裁切若只發生在「特定頁面」或「特定字型大小」而非每一頁都發生，代表症狀符合「欄位高度非行高整數倍，導致該欄最後一行卡在邊界」的假說（見 Task 4）；若每一頁都固定裁切同樣位置，則較可能是容器整體尺寸量測錯誤（例如系統列/瀏海未正確排除）。
```

- [ ] **Step 2：逐列執行重現並填表**

沿用 Task 2 已安裝的 debug APK，針對表格每一列：

```bash
# 切換裝置方向為直立（若為真機，手動旋轉；若為模擬器，可用 adb 或模擬器工具列切換）
adb -s <device-id> shell wm size
adb -s <device-id> shell wm density
```

開啟對應書籍、切換為直排模式（並視需要調整字型大小），翻閱全書，觀察是否仍有文字被上下裁切的現象；截圖記錄：

Run（拉取截圖時回到專案根目錄）：
```bash
adb -s <device-id> shell screencap -p /sdcard/qa-issue-3-clip-<列號>.png
cd ..
adb -s <device-id> pull /sdcard/qa-issue-3-clip-<列號>.png docs/epics/epic-2-vertical-core/
cd app
```

把裝置型號、螢幕方向、書籍、字型大小、是否裁切、裁切位置、截圖檔名填入表格對應欄位；若無法取得第二支裝置/模擬器，第 6 列填寫「無可用裝置，未執行」並說明原因，不影響本 issue 其餘結論。

Expected：表格六列（或視裝置可用性至少完成第 1-3 列）皆有明確記錄；至少能回答「裁切是否只在特定頁面出現（偶發）」這個判別問題。

- [ ] **Step 3：Commit（含截圖與紀錄文件更新）**

Run（返回專案根目錄執行 Git 指令）：
```bash
cd ..
git add docs/epics/epic-2-vertical-core/qa-issue-3-writing-mode-verification.md docs/epics/epic-2-vertical-core/qa-issue-3-*.png
git commit -m "Document FR-32 comparison and text-clipping repro matrix for Issue 3"
cd app
```

---

### Task 4：根因比對——ReadiumCSS 內建常數與 upstream 已知 issue 交叉核對

**Files:**
- Modify: `docs/epics/epic-2-vertical-core/qa-issue-3-writing-mode-verification.md`

**Interfaces:**
- Consumes: Task 3 的重現條件矩陣
- Produces: 驗證紀錄文件新增「四、根因分析」章節，供 Task 6 決策使用。

**背景（Architecting 階段既有靜態分析基礎）：** `spec.md`「已驗證的技術基礎」已確認 `cjk-vertical` ReadiumCSS 對 `:lang(zh)` 內建 `line-break:strict`（FR-32 範圍）；本 Task 需要進一步檢視同一份 CSS 中，直排模式下實際驅動分頁欄位尺寸的常數，因為使用者回報的裁切症狀與標點無關，是欄位（頁）本身的高度計算問題。

- [ ] **Step 1：解壓 AAR 並檢視 `cjk-vertical` 分頁相關 CSS 常數**

本步驟需在暫存目錄中，自動尋找並解壓 `readium-navigator-3.3.0.aar`。

對於 Bash (macOS/Linux) 環境，執行：
```bash
mkdir -p readium_aar_check && cd readium_aar_check
AAR_PATH=$(find ~/.gradle/caches/ -name "readium-navigator-3.3.0.aar" | head -n 1)
unzip -o -q "$AAR_PATH" -d .
grep -o ':root{[^}]*}' assets/readium/readium-css/cjk-vertical/ReadiumCSS-after.css | head -1
cd .. && rm -rf readium_aar_check
```

對於 Windows PowerShell (pwsh) 環境，執行：
```powershell
New-Item -ItemType Directory -Path ".\readium_aar_check" -Force
cd .\readium_aar_check
$aar = Get-ChildItem -Path "$HOME\.gradle\caches\" -Filter "readium-navigator-3.3.0.aar" -Recurse | Select-Object -First 1 -ExpandProperty FullName
Expand-Archive -Path $aar -DestinationPath "." -Force
Select-String -Path ".\assets\readium\readium-css\cjk-vertical\ReadiumCSS-after.css" -Pattern ":root\{[^}]*\}"
cd ..
Remove-Item -Recurse -Force .\readium_aar_check
```

Expected：輸出應包含 `--RS__colWidth:100vh`、`--RS__colCount:1`、`height:100vh`、`max-height:100vh`、`min-height:100vh` 等宣告（本計劃撰寫時已用此指令確認過一次，執行者需親自重跑以複查，不可只依賴本計劃文字敘述）。這代表**直排模式下，每一欄（頁）的尺寸是由 CSS `100vh`（viewport 高度）驅動，而非由 App 端顯式計算像素值傳給 WebView**——若 WebView 內部計算出的 `100vh` 與畫面實際可視高度存在任何誤差（次像素捨入、密度轉換誤差等），就會導致某一欄最後一行文字剛好卡在欄位邊界而被裁切。

- [ ] **Step 2：查閱 Readium 官方倉庫已知 issue，確認是否為已知的上游限制**

使用 `WebFetch` 讀取以下兩個 URL 的完整內容（本計劃撰寫時已用 `WebSearch` 找到並確認其摘要與本問題症狀高度吻合，執行者需親自開啟確認完整討論內容再引用）：

- `https://github.com/readium/swift-toolkit/issues/804`（標題：Reflowable EPUB: column height not aligned to line-height clips partial last line at column boundary）
- `https://github.com/readium/readium-css/issues/141`（標題：Park support of pagination for vertical writing）

在驗證紀錄中新增：

```markdown
## 四、根因分析

**CSS 靜態證據：** 解壓 `readium-navigator:3.3.0` AAR，`assets/readium/readium-css/cjk-vertical/ReadiumCSS-after.css` 的 `:root` 規則將 `--RS__colWidth` 設為 `100vh`、`height`/`max-height`/`min-height` 皆為 `100vh`，即直排分頁的欄位（頁）尺寸完全由 CSS viewport-height 單位驅動，沒有任何機制確保 `100vh` 是行高（line-height）的整數倍。

**Upstream 已知 issue：**
- `readium/swift-toolkit#804`：（執行時填入該 issue 實際內容摘要——已知摘要方向為「WebView 的 clientHeight 若非行高整數倍，會在欄位邊界產生被裁切的半行文字，肉眼可見的效果是頁面上下緣出現字元的上半部或下半部」）
- `readium/readium-css#141`：（執行時填入該 issue 實際內容摘要——已知摘要方向為「CSS Fragmentation／多欄佈局規格本身對直排分頁的支援已被上游團隊 park（暫緩），承認目前 CSS 規格層級無法完全解決」）

**與 Task 3 重現結果的交叉比對：** （執行時依 Task 3 表格實際結果填入——若裁切僅偶發於特定頁面而非每頁固定發生，則與 #804 描述的「欄位高度非行高整數倍」症狀特徵一致，可判定為同一根因；若每頁固定裁切同一位置，需另外考慮是否為容器量測（系統列/瀏海）問題，不能直接歸因於 #804）

**結論：** （執行時填入——是否確認為 Readium/CSS 多欄分頁機制在直排書寫模式下的已知上游限制，而非本專案 `EpubReaderView.kt`/`EpubReaderView.dart` 的程式碼缺陷）
```

- [ ] **Step 3：Commit**

Run（返回專案根目錄執行 Git 指令）：
```bash
cd ..
git add docs/epics/epic-2-vertical-core/qa-issue-3-writing-mode-verification.md
git commit -m "Document root-cause analysis for vertical pagination text clipping"
cd app
```

---

### Task 5：緩解方案診斷實驗（暫時性，驗證後即還原）

**Files:**
- Temporarily modify（驗證後還原，不 commit）: `app/android/app/src/main/kotlin/cc/ugotit/elinkbook/EpubReaderView.kt`
- Modify: `docs/epics/epic-2-vertical-core/qa-issue-3-writing-mode-verification.md`

**Interfaces:**
- Consumes: Task 4 的根因假說（欄位高度由 `100vh` 驅動、與行高不對齊）
- Produces: 驗證紀錄文件新增「五、緩解方案實驗」章節，記錄 `EpubPreferences` 既有欄位（`scroll`、`lineHeight`、`pageMargins`）是否能規避裁切，供 Task 6 決策參考。

**背景：** `EpubPreferences`（`org.readium.r2.navigator.epub.EpubPreferences`，反編譯確認欄位）除了本 epic 已使用的 `verticalText` 外，還提供 `scroll: Boolean?`、`lineHeight: Double?`、`pageMargins: Double?`、`columnCount: ColumnCount?` 等欄位。`scroll = true` 會讓 Readium 改用連續捲動渲染（不分頁），完全不涉及「欄位高度」概念，若此模式下裁切消失，可強化 Task 4 的根因判斷，同時提供一個目前技術棧內就能做到的暫行方案參考。

- [ ] **Step 1：暫時修改 `setWritingMode`，加入 `scroll = true` 做對照實驗**

開啟 `app/android/app/src/main/kotlin/cc/ugotit/elinkbook/EpubReaderView.kt`，找到：

```kotlin
    private fun setWritingMode(mode: String?) {
        navigatorFragment?.submitPreferences(EpubPreferences(verticalText = mode == "vertical"))
    }
```

暫時改為（僅供本地實驗，稍後會還原）：

```kotlin
    private fun setWritingMode(mode: String?) {
        navigatorFragment?.submitPreferences(
            EpubPreferences(verticalText = mode == "vertical", scroll = true),
        )
    }
```

Run（清除快取並編譯安裝，拉取截圖時回到專案根目錄）：
```bash
flutter clean
flutter build apk --debug
flutter install -d <device-id>
adb -s <device-id> shell screencap -p /sdcard/qa-issue-3-mitigation-scroll.png
cd ..
adb -s <device-id> pull /sdcard/qa-issue-3-mitigation-scroll.png docs/epics/epic-2-vertical-core/
cd app
```
在裝置上開啟 `sample_long_vertical.epub`、切換為直排，翻閱全書，觀察是否仍有文字被上下裁切的現象；截圖記錄。

- [ ] **Step 2：還原暫時性變更**

Run（回到專案根目錄執行 Git 還原與狀態檢查）：
```bash
cd ..
git checkout -- app/android/app/src/main/kotlin/cc/ugotit/elinkbook/EpubReaderView.kt
git status
cd app
```
Expected：`git status` 顯示 `EpubReaderView.kt` 不再出現於已變更檔案清單中（工作樹乾淨，只剩驗證紀錄文件與截圖為未追蹤/已變更狀態）。

- [ ] **Step 3：記錄實驗結果**

在 `docs/epics/epic-2-vertical-core/qa-issue-3-writing-mode-verification.md` 的「四、根因分析」之後新增：

```markdown
## 五、緩解方案實驗

**實驗設計：** 暫時將 `EpubReaderView.kt` 的 `setWritingMode` 改為額外送出 `EpubPreferences(scroll = true)`，讓直排模式改用連續捲動渲染（不分頁、無欄位高度概念），觀察文字裁切現象是否消失。實驗程式碼**未提交進版控**，驗證後已用 `git checkout --` 還原。

| 實驗 | 設定 | 是否仍出現裁切 | 截圖 |
| --- | --- | --- | --- |
| A：捲動模式 | `scroll = true` | （執行時填入：是／否） | qa-issue-3-mitigation-scroll.png |

**結論：** （執行時填入——若捲動模式下裁切消失，代表根因確實出在「分頁欄位高度計算」而非其他因素，且捲動模式可作為 `epic-3-fonts-layout` 的「換頁模式（捲動 vs 無）」控制項提供使用者選擇時的一個已驗證可行的暫行方案；若捲動模式下裁切依然出現，代表根因不只是欄位高度，需要在 Task 6 的後續 issue 中要求更深入的原生渲染調查，不應直接假設是欄位高度問題）
```

- [ ] **Step 4：Commit**

Run（返回專案根目錄執行 Git 指令）：
```bash
cd ..
git add docs/epics/epic-2-vertical-core/qa-issue-3-writing-mode-verification.md docs/epics/epic-2-vertical-core/qa-issue-3-mitigation-scroll.png
git commit -m "Document scroll-mode mitigation experiment for vertical pagination clipping"
cd app
```

---

### Task 6：彙整最終結論、決策，並視需要新增後續 issue

**Files:**
- Modify: `docs/epics/epic-2-vertical-core/qa-issue-3-writing-mode-verification.md`
- Modify（僅在決策為「需要新增後續 issue」時）: `docs/epics/epic-2-vertical-core/issues.md`

**Interfaces:**
- Consumes: Task 2-5 產出的全部記錄
- Produces: Issue 3 最終驗收結論；若適用，`issues.md` 新增的 Issue 4 條目。

- [ ] **Step 1：彙整「二、結論」段落**

回到 `docs/epics/epic-2-vertical-core/qa-issue-3-writing-mode-verification.md` 的「二、結論」段落，依 Task 2 的表格結果，把佔位文字替換為以下兩種情形之一：

情形 A（FR-32 完全符合）：
```markdown
## 二、結論

符合 CNS 11643。上表六個類別的標點轉向、置中與避頭尾換行規則，實機比對結果與預期一致，`cjk-vertical` ReadiumCSS 內建的 `line-break:strict` 規則已足夠涵蓋，本項不需額外開發或覆寫。
```

情形 B（發現落差）：
```markdown
## 二、結論

發現以下落差：（執行時逐條列出差異字元、發生位置、對應截圖檔名）。已評估 Readium 是否提供 user stylesheet／樣式覆寫擴充點：（執行時填入評估結果）。是否需要新增後續 issue：（執行時填入是／否及理由）。
```

- [ ] **Step 2：依「五、緩解方案實驗」結果決策文字裁切問題的後續處理**

若 Task 5 證實根因為「分頁欄位高度非行高整數倍」（`scroll = true` 後裁切消失，且 Task 4 的 upstream issue 交叉比對吻合），在 `issues.md` 追加以下內容（開啟 `docs/epics/epic-2-vertical-core/issues.md`，於 Issue 3 區塊結尾、檔案末尾之前插入）：

```markdown
---

## Issue 4：直排分頁「欄位高度非行高整數倍」導致文字上下裁切——暫行方案評估

**Status:** ⚪ 未開始

**依賴：** Issue 3（本 issue 的根因分析與重現記錄）

**背景：** Issue 3 的實機驗證與根因調查（見 `qa-issue-3-writing-mode-verification.md`）確認：直排（vertical-RL）閱讀模式下，`readium-navigator:3.3.0` 內建的 `cjk-vertical` ReadiumCSS 把每一欄（頁）的高度設為 CSS `100vh`，未確保其為行高（line-height）的整數倍，導致某些頁面的最後一行文字被物理裁切於欄位邊界（畫面上緣或下緣出現半個字）。此為 Readium/CSS 多欄分頁機制在直排書寫模式下的已知上游限制（`readium/swift-toolkit#804`、`readium/readium-css#141`——後者顯示上游團隊已將直排分頁的完整支援 park），並非本專案 `EpubReaderView.kt`/`EpubReaderView.dart` 的程式碼缺陷，因此無法透過本專案自行維護的 user stylesheet 覆寫徹底修復（CSS Fragmentation 規格層級限制，非樣式覆寫可解決）。

**描述：** 依 Issue 3 Task 5 已驗證可行的暫行方案（`EpubPreferences(scroll = true)`），評估並設計「直排模式預設或提供選項改用捲動渲染，避免分頁欄位裁切」的具體實作方式，與 `epic-3-fonts-layout` 既有規劃的「換頁模式（捲動 vs 無）」控制項整合（不要為此另外新增一套獨立的模式切換 UI）。需要決定：(a) 直排模式是否應該預設使用捲動模式（而非現況的分頁模式）；(b) 若使用者透過 `epic-3` 的換頁模式控制項手動選擇「分頁」，是否仍要顯示裁切風險提示；(c) 是否需要監控未來 `readium-kotlin-toolkit`/`readium-css` 版本更新是否修復此上游限制，屆時可移除本暫行方案。

**單元測試要求：**
- `integration_test`（真機）：直排模式下使用捲動渲染時，翻閱 Issue 3 的 `sample_long_vertical.epub` 全書，確認無 `onError` 觸發、`onPageRendered` 正常觸發。
- 人工視覺 QA：比照 Issue 3 Task 3 的重現條件矩陣，確認捲動模式下原本會裁切的頁面不再出現裁切。

**驗收標準：**
- 已決定直排模式的預設渲染方式（分頁或捲動），並有明確理由記錄於本 issue 或對應的 `epic-3-fonts-layout` spec 中。
- 上述測試皆通過。
```

若 Task 5 未能證實此根因（`scroll = true` 後裁切依然出現），則不使用上述模板，改為在驗證紀錄的「結論」中明確記錄「需要更深入的原生渲染調查（例如檢查 WebView 版本相關已知 bug、Flutter PlatformView Texture 合成模式的尺寸量測時機），並在 `issues.md` 新增一則描述已排除可能性（欄位高度假說不成立）、要求後續 issue 從頭以 `systematic-debugging` 流程重新收斂根因」的 Issue 4，不得沿用上述模板中已被證偽的根因敘述。

- [ ] **Step 3：確認驗證紀錄與（若適用）issues.md 更新皆已完成**

Run（返回專案根目錄執行 Git 指令）：
```bash
cd ..
git diff --stat
```
Expected：顯示 `qa-issue-3-writing-mode-verification.md` 的異動，以及（若 Task 6 決策為新增後續 issue）`issues.md` 的異動；不應出現任何 `app/android`／`app/lib` 底下的殘留異動（Task 5 的暫時性程式碼已在其自身 Step 2 還原）。

- [ ] **Step 4：Commit**

Run（在專案根目錄 Commit）：
```bash
git add docs/epics/epic-2-vertical-core/qa-issue-3-writing-mode-verification.md docs/epics/epic-2-vertical-core/issues.md
git commit -m "Finalize Issue 3 verification record and log follow-up issue if needed"
```

---

## 自我審查紀錄

- **Spec 涵蓋範圍：** `issues.md` Issue 3 的兩項驗收標準——「產出驗證紀錄，明確結論『符合 CNS 11643』或『發現以下落差』」對應 Task 2/Task 6 Step 1；「若有落差且需要後續處理，已建立對應的後續 issue」對應 Task 6 Step 2。使用者本次提出的實機裁切回報，透過 Task 1（可重現的長篇 fixture）、Task 3（系統化重現矩陣）、Task 4（根因比對，含已查得的 upstream issue 佐證）、Task 5（暫行方案實驗）完整覆蓋，屬於 Issue 3 原始範圍內「驗證直排渲染」工作在真機測試中自然發現的落差，非另立無關工單。
- **佔位符掃描：** 各任務的程式碼（Python fixture 產生腳本、Kotlin 診斷實驗程式碼、`adb`/`flutter` 指令）皆為完整可執行內容；驗證紀錄文件中標註「執行時填入」的欄位是人工視覺 QA 與真機重現本質上必然存在的實測數據欄位（例如螢幕解析度、是否觀察到裁切），並非對「該做什麼」語焉不詳的佔位符——每個此類欄位在其緊鄰的 Step 中都給了明確的取得指令（`adb shell wm size` 等）與判斷準則。
- **型別/命名一致性：** 沿用 Issue 1/2 既有的 fixture 命名慣例（`sample_<描述>.epub`）；驗證紀錄檔名、截圖檔名前綴（`qa-issue-3-`）在 Task 2-6 全程一致。
- **已知、記錄在案但刻意不處理的情形：** 若裝置環境只有單一模擬器可用，Task 3 的重現矩陣允許第 4 列留空並註明原因，不阻塞本 issue 其餘結論——這與 `issues.md` Issue 3「不阻塞本 epic 其餘 issue 合併」的原則一致。
- **依 `review-plan-issue-3.md` 修訂：** Task 1 Step 2 的 Python 驗證指令改為單行寫法，避免在純 PowerShell 終端機下因多行字串與引號巢狀解析失敗；Task 4 Step 1 補上 `Expand-Archive`/`Select-String` 的 PowerShell 替代指令，供未使用 Bash 工具/git-bash 執行時的備援；全域限制條件新增截圖檔案大小檢查與裁切建議，避免未壓縮的高解析度截圖不必要地存入 git 歷史。
