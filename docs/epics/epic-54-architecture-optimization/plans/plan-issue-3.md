# Issue 3：字型重新連結搬出 Widget、持久化授權集中 實作計畫

> **給執行者：** 必要子技能：使用 `superpowers:subagent-driven-development`（建議）或 `superpowers:executing-plans` 逐 Task 執行本計畫。步驟使用 checkbox（`- [ ]`）語法追蹤進度；每完成一個 Step 就把它改為 `- [x]`。

**Goal：** 把字型重新連結的規則從 `FontManagementScreen` 搬進可獨立測試的 `CustomFontRelinker`（結果型別與書籍的 `BookRelinkResult` 並列對齊）、把散在 4 處的 `takePersistableUriPermission` 呼叫收攏成一個 `persistReadAccess()`，並讓兩個過去靜默的失敗（字型重新連結失敗、資料夾匯入失敗）有使用者可見的回饋。

**Architecture：** 新增 `app/lib/storage/storage_permission.dart`（`persistReadAccess`，只集中「呼叫與例外轉換」，各呼叫端的失敗處置不變）、`app/lib/reader/custom_font_relinker.dart`（`CustomFontRelinker`＋密封類別 `FontRelinkResult`）；`font_name_parser.dart` 新增 `resolveFontFamilyName`／`stripFontFileExtension` 讓上傳與重新連結共用同一條家族名稱規則；`ImportResult` 新增 `failure` 欄位。選檔器、SnackBar、`_relinkingIds` 按鈕停用、探測標示更新留在 Widget。

**Tech Stack：** Flutter／Dart、`flutter_test`、`sqflite`（既有）。指令一律在 `app/` 目錄下執行。

**Spec：** 沒有獨立的 `spec.md`，設計依據是 2026-10-01 `/grill-with-docs` 的決策，記錄於 `docs/epics/epic-54-architecture-optimization/epic.md`「Issue 3 設計決策」與 `CONTEXT.md`「持久化授權」詞條。

## 與設計決策的一處細部差異（寫計畫時讀程式發現）

設計表寫「`_stripExtension` 因 `displayName` 仍需要而保留（在畫面內）」。實際改完後，畫面內只剩 `displayName` 一處使用，而 `resolveFontFamilyName` 需要同一個去副檔名邏輯。為避免兩份私有實作，改為把它公開成 `stripFontFileExtension`（放在 `font_name_parser.dart`），畫面的私有 `_stripExtension` 刪除、改呼叫公開版。行為完全不變。

## Global Constraints

- **語言**：所有文件、註解、測試名稱一律正體中文（zh-TW），禁止簡體中文；程式碼命名維持英文慣例。
- **不動的東西**：`CustomFontsRepository` 介面（含 `updateUri`）、`BookImportService.relinkBook`／`BookRelinkResult` 家族、`probeStorageAccess`（Issue 4 才搬）、`FontManagementScreen` 對外建構參數（`repository`／`downloadableFontStore`／`pickSingleFontFile`）、`SingleFontFilePicker` typedef、所有既有 `Key`（`font_management_relink_button_$id`／`font_management_relink_progress_$id` 等）、`kBookMetadataChannel` 與 `takePersistableUriPermission` 這個原生方法名稱（`BookMetadataChannel.kt` 不動，既有測試以該 channel 名稱 mock）。
- **四處失敗處置維持不變**（只換成呼叫 `persistReadAccess()`）：書籍匯入／書籍重新連結失敗 → 複製到 App 私有目錄當退路（ADR 0029）；批次上傳字型、字型重新連結失敗 → 忽略、照常繼續（ADR 0021）；資料夾匯入失敗 → 中止（本 Issue 新增使用者回饋）。
- **兩處刻意的行為調整**：① 字型重新連結的 `FontRelinkFailed`（資料庫寫入失敗等）顯示 SnackBar，重用既有 l10n 鍵 `readerStorageRelinkFailed`，不改鍵名；② `importFolder` 的三條失敗路徑（授權失敗、列舉失敗、列舉為 null）回傳 `ImportResult.failure`，`showImportResultSnackBar` 顯示**一則**新訊息 `libraryImportFolderFailedMessage`（新增 1 個 ARB 鍵，同步 4 份：`app_zh_TW`／`app_zh`／`app_zh_CN`／`app_en`）。
- **不納入**：資料夾裡合法地沒有可匯入的書；`pickAndImportFolder`／`pickAndImportFiles` 的「選擇器例外一律靜默」；批次上傳時資料庫寫入失敗的回饋。
- **指令語法**：本計畫的指令是 bash 語法，用 Bash 工具（Git Bash）執行，路徑 `/c/Users/...` 與 `/tmp` 皆可用；若改用 PowerShell 需自行換成對應寫法。
- **Windows 環境**：`python` 在此環境不會實際執行（無輸出、檔案不變），不可用來編輯檔案；用 Edit 工具或 Node 腳本。多數原始檔是 CRLF 換行，Node 腳本要保留。Node 讀寫檔案時請使用 Windows 路徑（`C:/...`），bash 的 `/tmp` 與 Node 看到的不是同一個位置。
- **測試範圍**（CLAUDE.md）：單一 Task 只跑異動實際觸及的測試檔；完整 `flutter test`（無參數）只在最後一個 Task 跑一次（耗時約 6 分鐘，用 `run_in_background`）。
- **提交前**：`flutter analyze` 必須是 "No issues found!"，並跑 `node tool/check_l10n_hardcoded_strings.js`。
- **Commit 結尾**必須帶 `Co-Authored-By: Claude Sonnet 5.5 <noreply@anthropic.com>`。
- **流程**：直接 TDD；程式審查先出報告（存於 `reviews/`，該目錄 gitignore、不進版控），審查者不直接改程式；審查摘要放進 `epic.md`。

## Review Focus

以下是設計隱含、既有測試未涵蓋、最可能咬到使用者的情況（依可能性排序），每一條都有對應測試：

1. **字型家族名稱不符時，絕不能持久化授權、也不能改記錄。** 選錯檔案若先消耗系統的持久化授權配額或改了 URI，使用者的字型會被換成別的檔案。→ Task 3 純測試。
2. **資料夾匯入三條失敗路徑都要回報失敗；授權失敗時不得再嘗試列舉。** 授權失敗、`listFolderContents` 拋例外、回傳 null 目前都靜默。另外「合法的空資料夾」必須維持 `failure == null`，不能被誤判為失敗。→ Task 5 純測試。（失敗路徑都發生在取得資料夾名稱之前，本來就不會建立分類；測試仍以「群組名單前後不變」作為迴歸保護。資料庫建立時就預設有系統保留分類「未分類」，所以不能斷言群組清單為空。）
3. **持久化授權失敗時，書籍仍走複製退路。** 換成 `persistReadAccess()` 後，書籍匯入／重新連結在媒體庫文件提供者上不得退化。→ Task 5 跑既有「複製退路」測試（`book_import_service_test.dart` 的 `copyContentUriToFile` 群組）並新增一條明確斷言。
4. **字型授權失敗不中止重新連結與上傳**（ADR 0021）：`persistReadAccess` 回 `false` 仍要更新 URI；但授權函式本身拋出非預期例外時，`relink()` 必須回傳 `FontRelinkFailed` 而不是讓例外穿出（保證不拋）。→ Task 3 純測試。
5. **失敗訊息不得與成功計數混在一起。** `ImportResult.failure` 不為 null 時只顯示失敗訊息；`failure` 為 null 的既有匯入結果（含兩者皆 0 時不顯示）行為完全不變。→ Task 6 widget 測試與既有測試維持綠燈。

