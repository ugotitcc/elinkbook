# 依據 docker/README.md 部署說明與 docs/sync-protocol.md 建置之 PocketBase 容器化映像
FROM alpine:3.22

# PocketBase 版本變數 (預設 0.40.4，需 >= 0.23 支援 Batch API)
ARG PB_VERSION=0.40.4

# 安裝基本套件並下載指定版本 PocketBase 二進位檔
RUN apk add --no-cache unzip ca-certificates wget && \
    wget https://github.com/pocketbase/pocketbase/releases/download/v${PB_VERSION}/pocketbase_${PB_VERSION}_linux_amd64.zip && \
    unzip pocketbase_${PB_VERSION}_linux_amd64.zip -d /pb && \
    rm pocketbase_${PB_VERSION}_linux_amd64.zip

EXPOSE 80

VOLUME /pb/pb_data
VOLUME /pb/pb_hooks
VOLUME /pb/pb_migrations

ENTRYPOINT ["/pb/pocketbase", "serve", "--http=0.0.0.0:80"]
