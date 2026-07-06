# Issue 5 實作計劃：FR-32 避頭尾換行規則——長段落 fixture 補強與重新驗證

> **給執行的 Agent：** 建議使用 superpowers:subagent-driven-development（推薦）或 superpowers:executing-plans 逐任務執行本計劃。步驟採用核取方塊（`- [ ]`）語法追蹤進度。

**目標：** 補強 Issue 3 驗證時留下的測試覆蓋缺口——Issue 3 使用的 `sample_long_vertical.epub` fixture 全書 60 段皆為短句，段落與欄位邊界永遠精準對齊，從未真正觸發「連續文字因欄高被強制換行」的情形，導致 CNS 11643 避頭尾兩類規則（收尾類標點不可置於欄首、起頭類標點不可置於欄尾）始終無法被實際驗證。本 issue 新建一份含強制段內換行長段落的直排 CJK fixture，於真機重新視覺比對這兩類規則，產出明確結論（符合／發現落差），若有落差則依既有原則評估是否需另立後續 issue。

**架構：** 沿用 Issue 3 Task 1 已驗證的 fixture 產生手法（暫時性 Python 腳本產生 minimal EPUB zip，用畢即刪、不提交版控），但改變內容設計：不再是 60 個彼此獨立、長度皆可完整容納於單一欄位的短段落，而是**一段長度遠超單一欄位容納量的連續文字**（實測 2452 字，由 10 種句型模板循環 200 次組成，密集且均勻地安排收尾類與起頭/收尾成對標點），確保無論實際裝置/字級下單一欄位能容納多少字元，都會在段落內部發生數個強制換行點，且這些換行點附近必然存在可觀察的標點字元。真機驗證方式沿用 Issue 3 Task 2 已驗證可行的方法（`flutter build apk --debug` 安裝＋App 內既有「本機檔案匯入」流程開啟＋人工逐頁瀏覽＋`adb shell screencap` 截圖比對），不使用 `integration_test` 自動化分頁手勢（Issue 3 Task 3 已確認 `flutter test integration_test` 執行期間，模擬手勢無法可靠觸發 Readium 底層真正的分頁翻頁，見 `qa-issue-3-writing-mode-verification.md`「三、文字裁切問題重現」）。

**技術棧：** Python（僅用於一次性產生 fixture，非提交程式碼）、`pubspec.yaml`（新增 asset 註冊）、`adb`（真機安裝／推送檔案／截圖）、Readium `readium-navigator` 內建 `cjk-vertical` ReadiumCSS 的 `line-break: strict`（唯讀觀察對象，本 issue 不修改任何 production 程式碼）。

## ⚠️ 執行前環境確認事項

Task 2 的驗證步驟須在真實 Android 裝置/模擬器上執行——執行前請先確認 `flutter devices`（於 `app/` 目錄下）能列出至少一個 Android 裝置/模擬器。

**沿用 Issue 3/4 已驗證的裝置操作技巧（務必遵守，否則會重蹈先前執行過程中遇到的問題）：**
1. **Git Bash 路徑轉換陷阱：** 所有 `adb` 指令若參數包含 `/sdcard/...` 這類路徑，須在指令前加上 `MSYS_NO_PATHCONV=1` 前綴（例如 `MSYS_NO_PATHCONV=1 adb -s <device-id> shell screencap -p /sdcard/foo.png`），否則 Git Bash 的 MSYS 路徑轉換會把它改寫成錯誤的 Windows 路徑導致指令失敗。
2. **本 issue 不使用 `flutter test integration_test` 驅動真機互動**（見上方「架構」說明），因此不會遇到 Issue 3/4 記錄的「殘留 debug 連線」問題；但若 `flutter install -d <device-id>` 前裝置上已有舊版 App 處於異常狀態，先執行 `adb -s <device-id> shell am force-stop cc.ugotit.elinkbook` 再重新安裝。
3. **背景等待須設定合理逾時、逾時後直接查看實際畫面而非無限重試**：`flutter build apk --debug` 可能需要 1-3 分鐘；若等待超過 3 分鐘仍未完成，直接檢查終端機輸出判斷實際狀態。

## 全域限制條件

