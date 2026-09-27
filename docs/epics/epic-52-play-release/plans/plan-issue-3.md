# Issue 3：版本號腳本與版本對照表 實作計畫

> **給執行者（agentic worker）：** 必須使用子技能 superpowers:subagent-driven-development（建議）或 superpowers:executing-plans，逐一執行本計畫的 Task。步驟使用核取方塊（`- [ ]`），完成一個就改成 `- [x]`。

**目標：** 新增 `app/tool/bump_version.js`，建置前執行它，會詢問版本號、寫回 `app/pubspec.yaml`，並在 `store/google-play/release-log.md` 加一筆紀錄；同時建立這份對照表。

**架構：** 一支 CommonJS 腳本，分成兩層：
- 純函式：解析、改寫、檢查、格式化，不碰檔案也不碰終端機，給單元測試直接呼叫。
- `main()`：負責讀寫檔案、詢問使用者、呼叫 git。

測試是一支 `.mjs`，用 `node:test` 測純函式，並用 `spawnSync` 在暫存資料夾實際執行腳本，確認端到端行為。

**技術：** Node.js 24、`node:test`、`node:assert/strict`、`node:readline`、`node:child_process`。零外部依賴，不用 `npm install`。

**規格：** `docs/epics/epic-52-play-release/issues.md` Issue 3、`docs/research/google_play_release_sop.md` 第 0 節「版本號規則」與第 2.5、3 節。

## 全域限制

- 只用 Node 內建模組，不加 `package.json`、不加 npm 依賴。慣例比照 `app/tool/check_l10n_hardcoded_strings.js`：CommonJS、`module.exports`、`if (require.main === module)`。
- 預設路徑以腳本所在位置計算（`__dirname`），不受執行時所在目錄影響：
  - `pubspec.yaml`：`app/pubspec.yaml`
  - 對照表：`store/google-play/release-log.md`（repo 根目錄下）
- 另外提供 `--pubspec <路徑>`、`--log <路徑>` 兩個旗標，給測試與驗收指定暫存檔案。
- `version:` 格式固定為 `數字.數字.數字+數字`，例如 `1.0.0+1`。
- 只改 `version:` 那一行，其餘位元組完全不變；CRLF 與 LF 都要保留原樣。
- 對照表表頭固定為 `| versionName | versionCode | 日期 | 軌道 | commit | 說明 |`，日期格式 `YYYY-MM-DD`，腳本新增的紀錄軌道固定是「內部測試」。
- 結束碼：`0` 成功；`1` 使用者輸入中斷（EOF），沒有修改任何檔案；`2` 設定錯誤（檔案不存在、`version:` 格式錯誤、不認得的旗標），沒有修改任何檔案，或是寫檔時發生未預期的錯誤（此時可能只寫了一個檔案，訊息會提醒用 `git status` 確認）。
- 所有給使用者看的訊息用正體中文。錯誤訊息寫出發生什麼、為什麼、要做什麼。
- 本計畫的 shell 指令在 **Git Bash** 執行（repo 根目錄）。Claude Code 的 Bash 工具就是 Git Bash，`mktemp`、`cygpath`、`printf`、`tail`、`diff` 都能直接用。如果執行環境只有 PowerShell（例如 Antigravity），不要把指令改寫成 PowerShell，改用 `& "C:\Program Files\Git\bin\bash.exe" -lc '<指令>'` 包起來執行，或先開一個 Git Bash 再照做。
- 每次執行指令都是新的 shell，變數和 `cd` 不會保留到下一次。每個指令區塊要整塊一次執行。

### 與 Issue 3 規格文字的差異（執行時照本計畫做）

1. **「加 1」的基準改成「`pubspec.yaml` 與對照表最後一筆，兩者較大的 versionCode 再加 1」。**
   規格寫「`pubspec.yaml` 的 versionCode 加 1」。當 `pubspec.yaml` 落後對照表時（例如 3 對 5），加 1 得到 4，仍然不合法；照規格「不合法就重問」，回答 y 或 n 都過不了，會無限重問。改成取較大值後，回答 y 永遠合法。
2. **`--yes` 不需要「加 1 後仍不大於最後一筆」的錯誤分支。** 理由同上，這個分支永遠不會發生，所以不實作。
3. **測試用 `node:test`。** 規格就是這樣寫的；`app/tool/` 其他測試用裸 `assert`，兩者都是零依賴，執行方式一樣是 `node <檔案>`。

Task 3 會把第 1、2 點回寫到 `issues.md`。

## Review Focus

1. **`pubspec.yaml` 落後對照表**：例如 `pubspec.yaml` 是 `+3`、對照表最後一筆是 `5`。使用者預期回答 y 會得到 `6`，而不是被卡在重問迴圈。Task 1 用 `nextVersionCode(3, {code: 5})` 測試，Task 2 端到端情境「pubspec 落後」再確認一次。
2. **輸入中斷**：用管線（pipe）執行或按 Ctrl+Z／Ctrl+D 時，stdin 在回答前就結束。使用者預期腳本結束、檔案都沒被改，而不是卡住。Task 2 端到端情境「EOF」確認結束碼 `1` 且兩個檔案位元組不變。
3. **不是 git repo，或沒有安裝 git**：commit 欄位要填 `unknown`、印出警告，腳本繼續完成。Task 1 用注入的假執行函式測試；Task 2 的暫存資料夾本身就不是 git repo，端到端情境會自然走到這條路徑。
4. **對照表後面還有其他文字**：腳本把新紀錄加在檔案最後。如果有人在表格後面加了說明文字，新紀錄會跑到表格外面。對照表檔頭會寫明「表格必須放在檔案最後」；腳本不另外處理。
5. **使用者輸入大小寫與空白**：`Y`、` y `、`yes`、直接 Enter 都當成「是」；`N`、`no` 當成「否」；其他輸入要重問。Task 2 端到端情境「非預期輸入」確認。

