import { makeBook } from './view.js'
import { Overlayer } from './overlayer.js'

const view = document.getElementById('view')

// JS→Dart 橋接透過 window.flutter_inappwebview.callHandler(...) 呼叫（見
// 下方各處呼叫），對應的 handler 由 Dart 端 foliate_epub_reader_view.dart
// 的 _onWebViewCreated() 用 InAppWebViewController.addJavaScriptHandler()
// 註冊（epic-18 Issue 10 遷移，取代原本 Kotlin 端
// WebView.addJavascriptInterface() 注入的 FoliateBridge 機制）——不是
// console.log 解析（那是 Issue 1 Spike harness 專屬手法）。

const params = new URLSearchParams(location.search)
const initialPrefs = JSON.parse(params.get('prefs') || '{}')
// 5 款內建字型的 @font-face 宣告（見 foliate_native_bridge.dart
// buildFontFaceCss()），開書當下由 Dart 端算好透過 query string 傳入，字型
// 檔案路徑固定不隨後續 applyPreferences 呼叫變動。
const fontFaceCss = params.get('fontFaceCss') || ''
// 開書起始定位（epic-17 Issue 6）：Dart 端已透過 foliate_bridge_codec.dart
// extractCfi() 驗證過格式，這裡拿到的要嘛是合法 CFI 字串，要嘛是空字串
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
// Issue 9：裝置旋轉/視窗尺寸變化時重新呼叫 applyPreferences() 需要知道
// 「最後一次完整套用過的偏好物件」是什麼，見下方 window.applyPreferences()
// 開頭賦值處與 openBook() 內的 ResizeObserver 註冊。初始值設為 initialPrefs，
// 涵蓋「開書當下第一次 relocate 事件觸發 applyPreferences() 之前」若恰好
// 發生一次 resize 的邊界情況（此時仍能拿到開書時傳入的完整偏好，而非
// undefined）。
let lastAppliedPrefs = initialPrefs

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
    // epic-18-reader-device-qa Issue 25 把行高滑桿範圍下限改為 0 後，
    // prefs.lineHeight 可能真的是 0——CSS line-height: 0 會讓每一行文字
    // 的行高坍塌為 0px，所有行完全疊在一起、無法閱讀（審查發現，
    // 2026-08-05）。下限訂為 0.8（常見可讀行高下限，含本 App 目標的
    // CJK 直排內容），比照上面 fontWeight 已有的防呆 clamp 慣例。
    const effectiveLineHeight = Math.max(0.8, prefs.lineHeight)
    // 【診斷修正，epic-18-reader-device-qa Issue 34】原本只鎖定
    // `html, body`，只設定「可被繼承的值」——書本自己的 CSS 若在 p／
    // div 等元素直接宣告 line-height（常見於 Calibre 轉檔或出版社排版
    // 樣式），直接宣告一律贏過繼承值，不論本規則加不加 !important、
    // 不論設定的數值是多少，導致滑桿設定在這類書上完全無效。改用跟
    // fontWeight／fontFamily 相同的 selector（涵蓋 p/div/span 等實際
    // 文字容器元素），比照既有慣例直接覆蓋，不再依賴繼承。已用 headless
    // Chromium 重現並驗證：舊版對「書本宣告 p{line-height:1.2}」的最小
    // 重現案例完全無效（computed 值恆為 19.2px，不論覆蓋值為 0.9 或
    // 2.0）；改用 selector 後正確覆蓋（0.9 → computed 14.4px）。
    rules.push(`${selector} { line-height: ${effectiveLineHeight} !important; }`)
  }
  if (typeof prefs.paragraphSpacing === 'number') {
    rules.push(`p { margin-bottom: ${prefs.paragraphSpacing}em !important; }`)
  }
  if (prefs.textAlign) {
    rules.push(`p { text-align: ${prefs.textAlign} !important; }`)
  }
  // epic-22-reader-theme-integration Issue 1：文字色沿用上面同一組廣
  // selector（涵蓋 p/div/span 等實際文字容器元素），確保書本自己在
  // 這些元素直接宣告的文字顏色也會被蓋過（與 fontWeight/lineHeight
  // 既有覆蓋邏輯一致，比照 Issue 34 的既有教訓：只設定 html/body 這種
  // 可被繼承的值，遇到書本直接宣告會完全失效）。
  if (prefs.textColor) {
    rules.push(`${selector} { color: ${prefs.textColor} !important; }`)
  }
  // 背景色刻意只套用 html/body，不用上面的廣 selector——若逐一對
  // p/div/span 等元素套用 background-color，會在包裹圖片的容器上畫出
  // 不協調的色塊（真實可見的視覺瑕疵，取捨已於 spec.md 定案）。
  if (prefs.backgroundColor) {
    rules.push(`html, body { background-color: ${prefs.backgroundColor} !important; }`)
  }
  return rules.join('\n')
}

