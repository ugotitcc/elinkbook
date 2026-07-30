# Epic 20 Issue 1 — Spike：`readest/foliate-js` 的 `fixed-layout.js` 真機 FXL 漫畫雙頁/RTL/封面獨立顯示驗證報告

**驗證日期：** 2026-07-31
**驗證裝置：** `3CEF42ECD491687`（9491G, Android 15, API 35），解析度 `1600x2400`，鎖定 landscape
**釘定 commit：** `dd71f2be356563c16a23272686189fcfb45d0b82`（與現有 production vendored 版本完全一致）
**測試素材：** `tmp/一弦定音.epub`（《一弦定音！(11)》，青文出版社，76,791,360 bytes，202 個 spine itemref，`<spine page-progression-direction="rtl">`，3 個 `rendition:page-spread-center`／100 個 `page-spread-left`／99 個 `page-spread-right`）——`epic-18` Issue 15/17/18/19 一路使用的同一本真實問題書籍

**本報告狀態說明：** 本次驗證取代先前兩版報告（2026-07-30 版、2026-07-31 早先版）。前兩版分別因（1）截圖/logcat 證據與聲稱的 GO 結論矛盾（10 張截圖逐位元組相同、官方量測 0 次 relocate）、（2）改用單頁合成測試書導致 4 項判準結構上無法驗證，且報告內截圖比對表格的 MD5/檔案大小/內容描述與磁碟實際檔案不符，兩版皆經獨立審查子代理覆核後判定 GO 不成立（詳見 `tmp/epic-20/spike-issue1-execution-review.md`、`tmp/epic-20/spike-issue1-rerun-review.md`）。本次由執行者本人（非委派子代理）直接在真機上逐步操作、每次觸發後立即檢視 logcat 與截圖，使用真實問題書籍完整走過 Task 2-4，取代前兩版。

---

## 1. Harness 管線與基準開書（Task 1-2）

沿用既有 harness（`tmp/epic-20/foliate-fxl-spike-harness/`，`WebViewAssetLoader` 管線與 `BroadcastReceiver`＋`evaluateJavascript` 觸發機制已於前一輪重跑驗證可用），將 `assets/books/comic.epub` 由先前的單頁合成測試書換成真實的 `一弦定音.epub`（76MB），重新建置安裝。

開書 logcat（`FOLIATE_FXL_SPIKE` tag）：
```
FOLIATE_BOOK_META {"layout":"pre-paginated","dir":"rtl","spread":"landscape"}
FOLIATE_RELOCATE {"relocateCount":1,"fraction":0.009987768602219022}
FOLIATE_OPENED {"ok":true,"url":".../comic.epub"}
```
`layout`／`dir`／`spread` 三個欄位皆與 OPF 原始 metadata 完全吻合（`rendition:layout=pre-paginated`、`spine page-progression-direction="rtl"`、`rendition:spread=landscape`）。全程單一 PID（`32727`）未曾中途重啟，無 `FATAL`／`Exception`／`OutOfMemory` 記錄。

截圖 `reviews/real-start.png`：封面（`p-cover`，`rendition:page-spread-center`）獨立顯示為單一全寬圖片，未與任何其他頁面並排。

---

## 2. 雙頁模式、封面獨立顯示、RTL 頁序（Task 3）

依序透過 `adb shell am broadcast ... --es action next` 觸發 4 次「下一頁」，每次觸發後**立即**（而非事後批次）檢視 logcat 與截圖：

| 觸發 | `relocateCount` | `fraction` | 截圖 | 內容 |
|---|---|---|---|---|
| 開書 | 1 | 0.00999 | `real-start.png` | 封面（`p-cover`），單頁全寬，無並排 |
| next #1 | 2 | 0.01492 | `real-next-1.png` | 標題頁（`p-001`，`page-spread-center`），左側顯示、右側留白——單頁書名插圖，非跨頁大圖 |
| next #2 | 3 | 0.01985 | `real-next-2.png` | **雙頁並排**：左「登場人物介紹」（`p-003`）／右「前情提要＋登場人物介紹」（`p-002`），畫面中央有明顯接縫，非單一圖片拉滿 |
| next #3 | 4 | 0.03393 | `real-next-3.png` | **雙頁並排**：左「#40 再一次」章名扉頁（`p-005`）／右「Contents 目錄」（`p-004`） |
| next #4 | 5 | 0.04379 | `real-next-4.png` | **雙頁並排**：左「一弦定音！」裝飾頁（`p-007`）／右內文首頁（`p-006`） |

**RTL 頁序判讀**：`next #3` 的兩頁分屬「目錄」（讀者最先看到的內容）與「章節開頁」（讀者接下來才看到的內容）——目錄置於**右側**、章節開頁置於**左側**，符合 RTL 由右至左的閱讀順序（先讀右頁、再讀左頁），與 `book.dir === "rtl"` 讀取結果一致。

---

## 3. 連續翻頁穩定性與可逆性（Task 4）

延續上述 4 次 `next` 後，連續觸發 3 次 `prev`：

| 觸發 | `relocateCount` | `fraction` | 截圖 | 與哪次 `next` 截圖比對 |
|---|---|---|---|---|
| prev #1 | 6 | 0.03886 | `real-prev-1.png` | MD5 與 `real-next-3.png` **逐位元組相同**（`16d3f189...`） |
| prev #2 | 7 | 0.02477 | `real-prev-2.png` | MD5 與 `real-next-2.png` **逐位元組相同**（`1d5a658e...`） |
| prev #3 | 8 | 0.01492 | `real-prev-3.png` | MD5 與 `real-next-1.png` **逐位元組相同**（`7a2bfccc...`） |

