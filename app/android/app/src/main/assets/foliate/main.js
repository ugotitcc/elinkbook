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
    await view.open(book)
    view.renderer.setAttribute(
      'flow',
      initialPrefs.pageTurnMode === 'scroll' ? 'scrolled' : 'paginated',
    )
    await view.init({})
  } catch (e) {
    window.FoliateBridge.onError(String((e && e.message) || e))
  }
}

openBook()
