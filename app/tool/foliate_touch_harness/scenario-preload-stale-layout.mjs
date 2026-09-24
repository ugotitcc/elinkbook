// 預讀章節套用過時排版（時序競爭）的回歸場景。
//
// 背景（fix(reader): 預讀章節套用過時排版導致直排單欄偶爾變雙欄）：
// paginator.js 預讀相鄰章節時，在 `await view.load()` 之前就捕捉 `#lastLayout`；
// 若載入期間主要章節的排版改變，預讀章節載完後仍套用過時的 columnWidth，之後沒有
// 任何機制修正——直排文件套到過時的欄寬，會在容器內排成 2 欄，翻到該章才看見。
// 真機開書時，applyPreferences() 於首章尚未載完時就執行（以橫排數值排版空白文件並
// 觸發預讀）即是實際觸發來源；本場景以「延遲預讀章節的 iframe load」＋「延遲期間
// 改變排版」決定性地重現同類競爭。
//
// 防護在 main.js（章節載入完成後比對各章節文件的 column-width，不一致就呼叫
// renderer.render()）。移除該防護時，本場景應 FAIL。

import { launchHarnessPage, buildStoredZip, report } from './lib/harness.mjs'

const PRELOAD_LOAD_DELAY_MS = 1500
const SECTION_COUNT = 5

/** 記憶體中組一本 5 個短章節的最小合法 EPUB（比照 scenario-disable-publisher-styles.mjs，
 * 不需另外提交二進位 fixture）。章節夠短，開書後翻頁即會預讀相鄰章節。 */
function buildFixtureEpub() {
  const ids = Array.from({ length: SECTION_COUNT }, (_, i) => i + 1)
  const containerXml = `<?xml version="1.0" encoding="UTF-8"?>
<container version="1.0" xmlns="urn:oasis:names:tc:opendocument:xmlns:container">
  <rootfiles><rootfile full-path="OEBPS/content.opf" media-type="application/oebps-package+xml"/></rootfiles>
</container>
`
  const contentOpf = `<?xml version="1.0" encoding="UTF-8"?>
<package xmlns="http://www.idpf.org/2007/opf" version="3.0" unique-identifier="pub-id">
  <metadata xmlns:dc="http://purl.org/dc/elements/1.1/">
    <dc:identifier id="pub-id">urn:uuid:00000000-0000-0000-0000-000000000098</dc:identifier>
    <dc:title>預讀章節排版競爭診斷用EPUB</dc:title>
    <dc:language>zh-TW</dc:language>
    <meta property="dcterms:modified">2026-01-01T00:00:00Z</meta>
  </metadata>
  <manifest>
    <item id="nav" href="nav.xhtml" media-type="application/xhtml+xml" properties="nav"/>
    <item id="style" href="style.css" media-type="text/css"/>
${ids.map((i) => `    <item id="c${i}" href="c${i}.xhtml" media-type="application/xhtml+xml"/>`).join('\n')}
  </manifest>
  <spine>
${ids.map((i) => `    <itemref idref="c${i}"/>`).join('\n')}
  </spine>
</package>
`
  const navXhtml = `<?xml version="1.0" encoding="UTF-8"?>
<html xmlns="http://www.w3.org/1999/xhtml" xmlns:epub="http://www.idpf.org/2007/ops">
<head><title>目錄</title></head>
<body><nav epub:type="toc"><ol>
${ids.map((i) => `<li><a href="c${i}.xhtml">第${i}章</a></li>`).join('')}
</ol></nav></body>
</html>
`
  const chapter = (i) => `<?xml version="1.0" encoding="UTF-8"?>
<html xmlns="http://www.w3.org/1999/xhtml">
<head><title>第${i}章</title><link rel="stylesheet" type="text/css" href="style.css"/></head>
<body>
  <h1>第${i}章</h1>
  <p>這是第${i}章的第一段內容，用來讓直排文件有足夠的文字可以排版與分頁，長度需超過測試門檻。</p>
  <p>這是第${i}章的第二段內容，同樣是為了診斷預讀章節排版而準備的示範文字。</p>
</body>
</html>
`
  return buildStoredZip([
    { name: 'mimetype', data: Buffer.from('application/epub+zip') },
    { name: 'META-INF/container.xml', data: Buffer.from(containerXml) },
    { name: 'OEBPS/content.opf', data: Buffer.from(contentOpf) },
    { name: 'OEBPS/nav.xhtml', data: Buffer.from(navXhtml) },
    { name: 'OEBPS/style.css', data: Buffer.from('body { margin: 0; }') },
    ...ids.map((i) => ({ name: `OEBPS/c${i}.xhtml`, data: Buffer.from(chapter(i)) })),
  ])
}

// 直排、單欄；用真機（AiPaper Reader C）尺寸，容器高度與 max-inline-size 的關係才會
// 讓欄數判定貼近真實。
const PREFS = {
  fontSize: 1.875, lineHeight: 1.3, letterSpacing: 0.06,
  marginTop: 0, marginBottom: 0, marginLeft: 16, marginRight: 20,
  columnMode: 'single', columnSize: 720,
}

