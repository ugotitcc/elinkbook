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
