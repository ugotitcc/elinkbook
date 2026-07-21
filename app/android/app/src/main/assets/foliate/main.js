import { makeBook } from './view.js'

const view = document.getElementById('view')

// FoliateBridge 由原生端 FoliateEpubReaderView.kt 透過
// WebView.addJavascriptInterface() 注入，見該檔案 KDoc 說明——不是
// console.log 解析（那是 Issue 1 Spike harness 專屬手法）。
async function openBook() {
  try {
    const book = await makeBook(
      'https://appassets.androidplatform.net/book/current.epub',
    )
    await view.open(book)
    view.renderer.setAttribute('flow', 'paginated')
    view.addEventListener('relocate', () => {
      window.FoliateBridge.onPageRendered()
    }, { once: true })
    // 見 Issue 1 Spike（plans/plan-issue-1.md Task 2）已驗證的行為：
    // view.open(book) 本身不會導覽到任何 section，必須呼叫 view.init()
    // 才會觸發首次渲染與 relocate 事件；空物件會落入其 else 分支
    // （history.pushState(0); this.next()），固定從第 0 節開始。
    await view.init({})
  } catch (e) {
    window.FoliateBridge.onError(String((e && e.message) || e))
  }
}

openBook()
