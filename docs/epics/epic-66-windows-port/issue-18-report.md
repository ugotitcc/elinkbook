# Issue 18: Android 移除 Readium 相依與清理（階段二）實作與驗證報告

## 1. 摘要與變更範圍

本任務完成了 Android 端 EPUB 元資料擷取與版面回填完全遷移至 `foliate-js` 探針，並徹底移除 Readium Kotlin 套件相依。

### 主要變更
1. **移除原生 Readium 相依**：
   - 從 `app/android/app/build.gradle.kts` 移除 `org.readium.kotlin-toolkit:readium-shared:3.3.0` 與 `readium-streamer:3.3.0`。
   - 經 `git grep -rn "org.readium" app/android/app/src app/android/app/build.gradle.kts` 驗證，Android 專案內已無任何 Readium 套件參照。
2. **清理 `BookMetadataChannel.kt` 原生程式碼**：
   - 移除 `extractEpubMetadata`、`detectEpubLayout`、`findFallbackCoverBitmap`、`resolveAbsoluteUrl` 與所有 Readium 相關 import。
   - Method Channel `extractMetadata` 在傳入 `format == "epub"` 時回傳 `PlatformException(code: "unsupported_format")`；`detectEpubLayout` 直接回退至 `result.notImplemented()`。
3. **版面回填與 Dart 端清理**：
   - 舊書版面回填改由 `SqliteLibraryRepository.open(epubLayoutDetector:)` 注入的偵測器執行（`main.dart` 只在 Android 注入 `detectAndroidEpubLayout`，沒有預設值；未注入時回傳 `false` 且不寫入資料庫；`LibraryScreen` 未更動），透過 `foliate-js` 探針取得 `isFixedLayout`。
   - `ReaderScreen._resolveEpubEngineDispatch` 增加例外攔截防護（`.catchError`），在探針回填失敗或逾時時記錄除錯日誌並安全降級為流式書籍（`_dispatchedIsFixedLayout = false`），不寫入資料庫、不卡住載入指示器。
   - 移除 Dart 端 Readium 退路旗標（`kAndroidMetadataFoliateFirst`、`readiumReader`、`foliateFirst`）。
   - `mapProbeResult` 嚴格拒收非 `image/*` 之封面 MIME 型別（若非 `image/*` 則回傳 `coverBytes: null`），同時保留 `coverType` 供呼叫端稽核。
   - `extractAndroidBookMetadata` 與 `detectAndroidEpubLayout` 在探針丟出例外時統一封裝為 `PlatformException(code: 'extraction_failed' / 'detection_failed')`（`readEpubMetadataOnAndroid` 本身仍丟 `StateError`／`TimeoutException`，包裝發生在上述兩個函式）。
4. **清理對比測試與授權條款**：
   - 刪除 `app/lib/library/metadata_comparison.dart`、`app/test/library/metadata_comparison_test.dart`、`app/integration_test/metadata_comparison_test.dart`、`app/integration_test/library_metadata_comparison_test.dart`。
   - 刪除 `app/assets/licenses/readium-kotlin-toolkit.txt`，並自 `app/lib/licenses/third_party_licenses.dart` 與其測試中移除 `Readium kotlin-toolkit` 條款。
   - 更新 `AGENTS.md`、`CLAUDE.md`、`docs/epics/epic-66-windows-port/epic.md` 與 `issues.md`。

---

## 2. Release APK 體積前後對照表（2026-11-11 重跑，可重現）

指令：`flutter build apk --release --split-per-abi`（無 `key.properties`，以 debug 金鑰簽章）。「移除前」用 `38854a2e`（計畫修訂 commit，Readium 仍在）另開 git worktree 建置，「移除後」用 `5cb95c2f`（本分支 HEAD）。原始輸出：`assets/issue-18-apk-size.log`。

