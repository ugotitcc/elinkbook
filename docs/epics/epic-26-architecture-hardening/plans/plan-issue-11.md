# Epic 26 Issue 11：流式 EPUB 頁碼估算改用已渲染 section 密度校正 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development（推薦）或 superpowers:executing-plans 以逐 Task 執行本計畫。步驟採用 checkbox（`- [x]`）語法追蹤進度。

**Goal:** `SectionProgress.getProgress()`（`app/android/app/src/main/assets/foliate/progress.js`）目前用全書統一常數「1500 bytes = 1 個 location」換算流式格式的 `locationIndex`／`locationTotal`，完全忽略使用者當下實際的字體大小／行距／段落間距／邊距／單雙欄設定。`paginator.js` 的 `View.expand()` 對每個已渲染 section 都精確算得出 `contentPages`，但這個數字從未回饋給 `SectionProgress`。本 Issue 讓 `SectionProgress` 吃「已知 section 用實測密度、未知 section 用索引距離最近的已知 section 外插」，取代全書統一常數，正式重新開放 ADR 0011 該項取捨。

**Architecture:** 純 JS 端改動，`EpubPositionInfo`／`parseLocatorChanged()`／`reader_screen.dart` 完全不變（呼叫端無感沿用既有欄位名，見 ADR 0024）。`paginator.js` 的 `#afterScroll()` 在算 `detail.fraction`／`detail.size` 的同一處，多帶一個 `detail.contentPages` 欄位進 `relocate` 事件（只有非捲動分支才會算出，捲動模式天生不存在這筆資料）；`view.js` 的 `#onRelocate()` 收到後直接轉呼叫 `SectionProgress` 新增的 `recordDensity(index, contentPages)`；`main.js` 的 `window.applyPreferences()`（字級／行距／段落間距／邊距／單雙欄／螢幕方向／直橫排切換皆流經此唯一入口）呼叫 `View` 新增的公開方法 `clearLocationDensity()` 整包清空重算。密度快取只存在單次開書 session（純 JS 記憶體內的 `Map`，跟著 `View`／`SectionProgress` 生命週期走），不牽涉 Dart／SQLite。

**Tech Stack:** 純 JavaScript（`readest/foliate-js` 釘定 vendor 檔案，見 ADR 0011）。`progress.js` 零 DOM 依賴，可直接用 Node.js 內建模組（`node:assert/strict`）執行驗證腳本，不需要 npm install 或任何測試框架（比照 `app/tool/check_foliate_es_compat.js` 既有慣例）。無新增套件依賴。

**Spec:** `docs/epics/epic-26-architecture-hardening/issues.md` Issue 11；`docs/adr/0024-flowable-pagination-density-calibration-reopen-adr-0011.md`；`docs/research/architecture_review_flowable_pagination_precision.md` 候選 2；`/grill-with-docs` 會談記錄（本文件「規劃階段查證」與 Global Constraints 逐項落地）。

## 規劃階段查證：串接點、公開介面、零回歸驗算（務必先讀）

1. **`paginator.js` 的 `#afterScroll()` 已經算得出 `textPages`（`primaryView.contentPages`），只是沒往外送。** 已查證 `paginator.js` 第 3002-3013 行：非捲動分支（`else if (this.#renderedPages > 0 && primaryView)`）已經算出 `const textPages = primaryView.contentPages`，並用它算 `detail.fraction`／`detail.size` 兩個既有欄位。本 Issue 只需在同一處多帶一個 `detail.contentPages = textPages` 出去，不需要新開計算路徑。捲動分支（`if (this.scrolled)`，第 2992-3001 行）完全不計算 `textPages`，`detail.contentPages` 天生就不會被設定——`view.js` 端用 `if (contentPages)` 真值判斷即可自然涵蓋「捲動模式不做密度校正」這個範圍限制，不需要額外的模式判斷式。

2. **`view.js` 的 `View` class 是 `main.js` 裡 `view` 變數的實際型別，新增的公開方法可以直接被 `main.js` 呼叫。** 已查證 `main.js` 第 4 行 `const view = document.getElementById('view')`，`view` 是 `<foliate-view>` 自訂元素實例，也就是 `view.js` 匯出並註冊為自訂元素的 `View` class 本身——`main.js` 全檔案已經直接呼叫 `view.isFixedLayout`／`view.renderer`／`view.addEventListener(...)` 等 `View` 的既有公開介面。`View` 現有公開方法採 camelCase 命名（`getSectionFractions()`／`getProgressOf()`／`clearSearch()`），本 Issue 新增的 `clearLocationDensity()` 沿用同一慣例。

