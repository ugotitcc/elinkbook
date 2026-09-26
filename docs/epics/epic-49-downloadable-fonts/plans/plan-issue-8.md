# Issue 8：恢復原俠正楷、台灣圓體、源流明體三款可下載字型 實作計畫

> **給執行者：** 必須搭配 superpowers:subagent-driven-development（建議）或 superpowers:executing-plans 逐項執行。步驟使用核取方塊（`- [ ]`），完成一個就改成 `- [x]`。

**目標：** 把 epic-48 停用的 3 款字型恢復成可下載字型，字型管理、閱讀設定、閱讀器都能用。

**架構：** 字型清單的唯一來源是 `AppFont` enum。字型管理、閱讀設定、`buildFontFaceCss()`、`DownloadableFontStore` 都走訪 `AppFont.values`，所以只要解除 `[字型停用]` 註解、補上顯示名稱，其他地方自動生效。字型檔已在 R2（Issue 2），不動 Worker 與 `fonts-cdn/`。

```
AppFont enum（解除 [字型停用]）
  ├─ familyName          ── GuanKiapTsingKhai / TaiwanPearl / GenRyuMinTW
  ├─ displayName(l10n)   ── 新增 3 個 l10n key
  └─ fontDownloadSpecOf  ── 3 筆下載資訊（數值早已寫好，只解除註解）
        │
        v   以下都走訪 AppFont.values，不用改
  字型管理畫面 / 閱讀設定選單 / buildFontFaceCss() / DownloadableFontStore
        │
        v
  Issue 7 依大小判斷：3 款都小於 30MB → WebView 91 也列出
```

**技術：** Flutter、`flutter_test`、`flutter gen-l10n`。

**規格：** `docs/epics/epic-49-downloadable-fonts/issues.md` Issue 8；`spec.md` 使用者故事 34、「字型目錄」表格；`docs/adr/0035-downloadable-fonts-via-r2-worker.md`。

**分支：** 從最新的 `main` 建立 `epic-49/issue-8-restore-fonts`。

## 工單疑問的查核結果（工單要求寫明）

- **舊偏好對照表**：`app/lib/library/sqlite_library_repository.dart` 約 804 行的 `legacyToFamilyName` 把 `guanKiapTsingKhai`／`taiwanPearl`／`genRyuMinTW` 對應到 `GuanKiapTsingKhai`／`TaiwanPearl`／`GenRyuMinTW`，和恢復後的 `familyName` 完全一致，**不用改**。
- **`app/assets/fonts/`**：目錄已經不存在（epic-49 Issue 1 把原檔搬到 `fonts-cdn/fonts/`），**不用刪**。`pubspec.yaml` 只剩註解。
- **其他 switch**：規劃時暫時解除註解並執行 `flutter analyze`，結果 `No issues found!`。除了 `displayName()` 之外，沒有別的 exhaustive switch 要補。

## 計畫做的決定（工單要求寫明）

1. **英文顯示名稱取自字型檔 `name` table 的英文家族名**（nameID 1／16，語系 0x409），去掉技術後綴，比照思源黑體 `Source Han Sans TC VF` 顯示成 `Source Han Sans` 的前例：
   | 字型 | `name` table 英文家族名 | 英文顯示名稱 |
   |---|---|---|
   | 原俠正楷 | `GuanKiapTsingKhai` | `GuanKiapTsingKhai` |
   | 台灣圓體 | `TaiwanPearl` | `TaiwanPearl` |
   | 源流明體 | `GenRyuMin TW TTF` | `GenRyuMin TW` |

   簡體中文：原侠正楷、台湾圆体、源流明体。
2. **enum 順序沿用註解裡的順序**：思源黑體、思源宋體、原俠正楷、台灣圓體、源流明體。字型管理與閱讀設定依這個順序列出。
3. **會壞的既有測試，依新行為更新**（規劃時暫時解除註解並執行完整 `flutter test` 找到的 4 個；第 5 個失敗是 `epic-50-wifi-transfer-test-fix` 的既有問題）：
   | 測試 | 失敗原因 | 處理 |
   |---|---|---|
   | `test/reader/app_font_test.dart`「每個 AppFont 都有對應的家族名稱字串…」 | 寫死只有 2 款 | 改成 5 款 |
   | `test/reader/downloadable_font_store_test.dart`「舊 WebView（91）：supportedFonts 不含超過 30MB 的字型」 | `mixedSpecOf` 讓黑體以外都是 50,000 bytes，期望值寫死 `[sourceHanSerif]` | 期望值改成「黑體以外的全部字型」 |
   | 同檔「舊 WebView：檔案存在也不列為已下載」 | 同上 | 同上 |
   | `test/screens/reader_settings_sheet_test.dart`「偏好設定存著已停用的字型時…」 | 用 `GuanKiapTsingKhai` 代表「不認得的名稱」，恢復後變成認得 | 改用不存在的名稱 `NoSuchFont`，測試名稱去掉「已停用」 |
   | `test/screens/reader_screen_test.dart`「不認得的字型名稱（含 epic-48 停用字型）照原值傳遞」 | 同上 | 同上 |
   | `test/screens/font_management_screen_test.dart`「顯示標題與 2 款內建字型…已停用的 3 款不顯示（epic-48）」 | 恢復後無 store 模式渲染 5 款，`findsNothing` 斷言必敗（審查 I-1） | 標題改成「5 款內建字型」，三款期望值改 `findsOneWidget` |
   | `test/screens/reader_settings_sheet_test.dart`「英文介面下…已停用字型不列出（epic-48）」 | 恢復後字型確實列出（英文名顯示），標題「已停用字型不列出」語意過時（審查 M-1） | 標題去掉「已停用字型不列出」，補英文名稱斷言 |

   這兩個「不認得的名稱」測試守的是「名稱不在清單裡也不會壞」，換一個真的不存在的名稱，保留原本的意圖。
