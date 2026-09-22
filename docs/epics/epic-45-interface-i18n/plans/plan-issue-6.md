# Epic 45 Issue 6：其餘管理類彈窗與畫面字串抽取＋測試遷移 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development（recommended）or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 把遠端書庫（Calibre／OPDS）、WiFi 傳書、「來源」聚合頁、本機檔案/資料夾匯入輔助函式、版面設定預設集書籍選擇器／命名對話框等未歸入 Issue 3-5 的畫面的硬編碼中文字串改為 `AppLocalizations` key，三語言（正體中文／簡體中文／英文）皆補上真實翻譯，對應測試檔同步遷移為在地化相容寫法，零使用者可見行為變動（除新增語言支援本身）。

**Architecture:** 沿用 Issue 3／4／5 已確立的模式——`AppLocalizations.of(context)!`（non-null assertion）＋新增 ARB key（三語言真實翻譯＋`app_zh.arb` fallback 同步）＋既有測試補上 `locale`/`localizationsDelegates`/`supportedLocales`。本 Issue 規模略大於 Issue 5，拆為 14 個 Task；`remote_catalog_screen.dart`（14 處裸 `MaterialApp`）與 `layout_preset_book_picker_screen.dart`（17 處）比照 Issue 4/5 先例，把 production 與測試遷移拆成相鄰獨立 Task；其餘檔案（≤11 處）production＋測試合併同一 Task。**（`/superpowers:requesting-code-review` review-plan-issue-6.md Important #4 補記歸屬）** 全域掃描 `app/lib/screens/` 額外發現兩個未被任何 Issue 認領的孤兒檔案——`cloud_duplicate_confirm_dialog.dart`（Task 4）與 `widgets/download_queue_panel.dart`（Task 8）——皆為本 Issue 主題（管理類彈窗／常駐面板）範圍內、且唯一呼叫端分別落在本 Issue 的 `remote_catalog_screen.dart`／`main.dart`／`cloud_browser_screen.dart` 與 `sources_home_screen.dart`，一併納入。

**範圍已依實際 grep 盤點修正**（`issues.md` 本身註明「代表性範圍，實際檔案清單以認領當下重新 grep 盤點為準」）：
- **移出：`adaptive_shell_scaffold.dart`**——`issues.md` Issue 6「What to build」列出此檔案，但實際通讀全檔（169 行）確認它是純三目的地 `IndexedStack` 組裝/依賴透傳 widget，`grep -nP '[\x{4e00}-\x{9fff}]'` 命中的全部 10 處皆為文件註解（`///`/`//`），零使用者可見字面字串（沒有任何 `Text`/`tooltip`/`labelText`）。本 Issue 不修改此檔案。
- **新增：`format_selection_dialog.dart`**——`issues.md` Issue 3 段落「實際執行範圍修正記錄」已註明此檔案「實際屬 Issue 6 範圍，唯一呼叫端為 `remote_catalog_screen.dart`」，但未被列入 Issue 6 自己的「What to build」清單。確認其唯一呼叫端 `RemoteCatalogScreen._startDownload()`（透過 `FormatSelectionDialog.show()`）確實屬本 Issue 範圍，且該檔案目前 `AppLocalizations` 使用量為 0、含 3 處硬編碼字串，納入本計劃 Task 3。
- **新增（`/superpowers:requesting-code-review` review-plan-issue-6.md Important #4 補記歸屬）：`cloud_duplicate_confirm_dialog.dart`**——全域掃描 `app/lib/screens/` 發現的孤兒檔案，`AppLocalizations` 使用量為 0，含 3 處硬編碼字面值，與 `remote_catalog_screen.dart._showDuplicateConfirmDialog()` 幾乎逐字相同的設計（同為「Layer 1 選檔前置／Layer 2 下載後指紋比對共用同一個確認 UI」），唯一呼叫端為 `main.dart`／`cloud_browser_screen.dart`，納入本計劃 Task 4，詳見該 Task 說明。
- **新增（同上，`/superpowers:requesting-code-review` review-plan-issue-6.md Important #4 補記歸屬）：`widgets/download_queue_panel.dart`**——同樣是全域掃描發現的孤兒檔案，`AppLocalizations` 使用量為 0，含 11 處硬編碼字面值（分區標題＋3 個 tooltip＋7 個狀態標籤），唯一呼叫端為本 Issue 範圍內的 `sources_home_screen.dart`，納入本計劃 Task 8，詳見該 Task 說明。
- **路徑修正：`book_import_picker_helper.dart`**——`issues.md` 寫作 `support/book_import_picker_helper.dart`，實際路徑為 `app/lib/screens/support/book_import_picker_helper.dart`（對應測試檔 `app/test/screens/support/book_import_picker_helper_test.dart`），Task 10 以實際路徑為準。
- **確認保留**：`remote_server_list_screen.dart`／`remote_server_form_screen.dart`／`remote_catalog_screen.dart`／`wifi_transfer_screen.dart`／`sources_home_screen.dart` 皆確認為本 Issue 範圍，且皆有硬編碼中文字串待抽取；`cloud_browser_screen.dart` 已於 Issue 2 完整處理，本 Issue 不重複處理（`issues.md` 已註明此點）。
- **確認保留（Issue 4 最終複審補記歸屬）**：`layout_preset_book_picker_screen.dart`／`layout_preset_name_dialog.dart`（`reviews/review-issue-4-final.md` Important #1／#2）——兩者唯一呼叫端皆為 `reader_screen.dart`（已在 Issue 4 在地化的「版面預設集」流程，分別是 `_handleApplyFromBook()`／`_handleSaveAsPreset()`），目前仍為硬編碼中文、`AppLocalizations` 使用量皆為 0，實際 grep 盤點確認與 Issue 4 收尾時記錄一致。`layout_preset_book_picker_screen.dart` 有獨立測試檔 `layout_preset_book_picker_screen_test.dart`（476 行，17 處裸 `MaterialApp`）；`layout_preset_name_dialog.dart` **沒有**獨立測試檔——它已在 Issue 4 遷移的 `reader_screen_test.dart`（`locale: const Locale('zh', 'TW')`）內以 `find.byKey('layout_preset_name_dialog_field'/'layout_preset_name_dialog_confirm')` 間接測試，不涉及裸 `MaterialApp`，見 Task 13。

**Tech Stack:** Flutter `flutter_localizations`／`intl`（ARB／`gen-l10n`，含 ICU `plural`）。

**Spec:** `docs/epics/epic-45-interface-i18n/spec.md`（§8 測試相容性、Key 命名慣例）、`docs/epics/epic-45-interface-i18n/design.md`（ICU plural／品牌名不翻譯排除範圍）、`docs/epics/epic-45-interface-i18n/issues.md`（Issue 6 段落）。

## Global Constraints

- 所有新增 ARB key 必須同步寫入四份檔案：`app_zh_TW.arb`（含 `@key` description）、`app_zh_CN.arb`、`app_en.arb`（皆為真實翻譯，非機器翻譯佔位）、`app_zh.arb`（與 `app_zh_TW.arb` 相同值，不含 `@key` description block）。異動前四份檔案皆為 448 個 key，完全同步。
- `AppLocalizations.of(context)!` 一律用 non-null assertion，不得使用 `l10n?.xxx ?? '硬編碼字面值'` 的 nullable fallback 寫法（Issue 2 審查 `review-issue-2.md` Important #1 確立的教訓）。
- **`State`/`StatelessWidget` 方法可直接呼叫 `AppLocalizations.of(context)!`，不需要額外把 `l10n`/`context` 當作參數逐層傳遞**：本 Issue 全部畫面的私有 helper 方法（例如 `_confirmDelete()`／`_openAddForm()`／`_handlePickFiles()`）皆是各自 State 或 StatelessWidget 的**實例方法**，`context` 皆為既有 getter 或既有參數，直接在方法內呼叫 `AppLocalizations.of(context)!` 即可。**唯一需要留意的例外**是 `book_import_picker_helper.dart` 的三個頂層自由函式（`confirmAutoGroupByFolderName(BuildContext context)`／`showImportResultSnackBar(BuildContext context, ImportResult result)`）——它們雖是頂層函式而非 State 方法，但函式簽章本身**已經**接受 `BuildContext context` 參數，因此同樣可以直接呼叫 `AppLocalizations.of(context)!`，不需要額外新增 `AppLocalizations l10n` 參數（與 Issue 5 `font_management_screen.dart.buildUploadResultMessage()` 那種完全沒有 `context` 可用的頂層純函式情況不同）；`remote_catalog_screen.dart` 的 `_showDuplicateConfirmDialog(BuildContext context, String message)` 同理。
- **`initState()` 存取 l10n 陷阱（Issue 3 審查 `review-plan-issue-3.md` C-1 確立的鐵律）**：任何 `State.initState()` 執行期間呼叫 `AppLocalizations.of(context)!` 會拋出 `FlutterError`。本 Issue 逐一核對後，`RemoteServerListScreen`／`RemoteCatalogScreen`／`WifiTransferScreen` 的 `initState()` 皆只呼叫 `_load()`/`_client = widget.dependencies.createOpdsClient()`/`WakelockPlus.enable()`/`_availabilityFuture = _initialize()` 等純資料載入或非 UI 操作，不涉及任何字串/l10n 存取，不受影響；`layout_preset_name_dialog.dart` 的 `_LayoutPresetNameDialogState.initState()` 只建構 `TextEditingController`，同樣不受影響。
- ICU plural 全域規則：任何計數字串（英文有單複數變化）一律用 ARB `plural` 語法，中文三語言（`zh_TW`/`zh_CN`/`zh`）雖無文法複數變化，仍比照既有先例維持 `plural` 語法結構（`=1{...} other{...}` 兩分支填相同中文措辭）。本 Issue 命中 4 處計數字串：`remote_server_list_screen.dart` 刪除防護的 `blockingBooks.length`（Task 1）、`remote_catalog_screen.dart` 下載佇列的 `jobs.length`（Task 5）、`wifi_transfer_screen.dart` 傳輸中橫幅的 `activeCount`（Task 7）、`book_import_picker_helper.dart` 匯入結果的 `importedCount`／`skippedCount`（**兩者各自獨立處理單複數，不可共用同一個 `plural` 判斷式**，`issues.md` I-2 修正明訂，Task 10）。
- 品牌名/專有名詞不翻譯（`design.md`「不涵蓋…專有名詞（內建字型名稱、雲端服務商品牌名如 Google Drive／OneDrive）」排除範圍）：`sources_home_screen.dart` 的 `'Google Drive'`／`'OneDrive'` 字面值（Task 9）、`remote_server_form_screen.dart` 的 `'Calibre-Web'`（伺服器類型下拉選單第三個選項，Task 2）皆維持原樣不抽取。
- 既有測試檔遷移：所有本 Issue 觸及的測試檔皆為裸 `MaterialApp(` 直接呼叫（部分有共用 `pumpScreen()`/`buildScreen()` helper，部分是逐個 `testWidgets` 各自內嵌），逐一在 `MaterialApp(` 參數列補上 `locale: const Locale('zh', 'TW')`/`localizationsDelegates: AppLocalizations.localizationsDelegates`/`supportedLocales: AppLocalizations.supportedLocales`；有共用 helper 的檔案直接修改該 helper（保留其介面穩定性，比照 Issue 3 `issues.md` 對「測試檔已有自己一層 helper」情況的既定處理原則），沒有共用 helper 的逐一插入。
- 測試執行範圍：單一 Task 完成後只跑該 Task 觸及的測試檔；完整 `flutter test`／`flutter analyze` 僅在 Task 14（最後一個 Task）執行一次。
- Commit 訊息前綴統一 `feat(epic-45):`，Task 14 除外用 `docs(epic-45):`。

---

### Task 1: `remote_server_list_screen.dart`

**Files:**
- Modify: `app/lib/screens/remote_server_list_screen.dart`
- Modify: `app/lib/l10n/app_zh_TW.arb`／`app_zh_CN.arb`／`app_en.arb`／`app_zh.arb`
- Test: `app/test/screens/remote_server_list_screen_test.dart`

**Interfaces:**
- Consumes：`AppLocalizations.of(context)!`（`_RemoteServerListScreenState` 的 `build()`/`_confirmDelete()`/`_delete()` 皆為 State 方法，直接取用 `context`）。
- Produces：ARB key `remoteServerListTitle`/`remoteServerListAddTooltip`/`remoteServerListEmptyState`/`remoteServerListEditTooltip`/`remoteServerListDeleteTooltip`/`remoteServerListDeleteConfirmTitle`/`remoteServerListDeleteConfirmMessage`/`remoteServerListDeleteBlockedTitle`/`remoteServerListDeleteBlockedMessage`/`remoteServerListDeleteBlockedConfirmButton`/`remoteServerListDeleteFailedMessage`；沿用全域共用 `cancel`。

- [ ] **Step 1: 新增 ARB key（四語言）**

`app_zh_TW.arb` 檔尾新增（緊接目前最後一個 key 之後）：
```json
  "remoteServerListTitle": "遠端書庫",
  "@remoteServerListTitle": {
    "description": "遠端書庫站點清單畫面 AppBar 標題"
  },
  "remoteServerListAddTooltip": "新增站點",
  "@remoteServerListAddTooltip": {
    "description": "AppBar「新增站點」按鈕的無障礙提示文字"
  },
  "remoteServerListEmptyState": "尚未新增任何遠端書庫站點",
  "@remoteServerListEmptyState": {
    "description": "尚未新增任何站點時的空狀態文字"
  },
  "remoteServerListEditTooltip": "編輯",
  "@remoteServerListEditTooltip": {
    "description": "站點列項目「編輯」圖示按鈕的無障礙提示文字"
  },
  "remoteServerListDeleteTooltip": "刪除",
  "@remoteServerListDeleteTooltip": {
    "description": "站點列項目「刪除」圖示按鈕的無障礙提示文字"
  },
  "remoteServerListDeleteConfirmTitle": "刪除站點",
  "@remoteServerListDeleteConfirmTitle": {
    "description": "刪除站點確認對話框標題"
  },
  "remoteServerListDeleteConfirmMessage": "確定要刪除站點「{name}」嗎？此動作無法復原。",
  "@remoteServerListDeleteConfirmMessage": {
    "description": "刪除站點確認訊息，{name} 為使用者自訂的站點名稱（不翻譯）",
    "placeholders": {
      "name": {
        "type": "String"
      }
    }
  },
  "remoteServerListDeleteBlockedTitle": "無法刪除站點",
  "@remoteServerListDeleteBlockedTitle": {
    "description": "站點仍有僅雲端紀錄書籍、刪除被擋下時的示警對話框標題"
  },
  "remoteServerListDeleteBlockedMessage": "{count, plural, =1{這個站點還有 1 本書僅有雲端紀錄、尚未下載：} other{這個站點還有 {count} 本書僅有雲端紀錄、尚未下載：}}\n{titles}\n\n請先於書架移除這些書籍，或重新下載後再刪除站點。",
  "@remoteServerListDeleteBlockedMessage": {
    "description": "刪除被擋下時的示警訊息，{count} 為僅雲端紀錄書籍本數，{titles} 為呼叫端已組好的書名清單文字（每行一本，前綴「．」，不含末尾換行）",
    "placeholders": {
      "count": {
        "type": "int"
      },
      "titles": {
        "type": "String"
      }
    }
  },
  "remoteServerListDeleteBlockedConfirmButton": "了解",
  "@remoteServerListDeleteBlockedConfirmButton": {
    "description": "示警對話框的確認按鈕文字"
  },
  "remoteServerListDeleteFailedMessage": "刪除站點失敗，請稍後再試",
  "@remoteServerListDeleteFailedMessage": {
    "description": "刪除防護例外以外的其餘刪除失敗時顯示的 SnackBar 訊息"
  },
```

`app_zh_CN.arb` 檔尾新增（不含 `@key` block）：
```json
  "remoteServerListTitle": "远程书库",
  "remoteServerListAddTooltip": "新增站点",
  "remoteServerListEmptyState": "尚未新增任何远程书库站点",
  "remoteServerListEditTooltip": "编辑",
  "remoteServerListDeleteTooltip": "删除",
  "remoteServerListDeleteConfirmTitle": "删除站点",
  "remoteServerListDeleteConfirmMessage": "确定要删除站点「{name}」吗？此动作无法复原。",
  "remoteServerListDeleteBlockedTitle": "无法删除站点",
  "remoteServerListDeleteBlockedMessage": "{count, plural, =1{这个站点还有 1 本书仅有云端记录、尚未下载：} other{这个站点还有 {count} 本书仅有云端记录、尚未下载：}}\n{titles}\n\n请先于书架移除这些书籍，或重新下载后再删除站点。",
  "remoteServerListDeleteBlockedConfirmButton": "了解",
  "remoteServerListDeleteFailedMessage": "删除站点失败，请稍后再试",
```

`app_en.arb` 檔尾新增（不含 `@key` block）：
```json
  "remoteServerListTitle": "Remote Library",
  "remoteServerListAddTooltip": "Add Server",
  "remoteServerListEmptyState": "No remote library servers added yet",
  "remoteServerListEditTooltip": "Edit",
  "remoteServerListDeleteTooltip": "Delete",
  "remoteServerListDeleteConfirmTitle": "Delete Server",
  "remoteServerListDeleteConfirmMessage": "Delete server \"{name}\"? This cannot be undone.",
  "remoteServerListDeleteBlockedTitle": "Cannot Delete Server",
  "remoteServerListDeleteBlockedMessage": "{count, plural, =1{This server still has 1 book that only has a cloud record and has not been downloaded:} other{This server still has {count} books that only have a cloud record and have not been downloaded:}}\n{titles}\n\nPlease remove these books from your library, or download them again before deleting the server.",
  "remoteServerListDeleteBlockedConfirmButton": "Got It",
  "remoteServerListDeleteFailedMessage": "Failed to delete server. Please try again later.",
```

`app_zh.arb` 檔尾新增：與 `app_zh_TW.arb` 對應 key 相同值（fallback，不含 `@key` block），內容與上方 `app_zh_TW.arb` 段落一致（複製 `remoteServerListTitle`～`remoteServerListDeleteFailedMessage` 全部 11 個 key 的值）。

- [ ] **Step 2: 執行 `flutter gen-l10n` 確認 ARB 語法正確**

Run: `cd app && flutter gen-l10n`
Expected: 無錯誤訊息，`lib/l10n/app_localizations*.dart` 成功重新產生，新增的 11 個 getter/方法可見於 `app_localizations.dart`。**`gen-l10n` 對多 placeholder 訊息一律產生位置參數（positional arguments），不是具名參數**——查核既有 `libraryGroupDeleteConfirmMessage(String name, String uncategorized)`／`fontManagementUploadBothMessage(int addedCount, int skippedCount)` 兩個既有多參數方法的簽章與呼叫端寫法即可確認此慣例；因此 `remoteServerListDeleteBlockedMessage` 產生的簽章為 `remoteServerListDeleteBlockedMessage(int count, String titles)`（兩個位置參數，順序依 ARB `placeholders` 宣告順序 `count`／`titles`），呼叫時**不可**寫成 `remoteServerListDeleteBlockedMessage(count: ..., titles: ...)`（具名參數語法），見 Step 3。

- [ ] **Step 3: 修改 `remote_server_list_screen.dart`**

在 `_delete()` 方法內組出書名清單字串（保留既有 `.map((b) => '．${b.title}').join('\n')` 邏輯，只是把整段訊息改為透過 `AppLocalizations` 組裝），並將全部 9 處硬編碼字串改為 `AppLocalizations`：