## File Structure

| 檔案 | 動作 | 責任 |
|---|---|---|
| `app/lib/storage/storage_permission.dart` | 新增 | `persistReadAccess(uri) → bool`，`PlatformException` 轉 `false` |
| `app/test/storage/storage_permission_test.dart` | 新增 | 上述函式的純測試 |
| `app/lib/reader/font_name_parser.dart` | 修改 | 新增 `stripFontFileExtension`、`resolveFontFamilyName` |
| `app/test/reader/font_name_parser_test.dart` | 修改 | 兩個新函式的測試 |
| `app/lib/reader/custom_font_relinker.dart` | 新增 | `CustomFontRelinker`、`FontRelinkResult` 家族、`PickedFontFile` |
| `app/test/reader/custom_font_relinker_test.dart` | 新增 | 重新連結規則的純測試 |
| `app/lib/screens/font_management_screen.dart` | 修改 | `_relinkFont` 改呼叫 relinker＋失敗 SnackBar；上傳改用 `persistReadAccess`／`resolveFontFamilyName`；刪私有 `_stripExtension` |
| `app/test/screens/font_management_screen_test.dart` | 修改 | 刪 1 個規則類測試、`updateUri` 寫入失敗測試補 SnackBar 斷言 |
| `app/lib/library/book_import_service.dart` | 修改 | `ImportFailure` 列舉、`ImportResult.failure` |
| `app/lib/library/book_import_service_impl.dart` | 修改 | `_persistPermissionOrLandCopy`／`importFolder` 改用 `persistReadAccess`；三條失敗路徑回傳 `failure` |
| `app/test/library/book_import_service_test.dart` | 修改 | 三條失敗路徑＋授權失敗仍複製的測試 |
| `app/lib/l10n/app_{zh_TW,zh,zh_CN,en}.arb`、`app_localizations*.dart` | 修改 | 新鍵 `libraryImportFolderFailedMessage`（`flutter gen-l10n` 產生） |
| `app/lib/screens/support/book_import_picker_helper.dart` | 修改 | `showImportResultSnackBar` 處理 `failure` |
| `app/test/screens/support/book_import_picker_helper_test.dart` | 修改 | 新增失敗訊息測試 |
| `docs/epics/epic-54-architecture-optimization/{epic.md,issues.md}`、`docs/epics.md` | 修改 | 開發記錄、狀態 |

---

### Task 0：提交計畫、建立 worktree

**Files：**
- Commit：本計畫檔（在 `main` 上，純文件，比照 Issue 1／3 設計文件的作法）
- 建立 worktree：`.worktrees/epic-54-issue-3-font-relink-permission`（`.worktrees/` 已 gitignore）

**Interfaces：**
- Consumes：無。
- Produces：後續 Task 都在 worktree 的分支 `epic-54/issue-3-font-relink-permission` 上進行與提交。

- [ ] **Step 1：在 `main` 提交計畫**

```bash
cd /c/Users/fycdc/AI/elinkBook
git status --short
git add docs/epics/epic-54-architecture-optimization/plans/plan-issue-3.md
git commit -m "docs(epic-54): Issue 3 實作計畫

Co-Authored-By: Claude Sonnet 5.5 <noreply@anthropic.com>"
```

Expected：`git status --short` 在 add 之前只有該計畫檔（若有其他未提交異動，先釐清來源，不要一併提交）。

- [ ] **Step 2：建立 worktree 與分支**

```bash
cd /c/Users/fycdc/AI/elinkBook
git worktree add .worktrees/epic-54-issue-3-font-relink-permission -b epic-54/issue-3-font-relink-permission main
cd .worktrees/epic-54-issue-3-font-relink-permission/app
flutter pub get
```

Expected：`Preparing worktree (new branch 'epic-54/issue-3-font-relink-permission')`。之後所有指令都在這個 worktree 的 `app/` 下執行。

---

### Task 1：`persistReadAccess` 與純測試

**Files：**
- Create: `app/lib/storage/storage_permission.dart`
- Test: `app/test/storage/storage_permission_test.dart`

**Interfaces：**
- Consumes：`kBookMetadataChannel`（`app/lib/library/library_repository.dart:9`，`MethodChannel('elinkbook/book_metadata')`）。
- Produces（Task 3、4、5 依賴，名稱與型別必須一字不差）：

```dart
/// 對 [uri] 持久化讀取授權；核發成功回傳 true，原生端拋出 PlatformException
/// （文件提供者不核發）回傳 false。
Future<bool> persistReadAccess(String uri);
```

- [ ] **Step 1：寫失敗的測試**

建立 `app/test/storage/storage_permission_test.dart`：

```dart
import 'package:elinkbook/library/library_repository.dart'
    show kBookMetadataChannel;
import 'package:elinkbook/storage/storage_permission.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

  tearDown(() => messenger.setMockMethodCallHandler(kBookMetadataChannel, null));

  test('核發成功：回傳 true，並把 uri 以 takePersistableUriPermission 傳給原生端', () async {
    final calls = <MethodCall>[];
    messenger.setMockMethodCallHandler(kBookMetadataChannel, (call) async {
      calls.add(call);
      return null;
    });

    final granted = await persistReadAccess('content://x/font.ttf');

    expect(granted, isTrue);
    expect(calls.single.method, 'takePersistableUriPermission');
    expect((calls.single.arguments as Map)['uri'], 'content://x/font.ttf');
  });

  test('原生端拋出 PlatformException（提供者不核發）：回傳 false', () async {
    messenger.setMockMethodCallHandler(kBookMetadataChannel, (call) async {
      throw PlatformException(code: 'denied');
    });

    expect(await persistReadAccess('content://x/font.ttf'), isFalse);
  });

  test('只轉換 PlatformException：原生端沒有實作（MissingPluginException）時照樣拋出', () async {
    // 沒有設定 mock handler
    expect(
      () => persistReadAccess('content://x/font.ttf'),
      throwsA(isA<MissingPluginException>()),
    );
  });
}
```

- [ ] **Step 2：執行測試確認失敗**

Run：`flutter test test/storage/storage_permission_test.dart`
Expected：編譯失敗，`Target of URI doesn't exist: 'package:elinkbook/storage/storage_permission.dart'`。

- [ ] **Step 3：寫最小實作**

建立 `app/lib/storage/storage_permission.dart`：