- 本 issue 是**驗證/研究性質**工單，不預先假設一定要動到 production 程式碼；若驗證結果符合預期，僅需產出驗證紀錄，不修改任何 `app/lib`／`app/android` 程式碼。
- 新 fixture 需具備 `dc:language=zh-TW` 與 `<html lang="zh-TW">`，比照既有 `sample_long_vertical.epub`，確保觸發 Readium 對 `:lang(zh)` 內建的 `line-break: strict` 規則（見 `docs/epics/epic-2-vertical-core/spec.md`「已驗證的技術基礎」）。
- fixture 產生腳本比照 Issue 3 Task 1 慣例：暫時性 Python 腳本，用畢即刪，不提交版控；只有產生出的 `.epub` 二進位檔案與 `pubspec.yaml` 的 asset 註冊需要提交。
- 驗證方法比照 Issue 3 Task 2 已驗證可行的手法（真機安裝 debug APK＋App 內「本機檔案匯入」流程＋人工視覺比對＋`adb shell screencap` 截圖），**不**使用 `integration_test` 自動化分頁手勢（該手法已被 Issue 3 Task 3 證實無法可靠觸發真正的分頁翻頁）。
- 驗收標準：對兩個先前未能驗證的類別（收尾類標點不可置於行首、起頭類標點不可置於行尾）產出明確結論，不得再次因 fixture 限制而懸而未決。
- 若發現落差：記錄具體差異字元、發生位置、截圖檔名；依 `spec.md`「範圍外」章節原則，具體覆寫方案的設計與實作**不在本 issue 內展開**，改為評估是否需要另立後續 issue（比照 Issue 3 決定新增 Issue 4／Issue 5 的既有模式）。
- 所有新增程式碼註解與文件維持正體中文。
- 若本 issue 過程中觸碰到任何 Dart 程式碼（目前預期僅 `pubspec.yaml`），`flutter analyze` 全程須維持 `No issues found!`。

---

### Task 1：建立含強制段內換行的直排 CJK 測試 fixture（`sample_forced_linebreak_vertical.epub`）

**Files:**
- Create: `app/test/fixtures/sample_forced_linebreak_vertical.epub`
- Modify: `app/pubspec.yaml`

**Interfaces:**
- Consumes: 無（獨立於既有 fixture，不修改 `sample_long_vertical.epub`）
- Produces: `test/fixtures/sample_forced_linebreak_vertical.epub`——`dc:language=zh-TW`、`<html lang="zh-TW">`、內含一段實測 2452 字連續文字（無內部 `<p>` 分段）的直排 CJK EPUB，供 Task 2 使用。

- [ ] **Step 1：撰寫並執行 fixture 產生腳本**

在 `app/test/fixtures/` 目錄下建立暫時腳本 `_build_forced_linebreak_fixture.py`（本步驟結束後會刪除，不會提交進版控）：

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
    <dc:identifier id="pub-id">urn:uuid:00000000-0000-0000-0000-000000000005</dc:identifier>
    <dc:title>elinkBook 直排強制換行避頭尾測試 EPUB</dc:title>
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

# 10 種句型模板，聚焦 Issue 3 尚未驗證的兩類避頭尾規則：
# 1-7：以各種收尾類標點結尾（句號、逗號、頓號、分號、冒號、問號、驚嘆號）
#      ——驗證這些標點不應該被推到下一欄的最上方（不可置於欄首）。
# 8-10：左右成對符號（引號/括號）——同時驗證起頭符號（「『（）不應
#       獨自留在欄尾（不可置於欄尾），以及收尾符號（」』）不應被推到
#       下一欄欄首（同第 1-7 類規則）。
# 刻意不重複 Issue 3 已驗證過的破折號/刪節號/書名號/一般標點置中類別。
TEMPLATES = [
    "第{n}小段以句號作結。",
    "第{n}小段以逗號作結，",
    "第{n}小段以頓號作結、",
    "第{n}小段以分號作結；",
    "第{n}小段以冒號作結：",
    "第{n}小段以問號作結？",
    "第{n}小段以驚嘆號作結！",
    "「第{n}小段測試左右引號」",
    "『第{n}小段測試另一種引號』",
    "（第{n}小段測試左右括號）",
]

