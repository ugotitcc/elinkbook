# Issue 1：字型下載服務程式（`fonts-cdn/`）實作計畫

> **給執行者（agentic worker）：** 必須使用子技能 superpowers:subagent-driven-development（建議）或 superpowers:executing-plans，逐一執行本計畫的 Task。步驟使用核取方塊（`- [ ]`），完成一個就改成 `- [x]`。

**目標：** 在 repo 根目錄建立 `fonts-cdn/`：5 款字型原檔與授權檔、字型清單、Cloudflare Worker（從 R2 提供字型下載）、上傳腳本、線上驗證腳本、部署 wizard，全部附上可在本機執行的 Node 測試。

**架構：** 字型清單 `fonts.json` 是單一事實來源，上傳、驗證、自我檢查三支腳本都讀它。Worker 是一個 ES module，只提供 `GET`／`HEAD /v<N>/<檔名>.ttf`，透過 R2 binding `FONTS` 讀檔。所有腳本只用 Node 內建模組（Node 24，內建 `fetch`、`Response`），免 `npm install`；只有部署與上傳會用 `npx wrangler@4`。

**技術：** Node.js 24（ESM）、Cloudflare Workers、Cloudflare R2、`wrangler` 4、Bash（部署 wizard）。

**規格：** `docs/epics/epic-49-downloadable-fonts/spec.md`（「字型目錄」「字型下載服務」兩節）、`docs/adr/0035-downloadable-fonts-via-r2-worker.md`、`docs/epics/epic-49-downloadable-fonts/issues.md` Issue 1。

## 全域限制

- 發布路徑格式：`v1/<檔名>`；已發布的 key **永遠不覆蓋、不刪除**。上傳腳本在目標 key 已存在時直接中止。
- 5 款字型的位元組大小與 SHA-256 必須和 `spec.md`「字型目錄」表格完全一致：

  | id（`AppFont` 列舉名） | 發布路徑 | 位元組 | SHA-256 |
  |---|---|---|---|
  | `sourceHanSans` | `v1/SourceHanSansTC-VF.ttf` | 36034016 | `1a273a56aa47250c7af95e461ee0c8236c60d7141e14a37bd18baccb1e851b19` |
  | `sourceHanSerif` | `v1/SourceHanSerifTC-VF.ttf` | 59898316 | `71354ed752104c8a3cbcff18943c6110d179d01cc6eaaf1aff7ea14c4a447879` |
  | `guanKiapTsingKhai` | `v1/GuanKiapTsingKhai.ttf` | 14675776 | `758632243c499e431fd0c847f5e8c431acf59a9b41a26237a819466139994d38` |
  | `taiwanPearl` | `v1/TaiwanPearl-Regular.ttf` | 21704488 | `51b3c9a4ab1b6b45dcdad7c5ae93386aea399fd3dabb85d2ac41110dc57f211d` |
  | `genRyuMinTW` | `v1/GenRyuMinTW-Regular.ttf` | 15976964 | `9178c199d633075b8bb91902216c3e1bc977a11fde12471a2c9a250434402927` |

- Worker 回應標頭：`Content-Type: font/ttf`、`Content-Length`、`ETag`、`Cache-Control: public, max-age=31536000, immutable`。`GET` 用 `bucket.get()`，`HEAD` **只能**用 `bucket.head()`。其他方法回 `405`，其他路徑回 `404`，不支援 `Range`。
- R2 bucket 名稱：`elinkbook-fonts`；Worker 名稱：`elinkbook-fonts`；R2 binding 名稱：`FONTS`。
- 驗證身分使用 `wrangler login`（互動式），不建立 API Token。
- 腳本只用 Node 內建模組，不加 `node_modules`、不加 npm 依賴。
- 本計畫的 shell 指令一律在 **Git Bash** 執行（repo 根目錄），不要貼到 PowerShell：語法不同，而且 PowerShell 的 `>` 可能重新編碼二進位輸出。
- 文件與註解一律使用正體中文。

## 審查重點（Review Focus）

1. **R2 物件不存在時的 `HEAD`**：必須回 `404`，不可因為 `head()` 回傳 `null` 而拋例外變成 500。→ Task 2 測試「HEAD 不存在的物件回 404」。
2. **路徑穿越（`/v1/../x`、`/v1/%2e%2e/x`）**：不可讀到版本目錄以外的 key。→ Task 2 測試「路徑穿越與編碼字元回 404」。
3. **上傳腳本遇到「本機檔案雜湊與清單不符」**：必須在任何上傳發生前中止，不可上傳一半。→ Task 3 測試「清單雜湊不符時，dry-run 不列出任何上傳指令且結束碼非 0」。
4. **線上驗證遇到伺服器回傳內容不同但大小相同的檔案**：必須以 SHA-256 判定失敗，不能只比大小。→ Task 3 測試「內容被竄改但大小相同時驗證失敗」。
5. **上傳腳本對已存在的 key**：內容和清單不同時必須中止整批（不是略過繼續），不可覆蓋。→ Task 3 測試「任一 key 已存在時結束碼非 0，且不列出任何上傳指令」。
   > **程式審查修訂（`review-issue-1.md` I-1，人類裁定採方案 A）**：已存在且大小與 SHA-256 都和清單一致的 key 改為略過，讓上傳中途失敗後重跑可以補完；內容不同時仍然整批中止。測試改為「已存在但內容不同 → 中止」「已存在且內容一致 → 略過，只列出其餘字型」「全部都已發布 → 不列出任何指令」。

---

## 檔案結構

```
fonts-cdn/
├── .gitattributes                # .sh 固定 LF、.ttf 視為二進位
├── README.md                     # 目錄用途、發布規則、腳本用法
├── package.json                  # {"type":"module"}，讓 .js 以 ESM 載入；無任何依賴
├── wrangler.toml                 # Worker 與 R2 binding 設定
├── fonts.json                    # 字型清單（單一事實來源）
├── fonts/                        # 5 款字型原檔
│   └── licenses/                 # 各字型的授權檔
├── worker/index.js               # Worker 程式
├── scripts/
│   ├── lib.mjs                   # 共用：讀清單、串流計算 SHA-256
│   ├── check_manifest.mjs        # 本機檔案 vs 清單的自我檢查
│   ├── upload.mjs                # 上傳到 R2（支援 --dry-run）
│   └── verify_remote.mjs         # 線上驗證
├── test/
│   ├── test_worker.mjs
│   └── test_scripts.mjs          # upload dry-run 與 verify_remote 的測試
└── deploy-wizard.sh              # 人類操作的部署引導
```

