import { makeBook } from './view.js'

const view = document.getElementById('view')

// FoliateBridge 由原生端 FoliateEpubReaderView.kt 透過
// WebView.addJavascriptInterface() 注入，見該檔案 KDoc 說明——不是
// console.log 解析（那是 Issue 1 Spike harness 專屬手法）。

const params = new URLSearchParams(location.search)
const initialPrefs = JSON.parse(params.get('prefs') || '{}')
// 5 款內建字型的 @font-face 宣告（見 FoliateEpubReaderView.kt
// buildFontFaceCss()），開書當下由原生端算好透過 query string 傳入，字型
// 檔案路徑固定不隨後續 applyPreferences 呼叫變動。
const fontFaceCss = params.get('fontFaceCss') || ''
// 開書起始定位（epic-17 Issue 6）：原生端已透過 FoliateLocatorCodec
// .extractCfi() 驗證過格式，這裡拿到的要嘛是合法 CFI 字串，要嘛是空字串
// （缺席／舊格式／無效資料的優雅退回，見 Global Constraints），不需要
// 再自行判斷格式。
const initialCfi = params.get('initialCfi') || ''

// 判斷書本第一個 section 的 CSS 是否已宣告 writing-mode（epic-17
// Issue 4，FR-06）。同時涵蓋標準屬性與 EPUB 專屬的 -epub- 前綴寫法；只
// 檢查值是否為 vertical-rl/vertical-lr——horizontal-tb 或其他非直排值視為
// 「未宣告直排」，交由後續判斷邏輯處理。
const WRITING_MODE_DECLARATION_RE =
  /(?:^|[^-])(?:-epub-)?writing-mode\s*:\s*vertical-(?:rl|lr)/i

// FR-06 偵測結果，null 代表尚未偵測到任何 CSS 資源（理論上開書流程中
// 第一個 CSS 資源解析時就會賦值一次，之後維持不變——只需要書本「第一個」
// section 的判斷結果，見 issues.md Issue 4 描述）。
let detectedBookWritingMode = null

/**
 * 依目前偏好 [prefs] 產生要疊加在書本樣式之上的覆蓋 CSS 文字（透過
 * Paginator.setStyles() 的第二個陣列元素套用，見 Global Constraints）。
 * `publisherStyles === false` 時改用萬用選取器 `*`，讓覆蓋規則的優先度
 * 蓋過書本自己更具體的選取器（比照 Readium「忽略出版社樣式」的既有語意
 * 精神，非逐位元組相同的實作，這兩套渲染引擎本就刻意獨立，見 ADR 0011）。
 */
function buildOverrideCss(prefs) {
  const rules = []
  const selector = prefs.publisherStyles === false
    ? '*'
    : 'body, p, div, li, span, td, th, blockquote, dd, dt, a, h1, h2, h3, h4, h5, h6'

  if (prefs.writingMode === 'vertical') {
    // 註：若原書宣告 vertical-lr，覆蓋時亦統一輸出 CJK 主流之 vertical-rl !important（符合本 App 直排規劃目標）
    rules.push('html, body { writing-mode: vertical-rl !important; }')
  } else if (prefs.writingMode === 'horizontal') {
    rules.push('html, body { writing-mode: horizontal-tb !important; }')
  }
  if (prefs.fontFamily) {
    rules.push(`${selector} { font-family: '${prefs.fontFamily}' !important; }`)
  }
  if (typeof prefs.fontSize === 'number') {
    rules.push(`html { font-size: ${prefs.fontSize * 100}% !important; }`)
  }
  if (typeof prefs.fontWeight === 'number') {
    // 換算方式與 EpubReaderView.kt applyFontWeightCascade() 一致
    // （0-1000 CSS font-weight 數值空間，Readium 倍率 1.0 對應 CSS 400）。
    const cssWeight = Math.min(1000, Math.max(1, Math.round(prefs.fontWeight * 400)))
    rules.push(`${selector} { font-weight: ${cssWeight} !important; }`)
  }
  if (typeof prefs.lineHeight === 'number') {
    rules.push(`html, body { line-height: ${prefs.lineHeight} !important; }`)
  }
  if (typeof prefs.paragraphSpacing === 'number') {
    rules.push(`p { margin-bottom: ${prefs.paragraphSpacing}em !important; }`)
  }
  if (typeof prefs.pageMargins === 'number') {
    rules.push(`body { padding: 0 ${1.5 * prefs.pageMargins}em !important; }`)
  }
  if (prefs.textAlign) {
    rules.push(`p { text-align: ${prefs.textAlign} !important; }`)
  }
  return rules.join('\n')
}