---

### Task 1：純函式與單元測試

**Files:**
- Create: `app/tool/bump_version.js`（本 Task 只放純函式與 `module.exports`）
- Create: `app/tool/test_bump_version.mjs`

**Interfaces:**
- Consumes：無。
- Produces（`module.exports`，Task 2 會用到）：
  - `parsePubspecVersion(text: string) → { name: string, code: number }`，格式錯誤時丟出 `Error`（訊息是正體中文）。
  - `replacePubspecVersion(text: string, name: string, code: number) → string`
  - `parseLogEntries(text: string) → Array<{ name, code: number, date, track, commit, note }>`
  - `lastLogEntry(text: string) → 上面的物件 | null`
  - `isValidVersionName(s: string) → boolean`
  - `nextVersionCode(pubspecCode: number, last: object | null) → number`
  - `checkVersionCode(code: number, last: object | null) → string | null`（`null` 表示合法，否則是錯誤訊息）
  - `formatDate(d: Date) → string`（本地時間 `YYYY-MM-DD`）
  - `getHeadCommit(run?: (cmd: string) => string | Buffer) → string`（失敗時回傳 `'unknown'`）
  - `appendLogEntry(text: string, entry: { name, code, date, track, commit, note }) → string`

- [x] **Step 1：開分支**

```bash
git switch main && git pull
git switch -c epic-52/issue-3-bump-version
```

- [x] **Step 2：寫失敗的單元測試**

建立 `app/tool/test_bump_version.mjs`：

