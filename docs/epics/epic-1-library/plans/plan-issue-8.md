# Issue 8 實作計劃：資料夾批次匯入 + 匯入自動分類

> **給執行的 Agent：** 建議使用 superpowers:subagent-driven-development（推薦）或 superpowers:executing-plans 逐任務執行本計劃。步驟採用核取方塊（`- [ ]`）語法追蹤進度。

**目標：** 擴充 `BookImportService`，實作 `importFolder(folderUri, {autoGroupByFolderName = true})`：批次匯入一個資料夾內所有支援格式的檔案，並依 `autoGroupByFolderName` 開關決定是否依資料夾名稱自動建立/歸入分類群組。

**架構：** 這個功能無法單靠 `file_picker` 完成——已對照套件實際的 Android 原生實作原始碼（`FileUtils.kt`）確認 `FilePicker.getDirectoryPath()` 在 Android 上**不會**回傳真正的 `content://.../tree/...` URI，而是用文件 ID 字串猜測重建的檔案系統路徑（套件文件自承對受保護路徑會失敗回傳 `/`），這種猜測路徑無法拿來做可靠的 SAF 目錄列舉。因此本工單繞過 `file_picker` 的資料夾選取功能，新增一個獨立的原生 MethodChannel（`elinkbook/folder_picker`），用 AndroidX 標準的 `ActivityResultContracts.OpenDocumentTree()` 取得真正的 tree URI 並立即持久化權限；資料夾內容列舉則透過既有的 `elinkbook/book_metadata` channel 新增 `listFolderContents` 方法，用 `androidx.documentfile.provider.DocumentFile` 列出子檔案。`BookImportServiceImpl.importFolder()` 呼叫這兩個原生方法取得 `{folderName, fileUris}`，再重用既有的單檔匯入邏輯（`_importSingleFile`，新增一個 `takePermission` 參數控制是否要對個別檔案再次持久化權限——資料夾內的子檔案 URI 共用資料夾層級已取得的權限，不需要、也不應該對每個子檔案再呼叫一次 `takePersistableUriPermission`，因為子文件 URI 是否支援獨立的 persistable 授權是不確定的平台行為）。

**技術棧：** Flutter（Dart）、Kotlin（`androidx.activity.result.contract.ActivityResultContracts.OpenDocumentTree`、`androidx.documentfile.provider.DocumentFile`，兩者皆為 AndroidX 標準 API）、既有的 `elinkbook/book_metadata` channel（Issue 2/4，擴充新方法）。

## ⚠️ 執行前環境確認事項

Task 1 為純 Dart，不需裝置。Task 2 涉及新的原生 Android 程式碼（`ActivityResultContracts.OpenDocumentTree`／`DocumentFile` 是本專案首次使用，先前的原生擴充都是既有 channel 新增方法，這次額外新增了一個 Activity 層級的 Activity Result launcher）——**執行前請先確認 `flutter devices` 能列出至少一個 Android 裝置/模擬器**，且務必在真實裝置上實際建置執行，不要只憑程式碼審閱斷定原生部分正確。若編譯或執行期出現與本計劃程式碼不符的錯誤（例如 API 簽章差異），依實際情況修正並在報告中記錄差異（比照 Issue 4 決解 Readium 原生 API 簽章落差的做法）。

## Global Constraints（全域限制條件）