4. **不動 Worker、R2、`fonts-cdn/`**：檔案已上傳，`font_download_catalog_test.dart` 的一致性測試本來就走訪 `AppFont.values`，恢復後自動比對 5 款。

## 全域限制

- 不改資料庫 schema，不改寫書籍偏好。
- 不改 `ReaderScreen`、`ReaderSettingsSheet`、`FontManagementScreen`、`FoliateReaderView`、`buildFontFaceCss()`、`DownloadableFontStore`：它們都走訪 `AppFont.values`。
- 所有指令在 `app/` 目錄執行。
- 每個 Task 只跑異動到的測試檔；完整 `flutter test` 只在 Task 3 跑一次（專案慣例，全套約 5 分鐘）。
- 提交前 `flutter analyze` 必須輸出 `No issues found!`。
- 新增介面字串要同時加進 4 個 arb：`app_zh_TW.arb`（範本，含 `@` 說明）、`app_zh.arb`、`app_zh_CN.arb`、`app_en.arb`，再執行 `flutter gen-l10n`。產生的 `app_localizations*.dart` 有進版控，要一起提交。
- 提交前執行 `node tool/check_l10n_hardcoded_strings.js`。
- commit 訊息結尾加 `Co-Authored-By` 署名行（依當次工作階段的 system reminder）。

## 審查重點（Review Focus）

以下五種情況最可能在真機上出錯，每一條都已在負責的 Task 補上測試：

1. **舊 WebView 用真的字型目錄**：WebView 91 時，`supportedFonts` 必須剛好是新恢復的 3 款（都小於 30 MB），思源黑體、思源宋體仍隱藏。→ Task 1 store 測試（用正式的 `fontDownloadSpecOf`，不是測試用的假大小）。
2. **epic-48 以前就選了原俠正楷的書**：偏好值是 `GuanKiapTsingKhai`。沒下載時閱讀器收到 `null`（改用書本字型），下載後照原值傳遞；偏好都不改寫。→ Task 2 閱讀器測試。
3. **字型管理一次列 5 款加提示**：5 列都要顯示，大小文字正確（14.0／20.7／15.2 MB）。→ Task 2 字型管理測試。
4. **只有部分字型被隱藏**：WebView 91 時列出 3 款，同時顯示 Issue 7 的提示。→ Task 2 字型管理測試。
5. **三種介面語系的名稱**：繁中、簡中、英文都不能漏，也不能顯示成 enum 名稱。→ Task 1 `app_font_test.dart`。

---

## 檔案結構

| 檔案 | 動作 | 責任 |
|---|---|---|
| `app/lib/reader/app_font.dart` | 修改 | 解除 `[字型停用]`；`displayName()` 補 3 款；更新說明註解 |
| `app/lib/reader/font_download_catalog.dart` | 修改 | 解除 `[字型停用]` |
| `app/pubspec.yaml` | 修改 | 更新字型相關註解 |
| `app/lib/l10n/app_zh_TW.arb`、`app_zh.arb`、`app_zh_CN.arb`、`app_en.arb` | 修改 | 新增 `fontNameGuanKiapTsingKhai`、`fontNameTaiwanPearl`、`fontNameGenRyuMinTW` |
| `app/lib/l10n/app_localizations*.dart` | 重新產生 | `flutter gen-l10n` |
| `app/test/reader/app_font_test.dart` | 修改 | 5 款的家族名稱與三語系顯示名稱 |
| `app/test/reader/font_download_catalog_test.dart` | 修改 | 3 款的下載資訊 |
| `app/test/reader/downloadable_font_store_test.dart` | 修改 | 更新 2 個 Issue 7 測試；新增正式目錄的舊 WebView 測試 |
| `app/test/screens/reader_settings_sheet_test.dart` | 修改 | 更新「不認得的名稱」測試與英文介面測試標題／斷言；新增新字型出現在選單的測試 |
| `app/test/screens/reader_screen_test.dart` | 修改 | 更新「不認得的名稱」測試；新增舊偏好 `GuanKiapTsingKhai` 的兩個測試 |
| `app/test/screens/font_management_screen_test.dart` | 修改 | 更新無 store 斷言為 5 款；新增 5 款列出、大小、部分隱藏、英文名稱 |
| `CLAUDE.md`、`docs/prd.md` | 修改 | 刪掉「3 款暫時隱藏」的描述（Task 3） |
| `docs/epics/epic-49-downloadable-fonts/epic.md`、`issues.md`、`docs/epics.md` | 修改 | 進度記錄（Task 3） |

---

### Task 1：恢復 3 款字型的 enum、下載資訊與顯示名稱