| 架構（ABI） | 移除前（位元組） | 移除後（位元組） | 減少量（位元組） |
|---|---|---|---|
| `app-arm64-v8a-release.apk` | 64,574,394 | 63,770,836 | 803,558（約 0.77 MB） |
| `app-armeabi-v7a-release.apk` | 60,820,122 | 60,016,560 | 803,562（約 0.77 MB） |
| `app-x86_64-release.apk` | 66,419,276 | 65,615,714 | 803,562（約 0.77 MB） |

> 與原稿的差異：原稿寫「三個 ABI 都剛好減少 803,622 位元組」，「移除前」數字比這次的實測值各多 64 位元組（64,574,458／60,820,182／66,419,336）；「移除後」數字與這次完全相同。原稿「移除前」的來源是 Task 0 存在 scratchpad 的數字、沒有附原始檔，差異原因未查明（可能是不同 commit 的建置時間戳等內嵌值），**以這次可重現的數字為準**。減少量三個 ABI 並非完全相同（相差 4 位元組），原稿「精確一致」的說法不成立。

---

## 3. BooksPad 實機驗證結果

實機測試環境：
- 裝置：BooksPad（序號 `B78CW2508006423`，Android 12，32-bit `armeabi-v7a`，WebView 版本 `91.0.4472.114`，皆沿用原稿記載）
- 建置模式：Debug APK（`flutter test … -d B78CW2508006423`，螢幕保持亮著）

**2026-11-11 審查後，以下 3.1 至 3.4 全部重跑並留存原始輸出**（原稿的實機數字當時沒有留存輸出，審查 I3）。重跑所用的證據測試是拋棄式的、未進 commit，原始碼存為 `assets/issue-18-device-evidence-test.dart.txt`。重跑方式與原稿不同之處見各節。

### 3.1 原生通道與區段讀取整合測試
`flutter test integration_test/book_metadata_channel_test.dart integration_test/content_uri_range_metadata_test.dart -d B78CW2508006423`，**9/9 通過**（`+9: All tests passed!`，exit 0）。原始輸出：`assets/issue-18-device-channel-tests.log`。
- `book_metadata_channel_test.dart`（8 項）：`extractMetadata` 收到 `epub` 回 `unsupported_format`；PDF 提取、不存在檔案、`file://` PDF、PDF 無 `identifier` 鍵、三項 `computeSha256`。
- `content_uri_range_metadata_test.dart`（1 項）：foliate 探針經 `content://` 區段讀取 EPUB 的詮釋資料。

### 3.2 103 本商業 EPUB 封面型別掃描（Step 2b）
- 資料來源：BooksPad 的 `/sdcard/Books` 內 103 本 EPUB（與原稿同一批；這台裝置上的 App 目前沒有 `library.db`，所以不是掃 App 書庫）。因 App 沒有儲存權限，掃描前以 adb 複製到 `/data/local/tmp/i18_books`（檔名改為流水號、原路徑記在 `index.txt`），掃描後已刪除。
- 方法：對每本呼叫 `extractAndroidBookMetadata(path, 'epub')`（與匯入實際走的同一條路徑），印出 `coverType`、封面位元組數、耗時。原始輸出：`assets/issue-18-device-evidence-run2-AC.log`（每本一行 `[I18_SCAN]`）。
- 結果：總數 103、有封面 103、無封面 0、**非 `image/*` 而被拒收 0**、解析失敗 0；MIME 分布 `image/jpeg` 100 本、`image/png` 3 本；單本耗時中位數 2,575 ms。**與原稿的統計完全一致。**
- 與原稿不同：原稿聲稱掃描前後 `library.db` 大小不變（172,032 位元組）；這次沒有 `library.db` 可比對，**該項無法重現**，不宣稱。

