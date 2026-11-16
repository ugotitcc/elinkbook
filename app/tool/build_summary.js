// 打包收尾摘要與簽章身分判定（epic-54 後續項目）。
//
// 供 build_release.js 在建置完成後：驗證產物「實際」被哪一把金鑰簽的、與該打包目標
// 應有的身分比對，再印出一份摘要（版本、簽章、OAuth、產物、下一步）。
// 純函式為主、免 npm install（比照 bump_version.js 慣例），單元測試見
// test_build_summary.mjs。
//
// 簽章身分以「憑證」判定，不是建置時的宣告：
//   - 憑證 DN 含 CN=Android Debug → debug 金鑰（debug 金鑰每台開發機各自不同，
//     用 DN 判定才不必登錄每台機器的指紋）。
//   - 其餘比對 app/config/signing_fingerprints.json 登錄的公開指紋
//     （release / upload / playSigning）。指紋是公開資訊，不是密碼。

const fs = require('fs');
const path = require('path');

// 打包目標 → 應有的簽章身分。
const EXPECTED_IDENTITY = { apk: 'release', aab: 'upload', debug: 'debug' };

const IDENTITY_LABEL = {
  debug: 'debug 金鑰',
  release: '發佈金鑰',
  upload: '上傳金鑰',
  playSigning: 'Google Play 簽署金鑰',
  unknown: '未知金鑰',
};

function expectedIdentityOf(target) {
  return EXPECTED_IDENTITY[target];
}

// apksigner verify --print-certs 的輸出 → { dn, sha256 }；沒有簽章資訊回 null。
function parseApksignerOutput(text) {
  const dn = /Signer #1 certificate DN:\s*(.+)/.exec(text);
  const sha = /Signer #1 certificate SHA-256 digest:\s*([0-9a-fA-F]+)/.exec(text);
  if (!dn || !sha) return null;
  return { dn: dn[1].trim(), sha256: sha[1].toLowerCase() };
}

// keytool -printcert -jarfile 的輸出（AAB 用）→ { dn, sha256 }；SHA256 去冒號轉小寫。
function parseKeytoolOutput(text) {
  const dn = /Owner:\s*(.+)/.exec(text);
  const sha = /SHA256:\s*([0-9A-Fa-f:]+)/.exec(text);
  if (!dn || !sha) return null;
  return { dn: dn[1].trim(), sha256: sha[1].replace(/:/g, '').toLowerCase() };
}

// 憑證 → 簽章身分。空白指紋視為「未登錄」，絕不拿來比對（空字串會誤判）。
function classifyIdentity(cert, fingerprints) {
  if (/CN=Android Debug/.test(cert.dn || '')) return 'debug';
  for (const key of ['release', 'upload', 'playSigning']) {
    const registered = (fingerprints[key] || '').toLowerCase();
    if (registered && registered === (cert.sha256 || '').toLowerCase()) return key;
  }
  return 'unknown';
}

// 實際身分 vs 預期身分 → ok / mismatch / unregistered。
//   unregistered：預期金鑰的指紋還沒登錄、實際又是未知金鑰，無法驗證，只警告。
function evaluateSigning(actual, expected, fingerprints) {
  if (actual === expected) return 'ok';
  const expectedRegistered = Boolean((fingerprints[expected] || '').trim());
  if (actual === 'unknown' && !expectedRegistered) return 'unregistered';
  return 'mismatch';
}

// keytool 驗 AAB 簽章的參數。中文 JDK 的 keytool 預設輸出在地化欄位（「擁有者:」），
// parseKeytoolOutput 只認英文標籤，所以用 -J 鎖定英文輸出（-J 選項要放在子命令之前）。
function keytoolArgs(file) {
  return ['-J-Duser.language=en', '-J-Duser.country=US', '-printcert', '-jarfile', file];
}

// key.properties 文字 → { storeFile, keyAlias, storePassword }；缺欄位的值為空字串。
function parseKeyProperties(text) {
  const read = (k) => {
    const m = new RegExp(`^${k}=(.*)$`, 'm').exec(text);
    return m ? m[1].trim() : '';
  };
  return {
    storeFile: read('storeFile'),
    keyAlias: read('keyAlias'),
    storePassword: read('storePassword'),
  };
}

// keytool 直接讀金鑰庫指紋的參數（打包前確認用）。密碼不放進參數，由呼叫端放進環境變數
// 並用 -storepass:env 讀取，避免出現在處理程序清單。-J 選項理由同 keytoolArgs。
function keystoreListArgs(storeFile, alias, passwordEnvName) {
  return [
    '-J-Duser.language=en',
    '-J-Duser.country=US',
    '-list',
    '-v',
    '-keystore',
    storeFile,
    '-alias',
    alias,
    `-storepass:env`,
    passwordEnvName,
  ];
}

