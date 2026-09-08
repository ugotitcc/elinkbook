# elinkBook 設計系統規範 (Design System Specification)

本文件基於現行 Flutter 程式碼庫與 UI/UX 稽核報告，為 elinkBook 電子書閱讀器定義一套全新的設計系統。本規範的核心目標是在**保留並精緻化現有產品識別**的基礎上，提升全域 UI 的一致性與可用性，並**深度兼顧與最佳化 Android E-Ink 電子紙閱讀器裝置**的閱讀體驗。

---

## 核心設計原則

1. **視覺與體驗分流 (Separation of Chrome and Page)**
   App 的操作介面（書架、設定、Sheet、對話框，統稱 **Chrome**）與書籍內容的閱讀頁面（流式文字、PDF 頁面，統稱 **Page**）之主題設定必須徹底分流。使用者可以設定深色 Chrome 搭配羊皮紙 Page，或 Page 跟隨環境光感應而 Chrome 維持不變。
2. **E-Ink 作為全域修飾子 (E-Ink as a Modifier)**
   E-Ink 模式不是第四種主題，而是一個全域的**狀態修飾子 (State Modifier)**。當 `isEinkMode` 啟用時，應動態修飾當前主題（Light/Dark/Sepia），將連續動畫降級為無轉場、將 Slider 替換為 Stepper、將連續滾動降級為離散翻頁，並強制邊框與純黑白高對比色彩。
3. **畫面只負責組合，元件負責樣式 (Composition over Styling in Screens)**
   禁止在畫面層 (Screens/Views) 出現寫死的顏色 (Hex/Colors)、字級 (fontSize)、間距 (EdgeInsets/SizedBox) 或圓角數值。畫面層應僅使用設計系統定義的基礎元件 (EB Component) 與領域元件，並透過 Token 系統存取樣式。

---

## 1. 色彩 Token 系統 (Color Tokens)

為了解決寫死灰/黑色穿透主題、以及羊皮紙主題下 Material 3 預設淡紫外洩的問題，我們**參考並整合「白陽書院」的典雅水墨書院色彩系統**，定義 Light (晴空藍天)、Dark (夜讀水墨)、Sepia (宣紙古風) 三種主題的完整 `ColorScheme` 與專屬的 `ElinkTokens`。

### 1.1 全域 Material 3 ColorScheme 補齊規範

| 語義角色 | 晴空藍天 (Light) | 夜讀水墨 (Dark) | 宣紙古風 (Sepia) | E-Ink 模式 (E-Ink Mod) |
| :--- | :--- | :--- | :--- | :--- |
| `primary` (主操作色) | `#0284c7` (天空藍) | `#38bdf8` (夜光天藍) | `#b8362d` (硃砂印泥紅)| `#000000` (純黑) |
| `onPrimary` | `#FFFFFF` | `#141416` | `#FFFFFF` | `#FFFFFF` |
| `primaryContainer` | `#e0f2fe` (蔚藍輕雲)| `#182836` | `#faecea` (硃砂粉紅) | `#FFFFFF` (外框 `primary`) |
| `onPrimaryContainer`| `#0284c7` | `#38bdf8` | `#b8362d` | `#000000` |
| `surface` (卡片/控制項)| `#FFFFFF` | `#1d1d22` (深墨) | `#FAF3E3` (淺宣紙) | `#FFFFFF` |
| `onSurface` (主文字) | `#0f172a` (晴空夜墨) | `#f2efe6` (月白宣紙字) | `#1f2022` (松煙濃墨)| `#000000` |
| `onSurfaceVariant` (副字) | `#334155` (遠山青灰) | `#b5b2a8` (寒煙灰) | `#535457` (焦茶淡墨)| `#000000` |
| `outline` (分隔線/邊框) | `#cbdfe9` (天際線) | `#2c2c34` | `#e6dfcb` (書頁框線)| `#000000` (邊框 ≥ 1.5dp) |
| `scaffoldBackground`| `#f0f6fc` (蔚藍底色) | `#141416` (玄青夜色) | `#fcfaf2` (宣紙底色) | `#FFFFFF` |
| `surfaceContainerHighest` | `#e6f1fa` | `#19191d` | `#f0ebd9` (陳年宣紙色)| `#FFFFFF` (邊框) |
| `error` | `#EF4444` | `#F87171` | `#DC2626` | `#000000` |

### 1.2 ElinkTokens (ThemeExtension) 專屬語意色

