# ADR 0006：`EpubReaderView` 契約改為批次偏好設定，並支援開書當下套用已持久化偏好

## 狀態

已採納

## 背景

Epic 2（ADR 0003／0004）建立的 `setWritingMode`／`setPageTurnMode` 模式有兩個隨 Epic 3 範圍擴大而浮現的問題：

1. **持久化設定在開書當下沒有真正套用**：目前偏好設定同步完全依賴 `didUpdateWidget` 偵測「值改變」才呼叫原生端 setter；若 `ReaderScreen` 建構當下就把狀態初始化為已持久化的值，`didUpdateWidget` 不會在首次建構時觸發，持久化設定會停留在 Dart 端 UI 顯示，但從未真正送達原生端套用（ADR 0004 已預留此缺口，見其「未來注意」段落）。
2. **一個維度一個方法不再具擴充性**：Epic 3 一次新增 8 個新的偏好維度（`fontFamily`/`fontSize`/`fontWeight`/`lineHeight`/`paragraphSpacing`/`pageMargins`/`textAlign`/`publisherStyles`），若比照既有慣例各自一個方法，`EpubReaderView.kt` 會新增 8 個結構幾乎一模一樣的方法，且 Dart 端 `didUpdateWidget` 也要對應新增 8 段比對邏輯。

## 決策

- **`openBook` 契約擴充**：簽章擴充為 `openBook(path, initialPreferences: Map<String, Any?>?)`。原生端 `attachNavigator()` 成功、`Publication` 就緒後，若 `initialPreferences` 非空，組出對應 `EpubPreferences`、`plus()` 合併進 `currentPreferences`，呼叫一次 `submitPreferences()`——不等待任何後續的 `didUpdateWidget` 觸發。
- **`setWritingMode`／`setPageTurnMode` 走入歷史，合併為單一 `setPreferences(Map<String, Any?>)`**：兩者視為 `setPreferences` 的特例，個別方法移除。Dart 端 `didUpdateWidget` 偵測到任一偏好欄位變動時，把**目前所有非 null 的偏好欄位**（不只是變動的那個）組成一個 map，透過這個單一方法送出；原生端統一組出對應 `EpubPreferences`、`plus()` 合併進 `currentPreferences`、呼叫 `submitPreferences()`。
- `initialPreferences` 與 `setPreferences` 使用同一組 map key 命名慣例，兩者邏輯高度共用（原生端可用同一段組裝 `EpubPreferences` 的程式碼服務兩個呼叫點）。
- `onPageRendered`/`onError`/`onLayoutResolved`（對外行為）既有契約簽章不變。

## 曾考慮的替代方案

- **維持一個維度一個方法**（`setFontSize`、`setLineHeight`……8 個新方法）：一致性高、每個方法職責單一明確，但程式碼重複量大，且未來每新增一個偏好維度都要重複這個模式；予以排除。
- **只解決「開書當下套用」缺口，不合併既有的 `setWritingMode`/`setPageTurnMode`**：會讓契約同時存在兩種風格（新欄位走批次 map、舊欄位走個別方法），對讀者造成不必要的認知負擔；既然要為新欄位設計批次機制，一併把既有兩個方法納入同一套機制，維護上更一致。

## 後果

- `EpubReaderView.kt` 移除 `setWritingMode`／`setPageTurnMode` 兩個既有方法，改為單一 `setPreferences`；呼叫端（Dart）程式碼需同步調整，不再有個別對應的方法呼叫。
- 新增/未來的偏好維度只需要在 map 裡新增一個 key、在原生端組裝邏輯裡新增一個對應分支，不需要新增新的 method channel 方法名稱與對應 Dart 呼叫端程式碼。
- `initialPreferences` 解決了 Epic 3 持久化設定「開書當下沒有真正套用」的核心缺口，此機制也回溯適用於既有的 `writingMode`/`pageTurnMode`（兩者的持久化覆寫同樣受惠於這個開書當下套用的機制）。