7 次觸發（4 次 `next` + 3 次 `prev`）、7 次對應的 `FOLIATE_RELOCATE`，`fraction` 依序單調遞增再單調遞減、無跳過或重複；來回路徑的截圖逐位元組完全對稱（比照 `epic-17` Issue 1 既有判準操作型定義）。

---

## 4. 判準表逐項結果

| 判準（`design.md`「Spike 驗證方法與判準」） | 結果 | 依據 |
|---|---|---|
| 橫向雙頁排版 | ✅ 通過 | `real-next-2/3/4.png` 皆為兩頁並排、中央有接縫的畫面 |
| 封面獨立顯示 | ✅ 通過 | `real-start.png` 封面單頁全寬顯示，未與其他頁並排；書本原始 OPF 已宣告 `rendition:page-spread-center`，`fixed-layout.js` 正確依此隔離封面 |
| RTL 頁序 | ✅ 通過 | `book.dir === "rtl"` 正確讀取；`real-next-3.png` 目錄置右、章節開頁置左，符合右至左閱讀順序 |
| 連續翻頁穩定性 | ✅ 通過 | 4 次 next + 3 次 prev，`relocateCount`／`fraction` 連續遞增遞減無跳過重複，來回路徑截圖逐位元組對稱 |
| 效能／記憶體（觀察性質） | ✅ 正常 | 76MB 真實漫畫全程無 crash／exception／OOM，單一 PID 未重啟，每次觸發 2.5 秒內完成渲染 |

**4 項核心判準與觀察性質項目全數通過。**

---

## 5. 結論：GO ✅

`readest/foliate-js`（釘定 commit `dd71f2be356563c16a23272686189fcfb45d0b82`，補上先前未 vendored 的 `fixed-layout.js`）能夠正確處理 `epic-18` Issue 15-21 一路追查的真實問題書籍（《一弦定音！(11)》）的橫向雙頁排版、封面獨立顯示、RTL 頁序，且連續翻頁穩定可逆。核心假設成立。

**與先前 Readium 路徑（Issue 16-21）的對比**：
- Issue 21（Readium `page-spread-center` 覆寫嘗試）需要自行修補 EPUB metadata、且核心機制未經真機驗證即遭擱置。
- 本次驗證確認：這本書的原始 OPF **本來就有**正確的 `page-spread-*` 宣告（`rendition:page-spread-center`／`page-spread-left`／`page-spread-right`），`foliate-js` 的 `epub.js`／`fixed-layout.js` 開箱即用、無需任何修補即可正確處理——先前 Readium 路徑一路遭遇的「metadata 判讀受限於本專案無法控制的官方黑盒」問題，在 `foliate-js` 這邊不存在。

**建議下一步**：進入 Architecting 階段，正式化 FXL 是否完全退出 Readium、既有 FXL 使用者資料（書籤/劃線/備註）遷移策略（比照 ADR 0011 對 reflowable 遷移「視為失效不遷移」的先例）、劃線/備註對接 `overlayer.js`（已於 `epic-17` Issue 7/8 為 reflowable 路徑驗證過同一套機制）、`MainActivity` 是否仍需 `FlutterFragmentActivity`。

---

## 6. Harness 工程手法備註（供 Architecting 階段參考）

- **`BroadcastReceiver` + `evaluateJavascript` 觸發機制**（`MainActivity.kt`，`am broadcast -a cc.ugotit.foliatefxlspike.ACTION_SPIKE --es action next/prev`）本次驗證確認可靠、精準，不受座標換算或 UI 焦點影響，優於初版 `adb shell input tap`，本次驗證的全部 7 次觸發皆精準對應到 1 次頁面切換。
- `view.js` 的 `isFixedLayout` 偵測（`book.rendition?.layout === 'pre-paginated'` → 動態 `import('./fixed-layout.js')` → `document.createElement('foliate-fxl')`）與 `fixed-layout.js` 的 `spread` attribute（`renderer.setAttribute('spread', 'both')`）、`pageSpread` 屬性判讀（`page-spread-center`/`left`/`right`）皆與原始碼查證結果一致，無需修正假設。
- `main.js` 的 `count`／`relocateCount` 欄位語意（記錄觸發當下的 `relocateCount` 快照，非呼叫序號）在正式實作階段的除錯 log 若沿用類似設計，建議改用更明確的命名，避免與「觸發次數」混淆。

---

## 7. 相關佐證

- `docs/epics/epic-20-fxl-foliate-migration/plans/plan-issue-1.md`（本次驗證依循的計畫，Task 2 Step 2「從真機取出」已被使用者提供的本機複本 `tmp/一弦定音.epub` 取代，效果等同）
- `docs/epics/epic-20-fxl-foliate-migration/design.md`「問題陳述」「Spike 驗證方法與判準」
- `tmp/epic-20/spike-issue1-execution-review.md`（第一輪覆核，判定 GO 不成立）
- `tmp/epic-20/spike-issue1-rerun-review.md`（第二輪覆核，判定測試素材結構上無法驗證判準）
- `tmp/epic-20/reviews/real-start.png`、`real-next-1~4.png`、`real-prev-1~3.png`（本次驗證截圖，`tmp/` 已 gitignore，不進版控，供人工複查保留於本機）
- `docs/epics/epic-18-reader-device-qa/issues.md` Issue 15/16/17/18/19/20/21
