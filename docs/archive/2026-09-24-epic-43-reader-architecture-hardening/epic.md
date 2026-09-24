# `epic-43-reader-architecture-hardening` 閱讀器模組架構深化機會（`reader_screen.dart`/`library_screen.dart` 熱點盤點）

**狀態：** 🟢 已歸檔 (Archived)
**存放路徑：** `docs/archive/2026-09-24-epic-43-reader-architecture-hardening/`
**關聯 PRD 章節：** 無直接對應（架構深化，源自 `/improve-codebase-architecture` 盤點，不新增產品功能）

## 開發記錄

2026-09-16 依 `/improve-codebase-architecture` 產出的候選深化機會（範圍：全專案最近 300 個 commit 異動次數最高的檔案——`reader_screen.dart`〔44 次〕、`library_screen.dart`〔35 次〕、`main.js`〔27 次〕等，4 個候選）立案，跳過 Discovery/Architecting（來源已是整合後的候選清單，非從零探索，比照 `epic-26-architecture-hardening`／`epic-41-search-architecture-hardening` 既有慣例）。四個候選將逐一用 `/grilling` 敲定實作細節後拆為 Issue。

2026-09-16 候選 1 已完成 `/grilling`（Q1-Q7，全數採建議答案 (a) 定案：Locator 比照 `Highlight`/`Note` 既有「一組欄位皆可空」寫法、不引入正式 adapter 介面；`AnnotationSession` 維持無狀態回傳快照；「送原生端」「跳窗拿備註文字」「刪除後 UI 收尾」皆留在 `ReaderScreen` 呼叫端；書籤不併入；做成建構子注入依賴的類別而非頂層函式），寫入 `issues.md` Issue 1（`ready-for-agent`）。候選 2-4 尚未 `/grilling`，`issues.md` 先佔位記錄來源與背景，`Status` 皆為 `needs-grilling`。

2026-09-16 候選 2 已完成 `/grilling`（Q1-Q4 全數採建議答案定案；Q5「補齊 `_handleApplyPreset`/`_handleApplyFromBook`/`_handleDeletePreset` 錯誤處理不對稱」使用者確認需要但不夾帶，另立 Issue 5）。與候選 1 不同，`LayoutPresetRepository`／`BookReaderPrefsRepository` 已證實不永遠成對提供（`reader_screen_test.dart` `pumpReaderScreen()` 刻意讓前者可為 `null`、後者維持非空），故本候選**不**沿用候選 1「建構子注入的類別」形狀，改比照 `bookmark_toggle.dart` 風格做頂層函式，各自宣告自己實際需要的 repository 為必要參數。寫入 `issues.md` Issue 2（`ready-for-agent`，依賴 Issue 1 完成後再進行）與 Issue 5（`ready-for-agent`，依賴 Issue 2）。

2026-09-16 候選 3 讀碼後發現與報告原估落差很大：`_buildGroupTiles()` 其實已是獨立方法，`_buildBookList()` 只有 194 行（非 310 行），真正屬於過濾邏輯的只有 `visibleBooks` 約 7 行，方法篇幅主要是有明確理由支撐的分頁/格線幾何計算（`epic-36` Issue 7 遺留）。`/grilling` Q1 使用者確認採 (b)：降級為記錄用，不立即拆 Issue，寫入 `issues.md` Issue 3（`needs-info`，比照 `epic-41` Issue 6 先例）。

2026-09-16 候選 4 讀碼後範圍縮小：Dart→JS（`window.*` 17 個）皆單一呼叫點，deletion test 站不住腳；JS→Dart（`callHandler`，8 個相異名稱）在 `foliate_reader_view.dart`／`search/foliate_content_indexer.dart` 兩檔透過 `JsBridgeGateway.register()`/`.request()` 有真實字串常值重複（`onPageRendered`/`onError` 甚至跨檔重複）。`/grilling` Q1 使用者確認採 (a)：縮小範圍只做 Dart 端 handler name 常數化，寫入 `issues.md` Issue 4（`ready-for-agent`）。