**Files:**
- Modify: `app/lib/reader/app_font.dart`
- Modify: `app/lib/reader/font_download_catalog.dart:44-61`
- Modify: `app/pubspec.yaml:226-233`
- Modify: `app/lib/l10n/app_zh_TW.arb`、`app_zh.arb`、`app_zh_CN.arb`、`app_en.arb`
- Regenerate: `app/lib/l10n/app_localizations.dart`、`app_localizations_en.dart`、`app_localizations_zh.dart`
- Test: `app/test/reader/app_font_test.dart`
- Test: `app/test/reader/font_download_catalog_test.dart`
- Test: `app/test/reader/downloadable_font_store_test.dart`
- Test: `app/test/screens/reader_settings_sheet_test.dart:1092-1104,1106-1115`
- Test: `app/test/screens/reader_screen_test.dart:6790-6798`
- Test: `app/test/screens/font_management_screen_test.dart:36-48`

**Interfaces:**
- Produces：
  - `AppFont.guanKiapTsingKhai`、`AppFont.taiwanPearl`、`AppFont.genRyuMinTW`（依序接在 `sourceHanSerif` 之後）
  - `familyName`：`'GuanKiapTsingKhai'`、`'TaiwanPearl'`、`'GenRyuMinTW'`
  - l10n getter：`fontNameGuanKiapTsingKhai`、`fontNameTaiwanPearl`、`fontNameGenRyuMinTW`

- [x] **Step 1：建立分支**

在 repo 根目錄：
```bash
git switch main && git pull --ff-only origin main
git switch -c epic-49/issue-8-restore-fonts
```

- [x] **Step 2：寫失敗的測試**

把 `app/test/reader/app_font_test.dart` 整個換成：

```dart
import 'package:elinkbook/l10n/app_localizations.dart';
import 'package:elinkbook/reader/app_font.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('每個 AppFont 都有對應的家族名稱字串，且彼此互不相同', () {
    const expected = {
      AppFont.sourceHanSans: 'SourceHanSansTC',
      AppFont.sourceHanSerif: 'SourceHanSerifTC',
      AppFont.guanKiapTsingKhai: 'GuanKiapTsingKhai',
      AppFont.taiwanPearl: 'TaiwanPearl',
      AppFont.genRyuMinTW: 'GenRyuMinTW',
    };
    // epic-49 Issue 8：epic-48 停用的 3 款恢復為可下載字型，順序即字型管理與閱讀設定的列出順序
    expect(AppFont.values, [
      AppFont.sourceHanSans,
      AppFont.sourceHanSerif,
      AppFont.guanKiapTsingKhai,
      AppFont.taiwanPearl,
      AppFont.genRyuMinTW,
    ]);
    for (final font in AppFont.values) {
      expect(font.familyName, expected[font]);
    }
    final allNames = AppFont.values.map((f) => f.familyName).toSet();
    expect(
      allNames.length,
      AppFont.values.length,
      reason: '家族名稱字串必須互不相同，否則原生端登記時後者會覆蓋前者',
    );
  });

  test('三種介面語系的顯示名稱（epic-49 Issue 8）', () {
    String namesIn(Locale locale) {
      final l10n = lookupAppLocalizations(locale);
      return AppFont.values.map((f) => f.displayName(l10n)).join('、');
    }

    expect(namesIn(const Locale('zh', 'TW')), '思源黑體、思源宋體、原俠正楷、台灣圓體、源流明體');
    expect(namesIn(const Locale('zh', 'CN')), '思源黑体、思源宋体、原侠正楷、台湾圆体、源流明体');
    expect(namesIn(const Locale('en')),
        'Source Han Sans、Source Han Serif、GuanKiapTsingKhai、TaiwanPearl、GenRyuMin TW');
  });
}
```

在 `app/test/reader/font_download_catalog_test.dart` 第一個 `test`（「啟用中的字型對應 spec.md『字型目錄』表格的數值」）的 `serif.sha256` 斷言之後、`});` 之前加入：

```dart

    // epic-49 Issue 8：恢復的 3 款
    final guanKiap = fontDownloadSpecOf(AppFont.guanKiapTsingKhai);
    expect(guanKiap.publishPath, 'v1/GuanKiapTsingKhai.ttf');
    expect(guanKiap.sizeBytes, 14675776);
    expect(guanKiap.sha256,
        '758632243c499e431fd0c847f5e8c431acf59a9b41a26237a819466139994d38');

    final pearl = fontDownloadSpecOf(AppFont.taiwanPearl);
    expect(pearl.publishPath, 'v1/TaiwanPearl-Regular.ttf');
    expect(pearl.sizeBytes, 21704488);
    expect(pearl.sha256,
        '51b3c9a4ab1b6b45dcdad7c5ae93386aea399fd3dabb85d2ac41110dc57f211d');

    final genRyu = fontDownloadSpecOf(AppFont.genRyuMinTW);
    expect(genRyu.publishPath, 'v1/GenRyuMinTW-Regular.ttf');
    expect(genRyu.sizeBytes, 15976964);
    expect(genRyu.sha256,
        '9178c199d633075b8bb91902216c3e1bc977a11fde12471a2c9a250434402927');
```

在 `app/test/reader/downloadable_font_store_test.dart` 的 `group('WebView 太舊時只公開載得動的字型（Issue 7）'` 裡：

1. 把
```dart
    test('舊 WebView（91）：supportedFonts 不含超過 30MB 的字型', () {
      expect(storeFor(91).supportedFonts, [AppFont.sourceHanSerif]);
    });
```
改成：
```dart
    /// mixedSpecOf 只把思源黑體標成 40MB，其他字型都是 50,000 bytes
    final allButSans = AppFont.values.where((f) => f != AppFont.sourceHanSans).toList();

    test('舊 WebView（91）：supportedFonts 不含超過 30MB 的字型', () {
      expect(storeFor(91).supportedFonts, allButSans);
    });
```

