# PocketBase 同步帳號架構：自架可設定 base URL、email+password、Token 加密儲存

`epic-8-sync`（雲端同步，對應 FR-19/20/30）需要引入一個全新的帳號/後端整合層，目前專案完全沒有任何帳號或網路相依套件。決策如下：

1. **PocketBase base URL 由使用者自行輸入、可設定，非寫死在 App 內的單一官方端點**（Settings「同步」子頁面提供伺服器網址欄位，預設帶一組官方 URL、可改）。理由：專案要交付一份 PocketBase 自架 SOP，若 App 端寫死網址，自架文件就沒有意義；產品定位本來就強調去中心化、使用者自主（不做電子書商店/租閱），自架同步伺服器與此調性一致；開發/測試也需要能切換不同 PocketBase 實例。
2. **登入方式只做 email + password（PocketBase 內建），不做任何 OAuth 第三方登入**（Google/Apple 等）。理由：目標裝置明確涵蓋無 Google Play Services（GMS）的 E-Ink 閱讀器（PRD FR-02 已有相同顧慮的先例），OAuth 尤其 Google Sign-In 在無 GMS 環境常整個不能用或需另接 Web-based fallback；email+password 開箱即用，不需要額外 SDK 相依。
3. **認證憑證（PocketBase auth token）改用 `flutter_secure_storage`（Android Keystore／iOS Keychain 加密儲存），不沿用既有的明文 `SharedPreferences`**。這是專案首次引入任何「安全性相關」儲存機制，僅限這一項敏感憑證，其餘既有偏好設定用途不變、不做全面遷移。
4. **同步帳號完全可選（opt-in）**：不登入也能完整使用 App 所有既有單機功能，與產品現況（零帳號概念、單機優先）一致。

## Considered Options

- 寫死單一官方 PocketBase 端點（類似 SaaS 模式）——與「要交付自架 SOP」的前提矛盾，放棄。
- OAuth（Google Sign-In）作為登入方式之一——因無 GMS 環境相容性疑慮而不採用；未來若有需求可再增量擴充，不影響現有帳號資料模型。

## Consequences

- 需要在 Settings 新增「同步」子頁面，含 base URL／帳密欄位與「測試連線」按鈕（驗證組合可連通）。
- `pubspec.yaml` 新增 PocketBase SDK（或等效 HTTP client）與 `flutter_secure_storage` 兩項全新依賴。
