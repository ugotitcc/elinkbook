// 打包腳本：依選擇的打包目標，自動把對應的簽章金鑰與 OAuth 設定檔配對、建置、再還原。
//
// 取代 docs/research/release_apk_sop.md 第 2.2、2.3 節的手動 cp。它會：
//   1. 備份目前的 android/key.properties 與 config/cloud_oauth.json。
//   2. 依目標複製對應的檔案（見下方 TARGETS）。
//   3. 執行 flutter build。
//   4. 不論成功或失敗，都把備份還原（含 Ctrl+C）。
// 慣例比照 bump_version.js（純 Node 內建模組、免 npm install）。
//
// 用法（在 app/ 目錄下）：
//   node tool/build_release.js                  # 問答式：選目標 → 看確認清單 → 輸入 y 才打包
//   node tool/build_release.js --target apk     # GitHub APK
//   node tool/build_release.js --target aab     # Google Play AAB
//   node tool/build_release.js --target debug   # debug APK
//   加上 --yes 可略過最後的 y/N 確認（給自動化用）；金鑰不符一律擋下，不受 --yes 影響。
//
// 結束碼 0：成功；1：使用者取消；2：設定錯誤或建置失敗（檔案已還原）。

const fs = require('fs');
const path = require('path');
const readline = require('readline');
const crypto = require('crypto');
const { spawnSync } = require('child_process');
const summary = require('./build_summary');

const APP_DIR = path.join(__dirname, '..');
const KEY_PROPS = path.join(APP_DIR, 'android', 'key.properties');
const OAUTH = path.join(APP_DIR, 'config', 'cloud_oauth.json');
// 公開的簽章指紋對照表（不含機密），收尾驗簽時用來判定實際簽章身分。
const FINGERPRINTS = path.join(APP_DIR, 'config', 'signing_fingerprints.json');

// 打包目標。keySource 為 null 代表不換金鑰（debug 建置不讀 key.properties）。
const TARGETS = {
  apk: {
    label: 'GitHub APK（發佈金鑰，依 ABI 拆開）',
    keySource: path.join(APP_DIR, 'android', 'key.properties.release'),
    oauthSource: path.join(APP_DIR, 'config', 'cloud_oauth.release.json'),
    buildArgs: ['build', 'apk', '--release', '--split-per-abi'],
    // 另外多建一次不拆 ABI 的共用版（app-release.apk），發版要 5 個檔含它。
    extraBuildArgs: [['build', 'apk', '--release']],
    output: 'build/app/outputs/flutter-apk/',
    mode: 'release',
    kind: 'apk',
    artifactMatch: (f) => f.endsWith('-release.apk'),
    nextSteps: [
      'adb install -r build/app/outputs/flutter-apk/app-arm64-v8a-release.apk（禁用 flutter install，會清掉書架資料）',
      '發版：依 docs/research/release_apk_sop.md 第 2.5 節改檔名並產生 SHA256SUMS',
    ],
  },
  aab: {
    label: 'Google Play AAB（上傳金鑰）',
    keySource: path.join(APP_DIR, 'android', 'key.properties.upload'),
    oauthSource: path.join(APP_DIR, 'config', 'cloud_oauth.release.json'),
    buildArgs: ['build', 'appbundle', '--release'],
    output: 'build/app/outputs/bundle/release/',
    mode: 'release',
    kind: 'aab',
    artifactMatch: (f) => f.endsWith('.aab'),
    nextSteps: ['上傳到 Google Play Console（依 docs/research/google_play_release_sop.md）'],
  },
  debug: {
    label: 'debug APK（不換金鑰）',
    keySource: null,
    oauthSource: path.join(APP_DIR, 'config', 'cloud_oauth.debug.json'),
    buildArgs: ['build', 'apk', '--debug'],
    output: 'build/app/outputs/flutter-apk/',
    mode: 'debug',
    kind: 'apk',
    artifactMatch: (f) => f === 'app-debug.apk',
    nextSteps: [
      'adb install -r build/app/outputs/flutter-apk/app-debug.apk（禁用 flutter install，會清掉書架資料）',
      '不要把 debug APK 放到 GitHub Release 或官網',
    ],
  },
};

function fail(msg) {
  console.error(`[錯誤] ${msg}`);
  process.exit(2);
}

// 問一個問題，回傳去掉前後空白的答案。
async function ask(question) {
  const rl = readline.createInterface({ input: process.stdin, output: process.stdout });
  // 輸入被關閉（EOF）時當成空答案，呼叫端會視為取消。
  const answer = await new Promise((resolve) => {
    rl.once('close', () => resolve(''));
    rl.question(question, resolve);
  });
  rl.close();
  return answer.trim();
}