2. 把
```dart
      expect(await storeFor(91).installedFonts(), {AppFont.sourceHanSerif});
```
改成：
```dart
      expect(await storeFor(91).installedFonts(), allButSans.toSet());
```

3. 在這個 group 結尾的 `});` 之前加入：
```dart

    test('正式字型目錄＋舊 WebView（91）：只公開新恢復的 3 款（Issue 8）', () {
      final store = DownloadableFontStore(
        httpClient: serving({}),
        directory: fontsDir,
        baseUri: Uri.parse('https://fonts.test/'),
        webViewMajorVersion: 91,
      );
      expect(store.supportedFonts,
          [AppFont.guanKiapTsingKhai, AppFont.taiwanPearl, AppFont.genRyuMinTW]);
    });
```
（不傳 `specOf`，就是用正式的 `fontDownloadSpecOf`。）

在 `app/test/screens/reader_settings_sheet_test.dart` 把
```dart
  testWidgets('偏好設定存著已停用的字型時，面板正常開啟且下拉選單顯示「使用書本字型」（epic-48）',
      (tester) async {
    await _pumpSheet(
        tester, const BookReaderPrefs(fontFamily: 'GuanKiapTsingKhai'), (_) {});
```
改成：
```dart
  testWidgets('偏好設定存著不認得的字型名稱時，面板正常開啟且下拉選單顯示「使用書本字型」（epic-48）',
      (tester) async {
    // epic-49 Issue 8 恢復原俠正楷後，改用真的不存在的名稱，保留「不認得也不會壞」的意圖
    await _pumpSheet(
        tester, const BookReaderPrefs(fontFamily: 'NoSuchFont'), (_) {});
```

在 `app/test/screens/reader_screen_test.dart` 把
```dart
    testWidgets('不認得的字型名稱（含 epic-48 停用字型）照原值傳遞（審查重點 4）',
        (tester) async {
      await prefsManager.saveBookPrefs(
          'b1', const BookReaderPrefs(fontFamily: 'GuanKiapTsingKhai'));

      await pumpReader(tester, store: FakeDownloadableFontStore());

      expect(readerView(tester).fontFamily, 'GuanKiapTsingKhai');
    });
```
改成：
```dart
    testWidgets('不認得的字型名稱照原值傳遞（審查重點 4）', (tester) async {
      // epic-49 Issue 8 恢復原俠正楷後，改用真的不存在的名稱，保留原本的意圖
      await prefsManager.saveBookPrefs(
          'b1', const BookReaderPrefs(fontFamily: 'NoSuchFont'));

      await pumpReader(tester, store: FakeDownloadableFontStore());

      expect(readerView(tester).fontFamily, 'NoSuchFont');
    });
```

在 `app/test/screens/font_management_screen_test.dart` 把
```dart
  testWidgets('顯示標題與 2 款內建字型（無操作按鈕），已停用的 3 款不顯示（epic-48）',
      (tester) async {
    await pumpScreen(tester);

    expect(find.text('字型管理'), findsOneWidget);
    expect(find.text('思源黑體'), findsOneWidget);
    expect(find.text('思源宋體'), findsOneWidget);
    expect(find.text('原俠正楷'), findsNothing);
    expect(find.text('台灣圓體'), findsNothing);
    expect(find.text('源流明體'), findsNothing);
    expect(find.byKey(const Key('font_management_upload_button')),
        findsOneWidget);
  });
```
改成（審查 I-1：恢復後無 store 時 `builtInFonts = AppFont.values`，5 款都會渲染）：
```dart
  testWidgets('沒有 store 時顯示標題與 5 款內建字型（無操作按鈕）（epic-48，epic-49 Issue 8）',
      (tester) async {
    await pumpScreen(tester);

    expect(find.text('字型管理'), findsOneWidget);
    expect(find.text('思源黑體'), findsOneWidget);
    expect(find.text('思源宋體'), findsOneWidget);
    expect(find.text('原俠正楷'), findsOneWidget);
    expect(find.text('台灣圓體'), findsOneWidget);
    expect(find.text('源流明體'), findsOneWidget);
    expect(find.byKey(const Key('font_management_upload_button')),
        findsOneWidget);
  });
```

在 `app/test/screens/reader_settings_sheet_test.dart` 把
```dart
  testWidgets('英文介面下字型選單的內建字型名稱以英文顯示，已停用字型不列出（epic-48）',
      (tester) async {
    await _pumpSheet(tester, const BookReaderPrefs(), (_) {},
        locale: const Locale('en'));

    await tester.tap(find.byKey(const Key('reader_settings_font_family')));
    await tester.pumpAndSettle();

    expect(find.text('Source Han Sans'), findsWidgets);
    expect(find.text('Source Han Serif'), findsWidgets);
    expect(find.text('思源黑體'), findsNothing);
    expect(find.text('原俠正楷'), findsNothing);
  });
```
改成（審查 M-1：恢復後字型確實列出，「已停用字型不列出」語意過時）：
```dart
  testWidgets('英文介面下字型選單的內建字型名稱以英文顯示（epic-48，epic-49 Issue 8）',
      (tester) async {
    await _pumpSheet(tester, const BookReaderPrefs(), (_) {},
        locale: const Locale('en'));

    await tester.tap(find.byKey(const Key('reader_settings_font_family')));
    await tester.pumpAndSettle();

    expect(find.text('Source Han Sans'), findsWidgets);
    expect(find.text('Source Han Serif'), findsWidgets);
    expect(find.text('GuanKiapTsingKhai'), findsWidgets);
    expect(find.text('TaiwanPearl'), findsWidgets);
    expect(find.text('GenRyuMin TW'), findsWidgets);
    expect(find.text('思源黑體'), findsNothing);
  });
```

