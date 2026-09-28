# Epic 15 — 儲存權限失效偵測與復原：工單清單 (Issues)

依 [spec.md](./spec.md)（唯一事實來源）拆成 4 個垂直切片。Issue 0 是不改行為的 prefactor，先把 `ReaderScreen` 的檔案路徑來源與依賴注入鏈路收斂好，讓 Issue 1、2 的改動變小。Issue 1 放在 Issue 0 之後，是為了避免兩者同時改 `ReaderScreen` 產生衝突，不是邏輯上的依賴。Issue 2 與 Issue 3 都只依賴 Issue 1，可以平行開發。

```
Issue 0（prefactor）──> Issue 1（失效分類提示）──┬──> Issue 2（書籍重新連結）
                                                  └──> Issue 3（字型失效與重新連結）
```

---

## Issue 0：閱讀器改用「目前生效的檔案路徑」，匯入服務併入依賴 bundle（prefactor）

**Status:** completed

**依賴：** 無。

**What to build：**
- `ReaderScreen` 的 State 新增「目前生效的檔案路徑」，初始值是建構參數 `filePath`。State 內原本所有讀取 `widget.filePath` 的地方（格式判斷、EPUB 版面偵測、書籤／劃線定位、傳給閱讀視圖的路徑等）一律改讀這個值。本 Issue 不提供任何改變它的途徑，所以行為完全不變。
- `FoliateReaderView`／`PdfReaderView` **維持原本的 GlobalKey**（`ReaderScreen` 有二十多處透過它呼叫翻頁、跳頁、目錄、劃線裝飾、朗讀高亮等），不另加 `ValueKey`，也不外包 `KeyedSubtree`。後者無效，因為同一幀內 GlobalKey 換位置時 Flutter 會搬移既有 State。重新開書能拿到全新視圖實例，是因為錯誤視圖會把閱讀視圖整個移出樹，詳見 spec.md「重新開書的復位清單」。
- `LibraryReaderFeatureRepositories` 新增一個可為 null 的 `BookImportService` 欄位，預設 null。以下三處負責讓它一路傳到閱讀器：
  - `main.dart` 建立 bundle 時填入既有的匯入服務實例。
  - `buildReaderScreen` 把它轉交給 `ReaderScreen` 新增的選用建構參數。
  - `ReaderScreen` 開啟單書搜尋時會自行重建一份 bundle，這一處也要把它轉送下去，否則「閱讀器 → 單書搜尋 → 閱讀器」這條路徑會遺失匯入服務。
- 書架、全庫搜尋、單書搜尋本來就是透過這個 bundle 開啟閱讀器，不需要改它們的建構子。
- 本 Issue 不使用這個匯入服務，它只是先鋪好路，供 Issue 2 使用。

**測試要求：**
- `reader_screen_route_test.dart` 新增案例：bundle 帶匯入服務時，`buildReaderScreen` 產出的 `ReaderScreen` 持有同一個實例；bundle 不帶時為 null。
- `library_screen_dependencies_test.dart` 補上新欄位的斷言，比照既有欄位：預設為 null，傳入時保留同一個實例。
- 跑既有的 `reader_screen_test.dart`、`reader_screen_route_test.dart`、`library_search_screen_test.dart`、`book_search_screen_test.dart`、`library_screen_test.dart` 全數通過，證明行為沒有改變。
- 本 Issue 是整張計畫中唯一大範圍改動 `ReaderScreen` 的 prefactor，完成時跑一次完整 `flutter test`，確認零回歸。

**驗收標準：** `ReaderScreen` 的 State 內不再有讀取 `widget.filePath` 的地方（建構參數只用來初始化）；上述測試全數通過；`flutter analyze` 乾淨。

**Blocked by：** 無（可以馬上開始）。

---

## Issue 1：開書失敗時分辨「權限失效／找不到檔案」並顯示對應說明

**Status:** completed

**依賴：** Issue 0。