以下色彩屬性透過 `Theme.of(context).extension<ElinkTokens>()` 存取，杜絕寫死色值：

```dart
class ElinkTokens extends ThemeExtension<ElinkTokens> {
  final Color highlightYellow;     // 劃線黃：晴空 #FEF08A, 深色 #854D0E, 宣紙 #fef3c7 (泥金), E-Ink 無背景(下劃線)
  final Color highlightGreen;      // 劃線綠：晴空 #BBF7D0, 深色 #166534, 宣紙 #edf5f0 (竹青), E-Ink 無背景
  final Color highlightBlue;       // 劃線藍：晴空 #BFDBFE, 深色 #1E40AF, 宣紙 #edf2f7 (黛藍), E-Ink 無背景
  final Color underlineColor;      // 劃線底線色：晴空 #0284c7, 深色 #38bdf8, 宣紙 #b8362d, E-Ink #000000
  final Color progressTrack;       // 進度條軌道：晴空 #cbdfe9, 深色 #2c2c34, 宣紙 #e6dfcb, E-Ink #000000 (空心)
  final Color coverPlaceholder;    // 封面佔位色：晴空 #e6f1fa, 深色 #1d1d22, 宣紙 #f0ebd9, E-Ink #FFFFFF (加框)
  final Color badgeScrim;          // 徽章半透明罩：晴空 #94a3b8, 深色 #7a7872, 宣紙 #848588, E-Ink #000000
  final Color ttsActiveHighlight;  // TTS 朗讀高亮：晴空 #e0f2fe, 深色 #182836, 宣紙 #faecea, E-Ink 無背景(加外框/點虛線)
  
  // E-Ink 核心適配標籤
  final bool isEink;               // 是否為 E-Ink 模式
  final bool reducedMotion;        // 是否簡化動態（E-Ink 下為 true）
  final bool discretePaging;       // 是否離散換頁（E-Ink 下為 true）
  
  // ... 建構子與 copyWith / lerp 實作
}
```

---

## 2. 字體 Token 系統 (Typography Tokens)

為確保中文直排與橫排的閱讀流暢性，並適應中老年讀者的視力需求，所有字體大小與行高均需遵循統一規格，並完全支持 `MediaQuery.textScalerOf`。

### 2.1 系統字級定義

```
EBTextTheme
├─ display       : 32sp / 行高 1.3  (大標題/書名詳細頁)
├─ titleLarge    : 20sp / 行高 1.4  (AppBar 標題、Dialog 標題)
├─ titleMedium   : 16sp / 行高 1.5  (區段主標題、設定分組標題)
├─ bodyLarge     : 15sp / 行高 1.6  (主要文字：書架書名、列表標題、設定主要文字)
├─ bodyMedium    : 14sp / 行高 1.6  (次要文字：Sheet選項標籤、對話框內文)
├─ labelMedium   : 13sp / 行高 1.5  (輔助說明文字、書頁進度與章節名稱、書籍詮釋資料)
└─ labelSmall    : 11sp / 行高 1.4  (徽章、微型進度百分比)
```

### 2.2 核心排版原則

- **CJK 安全行高**：操作介面的中文行高一律不低於 `1.5`，閱讀頁內文字體行高依偏好設定，預設為 `1.6`。
- **防止中文書名截斷**：書架格狀視圖的書名限制最少為 `2 行`，字級不低於 `15sp`。
- **字型管理**：支援內建 5 款 CJK 字型及使用者透過 SAF 引入的 `Custom Font`。字型統一以 Family Name 字串形式儲存。

---

## 3. 間距 Token 系統 (Spacing Tokens)

elinkBook 採用 `4dp` 步進的間距系統，解決臨機間距導致的視覺節奏斷裂問題。

```dart
class EBSpace {
  static const double none = 0;
  static const double xxs  = 2;
  static const double xs   = 4;
  static const double sm   = 8;
  static const double md   = 12;
  static const double lg   = 16;
  static const double xl   = 24;
  static const double xxl  = 32;
  
  // 平板最大內容寬度限制
  static const double maxContentWidth = 680;
}
```

- **應用指引**：
  - 封面與文字間距：`xs` (4dp) 或 `sm` (8dp)。
  - 列表項目 Padding：`md` (12dp) 垂直，`lg` (16dp) 水平。
  - Bottom Sheet 內邊距：`lg` (16dp) 四週。
  - 平板版面限制：大螢幕上的設定與表單畫面，其最大寬度限制為 `maxContentWidth`，左右兩側自動留白，避免無限拉寬。

---