```dart
import 'package:flutter/services.dart';

import '../library/library_repository.dart' show kBookMetadataChannel;

/// 對 [uri] 持久化讀取授權（見 CONTEXT.md「持久化授權」），讓 App 重啟後仍能
/// 讀取這個 `content://` 檔案或資料夾。核發成功回傳 `true`；部分文件提供者
/// （例如媒體庫）不保證核發，原生端會拋出 [PlatformException]，此時回傳
/// `false`。
///
/// 本函式只集中「呼叫與例外轉換」，**不決定失敗後怎麼辦**——各呼叫端的處置
/// 刻意不同：書籍匯入／重新連結改複製一份到 App 私有目錄（ADR 0029）；字型
/// 不複製、忽略失敗（ADR 0021）；資料夾匯入無法列舉就中止。只轉換
/// [PlatformException]，其他例外（例如測試環境沒有原生實作的
/// [MissingPluginException]）維持原樣拋出。
Future<bool> persistReadAccess(String uri) async {
  try {
    await kBookMetadataChannel.invokeMethod<void>(
      'takePersistableUriPermission',
      {'uri': uri},
    );
    return true;
  } on PlatformException {
    return false;
  }
}
```

- [ ] **Step 4：執行測試確認通過**

Run：`flutter test test/storage/storage_permission_test.dart`
Expected：3 個測試 PASS。

- [ ] **Step 5：analyze 並提交**

```bash
flutter analyze
git add lib/storage/storage_permission.dart test/storage/storage_permission_test.dart
git commit -m "feat(storage): epic-54 Issue 3 新增 persistReadAccess 集中持久化授權呼叫

Co-Authored-By: Claude Sonnet 5.5 <noreply@anthropic.com>"
```

Expected：`No issues found!`。

---

### Task 2：`resolveFontFamilyName`／`stripFontFileExtension`

**Files：**
- Modify: `app/lib/reader/font_name_parser.dart`（檔尾新增兩個頂層函式）
- Test: `app/test/reader/font_name_parser_test.dart`（`main()` 結尾前新增一個 group）

**Interfaces：**
- Consumes：既有 `parseFontFamilyName(Uint8List) → String?`。
- Produces（Task 3、4 依賴）：

```dart
String stripFontFileExtension(String fileName);
String resolveFontFamilyName(Uint8List bytes, String fileName);
```

- [ ] **Step 1：寫失敗的測試**

Read `app/test/reader/font_name_parser_test.dart` 檔尾，在 `main()` 的結尾 `}` 之前新增（若 `dart:io`、`dart:typed_data`、`font_name_parser.dart` 的 import 已存在則不重複加）：

```dart
  group('stripFontFileExtension', () {
    test('去掉最後一段副檔名', () {
      expect(stripFontFileExtension('KingHwa.ttf'), 'KingHwa');
      expect(stripFontFileExtension('My.Font.Name.otf'), 'My.Font.Name');
    });

    test('沒有副檔名或只有開頭的點時原樣回傳', () {
      expect(stripFontFileExtension('NoExtension'), 'NoExtension');
      expect(stripFontFileExtension('.hidden'), '.hidden');
    });
  });

  group('resolveFontFamilyName', () {
    test('解析得到家族名稱時採用解析結果，不管檔名', () {
      final bytes = File('test/fixtures/sample.ttf').readAsBytesSync();

      expect(resolveFontFamilyName(bytes, 'whatever.ttf'), 'KingHwa_OldSong');
    });

    test('解析失敗（位元組不足以構成合法字型）時退回檔名去副檔名', () {
      final junk = Uint8List.fromList([1, 2, 3]);

      expect(resolveFontFamilyName(junk, 'OtherFamily.ttf'), 'OtherFamily');
    });
  });
```

- [ ] **Step 2：執行測試確認失敗**

Run：`flutter test test/reader/font_name_parser_test.dart`
Expected：編譯失敗，`The function 'stripFontFileExtension' isn't defined`。

- [ ] **Step 3：寫最小實作**

在 `app/lib/reader/font_name_parser.dart` 檔尾新增：

```dart
/// 字型檔名去除副檔名。供 [resolveFontFamilyName] 退回依據，也供上傳時產生
/// 預設顯示名稱使用。沒有副檔名、或點在最開頭（例如 `.hidden`）時原樣回傳。
String stripFontFileExtension(String fileName) {
  final dotIndex = fileName.lastIndexOf('.');
  return dotIndex > 0 ? fileName.substring(0, dotIndex) : fileName;
}

/// 決定字型檔案的家族名稱：優先採用 [parseFontFamilyName] 解析出的實際家族
/// 名稱，解析失敗退回檔名去副檔名。批次上傳與重新連結**必須共用這一條規則**
/// ——否則同一個檔案在兩條路徑可能得出不同家族名稱，重新連結就會誤判不符。
String resolveFontFamilyName(Uint8List bytes, String fileName) =>
    parseFontFamilyName(bytes) ?? stripFontFileExtension(fileName);
```

- [ ] **Step 4：執行測試確認通過**

Run：`flutter test test/reader/font_name_parser_test.dart`
Expected：全部 PASS（含既有測試）。

- [ ] **Step 5：analyze 並提交**

```bash
flutter analyze
git add lib/reader/font_name_parser.dart test/reader/font_name_parser_test.dart
git commit -m "feat(reader): epic-54 Issue 3 新增 resolveFontFamilyName 讓上傳與重新連結共用家族名稱規則

Co-Authored-By: Claude Sonnet 5.5 <noreply@anthropic.com>"
```

---

### Task 3：`CustomFontRelinker` 與純測試

**Files：**
- Create: `app/lib/reader/custom_font_relinker.dart`
- Test: `app/test/reader/custom_font_relinker_test.dart`

**Interfaces：**
- Consumes：`CustomFont`（`app/lib/reader/custom_font.dart`，欄位 `id`／`displayName`／`familyName`／`fontUri`）、`CustomFontsRepository.updateUri(int id, String fontUri)`、Task 1 的 `persistReadAccess`、Task 2 的 `resolveFontFamilyName`、測試替身 `FakeCustomFontsRepository`（`app/test/support/fake_custom_fonts_repository.dart`，有 `insert`／`listAll`／`updateUriError`）。
- Produces（Task 4 依賴，名稱與型別必須一字不差）：

```dart
typedef PickedFontFile = ({String uri, String name, Uint8List bytes});
typedef PersistReadAccess = Future<bool> Function(String uri);

sealed class FontRelinkResult
final class FontRelinkSuccess extends FontRelinkResult          // const FontRelinkSuccess()
final class FontRelinkFamilyMismatch extends FontRelinkResult   // const FontRelinkFamilyMismatch()
final class FontRelinkFailed extends FontRelinkResult           // const FontRelinkFailed()

class CustomFontRelinker {
  CustomFontRelinker({required CustomFontsRepository repository,
      PersistReadAccess persistAccess = persistReadAccess});
  Future<FontRelinkResult> relink(CustomFont font, PickedFontFile picked);
}
```

- [ ] **Step 1：寫失敗的純測試**

建立 `app/test/reader/custom_font_relinker_test.dart`：