**What to build：**
- **原生探測方法**：在 `elinkbook/reader_resources_cache` 背景任務佇列通道新增 `probeUriAccess`。
  - 引數：`{'uri': String}`
  - 行為：嘗試開啟輸入串流後立即關閉，不讀取內容。
  - 回傳：`readable`／`permissionRevoked`／`fileNotFound`／`unknownError` 四個代碼字串之一，對應規則見 spec.md「存取探測」。
  - 後三類以警告等級寫入 logcat，內容包含 URI 與例外類別。
- **Dart 端包裝**（閱讀器原生橋接模組）：
  - 新增 `StorageAccessProbeResult` 列舉、`ProbeStorageAccess` 函式型別，以及可覆寫的頂層函式變數 `probeStorageAccess`。
  - 預設實作：
    - 非 `content://` 的輸入直接回傳 `unknownError`，不呼叫原生。
    - 3 秒逾時，逾時回傳 `unknownError`。
    - 收到 `PlatformException` 或無法辨識的代碼時，回傳 `unknownError`。
  - 結果一律寫入 `ReaderConsoleLog`。
- **`ReaderScreen` 錯誤處理**：
  - 開書失敗、而且目前生效的檔案路徑是 `content://` 時：
    - 記下錯誤訊息、取消開書逾時計時器、設定「探測中」旗標，並維持載入指示器。
    - 探測結果回來後先確認 State 仍然 mounted，才切到錯誤視圖。
  - 探測中再收到的錯誤，以及探測中觸發的開書逾時，一律忽略。
  - 開書逾時、不支援的格式、非 `content://` 的書，維持現有行為，不探測。
- **探測結果以型別化欄位保存**：`ReaderScreen` 的 State 用一個可為 null 的 `StorageAccessProbeResult` 欄位記錄探測結果，錯誤視圖依這個欄位分流。不可只把結果轉成字串寫進錯誤訊息，因為 Issue 2 要依這個欄位決定是否顯示按鈕。
- **錯誤視圖依結果分流**：
  - `permissionRevoked` 顯示權限失效說明。
  - `fileNotFound` 顯示找不到檔案說明。
  - `readable`／`unknownError` 維持原本的錯誤文字。
  - 說明文字仍掛在既有的 `Key('reader_error_text')` 上。
  - 本 Issue **不加**重新選取按鈕。
- **在地化**：新增 `readerStoragePermissionRevokedMessage`、`readerStorageFileNotFoundMessage` 兩個 key，文案方向見 spec.md 的 ARB 表格。四份 ARB 都要補：`app_zh_TW.arb`（範本，含 `@key` 說明）、`app_zh.arb`（中文退路，內容同正體中文）、`app_zh_CN.arb`、`app_en.arb`。改完執行 `flutter gen-l10n`，生成的 `app_localizations*.dart` 已納入版控，要一起提交。

**測試要求：**
- `ReaderScreen` widget test（覆寫 `cacheBookForServing` 回傳 null 模擬開書失敗，覆寫 `probeStorageAccess` 注入結果）：
  - `permissionRevoked`、`fileNotFound` 各自顯示對應的說明文字。
  - `readable`、`unknownError` 顯示原本的通用錯誤文字。
  - 非 `content://` 的書不呼叫探測。
  - 開書逾時不呼叫探測。
  - 探測尚未完成時（用 Completer 控制），底層連續回報兩次錯誤，探測只被呼叫一次；探測期間畫面仍是載入指示器。
  - 探測尚未完成時離開閱讀器，結果回來後不拋例外。
- Dart 包裝的單元測試（以假的 MethodChannel handler）：
  - 四個代碼各自對應到正確的列舉值。
  - 無法辨識的代碼回傳 `unknownError`。
  - `PlatformException` 回傳 `unknownError`。
  - 逾時回傳 `unknownError`。
  - 非 `content://` 的輸入不呼叫通道。
- 真機手動驗證，並把結果記錄在 `epic.md`：
  - 以資料夾匯入一本 EPUB 與一本 PDF。
  - 正常情況下可以開啟。
  - 在系統設定清除 App 的檔案授權，或以 adb 撤銷授權後開書，顯示權限失效說明，logcat 有對應記錄。
  - 刪除或搬移原始檔案後開書，顯示找不到檔案說明。
