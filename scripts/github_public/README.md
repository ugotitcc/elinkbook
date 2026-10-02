# elinkBook 易閱書

這個 repo 放 elinkBook 的 Android APK 發行檔、雲端同步後端的部署檔，以及同步功能的說明文件。

- 下載：請到 [Releases](../../releases/latest)
- 官網：https://www.ugotit.cc/
- 隱私權政策：https://www.ugotit.cc/privacy
- 聯絡：app@ugotit.cc

每個版本都附 `SHA256SUMS.txt`，下載後請比對校驗值。

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

其餘 Flutter 與 Dart 套件的授權，請見 App 內「關於」頁的開源授權清單。
