# Epic 7 — 互動控制：設計 (Design)

> 本文件由 `/grill-with-docs` 2026-07-18 逐項確認產生，結合 `/domain-modeling` 詞彙表維護（見 `CONTEXT.md`「熱區模式」「熱區動作」「沉浸模式」）。

## 問題陳述

FR-18 要求裝置音量鍵可翻頁（方向固定），FR-24 要求可自訂的 3×3 九宮格點擊導航區域，支援多種翻頁映射模式以適應左右手持機習慣。目前專案完全沒有音量鍵處理程式碼；點擊翻頁僅有 EPUB FXL 的暫代版三欄熱區（`epic-16-dual-page` Issue 9，`CONTEXT.md` 明文標註為範圍受限的臨時方案），EPUB 流式完全交由 Readium 原生手勢，PDF 僅有橫向滑動翻頁手勢。

## 範圍界定

### 包含範圍

- **FR-18 音量鍵翻頁**：全新開發，原生 Activity 層攔截。
- **FR-24 3×3 熱區**：統一涵蓋 EPUB 流式、PDF、EPUB FXL 三種畫面，取代 FXL 現有暫代版熱區（決策 #1）。
- 熱區「選單」動作觸發的「沉浸模式」（介面顯示/隱藏切換），含 EPUB 流式／PDF 新增可隱藏 AppBar+頁尾的能力（決策 #12）。

### 明確排除

- **TXT 格式**：`epic-11-txt-engine` 尚未開始，本 epic 不涵蓋。
- **`epic-14-system-settings` 的完整全域設定畫面架構**：僅在既有 `SettingsScreen` 輕量插入一個「導航熱區」入口，不提前建置整個 epic-14。
- **FR-36 音量鍵總開關**：留給 `epic-14-system-settings`；本 epic 音量鍵翻頁預設永遠啟用、無法關閉。
- **熱區設定的單書覆寫**：明確排除，熱區模式為全域生效，不分書籍（決策 #9）。
- **直排(RTL)自動鏡像**：明確排除，與 PRD FR-24 原文字面偏離，見 ADR 0009。

## 決策紀錄（Discovery 逐項確認）

