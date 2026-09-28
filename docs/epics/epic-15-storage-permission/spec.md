# Spec：儲存權限失效偵測與復原（epic-15-storage-permission）

Status: ready-for-agent

> Architecting 階段產出（2026-09-28 `/to-spec`），自此為本 Epic 的唯一事實來源。上游文件：[design.md](./design.md)、[ADR 0029](../../adr/0029-storage-permission-saf-resilience-over-manage-external-storage.md)、ADR 0002（`content://` URI 讀取契約）、ADR 0021（自訂字型不落地複本）。
>
> **與 design.md 的差異**：design §3 原規劃「原生讀取方法全面改用 `result.error` 透傳例外型別」。Architecting 盤點後發現 `cacheBookForServing`／`readContentUriAll` 共有 5 個呼叫端（兩個閱讀器、兩個全文索引器、WiFi 傳書）皆以「回傳 null」判斷失敗，全面改丟例外會擴散到與本 Epic 無關的模組。改採「開書失敗後才做一次存取探測」：既有讀取方法的契約完全不變，另立單一探測方法負責分類失效原因。design 的其餘結論（開書當下按需偵測、不背景輪詢、書架不批次探測、單書 Re-link 保全 `book.id`、字型靜默降級、修復入口在字型管理）全數沿用。

## Problem Statement

使用者從手機儲存空間匯入的書（尤其是用「匯入資料夾」一次匯入的書），App 並沒有複製檔案，而是記住系統核發的檔案存取授權，每次開書都直接讀原始檔案。某些裝置或廠商 ROM 會在某個時間點讓這份授權失效（例如手機管家自動清理權限、SD 卡重新掛載），或是原始檔案被搬走、改名、刪除。

這時使用者點開書，只會看到一句籠統的「無法開啟書籍」，不知道是什麼原因，也不知道該怎麼辦。唯一的補救是刪掉這本書再重新匯入，但這樣會連同這本書的閱讀進度、劃線、備註、書籤一起消失。自訂字型也有同樣問題：字型檔讀不到時閱讀器會悄悄改用預設字型，使用者不知道為什麼字型變了，字型管理畫面也看不出哪個字型已經失效。

## Solution

使用者開書失敗時，閱讀器會判斷失敗原因，分成三種：

- **存取權限已失效**：畫面說明「App 對這個檔案的存取權限已失效」，提供「重新選取檔案」按鈕。
- **找不到原始檔案**：畫面說明「原始檔案可能已被移動、改名或刪除」，提醒使用者先確認檔案還在，同樣提供「重新選取檔案」按鈕。
- **其他原因**：維持現有的通用錯誤訊息，不提供重新選取。

使用者按下「重新選取檔案」、選到原本那本書的檔案後，App 會確認選到的確實是同一本書（格式相同、內容指紋相同），再把這本書記錄的檔案位置原地換成新的位置，然後直接在同一個閱讀器畫面重新開書。書的閱讀進度、劃線、備註、書籤全部保留。如果選到的不是同一本書，App 會拒絕並說明原因，原本的書籍記錄完全不動。

自訂字型方面，閱讀器維持靜默改用預設字型、不打斷閱讀。使用者進入「字型管理」時，讀不到的自訂字型會標示為「檔案無法讀取」，並提供「重新連結字型檔案」；選到同一款字型（字型家族名稱相同）後原地更新，所有使用這款字型的書都會自動恢復。

整個過程都不新增任何系統權限，也不會在背景定期檢查、不會在書架畫面逐本探測。

## User Stories