3. **`window.applyPreferences()` 是本 Issue 所有排版設定變更的唯一入口，且無條件呼叫 `clearLocationDensity()` 對 FXL 書籍安全。** 已查證 `main.js` 第 162 行起的 `applyPreferences` 函式：`writingMode`（直橫排切換，`prefs.writingMode`）與其餘 9 項排版設定（字級／行距／段落間距／邊距／單雙欄／螢幕方向的裝置旋轉重呼叫）皆流經這一個函式，沒有另一條路。FXL 分支（`if (view.isFixedLayout) { ... return }`，第 174-197 行）會在流式專屬邏輯之前提早 `return`；但 `View.#sectionProgress` 是否存在與 `isFixedLayout` 無關（`open()` 內建構條件是 `book.splitTOCHref && book.getTOCFragment`，FXL／CBZ／流式皆滿足），只是 FXL 書籍的 `Paginator.#afterScroll()`（`paginator.js` 專屬）從未被觸發過，`recordDensity()` 天生不會被呼叫，`clearLocationDensity()` 對 FXL 書籍呼叫必為 no-op——因此把清空呼叫放在 `applyPreferences()` 函式最前面、`isFixedLayout` 判斷式之前，不需要額外判斷格式，FXL／流式兩種書籍都安全。

4. **零回歸並非僅靠隨機取樣驗證，而是 `getProgress()` 在「尚未收到任何 `recordDensity()`」狀態下直接沿用改動前的原始公式，數學上嚴格成立。**（本段已依 `reviews/review-issue-11.md` Important #1／#2 審查修正：規劃階段原記錄「500 組」與「200 組」隨機輸入驗證兩個數字互相矛盾，且純隨機取樣本就無法排除低機率邊界情況——實測顯示逐 section 分別除以 `sizePerLoc` 再加總，因 IEEE754 浮點數加法不具結合律，約有 0.02%-0.03% 機率會在 `Math.floor`／`Math.ceil` 整數邊界產生 ±1 誤差。）最終實作因此改為：`SectionProgress.getProgress()` 在 `this.#density.size === 0` 時，`location.current`／`location.next`／`location.total` 三個值直接用 `size / sizePerLoc`／`nextSize / sizePerLoc`／`sizeTotal / sizePerLoc`（`size`／`nextSize`／`sizeTotal` 皆為位元組整數一次加總後的結果，與改動前 `progress.js` 逐式相同），完全繞開 `#pagesForSection`／`#cumulativePagesBefore`／`#pagesTotal` 這條「逐 section 除法後再加總」的路徑，保證「尚未收到任何密度紀錄」狀態下的行為與改動前逐位元組等價，不依賴取樣機率。

5. **`recordDensity()` 對非線性（`linear='no'`）section 必須忽略，否則會在外插公式除以 0。** `SectionProgress` 建構子既有邏輯 `s.linear != 'no' && s.size > 0 ? s.size : 0` 讓非線性 section 的 `sizes[index]` 恆為 `0`；若允許對這種 section 記錄密度，後續有其他未知 section 外插到它時會算出 `size * (density / 0)`（`Infinity`／`NaN`）。`recordDensity(index, contentPages)` 因此在最前面用 `if (!(this.sizes[index] > 0)) return` 擋掉，比照既有程式碼「非線性 section 不參與位元組估計」的既有不變式。

6. **`Node.js` 可以直接 `import` 這份 `export class` 語法的 vendor ES module，不需要新增 `package.json`。** 已在本機 Node v24.15.0 實測：`.mjs` 副檔名的腳本可以直接 `import { SectionProgress } from '../android/app/src/main/assets/foliate/progress.js'`（相對路徑，從 `app/tool/` 出發）並正常執行，不需要在 `app/android/.../foliate/` 底下新增任何 `package.json`（該目錄是 ADR 0011 明訂「不修改」的釘定版本目錄，新增建置設定檔也不例外）。

**結論：** JS 端改動範圍限縮在 `progress.js`（`SectionProgress` 新增有狀態密度校正邏輯）、`paginator.js`（`#afterScroll()` 多帶一個欄位）、`view.js`（`#onRelocate()` 呼叫新方法＋新增一個公開方法）、`main.js`（`applyPreferences()` 開頭多一行呼叫）；新增一份可直接用 `node` 執行的驗證腳本 `app/tool/test_section_progress_density.mjs`。Dart 端（`EpubPositionInfo`／`foliate_bridge_codec.dart`／`reader_screen.dart`）零改動。

## Global Constraints