```js
// epic-52-play-release Issue 3：bump_version.js 行為驗證。
// 零外部依賴，用 Node.js 內建的 node:test 執行。
//
// 用法：node app/tool/test_bump_version.mjs

import { test } from 'node:test'
import assert from 'node:assert/strict'
import bump from './bump_version.js'

const {
  parsePubspecVersion,
  replacePubspecVersion,
  parseLogEntries,
  lastLogEntry,
  isValidVersionName,
  nextVersionCode,
  checkVersionCode,
  formatDate,
  getHeadCommit,
  appendLogEntry,
} = bump

// 對照表範本：說明文字、表頭、分隔線，沒有資料列
const LOG_HEADER = [
  '# Google Play 版本對照表',
  '',
  '- 說明文字 | 裡面有直線符號也不能被當成資料列',
  '',
  '| versionName | versionCode | 日期 | 軌道 | commit | 說明 |',
  '|---|---|---|---|---|---|',
  '',
].join('\n')

const LOG_TWO_ROWS =
  LOG_HEADER +
  '| 1.0.0 | 1 | 2026-10-01 | 內部測試 | e1a12ed6 | 第一次上傳 |\n' +
  '| 1.0.0 | 1 | 2026-10-03 | 正式版 | e1a12ed6 |  |\n'

test('parsePubspecVersion：解析 name 與 code', () => {
  const text = 'name: app\nversion: 1.0.1+5\nenvironment:\n'
  assert.deepEqual(parsePubspecVersion(text), { name: '1.0.1', code: 5 })
})

test('parsePubspecVersion：不理會註解裡的 version 字樣', () => {
  const text = '# Read more about iOS versioning\n# version: 9.9.9+99\nversion: 1.0.0+1\n'
  assert.deepEqual(parsePubspecVersion(text), { name: '1.0.0', code: 1 })
})

test('parsePubspecVersion：找不到或格式錯誤時丟出錯誤', () => {
  assert.throws(() => parsePubspecVersion('name: app\n'), /找不到 version:/)
  assert.throws(() => parsePubspecVersion('version: 1.0.0\n'), /格式不對/)
  assert.throws(() => parsePubspecVersion('version: 1.0+3\n'), /格式不對/)
})

test('replacePubspecVersion：LF 檔案只改 version 那一行', () => {
  const before = 'name: app\n\n# 註解\nversion: 1.0.1+5\ndependencies:\n'
  const after = 'name: app\n\n# 註解\nversion: 1.0.2+6\ndependencies:\n'
  assert.equal(replacePubspecVersion(before, '1.0.2', 6), after)
})

test('replacePubspecVersion：CRLF 檔案保留 \\r\\n，其餘位元組不變', () => {
  const before = 'name: app\r\n\r\nversion: 1.0.1+5\r\n# 註解\r\n'
  const after = 'name: app\r\n\r\nversion: 1.0.1+6\r\n# 註解\r\n'
  assert.equal(replacePubspecVersion(before, '1.0.1', 6), after)
})

test('parseLogEntries／lastLogEntry：只有表頭時沒有紀錄', () => {
  assert.deepEqual(parseLogEntries(LOG_HEADER), [])
  assert.equal(lastLogEntry(LOG_HEADER), null)
})

test('lastLogEntry：回傳最後一筆資料列', () => {
  assert.deepEqual(lastLogEntry(LOG_TWO_ROWS), {
    name: '1.0.0',
    code: 1,
    date: '2026-10-03',
    track: '正式版',
    commit: 'e1a12ed6',
    note: '',
  })
})

test('lastLogEntry：CRLF 對照表也能解析', () => {
  const crlf = LOG_TWO_ROWS.replace(/\n/g, '\r\n')
  assert.equal(lastLogEntry(crlf).track, '正式版')
})

test('parseLogEntries：說明欄裡有 | 時不截斷', () => {
  const text = LOG_HEADER + '| 1.0.2 | 3 | 2026-10-12 | 內部測試 | abc1234 | 修正 A | B 問題 |
'
  assert.equal(lastLogEntry(text).note, '修正 A | B 問題')
})

test('isValidVersionName：只接受 數字.數字.數字', () => {
  for (const ok of ['1.0.0', '10.20.30', '0.0.1']) assert.equal(isValidVersionName(ok), true, ok)
  for (const bad of ['1.0', '1.0.0.1', 'a.b.c', '1.0.0+1', ' 1.0.0', '']) {
    assert.equal(isValidVersionName(bad), false, bad)
  }
})

test('nextVersionCode：取 pubspec 與最後一筆較大者再加 1', () => {
  assert.equal(nextVersionCode(5, null), 6)
  assert.equal(nextVersionCode(5, { code: 5 }), 6)
  assert.equal(nextVersionCode(7, { code: 5 }), 8)
  // Review Focus 1：pubspec 落後對照表
  assert.equal(nextVersionCode(3, { code: 5 }), 6)
})

test('checkVersionCode：對照表沒有紀錄時，正整數都接受', () => {
  assert.equal(checkVersionCode(1, null), null)
  assert.match(checkVersionCode(0, null), /正整數/)
})

test('checkVersionCode：必須大於最後一筆', () => {
  const last = { name: '1.0.1', code: 5, date: '2026-10-10' }
  assert.equal(checkVersionCode(6, last), null)
  assert.match(checkVersionCode(5, last), /最後一筆是 5/)
  assert.match(checkVersionCode(4, last), /最後一筆是 5/)
})

test('formatDate：本地時間 YYYY-MM-DD，月和日補零', () => {
  assert.equal(formatDate(new Date(2026, 0, 5, 23, 59)), '2026-01-05')
  assert.match(formatDate(new Date()), /^\d{4}-\d{2}-\d{2}$/)
})

test('getHeadCommit：成功時回傳去掉換行的結果', () => {
  assert.equal(getHeadCommit(() => Buffer.from('abc1234\n')), 'abc1234')
})

test('getHeadCommit：git 失敗時回傳 unknown，不丟出例外', () => {
  const fail = () => {
    throw new Error('git: command not found')
  }
  assert.equal(getHeadCommit(fail), 'unknown')
  assert.equal(getHeadCommit(() => ''), 'unknown')
})

test('appendLogEntry：新增一筆，舊內容不變', () => {
  const entry = { name: '1.0.1', code: 2, date: '2026-10-10', track: '內部測試', commit: 'abc1234', note: '' }
  const result = appendLogEntry(LOG_TWO_ROWS, entry)
  assert.ok(result.startsWith(LOG_TWO_ROWS))
  assert.equal(result.slice(LOG_TWO_ROWS.length), '| 1.0.1 | 2 | 2026-10-10 | 內部測試 | abc1234 |  |\n')
  assert.deepEqual(lastLogEntry(result), entry)
})

test('appendLogEntry：CRLF 檔案用 CRLF；檔尾沒有換行時先補一個', () => {
  const entry = { name: '1.0.0', code: 1, date: '2026-10-01', track: '內部測試', commit: 'unknown', note: '' }
  const crlf = LOG_HEADER.replace(/\n/g, '\r\n')
  assert.ok(appendLogEntry(crlf, entry).endsWith('|  |\r\n'))
  const noTrailing = LOG_HEADER.trimEnd()
  assert.equal(appendLogEntry(noTrailing, entry), noTrailing + '\n| 1.0.0 | 1 | 2026-10-01 | 內部測試 | unknown |  |\n')
})
```

- [x] **Step 3：確認測試失敗**

```bash
node app/tool/test_bump_version.mjs
```

Expected：失敗，錯誤是找不到 `./bump_version.js`（`ERR_MODULE_NOT_FOUND`）。

- [x] **Step 4：實作純函式**

建立 `app/tool/bump_version.js`：