1. 身為從資料夾匯入書籍的讀者，我希望在授權失效時看到明確的原因說明，才知道問題不是書本身壞了。
2. 身為讀者，我希望「權限失效」和「檔案不見了」顯示不同的說明，才知道該重新授權，還是先去找原始檔案。
3. 身為讀者，我希望錯誤畫面上直接有「重新選取檔案」按鈕，不必自己摸索修復方法。
4. 身為讀者，我希望重新選取檔案後，閱讀進度仍停在原本讀到的地方。
5. 身為讀者，我希望重新選取檔案後，原本的劃線、備註、書籤全部都在，而且位置正確。
6. 身為讀者，我希望重新選取檔案後，這本書在書架上的分類、封面、書名都不變。
7. 身為讀者，我希望重新選取檔案成功後能直接繼續閱讀，不必退回書架再點一次。
8. 身為讀者，我希望不小心選錯檔案（另一本書）時，App 會拒絕並告訴我原因，而不是把另一本書的內容套進這本書的記錄。
9. 身為讀者，我希望選錯格式（例如原書是 EPUB，卻選了 PDF）時，App 會直接告訴我格式不符。
10. 身為讀者，我希望在選檔畫面按取消時，錯誤畫面維持原樣，我可以再試一次或返回書架。
11. 身為讀者，我希望重新選取失敗時，原本的書籍記錄不會被改壞，下次還能再試。
12. 身為讀者，我希望如果選到的檔案已經是書庫裡另一本書，App 會告訴我它已存在於書庫，而不是讓兩筆記錄指向同一個檔案。
13. 身為讀者，我希望錯誤原因不明時（例如一般讀取錯誤），看到的仍是現在的通用錯誤訊息，不會被誤導去重新選檔。
14. 身為讀者，我希望錯誤畫面仍保留返回鍵，可以隨時離開閱讀器。
15. 身為 E-Ink 裝置使用者，我希望 App 不在背景定期檢查檔案權限，避免耗電、干擾裝置深度待機。
16. 身為書很多的讀者，我希望書架畫面不會因為要檢查每本書能不能讀而變慢或閃爍。
17. 身為讀者，我希望開書成功時不增加任何額外等待時間。
18. 身為讀者，我希望重新連結後的書籍，之後不再依賴原本那個資料夾的授權，比較不容易再次失效。
19. 身為讀者，我希望原始檔案沒有可辨識副檔名時（例如從「最近檔案」選取），重新選取仍然能成功，行為與第一次匯入時一致。
20. 身為讀者，我希望重新連結同一本書後，已建立的全文檢索索引仍然有效，不必重新建立。
21. 身為使用自訂字型的讀者，我希望字型檔讀不到時閱讀仍能正常進行，只是暫時改用預設字型。
22. 身為使用自訂字型的讀者，我希望在字型管理畫面看得出哪個自訂字型的檔案讀不到了。
23. 身為使用自訂字型的讀者，我希望能在字型管理畫面重新連結該字型檔，不必刪除字型再重新上傳。
24. 身為使用自訂字型的讀者，我希望重新連結字型後，原本指定這款字型的所有書籍都自動恢復使用它，不必逐本重新設定。
25. 身為使用自訂字型的讀者，我希望選到不同字型家族的檔案時，App 會拒絕並說明原因，不會讓書籍套用到錯的字型。
26. 身為使用自訂字型的讀者，我希望字型管理畫面檢查字型狀態時不會明顯卡頓。
27. 身為使用簡體中文或英文介面的讀者，我希望所有新增的錯誤說明與按鈕文字都以我的介面語言顯示。
28. 身為 E-Ink 高對比模式使用者，我希望新的錯誤畫面與按鈕在高對比模式下清楚可辨。
29. 身為開發者，我希望既有的書籍讀取方法維持「失敗回傳 null」的契約，全文索引與 WiFi 傳書的錯誤處理不受影響。
30. 身為開發者，我希望失效原因的判斷集中在一個探測方法裡，將來追查特定 ROM 的問題時只需要看一處。
31. 身為開發者，我希望探測失敗時會記錄到 Console Log／logcat（含 URI 與例外類型），方便真機回報時對照 design.md 的成因假說排查。
32. 身為開發者，我希望整條「錯誤視圖 → 重新選取 → 原地更新 → 重新開書」流程能用一般 widget test 驗證，不需要真機。
33. 身為讀者，我希望不論從書架、全庫搜尋還是書內搜尋打開書，遇到存取失效時都看得到「重新選取檔案」按鈕。
34. 身為讀者，我希望重新選取的檔案在計算比對期間，按鈕會顯示處理中並暫時無法再按，不會讓我以為沒反應而重複操作。
35. 身為讀者，我希望選錯檔案不會在系統留下多餘的授權或佔用空間的複本。
36. 身為讀者，我希望重新選取後如果書還是打不開，閱讀器仍會在合理時間內告訴我，而不是一直轉圈。

## Implementation Decisions

### 受影響範圍（界定探測何時有意義）