```dart
import 'dart:io';

import 'package:elinkbook/library/library_repository.dart'
    show kBookMetadataChannel;
import 'package:elinkbook/reader/custom_font.dart';
import 'package:elinkbook/reader/custom_font_relinker.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/fake_custom_fonts_repository.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  // 真實字型檔（家族名稱為 KingHwa_OldSong）
  final sampleFontBytes = File('test/fixtures/sample.ttf').readAsBytesSync();
  const oldUri = 'content://old/font';
  const newUri = 'content://new/font';

  late FakeCustomFontsRepository repository;
  late List<String> persistedUris;
  late CustomFont font;

  /// 以假授權函式建立 relinker；[persistResult] 為授權回傳值，
  /// [persistError] 非 null 時授權函式拋出它。
  CustomFontRelinker buildRelinker({
    bool persistResult = true,
    Object? persistError,
  }) {
    return CustomFontRelinker(
      repository: repository,
      persistAccess: (uri) async {
        persistedUris.add(uri);
        if (persistError != null) throw persistError;
        return persistResult;
      },
    );
  }

  PickedFontFile sameFamily() =>
      (uri: newUri, name: 'KingHwa.ttf', bytes: sampleFontBytes);

  /// 只有 3 個位元組，解析不出家族名稱，退回檔名「OtherFamily」。
  PickedFontFile otherFamily() => (
        uri: newUri,
        name: 'OtherFamily.ttf',
        bytes: sampleFontBytes.sublist(0, 3),
      );

  Future<String> storedUri() async =>
      (await repository.listAll()).single.fontUri;

  setUp(() async {
    repository = FakeCustomFontsRepository();
    persistedUris = [];
    final id = await repository.insert(const CustomFont(
      displayName: '舊字型',
      familyName: 'KingHwa_OldSong',
      fontUri: oldUri,
    ));
    font = (await repository.listAll()).single;
    expect(font.id, id);
  });

  test('同家族：回傳 success，URI 更新、顯示名稱與家族名稱不動，並持久化新 URI 的授權', () async {
    final result = await buildRelinker().relink(font, sameFamily());

    expect(result, isA<FontRelinkSuccess>());
    final stored = (await repository.listAll()).single;
    expect(stored.fontUri, newUri);
    expect(stored.displayName, '舊字型');
    expect(stored.familyName, 'KingHwa_OldSong');
    expect(persistedUris, [newUri]);
  });

  test('解析失敗退回檔名，檔名剛好等於原家族名稱時視為同家族（與上傳規則一致）', () async {
    final renamed = await repository.insert(const CustomFont(
      displayName: '另一個',
      familyName: 'OtherFamily',
      fontUri: 'content://old/other',
    ));
    final target = (await repository.listAll())
        .firstWhere((f) => f.id == renamed);

    final result = await buildRelinker().relink(target, otherFamily());

    expect(result, isA<FontRelinkSuccess>());
  });

  test('家族不同：回傳 familyMismatch，不持久化授權、不改記錄（Review Focus 1）', () async {
    final result = await buildRelinker().relink(font, otherFamily());

    expect(result, isA<FontRelinkFamilyMismatch>());
    expect(persistedUris, isEmpty);
    expect(await storedUri(), oldUri);
  });

  test('授權回傳 false（提供者不核發）：不中止，仍更新 URI（ADR 0021，Review Focus 4）', () async {
    final result =
        await buildRelinker(persistResult: false).relink(font, sameFamily());

    expect(result, isA<FontRelinkSuccess>());
    expect(await storedUri(), newUri);
  });

  test('授權函式拋出非預期例外：回傳 failed、不改記錄，例外不穿出（Review Focus 4）', () async {
    final result = await buildRelinker(persistError: StateError('爆掉'))
        .relink(font, sameFamily());

    expect(result, isA<FontRelinkFailed>());
    expect(await storedUri(), oldUri);
  });

  test('updateUri 寫入失敗：回傳 failed，記錄不變', () async {
    repository.updateUriError = StateError('disk full');

    final result = await buildRelinker().relink(font, sameFamily());

    expect(result, isA<FontRelinkFailed>());
    repository.updateUriError = null;
    expect(await storedUri(), oldUri);
  });

  test('未注入 persistAccess（正式環境的接線）：預設走 persistReadAccess，向原生端要求新 URI 的授權', () async {
    final calls = <MethodCall>[];
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(kBookMetadataChannel, (call) async {
      calls.add(call);
      return null;
    });
    addTearDown(
        () => messenger.setMockMethodCallHandler(kBookMetadataChannel, null));

    final result = await CustomFontRelinker(repository: repository)
        .relink(font, sameFamily());

    expect(result, isA<FontRelinkSuccess>());
    expect(calls.single.method, 'takePersistableUriPermission');
    expect((calls.single.arguments as Map)['uri'], newUri);
  });

  test('字型沒有 id（尚未寫入資料庫）：回傳 failed，不呼叫授權', () async {
    const unsaved = CustomFont(
      displayName: '未儲存',
      familyName: 'KingHwa_OldSong',
      fontUri: oldUri,
    );

    final result = await buildRelinker().relink(unsaved, sameFamily());

    expect(result, isA<FontRelinkFailed>());
    expect(persistedUris, isEmpty);
  });
}
```

- [ ] **Step 2：執行測試確認失敗**

Run：`flutter test test/reader/custom_font_relinker_test.dart`
Expected：編譯失敗，`Target of URI doesn't exist: 'package:elinkbook/reader/custom_font_relinker.dart'`。

- [ ] **Step 3：寫最小實作**

建立 `app/lib/reader/custom_font_relinker.dart`：

```dart
import 'dart:typed_data';

import 'package:flutter/foundation.dart';

import '../storage/storage_permission.dart';
import 'custom_font.dart';
import 'custom_fonts_repository.dart';
import 'font_name_parser.dart';

/// 使用者重新選取的字型檔案（與 `SingleFontFilePicker` 的回傳型別相同）。
typedef PickedFontFile = ({String uri, String name, Uint8List bytes});

/// 持久化授權函式；預設是 [persistReadAccess]，測試注入假的以免碰原生。
typedef PersistReadAccess = Future<bool> Function(String uri);

/// [CustomFontRelinker.relink] 的結果，與書籍的 `BookRelinkResult` 並列：
/// 畫面只負責把結果對應成文字，規則都在 relinker 內。
sealed class FontRelinkResult {
  const FontRelinkResult();
}

/// 重新連結成功：記錄的 URI 已更新為新選取的檔案。
final class FontRelinkSuccess extends FontRelinkResult {
  const FontRelinkSuccess();

  // 只覆寫 toString：測試斷言失敗時看得到是哪個結果，不會只印 Instance of。
  // 刻意不實作 ==／hashCode：呼叫端與測試都以 isA<>／switch 比對型別，沒有人
  // 需要值等價（比照 OpenBookState）。
  @override
  String toString() => 'FontRelinkSuccess';
}

/// 選取的字型與原字型的家族名稱不同：記錄完全不動、也沒有持久化授權。
final class FontRelinkFamilyMismatch extends FontRelinkResult {
  const FontRelinkFamilyMismatch();

  @override
  String toString() => 'FontRelinkFamilyMismatch';
}

/// 其他失敗（資料庫寫入失敗等）：記錄維持原樣。
final class FontRelinkFailed extends FontRelinkResult {
  const FontRelinkFailed();

  @override
  String toString() => 'FontRelinkFailed';
}

/// 字型重新連結（CONTEXT.md「重新連結」；epic-15-storage-permission Issue 3
/// 原本寫在 `FontManagementScreen`，epic-54 Issue 3 搬出）。
///
/// 流程：比對家族名稱 → 持久化授權（盡力而為）→ 更新 URI。單書版面偏好以
/// 家族名稱引用字型，所以更新 URI 後所有使用這款字型的書自動恢復，不需要
/// 遷移。選檔器、SnackBar、按鈕停用狀態留在畫面。
class CustomFontRelinker {
  CustomFontRelinker({
    required this.repository,
    this.persistAccess = persistReadAccess,
  });

  final CustomFontsRepository repository;
  final PersistReadAccess persistAccess;

  /// 保證不拋出例外：任何非預期的例外都視為 [FontRelinkFailed]，畫面只需
  /// 依結果顯示對應 SnackBar。
  Future<FontRelinkResult> relink(CustomFont font, PickedFontFile picked) async {
    final id = font.id;
    if (id == null) return const FontRelinkFailed();

    // 家族名稱解析規則與批次上傳共用（resolveFontFamilyName）。
    final pickedFamily = resolveFontFamilyName(picked.bytes, picked.name);
    if (pickedFamily != font.familyName) {
      // 不符一律拒絕：選錯檔案不該白白消耗系統的持久化授權配額，更不能改記錄。
      return const FontRelinkFamilyMismatch();
    }

    try {
      // 字型檔不做落地複本退路（ADR 0021），授權盡力而為：被拒絕（false）
      // 不中止重新連結。
      await persistAccess(picked.uri);
      await repository.updateUri(id, picked.uri);
      return const FontRelinkSuccess();
    } catch (e) {
      // 資料庫寫入失敗（機率很低）等：記錄後回傳 failed，記錄與標示維持原樣，
      // 使用者可以再試一次。
      debugPrint('Failed to relink custom font: $e');
      return const FontRelinkFailed();
    }
  }
}
```