- `BookImportService`/`BookImportServiceImpl` 的既有公開簽章不得變更：`Future<List<Book>> importFolder(String folderUri, {bool autoGroupByFolderName = true})`（已在 Issue 4 宣告）。
- `_importSingleFile` 既有的 `importFiles()`（單檔/多檔匯入）行為**不得改變**——新增的 `takePermission` 參數預設值必須是 `true`，讓既有呼叫路徑維持逐字相同的行為。
- 資料夾層級的 URI 權限只在**兩處**持久化：(1) 原生 `MainActivity` 的 `ActivityResultContracts.OpenDocumentTree()` 回呼中，選取資料夾後立即呼叫 `takePersistableUriPermission`；(2) `BookImportServiceImpl.importFolder()` 內再呼叫一次既有的 `takePersistableUriPermission`（防禦性重試，冪等安全）。資料夾內個別子檔案的 URI **不得**再呼叫 `takePersistableUriPermission`——這是本計劃刻意的架構決策，避免依賴不確定的子文件層級持久化授權行為。
- `androidx.documentfile:documentfile:1.0.1` 依賴須明確加入 `app/android/app/build.gradle.kts`，不得依賴未宣告的隱性遞移依賴。
- `registerForActivityResult` 必須以類別層級屬性（property initializer）的方式註冊在 `MainActivity`，不得放在 `configureFlutterEngine()` 方法內——AndroidX 要求它必須在 Activity 進入 STARTED 生命週期之前呼叫，屬性初始化是官方建議的正確寫法。
- `BookMetadataChannel.kt`（Issue 2/4）既有的 `extractMetadata`／`takePersistableUriPermission`／`createTestContentUri` 方法與其內部邏輯**不得修改**，只能新增 `listFolderContents` 這個方法。
- 新增的 Key：`Key('library_import_files_option')`（匯入選單「選擇檔案」）、`Key('library_import_folder_option')`（匯入選單「選擇資料夾」）、`Key('library_import_folder_auto_group_checkbox')`（自動分類開關）、`Key('library_import_folder_confirm')`（確認匯入資料夾）。
- `LibraryScreen` 既有的公開建構子與其餘既有 Key（`library_view_mode_toggle`、`library_sort_button`、`library_sort_option_<name>`、`library_empty_import_button`、`library_grid_view`、`library_list_view`、`book_item_<id>`、分類群組相關 Key）**不得**變更語意。`library_import_button` 這個 Key 底層元件會從單一動作的 `IconButton` 改為 `PopupMenuButton`（提供「選擇檔案」/「選擇資料夾」兩個選項）——這是 `design.md` 從最初設計就預期的行為（「匯入入口：LibraryScreen AppBar 新增匯入按鈕（單檔/多檔/資料夾三選項）」），不是語意變更；既有測試只檢查這個 Key 存在（`findsOneWidget`），不受影響。
- 所有 UI 文字、對話框文字與程式註解維持正體中文。

---

### Task 1：`BookImportService.importFolder()` 核心邏輯（純 Dart）

**Files:**
- Modify: `app/lib/library/book_import_service_impl.dart`
- Modify: `app/test/library/book_import_service_test.dart`

**Interfaces:**
- Consumes：既有 `elinkbook/book_metadata` channel 的 `takePersistableUriPermission`（Issue 4，已存在，不異動）。本任務假設原生端已新增 `listFolderContents(uri: String) -> { folderName: String, fileUris: List<String> }`（Task 2 才會真正實作原生端，本任務用 mock 驅動）。
- Produces：`_importSingleFile` 新增的 `takePermission` 參數（預設 `true`）——Task 2 的 UI 層不會直接呼叫 `_importSingleFile`（它是 private 方法），但需要知道 `importFolder()` 內部呼叫 `_importSingleFile` 時一律傳入 `takePermission: false`，這樣 Task 2 的手動驗證才能正確理解「資料夾匯入不會對子檔案逐一要求權限」這個行為。

- [ ] **Step 1：移除過時的「尚未實作」測試，寫失敗測試（批次匯入）**

修改 `app/test/library/book_import_service_test.dart`：在檔案最上方 `import` 區塊補上：

```dart
import 'package:elinkbook/library/models/book_group.dart';
```

刪除檔案末尾這個測試（因為 `importFolder` 即將被實作，不再拋出 `UnimplementedError`）：

```dart
  test('importFolder 尚未實作，呼叫時拋出 UnimplementedError', () async {
    expect(
      () => service.importFolder('content://example/folder'),
      throwsA(isA<UnimplementedError>()),
    );
  });
```

