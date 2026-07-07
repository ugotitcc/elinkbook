# elinkBook

跨平台電子書閱讀器，核心差異化在於直排（vertical-RL）繁體中文排版與深度版面客製化。單一情境，全專案共用本詞彙表。

## Language

**主題（Theme）**：
三選一的全域閱讀色彩配置：深色（Dark）、羊皮紙（Sepia）、預設（Light）。跨書籍一致，不可單書覆寫。
_Avoid_: 外觀模式、色彩方案

**E-Ink 高對比模式**：
獨立於「主題」之外的全域布林開關，可與任一主題同時生效（例如「羊皮紙 + E-Ink 高對比」）；訴求是無障礙/E-Ink 裝置相容性（高對比、減少殘影），不是第 4 種主題選項。
_Avoid_: E-Ink 主題

**單書版面偏好設定（Book Reader Preferences）**：
單一書籍專屬的版面設定值（字型、行距、邊距、對齊、排版方向覆寫、螢幕方向覆寫、翻頁模式覆寫等），儲存於 `book_reader_prefs` 表（與 `books` 表 1:1，以 `book_id` 為外鍵）。
_Avoid_: 單書設定、閱讀器設定

**全域預設值（Global Default）**：
跨書籍生效的系統層級預設值（例如螢幕方向、翻頁模式），對應 PRD FR-37/FR-38；單書版面偏好設定可覆寫，未覆寫時回退至此值。目前無對應設定畫面（`epic-14-system-settings` 尚未開發），先以 `shared_preferences` 存放沿用現有行為的初始值。
_Avoid_: 系統設定、全域設定（兩者在 PRD 中另指 `epic-14` 的獨立系統設定畫面本身，容易與「全域預設值」這個資料層概念混淆）

**開書初始偏好（Initial Preferences）**：
`openBook` 契約新增的參數，讓已持久化的偏好設定（單書覆寫值或全域預設值解析後的結果）能在開書當下、`attachNavigator()` 成功後立即套用，不依賴 `didUpdateWidget` 的「值改變才觸發」機制。
_Avoid_: 初始設定、預設偏好
