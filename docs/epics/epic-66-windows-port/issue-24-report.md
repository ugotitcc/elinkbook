# Epic 66 Issue 24 報告：雙欄一般翻頁的「目前章節」判定

- **日期**：2026-11-13　**分支**：`fix/epic-66-issue-24-dual-column-chapter`
- **程式變更**：`app/android/app/src/main/assets/foliate/main.js`（新增 `firstColumnRange()`、`resolveFlowableTocItemId()`）；測試：harness 場景 `scenario-dual-column-toc-item.mjs`、`app/integration_test/epub_toc_test.dart` 新案例、新 fixture `sample_single_spine_flat_toc.epub`；詞彙表 `CONTEXT.md` 新增「目前章節」。**不改釘定 vendor、不改 Dart 契約；`app/lib/` 0 行。**

## 1. 問題與重現
雙欄（兩欄同時可見）時，foliate 的 `TOCProgress.getProgress(index, range)` 取「range 內最後一個目錄項」，而 range 涵蓋兩欄，所以第二欄才出現的標題會讓目前章節領先使用者先讀到的那一欄。harness（1280x800、`sample_single_spine_multi_anchor.epub`）重現：橫排翻頁 1 現行判定第二節、第一欄仍在第一節；翻頁 3 現行判定第三節、第一欄在第二節；直排同樣偏。影響範圍：目前章節共用同一個來源，涵蓋目錄面板高亮與展開、頁首章名、書籤預設名稱、劃線筆記章名。

**BooksPad 直立時就是雙欄**（CSS 寬約 749，`divisor = min(maxColumnCount, ceil(寬 / 720)) = 2`；橫向約 998 也是 2），所以影響的是主力裝置，不只是橫向平板。

## 2. 規則決定的經過（含一次失誤）
1. 最初選**規則 A＝可視範圍起點**（把 range 收成起點再算），人類同意。
2. 實作後 Windows 子集跑測發現 **2 個回歸**（`assets/issue-24-windows-subset.log`）：(a) `epub_toc_test` 單 spine 多錨點案例「開書位於第一節」失敗（Windows 預設視窗 800x600 就是雙欄，開書第一頁左欄含上層標題與第一節標題，起點規則標到上層項）；(b) `foliate_toc_footer_test`「跳到第三節後 tocItemId 應為 3，實際為 2」失敗（標題不在第一欄最上方時標成前一節）。**這是我先前低估了規則 A 的限制**（我當時只說「第一頁會標到上層項」，沒有指出它會破壞既有測試、也會影響錨點跳轉）。
3. 人類改選**規則 B＝把第一欄當成單欄的那一頁，取第一欄範圍內最後一個目錄項**，並指定**不改 vendor、在 `main.js` 自己算**。

## 3. 規則 B 的實作
- 第一欄（先讀的欄）：橫排為左欄；**直排雙欄是沿垂直方向的上下兩欄，先讀上欄**（每欄內的行再由右向左）。我先前寫「直排為右欄」是錯的，已更正於詞彙表與計畫。
- `firstColumnRange(view, range, columnCount)`：以 `view.renderer` 公開的 `start`／`size`／`columnCount` 算邊界 `start + size / columnCount`（橫排用 `left`、直排用 `top`），從 range 起點所在文字節點往後走，找最後一個「字的起點座標小於邊界」的位置，跨界節點用二分搜尋；把 range 結尾截到那裡。range 沒有任何行落在第二欄、水平 RTL、找不到文字或任何例外時回傳 null。
- `resolveFlowableTocItemId(view, detail)`：只有流式分支、`columnCount > 1` 且切得出第一欄時，才呼叫現成的 `view.getProgressOf(section.current, 第一欄 range)`；否則回退 `detail.tocItem`。**絕不拋出**（拋出會讓後面的 `onLocatorChanged` 回報中斷、進度追蹤凍結）。FXL／CBZ 分支、`locatorJson`、vendor、Dart 都不動。
- 雙欄偵測採公開屬性 `view.renderer.columnCount`：1280x800 自動欄數（橫排、直排）為 2，400x800 與強制單欄為 1。（計畫初稿誤寫「沒有公開讀取方法」，經審查更正。）
- **座標依據（實測）：** 橫排 1280x800 `start/size` 為 0/1223、1223/1223…，第二欄文字 x 約 `start + 612` 起；直排 1280x800 `size` 800（沿 y 軸），第二欄 y 自 `start + 400` 起。

## 4. 驗證
| 項目 | 結果 |
|---|---|
| harness 場景 `scenario-dual-column-toc-item.mjs` | 規則 B **20 項全過**（雙欄橫排 7 頁、雙欄直排 6 頁、單欄 400x800 13 頁、強制單欄 9 頁，逐頁比對，另加錨點跳轉）；修改前舊規則雙欄 4 項失敗（單欄全過）。**預期值不手寫**：以獨立 DOM 座標當標準答案（標題 `h2#s1/s2/s3` 座標小於第一欄邊界者的最後一個），並斷言涵蓋 id 1／2／3 以免空轉 |
| harness 全套 `run-all.mjs` | **147 項 PASS、1 項 FAIL**：失敗的是 `scenario-cross-mechanism-tap-boundary`（Issue 26 已登記的偶發失敗），其餘全過（含本 Issue 的 20 項）。見第 4.1 節 |
| Windows `epub_toc_test` | **4/4**；新案例暫時還原 `main.js` 後失敗（舊規則序列 `[第一章, 第二章, 第二章, 第二章]`，新規則 `[第一章, 第一章, 第二章, 第二章]`） |
| Windows 相關 11 個檔案 | **11/11**（`epub_toc_test`×3、`foliate_toc_footer_test`、`epub_pagination`、`epub_dual_page`、`reading_position`、`foliate_epub_reader_view`、`reader_footer`、`foliate_single_column`、`reader_header_footer_toggle`，`assets/issue-24-windows-subset-B.log`） |
| **Windows 整份冒煙套件** | **28/28**（0 失敗、0 逾時、0 中止，1560 秒，`assets/issue-24-windows-smoke-suite.log`） |
| BooksPad `foliate_toc_footer_test` | **3/3**（4 項，`assets/issue-24-android-foliate_toc_footer_test-run1..3.log`） |
| BooksPad `epub_toc_test` | 改版後 **3/3**（4 項，`assets/issue-24-android2-*`）；改版前 3 次各有 1 項失敗，見第 5 節 |
| `flutter analyze`、`check_integration_keys.js`、`check_l10n_hardcoded_strings.js`、`check_foliate_es_compat.js` | 皆乾淨 |
| 全套 `flutter test` | **5167 通過、2 略過、0 失敗** |