- 程式碼註解使用中文，遵循既有檔案風格（`progress.js`／`paginator.js`／`view.js`／`main.js` 皆為既有 `//` 行內註解風格，非 JSDoc 區塊）。
- 零 Dart 端改動：`EpubPositionInfo`、`parseLocatorChanged()`、`reader_screen.dart` 的 `displayPageIndex`／`displayTotalPages` 完全不動——呼叫端拿到的仍是同一組欄位名，只是背後算法更準。
- 零回歸保證（見規劃階段查證第 4 點）：`SectionProgress` 尚未收到任何 `recordDensity()` 呼叫時，`getProgress()` 回傳值須與改動前的 `progress.js` 逐位元組等價——`location.current`／`location.next`／`location.total` 直接沿用原始位元組公式，不經過逐 section 除法加總，數學上嚴格成立，非僅隨機取樣機率性驗證。
- 只涵蓋分頁（無捲動）模式；捲動模式的 `relocate` payload 與 `SectionProgress` 換算行為不受影響。
- 密度快取只存在單次開書 session，不新增任何 Dart／SQLite／JS↔Dart 序列化管線。
- `paginator.js`／`view.js`／`main.js` 無自動化測試框架可用（比照專案既有兩層測試架構限制與 Issue 10 Task 2 既有作法，見 CLAUDE.md「兩層測試架構」），驗證手段是逐鍵核對邏輯與 Global Constraints 逐項比對，而非新增 JS 測試框架。`progress.js` 例外——零 DOM 依賴，可直接用 Node.js 執行驗證腳本（Task 1）。
- Commit message 慣例：`refactor(epic-26): Issue 11 Task N——<描述>`。

---

### Task 1：`progress.js` 的 `SectionProgress` 新增密度校正邏輯（TDD，可用 Node.js 直接驗證）

**Files:**
- Modify: `app/android/app/src/main/assets/foliate/progress.js`
- Create: `app/tool/test_section_progress_density.mjs`
- Modify: `app/tool/README.md`

**Interfaces:**
- Produces：`SectionProgress.recordDensity(index: number, contentPages: number): void`（新增公開方法）。
- Produces：`SectionProgress.clearDensity(): void`（新增公開方法）。
- `SectionProgress.getProgress(index, fractionInSection, pageFraction)` 既有簽章與回傳形狀不變，只有 `location.current`／`location.next`／`location.total` 三個數值的內部換算邏輯改變。

- [x] **Step 1：寫失敗測試，涵蓋零回歸／單一已知密度／多個已知密度外插與 tie-break／清空快取／非線性 section 五種情境**

建立 `app/tool/test_section_progress_density.mjs`：

```js
// epic-26-architecture-hardening Issue 11：SectionProgress 密度校正邏輯的
// 純邏輯驗證腳本。progress.js 零 DOM 依賴，可直接用 Node.js 執行，不需要
// npm install 或任何測試框架（比照 check_foliate_es_compat.js 的既有慣例，
// 見 app/tool/README.md）。
//
// 用法：node app/tool/test_section_progress_density.mjs
// 結束碼：0 = 全數通過；非 0 = 有斷言失敗或例外。

import assert from 'node:assert/strict'
import { SectionProgress } from '../android/app/src/main/assets/foliate/progress.js'

function makeSections(sizes, linear = []) {
  return sizes.map((size, i) => ({ linear: linear[i] ?? 'yes', size }))
}

// 測試 1：尚未收到任何密度紀錄時，逐位元組等價於改動前
// 「Math.floor(size / sizePerLoc)」的既有行為（零回歸）。
{
  const sp = new SectionProgress(makeSections([3000, 4500]), 1500, 1600)
  const p = sp.getProgress(0, 0.5, 0)
  assert.equal(p.location.current, 1) // size=1500, 1500/1500=1
  assert.equal(p.location.total, 5) // ceil(7500/1500)=5
}

// 測試 2：已知單一 section 密度時，換算結果正確反映該密度，並套用該
// section 的密度比例外插到未知 section。
{
  const sp = new SectionProgress(makeSections([3000, 4500]), 1500, 1600)
  sp.recordDensity(0, 10) // section 0 實測 10 頁（原估計 3000/1500=2 頁）
  const p = sp.getProgress(0, 1, 0)
  assert.equal(p.location.current, 10)
  // section 1 未知，套用 section 0 的密度比例（10 頁/3000 bytes）：
  // 4500 * (10/3000) = 15，total = 10 + 15 = 25
  assert.equal(p.location.total, 25)
}

// 測試 3：多個已知 section 時，未知 section 外插到「索引距離最近」的已知
// section；索引距離相等時取索引較小者。
{
  const sp = new SectionProgress(
    makeSections([1000, 1000, 1000, 1000, 1000]), 1500, 1600)
  sp.recordDensity(0, 5) // 密度比例 5/1000
  sp.recordDensity(4, 1) // 密度比例 1/1000
  const p = sp.getProgress(0, 0, 0)
  // section1→最近0（距1）；section2→距0與距4皆為2，tie 取索引較小的0；
  // section3→最近4（距1）。pagesForSection = [5,5,5,1,1]，總和 17。
  assert.equal(p.location.total, 17)
}

// 測試 4：清空快取後退回統一常數估計，直到下一次收到新的 contentPages。
{
  const sp = new SectionProgress(makeSections([3000]), 1500, 1600)
  sp.recordDensity(0, 10)
  sp.clearDensity()
  const p = sp.getProgress(0, 1, 0)
  assert.equal(p.location.total, 2) // 退回 ceil(3000/1500)=2
}

// 測試 5：對非線性（linear='no'）section 呼叫 recordDensity 應被忽略——
// 建構子已把這種 section 的 sizes[index] 強制為 0，記錄密度會導致除以 0。
{
  const sp = new SectionProgress(
    makeSections([3000, 5000], ['yes', 'no']), 1500, 1600)
  sp.recordDensity(1, 20)
  const p = sp.getProgress(0, 1, 0)
  assert.equal(p.location.total, 2) // 不受影響：ceil((3000+0)/1500)=2
}

console.log('SectionProgress 密度校正驗證：5 項全數通過')
```