在同一個位置（檔案末尾、`}` 之前）改為新增以下四個測試：

```dart
  test('批次匯入資料夾內多個檔案，皆正確寫入 LibraryRepository', () async {
    mockChannel((call) async {
      if (call.method == 'takePersistableUriPermission') return null;
      if (call.method == 'listFolderContents') {
        return {
          'folderName': '歷史小說',
          'fileUris': [
            'content://example/tree/folder/document/book1.epub',
            'content://example/tree/folder/document/book2.pdf',
          ],
        };
      }
      return {'title': null, 'author': null, 'coverBytes': null};
    });

    final books = await service.importFolder('content://example/tree/folder');

    expect(books, hasLength(2));
    final savedBooks = await repository.listBooks();
    expect(savedBooks, hasLength(2));
  });

  test('autoGroupByFolderName=true 且群組不存在時，自動建立同名群組並歸入', () async {
    mockChannel((call) async {
      if (call.method == 'takePersistableUriPermission') return null;
      if (call.method == 'listFolderContents') {
        return {
          'folderName': '歷史小說',
          'fileUris': ['content://example/tree/folder/document/book1.epub'],
        };
      }
      return {'title': null, 'author': null, 'coverBytes': null};
    });

    final books = await service.importFolder(
      'content://example/tree/folder',
      autoGroupByFolderName: true,
    );

    expect(books.single.groupName, '歷史小說');
    final groups = await repository.listGroups();
    expect(groups.map((g) => g.name), contains('歷史小說'));
  });

  test('autoGroupByFolderName=true 且群組已存在時，直接歸入既有群組、不重複建立',
      () async {
    await repository.upsertGroup('歷史小說');
    mockChannel((call) async {
      if (call.method == 'takePersistableUriPermission') return null;
      if (call.method == 'listFolderContents') {
        return {
          'folderName': '歷史小說',
          'fileUris': ['content://example/tree/folder/document/book1.epub'],
        };
      }
      return {'title': null, 'author': null, 'coverBytes': null};
    });

    await service.importFolder('content://example/tree/folder');

    final groups = await repository.listGroups();
    expect(groups.where((g) => g.name == '歷史小說'), hasLength(1));
  });

  test('autoGroupByFolderName=false 時，匯入書籍歸入預設「未分類」', () async {
    mockChannel((call) async {
      if (call.method == 'takePersistableUriPermission') return null;
      if (call.method == 'listFolderContents') {
        return {
          'folderName': '歷史小說',
          'fileUris': ['content://example/tree/folder/document/book1.epub'],
        };
      }
      return {'title': null, 'author': null, 'coverBytes': null};
    });

    final books = await service.importFolder(
      'content://example/tree/folder',
      autoGroupByFolderName: false,
    );

    expect(books.single.groupName, BookGroup.uncategorized);
  });
```

- [ ] **Step 2：執行測試，確認失敗**

Run: `flutter test test/library/book_import_service_test.dart -v`
Expected: FAIL（`importFolder` 目前仍拋出 `UnimplementedError`）

- [ ] **Step 3：實作 `importFolder()` 與 `_importSingleFile` 的 `takePermission` 參數**

修改 `app/lib/library/book_import_service_impl.dart`：把 `_importSingleFile` 方法簽章改為：

```dart
  Future<Book?> _importSingleFile(
    String uri, {
    String? folderName,
    bool takePermission = true,
  }) async {
    final format = detectBookFileFormat(uri);
    if (format == null) return null;

    // 只對 content:// scheme 持久化權限（file_picker 在 Android 上一定回傳
    // content:// URI；此判斷主要防禦測試/除錯情境誤傳純路徑）。持久化失敗
    // 時（例如來源 URI 不支援 persistable 權限）視為這個檔案匯入失敗並略過
    // ——不能假裝成功寫入資料庫，因為當次的暫時讀取權限只在本次 App 行程
    // 存活期間有效，寫入的 filePath 極可能在下次啟動後無法讀取，那會是比
    // 略過更糟的靜默壞資料。資料夾批次匯入（importFolder）的子檔案 URI 共用
    // 資料夾層級已取得的權限，呼叫時傳入 takePermission: false 跳過這一步。
    if (takePermission && uri.startsWith('content://')) {
      try {
        await _channel.invokeMethod<void>(
          'takePersistableUriPermission',
          {'uri': uri},
        );
      } on PlatformException {
        return null;
      }
    }
```