## 4. 圓角 Token 系統 (Radius Tokens)

為了維持介面元素輪廓的系統性，圓角限制為三階：

```dart
class EBRadius {
  static const double sm = 8;   // EBButton、小卡片、封面圓角、輸入框
  static const double md = 16;  // Dialog 容器、EBCard 卡片、分類格子
  static const double lg = 28;  // Bottom Sheet 頂部圓角、TTS 懸浮控制列
}
```

*註：在 E-Ink 模式下，圓角維持不變，但必須額外繪製 `1.5dp` 的純黑色邊框以建立明確邊界。*

---

## 5. 陰影與海拔 Token 系統 (Elevation Tokens)

為防止電子紙裝置因半透明陰影抖動而產生殘影，陰影極度簡化：

```dart
class EBElevation {
  static const double none = 0; // 無陰影。E-Ink 模式下所有元件強制為 none。
  static const double sm   = 2; // 用於普通卡片、懸浮操作列（如 TTS Mini Player）
  static const double md   = 4; // 用於對話框 (Dialog) 與 底部抽屜 (Bottom Sheet)
}
```

- **E-Ink 模式陰影替代方案**：所有原本需要 Elevation 產生深度的元件，改為 `Border` (邊框) 或 `Divider` 作為視覺分隔。

---

## 6. 圖示指引與語義規範 (Icon Guidelines)

為了解決原書籤（星星）與筆記（bookmark）圖示語言矛盾、以及分頁標籤使用 emoji 的混亂，在此規範標準 Icon 語義：

### 6.1 核心操作圖示對照表

| 功能概念 | 規範圖示 (Icon) | 原有用法（已淘汰） |
| :--- | :--- | :--- |
| **書籤 (Bookmark)** | `Icons.bookmark` / `Icons.bookmark_border` | `Icons.star` (星星) |
| **劃線與備註 (Note)** | `Icons.edit_note` | ✏️ (Emoji) / `Icons.notes` |
| **目錄 (TOC)** | `Icons.toc` / `Icons.list` | `Icons.toc` |
| **筆記與書籤入口 (Notes Entry)**| `Icons.bookmarks` | `Icons.star_outline` |
| **圖書來源 (Book Source)** | `Icons.cloud_download` | `Icons.add` |
| **排序/檢視切換 (Sort/View Toggle)** | `Icons.sort` / `Icons.view_list` | 無 |
| **全螢幕/沉浸式切換** | `Icons.fullscreen` / `Icons.fullscreen_exit` | 無 |
| **設定 (Settings)** | `Icons.settings` | `Icons.tune` |
| **電子紙刷新 (E-Ink Flash)** | `Icons.refresh` | 無 |

### 6.2 設計與渲染要求
- **觸控精度與尺寸**：圖示自身視覺尺寸為 `24dp`，但其包裝容器（IconButton）的物理觸控目標必須滿足**最小 48dp** (E-Ink 模式下提高至 `56dp`)。
- **禁用 UI Emoji**：分頁籤、按鈕等控制項文字旁嚴禁使用 Emoji，一律改用標準 Material 圖示。

---

## 7. 按鈕變體與觸控規範 (Button Variants)

所有按鈕元件 (EBButton, EBIconButton) 必須提供三個視覺變體，並在底層強制最小觸控目標。

### 7.1 按鈕變體定義
1. **Filled Button (填滿變體)**：主要動作（如「確認刪除」、「套用預設」）。
2. **Outlined Button (描邊變體)**：次要/並列動作（如「取消」、「複製自其他書」）。
3. **Text Button (文字變體)**：低優先級動作（如「還原預設值」）。

### 7.2 觸控目標與狀態規範

- **觸控目標 (Touch Target)**：
  - 一般模式：最小 `48dp × 48dp`。
  - E-Ink 模式：最小 `56dp × 56dp`。
- **狀態反饋 (State Feedback)**：
  - **一般模式**：Hover 狀態亮度微調，Pressed 狀態觸發波紋動畫。
  - **E-Ink 模式**：
    - 停用所有 Splash/Ripple/Hover/Highlight 效果（避免殘影）。
    - 採用**離散狀態變更**：點擊時以「反白（Invert Background/Text）」或「加粗邊框（Border Width 1.5dp -> 3dp）」作為即時物理反饋。

---

## 8. 卡片變體與視覺規範 (Card Variants)

`EBCard` 是書架格狀物件、分類資料夾、OPDS 來源卡片與設定區塊的基礎。

### 8.1 卡片變體與規格