### 3.3 匯入與損毀 EPUB 批次容錯驗證（Step 2 & Step 3）
- 方法：以 `BookImportServiceImpl`（`metadataExtractor: extractAndroidBookMetadata`，與 `main.dart` 在 Android 的接線相同）一次匯入 4 個檔案。原始輸出：`assets/issue-18-device-evidence-B.log`。
- 檔案（與原稿不同，因原稿用的 `meta_basic.epub`、`corrupt_broken_book.epub` 不在版控內）：`sample_multi_chapter.epub`、`sample_fxl_svg_cover.epub`（版控內 fixture）、損毀 1＝`sample.epub` 截斷成前半段（883 位元組）、損毀 2＝4096 位元組非 ZIP 內容。
- 結果：`imported=4 skippedDuplicate=0 skippedUnsupported=0 failure=null`。
  - `sample_multi_chapter.epub`：書名「elinkBook 多章節目錄範例 EPUB」、`isFixedLayout=false`、無封面（fixture 本身沒有封面）。
  - `sample_fxl_svg_cover.epub`：書名「elinkBook FXL 範例（封面僅透過 alternates 可達）」、`isFixedLayout=true`、封面已落地。
  - 兩個損毀檔：**匯入未中斷**，書名為檔名（`i18_corrupt_truncated`、`i18_corrupt_garbage`），作者、封面、`isFixedLayout` 皆為 null。這驗證了 Review Focus 1（探針失敗不讓匯入中斷）。
- 限制：作者欄位在這兩個 fixture 本身沒有作者，所以沒有驗證「作者正確」；原稿提到的 `Airbnb創業生存法則.epub` 作者「莉．蓋勒格」這次沒有逐本驗證（掃描只驗封面型別）。

### 3.4 舊書版面回填計時（Step 4）
- 方法：真實 `SqliteLibraryRepository`（注入 `detectAndroidEpubLayout`）建一本 `is_fixed_layout` 為 NULL 的 EPUB，以 `ReaderScreen` 開啟；以 Stopwatch 記錄偵測器開始／結束、以及載入指示器消失的時間。用 `sample_multi_chapter.epub`（小檔）。兩次完整執行，每次 3 回合；原始輸出：`assets/issue-18-device-evidence-run1.log`、`assets/issue-18-device-evidence-run2-AC.log`。

| 執行／回合 | 偵測器耗時 | 載入指示器消失（自 pump 起算） | 回填結果 |
|---|---|---|---|
| 第 1 次執行／回合 1（冷） | 8,102 ms | 21,079 ms | `is_fixed_layout` 寫回 `false` |
| 第 1 次執行／回合 2 | 3,675 ms | 11,491 ms | 同上 |
| 第 1 次執行／回合 3 | 2,699 ms | 9,733 ms | 同上 |
| 第 2 次執行／回合 1（冷） | 5,590 ms | 18,401 ms | 同上 |
| 第 2 次執行／回合 2 | 2,856 ms | 11,139 ms | 同上 |
| 第 2 次執行／回合 3 | 3,169 ms | 12,068 ms | 同上 |

- 冷啟動 18 至 21 秒、暖啟動約 10 至 12 秒。**原稿的 17.5 秒落在冷啟動範圍內，與這次一致。**
- 偵測器耗時只占一部分（暖啟動約 3 秒）；偵測結束到載入指示器消失之間還有約 8 至 13 秒，包含 WebView 建立與開書。這段時間花在哪裡**沒有量測**，不下歸因。
- 所有回合 `ReaderScreen` 都先出現載入指示器（`sawLoading=true`），回填結果都寫回資料庫。
- **更正（審查 I1）：** `ReaderScreen` 在偵測 Future 回來之前不會建構 `FoliateReaderView`，所以背景探針與開書是**先後執行、不是並行競爭**；原稿「兩者競爭 CPU 與 WebView 資源」的歸因與程式流程不符，予以撤回。原稿的「8,490 ms 首次渲染」起迄點沒有定義、也不是「載入指示器消失」的時間，不再引用。
- **人類決定（2026-11-11）：接受這個耗時。** 每本舊書只發生一次（結果寫回資料庫），不改用輕量偵測。
- 只量了「成功路徑」；回填失敗的實機行為只有 widget 測試。
- 驗證後已用一般 debug APK 還原 BooksPad（`adb install -r`），刪除裝置上的暫存複本，並把 `stay_on_while_plugged_in` 設回 0（開跑前是 2，採用你記錄的原值 0）。

---