- [ ] **Step 4：執行測試確認通過**

Run：`flutter test test/reader/custom_font_relinker_test.dart`
Expected：8 個測試 PASS。

- [ ] **Step 5：analyze 並提交**

```bash
flutter analyze
git add lib/reader/custom_font_relinker.dart test/reader/custom_font_relinker_test.dart
git commit -m "feat(reader): epic-54 Issue 3 新增 CustomFontRelinker 與純測試

Co-Authored-By: Claude Sonnet 5.5 <noreply@anthropic.com>"
```

---

### Task 4：`FontManagementScreen` 改接 relinker、上傳改用共用函式

**Files：**
- Modify: `app/lib/screens/font_management_screen.dart`
- Modify: `app/test/screens/font_management_screen_test.dart`

**Interfaces：**
- Consumes：Task 1 的 `persistReadAccess`、Task 2 的 `resolveFontFamilyName`／`stripFontFileExtension`、Task 3 的 `CustomFontRelinker`／`FontRelinkResult` 家族。
- Produces：`FontManagementScreen` 對外行為不變，僅「重新連結失敗」多一則 SnackBar。

- [ ] **Step 1：先改測試（失敗的測試先行）**

在 `app/test/screens/font_management_screen_test.dart`：

1. 找到 `testWidgets('updateUri 寫入失敗：不拋出未捕捉例外、記錄不變、標示仍在、按鈕恢復可用（程式審查 M-1）'`，把名稱與斷言改為（新增 SnackBar 斷言）：

```dart
    testWidgets(
        'updateUri 寫入失敗：不拋出未捕捉例外、顯示失敗 SnackBar、記錄不變、標示仍在、按鈕恢復可用（程式審查 M-1；epic-54 Issue 3）',
        (tester) async {
      mockPersistPermission();
      repository.updateUriError = StateError('disk full');
      final id = await insertFont('舊字型', 'KingHwa_OldSong', 'content://old/font');
      probeByUri['content://old/font'] =
          StorageAccessProbeResult.permissionRevoked;
      await pumpTall(
        tester,
        pickSingleFontFile: () async =>
            (uri: 'content://new/font', name: 'KingHwa.ttf', bytes: sampleFontBytes),
      );

      await tester.tap(relink(id));
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(find.text('重新連結失敗，請再試一次'), findsOneWidget);
      repository.updateUriError = null;
      expect((await repository.listAll()).single.fontUri, 'content://old/font');
      expect(badge(id), findsOneWidget);
      expect(tester.widget<OutlinedButton>(relink(id)).onPressed, isNotNull);
    });
```

2. 刪除整個 `testWidgets('持久化授權失敗不中止：仍然更新 URI（比照 ADR 0021）'` 區塊（規則已由 `custom_font_relinker_test.dart`「授權回傳 false…仍更新 URI」涵蓋）。

- [ ] **Step 2：執行測試確認失敗**

Run：`flutter test test/screens/font_management_screen_test.dart --plain-name "updateUri 寫入失敗"`
Expected：FAIL（找不到 `重新連結失敗，請再試一次`，目前失敗時沒有 SnackBar）。

- [ ] **Step 3：改 import 與欄位**

在 `app/lib/screens/font_management_screen.dart`：

1. import 區塊新增（依字母順序放入既有 import 之間）：

```dart
import '../reader/custom_font_relinker.dart';
import '../storage/storage_permission.dart';
```

2. 在 `_FontManagementScreenState` 內、`final Set<int> _relinkingIds = {};` 之後新增：

```dart

  /// 字型重新連結規則（家族名稱比對、授權、更新 URI）；畫面只負責選檔與顯示。
  late final CustomFontRelinker _relinker =
      CustomFontRelinker(repository: widget.repository);
```

- [ ] **Step 4：改寫 `_relinkFont`**

把整個 `_relinkFont` 方法（含其上方 doc comment，約第 525–575 行）換成：

```dart
  /// 重新連結字型檔案（epic-15-storage-permission Issue 3；規則自
  /// epic-54 Issue 3 起收在 [CustomFontRelinker]）：選檔 → 交給 relinker →
  /// 依結果顯示。成功時更新探測標示並重新載入清單。
  Future<void> _relinkFont(CustomFont font) async {
    final id = font.id;
    if (id == null || _relinkingIds.contains(id)) return;
    setState(() => _relinkingIds.add(id));
    try {
      final picker = widget.pickSingleFontFile ?? pickSingleFontFileViaFilePicker;
      final picked = await picker();
      // 選檔期間使用者可能已離開畫面：不再解析、不持久化授權、不寫資料庫
      if (picked == null || !mounted) return;

      final result = await _relinker.relink(font, picked);
      if (!mounted) return;
      switch (result) {
        case FontRelinkSuccess():
          setState(() => _probeResults[id] = StorageAccessProbeResult.readable);
          await _loadFonts();
        case FontRelinkFamilyMismatch():
          _showRelinkSnackBar(
              AppLocalizations.of(context)!.fontManagementFamilyMismatchMessage);
        case FontRelinkFailed():
          // epic-54 Issue 3：過去只 debugPrint，使用者看不到；改與書籍重新連結
          // 一致，重用既有文字。
          _showRelinkSnackBar(
              AppLocalizations.of(context)!.readerStorageRelinkFailed);
      }
    } finally {
      if (mounted) setState(() => _relinkingIds.remove(id));
    }
  }

  /// 先收掉上一則再顯示，連續失敗時新結果不必排在前一則之後。
  void _showRelinkSnackBar(String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }
```

- [ ] **Step 5：改上傳流程用共用函式**

在 `_pickAndUploadFonts` 內：

1. 把
```dart
        final parsed = parseFontFamilyName(file.bytes!);
        parsedFamilyNames.add(parsed ?? _stripExtension(file.name));
```
換成
```dart
        parsedFamilyNames.add(resolveFontFamilyName(file.bytes!, file.name));
```