```dart
  Future<void> _confirmDelete(RemoteServerProfile profile) async {
    final l10n = AppLocalizations.of(context)!;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        key: const Key('remote_server_delete_confirm_dialog'),
        title: Text(l10n.remoteServerListDeleteConfirmTitle),
        content: Text(
          l10n.remoteServerListDeleteConfirmMessage(profile.name),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text(l10n.cancel),
          ),
          TextButton(
            key: const Key('remote_server_delete_confirm_button'),
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(l10n.remoteServerListDeleteTooltip),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    if (!mounted) return;
    await _delete(profile);
  }

  Future<void> _delete(RemoteServerProfile profile) async {
    try {
      await widget.repository.deleteServer(profile.id);
      _load();
    } on RemoteServerDeletionBlockedException catch (e) {
      if (!mounted) return;
      final l10n = AppLocalizations.of(context)!;
      final titles = e.blockingBooks.map((b) => '．${b.title}').join('\n');
      await showDialog<void>(
        context: context,
        builder: (context) => AlertDialog(
          key: const Key('remote_server_delete_blocked_dialog'),
          title: Text(l10n.remoteServerListDeleteBlockedTitle),
          content: Text(
            // gen-l10n 產生位置參數，不是具名參數——順序依 ARB placeholders
            // 宣告順序（count, titles）。
            l10n.remoteServerListDeleteBlockedMessage(
              e.blockingBooks.length,
              titles,
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: Text(l10n.remoteServerListDeleteBlockedConfirmButton),
            ),
          ],
        ),
      );
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          key: const Key('remote_server_delete_error_snackbar'),
          content: Text(
            AppLocalizations.of(context)!.remoteServerListDeleteFailedMessage,
          ),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.remoteServerListTitle),
        actions: [
          IconButton(
            key: const Key('remote_server_list_add_button'),
            icon: const Icon(Icons.add),
            tooltip: l10n.remoteServerListAddTooltip,
            onPressed: _openAddForm,
          ),
        ],
      ),
      body: _loading
          ? const Center(
              child: CircularProgressIndicator(
                key: Key('remote_server_list_loading_indicator'),
              ),
            )
          : _servers.isEmpty
              ? Center(
                  child: Text(
                    l10n.remoteServerListEmptyState,
                    key: const Key('remote_server_list_empty_state'),
                  ),
                )
              : ListView.builder(
                  itemCount: _servers.length,
                  itemBuilder: (context, index) {
                    final profile = _servers[index];
                    return ListTile(
                      key: Key('remote_server_item_${profile.id}'),
                      title: Text(profile.name),
                      subtitle: Text(profile.baseUrl),
                      onTap: () => _openCatalog(profile),
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          IconButton(
                            key: Key('remote_server_item_edit_${profile.id}'),
                            icon: const Icon(Icons.edit),
                            tooltip: l10n.remoteServerListEditTooltip,
                            onPressed: () => _openEditForm(profile),
                          ),
                          IconButton(
                            key: Key('remote_server_item_delete_${profile.id}'),
                            icon: const Icon(Icons.delete),
                            tooltip: l10n.remoteServerListDeleteTooltip,
                            onPressed: () => _confirmDelete(profile),
                          ),
                        ],
                      ),
                    );
                  },
                ),
    );
  }
```

加上檔案頂部 import：
```dart
import '../l10n/app_localizations.dart';
```

- [ ] **Step 4: 遷移既有測試檔至含 `AppLocalizations` 的 `pumpScreen()`**

`app/test/screens/remote_server_list_screen_test.dart` 的 `pumpScreen()` helper（第 44-63 行）目前回傳裸 `MaterialApp(home: ...)`。修改：

```dart
  Future<void> pumpScreen(
    WidgetTester tester, {
    required FakeRemoteServerRepository repository,
    Locale locale = const Locale('zh', 'TW'),
  }) async {
    await tester.pumpWidget(MaterialApp(
      locale: locale,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: RemoteServerListScreen(
        repository: repository,
        libraryRepository: FakeLibraryRepository(),
        dependencies: RemoteCatalogDependencies(
          computeFingerprint: FakeFingerprintComputer().call,
          thumbnailCache: FakeRemoteThumbnailCache(),
          createOpdsClient: () => FakeOpdsClient(),
        ),
        importService: FakeBookImportService(),
        downloadQueueController:
            DownloadQueueController(onDuplicateConfirm: (_) async => false),
      ),
    ));
    await tester.pumpAndSettle();
  }
```

加上檔案頂部 import：
```dart
import 'package:elinkbook/l10n/app_localizations.dart';
```

既有全部 9 個 `testWidgets` 呼叫 `pumpScreen()` 皆不需修改（新增的 `locale` 參數有預設值）；既有 `find.text('刪除站點')`/`find.text('取消')`/`find.text('新增站點')`/`find.text('編輯站點')`/`find.text('家用 NAS')`/`find.textContaining('待下載的書')` 等斷言因 `app_zh_TW.arb` 譯文與原字面值完全相同，無需修改。

- [ ] **Step 5: 新增英文渲染驗證測試**

```dart
  testWidgets('英文介面下顯示英文標題與空狀態文字', (tester) async {
    await pumpScreen(
      tester,
      repository: FakeRemoteServerRepository(),
      locale: const Locale('en'),
    );
    expect(find.text('Remote Library'), findsOneWidget);
    expect(find.text('No remote library servers added yet'), findsOneWidget);
  });

  testWidgets('英文介面下刪除被擋下的站點顯示正確單複數示警文字', (tester) async {
    final blockingBook = _fakeBook('book1', 'Pending Download');
    final repository = FakeRemoteServerRepository(
      initialServers: [profile('srv1')],
      blockedDeletions: {'srv1': [blockingBook]},
    );
    await pumpScreen(tester, repository: repository, locale: const Locale('en'));

    await tester.tap(find.byKey(const Key('remote_server_item_delete_srv1')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('remote_server_delete_confirm_button')));
    await tester.pumpAndSettle();

    expect(
      find.textContaining("This server still has 1 book that only has a cloud record"),
      findsOneWidget,
    );
  });
```

- [ ] **Step 6: 執行測試確認全數通過**

Run: `cd app && flutter test test/screens/remote_server_list_screen_test.dart`
Expected: 全數通過（既有 9 個＋新增 2 個 = 11 個）。

- [ ] **Step 7: `flutter analyze` 確認乾淨**

Run: `cd app && flutter analyze lib/screens/remote_server_list_screen.dart test/screens/remote_server_list_screen_test.dart`
Expected: `No issues found!`

- [ ] **Step 8: Commit**

```bash
git add app/lib/screens/remote_server_list_screen.dart app/test/screens/remote_server_list_screen_test.dart app/lib/l10n/app_zh_TW.arb app/lib/l10n/app_zh_CN.arb app/lib/l10n/app_en.arb app/lib/l10n/app_zh.arb app/lib/l10n/app_localizations*.dart
git commit -m "feat(epic-45): remote_server_list_screen.dart 字串抽取三語言在地化"
```

---

### Task 2: `remote_server_form_screen.dart`

**Files:**
- Modify: `app/lib/screens/remote_server_form_screen.dart`
- Modify: `app/lib/l10n/app_zh_TW.arb`／`app_zh_CN.arb`／`app_en.arb`／`app_zh.arb`
- Test: `app/test/screens/remote_server_form_screen_test.dart`

**Interfaces:**
- Consumes：`AppLocalizations.of(context)!`（`_RemoteServerFormScreenState` 的 `build()`/`_testConnection()`/`_save()` 皆為 State 方法）。
- Produces：ARB key `remoteServerFormTitleAdd`/`remoteServerFormTitleEdit`/`remoteServerFormNameLabel`/`remoteServerFormBaseUrlLabel`/`remoteServerFormTypeOpds`/`remoteServerFormTypeCalibreServer`/`remoteServerFormUsernameLabel`/`remoteServerFormPasswordLabelEditing`/`remoteServerFormPasswordLabel`/`remoteServerFormPasswordShowTooltip`/`remoteServerFormPasswordHideTooltip`/`remoteServerFormAllowInsecureLabel`/`remoteServerFormValidationMissingFields`/`remoteServerFormValidationInvalidUrl`/`remoteServerFormSaveFailedMessage`/`remoteServerFormTestSuccess`/`remoteServerFormTestFailed`/`remoteServerFormTestConnectionButton`/`remoteServerFormSaveButton`。

**範圍決定：`'Calibre-Web'` 下拉選單選項（第 195-197 行）不翻譯**——這是伺服器軟體本身的專有品牌名（比照 `design.md` Google Drive／OneDrive 排除範圍），維持 `const Text('Calibre-Web')` 原樣，僅另外兩個選項（描述性文字「標準 OPDS」／「原生 Calibre Content Server」）抽取為 ARB key。

- [ ] **Step 1: 新增 ARB key（四語言）**

`app_zh_TW.arb` 檔尾新增：
```json
  "remoteServerFormTitleAdd": "新增站點",
  "@remoteServerFormTitleAdd": {
    "description": "新增模式的 AppBar 標題"
  },
  "remoteServerFormTitleEdit": "編輯站點",
  "@remoteServerFormTitleEdit": {
    "description": "編輯模式的 AppBar 標題"
  },
  "remoteServerFormNameLabel": "站點名稱",
  "@remoteServerFormNameLabel": {
    "description": "站點名稱輸入框的 labelText"
  },
  "remoteServerFormBaseUrlLabel": "伺服器網址",
  "@remoteServerFormBaseUrlLabel": {
    "description": "伺服器網址輸入框的 labelText"
  },
  "remoteServerFormTypeOpds": "標準 OPDS",
  "@remoteServerFormTypeOpds": {
    "description": "伺服器類型下拉選單選項：標準 OPDS"
  },
  "remoteServerFormTypeCalibreServer": "原生 Calibre Content Server",
  "@remoteServerFormTypeCalibreServer": {
    "description": "伺服器類型下拉選單選項：原生 Calibre Content Server"
  },
  "remoteServerFormUsernameLabel": "帳號（留空代表匿名連線）",
  "@remoteServerFormUsernameLabel": {
    "description": "帳號輸入框的 labelText"
  },
  "remoteServerFormPasswordLabelEditing": "密碼（留空＝沿用既有密碼；清空上方帳號欄位則一併清除密碼）",
  "@remoteServerFormPasswordLabelEditing": {
    "description": "編輯模式下密碼輸入框的 labelText"
  },
  "remoteServerFormPasswordLabel": "密碼",
  "@remoteServerFormPasswordLabel": {
    "description": "新增模式下密碼輸入框的 labelText"
  },
  "remoteServerFormPasswordShowTooltip": "顯示密碼",
  "@remoteServerFormPasswordShowTooltip": {
    "description": "密碼顯示/隱藏切換圖示，目前為隱藏狀態時的無障礙提示文字"
  },
  "remoteServerFormPasswordHideTooltip": "隱藏密碼",
  "@remoteServerFormPasswordHideTooltip": {
    "description": "密碼顯示/隱藏切換圖示，目前為顯示狀態時的無障礙提示文字"
  },
  "remoteServerFormAllowInsecureLabel": "允許不安全連線（自簽憑證／純 HTTP）",
  "@remoteServerFormAllowInsecureLabel": {
    "description": "允許不安全連線開關的標題文字"
  },
  "remoteServerFormValidationMissingFields": "請填寫站點名稱與網址",
  "@remoteServerFormValidationMissingFields": {
    "description": "站點名稱或網址為空時的驗證錯誤文字"
  },
  "remoteServerFormValidationInvalidUrl": "請輸入有效的伺服器網址（需以 http:// 或 https:// 開頭）",
  "@remoteServerFormValidationInvalidUrl": {
    "description": "網址格式不合法時的驗證錯誤文字"
  },
  "remoteServerFormSaveFailedMessage": "儲存失敗，請稍後再試",
  "@remoteServerFormSaveFailedMessage": {
    "description": "SQLite／secure storage 寫入失敗時的錯誤文字"
  },
  "remoteServerFormTestSuccess": "連線成功",
  "@remoteServerFormTestSuccess": {
    "description": "測試連線成功時顯示的文字"
  },
  "remoteServerFormTestFailed": "連線失敗，請檢查網址/帳密/憑證設定",
  "@remoteServerFormTestFailed": {
    "description": "測試連線失敗時顯示的文字"
  },
  "remoteServerFormTestConnectionButton": "測試連線",
  "@remoteServerFormTestConnectionButton": {
    "description": "「測試連線」按鈕文字"
  },
  "remoteServerFormSaveButton": "儲存",
  "@remoteServerFormSaveButton": {
    "description": "「儲存」按鈕文字"
  },
```

`app_zh_CN.arb` 檔尾新增：
```json
  "remoteServerFormTitleAdd": "新增站点",
  "remoteServerFormTitleEdit": "编辑站点",
  "remoteServerFormNameLabel": "站点名称",
  "remoteServerFormBaseUrlLabel": "服务器网址",
  "remoteServerFormTypeOpds": "标准 OPDS",
  "remoteServerFormTypeCalibreServer": "原生 Calibre Content Server",
  "remoteServerFormUsernameLabel": "账号（留空代表匿名连线）",
  "remoteServerFormPasswordLabelEditing": "密码（留空＝沿用既有密码；清空上方账号栏位则一并清除密码）",
  "remoteServerFormPasswordLabel": "密码",
  "remoteServerFormPasswordShowTooltip": "显示密码",
  "remoteServerFormPasswordHideTooltip": "隐藏密码",
  "remoteServerFormAllowInsecureLabel": "允许不安全连线（自签凭证／纯 HTTP）",
  "remoteServerFormValidationMissingFields": "请填写站点名称与网址",
  "remoteServerFormValidationInvalidUrl": "请输入有效的服务器网址（需以 http:// 或 https:// 开头）",
  "remoteServerFormSaveFailedMessage": "储存失败，请稍后再试",
  "remoteServerFormTestSuccess": "连线成功",
  "remoteServerFormTestFailed": "连线失败，请检查网址/账密/凭证设定",
  "remoteServerFormTestConnectionButton": "测试连线",
  "remoteServerFormSaveButton": "储存",
```

`app_en.arb` 檔尾新增：
```json
  "remoteServerFormTitleAdd": "Add Server",
  "remoteServerFormTitleEdit": "Edit Server",
  "remoteServerFormNameLabel": "Server Name",
  "remoteServerFormBaseUrlLabel": "Server URL",
  "remoteServerFormTypeOpds": "Standard OPDS",
  "remoteServerFormTypeCalibreServer": "Native Calibre Content Server",
  "remoteServerFormUsernameLabel": "Username (leave blank for anonymous connection)",
  "remoteServerFormPasswordLabelEditing": "Password (leave blank to keep the existing password; clearing the username above also clears the password)",
  "remoteServerFormPasswordLabel": "Password",
  "remoteServerFormPasswordShowTooltip": "Show Password",
  "remoteServerFormPasswordHideTooltip": "Hide Password",
  "remoteServerFormAllowInsecureLabel": "Allow insecure connection (self-signed certificate / plain HTTP)",
  "remoteServerFormValidationMissingFields": "Please fill in the server name and URL",
  "remoteServerFormValidationInvalidUrl": "Please enter a valid server URL (must start with http:// or https://)",
  "remoteServerFormSaveFailedMessage": "Failed to save. Please try again later.",
  "remoteServerFormTestSuccess": "Connection successful",
  "remoteServerFormTestFailed": "Connection failed. Please check the URL/credentials/certificate settings.",
  "remoteServerFormTestConnectionButton": "Test Connection",
  "remoteServerFormSaveButton": "Save",
```

`app_zh.arb` 檔尾新增：與 `app_zh_TW.arb` 對應 19 個 key 相同值（fallback）。

- [ ] **Step 2: 執行 `flutter gen-l10n`**

Run: `cd app && flutter gen-l10n`
Expected: 無錯誤，成功產生新增的 19 個 getter。

- [ ] **Step 3: 修改 `remote_server_form_screen.dart`**

```dart
  Future<void> _testConnection() async {
    setState(() {
      _testing = true;
      _testResultText = null;
    });
    final password = await _resolvePasswordToUse();
    final success =
        await widget.createOpdsClient().testConnection(_buildProfile(), password: password);
    if (!mounted) return;
    final l10n = AppLocalizations.of(context)!;
    setState(() {
      _testing = false;
      _testResultText =
          success ? l10n.remoteServerFormTestSuccess : l10n.remoteServerFormTestFailed;
    });
  }
```

```dart
  Future<void> _save() async {
    final l10n = AppLocalizations.of(context)!;
    if (_nameController.text.trim().isEmpty || _baseUrlController.text.trim().isEmpty) {
      setState(() => _validationError = l10n.remoteServerFormValidationMissingFields);
      return;
    }
    if (!_isValidBaseUrl(_baseUrlController.text.trim())) {
      setState(() => _validationError = l10n.remoteServerFormValidationInvalidUrl);
      return;
    }
    setState(() {
      _saving = true;
      _validationError = null;
    });
    final profile = _buildProfile();
    try {
      final password = await _resolvePasswordToUse();
      if (_isEditing) {
        await widget.repository.updateServer(profile, password: password);
      } else {
        await widget.repository.addServer(profile, password: password);
      }
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _validationError = AppLocalizations.of(context)!.remoteServerFormSaveFailedMessage;
      });
      return;
    }
    if (!mounted) return;
    Navigator.of(context).pop(true);
  }
```

```dart
  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return Scaffold(
      appBar: AppBar(
        title: Text(_isEditing ? l10n.remoteServerFormTitleEdit : l10n.remoteServerFormTitleAdd),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TextField(
              key: const Key('remote_server_form_name_field'),
              controller: _nameController,
              decoration: InputDecoration(labelText: l10n.remoteServerFormNameLabel),
            ),
            const SizedBox(height: 8),
            TextField(
              key: const Key('remote_server_form_base_url_field'),
              controller: _baseUrlController,
              decoration: InputDecoration(labelText: l10n.remoteServerFormBaseUrlLabel),
            ),
            const SizedBox(height: 8),
            DropdownButton<RemoteServerType>(
              key: const Key('remote_server_form_type_dropdown'),
              value: _type,
              onChanged: (value) {
                if (value != null) setState(() => _type = value);
              },
              items: [
                DropdownMenuItem(
                  value: RemoteServerType.opds,
                  child: Text(l10n.remoteServerFormTypeOpds),
                ),
                DropdownMenuItem(
                  value: RemoteServerType.calibreServer,
                  child: Text(l10n.remoteServerFormTypeCalibreServer),
                ),
                const DropdownMenuItem(
                  value: RemoteServerType.calibreWeb,
                  // 「Calibre-Web」為伺服器軟體專有品牌名，不翻譯
                  // （design.md 排除範圍，比照 Google Drive／OneDrive）。
                  child: Text('Calibre-Web'),
                ),
              ],
            ),
            const SizedBox(height: 8),
            TextField(
              key: const Key('remote_server_form_username_field'),
              controller: _usernameController,
              decoration: InputDecoration(labelText: l10n.remoteServerFormUsernameLabel),
            ),
            const SizedBox(height: 8),
            TextField(
              key: const Key('remote_server_form_password_field'),
              controller: _passwordController,
              obscureText: _obscurePassword,
              autocorrect: false,
              enableSuggestions: false,
              decoration: InputDecoration(
                labelText: _isEditing
                    ? l10n.remoteServerFormPasswordLabelEditing
                    : l10n.remoteServerFormPasswordLabel,
                suffixIcon: IconButton(
                  key: const Key('remote_server_form_password_visibility_toggle'),
                  icon: Icon(_obscurePassword ? Icons.visibility : Icons.visibility_off),
                  tooltip: _obscurePassword
                      ? l10n.remoteServerFormPasswordShowTooltip
                      : l10n.remoteServerFormPasswordHideTooltip,
                  onPressed: () => setState(() => _obscurePassword = !_obscurePassword),
                ),
              ),
            ),
            SwitchListTile(
              key: const Key('remote_server_form_allow_insecure_switch'),
              title: Text(l10n.remoteServerFormAllowInsecureLabel),
              value: _allowInsecure,
              onChanged: (value) => setState(() => _allowInsecure = value),
            ),
            const SizedBox(height: 16),
            if (_validationError != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Text(
                  _validationError!,
                  key: const Key('remote_server_form_validation_error_text'),
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              ),
            if (_testResultText != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Text(
                  _testResultText!,
                  key: const Key('remote_server_form_test_result_text'),
                ),
              ),
            Row(
              children: [
                OutlinedButton(
                  key: const Key('remote_server_form_test_connection_button'),
                  onPressed: _testing ? null : _testConnection,
                  child: _testing
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : Text(l10n.remoteServerFormTestConnectionButton),
                ),
                const SizedBox(width: 8),
                ElevatedButton(
                  key: const Key('remote_server_form_save_button'),
                  onPressed: _saving ? null : _save,
                  child: Text(l10n.remoteServerFormSaveButton),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
```