```js
// epic-52-play-release Issue 3：版本號腳本。
//
// 建置要上傳到 Google Play 的 .aab 之前執行。它會：
//   1. 顯示 app/pubspec.yaml 目前的版本，以及版本對照表最後一筆紀錄。
//   2. 詢問 versionCode 要不要加 1、versionName 要不要改。
//   3. 寫回 pubspec.yaml（只改 version: 那一行），並在對照表加一筆「內部測試」紀錄。
// 流程見 docs/research/google_play_release_sop.md 第 2.5、3 節。
// 慣例比照 check_l10n_hardcoded_strings.js（純 Node 內建模組、免 npm install）。
//
// 用法（在 app/ 目錄下）：
//   node tool/bump_version.js                 # 互動式詢問
//   node tool/bump_version.js --yes           # 不詢問：versionCode 加 1、versionName 不變
//   node tool/bump_version.js --pubspec <路徑> --log <路徑>   # 指定檔案（測試／驗收用）
//
// 結束碼 0：成功；1：輸入中斷，沒有修改任何檔案；2：設定錯誤，沒有修改任何檔案。

const fs = require('fs');
const path = require('path');
const readline = require('readline');
const { execSync } = require('child_process');

const DEFAULT_PUBSPEC = path.join(__dirname, '..', 'pubspec.yaml');
const DEFAULT_LOG = path.join(__dirname, '..', '..', 'store', 'google-play', 'release-log.md');

// 行首的 version: 那一行。[^\r\n]* 不吃換行字元，替換時原本的 \r\n 或 \n 會留著。
// JavaScript 的 m 旗標把 \r 也當成行尾，所以 $ 會停在 \r 之前。
const VERSION_LINE = /^version:[ \t]*([^\r\n]*)$/m;
const VERSION_VALUE = /^(\d+\.\d+\.\d+)\+(\d+)$/;
const VERSION_NAME = /^\d+\.\d+\.\d+$/;

function parsePubspecVersion(text) {
  const line = VERSION_LINE.exec(text);
  if (!line) {
    throw new Error('pubspec.yaml 裡找不到 version: 這一行。請確認檔案是 Flutter 專案的 pubspec.yaml。');
  }
  const value = line[1].trim();
  const parts = VERSION_VALUE.exec(value);
  if (!parts) {
    throw new Error(
      `pubspec.yaml 的版本「${value}」格式不對。應該是「數字.數字.數字+數字」，例如 1.0.0+1。請先手動修正再執行。`
    );
  }
  return { name: parts[1], code: Number(parts[2]) };
}

function replacePubspecVersion(text, name, code) {
  return text.replace(VERSION_LINE, `version: ${name}+${code}`);
}

// 對照表的資料列：以 | 開頭，而且第 2 欄（versionCode）是數字。
// 表頭（versionCode）、分隔線（---）和說明文字都會被排除。
function parseLogEntries(text) {
  return text
    .split(/\r?\n/)
    .map((line) => line.trim())
    .filter((line) => line.startsWith('|'))
    .map((line) => line.replace(/^\|/, '').replace(/\|$/, '').split('|').map((cell) => cell.trim()))
    .filter((cells) => cells.length >= 6 && /^\d+$/.test(cells[1]))
    .map((cells) => ({
      name: cells[0],
      code: Number(cells[1]),
      date: cells[2],
      track: cells[3],
      commit: cells[4],
      // 說明欄裡如果有 |，會被 split 切開，這裡接回去。
      note: cells.slice(5).join(' | '),
    }));
}

function lastLogEntry(text) {
  const entries = parseLogEntries(text);
  return entries.length > 0 ? entries[entries.length - 1] : null;
}

function isValidVersionName(s) {
  return VERSION_NAME.test(s);
}

// 「加 1」的基準取 pubspec 與對照表最後一筆較大者，
// 這樣 pubspec 落後對照表時，回答「加 1」也一定合法，不會卡在重問迴圈。
function nextVersionCode(pubspecCode, last) {
  return Math.max(pubspecCode, last ? last.code : 0) + 1;
}

function checkVersionCode(code, last) {
  if (!Number.isInteger(code) || code < 1) {
    return `versionCode 必須是正整數，目前是 ${code}。`;
  }
  if (last && code <= last.code) {
    return `Play 不收重複或變小的 versionCode，對照表最後一筆是 ${last.code}（${last.name}，${last.date}）。請回答 y 讓腳本加 1。`;
  }
  return null;
}

function formatDate(d) {
  const pad = (n) => String(n).padStart(2, '0');
  return `${d.getFullYear()}-${pad(d.getMonth() + 1)}-${pad(d.getDate())}`;
}

function defaultRun(cmd) {
  return execSync(cmd, { stdio: ['ignore', 'pipe', 'ignore'] });
}

// 取得目前 HEAD 的短 hash。沒有 git、不在 repo 裡等任何失敗都回傳 unknown。
function getHeadCommit(run = defaultRun) {
  try {
    const out = String(run('git rev-parse --short HEAD')).trim();
    return out || 'unknown';
  } catch {
    return 'unknown';
  }
}

function appendLogEntry(text, entry) {
  const nl = text.includes('\r\n') ? '\r\n' : '\n';
  const row = `| ${entry.name} | ${entry.code} | ${entry.date} | ${entry.track} | ${entry.commit} | ${entry.note} |`;
  const base = text.length === 0 || text.endsWith('\n') ? text : text + nl;
  return base + row + nl;
}

module.exports = {
  parsePubspecVersion,
  replacePubspecVersion,
  parseLogEntries,
  lastLogEntry,
  isValidVersionName,
  nextVersionCode,
  checkVersionCode,
  formatDate,
  getHeadCommit,
  appendLogEntry,
};
```

`fs`、`readline`、`DEFAULT_PUBSPEC`、`DEFAULT_LOG` 在 Task 2 的 `main()` 才會用到，先宣告沒關係。

- [x] **Step 5：確認測試通過**

```bash
node app/tool/test_bump_version.mjs
```

Expected：`# pass 18`、`# fail 0`，結束碼 `0`。

- [x] **Step 6：Commit**

```bash
git add app/tool/bump_version.js app/tool/test_bump_version.mjs
git commit -m "feat(tool): bump_version.js 版本號解析與對照表純函式（epic-52 Issue 3）"
```

---

### Task 2：`main()`、對照表檔案與端到端測試