- [x] **Step 3：執行測試，確認失敗**

```bash
flutter test test/reader/app_font_test.dart test/reader/font_download_catalog_test.dart test/reader/downloadable_font_store_test.dart
```
預期：FAIL，編譯錯誤 `Member not found: 'guanKiapTsingKhai'`（以及 `taiwanPearl`、`genRyuMinTW`）。

（`reader_settings_sheet_test.dart`、`reader_screen_test.dart`、`font_management_screen_test.dart` 的改名／改斷言測試在恢復前後都會通過，它們是為了不讓 Step 4 弄壞而先改，Step 6 一起執行。）

- [x] **Step 4：寫實作**

1. `app/lib/reader/app_font.dart`：

說明註解（9-11 行）
```dart
/// [字型停用] epic-48：清單只保留思源黑體／思源宋體，其餘 3 款先註解停用
/// （不顯示在字型選單）。恢復時搜尋 `[字型停用]` 標記，把註解掉的 enum 值
/// 與 switch 分支一併解除註解即可。
```
改成：
```dart
/// epic-48 曾停用原俠正楷、台灣圓體、源流明體，epic-49 Issue 8 恢復為可下載字型。
```

enum 與 `familyName` 的 6 行 `// [字型停用] ` 前綴全部拿掉，結果是：
```dart
enum AppFont {
  sourceHanSans, // 思源黑體 SourceHanSansTC-VF.ttf
  sourceHanSerif, // 思源宋體 SourceHanSerifTC-VF.ttf
  guanKiapTsingKhai, // 原俠正楷 GuanKiapTsingKhai.ttf
  taiwanPearl, // 台灣圓體 TaiwanPearl-Regular.ttf
  genRyuMinTW, // 源流明體 GenRyuMinTW-Regular.ttf
}
```
```dart
      case AppFont.sourceHanSerif:
        return 'SourceHanSerifTC';
      case AppFont.guanKiapTsingKhai:
        return 'GuanKiapTsingKhai';
      case AppFont.taiwanPearl:
        return 'TaiwanPearl';
      case AppFont.genRyuMinTW:
        return 'GenRyuMinTW';
```

`displayName()` 在 `return l10n.fontNameSourceHanSerif;` 之後加上：
```dart
      case AppFont.guanKiapTsingKhai:
        return l10n.fontNameGuanKiapTsingKhai;
      case AppFont.taiwanPearl:
        return l10n.fontNameTaiwanPearl;
      case AppFont.genRyuMinTW:
        return l10n.fontNameGenRyuMinTW;
```

2. `app/lib/reader/font_download_catalog.dart` 44-61 行：18 行的 `// [字型停用] ` 前綴全部拿掉（數值不動），結果是：
```dart
    case AppFont.guanKiapTsingKhai:
      return const FontDownloadSpec(
        publishPath: 'v1/GuanKiapTsingKhai.ttf',
        sizeBytes: 14675776,
        sha256: '758632243c499e431fd0c847f5e8c431acf59a9b41a26237a819466139994d38',
      );
    case AppFont.taiwanPearl:
      return const FontDownloadSpec(
        publishPath: 'v1/TaiwanPearl-Regular.ttf',
        sizeBytes: 21704488,
        sha256: '51b3c9a4ab1b6b45dcdad7c5ae93386aea399fd3dabb85d2ac41110dc57f211d',
      );
    case AppFont.genRyuMinTW:
      return const FontDownloadSpec(
        publishPath: 'v1/GenRyuMinTW-Regular.ttf',
        sizeBytes: 15976964,
        sha256: '9178c199d633075b8bb91902216c3e1bc977a11fde12471a2c9a250434402927',
      );
```

3. `app/pubspec.yaml` 226-233 行，把
```yaml
    # epic-48：內建字型一律不打包進 APK，改由 epic-49「可下載字型」在使用者
    # 點下載後才取得。下載功能完成前，選思源黑體／宋體會由系統字型補位。
    # - assets/fonts/SourceHanSansTC-VF.ttf
    # - assets/fonts/SourceHanSerifTC-VF.ttf
    # [字型停用] 其餘 3 款同時從字型清單隱藏（見 lib/reader/app_font.dart 的恢復說明）。
    # 5 款字型原檔都放在 repo 根目錄的 fonts-cdn/fonts/（epic-49），不再放在 assets/fonts/。
    # - assets/fonts/GuanKiapTsingKhai.ttf
    # - assets/fonts/TaiwanPearl-Regular.ttf
    # - assets/fonts/GenRyuMinTW-Regular.ttf
```
改成：
```yaml
    # epic-48：內建字型一律不打包進 APK，改由 epic-49「可下載字型」在使用者
    # 點下載後才取得（ADR 0035）。5 款字型原檔放在 repo 根目錄的 fonts-cdn/fonts/。
```

4. 4 個 arb 新增字串。