// 從 --target 取得目標；沒帶就互動詢問。
async function pickTarget() {
  const i = process.argv.indexOf('--target');
  if (i !== -1) {
    const t = process.argv[i + 1];
    if (!TARGETS[t]) fail(`不認得的 --target「${t}」。可用值：${Object.keys(TARGETS).join('、')}。`);
    return t;
  }
  const keys = Object.keys(TARGETS);
  console.log('要打包哪一種？');
  keys.forEach((k, n) => console.log(`  ${n + 1}. ${k}：${TARGETS[k].label}`));
  const answer = await ask('輸入編號：');
  const t = keys[Number(answer) - 1];
  if (!t) {
    console.error('沒有選擇有效的編號，已取消。');
    process.exit(1);
  }
  return t;
}

// ---- 打包前確認 ----

// 直接讀金鑰庫（.jks）的憑證指紋；讀不到（沒有 keytool、檔案不在、密碼錯）回 null。
// 密碼只放環境變數，不進指令列、不印出。
function keystoreCert(props) {
  if (!props.storeFile || !props.keyAlias) return null;
  const r = spawnSync(
    'keytool',
    summary.keystoreListArgs(`"${props.storeFile}"`, `"${props.keyAlias}"`, 'ELINK_STOREPASS'),
    { encoding: 'utf8', shell: true, env: { ...process.env, ELINK_STOREPASS: props.storePassword } }
  );
  if (r.status !== 0) return null;
  return summary.parseKeytoolOutput(r.stdout);
}

// 印出「這次到底會打成什麼」的確認清單，回傳 keyCheck 狀態（debug 回 null）。
function printPreflight(name, t) {
  const fingerprints = readJsonOrEmpty(FINGERPRINTS);
  const expected = summary.expectedIdentityOf(name);
  let keyCheck = null;
  if (t.keySource) {
    const props = summary.parseKeyProperties(fs.readFileSync(t.keySource, 'utf8'));
    const cert = keystoreCert(props);
    keyCheck = {
      alias: props.keyAlias,
      storeName: path.basename(props.storeFile),
      expected,
      sha256: cert ? cert.sha256 : null,
      identity: null,
      status: 'unreadable',
    };
    if (cert) {
      keyCheck.identity = summary.classifyIdentity(cert, fingerprints);
      keyCheck.status = summary.evaluateSigning(keyCheck.identity, expected, fingerprints);
    }
  }
  const oauthId = readJsonOrEmpty(t.oauthSource).GOOGLE_OAUTH_CLIENT_ID || '';
  const pubspec = fs.readFileSync(path.join(APP_DIR, 'pubspec.yaml'), 'utf8');
  console.log(
    summary.formatPreflight({
      label: t.label,
      mode: t.mode,
      version: summary.readPubspecVersion(pubspec),
      keyCheck,
      oauthFile: path.relative(APP_DIR, t.oauthSource).split(path.sep).join('/'),
      oauthPrefix: oauthId.slice(0, 6),
      commands: [t.buildArgs, ...(t.extraBuildArgs || [])].map((a) => 'flutter ' + a.join(' ')),
    })
  );
  return keyCheck;
}

// ---- 收尾摘要（epic-54 後續項目）----

function sha256OfFile(file) {
  return crypto.createHash('sha256').update(fs.readFileSync(file)).digest('hex');
}

function readJsonOrEmpty(file) {
  try {
    return JSON.parse(fs.readFileSync(file, 'utf8'));
  } catch (_) {
    return {};
  }
}

// 從 android/local.properties 的 sdk.dir 取得 Android SDK 路徑。
function androidSdkDir() {
  try {
    const text = fs.readFileSync(path.join(APP_DIR, 'android', 'local.properties'), 'utf8');
    const m = /^sdk\.dir=(.+)$/m.exec(text);
    // .properties 會把路徑裡的反斜線寫成 \\、冒號寫成 \:，還原成一般路徑。
    return m ? m[1].trim().split('\\\\').join('\\').split('\\:').join(':') : null;
  } catch (_) {
    return null;
  }
}

// 對產物做驗簽，回傳 { cert|null }：APK 用 apksigner，AAB 用 keytool。
// 找不到工具或執行失敗回 null（呼叫端標「未驗證」，不讓打包失敗）。
function verifyArtifact(kind, file) {
  if (kind === 'apk') {
    const sdk = androidSdkDir();
    const apksigner = sdk && summary.findApksigner(sdk);
    if (!apksigner) return null;
    // .bat 在 Windows 要走 shell；路徑可能含空白，所以自己加引號。
    const r = spawnSync(`"${apksigner}"`, ['verify', '--print-certs', `"${file}"`], {
      encoding: 'utf8',
      shell: true,
    });
    if (r.status !== 0) return null;
    return summary.parseApksignerOutput(r.stdout);
  }
  const r = spawnSync('keytool', summary.keytoolArgs(`"${file}"`), {
    encoding: 'utf8',
    shell: true,
  });
  if (r.status !== 0) return null;
  return summary.parseKeytoolOutput(r.stdout);
}

