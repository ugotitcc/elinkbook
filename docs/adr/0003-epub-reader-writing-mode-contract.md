# ADR 0003：`EpubReaderView` 契約擴充為雙向即時偏好設定

## 狀態

已採納

## 背景

`epic-0-skeleton` 建立的 `EpubReaderView` 原生契約是單次靜態開書：`openBook(path)` → `onPageRendered()`/`onError(message)`。開書之後，Dart 端無法再傳遞任何設定給原生端；原生端也只在開書當下呼叫一次 Readium API，之後不再與 Dart 端互動。

`epic-2-vertical-core` 需要讓使用者在閱讀中「一鍵切換」橫排／直排（FR-05），且切換須即時生效、不能要求使用者重新打開書本（沿用 `prototype/index.html` 既有的即時切換體驗）。這代表契約必須從「單次靜態開書」擴充為「開書後仍可持續下達指令、且原生端能主動回報狀態」的雙向溝通模式。

## 決策

擴充 `EpubReaderView` 契約，新增以下方法：

- **Dart → 原生**：`setWritingMode(mode: horizontal | vertical)`，可在書本開啟後任何時間點呼叫。原生端收到後組出 `EpubPreferences(verticalText = mode == vertical)`，呼叫 Readium navigator 的 `submitPreferences()` 即時套用，不重新載入書本。
- **原生 → Dart**：新增一次性回呼 `onWritingModeResolved(mode: horizontal | vertical)`，在 `openBook` 完成、Readium 透過 `EpubSettingsResolver.resolveVerticalText(null, language, readingProgression)` 自動判斷出初始模式後觸發，讓 Dart 端的切換 UI 能立刻顯示正確的初始狀態。
- 初次開書**不**主動設定 `verticalText`（保持 `null`），讓 Readium 依書本語言／閱讀方向自動判斷（對應 FR-06）；`setWritingMode` 只在使用者手動切換時才會覆寫這個自動判斷結果。
- `openBook`/`onPageRendered`/`onError` 既有行為與簽章不變。

## 後果

- `EpubReaderView.kt` 需要持有目前開啟中的 navigator 實例參照，供 `setWritingMode` 呼叫時使用（原本呼叫完 `openBook` 後即不再需要保留 navigator 參照，本次是新增的生命週期需求）。
- Dart 端 `EpubReaderView` widget 需要新增對應的 method channel 呼叫封裝與 `onWritingModeResolved` 回呼轉發；`ReaderScreen` 是否需要往外暴露這個能力（例如以 controller 物件形式），或僅在 `ReaderScreen` 內部管理切換按鈕狀態，於 `spec.md` 定義。
- `PdfReaderView` 不受影響（PDF 無 writing-mode 概念，契約不變）。
- `integration_test/` 需要新增涵蓋「開書後呼叫 `setWritingMode` 並驗證畫面重新渲染」的案例，不能只測開書當下的靜態渲染。
- 這是對 `epic-0-skeleton` 已定案 seam 的擴充而非取代——`openBook` 的既有呼叫方式與行為完全不變。

## 曾考慮的替代方案

- **偏好設定寫入本機設定、切換時整個重新 `openBook`**：不需要讓原生端持有 navigator 參照、實作最單純，但每次切換都要重新載入整本書（含重新解析、重新渲染），使用者體感是「重新開書」而非「即時切換」，與 PRD 的「一鍵切換」及 `prototype/index.html` 既有的即時切換體驗不符，予以排除。
- **在 Dart 端自行解析 EPUB metadata 判斷初始模式，原生端只負責被動接收 `setWritingMode`**：會讓 Dart 端重新實作一次 Readium 原生已內建的 `EpubSettingsResolver.resolveVerticalText` 邏輯，違反專案「不重新發明 Readium 已提供的能力」的技術棧決策，予以排除。