另外修改：`app/pubspec.yaml`（字型註解）；刪除 `app/assets/fonts/GuanKiapTsingKhai.ttf`（移到 `fonts-cdn/fonts/`）。

---

### Task 1：字型原檔、授權檔、字型清單與自我檢查

**Files:**
- Create: `fonts-cdn/.gitattributes`、`fonts-cdn/package.json`、`fonts-cdn/fonts.json`、`fonts-cdn/scripts/lib.mjs`、`fonts-cdn/scripts/check_manifest.mjs`
- Create: `fonts-cdn/fonts/*.ttf`（5 個）、`fonts-cdn/fonts/licenses/*.txt`
- Move: `app/assets/fonts/GuanKiapTsingKhai.ttf` → `fonts-cdn/fonts/GuanKiapTsingKhai.ttf`
- Modify: `app/pubspec.yaml`（字型區塊註解）

**Interfaces:**
- Produces：`fonts-cdn/fonts.json`，格式如下（Issue 4 的 Dart 一致性測試會用 `id` 對應 `AppFont` 列舉名）：
  ```json
  { "fonts": [ { "id": "sourceHanSans", "file": "fonts/SourceHanSansTC-VF.ttf", "path": "v1/SourceHanSansTC-VF.ttf", "bytes": 36034016, "sha256": "1a27…" } ] }
  ```
- Produces：`scripts/lib.mjs` 匯出 `readManifest(manifestPath) → { fonts: [...] , baseDir }` 與 `sha256OfFile(filePath) → Promise<string>`（小寫十六進位）。

- [x] **Step 1：還原與移動字型原檔**

在 repo 根目錄執行（Git Bash）。字型檔由 `git restore` 直接寫到磁碟，**不要**改成 `git show … > 檔案`：在 PowerShell 下 `>` 可能重新編碼二進位輸出，把字型檔弄壞。`git restore --worktree` 只寫工作目錄、不動 index：

```bash
mkdir -p fonts-cdn/fonts/licenses
git restore --source=eddcc85e^ --worktree -- \
  app/assets/fonts/SourceHanSansTC-VF.ttf app/assets/fonts/SourceHanSerifTC-VF.ttf \
  app/assets/fonts/TaiwanPearl-Regular.ttf app/assets/fonts/GenRyuMinTW-Regular.ttf
mv app/assets/fonts/SourceHanSansTC-VF.ttf app/assets/fonts/SourceHanSerifTC-VF.ttf \
   app/assets/fonts/TaiwanPearl-Regular.ttf app/assets/fonts/GenRyuMinTW-Regular.ttf fonts-cdn/fonts/
git mv app/assets/fonts/GuanKiapTsingKhai.ttf fonts-cdn/fonts/GuanKiapTsingKhai.ttf
ls -l fonts-cdn/fonts
```

預期：5 個 `.ttf`，大小與「全域限制」表格一致；`app/assets/fonts/` 已沒有任何檔案。雜湊在 Step 6 由 `check_manifest.mjs` 驗證。

再建立 `fonts-cdn/.gitattributes`。本機 `core.autocrlf=true`，沒有這個檔案的話，`deploy-wizard.sh` checkout 時會變成 CRLF，Git Bash 執行時會出現 `\r: command not found`：

```gitattributes
# 部署 wizard 在 Windows 上也要保持 LF，否則 Git Bash 執行會出現 \r: command not found
*.sh text eol=lf
# 字型原檔一律視為二進位，不做換行轉換
*.ttf binary
```

- [x] **Step 2：取得授權檔**

四款字型的上游 repo 有附授權檔，直接下載 raw 檔案（以下網址已於 2026-09-25 逐一確認可下載，且都含「Open Font License」字樣）。不要改用 GitHub `/license` API：源流明體、台灣圓體的授權檔名是 `SIL_Open_Font_License_1.1.txt`，GitHub 認不出來，API 會回 404。

```bash
cd fonts-cdn/fonts/licenses
curl -fsSL https://raw.githubusercontent.com/adobe-fonts/source-han-sans/master/LICENSE.txt -o SourceHanSans-LICENSE.txt
curl -fsSL https://raw.githubusercontent.com/adobe-fonts/source-han-serif/master/LICENSE.txt -o SourceHanSerif-LICENSE.txt
curl -fsSL https://raw.githubusercontent.com/ButTaiwan/genryu-font/master/SIL_Open_Font_License_1.1.txt -o GenRyuMin-LICENSE.txt
curl -fsSL https://raw.githubusercontent.com/max32002/TaiwanPearl/master/SIL_Open_Font_License_1.1.txt -o TaiwanPearl-LICENSE.txt
```

原俠正楷的 repo（`tonyhuan/GuanKiapTsingKhai`）只在 README 聲明採用 SIL OFL 1.1，沒有附授權檔。它的授權檔由 OFL 官方全文組成，開頭的著作權聲明**不自行撰寫**，而是取自兩個來源：

- 字型檔 `name` table 的 nameID 0：`Copyright 2022-2025 Tony Huang (https://github.com/tonyhuan/GuanKiapTsingKhai)`
- README「開源授權規定」一節列出的保留名稱：「原俠」、「GuanKiap」

```bash
curl -fsSL https://openfontlicense.org/documents/OFL.txt -o OFL-template.txt
node -e '
const fs = require("fs")
const template = fs.readFileSync("OFL-template.txt", "utf8")
// 官方範本開頭是 <Copyright Holder> 等佔位行，從「This Font Software is licensed」這一行開始才是條款本文
const body = template.slice(template.indexOf("This Font Software is licensed"))
const header = [
  "Copyright 2022-2025 Tony Huang (https://github.com/tonyhuan/GuanKiapTsingKhai),",
  "with Reserved Font Names \"原俠\" and \"GuanKiap\".",
  "",
  "",
].join("\n")
fs.writeFileSync("GuanKiapTsingKhai-LICENSE.txt", header + body)
'
rm OFL-template.txt
grep -l "Open Font License" *.txt
```