2. 把
```dart
        try {
          await kBookMetadataChannel
              .invokeMethod<void>('takePersistableUriPermission', {'uri': uri});
        } on PlatformException {
          // 部分文件提供者不保證核發可持久化授權（比照書籍匯入既有慣例，
          // book_import_service_impl.dart:201-207）；字型檔案本身刻意不做
          // 落地複本退路（ADR 0021），僅盡力而為，不因此中止整批上傳。
        }
```
換成
```dart
        // 部分文件提供者不保證核發持久化授權（見 CONTEXT.md「持久化授權」）；
        // 字型檔案刻意不做落地複本退路（ADR 0021），僅盡力而為，結果忽略，
        // 不因此中止整批上傳。
        await persistReadAccess(uri);
```

3. 把 `displayName: _stripExtension(file.name),` 換成 `displayName: stripFontFileExtension(file.name),`。

4. 刪除檔尾私有函式 `_stripExtension`（含其 doc comment，約第 695–700 行）。

- [ ] **Step 6：清理未使用的 import 並 analyze**

Run：`flutter analyze`
Expected：若出現 `unused_import`（常見是 `../library/library_repository.dart`，因 `kBookMetadataChannel` 已不被此檔使用；`dart:ui`／`services.dart` 仍因 `Uint8List` 保留），逐一移除；最後 `No issues found!`。

- [ ] **Step 7：執行測試**

Run：`flutter test test/screens/font_management_screen_test.dart test/reader/custom_font_relinker_test.dart`
Expected：全部 PASS（包含「重新連結成功」「選到不同家族的字型」「選檔期間離開畫面」「處理中連點只開一次選擇器」等既有 widget 測試，證明接線沒斷）。

- [ ] **Step 8：提交**

```bash
git add lib/screens/font_management_screen.dart test/screens/font_management_screen_test.dart
git commit -m "refactor(reader): epic-54 Issue 3 FontManagementScreen 改接 CustomFontRelinker

字型重新連結失敗改為顯示 SnackBar（重用 readerStorageRelinkFailed）；
上傳與重新連結共用 resolveFontFamilyName 與 persistReadAccess。

Co-Authored-By: Claude Sonnet 5.5 <noreply@anthropic.com>"
```

---

### Task 5：書籍匯入改用 `persistReadAccess`，資料夾匯入回報失敗

**Files：**
- Modify: `app/lib/library/book_import_service.dart`
- Modify: `app/lib/library/book_import_service_impl.dart`
- Test: `app/test/library/book_import_service_test.dart`

**Interfaces：**
- Consumes：Task 1 的 `persistReadAccess`。
- Produces（Task 6 依賴）：

```dart
enum ImportFailure { folderAccessDenied, folderListingFailed }

class ImportResult {
  final List<Book> importedBooks;
  final int skippedDuplicateCount;
  final ImportFailure? failure;        // 新增，預設 null
  const ImportResult({required this.importedBooks, this.skippedDuplicateCount = 0, this.failure});
}
```

- [ ] **Step 1：寫失敗的測試**

在 `app/test/library/book_import_service_test.dart`，緊接在 `test('autoGroupByFolderName=false 時，匯入書籍歸入預設「未分類」'…` 之後、`group('重複匯入偵測…` 之前新增：

```dart
  group('importFolder 失敗回報（epic-54 Issue 3）', () {
    /// 目前的群組名稱清單（資料庫建立時預設就有系統保留分類「未分類」）。
    Future<List<String>> groupNames() async =>
        (await repository.listGroups()).map((g) => g.name).toList();

    test('持久化授權失敗：回傳 folderAccessDenied、沒有匯入任何書、不嘗試列舉（Review Focus 2）',
        () async {
      final groupsBefore = await groupNames();
      var listCalled = false;
      mockChannel((call) async {
        if (call.method == 'takePersistableUriPermission') {
          throw PlatformException(code: 'denied');
        }
        if (call.method == 'listFolderContents') listCalled = true;
        return null;
      });

      final result = await service.importFolder('content://example/tree/folder');

      expect(result.failure, ImportFailure.folderAccessDenied);
      expect(result.importedBooks, isEmpty);
      expect(listCalled, isFalse, reason: '沒有授權就不該嘗試列舉');
      expect(await groupNames(), groupsBefore);
    });

    test('列舉資料夾內容拋出 PlatformException：回傳 folderListingFailed、群組不變', () async {
      final groupsBefore = await groupNames();
      mockChannel((call) async {
        if (call.method == 'takePersistableUriPermission') return null;
        if (call.method == 'listFolderContents') {
          throw PlatformException(code: 'listing_failed');
        }
        return null;
      });

      final result = await service.importFolder('content://example/tree/folder');

      expect(result.failure, ImportFailure.folderListingFailed);
      expect(result.importedBooks, isEmpty);
      expect(await groupNames(), groupsBefore);
    });

    test('列舉結果為 null：回傳 folderListingFailed', () async {
      mockChannel((call) async => null);

      final result = await service.importFolder('content://example/tree/folder');

      expect(result.failure, ImportFailure.folderListingFailed);
    });

    test('正常匯入：failure 維持 null', () async {
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

      final result = await service.importFolder('content://example/tree/folder');

      expect(result.failure, isNull);
    });

    test('資料夾裡沒有可匯入的書（合法的空結果）：不是失敗，failure 為 null', () async {
      mockChannel((call) async {
        if (call.method == 'takePersistableUriPermission') return null;
        if (call.method == 'listFolderContents') {
          return {'folderName': '空資料夾', 'fileUris': <String>[]};
        }
        return null;
      });

      final result = await service.importFolder('content://example/tree/folder');

      expect(result.failure, isNull);
      expect(result.importedBooks, isEmpty);
    });
  });
```

若 `PlatformException` 在該測試檔尚未 import，檔頭加 `import 'package:flutter/services.dart';`（多半已存在，因為 `MethodCall` 已被使用）。

- [ ] **Step 2：執行測試確認失敗**

Run：`flutter test test/library/book_import_service_test.dart --plain-name "importFolder 失敗回報"`
Expected：編譯失敗，`Undefined name 'ImportFailure'`（或 `The getter 'failure' isn't defined for the class 'ImportResult'`）。

- [ ] **Step 3：新增 `ImportFailure` 與 `ImportResult.failure`**

在 `app/lib/library/book_import_service.dart`，把

```dart
class ImportResult {
  final List<Book> importedBooks;
  final int skippedDuplicateCount;

  const ImportResult({
    required this.importedBooks,
    this.skippedDuplicateCount = 0,
  });
}
```

換成：

```dart
/// 一次匯入「整體失敗」的原因（目前只有資料夾匯入會失敗）。單檔匯入失敗仍是
/// 該檔被略過、不影響其他檔案，不屬於這裡。
enum ImportFailure {
  /// 無法取得資料夾的持久化授權（見 CONTEXT.md「持久化授權」），沒有授權就
  /// 無法列舉內容。
  folderAccessDenied,

  /// 已有授權，但列舉資料夾內容失敗（原生端拋例外或沒有回傳內容）。
  folderListingFailed,
}

class ImportResult {
  final List<Book> importedBooks;
  final int skippedDuplicateCount;

  /// 非 null 代表整次匯入失敗（此時 [importedBooks] 為空）。「資料夾裡本來
  /// 就沒有可匯入的書」不是失敗，維持 null。
  final ImportFailure? failure;

  const ImportResult({
    required this.importedBooks,
    this.skippedDuplicateCount = 0,
    this.failure,
  });
}
```

- [ ] **Step 4：`importFolder` 與 `_persistPermissionOrLandCopy` 改用 `persistReadAccess`**

在 `app/lib/library/book_import_service_impl.dart`：