**Files:**
- Modify: `app/tool/bump_version.js`（在 `module.exports` 之前加入 `parseArgs`、`main`；檔尾加入 `require.main` 判斷）
- Modify: `app/tool/test_bump_version.mjs`（檔尾加入端到端測試）
- Create: `store/google-play/release-log.md`

**Interfaces:**
- Consumes：Task 1 的全部純函式。
- Produces：CLI `node app/tool/bump_version.js [--yes] [--pubspec <路徑>] [--log <路徑>]`，結束碼 `0`／`1`／`2`。

- [x] **Step 1：寫失敗的端到端測試**

在 `app/tool/test_bump_version.mjs` 最上方的 import 區加入：

```js
import fs from 'node:fs'
import os from 'node:os'
import path from 'node:path'
import { fileURLToPath } from 'node:url'
import { spawnSync } from 'node:child_process'
```

在檔案最後加入：

```js
// ---- 端到端：在暫存資料夾實際執行腳本 ----
// 暫存資料夾不是 git repo，所以 commit 欄位會是 unknown（Review Focus 3）。

const SCRIPT = path.join(path.dirname(fileURLToPath(import.meta.url)), 'bump_version.js')

// GIT_CEILING_DIRECTORIES 讓 git 不會往暫存資料夾的上層找 repo，
// 即使系統暫存資料夾剛好在某個 git repo 底下，commit 欄位也固定是 unknown。
// t.after 在每個測試結束後刪除暫存資料夾。
function setup(t, pubspec, log) {
  const dir = fs.mkdtempSync(path.join(os.tmpdir(), 'bump-version-'))
  t.after(() => fs.rmSync(dir, { recursive: true, force: true }))
  const pubspecPath = path.join(dir, 'pubspec.yaml')
  const logPath = path.join(dir, 'release-log.md')
  fs.writeFileSync(pubspecPath, pubspec)
  if (log !== undefined) fs.writeFileSync(logPath, log)
  const run = (args, input = '') =>
    spawnSync(process.execPath, [SCRIPT, '--pubspec', pubspecPath, '--log', logPath, ...args], {
      input,
      encoding: 'utf8',
      cwd: dir,
      env: { ...process.env, GIT_CEILING_DIRECTORIES: os.tmpdir() },
    })
  const read = () => ({
    pubspec: fs.readFileSync(pubspecPath, 'utf8'),
    log: fs.existsSync(logPath) ? fs.readFileSync(logPath, 'utf8') : null,
  })
  return { dir, run, read }
}

const PUBSPEC_CRLF = 'name: app\r\n# version: 註解\r\nversion: 1.0.1+5\r\ndependencies:\r\n'
const LOG_LAST_5 = LOG_HEADER + '| 1.0.1 | 5 | 2026-10-10 | 內部測試 | abc1234 |  |\n'
const TODAY = formatDate(new Date())

test('端到端 --yes：versionCode 加 1，保留 CRLF，對照表加一筆', (t) => {
  const { run, read } = setup(t, PUBSPEC_CRLF, LOG_LAST_5)
  const r = run(['--yes'])
  assert.equal(r.status, 0, r.stderr)
  assert.equal(read().pubspec, PUBSPEC_CRLF.replace('1.0.1+5', '1.0.1+6'))
  assert.equal(read().log, LOG_LAST_5 + `| 1.0.1 | 6 | ${TODAY} | 內部測試 | unknown |  |\n`)
  assert.match(r.stdout + r.stderr, /unknown/)
})

test('端到端 第一次上架：對照表沒有紀錄，回答 n 保留 1.0.0+1', (t) => {
  const pubspec = 'name: app\nversion: 1.0.0+1\n'
  const { run, read } = setup(t, pubspec, LOG_HEADER)
  const r = run([], 'n\n\n')
  assert.equal(r.status, 0, r.stderr)
  assert.equal(read().pubspec, pubspec)
  assert.equal(lastLogEntry(read().log).code, 1)
  assert.equal(lastLogEntry(read().log).name, '1.0.0')
})

test('端到端 回答 n 但數字不夠大：印出原因並重問，改答 y 後成功', (t) => {
  const { run, read } = setup(t, 'version: 1.0.1+5\n', LOG_LAST_5)
  const r = run([], 'n\ny\n1.1.0\n')
  assert.equal(r.status, 0, r.stderr)
  assert.match(r.stdout, /最後一筆是 5/)
  assert.equal(read().pubspec, 'version: 1.1.0+6\n')
  assert.equal(lastLogEntry(read().log).name, '1.1.0')
})

test('端到端 pubspec 落後對照表：回答 y 得到最後一筆加 1', (t) => {
  const { run, read } = setup(t, 'version: 1.0.1+3\n', LOG_LAST_5)
  const r = run([], 'y\n\n')
  assert.equal(r.status, 0, r.stderr)
  assert.equal(read().pubspec, 'version: 1.0.1+6\n')
})

test('端到端 非預期輸入：大小寫、空白、錯誤格式都會重問', (t) => {
  const { run, read } = setup(t, 'version: 1.0.1+5\n', LOG_LAST_5)
  const r = run([], 'maybe\n  Y  \n1.0\n1.2.0\n')
  assert.equal(r.status, 0, r.stderr)
  assert.match(r.stdout, /請輸入 y 或 n/)
  assert.match(r.stdout, /數字\.數字\.數字/)
  assert.equal(read().pubspec, 'version: 1.2.0+6\n')
})

test('端到端 EOF：輸入中斷時結束碼 1，兩個檔案都不變', (t) => {
  const { run, read } = setup(t, PUBSPEC_CRLF, LOG_LAST_5)
  const r = run([], '')
  assert.equal(r.status, 1)
  assert.equal(read().pubspec, PUBSPEC_CRLF)
  assert.equal(read().log, LOG_LAST_5)
})

test('端到端 找不到對照表：結束碼 2，pubspec 不變', (t) => {
  const { run, read } = setup(t, PUBSPEC_CRLF, undefined)
  const r = run(['--yes'])
  assert.equal(r.status, 2)
  assert.match(r.stderr, /找不到/)
  assert.equal(read().pubspec, PUBSPEC_CRLF)
})

test('端到端 pubspec 版本格式錯誤：結束碼 2，檔案都不變', (t) => {
  const { run, read } = setup(t, 'version: 1.0\n', LOG_LAST_5)
  const r = run(['--yes'])
  assert.equal(r.status, 2)
  assert.match(r.stderr, /格式不對/)
  assert.equal(read().pubspec, 'version: 1.0\n')
  assert.equal(read().log, LOG_LAST_5)
})

test('端到端 不認得的旗標：結束碼 2', (t) => {
  const { run } = setup(t, 'version: 1.0.1+5\n', LOG_LAST_5)
  const r = run(['--force'])
  assert.equal(r.status, 2)
  assert.match(r.stderr, /--force/)
})
```