/**
 * 移植自 EpubReaderView.kt（Readium 路徑既有邏輯，:149-151），FXL 雙頁
 * 模式的觸發判斷——ALWAYS 恆真、AUTO 依 isLandscape、NEVER 恆假。
 * 沿用該處把結果摺疊成二值（而非細緻的三態 spread 值）的既有設計，
 * 見 plan-issue-3.md「已查證的關鍵技術事實」。
 */
function isDualPageEnabled(dualPageMode, isLandscape) {
  return dualPageMode === 'always' || (dualPageMode === 'auto' && isLandscape === true)
}

/**
 * 套用完整偏好設定（開書當下的 initialPreferences，或後續 setPreferences
 * 呼叫，兩者格式相同）：pageTurnMode 對應 Paginator 的 flow 屬性（獨立於
 * CSS 覆蓋之外的設定），其餘 9 項透過 setStyles() 疊加 CSS。暴露為
 * window 全域函式供 Dart 端 InAppWebViewController.evaluateJavascript
 * 呼叫（見 foliate_epub_reader_view.dart didUpdateWidget()，偏好變動時
 * 呼叫；開書當下的初次套用改由 _buildIndexUri() 透過 query string 傳入，
 * 不經過本函式）。
 */
window.applyPreferences = function (prefs) {
  // Issue 9：每次套用偏好都同步記錄下來，供 openBook() 內的
  // ResizeObserver debounce callback 在裝置旋轉/視窗尺寸變化後，能重新
  // 呼叫本函式並拿到「使用者最後一次實際設定的完整偏好」，而不是只拿到
  // 旋轉當下手邊剛好有的局部資料。
  lastAppliedPrefs = prefs

  // Epic 20 Issue 2：FXL（定樣式）書籍不套用流式（reflowable） Paginator
  // 專屬的排版參數。`foliate-fxl` 的 observedAttributes 只有
  // ['zoom', 'scale-factor', 'spread', 'flow', 'scroll-gap']，其中只有
  // flow 共通；setStyles() 對 foliate-fxl 完全不存在（呼叫會拋 TypeError）。
  // FXL 書籍本質上是圖片頁，無 reflow 概念，不需要字級/行距/邊距/CSS 覆蓋。
  if (view.isFixedLayout) {
    // FXL 分支：只保留 flow attribute（FXL 仍可能需要）與 lastAppliedPrefs 記錄，
    // 跳過所有 Paginator 專屬呼叫。
    if (prefs.pageTurnMode) {
      view.renderer.setAttribute(
        'flow',
        prefs.pageTurnMode === 'scroll' ? 'scrolled' : 'paginated',
      )
    }
    if (prefs.writingMode) {
      currentWritingMode = prefs.writingMode
    }
    // Epic 20 Issue 3：橫向雙頁模式。'both' 同時控制 foliate-fxl 的 section
    // 配對（#spread()，非 'none' 時依 page-spread-* metadata + book.dir
    // 自動配對——封面獨立顯示/RTL 頁序不受影響）與略過容器長寬比啟發式
    // （#render()，僅 'both'/'portrait' 會強制以橫向雙頁樣式渲染），對應
    // EpubReaderView.kt:784 既有的二值 Spread.ALWAYS/NEVER 摺疊設計，見
    // plan-issue-3.md「已查證的關鍵技術事實」。
    view.renderer?.setAttribute(
      'spread',
      isDualPageEnabled(prefs.dualPageMode, prefs.isLandscape) ? 'both' : 'none',
    )
    return
  }

  // 以下為流式（reflowable）書籍的既有邏輯，完全不變動。
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
  // /diagnose（2026-07-27，ViWoods Air Reader 直排字級過小）：paginator.js
  // 的分欄上限公式是 `maxColumnCount + (vertical ? 1 : 0)`（見
  // paginator.js #beforeRender()），直排永遠比橫排多 1 欄上限。多數裝置
  // 旋轉時寬高會互換，這個 +1 差異通常不明顯；但 ViWoods Air Reader 這類
  // 「旋轉後寬度幾乎不變、只有高度大幅縮水」的裝置上，直排會用（比橫排
  // 大上許多的）高度去逼近這個上限，導致直排硬是比橫排多切出一欄，畫面
  // 塞入更多文字、視覺上判讀為「字變小」（詳見
  // docs/epics/epic-18-reader-device-qa/reviews/ 的真機除錯面板量測記錄）。
  // 讓 --_max-column-count 依目前排版方向動態設定，使直排／橫排的「有效
  // 上限」（含 paginator.js 內建 +1）永遠一致為 2 欄，不再因排版方向而
  // 不對稱。
  view.renderer.setAttribute(
    'max-column-count',
    currentWritingMode === 'vertical' ? '1' : '2',
  )
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
  // epic-18 Issue 14：上/下邊距改用獨立的 marginTop/marginBottom 欄位
  // （取代 Issue 4 引入的 pageMargins 倍率公式），且不再限制僅直排生效
  // ——橫排模式現在也依這兩個欄位動態設定，取代原本「橫排永遠固定
  // paginator.js 內建 48px」的既有限制（見 design.md「第三輪真機使用
  // 回報」項目 4）。因為兩個方向現在共用同一套邏輯，不再需要「切換
  // 排版方向時重設回 48px」這層既有的持久性補償（原本 Issue 4 的
  // if/else 分支正是為了這個補償而存在）。
  // 未設定時的預設值（32px/16px）延續 Issue 4 當初為修正直排頂端裁切
  // 問題而定的數值；marginBottom 不再依 showFooter 動態調整——Issue 7
  // 已把頁尾改為浮動疊加層，不再壓縮 WebView 可視高度，「頁尾顯示時
  // 縮小下邊距」的補償理由已不成立，此為刻意簡化。
  const marginTopPx = typeof prefs.marginTop === 'number' ? prefs.marginTop : 32
  const marginBottomPx = typeof prefs.marginBottom === 'number' ? prefs.marginBottom : 16
  view.renderer.setAttribute('margin-top', `${marginTopPx}px`)
  view.renderer.setAttribute('margin-bottom', `${marginBottomPx}px`)
  // /diagnose（2026-07-28，左右邊界設為 0 仍留有一大塊空白）：左右邊距原本
  // 透過 buildOverrideCss() 疊加 `body { padding-left/right }` 覆蓋 CSS，
  // 但 Paginator（paginator.js）自己內建的 --_margin-left/--_margin-right
  // 預設值（48px，見該檔案 #top 樣式區塊）完全沒被觸碰，兩者是各自獨立的
  // 留白來源——使用者把滑桿調到 0 只清空了自己疊加的 body padding，
  // paginator.js 內建的 48px 邊界依然存在，看起來像「留白怎麼調都調不掉」。
  // 改為直接比照 margin-top/margin-bottom 的既有作法，把值送進 Paginator
  // 原生的 margin-left/margin-right attribute（該 custom element 的
  // observedAttributes 本就含這兩項，見 paginator.js attributeChangedCallback()），
  // 徹底取代 paginator.js 內建的 48px 預設，才能讓使用者設定的值（含 0）
  // 真正生效；使用者已確認浮動按鈕（FAB）疊在內容上沒關係，不需要另外
  // 保留按鈕安全邊界。未設定時的預設值（24px）比照 ReaderSettingsSheet
  // 滑桿的既有預設常數（_defaultMarginLeft/_defaultMarginRight）。
  const marginLeftPx = typeof prefs.marginLeft === 'number' ? prefs.marginLeft : 24
  const marginRightPx = typeof prefs.marginRight === 'number' ? prefs.marginRight : 24
  view.renderer.setAttribute('margin-left', `${marginLeftPx}px`)
  view.renderer.setAttribute('margin-right', `${marginRightPx}px`)
  view.renderer.setStyles([fontFaceCss, buildOverrideCss(prefs)])
}