（方法其餘內容——`id`/`fallbackTitle`/`now`/`title`/`author`/`coverPath` 的宣告與後續 TXT/EPUB/PDF 分支邏輯、最終 `Book(...)` 建構與 `_repository.insertBook(book)` 呼叫——逐字不變，只有上面這段開頭的簽章與註解需要修改。）

在 `_importSingleFile` 方法之前（`importFiles` 方法之後），把 `importFolder` 從空殼改為：

```dart
  @override
  Future<List<Book>> importFolder(
    String folderUri, {
    bool autoGroupByFolderName = true,
  }) async {
    try {
      await _channel.invokeMethod<void>(
        'takePersistableUriPermission',
        {'uri': folderUri},
      );
    } on PlatformException {
      return [];
    }

    Map<Object?, Object?>? contents;
    try {
      contents = await _channel.invokeMapMethod<Object?, Object?>(
        'listFolderContents',
        {'uri': folderUri},
      );
    } on PlatformException {
      return [];
    }
    if (contents == null) return [];

    final folderName = contents['folderName'] as String?;
    final fileUris =
        (contents['fileUris'] as List?)?.cast<String>() ?? const [];

    final groupName =
        autoGroupByFolderName && folderName != null && folderName.isNotEmpty
            ? folderName
            : null;

    if (groupName != null) {
      await _repository.upsertGroup(groupName);
    }

    final imported = <Book>[];
    for (final uri in fileUris) {
      final book = await _importSingleFile(
        uri,
        folderName: groupName,
        takePermission: false,
      );
      if (book != null) imported.add(book);
    }
    return imported;
  }
```

- [ ] **Step 4：執行測試，確認通過**

Run: `flutter test test/library/book_import_service_test.dart -v`
Expected: 全數 PASS

- [ ] **Step 5：執行完整測試與靜態分析**

Run: `flutter test`
Expected: 全數 PASS

Run: `flutter analyze`
Expected: `No issues found!`

- [ ] **Step 6：Commit**

```bash
git add app/lib/library/book_import_service_impl.dart app/test/library/book_import_service_test.dart
git commit -m "feat: implement BookImportService.importFolder batch import logic"
```

---

### Task 2：原生資料夾選取 + 內容列舉 + UI 整合 + 手動驗證

**Files:**
- Modify: `app/android/app/build.gradle.kts`（新增 `androidx.documentfile` 依賴）
- Modify: `app/android/app/src/main/kotlin/cc/ugotit/elinkbook/MainActivity.kt`
- Modify: `app/android/app/src/main/kotlin/cc/ugotit/elinkbook/BookMetadataChannel.kt`
- Modify: `app/lib/screens/library_screen.dart`
- Modify: `app/test/screens/library_screen_test.dart`

**Interfaces:**
- Consumes：Task 1 的 `BookImportServiceImpl.importFolder()`（已完整實作，本任務只需要提供它呼叫的原生方法真正的實作，並在 UI 層呼叫它）。
- Produces：新原生 channel `elinkbook/folder_picker` 的 `pickFolder() -> String?`（回傳使用者選取的資料夾 tree URI，取消則為 `null`）；`elinkbook/book_metadata` 新增的 `listFolderContents(uri: String) -> { folderName: String, fileUris: List<String> }`。本工單為 Issue 8 最後一個任務，無後續工單依賴這些細節。