1. **Elevated Card**：`elevation = EBElevation.sm`，用於書架上的書籍卡片與分類資料夾。
2. **Outlined Card**：`border = outline` 且 `elevation = none`，用於設定區塊、下載佇列卡片。E-Ink 模式下，Elevated Card 自動降級為此變體。

### 8.2 封面佔位符 (Cover Placeholder) 規範

- 嚴禁使用寫死的 `Colors.grey.shade300` 等中間灰。
- 佔位符背景使用 `Theme.of(context).extension<ElinkTokens>().coverPlaceholder`。
- 佔位符內必須包含：`Icons.book` 圖示（前景採用 `onSurfaceVariant`）與書名文字的微型縮略。
- E-Ink 模式下的佔位符為**純白底＋1.5dp 純黑實線外框**。

---

## 9. 對話框規範 (Dialog Variants)

`EBDialogShell` 統一管理全域對話框的排版、最大寬度與操作按鈕擺放。

### 9.1 排版結構
- **寬度約束**：對話框在手機上寬度為螢幕寬度之 85%，在平板上強制限制最大寬度為 `400dp`。
- **按鈕佈置**：動作按鈕一律靠右並排。主動作（確認）在右，次動作（取消）在左。
- **E-Ink 模式**：取消對話框背景後的半透明 Scrim 漸變動畫，改為**即時不透明度切換**或**全幅純白覆蓋**。

### 9.2 破壞性操作安全守衛 (Destructive Actions Guard)
- **規範**：凡涉及「刪除書籍」、「移除本機快取」、「清除劃線備註」等破壞性操作，必須彈出確認對話框。
- **確認文案**：主動作按鈕文字需標明具體後果（如「確認刪除檔案」而非模糊的「確定」），按鈕顏色採用 `error` 色。

---

## 10. 底部抽屜模式 (Bottom Sheet Patterns)

目錄、筆記、版面設定與 TTS 控制面板一律由 `EBSheetShell` 統一包裹。

### 10.1 物理規格與佈局
- **拖曳把手 (Drag Handle)**：頂部居中設置一個 `32 × 4dp` 的條狀把手，圓角 `EBRadius.sm`。
- **安全區**：底部必須自動填充 `MediaQuery.of(context).padding.bottom`（防止被系統導覽列遮擋）。
- **最大高度**：高度限制為螢幕高度的 `50%` 至 `85%`，高於此限制時內部採用 `ListView` 滾動。

### 10.2 關閉與防殘影機制
- **關閉按鈕**：右上角恆常顯示一個 `Icons.close` 的 `EBIconButton`，為單手觸控提供明確退出入口。
- **E-Ink 模式**：禁用 Bottom Sheet 的「滑入/滑出」動畫，改為**瞬間淡入/淡出**或**直接具現化顯示**。

---

## 11. 導覽與響應式斷點模式 (Navigation Patterns)

為解決大平板上介面無限拉寬、以及分類下鑽導致書架堆疊無窮畫面的問題，建立基於 `AdaptiveScaffold` 的導覽模型。

### 11.1 導覽架構收斂

App 的主要導覽點收斂為三個常駐目的地：**「書架」**、**「來源」**、**「設定」**。

```
AdaptiveScaffold (根據螢幕寬度自適應)
├─ 手機 (Width < 600dp)   : 標題列右側圖示導覽（書架/來源/設定三個目的地），不使用底部導覽列
├─ 平板 (Width >= 600dp)  : 側邊導覽軌 (NavigationRail)
└─ 桌機 (Width >= 1024dp) : 側邊導覽軌 + 雙欄 Master-Detail 版面
```

手機寬度不用底部導覽列，是因為電子紙常駐一整排圖示比手機更浪費畫面，也不需要底部單手熱區；此決策**不分主題或 E-Ink 修飾子**，Light/Dark/Sepia 與 E-Ink 全部統一採用標題列圖示導覽，已於 `prototype/elinkbook_theme_prototype.html` 驗證。

三個目的地畫面的標題列，固定顯示「**另外兩個目的地**的圖示」＋「當下畫面專屬的動作圖示」：
- **書架**：☰ 排序/檢視（畫面專屬）、⇩ 來源、⚙ 設定。
- **來源**：▦ 書架、⚙ 設定。
- **設定**：▦ 書架、⇩ 來源。