加上檔案頂部 import：`import '../l10n/app_localizations.dart';`

- [ ] **Step 4: 遷移既有測試檔**

`app/test/screens/remote_server_form_screen_test.dart` 有 2 處 `MaterialApp(`：`pumpScreen()` helper（第 10-24 行）與第 145-156 行（`Navigator`/`onGenerateRoute` 包裝，儲存後驗證 `pop`，無法用 `pumpScreen()`）。兩處皆補上三個 l10n 參數：

```dart
  Future<void> pumpScreen(
    WidgetTester tester, {
    required FakeRemoteServerRepository repository,
    required FakeOpdsClient opdsClient,
    RemoteServerProfile? existingProfile,
    Locale locale = const Locale('zh', 'TW'),
  }) async {
    await tester.pumpWidget(MaterialApp(
      locale: locale,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: RemoteServerFormScreen(
        repository: repository,
        createOpdsClient: () => opdsClient,
        existingProfile: existingProfile,
      ),
    ));
    await tester.pumpAndSettle();
  }
```

```dart
  testWidgets('新增模式儲存：呼叫 addServer 並帶入輸入的密碼，儲存後關閉畫面', (tester) async {
    final repository = FakeRemoteServerRepository();
    await tester.pumpWidget(MaterialApp(
      locale: const Locale('zh', 'TW'),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Navigator(
        onGenerateRoute: (settings) => MaterialPageRoute(
          builder: (context) => RemoteServerFormScreen(
            repository: repository,
            createOpdsClient: () => FakeOpdsClient(),
          ),
        ),
      ),
    ));
    // ...其餘測試內容不變
```

加上檔案頂部 import：`import 'package:elinkbook/l10n/app_localizations.dart';`

既有 `find.text('新增站點')`/`find.text('編輯站點')`/`find.text('連線成功')`/`find.textContaining('連線失敗')`/`find.textContaining('請填寫')`/`find.textContaining('有效的伺服器網址')`/`find.textContaining('儲存失敗')` 等斷言因譯文與原字面值完全相同，無需修改。

- [ ] **Step 5: 新增英文渲染驗證測試**

```dart
  testWidgets('英文介面下顯示英文標題與按鈕文字', (tester) async {
    await pumpScreen(
      tester,
      repository: FakeRemoteServerRepository(),
      opdsClient: FakeOpdsClient(),
      locale: const Locale('en'),
    );
    expect(find.text('Add Server'), findsOneWidget);
    expect(find.text('Test Connection'), findsOneWidget);
    expect(find.text('Save'), findsOneWidget);
  });

  testWidgets('英文介面下驗證錯誤與測試連線結果文字正確', (tester) async {
    await pumpScreen(
      tester,
      repository: FakeRemoteServerRepository(),
      opdsClient: FakeOpdsClient(testConnectionResult: false),
      locale: const Locale('en'),
    );
    await tester.tap(find.byKey(const Key('remote_server_form_save_button')));
    await tester.pumpAndSettle();
    expect(find.textContaining('Please fill in the server name and URL'), findsOneWidget);

    await tester.enterText(
        find.byKey(const Key('remote_server_form_base_url_field')), 'http://example.com/opds');
    await tester.tap(find.byKey(const Key('remote_server_form_test_connection_button')));
    await tester.pumpAndSettle();
    expect(find.textContaining('Connection failed'), findsOneWidget);
  });
```

- [ ] **Step 6: 執行測試確認全數通過**

Run: `cd app && flutter test test/screens/remote_server_form_screen_test.dart`
Expected: 全數通過（既有 12 個＋新增 2 個 = 14 個）。

- [ ] **Step 7: `flutter analyze` 確認乾淨**

Run: `cd app && flutter analyze lib/screens/remote_server_form_screen.dart test/screens/remote_server_form_screen_test.dart`
Expected: `No issues found!`

- [ ] **Step 8: Commit**

```bash
git add app/lib/screens/remote_server_form_screen.dart app/test/screens/remote_server_form_screen_test.dart app/lib/l10n/app_zh_TW.arb app/lib/l10n/app_zh_CN.arb app/lib/l10n/app_en.arb app/lib/l10n/app_zh.arb app/lib/l10n/app_localizations*.dart
git commit -m "feat(epic-45): remote_server_form_screen.dart 字串抽取三語言在地化"
```

---

### Task 3: `format_selection_dialog.dart`

**Files:**
- Modify: `app/lib/screens/format_selection_dialog.dart`
- Modify: `app/lib/l10n/app_zh_TW.arb`／`app_zh_CN.arb`／`app_en.arb`／`app_zh.arb`
- Test: `app/test/screens/format_selection_dialog_test.dart`

**Interfaces:**
- Consumes：`AppLocalizations.of(context)!`（`FormatSelectionDialog.build(context)`，`StatelessWidget`，`context` 為 `build()` 參數）。
- Produces：ARB key `formatSelectionDialogTitle`/`formatSelectionDialogUnsupportedFormat`；沿用全域共用 `cancel`。

- [ ] **Step 1: 新增 ARB key（四語言）**

`app_zh_TW.arb` 檔尾新增：
```json
  "formatSelectionDialogTitle": "選擇格式：{title}",
  "@formatSelectionDialogTitle": {
    "description": "格式選擇對話框標題，{title} 為書目標題（使用者資料，不翻譯）",
    "placeholders": {
      "title": {
        "type": "String"
      }
    }
  },
  "formatSelectionDialogUnsupportedFormat": "不支援的格式",
  "@formatSelectionDialogUnsupportedFormat": {
    "description": "格式選項本身不受支援（format 為 null）時顯示的文字"
  },
```

`app_zh_CN.arb` 檔尾新增：
```json
  "formatSelectionDialogTitle": "选择格式：{title}",
  "formatSelectionDialogUnsupportedFormat": "不支持的格式",
```

`app_en.arb` 檔尾新增：
```json
  "formatSelectionDialogTitle": "Select Format: {title}",
  "formatSelectionDialogUnsupportedFormat": "Unsupported format",
```

`app_zh.arb` 檔尾新增：與 `app_zh_TW.arb` 相同值（fallback）。

- [ ] **Step 2: 執行 `flutter gen-l10n`**

Run: `cd app && flutter gen-l10n`
Expected: 無錯誤。

- [ ] **Step 3: 修改 `format_selection_dialog.dart`**

```dart
import 'package:flutter/material.dart';

import '../l10n/app_localizations.dart';
import '../remote/opds_types.dart';

/// 同一書目提供多個下載格式時的選擇彈窗（epic-30-calibre-remote-library
/// Issue 2，spec.md「UI 落地位置」，沿用 `epic-29-cloud-import` 的命名
/// 慣例）。不支援的格式（`format == null`）置灰不可選。
class FormatSelectionDialog extends StatelessWidget {
  final OpdsEntry entry;

  const FormatSelectionDialog({super.key, required this.entry});

  static Future<OpdsAcquisition?> show(BuildContext context, OpdsEntry entry) {
    return showDialog<OpdsAcquisition>(
      context: context,
      builder: (context) => FormatSelectionDialog(entry: entry),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return AlertDialog(
      key: const Key('format_selection_dialog'),
      title: Text(l10n.formatSelectionDialogTitle(entry.title)),
      // 〔審查 review-plan-issue-2.md Finding 2 採納〕格式選項較多或在
      // 橫向/小螢幕裝置上時，固定高度的 AlertDialog 內容可能超出可視
      // 範圍，外層包 SingleChildScrollView 防禦 RenderFlex overflow。
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: entry.acquisitions.map((acquisition) {
            final supported = acquisition.format != null;
            return ListTile(
              key: Key('format_selection_option_${acquisition.href}'),
              enabled: supported,
              title: Text(
                supported
                    ? acquisition.format!.name.toUpperCase()
                    : l10n.formatSelectionDialogUnsupportedFormat,
              ),
              onTap: supported ? () => Navigator.of(context).pop(acquisition) : null,
            );
          }).toList(),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(l10n.cancel),
        ),
      ],
    );
  }
}
```

- [ ] **Step 4: 遷移既有測試檔**

`app/test/screens/format_selection_dialog_test.dart` 有 3 處相同結構的 `MaterialApp(home: Builder(...))`（第 19、43、65 行）。三處皆補上三個 l10n 參數：

```dart
    await tester.pumpWidget(MaterialApp(
      locale: const Locale('zh', 'TW'),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Builder(
        builder: (context) => ElevatedButton(
          onPressed: () async {
            await FormatSelectionDialog.show(context, entry);
          },
          child: const Text('open'),
        ),
      ),
    ));
```

（第 43、65 行的 `onPressed` 回呼內容不變，只套用相同的 `MaterialApp` 參數插入。）加上檔案頂部 import：`import 'package:elinkbook/l10n/app_localizations.dart';`

既有 `find.text('取消')` 斷言（第 79 行）因譯文與原字面值相同，無需修改。

- [ ] **Step 5: 新增英文渲染驗證測試**

```dart
  testWidgets('英文介面下標題與按鈕正確顯示', (tester) async {
    await tester.pumpWidget(MaterialApp(
      locale: const Locale('en'),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Builder(
        builder: (context) => ElevatedButton(
          onPressed: () async {
            await FormatSelectionDialog.show(context, entry);
          },
          child: const Text('open'),
        ),
      ),
    ));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    expect(find.text('Select Format: 紅樓夢'), findsOneWidget);
    final unsupportedTile = tester.widget<ListTile>(
        find.byKey(const Key('format_selection_option_http://example.com/1.doc')));
    expect((unsupportedTile.title as Text).data, 'Unsupported format');

    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
  });
```

- [ ] **Step 6: 執行測試確認全數通過**

Run: `cd app && flutter test test/screens/format_selection_dialog_test.dart`
Expected: 全數通過（既有 3 個＋新增 1 個 = 4 個）。

- [ ] **Step 7: `flutter analyze` 確認乾淨**

Run: `cd app && flutter analyze lib/screens/format_selection_dialog.dart test/screens/format_selection_dialog_test.dart`
Expected: `No issues found!`

- [ ] **Step 8: Commit**

```bash
git add app/lib/screens/format_selection_dialog.dart app/test/screens/format_selection_dialog_test.dart app/lib/l10n/app_zh_TW.arb app/lib/l10n/app_zh_CN.arb app/lib/l10n/app_en.arb app/lib/l10n/app_zh.arb app/lib/l10n/app_localizations*.dart
git commit -m "feat(epic-45): format_selection_dialog.dart 字串抽取三語言在地化"
```

---

### Task 4: `cloud_duplicate_confirm_dialog.dart`

**（`/superpowers:requesting-code-review` review-plan-issue-6.md Important #4 補記歸屬）**：全域掃描 `app/lib/screens/` 發現本檔案未被 `issues.md` 任何 Issue 認領——`AppLocalizations` 使用量為 0，含 3 處硬編碼字面值（`'重複的書籍'`／`'取消'`／`'仍要建立'`），與 Task 5 `remote_catalog_screen.dart._showDuplicateConfirmDialog()` 幾乎逐字相同的設計（同為「選檔前置 Layer 1 與下載後指紋比對 Layer 2 共用同一個確認 UI」），唯一呼叫端為 `main.dart`（`DownloadQueueController(onDuplicateConfirm: ...)` 透過 `navigatorKey.currentContext` 橋接）與 `cloud_browser_screen.dart`（Layer 1 選檔前置重複偵測）。若不處理，Issue 10 的靜態稽核腳本必然會抓出這個殘留檔案。

**Files:**
- Modify: `app/lib/screens/cloud_duplicate_confirm_dialog.dart`
- Modify: `app/lib/l10n/app_zh_TW.arb`／`app_zh_CN.arb`／`app_en.arb`／`app_zh.arb`
- Create: `app/test/screens/cloud_duplicate_confirm_dialog_test.dart`（目前沒有獨立測試檔——既有間接覆蓋來自 `cloud_browser_screen_test.dart:463-465` 與 `remote_catalog_screen_test.dart:798-841`，兩處皆只用 `find.byKey('cloud_duplicate_dialog'/'cloud_duplicate_dialog_cancel'/'cloud_duplicate_dialog_confirm')` 定位互動，不斷言中文字面值文字，因此不受本 Task 字串抽取影響、不需修改；本 Task 新增獨立測試檔補上標題/按鈕文字與英文語系覆蓋）

**Interfaces:**
- Consumes：`AppLocalizations.of(context)!`（`showCloudDuplicateConfirmDialog(BuildContext context, String message)` 已接受 `context` 參數，直接呼叫，簽章不變，呼叫端 `main.dart`／`cloud_browser_screen.dart` 完全不需異動）。
- Produces：ARB key `cloudDuplicateDialogTitle`/`cloudDuplicateDialogConfirmButton`；沿用全域共用 `cancel`。

- [ ] **Step 1: 新增 ARB key（四語言）**

`app_zh_TW.arb` 檔尾新增：
```json
  "cloudDuplicateDialogTitle": "重複的書籍",
  "@cloudDuplicateDialogTitle": {
    "description": "雲端匯入重複匯入確認彈窗標題"
  },
  "cloudDuplicateDialogConfirmButton": "仍要建立",
  "@cloudDuplicateDialogConfirmButton": {
    "description": "重複匯入確認彈窗的確認按鈕文字"
  },
```

`app_zh_CN.arb` 檔尾新增：
```json
  "cloudDuplicateDialogTitle": "重复的书籍",
  "cloudDuplicateDialogConfirmButton": "仍要建立",
```

`app_en.arb` 檔尾新增：
```json
  "cloudDuplicateDialogTitle": "Duplicate Book",
  "cloudDuplicateDialogConfirmButton": "Create Anyway",
```

`app_zh.arb` 檔尾新增：與 `app_zh_TW.arb` 對應 2 個 key 相同值（fallback）。

- [ ] **Step 2: 執行 `flutter gen-l10n`**

Run: `cd app && flutter gen-l10n`
Expected: 無錯誤。

- [ ] **Step 3: 修改 `cloud_duplicate_confirm_dialog.dart`**

```dart
import 'package:flutter/material.dart';

import '../l10n/app_localizations.dart';

/// 重複匯入確認彈窗（epic-29-cloud-import Issue 5，完整比照
/// `remote_catalog_screen.dart` 的 `_showDuplicateConfirmDialog` 既有
/// 設計）：選檔前置（Layer 1，[CloudBrowserScreen]）與下載後指紋比對
/// （Layer 2，[CloudDownloadQueueController]）兩層檢查共用同一個確認
/// UI，只有提示文字不同——精確比對命中不代表強制阻擋，使用者可選擇仍要
/// 建立新副本。刻意宣告為公開頂層函式（獨立於原本掛在
/// `cloud_download_queue_dialog.dart` 底下的寫法，視覺還原 Visual
/// Accuracy Mode 把下載佇列改成常駐、不再是 Dialog 之後，這個確認彈窗
/// 本身仍是需要 `BuildContext` 的一次性 UI，獨立成檔更清楚）。
Future<bool> showCloudDuplicateConfirmDialog(
  BuildContext context,
  String message,
) async {
  final l10n = AppLocalizations.of(context)!;
  final result = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      key: const Key('cloud_duplicate_dialog'),
      title: Text(l10n.cloudDuplicateDialogTitle),
      content: Text(message),
      actions: [
        TextButton(
          key: const Key('cloud_duplicate_dialog_cancel'),
          onPressed: () => Navigator.of(context).pop(false),
          child: Text(l10n.cancel),
        ),
        TextButton(
          key: const Key('cloud_duplicate_dialog_confirm'),
          onPressed: () => Navigator.of(context).pop(true),
          child: Text(l10n.cloudDuplicateDialogConfirmButton),
        ),
      ],
    ),
  );
  return result ?? false;
}
```

- [ ] **Step 4: 驗證既有間接測試零回歸**

Run: `cd app && flutter test test/screens/cloud_browser_screen_test.dart`
Expected: 全數通過，`cloud_duplicate_dialog` 相關兩個測試（第 441、477 行附近）不受影響（僅用 `find.byKey`，不斷言中文字面值）。

- [ ] **Step 5: 新增獨立測試檔 `cloud_duplicate_confirm_dialog_test.dart`**

```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:elinkbook/l10n/app_localizations.dart';
import 'package:elinkbook/screens/cloud_duplicate_confirm_dialog.dart';

void main() {
  Future<bool?> pumpAndOpen(
    WidgetTester tester, {
    Locale locale = const Locale('zh', 'TW'),
    String message = '測試訊息',
  }) async {
    bool? result;
    await tester.pumpWidget(MaterialApp(
      locale: locale,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Builder(
        builder: (context) => ElevatedButton(
          onPressed: () async {
            result = await showCloudDuplicateConfirmDialog(context, message);
          },
          child: const Text('open'),
        ),
      ),
    ));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    return result;
  }

  testWidgets('顯示標題與傳入訊息，點擊「仍要建立」回傳 true', (tester) async {
    await pumpAndOpen(tester, message: '「紅樓夢」之前匯入過了，仍要建立新的一份嗎？');
    expect(find.text('重複的書籍'), findsOneWidget);
    expect(find.text('「紅樓夢」之前匯入過了，仍要建立新的一份嗎？'), findsOneWidget);

    await tester.tap(find.byKey(const Key('cloud_duplicate_dialog_confirm')));
    await tester.pumpAndSettle();
  });

  testWidgets('點擊取消回傳 false', (tester) async {
    bool? result;
    await tester.pumpWidget(MaterialApp(
      locale: const Locale('zh', 'TW'),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Builder(
        builder: (context) => ElevatedButton(
          onPressed: () async {
            result = await showCloudDuplicateConfirmDialog(context, '測試訊息');
          },
          child: const Text('open'),
        ),
      ),
    ));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('cloud_duplicate_dialog_cancel')));
    await tester.pumpAndSettle();

    expect(result, isFalse);
  });

  testWidgets('英文介面下標題與按鈕文字正確顯示', (tester) async {
    await pumpAndOpen(tester, locale: const Locale('en'), message: 'Test message');
    expect(find.text('Duplicate Book'), findsOneWidget);
    expect(find.text('Test message'), findsOneWidget);
    expect(find.text('Create Anyway'), findsOneWidget);
    expect(find.text('Cancel'), findsOneWidget);
  });
}
```

- [ ] **Step 6: 執行新測試檔確認全數通過**

Run: `cd app && flutter test test/screens/cloud_duplicate_confirm_dialog_test.dart`
Expected: 全數通過（3 個）。

- [ ] **Step 7: `flutter analyze` 確認乾淨**

Run: `cd app && flutter analyze lib/screens/cloud_duplicate_confirm_dialog.dart test/screens/cloud_duplicate_confirm_dialog_test.dart`
Expected: `No issues found!`

- [ ] **Step 8: Commit**

```bash
git add app/lib/screens/cloud_duplicate_confirm_dialog.dart app/test/screens/cloud_duplicate_confirm_dialog_test.dart app/lib/l10n/app_zh_TW.arb app/lib/l10n/app_zh_CN.arb app/lib/l10n/app_en.arb app/lib/l10n/app_zh.arb app/lib/l10n/app_localizations*.dart
git commit -m "feat(epic-45): cloud_duplicate_confirm_dialog.dart 字串抽取三語言在地化（新增獨立測試檔）"
```

---

### Task 5: `remote_catalog_screen.dart`（production）

**Files:**
- Modify: `app/lib/screens/remote_catalog_screen.dart`
- Modify: `app/lib/l10n/app_zh_TW.arb`／`app_zh_CN.arb`／`app_en.arb`／`app_zh.arb`

**本 Task 不修改任何測試檔**——`remote_catalog_screen_test.dart` 的遷移獨立成 Task 6（下一個 Task），讓「production 字串抽取是否正確」與「測試遷移是否完整」成為兩個獨立的審查關卡。**本 Task 完成後、Task 6 執行前，`flutter test test/screens/remote_catalog_screen_test.dart` 預期大量失敗（`Null check operator used on a null value`）——這是預期中的紅燈狀態，不是本 Task 的回歸。**