1. import 區塊新增（依既有順序）：`import '../storage/storage_permission.dart';`

2. 把 `importFolder` 開頭到 `if (contents == null) ...` 那段：

```dart
    try {
      await kBookMetadataChannel.invokeMethod<void>(
        'takePersistableUriPermission',
        {'uri': folderUri},
      );
    } on PlatformException {
      return const ImportResult(importedBooks: []);
    }

    Map<Object?, Object?>? contents;
    try {
      contents = await kBookMetadataChannel.invokeMapMethod<Object?, Object?>(
        'listFolderContents',
        {'uri': folderUri},
      );
    } on PlatformException {
      return const ImportResult(importedBooks: []);
    }
    if (contents == null) return const ImportResult(importedBooks: []);
```

換成：

```dart
    // 資料夾沒有持久化授權就無法列舉：整次匯入失敗，並讓畫面告知使用者原因。
    if (!await persistReadAccess(folderUri)) {
      return const ImportResult(
        importedBooks: [],
        failure: ImportFailure.folderAccessDenied,
      );
    }

    Map<Object?, Object?>? contents;
    try {
      contents = await kBookMetadataChannel.invokeMapMethod<Object?, Object?>(
        'listFolderContents',
        {'uri': folderUri},
      );
    } on PlatformException {
      return const ImportResult(
        importedBooks: [],
        failure: ImportFailure.folderListingFailed,
      );
    }
    if (contents == null) {
      return const ImportResult(
        importedBooks: [],
        failure: ImportFailure.folderListingFailed,
      );
    }
```

3. 在 `_persistPermissionOrLandCopy` 內，把

```dart
    var permissionGranted = true;
    try {
      await kBookMetadataChannel.invokeMethod<void>(
        'takePersistableUriPermission',
        {'uri': uri},
      );
    } on PlatformException {
      permissionGranted = false;
    }
    if (!permissionGranted || detectBookFileFormat(uri) == null) {
```

換成：

```dart
    final permissionGranted = await persistReadAccess(uri);
    if (!permissionGranted || detectBookFileFormat(uri) == null) {
```

- [ ] **Step 5：analyze 並跑測試**

```bash
flutter analyze
flutter test test/library/book_import_service_test.dart
```

Expected：`No issues found!`（若 `PlatformException` 的 import 仍被 `listFolderContents` 的 catch 使用，則不會有 unused import）；全部 PASS，包含既有「持久化失敗改複製」測試（`copyContentUriToFile` 相關，Review Focus 3）與新增 5 個。

- [ ] **Step 6：確認「授權失敗仍走複製退路」的既有測試仍綠燈（Review Focus 3）**

不需要新增測試，既有測試已涵蓋匯入與重新連結兩條路徑（計畫審查 M-3 已查證）：
- 匯入：`book_import_service_test.dart` 內以 `copyContentUriToFile` 為關鍵字的既有測試（約第 182、226、310、341 行）。
- 重新連結：`test('驗證通過後持久化授權失敗：改存落地複本，回傳帶本機路徑的成功結果'`（約第 1772 行）與 `test('持久化授權與落地複本都失敗時回傳 failed，記錄不變'`（約第 1802 行）。

Run：`flutter test test/library/book_import_service_test.dart --plain-name "持久化授權"`
Expected：上述測試 PASS；再跑整個檔案 `flutter test test/library/book_import_service_test.dart` 全部 PASS。

- [ ] **Step 7：提交**

```bash
git add lib/library/book_import_service.dart lib/library/book_import_service_impl.dart test/library/book_import_service_test.dart
git commit -m "feat(library): epic-54 Issue 3 資料夾匯入失敗回報 ImportResult.failure，書籍匯入改用 persistReadAccess

Co-Authored-By: Claude Sonnet 5.5 <noreply@anthropic.com>"
```

---

### Task 6：新增 l10n 訊息並讓 `showImportResultSnackBar` 顯示失敗

**Files：**
- Modify: `app/lib/l10n/app_zh_TW.arb`、`app_zh.arb`、`app_zh_CN.arb`、`app_en.arb`
- Modify（由 `flutter gen-l10n` 產生）：`app/lib/l10n/app_localizations.dart`、`app_localizations_zh.dart`、`app_localizations_en.dart`
- Modify: `app/lib/screens/support/book_import_picker_helper.dart`
- Test: `app/test/screens/support/book_import_picker_helper_test.dart`

**Interfaces：**
- Consumes：Task 5 的 `ImportResult.failure`／`ImportFailure`。
- Produces：`AppLocalizations.libraryImportFolderFailedMessage`（`String get`）。

- [ ] **Step 1：寫失敗的 widget 測試**

在 `app/test/screens/support/book_import_picker_helper_test.dart` 的 `group('showImportResultSnackBar'` 內、第一個 `testWidgets('兩者皆為 0 時不顯示任何 SnackBar'` 之前新增（沿用該 group 既有的 pump 寫法）：

```dart
    testWidgets('failure 不為 null：只顯示資料夾讀取失敗訊息（epic-54 Issue 3）', (tester) async {
      for (final failure in ImportFailure.values) {
        await tester.pumpWidget(
          MaterialApp(
            locale: const Locale('zh', 'TW'),
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            home: Scaffold(
              body: Builder(
                builder: (context) => ElevatedButton(
                  onPressed: () => showImportResultSnackBar(
                    context,
                    ImportResult(
                      importedBooks: const [],
                      failure: failure,
                    ),
                  ),
                  child: const Text('Show SnackBar'),
                ),
              ),
            ),
          ),
        );

        await tester.tap(find.text('Show SnackBar'));
        await tester.pump();

        expect(find.text('無法讀取這個資料夾，請確認已授權存取後再試一次'), findsOneWidget,
            reason: '$failure');
        expect(find.textContaining('已匯入'), findsNothing);
        expect(find.textContaining('已跳過'), findsNothing);

        ScaffoldMessenger.of(tester.element(find.byType(Scaffold)))
            .clearSnackBars();
        await tester.pumpAndSettle();
      }
    });

    // 「failure 為 null 且兩者皆為 0 不顯示」不另加測試：既有的
    // 『兩者皆為 0 時不顯示任何 SnackBar』傳入的 ImportResult 預設 failure 即為
    // null，已涵蓋（計畫審查 I-4）。
```

（`ImportFailure` 由已 import 的 `book_import_service.dart` 提供。）

- [ ] **Step 2：新增 ARB 鍵**

四份 ARB 都在 `libraryImportResultSkippedOnlyMessage` 之後新增 `libraryImportFolderFailedMessage`。

1. `app/lib/l10n/app_zh_TW.arb`（範本檔，需附 `@` 描述）：用 Edit 把

```
  "libraryImportResultSkippedOnlyMessage": "{skippedCount, plural, =1{1 本已存在，已跳過} other{{skippedCount} 本已存在，已跳過}}",
  "@libraryImportResultSkippedOnlyMessage": {
    "description": "匯入完成時，僅有跳過重複（無成功匯入）的提示",
    "placeholders": {
      "skippedCount": {
        "type": "int"
      }
    }
  },
```

換成同樣內容，後面緊接：

```
  "libraryImportFolderFailedMessage": "無法讀取這個資料夾，請確認已授權存取後再試一次",
  "@libraryImportFolderFailedMessage": {
    "description": "資料夾匯入整體失敗（無法取得持久化授權，或列舉資料夾內容失敗）時的 SnackBar；兩種失敗使用者能做的事相同（重新選資料夾／重新授權），共用一則"
  },
```

