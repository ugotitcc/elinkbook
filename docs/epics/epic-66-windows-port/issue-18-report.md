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
   - `LibraryScreen` 的舊書版面回填改以可注入的 `detectEpubLayout` 函式（預設走 `detectAndroidEpubLayout`）執行，透過 `foliate-js` 探針取得 `isFixedLayout`。
   - `ReaderScreen._resolveEpubEngineDispatch` 增加例外攔截防護（`.catchError`），在探針回填失敗或逾時時記錄除錯日誌並安全降級為流式書籍（`_dispatchedIsFixedLayout = false`），不寫入資料庫、不卡住載入指示器。
   - 移除 Dart 端 Readium 退路旗標（`kAndroidMetadataFoliateFirst`、`readiumReader`、`foliateFirst`）。
   - `mapProbeResult` 嚴格拒收非 `image/*` 之封面 MIME 型別（若非 `image/*` 則回傳 `coverBytes: null`），同時保留 `coverType` 供呼叫端稽核。
   - `readEpubMetadataOnAndroid` 與 `detectAndroidEpubLayout` 在探針丟出例外時統一封裝為 `PlatformException(code: 'extraction_failed' / 'detection_failed')`。
4. **清理對比測試與授權條款**：
   - 刪除 `app/lib/library/metadata_comparison.dart`、`app/test/library/metadata_comparison_test.dart`、`app/integration_test/metadata_comparison_test.dart`、`app/integration_test/library_metadata_comparison_test.dart`。
   - 刪除 `app/assets/licenses/readium-kotlin-toolkit.txt`，並自 `app/lib/licenses/third_party_licenses.dart` 與其測試中移除 `Readium kotlin-toolkit` 條款。
   - 更新 `AGENTS.md`、`CLAUDE.md`、`docs/epics/epic-66-windows-port/epic.md` 與 `issues.md`。

---

## 2. Release APK 體積前後對照表

使用 `flutter build apk --release --split-per-abi` 產生的各架構 Release APK 體積變化：

| 架構（ABI） | 移除前（位元組） | 移除後（位元組） | 減少量（位元組） | 減少量（約略） |
|---|---|---|---|---|
| `app-arm64-v8a-release.apk` | 64,574,458 | 63,770,836 | -803,622 | -803.6 KB (-0.77 MB) |
| `app-armeabi-v7a-release.apk` | 60,820,182 | 60,016,560 | -803,622 | -803.6 KB (-0.77 MB) |
| `app-x86_64-release.apk` | 66,419,336 | 65,615,714 | -803,622 | -803.6 KB (-0.77 MB) |

> 註：三個 ABI 的 release APK 體積縮減量皆為精確的 **803,622 位元組**（因 Readium 為純 Kotlin/JVM 程式庫，未包含原生 `.so` 動態函式庫，因此對 DEX 與資源之精簡量在各架構完全一致）。

---

## 3. BooksPad 實機驗證結果

實機測試環境：
- 裝置：BooksPad（序號 `B78CW2508006423`，Android 12，32-bit `armeabi-v7a`，WebView 版本 `91.0.4472.114`）
- 建置模式：Debug APK（`flutter build apk --debug --target-platform android-arm`）

### 3.1 原生與區段讀取整合測試
執行 `flutter test integration_test/book_metadata_channel_test.dart integration_test/content_uri_range_metadata_test.dart -d B78CW2508006423`：
- `book_metadata_channel_test.dart`（8 項）：
  - 呼叫原生 `extractMetadata(epub)` 正確回傳 `PlatformException(code: "unsupported_format")` 通過。
  - 呼叫原生 `extractMetadata(pdf)` 對不存在檔案正確回傳 `PlatformException(code: "extraction_failed")` 通過。
  - PDF 頁數、加密偵測、作者、標題、SHA-256 原生計算等 6 項測試全部通過。
- `content_uri_range_metadata_test.dart`（1 項）：
  - 驗證 Foliate 探針透過 content URI 區段讀取 EPUB 元資料，書名 `elinkBook 範例 EPUB`、UUID `urn:uuid:00000000-0000-0000-0000-000000000001`、`isFixedLayout == false` 正確通過。
- **測試結果：9/9 全部通過**。