- 只有 `Book.filePath` 仍是 `content://` URI 的書需要探測。依現行匯入流程，這實際上是 EPUB／PDF／KF8(AZW3) 中「持久化授權成功且 URI 帶可辨識副檔名」的書，以資料夾匯入為大宗。
- TXT／MD（匯入時已合成 EPUB 並落地）、CBZ（匯入時重建並落地）、雲端／Calibre／WiFi 傳書（下載後落地）、單檔匯入時授權失敗而改用落地複本的書，`filePath` 都是 App 私有路徑，不在本 Epic 範圍內。開書失敗時仍維持現有的通用錯誤處理。

### 存取探測（新增的唯一原生 seam）

- 原生端新增「探測 URI 可讀性」方法：嘗試開啟輸入串流後立即關閉，不讀取內容。
- **跨端契約**：
  - 通道：`elinkbook/reader_resources_cache`（背景任務佇列通道）。雖然只是開關串流，但若 URI 來自有缺陷的第三方或雲端文件提供者，`openInputStream` 可能因跨行程 IPC 卡住；放在主執行緒會直接造成 ANR，Dart 端的逾時也救不了主執行緒。
  - 方法名：`probeUriAccess`
  - 引數：`{'uri': String}`
  - 回傳：`String`，固定為下列四個代碼之一（比照 ADR 0034「原生回代碼、Dart 端在地化」的精神，原生端不回傳任何使用者可見文字）：
    - `readable`：可讀取
    - `permissionRevoked`：捕捉到 `SecurityException`
    - `fileNotFound`：捕捉到 `FileNotFoundException`，或內容提供者回傳 null 串流
    - `unknownError`：其他所有例外
- 原生端對後三類一律以警告等級記錄 logcat，內容包含 URI 與例外類別；不可用除錯等級，因為部分 ROM 會過濾除錯等級的 log，這是專案既有的教訓。
- **Dart 端型別**（位於閱讀器原生橋接模組，比照 `cacheBookForServing` 的可覆寫頂層函式變數慣例，讓 widget test 注入假結果）：

  ```dart
  enum StorageAccessProbeResult { readable, permissionRevoked, fileNotFound, unknownError }

  typedef ProbeStorageAccess = Future<StorageAccessProbeResult> Function(String uri);

  ProbeStorageAccess probeStorageAccess = _defaultProbeStorageAccess;
  ```

  - 預設實作的規則：
    - 非 `content://` 的輸入直接回傳 `unknownError`，不呼叫原生。
    - 原生呼叫包一道 3 秒逾時，逾時回傳 `unknownError`。
    - 收到無法辨識的代碼或 `PlatformException` 時，也回傳 `unknownError`。
  - 不論哪個結果，都一併寫入 `ReaderConsoleLog`。
- **既有的 `cacheBookForServing`、`readContentUriAll`、`readCustomFontBytes` 契約完全不變**，仍然是失敗時回傳 null。

### 閱讀器錯誤視圖（`ReaderScreen`）

- 觸發時機：只在 `ReaderScreen` 從載入中進入錯誤狀態、而且這本書目前生效的檔案路徑是 `content://` URI 時，才探測一次。
  - 開書逾時、不支援的格式、非 `content://` 的書，都不探測。
  - 探測期間維持載入指示器，完成後才切到錯誤視圖，避免畫面閃兩次；這對 E-Ink 的殘影有意義。
- **探測期間的防重入與生命週期**：
  - 第一次錯誤進來時，立即記下該錯誤訊息、取消開書逾時計時器，並設「探測中」旗標。
  - 探測中再收到的任何錯誤一律忽略：底層視圖此時仍在樹上，可能連續回報多次錯誤。
  - 探測中觸發的開書逾時也一律忽略。
  - 探測結果回來時，先確認 State 仍然 mounted，才切換到錯誤視圖；若使用者已離開閱讀器，直接捨棄結果。
- 錯誤視圖依探測結果分流：
  - `permissionRevoked`：顯示權限失效說明＋「重新選取檔案」按鈕。
  - `fileNotFound`：顯示檔案不存在說明（提醒先確認原始檔案仍在）＋「重新選取檔案」按鈕。
  - `readable`、`unknownError`：維持現有的通用錯誤文字，不顯示重新選取按鈕。探測結果是可讀取卻開書失敗，代表問題不在存取權限，例如檔案毀損或渲染失敗。
