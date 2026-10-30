# 依據 docker/README.md 部署說明與 docs/sync-protocol.md 建置之 PocketBase 容器化映像
# Alpine 版本標籤（預設 latest；需要可重現建置時，在 .env 設 ALPINE_TAG 釘住版本）
ARG ALPINE_TAG=latest
FROM alpine:${ALPINE_TAG}

# PocketBase 版本變數（0.41.1 含以上皆可；需 >= 0.23 支援 Batch API）
ARG PB_VERSION=0.41.1
# PocketBase 下載來源（官方已由 GitHub 搬到此站；新站失敗時可在 .env 改回
# https://github.com/pocketbase/pocketbase/releases/download）
ARG PB_BASE_URL=https://ganigeorgiev.com/meta/pocketbase/pocketbase/download

# 安裝基本套件，依 CPU 架構下載 PocketBase，並用 checksums.txt 驗證 SHA256（不符則 build 失敗）
RUN apk add --no-cache unzip ca-certificates wget && \
    case "$(uname -m)" in \
      aarch64|arm64) PB_ARCH=linux_arm64 ;; \
      armv7l)        PB_ARCH=linux_armv7 ;; \
      *)             PB_ARCH=linux_amd64 ;; \
    esac && \
    ZIP="pocketbase_${PB_VERSION}_${PB_ARCH}.zip" && \
    wget "${PB_BASE_URL}/v${PB_VERSION}/${ZIP}" && \
    wget "${PB_BASE_URL}/v${PB_VERSION}/checksums.txt" && \
    grep " ${ZIP}\$" checksums.txt | sha256sum -c - && \
    unzip "${ZIP}" -d /pb && \
    rm "${ZIP}" checksums.txt

EXPOSE 80

VOLUME /pb/pb_data
VOLUME /pb/pb_hooks
VOLUME /pb/pb_migrations

ENTRYPOINT ["/pb/pocketbase", "serve", "--http=0.0.0.0:80"]
