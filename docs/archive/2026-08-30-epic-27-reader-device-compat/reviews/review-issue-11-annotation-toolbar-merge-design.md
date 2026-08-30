# Review — Epic 27 Issue 11：長按已畫線區域改由畫線工具列統一處理（設計文件審查報告）

**審查對象：** `docs/superpowers/specs/2026-08-24-epic27-issue11-annotation-toolbar-merge-design.md`  
**對應工單：** `docs/epics/epic-27-reader-device-compat/issues.md` Issue 11  
**審查日期：** 2026-08-24（初審：22:53，複審核准：22:58）  
**審查性質：** 架構與實作可行性設計審查（Design Spec Review）  

---

## 總結評估（Executive Summary）

**整體評價：Approved（正式核准，可直接進入 Plan 階段）**

設計文件已針對初審提出的所有架構與實作關鍵事項（PDF 座標系反向轉換、非同步世代競速防護、搜尋高亮已知限制分析、工具列雙列高度實測原則）完成修訂。修訂內容嚴謹、技術細節精確，且完全符合專案架構規範（ADR 0011 不修改 vendored 檔案、與既有世代防護慣例一致）。

---

## 審查意見修訂對照（Review Findings Resolution）

| 項目 | 級別 | 初審意見摘要 | 修訂狀況與技術確認 | 狀態 |
|---|---|---|---|---|
| **1. PDF 座標轉換** | Important | `_extractTextInRect` 草稿直接將 `PercentRect` 轉 `PdfRect` 導致 Y 軸上下顛倒（`PdfRect` 要求 `top >= bottom`）。 | 已於 `pdf_search_geometry.dart` 明確定義 `percentRectToPdfRect` 逆轉換公式，`_extractTextInRect` 採用該 helper，並於測試計畫補上反函式與 assert 斷言。 | **Resolved** |
| **2. PDF 框選非同步防護** | Important | `_finishSelectionDrag` 轉為非同步呼叫 `loadStructuredText` 後存在 async gap，需防止過期結果覆蓋新框選。 | 比照 `_searchSessionId` 慣例加入 `_selectionDragGenerationId` 世代計數器，在手勢起點與 `await` 回來後檢查 `!mounted \|\| generationId != _selectionDragGenerationId`，並補上競速測試。 | **Resolved** |
| **3. EPUB 搜尋高亮命中** | Minor | `overlayer.hitTest` 逆序遍歷若遇搜尋高亮覆蓋可能遮蔽底層畫線。 | 評估修改 `overlayer.js` 遍歷行為會違反 ADR 0011，且情境極窄（搜尋面板開啟且像素重疊），已於文件第 50 行與第 363 行誠實記錄為「已知限制」。 | **Resolved** |
| **4. 工具列高度常數** | Minor | 雙列工具列高度需重測，避免套用硬編碼兩倍。 | 已更新第 331 行說明（概估 96–112dp），明確規範必須以 widget test 實際量測尺寸為準。 | **Resolved** |

---

## Strengths（保留架構優點）

1. **架構根因定位精準**：確認了 WebView 原生長按選字機制攔截 touch/pointer 導致 DOM click 事件失效的本質衝突，統一由 `AnnotationToolbar` 與選字狀態處理標記生命週期。
2. **跨格式統一性與單一職責**：EPUB 透過 Foliate 公開方法與模組變數反查，PDF 在 Flutter 層比對，雙端於 `ReaderScreen._resolveExistingAnnotation` 優雅匯流。
3. **小螢幕版面優化**：雙列排版（第一列 5 顆基本工具；第二列 3 顆進階動作）解決窄螢幕左右溢出問題。
4. **測試計畫嚴謹完備**：涵蓋 Widget Key 相容性、剪貼簿 mock 攔截、反函式幾何測試、非同步世代競速測試等。

---

## 結論與下一步（Conclusion & Next Steps）

設計文件已達到高品質標準，審查通過。

- [x] **設計文件審查通過（Approved）**
- **下一步：** 推進至 Implementation Plan 撰寫階段（`docs/epics/epic-27-reader-device-compat/plans/plan-issue-11.md`）。