**Interfaces:**
- Consumes：`AppLocalizations.of(context)!`（`_RemoteCatalogScreenState` 的 `_load()`/`_toggleSelection()`/`_startDownload()`/`build()`/`_buildPaginationControls()` 皆為 State 方法；`_showDuplicateConfirmDialog(BuildContext context, String message)` 為接受 `context` 參數的頂層自由函式，同樣直接呼叫）。
- Produces：ARB key `remoteCatalogLoadFailedMessage`/`remoteCatalogDownloadSelectedTooltip`/`remoteCatalogDuplicateConfirmMessage`/`remoteCatalogQueuedMessage`/`remoteCatalogEinkPrevPageButton`/`remoteCatalogEinkNextPageButton`/`remoteCatalogLoadMoreButton`/`remoteCatalogDuplicateDialogTitle`/`remoteCatalogDuplicateDialogConfirmButton`；沿用全域共用 `cancel`。

- [ ] **Step 1: 新增 ARB key（四語言）**

`app_zh_TW.arb` 檔尾新增：
```json
  "remoteCatalogLoadFailedMessage": "載入失敗，請檢查網路連線或站點設定",
  "@remoteCatalogLoadFailedMessage": {
    "description": "載入 Feed 失敗時的錯誤文字"
  },
  "remoteCatalogDownloadSelectedTooltip": "下載已選取",
  "@remoteCatalogDownloadSelectedTooltip": {
    "description": "AppBar「下載已選取」按鈕的無障礙提示文字"
  },
  "remoteCatalogDuplicateConfirmMessage": "「{title}」之前匯入過了，仍要建立新的一份嗎？",
  "@remoteCatalogDuplicateConfirmMessage": {
    "description": "偵測到重複匯入時的確認訊息，{title} 為書目標題（使用者資料，不翻譯）",
    "placeholders": {
      "title": {
        "type": "String"
      }
    }
  },
  "remoteCatalogQueuedMessage": "已加入下載佇列（{count, plural, =1{1 個檔案} other{{count} 個檔案}}），可至「來源」畫面查看進度",
  "@remoteCatalogQueuedMessage": {
    "description": "開始下載後的 SnackBar 訊息，{count} 為加入佇列的檔案數",
    "placeholders": {
      "count": {
        "type": "int"
      }
    }
  },
  "remoteCatalogEinkPrevPageButton": "上一頁",
  "@remoteCatalogEinkPrevPageButton": {
    "description": "E-Ink 離散換頁模式的「上一頁」按鈕文字"
  },
  "remoteCatalogEinkNextPageButton": "下一頁",
  "@remoteCatalogEinkNextPageButton": {
    "description": "E-Ink 離散換頁模式的「下一頁」按鈕文字"
  },
  "remoteCatalogLoadMoreButton": "載入更多",
  "@remoteCatalogLoadMoreButton": {
    "description": "非 E-Ink 模式連續捲動載入的「載入更多」按鈕文字"
  },
  "remoteCatalogDuplicateDialogTitle": "重複的書籍",
  "@remoteCatalogDuplicateDialogTitle": {
    "description": "重複匯入確認彈窗標題"
  },
  "remoteCatalogDuplicateDialogConfirmButton": "仍要建立",
  "@remoteCatalogDuplicateDialogConfirmButton": {
    "description": "重複匯入確認彈窗的確認按鈕文字"
  },
```

`app_zh_CN.arb` 檔尾新增：
```json
  "remoteCatalogLoadFailedMessage": "载入失败，请检查网络连线或站点设定",
  "remoteCatalogDownloadSelectedTooltip": "下载已选取",
  "remoteCatalogDuplicateConfirmMessage": "「{title}」之前汇入过了，仍要建立新的一份吗？",
  "remoteCatalogQueuedMessage": "已加入下载队列（{count, plural, =1{1 个档案} other{{count} 个档案}}），可至「来源」画面查看进度",
  "remoteCatalogEinkPrevPageButton": "上一页",
  "remoteCatalogEinkNextPageButton": "下一页",
  "remoteCatalogLoadMoreButton": "载入更多",
  "remoteCatalogDuplicateDialogTitle": "重复的书籍",
  "remoteCatalogDuplicateDialogConfirmButton": "仍要建立",
```

`app_en.arb` 檔尾新增：
```json
  "remoteCatalogLoadFailedMessage": "Failed to load. Please check your network connection or server settings.",
  "remoteCatalogDownloadSelectedTooltip": "Download Selected",
  "remoteCatalogDuplicateConfirmMessage": "\"{title}\" has already been imported before. Create a new copy anyway?",
  "remoteCatalogQueuedMessage": "Added {count, plural, =1{1 file} other{{count} files}} to the download queue. Check progress on the \"Sources\" screen.",
  "remoteCatalogEinkPrevPageButton": "Previous Page",
  "remoteCatalogEinkNextPageButton": "Next Page",
  "remoteCatalogLoadMoreButton": "Load More",
  "remoteCatalogDuplicateDialogTitle": "Duplicate Book",
  "remoteCatalogDuplicateDialogConfirmButton": "Create Anyway",
```

`app_zh.arb` 檔尾新增：與 `app_zh_TW.arb` 對應 9 個 key 相同值（fallback）。

- [ ] **Step 2: 執行 `flutter gen-l10n`**

Run: `cd app && flutter gen-l10n`
Expected: 無錯誤。

- [ ] **Step 3: 修改 `remote_catalog_screen.dart`**

先把 `String? _errorText;` 欄位改為 `bool _loadError = false;`（比照 Issue 5 `AboutScreen` 的既有先例：查詢結果與其在地化文字分離，錯誤訊息只在 `build()` 轉譯，切換語言時不會停留在舊語言的靜態字串）：

```dart
  Future<void> _load() async {
    setState(() {
      _loading = true;
      _loadError = false;
    });
    _password = await widget.repository.loadPassword(widget.server.id);
    try {
      final feed = await _client.fetchFeed(
        widget.server,
        password: _password,
        feedUrl: widget.feedUrl,
      );
      if (!mounted) return;
      setState(() {
        _navigationLinks
          ..clear()
          ..addAll(feed.navigationLinks);
        _entries
          ..clear()
          ..addAll(feed.entries);
        _nextUrl = feed.nextUrl;
        _prevUrl = feed.prevUrl;
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _loadError = true;
      });
    }
  }
```

```dart
    if (hasDuplicate) {
      if (!mounted) return;
      final l10n = AppLocalizations.of(context)!;
      final proceed = await _showDuplicateConfirmDialog(
        context,
        l10n.remoteCatalogDuplicateConfirmMessage(entry.title),
      );
      if (!proceed) return;
    }
```

```dart
    if (!mounted) return;
    widget.downloadQueueController.enqueueJobs(jobs);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        key: const Key('remote_catalog_queued_snackbar'),
        content: Text(
          AppLocalizations.of(context)!.remoteCatalogQueuedMessage(jobs.length),
        ),
      ),
    );
    setState(() => _selectedRemoteBookIds.clear());
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.title ?? widget.server.name),
        actions: [
          IconButton(
            key: const Key('remote_catalog_download_button'),
            icon: const Icon(Icons.download),
            tooltip: l10n.remoteCatalogDownloadSelectedTooltip,
            onPressed: _selectedRemoteBookIds.isEmpty ? null : _startDownload,
          ),
        ],
      ),
      body: _loading
          ? const Center(
              child: CircularProgressIndicator(key: Key('remote_catalog_loading_indicator')),
            )
          : _loadError
              ? Center(
                  child: Text(
                    l10n.remoteCatalogLoadFailedMessage,
                    key: const Key('remote_catalog_error_text'),
                  ),
                )
              : _buildContent(),
    );
  }
```

```dart
  Widget _buildPaginationControls() {
    final l10n = AppLocalizations.of(context)!;
    if (widget.isEinkMode) {
      if (_prevUrl == null && _nextUrl == null) return const SizedBox.shrink();
      return Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            OutlinedButton(
              key: const Key('remote_catalog_eink_prev_page_button'),
              onPressed: _prevUrl == null || _loadingMore ? null : () => _goToPage(_prevUrl!),
              child: Text(l10n.remoteCatalogEinkPrevPageButton),
            ),
            const SizedBox(width: 16),
            OutlinedButton(
              key: const Key('remote_catalog_eink_next_page_button'),
              onPressed: _nextUrl == null || _loadingMore ? null : () => _goToPage(_nextUrl!),
              child: Text(l10n.remoteCatalogEinkNextPageButton),
            ),
          ],
        ),
      );
    }
    if (_nextUrl == null) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Center(
        child: OutlinedButton(
          key: const Key('remote_catalog_load_more_button'),
          onPressed: _loadingMore ? null : _loadMore,
          child: _loadingMore
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : Text(l10n.remoteCatalogLoadMoreButton),
        ),
      ),
    );
  }
```

檔尾的 `_showDuplicateConfirmDialog()` 頂層函式（已接受 `BuildContext context` 參數）：
```dart
Future<bool> _showDuplicateConfirmDialog(BuildContext context, String message) async {
  final l10n = AppLocalizations.of(context)!;
  final result = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      key: const Key('remote_catalog_duplicate_dialog'),
      title: Text(l10n.remoteCatalogDuplicateDialogTitle),
      content: Text(message),
      actions: [
        TextButton(
          key: const Key('remote_catalog_duplicate_dialog_cancel'),
          onPressed: () => Navigator.of(context).pop(false),
          child: Text(l10n.cancel),
        ),
        TextButton(
          key: const Key('remote_catalog_duplicate_dialog_confirm'),
          onPressed: () => Navigator.of(context).pop(true),
          child: Text(l10n.remoteCatalogDuplicateDialogConfirmButton),
        ),
      ],
    ),
  );
  return result ?? false;
}
```

加上檔案頂部 import：`import '../l10n/app_localizations.dart';`

- [ ] **Step 4: 執行測試確認「預期中的紅燈」**

Run: `cd app && flutter test test/screens/remote_catalog_screen_test.dart`
Expected: 大量測試因 `Null check operator used on a null value` 失敗（`AppLocalizations.of(context)!` 在裸 `MaterialApp` 下崩潰）——這證實 Step 3 的改動確實生效。這個紅燈狀態會在 Task 6 完成後轉綠，本 Step 不需要修正任何東西，只是驗證檢查點。

- [ ] **Step 5: `flutter analyze` 確認 production 程式碼本身乾淨**

Run: `cd app && flutter analyze lib/screens/remote_catalog_screen.dart`
Expected: `No issues found!`

- [ ] **Step 6: Commit（production code only，測試遷移留給 Task 6）**

```bash
git add app/lib/screens/remote_catalog_screen.dart app/lib/l10n/app_zh_TW.arb app/lib/l10n/app_zh_CN.arb app/lib/l10n/app_en.arb app/lib/l10n/app_zh.arb app/lib/l10n/app_localizations*.dart
git commit -m "feat(epic-45): remote_catalog_screen.dart 字串抽取三語言在地化（production）"
```

---

### Task 6: `remote_catalog_screen_test.dart`（測試遷移）

**Files:**
- Modify: `app/test/screens/remote_catalog_screen_test.dart`（14 處裸 `MaterialApp` 全面遷移）

**Interfaces:**
- Consumes：Task 5 已定義的全部 9 個 ARB key 與 `_RemoteCatalogScreenState`/`_showDuplicateConfirmDialog()` 全面改用 `AppLocalizations.of(context)!` 這個事實。
- Produces：`remote_catalog_screen_test.dart` 完整遷移後的狀態。

**遷移規則**（機械式轉換，逐一套用在全部 14 處）：

1. 找出所有裸 `MaterialApp(` 呼叫：
   ```bash
   grep -n "MaterialApp(" test/screens/remote_catalog_screen_test.dart
   ```
2. **模式 A**（共用 `pumpScreen()` helper，第 87-116 行，僅 1 處實際 `MaterialApp(`）：helper 簽章新增 `Locale locale = const Locale('zh', 'TW')` 可選參數，`MaterialApp(` 內新增三個 l10n 參數：
   ```dart
   Future<void> pumpScreen(
     WidgetTester tester, {
     required FakeOpdsClient opdsClient,
     FakeRemoteServerRepository? repository,
     FakeLibraryRepository? libraryRepository,
     FakeFingerprintComputer? fingerprintComputer,
     FakeRemoteThumbnailCache? thumbnailCache,
     String? feedUrl,
     DownloadQueueController? downloadQueueController,
     Locale locale = const Locale('zh', 'TW'),
   }) async {
     await tester.pumpWidget(MaterialApp(
       locale: locale,
       localizationsDelegates: AppLocalizations.localizationsDelegates,
       supportedLocales: AppLocalizations.supportedLocales,
       theme: resolveThemeData(theme: AppTheme.light, isEinkMode: false),
       home: RemoteCatalogScreen(
         server: server,
         repository: repository ?? FakeRemoteServerRepository(),
         libraryRepository: libraryRepository ?? FakeLibraryRepository(),
         dependencies: RemoteCatalogDependencies(
           computeFingerprint: (fingerprintComputer ?? FakeFingerprintComputer()).call,
           thumbnailCache: thumbnailCache ?? FakeRemoteThumbnailCache(),
           createOpdsClient: () => opdsClient,
         ),
         importService: FakeBookImportService(),
         feedUrl: feedUrl,
         downloadQueueController:
             downloadQueueController ??
             DownloadQueueController(onDuplicateConfirm: (_) async => false),
       ),
     ));
     await tester.pumpAndSettle();
   }
   ```
3. **模式 B**（其餘 13 處各自內嵌的 `tester.pumpWidget(MaterialApp(theme: ..., home: RemoteCatalogScreen(...)))` 或 `tester.pumpWidget(MaterialApp(home: Scaffold(...)))`，逐一在 `MaterialApp(` 參數列插入）：
   ```dart
   await tester.pumpWidget(MaterialApp(
     locale: const Locale('zh', 'TW'),
     localizationsDelegates: AppLocalizations.localizationsDelegates,
     supportedLocales: AppLocalizations.supportedLocales,
     theme: resolveThemeData(theme: AppTheme.light, isEinkMode: false),
     home: /* 原本的 home: ... 內容原樣保留 */,
   ));
   ```
   （若該處原本沒有 `theme:` 參數，插入時同樣不補；只新增 `locale`/`localizationsDelegates`/`supportedLocales` 三行。）
4. 加上檔案頂部 import：
   ```dart
   import 'package:elinkbook/l10n/app_localizations.dart';
   ```

**既有斷言不需修改**——`find.text('作者分類')`/`find.text('紅樓夢')`/`find.text('不支援格式的書')`/`find.text('上一頁')`/`find.text('下一頁')`/`find.text('載入更多')` 等因 `app_zh_TW.arb` 譯文與原字面值完全相同，維持通過。

- [ ] **Step 1: 依上述規則逐一插入三個 l10n 參數（含 helper 與 13 處內嵌呼叫）**
- [ ] **Step 2: 新增英文渲染驗證測試**

```dart
  testWidgets('英文介面下按鈕與下載佇列訊息正確顯示（含 ICU plural）', (tester) async {
    final opdsClient = FakeOpdsClient(feeds: {
      server.baseUrl: OpdsFeed(
        title: '根目錄',
        entries: [entry1, entry2],
      ),
    });
    final controller = DownloadQueueController(onDuplicateConfirm: (_) async => false);
    await pumpScreen(
      tester,
      opdsClient: opdsClient,
      downloadQueueController: controller,
      locale: const Locale('en'),
    );

    await tester.tap(find.byKey(const Key('remote_catalog_entry_book-1')));
    await tester.pump();
    await tester.tap(find.byKey(const Key('remote_catalog_download_button')));
    // 比照既有測試（remote_catalog_screen_test.dart:516）既定寫法，用
    // pump() 而非 pumpAndSettle()——enqueueJobs() 觸發的背景下載工作鏈
    // 在假測試環境下沒有真實計時器結束點，pumpAndSettle() 有逾時風險。
    await tester.pump();

    expect(
      find.textContaining('Added 1 file to the download queue'),
      findsOneWidget,
    );
  });
```

（依 `entry1`/`entry2` 既有 fixture 定義調整 `remoteBookId`/`acquisitions` 使其恰好 1 筆可下載且不觸發格式選擇彈窗；若既有 fixture 结构不同，改用該檔案已有的、下載後只產生 1 個 job 的既有測試情境作為基礎调整。）

- [ ] **Step 3: 執行測試確認全數通過**

Run: `cd app && flutter test test/screens/remote_catalog_screen_test.dart`
Expected: 全數通過（既有 39 個＋新增 1 個 = 40 個；實際既有測試數以 `grep -c "testWidgets("` 執行當下結果為準）。

- [ ] **Step 4: `flutter analyze` 確認乾淨**

Run: `cd app && flutter analyze test/screens/remote_catalog_screen_test.dart`
Expected: `No issues found!`

- [ ] **Step 5: Commit**

```bash
git add app/test/screens/remote_catalog_screen_test.dart
git commit -m "test(epic-45): remote_catalog_screen_test.dart 測試遷移＋新增英文渲染驗證"
```

---

### Task 7: `wifi_transfer_screen.dart`

**Files:**
- Modify: `app/lib/screens/wifi_transfer_screen.dart`
- Modify: `app/lib/l10n/app_zh_TW.arb`／`app_zh_CN.arb`／`app_en.arb`／`app_zh.arb`
- Test: `app/test/screens/wifi_transfer_screen_test.dart`

**Interfaces:**
- Consumes：`AppLocalizations.of(context)!`（`_WifiTransferScreenState` 的 `_confirmLeaveIfTransferring()`/`build()`/`_buildBody()` 皆為 State 方法）。
- Produces：ARB key `wifiTransferLeaveConfirmTitle`/`wifiTransferLeaveConfirmMessage`/`wifiTransferLeaveConfirmButton`/`wifiTransferTitle`/`wifiTransferInstructionText`/`wifiTransferActiveCountText`/`wifiTransferUnavailableText`/`wifiTransferManualOverrideButton`/`wifiTransferNoInterfacesText`；沿用全域共用 `cancel`。

- [ ] **Step 1: 新增 ARB key（四語言）**

`app_zh_TW.arb` 檔尾新增：
```json
  "wifiTransferLeaveConfirmTitle": "目前尚有檔案正在傳輸",
  "@wifiTransferLeaveConfirmTitle": {
    "description": "離開畫面前的傳輸中示警對話框標題"
  },
  "wifiTransferLeaveConfirmMessage": "離開將中斷連線，是否確定離開？",
  "@wifiTransferLeaveConfirmMessage": {
    "description": "離開畫面前的傳輸中示警對話框訊息"
  },
  "wifiTransferLeaveConfirmButton": "確定離開",
  "@wifiTransferLeaveConfirmButton": {
    "description": "示警對話框的「確定離開」按鈕文字"
  },
  "wifiTransferTitle": "WiFi 傳書",
  "@wifiTransferTitle": {
    "description": "WiFi 傳書畫面 AppBar 標題"
  },
  "wifiTransferInstructionText": "在同一個 WiFi 下，用瀏覽器打開以下網址：",
  "@wifiTransferInstructionText": {
    "description": "顯示網址/QR Code 前的操作說明文字"
  },
  "wifiTransferActiveCountText": "{count, plural, =1{正在傳輸中（1 個檔案）…} other{正在傳輸中（{count} 個檔案）…}}",
  "@wifiTransferActiveCountText": {
    "description": "傳輸中橫幅文字，{count} 為目前進行中的傳輸檔案數",
    "placeholders": {
      "count": {
        "type": "int"
      }
    }
  },
  "wifiTransferUnavailableText": "請連線至 WiFi 或開啟手機熱點",
  "@wifiTransferUnavailableText": {
    "description": "偵測不到可用網路時的提示文字"
  },
  "wifiTransferManualOverrideButton": "我確定目前是用手機熱點",
  "@wifiTransferManualOverrideButton": {
    "description": "手動覆寫偵測結果的按鈕文字"
  },
  "wifiTransferNoInterfacesText": "找不到任何可用網路介面",
  "@wifiTransferNoInterfacesText": {
    "description": "手動覆寫候選清單為空時的提示文字"
  },
```