四個候選皆已完成 `/grilling`：Issue 1／2／4／5 為 `ready-for-agent`，Issue 3 為 `needs-info`（記錄用不動手）。

**2026-09-16 `/superpowers:requesting-code-review` 審查 `epic.md`／`issues.md` 文件本身**（`reviews/review-epic-and-issues.md`，0 Critical／3 Important／4 Minor）並已依審查意見修訂 `issues.md`：I-1（Issue 4 handler 數量由誤算的 8 個修正為 11 個，`FoliateBridgeHandlers` 補齊 `onLocatorChanged`/`onSelectionChanged`/`onSegmentsForSectionReady` 三個原本因多行 `callHandler(` 呼叫格式被盤點遺漏的 handler）、I-2（Issue 5 補上 `_handleApplyFromBook` 自己獨立一層 try/catch，涵蓋 `repository.load(sourceBookId)` 這段原本不在 `_applyPrefsToTargets` try/catch 保護範圍內的階段）、I-3（Issue 2 `_applyPrefsToTargets` 補上對話框後與寫入後兩處 `if (!mounted) return;`）皆已修正；M-1（Issue 1 `AnnotationSnapshot` 補上 `operator ==`/`hashCode`，改用 `listEquals` 比對，`Highlight`/`Note` 本身已有既有值相等性可直接利用）、M-2（Issue 2 `overwriteLayoutPreset` 入口補 `assert(target.id != null, ...)`）、M-3（Issue 5 兩個 catch 區塊顯示 SnackBar 前皆補 `if (!mounted) return;`，避免 `use_build_context_synchronously` analyzer 警告）、M-4（Issue 4 新增 `foliate_bridge_handlers_test.dart` 常數值比對測試）亦已修正。五個 Issue 的 `Status` 維持不變。

## 候選清單（來自 `/improve-codebase-architecture` 報告，2026-09-16）

1. **候選 1（Strong）→ Issue 1** — 收斂 `ReaderScreen` 的劃線/備註 CRUD 成 `AnnotationSession` 模組。`reader_screen.dart:1938-2153` 核心配對，另有 `_toggleBookmark`/`_togglePdfBookmark`（1270/1297）等散落同構配對，EPUB／PDF 兩條路徑共 5 對方法、約 220 行近乎逐行同構。Deletion test：刪掉一份，複雜度會在另一份重新出現（因為它已經重新出現過一次）。不牴觸 ADR 0022／0023（該兩份 ADR 只規定渲染路徑分離，未規定資料層 CRUD 邏輯也要分離）。
2. **候選 2（Worth exploring）→ Issue 2＋Issue 5** — 拆出 LayoutPreset 共用操作函式，收斂 `_handleApplyPreset`/`_handleApplyFromBook` 近乎逐行重複的邏輯；Issue 5 另外補齊錯誤處理一致性（使用者要求另立）。
3. **候選 3（Speculative）→ Issue 3（記錄用）** — 讀碼後範圍遠比報告估計小，僅 `visibleBooks` 約 7 行可抽，撐不起完整 Issue 生命週期成本，降級記錄。
4. **候選 4（Speculative）→ Issue 4（縮小範圍）** — 原框架「單一契約清單」站不住腳，改為只做 JS→Dart handler name 的 Dart 端常數化（有真實字串重複證據）。

**依賴順序：**

```
Issue 1（候選 1，獨立，優先）
  └→ Issue 2（候選 2，同檔 reader_screen.dart，降低 merge 衝突風險）
       └→ Issue 5（補齊候選 2 錯誤處理一致性，需在 Issue 2 之後）

Issue 4（候選 4）：獨立，無依賴，可隨時進行

Issue 3：needs-info，記錄用不動手
```

## 下一步

四個候選皆已完成 `/grilling` 並寫入 `issues.md`。依 SDD 生命週期逐一實作：Issue 1 → Issue 2 → Issue 5（依賴鏈），Issue 4 可平行或穿插進行。每個 Issue 開工前撰寫 `plans/plan-issue-<N>.md` 並先發起計畫審查，完成後走 TDD 紅-綠-重構＋獨立程式審查，結果歸檔至 `reviews/`，交由人類合併。