- 既有的 `Key('reader_error_text')` 保留在錯誤文字上，另外為「重新選取檔案」按鈕新增固定的 Key，供測試觀察。對外仍不新增公開 callback 參數，維持 ADR 0007 的慣例。
- 重新選取流程：
  1. 開啟單檔選擇器，副檔名限定為原書的格式。
  2. 使用者取消時什麼都不做。
  3. 選取後呼叫下方的 Re-link 服務。
  4. 依結果處理：
     - 成功：在同一個畫面內重新開書（見下方「重新開書的復位清單」）。
     - 失敗：以 SnackBar 顯示對應原因，錯誤視圖維持原樣。
- **處理中狀態**：
  - 從按下按鈕起，到 Re-link 服務回傳為止，按鈕都停用，並在按鈕位置顯示進度指示器。大檔案計算 SHA-256 可能要數秒，停用可以防止重複開啟選擇器，或平行發動多次 Re-link。
  - 使用者取消選檔，或處理結束（不論成功或失敗）時，一律在 finally 區段恢復按鈕。
  - 顯示 SnackBar 或重新開書前，都要先確認 State 仍然 mounted。
- **重新開書的復位清單**：
  - `ReaderScreen` 的 State 持有「目前生效的檔案路徑」，初始值是建構參數 `filePath`。State 內原本所有讀取 `widget.filePath` 的地方，一律改讀這個值。
  - Re-link 成功時，在同一次 `setState` 內：
    1. 把目前生效的檔案路徑更新為 `BookRelinkSuccess.updatedBook.filePath`。這可能是新的 `content://` URI，也可能是落地複本的本機路徑。
    2. 狀態改回載入中，清除錯誤訊息與探測結果。
    3. 重新啟動 30 秒開書逾時計時器。
  - `FoliateReaderView`／`PdfReaderView` 以目前生效的檔案路徑作為 `ValueKey`。錯誤視圖本來就把閱讀視圖整個移出樹，所以回到載入中時一定會建立全新的視圖實例，重新走一次快取與開書流程。加上 Key 是防禦性保證，不依賴這個隱含行為。
  - 不需要重跑的部分：
    - 偏好設定、閱讀位置、字型、版面預設集：以 `bookId` 載入，Re-link 不改 `bookId`，而且開書失敗期間沒有閱讀行為。
    - 版面分派（固定版面／流式的判斷）：Re-link 保證格式不變、內容相同。但若 EPUB 的版面偵測在失敗前尚未完成（結果仍是 null），要以新路徑重新觸發一次偵測，否則會永遠停在等待。
- **依賴注入全鏈路**：
  - 把匯入服務加進既有的 `LibraryReaderFeatureRepositories` bundle，成為一個可為 null 的欄位，不在各搜尋畫面的建構子逐一新增參數。
  - 這個 bundle 目前已經貫穿所有開啟閱讀器的路徑：書架、全庫搜尋、單書搜尋，以及閱讀器 → 單書搜尋 → 閱讀器。因此只需要改三處：
    - `main.dart` 建立 bundle 時填入匯入服務。
    - `buildReaderScreen` 把它轉交給 `ReaderScreen`。
    - `ReaderScreen` 開啟單書搜尋時自行重建 bundle 的那一處，把它一併轉送。
  - 比起逐一改搜尋畫面的建構子，這個做法少改兩個畫面的簽章，也不會漏掉「從閱讀器進單書搜尋再開書」這條路徑。
  - `LibraryRepository` 在 `buildReaderScreen` 已經是必填參數，不需改動。
  - 匯入服務為 null 時（例如既有測試），不顯示重新選取按鈕，只顯示分類後的說明文字。
- 單檔選擇器包成可注入的函式型別，由 `ReaderScreen` 的選用建構參數注入，預設走 `FilePicker`，讓 widget test 不必觸碰平台實作。回傳值是選取的 URI 與真實檔名，取消時回傳 null。
- 返回書架後，書架依既有的「從閱讀器返回即重新載入書單」行為反映更新後的記錄，本 Epic 不另外處理書架。

### Re-link 服務（擴充 `BookImportService`）