預期：`grep` 列出 5 個檔案。**若任何一個 `curl` 失敗（404 等）**，停下來回報人類，附上字型名稱與失敗的網址。不要自行猜測其他 repo 或分支，也不要自己撰寫授權條款。

- [x] **Step 3：建立 `package.json` 與 `fonts.json`**

`fonts-cdn/package.json`：

```json
{
  "private": true,
  "type": "module",
  "description": "elinkBook 可下載字型服務（epic-49）；無任何 npm 依賴"
}
```

`fonts-cdn/fonts.json`（數值逐字複製自「全域限制」表格）：

```json
{
  "fonts": [
    { "id": "sourceHanSans", "file": "fonts/SourceHanSansTC-VF.ttf", "path": "v1/SourceHanSansTC-VF.ttf", "bytes": 36034016, "sha256": "1a273a56aa47250c7af95e461ee0c8236c60d7141e14a37bd18baccb1e851b19" },
    { "id": "sourceHanSerif", "file": "fonts/SourceHanSerifTC-VF.ttf", "path": "v1/SourceHanSerifTC-VF.ttf", "bytes": 59898316, "sha256": "71354ed752104c8a3cbcff18943c6110d179d01cc6eaaf1aff7ea14c4a447879" },
    { "id": "guanKiapTsingKhai", "file": "fonts/GuanKiapTsingKhai.ttf", "path": "v1/GuanKiapTsingKhai.ttf", "bytes": 14675776, "sha256": "758632243c499e431fd0c847f5e8c431acf59a9b41a26237a819466139994d38" },
    { "id": "taiwanPearl", "file": "fonts/TaiwanPearl-Regular.ttf", "path": "v1/TaiwanPearl-Regular.ttf", "bytes": 21704488, "sha256": "51b3c9a4ab1b6b45dcdad7c5ae93386aea399fd3dabb85d2ac41110dc57f211d" },
    { "id": "genRyuMinTW", "file": "fonts/GenRyuMinTW-Regular.ttf", "path": "v1/GenRyuMinTW-Regular.ttf", "bytes": 15976964, "sha256": "9178c199d633075b8bb91902216c3e1bc977a11fde12471a2c9a250434402927" }
  ]
}
```

- [x] **Step 4：寫共用函式 `scripts/lib.mjs`**

```js
// epic-49 Issue 1：fonts-cdn 腳本共用函式。只用 Node 內建模組。
import { createHash } from 'node:crypto'
import { createReadStream } from 'node:fs'
import { readFile } from 'node:fs/promises'
import { dirname, resolve } from 'node:path'

// 讀取字型清單。baseDir 是清單所在目錄，清單內的 file 欄位相對於它。
export async function readManifest(manifestPath) {
  const absolute = resolve(manifestPath)
  const json = JSON.parse(await readFile(absolute, 'utf8'))
  if (!Array.isArray(json.fonts) || json.fonts.length === 0) {
    throw new Error(`字型清單格式錯誤：${absolute} 缺少 fonts 陣列`)
  }
  return { fonts: json.fonts, baseDir: dirname(absolute) }
}

// 以串流計算檔案的 SHA-256（字型最大約 57MB，不整個讀進記憶體）。
export function sha256OfFile(filePath) {
  return new Promise((resolvePromise, reject) => {
    const hash = createHash('sha256')
    createReadStream(filePath)
      .on('data', (chunk) => hash.update(chunk))
      .on('error', reject)
      .on('end', () => resolvePromise(hash.digest('hex')))
  })
}

// 讀取 --name value 形式的命令列參數；找不到時回傳 fallback。
export function argValue(args, name, fallback = undefined) {
  const index = args.indexOf(name)
  return index >= 0 && index + 1 < args.length ? args[index + 1] : fallback
}
```

- [x] **Step 5：寫自我檢查腳本 `scripts/check_manifest.mjs`**

```js
// epic-49 Issue 1：比對 fonts/ 內實際檔案的大小與 SHA-256 是否和 fonts.json 一致。
// 用法：node fonts-cdn/scripts/check_manifest.mjs [--manifest <路徑>]
// 結束碼：0 = 全部一致；1 = 有不一致或檔案缺漏。
import { stat } from 'node:fs/promises'
import { join } from 'node:path'
import { fileURLToPath } from 'node:url'
import { argValue, readManifest, sha256OfFile } from './lib.mjs'

const defaultManifest = fileURLToPath(new URL('../fonts.json', import.meta.url))
const { fonts, baseDir } = await readManifest(argValue(process.argv, '--manifest', defaultManifest))

let failed = 0
for (const font of fonts) {
  const filePath = join(baseDir, font.file)
  try {
    const { size } = await stat(filePath)
    const digest = await sha256OfFile(filePath)
    if (size !== font.bytes || digest !== font.sha256) {
      failed++
      console.error(`FAIL ${font.id}：大小 ${size}（應為 ${font.bytes}），SHA-256 ${digest}（應為 ${font.sha256}）`)
    } else {
      console.log(`OK   ${font.id}  ${font.path}`)
    }
  } catch (error) {
    failed++
    console.error(`FAIL ${font.id}：無法讀取 ${filePath}（${error.message}）`)
  }
}
if (failed > 0) {
  console.error(`${failed} 個字型與清單不一致`)
  process.exit(1)
}
console.log(`PASS：${fonts.length} 個字型與清單一致`)
```

- [x] **Step 6：執行自我檢查**

Run：`node fonts-cdn/scripts/check_manifest.mjs`
Expected：5 行 `OK`，最後一行 `PASS：5 個字型與清單一致`，結束碼 0。

- [x] **Step 7：確認自我檢查能抓到錯誤**

暫時把 `fonts.json` 中 `genRyuMinTW` 的 `sha256` 最後一個字元改掉，執行 Step 6 的指令。
Expected：`FAIL genRyuMinTW…`，結束碼 1。改回原值並再執行一次，確認回到 PASS。

- [x] **Step 8：更新 `app/pubspec.yaml` 的字型註解**

把字型區塊中這兩行：