### 11.2 書架分類格子與下鑽 (Drill-down) 導覽模式
- **保留**：保留先行程式的分類呈現方式，即頂層書架採用**分類格子（呈現 2x2 微縮封面拼貼）與獨立書籍（未分類書籍）混排**。
- **佈局規格**：書架網格**直排 3 欄、橫排 4 欄**（欄數固定）；每頁**列數**
  依裝置實際可用高度動態計算，矮/高裝置皆完整顯示整數列，不寫死「1
  行」（epic-36 Issue 7，詳見 §15.1）。每個分類格子佔用 1 欄，每本獨立書
  亦佔用 1 欄。
- **下鑽行為**：點擊分類格子時，在當前書架直接「下鑽」更新狀態，僅顯示該分類底下的所有書籍列表。頂部隨即出現「返回上層」的引導控制列，不再使用 `Navigator.push` 堆疊新畫面，徹底避免 AppBar 與功能按鈕的重複。
- **標題列圖示導覽為標準行為（非可選變體）**：手機寬度一律將「來源」「設定」入口收攏至 AppBar 右側圖示，不使用底部導覽列，騰出底部空間給書架的換頁控制列（`PagingBar`，定義見 §15.1），取代原先「無底部導覽變體」的可選描述，詳見 §11.1。

---

## 12. 閱讀器專屬元件與介面 (Reader-specific Components)

閱讀器畫面 (`ReaderScreen`) 新增 `ReaderChromeTopBar`／`ReaderChromeBottomBar` 取代兩套按鈕塔，將 EPUB 與 PDF 兩套重複的 chrome 合併為格式無關的統一控制列，並還原中文直排起讀點。

### 12.1 淘汰右側「浮動按鈕塔」
- **現狀問題**：右側 7 顆懸浮按鈕壓在內文上，破壞直排繁體中文的起讀邊界，且雙引擎各自寫死座標。
- **重構設計**：
  - 點擊螢幕中央熱區，觸發「沉浸模式」切換。
  - 喚醒介面時，僅在**頂部**與**底部**浮出兩條滿版 Chrome 控制列。
  - **頂部 Chrome Bar**：返回按鈕、書名與目前章節、內文搜尋按鈕、**顯示／隱藏工具列（⬓）按鈕**、書籤 Toggle 按鈕。
    - **⬓ 顯示／隱藏工具列**：點擊收合下方所有底部 Chrome 控制列（章節進度條、跳頁指示、目錄/劃線/版面/朗讀選單列，朗讀中則收合 TTS 面板），只留頂部 Chrome Bar 與內文，供長時間閱讀減少電子紙常駐刷新區域；再次點擊恢復顯示。此按鈕只切換 `_chromeVisible`，不讀寫 `showHeader`/`showFooter`（§17.1 顯示頁首／頁尾偏好僅控制邊角常駐文字，與此獨立）。
  - **底部 Chrome Bar**：
    - 第一列：直觀的章節進度條 (Slider/Stepper) 與跳頁指示。
    - 第二列：目錄按鈕、劃線筆記按鈕、版面設定按鈕、TTS 朗讀面板按鈕。

### 12.2 直排頁面標題與頁尾自適應
- **現狀問題**：直排時將橫排元件用 `RotatedBox` 轉 90 度，導致觸控與佈局軸向錯亂。
- **重構設計**：
  - 直排模式下，頁眉與頁尾改用專屬的直排佈局。
  - 頁首（書名）靠左垂直排列，頁尾（進度）靠右垂直排列，其字級固定為 `13sp`，字型跟隨閱讀偏好。

---

## 13. 語音朗讀 (TTS) 元件 (TTS-specific Components)

TTS 播放控制為常駐的 `TtsPanel`，與底部選單列 `ReaderChromeBottomBar` 依 `TtsController.status` 衍生互斥切換（不設手動旗標），確保章節播畢自動切回底部列，不需額外手動關閉。

### 13.1 TtsPanel (常駐朗讀面板)

`TtsPanel` 為 `StatelessWidget`，兩排固定結構：

- **展開控制列**（`isCollapsed` 為 `false` 時顯示；`isCollapsed` 為 `true` 時整排隱藏）：上一句／播放暫停／下一句／語速（循環 0.5x~2.0x，顯示如 `1.00x`）／語音選擇（呼叫 `TtsProvider.getAvailableVoices()` 即時清單，`RadioGroup` 單選，選擇後僅影響下一段合成，不寫入 `GlobalReaderPrefs.ttsVoiceId`）。
- **底層動作列**（恆常渲染，不受 `isCollapsed` 影響）：睡眠定時器（15/30/45/60 分＋不限時固定清單，到期為暫停非停止，不做逐秒倒數）／收合展開（`isCollapsed` 切換）／停止（呼叫 `TtsController.stop()` 真正停止並釋放音訊焦點）。