- 在 `BookImportService` 抽象介面新增「重新連結單本書籍」操作。
  - 輸入：書籍 id（不是 `Book` 物件）、新選取的 URI、選擇器提供的真實檔名。
  - 為什麼用 id：`updateBook` 會整列覆寫，若由呼叫端傳入 `Book` 快照，可能把閱讀位置等欄位蓋回舊值。所以由服務在寫入前，用既有的 `LibraryRepository.findBookById` 自行讀取最新記錄再修改。
- **回傳型別**：用 sealed class。純列舉無法在執行期帶出更新後的 `Book`，而呼叫端需要知道最終生效的檔案路徑，它可能是落地複本的本機路徑，不一定是選取的 URI。

  ```dart
  sealed class BookRelinkResult { const BookRelinkResult(); }

  final class BookRelinkSuccess extends BookRelinkResult {
    final Book updatedBook;
    const BookRelinkSuccess(this.updatedBook);
  }

  enum BookRelinkFailureReason { formatMismatch, contentMismatch, alreadyInLibrary, failed }

  final class BookRelinkFailure extends BookRelinkResult {
    final BookRelinkFailureReason reason;
    const BookRelinkFailure(this.reason);
  }

  // BookImportService 新增：
  Future<BookRelinkResult> relinkBook(String bookId, String newUri, {String? displayName});
  ```

  - 四種失敗原因的意義：
    - `formatMismatch`：格式不符
    - `contentMismatch`：內容不是同一本書
    - `alreadyInLibrary`：該檔案已是書庫中另一本書
    - `failed`：讀取或寫入失敗，也包含找不到該 id 的書籍記錄
- 放在匯入服務而不是新開模組，是為了共用它既有的私有規則：
  - 格式判斷：真實檔名優先，URI 作為退路。
  - 持久化授權。
  - 「授權失敗或 URI 沒有可辨識副檔名時，改存一份落地複本」的退路。

  這樣重新連結和第一次匯入的行為一致。
- **處理順序：先驗證，後持久化**。
  - 系統檔案選擇器回傳的 URI 本身就帶有暫時讀取授權，在目前 App 行程內可以直接讀取，不需要先持久化。所以在確認是同一本書之前，不持久化授權、也不做落地複本。
  - 這樣選錯檔案時不會白白消耗系統的持久化授權配額（原生端目前也沒有釋放授權的方法），也不會先複製上百 MB 再刪掉。
  - 任何一步失敗都直接回傳對應結果，**不修改任何既有記錄、不持久化授權、不留下檔案**。

  1. 用 `findBookById` 讀取原書最新記錄；找不到 → `failed`。
  2. 判斷新檔案格式，和原書 `Book.format` 不同 → `formatMismatch`。
  3. 新 URI 已等於書庫中另一本書的 `filePath` → `alreadyInLibrary`。等於原書自己的 `filePath` 則不擋，視為使用者重新授權同一個 URI。這裡要查整個書單，沿用既有的重複偵測方式。
  4. **利用暫時讀取授權**計算新檔案的內容指紋，算法必須和第一次匯入完全一致：
     - EPUB 先對新 URI 呼叫原生 `extractMetadata` 取出 OPF identifier，再當作 `epubIdentifier` 傳給 `computeBookContentFingerprint`；取不到 identifier 時才退回整檔 SHA-256。
     - 其他格式直接取整檔 SHA-256。
     - 如果跳過 `extractMetadata`，EPUB 會算出 SHA-256，和資料庫裡存的 OPF identifier 永遠對不上，導致所有 EPUB 都被拒絕。
  5. 和原書的 `contentFingerprint` 比對：
     - 不同 → `contentMismatch`。
     - 原書沒有指紋（null）時略過比對，把新算出的指紋一併寫回。
     - 讀取或計算失敗 → `failed`。
  6. 確認是同一本書後，才對新 URI 持久化授權。持久化失敗，或 URI 沒有可辨識副檔名時，改存一份落地複本；複本也失敗 → `failed`。
  7. 以 `LibraryRepository.updateBook` 原地更新：
     - 只改 `filePath`（新 URI 或落地複本路徑），以及第 5 步補上的指紋。
     - `id`、書名、作者、封面、分類、閱讀位置、同步欄位全部不動。
     - 回傳 `BookRelinkSuccess`，帶出更新後的 `Book`。
- 劃線、備註、書籤、閱讀進度、全文檢索索引都以 `book.id` 關聯，而且指紋相同代表內容相同，所以都不需要任何遷移或重建。
- 本 Epic 不處理資料夾層級的批次重新連結，理由見 design.md。

