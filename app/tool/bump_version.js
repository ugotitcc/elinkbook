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
