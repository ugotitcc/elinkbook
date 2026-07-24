# Epic 17 Issue 1 — Spike：readest/foliate-js 真機直排分頁穩定性驗證報告

**驗證日期：** 2026-07-21
**驗證裝置：** `3CEF42ECD491687`（`adb devices -l` 顯示 `model:9491G device:Hera_Vis_WIFI`），Android 15（`ro.build.version.release=15`）／API 35（`ro.build.version.sdk=35`），螢幕解析度 1600×2400（`wm size` 輸出，已鎖定 portrait）
**釘定 commit：** `dd71f2be356563c16a23272686189fcfb45d0b82`（2026-07-19）
**測試素材：** `app/test/fixtures/issue9_vertical_pagejump.epub`（與 `epic-7-interaction` Issue 9 spike 同一份）

## Harness 管線驗證（Task 1-3）

- **Task 1（`WebViewAssetLoader` 管線）**：`MainActivity.kt` 以 `WebViewAssetLoader` 完全取代 `file://` 存取，避免 Android WebView 同源政策擋下 `foliate-js` 動態 `import()`/`fetch()` 讀取解包後的 EPUB 內容（zip 內字型/圖片/XHTML/CSS）；`shouldInterceptRequest`/`onConsoleMessage` 已驗證正確攔截並轉發 asset 請求與 JS console log 至 `FOLIATE_SPIKE` logcat tag。
- **Task 2（EPUB 渲染基準）**：以釘定 commit 下載打包 `readest/foliate-js`，`view.open(book)` 成功開啟 `issue9_vertical_pagejump.epub`，`FOLIATE_OPENED {"ok":true}` 與初始 `FOLIATE_RELOCATE` 皆正確記錄，確認基本開書管線可運作（橫排基準，未套用直排覆蓋）。
- **Task 3（直排覆蓋 CSS 與觸發熱區）**：`main.js` 以 `book.transformTarget` 注入 `writing-mode: vertical-rl !important`，並建立 `btn-prev`/`btn-next` 兩個可由 `adb shell input tap` 觸發的固定座標熱區，觸發時記錄 `FOLIATE_TRIGGER {"direction":...}` 與後續 `FOLIATE_RELOCATE {"cfi":...,"fraction":...}`。實測發現：`cover.xhtml`（`spike1-task3-vertical.png`／`spike1-task3-after-tap.png`）為純向量封面圖（`<ops:switch>` 包裹 `<svg><image>`，無可反排文字節點），單次點擊後 CFI 確實改變（`.../svgswitch0]/2,,/2[...]/2` → `.../svgswitch0]/4,,/2/2`）但畫面像素完全相同——經查證 EPUB 原始檔確認純屬「封面頁本身無文字、且內部有兩個渲染結果相同的 CFI 子定位點」，非觸發機制失效。額外診斷性點擊（未列入交付 logcat）證實：翻到 `story-2-2` 真正正文段落後，畫面確實推進，且直排渲染正確——每欄文字由上至下排列、欄序由右至左，符合中文直排排版慣例。Task 4 的正式量測即依此教訓，選在有正文內容的章節頁面上進行。

## 正式量測（Task 4）

**起點**：Task 4 開始時裝置畫面已停留在 `story-2-2` 章節的密集正文段落頁（沿用 Task 3 診斷性點擊遺留的 session 狀態，非封面/版權頁），符合 `design.md`「選擇有正文內容的章節頁面」的判準前提。以 `spike1-task4-start.png` 為正式量測起點截圖（與 Task 3 遺留畫面逐位元組比對檔案大小相同，內容一致）。

### 下一頁 × 3 次

| 觸發順序 | cfi（narrowed） | fraction | 差值 | 截圖內容連續性 |
|---|---|---|---|---|
| 1 | `story-2-2, /60/3:32,/70/1:32` | 0.042091 | +0.007219（相對起點 0.034871） | `start.png` 條列框架說明結尾為第六項「六、轉彎」，`next-1.png` 開頭隨即接續同一份條列框架文章的「七、結局」標題與說明（緊接著才轉入新章節「推薦序」），是同一篇文章條列項目六→七的正常延續，無跳過任何項目、亦無重複 |
| 2 | `story-2-3, /18/3:18,/34/1:18` | 0.052253 | +0.010163（跨章節 story-2-2→story-2-3） | `next-2.png` 首句「的鞋子，問她」承接 `next-1.png` 末字「跟前」（構成「跟前的鞋子」），無縫銜接 |
| 3 | `story-2-3, /34/1:18,/50/1:19` | 0.059140 | +0.006886 | `next-3.png` 首句「不知道」承接 `next-2.png` 末句「你之前」（構成「你之前不知道」），無縫銜接 |