2. `app_zh.arb`：在 `"libraryImportResultSkippedOnlyMessage": "…",` 該行之後新增一行：

```
  "libraryImportFolderFailedMessage": "無法讀取這個資料夾，請確認已授權存取後再試一次",
```

3. `app_zh_CN.arb`：同上位置新增一行：

```
  "libraryImportFolderFailedMessage": "无法读取这个文件夹，请确认已授权访问后再试一次",
```

4. `app_en.arb`：同上位置新增一行：

```
  "libraryImportFolderFailedMessage": "Couldn't read this folder. Make sure access is allowed, then try again.",
```

- [ ] **Step 3：重新產生 l10n 並確認只有預期的差異**

```bash
flutter gen-l10n
git diff --stat -- lib/l10n
```

Expected：`app_localizations.dart`、`app_localizations_zh.dart`、`app_localizations_en.dart` 與四份 ARB 都只新增該鍵相關行，沒有其他連動差異。若出現無關差異，先釐清（可能是 Flutter 版本不同造成格式變動），不要提交無關變動。

- [ ] **Step 4：改 `showImportResultSnackBar`**

在 `app/lib/screens/support/book_import_picker_helper.dart`，把函式開頭

```dart
void showImportResultSnackBar(BuildContext context, ImportResult result) {
  final importedCount = result.importedBooks.length;
```

換成（並更新其上方 doc comment 補一句「整體失敗時只顯示失敗訊息」）：

```dart
void showImportResultSnackBar(BuildContext context, ImportResult result) {
  // 整體失敗（目前只有資料夾匯入）：只顯示失敗訊息，不混入成功／跳過計數。
  if (result.failure != null) {
    final l10n = AppLocalizations.of(context)!;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(l10n.libraryImportFolderFailedMessage)),
    );
    return;
  }
  final importedCount = result.importedBooks.length;
```

doc comment 中「兩者皆為 0 時不顯示任何提示」那句之後補：`整體失敗（[ImportResult.failure] 非 null，epic-54 Issue 3）時只顯示失敗訊息。`

- [ ] **Step 5：執行測試與檢查**

```bash
flutter analyze
node tool/check_l10n_hardcoded_strings.js
flutter test test/screens/support/book_import_picker_helper_test.dart test/l10n
```

Expected：`No issues found!`；兩行 PASS；全部 PASS（`test/l10n` 的 `app_localizations_generated_test` 等會確認四份語系鍵一致）。

- [ ] **Step 6：提交**

```bash
git add lib/l10n lib/screens/support/book_import_picker_helper.dart test/screens/support/book_import_picker_helper_test.dart
git commit -m "feat(library): epic-54 Issue 3 資料夾匯入失敗時顯示 SnackBar（新增 libraryImportFolderFailedMessage）

Co-Authored-By: Claude Sonnet 5.5 <noreply@anthropic.com>"
```

---

### Task 7：開發記錄、全套測試、程式審查、準備發 PR

**Files：**
- Modify: `docs/epics/epic-54-architecture-optimization/epic.md`（開發記錄）
- Modify: `docs/epics/epic-54-architecture-optimization/issues.md`（Issue 3 狀態）
- Modify: `docs/epics.md`（第 65 行，即表格編號 55 的那一列）

**Interfaces：**
- Consumes：Task 1–6 的實際測試數字。
- Produces：可發 PR 的分支。

- [ ] **Step 1：跑本 Issue 觸及的測試檔**

```bash
flutter test test/storage test/reader/font_name_parser_test.dart test/reader/custom_font_relinker_test.dart test/screens/font_management_screen_test.dart test/library/book_import_service_test.dart test/screens/support/book_import_picker_helper_test.dart test/l10n
```

Expected：全部 PASS。

- [ ] **Step 2：請求程式審查**

使用 `superpowers:requesting-code-review`，審查範圍為本分支相對 Task 0 提交計畫之後的 commit 範圍。審查報告存於 `docs/epics/epic-54-architecture-optimization/reviews/review-code-issue-3.md`（gitignore，不進版控）；審查者只出報告、不直接改程式；依報告修訂前須先由使用者決定。審查摘要要寫進 `epic.md`（見 Step 4），不能只留在報告裡。

- [ ] **Step 3：全套測試（整張計畫最後一個 Task，CLAUDE.md 規定此時跑一次）**

```bash
flutter test
flutter analyze
node tool/check_l10n_hardcoded_strings.js
```

全套約 6 分鐘，請用 `run_in_background`。Expected：`All tests passed!`；`No issues found!`；兩行 PASS。基準：Issue 5 合併後為 3255 通過、1 略過。

- [ ] **Step 4：寫開發記錄**

在 `epic.md`「開發記錄」末尾新增（數字以實際結果為準）：

```markdown
**YYYY-MM-DD Issue 3 實作完成**：新增 `persistReadAccess`（`app/lib/storage/storage_permission.dart`，集中 4 處 `takePersistableUriPermission` 呼叫，失敗處置仍由各呼叫端決定）、`CustomFontRelinker`（`app/lib/reader/custom_font_relinker.dart`，密封類別 `FontRelinkResult` 與 `BookRelinkResult` 並列）、`resolveFontFamilyName`／`stripFontFileExtension`（`font_name_parser.dart`，上傳與重新連結共用同一條家族名稱規則）；`ImportResult` 新增 `failure`。與設計表的差異：`_stripExtension` 改為公開的 `stripFontFileExtension` 並移入 `font_name_parser.dart`，避免兩份實作。行為調整：① 字型重新連結失敗顯示 SnackBar（重用 `readerStorageRelinkFailed`）；② 資料夾匯入三條失敗路徑回報 `failure` 並顯示新訊息 `libraryImportFolderFailedMessage`（4 份 ARB）。測試：新增純測試 N 個；`font_management_screen_test` 刪 1 個規則類、`updateUri` 失敗測試補 SnackBar 斷言。驗證：全套 `flutter test` N 通過、1 略過；`flutter analyze` No issues found；`check_l10n_hardcoded_strings.js` 兩行 PASS。程式審查摘要：…
```

並把 `issues.md` Issue 3 狀態改為「🟡 進行中（`plans/plan-issue-3.md`）」、`docs/epics.md` 第 65 行（表格編號 55）改為「…Issue 3 實作完成待發 PR…」。

- [ ] **Step 5：提交並準備發 PR**

```bash
cd /c/Users/fycdc/AI/elinkBook/.worktrees/epic-54-issue-3-font-relink-permission
git add docs/epics.md docs/epics/epic-54-architecture-optimization/epic.md docs/epics/epic-54-architecture-optimization/issues.md
git commit -m "docs(epic-54): Issue 3 實作完成，全套測試通過，準備發 PR

Co-Authored-By: Claude Sonnet 5.5 <noreply@anthropic.com>"
```

發 PR 前須經使用者確認（對外動作）；PR 描述結尾加 `🤖 Generated with [Claude Code](https://claude.com/claude-code)`。PR 合併後比照 Issue 1、5：在 `epic.md` 補合併記錄、`issues.md` 標為「🟢 已合併（PR #N）」、更新 `docs/epics.md`，並移除 worktree 與分支。