### 4.1 `tap-boundary` 偶發失敗與本修改的關係
`scenario-cross-mechanism-tap-boundary.mjs`（選取收尾保護期 150 ms 內快速點擊）是 Issue 26 登記的計時型偶發失敗。它用預設視窗 800x1200（`ceil(800/720)=2`，**雙欄**），所以本修改的 relocate 路徑會在其中執行。我在機器閒置、沒有殘留進程（確認過）時比較：

| 條件 | 單獨跑 `tap-boundary` 失敗次數 |
|---|---|
| 修改前（暫時還原 `main.js`） | 8 / 11 |
| 修改後（規則 B） | 18 / 19（另有最終 harness 全套 1 次） |

- **今天這個場景在沒有本修改時就多數失敗**（8/11），與 Issue 26 登記時（單跑 4 次皆過）不同，原因不明（可能與重開機後機器狀態有關，**未驗證**）。
- 修改後的失敗率較高（95% 對 73%），但樣本小、**無法確認差異是否真實**，我不能排除本修改使它略差。
- 直接量測本修改在 relocate 路徑增加的耗時：寬 800 雙欄下，翻頁到收到 `onLocatorChanged` 的延遲，修改前後都是 **2～3 ms**，沒有可量到的增加（只量到書的前 3 頁）。選取注入與 `cdpTap` 的間隔不經過 relocate 路徑。
- **後續更正（Issue 26，2026-11-13）：** 該場景失敗是系統性的（注入選取後觸控往返被拖慢約 100 ms，使選取到 `mousedown` 的間隔超出 150 ms 保護期），與本修改無關（還原 `main.js` 同樣失敗），已改為決定性場景，見 [issue-26-report.md](issue-26-report.md)。以下為當時的判斷。
- 結論：**不歸咎、也不排除**；此場景仍是 Issue 26 的偶發問題，建議在 Issue 26 處理時一併重新評估（它在這台機器今天的失敗率）。本 Issue 驗證時其餘 harness 場景（147 項）與 Windows、BooksPad 整合測試都不受影響。

### 4.2 全套
全套 `flutter test`（2026-11-13，工作區含本修改）：**5167 通過、2 略過、0 失敗**。

## 5. 一件測試本身的問題（已修）
新增的整合測試案例原本把 Windows 1280x800 的**分頁序列**寫死，BooksPad 上實際分頁不同（4 頁都落在第三章），導致 BooksPad 3 次各失敗 1 項。這是測試太依賴版面，不是產品問題；規則本身由 harness 的獨立標準答案驗證（與版面無關）。改為：所有平台都驗「頁首章名是目錄中的章、翻頁不倒退、同一時刻目錄面板高亮與頁首章名一致」，只有 Windows 才釘住完整序列。

## 6. 已知限制與未處理
- **第二欄才出現的標題要翻頁後才反映**（規則本身的定義）。
- **錨點跳轉後若標題落在第二欄，JS 層回報前一節**：harness 實測橫排跳到第三節時標題落在第二欄，標準答案就是第二節。目錄**面板**跳轉由 Dart 端 `TocJumpOverride` 處理（本 Issue 不動它）；書籤、劃線、搜尋跳轉**只觀察、不修、未驗證沒問題**。Windows 與 BooksPad 的既有 `foliate_toc_footer_test` 在各自的分頁位置下標題落在第一欄，所以仍通過，這不代表所有分頁位置都如此。
- **水平 RTL 書**（阿拉伯文等，非本專案主要目標）第一欄在右側，程式退回現行判定，未處理。
- **只在一台 BooksPad（32 位元、WebView 91）與這台 Windows 驗證**；其他 Android 裝置未驗證。BooksPad 上只跑了 `epub_toc_test` 與 `foliate_toc_footer_test`，沒有跑完整 Android 冒煙套件。
- 「章節尾頁只有一欄有內容」時 `columnCount` 的值未單獨驗證；此情境下 range 沒有行落在第二欄，`firstColumnRange` 回傳 null，退回現行判定。
- 效能：relocate 內新增的文字節點走訪與字元座標查詢只在 range 實際跨到第二欄時才執行，從 range 起點開始走（不從文件開頭）；**未量測前後翻頁耗時**（計畫的 Review Focus 6），harness 全套沒有觀察到翻頁逾時。
- 開書第一頁在雙欄與單欄現在一致（左欄含上層標題與第一節標題時標第一節），harness 與 `epub_toc_test` 都有涵蓋。
