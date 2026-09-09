# Design Tokens — `elinkbook_theme_prototype.html` 反向萃取

> 分析對象：`prototype/elinkbook_theme_prototype.html`（唯一權威來源，見 `CLAUDE.md`）
> 對照基準：`DESIGN.md`（已定義色彩／字體／間距／圓角／陰影／圖示等完整 Token 系統）
> 方法論：**這不是從零建立 Token，而是一份一致性稽核**——`DESIGN.md` 已有的 Token 定義照抄引用，本文件的價值在於標出「原型實際渲染值 vs `DESIGN.md` 定義值」是否相符。✅ = 相符／⚠️ `[CONFLICT]` = 不符／➕ `[INFERRED]` = `DESIGN.md` 未定義、原型獨有的資訊／❓ `[UNKNOWN]` = 原型也沒有示範，資訊不足。
> 顏色 Token 依 Grilling 階段共識，不重新從 CSS 反推，直接引用 `DESIGN.md` §1，僅核對原型渲染值是否與其一致。

---

## 1. Colors

`DESIGN.md` §1.1／§1.2 是唯一權威定義。原型（`<style>` 第 43–71 行）只用 CSS 變數實作了 **5 個角色**（`surface`／`on-surface`／`outline`／`primary`／`on-primary`），透過重新導向 Tailwind 的 `bg-white`/`text-black`/`border-black`/`bg-black`/`text-white`/`border-white` 六個既有寫死類別實現換色，畫面 markup 完全不用改。

| Token | 原型 CSS 變數 | 原型實際值 | `DESIGN.md` §1.1 定義值 | 相符？ | Usage |
|---|---|---|---|---|---|
| `color.primary` (Light) | `--color-primary` | `#0284c7` | `#0284c7` | ✅ | 主色（黑白反色映射的來源，`bg-black`→此值） |
| `color.onPrimary` (Light) | `--color-on-primary` | `#ffffff` | `#FFFFFF` | ✅ | `text-white` 映射 |
| `color.surface` (Light) | `--color-surface` | `#ffffff` | `#FFFFFF` | ✅ | `bg-white` 映射 |
| `color.onSurface` (Light) | `--color-on-surface` | `#0f172a` | `#0f172a` | ✅ | `text-black` 映射 |
| `color.outline` (Light) | `--color-outline` | `#cbdfe9` | `#cbdfe9` | ✅ | `border-black` 映射 |
| `color.primary` (Dark) | `--color-primary` | `#38bdf8` | `#38bdf8` | ✅ | |
| `color.onPrimary` (Dark) | `--color-on-primary` | `#141416` | `#141416` | ✅ | |
| `color.surface` (Dark) | `--color-surface` | `#1d1d22` | `#1d1d22` | ✅ | |
| `color.onSurface` (Dark) | `--color-on-surface` | `#f2efe6` | `#f2efe6` | ✅ | |
| `color.outline` (Dark) | `--color-outline` | `#2c2c34` | `#2c2c34`（規範值） | ✅ 對規範值 | ⚠️ 見下方「已知風險」——這是 `DESIGN.md` 理想值，不是目前 Flutter 正式程式碼實際使用的值 |
| `color.primary` (Sepia) | `--color-primary` | `#b8362d` | `#b8362d` | ✅ | |
| `color.onPrimary` (Sepia) | `--color-on-primary` | `#ffffff` | `#FFFFFF` | ✅ | |
| `color.surface` (Sepia) | `--color-surface` | `#faf3e3` | `#FAF3E3` | ✅ | |
| `color.onSurface` (Sepia) | `--color-on-surface` | `#1f2022` | `#1f2022` | ✅ | |
| `color.outline` (Sepia) | `--color-outline` | `#e6dfcb` | `#e6dfcb` | ✅ | |
| `color.*` (E-Ink) | 全部 | `primary/outline/onSurface`=`#000000`，`surface/onPrimary`=`#ffffff` | 同左 | ✅ | E-Ink 修飾子選擇器 `[data-eink="on"]` 優先權最高，強制覆蓋 |