CBZ 為純圖像格式，無文字可朗讀，`TtsPanel` 僅顯示停用狀態的播放鍵（`onPressed: null`，由 `disabledForegroundColor` 提供視覺回饋），其餘四顆按鈕不渲染；CBZ 因沒有真正的 `TtsController`，改用獨立的 `_cbzTtsPanelVisible` 手動旗標控制展開/收合，不受一般格式衍生切換影響。

觸控目標依 §7.2：一般模式 52dp、E-Ink 模式 56dp；停止按鈕為強調色（`backgroundColor: iconColor` 反白樣式）。

### 13.2 背景播放與系統整合

系統通知欄／鎖定畫面／耳機線控透過 `TtsAudioHandler`（`audio_service` `BaseAudioHandler`）與 `TtsController` 橋接，`stop` 控制項呼叫真正的 `controller.stop()` 釋放音訊焦點，而非 `pause()`。

---

## 14. 劃線與備註元件 (Annotation Components)

### 14.1 畫線浮動工具列 (`SelectionToolbar`)
- **現狀問題**：寫死 256×104 幾何定位，導致超出右側螢幕或遮擋選取內容。
- **重構設計**：
  - 工具列寬度與高度依字級動態計算，邊緣箝制公式修正：
    $$\text{left} = \text{clamp}(\text{selection.rect.left}, 0.0, \text{screenWidth} - \text{toolbarWidth})$$
  - 選取框位於螢幕上半部時，工具列錨定於選取框下方；位於下半部時，錨定於上方。
  - **按鈕功能**：黃/綠/藍三色螢光筆按鈕、底線按鈕、新增備註按鈕、複製文字按鈕、刪除劃線按鈕，以及明確的「✕ 關閉」按鈕。

### 14.2 筆記面板 (`NotesSheet`)
- 由 `EBSheetShell` 包裹，採用雙分頁結構：
  - **分頁一：`Icons.bookmark_outline` 書籤**（列表顯示所有書籤與建立時間，支援點擊跳轉）。
  - **分頁二：`Icons.edit_note` 劃線與備註**（合併顯示劃線與備註，標示劃線色彩/底線樣式與備註內文，支援點擊跳轉與滑動刪除）。
- 分頁標籤一律搭配文字標籤，不使用 Emoji（舊版曾用 🔖／✏️ 作為分頁圖示，已淘汰）。

---

## 15. 圖書庫與書架元件 (Library Components)

### 15.1 書本卡片元件 (BookCoverTile) 與分類格子 (GroupTile)
- **繼續閱讀列**：搜尋列下方固定顯示一列「最近閱讀」，展示使用者最後一次閱讀的書籍與進度，點擊直接跳轉繼續閱讀；此列常駐不受下方分類/書籍格狀區域換頁影響。
- **混排格狀視圖 (Grid Layout)**：
  - 書架網格排版直排 3 欄、橫排 4 欄（欄數不變）；每頁**列數**依裝置實際
    可用高度動態計算（`libraryRowsForHeight()`，見 `library_paging.dart`），
    矮/高裝置皆完整顯示整數列，不寫死「1 行」、不留白、也不出現半截列
    跑版（epic-36 Issue 7）。分頁本身仍為離散換頁（`PagingBar`），不是
    捲動。
  - **分類格子 (GroupTile)** 與 **獨立書籍 (BookCoverTile)** 同時混排在網格中，每項各佔 1 欄。
  - 二者在格狀視圖中一律強制維持 **`3:4` 的高度/寬度比例**，以確保視覺網格對齊無暇。
- **分類格子 (GroupTile) 外觀**：
  - 內部呈現為 2x2 微縮封面拼貼，其佔位底色與 CJK 邊框遵循設計系統規範。下方顯示分類名稱（如「科幻(3)」），限制 1 行。
- **書籍卡片 (BookCoverTile) 外觀**：
  - 呈現單一書籍封面。下方文字區：書名 `15sp` 限制 `2 行`；閱讀進度百分比與「未下載」徽章合為一列，字級 `13sp`。
- **清單視圖 (List)**：
  - 分類與書籍以清單列混排展示。