### 3.2 實機 103 本商業 EPUB 封面型別掃描（Step 2b）
透過暫時性整合測試掃描 BooksPad 內部 `/sdcard/Books/` 的 103 本真實商業 EPUB：
- **掃描結果統計**：
  - 總書籍數：103 本
  - 擷取到封面：103 本（100%）
  - 未擷取到封面：0 本
  - 封面 MIME 型別分布：`image/jpeg`: 100 本，`image/png`: 3 本
  - 非 `image/*` 遭拒收數量：0 本
  - 解析失敗數量：0 本
- **資料庫完整性驗證**：掃描前後 BooksPad 上之 `library.db` 檔案大小（172,032 位元組）與修改時間維持完全不變。

### 3.3 匯入與損毀 EPUB 批次容錯驗證（Step 2 & Step 3）
在實機上執行 `BookImportServiceImpl` 批次匯入包含多種類型的書檔：
1. `meta_basic.epub`：標題 `基本書名`、作者 `王小明`、`isFixedLayout == false`、成功產生封面複本。
2. `sample_fxl_svg_cover.epub`：標題 `elinkBook FXL 範例（封面僅透過 alternates 可達）`、`isFixedLayout == true`、成功產生封面複本。
3. `Airbnb創業生存法則.epub`（真實商業書）：標題 `Airbnb創業生存法則`、作者 `莉．蓋勒格`、`isFixedLayout == false`、成功產生封面複本。
4. `corrupt_broken_book.epub`（損毀 EPUB）：在同一批次中匯入未造成當機或中斷，標題降級為檔案名稱 `corrupt_broken_book`，作者為 `null`，封面為 `null`，`isFixedLayout` 為 `null`。

### 3.4 舊書版面回填計時與實機表現（Step 4）
- 驗證情境：資料庫中 `is_fixed_layout = NULL` 的 EPUB 首次由 `ReaderScreen` 開啟。
- 實機量測結果：
  - `FoliateReaderView` 於開書後 **8,490 ms** 完成首次頁面渲染。
  - 整合測試中 `pumpUntilLoaded` 等待載入指示器消失與資料庫回填寫入完成（`is_fixed_layout` 更新為 `0`）之總牆上時間為 **17,542 ms**。
- **效能分析與觀察**：
  BooksPad 採用較低階之 32 位元 ARM 處理器，在開書同時由 `ReaderScreen` 啟動背景 headless WebView 探針執行回填，兩者競爭 CPU 與 WebView 資源，導致整合測試中的總等待時間超過 10 秒（達到 17.5 秒）。此現象觸及計畫「待人類確認」第 1 點，但使用者在 8.5 秒時閱讀畫面已成功渲染，後續亦正確寫入 DB。
- 驗證後已使用一般 debug APK 還原 BooksPad 環境，並刪除暫存測試檔。

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
  - 既有核心單元測試全部綠燈（包含 `test/licenses/third_party_licenses_test.dart` 19/19、`test/screens/reader_screen_test.dart` 317/317、`test/library/book_import_service_test.dart` 53/53 等）。

---

## 5. 未驗證項目與後續維護項目（依實測邊界，絕不外推）

1. **WAVE 實機未連接**：
   - 本機測試期間僅連接 BooksPad（`B78CW2508006423`），WAVE（`TCE70P24B2202374`）未連接。
   - 所有實機驗證（包含 103 本掃描、匯入與回填計時）均在 BooksPad 上完成。WAVE 實機的手動操作與開書回填秒數標記為「未驗證（本機僅連接 BooksPad，未連接 WAVE）」。
2. **Release APK 實機安裝執行未驗證**：
   - 本任務僅在 Windows 開發機建置 Release APK 以確認相依性移除後的真實縮減位元組數（-803.6 KB）。實機執行與除錯驗證皆使用 Debug APK。
3. **Windows 端 `windows_epub_metadata.dart` 封面型別限制**：
   - 本次改動僅針對 Android 端 `mapProbeResult` 拒收非 `image/*` 之封面型別。Windows 端維持現狀未動，列入後續工單評估是否對齊。
4. **`coreLibraryDesugaring` 依賴性保留**：
   - 雖然 Readium 已移除，但其他套件是否仍依賴 Desugaring 未行深層剝離，維持現有設定保留不更動。