**已知風險（`DESIGN.md` 表格值 vs 正式 Flutter 程式碼實測值衝突，見 `docs/epics/epic-35-design-system-tokens/design.md`）**：Dark 主題的 `outline`／`surfaceContainerHighest` 兩角色，`epic-35` 因電子紙真機可辨識度實測，正式程式碼刻意採用 `#86868F`／`#3C3C44`（比 `DESIGN.md` 表格值亮得多），未採用 `DESIGN.md` 表格值（`#2c2c34`／`#19191d`）。**這份原型的 Dark 主題 `outline` 用的是 `DESIGN.md` 表格值 `#2c2c34`，不是正式 App 目前實際顯示的 `#86868F`**——若之後要拿這份原型的視覺當「目前 App 長什麼樣子」的參考依據，Dark 模式的邊框對比度會比正式 App 淡，屬於已知落差，不是原型錯誤。

**`DESIGN.md` 定義但原型未實作的角色（"Not defined in prototype"）**：
- `primaryContainer`／`onPrimaryContainer`／`onSurfaceVariant`／`error`／`surfaceContainerHighest`（原型合併簡化進 `surface`，未獨立變數）／`scaffoldBackground`（原型合併進 `surface`，未獨立區分卡片背景與畫面底色）。
- `ElinkTokens` 全部 8 個語意色（`highlightYellow`／`highlightGreen`／`highlightBlue`／`underlineColor`／`progressTrack`／`coverPlaceholder`／`badgeScrim`／`ttsActiveHighlight`）——這份原型沒有任何劃線／備註／封面佔位符／TTS 高亮的畫面示範，全部 `[UNKNOWN]`。

**原型侷限（`[INFERRED]`）**：原型的换色機制是「攔截 6 個寫死的黑白 Tailwind 類別、重新導向 CSS 變數」，而非真正逐一元件套用語意色角色——例如 `border-black` 統一導向 `outline`，但 `DESIGN.md` 裡有些邊框情境語意上其實該用 `onSurface`（純黑純白對比用途）而非 `outline`（分隔線用途，通常較淡）。這個簡化手法在原型demo階段可行，但不能直接當作「`outline` 就是唯一邊框色角色」的證據——原型受限於「六類別攔截」機制，天生無法區分這兩種語意，屬於方法論侷限，不是刻意的設計決策。

---

## 2. Typography

`DESIGN.md` §2.1 定義 `EBTextTheme`（7 級，sp 為單位）。原型未自訂 Tailwind `fontSize`（`tailwind.config` 只擴充了 `borderWidth`），一律用 Tailwind 預設字級尺標 + 少量任意值（`text-[9px]`/`text-[10px]`/`text-[11px]`）。

