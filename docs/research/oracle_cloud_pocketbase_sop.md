# Oracle Cloud Free Tier (OCI) 部署 PocketBase (elinkBook 雲端同步) 完整 SOP 手冊

本手冊指導如何在 **Oracle Cloud Infrastructure (OCI) Always Free（永久免費層）** 上，從零申請帳號、建立雲端虛擬機 (Compute VM)、設定網路與防火牆、到使用 **Docker + Docker Compose + Traefik 反向代理（自動 Let's Encrypt SSL）** 完整部署 [PocketBase](https://pocketbase.io/) 後端服務，專供 **elinkBook** 電子書閱讀器之雲端同步功能（閱讀位置、書籤、劃線、畫線備註）使用。

本手冊整合了專案現有架構標準（[`docs/research/synology_dsm7_pocketbase_sop.md`](synology_dsm7_pocketbase_sop.md) 與 [`docker/README.md`](../../docker/README.md)；Collection 欄位與同步流程見 [`docs/sync-protocol.md`](../sync-protocol.md)），針對 Oracle Cloud 雲端環境與公網 HTTPS 需求提供完整端到端教學。

---

## 1. 前置概念與架構總覽

### 1.1 系統架構拓撲

```text
+-------------------------------------------------------------------------+
|                        elinkBook Android App                            |
|                 (Base URL: https://sync.yourdomain.com)                 |
+-------------------------------------------------------------------------+
                                     │ (HTTPS / Port 443)
                                     ▼
+-------------------------------------------------------------------------+
|                  Oracle Cloud Infrastructure (OCI)                      |
|                                                                         |
|  [ VCN Security List: Ingress 80 (HTTP), 443 (HTTPS), 22 (SSH) ]        |
|                                    │                                    |
|                                    ▼                                    |
|  [ Ubuntu VM Host: iptables / ufw 放行 80, 443, 22 ]                    |
|                                    │                                    |
|  [ Docker Network: web (內部隔離橋接網路) ]                               |
|   ├── Traefik v3 (反向代理容器)                                         |
|   │   ├── 監聽 Host :80 (自動 301 重定向至 HTTPS :443)                    |
|   │   ├── 監聽 Host :443 (Let's Encrypt 自動申請與續約 ACME SSL 憑證)     |
|   │   └── 內部路由轉發 -> pocketbase:8090                                |
|   │                                                                     |
|   └── PocketBase 容器 (elinkBook 同步引擎)                              |
|       ├── 僅暴露於 Docker 內部網路 (Port 8090 不對公網開放，保障安全)    |
|       ├── 掛載 pb_data (SQLite data.db 持久化資料庫)                     |
|       ├── 掛載 pb_migrations (elinkBook 專屬 4 大 Collection 自動建表)   |
|       └── 掛載 pb_hooks (每日凌晨 30 天軟刪除墓碑自動清理排程)           |
+-------------------------------------------------------------------------+
```

### 1.2 OCI Always Free 規格與選型

Oracle Cloud 提供業界最慷慨的永久免費額度（Always Free）：
- **ARM64 (Ampere A1 Flex)**：最高提供 **4 OCPU、24 GB 記憶體** 與 200 GB 磁碟空間。本指南以此為**主要推薦**（建議配置 1~2 OCPU、6~12 GB RAM，足夠運行 PocketBase 及未來擴充多項個人服務）。
- **AMD64 (VM.Standard.E2.1.Micro)**：提供 2 台 1/8 OCPU、1 GB 記憶體實例。若特定熱門區域（如東京、首爾）ARM64 出現「Out of Host Capacity（主機容量不足）」時，可無痛降級套用本指南之 AMD64 備用配置。
- **公網 IP**：提供 1 個免費保留固定公網 IP (Reserved Public IP)。

