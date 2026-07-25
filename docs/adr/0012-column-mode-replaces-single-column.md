# ADR 0012：流式 EPUB 分欄控制從 `singleColumn` 布林改為「欄數」三態 +「欄位大小」閾值

## 狀態

已採納

## 背景

Epic 18 Issue 5 為直排 EPUB 新增「強制單欄」偏好（`BookReaderPrefs.singleColumn: bool?`），機制是透過 `main.js` 呼叫 `view.renderer.setAttribute('max-column-count', singleColumn ? '1' : '2')` 設定 `paginator.js` 的 `--_max-column-count` CSS 自訂屬性。Issue 5 的 code review 第三輪以真機 mutation test 發現：此開關在測試裝置 `3CEF42ECD491687`（1200dp 高度）上對直排書籍完全是 no-op。

根因是 `paginator.js:1817-1822` 的 `#beforeRender()` 分欄公式：

```js
const divisor = Math.min(
    maxColumnCount + (vertical ? 1 : 0),
    Math.ceil(Math.floor(hostSize) / Math.floor(maxInlineSize)),
)
```

直排書籍（`vertical === true`）會在 `maxColumnCount` 上無條件 `+1`——這是 vendored `readest/foliate-js` 的既有邏輯，本專案依既有決策（ADR 0011）不修改 vendored 檔案。設定 `max-column-count = 1` 時，直排的有效上限是 `1 + 1 = 2`，而 `ceil(hostSize / 720)` 在所有高度 > 720 CSS px 的裝置上都 >= 2，因此 `divisor` 永遠是 2——`singleColumn` 開關對直排書籍不產生任何可觀察差異。此外，在大螢幕裝置（如 AiPaper Reader C，~1758dp）上，使用者實際遇到了三欄排版的問題（`ceil(1758/720) = 3`），這是 `max-column-count` 機制無法解決的。

## 決策

用「欄數（Column Mode）」三態選擇 +「欄位大小（Column Size）」閾值滑桿取代 `singleColumn` 布林，核心機制改為透過 `setAttribute('max-inline-size', ...)` 控制分欄閾值，繞過 `max-column-count` 受制於直排 `+1` 的問題。

三態行為：
- **單欄**：`maxInlineSize` 設為極大值 → `ceil(hostSize / 極大值) = 1` → 強制 `divisor = 1`，不論裝置尺寸或排版方向
- **自動**：`maxInlineSize` 使用「欄位大小」滑桿值（預設 720px），由 paginator 公式自由決定欄數
- **雙欄**：JS 端動態計算，硬限 `divisor` 最多為 2

`max-inline-size` 是 `paginator.js` 既有的 `observedAttributes`（`paginator.js:1159`）且已有完整的 `attributeChangedCallback` 支援，不需要修改 vendored 檔案。

## 考量的替代方案

1. **修改 vendored `paginator.js` 移除直排 `+1` 邏輯**——違反 ADR 0011 釘定版本的既有決策，且該 `+1` 可能有其合理用途（readest/foliate-js 上游設計意圖不明），貿然移除風險不可控
2. **透過 CSS 直接覆蓋 `--_max-column-count-spread` / `--_max-column-count-portrait`**——這些 CSS 變數是 `paginator.js` 內部衍生值（`var(--_max-column-count)` 的 cascade），外部覆蓋會與 `attributeChangedCallback` 的寫入衝突，行為不可預測
3. **維持 `singleColumn` 布林但加大 `maxInlineSize` 預設值**——無法讓使用者在「完全交給引擎決定」和「我要強制單欄」之間做選擇，也無法解決三欄問題