```yaml
    # [字型停用] 其餘 3 款同時從字型清單隱藏（見 lib/reader/app_font.dart 的恢復說明）。
    # 原俠正楷字型檔仍在 assets/fonts/；其他字型檔可從 commit eddcc85e 的上一版取回。
```

改為：

```yaml
    # [字型停用] 其餘 3 款同時從字型清單隱藏（見 lib/reader/app_font.dart 的恢復說明）。
    # 5 款字型原檔都放在 repo 根目錄的 fonts-cdn/fonts/（epic-49），不再放在 assets/fonts/。
```

- [x] **Step 9：確認 App 端測試不受影響**

Run（在 `app/`）：`flutter test test/reader/foliate_native_bridge_test.dart`
Expected：全數通過（該測試本來就斷言 5 款字型 asset 都讀不到）。

- [x] **Step 10：Commit**

```bash
git add fonts-cdn/.gitattributes fonts-cdn/package.json fonts-cdn/fonts.json fonts-cdn/scripts/lib.mjs fonts-cdn/scripts/check_manifest.mjs fonts-cdn/fonts app/pubspec.yaml
git add -u app/assets/fonts
git commit -m "feat(fonts-cdn): 新增字型原檔、授權檔與字型清單（epic-49 Issue 1）"
```

---

### Task 2：Worker 與 Node 單元測試

**Files:**
- Create: `fonts-cdn/worker/index.js`、`fonts-cdn/wrangler.toml`、`fonts-cdn/test/test_worker.mjs`

**Interfaces:**
- Consumes：R2 binding `env.FONTS`，只用到 `get(key)` → `R2ObjectBody | null`（有 `size`、`httpEtag`、`body`）與 `head(key)` → `R2Object | null`（有 `size`、`httpEtag`）。
- Produces：`worker/index.js` 預設匯出 `{ fetch(request, env) }`。

- [x] **Step 1：寫失敗的測試 `test/test_worker.mjs`**

```js
// epic-49 Issue 1：Worker 的純 Node 單元測試。以假的 R2 binding 呼叫 fetch。
// 用法：node fonts-cdn/test/test_worker.mjs
// 結束碼：0 = 全數通過；非 0 = 有斷言失敗或例外。
import assert from 'node:assert/strict'
import worker from '../worker/index.js'

// 假的 R2 binding：記錄每次呼叫，讓測試能斷言 HEAD 完全沒有呼叫 get()。
function fakeBucket(objects) {
  const calls = []
  const meta = (key) => ({ size: objects[key].length, httpEtag: `"etag-${key}"` })
  return {
    calls,
    async get(key) {
      calls.push(['get', key])
      if (!(key in objects)) return null
      return { ...meta(key), body: new Blob([objects[key]]).stream() }
    },
    async head(key) {
      calls.push(['head', key])
      return key in objects ? meta(key) : null
    },
  }
}

const FONT_BYTES = new Uint8Array([1, 2, 3, 4, 5])
const request = (method, path) => new Request(`https://elinkbook-fonts.example.workers.dev${path}`, { method })
const call = async (method, path, objects = { 'v1/A.ttf': FONT_BYTES }) => {
  const env = { FONTS: fakeBucket(objects) }
  const response = await worker.fetch(request(method, path), env)
  return { response, calls: env.FONTS.calls }
}

// GET 200：標頭齊全、body 與物件內容相同
{
  const { response, calls } = await call('GET', '/v1/A.ttf')
  assert.equal(response.status, 200)
  assert.equal(response.headers.get('content-type'), 'font/ttf')
  assert.equal(response.headers.get('content-length'), '5')
  assert.equal(response.headers.get('etag'), '"etag-v1/A.ttf"')
  assert.equal(response.headers.get('cache-control'), 'public, max-age=31536000, immutable')
  assert.deepEqual(new Uint8Array(await response.arrayBuffer()), FONT_BYTES)
  assert.deepEqual(calls, [['get', 'v1/A.ttf']])
}

// HEAD 200：標頭與 GET 相同、沒有 body、只呼叫 head()
{
  const { response, calls } = await call('HEAD', '/v1/A.ttf')
  assert.equal(response.status, 200)
  assert.equal(response.headers.get('content-type'), 'font/ttf')
  assert.equal(response.headers.get('content-length'), '5')
  assert.equal(response.headers.get('etag'), '"etag-v1/A.ttf"')
  assert.equal(response.headers.get('cache-control'), 'public, max-age=31536000, immutable')
  assert.equal(response.body, null)
  assert.deepEqual(calls, [['head', 'v1/A.ttf']])
}

// 物件不存在：GET 與 HEAD 都回 404
{
  assert.equal((await call('GET', '/v1/Missing.ttf')).response.status, 404)
  assert.equal((await call('HEAD', '/v1/Missing.ttf')).response.status, 404)
}

// 未來的版本路徑（v2）也能服務，改版時不必重新部署 Worker
{
  const { response } = await call('GET', '/v2/A.ttf', { 'v2/A.ttf': FONT_BYTES })
  assert.equal(response.status, 200)
}

// 不提供列出檔案、非版本路徑、非 .ttf：一律 404，且完全不碰 R2
for (const path of ['/', '/v1/', '/v1', '/A.ttf', '/fonts/A.ttf', '/v1/A.txt', '/v0/A.ttf', '/vx/A.ttf']) {
  const { response, calls } = await call('GET', path)
  assert.equal(response.status, 404, `路徑 ${path} 應回 404`)
  assert.deepEqual(calls, [], `路徑 ${path} 不應呼叫 R2`)
}

// 路徑穿越與編碼字元：一律 404，且完全不碰 R2
for (const path of ['/v1/../A.ttf', '/v1/%2e%2e/A.ttf', '/v1/sub/A.ttf', '/v1/A%2F.ttf']) {
  const { response, calls } = await call('GET', path)
  assert.equal(response.status, 404, `路徑 ${path} 應回 404`)
  assert.deepEqual(calls, [], `路徑 ${path} 不應呼叫 R2`)
}

// GET／HEAD 以外的方法：405，並帶 Allow 標頭
for (const method of ['POST', 'PUT', 'DELETE', 'PATCH']) {
  const { response, calls } = await call(method, '/v1/A.ttf')
  assert.equal(response.status, 405, `${method} 應回 405`)
  assert.equal(response.headers.get('allow'), 'GET, HEAD')
  assert.deepEqual(calls, [])
}