`app/lib/l10n/app_zh_TW.arb`，加在 `"@fontNameSourceHanSerif": { … },` 區塊之後：
```json
  "fontNameGuanKiapTsingKhai": "原俠正楷",
  "@fontNameGuanKiapTsingKhai": {
    "description": "內建字型名稱：原俠正楷（字型管理清單與閱讀設定的字型下拉選單，epic-49 Issue 8）"
  },
  "fontNameTaiwanPearl": "台灣圓體",
  "@fontNameTaiwanPearl": {
    "description": "內建字型名稱：台灣圓體（字型管理清單與閱讀設定的字型下拉選單，epic-49 Issue 8）"
  },
  "fontNameGenRyuMinTW": "源流明體",
  "@fontNameGenRyuMinTW": {
    "description": "內建字型名稱：源流明體（字型管理清單與閱讀設定的字型下拉選單，epic-49 Issue 8）"
  },
```

`app/lib/l10n/app_zh.arb`，加在 `"fontNameSourceHanSerif": "思源宋體",` 之後：
```json
  "fontNameGuanKiapTsingKhai": "原俠正楷",
  "fontNameTaiwanPearl": "台灣圓體",
  "fontNameGenRyuMinTW": "源流明體",
```

`app/lib/l10n/app_zh_CN.arb`，加在 `"fontNameSourceHanSerif": "思源宋体",` 之後：
```json
  "fontNameGuanKiapTsingKhai": "原侠正楷",
  "fontNameTaiwanPearl": "台湾圆体",
  "fontNameGenRyuMinTW": "源流明体",
```

`app/lib/l10n/app_en.arb`，加在 `"fontNameSourceHanSerif": "Source Han Serif",` 之後：
```json
  "fontNameGuanKiapTsingKhai": "GuanKiapTsingKhai",
  "fontNameTaiwanPearl": "TaiwanPearl",
  "fontNameGenRyuMinTW": "GenRyuMin TW",
```

接著產生程式碼：
```bash
flutter gen-l10n
git status --short lib/l10n
```
預期：4 個 arb 與 `app_localizations.dart`、`app_localizations_en.dart`、`app_localizations_zh.dart` 顯示為已修改。

- [x] **Step 5：確認沒有殘留的停用標記**

```bash
git grep -n "字型停用" -- lib pubspec.yaml
```
預期：沒有輸出（結束碼 1）。

- [x] **Step 6：執行測試，確認通過**

```bash
flutter test test/reader/app_font_test.dart test/reader/font_download_catalog_test.dart test/reader/downloadable_font_store_test.dart test/screens/reader_settings_sheet_test.dart test/screens/reader_screen_test.dart
```
預期：`All tests passed!`。`font_download_catalog_test.dart` 的「與 fonts-cdn/fonts.json 完全一致」測試現在會比對 5 款。

- [x] **Step 7：analyze、l10n 檢查並提交**

```bash
flutter analyze
node tool/check_l10n_hardcoded_strings.js
git add lib/reader/app_font.dart lib/reader/font_download_catalog.dart pubspec.yaml lib/l10n test/reader/app_font_test.dart test/reader/font_download_catalog_test.dart test/reader/downloadable_font_store_test.dart test/screens/reader_settings_sheet_test.dart test/screens/reader_screen_test.dart test/screens/font_management_screen_test.dart
git commit -m "feat(fonts): 恢復原俠正楷、台灣圓體、源流明體為可下載字型（epic-49 Issue 8）"
```
預期：`No issues found!`；l10n 檢查兩行 PASS。

---

### Task 2：畫面層回歸測試

**Files:**
- Test: `app/test/screens/font_management_screen_test.dart`
- Test: `app/test/screens/reader_settings_sheet_test.dart`
- Test: `app/test/screens/reader_screen_test.dart`

**Interfaces:**
- Consumes：Task 1 的 3 個 enum 值、`familyName`、l10n 名稱；Fake 的 `installed`、`supported` 欄位（Issue 7）。
- Produces：無（只有測試）。

> **這個 Task 的新增測試第一次執行就會通過，這是預期的。** 畫面都走訪 `AppFont.values`，Task 1 恢復 enum 後行為就已經生效，沒有新的正式程式碼要寫。這些測試守住「畫面不能改成寫死字型清單」，並涵蓋審查重點 2、3、4。Task 1 已在 Step 2 更新了既有測試的過時斷言（`font_management_screen_test.dart` 與 `reader_settings_sheet_test.dart`），這裡只新增測試。

- [x] **Step 1：寫字型管理畫面的測試**

在 `app/test/screens/font_management_screen_test.dart` 的 `group('可下載字型（epic-49）', () {` 裡，`testWidgets('英文介面：字型名稱與狀態以英文顯示'` 之前加入：