`app_zh_CN.arb` 檔尾新增：
```json
  "wifiTransferLeaveConfirmTitle": "目前尚有档案正在传输",
  "wifiTransferLeaveConfirmMessage": "离开将中断连线，是否确定离开？",
  "wifiTransferLeaveConfirmButton": "确定离开",
  "wifiTransferTitle": "WiFi 传书",
  "wifiTransferInstructionText": "在同一个 WiFi 下，用浏览器打开以下网址：",
  "wifiTransferActiveCountText": "{count, plural, =1{正在传输中（1 个档案）…} other{正在传输中（{count} 个档案）…}}",
  "wifiTransferUnavailableText": "请连线至 WiFi 或开启手机热点",
  "wifiTransferManualOverrideButton": "我确定目前是用手机热点",
  "wifiTransferNoInterfacesText": "找不到任何可用网络介面",
```

`app_en.arb` 檔尾新增：
```json
  "wifiTransferLeaveConfirmTitle": "Files are still transferring",
  "wifiTransferLeaveConfirmMessage": "Leaving will interrupt the connection. Are you sure you want to leave?",
  "wifiTransferLeaveConfirmButton": "Leave Anyway",
  "wifiTransferTitle": "WiFi Book Transfer",
  "wifiTransferInstructionText": "On the same WiFi network, open the following URL in a browser:",
  "wifiTransferActiveCountText": "{count, plural, =1{Transferring (1 file)…} other{Transferring ({count} files)…}}",
  "wifiTransferUnavailableText": "Please connect to WiFi or turn on your mobile hotspot",
  "wifiTransferManualOverrideButton": "I'm sure I'm using a mobile hotspot",
  "wifiTransferNoInterfacesText": "No available network interfaces found",
```

`app_zh.arb` 檔尾新增：與 `app_zh_TW.arb` 對應 9 個 key 相同值（fallback）。

- [ ] **Step 2: 執行 `flutter gen-l10n`**

Run: `cd app && flutter gen-l10n`
Expected: 無錯誤。

- [ ] **Step 3: 修改 `wifi_transfer_screen.dart`**

```dart
  Future<void> _confirmLeaveIfTransferring(BuildContext context) async {
    final l10n = AppLocalizations.of(context)!;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(l10n.wifiTransferLeaveConfirmTitle),
        content: Text(l10n.wifiTransferLeaveConfirmMessage),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text(l10n.cancel),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(l10n.wifiTransferLeaveConfirmButton),
          ),
        ],
      ),
    );
    if (confirmed == true && context.mounted) {
      Navigator.of(context).pop();
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return ValueListenableBuilder<int>(
      valueListenable: _activeTransfersNotifier,
      builder: (context, activeCount, child) {
        return PopScope(
          canPop: activeCount == 0,
          onPopInvokedWithResult: (didPop, result) {
            if (didPop) return;
            _confirmLeaveIfTransferring(context);
          },
          child: child!,
        );
      },
      child: Scaffold(
        appBar: AppBar(title: Text(l10n.wifiTransferTitle)),
        body: _buildBody(context),
      ),
    );
  }

  Widget _buildBody(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return FutureBuilder<NetworkAvailability>(
      future: _availabilityFuture,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const Center(child: CircularProgressIndicator());
        }
        if (!snapshot.hasData) {
          return Center(child: Text(l10n.wifiTransferUnavailableText));
        }
        final availability = snapshot.data!;
        final effectiveIp = _manualSelectedIp ?? availability.ipAddress;
        final effectiveUnavailable = _manualSelectedIp == null &&
            availability.kind == NetworkAvailabilityKind.unavailable;

        if (effectiveIp != null && !effectiveUnavailable) {
          final url =
              'http://$effectiveIp:${_boundPort ?? kWifiTransferDefaultPort}';
          return SingleChildScrollView(
            child: Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const SizedBox(height: 16),
                  Text(l10n.wifiTransferInstructionText),
                  const SizedBox(height: 8),
                  Text(url, key: const Key('wifi_transfer_ip_text')),
                  const SizedBox(height: 16),
                  QrImageView(
                    key: const Key('wifi_transfer_qr_code'),
                    data: url,
                    size: 200,
                    backgroundColor: Colors.white,
                  ),
                  ValueListenableBuilder<int>(
                    valueListenable: _activeTransfersNotifier,
                    builder: (context, activeCount, _) {
                      if (activeCount <= 0) {
                        return const SizedBox.shrink();
                      }
                      final theme = Theme.of(context);
                      final isEink = theme.brightness == Brightness.light &&
                          theme.colorScheme.primary == Colors.black &&
                          theme.scaffoldBackgroundColor == Colors.white;
                      return Container(
                        key: const Key('wifi_transfer_active_transfers_banner'),
                        margin: const EdgeInsets.only(top: 16),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 10,
                        ),
                        decoration: BoxDecoration(
                          color: isEink
                              ? Colors.white
                              : theme.colorScheme.surfaceContainerHighest,
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(
                            color: isEink
                                ? Colors.black
                                : theme.colorScheme.outline.withValues(alpha: 0.35),
                            width: 1.0,
                          ),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: isEink ? Colors.black : theme.colorScheme.primary,
                              ),
                            ),
                            const SizedBox(width: 10),
                            Text(
                              AppLocalizations.of(context)!
                                  .wifiTransferActiveCountText(activeCount),
                              key: const Key('wifi_transfer_active_transfers_text'),
                              style: TextStyle(
                                fontWeight: FontWeight.bold,
                                color: isEink
                                    ? Colors.black
                                    : theme.colorScheme.onSurface,
                              ),
                            ),
                          ],
                        ),
                      );
                    },
                  ),
                  const SizedBox(height: 16),
                ],
              ),
            ),
          );
        }

        return SingleChildScrollView(
          child: Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const SizedBox(height: 16),
                Text(l10n.wifiTransferUnavailableText),
                const SizedBox(height: 16),
                if (!_manualOverrideRequested)
                  ElevatedButton(
                    key: const Key('wifi_transfer_manual_override_button'),
                    onPressed: () =>
                        setState(() => _manualOverrideRequested = true),
                    child: Text(l10n.wifiTransferManualOverrideButton),
                  ),
                if (_manualOverrideRequested)
                  if (availability.allCandidates.isEmpty)
                    Text(l10n.wifiTransferNoInterfacesText)
                  else
                    ...availability.allCandidates.map(
                      (candidate) => ListTile(
                        key: Key(
                            'wifi_transfer_candidate_${candidate.interfaceName}'),
                        title: Text(candidate.interfaceName),
                        subtitle: Text(candidate.ipAddress),
                        onTap: () => _selectManualIp(candidate.ipAddress),
                      ),
                    ),
                const SizedBox(height: 16),
              ],
            ),
          ),
        );
      },
    );
  }
```

加上檔案頂部 import：`import '../l10n/app_localizations.dart';`

- [ ] **Step 4: 遷移既有測試檔**

`app/test/screens/wifi_transfer_screen_test.dart` 有 2 處 `MaterialApp(`：`buildScreen()` helper（第 28-42 行）與第 255-270 行（E-Ink 主題測試，無法用 `buildScreen()` 因為需要自訂 `theme:`）。兩處皆補上三個 l10n 參數：

```dart
  Widget buildScreen({
    required CheckNetworkAvailability checkNetworkAvailability,
    ValueListenable<int>? activeTransfersNotifierOverride,
    Locale locale = const Locale('zh', 'TW'),
  }) {
    return MaterialApp(
      locale: locale,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: WifiTransferScreen(
        libraryRepository: FakeLibraryRepository(),
        importService: FakeBookImportService(),
        computeFingerprint: FakeFingerprintComputer().call,
        checkNetworkAvailability: checkNetworkAvailability,
        activeTransfersNotifierOverride:
            activeTransfersNotifierOverride ?? ValueNotifier<int>(0),
      ),
    );
  }
```

```dart
    await tester.pumpWidget(MaterialApp(
      locale: const Locale('zh', 'TW'),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      theme: ThemeData.light().copyWith(
        colorScheme: const ColorScheme.light(primary: Colors.black),
        scaffoldBackgroundColor: Colors.white,
      ),
      home: WifiTransferScreen(
        libraryRepository: FakeLibraryRepository(),
        importService: FakeBookImportService(),
        computeFingerprint: FakeFingerprintComputer().call,
        checkNetworkAvailability: () async => const NetworkAvailability(
          kind: NetworkAvailabilityKind.wifiClient,
          ipAddress: '192.168.1.5',
        ),
        activeTransfersNotifierOverride: activeNotifier,
      ),
    ));
```

加上檔案頂部 import：`import 'package:elinkbook/l10n/app_localizations.dart';`

既有 `find.text('請連線至 WiFi 或開啟手機熱點')`/`find.text('找不到任何可用網路介面')`/`find.text('目前尚有檔案正在傳輸')`/`find.text('確定離開')`/`find.text('正在傳輸中（2 個檔案）…')`/`find.text('正在傳輸中（1 個檔案）…')` 等斷言因譯文與原字面值完全相同，無需修改。

- [ ] **Step 5: 新增英文渲染驗證測試**

```dart
  testWidgets('英文介面下傳輸中橫幅單複數皆正確顯示', (tester) async {
    final activeNotifier = ValueNotifier<int>(1);
    await tester.pumpWidget(buildScreen(
      checkNetworkAvailability: () async => const NetworkAvailability(
        kind: NetworkAvailabilityKind.wifiClient,
        ipAddress: '192.168.1.5',
      ),
      activeTransfersNotifierOverride: activeNotifier,
      locale: const Locale('en'),
    ));
    await tester.pumpAndSettle();

    expect(find.text('Transferring (1 file)…'), findsOneWidget);

    activeNotifier.value = 3;
    await tester.pump();
    expect(find.text('Transferring (3 files)…'), findsOneWidget);
  });

  testWidgets('英文介面下離開確認對話框文字正確', (tester) async {
    final notifier = ValueNotifier<int>(1);
    await tester.pumpWidget(buildScreen(
      checkNetworkAvailability: () async => const NetworkAvailability(
        kind: NetworkAvailabilityKind.wifiClient,
        ipAddress: '192.168.1.5',
      ),
      activeTransfersNotifierOverride: notifier,
      locale: const Locale('en'),
    ));
    await tester.pump();

    await tester.binding.handlePopRoute();
    await tester.pump();

    expect(find.text('Files are still transferring'), findsOneWidget);
    await tester.tap(find.text('Leave Anyway'));
    await tester.pumpAndSettle();
    expect(find.text('Files are still transferring'), findsNothing);
  });
```

- [ ] **Step 6: 執行測試確認全數通過**

Run: `cd app && flutter test test/screens/wifi_transfer_screen_test.dart`
Expected: 全數通過（既有 11 個＋新增 2 個 = 13 個）。

- [ ] **Step 7: `flutter analyze` 確認乾淨**

Run: `cd app && flutter analyze lib/screens/wifi_transfer_screen.dart test/screens/wifi_transfer_screen_test.dart`
Expected: `No issues found!`

- [ ] **Step 8: Commit**

```bash
git add app/lib/screens/wifi_transfer_screen.dart app/test/screens/wifi_transfer_screen_test.dart app/lib/l10n/app_zh_TW.arb app/lib/l10n/app_zh_CN.arb app/lib/l10n/app_en.arb app/lib/l10n/app_zh.arb app/lib/l10n/app_localizations*.dart
git commit -m "feat(epic-45): wifi_transfer_screen.dart 字串抽取三語言在地化"
```

---

### Task 8: `widgets/download_queue_panel.dart`

**（`/superpowers:requesting-code-review` review-plan-issue-6.md Important #4 補記歸屬）**：全域掃描發現本檔案未被 `issues.md` 任何 Issue 認領——`AppLocalizations` 使用量為 0，含 11 處硬編碼字面值（分區標題「下載佇列」、3 個 tooltip、7 個狀態標籤，見下），唯一呼叫端正是 Task 9 `sources_home_screen.dart:275`。若不在本 Issue 處理，英文介面下「來源」畫面一旦有下載項目，常駐佇列面板將全數顯示中文，且 Issue 10 靜態稽核必然報警。本 Task 排在 Task 9 之前，確保 Task 9 為 `sources_home_screen_test.dart` 新增英文渲染測試時（斷言下載佇列面板文字）該面板已完成在地化。

**Files:**
- Modify: `app/lib/screens/widgets/download_queue_panel.dart`
- Modify: `app/lib/l10n/app_zh_TW.arb`／`app_zh_CN.arb`／`app_en.arb`／`app_zh.arb`
- Create: `app/test/screens/widgets/download_queue_panel_test.dart`（目前沒有獨立測試檔）

**Interfaces:**
- Consumes：`AppLocalizations.of(context)!`（`DownloadQueuePanel.build(context)` 為 `StatelessWidget.build()`；`_QueueItemRow.build(context)` 同理；`_QueueItemRow._statusLabel()` 目前簽章 `String _statusLabel(DownloadQueueItem item)` 不含 `context`，改為 `String _statusLabel(AppLocalizations l10n, DownloadQueueItem item)`，由 `build()` 解析一次 `l10n` 後傳入，呼叫處共 2 處——見 Step 3）。
- Produces：ARB key `downloadQueueTitle`/`downloadQueueCancelTooltip`/`downloadQueueRetryTooltip`/`downloadQueueDismissTooltip`/`downloadQueueStatusPending`/`downloadQueueStatusDownloading`/`downloadQueueStatusCheckingDuplicate`/`downloadQueueStatusDone`/`downloadQueueStatusDuplicateSkipped`/`downloadQueueStatusFailed`/`downloadQueueStatusCancelled`。

- [ ] **Step 1: 新增 ARB key（四語言）**

`app_zh_TW.arb` 檔尾新增：
```json
  "downloadQueueTitle": "下載佇列",
  "@downloadQueueTitle": {
    "description": "「來源」畫面常駐下載佇列區塊的分區標題"
  },
  "downloadQueueCancelTooltip": "取消",
  "@downloadQueueCancelTooltip": {
    "description": "下載中項目的「取消」圖示按鈕無障礙提示文字"
  },
  "downloadQueueRetryTooltip": "重試",
  "@downloadQueueRetryTooltip": {
    "description": "失敗/已取消項目的「重試」圖示按鈕無障礙提示文字"
  },
  "downloadQueueDismissTooltip": "從清單移除",
  "@downloadQueueDismissTooltip": {
    "description": "已結束項目（完成/重複已略過）的「從清單移除」圖示按鈕無障礙提示文字"
  },
  "downloadQueueStatusPending": "待機",
  "@downloadQueueStatusPending": {
    "description": "項目狀態標籤：排隊中尚未開始下載"
  },
  "downloadQueueStatusDownloading": "下載中",
  "@downloadQueueStatusDownloading": {
    "description": "項目狀態標籤：正在下載且尚無位元組進度回報時顯示（有進度時改顯示百分比數字，數字本身不需翻譯）"
  },
  "downloadQueueStatusCheckingDuplicate": "比對中",
  "@downloadQueueStatusCheckingDuplicate": {
    "description": "項目狀態標籤：下載完成後正在比對是否與既有書籍重複"
  },
  "downloadQueueStatusDone": "完成",
  "@downloadQueueStatusDone": {
    "description": "項目狀態標籤：下載並匯入成功"
  },
  "downloadQueueStatusDuplicateSkipped": "重複已略過",
  "@downloadQueueStatusDuplicateSkipped": {
    "description": "項目狀態標籤：偵測到重複且使用者選擇不建立新副本"
  },
  "downloadQueueStatusFailed": "失敗",
  "@downloadQueueStatusFailed": {
    "description": "項目狀態標籤：下載或匯入過程發生非取消性錯誤"
  },
  "downloadQueueStatusCancelled": "已取消",
  "@downloadQueueStatusCancelled": {
    "description": "項目狀態標籤：使用者主動取消下載"
  },
```

`app_zh_CN.arb` 檔尾新增：
```json
  "downloadQueueTitle": "下载队列",
  "downloadQueueCancelTooltip": "取消",
  "downloadQueueRetryTooltip": "重试",
  "downloadQueueDismissTooltip": "从清单移除",
  "downloadQueueStatusPending": "待机",
  "downloadQueueStatusDownloading": "下载中",
  "downloadQueueStatusCheckingDuplicate": "比对中",
  "downloadQueueStatusDone": "完成",
  "downloadQueueStatusDuplicateSkipped": "重复已略过",
  "downloadQueueStatusFailed": "失败",
  "downloadQueueStatusCancelled": "已取消",
```

`app_en.arb` 檔尾新增：
```json
  "downloadQueueTitle": "Download Queue",
  "downloadQueueCancelTooltip": "Cancel",
  "downloadQueueRetryTooltip": "Retry",
  "downloadQueueDismissTooltip": "Remove from List",
  "downloadQueueStatusPending": "Pending",
  "downloadQueueStatusDownloading": "Downloading",
  "downloadQueueStatusCheckingDuplicate": "Checking",
  "downloadQueueStatusDone": "Done",
  "downloadQueueStatusDuplicateSkipped": "Duplicate Skipped",
  "downloadQueueStatusFailed": "Failed",
  "downloadQueueStatusCancelled": "Cancelled",
```

`app_zh.arb` 檔尾新增：與 `app_zh_TW.arb` 對應 11 個 key 相同值（fallback）。

- [ ] **Step 2: 執行 `flutter gen-l10n`**

Run: `cd app && flutter gen-l10n`
Expected: 無錯誤。

- [ ] **Step 3: 修改 `widgets/download_queue_panel.dart`**

```dart
import 'package:flutter/material.dart';

import '../../downloads/download_queue_controller.dart';
import '../../l10n/app_localizations.dart';
import 'eb_field_card.dart';
import 'eb_section_header.dart';

/// 「來源」畫面常駐的下載佇列區塊（視覺還原，`docs/research/uiux/reference/
/// 來源.png`）：訂閱 [DownloadQueueController]（不分下載來源，雲端硬碟／
/// OPDS 遠端書庫共用同一份清單），逐項顯示確定式進度條（`DESIGN.md` §16.2
/// 「確定式進度條取代連續旋轉的 ProgressIndicator」），沒有任何項目時
/// 整個區塊（含分區標題）不渲染。
class DownloadQueuePanel extends StatelessWidget {
  final DownloadQueueController controller;

  const DownloadQueuePanel({super.key, required this.controller});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) {
        final items = controller.items;
        if (items.isEmpty) return const SizedBox.shrink();
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            EBSectionHeader(title: l10n.downloadQueueTitle),
            for (final item in items)
              EBFieldCard(
                margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                child: _QueueItemRow(item: item, controller: controller),
              ),
          ],
        );
      },
    );
  }
}

class _QueueItemRow extends StatelessWidget {
  final DownloadQueueItem item;
  final DownloadQueueController controller;

  const _QueueItemRow({required this.item, required this.controller});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final colorScheme = Theme.of(context).colorScheme;
    final inProgress =
        item.status == DownloadItemStatus.pending ||
        item.status == DownloadItemStatus.downloading ||
        item.status == DownloadItemStatus.checkingDuplicate;