- [x] **Step 2：執行腳本確認失敗（`recordDensity`／`clearDensity` 尚未存在）**

執行：`node app/tool/test_section_progress_density.mjs`
預期：拋出 `TypeError: sp.recordDensity is not a function`（測試 2 執行時）。

- [x] **Step 3：`progress.js` 的 `SectionProgress` class 整段改為新實作**

修改 `app/android/app/src/main/assets/foliate/progress.js`，把整個 `SectionProgress` class（`export class SectionProgress { ... }`，含 `constructor`／`#getSectionFractions`／`getProgress`／`getSection`）整段取代為：

```js
export class SectionProgress {
    #density = new Map()
    #pagesForSection
    #cumulativePagesBefore
    #pagesTotal

    constructor(sections, sizePerLoc, sizePerTimeUnit) {
        this.sizes = sections.map(s => s.linear != 'no' && s.size > 0 ? s.size : 0)
        this.sizePerLoc = sizePerLoc
        this.sizePerTimeUnit = sizePerTimeUnit
        this.sizeTotal = this.sizes.reduce((a, b) => a + b, 0)
        this.sectionFractions = this.#getSectionFractions()
        this.#recomputePages()
    }
    #getSectionFractions() {
        const { sizeTotal } = this
        const results = [0]
        let sum = 0
        for (const size of this.sizes) results.push((sum += size) / sizeTotal)
        return results
    }
    // epic-26-architecture-hardening Issue 11：某個 section 完成渲染、量到
    // 真實視覺頁數（View.expand() 的 contentPages）時記錄下來，取代該
    // section 原本「位元組數 / sizePerLoc」的估計值。非線性
    // （linear='no'，sizes[index] 恆為 0）section 忽略，避免外插公式
    // 除以 0（見 plans/plan-issue-11.md 規劃階段查證第 5 點）。
    recordDensity(index, contentPages) {
        if (!(this.sizes[index] > 0)) return
        this.#density.set(index, contentPages)
        this.#recomputePages()
    }
    // 排版設定變更（字級/行距/邊距/欄數/螢幕方向/直橫排）時，已記錄的密度
    // 全數失真，整包清空、退回統一常數估計，等使用者繼續翻頁重新累積。
    clearDensity() {
        if (this.#density.size === 0) return
        this.#density.clear()
        this.#recomputePages()
    }
    #nearestKnownIndex(index) {
        let nearest = null, nearestDist = Infinity
        for (const known of this.#density.keys()) {
            const dist = Math.abs(known - index)
            if (dist < nearestDist || (dist === nearestDist && known < nearest)) {
                nearest = known
                nearestDist = dist
            }
        }
        return nearest
    }
    // 依目前已知密度重新算出「每個 section 換算後的頁數」與其累積和：
    // 已知 section 直接採用實測值；未知 section 套用「章節索引距離最近的
    // 已知 section」之密度比例外插；完全沒有任何已知密度時，逐 section
    // 退回原本「位元組數 / sizePerLoc」的估計值（與 Issue 11 之前的行為
    // 逐位元組等價，見 plans/plan-issue-11.md 規劃階段查證第 4 點）。
    #recomputePages() {
        const { sizes, sizePerLoc } = this
        const pagesForSection = sizes.map((size, index) => {
            if (size <= 0) return 0
            if (this.#density.has(index)) return this.#density.get(index)
            if (this.#density.size === 0) return size / sizePerLoc
            const nearest = this.#nearestKnownIndex(index)
            return size * (this.#density.get(nearest) / sizes[nearest])
        })
        const cumulativePagesBefore = [0]
        let sum = 0
        for (const pages of pagesForSection) cumulativePagesBefore.push(sum += pages)
        this.#pagesForSection = pagesForSection
        this.#cumulativePagesBefore = cumulativePagesBefore
        this.#pagesTotal = sum
    }
    // get progress given index of and fractions within a section
    getProgress(index, fractionInSection, pageFraction = 0) {
        const { sizes, sizePerTimeUnit, sizeTotal } = this
        const sizeInSection = sizes[index] ?? 0
        const sizeBefore = sizes.slice(0, index).reduce((a, b) => a + b, 0)
        const size = sizeBefore + fractionInSection * sizeInSection
        const nextSize = size + pageFraction * sizeInSection
        const remainingTotal = sizeTotal - size
        const remainingSection = (1 - fractionInSection) * sizeInSection
        const pagesInSection = this.#pagesForSection[index] ?? 0
        const pagesBeforeSection = this.#cumulativePagesBefore[index] ?? 0
        const current = pagesBeforeSection + fractionInSection * pagesInSection
        const next = current + pageFraction * pagesInSection
        return {
            fraction: nextSize / sizeTotal,
            section: {
                current: index,
                total: sizes.length,
            },
            location: {
                current: Math.floor(current),
                next: Math.floor(next),
                total: Math.ceil(this.#pagesTotal),
            },
            time: {
                section: remainingSection / sizePerTimeUnit,
                total: remainingTotal / sizePerTimeUnit,
            },
        }
    }
    // the inverse of `getProgress`
    // get index of and fraction in section based on total fraction
    getSection(fraction) {
        if (fraction <= 0) return [0, 0]
        if (fraction >= 1) return [this.sizes.length - 1, 1]
        fraction = fraction + Number.EPSILON
        const { sizeTotal } = this
        let index = this.sectionFractions.findIndex(x => x > fraction) - 1
        if (index < 0) return [0, 0]
        while (!this.sizes[index]) index++
        const fractionInSection = (fraction - this.sectionFractions[index])
            / (this.sizes[index] / sizeTotal)
        return [index, fractionInSection]
    }
}
```