| `EBTextTheme` (`DESIGN.md` §2.1) | 定義值 | 原型對應 Tailwind class | 原型實際 px | 相符？ | 原型實際 Usage |
|---|---|---|---|---|---|
| `display` | 32sp / 1.3 | 無使用 | — | ❓ `[UNKNOWN]` | 原型沒有「書名詳細頁」這類大標題畫面 |
| `titleLarge` | 20sp / 1.4 | `text-xl` | 20px | ✅ | AppBar 標題（書架/來源/設定/版面設定的畫面標題「書架」「來源」等） |
| `titleMedium` | 16sp / 1.5 | `text-base` | 16px | ✅ | 較少見，僅螢幕方向切換按鈕（開發工具，非 App UI） |
| `bodyLarge` | 15sp / 1.6（§2.2 明訂「書架書名」用途，且規定不低於 15sp） | `text-sm` | **14px** | ⚠️ `[CONFLICT]` | 書架格狀書名（`<span class="text-sm font-bold line-clamp-2...">失落的百年致富聖經</span>`，第 254 行）用 14px，比 `DESIGN.md` §2.2 明訂的「書架書名字級不低於 15sp」少 1px |
| `bodyMedium` | 14sp / 1.6 | `text-sm` | 14px | ✅ | Sheet 選項標籤（步進器列標題「字級」「行距」等）、對話框內文 |
| `labelMedium` | 13sp / 1.5 | 無精確對應 | — | ❓ `[UNKNOWN]` | 原型最接近的是 `text-xs`(12px)，但 `DESIGN.md` 定義 13sp 專門用於「書頁進度與章節名稱」，原型該處實際用的是 `text-xs`，見下一列 |
| `labelSmall` | 11sp / 1.4 | `text-xs`（12px）與任意值 `text-[11px]` 皆有出現 | 11px／12px 混用 | ⚠️ `[CONFLICT]`（不一致） | 章節名稱／頁碼列（`184 / 468 · 39%`）用 `text-xs`=12px；字級步進器旁註解（「此書覆寫」「使用全域預設」）用 `text-[11px]`／`text-[10px]` 混用，同語意層級的文字在原型內部尺寸就不一致 |
| （`DESIGN.md` 未定義的更小尺寸） | — | `text-[10px]`／`text-[9px]` | 10px／9px | ➕ `[INFERRED]` | 進度百分比徽章、分類拼貼格「分類」角標、版面覆寫提示小字。**兩者都小於 `DESIGN.md` 定義的最小字級 `labelSmall`=11sp**——`DESIGN.md` 目前沒有涵蓋這個更小的微型標籤層級，是規格書的缺口，不是原型的錯誤，需要人類決定：(a) 補一個新 token（例如 `labelTiny`≈10sp）(b) 一律拉高到 `labelSmall`=11sp |

**字重（Font Weight）**：`DESIGN.md` 未定義字重 Token 系統。原型實際使用 `font-medium`(500)／`font-semibold`(600)／`font-bold`(700)／`font-black`(900) 四級，且用法有明確語意傾向：`font-black` 幾乎專用於標題／強調數值（AppBar 標題、字級數值、選中的分頁籤），`font-bold` 用於一般互動文字（按鈕、清單項目），`font-medium` 僅用於次要說明小字。➕ `[INFERRED]`：這是原型獨有、`DESIGN.md` 未涵蓋的資訊，建議之後補一個 `EBFontWeight` token 分級。

**Font Family（字型家族）**：❓ `[UNKNOWN]` / 未實作。原型完全沒有 `@font-face` 宣告，UI 文字用 `font-sans`（Tailwind 預設 sans-serif 堆疊）、閱讀器內文用 `font-serif`（Tailwind 預設 serif 堆疊），皆為瀏覽器通用字型，**不是**產品實際的 5 款內建 CJK 字型（思源黑體／思源宋體／原俠正楷／台灣圓體／源流明體）。`layout-tab-text` 分頁的「字型」步進器（`cycleFont()`）只是循環切換一個顯示文字字串，沒有真的套用對應 `font-family` CSS——換字型在畫面上完全沒有視覺變化。這是原型的已知侷限，字型視覺無法從這份原型反推。

**CJK 安全行高**：`DESIGN.md` §2.2「操作介面中文行高一律不低於 1.5」。原型多數文字區塊未顯式設定 `leading-*`（沿用 Tailwind text-size 配對的預設行高，符合或超過 1.5），少數明確覆寫：直排閱讀內文 `leading-[1.95]`（✅ 符合「閱讀頁內文字體行高預設 1.6」以上）、書名 `leading-tight`(1.25)／`leading-snug`(1.375) ⚠️ `[CONFLICT]`——書架格狀書名區塊用 `leading-tight`，低於 §2.2「操作介面中文行高不低於 1.5」的規定；但書名本身是否算「操作介面文字」還是「內容展示文字」，`DESIGN.md` 未明確定義邊界，需人類確認這條規則是否適用於書名。

---

## 3. Spacing

