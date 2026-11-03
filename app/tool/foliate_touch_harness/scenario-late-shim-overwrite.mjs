// applyPreferences 佔位 shim 晚到覆蓋真函式的回歸場景。
//
// 背景（真機 BooksPad，WebView 91.0.4472.114，單欄直排卻顯示雙欄）：
// foliate_reader_view.dart 以 initialUserScripts 在 AT_DOCUMENT_START 注入佔位 shim
// （window.applyPreferences = 只存值、window.__pendingApplyPreferences = null）。
// 舊版 WebView 偶爾讓這段注入晚到——真機 logcat 顯示失敗那次 `[UserAgent]`（同批注入腳本）
// 只出現 1 次、且晚於「頁面載入完成」。shim 晚到會把 main.js 已定義好的真函式蓋掉，
// 之後所有偏好只被暫存、永遠不套用：renderer 沒有 max-column-count／max-inline-size／
// 邊距屬性，退回預設 2 欄、720px。
//
// 本場景從 Dart 原始碼取出真正的 shim 字串（不重寫一份，避免測試與正式碼分叉），
// 開書完成後再執行一次 shim 模擬「晚到」，然後呼叫 applyPreferences 要求單欄直排。
// 防護在 shim（真函式存在時不得覆蓋）。移除防護時，案例 2 應 FAIL。

import { readFile } from 'node:fs/promises'
import path from 'node:path'
import { fileURLToPath } from 'node:url'
import { launchHarnessPage, report } from './lib/harness.mjs'

const __dirname = path.dirname(fileURLToPath(import.meta.url))
const DART_PATH = path.resolve(__dirname, '../../lib/reader/foliate_reader_view.dart')

const PREFS = {
  writingMode: 'vertical', pageTurnMode: 'paginated', columnMode: 'single',
  columnSize: 720, fontSize: 1.0, marginTop: 32, marginBottom: 16,
  marginLeft: 24, marginRight: 24,
}

/** 從 Dart 原始碼取出 `_applyPreferencesQueueShimJs` 的 JS 內容。 */
async function loadShimSource() {
  const dart = await readFile(DART_PATH, 'utf8')
  const m = dart.match(/const _applyPreferencesQueueShimJs = '''([\s\S]*?)''';/)
  if (!m) throw new Error('找不到 _applyPreferencesQueueShimJs，請確認 foliate_reader_view.dart')
  return m[1]
}

const readRendererAttrs = (page) => page.evaluate(() => {
  const r = document.querySelector('foliate-view').renderer
  return {
    maxInline: r.getAttribute('max-inline-size'),
    maxCol: r.getAttribute('max-column-count'),
    columnCount: r.columnCount,
  }
})

async function runCase(shimSource, { injectLate }) {
  const { browser, page, pageErrors } = await launchHarnessPage({
    fixtureFileName: 'sample.epub',
    writingMode: 'vertical',
    prefs: PREFS,
    // 正常順序：shim 先於 main.js（AT_DOCUMENT_START）。
    beforeNavigate: async (p) => { await p.evaluateOnNewDocument(shimSource) },
  })
  try {
    if (injectLate) await page.evaluate(shimSource) // 模擬 shim 晚到
    // 把 renderer 屬性清掉，確保斷言看到的是「這次呼叫」的結果，而非開書時殘留。
    await page.evaluate(() => {
      const r = document.querySelector('foliate-view').renderer
      for (const a of ['max-inline-size', 'max-column-count']) r.removeAttribute(a)
    })
    await page.evaluate((prefs) => window.applyPreferences(prefs), PREFS)
    const attrs = await readRendererAttrs(page)
    return { attrs, pageErrors }
  } finally {
    await browser.close()
  }
}

async function main() {
  const shimSource = await loadShimSource()

  const normal = await runCase(shimSource, { injectLate: false })
  report('案例 1（shim 正常先到）：單欄設定套用到 renderer',
    normal.attrs.maxInline === '99999px' && normal.attrs.maxCol === '1',
    JSON.stringify(normal.attrs))

  const late = await runCase(shimSource, { injectLate: true })
  report('案例 2（shim 晚到）：單欄設定仍套用到 renderer',
    late.attrs.maxInline === '99999px' && late.attrs.maxCol === '1',
    JSON.stringify(late.attrs))
  report('頁面沒有未捕捉的例外',
    normal.pageErrors.length === 0 && late.pageErrors.length === 0,
    [...normal.pageErrors, ...late.pageErrors].join(' | '))
}

main().catch((err) => { console.error(err); process.exitCode = 2 })
