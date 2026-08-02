# PocketBase 自架 SOP（elinkBook 雲端同步）

本文件供自行架設 elinkBook 雲端同步後端使用，對照
[`spec.md`](spec.md)「PocketBase Collection Schema」／「墓碑清理」／
「同步引擎」撰寫。伺服器部署本身（雲端主機選擇、網域/HTTPS 憑證等）
不在本文件範圍內（見 `design.md`「明確排除」），本文件只涵蓋「PocketBase
本身要怎麼裝、怎麼設定成 elinkBook 可用的狀態」。

## 最低版本需求

- **PocketBase ≥ 0.23**（App 端 checkpoint 同步依賴 Batch API `/api/batch`，
  該端點需要這個版本以上才有）。
- 建議實際使用時直接抓
  [GitHub Releases](https://github.com/pocketbase/pocketbase/releases)
  最新穩定版，不需要刻意鎖在 0.23——本文件撰寫當下最新版本為
  `0.39.10`，後續章節的指令皆以此版本號示範，自架時請自行替換成當時的
  最新版本號。

## 啟動方式

PocketBase 官方只發布單一可執行檔（不含任何官方 Docker image，見
[GitHub Releases](https://github.com/pocketbase/pocketbase/releases)
與[官方文件](https://pocketbase.io/docs/)——皆未提供任何容器映像）。
以下提供兩種啟動方式，擇一即可。

### 選項 A：直接執行（最簡單，官方唯一直接支援的方式）

```bash
# Linux amd64 範例，其他平台請至 Releases 頁面換成對應檔名
# （例如 darwin_arm64／windows_amd64／linux_arm64）
curl -LO https://github.com/pocketbase/pocketbase/releases/download/v0.39.10/pocketbase_0.39.10_linux_amd64.zip
unzip pocketbase_0.39.10_linux_amd64.zip -d pocketbase
cd pocketbase
./pocketbase serve
```

啟動後終端機會顯示類似：

```
Server started at http://127.0.0.1:8090
├─ REST API:  http://127.0.0.1:8090/api/
└─ Dashboard: http://127.0.0.1:8090/_/
```

### 選項 B：自製最小 Dockerfile（非官方映像，自行容器化用）

```dockerfile
FROM alpine:3.20
ARG PB_VERSION=0.39.10
RUN apk add --no-cache unzip ca-certificates && \
    wget https://github.com/pocketbase/pocketbase/releases/download/v${PB_VERSION}/pocketbase_${PB_VERSION}_linux_amd64.zip && \
    unzip pocketbase_${PB_VERSION}_linux_amd64.zip -d /pb && \
    rm pocketbase_${PB_VERSION}_linux_amd64.zip
EXPOSE 8090
VOLUME /pb/pb_data
ENTRYPOINT ["/pb/pocketbase", "serve", "--http=0.0.0.0:8090"]
```

```bash
docker build -t elinkbook-pocketbase .
docker run -d --name elinkbook-pocketbase -p 8090:8090 -v $(pwd)/pb_data:/pb/pb_data elinkbook-pocketbase
```

### 首次啟動：建立管理員帳號

不論選哪個選項，首次啟動後瀏覽器開啟 `http://127.0.0.1:8090/_/`
會要求建立第一個管理員帳號（email + 密碼），這是 **PocketBase 管理員
帳號**，與 App 使用者的 elinkBook 同步帳號（PocketBase Auth `users`
collection）是完全不同的兩件事，不要混淆。