/**
 * 套用完整偏好設定（開書當下的 initialPreferences，或後續 setPreferences
 * 呼叫，兩者格式相同）：pageTurnMode 對應 Paginator 的 flow 屬性（獨立於
 * CSS 覆蓋之外的設定），其餘 9 項透過 setStyles() 疊加 CSS。暴露為
 * window 全域函式供原生端 evaluateJavascript 呼叫（見
 * FoliateEpubReaderView.kt setPreferences()）。
 */
window.applyPreferences = function (prefs) {
  if (prefs.pageTurnMode) {
    view.renderer.setAttribute(
      'flow',
      prefs.pageTurnMode === 'scroll' ? 'scrolled' : 'paginated',
    )
  }
  view.renderer.setStyles([fontFaceCss, buildOverrideCss(prefs)])
}

/**
 * 換頁／跳轉全書進度比例，供原生端 FoliateEpubReaderView.kt 的
 * nextPage／previousPage／jumpToProgression method channel case 呼叫
 * （evaluateJavascript 只能存取掛在 window 上的函式，view 是本模組頂層
 * 作用域的 const，不會自動出現在 window 上，見 Global Constraints）。
 * view.next()/view.prev()/view.goToFraction() 為 readest/foliate-js
 * View 類別既有 API（已查證 view.js 原始碼確認存在），本函式不重新實作
 * 任何換頁邏輯，純粹是可供 evaluateJavascript 呼叫的橋接層。
 */
window.nextPage = function () {
  view.next()
}

window.previousPage = function () {
  view.prev()
}

window.jumpToFraction = function (fraction) {
  view.goToFraction(fraction)
}

/**
 * 跳轉到指定 CFI（epic-17 Issue 6）。[cfi] 已由原生端
 * FoliateLocatorCodec.extractCfi() 驗證過格式（新格式定位 JSON 才會呼叫
 * 到這裡，舊格式/無效 JSON 在原生端就已被過濾掉，見
 * FoliateEpubReaderView.kt「jumpToLocator」case），本函式不需要再自行
 * 解析 JSON 或判斷格式。
 */
window.jumpToLocator = function (cfi) {
  view.goTo(cfi)
}

/**
 * 遞迴解析單一目錄節點：透過 view.book.resolveHref() 取得 {index, anchor}，
 * 載入該 section 的文件（book.sections[index].createDocument()，獨立於
 * 目前實際顯示中的頁面，不影響閱讀畫面）後計算對應 CFI；href 無法解析、
 * 缺少頁內錨點（anchor(doc) 回傳非 Node 值，例如純章節起點連結）、或文件
 * 載入失敗時，退回 section 層級的 base CFI（view.getCFI(index, undefined)，
 * 不含頁內錨點精度，比照 view.js getCFI() 既有的 baseCFI 退路，仍可跳轉
 * 到正確章節，見 Global Constraints）。
 */
async function buildTocEntry(item) {
  const resolved = item.href ? view.book.resolveHref(item.href) : null
  let cfi = null
  let index = null
  let fraction = null
  if (resolved && resolved.index >= 0) {
    index = resolved.index
    try {
      const doc = await view.book.sections[index].createDocument()
      const frag = resolved.anchor(doc)
      let range
      if (frag instanceof Range) {
        range = frag
      } else if (frag && frag.nodeType) {
        range = doc.createRange()
        range.selectNodeContents(frag)
      }
      cfi = view.getCFI(index, range)
    } catch (e) {
      cfi = view.getCFI(index, undefined)
    }
    if (cfi) {
      const progress = await view.getCFIProgress(cfi)
      fraction = progress?.fraction ?? null
    }
  }
  const children = []
  for (const sub of item.subitems ?? []) {
    children.push(await buildTocEntry(sub))
  }
  return {
    title: item.label ?? '',
    locatorJson: cfi
      ? JSON.stringify({ cfi, index, fraction })
      : '',
    progression: fraction,
    children,
  }
}