# 200 個單位、平均每單位約 12 字，總長 2452 字（已實測確認）——遠超
# 一般手機在常見字級/欄寬設定下單一欄位可容納的字數，確保無論實際
# 欄位容量為何，都會在段落內部發生數個強制換行點；且因標點以約每
# 12 字的高密度均勻分布全文，任何換行點附近必然存在可觀察的收尾/
# 起頭標點。
units = []
for i in range(1, 201):
    template = TEMPLATES[(i - 1) % len(TEMPLATES)]
    units.append(template.format(n=i))

LONG_PARAGRAPH = "".join(units)

CHAPTER1 = """<?xml version="1.0" encoding="UTF-8"?>
<html xmlns="http://www.w3.org/1999/xhtml" lang="zh-TW" xml:lang="zh-TW">
<head><title>第一章</title></head>
<body>
  <h1>第一章：強制換行避頭尾測試</h1>
  <p>以下為單一長段落，用於強制觸發欄位內部換行，觀察避頭尾標點的實際渲染表現。</p>
  <p>{long_paragraph}</p>
  <p>長段落結束，以上為全部測試內容。</p>
</body>
</html>
""".format(long_paragraph=LONG_PARAGRAPH)


def build_epub(path, opf, nav, chapter1):
    with zipfile.ZipFile(path, "w") as zf:
        zf.writestr("mimetype", "application/epub+zip", compress_type=zipfile.ZIP_STORED)
        zf.writestr("META-INF/container.xml", CONTAINER_XML, compress_type=zipfile.ZIP_DEFLATED)
        zf.writestr("OEBPS/content.opf", opf, compress_type=zipfile.ZIP_DEFLATED)
        zf.writestr("OEBPS/nav.xhtml", nav, compress_type=zipfile.ZIP_DEFLATED)
        zf.writestr("OEBPS/chapter1.xhtml", chapter1, compress_type=zipfile.ZIP_DEFLATED)


build_epub("sample_forced_linebreak_vertical.epub", OPF, NAV, CHAPTER1)
print("done, long paragraph length:", len(LONG_PARAGRAPH))

# 驗證新產生的 epub 檔案
try:
    zf = zipfile.ZipFile('sample_forced_linebreak_vertical.epub')
    print([(i.filename, i.compress_type) for i in zf.infolist()])
    print(len(zf.read('OEBPS/chapter1.xhtml')), 'bytes in chapter1.xhtml')
except Exception as e:
    print("Verification failed:", e)
```

Run（於 `app/test/fixtures/` 目錄下）：
```bash
python _build_forced_linebreak_fixture.py
rm _build_forced_linebreak_fixture.py
```
Expected：印出 `done, long paragraph length: 2452`；接著印出 5 個項目（`mimetype` 的 `compress_type` 為 `0`／`ZIP_STORED` 且為第一個項目，其餘為 `8`／`ZIP_DEFLATED`），且 `chapter1.xhtml` 位元組數應遠大於 `sample_long_vertical.epub` 的同名檔案（UTF-8 編碼下長段落本身即約 6372 bytes，加上前後說明段落與 XHTML 標籤，預期總檔案大小 6500 bytes 以上）；`_build_forced_linebreak_fixture.py` 已刪除，不會被提交進版控。

- [ ] **Step 2：在 `pubspec.yaml` 註冊新 asset**

開啟 `app/pubspec.yaml`，把：

```yaml
  assets:
    - test/fixtures/sample.pdf
    - test/fixtures/sample.epub
    - test/fixtures/sample_horizontal.epub
    - test/fixtures/sample_fixed_layout.epub
    - test/fixtures/sample_long_vertical.epub
```

改為：

```yaml
  assets:
    - test/fixtures/sample.pdf
    - test/fixtures/sample.epub
    - test/fixtures/sample_horizontal.epub
    - test/fixtures/sample_fixed_layout.epub
    - test/fixtures/sample_long_vertical.epub
    - test/fixtures/sample_forced_linebreak_vertical.epub
