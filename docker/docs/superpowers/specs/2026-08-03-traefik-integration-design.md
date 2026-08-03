# PocketBase Traefik 整合與連接埠隔離設計文件 (內部改為 Port 80 版本)

## 🎯 目標
將 `elinkbook-pocketbase` 服務整合至 Traefik 反向代理中，使外部所有流量統一經由網域 `pbdev.jigong.org` (Port 80) 進入。同時配合其他容器的統一規範，將 PocketBase 在容器內部的監聽連接埠修改為 `80`，並隔離 PocketBase 容器對宿主機的直接連接埠暴露。

## 🛠️ 設計細節
1. **修改 Dockerfile (改用 Port 80)**
   - 將 [`Dockerfile`](file:///home/cds/ai/pocketbase/Dockerfile) 中的 `EXPOSE 8090` 修改為 `EXPOSE 80`。
   - 將 `ENTRYPOINT` 中的 `--http=0.0.0.0:8090` 修改為 `--http=0.0.0.0:80`。

2. **調整 .env 設定**
   - 將 [`.env`](file:///home/cds/ai/pocketbase/.env) 中的 `LOADBALANCER_SERVER_PORT` 設定為 `80`，以符合 Traefik 指向容器內部 Port 80 的規範。

3. **調整 docker-compose.yml (移除 Host 埠號對應與連接埠隔離)**
   - 刪除 [`docker-compose.yml`](file:///home/cds/ai/pocketbase/docker-compose.yml) 中的 `ports:` 區塊。
   - 確保 Traefik 標籤維持啟用：
     - `traefik.enable=true`
     - 網域路由規則：`Host(pbdev.jigong.org)`
     - 負載均衡連接埠：`80` (即為 `LOADBALANCER_SERVER_PORT`)
   - 服務加入外部網路 `${PROXY_NETWORK}` (`reverse-proxy`)。

## 🧪 驗證計畫
1. 執行 `docker compose config` 檢查語法。
2. 執行 `docker compose build --no-cache` 重新建置使用 Port 80 的 Docker 映像檔。
3. 執行 `docker compose up -d` 重新部署容器。
4. 執行 `docker compose ps` 確認沒有任何宿主機連接埠映射（PORTS 欄位不顯示映射關係，為空）。
5. 檢查容器內部服務狀態，確保在 Port 80 運作正常。
