# ADR 0037：依賴按使用者分組，以單一物件經建構子傳遞

## 狀態

已採納（2026-10-05）。取代 ADR 0007 中「依賴以建構子參數逐欄往下傳」的做法，以及 epic-26 Issue 7 的 bundle 切法。ADR 0007 的其餘決定（`bookId` 契約、不用 service locator）不變。

## 背景

依賴由 `main.dart` 建構後，經 `ElinkBookApp` → bundle → 各畫面逐欄展開再重組：`ElinkBookApp` 約 39 個欄位、`ReaderScreen` 28 個參數（其中 17 個是 repository／service，全部 nullable）、`SettingsScaffold` 22 個參數。`reader_screen.dart` 在「閱讀器→單書搜尋」流程中還要用 `widget.*` 手動逐欄重建 `LibraryReaderFeatureRepositories`。

這造成同一類缺陷反覆出現：新增欄位時，某一層漏轉送，編譯器抓不到（nullable 讓漏轉送變成執行期靜默失效）。epic-26 Issue 7 曾把 `LibraryScreen` 的參數收斂成 5 個 bundle，但 bundle 只是欄位集合，沒有改變「逐層展開重組」，之後仍漏轉發 `computeFingerprint`、`ttsDegradedNotice` 等欄位。

測試端也受 nullable 影響：測試只傳需要的參數，其餘靠省略，讓「缺依賴」在正式環境與測試環境行為不同。

## 決策

1. 依賴按「誰在用」分成四組：`ReaderFeatureDependencies`（閱讀器功能，含 `libraryRepository`、`importService`、`prefsManager`）、`SyncDependencies`、`SourceDependencies`（雲端／遠端來源）、`AppearanceDependencies`。容器 `AppDependencies` 持有四組，只在 `main.dart` 與根部使用。
2. 畫面以建構子接收所需的那一組（單一物件），不再逐欄接收。開書路徑（`LibraryScreen`、搜尋畫面、`BookSearchScreen`）整組轉傳同一個實例。
3. 組內的 repository、service、tracker 與函式型依賴（例如 `onManualSync`、`computeFingerprint`）一律 non-null required。真正可能缺席的能力（TTS 引擎、全文檢索）以明確的「不可用」adapter 或旗標表示，不用 null。
4. 測試使用 `test/support/` 的工廠建立預設全是 fake 的依賴組，只覆寫情境需要的欄位。正式與測試是兩個 adapter，seam 成立。
5. 不引入 DI 套件，也不使用 `InheritedWidget`；依賴仍顯式出現在建構子簽名上。
6. 遷移逐畫面一刀切，不保留新舊參數並存的過渡期。

## 後果

- 新增依賴只改「建立處」與「使用處」，中間的畫面不用動；漏轉送變成編譯錯誤。
- 畫面拿到的是整組而非單一依賴，單一畫面的 interface 比逐欄寬鬆；以按使用者分組控制寬度，不提供全部依賴的整包。
- 測試改動量大：`ReaderScreen(` 在 5 個檔案約 267 處、`LibraryScreen(` 約 135 處、`SettingsScaffold(` 約 53 處，靠共用工廠降低每處成本。
- 未選的做法：`InheritedWidget` 查找會讓缺依賴從編譯期錯誤變成執行期錯誤；保留 nullable 省略會延續目前的缺陷類型；新舊並存會延長漏轉送的風險期。
- 守衛測試縮小為身分比對：驗證 `main.dart` 組裝的同一個實例傳到每個開書路徑；欄位是否遺漏改由型別系統保證。