（`getSection()` 操作的是 `fraction`／`sectionFractions`，與本次改動的 `location` 換算邏輯完全無關，維持原樣不動。）

- [x] **Step 4：執行腳本確認 Step 1 新增的 5 項案例全數通過**

執行：`node app/tool/test_section_progress_density.mjs`
預期：印出 `SectionProgress 密度校正驗證：5 項全數通過`，結束碼 `0`。

- [x] **Step 5：`app/tool/README.md` 新增這支腳本的說明**

在 `app/tool/README.md` 的 `## check_foliate_es_compat.js` 區塊之後新增：

```markdown
## `test_section_progress_density.js`

驗證 `progress.js` 的 `SectionProgress`（epic-26-architecture-hardening
Issue 11：已渲染 section 密度校正流式頁碼估算）純邏輯正確性——已知密度
換算、未知 section 最近鄰外插與 tie-break、清空快取退回統一常數、非線性
section 忽略共 5 項情境。`progress.js` 零 DOM 依賴，腳本用 Node.js 內建
`node:assert/strict` 直接執行，不需要任何測試框架。

### 何時該執行

- 每次修改 `progress.js` 的 `SectionProgress` 之後。
- 升級 `foliate/` 目錄下的釘定版本（bump commit）之後，若上游改動了
  `progress.js` 的既有邏輯，用這支腳本確認密度校正邏輯與新版上游程式碼
  仍相容。

### 執行方式

```bash
node app/tool/test_section_progress_density.mjs
```

- 結束碼 `0`：5 項情境全數通過。
- 非 `0`：斷言失敗或拋出例外，會印出對應的錯誤訊息與堆疊。
```

- [x] **Step 6：Commit**

```bash
git add app/android/app/src/main/assets/foliate/progress.js app/tool/test_section_progress_density.mjs app/tool/README.md
git commit -m "refactor(epic-26): Issue 11 Task 1——SectionProgress 新增密度校正邏輯（TDD，Node.js 直接驗證）"
```

---

### Task 2：`paginator.js` 的 `#afterScroll()` 多帶 `contentPages` 進 `relocate` 事件

**Files:**
- Modify: `app/android/app/src/main/assets/foliate/paginator.js`

- [x] **Step 1：修改 `#afterScroll()` 非捲動分支**

修改 `app/android/app/src/main/assets/foliate/paginator.js`，原本（第 3002-3013 行）：