- [x] **Step 2：確認新測試失敗**

```bash
node app/tool/test_bump_version.mjs
```

Expected：Task 1 的 18 個測試通過，9 個端到端測試失敗（腳本還沒有 `main()`，執行後什麼都不做、結束碼 `0`，檔案沒有被改）。

- [x] **Step 3：實作 `parseArgs` 與 `main`**

在 `app/tool/bump_version.js` 的 `module.exports = {` 之前加入：

```js
function parseArgs(argv) {
  const opts = { yes: false, pubspec: DEFAULT_PUBSPEC, log: DEFAULT_LOG };
  for (let i = 0; i < argv.length; i++) {
    const arg = argv[i];
    if (arg === '--yes') {
      opts.yes = true;
    } else if (arg === '--pubspec' || arg === '--log') {
      const value = argv[++i];
      if (!value) throw new Error(`${arg} 後面要接檔案路徑。`);
      opts[arg.slice(2)] = value;
    } else {
      throw new Error(`不認得的參數「${arg}」。可用的參數：--yes、--pubspec <路徑>、--log <路徑>。`);
    }
  }
  return opts;
}

function readRequired(filePath, label) {
  if (!fs.existsSync(filePath)) {
    throw new Error(`找不到 ${label}：${filePath}。請確認檔案存在，或用參數指定正確路徑。`);
  }
  return fs.readFileSync(filePath, 'utf8');
}

async function main(argv, { input = process.stdin, output = process.stdout, errorOutput = process.stderr } = {}) {
  const say = (msg) => output.write(msg + '\n');
  const fail = (msg) => errorOutput.write(msg + '\n');

  let opts;
  let pubspecText;
  let logText;
  let current;
  try {
    opts = parseArgs(argv);
    pubspecText = readRequired(opts.pubspec, 'pubspec.yaml');
    logText = readRequired(opts.log, '版本對照表');
    current = parsePubspecVersion(pubspecText);
  } catch (e) {
    fail(`沒有修改任何檔案。${e.message}`);
    return 2;
  }

  const last = lastLogEntry(logText);
  const next = nextVersionCode(current.code, last);
  say(`目前版本：${current.name}+${current.code}`);
  say(last ? `對照表最後一筆：${last.name}+${last.code}（${last.track}，${last.date}）` : '對照表最後一筆：尚無紀錄');

  let code;
  let name;
  if (opts.yes) {
    code = next;
    name = current.name;
  } else {
    // 用非同步迭代逐行讀取：stdin 提早結束（EOF）時 next() 會回傳 done，不會卡住。
    const rl = readline.createInterface({ input, terminal: false });
    const lines = rl[Symbol.asyncIterator]();
    const ask = async (question) => {
      output.write(question);
      const { value, done } = await lines.next();
      if (done) return null;
      return value.trim();
    };
    try {
      for (;;) {
        const answer = await ask(`versionCode 要加 1 嗎？（${current.code} → ${next}）[Y/n] `);
        if (answer === null) break;
        const a = answer.toLowerCase();
        if (a === '' || a === 'y' || a === 'yes') code = next;
        else if (a === 'n' || a === 'no') code = current.code;
        else {
          say('請輸入 y 或 n。');
          continue;
        }
        const error = checkVersionCode(code, last);
        if (error) {
          say(error);
          code = undefined;
          continue;
        }
        break;
      }
      if (code !== undefined) {
        for (;;) {
          const answer = await ask(`versionName（目前 ${current.name}，直接 Enter 表示不改）：`);
          if (answer === null) break;
          if (answer === '') {
            name = current.name;
            break;
          }
          if (isValidVersionName(answer)) {
            name = answer;
            break;
          }
          say('versionName 格式要是「數字.數字.數字」，例如 1.0.1。');
        }
      }
    } finally {
      rl.close();
    }
    if (code === undefined || name === undefined) {
      output.write('\n');
      fail('輸入中斷，沒有修改任何檔案。');
      return 1;
    }
  }

  const commit = getHeadCommit((cmd) =>
    execSync(cmd, { cwd: path.dirname(path.resolve(opts.pubspec)), stdio: ['ignore', 'pipe', 'ignore'] })
  );
  if (commit === 'unknown') {
    fail('警告：無法執行 git rev-parse，對照表的 commit 欄位填 unknown。');
  }

  const entry = { name, code, date: formatDate(new Date()), track: '內部測試', commit, note: '' };
  fs.writeFileSync(opts.pubspec, replacePubspecVersion(pubspecText, name, code));
  fs.writeFileSync(opts.log, appendLogEntry(logText, entry));

  say(`已更新 pubspec.yaml：version: ${name}+${code}`);
  say(`已在對照表加一筆：${name}+${code}（內部測試，${entry.date}，commit ${commit}）`);
  say('下一步（在 app/ 目錄下）：');
  say('  git add pubspec.yaml ../store/google-play/release-log.md');
  say(`  git commit -m "chore(release): ${name}+${code}"`);
  return 0;
}
```

