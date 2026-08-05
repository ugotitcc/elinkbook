#!/usr/bin/env node
/**
 * 靜態掃描 app/android/app/src/main/assets/foliate/（readest/foliate-js
 * 釘定版本，見 ADR 0011「不修改釘定版本」）是否使用了較新的 ES 內建方法，
 * 而目前 lib/reader/foliate_epub_reader_view.dart 的 _esCompatPolyfillJs
 * 還沒有對應的 polyfill。
 *
 * 背景（見 epic-19 兩輪 /diagnose 紀錄）：這份釘定的 vendor 程式碼會無條件
 * 呼叫較新的 ES 內建方法（Object.groupBy/Map.groupBy、Array.prototype.at、
 * Array.prototype.findLastIndex），較舊的 Android System WebView（例如
 * Chromium 91 的 Mobiscribe WAVE）不支援，導致開書失敗（輕則拋出可觀察的
 * 例外，重則像 .at()/findLastIndex() 那樣在 WebView 沒開遠端除錯時完全
 * 靜默卡在載入指示器，非常難排查）。目前已知的落差已經手動找出並補上
 * polyfill，但下次升級這份釘定版本（bump 到新的 commit）時，上游可能引入
 * 新的、目前完全沒設防的 ES 內建方法用法——這支腳本就是為了在那個時間點
 * 提早攔截，不要每次都等真機回報「開書卡住」才後知後覺去找。
 *
 * 用法：node app/tool/check_foliate_es_compat.js
 * 結束碼：0 = 乾淨（找到的每個較新 API 用法都已有對應 polyfill 防護）；
 *         1 = 找到至少一個尚未防護的用法，印出詳細清單。
 *
 * 這支腳本本身純粹是靜態文字掃描（regex），會有誤判空間（例如某個變數剛好
 * 叫 `arr.at(...)` 但其實不是 Array.prototype.at）；設計上寧可偶爾多提醒
 * 一次、也不要漏掉真正的風險，故不追求零誤判。
 */

'use strict';

const fs = require('fs');
const path = require('path');

const REPO_ROOT = path.resolve(__dirname, '..', '..');
const FOLIATE_ASSETS_DIR = path.join(
  REPO_ROOT,
  'app', 'android', 'app', 'src', 'main', 'assets', 'foliate',
);
const POLYFILL_SOURCE_FILE = path.join(
  REPO_ROOT,
  'app', 'lib', 'reader', 'foliate_epub_reader_view.dart',
);

/**
 * 已知「較新、Android System WebView 可能還不支援」的 ES 內建方法/靜態方法
 * 清單。`usagePattern` 用來在 foliate-js 原始碼裡偵測「有沒有被呼叫到」；
 * `polyfillMarker` 用來在 _esCompatPolyfillJs 的原始碼裡偵測「有沒有已經
 * 補上對應防護」（用字串包含比對，不要求逐字一致，只要求那個方法名稱有
 * 出現在一個看起來像防護／賦值的上下文）。`minChromium` 僅供報告訊息參考，
 * 不影響判斷邏輯（判斷邏輯只看「有沒有 polyfill」，不管實際裝置版本）。
 */