```

若 `app/pubspec.yaml` 目前的 `assets:` 清單與上述「改為」之前的版本不完全一致（例如順序不同或已有其他項目），僅在既有清單中新增 `test/fixtures/sample_forced_linebreak_vertical.epub` 這一行，不調整既有項目順序。

- [ ] **Step 3：確認 asset 註冊無誤**

Run（於 `app/` 目錄下）：
```bash
flutter pub get
flutter analyze
```
Expected：`flutter pub get` 成功執行，無錯誤訊息；`flutter analyze` 顯示 `No issues found!`。

- [ ] **Step 4：Commit**

Run（於專案根目錄執行 Git 指令）：
```bash
git add app/test/fixtures/sample_forced_linebreak_vertical.epub app/pubspec.yaml
git commit -m "Add forced-linebreak vertical CJK EPUB fixture for FR-32 re-verification"
```

---

### Task 2：FR-32 避頭尾兩類規則人工視覺重新驗證（真機）

**Files:**
- Create: `docs/epics/epic-2-vertical-core/qa-issue-5-fr32-forced-linebreak-verification.md`

**Interfaces:**
- Consumes: Task 1 的 `sample_forced_linebreak_vertical.epub`
- Produces: 驗證紀錄文件，供 Task 3 彙整最終結論時引用。

本 task 是**人工視覺 QA 性質**，沒有自動化測試（比照 Issue 3 Task 2 的驗證方法，理由見計劃開頭「架構」段落）。

- [ ] **Step 1：建立驗證紀錄文件骨架**

建立 `docs/epics/epic-2-vertical-core/qa-issue-5-fr32-forced-linebreak-verification.md`：

```markdown
# Issue 5 驗證紀錄：FR-32 避頭尾兩類規則——強制換行長段落重新驗證

依 `docs/epics/epic-2-vertical-core/issues.md` Issue 5 與
`docs/epics/epic-2-vertical-core/plans/plan-issue-5.md` 產出。

## 測試環境

| 項目 | 值 |
| --- | --- |
| 裝置/模擬器型號 | （執行時填入 `adb shell getprop ro.product.model` 的輸出） |
| Android 版本 | （執行時填入 `adb shell getprop ro.build.version.release` 的輸出） |
| App 建置方式 | `flutter build apk --debug`（本機組建，未簽章 release） |

## 一、FR-32 避頭尾兩類規則比對（Issue 3 未能驗證的部分）

**方法：** 於裝置上安裝 debug APK，透過 App 內既有「本機檔案匯入」流程開啟
`sample_forced_linebreak_vertical.epub`，切換為直排模式，逐頁瀏覽至長段落所在
頁面，對照下表兩類 CNS 11643 避頭尾規則，記錄實際渲染結果；每一類別若觀察到
可能的落差，附上對應截圖檔名。

| 類別 | 代表字元 | 規則 | 觀察結果（符合／不符合＋說明＋截圖檔名） |
| --- | --- | --- | --- |
| 收尾類標點不可置於行首 | 」』）、。，；：？！ | 不可出現在下一欄（頁）的最上方 | |
| 起頭類標點不可置於行尾 | 「『（ | 不可出現在欄（頁）的最下方 | |

## 二、結論

