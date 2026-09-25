// epic-49 Issue 1：Worker 的純 Node 單元測試。以假的 R2 binding 呼叫 fetch。
// 用法：node fonts-cdn/test/test_worker.mjs
// 結束碼：0 = 全數通過；非 0 = 有斷言失敗或例外。
import assert from 'node:assert/strict'
import worker from '../worker/index.js'

// 假的 R2 binding：記錄每次呼叫，讓測試能斷言 HEAD 完全沒有呼叫 get()。
function fakeBucket(objects) {
  const calls = []
  const meta = (key) => ({ size: objects[key].length, httpEtag: `"etag-${key}"` })
  return {
    calls,
    async get(key) {
      calls.push(['get', key])
      if (!(key in objects)) return null
      return { ...meta(key), body: new Blob([objects[key]]).stream() }
    },
    async head(key) {
      calls.push(['head', key])
      return key in objects ? meta(key) : null
    },
  }
}

const FONT_BYTES = new Uint8Array([1, 2, 3, 4, 5])
const request = (method, path) => new Request(`https://elinkbook-fonts.example.workers.dev${path}`, { method })
const call = async (method, path, objects = { 'v1/A.ttf': FONT_BYTES }) => {
  const env = { FONTS: fakeBucket(objects) }
  const response = await worker.fetch(request(method, path), env)
  return { response, calls: env.FONTS.calls }
}

// GET 200：標頭齊全、body 與物件內容相同
{
  const { response, calls } = await call('GET', '/v1/A.ttf')
  assert.equal(response.status, 200)
  assert.equal(response.headers.get('content-type'), 'font/ttf')
  assert.equal(response.headers.get('content-length'), '5')
  assert.equal(response.headers.get('etag'), '"etag-v1/A.ttf"')
  assert.equal(response.headers.get('cache-control'), 'public, max-age=31536000, immutable')
  assert.deepEqual(new Uint8Array(await response.arrayBuffer()), FONT_BYTES)
  assert.deepEqual(calls, [['get', 'v1/A.ttf']])
}

// HEAD 200：標頭與 GET 相同、沒有 body、只呼叫 head()
{
  const { response, calls } = await call('HEAD', '/v1/A.ttf')
  assert.equal(response.status, 200)
  assert.equal(response.headers.get('content-type'), 'font/ttf')
  assert.equal(response.headers.get('content-length'), '5')
  assert.equal(response.headers.get('etag'), '"etag-v1/A.ttf"')
  assert.equal(response.headers.get('cache-control'), 'public, max-age=31536000, immutable')
  assert.equal(response.body, null)
  assert.deepEqual(calls, [['head', 'v1/A.ttf']])
}

// 物件不存在：GET 與 HEAD 都回 404
{
  assert.equal((await call('GET', '/v1/Missing.ttf')).response.status, 404)
  assert.equal((await call('HEAD', '/v1/Missing.ttf')).response.status, 404)
}

// 未來的版本路徑（v2）也能服務，改版時不必重新部署 Worker
{
  const { response } = await call('GET', '/v2/A.ttf', { 'v2/A.ttf': FONT_BYTES })
  assert.equal(response.status, 200)
}

// 不提供列出檔案、非版本路徑、非 .ttf：一律 404，且完全不碰 R2
for (const path of ['/', '/v1/', '/v1', '/A.ttf', '/fonts/A.ttf', '/v1/A.txt', '/v0/A.ttf', '/vx/A.ttf']) {
  const { response, calls } = await call('GET', path)
  assert.equal(response.status, 404, `路徑 ${path} 應回 404`)
  assert.deepEqual(calls, [], `路徑 ${path} 不應呼叫 R2`)
}

// 路徑穿越與編碼字元：一律 404，且完全不碰 R2
for (const path of ['/v1/../A.ttf', '/v1/%2e%2e/A.ttf', '/v1/sub/A.ttf', '/v1/A%2F.ttf']) {
  const { response, calls } = await call('GET', path)
  assert.equal(response.status, 404, `路徑 ${path} 應回 404`)
  assert.deepEqual(calls, [], `路徑 ${path} 不應呼叫 R2`)
}

// GET／HEAD 以外的方法：405，並帶 Allow 標頭
for (const method of ['POST', 'PUT', 'DELETE', 'PATCH']) {
  const { response, calls } = await call(method, '/v1/A.ttf')
  assert.equal(response.status, 405, `${method} 應回 405`)
  assert.equal(response.headers.get('allow'), 'GET, HEAD')
  assert.deepEqual(calls, [])
}

console.log('PASS：test_worker.mjs 全數通過')