把 `module.exports` 改成：

```js
module.exports = {
  parsePubspecVersion,
  replacePubspecVersion,
  parseLogEntries,
  lastLogEntry,
  isValidVersionName,
  nextVersionCode,
  checkVersionCode,
  formatDate,
  getHeadCommit,
  appendLogEntry,
  parseArgs,
  main,
};

if (require.main === module) {
  // 用 exitCode 而不是 process.exit()：輸出接到管線時，process.exit() 可能在寫完前就結束。
  main(process.argv.slice(2))
    .then((code) => {
      process.exitCode = code;
    })
    .catch((err) => {
      // 寫檔時的權限不足、檔案被鎖定等未預期錯誤。
      process.stderr.write(
        `發生未預期的錯誤：${err.message}。pubspec.yaml 或對照表可能只更新了一個，請用 git status 確認。\n`
      );
      process.exitCode = 2;
    });
}
```

`defaultRun` 在 Task 1 已宣告，`main()` 另外傳入帶 `cwd` 的執行函式，讓 `--pubspec` 指到其他資料夾時，commit 取的是那個資料夾所在 repo 的 HEAD。

- [x] **Step 4：確認全部測試通過**

```bash
node app/tool/test_bump_version.mjs
```

Expected：`# pass 27`、`# fail 0`，結束碼 `0`。

- [x] **Step 5：建立版本對照表**

repo 裡還沒有 `store/` 資料夾，先建立：

```bash
mkdir -p store/google-play
```

建立 `store/google-play/release-log.md`：

```markdown
# Google Play 版本對照表

每次上傳到 Google Play 都記一筆。流程見 `docs/research/google_play_release_sop.md`。

- 建置前在 `app/` 下執行 `node tool/bump_version.js`，腳本會自動加一筆「內部測試」紀錄。
- 推到正式版時，手動加一筆，軌道寫「正式版」，commit 欄位抄內部測試那一筆。
- 內部測試版有問題、沒推到正式版時，在說明欄註記「棄用」。
- 日期格式：`YYYY-MM-DD`。
- commit：執行 `bump_version.js` 當下的 HEAD，也就是這一版程式碼的最後一個 commit。git tag 指向之後的版本號 commit，兩者相差一個 commit。
- **表格必須放在檔案最後**。腳本會把新紀錄加在檔案結尾。

| versionName | versionCode | 日期 | 軌道 | commit | 說明 |
|---|---|---|---|---|---|
```

確認腳本讀得到它、而且目前沒有紀錄：

```bash
node -e "const b=require('./app/tool/bump_version.js');const t=require('fs').readFileSync('store/google-play/release-log.md','utf8');console.log(b.lastLogEntry(t))"
```

Expected：印出 `null`。

- [x] **Step 6：Commit**

```bash
git add app/tool/bump_version.js app/tool/test_bump_version.mjs store/google-play/release-log.md
git commit -m "feat(tool): bump_version.js 互動流程與版本對照表（epic-52 Issue 3）"
```

---

### Task 3：實際演練、文件與收尾

**Files:**
- Modify: `app/tool/README.md`（新增 `bump_version.js` 一節）
- Modify: `docs/epics/epic-52-play-release/issues.md`（Issue 3 的 Status 與規格差異）
- Modify: `docs/epics/epic-52-play-release/epic.md`（開發記錄）
- Modify: `docs/epics.md`（`epic-52-play-release` 那一列的備註）

**Interfaces:**
- Consumes：Task 2 的 CLI。
- Produces：無。

- [x] **Step 1：用真實檔案的複本演練一次**

```bash
T=$(cygpath -m "$(mktemp -d)")
cp app/pubspec.yaml "$T/pubspec.yaml"
cp store/google-play/release-log.md "$T/release-log.md"
printf 'n\n\n' | node app/tool/bump_version.js --pubspec "$T/pubspec.yaml" --log "$T/release-log.md"
echo "exit=$?"
diff app/pubspec.yaml "$T/pubspec.yaml" && echo "pubspec 位元組相同"
tail -1 "$T/release-log.md"
node app/tool/bump_version.js --yes --pubspec "$T/pubspec.yaml" --log "$T/release-log.md"
diff app/pubspec.yaml "$T/pubspec.yaml"
tail -2 "$T/release-log.md"
rm -rf "$T"
```