// epic-18-reader-device-qa Issue 39：main.js 這個 ES module 執行到這裡時
// 才「真正」定義出 window.applyPreferences，覆蓋掉 AT_DOCUMENT_START 階段
// 注入的佔位 shim（見 foliate_epub_reader_view.dart 的
// _applyPreferencesQueueShimJs）。若 Dart 端在這之前已經呼叫過一次（被
// shim 接住、存進 window.__pendingApplyPreferences），這裡立刻補套用一次，
// 避免那次呼叫被靜默遺漏。
if (window.__pendingApplyPreferences) {
  const pendingPrefs = window.__pendingApplyPreferences
  window.__pendingApplyPreferences = null
  window.applyPreferences(pendingPrefs)
}

/**
 * 換頁／跳轉全書進度比例，供 Dart 端 foliate_epub_reader_view.dart 的
 * FoliateEpubReaderView.nextPage／previousPage／jumpToProgression static
 * helper（透過 InAppWebViewController.evaluateJavascript）呼叫
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
 * 跳轉到指定 CFI（epic-17 Issue 6）。[cfi] 已由 Dart 端
 * foliate_bridge_codec.dart extractCfi() 驗證過格式（新格式定位 JSON 才會
 * 呼叫到這裡，舊格式/無效 JSON 在 Dart 端
 * FoliateEpubReaderView.jumpToLocator() static helper 就已被過濾掉，見
 * foliate_epub_reader_view.dart），本函式不需要再自行解析 JSON 或判斷
 * 格式。
 */