- **換頁控制列 (PagingBar)**：書架格狀／清單視圖不使用無限捲動，底部常駐一條換頁控制列（‹ 上一頁／頁碼／下一頁 ›），高度最小 `52dp`，按鈕觸控目標依 §7.2：一般模式 `48dp`、E-Ink 模式 `56dp`。此列**所有主題與 E-Ink 修飾子下皆存在**，是書架瀏覽的標準行為、非 E-Ink 專屬——與 §18 第 4 項「設定列表與 OPDS 書單在 E-Ink 模式下啟用分頁滾動」是兩件不同的事：後者是 E-Ink 專屬、以整螢幕高度為單位的長清單捲動降級手法，適用範圍不含書架。
- **批次操作模式**：長按進入多選，頂部出現 AppBar 操作列，支援「批次移動分類」、「批次移除本機快取（限遠端書庫書籍）」與「批次刪除」。
- **單書動作選單**：點擊書本卡片上的「⋮」圖示（不使用長按——長按保留給批次選取，兩者不共用同一手勢）彈出由 `EBSheetShell` 包裹的該書專屬 Bottom Sheet：詳細資料、移動（分類）、版面覆寫、移除快取（限遠端書庫書籍，本機匯入的書籍此選項隱藏/停用，與批次版本規則一致）、刪除。

### 15.2 書架 AppBar 與搜尋
- **搜尋列集成**：在書架 AppBar 內嵌入一個點擊展開的 `SearchView`。
- **過濾條件**：支持即時依書名、作者進行關鍵字過濾。
- **動作減壓**：取消「＋」匯入按鈕與 FAB——匯入書籍（本機檔案／資料夾／雲端／OPDS）與「來源」目的地做的是同一件事，保留兩個入口只會讓使用者猜哪個才是正確的路，已完全併入「來源」目的地。AppBar 右側改放「排序/檢視」（`Icons.sort`/`Icons.view_list`）、「來源」（`Icons.cloud_download`，見 §6.1）、「設定」三個低干擾圖示，取代底部導覽列（見 §11.1）。

---

## 16. 來源管理元件 (Source Management Components)

「來源」目的地整合所有把書弄進來的方式，將本機檔案、雲端硬碟、OPDS 書庫統合成單一瀏覽與選取架構。

### 16.1 統一來源瀏覽器 (`SourceBrowser`)
- **架構設計**：
  ```
  SourceBrowser (統一 UI 框架，包含列出、搜尋、多選、下載佇列、行動數據警告)
  ├─ LocalFileProvider  (瀏覽本機儲存空間)
  ├─ GoogleDriveProvider (OAuth 認證與雲端瀏覽)
  ├─ OneDriveProvider   (OAuth 認證與雲端瀏覽)
  └─ OpdsServerProvider  (標準 OPDS / Calibre 伺服器，支援 HTTP Basic Auth)
  ```
- **麵包屑導覽 (Breadcrumbs)**：在 OPDS 或雲端目錄下鑽時，頂部常駐麵包屑導覽列（如 `首頁 > 歷史 > 羅馬帝國`），點擊可直接返回上層，不再於 Navigator 上堆疊多個畫面。

### 16.2 下載佇列與同步狀態
- **`DownloadQueueRow`**：在來源頁面底部常駐一個可展開的下載佇列面板，顯示「正在下載 x 本，剩餘 y 本」，並以「確定式進度條 (Determinate ProgressBar)」取代連續旋轉的 ProgressIndicator。
- **`SyncStatusChip`**（同步狀態晶片）：在書架右上角靠近內容處，顯示「已同步」或「同步中...」的微型晶片，點擊可立即手動觸發 PocketBase Checkpoint 同步。

---

## 17. 設定畫面元件 (Settings Components)

設定畫面 (`SettingsScaffold`) 分為四個區塊，依序排列，各區塊標題採用 `EBSectionHeader`。

### 17.1 分區與內容
1. **外觀**：E-Ink 高對比模式開關、佈景選擇（Light/Dark/Sepia 三選一）、字型管理入口。
2. **閱讀**：閱讀預設值、顯示頁首／頁尾開關（與閱讀器內 ⬓ 快速鍵讀寫同一份設定，見 §12）、翻頁與熱區、朗讀語音與語速。
3. **同步與帳號**：跨裝置同步狀態與手動觸發入口。
4. **關於**：版本資訊、授權；診斷功能（Console Log 等開發用項目）移至此區塊，藏在連點版號之後，不與一般設定項混列。