| # | 決策點 | 採用結果 |
|---|---|---|
| 1 | FR-24 適用畫面範圍 | 統一涵蓋 EPUB 流式、PDF、EPUB FXL 三種畫面，取代 `epic-16-dual-page` Issue 9 建立的 FXL 暫代版三欄熱區 |
| 2 | 熱區映射模式 | 四選一互斥：左翻頁／右翻頁／單手（皆為固定模板，不可個別微調）／自訂（完全自由編輯 9 格）；**不**隨橫排/直排自動鏡像，使用者依閱讀方向與持機習慣手動選模式（見 ADR 0009，與 PRD FR-24 原文偏離） |
| 3 | 資料模型粒度 | 9 格各自獨立可設定的資料模型（即使目前 3 個固定模板皆是欄均勻行為），供「自訂」模式與未來擴充共用同一種結構，不做「3 欄」簡化模型 |
| 4 | 「左翻頁」模板定義 | 左欄＝下一頁、中欄＝選單、右欄＝上一頁（上中下三格同欄同動作） |
| 5 | 「右翻頁」模板定義 | 左欄＝上一頁、中欄＝選單、右欄＝下一頁 |
| 6 | 「單手」模板定義 | 左右欄完全對稱（不分左右手），依垂直位置決定動作：上排＝選單、中排＝上一頁、下排＝下一頁；中間欄全部無動作 |
| 7 | 「自訂」模式與固定模板的關係 | 兩者為分離、互斥的頂層選項；固定模板不可個別微調，任何差異化需求一律改用自訂模式的自由編輯器。**自訂編輯器強制驗證：9 格中至少須有 1 格指定為「選單」動作，否則不允許儲存**——避免使用者設定出全部為上一頁/下一頁/無動作、沒有任何格子能退出沉浸模式的死鎖組合（審查意見修正，原留待 spec.md 階段決定的風險已在此收斂） |
| 8 | 可指定的熱區動作 | 四選一：上一頁、下一頁、選單（觸發沉浸模式切換）、無動作（攔截觸控但不做事） |
| 9 | 熱區設定儲存層級 | 全域生效（`GlobalReaderPrefs` 擴充），不做單書覆寫——理由是持機習慣不因書籍而異，與字型/版面這類可能因書而異的設定性質不同 |
| 10 | 設定 UI 入口位置 | 插入既有 `SettingsScreen`（新增「導航熱區」項目），輕量插入、不提前完成整個 epic-14 |
| 11 | 熱區輔助線 | 納入範圍，作為使用者可見的顯示/隱藏設定開關（比照原型 `prototype/index.html` 既有的除錯輔助線構想，但正式化為使用者功能） |
| 12 | 「選單」動作的畫面行為 | 統一為「沉浸模式」（切換介面顯示/隱藏）：EPUB 流式／PDF 新增可隱藏的 Scaffold AppBar＋`ReaderFooter`（目前無此能力，需新增）；EPUB FXL 沿用既有懸浮控制項（返回/設定/書籤/筆記按鈕）顯示/隱藏機制 |
| 13 | 沉浸模式範圍 | AppBar＋頁尾一起隱藏／顯示，不是只隱藏 AppBar |
| 14 | 翻頁動作是否影響沉浸模式 | 上一頁／下一頁動作**不**影響介面顯示狀態，僅選單格可切換——與 FXL 現有「換頁一律強制收起懸浮控制項」行為不同，是刻意的行為變更（換頁後不再自動收起） |
| 15 | EPUB 流式捲動翻頁模式（`pageTurnMode == scroll`）下的熱區行為 | 左右熱區（上一頁/下一頁）失效；中間選單格仍可切換沉浸模式。PDF 無捲動模式，不受影響 |
| 16 | PDF 既有橫向滑動翻頁手勢 | 移除，改為純點擊熱區導覽（見 ADR 0010） |
| 17 | FXL「無動作」格子的觸控行為 | 攔截觸控但不做事，維持現有已知限制（FXL 內嵌超連結仍無法點選），不順便修復 |
| 18 | FR-24 各畫面底層手勢捕捉機制 | EPUB 流式：原生 Kotlin `InputListener.onTap()`（全新技術，全專案零使用，先安排獨立 Spike 工單驗證可行性，比照 `epic-16-dual-page` Issue 1 驗證 Readium spread 行為的先例）。EPUB FXL：沿用既有已驗證可行的 Flutter `GestureDetector` 疊加層，從 3 欄擴充為 9 格（FXL 不支援選字，無手勢競技場衝突風險）。PDF：新增 Flutter `GestureDetector`（PDF 無 WebView/Readium 可用，只能 Flutter 端實作），與既有長按拖曳框選（劃線）共存於同一手勢競技場 |
| 19 | FR-18 音量鍵捕捉層 | 原生 `MainActivity.dispatchKeyEvent()` 攔截 `KEYCODE_VOLUME_UP`/`KEYCODE_VOLUME_DOWN`；攔截與否的判斷依據**改為原生端可自行觀測的真實狀態——`EpubReaderView`/`PdfReaderView` PlatformView 是否目前附加於 `supportFragmentManager`**，取代原本「由 Dart 經 MethodChannel 主動通知的 async 旗標」（審查意見修正：async 旗標與 Flutter route 離開之間存在理論上的競態窗口，PlatformView 附加/移除是原生端唯一可靠、無額外非同步延遲的真實訊號）。避開 EPUB WebView 持有焦點時 Flutter `HardwareKeyboard`/`RawKeyboardListener` 可能收不到事件的已知風險。PlatformView 移除後（即離開閱讀畫面）音量鍵立即恢復系統原生音量調節 |

## 使用者流程（概要）

### 設定熱區模式（全域，`SettingsScreen`）

1. 使用者進入「設定」→「導航熱區」。
2. 四選一：左翻頁／右翻頁／單手／自訂。
3. 選「自訂」時進入 9 格自由編輯器，逐格指定動作（上一頁/下一頁/選單/無動作）。
4. 可另外開啟「顯示熱區輔助線」，回到閱讀畫面時能看見目前熱區邊界與對應動作標籤。
5. 設定即時全域生效，套用於所有書籍的 EPUB 流式／PDF／EPUB FXL 畫面。