/**
 * 讀取全書目錄（epic-17 Issue 6），供原生端 getTableOfContents method
 * channel case 呼叫。非同步計算完成後主動透過 FoliateBridge 回呼原生端
 * ——WebView.evaluateJavascript 的 callback 不會等待 async function 內部
 * 的 Promise resolve（只會拿到 Promise 物件本身序列化後的無意義結果），
 * 見 FoliateEpubReaderView.kt onTableOfContentsReady() 註解與 Global
 * Constraints，本函式因此不能單純依賴 evaluateJavascript 的回傳值。
 */
window.getTableOfContents = async function () {
  try {
    const items = view.book?.toc ?? []
    const entries = []
    for (const item of items) {
      entries.push(await buildTocEntry(item))
    }
    window.FoliateBridge.onTableOfContentsReady(JSON.stringify(entries))
  } catch (e) {
    window.FoliateBridge.onTableOfContentsReady(JSON.stringify([]))
  }
}

async function openBook() {
  try {
    const book = await makeBook(
      'https://appassets.androidplatform.net/book/current.epub',
    )
    // 雙向 writing-mode CSS 覆蓋 + FR-06 偵測：在每個 CSS 資源文字被解析前
    // 攔截——比照 Issue 1 Spike 已驗證的時序（見 Global Constraints），
    // 保證於 Paginator 第一次計算方向/分欄之前就已生效。
    book.transformTarget?.addEventListener('data', (e) => {
      if (e.detail.type !== 'text/css') return
      e.detail.data = Promise.resolve(e.detail.data).then((css) => {
        if (detectedBookWritingMode === null) {
          detectedBookWritingMode = WRITING_MODE_DECLARATION_RE.test(css)
            ? 'vertical'
            : 'horizontal'
        }
        // 初次開書若呼叫端（openBook 的 initialPreferences）未指定
        // writingMode，不附加任何覆蓋規則，讓書本自己的 CSS 宣告（或無
        // 宣告時的預設橫排）自然生效（ADR 0003「初次開書不主動設定」）。
        if (!initialPrefs.writingMode) return css
        const override = initialPrefs.writingMode === 'vertical'
          ? 'writing-mode: vertical-rl !important;'
          : 'writing-mode: horizontal-tb !important;'
        return `${css}\nhtml, body { ${override} }\n`
      })
    })
    // 見 Issue 1 Spike（plans/plan-issue-1.md Task 2）已驗證的行為與 Issue 3
    // 已驗證的觸發時機：view.open(book) 本身不導覽到任何 section，
    // relocate 事件在 view.init() 內部完成首次導覽後才觸發，{ once: true }
    // 確保只處理第一次。
    view.addEventListener('relocate', () => {
      const resolvedWritingMode =
        initialPrefs.writingMode ?? detectedBookWritingMode ?? 'horizontal'
      window.applyPreferences({ ...initialPrefs, writingMode: resolvedWritingMode })
      window.FoliateBridge.onPageRendered(resolvedWritingMode)
    }, { once: true })
    // 目前定位變動持續推播（epic-17 Issue 6）：與上方 { once: true } 的
    // FR-06/onPageRendered 監聽器各自獨立、互不影響，開書當下的第一次
    // relocate 事件兩者皆會觸發。location.current／location.total 為
    // foliate-js SectionProgress.getProgress() 既有輸出（見
    // progress.js），近似頁碼概念，非精確渲染頁數。
    view.addEventListener('relocate', (e) => {
      const { cfi, section, fraction, location } = e.detail
      window.FoliateBridge.onLocatorChanged(
        JSON.stringify({ cfi, index: section?.current ?? 0, fraction: fraction ?? 0 }),
        fraction ?? 0,
        location?.current ?? 0,
        location?.total ?? 0,
      )
    })
    await view.open(book)
    view.renderer.setAttribute(
      'flow',
      initialPrefs.pageTurnMode === 'scroll' ? 'scrolled' : 'paginated',
    )
    await view.init(initialCfi ? { lastLocation: initialCfi } : {})
  } catch (e) {
    window.FoliateBridge.onError(String((e && e.message) || e))
  }
}

openBook()
