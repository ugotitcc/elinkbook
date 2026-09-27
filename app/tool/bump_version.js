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
// 結束碼 0：成功；1：輸入中斷，沒有修改任何檔案；2：設定錯誤，沒有修改任何檔案，
// 或是寫檔時發生未預期的錯誤（此時可能只更新了一個檔案，要用 git status 確認）。

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

// versionCode 最大的一列（相同時取後面那列）。最後一列不一定最大：
// Play 允許把較舊的內部測試版推到正式版，SOP 2.9 會在最後手動加一列較小的號碼。
// 檢查新 versionCode 與「加 1」都要以這一列為準，才不會接受已經上傳過的號碼。
function maxLogEntry(text) {
  return parseLogEntries(text).reduce((max, entry) => (max === null || entry.code >= max.code ? entry : max), null);
}

function isValidVersionName(s) {
  return VERSION_NAME.test(s);
}

// 「加 1」的基準取 pubspec 與對照表最大的 versionCode 較大者，
// 這樣 pubspec 落後對照表時，回答「加 1」也一定合法，不會卡在重問迴圈。
// max 是 maxLogEntry() 的結果。
function nextVersionCode(pubspecCode, max) {
  return Math.max(pubspecCode, max ? max.code : 0) + 1;
}

function checkVersionCode(code, max) {
  if (!Number.isInteger(code) || code < 1) {
    return `versionCode 必須是正整數，目前是 ${code}。`;
  }
  if (max && code <= max.code) {
    return `Play 不收重複或變小的 versionCode，對照表裡最大的 versionCode 是 ${max.code}（${max.name}，${max.date}）。請回答 y 讓腳本加 1。`;
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

function parseArgs(argv) {
  const opts = { yes: false, pubspec: DEFAULT_PUBSPEC, log: DEFAULT_LOG };
  for (let i = 0; i < argv.length; i++) {
    const arg = argv[i];
    if (arg === '--yes') {
      opts.yes = true;
    } else if (arg === '--pubspec' || arg === '--log') {
      const value = argv[++i];
      // 值以 -- 開頭，代表漏寫路徑、直接接了下一個旗標。
      if (!value || value.startsWith('--')) throw new Error(`${arg} 後面要接檔案路徑。`);
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
  if (!fs.statSync(filePath).isFile()) {
    throw new Error(`${label} 的路徑不是檔案：${filePath}。請改成指向檔案的路徑。`);
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
  const max = maxLogEntry(logText);
  const next = nextVersionCode(current.code, max);
  say(`目前版本：${current.name}+${current.code}`);
  say(last ? `對照表最後一筆：${last.name}+${last.code}（${last.track}，${last.date}）` : '對照表最後一筆：尚無紀錄');
  if (max && max.code !== last.code) {
    say(`對照表最大的 versionCode：${max.name}+${max.code}（${max.track}，${max.date}）`);
  }

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
        const error = checkVersionCode(code, max);
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

module.exports = {
  parsePubspecVersion,
  replacePubspecVersion,
  parseLogEntries,
  lastLogEntry,
  maxLogEntry,
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