```dart
    testWidgets('5 款內建字型依序列出，大小正確（Issue 8）', (tester) async {
      // 預設測試畫面 800x600 放不下 5 列＋自訂字型區塊，加高避免 ListView 沒建出後面幾列
      tester.view.physicalSize = const Size(2400, 6000);
      addTearDown(tester.view.resetPhysicalSize);
      await pumpScreen(tester, store: store);

      expect(subtitleOf(AppFont.sourceHanSans, '34.4 MB · 未下載'), findsOneWidget);
      expect(subtitleOf(AppFont.sourceHanSerif, '57.1 MB · 未下載'), findsOneWidget);
      expect(subtitleOf(AppFont.guanKiapTsingKhai, '14.0 MB · 未下載'), findsOneWidget);
      expect(subtitleOf(AppFont.taiwanPearl, '20.7 MB · 未下載'), findsOneWidget);
      expect(subtitleOf(AppFont.genRyuMinTW, '15.2 MB · 未下載'), findsOneWidget);
      expect(find.text('原俠正楷'), findsOneWidget);
      expect(find.text('台灣圓體'), findsOneWidget);
      expect(find.text('源流明體'), findsOneWidget);

      // 順序：依 AppFont.values
      final tops = [
        for (final font in AppFont.values)
          tester.getTopLeft(find.byKey(Key('font_management_builtin_${font.name}'))).dy,
      ];
      expect(tops, List.of(tops)..sort());
      expect(find.byKey(const Key('font_management_builtin_unsupported_hint')), findsNothing);
    });

    testWidgets('舊 WebView 只載得動新恢復的 3 款：只列出這 3 款，並顯示提示（Issue 8）',
        (tester) async {
      store.supported = [AppFont.guanKiapTsingKhai, AppFont.taiwanPearl, AppFont.genRyuMinTW];
      await pumpScreen(tester, store: store);

      expect(find.text('思源黑體'), findsNothing);
      expect(find.text('思源宋體'), findsNothing);
      expect(find.text('原俠正楷'), findsOneWidget);
      expect(find.text('台灣圓體'), findsOneWidget);
      expect(find.text('源流明體'), findsOneWidget);
      expect(find.byKey(const Key('font_management_builtin_unsupported_hint')), findsOneWidget);
    });

    testWidgets('英文介面：新恢復的 3 款字型名稱以英文顯示（Issue 8）', (tester) async {
      tester.view.physicalSize = const Size(2400, 6000);
      addTearDown(tester.view.resetPhysicalSize);
      await pumpScreen(tester, store: store, locale: const Locale('en'));

      expect(find.text('GuanKiapTsingKhai'), findsOneWidget);
      expect(find.text('TaiwanPearl'), findsOneWidget);
      expect(find.text('GenRyuMin TW'), findsOneWidget);
      expect(subtitleOf(AppFont.taiwanPearl, '20.7 MB · Not downloaded'), findsOneWidget);
    });
```

- [x] **Step 2：寫閱讀設定的測試**

在 `app/test/screens/reader_settings_sheet_test.dart` 的 `group('只列出已下載的內建字型（epic-49 Issue 4）', () {` 裡，第一個 `testWidgets` 之後加入：

```dart
    testWidgets('只下載台灣圓體時，選單只有台灣圓體（Issue 8）', (tester) async {
      await _pumpSheet(tester, const BookReaderPrefs(), (_) {},
          installedFonts: {AppFont.taiwanPearl});

      await tester.tap(find.byKey(const Key('reader_settings_font_family')));
      await tester.pumpAndSettle();

      expect(find.text('台灣圓體'), findsWidgets);
      expect(find.text('原俠正楷'), findsNothing);
      expect(find.text('思源黑體'), findsNothing);
    });

    testWidgets('偏好為已下載的原俠正楷時，選單顯示原俠正楷（Issue 8）', (tester) async {
      await _pumpSheet(
          tester, const BookReaderPrefs(fontFamily: 'GuanKiapTsingKhai'), (_) {},
          installedFonts: {AppFont.guanKiapTsingKhai});

      final dropdown = tester.widget<DropdownButton<String?>>(
          find.byKey(const Key('reader_settings_font_family')));
      expect(dropdown.value, 'GuanKiapTsingKhai');
    });
```

- [x] **Step 3：寫閱讀器的測試**（審查重點 2）

在 `app/test/screens/reader_screen_test.dart` 的 `group('未下載字型改用書本字型（epic-49 Issue 6）', () {` 群組內、最後一個 `testWidgets` 之後（群組結尾的 `});` 之前）加入：

```dart
    testWidgets('epic-48 以前選的原俠正楷，沒下載時閱讀器收到 null，偏好不改寫（Issue 8）',
        (tester) async {
      await prefsManager.saveBookPrefs(
          'b1', const BookReaderPrefs(fontFamily: 'GuanKiapTsingKhai'));

      await pumpReader(tester, store: FakeDownloadableFontStore());

      expect(readerView(tester).fontFamily, isNull);
      expect(prefsManager.bookPrefsByBookId['b1']!.fontFamily, 'GuanKiapTsingKhai');
    });

    testWidgets('epic-48 以前選的原俠正楷，下載後照原值傳遞（Issue 8）', (tester) async {
      await prefsManager.saveBookPrefs(
          'b1', const BookReaderPrefs(fontFamily: 'GuanKiapTsingKhai'));
      final store = FakeDownloadableFontStore()..installed.add(AppFont.guanKiapTsingKhai);

      await pumpReader(tester, store: store);

      expect(readerView(tester).fontFamily, 'GuanKiapTsingKhai');
    });
```

- [x] **Step 4：執行測試**

```bash
flutter test test/screens/font_management_screen_test.dart test/screens/reader_settings_sheet_test.dart test/screens/reader_screen_test.dart
```
預期：`All tests passed!`（原因見本 Task 開頭的說明）。

- [x] **Step 5：analyze 並提交**

