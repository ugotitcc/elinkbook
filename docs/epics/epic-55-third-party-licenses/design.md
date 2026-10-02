# Epic 55 — App 授權頁登錄第三方授權：Discovery 決策

2026-10-02 `/grill-with-docs` 的結果。

## 已確認的事實

- `app/lib/screens/about_screen.dart` 用 `showLicensePage` 顯示授權，目前沒有登錄任何自訂授權。
- foliate-js 的版權行是 `Copyright (c) 2022 John Factotum`（MIT）。`zip.js` 是 `Copyright (c) 2023, Gildas Lormeau`（BSD-3-Clause）。`fflate` 是 `Copyright (c) 2026 Arjun Barrett`（MIT）。
- OpenCC 的 `LICENSE` 是 Apache-2.0 全文，沒有專屬版權行。專案內 `app/tool/opencc_data/LICENSE` 已有一份。
- Readium `kotlin-toolkit` 的版權行是 `Copyright (c) 2017, Readium`（BSD-3-Clause）。
- 5 款字型授權檔都在 `fonts-cdn/fonts/licenses/`：
  - 思源黑體、思源宋體：版權 Adobe。
  - 原俠正楷：`Copyright 2022-2025 Tony Huang`。
  - 源流明體：版權行是 Adobe（衍生自思源宋體）。
  - 台灣圓體：授權檔**沒有版權行**，直接是 OFL 條款。這是上游原檔的樣子。

## 決策

| # | 題目 | 決定 | 原因 |
|---|---|---|---|
| Q1 | 登錄範圍 | 5 項程式元件＋5 款字型，共 10 項 | 授權都要求保留聲明 |
| Q2 | 呈現位置 | 併入現有的 `showLicensePage`，不新增畫面 | 使用者找授權只會去那一頁 |
| Q3 | 授權文字來源 | 取自各上游 LICENSE 原檔，不改寫 | 改寫會失去法律效力 |
| Q4 | 台灣圓體缺版權行 | 照原檔顯示，不補寫、不猜測 | 版權人要有依據 |
| Q5 | 字型授權與字型是否已下載 | 無關，永遠顯示 | 授權頁是靜態資訊 |
| Q6 | 流程 | 開新 Epic，不併入 `epic-54` | 這是授權合規，不是架構優化 |

## 不做的事

- 不在字型管理畫面每款字型旁加授權連結。
- 不改 `fonts-cdn/` 內的授權檔。
- 不處理 Flutter／Dart 套件，Flutter 已自動收集。