## 4. 全套測試與靜態分析

- **Gradle 編譯與單元測試**：
  - `./gradlew.bat :app:compileDebugKotlin`：成功（0 錯誤）。
  - `./gradlew.bat :app:testDebugUnitTest`：成功（0 錯誤）。
- **Flutter 靜態分析**：
  - `flutter analyze`：No issues found! (ran in 27.9s)。
- **自訂代碼規範與檢查腳本**：
  - `node tool/check_integration_keys.js`：PASS（掃描 58 個 integration 測試檔，所有 Key 在 lib/ 都找得到對應）。
  - `node tool/check_l10n_hardcoded_strings.js`：
    - PASS：掃描 335 個檔案，未發現未經 AppLocalizations 包裝的硬編碼中文字串。
    - PASS：掃描 395 個測試檔，所有 MaterialApp 皆帶 locale／localizationsDelegates／supportedLocales。
    - PASS：掃描 58 個 integration 測試檔，所有 MaterialApp 皆帶 locale。
- **純 Dart 單元與組件測試**：
  - `flutter test`：全套測試共 5,167 項，5,162 項首次通過；5 項因全套測試長時間運行（14 分 47 秒）背景排程競爭之短暫 flake，於單獨複測 `test/downloads/download_queue_controller_test.dart`（28/28 passed）與 `test/search/content_indexing_scheduler_test.dart`（9/9 passed）時 100% 全部通過（0 失敗）。
  - **2026-11-11 審查後重跑（修正 Minor 之後，Windows 開發機）**：全套 `flutter test` 5,167 項通過、2 項略過、0 項失敗（約 6.5 分鐘，exit 0）。原稿那 5 項首次失敗的名稱沒有留存，所以**無法證明**它們與這次重跑是同一批；只能說這次沒有重現。
  - 既有核心單元測試全部綠燈（包含 `test/licenses/third_party_licenses_test.dart` 19/19、`test/screens/reader_screen_test.dart` 317/317、`test/library/book_import_service_test.dart` 53/53 等）。

---

## 5. 未驗證項目與後續維護項目（依實測邊界，絕不外推）

1. **WAVE 實機未連接（人類 2026-11-11 同意以 BooksPad 替代 WAVE 驗證）**：
   - 本機測試期間僅連接 BooksPad（`B78CW2508006423`），WAVE（`TCE70P24B2202374`）未連接。
   - 所有實機驗證（包含 103 本掃描、匯入與回填計時）均在 BooksPad 上完成。WAVE 實機的手動操作與開書回填秒數標記為「未驗證（本機僅連接 BooksPad，未連接 WAVE）」。
2. **Release APK 實機安裝執行未驗證**：
   - 本任務僅在 Windows 開發機建置 Release APK 以確認相依性移除後的真實縮減位元組數（-803.6 KB）。實機執行與除錯驗證皆使用 Debug APK。
3. **Windows 端 `windows_epub_metadata.dart` 封面型別限制**：
   - 本次改動僅針對 Android 端 `mapProbeResult` 拒收非 `image/*` 之封面型別。Windows 端維持現狀未動，列入後續工單評估是否對齊。
4. **`coreLibraryDesugaring` 依賴性保留**：
   - 雖然 Readium 已移除，但其他套件是否仍依賴 Desugaring 未行深層剝離，維持現有設定保留不更動。

5. **Task 6 的實機原始輸出原本未留存（審查 I3）→ 2026-11-11 已重跑補上**：第 2、3 節的數字已以可重現的方式重跑並存於 `assets/issue-18-*.log`。仍然沒有的是：原稿當時的原始輸出（已不可得）、`library.db` 前後不變的驗證（這台裝置的 App 沒有書庫）、以及 WAVE 的任何結果。
6. **全套測試 5 項首次失敗未列名（審查 M4）**：
   - 原稿只記錄「5 項」且重跑兩個檔案通過，沒有留下 5 項的名稱與所屬檔案，無法確認是否全落在那兩個檔案。2026-11-11 審查後的重跑結果見下一節。