- [ ] **Step 1：新增 `androidx.documentfile` 依賴**

修改 `app/android/app/build.gradle.kts`，在 `dependencies { ... }` 區塊內新增一行：

```kotlin
    implementation("androidx.documentfile:documentfile:1.0.1")
```

（完整區塊會是：）

```kotlin
dependencies {
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.5")

    implementation("org.readium.kotlin-toolkit:readium-shared:3.3.0")
    implementation("org.readium.kotlin-toolkit:readium-streamer:3.3.0")
    implementation("org.readium.kotlin-toolkit:readium-navigator:3.3.0")

    implementation("org.jetbrains.kotlinx:kotlinx-coroutines-android:1.11.0")
    implementation("androidx.fragment:fragment-ktx:1.8.9")
    implementation("androidx.documentfile:documentfile:1.0.1")
}
```

- [ ] **Step 2：`MainActivity` 新增資料夾選取的 Activity Result launcher + `elinkbook/folder_picker` channel**

整檔改寫 `app/android/app/src/main/kotlin/cc/ugotit/elinkbook/MainActivity.kt`：

```kotlin
package cc.ugotit.elinkbook

import android.content.Intent
import android.os.Bundle
import androidx.activity.result.contract.ActivityResultContracts
import androidx.fragment.app.commitNow
import io.flutter.embedding.android.FlutterFragmentActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import org.readium.r2.navigator.epub.EpubNavigatorFragment

class MainActivity : FlutterFragmentActivity() {
    private lateinit var bookMetadataChannel: BookMetadataChannel

    // 選擇資料夾的結果狀態（Issue 8）。registerForActivityResult 必須在
    // Activity 進入 STARTED 生命週期之前呼叫，因此以類別層級屬性初始化
    // （AndroidX 官方建議寫法），不放在 configureFlutterEngine() 內。
    private var pendingFolderPickResult: MethodChannel.Result? = null

    private val openDocumentTreeLauncher =
        registerForActivityResult(ActivityResultContracts.OpenDocumentTree()) { uri ->
            val result = pendingFolderPickResult
            pendingFolderPickResult = null
            if (uri != null) {
                try {
                    contentResolver.takePersistableUriPermission(
                        uri,
                        Intent.FLAG_GRANT_READ_URI_PERMISSION,
                    )
                } catch (e: Exception) {
                    // 權限持久化失敗時仍回傳 URI；BookImportServiceImpl.importFolder()
                    // 呼叫端會再嘗試一次 takePersistableUriPermission，失敗則視為
                    // 整個資料夾無法匯入（見 docs/epics/epic-1-library/spec.md）。
                }
            }
            result?.success(uri?.toString())
        }

    override fun onCreate(savedInstanceState: Bundle?) {
        // Android 在 process death 後重建這個 Activity 時，會嘗試用已儲存的
        // FragmentManager 狀態還原先前掛載的 EpubNavigatorFragment；但它的建構子是
        // internal，且用來建立它的 EpubNavigatorFactory（綁定特定 Publication）已隨
        // 行程一起消失，若不處理，預設的 FragmentFactory 會因無法呼叫該建構子而崩潰。
        // 依 Readium 官方文件建議：先裝一個「dummy」FragmentFactory 讓還原程序本身不會
        // 崩潰；還原完成後，若真的有 EpubNavigatorFragment 被還原出來，必須在它進入
        // onResume() 之前立刻移除（dummy fragment 一旦 onResume() 就會主動拋出
        // RestorationNotSupportedException）。這裡刻意不是「整個 Activity 一律
        // finish()」——本 App 只有單一 Activity，涵蓋書架/設定等所有畫面，process
        // death 後重建時不見得有任何 EpubReaderView 曾經存在，不應該無條件關閉整個
        // App；只有在真的偵測到被還原的 EpubNavigatorFragment 時才需要處理。
        supportFragmentManager.fragmentFactory = EpubNavigatorFragment.createDummyFactory()
        super.onCreate(savedInstanceState)
        supportFragmentManager.fragments
            .filterIsInstance<EpubNavigatorFragment>()
            .forEach { restored ->
                supportFragmentManager.commitNow(allowStateLoss = true) { remove(restored) }
            }
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        flutterEngine
            .platformViewsController
            .registry
            .registerViewFactory(
                "cc.ugotit.elinkbook/pdf_reader_view",
                PdfReaderViewFactory(flutterEngine.dartExecutor.binaryMessenger),
            )
        flutterEngine
            .platformViewsController
            .registry
            .registerViewFactory(
                "cc.ugotit.elinkbook/epub_reader_view",
                EpubReaderViewFactory(this, flutterEngine.dartExecutor.binaryMessenger),
            )
        bookMetadataChannel =
            BookMetadataChannel(this, flutterEngine.dartExecutor.binaryMessenger)

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "elinkbook/folder_picker")
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "pickFolder" -> {
                        // 防禦性判斷：避免使用者在系統選取器實際開啟前重複觸發
                        // pickFolder（例如快速連續點擊），導致前一次呼叫的
                        // MethodChannel.Result 被覆蓋、永遠不會被 resolve。
                        if (pendingFolderPickResult != null) {
                            result.error(
                                "already_active",
                                "選取資料夾操作已在進行中",
                                null,
                            )
                            return@setMethodCallHandler
                        }
                        pendingFolderPickResult = result
                        openDocumentTreeLauncher.launch(null)
                    }
                    else -> result.notImplemented()
                }
            }
    }
}
```