console.log('PASS：test_worker.mjs 全數通過')
```

- [x] **Step 2：執行測試確認失敗**

Run：`node fonts-cdn/test/test_worker.mjs`
Expected：失敗，錯誤為找不到模組 `../worker/index.js`。

- [x] **Step 3：寫 Worker `worker/index.js`**

```js
// epic-49 Issue 1：elinkBook 可下載字型服務（見 docs/adr/0035-downloadable-fonts-via-r2-worker.md）。
// 只提供 GET／HEAD /v<N>/<檔名>.ttf，從 R2 binding FONTS 讀取；不提供列出檔案。
// 已發布的檔案永遠不覆蓋，所以回應可以長期快取（immutable）。

// 版本號從 1 開始；檔名只允許英數、點、底線、連字號，不允許斜線與 %，
// 因此 ..、編碼字元、子目錄都無法通過，杜絕路徑穿越。
const FONT_PATH = /^\/(v[1-9][0-9]*\/[A-Za-z0-9._-]+\.ttf)$/

function headersFor(object) {
  return new Headers({
    'Content-Type': 'font/ttf',
    'Content-Length': String(object.size),
    ETag: object.httpEtag,
    'Cache-Control': 'public, max-age=31536000, immutable',
  })
}

export default {
  async fetch(request, env) {
    const method = request.method
    if (method !== 'GET' && method !== 'HEAD') {
      return new Response('Method Not Allowed', { status: 405, headers: { Allow: 'GET, HEAD' } })
    }
    const match = FONT_PATH.exec(new URL(request.url).pathname)
    // 「..」只剩在檔名中間時（例如 /v1/..ttf）也拒絕，不讓任何含 .. 的 key 進入 R2 查詢
    if (match === null || match[1].includes('..')) {
      return new Response('Not Found', { status: 404 })
    }
    const key = match[1]
    // HEAD 只讀中繼資料，避免為一個 HEAD 請求開啟最大 57MB 的物件串流（設計審查 I-1）
    const object = method === 'HEAD' ? await env.FONTS.head(key) : await env.FONTS.get(key)
    if (object === null) {
      return new Response('Not Found', { status: 404 })
    }
    return new Response(method === 'HEAD' ? null : object.body, { status: 200, headers: headersFor(object) })
  },
}
```

注意：`new URL()` 會把 `/v1/../A.ttf` 正規化成 `/A.ttf`、把 `%2e%2e` 也正規化，所以這兩種都會因為不符合 `FONT_PATH` 而回 404；`%2F` 因為含 `%` 字元而不符合。

- [x] **Step 4：執行測試確認通過**

Run：`node fonts-cdn/test/test_worker.mjs`
Expected：`PASS：test_worker.mjs 全數通過`，結束碼 0。

- [x] **Step 5：寫 `wrangler.toml`**

```toml
# epic-49 Issue 1：elinkBook 可下載字型服務的 Worker 設定。
# 部署：在 fonts-cdn/ 執行 npx wrangler@4 deploy（部署步驟見 deploy-wizard.sh）。
name = "elinkbook-fonts"
main = "worker/index.js"
compatibility_date = "2026-09-01"
workers_dev = true

[[r2_buckets]]
binding = "FONTS"
bucket_name = "elinkbook-fonts"
```

- [x] **Step 6：Commit**

```bash
git add fonts-cdn/worker/index.js fonts-cdn/wrangler.toml fonts-cdn/test/test_worker.mjs
git commit -m "feat(fonts-cdn): 新增字型下載 Worker 與單元測試（epic-49 Issue 1）"
```

---

### Task 3：上傳腳本與線上驗證腳本

**Files:**
- Create: `fonts-cdn/scripts/upload.mjs`、`fonts-cdn/scripts/verify_remote.mjs`、`fonts-cdn/test/test_scripts.mjs`

**Interfaces:**
- Consumes：Task 1 的 `readManifest`、`sha256OfFile`、`argValue`。
- Produces：
  - `node fonts-cdn/scripts/upload.mjs --bucket <bucket> --base-url <Worker 網址> [--manifest <路徑>] [--dry-run]`：結束碼 0 = 全部上傳（或 dry-run 列出指令）；1 = 前置檢查失敗、未上傳任何檔案。
  - `node fonts-cdn/scripts/verify_remote.mjs --base-url <Worker 網址> [--manifest <路徑>]`：結束碼 0 = 全部一致；1 = 有不一致。

- [x] **Step 1：寫失敗的測試 `test/test_scripts.mjs`**

測試用本機 HTTP 伺服器模擬 Worker，用極小的假字型與暫存清單，不需要網路與真實字型。

```js
// epic-49 Issue 1：upload.mjs（--dry-run）與 verify_remote.mjs 的測試。
// 以本機 HTTP 伺服器模擬 Worker；用極小的假字型與暫存清單，不需要網路。
// 用法：node fonts-cdn/test/test_scripts.mjs
import assert from 'node:assert/strict'
import { spawn } from 'node:child_process'
import { createHash } from 'node:crypto'
import { mkdtemp, mkdir, writeFile } from 'node:fs/promises'
import { createServer } from 'node:http'
import { tmpdir } from 'node:os'
import { join } from 'node:path'
import { fileURLToPath } from 'node:url'

const scriptsDir = fileURLToPath(new URL('../scripts/', import.meta.url))
const sha = (bytes) => createHash('sha256').update(bytes).digest('hex')

const FONT_A = Buffer.from('font-a-bytes')
const FONT_B = Buffer.from('font-b-bytes-longer')

// 建立暫存目錄：fonts/A.ttf、fonts/B.ttf 與清單；overrides 可改寫清單欄位
async function makeFixture(overrides = {}) {
  const dir = await mkdtemp(join(tmpdir(), 'fonts-cdn-test-'))
  await mkdir(join(dir, 'fonts'))
  await writeFile(join(dir, 'fonts', 'A.ttf'), FONT_A)
  await writeFile(join(dir, 'fonts', 'B.ttf'), FONT_B)
  const fonts = [
    { id: 'a', file: 'fonts/A.ttf', path: 'v1/A.ttf', bytes: FONT_A.length, sha256: sha(FONT_A), ...overrides.a },
    { id: 'b', file: 'fonts/B.ttf', path: 'v1/B.ttf', bytes: FONT_B.length, sha256: sha(FONT_B), ...overrides.b },
  ]
  const manifest = join(dir, 'fonts.json')
  await writeFile(manifest, JSON.stringify({ fonts }))
  return manifest
}