Expected：
- 第一次：`exit=0`；`pubspec 位元組相同`（第一次上架保留 `1.0.0+1`）；對照表最後一行是 `| 1.0.0 | 1 | <今天> | 內部測試 | unknown |  |`（暫存資料夾不是 git repo，並印出 unknown 警告）。
- 第二次：`diff` 只顯示 `version: 1.0.0+1` 變成 `version: 1.0.0+2` 這一行；對照表最後兩行是 versionCode `1` 和 `2`。
- 真正的 `app/pubspec.yaml` 和 `store/google-play/release-log.md` 沒有被改：

```bash
git status --short app/pubspec.yaml store/google-play/release-log.md
```

Expected：沒有輸出。

- [x] **Step 2：在 repo 內確認 commit 欄位**

把複本放在 `app/build/bump-rehearsal/`。這個資料夾在 repo 裡面（`app/.gitignore` 忽略了 `/build/`），所以腳本取得的是這個 repo 的 HEAD，而且完全不會碰到真正的 `app/pubspec.yaml` 和對照表。

```bash
R=app/build/bump-rehearsal
mkdir -p "$R"
cp app/pubspec.yaml store/google-play/release-log.md "$R/"
node app/tool/bump_version.js --yes --pubspec "$R/pubspec.yaml" --log "$R/release-log.md"
tail -1 "$R/release-log.md"
git rev-parse --short HEAD
rm -rf "$R"
git status --short
```

Expected：對照表最後一行的 commit 欄位等於 `git rev-parse --short HEAD` 的輸出；最後的 `git status` 沒有輸出（真實檔案沒有被改）。

- [x] **Step 3：更新 `app/tool/README.md`**

在 `## \`check_foliate_es_compat.js\`` 那一節之前插入：

````markdown
## `bump_version.js`

建置要上傳到 Google Play 的 `.aab` 之前，用它更新版本號並記錄到版本對照表
（epic-52-play-release Issue 3）。它會顯示目前版本和 `store/google-play/release-log.md`
最後一筆，詢問 versionCode 要不要加 1、versionName 要不要改，再寫回
`app/pubspec.yaml`（只改 `version:` 那一行，保留原本的換行符號），並在對照表加一筆
「內部測試」紀錄。完整發布流程見 `docs/research/google_play_release_sop.md`。

### 何時該執行

- 每次要上傳新版本到 Google Play 之前（SOP 第 2.5、3 節）。

### 執行方式

```bash
cd app
node tool/bump_version.js          # 互動式
node tool/bump_version.js --yes    # 不詢問：versionCode 加 1、versionName 不變

# 測試／驗收時可指定其他檔案：
node tool/bump_version.js --pubspec <路徑> --log <路徑>
```

- 「加 1」的基準是 `pubspec.yaml` 和對照表最後一筆中較大的 versionCode。
- 第一次上架（對照表沒有紀錄）時回答 `n`，保留 `1.0.0+1`。
- 結束碼 `0`：成功。`1`：輸入中斷，沒有修改任何檔案。`2`：設定錯誤（找不到檔案、
  `version:` 格式錯誤、不認得的參數），沒有修改任何檔案。
- 不在 git repo 裡或沒有安裝 git 時，commit 欄位填 `unknown` 並印出警告。

### 測試

```bash
node app/tool/test_bump_version.mjs
```

````

- [x] **Step 4：更新 Issue 3 規格與進度文件**

`docs/epics/epic-52-play-release/issues.md` Issue 3：
- `**Status:** open` 改成 `**Status:** completed`。
- 在 `**依賴：** 無。` 下一行加入：

```markdown

> **實作時的修正**：「versionCode 加 1」的基準改成「`pubspec.yaml` 與對照表最後一筆，兩者較大的再加 1」。原本以 `pubspec.yaml` 為基準時，如果它落後對照表，回答 y 或 n 都不合法，會無限重問。因此 `--yes` 也不再需要「加 1 後仍不大於最後一筆」的錯誤分支。詳見 `plans/plan-issue-3.md`。
```

`docs/epics/epic-52-play-release/epic.md` 最後加入：

```markdown

**YYYY-MM-DD Issue 3 完成**：新增 `app/tool/bump_version.js`、`app/tool/test_bump_version.mjs`（27 個測試）與 `store/google-play/release-log.md`，並在 `app/tool/README.md` 說明用法。「加 1」的基準改為 `pubspec.yaml` 與對照表最後一筆的較大者（原規格會造成無限重問）。已用 `app/pubspec.yaml` 的複本演練第一次上架與 `--yes` 兩種流程，真實檔案未被修改。
```

`docs/epics.md` 裡 `epic-52-play-release` 那一列的備註改成：`全數完成，待歸檔`。

`YYYY-MM-DD` 換成當天日期。

- [x] **Step 5：跑一次完整測試**

```bash
node app/tool/test_bump_version.mjs
mkdir -p app/build
(cd app && flutter test > build/flutter-test-issue3.log 2>&1; echo "exit=$?")
tail -3 app/build/flutter-test-issue3.log
```

Expected：`test_bump_version.mjs` 27 個全數通過。完整 `flutter test` 只允許 `wifi_transfer_http_server_test.dart` 第 570 行失敗（已登記的 `epic-51-wifi-transfer-test-fix`）；出現其他失敗就停下來查。這個 Issue 沒有改 Dart 程式碼，全套測試是計畫最後一個 Task 的例行確認。

- [x] **Step 6：Commit**

```bash
git add app/tool/README.md docs/epics.md docs/epics/epic-52-play-release
git commit -m "docs(epic-52): 記錄 Issue 3 完成，README 補上 bump_version.js 用法"
```
