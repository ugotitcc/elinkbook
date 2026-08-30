// epic-34-tts-readalong Issue 8／Issue 11 的安全視窗（Safe Viewport）翻頁
// 判斷邏輯，epic-26-architecture-hardening Issue 12 抽成獨立、零 DOM 依賴
// 的純函式（比照同目錄 progress.js 的既有模式）——main.js 第 5 行頂層執行
// document.getElementById()，若把這個函式留在 main.js 裡 export，Node
// 匯入整份 main.js 會直接因 document 未定義而掛掉，故獨立成此檔案，讓
// app/tool/test_tts_safe_window.mjs 可以直接匯入單元測試，不需要真機或
// WebView 環境。

// 「可視範圍 20%～80%」（issues.md 用語）——朗讀高亮的正規化位置只要
// 落在這個區間內就不觸發翻頁，避免逐句捲動造成頻繁刷新（E-Ink 殘影）／
// 頻繁跳動（一般裝置）。不對外匯出：常數搬離 main.js 後只有這個檔案的
// 內部邏輯使用得到它，行為已由下方函式的邊界值單元測試間接涵蓋。
const TTS_SAFE_WINDOW_MIN = 0.2
const TTS_SAFE_WINDOW_MAX = 0.8

/**
 * 依朗讀段落 Range 的頭尾矩形，判斷目前顯示畫面是否需要跟隨翻頁。
 *
 * @param {{left: number, right: number, top: number, bottom: number} | null | undefined} firstRect
 *   Range.getClientRects() 回傳陣列的第一個矩形（這句話開頭那一行）。
 * @param {{left: number, right: number, top: number, bottom: number} | null | undefined} lastRect
 *   Range.getClientRects() 回傳陣列的最後一個矩形（這句話結尾那一行）。
 * @param {{left: number, top: number} | null | undefined} iframeRect
 *   內容 iframe 的 getBoundingClientRect()。
 * @param {{left: number, top: number, width: number, height: number} | null | undefined} viewportRect
 *   外層 view 的 getBoundingClientRect()；`width`／`height` 為 0（或缺席）
 *   時視為無法判斷，回傳 null（除零防呆，正常渲染下不會發生）。
 * @param {boolean} isVertical 目前是否為直排(vertical-RL)排版。
 * @returns {'next' | 'prev' | null} 需要翻頁的方向；不需要翻頁則回傳 null。
 */
export function resolveTtsSafeWindowDirection(
  firstRect,
  lastRect,
  iframeRect,
  viewportRect,
  isVertical,
) {
  // 對應 main.js 原本 `if (firstRect && lastRect && frameEl)` 防呆——
  // 任一必要輸入缺席（例如朗讀高亮尚未附著在任何可視 iframe 上）時，
  // 視為無法判斷，不觸發翻頁。另外防護 viewportRect 寬高為 0 的除零情況
  // （正常渲染下不會發生，純屬邊界防呆，不影響任何真實場景行為）。
  if (
    !firstRect ||
    !lastRect ||
    !iframeRect ||
    !viewportRect ||
    !viewportRect.width ||
    !viewportRect.height
  ) {
    return null
  }

  const normOf = (rect) => ({
    x: (iframeRect.left + (rect.left + rect.right) / 2 - viewportRect.left) /
      viewportRect.width,
    y: (iframeRect.top + (rect.top + rect.bottom) / 2 - viewportRect.top) /
      viewportRect.height,
  })
  const first = normOf(firstRect)
  const last = normOf(lastRect)

  // needNext 看 Range 結尾那一行的位置——這句話開始播放的當下就先確認
  // 「唸到最後一個字時，畫面來不來得及顯示」，提前翻頁（見
  // epic-34-tts-readalong Issue 11 真機驗收記錄）。分頁模式下「頁首」是
  // 正常可見內容，needPrev 因此只能用真正超出頁面範圍的硬邊界
  // （0.0/1.0）判斷、依 Range 開頭矩形——否則剛翻到新頁的第一句會立刻
  // 被翻回上一頁，跟前一頁之間無限來回翻頁震盪（見
  // epic-34-tts-readalong Issue 8 review-plan-issue-8.md Critical #1）。
  const needNext = isVertical
    ? last.x < TTS_SAFE_WINDOW_MIN || last.y > 1.0
    : last.y > TTS_SAFE_WINDOW_MAX || last.x > 1.0
  const needPrev = isVertical
    ? first.x > 1.0 || first.y < 0.0
    : first.y < 0.0 || first.x < 0.0

  // 原本焊在 main.js 呼叫端的 if/else if 順序規則——needNext 優先於
  // needPrev，一併收進函式內部，避免呼叫端還留有一小塊未被測試涵蓋的
  // 判斷邏輯。
  if (needNext) return 'next'
  if (needPrev) return 'prev'
  return null
}