// 建完後驗簽並印摘要；簽章與目標不符回傳 false（呼叫端以結束碼 2 結束）。
function printBuildSummary(name, t) {
  const outDir = path.join(APP_DIR, t.output);
  const files = fs.existsSync(outDir) ? fs.readdirSync(outDir).filter(t.artifactMatch).sort() : [];
  const artifacts = files.map((name) => {
    const full = path.join(outDir, name);
    return { name, sizeBytes: fs.statSync(full).size, sha256: sha256OfFile(full) };
  });

  const fingerprints = readJsonOrEmpty(FINGERPRINTS);
  const cert = files.length > 0 ? verifyArtifact(t.kind, path.join(outDir, files[0])) : null;
  const expected = summary.expectedIdentityOf(name);
  let identity = null;
  let status = 'unverified';
  if (cert) {
    identity = summary.classifyIdentity(cert, fingerprints);
    status = summary.evaluateSigning(identity, expected, fingerprints);
  }

  const oauthId = readJsonOrEmpty(t.oauthSource).GOOGLE_OAUTH_CLIENT_ID || '';
  const pubspec = fs.readFileSync(path.join(APP_DIR, 'pubspec.yaml'), 'utf8');
  console.log(
    summary.formatSummary({
      label: t.label,
      mode: t.mode,
      version: summary.readPubspecVersion(pubspec),
      identity,
      sha256: cert ? cert.sha256 : null,
      status,
      oauthPrefix: oauthId.slice(0, 6),
      artifacts,
      nextSteps: t.nextSteps,
    })
  );
  return status !== 'mismatch';
}

async function main() {
  const name = await pickTarget();
  const t = TARGETS[name];

  // 先確認來源檔都在，再動任何檔案。
  const sources = [t.keySource, t.oauthSource].filter(Boolean);
  const missing = sources.filter((f) => !fs.existsSync(f));
  if (missing.length) {
    fail(
      `找不到配對檔：\n  ${missing.join('\n  ')}\n` +
        '這些檔案不進版控，要自己建立。樣板見 key.properties.example、cloud_oauth.example.json。'
    );
  }

  // 打包前確認：金鑰不符直接擋下；其餘讓使用者看過清單再決定。
  const keyCheck = printPreflight(name, t);
  if (keyCheck && keyCheck.status === 'mismatch') {
    fail('金鑰庫的實際身分與此目標不符，不能打包。請改選正確的目標，或修正 key.properties 配對檔。');
  }
  if (!process.argv.includes('--yes')) {
    const warn = keyCheck && keyCheck.status !== 'ok' ? '（上面有 ⚠，請確認）' : '';
    const answer = await ask(`以上內容正確，開始打包？${warn}(y/N)：`);
    if (!/^y(es)?$/i.test(answer)) {
      console.error('已取消，沒有打包。');
      process.exit(1);
    }
  }

  // 備份目前的檔案（不存在則記為 null，還原時刪除）。
  const targets = [OAUTH, ...(t.keySource ? [KEY_PROPS] : [])];
  const backups = new Map(
    targets.map((f) => [f, fs.existsSync(f) ? fs.readFileSync(f) : null])
  );
  let restored = false;
  const restore = () => {
    if (restored) return;
    restored = true;
    for (const [f, buf] of backups) {
      if (buf === null) fs.rmSync(f, { force: true });
      else fs.writeFileSync(f, buf);
    }
    console.log('[還原] 已把 key.properties 與 cloud_oauth.json 換回原內容。');
  };
  process.on('exit', restore);
  process.on('SIGINT', () => process.exit(1));

  fs.copyFileSync(t.oauthSource, OAUTH);
  console.log(`[配對] ${path.relative(APP_DIR, t.oauthSource)} -> config/cloud_oauth.json`);
  if (t.keySource) {
    fs.copyFileSync(t.keySource, KEY_PROPS);
    console.log(`[配對] ${path.relative(APP_DIR, t.keySource)} -> android/key.properties`);
  }

  for (const base of [t.buildArgs, ...(t.extraBuildArgs || [])]) {
    const args = [...base, '--dart-define-from-file=config/cloud_oauth.json'];
    console.log(`[建置] flutter ${args.join(' ')}`);
    // Windows 的 flutter 是 flutter.bat，要用 shell 才找得到。
    const r = spawnSync('flutter', args, { cwd: APP_DIR, stdio: 'inherit', shell: true });
    if (r.status !== 0) {
      console.error('[失敗] 建置沒有成功。檔案會自動還原。');
      process.exit(2);
    }
  }
  console.log(`[完成] 產物在 app/${t.output}`);
  if (!printBuildSummary(name, t)) {
    console.error('[失敗] 簽章與此打包目標應有的身分不符，產物不可發佈。檔案會自動還原。');
    process.exit(2);
  }
}

main();