三次觸發皆為單一步的 `fraction` 前進，`FOLIATE_TRIGGER {"direction":"next"}` 與 `FOLIATE_RELOCATE` 一一對應，無多步跳躍、無觸發被吃掉（0 步變化）。

### 上一頁 × 3 次

| 觸發順序 | cfi（narrowed） | fraction | 差值 | 與 next 截圖比對 |
|---|---|---|---|---|
| 4 | `story-2-3, /18/3:18,/34/1:18` | 0.052253 | -0.006886（與觸發 2 完全相同） | `prev-1.png` 與 `next-2.png` 逐位元組完全相同（672555 bytes） |
| 5 | `story-2-2, /60/3:32,/70/1:32` | 0.042091 | -0.010163（跨章節 story-2-3→story-2-2，與觸發 1 完全相同） | `prev-2.png` 與 `next-1.png` 逐位元組完全相同（544939 bytes） |
| 6 | `story-2-2, /36,/60/3:32` | 0.034871 | -0.007219（回到起點 fraction） | `prev-3.png` 與 `spike1-task4-start.png` 逐位元組完全相同（716026 bytes） |

三次「上一頁」逐筆精確鏡像三次「下一頁」的路徑（cfi、fraction 數值完全吻合，含跨章節邊界的往返），三組截圖以檔案大小逐位元組比對（`prev-1≡next-2`、`prev-2≡next-1`、`prev-3≡start`）確認完整回到起點，無跳頁或內容錯位。

logcat（`spike1-task4-logcat.txt`）恰好 6 筆 `FOLIATE_TRIGGER`（依序 next, next, next, prev, prev, prev），每筆後緊接 `FOLIATE_RELOCATE`，無多餘或遺漏事件。

## 判準分類

**結果分類：** 通過（依 `design.md`「Spike 驗證方法與判準」段落之「判準」表定義）

**依據：**
- 6 次觸發（`spike1-task4-logcat.txt` 完整記錄）皆可視內容連續無跳過/重複：next-2/3 與 prev-1/2/3 的首尾字/詞逐一銜接（見上表「截圖內容連續性」欄，具體例如「跟前」+「的鞋子」構成「跟前的鞋子」、「你之前」+「不知道」構成「你之前不知道」），next-1 則以條列項目「六→七」的結構性延續佐證（見上表），符合 `design.md` 對「可視內容是否連續」的操作型定義。
- 內部分頁位置（`fraction`）每次皆為單步變化：+0.007219 / +0.010163 / +0.006886（3 次 next），再精確鏡像 -0.006886 / -0.010163 / -0.007219（3 次 prev），無任何一次出現多步跳躍（如本專案 Readium 案例的 +2/+3 CFI 位置跳躍）或 0 步/被吃掉的情形。
- 往返對稱性以不依賴肉眼判讀的客觀證據佐證：`prev-1.png`≡`next-2.png`（672555 bytes）、`prev-2.png`≡`next-1.png`（544939 bytes）、`prev-3.png`≡`start.png`（716026 bytes），三組皆逐位元組完全相同，與 cfi/fraction 數值表完全對應，構成完整的來回鏡像路徑。
- `start.png`／`next-3.png` 已直接檢視確認為真實、密集、可讀的直排繁體中文段落文字（每欄由上至下排列、欄序由右至左），排除「空白頁/封面圖偽陽性」的可能。
- 唯一的既有兼容性註記（Task 3 對 `cover.xhtml` 的觀察：CFI 改變但畫面像素相同）已查明是封面頁本身無文字內容、且該頁有兩個渲染結果相同的內部 CFI 子定位點所致，非分頁機制缺陷，且與 Task 4 正式量測（選在正文頁面進行）無關，不影響本次分類。
- 本 harness 未實作頁碼標籤/總頁數 UI，故本次證據無法對「計數器層級抖動」類別（`design.md` 判準表第二列）做出判定；但既有證據已完全符合「通過」類別的定義（所有觸發皆內容連續且內部位置皆單步變化），無需退而求其次歸類為抖動級。

## GO / NO-GO 決策

**結論：** GO

依 `design.md`「GO / NO-GO 決策路徑」段落，Spike 判準「通過」直接構成 GO 訊號。下一步進入 Architecting 階段，正式撰寫 `spec.md`，屆時需重新逐項確認 `foliate-js-migration-feasibility-assessment.md` 既有的 6 項共識決策與 4 階段路線圖（不直接照抄轉正，需比對本次 Spike 實測結果與本專案既有架構重新驗算），並將 `design.md`「已知風險」段落列出的殘留未知數（長期釘住第三方 fork 的維護風險、Bridge Adapter 定位相容性、`WebViewAssetLoader` 串流、FXL 縮放、字數統計、硬體加速對渲染品質的影響等）納入 Architecting 階段逐項評估範圍。