- [ ] **Step 3：`BookMetadataChannel` 新增 `listFolderContents`**

修改 `app/android/app/src/main/kotlin/cc/ugotit/elinkbook/BookMetadataChannel.kt`：在檔案最上方的 `import` 區塊補上：

```kotlin
import androidx.documentfile.provider.DocumentFile
```

在 `onMethodCall` 的 `when (call.method) { ... }` 區塊內，於既有的 `"createTestContentUri" -> { ... }` 分支之後、`else -> result.notImplemented()` 之前，新增：

```kotlin
            "listFolderContents" -> {
                val uriString = call.argument<String>("uri")
                if (uriString == null) {
                    result.error("invalid_arguments", "缺少 uri 參數", null)
                    return
                }
                // DocumentFile.listFiles() 對 DocumentProvider 發出查詢，屬於跨
                // 行程 IPC（實質上是一次 SQLite 查詢），資料夾檔案數量多時會是
                // 阻塞式操作；比照既有 extractEpubMetadata/extractPdfMetadata
                // 的做法，移到 scope（Dispatchers.Main）搭配 withContext(Dispatchers.IO)
                // 執行，避免卡住 UI 執行緒導致 Jank 或 ANR。
                scope.launch {
                    try {
                        val (folderName, fileUris) = withContext(Dispatchers.IO) {
                            val folder =
                                DocumentFile.fromTreeUri(context, Uri.parse(uriString))
                            if (folder == null || !folder.isDirectory) {
                                throw IllegalArgumentException("無法讀取所選資料夾")
                            }
                            val uris = folder.listFiles()
                                .filter { it.isFile }
                                .map { it.uri.toString() }
                            Pair(folder.name ?: "", uris)
                        }
                        result.success(
                            mapOf(
                                "folderName" to folderName,
                                "fileUris" to fileUris,
                            ),
                        )
                    } catch (e: Exception) {
                        result.error(
                            "list_folder_failed",
                            "無法列出資料夾內容：${e.message}",
                            null,
                        )
                    }
                }
            }
```

（既有的 `extractMetadata`／`takePersistableUriPermission`／`createTestContentUri` 分支與 `extractEpubMetadata`／`extractPdfMetadata`／`bitmapToPngBytes` 等私有方法逐行不變。）