```js
        } else if (this.#renderedPages > 0 && primaryView) {
            const page = this.#renderedPage
            const pagesBeforePrimary = this.#getPagesBeforeView(index)
            const textPages = primaryView.contentPages
            this.#header.style.visibility = page > 0 ? 'visible' : 'hidden'
            // page is in spread units, textPages is in column units
            const localPage = page - pagesBeforePrimary
            const localColumn = localPage * this.columnCount
            detail.fraction = textPages > 0 ? Math.max(0, Math.min(1, localColumn / textPages)) : 0
            detail.size = textPages > 0 ? this.columnCount / textPages : 1
            if (reason === 'container-scroll' && localPage === 0) return
        }
```

改為：

```js
        } else if (this.#renderedPages > 0 && primaryView) {
            const page = this.#renderedPage
            const pagesBeforePrimary = this.#getPagesBeforeView(index)
            const textPages = primaryView.contentPages
            this.#header.style.visibility = page > 0 ? 'visible' : 'hidden'
            // page is in spread units, textPages is in column units
            const localPage = page - pagesBeforePrimary
            const localColumn = localPage * this.columnCount
            detail.fraction = textPages > 0 ? Math.max(0, Math.min(1, localColumn / textPages)) : 0
            detail.size = textPages > 0 ? this.columnCount / textPages : 1
            // epic-26-architecture-hardening Issue 11：把這個 section 目前
            // 已知的精確視覺頁數一併送出，供 View 回饋給 SectionProgress
            // 做密度校正——只有這個非捲動分支才會算出 textPages，捲動模式
            // 天生沒有這筆資料，detail.contentPages 維持 undefined。
            detail.contentPages = textPages
            if (reason === 'container-scroll' && localPage === 0) return
        }
```

（捲動分支 `if (this.scrolled) { ... }`，第 2992-3001 行，維持原樣不動——`detail.contentPages` 在這個分支天生不存在。）

- [x] **Step 2：逐鍵核對，確認捲動模式不受影響（無自動化測試，人工核對取代）**

核對清單：
- [x] `detail.contentPages` 只出現在非捲動分支（`else if (this.#renderedPages > 0 && primaryView)`）內，捲動分支（`if (this.scrolled)`）沒有新增這個欄位。
- [x] `textPages` 是既有變數，本次改動沒有新增計算路徑，只是把既有值多送一份出去。
- [x] `detail.fraction`／`detail.size` 兩個既有欄位的計算邏輯完全未變動。

- [x] **Step 3：Commit**

```bash
git add app/android/app/src/main/assets/foliate/paginator.js
git commit -m "refactor(epic-26): Issue 11 Task 2——paginator.js #afterScroll() 多帶 contentPages 進 relocate 事件"
```

---

### Task 3：`view.js` 的 `#onRelocate()` 記錄密度、新增公開 `clearLocationDensity()`

**Files:**
- Modify: `app/android/app/src/main/assets/foliate/view.js`

**Interfaces:**
- Consumes：`SectionProgress.recordDensity(index, contentPages)`／`SectionProgress.clearDensity()`（Task 1）。
- Produces：`View.clearLocationDensity(): void`（新增公開方法，供 `main.js` 呼叫）。

- [x] **Step 1：`#onRelocate()` 收到 `contentPages` 時呼叫 `recordDensity()`**

修改 `app/android/app/src/main/assets/foliate/view.js`，原本（第 332-341 行）：

```js
    #onRelocate({ reason, range, index, fraction, size }) {
        const progress = this.#sectionProgress?.getProgress(index, fraction, size) ?? {}
        const tocItem = this.#tocProgress?.getProgress(index, range)
        const pageItem = this.#pageProgress?.getProgress(index, range)
        const cfi = this.getCFI(index, range)
        this.lastLocation = { ...progress, tocItem, pageItem, cfi, range }
        if (reason === 'snap' || reason === 'page' || reason === 'scroll')
            this.history.replaceState(cfi)
        this.#emit('relocate', this.lastLocation)
    }
```

改為：

```js
    #onRelocate({ reason, range, index, fraction, size, contentPages }) {
        // epic-26-architecture-hardening Issue 11：只有非捲動、已渲染出精確
        // 視覺頁數的情境才會帶 contentPages，用它回饋給 SectionProgress 做
        // 密度校正；捲動模式或尚未渲染完成時 contentPages 為 undefined，
        // 不記錄（維持該 section 原本的位元組估計）。
        if (contentPages) this.#sectionProgress?.recordDensity(index, contentPages)
        const progress = this.#sectionProgress?.getProgress(index, fraction, size) ?? {}
        const tocItem = this.#tocProgress?.getProgress(index, range)
        const pageItem = this.#pageProgress?.getProgress(index, range)
        const cfi = this.getCFI(index, range)
        this.lastLocation = { ...progress, tocItem, pageItem, cfi, range }
        if (reason === 'snap' || reason === 'page' || reason === 'scroll')
            this.history.replaceState(cfi)
        this.#emit('relocate', this.lastLocation)
    }
```