### 1.3 核心元件最低版本需求
- **PocketBase**：必須 **≥ v0.23**（elinkBook checkpoint 同步引擎依賴 Batch API `/api/batch`）。本指南示範使用 **v0.40.4**（自架時亦可無痛替換為最新穩定版）。
- **Traefik**：v3.6 以上官方容器映像檔。較舊的 v3.1 搭配最新 Docker Engine（29 以上）可能無法連上 Docker socket。
- **版號確認**：部署前先到 [PocketBase Releases](https://github.com/pocketbase/pocketbase/releases) 確認 `PB_VERSION` 對應的版本存在，否則 Dockerfile 下載會失敗。
- **作業系統**：Ubuntu 24.04 LTS 或 22.04 LTS Minimal。

---

## 2. 步驟一：Oracle Cloud 帳號申請與避坑指南

Oracle Cloud 註冊審核極為嚴格，常見「Transactions Failed」或註冊後立即被風控鎖號。請務必遵守以下避坑準則：

### 2.1 註冊前置準備清單
1. **信用卡／簽帳卡**：
   - 必須使用支援國際交易的**實體 Visa / Mastercard 雙幣信用卡或簽帳金融卡**。
   - **絕對不要使用**：虛擬信用卡（如 Revolut 虛擬卡、網銀拋棄式卡片）、預付卡、商務虛擬卡（極高機率秒拒絕）。
   - 註冊時系統會發起約 1 美元／新加坡幣之小額預授權驗證扣款（隨後會自動刷退或解除保留額度）。
2. **乾淨的網路環境**：
   - 註冊全程**切勿開啟 VPN、代理伺服器、Tor 或任何出國網路**。
   - 建議使用家中固網（中華電信寬頻）或手機原生行動數據連線。
3. **資料一致性**：
   - 填寫的英文姓名、英文居住地址、郵遞區號，必須與該信用卡帳單地址完全一致。
   - 建議前往中華郵政網站查詢標準英譯地址。
4. **主區域 (Home Region) 選擇**：
   - **注意：Home Region 一旦註冊完成「永久無法變更」**。
   - 推薦區域（低延遲）：
     - 亞洲：`Japan East (Tokyo)`、`Japan Central (Osaka)`、`Singapore (Singapore)`。
     - 美洲（資源最充足、最少缺貨）：`US West (San Jose)`、`US West (Phoenix)`。
   - 若您居住於台灣/香港，連線首選為東京或新加坡；若遭遇 ARM 容量長期不足，美西亦是極佳的備選。

### 2.2 註冊操作流程
1. 前往 [Oracle Cloud Free Tier 官網](https://www.oracle.com/cloud/free/)，點擊 **Start for free**。
2. 填寫國家/地區、姓名及個人常用 Email。
3. 收取驗證信並設定密碼。
4. 在「Account Type」選擇 **Individual**，並設定租戶名稱（Cloud Account Name）。
5. 謹慎選擇 **Home Region**。
6. 填寫英譯地址與電話。
7. 進入付款資訊驗證，輸入信用卡卡號完成 3D 驗證。
8. 勾選服務協議，點擊 **Complete Sign-Up**。等待 5~15 分鐘租戶建立完成通知信。

### 2.3 關鍵避坑：防止 Always Free VM 被判定閒置回收策略

> [!WARNING]
> **官方閒置回收政策**：Oracle 規定，Always Free 運算實例若連續 7 天處於「閒置」，可能被回收。
> 判定條件（CPU 第 95 百分位、網路、記憶體是否低於 20%，以及哪些條件適用哪種 Shape）
> 以 [Oracle 官方 Always Free 文件](https://docs.oracle.com/en-us/iaas/Content/FreeTier/freetier_topic-Always_Free_Resources.htm) 為準。本手冊不複述門檻數字。

#### 防回收方案 A（推薦）：升級為 PAYG（隨收隨付）
1. 登入 OCI 控制台，進入 **Account Management → Billing & Payment → Upgrade**。
2. 升級至 **Pay As You Go (PAYG)**。
3. 綁定信用卡時，Oracle 會先做一筆預授權驗證。金額與退還時間以升級頁面顯示為準。
4. 升級後，Always Free 額度內的資源仍然是 0 元。超出額度的資源才會計費。
5. **立刻設定預算警示**：進入 **Billing & Cost Management → Budgets**，建立月預算（例如 1 美元），並設定超過 1 美元就寄信。這樣誤開付費資源時能馬上發現。
6. 是否能完全避免回收，請以 Oracle 官方文件為準。

#### 方案 B：不升級 PAYG
本手冊**不提供**保活腳本。單靠定時腳本很難可靠地拉高 7 天的 CPU 第 95 百分位。
如果不升級，請接受「VM 可能被回收」的風險，並確實做好第 9.1 節的備份，且把備份複製到 VM 以外的地方。

---

## 3. 步驟二：建立虛擬雲端網路 (VCN) 與開放防火牆

### 3.1 建立 VCN（若無現成預設網路）
1. 登入 OCI 控制台，點擊左上角漢堡選單 **Networking → Virtual cloud networks**。
2. 點擊 **Start VCN Wizard**，選擇 **Create VCN with Internet Connectivity**。
3. 輸入名稱（例如 `elinkbook-vcn`），其餘維持預設（VCN CIDR: `10.0.0.0/16`，Public Subnet CIDR: `10.0.0.0/24`），點擊 **Next → Create**。

### 3.2 配置 VCN 安全清單 (Security List Ingress Rules)
OCI 的虛擬防火牆預設僅開放 Port 22，必須手動放行 HTTP (80) 與 HTTPS (443)：
1. 進入剛建立的 VCN，點擊左側 **Security Lists**，點入 **Default Security List for elinkbook-vcn**。
2. 點擊 **Add Ingress Rules**，新增兩筆入站規則：
   - **規則 1 (HTTP - 供 Traefik 憑證挑戰與 80 轉向)**：
     - Source Type: `CIDR`
     - Source CIDR: `0.0.0.0/0`
     - IP Protocol: `TCP`
     - Destination Port Range: `80`
     - Description: `Allow HTTP for Traefik ACME Challenge`
   - **規則 2 (HTTPS - 供 elinkBook App 加密同步)**：
     - Source Type: `CIDR`
     - Source CIDR: `0.0.0.0/0`
     - IP Protocol: `TCP`
     - Destination Port Range: `443`
     - Description: `Allow HTTPS for elinkBook PocketBase Sync`
3. 點擊 **Add Ingress Rules** 儲存。

### 3.3 申請保留固定公網 IP (Reserved Public IP)
避免 VM 重啟後公網 IP 異動導致網域解析失效：
1. 前往 **Networking → IP management → Reserved Public IPs**。
2. 點擊 **Reserve public IP address**。
3. 名稱輸入 `elinkbook-ip`，確認為「Always Free」免費項目，點擊 **Reserve**。
4. 記下核發的 IP 位址（例如 `129.150.x.x`）。

---

## 4. 步驟三：建立並配置 Ubuntu 運算實例 (Compute VM)

### 4.1 建立 Compute Instance
1. 前往 **Compute → Instances**，點擊 **Create instance**。
2. **名稱 (Name)**：輸入 `elinkbook-server`。
3. **Placement & Availability Domain**：維持預設。
4. **Image and Shape**：
   - 點擊 **Change image**：選擇 **Canonical Ubuntu**，版本選擇 **24.04** 或 **22.04 Minimal**。
   - 點擊 **Change shape**：
     - 點選 **Ampere (ARM-based Processor)**。
     - 選擇 **VM.Standard.A1.Flex**（帶有 *Always Free Eligible* 標記）。
     - OCPU 調整為 `2`（或 `1`），記憶體調整為 `12 GB`（或 `6 GB`）。
   - *(降級備案：若提示 Out of Host Capacity，可切回 **Specialty and previous generation → VM.Standard.E2.1.Micro**，1 OCPU / 1GB RAM AMD64)*。
5. **Networking**：
   - 選擇剛剛建立的 VCN 與 Public Subnet。
   - 選擇 **Do not assign a public IPv4 address**（稍後我們會直接綁定申請好的固定保留 IP）。
6. **Add SSH keys（重要）**：
   - 點選 **Generate a key pair for me**。
   - 點擊 **Save private key** 將私鑰（`.key` 檔）下載並妥善保存至您的個人電腦（例如儲存為 `~/.ssh/oci_elinkbook.key`）。
7. **Boot volume**：
   - 維持預設 46.6 GB（Always Free 總共有 200 GB 免費額度，可自訂調高至 50~100 GB）。
8. 點擊底部 **Create**。

### 4.2 綁定保留固定 IP 至 VM
1. 待實例狀態變為綠色 **Running**。
2. 點擊左下側 **Attached VNICs**，點入該主要網卡名稱。
3. 點擊左側 **IPv4 Addresses**。
4. 在既有專用 IP 條目右側點擊三個點 `...` → **Edit**。
5. 在「Public IP Type」選 **Reserved public IP**，下拉選取方才建立的 `elinkbook-ip`，點擊 **Update**。

### 4.3 透過 SSH 連線至 VM

開啟本機終端機（macOS / Linux / Windows PowerShell）：

```bash
# 1. 調整私鑰權限（Windows 可略過或在檔案屬性中移除其他使用者權限）
chmod 400 ~/.ssh/oci_elinkbook.key

# 2. SSH 連線（預設使用者帳號為 ubuntu）
ssh -i ~/.ssh/oci_elinkbook.key ubuntu@<您的_OCI_公網_IP>
```

成功連線後，會看到 `ubuntu@elinkbook-server:~$` 提示符號。

### 4.4 備案：主機 iptables 擋住 80/443 時的處理

> [!NOTE]
> **注意**：OCI 的 Ubuntu 映像預設有嚴格的 `iptables` 入站規則（只放行 Port 22）。
> 本手冊用 Docker 發佈 80/443。Docker 發佈的連接埠通常不經過 `INPUT` 鏈，所以多半**不需要**這一節。
> 只有在第 8.2 節的 `curl` 逾時，而且 VCN 安全清單確定已放行時，才執行下面的指令。

```bash
# 放行 80 (HTTP) 與 443 (HTTPS)
sudo iptables -I INPUT 6 -m state --state NEW -p tcp --dport 80 -j ACCEPT
sudo iptables -I INPUT 6 -m state --state NEW -p tcp --dport 443 -j ACCEPT

# 安裝 iptables-persistent 並保存規則（DEBIAN_FRONTEND 可避免跳出互動視窗）
sudo apt update
sudo DEBIAN_FRONTEND=noninteractive apt install -y iptables-persistent netfilter-persistent
sudo netfilter-persistent save
```

---

## 5. 步驟四：網域名稱與 DNS 解析設定

Let's Encrypt 自動發放 SSL 憑證必須具備合法的網域名稱（FQDN）指向您的 OCI 公網 IP。

### 方案 A（推薦）：自有網域／子網域
若您已擁有個人網域（例如託管於 Cloudflare、GoDaddy、Namecheap、Gandi 等）：
1. 登入您的 DNS 管理後台。
2. 新增一筆 **A 紀錄**：
   - **Type**：`A`
   - **Name**：`sync`（或自訂子網域名稱，如 `pocketbase`）
   - **IPv4 Address**：填入您的 OCI 保留公網 IP（例如 `129.150.x.x`）
   - **TTL**：Auto 或 300 秒
   - *(若使用 Cloudflare，請先將橘色雲朵 **Proxy status** 設為 **DNS Only（灰色）**，讓 Traefik 順利完成初始 Let's Encrypt ACME 憑證簽發)*。
3. 最終 FQDN 為：`sync.yourdomain.com`。

### 方案 B（完全免費）：使用 DuckDNS 免費動態網域
若您沒有購買個人網域，可直接使用終身免費的 [DuckDNS](https://www.duckdns.org/)：
1. 瀏覽器開啟 DuckDNS 網站，使用 Google 或 GitHub 帳號登入。
2. 在 **domains** 欄位新增一個子網域，例如 `my-elinkbook`。
3. 在 **current ip** 欄位填入您的 OCI 保留公網 IP。
4. 點擊 **update ip**。
5. 最終 FQDN 為：`my-elinkbook.duckdns.org`。

---

## 6. 步驟五：安裝 Docker 與 Docker Compose

在 OCI Ubuntu 終端機中執行以下官方安裝流程：

```bash
# 1. 移除舊版本可能衝突的套件
sudo apt remove -y docker docker-engine docker.io containerd runc

# 2. 安裝必要依賴
sudo apt update
sudo apt install -y ca-certificates curl gnupg lsb-release

# 3. 新增 Docker 官方 GPG 密鑰
sudo install -m 0755 -d /etc/apt/keyrings
curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo gpg --dearmor -o /etc/apt/keyrings/docker.gpg
sudo chmod a+r /etc/apt/keyrings/docker.gpg

# 4. 新增 Docker APT 官方軟體庫
echo \
  "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu \
  $(lsb_release -cs) stable" | sudo tee /etc/apt/sources.list.d/docker.list > /dev/null

# 5. 安裝 Docker Engine 與 Docker Compose 插件
sudo apt update
sudo apt install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin

# 6. 將目前使用者 (ubuntu) 加入 docker 群組，免 sudo 執行
sudo usermod -aG docker $USER

# 7. 啟用並設定 Docker 開機自動啟動
sudo systemctl enable docker
sudo systemctl start docker

# 重新載入群組設定（或重新 SSH 連線）
newgrp docker

# 8. 驗證安裝
docker --version
docker compose version
```

---

## 7. 步驟六：部署 Traefik 反向代理與 PocketBase 容器

### 7.1 建立專案目錄結構

我們將專案集中管理於 `/opt/elinkbook-pocketbase`：

```bash
sudo mkdir -p /opt/elinkbook-pocketbase
sudo chown -R $USER:$USER /opt/elinkbook-pocketbase
cd /opt/elinkbook-pocketbase

mkdir -p pb_data pb_migrations pb_hooks traefik_data
# Traefik ACME 憑證金鑰檔必須具備嚴格 600 權限
touch traefik_data/acme.json
chmod 600 traefik_data/acme.json
```

目錄結構如下：
```text
/opt/elinkbook-pocketbase/
├── docker-compose.yml                             # Traefik 與 PocketBase 容器編排檔
├── Dockerfile                                     # 支援 ARM64/AMD64 多架構 PocketBase 映像檔定義
├── .env                                           # 環境變數設定檔（網域與 Email）
├── traefik_data/
│   └── acme.json                                  # Let's Encrypt SSL 憑證持久化儲存檔 (權限 600)
├── pb_data/                                       # SQLite 資料庫 (data.db) 持久化目錄
├── pb_migrations/                                 # 雲端同步 Collection Schema 自動遷移腳本
│   ├── 1785715200_create_sync_collections.js
│   ├── 1785801600_add_created_updated_autodate_fields.js
│   └── 1785801700_add_reading_positions_unique_index.js
└── pb_hooks/                                      # 伺服器端排程腳本
    └── purge_tombstones.pb.js                     # 每日自動清除 30 天軟刪除墓碑
```

### 7.2 部署 Migration 與 Hook 腳本

Migration 與 Hook 以 repo 為唯一來源，本手冊**不內嵌全文**，避免文件與程式不同步。

| repo 路徑 | VM 目標路徑 |
|---|---|
| `docker/pb_migrations/*.js`（3 支） | `/opt/elinkbook-pocketbase/pb_migrations/` |
| `docker/pb_hooks_example/purge_tombstones.pb.js` | `/opt/elinkbook-pocketbase/pb_hooks/` |

在**你的電腦**（repo 根目錄）執行，把檔案複製到 VM：

```bash
scp -i ~/.ssh/oci_elinkbook.key docker/pb_migrations/*.js   ubuntu@<您的_OCI_公網_IP>:/opt/elinkbook-pocketbase/pb_migrations/

scp -i ~/.ssh/oci_elinkbook.key docker/pb_hooks_example/purge_tombstones.pb.js   ubuntu@<您的_OCI_公網_IP>:/opt/elinkbook-pocketbase/pb_hooks/
```

在 **VM** 上確認檔案都到了：

```bash
ls /opt/elinkbook-pocketbase/pb_migrations /opt/elinkbook-pocketbase/pb_hooks
```

預期看到 3 支 migration 與 1 支 hook（檔名見 7.1 的目錄結構）。

> **注意**：
> - 來源檔在 `docker/pb_hooks_example/`，複製到 VM 後放在 `pb_hooks/` 目錄，PocketBase 才會載入。
> - 清理 hook 的排程 `0 3 * * *` 以 **UTC** 計算，等於台灣時間 11:00。
> - 每次執行最多清除 500 筆。
> - `deleted_at` 是毫秒時間戳記（number），沒刪除時為 `0`。這與 App 端一致，不要改成文字欄位。

### 7.3 撰寫多架構 Dockerfile

本 `Dockerfile` 內建自動架構偵測，不論您的 OCI VM 是 **ARM64 (Ampere A1)** 還是 **AMD64 (E2.1.Micro)**，皆能自動下載對應的官方 PocketBase 二進位檔：

```bash
cat << 'EOF' > Dockerfile
FROM alpine:3.22

ARG PB_VERSION=0.40.4

RUN apk add --no-cache unzip ca-certificates wget

# 依據硬體架構自動選擇下載 arm64 或 amd64 版本
RUN ARCH=$(uname -m) && \
    if [ "$ARCH" = "aarch64" ] || [ "$ARCH" = "arm64" ]; then \
      PB_ARCH="linux_arm64"; \
    elif [ "$ARCH" = "x86_64" ]; then \
      PB_ARCH="linux_amd64"; \
    else \
      PB_ARCH="linux_amd64"; \
    fi && \
    echo "Downloading PocketBase v${PB_VERSION} for ${PB_ARCH}..." && \
    wget https://github.com/pocketbase/pocketbase/releases/download/v${PB_VERSION}/pocketbase_${PB_VERSION}_${PB_ARCH}.zip && \
    unzip pocketbase_${PB_VERSION}_${PB_ARCH}.zip -d /pb && \
    rm pocketbase_${PB_VERSION}_${PB_ARCH}.zip

EXPOSE 8090

VOLUME ["/pb/pb_data", "/pb/pb_migrations", "/pb/pb_hooks"]

ENTRYPOINT ["/pb/pocketbase", "serve", "--http=0.0.0.0:8090"]
EOF
```

### 7.4 建立環境變數檔 `.env`

建立 `.env` 檔案設定您的網域名稱與 Let's Encrypt 註冊 Email（請替換為您自己的真實資料）：

```bash
cat << 'EOF' > .env
# 請替換為您的網域（例如 sync.yourdomain.com 或 my-elinkbook.duckdns.org）
DOMAIN_NAME=sync.yourdomain.com

# 請替換為您的有效 Email，供 Let's Encrypt 憑證過期通知用
ACME_EMAIL=your-email@example.com
EOF
```

### 7.5 撰寫 docker-compose.yml

```bash
cat << 'EOF' > docker-compose.yml
services:
  # 1. Traefik 反向代理與自動 SSL
  traefik:
    image: traefik:v3.6
    container_name: elinkbook-traefik
    restart: always
    command:
      - "--providers.docker=true"
      - "--providers.docker.exposedbydefault=false"
      - "--entrypoints.web.address=:80"
      - "--entrypoints.websecure.address=:443"
      # 全域設定：將所有 HTTP 請求自動 301 重定向至 HTTPS
      - "--entrypoints.web.http.redirections.entryPoint.to=websecure"
      - "--entrypoints.web.http.redirections.entryPoint.scheme=https"
      # ACME Let's Encrypt HTTP-01 憑證挑戰設定
      - "--certificatesresolvers.myresolver.acme.httpchallenge=true"
      - "--certificatesresolvers.myresolver.acme.httpchallenge.entrypoint=web"
      - "--certificatesresolvers.myresolver.acme.email=${ACME_EMAIL}"
      - "--certificatesresolvers.myresolver.acme.storage=/letsencrypt/acme.json"
    ports:
      - "80:80"
      - "443:443"
    volumes:
      - "/var/run/docker.sock:/var/run/docker.sock:ro"
      - "./traefik_data/acme.json:/letsencrypt/acme.json"
    networks:
      - web

  # 2. PocketBase 後端服務 (elinkBook 同步引擎)
  pocketbase:
    build:
      context: .
      dockerfile: Dockerfile
    container_name: elinkbook-pocketbase
    restart: always
    volumes:
      - ./pb_data:/pb/pb_data
      - ./pb_migrations:/pb/pb_migrations
      - ./pb_hooks:/pb/pb_hooks
    expose:
      - "8090"
    healthcheck:
      # 用 127.0.0.1 而非 localhost：Alpine 的 wget 可能先走 IPv6，而 PocketBase 只綁 IPv4
      test: ["CMD", "wget", "--no-verbose", "--tries=1", "--spider", "http://127.0.0.1:8090/api/health"]
      interval: 15s
      timeout: 5s
      retries: 3
    networks:
      - web
    labels:
      - "traefik.enable=true"
      # 綁定路由至網域名稱
      - "traefik.http.routers.pocketbase.rule=Host(`${DOMAIN_NAME}`)"
      - "traefik.http.routers.pocketbase.entrypoints=websecure"
      - "traefik.http.routers.pocketbase.tls=true"
      - "traefik.http.routers.pocketbase.tls.certresolver=myresolver"
      # 指定內部容器通訊埠號
      - "traefik.http.services.pocketbase.loadbalancer.server.port=8090"

networks:
  web:
    name: elinkbook-web
EOF
```

### 7.6 建置並啟動服務

```bash
# 建置 PocketBase 映像檔並啟動所有容器
docker compose up -d --build
```

### 7.7 觀察啟動日誌與憑證簽發狀態

```bash
# 觀察 Traefik 憑證簽發日誌
docker logs -f elinkbook-traefik
```
當日誌出現類似下面的內容時，代表憑證簽發成功（以下為**示意**，實際文字依 Traefik 版本而異）：
```text
level=info msg="Server started signature for domain: sync.yourdomain.com"
level=info msg="Certificates obtained for domains [sync.yourdomain.com]"
```

再檢視 PocketBase 遷移日誌：
```bash
docker logs elinkbook-pocketbase
```
會顯示自動執行了 3 支遷移腳本並建立好 4 個 Collection：
```text
> Applied 1785715200_create_sync_collections.js
> Applied 1785801600_add_created_updated_autodate_fields.js
> Applied 1785801700_add_reading_positions_unique_index.js
Server started at http://0.0.0.0:8090
```

---

## 8. 步驟七：PocketBase 初始化與 elinkBook App 連線驗證

### 8.1 建立 PocketBase Superuser 管理員帳號

PocketBase ≥ v0.23 使用 `superuser` 指令。我們可透過 Docker 容器指令快速建立管理員：

```bash
# 指令語法：docker exec -it elinkbook-pocketbase /pb/pocketbase superuser upsert <信箱> <密碼>
docker exec -it elinkbook-pocketbase /pb/pocketbase superuser upsert admin@example.com MyStrongAdminPassword123
```

建立成功後，即可使用瀏覽器開啟管理後台：
`https://sync.yourdomain.com/_/`
輸入帳號密碼登入，確認 Collections 列表中已存在：
- `users` (系統自建)
- `sync_reading_positions`
- `sync_bookmarks`
- `sync_highlights`
- `sync_notes`

### 8.2 外部健康檢查測試 (Health Check)

在您的個人電腦或外網環境終端機執行：

```bash
curl -i https://sync.yourdomain.com/api/health
```

**預期回傳**：
```http
HTTP/2 200 OK
content-type: application/json; charset=utf-8

{"code":200,"data":{},"message":"API is healthy."}
```
確認 HTTP 回應碼為 `200` 且走 `HTTP/2` 加密協定。

### 8.3 測試 App 使用者註冊與同步端點

在終端機測試建立一般 elinkBook 使用者帳號（即 App 端註冊行為）：

```bash
curl -i -X POST https://sync.yourdomain.com/api/collections/users/records \
  -H "Content-Type: application/json" \
  -d '{"email":"testreader@example.com", "password":"password123456", "passwordConfirm":"password123456"}'
```
回傳 `HTTP 200` 且帶有使用者物件 JSON 即代表 API 存取與資料庫寫入正常。

> **警告**：測試完立刻刪除這個測試帳號。到 Admin UI `/_/` → Collections → `users`，刪除 `testreader@example.com`。
> 公網伺服器的 `users` 預設允許任何人註冊。建立好自己的帳號後，請做下面兩件事：
> 1. 在 `users` 集合的 **API Rules → Create rule** 改成只有 superuser 可建立（鎖定）。之後用 Admin UI 手動建立帳號。
> 2. 在 **Settings → Application** 開啟 **Rate limiting**。
>
> 如果你要讓 App 內直接註冊，就不要鎖定 Create rule，但要自行承擔被陌生人註冊的風險。

### 8.4 啟用並測試 Batch API（elinkBook 同步引擎專用）

elinkBook 的 Checkpoint 批次同步依賴 PocketBase 的 Batch API。**這個 API 預設是關閉的**，必須先啟用。

1. 開啟 Admin UI `/_/` → **Settings → Application**。
2. 啟用 Batch API。
3. 將單批次上限設為 100 以上。

啟用後執行：

```bash
curl -i -X POST https://sync.yourdomain.com/api/batch \
  -H "Content-Type: application/json" \
  -d '{"requests":[]}'
```

- 回傳 `403`：Batch API 仍是關閉狀態。回到步驟 1。
- 回傳其他狀態（例如 `200` 或 `400`）：Batch API 已啟用。空的 `requests` 可能被當成格式錯誤，這不代表有問題。
- 最終驗證以第 8.5 節 App 實際同步成功為準。

### 8.5 elinkBook Android App 端連線操作

1. 打開手機上的 **elinkBook** App。
2. 點擊進入 **設定 (Settings)** → **同步與帳號 (Sync & Accounts)**。
3. 啟用 **PocketBase 同步**。
4. **伺服器位址 (Server URL)**：輸入 `https://sync.yourdomain.com`（注意：**必須為 https://**，且**不要加上連接埠 :8090 或斜線結尾**）。
5. 輸入在步驟 8.3 建立的使用者 Email 與密碼（或直接在 App 介面上點擊註冊）。
6. 點擊 **登入並測試連線**。顯示綠色勾勾「連線成功」後，開啟任一本書閱讀，進度即可跨裝置即時雙向同步！

---

## 9. 步驟八：日常維運、自動備份與平滑更版 SOP

### 9.1 SQLite 資料庫每日自動備份腳本 (Crontab)

PocketBase 的資料與帳號存在 `/opt/elinkbook-pocketbase/pb_data/data.db`。這個資料庫在執行中會持續寫入（WAL 模式）。

> **警告**：不要在服務執行中直接用 `tar` 打包 `pb_data`。備份檔可能不一致，還原時才發現壞掉。

下面的腳本改用 SQLite 內建的 `.backup` 指令，可以在服務執行中做出一致的備份。備份保留最近 30 天。

1. 安裝 `sqlite3`，建立備份目錄與腳本：
```bash
sudo apt install -y sqlite3
sudo mkdir -p /opt/backups/pocketbase
sudo chown -R $USER:$USER /opt/backups

cat << 'EOF' > /opt/elinkbook-pocketbase/backup.sh
#!/bin/bash
set -e

BACKUP_DIR="/opt/backups/pocketbase"
TIMESTAMP=$(date +"%Y%m%d_%H%M%S")
TARGET_FILE="${BACKUP_DIR}/pocketbase_backup_${TIMESTAMP}.tar.gz"
TMP_DIR=$(mktemp -d)
trap 'rm -rf "${TMP_DIR}"' EXIT

mkdir -p "${BACKUP_DIR}" "${TMP_DIR}/pb_data"

# 用 SQLite 內建備份取得一致的資料庫副本（服務不需停止）
sqlite3 /opt/elinkbook-pocketbase/pb_data/data.db ".backup '${TMP_DIR}/pb_data/data.db'"

# 打包成 pb_data/data.db 結構，還原時可直接解壓到專案目錄
tar -czf "${TARGET_FILE}" -C "${TMP_DIR}" pb_data

# 自動清理超過 30 天的舊備份
find "${BACKUP_DIR}" -type f -name "pocketbase_backup_*.tar.gz" -mtime +30 -exec rm {} \;

echo "[$(date)] Backup completed: ${TARGET_FILE}"
EOF

chmod +x /opt/elinkbook-pocketbase/backup.sh
```

2. 新增至每日排程。VM 預設時區是 **UTC**，`0 2 * * *` 等於台灣時間 10:00。想改成台灣凌晨，把時間改成 `0 18 * * *`（UTC 18:00 = 台灣 02:00）：
```bash
(crontab -l 2>/dev/null; echo "0 18 * * * /opt/elinkbook-pocketbase/backup.sh >> /opt/backups/pocketbase/backup.log 2>&1") | crontab -
```

3. **把備份複製到 VM 以外的地方。** 備份只放在同一顆磁碟，VM 被刪除或回收時會一起消失。可用 `scp`、`rclone` 或 OCI Object Storage 等方式，每天複製一份到另一處。

### 9.2 閒置回收風險備註

本手冊不提供保活腳本，原因見第 2.3 節。請升級 PAYG，或確實執行第 9.1 節的異地備份。

### 9.3 PocketBase 平滑更版 (Upgrade) 與回滾 SOP

當 PocketBase 官方釋出新版本時，請遵循以下維運流程：

#### 更版流程：
1. **立即執行手動備份**：
   ```bash
   /opt/elinkbook-pocketbase/backup.sh
   ```
2. **修改 Dockerfile 中的版本號**：
   編輯 `/opt/elinkbook-pocketbase/Dockerfile`，將 `ARG PB_VERSION=0.40.4` 修改為新版本（例如 `0.41.0`）。
3. **無快取重新建置並啟動**：
   ```bash
   cd /opt/elinkbook-pocketbase
   docker compose build --no-cache pocketbase
   docker compose up -d pocketbase
   ```
4. **驗證健康狀態**：
   ```bash
   docker logs -f elinkbook-pocketbase
   curl -i https://sync.yourdomain.com/api/health
   ```

#### 回滾流程（若更版後發生異常）：
1. 停止容器：
   ```bash
   docker compose stop pocketbase
   ```
2. 將 `pb_data` 回復至更版前之備份存檔（備份檔內含 `pb_data/data.db`，先刪除整個 `pb_data` 可一併清掉殘留的 `-wal`／`-shm` 檔）：
   ```bash
   rm -rf /opt/elinkbook-pocketbase/pb_data
   tar -xzf /opt/backups/pocketbase/pocketbase_backup_<TIMESTAMP>.tar.gz -C /opt/elinkbook-pocketbase/
   ```
3. 將 `Dockerfile` 版本號改回原本舊版，執行 `docker compose up -d --build pocketbase`。

---

## 10. 常見故障排查 (Troubleshooting)

| 狀況 / 錯誤現象 | 可能原因 | 解決步驟 |
| :--- | :--- | :--- |
| **建立 ARM 實例時提示 `Out of host capacity`** | 該 Availability Domain 目前 ARM 資源被搶光 | 1. 更換同一 Region 的其他 Availability Domain 重試。<br>2. 改選「VM.Standard.E2.1.Micro」(AMD64 1 OCPU/1GB RAM) 即可秒開。<br>3. 升級至 PAYG 帳號享有高優先權。 |
| **瀏覽器連線顯示 `ERR_CONNECTION_TIMED_OUT`** | 1. OCI VCN 安全清單未開 80/443<br>2. Ubuntu 系統內建 iptables 阻擋（較少見） | 1. 檢查 VCN Ingress Rules 是否有 `0.0.0.0/0` TCP 80 與 443。<br>2. 若 VCN 已放行仍逾時，再執行步驟 4.4 的 `iptables` 指令。 |
| **Traefik 日誌出現 `client version ... is too old`（Docker API 版本）** | Traefik 版本太舊，與新版 Docker Engine 不相容 | 將 `docker-compose.yml` 的映像改為 `traefik:v3.6` 以上，再執行 `docker compose up -d`。 |
| **瀏覽器顯示 `502 Bad Gateway`** | Traefik 無法連線至 PocketBase 8090 | 1. 檢查 PocketBase 容器是否異常退出：`docker logs elinkbook-pocketbase`。<br>2. 檢查 `docker-compose.yml` 中兩者是否都在 `web` 網路。 |
| **無法取得 HTTPS / SSL 憑證錯誤** | 1. DNS A 紀錄未生效或 IP 錯誤<br>2. Port 80 被防火牆擋住 (HTTP-01 失敗)<br>3. Cloudflare 開啟了橘色 Proxy | 1. 使用 `nslookup sync.yourdomain.com` 確認解析到的 IP 是否為 OCI 公網 IP。<br>2. 確認 Port 80 可由外網連入。<br>3. 若使用 Cloudflare，請切換為 **DNS Only (灰色雲朵)**。 |
| **App 同步時提示 `Connection Refused` 或 `Cleartext HTTP not permitted`** | App 端設定之 URL 錯誤 | 1. App 內的伺服器網址務必填寫 **`https://`** 開頭。<br>2. 絕對**不要**在網址後面附加 `:8090`，外網統一由 Traefik 443 代理轉發。 |
| **App 批次同步時報錯 `404 Not Found (/api/batch)`** | PocketBase 版本過舊 | PocketBase 必須 ≥ v0.23 才有 Batch API。請依本手冊安裝 v0.40.4 或以上版本。 |

---

## 11. 相關參考文件
- [`docs/research/synology_dsm7_pocketbase_sop.md`](synology_dsm7_pocketbase_sop.md)：Synology DSM 7 NAS 部署 SOP（可對照 Collection Schema）
- [`docker/README.md`](../../docker/README.md)：PocketBase 容器化部署說明與環境變數
- [`docs/sync-protocol.md`](../sync-protocol.md)：elinkBook 雲端同步 Protocol 與 Collection 欄位定義
- [PocketBase 官方文件](https://pocketbase.io/docs/)
- [Traefik 官方 Docker 整合文件](https://doc.traefik.io/traefik/user-guides/docker-compose/basic-example/)