### 閱讀時使用熱區

1. 使用者點擊畫面上對應熱區格。
2. 若動作為上一頁/下一頁：觸發翻頁，介面顯示狀態不變。
3. 若動作為選單：切換沉浸模式（EPUB流式/PDF 顯示/隱藏 AppBar+頁尾；FXL 顯示/隱藏懸浮控制項）。
4. 若動作為無動作：不做任何事（觸控仍被攔截，不穿透到底層內容）。
5. EPUB 流式若目前為捲動翻頁模式，左右熱區的翻頁動作不生效，選單格仍可用。

### 音量鍵翻頁

1. 使用者在 `ReaderScreen` 按下音量增加鍵 → 上一頁；音量減少鍵 → 下一頁，方向固定，不受熱區模式或排版方向影響。
2. 離開 `ReaderScreen` 後，音量鍵恢復系統原生音量調節功能。

## 新增的 `GlobalReaderPrefs` 欄位

| 欄位 | 型別 | 說明 |
|------|------|------|
| `navZoneMode` | `NavZoneMode`（non-nullable） | `leftFlip`／`rightFlip`／`oneHand`／`custom` 四選一，預設 `rightFlip`（最常見的橫排 LTR 慣例） |
| `navZoneCustomActions` | `List<ZoneAction>`（長度固定 9） | 僅 `navZoneMode == custom` 時有意義；三個固定模板（`leftFlip`/`rightFlip`/`oneHand`）的 9 格動作由程式碼常數表算出，不落地儲存 |
| `showNavZoneDebugOverlay` | `bool`（non-nullable） | 是否顯示熱區輔助線，預設 `false` |

> 沿用既有「全域預設值（Global Default）」模式：目前無 `epic-14-system-settings` 對應設定畫面，先以 `shared_preferences` 存放（比照 `pageTurnMode`/`screenOrientation` 既有作法），設定入口輕量插入既有 `SettingsScreen`（決策 #10）。

## 新增的 Enum 定義

```
NavZoneMode: leftFlip | rightFlip | oneHand | custom
ZoneAction: previousPage | nextPage | menu | none
```

9 格索引慣例（0-indexed，列優先）：
```
0 1 2
3 4 5
6 7 8
```

三個固定模板的 9 格常數（依上述索引，`menu` 亦稱「選單」）：

| 模板 | 0 | 1 | 2 | 3 | 4 | 5 | 6 | 7 | 8 |
|---|---|---|---|---|---|---|---|---|---|
| `leftFlip`（左翻頁） | next | menu | prev | next | menu | prev | next | menu | prev |
| `rightFlip`（右翻頁） | prev | menu | next | prev | menu | next | prev | menu | next |
| `oneHand`（單手） | menu | none | menu | prev | none | prev | next | none | next |

## 架構影響摘要

