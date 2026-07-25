import { makeBook } from './view.js'
import { Overlayer } from './overlayer.js'

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

// 目前生效的排版方向（epic-17 Issue 8）：與 detectedBookWritingMode
// 不同，這個變數追蹤「目前實際套用」的方向（可能被使用者手動切換），
// 供劃線/備註繪製時判斷 Overlayer.highlight()/underline() 該用哪種
// options 形狀（見下方 draw-annotation 監聽器）。初始值於下方 FR-06 的
// { once: true } relocate 監聽器內、以及每次 window.applyPreferences()
// 呼叫時更新。
let currentWritingMode = 'horizontal'

// 目前顯示中標記的 cfi → Dart 端不透明 id（"highlight:5"/"note:12"）對照
// 表（epic-17 Issue 8）。view.addAnnotation({value}) 的 value 欄位本身
// 必須是 view.resolveNavigation() 可解析的目標（此處固定用 cfi 字串），
// 不能直接塞 Dart 端的不透明 id 字串，故另建這份表供 show-annotation
// 事件反查，見
// docs/epics/epic-17-epub-render-migration/reviews/spike-overlayer-annotations.md
// 「已記錄的既有 API 落差」。window.setDecorations() 每次呼叫時整組
// 重建，非增量更新。
let decorationIdByCfi = new Map()

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
  // epic-17 Issue 8：劃線/備註繪製需要知道目前實際生效的排版方向，見
  // currentWritingMode 宣告處註解。
  if (prefs.writingMode) {
    currentWritingMode = prefs.writingMode
  }
  // Issue 6：欄數（columnMode）與欄位大小（columnSize）控制。
  // 用 max-inline-size 控制分欄閾值，徹底解決 paginator.js 對直排書籍
  // max-column-count 的 +1 邏輯問題（見 plan-issue-6.md）。
  // columnMode: 'auto' | 'single' | 'double'
  // columnSize: 360~1440px，僅 auto 時有效。
  if (prefs.columnMode === 'single') {
    // 強制單欄：設定極大 inline-size 確保 ceil(hostSize / maxInlineSize) 永遠為 1
    view.renderer.setAttribute('max-inline-size', '99999px')
  } else if (prefs.columnMode === 'double') {
    // 硬限雙欄：計算 hostSize 並將 max-inline-size 設為 Math.ceil(hostSize / 2)
    // 注意：必須使用 Math.ceil 而非 Math.floor，保證 targetSize * 2 >= hostSize，
    // 避免奇數/帶小數 hostSize 算出的 targetSize 偏小導致 ceil(hostSize / targetSize) 變成 3 欄！
    const hostRect = view.renderer.getBoundingClientRect()
    const hostSize = currentWritingMode === 'vertical' ? hostRect.height : hostRect.width
    const targetSize = Math.max(360, Math.ceil(hostSize / 2))
    view.renderer.setAttribute('max-inline-size', `${targetSize}px`)
  } else {
    // 自動模式：使用使用者設定的 columnSize（預設 720px）。
    // undefined 時保留 foliate-js 內建 --_max-inline-size: 720px 預設值。
    if (typeof prefs.columnSize === 'number') {
      view.renderer.setAttribute('max-inline-size', `${prefs.columnSize}px`)
    }
  }
  // epic-18 Issue 4：直排上下邊距。paginator.js 內建 --_margin-top/
  // --_margin-bottom 固定 48px，從未接上使用者 pageMargins 偏好（見
  // docs/epics/epic-18-reader-device-qa/design.md「調查結論」），導致
  // (a) 頂端文字在某些字級/行高組合下被裁切（使用者回報項目 6）、
  // (b) 本文與頁尾間空白過多（項目 7，因為 ReaderFooter 已經是 in-flow
  // 子項壓縮過 WebView 可視高度一次，paginator.js 又在這個已壓縮高度內
  // 再扣一次完整 48px 下邊距，兩者疊加）。用 currentWritingMode（上面
  // 已更新為本次呼叫的最新值）判斷，不用 prefs.writingMode——理由同上方
  // 單欄覆寫註解，prefs.writingMode 在特定呼叫時序下可能是 undefined，
  // currentWritingMode 已保證持有最新已知值。margin-top/margin-bottom
  // 是長度屬性，setAttribute 傳入值必須帶 CSS 單位（純數字會被靜默
  // 忽略，見 spec.md「CSS 單位要求」）。
  if (currentWritingMode === 'vertical') {
    // pageMargins 是既有的頁邊距倍率偏好（body 左右 padding 已使用同一個
    // 值，見 buildOverrideCss()），未設定時（prefs.pageMargins 非數字）
    // 以 1（既有 UI 滑桿中性初始位置對應的倍率）當基準。
    const marginMultiplier = typeof prefs.pageMargins === 'number' ? prefs.pageMargins : 1
    // 上邊距：以內建預設值 48px 為基準放大約 1.33 倍（起始建議值，見
    // Global Constraints），解決「頂端文字被裁切」；隨 pageMargins 倍率
    // 同步縮放，使用者可再依需要調整。
    const marginTopPx = Math.round(64 * marginMultiplier)
    // 下邊距：頁尾顯示時（prefs.showFooter !== false，涵蓋 true 與
    // undefined 兩種「視同顯示」情況）只需要小幅視覺緩衝（16px 起始
    // 建議值），避免在已經被頁尾壓縮過的可視高度內再扣一次完整邊距；
    // 頁尾明確隱藏時（prefs.showFooter === false）沒有頁尾提供視覺
    // 邊界，改用與上邊距相同的較大緩衝，避免文字貼齊螢幕底緣。
    const marginBottomPx = prefs.showFooter === false
      ? Math.round(64 * marginMultiplier)
      : Math.round(16 * marginMultiplier)
    view.renderer.setAttribute('margin-top', `${marginTopPx}px`)
    view.renderer.setAttribute('margin-bottom', `${marginBottomPx}px`)
  } else {
    // 橫排：還原 paginator.js 內建預設值。setAttribute 具持久性（不會
    // 隨排版方向切換自動歸零/還原），若省略這個 else 分支，使用者從
    // 直排切回橫排後會殘留直排時設定的邊距值，違反「橫排不受本 Issue
    // 影響」的驗收標準。
    view.renderer.setAttribute('margin-top', '48px')
    view.renderer.setAttribute('margin-bottom', '48px')
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
 * 把目前應顯示的完整標記清單一次性套用（epic-17 Issue 8，比照既有
 * window.applyPreferences「整組送出」慣例，非增量 diff）：先移除全部
 * 既有標記，再逐筆呼叫 view.addAnnotation() 重新加入。[decorations] 為
 * FoliateDecorationCodec.buildDecorationEntries() 產生的
 * [{id, cfi, color, isUnderline}, ...] 陣列，由原生端
 * FoliateEpubReaderView.kt 的 setDecorations method channel case 呼叫。
 * 實際繪製邏輯在下方 draw-annotation 監聽器（本函式只負責告知 view
 * 「這些位置需要標記」，繪製視覺樣式的決定權交給監聽器，因為 draw
 * callback 只有透過 view.addAnnotation() 觸發的 draw-annotation 事件才
 * 拿得到，見 view.js addAnnotation() 原始碼）。
 */
/**
 * 【已知限制，審查修正記錄於此】重複 CFI 的最後寫入覆蓋前者：
 * decorationIdByCfi（本身是 Map，key 唯一）與 Overlayer 內部的
 * annotation map（同樣以 value/CFI 當 key，見 overlayer.js `add()`：
 * `if (this.#map.has(key)) this.remove(key)`）皆以 CFI 為 key，若
 * [decorations] 中兩筆不同標記剛好指向完全相同的 CFI（例如對完全相同的
 * 選取範圍先後建立兩種不同顏色的劃線——極端邊界情況，spike 報告
 * spike-overlayer-annotations.md「已記錄的既有 API 落差」已明確記錄
 * 「Overlayer 以 annotation.value 當 Map key，必須唯一」這項前提假設，
 * 但未實測重複 key 情境），後面那筆會在兩個 Map 中都覆蓋前者：前者的
 * 視覺標記會消失、點擊該位置只會命中後者的 id。目前不主動去重/警告，
 * 依賴 Dart 端每筆標記的 CFI 天然互不相同（不同段落/選取範圍產生不同
 * CFI）這個假設；`FoliateDecorationCodec.buildDecorationEntries()`
 * （Kotlin 端）本身不對重複 CFI 做任何處理，原樣保留全部項目，去重/
 * 覆蓋行為完全發生在這裡（JS 端 Map 語意）。
 */
window.setDecorations = function (decorations) {
  for (const cfi of decorationIdByCfi.keys()) {
    view.deleteAnnotation({ value: cfi })
  }
  decorationIdByCfi = new Map()
  for (const { id, cfi, color, isUnderline } of decorations) {
    decorationIdByCfi.set(cfi, id)
    view.addAnnotation({ value: cfi, color, isUnderline })
  }
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
        // epic-17 Issue 8 審查修正：Overlayer.highlight() 內建
        // `opacity: var(--overlayer-highlight-opacity, .3)`（overlayer.js
        // 既有程式碼，不可修改），若不覆寫這個 CSS 自訂屬性，會疊加在
        // FoliateDecorationCodec.argbIntToCssColor() 已經算好的 tint
        // alpha 之上（兩者相乘），造成螢光筆/純備註視覺上明顯比 Readium/
        // FXL 路徑（直接用 tint alpha、無額外乘數）更淡。本 App 的透明度
        // 完全由 tint 的 ARGB alpha 決定，故固定覆蓋為 1（不透明度
        // 100%），讓 rgba() 自帶的 alpha 成為唯一透明度來源，與 Readium
        // 路徑語意一致。底線（Overlayer.underline()）不受影響，該函式
        // 未設定這個 CSS 變數。此規則須無條件套用（不像下方 writingMode
        // 覆蓋依 initialPrefs 決定是否附加），故獨立於下方判斷之外組裝。
        let overriddenCss = `${css}\nhtml, body { --overlayer-highlight-opacity: 1; }\n`
        // 初次開書若呼叫端（openBook 的 initialPreferences）未指定
        // writingMode，不附加排版方向覆蓋規則，讓書本自己的 CSS 宣告
        // （或無宣告時的預設橫排）自然生效（ADR 0003「初次開書不主動
        // 設定」）。
        if (initialPrefs.writingMode) {
          const override = initialPrefs.writingMode === 'vertical'
            ? 'writing-mode: vertical-rl !important;'
            : 'writing-mode: horizontal-tb !important;'
          overriddenCss += `html, body { ${override} }\n`
        }
        return overriddenCss
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
    // 劃線/備註繪製（epic-17 Issue 8）：view.addAnnotation() 對於一般
    // 標記（非 foliate-search:/foliate-note: 前綴），透過 draw-annotation
    // 事件把繪製決定權交還給呼叫端（見 view.js addAnnotation() 原始碼），
    // annotation 即是 window.setDecorations() 傳入 view.addAnnotation()
    // 的 {value, color, isUnderline} 物件本身（addAnnotation() 原樣透傳，
    // 未做任何欄位過濾）。Overlayer.highlight()/underline() 的 options
    // 形狀不同（vertical: boolean vs writingMode: string），依
    // isUnderline 分流組裝，不可共用同一組參數物件（見
    // spike-overlayer-annotations.md「已記錄的既有 API 落差」）。
    view.addEventListener('draw-annotation', (e) => {
      const { draw, annotation } = e.detail
      if (annotation.isUnderline) {
        draw(Overlayer.underline, {
          color: annotation.color,
          writingMode: currentWritingMode === 'vertical' ? 'vertical-rl' : 'horizontal-tb',
        })
      } else {
        draw(Overlayer.highlight, {
          color: annotation.color,
          vertical: currentWritingMode === 'vertical',
        })
      }
    })
    // 點擊既有標記（epic-17 Issue 8）：value 即建立時傳入的 cfi（見
    // window.setDecorations()），透過 decorationIdByCfi 反查 Dart 端的
    // 不透明 id 字串（"highlight:5"/"note:12"，見 epub_decoration.dart
    // decodeAnnotationId() 編碼慣例）。查無對應（理論上不會發生，標記
    // 只可能在 setDecorations 已呼叫過後才可能被點擊）時靜默忽略，比照
    // 本檔案既有對非致命錯誤的處理原則。
    view.addEventListener('show-annotation', (e) => {
      const id = decorationIdByCfi.get(e.detail.value)
      if (id) window.FoliateBridge.onAnnotationActivated(id)
    })
    // 選取範圍即時回報（epic-17 Issue 8）：'load' 事件對 look-ahead
    // 預讀章節同樣會觸發，故 doc/index 皆從本次 'load' 呼叫的區域變數
    // 閉包讀取，不快取到模組級共用變數再事後讀取（見
    // spike-overlayer-annotations.md「已記錄的既有 API 落差」，此陷阱
    // 在該次驗證的兩條獨立程式碼路徑上各自獨立命中）。長按拖曳選字這類
    // 使用者手勢天生只會發生在目前實際可視的 iframe 上，selectionchange
    // 在背景預讀章節的 doc 上觸發時 getSelection().rangeCount 恆為 0，
    // 不需要額外的「目前是否可視」判斷。選取範圍用
    // window.getSelection().getRangeAt(0) 取得，天然是文字節點邊界
    // （非 selectNodeContents(element)），CFI round-trip 不會被壓扁，見
    // spike-overlayer-annotations.md 研究問題 #1 的既有限制說明。
    view.addEventListener('load', (e) => {
      const doc = e.detail.doc
      const index = e.detail.index
      doc.addEventListener('selectionchange', async () => {
        const selection = doc.getSelection()
        if (!selection || selection.rangeCount === 0 || selection.isCollapsed) {
          window.FoliateBridge.onSelectionCleared()
          return
        }
        const range = selection.getRangeAt(0)
        const rect = range.getClientRects()[0]
        if (!rect) return
        const cfi = view.getCFI(index, range)
        const progress = await view.getCFIProgress(cfi)
        // 座標換算（Issue 7 Spike 已驗證公式）：iframe 內局部矩形 + iframe
        // 相對外層 #view 容器的位移，除以外層容器可視尺寸。只取第一個
        // client rect 當代表矩形（多欄選取的代表 rect 策略，見
        // spike-overlayer-annotations.md「留白」段落——現有 PercentRect
        // 契約本身就只回報單一矩形，這是既有契約的限制，非本工單新增）。
        const iframeRect = doc.defaultView.frameElement.getBoundingClientRect()
        const viewportRect = view.getBoundingClientRect()
        window.FoliateBridge.onSelectionChanged(
          JSON.stringify({ cfi, index, fraction: progress?.fraction ?? 0 }),
          progress?.fraction ?? 0,
          (iframeRect.left + rect.left - viewportRect.left) / viewportRect.width,
          (iframeRect.top + rect.top - viewportRect.top) / viewportRect.height,
          (iframeRect.left + rect.right - viewportRect.left) / viewportRect.width,
          (iframeRect.top + rect.bottom - viewportRect.top) / viewportRect.height,
        )
      })
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
