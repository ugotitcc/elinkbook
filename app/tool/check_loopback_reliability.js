#!/usr/bin/env node
// 量測本機 loopback 連線可靠度（epic-66 Issue 11）。
//
// 背景：某些 Windows 機器的 127.0.0.1 上，帶 `Connection: close` 的 TCP 連線
// 會被隨機重設（ECONNRESET 或空回應），導致 LocalBookServer 的測試隨機失敗。
// 這支腳本對多個位址、兩種連線模式各發 N 次請求，列出成功與失敗的次數，
// 用來判斷「問題只出在 127.0.0.1」還是「整個網路堆疊都不穩」。
//
// 用法：node tool/check_loopback_reliability.js [--count N]   （N 預設 100）
// 結束碼：127.0.0.1 任一模式出現失敗為 1，否則 0。只用 Node 內建模組。

'use strict';

const http = require('http');
const net = require('net');
const os = require('os');

const REQUEST_TIMEOUT_MS = 3000;

function parseCount(argv) {
  const i = argv.indexOf('--count');
  if (i === -1) return 100;
  const n = Number.parseInt(argv[i + 1], 10);
  if (!Number.isInteger(n) || n <= 0) {
    console.error('--count 必須是正整數');
    process.exit(2);
  }
  return n;
}

// 第一個非內部的區網 IPv4 位址；找不到就回傳 null。
function findLanAddress() {
  for (const list of Object.values(os.networkInterfaces())) {
    for (const info of list || []) {
      if (info.family === 'IPv4' && !info.internal) return info.address;
    }
  }
  return null;
}

// 對 host:port 發一次請求，回傳 'ok'、'empty'、'timeout' 或 'reset:<錯誤碼>'。
// mode 為 'close'：帶 Connection: close，等伺服器主動關閉；
// mode 為 'keepalive'：帶 Connection: keep-alive，收到完整回應後由客戶端關閉。
function requestOnce(host, port, mode) {
  return new Promise((resolve) => {
    let received = Buffer.alloc(0);
    let finished = false;
    const finish = (result) => {
      if (finished) return;
      finished = true;
      clearTimeout(timer);
      socket.destroy();
      resolve(result);
    };
    const socket = net.connect(port, host, () => {
      const connection = mode === 'close' ? 'close' : 'keep-alive';
      socket.write(
        `GET / HTTP/1.1\r\nHost: ${host}:${port}\r\nConnection: ${connection}\r\n\r\n`,
      );
    });
    const timer = setTimeout(() => finish('timeout'), REQUEST_TIMEOUT_MS);
    socket.on('data', (chunk) => {
      received = Buffer.concat([received, chunk]);
      // keep-alive 模式下伺服器不會關連線，看到回應本文（'ok'）就算完成。
      if (mode === 'keepalive' && received.toString('latin1').endsWith('\r\n\r\nok')) {
        finish('ok');
      }
    });
    socket.on('error', (err) => finish(`reset:${err.code || err.message}`));
    const onEnd = () => finish(received.length > 0 ? 'ok' : 'empty');
    socket.on('end', onEnd);
    socket.on('close', onEnd);
  });
}

// 在 host 上啟動伺服器，依序發 count 次請求，回傳各結果的次數表；無法綁定時回傳 { bindError }。
function trial(host, mode, count) {
  return new Promise((resolve) => {
    const server = http.createServer((req, res) => res.end('ok'));
    server.once('error', (err) => resolve({ bindError: err.code || err.message }));
    server.listen(0, host, async () => {
      const port = server.address().port;
      const tally = {};
      for (let i = 0; i < count; i++) {
        const result = await requestOnce(host, port, mode);
        tally[result] = (tally[result] || 0) + 1;
      }
      server.close();
      resolve({ tally });
    });
  });
}

function formatTally(tally) {
  const ok = tally.ok || 0;
  const failures = Object.entries(tally)
    .filter(([k]) => k !== 'ok')
    .map(([k, v]) => `${k}=${v}`);
  return `ok=${ok}` + (failures.length ? `  ${failures.join('  ')}` : '');
}

async function main() {
  const count = parseCount(process.argv.slice(2));
  const lan = findLanAddress();
  const hosts = ['127.0.0.1', '127.0.0.2', '::1'];
  if (lan) hosts.push(lan);

  console.log(`每列 ${count} 次請求（循序、每次新連線）`);
  let loopbackFailed = false;
  for (const host of hosts) {
    for (const mode of ['close', 'keepalive']) {
      const { tally, bindError } = await trial(host, mode, count);
      const label = `${host.padEnd(16)} ${mode.padEnd(10)}`;
      if (bindError) {
        console.log(`${label} 無法綁定:${bindError}`);
        continue;
      }
      console.log(`${label} ${formatTally(tally)}`);
      const failed = Object.keys(tally).some((k) => k !== 'ok');
      if (host === '127.0.0.1' && failed) loopbackFailed = true;
    }
  }
  if (loopbackFailed) {
    console.log(
      '\n127.0.0.1 有連線失敗。若其他位址正常，代表本機有軟體干擾 127.0.0.1，' +
        '可能造成 LocalBookServer 相關測試隨機失敗。',
    );
  }
  process.exit(loopbackFailed ? 1 : 0);
}

main();