`DESIGN.md` §3 定義 `EBSpace`（4dp 步進）：`none`=0／`xxs`=2／`xs`=4／`sm`=8／`md`=12／`lg`=16／`xl`=24／`xxl`=32／`maxContentWidth`=680。

原型實際使用的 Tailwind spacing（`p-*`/`gap-*`/`space-y-*`，1 單位=4px）：

| 原型實際值 (px) | 出現的 Tailwind class | 對應 `EBSpace` | 相符？ | 原型 Usage |
|---|---|---|---|---|
| 6px | `gap-1.5`／`space-y-1.5` | 無對應（介於 `xs`=4 與 `sm`=8 之間） | ⚠️ `[CONFLICT]` | 大量使用：分類/書籍卡片內部垂直堆疊、AppBar 圖示群組間距 |
| 8px | `gap-2`／`space-y-2` | `sm` | ✅ | E-Ink 開關區塊、麵包屑元素間距 |
| 10px | `p-2.5`／`gap-2.5`／`space-y-2.5` | 無對應（介於 `sm`=8 與 `md`=12 之間） | ⚠️ `[CONFLICT]` | 大量使用：步進器列 padding、呈現分頁三態按鈕群組 gap、預設集卡片內距 |
| 12px | `p-3`／`gap-3`／`space-y-3` | `md` | ✅ | 側欄 padding、繼續閱讀列 gap、來源清單項目 gap |
| 14px | `p-3.5`／`space-y-3.5` | 無對應（介於 `md`=12 與 `lg`=16 之間） | ⚠️ `[CONFLICT]` | 來源清單項目左右 padding、版面設定分頁內容垂直節奏 |
| 16px | `p-4`／`gap-4`／`space-y-4` | `lg` | ✅ | 版面設定分頁內容 padding、書籍長按動作項目、來源畫面各區塊間距 |
| 24px | `p-6`／`gap-6` | `xl` | ✅ | 模擬器外層 padding（開發工具，非 App）、書架換頁列按鈕間距 |

**系統性發現**：原型大量使用 `6px`／`10px`／`14px` 三個值，這三者精準地落在 `EBSpace` 相鄰兩級的**中點**（`xs`(4)/`sm`(8) 中點=6、`sm`(8)/`md`(12) 中點=10、`md`(12)/`lg`(16) 中點=14）。這不像隨機誤差，比較像是原型作者覺得 `EBSpace` 的 4dp 級距對「按鈕/卡片內部緊湊排版」而言太粗，手動加了一層半階間距。**這是需要人類決定的規格缺口**：(a) 承認這是真實需求，在 `EBSpace` 新增 `xs5`=6／`sm5`=10／`md5`=14 半階 token；(b) 判定原型這樣用不對，未來 Flutter 實作一律歸整到最近的 4dp 級距（10px→`sm`=8 或 `md`=12，二擇一）。

**`maxContentWidth`=680**：❓ `[UNKNOWN]`——原型的「橫排」模擬寬度只到 640px（見下方 Screen Layout 章節），從未達到平板等級寬度，這個 token 完全沒有被原型示範到。

---

## 4. Border Radius

`DESIGN.md` §4 定義 `EBRadius`：`sm`=8（按鈕/小卡片/封面/輸入框）／`md`=16（Dialog/卡片/分類格子）／`lg`=28（Bottom Sheet 頂部/TTS 懸浮列）。`tailwind.config` 未自訂 `borderRadius`，沿用 Tailwind 預設尺標。

| 原型實際 class | 實際值 | 對應 `EBRadius` | 相符？ | Usage |
|---|---|---|---|---|
| `rounded` | 4px（Tailwind 預設 `DEFAULT`） | 無對應，小於 `sm`=8 | ⚠️ `[CONFLICT]` | 來源畫面麵包屑文字 pill |
| `rounded-md` | 6px（Tailwind 預設） | 無對應，小於 `sm`=8 | ⚠️ `[CONFLICT]` | **幾乎全部**互動元件：按鈕、輸入框、卡片、Dialog 式的長按動作 Sheet 項目、Tab 按鈕 |
| `rounded-full` | 9999px（圓形/膠囊） | 無對應（`EBRadius` 未定義 pill token） | ➕ `[INFERRED]` | Switch 開關軌道與圓點、側欄主題色點 |
| `rounded-[24px]` | 24px | — | — | 僅用於開發工具的手機外框模擬（`#emulator-screen` 橫向模式），非 App UI 內容，不列入分析範圍 |