window.jumpToLocator = function (cfi) {
  view.goTo(cfi)
}

/**
 * 把目前應顯示的完整標記清單一次性套用（epic-17 Issue 8，比照既有
 * window.applyPreferences「整組送出」慣例，非增量 diff）：先移除全部
 * 既有標記，再逐筆呼叫 view.addAnnotation() 重新加入。[decorations] 為
 * foliate_bridge_codec.dart buildDecorationEntries() 產生的
 * [{id, cfi, color, isUnderline}, ...] 陣列，由 Dart 端
 * FoliateEpubReaderView.setDecorations() static helper（透過
 * InAppWebViewController.evaluateJavascript）呼叫。
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
 * CFI）這個假設；`foliate_bridge_codec.dart buildDecorationEntries()`
 * （Dart 端）本身不對重複 CFI 做任何處理，原樣保留全部項目，去重/
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
 * 讀取全書目錄（epic-17 Issue 6），供 Dart 端
 * FoliateEpubReaderView.loadTableOfContents() static helper（透過
 * InAppWebViewController.evaluateJavascript）呼叫。非同步計算完成後主動
 * 透過 window.flutter_inappwebview.callHandler('onTableOfContentsReady', ...)
 * 回呼 Dart 端——WebView.evaluateJavascript 的回傳值不會等待 async
 * function 內部的 Promise resolve（只會拿到 Promise 物件本身序列化後的
 * 無意義結果），見 foliate_epub_reader_view.dart
 * _requestTableOfContents()／addJavaScriptHandler('onTableOfContentsReady')
 * 註解與 Global Constraints，本函式因此不能單純依賴 evaluateJavascript
 * 的回傳值。
 */
