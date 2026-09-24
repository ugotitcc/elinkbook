// epic-47 全域 JS 錯誤捕捉誤報 ResizeObserver 警告的回歸場景
//
// 背景：foliate_native_bridge.dart 的 globalErrorCaptureJs（window.onerror）會把
// Chromium 的良性警告「ResizeObserver loop completed with undelivered notifications」
// 轉成 onError，Dart 端記成「openBook 失敗」；若剛好在載入完成前觸發，會把正常開啟的書
// 誤判為開啟失敗（2026-09-25 epic-46 真機驗證，AiPaper Reader C，Chrome 152）。
//
// 本場景直接從 Dart 原始碼抽出 globalErrorCaptureJs 注入頁面（與真機 AT_DOCUMENT_START
// 同一份腳本），觸發真實的 ResizeObserver loop，斷言不會回報 onError；並以真正的例外與
// 未處理的 Promise rejection 作為正向對照，確保過濾沒有把真錯誤一起吞掉。

import { readFile } from 'node:fs/promises'
import path from 'node:path'
import { fileURLToPath } from 'node:url'
import { launchHarnessPage, harnessEvents, resetHarnessEvents, report } from './lib/harness.mjs'

const __dirname = path.dirname(fileURLToPath(import.meta.url))
const BRIDGE_DART = path.resolve(__dirname, '../../lib/reader/foliate_native_bridge.dart')

/**
 * 從 Dart 原始碼抽出 `const globalErrorCaptureJs = '''…''';` 的 JS 內容。
 * 抽出的是原始碼字面，沒有還原 Dart 跳脫（`\$`、`\\`、`\'`）與字串插值；內容一旦
 * 出現 `\` 或 `$`，注入的腳本就可能與真機執行期字串不一致，故直接中止（程式審查 M-2）。
 */
async function loadGlobalErrorCaptureJs() {
  const dart = await readFile(BRIDGE_DART, 'utf8')
  const m = dart.match(/const globalErrorCaptureJs = '''([\s\S]*?)''';/)
  if (!m) throw new Error('在 foliate_native_bridge.dart 找不到 globalErrorCaptureJs')
  if (/[\\$]/.test(m[1])) {
    throw new Error('globalErrorCaptureJs 含有 \\ 或 $，原始碼字面可能與 Dart 執行期字串不同，須改寫抽取邏輯')
  }
  return m[1]
}

/**
 * 在頁面內觸發一次真實的 ResizeObserver loop：callback 內改變被觀察元素自身的尺寸，
 * Chromium 會在同一個 frame 內留下未送達的通知，並以 ErrorEvent 派送到 window.onerror。
 */
function triggerResizeObserverLoop() {
  const el = document.createElement('div')
  el.style.width = '100px'
  el.style.height = '10px'
  document.body.appendChild(el)
  let n = 0
  const ro = new ResizeObserver(() => {
    if (n++ < 5) el.style.width = `${100 + n * 10}px`
    else ro.disconnect()
  })
  ro.observe(el)
}

const sleep = (ms) => new Promise((r) => setTimeout(r, ms))

/**
 * 以頁面內的 <script> 執行程式碼：page.evaluate() 注入的程式屬於另一個 script 來源，
 * 其例外會被 Chromium 遮蔽成「Script error.」，無法代表真機上頁面腳本的例外。
 */
function runAsPageScript(page, code) {
  return page.evaluate((code) => {
    const s = document.createElement('script')
    s.textContent = code
    document.head.appendChild(s)
  }, code)
}

/** 等到 ResizeObserver 警告真的發生，再多等一段讓後續 frame 的警告都送達，避免漏到下一個案例。 */
async function waitRoFiredThenSettle(page) {
  const fired = await page.waitForFunction(() => window.__epic47RoFired === true, { timeout: 3000 })
    .then(() => true, () => false)
  await sleep(1000)
  return fired
}
const onErrorMessages = (events) => events.filter((e) => e.name === 'onError').map((e) => String(e.args[0]))