### 自訂字型的失效標示與重新連結（`FontManagementScreen`）

- 閱讀器內的行為不變：字型讀不到時仍由 WebView 退回預設字型，不探測、不提示。
- 使用者進入「字型管理」畫面載入自訂字型清單後，逐一以存取探測檢查每個自訂字型的 URI。
  - 探測在清單載入後非同步進行，不阻塞清單顯示。
  - 結果不是 `readable` 的字型，在該列標示「檔案無法讀取」，並提供「重新連結字型檔案」動作。
  - **狀態以字型資料庫主鍵為 key 保存**，也就是一個「字型 id → 探測結果」的對應表，不用清單索引。探測期間使用者可能刪除或重新命名字型，讓清單結構改變；用 id 對應可以避免結果錯位。結果回來時，若該 id 已不在清單中，就直接捨棄。
  - 每筆結果寫入狀態前，都要先確認 State 仍然 mounted。
- 重新連結流程：
  1. 開啟單檔選擇器（限定 ttf／otf，需要取得位元組才能解析家族名稱）。
  2. 解析字型家族名稱，和原字型的家族名稱比對；不同就拒絕，並以 SnackBar 說明原因。
  3. 家族名稱相同時，持久化新 URI 的授權，比照 ADR 0021 盡力而為、不做落地複本。
  4. 更新該字型記錄的 URI，並把該字型的探測狀態改為 `readable`。
  - 處理期間同樣停用該列的動作，並在 finally 區段恢復。
- 字型管理畫面新增單檔選擇器的注入點：可注入的函式型別，透過選用建構參數傳入，預設走 `FilePicker`。回傳選取的 URI、檔名與位元組，取消時回傳 null。現有的「上傳字型」批次選取流程不在本 Epic 範圍，維持不動。
- 因為單書版面偏好是以家族名稱引用字型，更新 URI 後所有使用這款字型的書籍會自動恢復，不需要遷移。
- 自訂字型資料存取層（`CustomFontsRepository`）新增 `Future<void> updateUri(int id, String fontUri)`，只更新該列的 URI 欄位，其餘欄位不變。這是單一 UPDATE 敘述，不需要額外的交易。測試替身 `FakeCustomFontsRepository` 同步實作。
- 可下載字型位於 App 私有目錄，不在探測範圍內。

### 介面文案與在地化

- 所有新增的使用者可見字串都走 `AppLocalizations`，同步補齊正體中文、簡體中文、英文三份 ARB，人工翻譯。ARB key 如下（正體中文文案為定稿方向，實作時可微調措辭，但 key 名稱以此為準）：

  | ARB key | 正體中文文案 |
  |---|---|
  | `readerStoragePermissionRevokedMessage` | App 對這個檔案的存取權限已失效，請重新選取檔案。 |
  | `readerStorageFileNotFoundMessage` | 找不到原始檔案，可能已被移動、改名或刪除。請先確認檔案仍在裝置中，再重新選取。 |
  | `readerStorageRelinkButton` | 重新選取檔案 |
  | `readerStorageRelinkFormatMismatch` | 選取的檔案格式與原書不同 |
  | `readerStorageRelinkContentMismatch` | 選取的檔案與原書內容不同，請選取同一本書 |
  | `readerStorageRelinkAlreadyInLibrary` | 這個檔案已經是書庫中的另一本書 |
  | `readerStorageRelinkFailed` | 重新連結失敗，請再試一次 |
  | `fontManagementFileInaccessibleBadge` | 檔案無法讀取 |
  | `fontManagementRelinkAction` | 重新連結字型檔案 |
  | `fontManagementFamilyMismatchMessage` | 選取的字型與原字型的家族名稱不同 |

- 提交前需通過 `check_l10n_hardcoded_strings.js`。
- 視覺與元件沿用既有 `ElinkTokens`（三主題＋E-Ink 修飾子），不新增 token。
  - 「重新選取檔案」按鈕必須有明確外框（OutlinedButton 類型的樣式，或採用專案既有設定頁按鈕的外框樣式），不可只靠底色區分。E-Ink 高對比模式下只有黑白兩色，純填色或純文字按鈕的輪廓容易和背景融在一起。
  - 字型列表的「檔案無法讀取」標示同樣不可只靠顏色表達，必須是文字標籤。