/** 註冊「可控制的 iframe load 延遲」：`window.__delayNextIframeLoads` 大於 0 時，下一個建立
 * 的 iframe 的 load 事件會延遲 PRELOAD_LOAD_DELAY_MS，並將計數減 1。這樣可以精準只延遲
 * 「目標預讀章節」那一個 iframe，其餘章節正常載入——若連其他預讀章節也延遲，它們載完時
 * 觸發的 render() 會偶然把過時排版的章節「救回來」，導致未修復時不穩定地通過。 */
async function installControllableIframeDelay(page) {
  await page.evaluateOnNewDocument((delay) => {
    window.__delayNextIframeLoads = 0
    const original = EventTarget.prototype.addEventListener
    EventTarget.prototype.addEventListener = function (type, listener, options) {
      if (type === 'load' && this instanceof HTMLIFrameElement && typeof listener === 'function'
          && window.__delayNextIframeLoads > 0) {
        window.__delayNextIframeLoads--
        const delayed = function (...args) { setTimeout(() => listener.apply(this, args), delay) }
        return original.call(this, type, delayed, options)
      }
      return original.call(this, type, listener, options)
    }
  }, PRELOAD_LOAD_DELAY_MS)
}

function iframeCount(page) {
  return page.evaluate(() => {
    const container = document.querySelector('foliate-view')?.renderer?.shadowRoot?.getElementById('container')
    return container?.querySelectorAll('iframe').length ?? 0
  })
}

function sectionColumnWidths(page) {
  return page.evaluate(() => {
    const renderer = document.querySelector('foliate-view').renderer
    return renderer.getContents().map((c) => ({
      index: c.index,
      columnWidth: Math.round(parseFloat(c.doc.documentElement.style.columnWidth)),
    }))
  })
}

/** 預讀章節依序載入（每個延遲 ${PRELOAD_LOAD_DELAY_MS}ms），輪詢到「所有章節文件都已排版
 * （column-width 為有限數）且連續兩次量測結果不變」才回傳；逾時則回傳最後一次量測。 */
async function waitForSectionsSettled(page, { timeoutMs = 20000, intervalMs = 400 } = {}) {
  const deadline = Date.now() + timeoutMs
  let previous = null
  let last = await sectionColumnWidths(page)
  while (Date.now() < deadline) {
    await new Promise((r) => setTimeout(r, intervalMs))
    last = await sectionColumnWidths(page)
    const allLaidOut = last.length >= 2 && last.every((w) => Number.isFinite(w.columnWidth))
    const serialized = JSON.stringify(last)
    if (allLaidOut && serialized === previous) return last
    previous = serialized
  }
  return last
}

async function main() {
  const { browser, page, pageErrors } = await launchHarnessPage({
    fixtureBuffer: buildFixtureEpub(),
    writingMode: 'vertical',
    prefs: PREFS,
    viewport: { width: 376, height: 752 },
    beforeNavigate: installControllableIframeDelay,
  })
  try {
    // 步驟 1：等開書時的初始預讀全部載完（iframe 數量穩定），取得基準數量。否則無法分辨
    // 之後看到的 iframe 是新預讀，還是開書時早已存在的。
    await waitForSectionsSettled(page)
    const baseline = await iframeCount(page)
    // 步驟 2：讓「下一個建立的 iframe」延遲載入，並翻頁直到出現「新增」的預讀 iframe。paginator 建立 iframe 與捕捉當下快取排版
    // 在同一個同步區段內，所以 iframe 一出現，該預讀章節的快取即已捕捉、且其 load 還要
    // PRELOAD_LOAD_DELAY_MS 才會完成。
    await page.evaluate(() => { window.__delayNextIframeLoads = 1 })
    for (let i = 0; i < 8 && (await iframeCount(page)) <= baseline; i++) {
      await page.evaluate(() => window.nextPage())
      await new Promise((r) => setTimeout(r, 150))
    }
    report('翻頁後出現新的預讀 iframe（確認落在競爭視窗內，避免空轉通過）',
      (await iframeCount(page)) > baseline, `基準=${baseline}`)
    // 步驟 3：在預讀章節載完之前，改變排版（單欄 -> 雙欄，使 columnWidth 減半），
    // 該預讀章節載完時套用的便是過時快取。
    await page.evaluate((prefs) => window.applyPreferences({
      ...prefs, writingMode: 'vertical', pageTurnMode: 'paginated', columnMode: 'double',
    }), PREFS)

    // 等目標預讀章節載完（其餘章節早已載完，沒有後續事件會救它），再量測。
    await new Promise((r) => setTimeout(r, PRELOAD_LOAD_DELAY_MS + 500))
    const widths = await waitForSectionsSettled(page, { timeoutMs: 5000 })
    report('預讀章節確實被載入（至少 2 個章節文件，避免空轉通過）',
      widths.length >= 2, `章節=${JSON.stringify(widths)}`)
    const distinct = [...new Set(widths.map((w) => w.columnWidth))]
    report('所有章節文件的 column-width 一致（預讀章節未停留在過時排版）',
      widths.length >= 2 && distinct.length === 1, `column-width 種類=${JSON.stringify(distinct)}`)
    report('頁面沒有未捕捉的例外', pageErrors.length === 0, pageErrors.join(' | '))
  } finally {
    await browser.close()
  }
}

main().catch((err) => { console.error(err); process.exitCode = 2 })