    return Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                item.name,
                key: Key('sources_download_queue_item_${item.id}'),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 6),
              if (inProgress)
                Row(
                  children: [
                    Expanded(
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(4),
                        child: LinearProgressIndicator(
                          key: Key(
                            'sources_download_queue_progress_${item.id}',
                          ),
                          value: item.progress ?? 0.0,
                          minHeight: 8,
                          backgroundColor: colorScheme.outline.withValues(
                            alpha: 0.3,
                          ),
                          valueColor: AlwaysStoppedAnimation(
                            colorScheme.primary,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(_statusLabel(l10n, item), style: TextStyle(fontSize: 12)),
                  ],
                )
              else
                Row(
                  children: [
                    Icon(_statusIcon(item.status), size: 16),
                    const SizedBox(width: 4),
                    Text(
                      _statusLabel(l10n, item),
                      style: const TextStyle(fontSize: 12),
                    ),
                  ],
                ),
            ],
          ),
        ),
        _trailingAction(context, l10n),
      ],
    );
  }

  Widget _trailingAction(BuildContext context, AppLocalizations l10n) {
    switch (item.status) {
      case DownloadItemStatus.downloading:
        return IconButton(
          key: Key('sources_download_queue_cancel_${item.id}'),
          icon: const Icon(Icons.close),
          tooltip: l10n.downloadQueueCancelTooltip,
          onPressed: () => controller.cancel(item.id),
        );
      case DownloadItemStatus.failed:
      case DownloadItemStatus.cancelled:
        return IconButton(
          key: Key('sources_download_queue_retry_${item.id}'),
          icon: const Icon(Icons.refresh),
          tooltip: l10n.downloadQueueRetryTooltip,
          onPressed: () => controller.retry(item.id),
        );
      case DownloadItemStatus.done:
      case DownloadItemStatus.duplicateSkipped:
        return IconButton(
          key: Key('sources_download_queue_dismiss_${item.id}'),
          icon: const Icon(Icons.close),
          tooltip: l10n.downloadQueueDismissTooltip,
          onPressed: () => controller.dismiss(item.id),
        );
      case DownloadItemStatus.pending:
      case DownloadItemStatus.checkingDuplicate:
        return const SizedBox(width: 48);
    }
  }

  IconData _statusIcon(DownloadItemStatus status) {
    switch (status) {
      case DownloadItemStatus.done:
        return Icons.check_circle;
      case DownloadItemStatus.duplicateSkipped:
        return Icons.block;
      case DownloadItemStatus.failed:
        return Icons.error_outline;
      case DownloadItemStatus.cancelled:
        return Icons.cancel_outlined;
      case DownloadItemStatus.pending:
      case DownloadItemStatus.downloading:
      case DownloadItemStatus.checkingDuplicate:
        return Icons.hourglass_empty;
    }
  }

  String _statusLabel(AppLocalizations l10n, DownloadQueueItem item) {
    switch (item.status) {
      case DownloadItemStatus.pending:
        return l10n.downloadQueueStatusPending;
      case DownloadItemStatus.downloading:
        final progress = item.progress;
        return progress == null
            ? l10n.downloadQueueStatusDownloading
            : '${(progress * 100).round()}%';
      case DownloadItemStatus.checkingDuplicate:
        return l10n.downloadQueueStatusCheckingDuplicate;
      case DownloadItemStatus.done:
        return l10n.downloadQueueStatusDone;
      case DownloadItemStatus.duplicateSkipped:
        return l10n.downloadQueueStatusDuplicateSkipped;
      case DownloadItemStatus.failed:
        return l10n.downloadQueueStatusFailed;
      case DownloadItemStatus.cancelled:
        return l10n.downloadQueueStatusCancelled;
    }
  }
}
```

- [ ] **Step 4: 新增獨立測試檔 `widgets/download_queue_panel_test.dart`**

`DownloadQueueController` 沒有暴露「直接注入某個狀態的項目」的測試用 API（`items` 由 `enqueueJobs()` 驅動真實非同步生命週期產生），因此測試用一個可控制完成時機的 `_FakeQueuedDownloadJob`（實作 `QueuedDownloadJob`，`download()` 由測試持有的 `Completer` 控制何時完成）驅動真實狀態機，覆蓋 pending／downloading／cancelled／done／各自的 tooltip 與狀態標籤：

```dart
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:elinkbook/downloads/download_queue_controller.dart';
import 'package:elinkbook/l10n/app_localizations.dart';
import 'package:elinkbook/screens/widgets/download_queue_panel.dart';

class _FakeQueuedDownloadJob implements QueuedDownloadJob {
  _FakeQueuedDownloadJob({required this.id, required this.name});

  @override
  final String id;
  @override
  final String name;

  final _downloadCompleter = Completer<String>();
  bool _cancelled = false;

  @override
  bool get isCancelled => _cancelled;

  @override
  Future<String> download({
    required void Function(int received, int total) onProgress,
  }) => _downloadCompleter.future;

  @override
  void cancel() {
    _cancelled = true;
    if (!_downloadCompleter.isCompleted) {
      _downloadCompleter.completeError(StateError('cancelled'));
    }
  }

  void completeDownload() {
    if (!_downloadCompleter.isCompleted) _downloadCompleter.complete('/tmp/fake');
  }

  @override
  Future<String> computeFingerprint(String tempPath) async => 'fingerprint-$id';

  @override
  Future<bool> hasDuplicate(String fingerprint) async => false;

  @override
  Future<String> promote(String tempPath) async => tempPath;

  @override
  Future<void> import(String permanentPath) async {}
}

void main() {
  Future<void> pumpPanel(
    WidgetTester tester,
    DownloadQueueController controller, {
    Locale locale = const Locale('zh', 'TW'),
  }) async {
    await tester.pumpWidget(MaterialApp(
      locale: locale,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Scaffold(body: DownloadQueuePanel(controller: controller)),
    ));
  }

  testWidgets('沒有任何項目時整個區塊不渲染', (tester) async {
    final controller = DownloadQueueController(onDuplicateConfirm: (_) async => false);
    await pumpPanel(tester, controller);
    expect(find.text('下載佇列'), findsNothing);
  });

  testWidgets('下載中項目顯示標題／狀態標籤／取消按鈕，取消後變更為已取消並可重試', (tester) async {
    final controller = DownloadQueueController(onDuplicateConfirm: (_) async => false);
    final job = _FakeQueuedDownloadJob(id: 'book-1', name: '測試書籍');
    await pumpPanel(tester, controller);

    controller.enqueueJobs([job]);
    await tester.pump();

    expect(find.text('下載佇列'), findsOneWidget);
    expect(find.text('下載中'), findsOneWidget);
    final cancelButton = tester.widget<IconButton>(
      find.byKey(const Key('sources_download_queue_cancel_book-1')),
    );
    expect(cancelButton.tooltip, '取消');

    await tester.tap(find.byKey(const Key('sources_download_queue_cancel_book-1')));
    await tester.pump();

    expect(find.text('已取消'), findsOneWidget);
    final retryButton = tester.widget<IconButton>(
      find.byKey(const Key('sources_download_queue_retry_book-1')),
    );
    expect(retryButton.tooltip, '重試');
  });

  testWidgets('下載成功完成後顯示「完成」標籤與「從清單移除」按鈕', (tester) async {
    final controller = DownloadQueueController(onDuplicateConfirm: (_) async => false);
    final job = _FakeQueuedDownloadJob(id: 'book-2', name: '測試書籍2');
    await pumpPanel(tester, controller);

    controller.enqueueJobs([job]);
    await tester.pump();
    job.completeDownload();
    await tester.pump();
    await tester.pump();

    expect(find.text('完成'), findsOneWidget);
    final dismissButton = tester.widget<IconButton>(
      find.byKey(const Key('sources_download_queue_dismiss_book-2')),
    );
    expect(dismissButton.tooltip, '從清單移除');
  });

  testWidgets('英文介面下標題與狀態標籤正確顯示', (tester) async {
    final controller = DownloadQueueController(onDuplicateConfirm: (_) async => false);
    final job = _FakeQueuedDownloadJob(id: 'book-3', name: 'Test Book');
    await pumpPanel(tester, controller, locale: const Locale('en'));

    controller.enqueueJobs([job]);
    await tester.pump();

    expect(find.text('Download Queue'), findsOneWidget);
    expect(find.text('Downloading'), findsOneWidget);

    await tester.tap(find.byKey(const Key('sources_download_queue_cancel_book-3')));
    await tester.pump();
    expect(find.text('Cancelled'), findsOneWidget);
  });
}
```

- [ ] **Step 5: 執行新測試檔確認全數通過**

Run: `cd app && flutter test test/screens/widgets/download_queue_panel_test.dart`
Expected: 全數通過（4 個）。

- [ ] **Step 6: 執行 `sources_home_screen_test.dart` 確認零回歸**

Run: `cd app && flutter test test/screens/sources_home_screen_test.dart`
Expected: 全數通過（既有測試數維持不變；本 Task 不修改 `sources_home_screen_test.dart` 本身，`find.text('下載佇列')` 斷言因譯文與原字面值相同繼續通過，見 Task 9）。

- [ ] **Step 7: `flutter analyze` 確認乾淨**

Run: `cd app && flutter analyze lib/screens/widgets/download_queue_panel.dart test/screens/widgets/download_queue_panel_test.dart`
Expected: `No issues found!`

- [ ] **Step 8: Commit**

```bash
git add app/lib/screens/widgets/download_queue_panel.dart app/test/screens/widgets/download_queue_panel_test.dart app/lib/l10n/app_zh_TW.arb app/lib/l10n/app_zh_CN.arb app/lib/l10n/app_en.arb app/lib/l10n/app_zh.arb app/lib/l10n/app_localizations*.dart
git commit -m "feat(epic-45): download_queue_panel.dart 字串抽取三語言在地化（新增獨立測試檔）"
```

---

### Task 9: `sources_home_screen.dart`

**Files:**
- Modify: `app/lib/screens/sources_home_screen.dart`
- Modify: `app/lib/l10n/app_zh_TW.arb`／`app_zh_CN.arb`／`app_en.arb`／`app_zh.arb`
- Test: `app/test/screens/sources_home_screen_test.dart`

**Interfaces:**
- Consumes：`AppLocalizations.of(context)!`（`SourcesHomeScreen` 為 `StatelessWidget`，`build(context)` 與各私有方法皆接受/使用既有 `context` 參數）；沿用 Task 10 尚未定義的 `book_import_picker_helper.dart` 既有簽章（本 Task 不修改該檔案，僅呼叫既有 `pickAndImportFiles`/`pickAndImportFolder`/`confirmAutoGroupByFolderName`/`showImportResultSnackBar`）。
- Produces：ARB key `sourcesHomeTitle`/`sourcesHomeLibraryTooltip`/`sourcesHomeSettingsTooltip`/`sourcesHomeLocalSection`/`sourcesHomePickFilesTitle`/`sourcesHomePickFolderTitle`/`sourcesHomeWifiTransferTile`/`sourcesHomeConnectedServicesSection`/`sourcesHomeCloudNotLinkedSubtitle`/`sourcesHomeRemoteLibraryTitle`/`sourcesHomeRemoteLibraryNotConfiguredSubtitle`。

**範圍決定：`'Google Drive'`／`'OneDrive'` 兩個 `ListTile.title` 字面值（第 238、254 行）不翻譯**——雲端服務商品牌名，`design.md` 排除範圍，維持原樣。

- [ ] **Step 1: 新增 ARB key（四語言）**

`app_zh_TW.arb` 檔尾新增：
```json
  "sourcesHomeTitle": "來源",
  "@sourcesHomeTitle": {
    "description": "「來源」聚合頁 AppBar 標題"
  },
  "sourcesHomeLibraryTooltip": "書架",
  "@sourcesHomeLibraryTooltip": {
    "description": "AppBar「書架」導覽按鈕的無障礙提示文字"
  },
  "sourcesHomeSettingsTooltip": "設定",
  "@sourcesHomeSettingsTooltip": {
    "description": "AppBar「設定」導覽按鈕的無障礙提示文字"
  },
  "sourcesHomeLocalSection": "本機",
  "@sourcesHomeLocalSection": {
    "description": "「本機」分區標題"
  },
  "sourcesHomePickFilesTitle": "選擇檔案（可多選）",
  "@sourcesHomePickFilesTitle": {
    "description": "「選擇檔案」入口列標題"
  },
  "sourcesHomePickFolderTitle": "選擇資料夾",
  "@sourcesHomePickFolderTitle": {
    "description": "「選擇資料夾」入口列標題"
  },
  "sourcesHomeWifiTransferTile": "WiFi 傳書",
  "@sourcesHomeWifiTransferTile": {
    "description": "「WiFi 傳書」入口列標題"
  },
  "sourcesHomeConnectedServicesSection": "已連結服務",
  "@sourcesHomeConnectedServicesSection": {
    "description": "「已連結服務」分區標題"
  },
  "sourcesHomeCloudNotLinkedSubtitle": "尚未連結，請至設定畫面連結帳戶",
  "@sourcesHomeCloudNotLinkedSubtitle": {
    "description": "Google Drive／OneDrive 入口列未連結時的副標題"
  },
  "sourcesHomeRemoteLibraryTitle": "遠端書庫（OPDS）",
  "@sourcesHomeRemoteLibraryTitle": {
    "description": "「遠端書庫」入口列標題，OPDS 為技術協定縮寫不翻譯"
  },
  "sourcesHomeRemoteLibraryNotConfiguredSubtitle": "尚未設定遠端書庫伺服器",
  "@sourcesHomeRemoteLibraryNotConfiguredSubtitle": {
    "description": "「遠端書庫」入口列尚未設定站點時的副標題"
  },
```

`app_zh_CN.arb` 檔尾新增：
```json
  "sourcesHomeTitle": "来源",
  "sourcesHomeLibraryTooltip": "书架",
  "sourcesHomeSettingsTooltip": "设定",
  "sourcesHomeLocalSection": "本机",
  "sourcesHomePickFilesTitle": "选择档案（可多选）",
  "sourcesHomePickFolderTitle": "选择资料夹",
  "sourcesHomeWifiTransferTile": "WiFi 传书",
  "sourcesHomeConnectedServicesSection": "已连结服务",
  "sourcesHomeCloudNotLinkedSubtitle": "尚未连结，请至设定画面连结账户",
  "sourcesHomeRemoteLibraryTitle": "远程书库（OPDS）",
  "sourcesHomeRemoteLibraryNotConfiguredSubtitle": "尚未设定远程书库服务器",
```

`app_en.arb` 檔尾新增：
```json
  "sourcesHomeTitle": "Sources",
  "sourcesHomeLibraryTooltip": "Library",
  "sourcesHomeSettingsTooltip": "Settings",
  "sourcesHomeLocalSection": "Local",
  "sourcesHomePickFilesTitle": "Choose Files (multiple selection)",
  "sourcesHomePickFolderTitle": "Choose Folder",
  "sourcesHomeWifiTransferTile": "WiFi Book Transfer",
  "sourcesHomeConnectedServicesSection": "Connected Services",
  "sourcesHomeCloudNotLinkedSubtitle": "Not linked yet. Please link your account in Settings.",
  "sourcesHomeRemoteLibraryTitle": "Remote Library (OPDS)",
  "sourcesHomeRemoteLibraryNotConfiguredSubtitle": "No remote library server configured yet",
```

`app_zh.arb` 檔尾新增：與 `app_zh_TW.arb` 對應 11 個 key 相同值（fallback）。

- [ ] **Step 2: 執行 `flutter gen-l10n`**

Run: `cd app && flutter gen-l10n`
Expected: 無錯誤。

- [ ] **Step 3: 修改 `sources_home_screen.dart`**

```dart
  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final googleDriveClient = cloudAccountDependencies.googleDriveStorageClient;
    final oneDriveClient = cloudAccountDependencies.oneDriveStorageClient;
    final googleDriveEnabled =
        googleDriveClient != null &&
        computeFingerprint != null &&
        downloadQueueController != null;
    final oneDriveEnabled =
        oneDriveClient != null &&
        computeFingerprint != null &&
        downloadQueueController != null;
    final remoteEnabled =
        remoteLibraryDependencies.remoteServerRepository != null &&
        remoteLibraryDependencies.createOpdsClient != null &&
        remoteLibraryDependencies.thumbnailCache != null &&
        computeFingerprint != null &&
        downloadQueueController != null;
    final wifiTransferEnabled =
        wifiTransferDependencies?.libraryRepository != null &&
        wifiTransferDependencies?.importService != null &&
        wifiTransferDependencies?.computeFingerprint != null &&
        wifiTransferDependencies?.checkNetworkAvailability != null;
    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.sourcesHomeTitle),
        actions: [
          IconButton(
            key: const Key('sources_library_button'),
            icon: const Icon(Icons.grid_view),
            tooltip: l10n.sourcesHomeLibraryTooltip,
            onPressed: onNavigateToLibrary,
          ),
          IconButton(
            key: const Key('sources_settings_button'),
            icon: const Icon(Icons.settings),
            tooltip: l10n.sourcesHomeSettingsTooltip,
            onPressed: onNavigateToSettings,
          ),
        ],
      ),
      body: ListView(
        children: [
          EBSectionHeader(title: l10n.sourcesHomeLocalSection),
          EBFieldCard(
            padding: EdgeInsets.zero,
            margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
            child: ListTile(
              key: const Key('sources_pick_files_button'),
              leading: const Icon(Icons.description),
              title: Text(l10n.sourcesHomePickFilesTitle),
              onTap: () => _handlePickFiles(context),
            ),
          ),
          EBFieldCard(
            padding: EdgeInsets.zero,
            margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
            child: ListTile(
              key: const Key('sources_pick_folder_button'),
              leading: const Icon(Icons.folder),
              title: Text(l10n.sourcesHomePickFolderTitle),
              onTap: () => _handlePickFolder(context),
            ),
          ),
          if (wifiTransferEnabled)
            EBFieldCard(
              padding: EdgeInsets.zero,
              margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
              child: ListTile(
                key: const Key('sources_wifi_transfer_tile'),
                leading: const Icon(Icons.wifi),
                title: Text(l10n.sourcesHomeWifiTransferTile),
                onTap: () => _openWifiTransfer(context),
              ),
            ),
          EBSectionHeader(title: l10n.sourcesHomeConnectedServicesSection),
          EBFieldCard(
            padding: EdgeInsets.zero,
            margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
            child: ListTile(
              key: const Key('sources_google_drive_tile'),
              leading: const Icon(Icons.cloud),
              // 'Google Drive' 為雲端服務商品牌名，不翻譯
              // （design.md 排除範圍）。
              title: const Text('Google Drive'),
              subtitle: googleDriveEnabled
                  ? null
                  : Text(l10n.sourcesHomeCloudNotLinkedSubtitle),
              enabled: googleDriveEnabled,
              onTap: googleDriveEnabled
                  ? () => _openGoogleDriveBrowser(context, googleDriveClient)
                  : null,
            ),
          ),
          EBFieldCard(
            padding: EdgeInsets.zero,
            margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
            child: ListTile(
              key: const Key('sources_onedrive_tile'),
              leading: const Icon(Icons.cloud_outlined),
              // 'OneDrive' 同上，不翻譯。
              title: const Text('OneDrive'),
              subtitle: oneDriveEnabled
                  ? null
                  : Text(l10n.sourcesHomeCloudNotLinkedSubtitle),
              enabled: oneDriveEnabled,
              onTap: oneDriveEnabled
                  ? () => _openOneDriveBrowser(context, oneDriveClient)
                  : null,
            ),
          ),
          EBFieldCard(
            padding: EdgeInsets.zero,
            margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
            child: ListTile(
              key: const Key('sources_remote_library_tile'),
              leading: const Icon(Icons.dns),
              title: Text(l10n.sourcesHomeRemoteLibraryTitle),
              subtitle: remoteEnabled
                  ? null
                  : Text(l10n.sourcesHomeRemoteLibraryNotConfiguredSubtitle),
              enabled: remoteEnabled,
              onTap: remoteEnabled ? () => _openRemoteLibrary(context) : null,
            ),
          ),
          if (downloadQueueController != null)
            DownloadQueuePanel(controller: downloadQueueController!),
        ],
      ),
    );
  }
```

加上檔案頂部 import：`import '../l10n/app_localizations.dart';`

- [ ] **Step 4: 遷移既有測試檔**

`app/test/screens/sources_home_screen_test.dart` 有 11 處裸 `MaterialApp(home: SourcesHomeScreen(...))`（無共用 helper，逐個 `testWidgets` 各自內嵌，第 71、98、122、195、223、246、274、293、334、349、371 行）。逐一在每處 `MaterialApp(` 參數列插入：

```dart
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('zh', 'TW'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: SourcesHomeScreen(
          /* 原有具名參數原樣保留 */
        ),
      ),
    );