// 打包前確認清單。keyCheck 為 null 代表此目標不換金鑰（debug）。
// keyCheck.status：ok / mismatch / unregistered / unreadable。
function formatPreflight(info) {
  const lines = [];
  lines.push('============== 打包前確認 ==============');
  lines.push(` 目標    ：${info.label}（${info.mode} 模式）`);
  lines.push(` 版本    ：${info.version || '（讀不到）'}`);
  const k = info.keyCheck;
  if (!k) {
    lines.push(' 簽章金鑰：不換金鑰（debug 建置使用 Android 預設 debug 金鑰）');
  } else {
    lines.push(` 簽章金鑰：${k.alias}（${k.storeName}）`);
    if (k.status === 'ok') {
      lines.push(`   指紋 ${k.sha256}`);
      lines.push(`   ✔ 這是「${IDENTITY_LABEL[k.identity]}」，與此目標相符`);
    } else if (k.status === 'mismatch') {
      lines.push(`   指紋 ${k.sha256}`);
      lines.push(
        `   ✘ 這是「${IDENTITY_LABEL[k.identity]}」，但此目標需要「${IDENTITY_LABEL[k.expected]}」`
      );
    } else if (k.status === 'unregistered') {
      lines.push(`   指紋 ${k.sha256}`);
      lines.push('   ⚠ 指紋未登錄在 config/signing_fingerprints.json，無法確認是哪一把金鑰');
    } else {
      lines.push('   ⚠ 讀不到金鑰庫指紋（找不到 keytool、檔案不存在或密碼不對）');
    }
  }
  lines.push(` OAuth   ：${info.oauthFile}（Google Client ID 前 6 碼 ${info.oauthPrefix || '（空）'}）`);
  lines.push(` 建置指令：${info.commands.join('；')}`);
  lines.push('=========================================');
  return lines.join('\n');
}

function readPubspecVersion(pubspecText) {
  const m = /^version:\s*(\S+)/m.exec(pubspecText);
  return m ? m[1] : null;
}

// 從 Android SDK 的 build-tools 找最新版的 apksigner；找不到回 null。
// （SOP 曾寫死 36.1.0，換機器就找不到，所以改成自動挑最新。）
function findApksigner(sdkDir) {
  const root = path.join(sdkDir, 'build-tools');
  if (!fs.existsSync(root)) return null;
  const versions = fs
    .readdirSync(root)
    .filter((v) => /^\d+(\.\d+)*$/.test(v))
    .sort((a, b) => {
      const pa = a.split('.').map(Number);
      const pb = b.split('.').map(Number);
      for (let i = 0; i < Math.max(pa.length, pb.length); i++) {
        const d = (pb[i] || 0) - (pa[i] || 0);
        if (d !== 0) return d;
      }
      return 0;
    });
  const exe = process.platform === 'win32' ? 'apksigner.bat' : 'apksigner';
  for (const v of versions) {
    const candidate = path.join(root, v, exe);
    if (fs.existsSync(candidate)) return candidate;
  }
  return null;
}

function megabytes(bytes) {
  return `${(bytes / (1024 * 1024)).toFixed(1)} MB`;
}

// 產生收尾摘要文字。status：ok / mismatch / unregistered / unverified。
function formatSummary(info) {
  const lines = [];
  lines.push('============== 打包資訊 ==============');
  lines.push(` 目標    ：${info.label}（${info.mode} 模式）`);
  lines.push(` 版本    ：${info.version || '（讀不到）'}`);

  const label = info.identity ? IDENTITY_LABEL[info.identity] : null;
  const fp = info.sha256 ? `  SHA-256 ${info.sha256}` : '';
  if (info.status === 'ok') {
    lines.push(` 簽章    ：${label} ✔${fp}`);
  } else if (info.status === 'mismatch') {
    lines.push(` 簽章    ：${label} ✘ 與此目標應有的簽章不符${fp}`);
    lines.push(' >>> 不要發佈！金鑰配對有誤，請回頭檢查 key.properties 的配對。');
  } else if (info.status === 'unregistered') {
    lines.push(` 簽章    ：${label}（預期金鑰的指紋未登錄，無法驗證）${fp}`);
    lines.push(' >>> 把上面的 SHA-256 填進 app/config/signing_fingerprints.json 對應欄位，之後就能自動驗證。');
  } else {
    lines.push(' 簽章    ：未驗證（找不到 apksigner／keytool，產物本身仍已建置完成）');
  }

  lines.push(` OAuth   ：Google Client ID（僅顯示前 6 碼）：${info.oauthPrefix}`);
  if (info.artifacts.length > 0) {
    lines.push(' 產物    ：');
    for (const a of info.artifacts) {
      lines.push(`   ${a.name}   ${megabytes(a.sizeBytes)}   sha256 ${a.sha256}`);
    }
  }
  if (info.nextSteps.length > 0) {
    lines.push(' 下一步  ：');
    for (const s of info.nextSteps) lines.push(`   ${s}`);
  }
  lines.push('=======================================');
  return lines.join('\n');
}

module.exports = {
  EXPECTED_IDENTITY,
  IDENTITY_LABEL,
  expectedIdentityOf,
  parseApksignerOutput,
  parseKeytoolOutput,
  classifyIdentity,
  evaluateSigning,
  readPubspecVersion,
  findApksigner,
  keytoolArgs,
  parseKeyProperties,
  keystoreListArgs,
  formatPreflight,
  formatSummary,
};
