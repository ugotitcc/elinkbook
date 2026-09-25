#!/usr/bin/env bash
# epic-49 Issue 2：一步一步引導部署 elinkBook 字型下載服務。
# 用法：在 repo 根目錄執行 bash fonts-cdn/deploy-wizard.sh
# 需要人類操作的步驟（註冊、綁卡、瀏覽器登入）會暫停等待確認；其餘由腳本執行。
set -euo pipefail
cd "$(dirname "$0")"

BUCKET="elinkbook-fonts"

step() { echo; echo "=================================================="; echo "步驟 $1：$2"; echo "=================================================="; }
confirm() { read -r -p "$1（完成後輸入 y 繼續，其他鍵中止）：" answer; [[ "$answer" == "y" ]] || { echo "已中止"; exit 1; }; }

step 0 "檢查本機工具"
command -v node >/dev/null || { echo "找不到 node，請先安裝 Node.js 24"; exit 1; }
command -v npx  >/dev/null || { echo "找不到 npx，請先安裝 Node.js 24"; exit 1; }
node --version
node scripts/check_manifest.mjs

step 1 "Cloudflare 帳號與付款方式"
echo "1. 前往 https://dash.cloudflare.com/sign-up 註冊（已有帳號可略過）。"
echo "2. 到 Billing → Payment info 綁定信用卡或 PayPal。"
echo "   R2 在免費額度內（儲存 10GB、每月 1,000 萬次讀取）不會扣款，但未綁定付款方式無法啟用 R2。"
confirm "帳號已建立且已綁定付款方式？"

step 2 "啟用 R2"
echo "在 Cloudflare 後台左側選單點 R2 Object Storage，依畫面指示啟用（選免費方案）。"
confirm "R2 已啟用？"

step 3 "登入 wrangler"
echo "接下來會開啟瀏覽器進行 Cloudflare 授權，不需要建立 API Token。"
echo "若詢問 Need to install the following packages: wrangler@4 Ok to proceed?，輸入 y。"
npx wrangler@4 login
npx wrangler@4 whoami

step 4 "建立 R2 bucket：$BUCKET"
if npx wrangler@4 r2 bucket list | grep -q "$BUCKET"; then
  echo "bucket 已存在，略過建立。"
else
  npx wrangler@4 r2 bucket create "$BUCKET"
fi

step 5 "部署 Worker"
echo "第一次部署時，wrangler 若詢問是否註冊 workers.dev 子網域，請選擇同意並取一個名稱，"
echo "這個名稱會成為字型下載網址的一部分（https://elinkbook-fonts.<子網域>.workers.dev），之後不容易更改。"
npx wrangler@4 deploy
echo
echo "請從上方輸出找到 https://elinkbook-fonts.<你的子網域>.workers.dev 這個網址。"
read -r -p "貼上 Worker 網址：" WORKER_URL
[[ "$WORKER_URL" =~ ^https://[a-z0-9.-]+\.workers\.dev/?$ ]] || { echo "網址格式不正確：$WORKER_URL"; exit 1; }
WORKER_URL="${WORKER_URL%/}"

step 6 "上傳字型（先 dry-run 檢查，再正式上傳）"
echo "若上傳到一半失敗，排除問題後重跑本 wizard 即可：已上傳且內容一致的字型會自動略過。"
node scripts/upload.mjs --bucket "$BUCKET" --base-url "$WORKER_URL" --dry-run
confirm "以上上傳指令正確？（第一次部署應為 5 條）"
node scripts/upload.mjs --bucket "$BUCKET" --base-url "$WORKER_URL"

step 7 "線上驗證"
node scripts/verify_remote.mjs --base-url "$WORKER_URL"

step 8 "完成"
echo "請把以下網址記錄到 docs/epics/epic-49-downloadable-fonts/epic.md（Issue 2 驗收），"
echo "Issue 4 會把它填入 App 的下載服務基底網址常數："
echo
echo "  $WORKER_URL"