const RISKY_APIS = [
  {
    // `.at(N)` 純文字掃描分辨不出呼叫對象是 Array 還是 String（兩者都有
    // 同名的 .at() 方法，語意相同），故用 OR 語意：只要 polyfill 裡對
    // Array.prototype.at 或 String.prototype.at 任一個補上防護，就視為
    // 這個用法已受防護，避免明明只需要 Array 版本、卻永遠被誤判成
    // 「String 版本沒 polyfill」的無法修復假警報。
    name: '.at(N)（Array.prototype.at 或 String.prototype.at）',
    usagePattern: /\.at\(\s*-?\d/g,
    polyfillMarkers: ['Array.prototype.at', 'String.prototype.at'],
    minChromium: 92,
    specYear: 'ES2022',
  },
  {
    name: 'Object.hasOwn',
    usagePattern: /Object\.hasOwn\(/g,
    polyfillMarkers: ['Object.hasOwn'],
    minChromium: 93,
    specYear: 'ES2022',
  },
  {
    name: 'Array.prototype.findLast',
    usagePattern: /\.findLast\(/g,
    polyfillMarkers: ['Array.prototype.findLast '],
    minChromium: 97,
    specYear: 'ES2023',
  },
  {
    name: 'Array.prototype.findLastIndex',
    usagePattern: /\.findLastIndex\(/g,
    polyfillMarkers: ['Array.prototype.findLastIndex'],
    minChromium: 97,
    specYear: 'ES2023',
  },
  {
    name: 'Array.prototype.toReversed',
    usagePattern: /\.toReversed\(\)/g,
    polyfillMarkers: ['Array.prototype.toReversed'],
    minChromium: 110,
    specYear: 'ES2023',
  },
  {
    name: 'Array.prototype.toSorted',
    usagePattern: /\.toSorted\(/g,
    polyfillMarkers: ['Array.prototype.toSorted'],
    minChromium: 110,
    specYear: 'ES2023',
  },
  {
    name: 'Array.prototype.toSpliced',
    usagePattern: /\.toSpliced\(/g,
    polyfillMarkers: ['Array.prototype.toSpliced'],
    minChromium: 110,
    specYear: 'ES2023',
  },
  {
    name: 'Array.prototype.with',
    usagePattern: /\.with\(\s*\d/g,
    polyfillMarkers: ['Array.prototype.with'],
    minChromium: 110,
    specYear: 'ES2023',
  },
  {
    name: 'Object.groupBy',
    usagePattern: /Object\.groupBy\(/g,
    polyfillMarkers: ['Object.groupBy'],
    minChromium: 117,
    specYear: 'ES2024',
  },
  {
    name: 'Map.groupBy',
    usagePattern: /Map\.groupBy\(/g,
    polyfillMarkers: ['Map.groupBy'],
    minChromium: 117,
    specYear: 'ES2024',
  },
  {
    name: 'Promise.withResolvers',
    usagePattern: /Promise\.withResolvers\(\)/g,
    polyfillMarkers: ['Promise.withResolvers'],
    minChromium: 119,
    specYear: 'ES2024',
  },
  {
    name: 'String.prototype.isWellFormed',
    usagePattern: /\.isWellFormed\(\)/g,
    polyfillMarkers: ['isWellFormed'],
    minChromium: 111,
    specYear: 'ES2024',
  },
  {
    name: 'String.prototype.toWellFormed',
    usagePattern: /\.toWellFormed\(\)/g,
    polyfillMarkers: ['toWellFormed'],
    minChromium: 111,
    specYear: 'ES2024',
  },
  {
    name: 'structuredClone',
    usagePattern: /\bstructuredClone\(/g,
    polyfillMarkers: ['structuredClone'],
    minChromium: 98,
    specYear: '（平台 API，非 TC39 提案）',
  },
  {
    name: 'Array.fromAsync',
    usagePattern: /Array\.fromAsync\(/g,
    polyfillMarkers: ['Array.fromAsync'],
    minChromium: 121,
    specYear: 'ES2024',
  },
  {
    name: 'String.prototype.replaceAll',
    usagePattern: /\.replaceAll\(/g,
    polyfillMarkers: ['String.prototype.replaceAll'],
    minChromium: 85,
    specYear: 'ES2021',
  },
  {
    name: 'WeakRef',
    usagePattern: /\bnew WeakRef\(/g,
    polyfillMarkers: ['WeakRef'],
    minChromium: 84,
    specYear: 'ES2021',
  },
];

function readFileSafe(filePath) {
  return fs.readFileSync(filePath, { encoding: 'utf8' });
}

function listJsFilesRecursive(dir) {
  const entries = fs.readdirSync(dir, { withFileTypes: true });
  const files = [];
  for (const entry of entries) {
    const fullPath = path.join(dir, entry.name);
    if (entry.isDirectory()) {
      files.push(...listJsFilesRecursive(fullPath));
    } else if (entry.isFile() && entry.name.endsWith('.js')) {
      files.push(fullPath);
    }
  }
  return files;
}

function extractPolyfillSource(dartSource) {
  // _esCompatPolyfillJs 是一個 Dart 三引號字串常數（'''...'''），直接抓
  // 這個常數宣告與它後面第一個 ''' 之間的內容，不需要完整解析 Dart 語法。
  const match = dartSource.match(
    /const _esCompatPolyfillJs = '''([\s\S]*?)''';/,
  );
  if (!match) {
    throw new Error(
      '在 foliate_epub_reader_view.dart 找不到 _esCompatPolyfillJs 常數' +
      '——是不是被改名或搬移了？請同步更新這支腳本的 POLYFILL_SOURCE_FILE' +
      '/extractPolyfillSource() 邏輯。',
    );
  }
  return match[1];
}

function findLineNumber(source, index) {
  return source.slice(0, index).split('\n').length;
}

function main() {
  const polyfillDartSource = readFileSafe(POLYFILL_SOURCE_FILE);
  const polyfillJs = extractPolyfillSource(polyfillDartSource);

  const jsFiles = listJsFilesRecursive(FOLIATE_ASSETS_DIR);
  if (jsFiles.length === 0) {
    console.error(
      `[check_foliate_es_compat] 在 ${FOLIATE_ASSETS_DIR} 找不到任何 .js ` +
      '檔案，路徑是否正確？',
    );
    process.exit(1);
  }

  const findings = [];

  for (const api of RISKY_APIS) {
    const isPolyfilled = api.polyfillMarkers.some(
      (marker) => polyfillJs.includes(marker),
    );
    if (isPolyfilled) continue;

    for (const filePath of jsFiles) {
      const source = readFileSafe(filePath);
      const pattern = new RegExp(api.usagePattern.source, 'g');
      let match;
      while ((match = pattern.exec(source)) !== null) {
        findings.push({
          api,
          filePath: path.relative(REPO_ROOT, filePath),
          line: findLineNumber(source, match.index),
          snippet: source.slice(
            Math.max(0, match.index - 20),
            match.index + match[0].length + 20,
          ).replace(/\s+/g, ' ').trim(),
        });
      }
    }
  }

  if (findings.length === 0) {
    console.log(
      '[check_foliate_es_compat] 乾淨——目前已知的較新 ES 內建方法用法都' +
      '已有對應 polyfill 防護。',
    );
    process.exit(0);
  }

  console.error(
    `[check_foliate_es_compat] 發現 ${findings.length} 處較新 ES 內建方法` +
    '用法，_esCompatPolyfillJs 目前沒有對應防護：\n',
  );
  for (const finding of findings) {
    console.error(
      `  - ${finding.api.name}（${finding.api.specYear}，需 Chromium ` +
      `${finding.api.minChromium}+）\n` +
      `    ${finding.filePath}:${finding.line}\n` +
      `    ...${finding.snippet}...\n`,
    );
  }
  console.error(
    '請至 app/lib/reader/foliate_epub_reader_view.dart 的 ' +
    '_esCompatPolyfillJs 補上對應的 polyfill（僅在缺席時才定義，比照既有' +
    '寫法），並用 Node.js + @xmldom/xmldom 對照未經修改的實際 epub.js 驗證' +
    '過缺席時會拋出例外、補上後可修復，再重新執行這支腳本確認乾淨。',
  );
  process.exit(1);
}

main();