async function main() {
  const captureJs = await loadGlobalErrorCaptureJs()

  const { browser, page } = await launchHarnessPage({
    fixtureFileName: 'sample.epub',
    beforeNavigate: async (p) => {
      await p.evaluateOnNewDocument(captureJs)
      // 以 addEventListener 另外記錄 ResizeObserver 警告是否真的發生（不受 window.onerror
      // 過濾影響），作為「確實觸發」的前提檢查，避免場景空轉通過。
      await p.evaluateOnNewDocument(() => {
        window.__epic47RoFired = false
        window.addEventListener('error', (e) => {
          if (String(e.message).includes('ResizeObserver')) window.__epic47RoFired = true
        })
      })
      // 案例 A：開書流程早期（DOMContentLoaded）就觸發 ResizeObserver loop，並記錄當下是否
      // 已收到 onPageRendered，作為「確實在開書完成前觸發」的前提檢查（程式審查 M-3）。
      await p.evaluateOnNewDocument(`document.addEventListener('DOMContentLoaded', () => {
        window.__epic47RenderedAtTrigger = window.__harnessEvents.some((e) => e.name === 'onPageRendered');
        (${triggerResizeObserverLoop.toString()})()
      })`)
    },
  })
  try {
    // 案例 A：開書期間
    const roFiredDuringLoad = await waitRoFiredThenSettle(page)
    const eventsA = await harnessEvents(page)
    const roReportsA = onErrorMessages(eventsA).filter((m) => m.includes('ResizeObserver'))
    report('前提：開書期間確實觸發了 ResizeObserver loop（避免空轉通過）', roFiredDuringLoad === true,
      `fired=${roFiredDuringLoad}`)
    const renderedAtTrigger = await page.evaluate(() => window.__epic47RenderedAtTrigger)
    report('前提：觸發當下尚未收到 onPageRendered（確實在開書完成前）', renderedAtTrigger === false,
      `renderedAtTrigger=${renderedAtTrigger}`)
    report('A 開書期間的 ResizeObserver 警告不應回報 onError', roReportsA.length === 0,
      `onError=${JSON.stringify(roReportsA)}`)

    // 案例 B：開書完成後
    await resetHarnessEvents(page)
    await page.evaluate(() => { window.__epic47RoFired = false })
    await page.evaluate(triggerResizeObserverLoop)
    const roFiredAfterOpen = await waitRoFiredThenSettle(page)
    const roReportsB = onErrorMessages(await harnessEvents(page)).filter((m) => m.includes('ResizeObserver'))
    report('前提：開書後確實觸發了 ResizeObserver loop', roFiredAfterOpen === true, `fired=${roFiredAfterOpen}`)
    report('B 開書後的 ResizeObserver 警告不應回報 onError', roReportsB.length === 0,
      `onError=${JSON.stringify(roReportsB)}`)

    // 案例 C：正向對照——真正的未捕捉例外仍須回報
    await resetHarnessEvents(page)
    await runAsPageScript(page, "setTimeout(() => { throw new Error('epic47-real-error') }, 0)")
    await sleep(200)
    const reportsC = onErrorMessages(await harnessEvents(page))
    report('C 真正的未捕捉例外仍須回報 onError', reportsC.some((m) => m.includes('epic47-real-error')),
      `onError=${JSON.stringify(reportsC)}`)

    // 案例 D：正向對照——未處理的 Promise rejection 仍須回報
    await resetHarnessEvents(page)
    await runAsPageScript(page, "Promise.reject(new Error('epic47-real-rejection'))")
    await sleep(200)
    const reportsD = onErrorMessages(await harnessEvents(page))
    report('D 未處理的 Promise rejection 仍須回報 onError', reportsD.some((m) => m.includes('epic47-real-rejection')),
      `onError=${JSON.stringify(reportsD)}`)

    // 案例 E：正向對照——真正的例外即使訊息以「ResizeObserver loop」開頭，也須回報
    // （過濾條件須同時要求「沒有 Error 物件」與「訊息開頭錨定」，程式審查 M-1）
    await resetHarnessEvents(page)
    await runAsPageScript(page, "setTimeout(() => { throw new Error('ResizeObserver loop epic47-real-error') }, 0)")
    await sleep(200)
    const reportsE = onErrorMessages(await harnessEvents(page))
    report('E 訊息含「ResizeObserver loop」的真正例外仍須回報 onError',
      reportsE.some((m) => m.includes('ResizeObserver loop epic47-real-error')),
      `onError=${JSON.stringify(reportsE)}`)
  } finally {
    await browser.close()
  }
}

main().catch((err) => { console.error(err); process.exitCode = 2 })