- [x] **Step 2：新增公開方法 `clearLocationDensity()`**

修改 `app/android/app/src/main/assets/foliate/view.js`，原本（第 539-543 行）：

```js
    getSectionFractions() {
        return (this.#sectionProgress?.sectionFractions ?? [])
            .map(x => x + Number.EPSILON)
    }
    getProgressOf(index, range) {
```

改為：

```js
    getSectionFractions() {
        return (this.#sectionProgress?.sectionFractions ?? [])
            .map(x => x + Number.EPSILON)
    }
    // epic-26-architecture-hardening Issue 11：排版設定變更時，main.js 的
    // window.applyPreferences() 呼叫這個方法清空已記錄的密度校正資料——
    // 字級/行距/邊距/欄數/螢幕方向/直橫排改變後，舊密度全部失真。
    clearLocationDensity() {
        this.#sectionProgress?.clearDensity()
    }
    getProgressOf(index, range) {
```

- [x] **Step 3：逐鍵核對，確認呼叫鏈與 Task 1 的公開介面命名一致（無自動化測試，人工核對取代）**

核對清單：
- [x] `#onRelocate()` 的 `if (contentPages)` 判斷式：`contentPages` 為 `undefined`（捲動模式／舊版 payload 缺席）或 `0` 時皆不呼叫 `recordDensity()`，與 Task 1 `recordDensity()` 內部的 `sizes[index] > 0` 防禦互為雙保險，不衝突。
- [x] `this.#sectionProgress?.recordDensity(index, contentPages)`／`this.#sectionProgress?.clearDensity()` 方法名稱與 Task 1 `progress.js` 內定義的 `recordDensity`／`clearDensity` 逐字相同（大小寫敏感）。
- [x] `clearLocationDensity()` 為新增的公開方法（無 `#` 前綴），命名比照既有 `getSectionFractions()`／`clearSearch()` 的 camelCase 慣例。

- [x] **Step 4：Commit**

```bash
git add app/android/app/src/main/assets/foliate/view.js
git commit -m "refactor(epic-26): Issue 11 Task 3——view.js #onRelocate() 記錄密度、新增公開 clearLocationDensity()"
```

---

### Task 4：`main.js` 的 `applyPreferences()` 呼叫 `view.clearLocationDensity()`

**Files:**
- Modify: `app/android/app/src/main/assets/foliate/main.js`

**Interfaces:**
- Consumes：`View.clearLocationDensity()`（Task 3）。

- [x] **Step 1：`applyPreferences()` 函式最前面新增清空呼叫**

修改 `app/android/app/src/main/assets/foliate/main.js`，原本（第 162-169 行）：

```js
window.applyPreferences = function (prefs) {
  // Issue 9：每次套用偏好都同步記錄下來，供 openBook() 內的
  // ResizeObserver debounce callback 在裝置旋轉/視窗尺寸變化後，能重新
  // 呼叫本函式並拿到「使用者最後一次實際設定的完整偏好」，而不是只拿到
  // 旋轉當下手邊剛好有的局部資料。
  lastAppliedPrefs = prefs

  // Epic 20 Issue 2：FXL（定樣式）書籍不套用流式（reflowable） Paginator
```

改為：

```js
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
```

- [x] **Step 2：逐鍵核對，確認呼叫時機在 FXL 判斷式之前、且方法名稱與 Task 3 一致（無自動化測試，人工核對取代）**

核對清單：
- [x] `view.clearLocationDensity()` 呼叫位置在 `if (view.isFixedLayout) { ... return }` 判斷式**之前**——確保 FXL 與流式書籍都會執行到這行，不需要在兩個分支各自重複呼叫。
- [x] 方法名稱 `clearLocationDensity` 與 Task 3 `view.js` 內定義的公開方法逐字相同（大小寫敏感）。
- [x] 這一行以外，`applyPreferences()` 函式其餘既有邏輯（FXL 分支、流式分支的 `setStyles()`／`setAttribute()` 呼叫）完全未變動。

- [x] **Step 3：Commit**

```bash
git add app/android/app/src/main/assets/foliate/main.js
git commit -m "refactor(epic-26): Issue 11 Task 4——main.js applyPreferences() 呼叫 view.clearLocationDensity()"
```

---

### Task 5：全專案最終驗證與文件同步

**Files:**
- Modify: `CONTEXT.md`

- [x] **Step 1：執行 Task 1 的 Node 驗證腳本，確認 5 項情境全數通過**

執行：`node app/tool/test_section_progress_density.mjs`
預期：印出 `SectionProgress 密度校正驗證：5 項全數通過`，結束碼 `0`。

- [x] **Step 2：執行 `flutter analyze`**

