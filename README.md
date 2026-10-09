# elinkBook 易閱書

這個 repo 放 elinkBook 的 Android APK 發行檔、雲端同步後端的部署檔，以及同步功能的說明文件。

- 下載：請到 [Releases](https://github.com/ugotitcc/elinkbook/releases/latest)
- 官網：https://www.ugotit.cc/
- 隱私權政策：https://www.ugotit.cc/privacy
- 聯絡：app@ugotit.cc

每個版本都附 `SHA256SUMS.txt`，下載後請比對校驗值。

## 該下載哪個檔案

每個版本提供 4 個 APK，內容相同，差別在支援的 CPU 類型：

| 檔案 | 大小 | 適用 |
|---|---|---|
| `elinkbook-<版本>-arm64-v8a.apk` | 約 57 MB | 多數近年的 Android 手機。不確定時選這個 |
| `elinkbook-<版本>-armeabi-v7a.apk` | 約 54 MB | 較舊的 32 位元 Android 裝置 |
| `elinkbook-<版本>-x86_64.apk` | 約 59 MB | x86 模擬器或少數 x86 裝置 |
| `elinkbook-<版本>.apk`（共用檔） | 約 115 MB | 所有裝置。不想挑檔案時選這個，但檔案較大 |

如果裝置顯示「與目前已安裝的版本不相容」，請改選另一個檔案，或先解除安裝舊版。

## 同步後端

elinkBook 的雲端同步使用 [PocketBase](https://pocketbase.io/)。你可以自己架設，資料只存在你的伺服器。

- [`docker/`](docker/)：用 Docker 部署 PocketBase。從 [`docker/README.md`](docker/README.md) 開始看。

## 文件

- [`docs/sync-protocol.md`](docs/sync-protocol.md)：同步協定與 Collection 欄位定義。
- [`docs/research/synology_dsm7_pocketbase_sop.md`](docs/research/synology_dsm7_pocketbase_sop.md)：Synology DSM 7 部署手冊。
- [`docs/research/oracle_cloud_pocketbase_sop.md`](docs/research/oracle_cloud_pocketbase_sop.md)：Oracle Cloud 部署手冊。

## 授權

[`LICENSE`](LICENSE)（MIT）只涵蓋 `docker/` 與 `docs/` 內的檔案。APK 發行檔不在此授權範圍。

## 使用的開源元件

APK 內含以下開源元件，版權與授權如下：

| 元件 | 授權 | 版權 |
|---|---|---|
| [readest/foliate-js](https://github.com/readest/foliate-js) | MIT | Copyright (c) 2022 John Factotum |
| [zip.js](https://github.com/gildas-lormeau/zip.js) | BSD-3-Clause | Copyright (c) 2023, Gildas Lormeau |
| [fflate](https://github.com/101arrowz/fflate) | MIT | Copyright (c) 2026 Arjun Barrett |
| [OpenCC](https://github.com/BYVoid/OpenCC)（簡繁字元對照表） | Apache-2.0 | BYVoid/OpenCC 專案貢獻者 |
| [Readium kotlin-toolkit](https://github.com/readium/kotlin-toolkit) | BSD-3-Clause | Copyright (c) 2017, Readium |

其餘 Flutter 與 Dart 套件的授權，請見 App 內「關於」頁的開源授權清單。

## 可下載字型

字型檔不包含在 APK 內，由使用者在 App 的字型管理下載。7 款皆為 SIL Open Font License 1.1（OFL），可商用、可再散布。

| 字型 | 授權 | 版權 |
|---|---|---|
| 思源黑體（Source Han Sans） | SIL OFL 1.1 | Copyright 2014-2025 Adobe |
| 思源宋體（Source Han Serif） | SIL OFL 1.1 | Copyright 2017-2022 Adobe |
| 原俠正楷（GuanKiapTsingKhai） | SIL OFL 1.1 | Copyright 2022-2025 Tony Huang |
| 源流明體（GenRyuMin） | SIL OFL 1.1 | Copyright 2014-2019 Adobe（衍生自思源宋體） |
| 台灣圓體（TaiwanPearl） | SIL OFL 1.1 | 上游授權檔未載明版權人 |
| 白鷺楷（BailuKai） | SIL OFL 1.1 | Copyright 2022-2025 Tony Huang；Copyright 2026 Hu Yen-Chuan（衍生自原俠正楷） |
| 獅尾B2加糖宋體（SweiB2Sugar） | SIL OFL 1.1 | 上游授權檔未載明版權人 |