- `node tool/check_l10n_hardcoded_strings.js` 通過。

**驗收標準：** 上述測試通過；真機三種情境符合預期；既有的 `cacheBookForServing`／`readContentUriAll`／`readCustomFontBytes` 行為與回傳契約完全沒變；`flutter analyze` 乾淨。

**Blocked by：** Issue 0。

---

## Issue 2：在閱讀器錯誤畫面重新選取檔案，書籍原地重新連結並繼續閱讀

**Status:** ready-for-human（程式、自動化測試、程式審查皆已完成；只剩真機驗證需要真人操作，驗證通過後改為 `completed`）

**依賴：** Issue 1。

**What to build：**
- **`BookImportService.relinkBook(bookId, newUri, {displayName})`**：回傳 spec.md 定義的 sealed class `BookRelinkResult`，成功時是帶著更新後 `Book` 的 `BookRelinkSuccess`，失敗時是 `BookRelinkFailure` 加上失敗原因。處理順序照 spec.md「先驗證，後持久化」的 7 步：
  1. 用 `findBookById` 讀取原書的最新記錄。
  2. 檢查格式和原書相同。
  3. 檢查新檔案不是書庫中另一本書：新 URI 等於**其他書籍**（id 不同）的 `filePath` 時回傳 `alreadyInLibrary`；等於原書自己的 `filePath` 則不擋，因為這正是「撤銷授權後重新選取同一個檔案」的主要情境。
  4. 用選檔器給的暫時讀取授權計算內容指紋：EPUB 先呼叫 `extractMetadata` 取得 OPF identifier，其餘格式取整檔 SHA-256。
  5. 和原書的內容指紋比對；原書沒有指紋時略過比對，並補寫新算出的指紋。
  6. 確認是同一本書後，才持久化授權。持久化失敗或 URI 沒有可辨識副檔名時，改存一份落地複本。
  7. 以 `updateBook` 原地更新，只改 `filePath`（與補寫的指紋）。

  任何一步失敗都不寫資料庫、不持久化授權、不留下檔案。格式判斷、持久化授權、落地複本三段規則，必須和第一次匯入共用同一份實作，不可另寫一份。
- **所有 `BookImportService` 實作同步補上 `relinkBook`**，否則既有測試會編譯失敗：
  - 正式實作 `BookImportServiceImpl`。
  - 共用測試替身 `FakeBookImportService`：可設定回傳值，並記錄收到的引數。這個替身有二十多個測試檔在用。
  - WiFi 傳書測試內的 `_ThrowingImportService`。
- **錯誤視圖的「重新選取檔案」按鈕**：
  - 顯示條件：探測結果是 `permissionRevoked` 或 `fileNotFound`，而且 bundle 中有匯入服務。
  - 按鈕 Key：`Key('reader_storage_relink_button')`。
  - 樣式要有明確外框，在 E-Ink 高對比模式下也看得清楚（見 spec.md「介面文案與在地化」）。
- **單檔選擇器注入點**：
  - `ReaderScreen` 新增選用建構參數，型別如下，預設實作走 `FilePicker`：

    ```dart
    typedef SingleBookFilePicker =
        Future<({String uri, String? displayName})?> Function(List<String> allowedExtensions);
    ```

  - `allowedExtensions` 依原書格式傳入（例如 EPUB 傳 `['epub']`）；使用者取消時回傳 null。
- **處理中狀態**：
  - 從按下按鈕到 Re-link 回傳為止，按鈕停用並顯示進度指示器；在 finally 區段恢復。
  - 顯示 SnackBar 或重新開書前，先確認 State 仍然 mounted。
