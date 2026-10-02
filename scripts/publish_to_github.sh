#!/usr/bin/env bash
# 把「可公開」的檔案複製到公開 repo（huthief/elinkbook）的本機 clone，並在 clone 內 commit。
# 本腳本只做到 commit，不會 push。push 前請先檢視 diff。
#
# 用法：scripts/publish_to_github.sh [公開 repo 的本機 clone 路徑]
# 預設路徑：與本 repo 同層的 elinkbook-public
#
# 做法是「白名單」：只複製下方列出的路徑，清單外的檔案一律不會被複製。
set -euo pipefail

SRC="$(cd "$(dirname "$0")/.." && pwd)"
DEST="${1:-$(dirname "$SRC")/elinkbook-public}"
REMOTE_URL="https://github.com/huthief/elinkbook.git"

# ---- 白名單（相對於本 repo 根目錄）-------------------------------------------
DOCKER_FILES=(
  .env.example
  Dockerfile
  README.md
  docker-compose.yml
  docker-compose.dev.nossl.yml
  docker-compose.org.yml
)
DOCKER_DIRS=(pb_hooks_example pb_migrations)
DOC_FILES=(
  docs/sync-protocol.md
  docs/research/synology_dsm7_pocketbase_sop.md
  docs/research/oracle_cloud_pocketbase_sop.md
)

# ---- 1. 準備公開 repo 的 clone ------------------------------------------------
if [ ! -d "$DEST/.git" ]; then
  echo "[準備] 第一次執行，clone 到 $DEST"
  git clone "$REMOTE_URL" "$DEST"
else
  if [ -n "$(git -C "$DEST" status --porcelain)" ]; then
    echo "[錯誤] $DEST 有未提交的修改。請先處理後再執行。" >&2
    exit 1
  fi
  echo "[準備] 更新 $DEST"
  git -C "$DEST" pull --ff-only
fi

# ---- 2. 清掉由本腳本管理的路徑，再重新複製（讓來源刪掉的檔案也會同步刪除）-----
rm -rf "$DEST/docker" "$DEST/docs"
mkdir -p "$DEST/docker" "$DEST/docs/research"

for f in "${DOCKER_FILES[@]}"; do cp "$SRC/docker/$f" "$DEST/docker/$f"; done
for d in "${DOCKER_DIRS[@]}"; do cp -r "$SRC/docker/$d" "$DEST/docker/$d"; done
for f in "${DOC_FILES[@]}"; do cp "$SRC/$f" "$DEST/$f"; done
cp "$SRC/scripts/github_public/README.md" "$DEST/README.md"
cp "$SRC/scripts/github_public/LICENSE" "$DEST/LICENSE"

# ---- 3. 攔截檢查：出現任何一項就中止 -------------------------------------------
fail=0
for p in "docker/.env" "docker/pb_hooks" "docker/docs"; do
  if [ -e "$DEST/$p" ]; then echo "[攔截] 不該公開的路徑存在：$p" >&2; fail=1; fi
done
hits="$(grep -rIlE 'jigong|superpowers' "$DEST" --exclude-dir=.git || true)"
if [ -n "$hits" ]; then
  echo "[攔截] 以下檔案含有 jigong 或 superpowers 字樣：" >&2
  echo "$hits" >&2
  fail=1
fi
if [ "$fail" -ne 0 ]; then
  echo "[中止] 請修正後重跑。clone 內的檔案尚未 commit。" >&2
  exit 1
fi

# ---- 4. commit（不 push）-------------------------------------------------------
git -C "$DEST" add -A
if git -C "$DEST" diff --cached --quiet; then
  echo "[完成] 沒有任何變更，不需要 commit。"
  exit 0
fi
git -C "$DEST" commit -q -m "docs: 同步後端部署檔與文件更新"
git -C "$DEST" show --stat --format='%h %s' HEAD
echo
echo "[完成] 已在 $DEST commit，尚未 push。"
echo "檢視完整差異：git -C \"$DEST\" show HEAD"
echo "確認無誤後再 push：git -C \"$DEST\" push"