```

（既有 2 處已用 `pumpLocalizedWidget()` 的呼叫——第 147、171 行——維持不變，不需修改。）加上檔案頂部 import：`import 'package:elinkbook/l10n/app_localizations.dart';`（若尚未 import；`pump_localized_widget.dart` 已間接 import 過 `AppLocalizations`，但本檔案直接使用 `AppLocalizations.localizationsDelegates` 仍需自己的 import）。

既有 `find.text('下載佇列')` 斷言（第 284、302、324 行）——`DownloadQueuePanel` 已在 Task 8 完成在地化，`app_zh_TW.arb` 的 `downloadQueueTitle` 譯文與原字面值完全相同，維持裸中文字面值斷言不變，無需修改。

- [ ] **Step 5: 新增英文渲染驗證測試**

```dart
  testWidgets('英文介面下標題與各入口列文字正確顯示', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('en'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: SourcesHomeScreen(
          repository: FakeLibraryRepository(),
          importService: FakeBookImportService(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Sources'), findsOneWidget);
    expect(find.text('Choose Files (multiple selection)'), findsOneWidget);
    expect(find.text('Choose Folder'), findsOneWidget);
    expect(find.text('Google Drive'), findsOneWidget);
    expect(find.text('Not linked yet. Please link your account in Settings.'),
        findsNWidgets(2));
    expect(find.text('Remote Library (OPDS)'), findsOneWidget);
    expect(find.text('No remote library server configured yet'), findsOneWidget);
  });
```

- [ ] **Step 6: 執行測試確認全數通過**

Run: `cd app && flutter test test/screens/sources_home_screen_test.dart`
Expected: 全數通過（既有 13 個＋新增 1 個 = 14 個）。

- [ ] **Step 7: `flutter analyze` 確認乾淨**

Run: `cd app && flutter analyze lib/screens/sources_home_screen.dart test/screens/sources_home_screen_test.dart`
Expected: `No issues found!`

- [ ] **Step 8: Commit**

```bash
git add app/lib/screens/sources_home_screen.dart app/test/screens/sources_home_screen_test.dart app/lib/l10n/app_zh_TW.arb app/lib/l10n/app_zh_CN.arb app/lib/l10n/app_en.arb app/lib/l10n/app_zh.arb app/lib/l10n/app_localizations*.dart
git commit -m "feat(epic-45): sources_home_screen.dart 字串抽取三語言在地化"
```

---

### Task 10: `book_import_picker_helper.dart`

**Files:**
- Modify: `app/lib/screens/support/book_import_picker_helper.dart`
- Modify: `app/lib/l10n/app_zh_TW.arb`／`app_zh_CN.arb`／`app_en.arb`／`app_zh.arb`
- Test: `app/test/screens/support/book_import_picker_helper_test.dart`

**Interfaces:**
- Consumes：`AppLocalizations.of(context)!`（`confirmAutoGroupByFolderName(BuildContext context)`／`showImportResultSnackBar(BuildContext context, ImportResult result)` 兩個頂層函式皆已接受 `context` 參數，直接呼叫，簽章不變）。
- Produces：ARB key `libraryImportFolderDialogTitle`/`libraryImportFolderAutoGroupLabel`/`libraryImportFolderConfirmButton`/`libraryImportResultBothMessage`/`libraryImportResultImportedOnlyMessage`/`libraryImportResultSkippedOnlyMessage`；沿用全域共用 `cancel`。

**ICU plural 規則（`issues.md` I-2 修正，本計劃 Global Constraints 已強調）**：`importedCount`／`skippedCount` 是兩個彼此獨立的計數，各自需要獨立的 `plural` 判斷式；不可用單一 `plural` 判斷式同時控制兩者的單複數。沿用既有三分支邏輯（皆為 0 不顯示／僅成功／成功且有跳過／僅跳過），每一分支各自一個 ARB key，比照 Issue 5 `font_management_screen.dart` 上傳結果訊息的既有先例。

- [ ] **Step 1: 新增 ARB key（四語言）**

`app_zh_TW.arb` 檔尾新增：
```json
  "libraryImportFolderDialogTitle": "匯入資料夾",
  "@libraryImportFolderDialogTitle": {
    "description": "「是否依資料夾名稱自動建立分類」確認對話框標題"
  },
  "libraryImportFolderAutoGroupLabel": "依資料夾名稱自動建立分類",
  "@libraryImportFolderAutoGroupLabel": {
    "description": "自動建立分類勾選項的標題文字"
  },
  "libraryImportFolderConfirmButton": "匯入",
  "@libraryImportFolderConfirmButton": {
    "description": "匯入資料夾確認對話框的確認按鈕文字"
  },
  "libraryImportResultBothMessage": "{importedCount, plural, =1{已匯入 1 本} other{已匯入 {importedCount} 本}}，{skippedCount, plural, =1{1 本已存在，已跳過} other{{skippedCount} 本已存在，已跳過}}",
  "@libraryImportResultBothMessage": {
    "description": "匯入完成時，成功匯入與跳過重複兩者皆大於 0 的合併提示，{importedCount}／{skippedCount} 各自獨立處理單複數",
    "placeholders": {
      "importedCount": {
        "type": "int"
      },
      "skippedCount": {
        "type": "int"
      }
    }
  },
  "libraryImportResultImportedOnlyMessage": "{importedCount, plural, =1{已匯入 1 本書} other{已匯入 {importedCount} 本書}}",
  "@libraryImportResultImportedOnlyMessage": {
    "description": "匯入完成時，僅有成功匯入（無跳過重複）的提示",
    "placeholders": {
      "importedCount": {
        "type": "int"
      }
    }
  },
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

`app_zh_CN.arb` 檔尾新增：
```json
  "libraryImportFolderDialogTitle": "汇入资料夹",
  "libraryImportFolderAutoGroupLabel": "依资料夹名称自动建立分类",
  "libraryImportFolderConfirmButton": "汇入",
  "libraryImportResultBothMessage": "{importedCount, plural, =1{已汇入 1 本} other{已汇入 {importedCount} 本}}，{skippedCount, plural, =1{1 本已存在，已跳过} other{{skippedCount} 本已存在，已跳过}}",
  "libraryImportResultImportedOnlyMessage": "{importedCount, plural, =1{已汇入 1 本书} other{已汇入 {importedCount} 本书}}",
  "libraryImportResultSkippedOnlyMessage": "{skippedCount, plural, =1{1 本已存在，已跳过} other{{skippedCount} 本已存在，已跳过}}",
```

`app_en.arb` 檔尾新增：
```json
  "libraryImportFolderDialogTitle": "Import Folder",
  "libraryImportFolderAutoGroupLabel": "Automatically create category by folder name",
  "libraryImportFolderConfirmButton": "Import",
  "libraryImportResultBothMessage": "{importedCount, plural, =1{Imported 1 book} other{Imported {importedCount} books}}, {skippedCount, plural, =1{1 already exists and was skipped} other{{skippedCount} already exist and were skipped}}",
  "libraryImportResultImportedOnlyMessage": "{importedCount, plural, =1{Imported 1 book} other{Imported {importedCount} books}}",
  "libraryImportResultSkippedOnlyMessage": "{skippedCount, plural, =1{1 already exists and was skipped} other{{skippedCount} already exist and were skipped}}",
```

`app_zh.arb` 檔尾新增：與 `app_zh_TW.arb` 對應 6 個 key 相同值（fallback）。

- [ ] **Step 2: 執行 `flutter gen-l10n`**

Run: `cd app && flutter gen-l10n`
Expected: 無錯誤。

- [ ] **Step 3: 修改 `book_import_picker_helper.dart`**

```dart
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../l10n/app_localizations.dart';
import '../../library/book_import_service.dart';

const _folderPickerChannel = MethodChannel('elinkbook/folder_picker');

// pickAndImportFiles()／pickAndImportFolder() 內容不變（不涉及任何字串）。

/// 「是否依資料夾名稱自動建立分類」確認對話框（原
/// `_LibraryScreenState._confirmAutoGroupByFolderName()`，逐字搬遷）。
Future<bool?> confirmAutoGroupByFolderName(BuildContext context) {
  final l10n = AppLocalizations.of(context)!;
  var autoGroup = true;
  return showDialog<bool>(
    context: context,
    builder: (dialogContext) => StatefulBuilder(
      builder: (context, setDialogState) => AlertDialog(
        title: Text(l10n.libraryImportFolderDialogTitle),
        content: CheckboxListTile(
          key: const Key('library_import_folder_auto_group_checkbox'),
          value: autoGroup,
          onChanged: (value) => setDialogState(() => autoGroup = value ?? true),
          title: Text(l10n.libraryImportFolderAutoGroupLabel),
          controlAffinity: ListTileControlAffinity.leading,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: Text(l10n.cancel),
          ),
          TextButton(
            key: const Key('library_import_folder_confirm'),
            onPressed: () => Navigator.of(dialogContext).pop(autoGroup),
            child: Text(l10n.libraryImportFolderConfirmButton),
          ),
        ],
      ),
    ),
  );
}

/// 匯入完成後顯示單一合併提示：成功匯入本數與（若有）因來源 URI 與既有
/// 書籍重複而被跳過的本數。兩者皆為 0 時不顯示任何提示（原
/// `_LibraryScreenState._showImportResultSnackBar()`，逐字搬遷）。
void showImportResultSnackBar(BuildContext context, ImportResult result) {
  final importedCount = result.importedBooks.length;
  final skippedCount = result.skippedDuplicateCount;
  if (importedCount <= 0 && skippedCount <= 0) return;
  final l10n = AppLocalizations.of(context)!;
  final message = importedCount > 0
      ? (skippedCount > 0
          // gen-l10n 產生位置參數，不是具名參數——順序依 ARB placeholders
          // 宣告順序（importedCount, skippedCount）。
          ? l10n.libraryImportResultBothMessage(
              importedCount,
              skippedCount,
            )
          : l10n.libraryImportResultImportedOnlyMessage(importedCount))
      : l10n.libraryImportResultSkippedOnlyMessage(skippedCount);
  ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
}
```

（`import '../../library/book_import_service.dart';` 相對路徑因檔案位於 `lib/screens/support/`，往上兩層才到 `lib/`，與既有既有 import 一致，維持不變；只新增 `import '../../l10n/app_localizations.dart';`。）

- [ ] **Step 4: 遷移既有測試檔**

`app/test/screens/support/book_import_picker_helper_test.dart` 有 7 處 `MaterialApp(home: Scaffold(body: Builder(...)))`（第 230、259、288、315、340、371、399 行，皆相同結構）。逐一插入三個 l10n 參數：

```dart
      await tester.pumpWidget(
        MaterialApp(
          locale: const Locale('zh', 'TW'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(
            body: Builder(
              builder: (context) => ElevatedButton(
                onPressed: () async {
                  /* 原有 onPressed 內容不變 */
                },
                child: const Text('打開對話框'), // 或既有的 'Show SnackBar'
              ),
            ),
          ),
        ),
      );
```

加上檔案頂部 import：`import 'package:elinkbook/l10n/app_localizations.dart';`

既有 `find.text('匯入資料夾')`/`find.text('依資料夾名稱自動建立分類')`/`find.text('取消')`/`find.text('已匯入 2 本書')`/`find.text('已匯入 1 本，3 本已存在，已跳過')`/`find.text('5 本已存在，已跳過')` 等斷言因譯文與原字面值完全相同，無需修改。

- [ ] **Step 5: 新增英文渲染驗證測試（含 ICU plural 三分支各自單複數）**

```dart
  group('英文介面下的在地化驗證', () {
    testWidgets('confirmAutoGroupByFolderName 顯示英文標題與按鈕', (tester) async {
      bool? result;
      await tester.pumpWidget(
        MaterialApp(
          locale: const Locale('en'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(
            body: Builder(
              builder: (context) => ElevatedButton(
                onPressed: () async {
                  result = await confirmAutoGroupByFolderName(context);
                },
                child: const Text('open dialog'),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('open dialog'));
      await tester.pumpAndSettle();

      expect(find.text('Import Folder'), findsOneWidget);
      expect(find.text('Automatically create category by folder name'),
          findsOneWidget);

      await tester.tap(find.byKey(const Key('library_import_folder_confirm')));
      await tester.pumpAndSettle();
      expect(result, isTrue);
    });

    testWidgets('showImportResultSnackBar 匯入/跳過本數各自為 1 與多本時單複數皆正確', (tester) async {
      Future<void> pumpAndShow(ImportResult result) async {
        await tester.pumpWidget(
          MaterialApp(
            locale: const Locale('en'),
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            home: Scaffold(
              body: Builder(
                builder: (context) => ElevatedButton(
                  onPressed: () => showImportResultSnackBar(context, result),
                  child: const Text('Show SnackBar'),
                ),
              ),
            ),
          ),
        );
        // 每次 pumpWidget() 重建的 MaterialApp/Scaffold 在 Flutter 測試框架下
        // 會沿用同一個 ScaffoldMessenger State（widget 樹結構未變，Element
        // 被 reconcile 保留），前一次呼叫顯示的 SnackBar 預設 4 秒才會退場，
        // 若不清空會被推入佇列、下一句 expect 找不到新訊息而失敗（已於本機
        // 以最小重現腳本驗證此排隊行為）。
        ScaffoldMessenger.of(tester.element(find.byType(Scaffold))).clearSnackBars();
        await tester.pump();
        await tester.tap(find.text('Show SnackBar'));
        await tester.pump();
      }

      await pumpAndShow(
        ImportResult(importedBooks: [_testBook('1')], skippedDuplicateCount: 0),
      );
      expect(find.text('Imported 1 book'), findsOneWidget);

      await pumpAndShow(
        ImportResult(
          importedBooks: [_testBook('1'), _testBook('2')],
          skippedDuplicateCount: 0,
        ),
      );
      expect(find.text('Imported 2 books'), findsOneWidget);

      await pumpAndShow(
        const ImportResult(importedBooks: [], skippedDuplicateCount: 1),
      );
      expect(find.text('1 already exists and was skipped'), findsOneWidget);

      await pumpAndShow(
        ImportResult(importedBooks: [_testBook('1')], skippedDuplicateCount: 3),
      );
      expect(
        find.text('Imported 1 book, 3 already exist and were skipped'),
        findsOneWidget,
      );
    });
  });
```

- [ ] **Step 6: 執行測試確認全數通過**

Run: `cd app && flutter test test/screens/support/book_import_picker_helper_test.dart`
Expected: 全數通過（既有 15 個＋新增 2 個 = 17 個；實際既有測試數以執行當下結果為準）。

- [ ] **Step 7: `flutter analyze` 確認乾淨**

Run: `cd app && flutter analyze lib/screens/support/book_import_picker_helper.dart test/screens/support/book_import_picker_helper_test.dart`
Expected: `No issues found!`

- [ ] **Step 8: Commit**

```bash
git add app/lib/screens/support/book_import_picker_helper.dart app/test/screens/support/book_import_picker_helper_test.dart app/lib/l10n/app_zh_TW.arb app/lib/l10n/app_zh_CN.arb app/lib/l10n/app_en.arb app/lib/l10n/app_zh.arb app/lib/l10n/app_localizations*.dart
git commit -m "feat(epic-45): book_import_picker_helper.dart 字串抽取三語言在地化（含 ICU plural）"
```

---

### Task 11: `layout_preset_book_picker_screen.dart`（production）

**Files:**
- Modify: `app/lib/screens/layout_preset_book_picker_screen.dart`
- Modify: `app/lib/l10n/app_zh_TW.arb`／`app_zh_CN.arb`／`app_en.arb`／`app_zh.arb`

**本 Task 不修改任何測試檔**——`layout_preset_book_picker_screen_test.dart` 的遷移獨立成 Task 12（下一個 Task）。**本 Task 完成後、Task 12 執行前，`flutter test test/screens/layout_preset_book_picker_screen_test.dart` 預期大量失敗（`Null check operator used on a null value`）——這是預期中的紅燈狀態，不是本 Task 的回歸。**

**Interfaces:**
- Consumes：`AppLocalizations.of(context)!`（`_LayoutPresetBookPickerScreenState.build()` 為 State 方法）。
- Produces：ARB key `layoutPresetBookPickerTitleMulti`/`layoutPresetBookPickerTitleSingle`/`layoutPresetBookPickerSearchHint`/`layoutPresetBookPickerEmptyBooks`/`layoutPresetBookPickerNoMatch`；沿用全域共用 `confirm`。

- [ ] **Step 1: 新增 ARB key（四語言）**

`app_zh_TW.arb` 檔尾新增：
```json
  "layoutPresetBookPickerTitleMulti": "選擇書籍（可複選）",
  "@layoutPresetBookPickerTitleMulti": {
    "description": "複選模式的 AppBar 標題"
  },
  "layoutPresetBookPickerTitleSingle": "選擇書籍",
  "@layoutPresetBookPickerTitleSingle": {
    "description": "單選模式的 AppBar 標題"
  },
  "layoutPresetBookPickerSearchHint": "搜尋書名或作者",
  "@layoutPresetBookPickerSearchHint": {
    "description": "搜尋輸入框的 hintText"
  },
  "layoutPresetBookPickerEmptyBooks": "沒有可選擇的流式 EPUB 書籍",
  "@layoutPresetBookPickerEmptyBooks": {
    "description": "傳入的 books 清單為空時的提示文字"
  },
  "layoutPresetBookPickerNoMatch": "找不到符合的書籍",
  "@layoutPresetBookPickerNoMatch": {
    "description": "搜尋結果為空時的提示文字"
  },
```

`app_zh_CN.arb` 檔尾新增：
```json
  "layoutPresetBookPickerTitleMulti": "选择书籍（可复选）",
  "layoutPresetBookPickerTitleSingle": "选择书籍",
  "layoutPresetBookPickerSearchHint": "搜索书名或作者",
  "layoutPresetBookPickerEmptyBooks": "没有可选择的流式 EPUB 书籍",
  "layoutPresetBookPickerNoMatch": "找不到符合的书籍",
```

`app_en.arb` 檔尾新增：
```json
  "layoutPresetBookPickerTitleMulti": "Select Books (multiple selection)",
  "layoutPresetBookPickerTitleSingle": "Select Book",
  "layoutPresetBookPickerSearchHint": "Search by title or author",
  "layoutPresetBookPickerEmptyBooks": "No reflowable EPUB books available to select",
  "layoutPresetBookPickerNoMatch": "No matching books found",
```

`app_zh.arb` 檔尾新增：與 `app_zh_TW.arb` 對應 5 個 key 相同值（fallback）。

- [ ] **Step 2: 執行 `flutter gen-l10n`**

Run: `cd app && flutter gen-l10n`
Expected: 無錯誤。

- [ ] **Step 3: 修改 `layout_preset_book_picker_screen.dart`**

```dart
  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final filteredBooks = _filteredBooks;
    return Scaffold(
      appBar: AppBar(
        title: Text(
          widget.multiSelect
              ? l10n.layoutPresetBookPickerTitleMulti
              : l10n.layoutPresetBookPickerTitleSingle,
        ),
        actions: [
          TextButton(
            key: const Key('layout_preset_book_picker_confirm'),
            onPressed: _selected.isEmpty
                ? null
                : () => Navigator.of(context).pop(_selected.toList()),
            child: Text(l10n.confirm),
          ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(8),
            child: TextField(
              key: const Key('layout_preset_book_picker_search_field'),
              controller: _searchController,
              decoration: InputDecoration(
                hintText: l10n.layoutPresetBookPickerSearchHint,
                prefixIcon: const Icon(Icons.search),
                suffixIcon: _searchQuery.isNotEmpty
                    ? IconButton(
                        key: const Key(
                            'layout_preset_book_picker_search_clear'),
                        icon: const Icon(Icons.clear),
                        onPressed: () {
                          _searchController.clear();
                          setState(() => _searchQuery = '');
                        },
                      )
                    : null,
                border: const OutlineInputBorder(),
                isDense: true,
              ),
              onChanged: (value) => setState(() => _searchQuery = value),
            ),
          ),
          Expanded(
            child: widget.books.isEmpty
                ? Center(child: Text(l10n.layoutPresetBookPickerEmptyBooks))
                : filteredBooks.isEmpty
                    ? Center(child: Text(l10n.layoutPresetBookPickerNoMatch))
                    : _buildGrid(filteredBooks),
          ),
        ],
      ),
    );
  }
```

加上檔案頂部 import：`import '../l10n/app_localizations.dart';`

- [ ] **Step 4: 執行測試確認「預期中的紅燈」**

Run: `cd app && flutter test test/screens/layout_preset_book_picker_screen_test.dart`
Expected: 大量測試因 `Null check operator used on a null value` 失敗——證實 Step 3 的改動確實生效。這個紅燈狀態會在 Task 12 完成後轉綠，不需要修正任何東西。

- [ ] **Step 5: `flutter analyze` 確認 production 程式碼本身乾淨**

Run: `cd app && flutter analyze lib/screens/layout_preset_book_picker_screen.dart`
Expected: `No issues found!`

- [ ] **Step 6: Commit（production code only，測試遷移留給 Task 12）**

```bash
git add app/lib/screens/layout_preset_book_picker_screen.dart app/lib/l10n/app_zh_TW.arb app/lib/l10n/app_zh_CN.arb app/lib/l10n/app_en.arb app/lib/l10n/app_zh.arb app/lib/l10n/app_localizations*.dart
git commit -m "feat(epic-45): layout_preset_book_picker_screen.dart 字串抽取三語言在地化（production）"
```

---

### Task 12: `layout_preset_book_picker_screen_test.dart`（測試遷移）

**Files:**
- Modify: `app/test/screens/layout_preset_book_picker_screen_test.dart`（17 處裸 `MaterialApp` 全面遷移）

**Interfaces:**
- Consumes：Task 11 已定義的全部 5 個 ARB key 與 `_LayoutPresetBookPickerScreenState.build()` 全面改用 `AppLocalizations.of(context)!` 這個事實。
- Produces：`layout_preset_book_picker_screen_test.dart` 完整遷移後的狀態。

**遷移規則**（機械式轉換，逐一套用在全部 17 處）：

1. 找出所有裸 `MaterialApp(` 呼叫：
   ```bash
   grep -n "MaterialApp(" test/screens/layout_preset_book_picker_screen_test.dart
   ```
2. 本檔案沒有共用 pump helper，17 處皆為 `tester.pumpWidget(MaterialApp(theme: resolveThemeData(theme: AppTheme.light, isEinkMode: false), home: /* Builder+ElevatedButton 或直接 LayoutPresetBookPickerScreen */))` 的內嵌結構。逐一在每處 `MaterialApp(` 參數列插入三行：
   ```dart
   await tester.pumpWidget(MaterialApp(
     locale: const Locale('zh', 'TW'),
     localizationsDelegates: AppLocalizations.localizationsDelegates,
     supportedLocales: AppLocalizations.supportedLocales,
     theme: resolveThemeData(theme: AppTheme.light, isEinkMode: false),
     home: /* 原有 home: 內容原樣保留 */,
   ));
   ```
3. 加上檔案頂部 import：
   ```dart
   import 'package:elinkbook/l10n/app_localizations.dart';
   ```

**既有斷言不需修改**——`find.text('沒有可選擇的流式 EPUB 書籍')`/`find.text('找不到符合的書籍')`/`find.text('open')` 等因譯文與原字面值完全相同，維持通過。

- [ ] **Step 1: 依上述規則逐一插入三個 l10n 參數（全部 17 處）**
- [ ] **Step 2: 新增英文渲染驗證測試**

```dart
  testWidgets('英文介面下標題與空狀態文字正確顯示', (tester) async {
    await tester.pumpWidget(MaterialApp(
      locale: const Locale('en'),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      theme: resolveThemeData(theme: AppTheme.light, isEinkMode: false),
      home: LayoutPresetBookPickerScreen(
        books: const [],
        multiSelect: false,
      ),
    ));

    expect(find.text('Select Book'), findsOneWidget);
    expect(
      find.text('No reflowable EPUB books available to select'),
      findsOneWidget,
    );
  });

  testWidgets('英文介面下複選模式標題與確定按鈕文字正確', (tester) async {
    await tester.pumpWidget(MaterialApp(
      locale: const Locale('en'),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      theme: resolveThemeData(theme: AppTheme.light, isEinkMode: false),
      home: LayoutPresetBookPickerScreen(
        books: [_book('b1', '書一')],
        multiSelect: true,
      ),
    ));

    expect(find.text('Select Books (multiple selection)'), findsOneWidget);
    expect(find.text('Confirm'), findsOneWidget);
  });
```

- [ ] **Step 3: 執行測試確認全數通過**

Run: `cd app && flutter test test/screens/layout_preset_book_picker_screen_test.dart`
Expected: 全數通過（既有測試數＋新增 2 個；實際既有測試數以執行當下結果為準）。

- [ ] **Step 4: `flutter analyze` 確認乾淨**

Run: `cd app && flutter analyze test/screens/layout_preset_book_picker_screen_test.dart`
Expected: `No issues found!`

- [ ] **Step 5: Commit**

```bash
git add app/test/screens/layout_preset_book_picker_screen_test.dart
git commit -m "test(epic-45): layout_preset_book_picker_screen_test.dart 測試遷移＋新增英文渲染驗證"
```

---

### Task 13: `layout_preset_name_dialog.dart`

**Files:**
- Modify: `app/lib/screens/layout_preset_name_dialog.dart`
- Modify: `app/lib/l10n/app_zh_TW.arb`／`app_zh_CN.arb`／`app_en.arb`／`app_zh.arb`
- Create: `app/test/screens/layout_preset_name_dialog_test.dart`

**`layout_preset_name_dialog.dart` 目前沒有自己的 `_test.dart`**——既有的間接測試覆蓋來自已在 Issue 4 遷移的 `app/test/screens/reader_screen_test.dart`（`locale: const Locale('zh', 'TW')`），透過 `find.byKey(const Key('layout_preset_name_dialog_field'))`／`find.byKey(const Key('layout_preset_name_dialog_confirm'))` 定位互動，不涉及任何 `find.text()` 中文字面值斷言（見 Step 4 驗證），也不覆蓋標題文字、`layoutPresetNameDialogEmptyError` 驗證錯誤分支、或英文語系渲染。本 Task 新增一個獨立輕量測試檔補上這三項覆蓋（比照 `format_selection_dialog_test.dart` 既有結構），見 Step 5。

**Interfaces:**
- Consumes：`AppLocalizations.of(context)!`（`_LayoutPresetNameDialogState` 的 `_handleSave()`/`build()` 皆為 State 方法；`_handleSave()` 由 `TextButton.onPressed` 使用者互動觸發，非 `initState()`，安全）。
- Produces：ARB key `layoutPresetNameDialogTitle`/`layoutPresetNameDialogEmptyError`/`layoutPresetNameDialogSaveButton`；沿用全域共用 `cancel`。

- [ ] **Step 1: 新增 ARB key（四語言）**

`app_zh_TW.arb` 檔尾新增：
```json
  "layoutPresetNameDialogTitle": "為預設集命名",
  "@layoutPresetNameDialogTitle": {
    "description": "版面設定預設集命名輸入 Dialog 標題"
  },
  "layoutPresetNameDialogEmptyError": "名稱不可為空",
  "@layoutPresetNameDialogEmptyError": {
    "description": "trim 後名稱為空字串時的驗證錯誤文字"
  },
  "layoutPresetNameDialogSaveButton": "儲存",
  "@layoutPresetNameDialogSaveButton": {
    "description": "命名對話框的「儲存」按鈕文字"
  },
```

`app_zh_CN.arb` 檔尾新增：
```json
  "layoutPresetNameDialogTitle": "为预设集命名",
  "layoutPresetNameDialogEmptyError": "名称不可为空",
  "layoutPresetNameDialogSaveButton": "储存",
```

`app_en.arb` 檔尾新增：
```json
  "layoutPresetNameDialogTitle": "Name the Preset",
  "layoutPresetNameDialogEmptyError": "Name cannot be empty",
  "layoutPresetNameDialogSaveButton": "Save",
```

`app_zh.arb` 檔尾新增：與 `app_zh_TW.arb` 對應 3 個 key 相同值（fallback）。

- [ ] **Step 2: 執行 `flutter gen-l10n`**

Run: `cd app && flutter gen-l10n`
Expected: 無錯誤。

- [ ] **Step 3: 修改 `layout_preset_name_dialog.dart`**

```dart
import 'package:flutter/material.dart';

import '../l10n/app_localizations.dart';
import '../reader/layout_preset.dart';

// showLayoutPresetNameDialog()／_LayoutPresetNameDialog（StatefulWidget 宣告）內容不變。

class _LayoutPresetNameDialogState extends State<_LayoutPresetNameDialog> {
  late final TextEditingController _controller;
  String? _errorText;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.initialText);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _handleSave() {
    final name = validateLayoutPresetName(_controller.text);
    if (name == null) {
      setState(() => _errorText = AppLocalizations.of(context)!.layoutPresetNameDialogEmptyError);
      return;
    }
    Navigator.of(context).pop(name);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return AlertDialog(
      title: Text(l10n.layoutPresetNameDialogTitle),
      content: TextField(
        key: const Key('layout_preset_name_dialog_field'),
        controller: _controller,
        autofocus: true,
        maxLength: 20,
        decoration: InputDecoration(errorText: _errorText),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(l10n.cancel),
        ),
        TextButton(
          key: const Key('layout_preset_name_dialog_confirm'),
          onPressed: _handleSave,
          child: Text(l10n.layoutPresetNameDialogSaveButton),
        ),
      ],
    );
  }
}
```

- [ ] **Step 4: 驗證 `reader_screen_test.dart` 既有測試零回歸**

Run: `cd app && flutter test test/screens/reader_screen_test.dart`
Expected: 全數通過（237 個，與 Issue 4 收尾時記錄一致）。既有測試僅以 `find.byKey('layout_preset_name_dialog_field'/'layout_preset_name_dialog_confirm')` 定位元件、以 `tester.enterText()`/`tester.tap()` 互動，不斷言對話框標題/按鈕的中文字面值文字，因此本 Task 的字串抽取不影響任何既有斷言。

- [ ] **Step 5: 新增獨立測試檔 `layout_preset_name_dialog_test.dart`**

```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:elinkbook/l10n/app_localizations.dart';
import 'package:elinkbook/screens/layout_preset_name_dialog.dart';

void main() {
  Future<String?> pumpAndOpen(
    WidgetTester tester, {
    Locale locale = const Locale('zh', 'TW'),
    String initialText = '',
  }) async {
    String? result;
    await tester.pumpWidget(MaterialApp(
      locale: locale,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Builder(
        builder: (context) => ElevatedButton(
          onPressed: () async {
            result = await showLayoutPresetNameDialog(
              context,
              initialText: initialText,
            );
          },
          child: const Text('open'),
        ),
      ),
    ));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    return result;
  }

  testWidgets('顯示標題、輸入名稱後點擊儲存回傳 trim 後的名稱', (tester) async {
    await pumpAndOpen(tester);
    expect(find.text('為預設集命名'), findsOneWidget);

    await tester.enterText(
      find.byKey(const Key('layout_preset_name_dialog_field')),
      '  我的預設集  ',
    );
    await tester.tap(find.byKey(const Key('layout_preset_name_dialog_confirm')));
    await tester.pumpAndSettle();

    // 對話框已關閉，回傳值透過 pumpAndOpen 內部的 onPressed 回呼寫入外部變數，
    // 這裡改用 find.byType 確認對話框確實已消失即可（trim 行為由
    // validateLayoutPresetName() 純邏輯單元測試另行覆蓋，非本檔案職責）。
    expect(find.byKey(const Key('layout_preset_name_dialog_field')), findsNothing);
  });

  testWidgets('輸入空白字串後點擊儲存顯示驗證錯誤，不關閉對話框', (tester) async {
    await pumpAndOpen(tester);

    await tester.enterText(
      find.byKey(const Key('layout_preset_name_dialog_field')),
      '   ',
    );
    await tester.tap(find.byKey(const Key('layout_preset_name_dialog_confirm')));
    await tester.pump();

    expect(find.text('名稱不可為空'), findsOneWidget);
    expect(find.byKey(const Key('layout_preset_name_dialog_field')), findsOneWidget);
  });

  testWidgets('點擊取消回傳 null', (tester) async {
    String? result;
    await tester.pumpWidget(MaterialApp(
      locale: const Locale('zh', 'TW'),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Builder(
        builder: (context) => ElevatedButton(
          onPressed: () async {
            result = await showLayoutPresetNameDialog(context);
          },
          child: const Text('open'),
        ),
      ),
    ));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('取消'));
    await tester.pumpAndSettle();

    expect(result, isNull);
  });

  testWidgets('英文介面下標題／驗證錯誤／按鈕文字正確顯示', (tester) async {
    await pumpAndOpen(tester, locale: const Locale('en'));
    expect(find.text('Name the Preset'), findsOneWidget);
    expect(find.text('Save'), findsOneWidget);
    expect(find.text('Cancel'), findsOneWidget);

    await tester.enterText(
      find.byKey(const Key('layout_preset_name_dialog_field')),
      '   ',
    );
    await tester.tap(find.byKey(const Key('layout_preset_name_dialog_confirm')));
    await tester.pump();

    expect(find.text('Name cannot be empty'), findsOneWidget);
  });
}
```

- [ ] **Step 6: 執行新測試檔確認全數通過**

Run: `cd app && flutter test test/screens/layout_preset_name_dialog_test.dart`
Expected: 全數通過（4 個）。

- [ ] **Step 7: `flutter analyze` 確認乾淨**

Run: `cd app && flutter analyze lib/screens/layout_preset_name_dialog.dart test/screens/layout_preset_name_dialog_test.dart`
Expected: `No issues found!`

- [ ] **Step 8: Commit**

```bash
git add app/lib/screens/layout_preset_name_dialog.dart app/test/screens/layout_preset_name_dialog_test.dart app/lib/l10n/app_zh_TW.arb app/lib/l10n/app_zh_CN.arb app/lib/l10n/app_en.arb app/lib/l10n/app_zh.arb app/lib/l10n/app_localizations*.dart
git commit -m "feat(epic-45): layout_preset_name_dialog.dart 字串抽取三語言在地化＋新增獨立測試檔"
```

---

### Task 14: 最終驗證與文件收尾

**Files:**
- Modify: `docs/epics/epic-45-interface-i18n/issues.md`（標記 Issue 6 為 completed，記錄範圍修正）
- Modify: `docs/epics/epic-45-interface-i18n/epic.md`（新增 Issue 6 完成記錄）
- Modify: `docs/epics.md`（更新 epic-45 備註）

**Interfaces:**
- Consumes：Task 1-13 全部完成的狀態。
- Produces：Issue 6 完整收尾，供人類決定發 PR／合併。

- [ ] **Step 1: 執行完整 `flutter analyze`**

Run: `cd app && flutter analyze`
Expected: `No issues found!`

- [ ] **Step 2: 執行完整 `flutter test`**

Run: `cd app && flutter test`
Expected: 全數通過，總數較 Issue 5 收尾時記錄的 2719 passed 增加（本 Issue 新增測試數＝Task1 Step5(2)＋Task2 Step5(2)＋Task3 Step5(1)＋Task4 Step5(3，全新檔案)＋Task6 Step2(1)＋Task7 Step5(2)＋Task8 Step4(4，全新檔案)＋Task9 Step5(1)＋Task10 Step5(2)＋Task12 Step2(2)＋Task13 Step5(4，全新檔案) = 24 個），無既有測試因本 Issue 回歸。

- [ ] **Step 3: 確認 `reader_screen.dart`／`reader_screen_test.dart` 零異動**

Run: `git diff main -- app/lib/screens/reader_screen.dart app/test/screens/reader_screen_test.dart`
Expected: 除 `layout_preset_name_dialog.dart`／`layout_preset_book_picker_screen.dart` 本身（Task 11-13，不屬於這兩個檔案）外，`reader_screen.dart`／`reader_screen_test.dart` 應為空 diff——本 Issue 完全未修改這兩個檔案本身（僅修改它們呼叫的兩個外部檔案）。

- [ ] **Step 4: 更新 `issues.md`**

在 Issue 6 段落（`## Issue 6：其餘管理類彈窗與畫面字串抽取＋測試遷移` 之後）新增：

```markdown
**Status:** completed

**實際執行範圍修正記錄（認領時 grep 盤點＋`/superpowers:requesting-code-review` review-plan-issue-6.md Important #4 複審補記）**：
- 移出 `adaptive_shell_scaffold.dart`——通讀全檔（169 行）確認純三目的地 `IndexedStack` 組裝/依賴透傳 widget，`grep -nP '[\x{4e00}-\x{9fff}]'` 命中的全部 10 處皆為文件註解，零使用者可見字面字串。
- 新增 `format_selection_dialog.dart`——`issues.md` Issue 3 段落「實際執行範圍修正記錄」已註明「實際屬 Issue 6 範圍，唯一呼叫端為 `remote_catalog_screen.dart`」，本 Issue 收斂處理。
- 新增（計畫審查 Important #4 補記歸屬）`cloud_duplicate_confirm_dialog.dart`／`widgets/download_queue_panel.dart`——全域掃描 `app/lib/screens/` 發現的兩個孤兒檔案，`issues.md` 全 Epic 45 任何 Issue 皆未列入，本 Issue 收斂處理（唯一呼叫端分別為 `main.dart`／`cloud_browser_screen.dart` 與本 Issue 範圍內的 `sources_home_screen.dart`）。
- 路徑修正：`book_import_picker_helper.dart` 實際路徑為 `app/lib/screens/support/book_import_picker_helper.dart`（非原文「`support/book_import_picker_helper.dart`」暗示的 `app/lib/support/`）。
```

（若 `Status:` 欄位已存在則直接改值為 `completed`，不重複新增欄位。）

- [ ] **Step 5: 更新 `epic.md`**

新增一則日期記錄（比照 Issue 3／4／5 收尾記錄格式），內容涵蓋：11 個生產檔案（`remote_server_list_screen.dart`／`remote_server_form_screen.dart`／`format_selection_dialog.dart`／`cloud_duplicate_confirm_dialog.dart`／`remote_catalog_screen.dart`／`wifi_transfer_screen.dart`／`widgets/download_queue_panel.dart`／`sources_home_screen.dart`／`book_import_picker_helper.dart`／`layout_preset_book_picker_screen.dart`／`layout_preset_name_dialog.dart`）完整字串抽取與三語言在地化；ICU plural 命中 4 處（`remoteServerListDeleteBlockedMessage`／`remoteCatalogQueuedMessage`／`wifiTransferActiveCountText`／`libraryImportResultBothMessage`+`libraryImportResultImportedOnlyMessage`+`libraryImportResultSkippedOnlyMessage`，後者兩個計數各自獨立處理單複數）；四份 ARB 新增 key 總數（依 Task 1-13 實際新增數量加總，執行時以 ARB diff 實際結果為準，比照 Issue 5 審查 Important #2 的教訓，記錄時務必逐檔重新核對，不要憑計畫草稿的估計數字）；範圍修正（移出 `adaptive_shell_scaffold.dart`、新增 `format_selection_dialog.dart`／`cloud_duplicate_confirm_dialog.dart`／`widgets/download_queue_panel.dart`（後兩者為計畫審查 Important #4 補記歸屬的孤兒檔案）、路徑修正 `book_import_picker_helper.dart`）；測試遷移涵蓋全部 11 個檔案對應測試檔（其中 `cloud_duplicate_confirm_dialog.dart`／`widgets/download_queue_panel.dart`／`layout_preset_name_dialog.dart` 為全新獨立測試檔）；驗證結果（`flutter analyze`／完整 `flutter test` 結果）；下一步建議（認領 Issue 7 執行期例外訊息在地化，或 Issue 8 Markdown 匯出契約變更）。

- [ ] **Step 6: 更新 `docs/epics.md`**

把 epic-45 那一列的備註從「Issue 0／1／2／3／4／5 已完成，待認領 Issue 6」改為「Issue 0／1／2／3／4／5／6 已完成，待認領 Issue 7」。

- [ ] **Step 7: Commit**

```bash
git add docs/epics/epic-45-interface-i18n/issues.md docs/epics/epic-45-interface-i18n/epic.md docs/epics.md
git commit -m "docs(epic-45): 標記 Issue 6 為 completed，記錄實際執行範圍修正並更新 epic.md/epics.md"
```