**重大衝突**：原型**完全沒有用到** `EBRadius.sm`(8)／`md`(16)／`lg`(28) 這三個定義值中的任何一個——按鈕與卡片全部是 6px（`rounded-md`），比 `DESIGN.md` 最小的 `sm`=8 還小 25%。這不是單一元件個案，是原型全域一致的圓角尺標，需要人類確認：是 `DESIGN.md` 的 8/16/28 三階定案前的舊版視覺習慣殘留（原型底稿沿用 `eink_redesign_prototype.html`，早於 `DESIGN.md` 定案），還是 `EBRadius.sm` 這個值本身需要重新檢討。

**Bottom Sheet 頂部圓角（`EBRadius.lg`=28）具體缺口**：書籍長按動作 Sheet（`#book-action-sheet`，第 323–336 行）容器類別為 `bg-white border-t-2 border-black flex flex-col flex-shrink-0`——**沒有任何 `rounded-t-*` class**，頂部是直角，不是 `DESIGN.md` §10.1 規定的圓角 Bottom Sheet。同時也沒有 §10.1 規定的「頂部居中 32×4dp 拖曳把手」元素。這兩點在 `COMPONENT_SPEC.md` 的 `BookActionSheet` 一節有詳細記錄。

---

## 5. Shadows / Elevation

`DESIGN.md` §5 定義 `EBElevation`：`none`=0（E-Ink 強制）／`sm`=2（一般卡片、懸浮操作列）／`md`=4（Dialog、Bottom Sheet）。§8.1 進一步規定 Light/Dark/Sepia 非 E-Ink 主題下，書架卡片應為「Elevated Card」（有陰影），E-Ink 模式才降級為「Outlined Card」（純邊框）。

**重大衝突**：原型內 `#emulator-screen` 範圍（App 畫面本身）**完全沒有使用任何 `shadow-*` class**，不論目前選的是 Light／Dark／Sepia 或 E-Ink——書籍卡片、分類格子、對話框式的長按動作 Sheet、按鈕，全部只用 `border-[1.5px] border-black`（換色後對應 `outline` 角色）表現邊界，沒有陰影。

僅有的兩個 `shadow-*` 用例都在開發工具外殼、不屬於 App 畫面：`shadow-2xl` 是手機外框模擬器邊框裝飾，`shadow-lg` 是系統通知 Toast 浮層。

**根本原因（`[INFERRED]`，非猜測，有原型自身註解佐證）**：原型第 73–77 行明確註解「既有畫面全部是用 Tailwind 寫死的 `bg-white`/`text-black`/`border-black`... 六個類別在畫的（**因為原本只做純黑白 E-Ink**）」——這份原型的視覺底稿沿用自 `eink_redesign_prototype.html`（純黑白 E-Ink 版），主題系統只是把這 6 個寫死類別重新導向 CSS 變數換色，**並未針對 Light/Dark/Sepia 非 E-Ink 主題重新設計 Elevated Card 樣式**。也就是說，**這份原型從頭到尾只示範了 `DESIGN.md` §8.1 的「Outlined Card」變體，從未示範過「Elevated Card」變體長什麼樣子**——即使切到 Light 主題也一樣。這是留給 Flutter 實作階段的真空地帶，需要人類決定：Elevated Card 的陰影具體視覺效果要另外設計，不能從這份原型反推。

