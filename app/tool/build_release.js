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
//   node tool/build_release.js                  # 互動式選擇
//   node tool/build_release.js --target apk     # GitHub APK
//   node tool/build_release.js --target aab     # Google Play AAB
//   node tool/build_release.js --target debug   # debug APK
//
// 結束碼 0：成功；1：使用者取消；2：設定錯誤或建置失敗（檔案已還原）。

const fs = require('fs');
const path = require('path');
const readline = require('readline');
const { spawnSync } = require('child_process');

const APP_DIR = path.join(__dirname, '..');
const KEY_PROPS = path.join(APP_DIR, 'android', 'key.properties');
const OAUTH = path.join(APP_DIR, 'config', 'cloud_oauth.json');

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
  },
  aab: {
    label: 'Google Play AAB（上傳金鑰）',
    keySource: path.join(APP_DIR, 'android', 'key.properties.upload'),
    oauthSource: path.join(APP_DIR, 'config', 'cloud_oauth.release.json'),
    buildArgs: ['build', 'appbundle', '--release'],
    output: 'build/app/outputs/bundle/release/',
  },
  debug: {
    label: 'debug APK（不換金鑰）',
    keySource: null,
    oauthSource: path.join(APP_DIR, 'config', 'cloud_oauth.debug.json'),
    buildArgs: ['build', 'apk', '--debug'],
    output: 'build/app/outputs/flutter-apk/',
  },
};

function fail(msg) {
  console.error(`[錯誤] ${msg}`);
  process.exit(2);
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
  const rl = readline.createInterface({ input: process.stdin, output: process.stdout });
  const answer = await new Promise((resolve) => rl.question('輸入編號：', resolve));
  rl.close();
  const t = keys[Number(answer.trim()) - 1];
  if (!t) {
    console.error('沒有選擇有效的編號，已取消。');
    process.exit(1);
  }
  return t;
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
}

main();
