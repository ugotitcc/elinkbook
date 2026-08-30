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
  if (typeof prefs.letterSpacing === 'number') {
    // epic-28-reader-settings-enhancements Issue 1：letter-spacing 作用於
    // inline 軸方向，vertical-rl 下 inline 軸即為垂直方向，語意依然合法，
    // 橫排/直排皆套用同一份規則，不需要依 writingMode 分支處理。沿用
    // fontWeight/lineHeight 既有的廣 selector，避免書本自己直接宣告
    // letter-spacing 時覆蓋無效（比照 Issue 34 既有教訓）。
    rules.push(`${selector} { letter-spacing: ${prefs.letterSpacing}em !important; }`)
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

  // epic-26-architecture-hardening Issue 11：字級/行距/段落間距/邊距/
  // 單雙欄/螢幕方向/直橫排切換全部流經這個唯一入口，任一項改變都會讓
  // SectionProgress 已記錄的密度校正資料失真，整包清空重算（FXL 書籍
  // 沒有這筆資料，clearLocationDensity() 內部為 no-op，此處無條件呼叫
  // 不需要額外判斷 isFixedLayout，見 plans/plan-issue-11.md 規劃階段
  // 查證第 3 點）。
  view.clearLocationDensity()

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
  // /diagnose（Epic 18 Issue 45）：切換方向後修法需要知道「這次呼叫是否
  // 真的改變了 writingMode」，故在覆蓋前先留一份舊值（見本函式最後的
  // view.goTo() 修法段落）。
  const previousWritingMode = currentWritingMode
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

  // /diagnose（Epic 18 Issue 45，2026-08-11）：切換書寫方向後翻頁一次跳
  // 好幾頁、退出重進才恢復正常。根因：Paginator 內部決定分欄/捲動軸
  // 方向的私有欄位 this.#vertical，只有在 section「第一次載入」時才會
  // 從 getDirection(doc) 正確推導；書本已經開啟、只是切換方向的情境下，
  // 上面 setAttribute 觸發的 render() 只會自我參照 this.#vertical 目前
  // 的值，setStyles()（上一行，真正讓 CSS 翻轉的呼叫）本身也完全不會
  // 觸發任何重新推導——已用 headless Chromium 量測證實：切換完成當下，
  // 位置在沒有任何明確翻頁動作的情況下就已經跳動數頁份量（見
  // docs/epics/epic-18-reader-device-qa/reviews/bugfix-repro-issue-45.md
  // 「審查修正（Round 2）」之後的 Phase 3/4 稽核紀錄）。
  //
  // 修法：writingMode 真的改變時，呼叫 view.goTo() 導覽回目前位置。
  // Paginator.goTo() 內建的 directionChanged 偵測（paginator.js 私有
  // 方法 #goTo()，讀取 getDirection(view.document) 這個當下真實 CSS
  // 狀態，不像 render() 是自我參照）會正確判定方向已變，強制銷毀重建
  // 該 section 的 view、重新走一次 View.load() 的 getDirection() 推導
  // 路徑，修正 this.#vertical——這是 paginator.js 既有的公開行為，不是
  // 新增或修改 vendored 檔案（ADR 0011）。
  //
  // 刻意只在 writingMode 真的變動時才觸發（不是「有帶 writingMode 欄位
  // 就觸發」）：Issue 9 裝置旋轉時會重新呼叫 applyPreferences(lastAppliedPrefs)，
  // 其中通常包含未變動的 writingMode，若不排除會讓每次旋轉都多一次不必要
  // 的 view.goTo()（#goTo() 判定 directionChanged=false 時仍會有短暫的
  // opacity 0→1 淡出淡入，見 paginator.js #goTo() 該分支）。用完整 CFI
  // （而非 section index）導覽是必要的——若只給 index，#goTo() 的
  // resolvedAnchor 會退回該 section 開頭而非保留原本閱讀位置。
  if (prefs.writingMode && prefs.writingMode !== previousWritingMode) {
    const cfi = view.lastLocation?.cfi
    if (cfi) view.goTo(cfi)
  }
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
 * 主動清除目前的原生文字選取狀態（epic-25 Issue 3）：使用者點擊
 * AnnotationToolbar 的關閉按鈕後，Dart 端會清空 _currentSelection 讓工具列
 * 消失，但 WebView 原生選取（藍色反白＋拖曳控點）是瀏覽器自己的視覺層，
 * 不受 Dart state 影響，若不主動清除，畫面會殘留「工具列已消失、但文字
 * 仍反白」的不一致體驗。逐一走訪目前所有已載入內容（雙頁模式下可能同時
 * 有兩個 iframe），清空各自的選取——呼叫 removeAllRanges() 會自然觸發
 * selectionchange，讓既有 reportSelection()（見上方 view.addEventListener
 * ('load', ...) hook）回報 onSelectionCleared 給 Dart 端，不需要額外手動
 * 呼叫 callback，也不會與 Dart 端已經呼叫過的 _handleSelectionCleared()
 * 衝突（該方法本身是 idempotent，重複呼叫只是把已經是 null 的欄位再設一次
 * null）。
 */
window.clearSelection = function () {
  for (const { doc } of view.renderer.getContents()) {
    doc.getSelection()?.removeAllRanges()
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
      `https://appassets.androidplatform.net/book/${params.get('bookFileName') || 'current.epub'}`,
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
    // relocate 事件兩者皆會觸發。
    // epic-26-architecture-hardening Issue 10：payload 改為兩參數——
    // 第 1 個參數（locatorJson）內容維持不動，會被 Dart 端持久化並跨裝置
    // 同步，不可混入下方估計/真實頁碼；第 2 個參數是具名 JSON 物件，依
    // view.isFixedLayout 分流只填其中一組頁碼欄位，另一組明確傳 null
    // （取代原本 pageIndex/totalPages 兩個欄位在不同格式下語意不一致的
    // 舊寫法）。
    view.addEventListener('relocate', (e) => {
      const { cfi, section, fraction, location } = e.detail
      // locatorJson 內嵌的 index 是章節/spine index，非頁碼——沿用既有
      // 寫法不動（extractCfi() 從未讀取這個鍵，見規劃階段查證）。
      const chapterIndex = section?.current ?? 0
      // 重構前的判斷式多了 `!totalPages`（即 `location?.total ?? 0` 恰好為
      // 0 才覆寫成 view.renderer.page/.pages）：`location.total` 是
      // `Math.ceil(sizeTotal / 1500)`（progress.js），sizeTotal 只要 > 0
      // 該值恆 >= 1，代表這個舊條件對任何有實際內容的真實書籍幾乎從未
      // 成立過——FXL／CBZ 書籍先前實際顯示的其實長期是這個位元組估計值
      // （對圖片較大的 CBZ 而言可能是遠大於真實頁數的離譜數字），而非
      // 真實視覺頁碼。這裡刻意移除該條件閘，讓 FXL／CBZ 一律採用真實
      // 視覺頁數——這是本 Issue 順帶修正的一個既有頁碼顯示錯誤，不是嚴格
      // 的零行為改變（見 review-issue-10.md Important #2、issues.md
      // Issue 10 驗收標準）。
      const position = view.isFixedLayout && view.renderer
        // FXL/CBZ：view.renderer.page/.pages（fixed-layout.js）是全書
        // 真實視覺頁數，非估計值。
        ? {
            fraction: fraction ?? 0,
            locationIndex: null,
            locationTotal: null,
            visualPageIndex: view.renderer.page ?? 0,
            visualTotalPages: view.renderer.pages ?? 0,
          }
        // 流式格式：location.current/.total 是 SectionProgress 的位元組
        // 估計刻度（每 1500 bytes 一個刻度），非精確視覺頁數。
        : {
            fraction: fraction ?? 0,
            locationIndex: location?.current ?? chapterIndex,
            locationTotal: location?.total ?? 0,
            visualPageIndex: null,
            visualTotalPages: null,
          }
      window.flutter_inappwebview.callHandler(
        'onLocatorChanged',
        JSON.stringify({ cfi, index: chapterIndex, fraction: fraction ?? 0 }),
        JSON.stringify(position),
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

      // Epic 18 Issue 47 修復：長按候選期間（touchstart 到瀏覽器原生
      // 選取真正建立之間）攔截 touchmove，避免 paginator.js 的
      // #onTouchMove 選取守衛（paginator.js:2191-2195，只在
      // selection.rangeCount > 0 && !selection.isCollapsed 才擋下）在
      // 這段空窗期誤判為滑動換頁而位移內容（已用 CDP 觸控注入＋真機
      // 驗證確認橫排/直排皆會重現，見
      // docs/epics/epic-18-reader-device-qa/reviews/bugfix-repro-issue-47.md）。
      //
      // 用 capture 階段監聽器搶在 paginator.js 自己註冊在同一個 doc 上
      // 的 bubble 階段監聽器（paginator.js:1452-1455）之前執行，呼叫
      // stopImmediatePropagation() 讓事件完全不會傳到 paginator 的處理
      // 常式（含其 e.preventDefault() 呼叫與後續所有分支）——不修改
      // paginator.js 任何一行（ADR 0011）。只攔截「看起來像長按候選」
      // 的 touchmove（時間短、位移小、平均速度低、選取尚未確立），真正
      // 的滑動換頁手勢與選取已確立後的 touchmove 都會立即放行。
      //
      // 【審查修正 Critical #1，見 tmp/epic-18/review-plan-issue-47-fix.md】
      // 逃逸條件必須同時看「距離」與「平均速度」，不能只看距離：
      // paginator.js 的 #touchState.x/y（2203-2204 行）只在 #onTouchMove
      // 真正執行到那裡才會更新——若前幾個 touchmove 一路被本攔截器擋下，
      // state.x/y 會停留在 touchstart 當下的初始值；等累積位移終於超過
      // 純距離門檻、放行第一個 touchmove 給 paginator.js 時，它算出的
      // dx = state.x - x 會是「手勢一開始到現在」的全部累積位移，而不是
      // 這一影格的增量，造成 scrollBy() 一次性暴跳（審查報告已用具體
      // 影格算例驗證：15px→40px→65px，第 3 影格單次跳 65px）。改用
      // 「距離死區（調降到 15px）＋平均速度」雙門檻：真正的滑動手勢
      // 通常在第一影格就有夠高的平均速度，會在距離門檻生效、state.x/y
      // 累積誤差之前就先被速度條件放行，state.x/y 這時仍是準確值，不會
      // 暴跳；長按選字的手指自然微幅晃動速度遠低於門檻，會正確停留在
      // 攔截狀態。
      const LONG_PRESS_GATE_MS = 500 // 對齊 Android ViewConfiguration.getLongPressTimeout() 預設值
      const SWIPE_DISTANCE_DEADZONE_PX = 15 // 累積位移死區：超過就放行，把最大暴跳量壓到跟正常單影格位移同量級
      const SWIPE_VELOCITY_ESCAPE_PX_PER_MS = 0.3 // 平均速度（累積位移/累積時間）門檻：真正滑動手勢通常第一影格就超過
      let longPressGateState = null
      doc.addEventListener('touchstart', (evt) => {
        const touch = evt.touches[0]
        if (!touch || evt.touches.length > 1) {
          longPressGateState = null
          return
        }
        longPressGateState = { x: touch.screenX, y: touch.screenY, t: evt.timeStamp }
      }, { capture: true })
      doc.addEventListener('touchmove', (evt) => {
        if (!longPressGateState) return
        if (evt.touches.length > 1) {
          longPressGateState = null
          return
        }
        const selection = doc.getSelection()
        if (selection && selection.rangeCount > 0 && !selection.isCollapsed) {
          // 選取已經確立，paginator.js 既有守衛從這裡開始會正確接手。
          longPressGateState = null
          return
        }
        const touch = evt.touches[0]
        if (!touch) return
        const elapsed = evt.timeStamp - longPressGateState.t
        const dx = touch.screenX - longPressGateState.x
        const dy = touch.screenY - longPressGateState.y
        const distance = Math.hypot(dx, dy)
        const avgVelocity = elapsed > 0 ? distance / elapsed : Infinity
        if (elapsed >= LONG_PRESS_GATE_MS
          || distance > SWIPE_DISTANCE_DEADZONE_PX
          || avgVelocity > SWIPE_VELOCITY_ESCAPE_PX_PER_MS) {
          // 超過長按辨識時間、或位移/平均速度已經大到明顯是滑動手勢——
          // 放行給 paginator.js 正常處理，不再攔截這個手勢剩餘的
          // touchmove。
          longPressGateState = null
          return
        }
        // 仍在長按候選期間（時間短、位移小、速度低、尚未確立選取）：攔截。
        //
        // 【Epic 25 Issue 1，見
        // docs/epics/epic-25-annotation-interaction-qa/issues.md】
        // stopImmediatePropagation() 會讓 paginator.js 的 #onTouchMove 整個
        // 不執行，連帶它在 paginator.js:2198 無條件呼叫的
        // e.preventDefault() 也不會被呼叫，所以本攔截器自己必須先呼叫
        // preventDefault()，讓瀏覽器一開始就看到有人取消了這個
        // touchmove——否則 Chromium 會判定「沒人要攔」而自行接管為原生
        // 捲動，一旦接管，該手勢剩餘所有 touchmove 都會被標記為不可取消，
        // 之後不論攔截器還是 paginator.js 再呼叫 preventDefault() 都會被
        // 忽略，畫面位移改由瀏覽器合成器直接控制，完全繞過 paginator.js
        // 自己的 #touchState/containerPosition 追蹤（真機重現症狀：選取
        // 是否已確立無關，任何落入候選窗口且沒被成功取消的手勢皆會誘發）。
        //
        // 本監聽器必須明確加上 { passive: false }（見下方註冊）：Chromium
        // 對直接掛在 Document 物件（doc 正是 iframe 的 contentDocument）
        // 上、沒有明確指定 passive 的 touchstart/touchmove 監聽器，預設
        // 會當成 passive 處理，passive 監聽器內呼叫 preventDefault() 會被
        // 靜默忽略（只印警告，不拋例外）——若漏了這個選項，上面的
        // preventDefault() 呼叫形同虛設。
        evt.preventDefault()
        evt.stopImmediatePropagation()
      }, { capture: true, passive: false })
      doc.addEventListener('touchend', () => { longPressGateState = null }, { capture: true })
      doc.addEventListener('touchcancel', () => { longPressGateState = null }, { capture: true })

      // Epic 25 Issue 4 修法：nav-zone 熱區點擊與畫線點擊共用同一組觸控
      // 手勢、同一螢幕座標，兩者天生無法用純技術訊號區分意圖（真機資料已
      // 證實：click 事件命中畫線的時序有時早於、有時晚於
      // window.nextPage() 實際執行，純時序競速修法無法涵蓋兩種情況，見
      // docs/epics/epic-25-annotation-interaction-qa/issues.md Issue 4）。
      // 採用人類確認的產品方向：按壓時長作為判斷依據——快速點擊視為換頁
      // 意圖，攔截合成 click 事件、不讓它傳到 view.js #createOverlayer
      // 註冊的畫線點擊 hitTest 監聽器（view.js:440，bubble 階段）；按壓
      // 夠久則視為使用者確實想操作畫線，不攔截，讓 click 正常傳遞。門檻
      // 值 700ms 比照既有 _NavZoneTapDetector._tapMaxDurationMs
      // （foliate_epub_reader_view.dart，Epic 25 Issue 1 真機多輪校準得出
      // 的同一個值），維持 Dart／JS 兩側一致的「多短算快速點擊」心智模型
      // （兩者各自獨立判斷，不透過橋接同步，純粹數值上取一致，避免額外
      // 跨執行緒往返）。
      //
      // 【明確排除超連結點擊，真實回歸非假設性風險】#handleLinks
      // （view.js:353-380）的超連結點擊監聽器與 #createOverlayer 的畫線
      // 點擊監聽器是同一個 doc 節點上兩個獨立的 bubble 階段 click 監聽器，
      // stopImmediatePropagation() 會讓「呼叫當下尚未執行」的其餘監聽器
      // 整個收不到事件（不分是否與畫線相關）——若不排除超連結，快速點擊
      // 書本內文超連結會連帶失效，已用原始碼交叉核對排除此風險。排除條件
      // 選用與 #handleLinks 完全相同的 a[href] 選擇器（非更寬的
      // role="link"/button/input 等）：已用 grep 逐一核對整個 vendored＋
      // 整合層（paginator.js/view.js/epub.js/main.js）只有 main.js:679（本
      // 監聽器）、view.js:356（#handleLinks）、view.js:440
      // （#createOverlayer）三個 doc 層級 click 監聽器，沒有任何監聽器處理
      // role="button"/button/input/select/textarea——擴大排除範圍不會保護
      // 任何現存功能，只會讓這些元素若與畫線重疊時重新出現本次要修的誤觸
      // 發，故刻意不擴充（獨立審查報告 `tmp/epic-25/
      // plan-issue-4-fix-review-report.md` 建議擴充，已查證後維持現狀，
      // 詳見 Global Constraints）。
      const ANNOTATION_CLICK_TAP_MAX_MS = 700
      let annotationClickTouchStartTime = null
      doc.addEventListener('touchstart', (evt) => {
        annotationClickTouchStartTime = evt.touches.length === 1 ? evt.timeStamp : null
      }, { capture: true })
      doc.addEventListener('touchcancel', () => {
        annotationClickTouchStartTime = null
      }, { capture: true })
      doc.addEventListener('click', (evt) => {
        const startTime = annotationClickTouchStartTime
        annotationClickTouchStartTime = null
        if (startTime === null) return // 非觸控手勢產生的 click（例如滑鼠），不受影響
        if (evt.target.closest('a[href]')) return // 超連結點擊一律放行
        if (evt.timeStamp - startTime <= ANNOTATION_CLICK_TAP_MAX_MS) {
          evt.stopImmediatePropagation()
        }
      }, { capture: true })
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
    // epic-11-multi-format-reader Issue 3（CBZ 支援）：翻頁方向覆寫，須在
    // view.open(book) 之前設定 book.dir——fixed-layout.js 的 open() 只在
    // 當下一次性讀取 book.dir 決定 this.rtl（見 next()/prev() 固定讀取
    // this.rtl 決定要呼叫 #goLeft() 還是 #goRight()，不會之後重新推導），
    // 比照上方 isFixedLayoutHint 覆寫「必須在 open() 之前」的既有限制。
    // 僅在 isComicBookHint === true 時套用，避免誤觸 EPUB 固定版面既有的
    // page-progression-direction 自動偵測——comic-book.js 回傳的 book
    // 物件不含 dir 欄位（見 issues.md Issue 1 Spike 查證），EPUB FXL 則由
    // epub.js 自行依 OPF metadata 設定，不應被本專案覆寫（spec.md
    // 「CBZ 支援」）。
    if (initialPrefs.isComicBookHint === true) {
      book.dir = initialPrefs.dualPageDirection === 'rtl' ? 'rtl' : 'ltr'
      // 虛擬頁碼目錄（spec.md「CBZ 支援」）：comic-book.js 的 book.toc
      // 預設以檔名當作 label（例如重建後的 page_0001.jpg），對使用者無
      // 意義；book.resolveHref／book.sections 皆以 section.id（＝檔名）
      // 為鍵，href 沿用 section.id 可讓既有 window.getTableOfContents()
      // 的 buildTocEntry() 邏輯原樣重用（不需修改），只替換 label 顯示
      // 文字。buildTocEntry() 內 view.book.sections[index].createDocument()
      // 對漫畫頁面（無 createDocument 方法）會拋出例外，已有既有
      // try/catch 優雅退回 section 層級 base CFI（view.getCFI(index,
      // undefined)）——對漫畫「一頁即一個完整章節」的語意而言，這正是
      // 正確的行為，不需額外處理。
      book.toc = book.sections.map((section, i) => ({
        label: `第 ${i + 1} 頁`,
        href: section.id,
      }))
    }
    await view.open(book)
    // epic-27-reader-device-compat Issue 9：停用 paginator.js（FXL 為
    // foliate-fxl，兩者皆讀取同一個 view.renderer 參照）內建的滑動翻頁與
    // 放開時的 snap() 翻頁判定（paginator.js:2186/2499/2558 皆讀取此
    // 屬性）。已查證全專案目前從未設定過這個屬性，也沒有任何功能依賴滑動
    // 翻頁——本產品的導覽模型只有 3×3 熱區與音量鍵（見 CLAUDE.md／
    // prd.md）。不設定此屬性時，長按選字/拖曳劃線手勢會與 paginator.js
    // 內建的滑動翻頁搶同一組觸控事件，選取確立前的最初幾個 touchmove
    // 影格若被 main.js 自己的 longPressGate 攔截器放行，會被 paginator.js
    // 記錄成滑動位移，放開手指時可能誤判翻頁（見
    // docs/epics/epic-27-reader-device-compat/reviews/bugfix-repro.md
    // Issue 9 根因 B）。`setAttribute` 對任何自訂元素皆安全（不像呼叫該
    // 元素不存在的方法會拋例外），故不需要依 view.isFixedLayout 另外判斷。
    view.renderer.setAttribute('no-swipe', '')
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