// 啟動模擬 Worker：served 是 { 'v1/A.ttf': Buffer }，只回應 GET／HEAD
async function startServer(served) {
  const server = createServer((req, res) => {
    const key = req.url.replace(/^\//, '')
    if (!(key in served)) { res.writeHead(404); res.end(); return }
    res.writeHead(200, { 'Content-Type': 'font/ttf', 'Content-Length': served[key].length })
    res.end(req.method === 'HEAD' ? undefined : served[key])
  })
  await new Promise((resolve) => server.listen(0, '127.0.0.1', resolve))
  return { server, baseUrl: `http://127.0.0.1:${server.address().port}` }
}

// 以非同步子行程執行腳本。不能用 spawnSync：它會卡住本行程的事件迴圈，
// 同一行程裡的模擬伺服器就無法回應子行程的請求。
function run(script, args) {
  return new Promise((resolve) => {
    const child = spawn(process.execPath, [join(scriptsDir, script), ...args])
    let stdout = ''
    let stderr = ''
    child.stdout.on('data', (d) => (stdout += d))
    child.stderr.on('data', (d) => (stderr += d))
    child.on('close', (code) => resolve({ code, stdout, stderr }))
  })
}

// upload --dry-run：遠端沒有任何 key → 列出兩條上傳指令、結束碼 0
{
  const manifest = await makeFixture()
  const { server, baseUrl } = await startServer({})
  const result = await run('upload.mjs', ['--bucket', 'test-bucket', '--base-url', baseUrl, '--manifest', manifest, '--dry-run'])
  server.close()
  assert.equal(result.code, 0, result.stderr)
  assert.match(result.stdout, /r2 object put test-bucket\/v1\/A\.ttf/)
  assert.match(result.stdout, /r2 object put test-bucket\/v1\/B\.ttf/)
}

// upload：任一 key 已存在 → 結束碼 1，且不列出任何上傳指令（整批中止，不是略過）
{
  const manifest = await makeFixture()
  const { server, baseUrl } = await startServer({ 'v1/B.ttf': FONT_B })
  const result = await run('upload.mjs', ['--bucket', 'test-bucket', '--base-url', baseUrl, '--manifest', manifest, '--dry-run'])
  server.close()
  assert.equal(result.code, 1)
  assert.match(result.stderr, /v1\/B\.ttf 已存在/)
  assert.doesNotMatch(result.stdout, /r2 object put/)
}

// upload：本機檔案雜湊與清單不符 → 結束碼 1，且不列出任何上傳指令
{
  const manifest = await makeFixture({ b: { sha256: '0'.repeat(64) } })
  const { server, baseUrl } = await startServer({})
  const result = await run('upload.mjs', ['--bucket', 'test-bucket', '--base-url', baseUrl, '--manifest', manifest, '--dry-run'])
  server.close()
  assert.equal(result.code, 1)
  assert.match(result.stderr, /b.*SHA-256/)
  assert.doesNotMatch(result.stdout, /r2 object put/)
}

// upload：連不上下載服務 → 結束碼 1、列出友善訊息，不是未捕獲例外的堆疊
{
  const manifest = await makeFixture()
  const { server, baseUrl } = await startServer({})
  await new Promise((resolve) => server.close(resolve))  // 先關掉伺服器，讓 HEAD 連線被拒
  const result = await run('upload.mjs', ['--bucket', 'test-bucket', '--base-url', baseUrl, '--manifest', manifest, '--dry-run'])
  assert.equal(result.code, 1)
  assert.match(result.stderr, /v1\/A\.ttf：無法連線到下載服務/)
  assert.match(result.stderr, /前置檢查失敗/)
  assert.doesNotMatch(result.stdout, /r2 object put/)
}

// verify_remote：遠端內容與清單一致 → 結束碼 0
{
  const manifest = await makeFixture()
  const { server, baseUrl } = await startServer({ 'v1/A.ttf': FONT_A, 'v1/B.ttf': FONT_B })
  const result = await run('verify_remote.mjs', ['--base-url', baseUrl, '--manifest', manifest])
  server.close()
  assert.equal(result.code, 0, result.stderr)
  assert.match(result.stdout, /PASS/)
}

// verify_remote：內容被竄改但大小相同 → 以 SHA-256 判定失敗
{
  const manifest = await makeFixture()
  const tampered = Buffer.from(FONT_A)
  tampered[0] ^= 0xff
  const { server, baseUrl } = await startServer({ 'v1/A.ttf': tampered, 'v1/B.ttf': FONT_B })
  const result = await run('verify_remote.mjs', ['--base-url', baseUrl, '--manifest', manifest])
  server.close()
  assert.equal(result.code, 1)
  assert.match(result.stderr, /FAIL a/)
}

// verify_remote：遠端缺檔 → 失敗
{
  const manifest = await makeFixture()
  const { server, baseUrl } = await startServer({ 'v1/A.ttf': FONT_A })
  const result = await run('verify_remote.mjs', ['--base-url', baseUrl, '--manifest', manifest])
  server.close()
  assert.equal(result.code, 1)
  assert.match(result.stderr, /FAIL b.*404/)
}

console.log('PASS：test_scripts.mjs 全數通過')
```

- [x] **Step 2：執行測試確認失敗**

Run：`node fonts-cdn/test/test_scripts.mjs`
Expected：第一個斷言失敗（結束碼不是 0，因為 `upload.mjs` 不存在）。

- [x] **Step 3：寫 `scripts/upload.mjs`**

```js
// epic-49 Issue 1：把字型上傳到 R2。已發布的 key 永遠不覆蓋（見 ADR 0035）。
// 用法：node fonts-cdn/scripts/upload.mjs --bucket <bucket> --base-url <Worker 網址> [--manifest <路徑>] [--dry-run]
// 流程：先檢查全部字型（本機雜湊與清單一致、遠端 key 都不存在），全部通過才開始上傳；
// 任何一項不通過就整批中止，不上傳任何檔案。
// 結束碼：0 = 完成（或 dry-run 列出指令）；1 = 前置檢查失敗或上傳失敗。
import { spawnSync } from 'node:child_process'
import { join } from 'node:path'
import { fileURLToPath } from 'node:url'
import { argValue, readManifest, sha256OfFile } from './lib.mjs'

const args = process.argv
const bucket = argValue(args, '--bucket')
const baseUrl = argValue(args, '--base-url')
const dryRun = args.includes('--dry-run')
if (!bucket || !baseUrl) {
  console.error('用法：node upload.mjs --bucket <bucket> --base-url <Worker 網址> [--manifest <路徑>] [--dry-run]')
  process.exit(1)
}
const defaultManifest = fileURLToPath(new URL('../fonts.json', import.meta.url))
const { fonts, baseDir } = await readManifest(argValue(args, '--manifest', defaultManifest))

// 前置檢查：收集所有問題後一次列出
const problems = []
for (const font of fonts) {
  const digest = await sha256OfFile(join(baseDir, font.file))
  if (digest !== font.sha256) {
    problems.push(`${font.id}：本機檔案 SHA-256 ${digest} 與清單 ${font.sha256} 不符`)
  }
  // 連不上（網址打錯、DNS 未生效、離線）時 fetch 會拋例外，也算前置檢查失敗，一起列出
  try {
    const head = await fetch(new URL(font.path, baseUrl.endsWith('/') ? baseUrl : `${baseUrl}/`), { method: 'HEAD' })
    if (head.status === 200) {
      problems.push(`${font.path} 已存在，已發布的檔案不可覆蓋；改版請使用新的版本路徑`)
    } else if (head.status !== 404) {
      problems.push(`${font.path}：無法確認是否已存在（HEAD 回應 ${head.status}）`)
    }
  } catch (error) {
    problems.push(`${font.path}：無法連線到下載服務（${error.cause?.code ?? error.message}）`)
  }
}
if (problems.length > 0) {
  for (const problem of problems) console.error(problem)
  console.error('前置檢查失敗，未上傳任何檔案')
  process.exit(1)
}

for (const font of fonts) {
  const command = ['wrangler@4', 'r2', 'object', 'put', `${bucket}/${font.path}`,
    '--file', join(baseDir, font.file), '--content-type', 'font/ttf', '--remote']
  console.log(`npx ${command.join(' ')}`)
  if (dryRun) continue
  const result = spawnSync('npx', command, { stdio: 'inherit', shell: process.platform === 'win32' })
  if (result.status !== 0) {
    console.error(`上傳 ${font.path} 失敗（結束碼 ${result.status}）`)
    process.exit(1)
  }
}
console.log(dryRun ? 'dry-run：以上為將執行的上傳指令' : `完成：已上傳 ${fonts.length} 個字型`)
```

- [x] **Step 4：寫 `scripts/verify_remote.mjs`**

```js
// epic-49 Issue 1：逐一下載線上字型，比對大小與 SHA-256 是否和清單一致。
// 用法：node fonts-cdn/scripts/verify_remote.mjs --base-url <Worker 網址> [--manifest <路徑>]
// 結束碼：0 = 全部一致；1 = 有不一致、缺檔或連線失敗。
import { createHash } from 'node:crypto'
import { fileURLToPath } from 'node:url'
import { argValue, readManifest } from './lib.mjs'

const baseUrl = argValue(process.argv, '--base-url')
if (!baseUrl) {
  console.error('用法：node verify_remote.mjs --base-url <Worker 網址> [--manifest <路徑>]')
  process.exit(1)
}
const defaultManifest = fileURLToPath(new URL('../fonts.json', import.meta.url))
const { fonts } = await readManifest(argValue(process.argv, '--manifest', defaultManifest))
const base = baseUrl.endsWith('/') ? baseUrl : `${baseUrl}/`

let failed = 0
for (const font of fonts) {
  try {
    const response = await fetch(new URL(font.path, base))
    if (response.status !== 200) {
      failed++
      console.error(`FAIL ${font.id}：HTTP ${response.status}`)
      continue
    }
    // 串流計算雜湊，不把 57MB 整個讀進記憶體
    const hash = createHash('sha256')
    let size = 0
    for await (const chunk of response.body) {
      hash.update(chunk)
      size += chunk.length
    }
    const digest = hash.digest('hex')
    if (size !== font.bytes || digest !== font.sha256) {
      failed++
      console.error(`FAIL ${font.id}：大小 ${size}（應為 ${font.bytes}），SHA-256 ${digest}（應為 ${font.sha256}）`)
    } else {
      console.log(`OK   ${font.id}  ${font.path}`)
    }
  } catch (error) {
    failed++
    console.error(`FAIL ${font.id}：${error.message}`)
  }
}
if (failed > 0) {
  console.error(`${failed} 個字型驗證失敗`)
  process.exit(1)
}
console.log(`PASS：${fonts.length} 個字型線上內容與清單一致`)
```

- [x] **Step 5：執行測試確認通過**

Run：`node fonts-cdn/test/test_scripts.mjs`
Expected：`PASS：test_scripts.mjs 全數通過`，結束碼 0。

- [x] **Step 6：Commit**

```bash
git add fonts-cdn/scripts/upload.mjs fonts-cdn/scripts/verify_remote.mjs fonts-cdn/test/test_scripts.mjs
git commit -m "feat(fonts-cdn): 新增上傳與線上驗證腳本（epic-49 Issue 1）"
```

---

### Task 4：部署 wizard 與 README

**Files:**
- Create: `fonts-cdn/deploy-wizard.sh`、`fonts-cdn/README.md`

**Interfaces:**
- Consumes：Task 2 的 `wrangler.toml`（Worker 與 bucket 名稱）、Task 3 的 `upload.mjs`／`verify_remote.mjs`。
- Produces：`bash fonts-cdn/deploy-wizard.sh`，最後印出 Worker 網址，供人類記錄到 `epic.md`（Issue 2）。

- [x] **Step 1：寫 `deploy-wizard.sh`**

```bash
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
npx wrangler@4 login
npx wrangler@4 whoami

step 4 "建立 R2 bucket：$BUCKET"
if npx wrangler@4 r2 bucket list | grep -q "$BUCKET"; then
  echo "bucket 已存在，略過建立。"
else
  npx wrangler@4 r2 bucket create "$BUCKET"
fi

step 5 "部署 Worker"
npx wrangler@4 deploy
echo
echo "請從上方輸出找到 https://elinkbook-fonts.<你的子網域>.workers.dev 這個網址。"
read -r -p "貼上 Worker 網址：" WORKER_URL
[[ "$WORKER_URL" =~ ^https://[a-z0-9.-]+\.workers\.dev/?$ ]] || { echo "網址格式不正確：$WORKER_URL"; exit 1; }
WORKER_URL="${WORKER_URL%/}"

step 6 "上傳字型（先 dry-run 檢查，再正式上傳）"
node scripts/upload.mjs --bucket "$BUCKET" --base-url "$WORKER_URL" --dry-run
confirm "以上 5 條上傳指令正確？"
node scripts/upload.mjs --bucket "$BUCKET" --base-url "$WORKER_URL"

step 7 "線上驗證"
node scripts/verify_remote.mjs --base-url "$WORKER_URL"

step 8 "完成"
echo "請把以下網址記錄到 docs/epics/epic-49-downloadable-fonts/epic.md（Issue 2 驗收），"
echo "Issue 4 會把它填入 App 的下載服務基底網址常數："
echo
echo "  $WORKER_URL"
```

- [x] **Step 2：語法檢查**

Run：`bash -n fonts-cdn/deploy-wizard.sh`
Expected：沒有任何輸出，結束碼 0。

- [x] **Step 3：寫 `README.md`**

````markdown
# `fonts-cdn/`：elinkBook 可下載字型服務

App 不打包任何字型檔（見 `docs/adr/0035-downloadable-fonts-via-r2-worker.md`）。使用者在「字型管理」點下載時，App 從這裡部署的 Cloudflare Worker 取得字型；Worker 從 R2 bucket `elinkbook-fonts` 讀檔。

## 目錄內容

| 路徑 | 用途 |
|---|---|
| `fonts.json` | 字型清單：`id`（對應 App 的 `AppFont` 列舉名）、本機檔案、發布路徑、位元組大小、SHA-256。**單一事實來源**，App 端的字型目錄必須和它一致（Issue 4 有 Dart 測試比對） |
| `fonts/` | 5 款字型原檔；`fonts/licenses/` 是各字型的 SIL OFL 授權檔 |
| `worker/index.js` | Worker：只提供 `GET`／`HEAD /v<N>/<檔名>.ttf` |
| `scripts/` | 自我檢查、上傳、線上驗證腳本 |
| `test/` | Worker 與腳本的 Node 測試 |
| `deploy-wizard.sh` | 第一次部署的引導腳本 |

## 發布規則

- 已發布的檔案**永遠不覆蓋、不刪除**。已安裝的舊版 App 寫死了網址與 SHA-256，覆蓋會讓它們下載失敗。
- 字型改版時，發布到新的版本路徑（例如 `v2/<檔名>`），並在 `fonts.json` 新增或更新條目，App 發新版時同步更新字型目錄。
- `upload.mjs` 在任一目標 key 已存在時會整批中止，不上傳任何檔案。

## 常用指令（在 repo 根目錄執行，只需要 Node.js 24）

```bash
node fonts-cdn/scripts/check_manifest.mjs                     # 本機檔案與清單是否一致
node fonts-cdn/test/test_worker.mjs                           # Worker 測試
node fonts-cdn/test/test_scripts.mjs                          # 上傳／驗證腳本測試
node fonts-cdn/scripts/verify_remote.mjs --base-url <網址>     # 線上驗證
bash fonts-cdn/deploy-wizard.sh                               # 第一次部署
```

## 費用

R2 免費額度：儲存 10GB、每月 1,000 萬次讀取、下載流量不收費；Worker 免費額度：每天 10 萬次請求。目前 5 款字型合計約 140MB，遠低於上限。啟用 R2 必須綁定付款方式。
````

- [x] **Step 4：Commit**

```bash
git add fonts-cdn/deploy-wizard.sh fonts-cdn/README.md
git commit -m "docs(fonts-cdn): 新增部署 wizard 與 README（epic-49 Issue 1）"
```

---

### Task 5：整體驗證與進度記錄

**Files:**
- Modify: `docs/epics/epic-49-downloadable-fonts/issues.md`（Issue 1 的 `Status`）、`docs/epics/epic-49-downloadable-fonts/epic.md`、`docs/epics.md`（第 50 列備註）

- [x] **Step 1：跑完 Issue 1 所有檢查**

```bash
node fonts-cdn/scripts/check_manifest.mjs
node fonts-cdn/test/test_worker.mjs
node fonts-cdn/test/test_scripts.mjs
bash -n fonts-cdn/deploy-wizard.sh
git ls-files app/assets/fonts | wc -l   # 版控中已沒有 App 字型檔，應為 0
git ls-files --eol fonts-cdn/deploy-wizard.sh   # 應顯示 i/lf w/lf
```

Expected：三支 Node 腳本都印出 `PASS`；`git ls-files` 那行為 `0`；wizard 在 index 與工作目錄都是 LF。

- [x] **Step 2：確認 App 端涉及字型 asset 的測試仍通過**

Run（在 `app/`）：`flutter test test/reader/foliate_native_bridge_test.dart test/reader/app_font_test.dart`
Expected：全數通過。

- [x] **Step 3：更新進度**

- `issues.md` Issue 1 的 `**Status:**` 改為 `completed`。
- `epic.md` 追加一段「Issue 1 完成」記錄：列出新增的目錄與三支測試的結果。
- `docs/epics.md` 第 50 列備註改為「Issue 1 已完成」。

- [x] **Step 4：Commit**

```bash
git add docs/epics.md docs/epics/epic-49-downloadable-fonts/issues.md docs/epics/epic-49-downloadable-fonts/epic.md
git commit -m "docs(epic-49): 記錄 Issue 1 完成"
```
