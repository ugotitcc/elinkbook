// epic-49 Issue 1：elinkBook 可下載字型服務（見 docs/adr/0035-downloadable-fonts-via-r2-worker.md）。
// 只提供 GET／HEAD /v<N>/<檔名>.ttf，從 R2 binding FONTS 讀取；不提供列出檔案。
// 已發布的檔案永遠不覆蓋，所以回應可以長期快取（immutable）。

// 版本號從 1 開始；檔名只允許英數、點、底線、連字號，不允許斜線與 %，
// 因此 ..、編碼字元、子目錄都無法通過，杜絕路徑穿越。
const FONT_PATH = /^\/(v[1-9][0-9]*\/[A-Za-z0-9._-]+\.ttf)$/

function headersFor(object) {
  return new Headers({
    'Content-Type': 'font/ttf',
    'Content-Length': String(object.size),
    ETag: object.httpEtag,
    'Cache-Control': 'public, max-age=31536000, immutable',
  })
}

export default {
  async fetch(request, env) {
    const method = request.method
    if (method !== 'GET' && method !== 'HEAD') {
      return new Response('Method Not Allowed', { status: 405, headers: { Allow: 'GET, HEAD' } })
    }
    const match = FONT_PATH.exec(new URL(request.url).pathname)
    // 「..」只剩在檔名中間時（例如 /v1/..ttf）也拒絕，不讓任何含 .. 的 key 進入 R2 查詢
    if (match === null || match[1].includes('..')) {
      return new Response('Not Found', { status: 404 })
    }
    const key = match[1]
    // HEAD 只讀中繼資料，避免為一個 HEAD 請求開啟最大 57MB 的物件串流（設計審查 I-1）
    const object = method === 'HEAD' ? await env.FONTS.head(key) : await env.FONTS.get(key)
    if (object === null) {
      return new Response('Not Found', { status: 404 })
    }
    return new Response(method === 'HEAD' ? null : object.body, { status: 200, headers: headersFor(object) })
  },
}