### 17.2 佈景選擇與 E-Ink 鎖定行為
- 佈景選擇只提供**單一選擇器**，同時套用於 Chrome 與 Page（不拆分兩個獨立選擇器）——雖然核心設計原則第 1 條允許 Chrome/Page 分開設定色彩，但為求好維護、降低使用者混淆，UI 上暫不開放兩者分開選。
- 當 E-Ink 高對比模式開啟時，佈景選擇器（無論在設定畫面或其他入口）一律**鎖住**：不可點擊，視覺上比照 §7.2 E-Ink 按壓反饋語彙——邊框加粗為 `3dp` 虛線（不使用「降低對比度」或灰階效果，E-Ink 色票僅有純黑純白，見 §1.1 與核心設計原則第 2 條，不引入 Token 系統未定義的灰階值），並顯示提示文字說明「這裡選的是關閉 E-Ink 後要恢復的主題」。E-Ink 關閉後畫面色彩才恢復成選擇的主題。仍保留 Semantics 標籤供螢幕報讀機（如 TalkBack）讀出鎖定狀態與目前底下選的是哪個主題，僅移除互動語意。

---

## 18. E-Ink 模式修飾與適配指引 (E-Ink Adaptations)

當 `ElinkTokens.isEink` 為 true 時，App 必須無條件啟用以下防殘影與高對比最佳化：

1. **零動畫轉場 (Zero Transitions)**：
   - 禁用所有 `MaterialPageRoute` 的滑動與漸變轉場。
   - 所有畫面切換、Bottom Sheet 彈出、Dialog 具現化，一律套用零時長（`Duration.zero`）的 `PageRouteBuilder`，實現瞬間切換。
2. **確定式進度 (Determinate Progress)**：
   - 禁用 `CircularProgressIndicator` 等無限旋轉的連續動畫。
   - 載入狀態一律改用 **骨架屏 (Skeleton Screens)** 或 **離散的百分比數值 (Determinate ProgressBar/Text)**，載入完成前畫面維持靜止。
3. **步進控制 (Stepper Control)**：
   - 禁用所有 Slider 元件。
   - 字級、字重、行邊距、TTS 語速、閱讀進度跳頁等控制項，一律自動替換為 **`EBStepper` (帶有 `-` 與 `+` 的離散點擊按鈕)**。
4. **離散翻頁與滾動 (Discrete Scrolling)**：
   - 設定列表與 OPDS 書單在 E-Ink 模式下，啟用「分頁滾動」，每次滑動以一個螢幕高度為單位進行整頁刷新。
5. **強制高對比線條**：
   - 所有輸入框、按鈕、卡片與 Dialog 邊界，在 E-Ink 模式下強制繪製 `1.5dp` 的純黑色邊框。

---

## 19. 重構與實作路線圖 (Roadmap)

重構將遵循「每一步都讓下一步更便宜」的原則，分階段推進：

### 階段一：Token 系統落地與色彩清理 (P0)
- 實作 `ElinkTokens` 擴充類。
- 補齊三套主題的 `ColorScheme`（解決淡紫外洩）。
- 搜尋並清理程式碼庫中所有寫死的 `Colors.grey/black45/white`，全部替換為語意色。

### 階段二：閱讀器 UI 與 TTS 重構 (P0)
- 拆分 `ReaderScreen` 的業務邏輯與 Chrome 介面。
- 淘汰右側按鈕塔，改為上下 Chrome Bar 控制列。
- 實作常駐型 `TTSMiniPlayer`，修正 TTS 關閉與狀態丟失問題。

### 階段三：基礎元件抽離與導覽架構 (P1)
- 抽離第 1 層基礎元件 (EBButton, EBSheetShell 等)。
- 導入 `AdaptiveScaffold`，將書架、來源、設定整合至單一主框架，手機寬度統一採標題列圖示導覽（見 §11.1）。
- 書架分類**維持**下鑽模式（見 §11.2），**不**改為 Filter Chip 篩選——修正：本節原先跟隨稽核報告建議改用篩選晶片，但與 §11.2「保留」的既有決策衝突；經確認後以 §11.2 為準，稽核報告該項建議不採納。
- 重構設定畫面為 §17 定義的四區塊結構（外觀／閱讀／同步與帳號／關於），含統一佈景選擇器與 E-Ink 鎖定行為。

### 階段四：來源管理與下載佇列 (P1)
- 整合 Local, Cloud, OPDS 瀏覽器至 `SourceBrowser`。
- 實作麵包屑導覽，解決目錄下鑽堆疊畫面問題。
- 補齊匯入失敗的詳細結果對話框（拒絕靜默 catch）。