### 不需要新增 ADR

本階段的主要取捨是「失敗後探測」取代「例外全面透傳」。這個做法可以輕易反轉（兩者可以並存或替換），不符合 ADR 的「難以逆轉」條件，所以記錄在本 spec 開頭的差異說明，不另立 ADR。ADR 0029 的結論不變。

## Testing Decisions

- **好測試的標準**：只驗證外部可觀察的行為，例如畫面上出現哪段文字或哪個按鈕、`LibraryRepository` 最後存了什麼記錄、回傳哪個結果列舉值，不驗證內部呼叫順序或私有狀態。
- **最高層 seam：`ReaderScreen` widget test**。注入假的 `cacheBookForServing`（回傳 null 模擬開書失敗）、假的存取探測、假的單檔選擇器，以及記憶體版 `LibraryRepository`／`BookImportService` 測試替身，驗證：
  - `permissionRevoked`／`fileNotFound` 各自顯示對應說明與重新選取按鈕。
  - `readable`／`unknownError`／非 `content://` 書籍維持通用錯誤、沒有按鈕。
  - 開書逾時不觸發探測。
  - 探測尚未完成時，底層連續回報多次錯誤，探測只發生一次。做法是用 Completer 控制假探測何時回傳，並計算呼叫次數。
  - 探測尚未完成時離開閱讀器，結果回來後不拋例外。
  - 選取成功後，repository 中該書 `filePath` 已更新、`id` 不變；畫面重新進入載入中，並以新路徑開書（假 `cacheBookForServing` 收到新路徑）。
  - 重新開書後若再次卡住，30 秒開書逾時仍會觸發。
  - 落地複本情境：`BookRelinkSuccess` 帶回本機路徑時，重新開書使用的是本機路徑，不是選取的 URI。
  - Re-link 處理中按鈕停用並顯示進度；處理結束後恢復。
  - 選擇器取消、Re-link 各種失敗結果下，錯誤視圖維持原樣並顯示對應 SnackBar，repository 記錄不變。
  - bundle 中沒有匯入服務時不顯示按鈕。
  - 前例可參考既有的 `reader_screen_test.dart`，它已經用覆寫 `cacheBookForServing` 的方式模擬開書結果。
- **依賴注入鏈路**：在 `reader_screen_route_test.dart`（`buildReaderScreen` 的既有測試）新增一個案例，斷言 bundle 中的匯入服務有轉交給 `ReaderScreen`。
- **`BookImportService` 的 Re-link 單元測試**，以假的原生通道控制授權、中繼資料、指紋回應，逐一覆蓋：
  - 成功，以及四種失敗原因。
  - EPUB 的指紋比對以 `extractMetadata` 取得的 OPF identifier 為準：資料庫存的是 identifier，新檔案回傳同一個 identifier 時必須判定為相同。這個案例直接防止「EPUB 全部被誤判為不同」的回歸。
  - `formatMismatch`／`alreadyInLibrary`／`contentMismatch` 時，**完全沒有**呼叫 `takePersistableUriPermission`，也沒有產生落地複本。
  - 原書沒有指紋時略過比對並補寫。
  - 驗證通過後，URI 無副檔名或授權失敗時改用落地複本，並回傳帶本機路徑的 `BookRelinkSuccess`。
  - 任何失敗都不呼叫 `updateBook`。
  - 寫入以 `findBookById` 取得的最新記錄為基礎：測試替身中的閱讀位置在呼叫後仍保留。
  - 前例可參考既有的 `book_import_service_test.dart`。
- **`FontManagementScreen` widget test**：注入假的探測結果與單檔選擇器，驗證：
  - 失效標示只出現在非 `readable` 的字型。
  - 家族名稱相同時 URI 已更新、標示消失；不同時拒絕，且記錄不變。
  - 探測尚未完成時刪除某個字型，結果回來後不錯位、不拋例外。
  - 前例可參考既有的 `font_management_screen_test.dart`。
- **自訂字型資料存取層**：「更新單一字型 URI」的測試比照既有 repository 測試慣例。
- **原生探測方法**：不寫 Dart 端自動化測試，因為 `flutter test` 碰不到真實的 `ContentResolver`。以真機手動驗證三種情境：
  - 正常可讀
  - 在系統設定清除授權，或以 adb 撤銷授權，模擬權限失效
  - 刪除或搬移原始檔案，模擬檔案不存在
