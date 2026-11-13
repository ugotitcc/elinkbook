// 把 assets/foliate/ 的 JS 降級成 Chrome 83 看得懂的語法，輸出到 assets/foliate/legacy/。
//
// 為什麼需要：iReader Ocean 4 Plus 的 WebView 是 Chrome 83，看不懂私有方法（#foo()，
// Chrome 84 才支援），釘定的 foliate-js 整個載入失敗。原始檔案不動，只產生降級副本；
// 執行期由 index.html／探針頁依 UA 版本決定載入哪一份（見 FoliateLegacy 說明）。
//
// 用法（在本資料夾）：pnpm install && pnpm build
import { readdirSync, statSync, mkdirSync, rmSync, readFileSync, writeFileSync } from 'node:fs'
import { join, relative, dirname } from 'node:path'
import { fileURLToPath } from 'node:url'
import { transform } from 'esbuild'

const here = dirname(fileURLToPath(import.meta.url))
const srcDir = join(here, '..', '..', 'android', 'app', 'src', 'main', 'assets', 'foliate')
const outDir = join(srcDir, 'legacy')

// 目標：Chrome 83。esbuild 會降級私有方法、??=、static block 等；
// 遇到無法降級的語法（例如頂層 await）會直接報錯，不會默默放過。
const TARGET = 'chrome83'

function listJs(dir) {
  const result = []
  for (const name of readdirSync(dir)) {
    const full = join(dir, name)
    if (full === outDir) continue // 不處理自己的輸出
    if (statSync(full).isDirectory()) result.push(...listJs(full))
    else if (name.endsWith('.js')) result.push(full)
  }
  return result
}

rmSync(outDir, { recursive: true, force: true })
let count = 0
let failed = 0
for (const file of listJs(srcDir)) {
  const rel = relative(srcDir, file)
  const code = readFileSync(file, 'utf8')
  try {
    const out = await transform(code, {
      loader: 'js',
      format: 'esm',
      target: TARGET,
      sourcefile: rel,
      legalComments: 'none',
    })
    let outCode = out.code
    // CSS 的 :is()（Chrome 88+）esbuild 不會處理，Chrome 83 會整條規則丟棄，
    // 改寫成展開後的等價選擇器（只有 paginator.js 的頁首／頁尾樣式用到）。
    outCode = outCode
      .replaceAll(':is(#header, #footer) > * > * {', '#header > * > *, #footer > * > * {')
      .replaceAll(':is(#header, #footer) > * {', '#header > *, #footer > * {')
    if (outCode.includes(':is(')) console.warn(`⚠ ${rel} 仍含 :is()，Chrome 83 不支援`)
    const dest = join(outDir, rel)
    mkdirSync(dirname(dest), { recursive: true })
    writeFileSync(dest, outCode)
    count++
  } catch (e) {
    failed++
    console.error(`✗ ${rel}\n${e.message}`)
  }
}
console.log(`完成：${count} 個檔案降級到 ${relative(process.cwd(), outDir)}，失敗 ${failed} 個`)
process.exit(failed === 0 ? 0 : 1)