- **移除 Issue 0 的暫時性 lint 豁免**：Issue 0 因 `_activeFilePath` 尚無寫入點，加了 `// ignore: prefer_final_fields` 與一行說明註解；本 Issue 加上寫入點後一併移除這兩行，並確認 `flutter analyze` 仍乾淨。
- **成功後重新開書**（閱讀視圖維持原本的 GlobalKey，不加 `ValueKey`，見 Issue 0）：在同一次 `setState` 內完成以下動作：
  - 把目前生效的檔案路徑更新為 `updatedBook.filePath`。
  - 狀態改回載入中，並清除錯誤訊息與探測結果。
  - 重新啟動 30 秒開書逾時計時器。
  - 若 EPUB 版面偵測在失敗前尚未完成，以新路徑重新觸發一次偵測。
- **失敗**：依失敗原因以 SnackBar 顯示對應文字，錯誤視圖維持原樣，可以再試一次。
- **在地化**：新增 `readerStorageRelinkButton`、`readerStorageRelinkFormatMismatch`、`readerStorageRelinkContentMismatch`、`readerStorageRelinkAlreadyInLibrary`、`readerStorageRelinkFailed` 五個 key。四份 ARB 都要補：`app_zh_TW.arb`（範本，含 `@key` 說明）、`app_zh.arb`（中文退路，內容同正體中文）、`app_zh_CN.arb`、`app_en.arb`。改完執行 `flutter gen-l10n`，生成的 `app_localizations*.dart` 已納入版控，要一起提交。

**測試要求：**
- `book_import_service_test.dart`（假的原生通道控制授權、中繼資料、指紋回應）：
  - 成功，以及四種失敗原因各一個案例。
  - **EPUB identifier 回歸測試**：資料庫中存的指紋是 OPF identifier，新檔案的 `extractMetadata` 回傳同一個 identifier 時，必須判定為同一本書並成功。
  - 選取的 URI 等於原書自己的 `filePath` 時，不被判定為 `alreadyInLibrary`，而是正常走完驗證並成功。
  - `formatMismatch`、`alreadyInLibrary`、`contentMismatch` 三種情況下，完全沒有呼叫 `takePersistableUriPermission`，也沒有產生落地複本檔案。
  - 原書沒有指紋時略過比對，並把新指紋寫回。
  - 驗證通過後持久化授權失敗，或 URI 沒有副檔名時，改用落地複本，並回傳帶本機路徑的 `BookRelinkSuccess`。
  - 任何失敗都不呼叫 `updateBook`。
  - 以 `findBookById` 取得的最新記錄為基礎：測試替身中預先寫入的閱讀位置，在 Re-link 後仍然保留。
- `ReaderScreen` widget test（注入假的探測、假的選擇器、記憶體版 repository 與匯入服務測試替身）：
  - `permissionRevoked`／`fileNotFound` 顯示按鈕；`readable`／`unknownError` 不顯示；bundle 中沒有匯入服務時不顯示。
  - **補 Issue 1 程式審查 M-1**：在測試內暫時讓 `cacheBookForServing` 回傳 null（其餘測試維持全檔的成功覆寫），確認「`FoliateReaderView` 讀取失敗 → `onError` → 探測」這條完整鏈路會呼叫探測一次並顯示對應說明。Issue 1 的測試是直接呼叫 `onError`，沒有覆蓋這一段。
  - **補 Issue 1 程式審查 M-2**：新增一個 `content://…/book.pdf` 的 `permissionRevoked` 案例，確認 PDF 書也會觸發探測並顯示重新選取按鈕。
  - 選取成功後，repository 中該書的 `filePath` 已更新、`id` 不變，畫面回到載入中，而且假 `cacheBookForServing` 被**再呼叫一次**，收到的是新路徑。這個案例同時證明閱讀視圖確實重新建立，所以不需要 `ValueKey`。
  - Re-link 回傳落地複本路徑時，重新開書使用的是該本機路徑。
  - 重新開書後再次卡住時，30 秒開書逾時仍會觸發。
  - 處理中按鈕停用並顯示進度，結束後恢復。
  - 選擇器取消時：錯誤視圖維持原樣、**不顯示任何 SnackBar**、按鈕恢復可用、repository 記錄不變。
  - 四種失敗原因下：錯誤視圖維持原樣並顯示對應原因的 SnackBar 文字，repository 記錄不變。