```bash
flutter analyze
git add test/screens/font_management_screen_test.dart test/screens/reader_settings_sheet_test.dart test/screens/reader_screen_test.dart
git commit -m "test(fonts): 字型管理、閱讀設定、閱讀器涵蓋恢復的 3 款字型（epic-49 Issue 8）"
```
預期：`No issues found!`。

---

### Task 3：整體驗證、真機確認與進度記錄

**Files:**
- Modify: `CLAUDE.md:92`
- Modify: `docs/prd.md`（frontmatter `lastEdited`、`editHistory`；FR-09）
- Modify: `docs/epics/epic-49-downloadable-fonts/epic.md`
- Modify: `docs/epics/epic-49-downloadable-fonts/issues.md`
- Modify: `docs/epics.md`
- Modify: `docs/epics/epic-49-downloadable-fonts/plans/plan-issue-8.md`（勾選步驟）

- [x] **Step 1：完整測試與靜態檢查**

在 `app/`：
```bash
flutter test
flutter analyze
node tool/check_l10n_hardcoded_strings.js
```
預期：只有 1 個失敗，是 `test/wifi_transfer/wifi_transfer_http_server_test.dart`「下載期間 activeTransfersNotifier 維持在 1…」（`epic-50-wifi-transfer-test-fix` 的既有問題）。其他全部通過；`No issues found!`；l10n 檢查兩行 PASS。出現任何其他失敗都要先修。

- [x] **Step 2：更新 CLAUDE.md 與 PRD**

`CLAUDE.md` 第 92 行，把
```
- 內建字型：思源黑體與思源宋體（開源 SIL OFL 基礎字型），加上三款商用授權字型——原俠正楷、台灣圓體、源流明體（後三款目前暫時自清單隱藏）。
```
改成：
```
- 內建字型：思源黑體與思源宋體（開源 SIL OFL 基礎字型），加上三款商用授權字型——原俠正楷、台灣圓體、源流明體。
```
（同一行後半段「字型檔**不打包進 APK**…」不動。）

`docs/prd.md`：
1. frontmatter 的 `lastEdited` 改成執行當天日期（`YYYY-MM-DD`）。
2. `editHistory:` 下第一筆之前加入：
```yaml
  - date: '<YYYY-MM-DD>'
    changes: 'FR-09 恢復原俠正楷、台灣圓體、源流明體為可下載字型（epic-49 Issue 8），刪除「暫時自清單隱藏」。'
```
3. FR-09 那一列刪掉 `（原俠正楷、台灣圓體、源流明體目前暫時自清單隱藏）`。

確認：
```bash
git grep -n "暫時自清單隱藏" -- CLAUDE.md docs/prd.md
```
預期：只剩 `docs/prd.md` 舊的 `editHistory` 那一筆（2026-09-25，歷史記錄不改）。

- [x] **Step 3：建置 debug APK**

```bash
flutter build apk --debug
```
預期：`√ Built build\app\outputs\flutter-apk\app-debug.apk`。

- [x] **Step 4：真機確認（人類操作）**

需要 Issue 7 用過的兩台裝置。APK 用 USB 檔案傳輸複製到裝置「Download」資料夾後在裝置上安裝（同簽章覆蓋更新，資料保留）。

一般手機（9491G，WebView 154）：
1. 開字型管理。預期：5 款依序列出（思源黑體、思源宋體、原俠正楷、台灣圓體、源流明體），沒有提示；思源黑體、思源宋體仍是「已下載」。
2. 依序下載原俠正楷、台灣圓體、源流明體。預期：每款進度增加，完成後變「已下載」。
3. 開 `epic-49 字型驗證書` → 閱讀設定 → 字型選「台灣圓體」。預期：內文變成圓體。

電子紙（Allwinner WAVE，WebView 91）：
4. 開字型管理。預期：只有原俠正楷、台灣圓體、源流明體 3 款，「內建字型」下有 Issue 7 的提示。
5. 下載原俠正楷。預期：完成後變「已下載」。
6. 清空 log 後開驗證書，字型選「原俠正楷」。預期：內文變成楷體。在 repo 根目錄（Git Bash）：
   ```bash
   adb logcat -d | grep -iE "OTS|Failed to decode"
   ```
   預期：沒有輸出。

回報每一步「通過／失敗＋一句觀察」。

- [x] **Step 5：記錄進度**

依 Step 1、4 的實際結果：

1. `issues.md` Issue 8 的 `**Status:**` 改成 `completed`。
2. `epic.md` 開發記錄最後新增一段 `**<YYYY-MM-DD> Issue 8 完成**（分支 `epic-49/issue-8-restore-fonts`，待 PR 合併）`，寫明：工單疑問查核結果、計畫決定 1～4、完整測試結果、真機確認結果。
3. `docs/epics.md` epic-49 那一列備註改成：`全數完成（Issue 8 待 PR 合併），待歸檔`。

真機有失敗時照實記錄，Issue 8 維持 `ready-for-human`，由人類決定修正方式。

- [x] **Step 6：勾選本計畫並提交**

在 repo 根目錄：
```bash
git add CLAUDE.md docs/prd.md docs/epics.md docs/epics/epic-49-downloadable-fonts/epic.md docs/epics/epic-49-downloadable-fonts/issues.md docs/epics/epic-49-downloadable-fonts/plans/plan-issue-8.md
git commit -m "docs(epic-49): 記錄 Issue 8 完成，同步 CLAUDE.md 與 PRD 的字型清單"
```
之後依人類指示推送並發 PR。