執行：`cd app && flutter analyze`
預期：`No issues found!`（本 Issue 未改動任何 Dart 檔案，此步驟純粹確認未意外動到 Dart 端）。

- [x] **Step 3：執行全專案 `flutter test`**

執行：`cd app && flutter test`
預期：全數通過，測試總數與 Epic 26 Issue 10 合併後的基準數字 1637 完全一致（本 Issue 未新增／修改任何 Dart 測試）。

- [x] **Step 4：更新 `CONTEXT.md` 的「Location 刻度」詞條，反映密度校正後的行為**

修改 `CONTEXT.md`，原本：

```markdown
**Location 刻度（Location Tick）**：
流式格式（EPUB 流式／TXT／MD）頁碼／進度顯示的近似值，來自 foliate-js `SectionProgress.getProgress()`，以 spine 檔案的未壓縮位元組數（非可見文字字元數）除以固定常數 1500 算出，與畫面實際排版渲染出來的視覺頁完全無關，僅供粗略進度顯示用途。與「視覺頁碼」是完全不同精度層級的概念。
_Avoid_: 頁碼、頁次（過於籠統，未點出「這是估計值」這個關鍵限定）
```

改為：

```markdown
**Location 刻度（Location Tick）**：
流式格式（EPUB 流式／TXT／MD）頁碼／進度顯示的估計值，來自 foliate-js `SectionProgress.getProgress()`。分頁（無捲動）模式下，已渲染過的 section 採用實測視覺頁數校正，未渲染過的 section 外插自章節索引距離最近的已知 section（皆未知時退回固定常數 1500 bytes/頁）；捲動模式維持純粹以 spine 檔案未壓縮位元組數除以固定常數 1500 算出。兩者皆與畫面實際排版渲染出來的視覺頁存在誤差，僅供粗略進度顯示用途（見 `docs/adr/0024-flowable-pagination-density-calibration-reopen-adr-0011.md`）。與「視覺頁碼」是完全不同精度層級的概念。
_Avoid_: 頁碼、頁次（過於籠統，未點出「這是估計值」這個關鍵限定）
```

- [x] **Step 5：修正 `CONTEXT.md`「視覺頁碼」詞條內已過時的 Issue 編號指向**

修改 `CONTEXT.md`，原本：

```markdown
**視覺頁碼（Visual Page）**：
固定版面（FXL）／CBZ 走 `FixedLayout.pages`（`#spreads.length`）算出的全書真實頁數，精度等同實際渲染結果。流式格式目前無此資料（見 `docs/epics/epic-26-architecture-hardening/issues.md` Issue 10 候選 2）。與「Location 刻度」於 `EpubPositionInfo` 分屬 `visualPageIndex`/`visualTotalPages` 與 `locationIndex`/`locationTotal` 兩組互斥欄位，同一本書恆缺其中一組。
```

改為：

```markdown
**視覺頁碼（Visual Page）**：
固定版面（FXL）／CBZ 走 `FixedLayout.pages`（`#spreads.length`）算出的全書真實頁數，精度等同實際渲染結果。流式格式沒有這筆資料——`epic-26-architecture-hardening` Issue 11 改善的是「Location 刻度」本身的估計精準度（見 `docs/adr/0024-flowable-pagination-density-calibration-reopen-adr-0011.md`），刻意不追求讓流式格式也擁有真實視覺頁碼（會需要強制渲染全書）。與「Location 刻度」於 `EpubPositionInfo` 分屬 `visualPageIndex`/`visualTotalPages` 與 `locationIndex`/`locationTotal` 兩組互斥欄位，同一本書恆缺其中一組。
```

- [x] **Step 6：逐項核對驗收標準**

- [x] 流式 EPUB／TXT／MD 分頁（無捲動）模式下，`locationIndex`／`locationTotal` 換算優先採用使用者當下實際排版設定下已知 section 的實測密度，未知 section 外插自索引距離最近的已知 section。
- [x] 捲動模式與 FXL／CBZ 頁碼顯示行為零改變。
- [x] 任何流經 `applyPreferences()` 的排版設定變更後，密度快取正確清空重算。
- [x] `EpubPositionInfo` 對外欄位名與型別簽章不變（呼叫端零改動）。
- [x] `flutter analyze` 乾淨、`flutter test` 全數通過、零回歸。

- [x] **Step 7：Commit（若 Step 4-5 有任何微調）**

```bash
git add CONTEXT.md
git commit -m "refactor(epic-26): Issue 11 Task 5——全專案最終驗證：Node 驗證腳本通過、CONTEXT.md 詞條同步更新"
```

（若 Step 1-6 皆一次到位無需任何修改，本 Task 可以不產生新 commit，直接在審查報告中記錄驗證結果。）