- 真機手動驗證（接續 Issue 1 的情境）：
  - 撤銷授權後，重新選取同一個檔案，書可以開啟，閱讀位置、劃線、書籤都還在。
  - 選另一本書時被拒絕。
  - 返回書架後，這本書仍在原分類、封面不變。
- `node tool/check_l10n_hardcoded_strings.js` 通過。

**驗收標準：** 上述測試通過；真機驗證符合預期；`flutter analyze` 乾淨。

**Blocked by：** Issue 1。

---

## Issue 3：字型管理標示讀不到的自訂字型，並可重新連結

**Status:** ready-for-agent

**依賴：** Issue 1（只用到 `probeStorageAccess`，與 Issue 2 無關，可平行開發）。

**What to build：**
- **`CustomFontsRepository.updateUri(int id, String fontUri)`**：只更新該列的 URI 欄位。測試替身 `FakeCustomFontsRepository` 同步實作。
- **字型管理畫面的探測**：
  - 載入自訂字型清單後，以 `probeStorageAccess` 逐一非同步探測，不阻塞清單顯示。
  - 結果以「字型 id → 探測結果」的對應表保存，不使用清單索引。
  - 每筆結果寫入前，先確認 State 仍然 mounted，而且該 id 仍在清單中；不在就直接捨棄。
- **失效標示**：結果不是 `readable` 的字型，在該列顯示「檔案無法讀取」文字標籤（不能只靠顏色），並提供「重新連結字型檔案」動作。
  - 標籤 Key：`Key('font_management_inaccessible_badge_${font.id}')`
  - 動作 Key：`Key('font_management_relink_button_${font.id}')`
- **單檔選擇器注入點**：
  - 字型管理畫面新增選用建構參數，型別如下，預設實作走 `FilePicker`，限定 ttf／otf，並取得位元組：

    ```dart
    typedef SingleFontFilePicker =
        Future<({String uri, String name, Uint8List bytes})?> Function();
    ```

  - 位元組用來解析字型家族名稱；使用者取消時回傳 null。
  - 既有的「上傳字型」批次選取流程不動。
- **重新連結**：
  1. 解析選取檔案的字型家族名稱，和原字型比對；不同就以 SnackBar 拒絕，記錄不變。
  2. 相同時持久化授權（盡力而為，失敗不中止，比照 ADR 0021），再呼叫 `updateUri`，並把該字型的探測狀態改為 `readable`。
  3. 處理期間停用該列的動作，在 finally 區段恢復。
- 閱讀器內的字型行為不變（讀不到仍靜默改用預設字型）；可下載字型不探測。
- **在地化**：新增 `fontManagementFileInaccessibleBadge`、`fontManagementRelinkAction`、`fontManagementFamilyMismatchMessage` 三個 key。四份 ARB 都要補：`app_zh_TW.arb`（範本，含 `@key` 說明）、`app_zh.arb`（中文退路，內容同正體中文）、`app_zh_CN.arb`、`app_en.arb`。改完執行 `flutter gen-l10n`，生成的 `app_localizations*.dart` 已納入版控，要一起提交。

**測試要求：**
- `CustomFontsRepository` 測試：`updateUri` 只改 URI，顯示名稱與家族名稱不變。比照既有 repository 測試的慣例。
- `font_management_screen_test.dart`（注入假探測、假選擇器）：
  - 失效標示只出現在探測結果不是 `readable` 的字型。
  - 選到同家族的字型後，URI 已更新、標示消失。
  - 選到不同家族的字型時顯示拒絕訊息，記錄不變。
  - 選擇器取消時沒有任何變化。
  - 探測尚未完成時刪除某個字型，結果回來後不錯位、不拋例外。
- 真機手動驗證：撤銷某個自訂字型的授權後進入字型管理，該字型被標示失效；重新連結後，使用該字型的書恢復顯示這款字型。
- `node tool/check_l10n_hardcoded_strings.js` 通過。

**驗收標準：** 上述測試通過；真機驗證符合預期；`flutter analyze` 乾淨。

**Blocked by：** Issue 1。