**Flutter 近似對應建議**（不是原型示範內容，是本文件根據 `DESIGN.md` 數值給的 Flutter 落地建議，供之後參考）：`EBElevation.sm`(2) 建議對應 `Card(elevation: 2)` 或 `BoxShadow(blurRadius: 4, offset: Offset(0,1), color: Colors.black.withOpacity(0.08))`；`EBElevation.md`(4) 建議對應 `Card(elevation: 4)` 或約 `BoxShadow(blurRadius: 8, offset: Offset(0,2))`。**不要直接把 HTML box-shadow 語法套進 Flutter**——原型根本沒有 box-shadow 可供轉換，這兩個近似值純粹是依 Material 3 elevation-to-shadow 慣例換算，需要之後在真實 Flutter 環境試做確認觀感。

---

## 6. Border

| 屬性 | 原型實際值 | `DESIGN.md` 對應規定 | 相符？ |
|---|---|---|---|
| 一般模式邊框寬度 | `border-[1.5px]`（`tailwind.config` 自訂擴充 `borderWidth['1.5']`） | §1.1 `outline` 備註「邊框 ≥ 1.5dp」（E-Ink 語境）、§18 第 5 項「強制高對比線條...1.5dp 純黑色邊框」（同為 E-Ink 語境） | ⚠️ 部分衝突——`DESIGN.md` 把 1.5dp 邊框明確定位為 **E-Ink 模式專屬**的強制規則，但原型**不分主題**、Light/Dark/Sepia/E-Ink 全部統一使用 1.5px 邊框，等於把 E-Ink 專屬視覺規格套用到所有主題。需人類確認：這是刻意的「全主題統一邊框語彙」設計決策（且尚未寫進 `DESIGN.md`），還是原型繼承自純 E-Ink 底稿、尚未依主題差異化的殘留 |
| 強調/分隔邊框寬度 | `border-2`（AppBar 底部分隔線、視覺頁碼列頂部分隔線） | 未定義對應 token | ➕ `[INFERRED]` | 原型用「較粗的 2px 邊框」表示區塊主分隔線（AppBar 與內容區之間），「較細的 1.5px」表示元件內部邊界，形成一個未寫入 `DESIGN.md` 的雙層邊框寬度語彙 |
| 邊框樣式 | 全部 `solid` | 同左，除 §17.2 E-Ink 鎖定佈景選擇器要求「3dp 虛線」 | ⚠️ `[CONFLICT]` | 見下方「E-Ink 鎖定」說明 |
| 邊框顏色 | 一律對應 `outline`／`onSurface` 角色（透過六類別攔截機制，見「Colors」章節說明） | — | — |

**E-Ink 鎖定佈景選擇器的邊框衝突（`COMPONENT_SPEC.md` `ThemeSelector` 一節有完整細節）**：`DESIGN.md` §17.2 明訂 E-Ink 開啟時佈景選擇器要「邊框加粗為 3dp 虛線」且「不使用降低對比度或灰階效果」。原型的側欄主題按鈕（`applyThemeState()`，第 920–943 行）與設定畫面佈景圓點，E-Ink 鎖定時做的是 `btn.style.opacity = '0.35'`——**降低不透明度**，正是 `DESIGN.md` 明文禁止的手法，且沒有改用虛線邊框。這與 `epic-35-design-system-tokens` 的 `design.md` 記載的、正式 Flutter 程式碼曾經犯過同一個錯誤（`settings_screen.dart` 舊版用 `Opacity(0.4)`，已列入 `epic-35` Issue 3 修正範圍）完全一致——**代表這份「用完即丟」的原型本身也還沒套用 `DESIGN.md` 自己訂的這條規則**，不是 Flutter 落後於原型，而是原型跟 Flutter 舊版犯了同一個錯。

---

## 7. Iconography

原型完全沒有使用 SVG 或 icon font（例如 Material Icons webfont、Font Awesome），所有圖示都是 **Unicode 字元**（`☰`／`⇩`／`⚙`／`⌕`／`‹`／`›`／`✕`／`⚑`／`✎`／`Aa`／`◗`／`☁`／`▥`／`▤`／`▣`／`⬓`／`▦`／`⏮`／`⏸`／`▶`／`⏭` 等），部分位置用純文字（「Aa」代表版面設定、字型循環按鈕用「▾」）。

