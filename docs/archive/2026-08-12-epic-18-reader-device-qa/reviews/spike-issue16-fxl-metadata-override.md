# Issue 17 Spike 報告：強制 FXL 覆蓋檢查點後 `EpubNavigatorFragment` 渲染行為驗證

- **驗證日期**：2026-07-30
- **測試裝置**：`3CEF42ECD491687` (9491G, Android 15, API 35)
- **測試書籍**：Issue 15 驗收時已知會被誤判為流式的漫畫 EPUB（已套用「強制 FXL」）
- **結論**：**NO-GO ❌**

---

## 1. 驗證範圍摘要

本 Spike 驗證 Issue 16 的核心假設：`EpubReaderView.kt` 有 3 個各自獨立讀取 `publication.metadata.layout == Layout.FIXED` 的檢查點，但真正決定 WebView 渲染模式（FXL 左右並排 vs. reflowable 單欄連續捲動）的是 Readium 官方元件 `EpubNavigatorFragment`，其 `Configuration` 沒有任何欄位可以覆寫它自己對書本 metadata 的獨立判讀。

驗證方式：用最小範圍的硬編碼（不寫完整 Dart→Kotlin 旗標傳遞管線）覆寫本專案自己的 3 個檢查點後，觀察 `EpubNavigatorFragment` 是否真的會跟著渲染成 FXL。

---

## 2. Task 1：基準觀察（修改前）

### 2.1 執行方式
1. 於 `main` 分支建置 debug APK 並安裝至真機。
2. 開啟已套用「強制 FXL」的漫畫 EPUB。
3. 裝置轉橫向，確認「雙頁模式」設為「永遠雙頁」。
4. 觀察畫面渲染行為。

### 2.2 觀察結果
- 畫面**只顯示一頁（固定在左邊）**
- 翻頁行為為一頁一頁切換，非兩頁一組（spread）切換
- **Issue 16 症狀確認重現**

---

## 3. Task 2：硬編碼 3 個檢查點後驗證

### 3.1 硬編碼變更
於 `app/android/app/src/main/kotlin/cc/ugotit/elinkbook/EpubReaderView.kt` 進行 3 處暫時修改：

| 位置 | 原始程式碼 | 硬編碼後 |
|------|-----------|---------|
| `:501` `applyFxlFitScale()` | `val isFixedLayout = publication?.metadata?.layout == Layout.FIXED` | `val isFixedLayout = true` |
| `:998` tap 熱區監聽器註冊 | `if (openedPublication.metadata.layout != Layout.FIXED) {` | `if (false) {` |
| `:1199` `reportLayoutResolved()` | `val isFixedLayout = publication?.metadata?.layout == Layout.FIXED` | `val isFixedLayout = true` |

### 3.2 執行方式
1. 套用上述 3 處硬編碼。
2. 重新建置 debug APK 並安裝至真機。
3. 重複 Task 1 的觀察步驟。

### 3.3 觀察結果
- 畫面**仍為單頁顯示**
- 翻頁行為仍為一頁一頁切換
- **核心假設不成立**

### 3.4 附帶驗證
因主要假設已否決（NO-GO），跳過 tap 熱區雙重處理風險驗證。

---

## 4. 綜合決策判定：NO-GO ❌

| 判定條件 | 實測證據 | 結果 |
|----------|---------|------|
| 硬編碼 3 個 `isFixedLayout` 檢查點後，`EpubNavigatorFragment` 是否跟著渲染成 FXL（雙頁並排） | 畫面仍為單頁顯示，翻頁行為未改變 | ❌ 不通過 |

**結論**：`EpubNavigatorFragment` 不跟隨 `EpubReaderView.kt` 的 `isFixedLayout` 標誌。其渲染模式由 Readium 官方元件獨立判讀 publication metadata 決定，本專案無法透過覆寫自身檢查點來影響 `EpubNavigatorFragment` 的渲染行為。

---

## 5. 附帶發現

- **tap 熱區雙重處理風險**：因 NO-GO，未進行驗證。但從程式碼分析，`EpubReaderView.kt:998` 的 `if (false)` 硬編碼會導致 tap 熱區監聽器**永遠註冊**（不論書本類型），這在 GO 情境下會造成流式書本的 tap 事件被雙重處理（Dart 端 GestureDetector + Kotlin 端 InputListener）。此風險在 NO-GO 下無意義，但值得記錄供未來參考。

---

## 6. 建議下一步

**NO-GO 後的替代方案評估：**

1. **接受限制**：流式 EPUB 的 FXL 雙頁模式在 Readium kotlin-toolkit 下無法實現，改為在 UI 上提示使用者「此書不支援雙頁模式」。
2. **UI 提示層級**：當使用者嘗試開啟雙頁模式時，若偵測到書本為流式，顯示 Toast 或 Dialog 提示不支援。
3. **評估其他閱讀引擎**：若雙頁模式為必要功能，需評估是否更換閱讀引擎（但成本極高）。
4. **回頭評估 Issue 16 其餘替代方案**： Issue 16 的原始問題是「強制 FXL 後雙頁退化」，NO-GO 表示此路不通，需重新評估 Issue 16 的其他修復方向。

---

## 7. 相關文件

- `docs/epics/epic-18-reader-device-qa/plans/plan-issue-17.md` — 本 Spike 計劃
- `docs/epics/epic-18-reader-device-qa/design.md` — Issue 16/17 Discovery
- `docs/epics/epic-18-reader-device-qa/issues.md` — Issue 16/17 狀態
- `docs/epics/epic-18-reader-device-qa/reviews/spike-flutter-inappwebview-selection.md` — 格式參考