- **測試執行範圍**：依專案慣例，各 Task 只跑觸及的測試檔；計畫最後一個 Task 與發 PR 前各跑一次完整 `flutter test`。提交前 `flutter analyze` 須乾淨，並跑 l10n 稽核腳本。

## Out of Scope

- `MANAGE_EXTERNAL_STORAGE` 全域儲存權限（已由 ADR 0029 排除）。
- 背景定期檢查授權，以及書架畫面批次探測所有書籍。
- 資料夾層級的批次重新連結（重新選取整個資料夾後，自動比對多本書對應的新子檔案）。
- 修改既有讀取方法（`cacheBookForServing`／`readContentUriAll`／`readCustomFontBytes`）的回傳契約，或修改全文索引器、WiFi 傳書的錯誤處理。
- 指紋不一致時「警告後仍允許連結」。本 Epic 一律拒絕。
- 在閱讀器內提示或修復自訂字型失效（維持靜默降級）。
- 查明專案初期問題的根本成因，以及針對特定 ROM 引導使用者關閉自動清理或加入白名單（待有真機重現案例再依 design.md 的成因假說處理）。
- 探測結果的持久化或快取（每次開書失敗都重新探測，結果不寫入資料庫）。

## Further Notes

- **2026-09-28 規格審查修訂**：依 [review-spec.md](./reviews/review-spec.md)（3 Critical／7 Important／3 Minor）修訂，全數處理，其中 3 項採用審查的目的但改用不同做法：
  - C-1：EPUB 指紋比對明訂先呼叫 `extractMetadata` 取得 OPF identifier。
  - C-2：Re-link 改為先驗證、後持久化授權與落地。
  - C-3：回傳型別改為 sealed class。
  - I-1（改用不同做法）：審查建議逐一在兩個搜尋畫面的建構子新增參數。改為把匯入服務放進既有的 `LibraryReaderFeatureRepositories` bundle：改動更少，而且涵蓋審查未提到的「閱讀器 → 單書搜尋 → 閱讀器」路徑。
  - I-2：探測防重入與 mounted 檢查。
  - I-3（改用不同做法）：審查建議逐一重置 State。改為以目前生效的檔案路徑作為閱讀視圖的 `ValueKey`，並列出最小的復位清單，版面分派只在偵測尚未完成時才重跑。
  - I-4：明訂跨端契約與 Dart 型別。
  - I-5：Re-link 處理中停用按鈕並顯示進度。
  - I-6：這是本 spec 的事實錯誤（`findBookById` 早已存在），已更正。
  - I-7：字型管理新增選擇器注入點、以字型 id 保存探測狀態、`updateUri` 簽章。審查提到的「交易防護」不採用：單一 UPDATE 敘述不需要交易。
  - M-1：列出 ARB key。
  - M-2：按鈕與標示的 E-Ink 可辨識性。
  - M-3（改用不同做法）：審查只建議在 Dart 端加 3 秒逾時，但這無法防止原生主執行緒卡住導致 ANR。改為探測走背景任務佇列通道，並加上 Dart 端 3 秒逾時。
- 本 Epic 的觸發問題目前無法重現，探測方法的 logcat 記錄是將來真機回報時對照 design.md「成因分析假說」的主要線索。建議在 Issue 拆分時，把原生探測方法與真機驗證步驟排在最前面。
- Re-link 會把書籍從「依賴資料夾 Tree URI 授權」轉為「擁有自己的單檔授權，或落地複本」，對 design.md 假說 1（Tree 授權繼承不相容）與假說 3（SD 卡重掛載）有實質緩解效果。假說 2（授權配額上限）則會因此多佔一筆配額，影響可忽略，但真機回報若指向配額問題時應納入考量。
- 建議的 Issue 切片方向（供 Scrum Master 階段參考，非定案）：
  1. 原生探測方法＋Dart 包裝＋真機驗證
  2. `BookImportService` Re-link 操作
  3. `ReaderScreen` 錯誤視圖分流＋重新選取流程＋重新開書復位＋依賴注入鏈路（bundle 新增匯入服務）＋在地化字串
  4. 自訂字型資料存取層更新 URI＋`FontManagementScreen` 失效標示與重新連結