| HTML 實際符號 | 語意用途 | `DESIGN.md` §6.1 規範 Icon（Flutter） | 對應風險 |
|---|---|---|---|
| `⚑` | 書籤 | `Icons.bookmark`／`Icons.bookmark_border` | 低——語意明確，Flutter 已有明訂圖示 |
| `✎` | 劃線與備註 | `Icons.edit_note` | 低 |
| `☰` | 目錄／排序切換（原型中一魚兩吃：書架 AppBar 用於「排序/檢視」，閱讀器用於「目錄」——**同一符號在原型內兩種語意並存**） | `Icons.toc`／`Icons.list`（目錄）vs `Icons.sort`／`Icons.view_list`（排序/檢視） | ⚠️ 中——原型用同一個 Unicode 符號表示兩種不同語意，Flutter 化時必須依畫面情境選用不同圖示，不可直接照搬「看起來像什麼」 |
| `⚙` | 設定 | `Icons.settings` | 低 |
| `⇩` | 來源／下載 | `Icons.cloud_download` | 低 |
| `⬓` | 顯示/隱藏工具列（沉浸模式切換） | `Icons.fullscreen`／`Icons.fullscreen_exit` | 中——`DESIGN.md` §12.1 這顆按鈕語意是「切換 Chrome 顯示/隱藏」而非「全螢幕系統列」（兩者是 `CONTEXT.md` 明確區分的不同概念），但規範圖示對照表把 `fullscreen` icon 分配給「全螢幕/沉浸式切換」這個籠統類別，Flutter 化時要小心別把這顆按鈕誤接到「全螢幕模式」（系統列開關）功能上，應接「沉浸模式」 |
| `Aa` | 版面設定入口 | 無對應規範 | ➕ `[INFERRED]`——`DESIGN.md` 圖示對照表沒有列「版面設定」這個功能，需要新增，建議 `Icons.format_size` 或 `Icons.tune` 類 |
| `◗` | 朗讀（TTS）入口 | 無對應規範 | ➕ `[INFERRED]`——同樣未列於 `DESIGN.md` 對照表，建議 `Icons.record_voice_over` 或 `Icons.volume_up` |
| `☁` | 雲端服務（Google Drive/OneDrive） | 無對應規範 | ➕ `[INFERRED]` |
| `▥`／`▤`／`▣`／`▦` | 分別代表 OPDS/Calibre、選擇檔案、選擇資料夾、書架檢視切換 | 無對應規範 | ➕ `[INFERRED]` |
| `›`／`‹` | 前進/返回 chevron | 無對應規範，但屬 Flutter 標準慣例 `Icons.chevron_right`／`Icons.chevron_left` | 低 |

**圖示尺寸與觸控目標**：`DESIGN.md` §6.2 規定圖示視覺 24dp、容器觸控目標最小 48dp（E-Ink 56dp）。原型的圖示按鈕實際容器多為 `w-11 h-11`(44px) 或 `w-12 h-12`(48px)，**44px 版本小於 `DESIGN.md` 規定的 48dp 下限**，例如 AppBar 排序/來源/設定三個按鈕（`w-11 h-11`，第 177–179 行）。⚠️ `[CONFLICT]`，詳細清單見 `COMPONENT_SPEC.md` 各元件的 Dimensions 小節。

**Emoji 使用**：`DESIGN.md` §6.2「分頁籤、按鈕等控制項文字旁嚴禁使用 Emoji」。原型除了上述 Unicode 符號圖示外，程式碼註解與 `showNotification()` 提示文字內有 emoji（如 `☁️`／`🔖`），但這些都不是畫面上常駐顯示的 UI 元素（是模擬通知的一次性 Toast 文字），不算違反此規則；真正常駐的分頁籤（版面設定「文字/邊界/呈現/預設集」）確實只用純文字，符合規範。