window.getTableOfContents = async function () {
  try {
    const items = view.book?.toc ?? []
    const entries = []
    for (const item of items) {
      entries.push(await buildTocEntry(item))
    }
    window.flutter_inappwebview.callHandler('onTableOfContentsReady', JSON.stringify(entries))
  } catch (e) {
    window.flutter_inappwebview.callHandler('onTableOfContentsReady', JSON.stringify([]))
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
        // foliate_bridge_codec.dart argbToCssColor() 已經算好的 tint
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
      window.flutter_inappwebview.callHandler('onPageRendered', resolvedWritingMode)
    }, { once: true })
    // 目前定位變動持續推播（epic-17 Issue 6）：與上方 { once: true } 的
    // FR-06/onPageRendered 監聽器各自獨立、互不影響，開書當下的第一次
    // relocate 事件兩者皆會觸發。location.current／location.total 為
    // foliate-js SectionProgress.getProgress() 既有輸出（見
    // progress.js），近似頁碼概念，非精確渲染頁數。
    // Epic 20 Issue 2：FXL 書籍的 relocate 事件 e.detail 欄位形狀可能與
    // 流式書籍不同——fixed-layout.js 有 page/pages/index 等 getter，但
    // location.current/location.total 可能不存在。依 view.isFixedLayout 分流
    // 組裝 onLocatorChanged payload，確保 FXL 書籍的 pageIndex/totalPages
    // 仍有意義。
    view.addEventListener('relocate', (e) => {
      const { cfi, section, fraction, location } = e.detail
      let pageIndex = section?.current ?? 0
      let totalPages = location?.total ?? 0
      // FXL 書籍：若 location.current/total 不存在，改用 renderer 的 page/pages
      if (view.isFixedLayout && !totalPages && view.renderer) {
        pageIndex = view.renderer.page ?? pageIndex
        totalPages = view.renderer.pages ?? totalPages
      }
      window.flutter_inappwebview.callHandler(
        'onLocatorChanged',
        JSON.stringify({ cfi, index: pageIndex, fraction: fraction ?? 0 }),
        fraction ?? 0,
        location?.current ?? pageIndex,
        totalPages,
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
      if (id) window.flutter_inappwebview.callHandler('onAnnotationActivated', id)
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

      // 選取範圍即時回報（epic-17 Issue 8）：抽成共用函式，供既有
      // selectionchange 與下方 ADR 0013 既定的 Android 專用
      // contextmenu/pointercancel 分支共同呼叫，避免重複實作同一段
      // CFI/座標換算邏輯。'load' 事件對 look-ahead 預讀章節同樣會觸發，
      // 故 doc/index 皆從本次 'load' 呼叫的區域變數閉包讀取（見
      // spike-overlayer-annotations.md「已記錄的既有 API 落差」）。
      const reportSelection = async () => {
        const selection = doc.getSelection()
        if (!selection || selection.rangeCount === 0 || selection.isCollapsed) {
          window.flutter_inappwebview.callHandler('onSelectionCleared')
          return
        }
        const range = selection.getRangeAt(0)
        const rect = range.getClientRects()[0]
        if (!rect) return
        const cfi = view.getCFI(index, range)
        const progress = await view.getCFIProgress(cfi)
        const iframeRect = doc.defaultView.frameElement.getBoundingClientRect()
        const viewportRect = view.getBoundingClientRect()
        window.flutter_inappwebview.callHandler(
          'onSelectionChanged',
          JSON.stringify({ cfi, index, fraction: progress?.fraction ?? 0 }),
          progress?.fraction ?? 0,
          (iframeRect.left + rect.left - viewportRect.left) / viewportRect.width,
          (iframeRect.top + rect.top - viewportRect.top) / viewportRect.height,
          (iframeRect.left + rect.right - viewportRect.left) / viewportRect.width,
          (iframeRect.top + rect.bottom - viewportRect.top) / viewportRect.height,
        )
      }

      doc.addEventListener('selectionchange', reportSelection)

      // ADR 0013 既定決策（非本計畫視情況新增）：比照 anx-reader 已驗證的
      // 手法（見 tmp/epic-18/reviews/anx_reader_foliate_js_highlighting_
      // analysis.md 5 節）——contextmenu 在長按觸發原生選字/顯示控點時
      // 觸發，需 preventDefault() 避免原生選單彈出與既有 AnnotationToolbar
      // 衝突；pointercancel 在拖曳控點期間，原本的 pointer 手勢因系統選取
      // 手勢接管而觸發，兩者皆代表「選取狀態可能剛建立或變動」，作為
      // selectionchange 的主動觸發備援（不同 Android WebView 版本/廠牌
      // 客製化/E-Ink 裝置對 selectionchange 事件觸發時機的行為差異，比
      // 依賴單一被動事件更穩健）。
      doc.addEventListener('contextmenu', (evt) => {
        evt.preventDefault()
        reportSelection()
      })
      doc.addEventListener('pointercancel', () => reportSelection())
    })
    // Epic 20 Issue 2（ADR 0017 決策 4）：isFixedLayoutHint 覆蓋機制。
    // 當 Dart 端傳入 isFixedLayoutHint === true 時，強制將書本的
    // rendition.layout 覆寫為 'pre-paginated'，讓 view.js 的 isFixedLayout
    // 偵測邏輯（book.rendition?.layout === 'pre-paginated'）觸發 FXL 路徑。
    // 用於 epub.js 自己判斷不出 FXL 但人工強制的邊界案例。
    // 覆寫必須在 view.open(book) 之前，因為 view.js 在 open() 內部讀取
    // book.rendition 並據此決定是否動態 import('./fixed-layout.js')。
    if (initialPrefs.isFixedLayoutHint === true && book.rendition?.layout !== 'pre-paginated') {
      book.rendition = { ...book.rendition, layout: 'pre-paginated' }
    }
    await view.open(book)
    view.renderer.setAttribute(
      'flow',
      initialPrefs.pageTurnMode === 'scroll' ? 'scrolled' : 'paginated',
    )
    // Issue 9：裝置旋轉/視窗尺寸變化時重新呼叫 applyPreferences()。
    // 根因（見 ADR 0012「已知限制」段）：「雙欄」欄數模式的
    // max-inline-size（targetSize = Math.ceil(hostSize / 2)，見上方
    // window.applyPreferences() 的 columnMode === 'double' 分支）是呼叫
    // applyPreferences() 當下 getBoundingClientRect() 的一次性快照，寫死後
    // 不會再變動。paginator.js 自己的 ResizeObserver（paginator.js:1367，
    // 觀察內部私有 #container）在裝置旋轉/視窗尺寸變化後只會重新計算
    // divisor（用「當下真實 hostSize」對比「呼叫當下算出、此後不變的
    // max-inline-size」），不會觸發 applyPreferences() 重新執行、也不會
    // 重新計算 targetSize。
    // 這裡新增一個本專案自建、完全獨立的 ResizeObserver（觀察
    // view.renderer 這個 <foliate-paginator> 自訂元素本身的 box 尺寸——與
    // window.applyPreferences() 的 columnMode === 'double' 分支算 hostSize
    // 時用的是同一個元素的 getBoundingClientRect()，語意一致），debounce
    // 200ms（起始建議值，避免旋轉動畫過程中連續觸發多次不必要的重排）後
    // 呼叫 window.applyPreferences(lastAppliedPrefs)，讓「雙欄」模式的
    // targetSize 依當下真實尺寸重新計算。不特例只挑 columnMode ===
    // 'double' 才重算——整包 lastAppliedPrefs 重新套用一次，其餘欄位
    // （字級/邊距/CSS 覆蓋/max-column-count）重算是 idempotent、無副作用
    // （見 Global Constraints）。
    // 保留參照（比照 paginator.js 自己的 #observer 於 destroy() 呼叫
    // unobserve() 的既有謹慎作法，見 paginator.js:3493）：openBook() 全
    // repo 只在檔案最底部被呼叫一次，本 WebView 頁面沒有「換書但不重建
    // InAppWebView」的既有機制，整個 JS context 會隨頁面關閉一併回收，
    // 故目前沒有對應的 disconnect() 呼叫時機，不無中生有加一個沒有呼叫端
    // 的 disconnect() 呼叫。
    let resizeDebounceTimer = null
    const hostResizeObserver = new ResizeObserver(() => {
      if (resizeDebounceTimer) clearTimeout(resizeDebounceTimer)
      resizeDebounceTimer = setTimeout(() => {
        window.applyPreferences(lastAppliedPrefs)
      }, 200)
    })
    hostResizeObserver.observe(view.renderer)
    await view.init(initialCfi ? { lastLocation: initialCfi } : {})
  } catch (e) {
    window.flutter_inappwebview.callHandler('onError', String((e && e.message) || e))
  }
}

openBook()