- [ ] **Step 4：`LibraryScreen` 匯入選單改為「選擇檔案」/「選擇資料夾」，新增自動分類確認對話框**

在 `app/lib/screens/library_screen.dart` 檔案最上方的 `import` 區塊補上：

```dart
import 'package:flutter/services.dart';
```

在既有的 `import 'reader_screen.dart';` 之前（或任一 import 之後皆可，維持風格一致即可）新增模組層級常數：

```dart
const _folderPickerChannel = MethodChannel('elinkbook/folder_picker');
```

在 `_LibraryScreenState` 內、`_pickAndImportFiles()` 方法之後，新增兩個方法：

```dart
  Future<void> _pickAndImportFolder() async {
    try {
      final folderUri =
          await _folderPickerChannel.invokeMethod<String>('pickFolder');
      if (folderUri == null) return;
      final autoGroup = await _confirmAutoGroupByFolderName();
      if (autoGroup == null) return;
      await widget.importService.importFolder(
        folderUri,
        autoGroupByFolderName: autoGroup,
      );
      await _loadGroups();
      await _loadBooks();
    } catch (_) {
      // 匯入失敗時靜默吞掉，避免異常傳播破壞 widget 樹或留下不一致狀態
    }
  }

  Future<bool?> _confirmAutoGroupByFolderName() {
    var autoGroup = true;
    return showDialog<bool>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('匯入資料夾'),
          content: CheckboxListTile(
            key: const Key('library_import_folder_auto_group_checkbox'),
            value: autoGroup,
            onChanged: (value) =>
                setDialogState(() => autoGroup = value ?? true),
            title: const Text('依資料夾名稱自動建立分類'),
            controlAffinity: ListTileControlAffinity.leading,
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: const Text('取消'),
            ),
            TextButton(
              key: const Key('library_import_folder_confirm'),
              onPressed: () => Navigator.of(dialogContext).pop(autoGroup),
              child: const Text('匯入'),
            ),
          ],
        ),
      ),
    );
  }
```

把 AppBar `actions` 陣列中既有的匯入 `IconButton`：

```dart
          IconButton(
            key: const Key('library_import_button'),
            icon: const Icon(Icons.add),
            tooltip: '匯入書籍',
            onPressed: _pickAndImportFiles,
          ),
```

改為：

```dart
          PopupMenuButton<void>(
            key: const Key('library_import_button'),
            icon: const Icon(Icons.add),
            tooltip: '匯入書籍',
            itemBuilder: (context) => [
              PopupMenuItem<void>(
                key: const Key('library_import_files_option'),
                onTap: _pickAndImportFiles,
                child: const Text('選擇檔案（可多選）'),
              ),
              PopupMenuItem<void>(
                key: const Key('library_import_folder_option'),
                onTap: _pickAndImportFolder,
                child: const Text('選擇資料夾'),
              ),
            ],
          ),
```

- [ ] **Step 5：寫失敗測試（匯入選單 → 選擇資料夾 → 確認自動分類 → 分類 tab 出現）**

在 `app/test/screens/library_screen_test.dart` 檔案最上方的 `import` 區塊補上：

```dart
import 'package:elinkbook/library/book_import_service_impl.dart';
```

在 `void main() { ... }` 內、既有測試之後，新增：

