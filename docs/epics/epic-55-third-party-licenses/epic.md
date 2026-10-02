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
