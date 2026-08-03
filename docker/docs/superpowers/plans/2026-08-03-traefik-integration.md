# PocketBase Traefik 整合與連接埠隔離執行計畫

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 將 PocketBase 內部連接埠改為 Port 80，整合至 Traefik 並完全阻隔宿主機的 Port 暴露。

**Architecture:** 修改 Dockerfile 調整容器內監聽埠，更新 .env 的負載均衡埠為 80，修改 docker-compose.yml 移除 ports 埠號映射以進行網路隔離。

**Tech Stack:** Docker, Docker Compose, Traefik

## Global Constraints

- 服務完全整合進 Traefik，不得向宿主機暴露任何直接連接埠。
- 容器內部服務必須執行在 Port 80。

---

### Task 1: 容器連接埠配置與網路隔離

**Files:**
- Modify: `/home/cds/ai/pocketbase/Dockerfile`
- Modify: `/home/cds/ai/pocketbase/.env`
- Modify: `/home/cds/ai/pocketbase/docker-compose.yml`

**Interfaces:**
- Consumes: None
- Produces: 透過 Traefik 與 Domain `pbdev.jigong.org` 路由的 PocketBase 服務。

- [ ] **Step 1: 修改 Dockerfile 的內部監聽埠**

  將 [`Dockerfile`](file:///home/cds/ai/pocketbase/Dockerfile) 中的服務連接埠更換為 `80`。
  
  修改內容：
  ```diff
  -EXPOSE 8090
  +EXPOSE 80
  
  -ENTRYPOINT ["/pb/pocketbase", "serve", "--http=0.0.0.0:8090"]
  +ENTRYPOINT ["/pb/pocketbase", "serve", "--http=0.0.0.0:80"]
  ```

- [ ] **Step 2: 修改 .env 中的 Traefik 負載均衡連接埠**

  將 [`.env`](file:///home/cds/ai/pocketbase/.env) 中的 `LOADBALANCER_SERVER_PORT` 設定為 `80`。

  修改內容：
  ```diff
  -LOADBALANCER_SERVER_PORT=8090
  +LOADBALANCER_SERVER_PORT=80
  ```

- [ ] **Step 3: 修改 docker-compose.yml 移除 ports 映射**

  將 [`docker-compose.yml`](file:///home/cds/ai/pocketbase/docker-compose.yml) 中的 `ports:` 區塊完全刪除。

  修改內容：
  ```diff
  -    ports:
  -      - "${PORT:-8090}:8090"
  ```

- [ ] **Step 4: 重新建置與啟動服務**

  執行無快取的 Docker 映像建置，確保連接埠更新生效，然後重啟容器：
  ```bash
  docker compose build --no-cache
  docker compose up -d
  ```

- [ ] **Step 5: 驗證服務運作與連接埠隔離**

  執行狀態檢查指令：
  ```bash
  docker compose ps
  ```
  **預期結果：**
  - 容器名稱 `elinkbook-pocketbase` 的 STATUS 顯示為 `healthy`。
  - PORTS 欄位只顯示容器內部監聽資訊，不顯示任何與外部宿主機的映射關係（例如：不應該有 `0.0.0.0:8090->80/tcp` 等）。