```dart
  testWidgets('點擊「選擇資料夾」，確認自動分類開關後，匯入資料夾內書籍並依資料夾名稱建立分類',
      (tester) async {
    const folderPickerChannel = MethodChannel('elinkbook/folder_picker');
    const metadataChannel = MethodChannel('elinkbook/book_metadata');
    addTearDown(() {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(folderPickerChannel, null);
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(metadataChannel, null);
    });
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(folderPickerChannel, (call) async {
      if (call.method == 'pickFolder') {
        return 'content://example/tree/folder';
      }
      return null;
    });
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(metadataChannel, (call) async {
      if (call.method == 'takePersistableUriPermission') return null;
      if (call.method == 'listFolderContents') {
        return {
          'folderName': '歷史小說',
          'fileUris': ['content://example/tree/folder/document/book1.epub'],
        };
      }
      return {'title': null, 'author': null, 'coverBytes': null};
    });

    final repository = FakeLibraryRepository();
    await tester.pumpWidget(
      MaterialApp(
        home: LibraryScreen(
          repository: repository,
          importService: BookImportServiceImpl(repository: repository),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('library_import_button')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('library_import_folder_option')));
    await tester.pumpAndSettle();

    expect(find.text('匯入資料夾'), findsOneWidget);

    await tester.tap(find.byKey(const Key('library_import_folder_confirm')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('library_group_tab_歷史小說')), findsOneWidget);
  });
```

（這個測試刻意使用真正的 `BookImportServiceImpl`（搭配同一個 `FakeLibraryRepository`），而非其他測試慣用的 `FakeBookImportService`——因為這個測試的目的正是驗證「UI 呼叫到真正的匯入服務、走完整條路徑」，`FakeBookImportService.importFolder()` 目前只是回傳空清單的空殼，無法驗證這個行為。`coverBytes` 皆回傳 `null`，因此不會觸發需要 `path_provider` 的封面落地邏輯，widget test 環境不需要額外處理。)

- [ ] **Step 6：執行測試，確認失敗**

Run: `flutter test test/screens/library_screen_test.dart -v`
Expected: FAIL（`library_import_folder_option`／`library_import_folder_confirm` 等 Key 尚不存在；`elinkbook/folder_picker` channel 尚未在 Dart 端使用）

- [ ] **Step 7：執行測試，確認通過**

（Step 1-4 的原生與 Dart 程式碼已是完整實作，此處直接驗證 Dart 端測試。原生程式碼本身無法透過純 Dart widget test 驗證，留給 Step 9 的真實裝置手動驗證。）

Run: `flutter test test/screens/library_screen_test.dart -v`
Expected: 全數 PASS

- [ ] **Step 8：執行完整測試與靜態分析**

Run: `flutter test`
Expected: 全數 PASS

Run: `flutter analyze`
Expected: `No issues found!`

Run（真實裝置，確認原生變更未破壞既有建置與啟動）：`flutter test integration_test/smoke_test.dart -d <device-id>`
Expected: `All tests passed!`

- [ ] **Step 9：Commit**

```bash
git add app/android/app/build.gradle.kts app/android/app/src/main/kotlin/cc/ugotit/elinkbook/MainActivity.kt app/android/app/src/main/kotlin/cc/ugotit/elinkbook/BookMetadataChannel.kt app/lib/screens/library_screen.dart app/test/screens/library_screen_test.dart
git commit -m "feat: wire folder import UI to native SAF directory picker and listing"
```

- [ ] **Step 10：手動驗證（對應驗收標準）**

在真實裝置上執行 `flutter run`，確認：
1. 準備一個真實資料夾（例如裝置的 `Download` 目錄下建立一個新資料夾），放入至少 2 本支援格式的書籍（EPUB/PDF/TXT 任意組合）。
2. 點擊書架的匯入按鈕，選擇「選擇資料夾」。
3. 在系統資料夾選擇器中選取步驟 1 準備的資料夾。
4. 確認彈出「依資料夾名稱自動建立分類」的核取方塊對話框，保持勾選並按「匯入」。
5. 匯入完成後，書架依資料夾名稱出現對應的分類 tab；點擊該 tab，確認資料夾內的書籍皆正確出現且能正常開啟閱讀。
6. 重複步驟 2-4，但這次取消勾選「依資料夾名稱自動建立分類」，確認匯入後的書籍歸入「未分類」而非新分類。

此步驟為手動驗證，不寫入自動化測試——與 Issue 4/5 對於需要真實系統選擇器互動的行為採用相同的處理方式（Android Instrumentation 環境下無法可靠驅動系統資料夾選擇器）。
