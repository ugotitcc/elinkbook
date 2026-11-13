# `epic-55-third-party-licenses` App 授權頁登錄第三方授權（含可下載字型）

**狀態：** 🟡 開發中 (Active)
**存放路徑：** `docs/epics/epic-55-third-party-licenses/`
**關聯文件：** `docs/epics/epic-55-third-party-licenses/design.md`、`spec.md`、`issues.md`

## 背景

App 的「關於 → 開源授權」用 Flutter 的 `showLicensePage`。這個頁面只會列出 Dart 套件的授權。

APK 內還有 5 項不是 Dart 套件的元件，授權不會出現在頁面上：

- `readest/foliate-js`（MIT）、`zip.js`（BSD-3-Clause）、`fflate`（MIT）：放在 `app/android/app/src/main/assets/foliate/`。
- OpenCC 簡繁字元對照表（Apache-2.0）：編進 `text_conversion_dict.js`。
- Readium `kotlin-toolkit`（BSD-3-Clause）：`readium-shared`、`readium-streamer` 兩個 Android 相依。

另外有 5 款可下載字型。它們不在 APK 內，但由使用者在 App 內下載，授權是 SIL OFL 1.1。授權檔在 `fonts-cdn/fonts/licenses/`。

這些授權都要求「散布時保留版權與授權聲明」。這個 Epic 讓 App 授權頁顯示它們。

## 開發記錄

**2026-10-02 `/grill-with-docs` Discovery**

- 起因：官網與 GitHub 公開後，檢查 APK 內含的開源元件，發現授權頁不完整。
- 決策細節見 `design.md`，介面見 `spec.md`，拆成 2 個 Issue，見 `issues.md`。
- 同次已完成的文件更正（不屬於本 Epic）：
  - GitHub 公開 README 補上 5 項元件與 5 款字型的授權表。
  - `README.md`、`CLAUDE.md`、`docs/prd.md` 的「商用授權字型」改為「SIL OFL 開源字型」。
  - ADR 0011、0013、0018 補上指向 ADR 0024、0025 的註記。

**2026-10-02 Issue 1 已合併（PR #308）**

- 新增 `registerThirdPartyLicenses` 與 5 項程式元件授權（foliate-js、zip.js、fflate、OpenCC、Readium kotlin-toolkit），`main.dart` 啟動時登錄；真機驗收通過。
- 計畫審查採納 5 項、不採納 1 項（為 `ThirdPartyLicense` 補 `==`／`hashCode`，屬投機彈性）。
- 規格外追加：授權頁以 `applicationLegalese` 顯示「本 App 使用下列開源元件…」說明（新增 ARB 鍵 `aboutScreenLicensesLegalese`），避免「Powered by Flutter」讓人誤以為清單全是 Flutter 元件。

**2026-10-02 Issue 2 已合併（PR #309）**

- 5 款可下載字型（思源黑體、思源宋體、原俠正楷、台灣圓體、源流明體）的 SIL OFL 1.1 授權登錄進授權頁，與字型是否已下載無關；授權頁共 10 項，真機驗收通過。
- 計畫審查：採納 M-2、M-3，M-1 部分採納（只加 `caseSensitive: false`；審查建議的 `^s*Copyright` 會命中原檔 OFL 條款本文的 `Copyright Holder` 行，故不採）。
- 設計修訂（Q4）：台灣圓體上游授權檔仍無版權行、不補寫版權人與年份；依其 README「著作權與授權」段，在授權全文之後附加一段來源說明（改作自 Adobe／Google 的思源黑體，並取用小杉圓體部分中文字），標明非 OFL 條款的一部分。`design.md` Q4 與 `spec.md` 已同步修訂。
- 一致性測試比對 asset 與 `fonts-cdn` 原檔時先正規化行尾（git 索引為 LF、Windows 工作目錄為 CRLF）。

**2026-10-09 Issue 3 已合併（PR #341）（`/grill-with-docs`）：新增白鷺楷與獅尾B2加糖宋體兩款可下載字型**

- 起因：使用者要增加兩款字型。字型授權登錄屬本 Epic 範圍，依「不要一個問題開一個 Epic」原則併入。
- 白鷺楷衍生自原俠正楷（OFL 1.1）。原 repo `huthief/BailuKai` 沒有授權檔，先補上 `OFL.txt`（保留原俠版權行與 Reserved Font Names）才收進來。
- 獅尾B2加糖宋體衍生自思源宋體（OFL 1.1），上游授權檔沒有版權行，比照台灣圓體在 asset 末尾附來源說明。
- 只收橫排版 `BailuKai-Medium.ttf`，不收偽直排 `-90` 版（閱讀器已有原生直排，會轉兩次）。
- 清單順序接在最後，不動既有字型位置。兩款檔案都小於 30MB，舊 WebView 也會列出。
- 發布路徑用 `v1/`（只新增、不覆蓋）。
- 字型檔已上傳 R2（`v1/`），`verify_remote.mjs` 7 款一致；TCL 14 真機驗證通過。
- 完整 `flutter test` 有 3 個 PDF 沉浸模式測試失敗（`reader_screen_test.dart`），不碰字型、單獨執行全過，疑為整套同時跑的時序問題，未在 `main` 上重跑確認。