（符合 CNS 11643 ／發現以下落差：……——由 Task 3 彙整填入最終結論）
```

- [ ] **Step 2：安裝 debug APK 並推送 fixture 到裝置**

Run（於 `app/` 目錄下；`<device-id>` 替換為 `flutter devices` 列出的實際裝置 ID）：
```bash
flutter build apk --debug
flutter install -d <device-id>
MSYS_NO_PATHCONV=1 adb -s <device-id> push test/fixtures/sample_forced_linebreak_vertical.epub /sdcard/Download/sample_forced_linebreak_vertical.epub
```
Expected：三個指令皆成功執行無錯誤（`flutter build apk --debug` 首次冷建置約 1-3 分鐘）。

- [ ] **Step 3：於裝置上手動匯入並瀏覽比對**

在裝置上手動開啟 App、進入書架畫面，點擊右上角「匯入書籍」按鈕（`library_import_button`）→「匯入檔案」（`library_import_files_option`），於系統檔案選擇器中導覽至 `/sdcard/Download/` 選取 `sample_forced_linebreak_vertical.epub` 完成匯入，點擊進入該書的閱讀畫面。

開啟後按下 AppBar 的橫直排切換按鈕（`reader_writing_mode_toggle`）確認目前為直排模式（沿用既有 fixture 慣例，`lang="zh-TW"` 書籍預設應自動判定為直排；若初始已是直排則不需點擊）。逐頁翻閱直到長段落所在頁面（依 fixture 內容順序，長段落緊接在第一段簡短說明文字之後，應在前 1-2 頁內即可看到），觀察每一次分頁（換欄）發生的位置：

- 檢查每一欄的**最上方**字元：是否曾出現收尾類標點（」』）、。，；：？！）獨自出現在欄位最上方、而非留在前一欄的結尾。
- 檢查每一欄的**最下方**字元：是否曾出現起頭類標點（「『（）獨自出現在欄位最下方、而非被推至下一欄開頭。

對每一個換欄點，若懷疑有不符合避頭尾規則的情形，執行：
```bash
MSYS_NO_PATHCONV=1 adb -s <device-id> shell screencap -p /sdcard/qa-issue-5-fr32-<編號>.png
MSYS_NO_PATHCONV=1 adb -s <device-id> pull /sdcard/qa-issue-5-fr32-<編號>.png docs/epics/epic-2-vertical-core/
```
把截圖存放於 `docs/epics/epic-2-vertical-core/`（與驗證紀錄同目錄，檔名前綴 `qa-issue-5-fr32-`），在 Step 1 建立的表格「觀察結果」欄位中填入比對結論與對應截圖檔名（若該類別完全符合預期、未觀察到任何落差，仍建議附上至少一張顯示正常換欄行為的截圖作為佐證）。

Expected：完成表格兩列的填寫，各自明確記錄「符合」或「發現以下落差：具體字元＋位置＋截圖檔名」。

- [ ] **Step 4：清理裝置端暫存檔案**

Run：
```bash
MSYS_NO_PATHCONV=1 adb -s <device-id> shell rm /sdcard/Download/sample_forced_linebreak_vertical.epub
adb -s <device-id> shell am force-stop cc.ugotit.elinkbook
git status --short
```
Expected：`git status --short` 顯示本次新增的 QA 紀錄與截圖檔案（若有），工作樹沒有其他暫時性殘留。

- [ ] **Step 5：Commit**

Run（於專案根目錄執行 Git 指令）：
```bash
git add docs/epics/epic-2-vertical-core/qa-issue-5-fr32-forced-linebreak-verification.md
git add docs/epics/epic-2-vertical-core/qa-issue-5-fr32-*.png 2>/dev/null || true
git commit -m "Document FR-32 forced-linebreak verification for Issue 5"
```

---

### Task 3：彙整最終結論、決策，並視需要新增後續 issue

**Files:**
- Modify: `docs/epics/epic-2-vertical-core/qa-issue-5-fr32-forced-linebreak-verification.md`
- Modify: `docs/epics/epic-2-vertical-core/issues.md`

**Interfaces:**
- Consumes: Task 1-2 完成的全部成果
- Produces: Issue 5 最終驗收結論

- [ ] **Step 1：彙整驗證紀錄的「結論」段落**

開啟 `docs/epics/epic-2-vertical-core/qa-issue-5-fr32-forced-linebreak-verification.md`，依 Task 2 表格的實際觀察結果，把「二、結論」段落的佔位文字：

```markdown
（符合 CNS 11643 ／發現以下落差：……——由 Task 3 彙整填入最終結論）
```

改為以下其中一種（依實際結果擇一填入，須為完整、明確的結論陳述，不得保留任何「待補」字樣）：

- 若兩類皆符合預期：
  ```markdown
  兩類規則皆符合 CNS 11643 預期：收尾類標點（」』）、。，；：？！）從未獨自出現於欄位最上方，起頭類標點（「『（）從未獨自出現於欄位最下方。至此，Issue 3「一、FR-32 標點轉向與避頭尾比對」表格中六類規則已全數完成驗證，四類（破折號、刪節號、書名號、一般標點置中）於 Issue 3 驗證，另兩類（收尾/起頭類避頭尾）於本 issue 補強驗證，FR-32 驗證範圍已完整覆蓋，無需新增後續修復 issue。
  ```
- 若發現落差：
  ```markdown
  發現以下落差：[具體字元]在[具體位置，例如「第 N 次換欄」]被觀察到違反避頭尾規則，詳見 Step 2 表格與對應截圖 [檔名]。已依 `spec.md`「範圍外」章節原則評估：[評估結論，例如「屬於 Readium user stylesheet 覆寫可處理的範圍，已新增 Issue N 追蹤具體覆寫方案設計與實作」或「屬於上游 Readium/ReadiumCSS 限制，比照 Issue 4 的處理方式記錄為已知限制，暫不修復」]。
  ```

- [ ] **Step 2：更新 Issue 5 的驗收狀態**

開啟 `docs/epics/epic-2-vertical-core/issues.md`，找到 Issue 5 區塊的 `**Status:** ⚪ 未開始`，改為：

```markdown
**Status:** ✅ 已完成。使用 Task 1 新建的 `sample_forced_linebreak_vertical.epub`（單一長段落 2452 字，密集安排收尾/起頭類標點，確保觸發欄位內部強制換行）重新驗證 Issue 3 遺留的兩類 FR-32 避頭尾測試覆蓋缺口。[執行時依 Step 1 的實際結論，二擇一填入：「驗證結果：兩類規則皆符合 CNS 11643 預期，FR-32 六類避頭尾/標點規則驗證範圍至此全數完整覆蓋。」或「驗證結果：發現落差（[具體字元與位置]），已新增 Issue N 追蹤後續修復。」]驗證紀錄見 `qa-issue-5-fr32-forced-linebreak-verification.md`。
```

- [ ] **Step 3：確認全域限制條件皆已滿足**

Run（於 `app/` 目錄下）：
```bash
flutter analyze
flutter test
```
Run（於專案根目錄下）：
```bash
git status --short
```
Expected：`flutter analyze` 顯示 `No issues found!`；`flutter test` 全數通過，無回歸；`git status --short` 除了本次要 commit 的檔案外，工作樹乾淨（確認 Task 1 的暫時性 Python 腳本已不存在）。

- [ ] **Step 4：Commit**

```bash
git add docs/epics/epic-2-vertical-core/qa-issue-5-fr32-forced-linebreak-verification.md docs/epics/epic-2-vertical-core/issues.md
git commit -m "Finalize Issue 5: FR-32 forced-linebreak verification conclusion"
```

---

## 自我審查紀錄

- **Spec 涵蓋範圍：** Issue 5 描述的「新增（或擴充既有）一份直排 CJK fixture，其中至少包含一段足夠長的連續文字」對應 Task 1；「以此 fixture 重新執行 Issue 3 未能驗證的兩個類別」對應 Task 2；「產出補充驗證紀錄，明確結論」與「若發現落差，依相同原則決定是否需要新增後續修復 issue」對應 Task 3。單元測試要求（人工視覺 QA、`adb shell screencap` 截圖 + 逐字元比對）對應 Task 2 的執行方法，與 Issue 3 Task 2 保持一致。
- **佔位符掃描：** 所有步驟皆含完整程式碼、明確指令與預期輸出；Task 2 驗證紀錄範本與 Task 3 的「結論」二選一範本中標註「執行時填入」/「依實際結果擇一填入」的欄位，屬於人工視覺 QA 本質上必然存在的實測數據欄位（與 Issue 3/4 QA 紀錄的既有慣例一致），非語焉不詳的佔位符——兩種可能結論皆已提供完整範例文字，執行者只需依實測結果二擇一填入具體內容，不存在「留白」的情形。
- **型別/命名一致性：** 新 fixture 檔名 `sample_forced_linebreak_vertical.epub`、QA 紀錄檔名 `qa-issue-5-fr32-forced-linebreak-verification.md`、截圖前綴 `qa-issue-5-fr32-` 全程一致，且與既有 `sample_long_vertical.epub`／`qa-issue-3-fr32-*` 的命名慣例保持可辨識的家族相似性（同為 `sample_*_vertical.epub` 與 `qa-issue-N-fr32-*` 模式）。
- **與 Issue 3/4 既有結論的關係：** 本計劃明確排除重新測試 Issue 3 已驗證通過的四類規則（破折號、刪節號、書名號、一般標點置中），僅聚焦兩個真正未驗證的類別，避免重複勞動；驗證方法刻意選用 Issue 3 Task 2 已證實可行的真機手動流程，而非 Issue 3 Task 3 已證實不可靠的 `integration_test` 自動化分頁手勢，降低本計劃執行時重蹈覆轍的風險。
- **已知、記錄在案但刻意不處理的情形：** 若 Task 3 的結論是「發現落差」，本計劃刻意不在 Issue 5 範圍內展開具體覆寫方案的設計與實作（比照 `spec.md`「範圍外」章節與 Issue 3 的既有處理原則），改為視落差性質決定是否新增後續 issue——這是刻意的範圍界線，不是遺漏。