| 模組 | 異動類型 | 說明 |
|------|---------|------|
| `GlobalReaderPrefs` | 擴充 | 新增 `navZoneMode`／`navZoneCustomActions`／`showNavZoneDebugOverlay` 三欄位 |
| `NavZoneMode`／`ZoneAction`（新建） | 新建 | 兩個新 Enum，`NavZoneMode` 另需一份「模板→9 格陣列」的常數解析邏輯（`custom` 直接讀 `navZoneCustomActions`） |
| `SettingsScreen` | 擴充 | 新增「導航熱區」`ListTile` 入口 |
| 導航熱區設定畫面（新建） | 新建 | 四選一模板選擇 + 自訂模式的 9 格自由編輯器（儲存前驗證至少 1 格為選單，見決策 #7） + 熱區輔助線開關 |
| `ReaderScreen` | 擴充 | 新增沉浸模式狀態（AppBar／`ReaderFooter` 顯示/隱藏），依 `resolved`（或 `GlobalReaderPrefs`）的熱區設定分派上一頁/下一頁/選單/無動作；新增音量鍵事件的 MethodChannel 接收端 |
| `PdfReaderView.dart`/`.kt` | 核心改動 | 移除 `onHorizontalDragEnd` 滑動翻頁（ADR 0010）；新增 9 格點擊熱區判讀（與既有長按拖曳框選共存於同一手勢競技場，具體整合方式留待 `spec.md`/`plan-issue-N.md` 階段細化） |
| `EpubReaderView.kt` | 核心改動（流式路徑） | 新增原生 `InputListener.onTap()` 綁定，依座標換算熱區格＋依 `NavZoneMode`/`ZoneAction` 分派動作；需先透過獨立 Spike 工單驗證 API 可行性 |
| `EpubReaderView.dart`/`.kt` | 擴充（FXL 路徑） | 既有 3 欄 `Row`+`GestureDetector` 疊加層擴充為 9 格（3×3），沿用相同「no-op drag 搶手勢競技場」機制；「無動作」格維持攔截觸控 |
| `MainActivity.kt` | 新建 | 覆寫 `dispatchKeyEvent()` 攔截 `KEYCODE_VOLUME_UP`/`KEYCODE_VOLUME_DOWN`，依目前是否有 `EpubReaderView`/`PdfReaderView` PlatformView 附加於 `supportFragmentManager`（原生端真實狀態，非 Dart 主動通知的旗標，見決策 #19）決定攔截與否，透過 MethodChannel 通知 Dart 觸發翻頁 |
| `docs/prd.md` | 文字修正 | FR-24 文字與 editHistory 已同步修正，反映不自動鏡像的實際決策（見 ADR 0009） |
| `docs/adr/0009-*.md`/`0010-*.md`（新建） | 新建 | 記錄「不自動鏡像」與「PDF 移除滑動手勢」兩項與明顯路徑偏離的決策 |
| `CONTEXT.md` | 擴充 | 新增「熱區模式」「熱區動作」「沉浸模式」三個詞彙定義 |

## 已知風險 / 待 Architecting 階段確認的技術細節

- **`InputListener.onTap()` 可行性未驗證**（決策 #18）：Readium 的 `EpubNavigatorFragment` 是否已有內建點擊翻頁行為需要先停用、`InputListener` 回呼能否真的攔下並取代預設行為，全專案完全沒有先例。已決議先安排獨立 Spike 工單（比照 `epic-16-dual-page` Issue 1）在進入 Scrum Master 拆解前驗證並回填結論。
- **PDF 手勢競技場**：新的 9 格點擊熱區（`onTap`）與既有長按拖曳框選（`onLongPress*`，`epic-6-annotations` Issue 3／ADR 0008）共存於同一個 `GestureDetector`，雖然 Flutter 理論上可依按住時長/移動距離自然區分，仍需在真機上實測確認不會互相誤觸發，延續 ADR 0008 已標記但尚未收斂的風險。
- **FXL 熱區從 3 欄擴充為 9 格**：需與既有懸浮控制項（左上返回、右上設定/書籤/筆記按鈕）的觸控範圍協調，避免熱區疊加層搶走這些按鈕本身的點擊（懸浮按鈕通常位於熱區網格的角落格內）。
- **音量鍵攔截與系統音量條**：`dispatchKeyEvent()` 攔截並消費事件後，需真機驗證系統原生的音量提示 UI（音量條 Toast）是否仍會意外跳出。

## 範圍外 (Out of Scope)

- TXT 格式的熱區/音量鍵支援——`epic-11-txt-engine` 尚未開始。
- `epic-14-system-settings` 的完整全域設定畫面架構與 FR-36 音量鍵總開關——僅輕量插入一個設定入口，其餘留給 epic-14。
- 熱區設定的單書覆寫——明確排除，全域生效（決策 #9）。
- 直排(RTL)自動鏡像——明確排除，見 ADR 0009。
- FXL「無動作」格觸控穿透（修復內嵌超連結被擋的問題）——維持現有已知限制不處理（決策 #17）。
- 熱區/沉浸模式的進場/退場過場動畫——本 epic 不新增。
