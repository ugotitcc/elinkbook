# Epic 18 Issue 10：流式 EPUB 原生嵌入遷移至 `flutter_inappwebview`（完整實作）Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 把流式 EPUB（`FoliateEpubReaderView`）的原生嵌入元件從 `AndroidView`+自建 `android.webkit.WebView`（`FoliateEpubReaderView.kt`）換成 `flutter_inappwebview` 套件的 `InAppWebView`，修復真機長按選字後無法拖曳控點建立劃線的問題（ADR 0013），同時維持 `FoliateEpubReaderView` 對外公開介面（建構參數／callback／static helper 簽章）完全不變。

**Architecture:** Issue 8 Spike 已證實 `InAppWebView` 的原生觸控轉發機制能正確還原「長按選字→拖曳控點」手勢，且既有 `selectionchange` 監聽器本身不需更換（Spike harness 用的就是這個機制，見 `reviews/spike-flutter-inappwebview-selection.md` 1.3 節「DOM selectionchange 事件隨控點位移即時觸發」），也證實 `shouldInterceptRequest` 能正確服務既有 ES module 載入鏈結。基於這兩項證據，本計畫採用以下設計（取代 ADR 0013 寫下時、Spike 執行前的推測性方案）：

1. **JS↔Dart 橋接**從 Kotlin `addJavascriptInterface`+`MethodChannel` 全數換成 `flutter_inappwebview` 的 `addJavaScriptHandler`/`evaluateJavascript`，`main.js` 的 8 處 `window.FoliateBridge.xxx(...)` 呼叫點機械式改寫為 `window.flutter_inappwebview.callHandler('xxx', ...)`（參數列完全不變，見 Task 5）。
2. **資源載入**（`foliate-js` 8 個 JS/HTML 檔案、5 款內建字型、待開啟的 EPUB 檔案本體）全部改由 **Dart 端**的 `shouldInterceptRequest` 攔截並提供位元組內容，取代 Kotlin 端的 `WebViewAssetLoader`：
   - `foliate-js` 檔案（`app/android/app/src/main/assets/foliate/`）**維持放在 Android 原生 assets 目錄不搬動**（不是 Flutter `pubspec.yaml` 宣告的資源，`rootBundle` 讀不到），改由新增的極小型原生 MethodChannel（Task 2）以 `context.assets.open()` 讀取位元組回傳給 Dart。
   - 5 款字型檔案本來就是 Flutter assets（`pubspec.yaml` 已宣告），Dart 直接用 `rootBundle.load()` 讀取，不需要新的原生程式碼。
   - EPUB 檔案本體：檔案系統路徑用 `dart:io` 直接讀取（含 Task 1 的路徑範圍驗證）；`content://` URI（本機匯入的 SAF 檔案，見 ADR 0002）透過 Task 2 新增的原生 `ContentResolver` 橋接讀取（Dart 沒有內建能力讀取 `content://`）。
3. **`FoliateEpubReaderView.kt`／`FoliateEpubReaderViewFactory.kt`／`FoliateLocatorCodec.kt`／`FoliateDecorationCodec.kt`／`FoliatePathValidator.kt` 五個既有 Kotlin 檔案（連同其 JVM 測試）整批移除**——邏輯全數移植為 Dart 純函式（Task 1），移除後 `flutter_inappwebview` 套件自行負責 `InAppWebView` 的 `PlatformView` 註冊，`MainActivity.configureFlutterEngine()` 不再需要手動 `registerViewFactory` 這條路徑（Task 6）。
4. **音量鍵攔截依賴的 `ReaderViewAttachmentTracker.attach()/detach()`**（epic-7-interaction Issue 7）失去原本掛在 `FoliateEpubReaderView.kt` `init`/`dispose()` 的呼叫點，改由 Dart 端在 `onWebViewCreated`/`State.dispose()` 主動呼叫既有 `elinkbook/volume_key` MethodChannel 新增的兩個 case（Task 2），確保音量鍵翻頁功能不因這次遷移而回歸。
5. **9 宮格導航熱區維持既有 Dart `Stack` 疊加 `GestureDetector` 模式**，但接上 ADR 0013 規劃、原本要在 Issue 8 完成但因改走 Spike 路線而未實作的「有作用中選取範圍時才放行拖曳」`_hasActiveSelection` 邏輯（Task 4）。
6. **`main.js` 無條件新增 Android 專用 `contextmenu`/`pointercancel` 選取偵測分支**（ADR 0013 已採納的既定決策，比照 anx-reader 已驗證的手法）——Issue 8 Spike 在單一測試裝置上顯示既有 `selectionchange` 監聽器於 `InAppWebView` 下似乎已可運作，但這僅是「該裝置夠用」的證據，不足以支撐在計畫階段自行推翻一份已走完 SDD 流程、正式採納的 ADR（不同 Android WebView 版本/廠牌客製化/E-Ink 裝置的行為差異風險並未被排除）；本計畫維持 ADR 0013 原定範圍，Task 5 的真機驗證只用來確認「已實作的機制生效」，不做「是否要實作」的決策（審查修正：初版曾錯誤地把這點改為條件式，經審查指出後改回）。

**Tech Stack:** Flutter（`flutter_inappwebview: ^6.1.5`，已存在於 `pubspec.yaml`）、Kotlin（`context.assets`／`ContentResolver`，皆為 Android SDK 原生 API，非新增第三方套件）、`flutter_test`（純 Dart 邏輯層）、真機 `integration_test` 與人工驗證（WebView 手勢/JS 橋接行為，比照 Issue 8 Spike 與 Epic 18 既有真機 mutation test 慣例）。

## Global Constraints

- 不修改 vendored `readest/foliate-js`（`view.js`／`paginator.js`／`overlayer.js`／`epubcfi.js`／`progress.js`／`text-walker.js`／`epub.js`／`vendor/zip.js`），比照 ADR 0011。本計畫只碰 `main.js`（JS 橋接呼叫目標字串）與其所在目錄的服務方式，不碰其餘 8 個 vendored 檔案的內容。
- `FoliateEpubReaderView` 的公開建構參數與 callback 簽章（`filePath`／`onPageRendered`／`onError`／`onLayoutResolved`／9 項版面偏好／`columnMode`／`columnSize`／`showFooter`／`navZoneActions`／`onZoneAction`／`showNavZoneDebugOverlay`／`initialLocatorJson`／`onLocatorChanged`／`onSelectionChanged`／`onSelectionCleared`／`onAnnotationActivated`）與 6 個 static helper（`nextPage`／`previousPage`／`jumpToProgression`／`jumpToLocator`／`loadTableOfContents`／`setDecorations`）簽章**一律不變**（ADR 0013「Dart 端公開介面契約不變」）。`app/lib/screens/reader_screen.dart` 呼叫端**不需要修改任何一行**。
- EPUB（FXL，`EpubReaderView.kt`）與 PDF（`PdfReaderView.kt`）兩條既有原生路徑完全不受本計畫影響，不得變動。
- `flutter_inappwebview` 是本計畫新增的第一個直接依賴 `InAppWebView` widget 的檔案；既有 `foliate_epub_reader_view_test.dart`（~30 個測試）全部建立在「`AndroidView`+自建 `cc.ugotit.elinkbook/foliate_epub_reader_view_$id` MethodChannel」這個機制之上，該機制在本計畫後完全不存在，因此該測試檔**不是逐項修補、而是整份重寫**（Task 4）——重寫後的測試策略：能抽成不依賴真實 `InAppWebViewController` 的純 Dart 函式（偏好 map 組裝、JS handler 參數解析、CFI/TOC/劃線格式轉換）一律維持 `flutter_test` 完整覆蓋；`InAppWebView` 本身的真實 JS 橋接/觸控轉發行為，比照本 Epic 既有慣例（`main.js`/`setAttribute` 呼叫無 JS 單元測試），驗收依賴真機 `integration_test` 與人工操作，不強行用 mock 偽造一個 `flutter_inappwebview` 從未提供簡單測試替身的機制。
- 每個 Task 完成後執行 `flutter analyze`（Dart 變動）或對應 Kotlin 變動後的 `flutter build apk --debug`（確認原生端可編譯，本計畫不新增/變動 JVM 單元測試以外的 Gradle 測試流程）。
- 真機驗證需要一台已連接、已授權 USB 偵錯的真實 Android 裝置（沿用本 Epic 既有裝置 `3CEF42ECD491687`）。

---

## Task 1：Dart 端純函式 Codec 層（取代 Kotlin `FoliateLocatorCodec`／`FoliateDecorationCodec`／`FoliatePathValidator`）

**Files:**
- Create: `app/lib/reader/foliate_bridge_codec.dart`
- Test: `app/test/reader/foliate_bridge_codec_test.dart`

**Interfaces:**
- Consumes: `app/lib/reader/toc_entry.dart`（`TocEntry.fromWire`）、`app/lib/reader/epub_decoration.dart`（`EpubDecoration`）
- Produces：
  - `String? extractCfi(String? locatorJson)`
  - `List<TocEntry> parseTableOfContents(String tocJson)`
  - `String argbToCssColor(int argb)`
  - `List<Map<String, Object?>> buildDecorationEntries(List<EpubDecoration> decorations)`
  - `bool isPathWithinRoot(String requestedCanonicalPath, String allowedRootCanonicalPath)`

這 5 個函式的行為需與 Kotlin 對應版本（`FoliateLocatorCodec.extractCfi`/`parseTocEntries`、`FoliateDecorationCodec.argbIntToCssColor`/`buildDecorationEntries`、`FoliatePathValidator.isPathWithinRoot`）逐一對稱，測試案例直接對照既有 3 份 JVM 測試（`app/android/app/src/test/kotlin/cc/ugotit/elinkbook/FoliateLocatorCodecTest.kt`／`FoliateDecorationCodecTest.kt`／`FoliatePathValidatorTest.kt`）搬移，不遺漏任何既有案例（這些檔案在 Task 6 會被刪除，本 Task 是它們的替代覆蓋）。

- [x] **Step 1：撰寫失敗測試——`extractCfi`**

```dart
import 'dart:convert';

import 'package:elinkbook/reader/epub_decoration.dart';
import 'package:elinkbook/reader/foliate_bridge_codec.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('extractCfi', () {
    test('新格式 JSON 正確取出 cfi 欄位', () {
      const json =
          '{"cfi":"epubcfi(/6/8!/4[story-2-2],/60/3:32,/70/1:32)","index":3,"fraction":0.042091}';
      expect(extractCfi(json), 'epubcfi(/6/8!/4[story-2-2],/60/3:32,/70/1:32)');
    });

    test('舊格式 Readium Locator JSON 沒有 cfi 欄位，回傳 null（優雅退回）', () {
      const readiumLocatorJson =
          '{"href":"/OEBPS/chapter1.xhtml","type":"application/xhtml+xml",'
          '"title":"Chapter 1","locations":{"progression":0.42,"totalProgression":0.1}}';
      expect(extractCfi(readiumLocatorJson), isNull);
    });

    test('格式錯誤的字串回傳 null，不拋出例外', () {
      expect(extractCfi('not a json string'), isNull);
    });

    test('null 輸入回傳 null', () {
      expect(extractCfi(null), isNull);
    });

    test('cfi 欄位為 null 值時回傳 null', () {
      expect(extractCfi('{"cfi":null,"index":0,"fraction":0}'), isNull);
    });

    test('cfi 欄位為非字串型別時回傳 null', () {
      expect(extractCfi('{"cfi":12345,"index":0,"fraction":0}'), isNull);
    });
  });
}
```

- [x] **Step 2：執行測試確認失敗（函式尚未存在）**

Run: `flutter test test/reader/foliate_bridge_codec_test.dart`
Expected: FAIL——`Error: Method not found: 'extractCfi'`（或等效的 undefined function 錯誤）。

- [x] **Step 3：實作 `extractCfi`**

建立 `app/lib/reader/foliate_bridge_codec.dart`：

```dart
import 'dart:convert';
import 'dart:typed_data';

import 'epub_decoration.dart';
import 'toc_entry.dart';

/// 解析/擷取 epic-17-epub-render-migration Issue 6 新增的定位 JSON 格式
/// （`{"cfi":"epubcfi(...)","index":N,"fraction":F}`），取代原本
/// `FoliateLocatorCodec.kt`（純函式，不觸碰 `InAppWebView`，見
/// epic-18-reader-device-qa plans/plan-issue-10.md ADR 0013 後續遷移）。
/// [locatorJson] 為 `null`、JSON 格式錯誤、或既有流式書籍留下的舊格式
/// Readium Locator JSON（無 `cfi` 鍵）皆回傳 `null`，供呼叫端優雅退回。
String? extractCfi(String? locatorJson) {
  if (locatorJson == null) return null;
  try {
    final obj = jsonDecode(locatorJson);
    if (obj is Map && obj['cfi'] is String) return obj['cfi'] as String;
    return null;
  } catch (_) {
    return null;
  }
}
```

- [x] **Step 4：執行測試確認通過**

Run: `flutter test test/reader/foliate_bridge_codec_test.dart`
Expected: All `extractCfi` 測試 PASS。

- [x] **Step 5：撰寫失敗測試——`parseTableOfContents`**

於同一測試檔新增：

```dart
  group('parseTableOfContents', () {
    test('解析扁平（無巢狀子項目）目錄陣列', () {
      const json = '['
          '{"title":"第一章","locatorJson":"{\\"cfi\\":\\"epubcfi(/6/4)\\",\\"index\\":0,\\"fraction\\":0.0}",'
          '"progression":0.0,"children":[]},'
          '{"title":"第二章","locatorJson":"{\\"cfi\\":\\"epubcfi(/6/6)\\",\\"index\\":1,\\"fraction\\":0.5}",'
          '"progression":0.5,"children":[]}'
          ']';
      final entries = parseTableOfContents(json);
      expect(entries.length, 2);
      expect(entries[0].title, '第一章');
      expect(entries[1].progression, 0.5);
    });

    test('解析含巢狀子項目的目錄陣列（round-trip 驗證巢狀結構保留）', () {
      const json = '['
          '{"title":"第一部","locatorJson":"","progression":null,'
          '"children":[{"title":"第一章",'
          '"locatorJson":"{\\"cfi\\":\\"epubcfi(/6/4)\\",\\"index\\":0,\\"fraction\\":0.0}",'
          '"progression":0.0,"children":[]}]}'
          ']';
      final entries = parseTableOfContents(json);
      expect(entries.length, 1);
      expect(entries[0].progression, isNull);
      expect(entries[0].children.length, 1);
      expect(entries[0].children[0].title, '第一章');
    });

    test('格式錯誤的 JSON 陣列字串回傳空清單，不拋出例外', () {
      expect(parseTableOfContents('not a json array'), isEmpty);
    });

    test('空陣列回傳空清單', () {
      expect(parseTableOfContents('[]'), isEmpty);
    });
  });
```

- [x] **Step 6：執行測試確認失敗**

Run: `flutter test test/reader/foliate_bridge_codec_test.dart`
Expected: FAIL——`parseTableOfContents` 未定義。

- [x] **Step 7：實作 `parseTableOfContents`**

於 `foliate_bridge_codec.dart` 新增：

```dart
/// 把 `main.js` `window.getTableOfContents()` 回傳的 JSON 陣列字串解析為
/// [TocEntry] 清單（取代原本 Kotlin 端 `FoliateLocatorCodec.parseTocEntries`
/// + `tocEntryFromJsonObject`）。`jsonDecode` 產生的 `Map<String, dynamic>`
/// 依 Dart 泛型協變規則可直接滿足 [TocEntry.fromWire] 要求的
/// `Map<Object?, Object?>` 型別（`String <: Object?`、`dynamic <: Object?`），
/// 不需要額外轉型。[tocJson] 格式錯誤時回傳空清單，不拋出例外——目錄讀取
/// 失敗不應該讓已成功開啟的書籍畫面顯示錯誤，比照原 Kotlin 實作的既有
/// 錯誤處理原則。
List<TocEntry> parseTableOfContents(String tocJson) {
  try {
    final array = jsonDecode(tocJson) as List<dynamic>;
    return array
        .map((e) => TocEntry.fromWire(e as Map<Object?, Object?>))
        .toList();
  } catch (_) {
    return const [];
  }
}
```

- [x] **Step 8：執行測試確認通過**

Run: `flutter test test/reader/foliate_bridge_codec_test.dart`
Expected: All PASS。

- [x] **Step 9：撰寫失敗測試——`argbToCssColor`**

新增：

```dart
  group('argbToCssColor', () {
    test('完全不透明色值換算 alpha 為 1.0', () {
      expect(argbToCssColor(0xFFFF0000), 'rgba(255, 0, 0, 1.0)');
    });

    test('完全透明色值換算 alpha 為 0.0', () {
      expect(argbToCssColor(0x0000FF00), 'rgba(0, 255, 0, 0.0)');
    });

    test('半透明色值正確拆解 RGB 並換算 alpha 為 0-1 浮點數', () {
      // highlighterYellowTint = Color(0x73FDE047)，見 highlight_style.dart。
      expect(
        argbToCssColor(0x73FDE047),
        'rgba(253, 224, 71, ${0x73 / 255.0})',
      );
    });
  });
```

- [x] **Step 10：執行測試確認失敗，然後實作 `argbToCssColor`**

Run: `flutter test test/reader/foliate_bridge_codec_test.dart` → FAIL（未定義）。

新增至 `foliate_bridge_codec.dart`：

```dart
/// 把 Dart `Color.toARGB32()`／Android `Color` int 皆採用的 0xAARRGGBB
/// 版面轉換為 SVG fill/stroke 屬性可直接使用的 `rgba()` CSS 字串（取代原本
/// `FoliateDecorationCodec.argbIntToCssColor`）。
String argbToCssColor(int argb) {
  final a = (argb >> 24) & 0xFF;
  final r = (argb >> 16) & 0xFF;
  final g = (argb >> 8) & 0xFF;
  final b = argb & 0xFF;
  return 'rgba($r, $g, $b, ${a / 255.0})';
}
```

Run: `flutter test test/reader/foliate_bridge_codec_test.dart` → PASS。

- [x] **Step 11：撰寫失敗測試——`buildDecorationEntries`**

新增（直接操作 `EpubDecoration` 物件，不再透過 wire map 中介——本函式現在與呼叫端在同一個 Dart 執行環境，不需要先序列化成 `Map` 再解析回來）：

```dart
  group('buildDecorationEntries', () {
    test('新格式 locatorJson 正確轉換為 cfi／color／isUnderline', () {
      final entries = buildDecorationEntries([
        EpubDecoration.forHighlight(
          highlightId: 5,
          locatorJson: '{"cfi":"epubcfi(/6/8!/4[story-2-2])","index":3,"fraction":0.04}',
          tint: 0xFFFF0000,
          isUnderline: false,
        ),
      ]);
      expect(entries.length, 1);
      expect(entries[0]['id'], 'highlight:5');
      expect(entries[0]['cfi'], 'epubcfi(/6/8!/4[story-2-2])');
      expect(entries[0]['color'], 'rgba(255, 0, 0, 1.0)');
      expect(entries[0]['isUnderline'], false);
    });

    test('isUnderline 預設為 false（forNote 不接受 isUnderline 參數）', () {
      final entries = buildDecorationEntries([
        EpubDecoration.forNote(
          noteId: 1,
          locatorJson: '{"cfi":"epubcfi(/6/4)","index":0,"fraction":0.0}',
          tint: 0x73D1D5DB,
        ),
      ]);
      expect(entries[0]['isUnderline'], false);
    });

    test('舊格式（Readium Locator JSON）locatorJson 該筆略過', () {
      final entries = buildDecorationEntries([
        EpubDecoration(
          id: 'highlight:1',
          locatorJson: '{"href":"/OEBPS/chapter1.xhtml","locations":{"progression":0.1}}',
          tint: 0xFFFF0000,
        ),
      ]);
      expect(entries, isEmpty);
    });

    test('多筆項目保留順序，單筆失敗不影響其餘', () {
      final entries = buildDecorationEntries([
        EpubDecoration.forHighlight(
          highlightId: 1,
          locatorJson: '{"cfi":"epubcfi(/6/4)","index":0,"fraction":0.0}',
          tint: 0xFFFF0000,
          isUnderline: false,
        ),
        EpubDecoration(
          id: 'highlight:2',
          locatorJson: '{"href":"/OEBPS/chapter1.xhtml"}',
          tint: 0xFF00FF00,
        ),
        EpubDecoration.forNote(
          noteId: 1,
          locatorJson: '{"cfi":"epubcfi(/6/6)","index":1,"fraction":0.5}',
          tint: 0x73D1D5DB,
        ),
      ]);
      expect(entries.length, 2);
      expect(entries[0]['id'], 'highlight:1');
      expect(entries[1]['id'], 'note:1');
    });

    test('空清單回傳空清單', () {
      expect(buildDecorationEntries(const []), isEmpty);
    });

    test('重複 cfi 的兩筆項目皆原樣保留，本函式不去重（已知限制，記錄於 main.js window.setDecorations 註解）', () {
      const sameCfi = '{"cfi":"epubcfi(/6/4)","index":0,"fraction":0.0}';
      final entries = buildDecorationEntries([
        EpubDecoration.forHighlight(
          highlightId: 1, locatorJson: sameCfi, tint: 0xFFFF0000, isUnderline: false,
        ),
        EpubDecoration.forHighlight(
          highlightId: 2, locatorJson: sameCfi, tint: 0xFF0000FF, isUnderline: false,
        ),
      ]);
      expect(entries.length, 2);
      expect(entries[0]['cfi'], 'epubcfi(/6/4)');
      expect(entries[1]['cfi'], 'epubcfi(/6/4)');
    });
  });
```

- [x] **Step 12：執行測試確認失敗，然後實作 `buildDecorationEntries`**

新增至 `foliate_bridge_codec.dart`：

```dart
/// 把 Dart 端的完整標記清單轉換為 `main.js window.setDecorations()` 所需的
/// `{"id","cfi","color","isUnderline"}` 清單（取代原本
/// `FoliateDecorationCodec.buildDecorationEntries`）。單筆 [EpubDecoration]
/// 的 `locatorJson` 解析失敗（[extractCfi] 回傳 `null`——缺席、格式錯誤、
/// 或既有流式書籍留下的舊格式 Readium Locator JSON）時該筆略過，不影響
/// 其餘標記，比照原 Kotlin 實作的既有非致命錯誤略過原則。與原 Kotlin 版本
/// 不同：本函式直接操作 [EpubDecoration] 物件，不再需要先序列化為 wire
/// map 再解析回來（呼叫端與本函式同在 Dart 執行環境內）。
List<Map<String, Object?>> buildDecorationEntries(
  List<EpubDecoration> decorations,
) {
  final entries = <Map<String, Object?>>[];
  for (final decoration in decorations) {
    final cfi = extractCfi(decoration.locatorJson);
    if (cfi == null) continue;
    entries.add({
      'id': decoration.id,
      'cfi': cfi,
      'color': argbToCssColor(decoration.tint),
      'isUnderline': decoration.isUnderline,
    });
  }
  return entries;
}
```

Run: `flutter test test/reader/foliate_bridge_codec_test.dart` → PASS。

- [x] **Step 13：撰寫失敗測試——`isPathWithinRoot`**

新增：

```dart
  group('isPathWithinRoot', () {
    const allowedRoot = '/data/user/0/cc.ugotit.elinkbook/files';

    test('合法路徑——請求路徑就是允許根目錄本身', () {
      expect(isPathWithinRoot(allowedRoot, allowedRoot), isTrue);
    });

    test('合法路徑——請求路徑是允許根目錄底下的子路徑', () {
      expect(
        isPathWithinRoot('$allowedRoot/books/novel.epub', allowedRoot),
        isTrue,
      );
    });

    test('不合法——已正規化解析後的路徑落在允許根目錄之外', () {
      expect(
        isPathWithinRoot(
          '/data/user/0/cc.ugotit.elinkbook/other/secret.txt',
          allowedRoot,
        ),
        isFalse,
      );
    });

    test('不合法——同前綴但其實是完全不同的目錄（純 startsWith 會誤判的邊界情況）', () {
      expect(
        isPathWithinRoot('${allowedRoot}_evil/secret.txt', allowedRoot),
        isFalse,
      );
    });

    test('不合法——符號連結指向允許目錄外，模擬解析後的絕對路徑', () {
      expect(
        isPathWithinRoot(
          '/data/user/0/other_app/databases/secrets.db',
          allowedRoot,
        ),
        isFalse,
      );
    });

    test('審查修正——Windows 反斜線路徑正規化後仍正確判斷（開發機平台相容性）', () {
      const windowsRoot = r'C:\Users\dev\AppData\Local\Temp\app\files';
      expect(
        isPathWithinRoot(
          r'C:\Users\dev\AppData\Local\Temp\app\files\sample.epub',
          windowsRoot,
        ),
        isTrue,
      );
      expect(
        isPathWithinRoot(
          r'C:\Users\dev\AppData\Local\Temp\app\files_evil\secret.txt',
          windowsRoot,
        ),
        isFalse,
      );
    });
  });
```

- [x] **Step 14：執行測試確認失敗，然後實作 `isPathWithinRoot`**

新增至 `foliate_bridge_codec.dart`：

```dart
/// 判斷「已正規化」的請求路徑是否真的落在允許根目錄之內（含根目錄本身）
/// （取代原本 `FoliatePathValidator.isPathWithinRoot`，純字串邊界比對，
/// 不做任何檔案系統 I/O）。刻意不用單純的
/// `requestedCanonicalPath.startsWith(allowedRootCanonicalPath)`——會誤判
/// 「同前綴但其實是不同目錄」的情況（例如 allowedRoot=".../files"，
/// requestedPath=".../files_evil/x" 純 startsWith 會誤判為合法）。必須
/// 額外要求邊界字元本身也對得上：完全相等，或後面緊接著路徑分隔符。
///
/// 審查修正：兩個參數先正規化為一律以 `/` 為分隔符再比對，而非直接假設
/// 呼叫端一定是 `/`。開發機（Windows）執行 `flutter test` 時，
/// `File.resolveSymbolicLinksSync()`（Task 3 `loadBookBytes` 呼叫）回傳的
/// 是反斜線路徑，若這裡的邊界字元寫死 `/`，Task 3 Step 12「允許目錄內的
/// 真實檔案」測試會在 Windows 開發機上直接判定為「不在允許範圍內」而失敗
/// ——本專案目標平台（Android）恆為 `/`，正規化為 `/` 不影響正式環境行為，
/// 只讓本函式在任何開發機平台上都能被正確測試。
bool isPathWithinRoot(
  String requestedCanonicalPath,
  String allowedRootCanonicalPath,
) {
  final normalizedRequested = requestedCanonicalPath.replaceAll('\\', '/');
  final normalizedRoot = allowedRootCanonicalPath.replaceAll('\\', '/');
  if (normalizedRequested == normalizedRoot) return true;
  return normalizedRequested.startsWith('$normalizedRoot/');
}
```

Run: `flutter test test/reader/foliate_bridge_codec_test.dart` → PASS（全部 20 個測試）。

- [x] **Step 15：`flutter analyze` 確認乾淨**

Run: `flutter analyze`
Expected: `No issues found!`

- [x] **Step 16：Commit**

```bash
git add app/lib/reader/foliate_bridge_codec.dart app/test/reader/foliate_bridge_codec_test.dart
git commit -m "feat(epic-18): 新增 Dart 端 foliate JS 橋接純函式 codec 層，取代 Kotlin Foliate*Codec"
```

---

## Task 2：原生端最小資源／附著橋接（新增 `ReaderResourceChannel`，volume_key 通道新增兩個 case）

**Files:**
- Create: `app/android/app/src/main/kotlin/cc/ugotit/elinkbook/ReaderResourceChannel.kt`
- Modify: `app/android/app/src/main/kotlin/cc/ugotit/elinkbook/MainActivity.kt`

**Interfaces:**
- Consumes：`android.content.Context.assets`（`AssetManager`）、`android.content.Context.contentResolver`、既有 `ReaderViewAttachmentTracker.attach()`/`detach()`（`ReaderViewAttachmentTracker.kt`，不修改）
- Produces：
  - `MethodChannel('elinkbook/reader_resources')`：`readAndroidAsset(path: String) -> ByteArray?`、`readContentUri(uri: String) -> ByteArray?`
  - 既有 `MethodChannel('elinkbook/volume_key')` 新增兩個 case：`attachReaderView`、`detachReaderView`

本 Task 純粹是 I/O 轉發（讀取 Android assets／`ContentResolver` 位元組），依本 Epic 既有慣例（`main.js`/`setAttribute` 呼叫無 JS 單元測試）不新增 JVM 單元測試——沒有可獨立驗證的純邏輯（不像 `FoliatePathValidator` 那種純字串比對），驗收依賴 Task 7 真機整合驗證。

- [ ] **Step 1：建立 `ReaderResourceChannel.kt`**

```kotlin
package cc.ugotit.elinkbook

import android.content.Context
import android.net.Uri
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodChannel

/**
 * 供 Dart 端 `InAppWebView.shouldInterceptRequest`（`foliate_native_bridge.dart`）
 * 讀取兩類原生端才能存取的位元組資料：
 *
 * 1. `readAndroidAsset`：`app/android/app/src/main/assets/foliate/` 底下的
 *    `foliate-js` 靜態檔案（不是 Flutter `pubspec.yaml` 宣告的資源，
 *    Dart 端 `rootBundle` 讀不到，見
 *    docs/epics/epic-18-reader-device-qa/plans/plan-issue-10.md 決策 #2）。
 * 2. `readContentUri`：本機匯入透過 SAF 取得的 `content://` URI（見
 *    docs/adr/0002-content-uri-reader-contract.md），Dart 端 `dart:io` 無法
 *    直接讀取，需要原生 `ContentResolver`。
 *
 * 取代原本 `FoliateEpubReaderView.kt` 的 `WebViewAssetLoader`／
 * `BookPathHandler`——本類別只負責「給定路徑/URI，回傳位元組」，不涉及
 * 任何 WebView 生命週期或 JS 橋接，是純粹的資源讀取轉發層。
 */
class ReaderResourceChannel(
    private val context: Context,
    messenger: BinaryMessenger,
) : MethodChannel.MethodCallHandler {
    private val channel = MethodChannel(messenger, "elinkbook/reader_resources")

    init {
        channel.setMethodCallHandler(this)
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "readAndroidAsset" -> {
                val path = call.argument<String>("path")
                if (path == null) {
                    result.success(null)
                    return
                }
                val bytes = try {
                    context.assets.open(path).use { it.readBytes() }
                } catch (e: Exception) {
                    null
                }
                result.success(bytes)
            }
            "readContentUri" -> {
                val uriString = call.argument<String>("uri")
                if (uriString == null) {
                    result.success(null)
                    return
                }
                val bytes = try {
                    context.contentResolver.openInputStream(Uri.parse(uriString))
                        ?.use { it.readBytes() }
                } catch (e: Exception) {
                    null
                }
                result.success(bytes)
            }
            else -> result.notImplemented()
        }
    }
}
```

注意本檔案需要 `import io.flutter.plugin.common.MethodCall`（`onMethodCall` 簽章使用），修正上方遺漏：檔案開頭 import 區塊需為：

```kotlin
import android.content.Context
import android.net.Uri
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
```

- [ ] **Step 2：`MainActivity.kt` 實例化 `ReaderResourceChannel`**

在 `configureFlutterEngine()`（`MainActivity.kt:103` 起）內，於既有 `bookMetadataChannel = ...`（第 126-127 行）之後新增：

```kotlin
        ReaderResourceChannel(this, flutterEngine.dartExecutor.binaryMessenger)
```

- [ ] **Step 3：`elinkbook/volume_key` 通道新增 `attachReaderView`／`detachReaderView` case**

修改 `MainActivity.kt` 既有的 `volumeKeyChannel?.setMethodCallHandler { ... }`（第 172-180 行）：

```kotlin
        volumeKeyChannel?.setMethodCallHandler { call, result ->
            when (call.method) {
                "notifyLeavingReader" -> {
                    ReaderViewAttachmentTracker.suppressedUntilReattach = true
                    result.success(null)
                }
                // Issue 10：InAppWebView 沒有自建的原生 PlatformView 生命週期
                // 可掛 ReaderViewAttachmentTracker.attach()/detach()（原本掛在
                // FoliateEpubReaderView.kt 的 init{}/dispose()，該檔案本次遷移
                // 已移除，見 Task 6），改由 Dart 端
                // foliate_native_bridge.dart 在 onWebViewCreated／
                // State.dispose() 主動呼叫這兩個 case 通知原生端。
                "attachReaderView" -> {
                    ReaderViewAttachmentTracker.attach()
                    result.success(null)
                }
                "detachReaderView" -> {
                    ReaderViewAttachmentTracker.detach()
                    result.success(null)
                }
                else -> result.notImplemented()
            }
        }
```

- [ ] **Step 4：確認原生端可編譯**

Run: `cd app && flutter build apk --debug`
Expected: 建置成功，無 Kotlin 編譯錯誤。

- [ ] **Step 5：Commit**

```bash
git add app/android/app/src/main/kotlin/cc/ugotit/elinkbook/ReaderResourceChannel.kt app/android/app/src/main/kotlin/cc/ugotit/elinkbook/MainActivity.kt
git commit -m "feat(epic-18): 新增 ReaderResourceChannel 供 Dart 端讀取 Android assets／content URI，volume_key 通道新增附著追蹤 case"
```

---

## Task 3：Dart 端原生資源載入層（串接 Task 2 通道 + `rootBundle` + `dart:io`）

**Files:**
- Create: `app/lib/reader/foliate_native_bridge.dart`
- Modify: `app/test/support/fake_path_provider_platform.dart`
- Test: `app/test/reader/foliate_native_bridge_test.dart`

**Interfaces:**
- Consumes：Task 1 的 `isPathWithinRoot`；Task 2 的 `elinkbook/reader_resources`／`elinkbook/volume_key` MethodChannel；既有 `app_font.dart`（`AppFont`／`AppFontFamilyName`，僅供文件參照，本檔案字型清單為固定常數不依賴列舉本身）
- Produces：
  - `String buildFontFaceCss()`
  - `Future<Uint8List?> loadAndroidAsset(String relativePath)`
  - `Future<Uint8List?> loadFlutterFontAsset(String assetPath)`
  - `Future<Uint8List?> loadBookBytes(String filePath)`
  - `Future<void> attachReaderView()`
  - `Future<void> detachReaderView()`

- [ ] **Step 1：擴充 `FakePathProviderPlatform` 支援 `getApplicationDocumentsPath`**

`loadBookBytes` 對檔案系統路徑分支需要驗證路徑落在 App 私有目錄範圍內（比照原 Kotlin `openBook()` 的 `FoliatePathValidator` 呼叫），需要 `getApplicationDocumentsDirectory()`。既有 `FakePathProviderPlatform`（`app/test/support/fake_path_provider_platform.dart`）只覆寫 `getTemporaryPath()`，新增 `getApplicationDocumentsPath()`：

```dart
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';

/// 測試用 [PathProviderPlatform] 替身：`flutter test`（無真實裝置）無法
/// 觸發 path_provider 的原生實作，直接回傳呼叫端指定的真實可寫入目錄
/// （例如 `Directory.systemTemp` 底下的暫存子目錄），讓
/// `getTemporaryDirectory()`／`getApplicationDocumentsDirectory()` 在純
/// widget test 環境下也能正常運作、寫出可驗證的真實檔案。比照本專案既有
/// `test/support/fake_*.dart` 命名慣例。
class FakePathProviderPlatform extends PathProviderPlatform {
  final String path;

  FakePathProviderPlatform(this.path);

  @override
  Future<String?> getTemporaryPath() async => path;

  @override
  Future<String?> getApplicationDocumentsPath() async => path;
}
```

- [ ] **Step 2：撰寫失敗測試——`buildFontFaceCss`（純函式）**

```dart
import 'dart:io';

import 'package:elinkbook/reader/foliate_native_bridge.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';

import '../support/fake_path_provider_platform.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('buildFontFaceCss 產生 5 款內建字型的 @font-face 宣告', () {
    final css = buildFontFaceCss();
    expect(css, contains(
      "@font-face { font-family: 'SourceHanSansTC'; "
      "src: url('https://appassets.androidplatform.net/assets/fonts/SourceHanSansTC-VF.ttf'); }",
    ));
    expect(css, contains(
      "@font-face { font-family: 'GuanKiapTsingKhai'; "
      "src: url('https://appassets.androidplatform.net/assets/fonts/GuanKiapTsingKhai.ttf'); }",
    ));
    expect('@font-face'.allMatches(css).length, 5);
  });
}
```

- [ ] **Step 3：執行測試確認失敗**

Run: `flutter test test/reader/foliate_native_bridge_test.dart`
Expected: FAIL——`foliate_native_bridge.dart` 不存在。

- [ ] **Step 4：建立 `foliate_native_bridge.dart`，實作 `buildFontFaceCss`**

```dart
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/services.dart' show MethodChannel, rootBundle;
import 'package:path_provider/path_provider.dart';

import 'app_font.dart';
import 'foliate_bridge_codec.dart';

const _readerResourcesChannel = MethodChannel('elinkbook/reader_resources');

/// 供 [attachReaderView]/[detachReaderView] 重用既有的
/// `elinkbook/volume_key` 通道（MainActivity.kt 既有的音量鍵事件通道，見
/// docs/epics/epic-18-reader-device-qa/plans/plan-issue-10.md Task 2）——
/// MethodChannel 物件本身只是依名稱字串指向同一條平台通道的輕量代理，
/// 與 `app/lib/screens/reader_screen.dart` 內私有的同名 `_volumeKeyChannel`
/// 是兩個各自獨立、但指向同一條原生通道的物件實例，皆可正常運作。
const _volumeKeyChannel = MethodChannel('elinkbook/volume_key');

/// 各 [AppFont] 列舉值對應的字型檔名（`app/assets/fonts/` 底下的實際檔
/// 名，`pubspec.yaml` 已宣告）。審查修正（DRY）：家族名稱字串不再於本
/// 檔案重複硬編碼一份，改重用 `app_font.dart` 既有的
/// `AppFontFamilyName.familyName`——本函式只保留「檔名」這一半確實找不到
/// 其他集中定義處的映射，且用 `switch` 而非 `Map<String, String>` 是刻意
/// 選擇：新增 [AppFont] 列舉值時，`switch` 缺少對應分支會直接編譯錯誤
/// （dart 的 exhaustiveness 檢查），比純字串 key 的 map 更難悄悄遺漏。
String _fontFileName(AppFont font) {
  switch (font) {
    case AppFont.sourceHanSans:
      return 'SourceHanSansTC-VF.ttf';
    case AppFont.sourceHanSerif:
      return 'SourceHanSerifTC-VF.ttf';
    case AppFont.guanKiapTsingKhai:
      return 'GuanKiapTsingKhai.ttf';
    case AppFont.taiwanPearl:
      return 'TaiwanPearl-Regular.ttf';
    case AppFont.genRyuMinTW:
      return 'GenRyuMinTW-Regular.ttf';
  }
}

/// 產生固定的 5 款內建字型 @font-face 宣告（FR-09），取代原本 Kotlin
/// `FoliateEpubReaderView.kt buildFontFaceCss()`。字型檔案本身是 Flutter
/// assets（`pubspec.yaml` 已宣告，見 [loadFlutterFontAsset]），故不需要
/// 透過 `FlutterInjector` 查找 Android AssetManager 的 lookup key——直接
/// 用固定虛擬路徑 `https://appassets.androidplatform.net/assets/fonts/...`，
/// 由 `InAppWebView.shouldInterceptRequest`（`foliate_epub_reader_view.dart`）
/// 攔截後呼叫 [loadFlutterFontAsset] 提供位元組。家族名稱字串直接取自
/// `AppFontFamilyName.familyName`（見 [_fontFileName] 註解），與
/// `app/lib/reader/app_font.dart` 保持單一事實來源，不重複維護。
String buildFontFaceCss() {
  final rules = <String>[];
  for (final font in AppFont.values) {
    final familyName = font.familyName;
    final fileName = _fontFileName(font);
    rules.add("@font-face { font-family: '$familyName'; "
        "src: url('https://appassets.androidplatform.net/assets/fonts/$fileName'); }");
  }
  return rules.join('\n');
}
```

- [ ] **Step 5：執行測試確認通過**

Run: `flutter test test/reader/foliate_native_bridge_test.dart` → PASS。

- [ ] **Step 6：撰寫失敗測試——`loadAndroidAsset`／`attachReaderView`／`detachReaderView`（MethodChannel mock）**

新增至測試檔：

```dart
  test('loadAndroidAsset 呼叫 elinkbook/reader_resources 的 readAndroidAsset', () async {
    MethodCall? captured;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('elinkbook/reader_resources'),
      (call) async {
        captured = call;
        return Uint8List.fromList([1, 2, 3]);
      },
    );

    final bytes = await loadAndroidAsset('foliate/main.js');

    expect(captured!.method, 'readAndroidAsset');
    expect(captured!.arguments, {'path': 'foliate/main.js'});
    expect(bytes, [1, 2, 3]);
  });

  test('attachReaderView／detachReaderView 呼叫 elinkbook/volume_key 對應 case', () async {
    final calledMethods = <String>[];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('elinkbook/volume_key'),
      (call) async {
        calledMethods.add(call.method);
        return null;
      },
    );

    await attachReaderView();
    await detachReaderView();

    expect(calledMethods, ['attachReaderView', 'detachReaderView']);
  });
```

- [ ] **Step 7：執行測試確認失敗，然後實作**

新增至 `foliate_native_bridge.dart`：

```dart
/// 讀取 `app/android/app/src/main/assets/foliate/` 底下的 `foliate-js`
/// 靜態檔案位元組（[relativePath] 例如 `'foliate/main.js'`），透過 Task 2
/// 新增的原生 `ReaderResourceChannel` 讀取（Flutter `rootBundle` 讀不到
/// Android 原生 assets 目錄，見本檔案頂部 import 區塊的架構說明）。找不到
/// 該檔案（例如 `view.js` 動態 import 但實際不存在的
/// `vendor/fflate.js`——已知既有情況，非本次遷移引入）時回傳 `null`。
Future<Uint8List?> loadAndroidAsset(String relativePath) {
  return _readerResourcesChannel
      .invokeMethod<Uint8List>('readAndroidAsset', {'path': relativePath});
}

/// 通知原生端「目前有一個流式 EPUB 的 InAppWebView 已建立」，取代原本
/// `FoliateEpubReaderView.kt` `init {}` 呼叫 `ReaderViewAttachmentTracker.attach()`
/// （epic-7-interaction Issue 7 音量鍵攔截依據）。呼叫時機：
/// `foliate_epub_reader_view.dart` 的 `onWebViewCreated` 回呼內。
Future<void> attachReaderView() =>
    _volumeKeyChannel.invokeMethod('attachReaderView');

/// 對稱 [attachReaderView]，取代原本 `FoliateEpubReaderView.kt dispose()`
/// 呼叫 `ReaderViewAttachmentTracker.detach()`。呼叫時機：
/// `_FoliateEpubReaderViewState.dispose()`。
Future<void> detachReaderView() =>
    _volumeKeyChannel.invokeMethod('detachReaderView');
```

- [ ] **Step 8：執行測試確認通過**

Run: `flutter test test/reader/foliate_native_bridge_test.dart` → PASS。

- [ ] **Step 9：撰寫失敗測試——`loadFlutterFontAsset`**

```dart
  test('loadFlutterFontAsset 透過 rootBundle 讀取 Flutter 字型 asset', () async {
    final bytes = await loadFlutterFontAsset('assets/fonts/GuanKiapTsingKhai.ttf');
    expect(bytes, isNotNull);
    expect(bytes!.isNotEmpty, isTrue);
  });
```

（`GuanKiapTsingKhai.ttf` 是目前唯一未被暫時停用的內建字型 asset，見 `pubspec.yaml` 註解，可直接在測試環境讀取真實內容。）

- [ ] **Step 10：執行測試確認失敗，然後實作**

新增至 `foliate_native_bridge.dart`：

```dart
/// 讀取 Flutter 已宣告的字型 asset（`pubspec.yaml` `assets:` 清單），供
/// `InAppWebView.shouldInterceptRequest` 服務 [buildFontFaceCss] 產生的
/// `@font-face src` 請求。
Future<Uint8List?> loadFlutterFontAsset(String assetPath) async {
  try {
    final data = await rootBundle.load(assetPath);
    return data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes);
  } catch (_) {
    return null;
  }
}
```

- [ ] **Step 11：執行測試確認通過**

Run: `flutter test test/reader/foliate_native_bridge_test.dart` → PASS。

- [ ] **Step 12：撰寫失敗測試——`loadBookBytes`（檔案系統路徑分支，含路徑驗證）**

```dart
  group('loadBookBytes（檔案系統路徑分支）', () {
    late Directory tempDir;

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('foliate_native_bridge_test_');
      PathProviderPlatform.instance =
          FakePathProviderPlatform('${tempDir.path}/files');
      await Directory('${tempDir.path}/files').create(recursive: true);
    });

    tearDown(() async {
      await tempDir.delete(recursive: true);
    });

    test('允許目錄內的真實檔案，正確讀回位元組內容', () async {
      final file = File('${tempDir.path}/files/sample.epub');
      await file.writeAsBytes([9, 8, 7]);

      final bytes = await loadBookBytes(file.path);

      expect(bytes, [9, 8, 7]);
    });

    test('允許目錄之外的路徑，回傳 null（不讀取內容）', () async {
      final outsideDir = await Directory.systemTemp.createTemp('outside_');
      addTearDown(() => outsideDir.delete(recursive: true));
      final file = File('${outsideDir.path}/secret.epub');
      await file.writeAsBytes([1]);

      final bytes = await loadBookBytes(file.path);

      expect(bytes, isNull);
    });

    test('檔案不存在時回傳 null', () async {
      final bytes = await loadBookBytes('${tempDir.path}/files/missing.epub');
      expect(bytes, isNull);
    });
  });
```

- [ ] **Step 13：執行測試確認失敗，然後實作 `loadBookBytes`**

新增至 `foliate_native_bridge.dart`：

```dart
/// 讀取待開啟的 EPUB 檔案本體位元組，供 `InAppWebView.shouldInterceptRequest`
/// 服務 `main.js` `makeBook()` 對 `/book/current.epub` 的一次性 fetch（已
/// 查證 `view.js` 原始碼確認一次性讀取整份內容、不發 HTTP Range 請求，見
/// 原 Kotlin `FoliateEpubReaderView.kt BookPathHandler` 註解）。[filePath]
/// 依 ADR 0002 可能是真實檔案系統路徑或 `content://` URI（`"://"` 啟發式
/// 判斷，比照既有慣例）：
/// - `content://` URI：透過 Task 2 的原生 `ContentResolver` 橋接讀取，
///   Android SAF 權限模型本身把關存取範圍，不做額外路徑檢查（比照原
///   Kotlin `openBook()` 對 `content://` 分支的既有信任層級）。
/// - 真實檔案路徑：先確認檔案存在，再用 [File.resolveSymbolicLinksSync]
///   取得已解析符號連結的絕對路徑，透過 [isPathWithinRoot] 驗證落在 App
///   私有資料目錄範圍內（`getApplicationDocumentsDirectory()` 的父目錄，
///   同時涵蓋 `files/`／`cache/`／`app_flutter/`，比照原
///   `FoliatePathValidator` 呼叫端的既有範圍定義），不在範圍內則回傳
///   `null`。
Future<Uint8List?> loadBookBytes(String filePath) async {
  if (filePath.contains('://')) {
    return _readerResourcesChannel
        .invokeMethod<Uint8List>('readContentUri', {'uri': filePath});
  }
  final file = File(filePath);
  if (!await file.exists()) return null;
  final canonicalPath = file.resolveSymbolicLinksSync();
  final docsDir = await getApplicationDocumentsDirectory();
  final allowedRoot = Directory(docsDir.path).parent.path;
  if (!isPathWithinRoot(canonicalPath, allowedRoot)) return null;
  return file.readAsBytes();
}
```

- [ ] **Step 14：執行測試確認通過**

Run: `flutter test test/reader/foliate_native_bridge_test.dart` → PASS（全部案例）。

- [ ] **Step 15：`flutter analyze` 確認乾淨**

Run: `flutter analyze`
Expected: `No issues found!`

- [ ] **Step 16：Commit**

```bash
git add app/lib/reader/foliate_native_bridge.dart app/test/reader/foliate_native_bridge_test.dart app/test/support/fake_path_provider_platform.dart
git commit -m "feat(epic-18): 新增 Dart 端原生資源載入層，串接 ReaderResourceChannel + rootBundle + dart:io"
```

---

## Task 4：`FoliateEpubReaderView` 改寫為 `InAppWebView`

**Files:**
- Modify: `app/lib/reader/foliate_epub_reader_view.dart`（整份改寫，公開介面不變）
- Modify: `app/test/reader/foliate_epub_reader_view_test.dart`（整份重寫，見 Global Constraints）

**Interfaces:**
- Consumes: Task 1（`extractCfi`／`buildDecorationEntries`）、Task 3（`buildFontFaceCss`／`loadAndroidAsset`／`loadFlutterFontAsset`／`loadBookBytes`／`attachReaderView`／`detachReaderView`）、`package:flutter_inappwebview/flutter_inappwebview.dart`
- Produces：`FoliateEpubReaderView` 公開介面**完全不變**（見 Global Constraints 逐項列舉），另新增 2 個供測試使用的**公開頂層函式**（供 `foliate_epub_reader_view_test.dart` 匯入驗證，不對外曝露為 widget API 的一部分，僅為維持可測試性的內部設計，比照 Task 1／3 純函式風格）：
  - `Map<String, Object?> buildFoliatePreferencesMap(FoliateEpubReaderView view)`
  - `bool foliatePreferencesChanged(FoliateEpubReaderView oldView, FoliateEpubReaderView newView)`

- [ ] **Step 1：真機/模擬環境確認 `InAppWebView` 能否在 `flutter_test` 下被 pump（決定既有 9 宮格測試是否可保留）**

在改寫正式程式碼前，先確認 `flutter_test`（純 Dart VM，無真實裝置）pump 一個裸 `InAppWebView()` widget 是否會拋出例外——這決定既有「9 個 `Key('nav_zone_\$index')` 皆存在、點擊觸發 `onZoneAction`」測試（`foliate_epub_reader_view_test.dart:545-582`）在改寫後是否還能保留。寫一個最小驗證檔：

```dart
// app/test/reader/_probe_inappwebview_pump.dart（驗證用，驗證完後於 Step 2 刪除，不進版控）
import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('裸 InAppWebView 是否能在 flutter_test 下 pump 而不拋出例外', (tester) async {
    await tester.pumpWidget(const MaterialApp(
      home: Stack(children: [InAppWebView()]),
    ));
    await tester.pump();
  });
}
```

Run: `flutter test test/reader/_probe_inappwebview_pump.dart`

Expected 分兩種可能結果，記錄實際發生哪一種於下方「驗證紀錄」：
- **若 PASS（無例外）**：`InAppWebView` 可在純 `flutter_test` 環境下安全 pump（即使底層原生 WebView 未真正建立），後續 Step 沿用既有「整份 `tester.pumpWidget` 後用 `find.byKey` 驗證 Stack 疊加層」測試風格，9 宮格 tap 測試與 `showNavZoneDebugOverlay` 測試可直接沿用既有寫法（只需把疊加層的兄弟節點從 `AndroidView(...)` 換成 `InAppWebView(...)`）。
- **若拋出例外**（例如 `MissingPluginException`／`PlatformException`，因為測試環境沒有真正的 `flutter_inappwebview` 平台實作）：改用 `tester.runAsync()` 包裹，或者若例外無法規避，9 宮格相關 widget test 一併改列入「無法純 `flutter_test` 覆蓋，依賴真機 `integration_test`」（比照本 Epic 對 WebView 行為的既有慣例），Step 4 之後的疊加層測試改寫為直接呼叫 `_FoliateEpubReaderViewState` 內部方法（不透過 `tester.pumpWidget`）或移至 Task 7 真機驗證清單，兩種情況本計畫皆已備妥對應寫法，實作者依實測結果二擇一，不得略過此驗證直接假設某一種結果。

刪除 `_probe_inappwebview_pump.dart`（驗證用，不進版控）。

- [ ] **Step 2：撰寫失敗測試——`buildFoliatePreferencesMap`（純函式，取代原本透過 MethodChannel mock 驗證 `openBook`/`setPreferences` 參數的測試）**

新建 `app/test/reader/foliate_epub_reader_view_test.dart`（取代整份既有內容）：

```dart
import 'package:elinkbook/reader/column_mode.dart';
import 'package:elinkbook/reader/epub_decoration.dart';
import 'package:elinkbook/reader/epub_position_info.dart';
import 'package:elinkbook/reader/epub_selection_info.dart';
import 'package:elinkbook/reader/foliate_epub_reader_view.dart';
import 'package:elinkbook/reader/writing_mode.dart';
import 'package:elinkbook/reader/app_font.dart';
import 'package:elinkbook/reader/epub_text_align.dart';
import 'package:elinkbook/reader/page_turn_mode.dart';
import 'package:elinkbook/reader/zone_action.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void _noop() {}
void _noopError(String message) {}

void main() {
  group('buildFoliatePreferencesMap', () {
    test('所有偏好欄位皆為 null 時回傳空 map', () {
      const view = FoliateEpubReaderView(
        filePath: '/tmp/sample.epub',
        onPageRendered: _noop,
        onError: _noopError,
      );
      expect(buildFoliatePreferencesMap(view), <String, Object?>{});
    });

    test('columnMode: single 時 map 含 columnMode: single', () {
      const view = FoliateEpubReaderView(
        filePath: '/tmp/sample.epub',
        onPageRendered: _noop,
        onError: _noopError,
        columnMode: ColumnMode.single,
      );
      expect(buildFoliatePreferencesMap(view), {'columnMode': 'single'});
    });

    test('showFooter: false 時 map 含 showFooter: false', () {
      const view = FoliateEpubReaderView(
        filePath: '/tmp/sample.epub',
        onPageRendered: _noop,
        onError: _noopError,
        showFooter: false,
      );
      expect(buildFoliatePreferencesMap(view), {'showFooter': false});
    });

    test('所有非 null 建構參數皆正確出現於 map', () {
      const view = FoliateEpubReaderView(
        filePath: '/tmp/sample.epub',
        onPageRendered: _noop,
        onError: _noopError,
        writingMode: WritingMode.vertical,
        pageTurnMode: PageTurnMode.scroll,
        fontFamily: AppFont.sourceHanSans,
        fontSize: 1.125,
        fontWeight: 1.75,
        lineHeight: 1.6,
        paragraphSpacing: 1.2,
        pageMargins: 1.3333,
        textAlign: EpubTextAlign.justify,
        publisherStyles: false,
        columnSize: 600.0,
      );
      expect(buildFoliatePreferencesMap(view), {
        'writingMode': 'vertical',
        'pageTurnMode': 'scroll',
        'fontFamily': 'SourceHanSansTC',
        'fontSize': 1.125,
        'fontWeight': 1.75,
        'lineHeight': 1.6,
        'paragraphSpacing': 1.2,
        'pageMargins': 1.3333,
        'textAlign': 'justify',
        'publisherStyles': false,
        'columnSize': 600.0,
      });
    });
  });

  group('foliatePreferencesChanged', () {
    test('columnMode 變動時回傳 true', () {
      const oldView = FoliateEpubReaderView(
        filePath: '/tmp/sample.epub',
        onPageRendered: _noop,
        onError: _noopError,
      );
      const newView = FoliateEpubReaderView(
        filePath: '/tmp/sample.epub',
        onPageRendered: _noop,
        onError: _noopError,
        columnMode: ColumnMode.single,
      );
      expect(foliatePreferencesChanged(oldView, newView), isTrue);
    });

    test('偏好欄位皆未變動時回傳 false', () {
      const oldView = FoliateEpubReaderView(
        filePath: '/tmp/sample.epub',
        onPageRendered: _noop,
        onError: _noopError,
        fontSize: 1.0,
      );
      const newView = FoliateEpubReaderView(
        filePath: '/tmp/sample.epub',
        onPageRendered: _noop,
        onError: _noopError,
        fontSize: 1.0,
      );
      expect(foliatePreferencesChanged(oldView, newView), isFalse);
    });
  });
}
```

- [ ] **Step 3：執行測試確認失敗**

Run: `flutter test test/reader/foliate_epub_reader_view_test.dart`
Expected: FAIL——`buildFoliatePreferencesMap`／`foliatePreferencesChanged` 未定義（`FoliateEpubReaderView` 舊版仍在，尚未改寫）。

- [ ] **Step 4：整份改寫 `foliate_epub_reader_view.dart`**

```dart
import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';

import 'app_font.dart';
import 'column_mode.dart';
import 'epub_decoration.dart';
import 'epub_position_info.dart';
import 'epub_selection_info.dart';
import 'epub_text_align.dart';
import 'foliate_bridge_codec.dart';
import 'foliate_native_bridge.dart';
import 'page_turn_mode.dart';
import 'percent_rect.dart';
import 'toc_entry.dart';
import 'writing_mode.dart';
import 'zone_action.dart';

/// 把目前所有非 null 的偏好參數組成一個 map，key 名稱與 `main.js`
/// `window.applyPreferences`/`window.FoliateBridge` 契約一致（取代原本
/// `_FoliateEpubReaderViewState._buildPreferencesMap()` 私有方法，改為
/// 公開頂層純函式以便不透過 `InAppWebView` 直接單元測試，見
/// docs/epics/epic-18-reader-device-qa/plans/plan-issue-10.md Task 4）。
/// `null` 值的欄位完全不出現在 map 中。
Map<String, Object?> buildFoliatePreferencesMap(FoliateEpubReaderView view) {
  final map = <String, Object?>{};
  if (view.writingMode != null) {
    map['writingMode'] =
        view.writingMode == WritingMode.vertical ? 'vertical' : 'horizontal';
  }
  if (view.pageTurnMode != null) {
    map['pageTurnMode'] =
        view.pageTurnMode == PageTurnMode.scroll ? 'scroll' : 'paginated';
  }
  if (view.fontFamily != null) map['fontFamily'] = view.fontFamily!.familyName;
  if (view.fontSize != null) map['fontSize'] = view.fontSize;
  if (view.fontWeight != null) map['fontWeight'] = view.fontWeight;
  if (view.lineHeight != null) map['lineHeight'] = view.lineHeight;
  if (view.paragraphSpacing != null) {
    map['paragraphSpacing'] = view.paragraphSpacing;
  }
  if (view.pageMargins != null) map['pageMargins'] = view.pageMargins;
  if (view.textAlign != null) map['textAlign'] = view.textAlign!.name;
  if (view.publisherStyles != null) {
    map['publisherStyles'] = view.publisherStyles;
  }
  if (view.columnMode != null) map['columnMode'] = view.columnMode!.name;
  if (view.columnSize != null) map['columnSize'] = view.columnSize;
  if (view.showFooter != null) map['showFooter'] = view.showFooter;
  return map;
}

/// 比較兩次 widget 建構參數，判斷是否需要重新呼叫
/// `window.applyPreferences()`（取代原本
/// `_FoliateEpubReaderViewState._preferencesChanged()`）。
bool foliatePreferencesChanged(
  FoliateEpubReaderView oldView,
  FoliateEpubReaderView newView,
) {
  return oldView.writingMode != newView.writingMode ||
      oldView.pageTurnMode != newView.pageTurnMode ||
      oldView.fontFamily != newView.fontFamily ||
      oldView.fontSize != newView.fontSize ||
      oldView.fontWeight != newView.fontWeight ||
      oldView.lineHeight != newView.lineHeight ||
      oldView.paragraphSpacing != newView.paragraphSpacing ||
      oldView.pageMargins != newView.pageMargins ||
      oldView.textAlign != newView.textAlign ||
      oldView.publisherStyles != newView.publisherStyles ||
      oldView.columnMode != newView.columnMode ||
      oldView.columnSize != newView.columnSize ||
      oldView.showFooter != newView.showFooter;
}

/// 包裝 readest/foliate-js（釘定 commit
/// dd71f2be356563c16a23272686189fcfb45d0b82）的 Flutter widget，供流式
/// （reflowable）EPUB 使用。原生嵌入元件為 `flutter_inappwebview` 的
/// `InAppWebView`（epic-18-reader-device-qa Issue 10，取代原本的
/// `AndroidView`+自建 `android.webkit.WebView`，見 ADR 0013）——本次遷移
/// 只換底層嵌入/JS 橋接機制，公開建構參數與 callback 契約與遷移前完全
/// 相同，`ReaderScreen` 等呼叫端不需要任何修改。
class FoliateEpubReaderView extends StatefulWidget {
  final String filePath;
  final VoidCallback onPageRendered;
  final ValueChanged<String> onError;
  final ValueChanged<EpubLayoutInfo>? onLayoutResolved;
  final WritingMode? writingMode;
  final PageTurnMode? pageTurnMode;
  final AppFont? fontFamily;
  final double? fontSize;
  final double? fontWeight;
  final double? lineHeight;
  final double? paragraphSpacing;
  final double? pageMargins;
  final EpubTextAlign? textAlign;
  final bool? publisherStyles;
  final ColumnMode? columnMode;
  final double? columnSize;
  final bool? showFooter;
  final List<ZoneAction> navZoneActions;
  final ValueChanged<ZoneAction>? onZoneAction;
  final bool showNavZoneDebugOverlay;
  final String? initialLocatorJson;
  final ValueChanged<EpubPositionInfo>? onLocatorChanged;
  final ValueChanged<EpubSelectionInfo>? onSelectionChanged;
  final VoidCallback? onSelectionCleared;
  final ValueChanged<String>? onAnnotationActivated;

  const FoliateEpubReaderView({
    super.key,
    required this.filePath,
    required this.onPageRendered,
    required this.onError,
    this.onLayoutResolved,
    this.writingMode,
    this.pageTurnMode,
    this.fontFamily,
    this.fontSize,
    this.fontWeight,
    this.lineHeight,
    this.paragraphSpacing,
    this.pageMargins,
    this.textAlign,
    this.publisherStyles,
    this.columnMode,
    this.columnSize,
    this.showFooter,
    this.navZoneActions = const [
      ZoneAction.none, ZoneAction.none, ZoneAction.none,
      ZoneAction.none, ZoneAction.none, ZoneAction.none,
      ZoneAction.none, ZoneAction.none, ZoneAction.none,
    ],
    this.onZoneAction,
    this.showNavZoneDebugOverlay = false,
    this.initialLocatorJson,
    this.onLocatorChanged,
    this.onSelectionChanged,
    this.onSelectionCleared,
    this.onAnnotationActivated,
  });

  static void nextPage(GlobalKey<State<FoliateEpubReaderView>> key) {
    final state = key.currentState;
    if (state is _FoliateEpubReaderViewState) {
      state._evaluate('window.nextPage()');
    }
  }

  static void previousPage(GlobalKey<State<FoliateEpubReaderView>> key) {
    final state = key.currentState;
    if (state is _FoliateEpubReaderViewState) {
      state._evaluate('window.previousPage()');
    }
  }

  static void jumpToProgression(
    GlobalKey<State<FoliateEpubReaderView>> key,
    double progression,
  ) {
    final state = key.currentState;
    if (state is _FoliateEpubReaderViewState) {
      state._evaluate('window.jumpToFraction($progression)');
    }
  }

  static void jumpToLocator(
    GlobalKey<State<FoliateEpubReaderView>> key,
    String locatorJson,
  ) {
    final state = key.currentState;
    if (state is _FoliateEpubReaderViewState) {
      final cfi = extractCfi(locatorJson);
      if (cfi != null) {
        state._evaluate('window.jumpToLocator(${jsonEncode(cfi)})');
      }
    }
  }

  static Future<List<TocEntry>> loadTableOfContents(
    GlobalKey<State<FoliateEpubReaderView>> key,
  ) async {
    final state = key.currentState;
    if (state is! _FoliateEpubReaderViewState) return const [];
    return state._requestTableOfContents();
  }

  static void setDecorations(
    GlobalKey<State<FoliateEpubReaderView>> key,
    List<EpubDecoration> decorations,
  ) {
    final state = key.currentState;
    if (state is _FoliateEpubReaderViewState) {
      final entries = buildDecorationEntries(decorations);
      state._evaluate('window.setDecorations(${jsonEncode(entries)})');
    }
  }

  @override
  State<FoliateEpubReaderView> createState() => _FoliateEpubReaderViewState();
}

class _FoliateEpubReaderViewState extends State<FoliateEpubReaderView> {
  InAppWebViewController? _controller;
  Completer<List<TocEntry>>? _pendingToc;

  /// Issue 8/ADR 0013：是否有作用中的文字選取範圍。`true` 時 9 宮格熱區的
  /// `GestureDetector` 不攔截拖曳手勢，讓「拖曳選取控點調整範圍」這個手勢
  /// 能傳遞到底下 `InAppWebView`；`false` 時維持既有攔截行為，避免滑動
  /// 手勢被 foliate-js 內建的滑動翻頁誤判（見
  /// docs/archive/2026-07-24-epic-7-interaction/design.md:115 的原始設計
  /// 意圖）。
  bool _hasActiveSelection = false;

  late final Uri _initialIndexUri = _buildIndexUri();

  Uri _buildIndexUri() {
    final params = <String, String>{
      'prefs': jsonEncode(buildFoliatePreferencesMap(widget)),
      'fontFaceCss': buildFontFaceCss(),
    };
    final cfi = extractCfi(widget.initialLocatorJson);
    if (cfi != null) params['initialCfi'] = cfi;
    return Uri.https(
      'appassets.androidplatform.net',
      '/assets/foliate/index.html',
      params,
    );
  }

  void _evaluate(String source) {
    _controller?.evaluateJavascript(source: source);
  }

  Future<List<TocEntry>> _requestTableOfContents() {
    if (_controller == null) return Future.value(const []);
    final completer = Completer<List<TocEntry>>();
    _pendingToc = completer;
    _evaluate('window.getTableOfContents()');
    return completer.future;
  }

  Future<void> _onWebViewCreated(InAppWebViewController controller) async {
    _controller = controller;
    controller.addJavaScriptHandler(
      handlerName: 'onPageRendered',
      callback: (args) {
        widget.onPageRendered();
        final writingModeStr = args.isNotEmpty ? args[0] as String : 'horizontal';
        widget.onLayoutResolved?.call(EpubLayoutInfo(
          isFixedLayout: false,
          writingMode: writingModeStr == 'vertical'
              ? WritingMode.vertical
              : WritingMode.horizontal,
        ));
      },
    );
    controller.addJavaScriptHandler(
      handlerName: 'onError',
      callback: (args) {
        widget.onError(args.isNotEmpty ? args[0] as String : '未知錯誤');
      },
    );
    controller.addJavaScriptHandler(
      handlerName: 'onLocatorChanged',
      callback: (args) {
        // 審查修正：main.js 目前以 `fraction ?? 0`／`location?.current ?? 0`／
        // `location?.total ?? 0` 保底，理論上不會送出 null；但改用 `as num?`
        // + `?? 0` 防禦性轉型，與本檔案其餘 handler（onPageRendered/onError/
        // onTableOfContentsReady 的 `args.isNotEmpty` 檢查）保持一致的防禦
        //風格，避免未來 main.js 若不慎移除 `?? 0` 保底時整個閱讀畫面直接
        // 因 TypeError 崩潰。
        widget.onLocatorChanged?.call(EpubPositionInfo(
          locatorJson: args.isNotEmpty ? args[0] as String : '',
          progression: (args.length > 1 ? args[1] as num? : null)?.toDouble() ?? 0.0,
          pageIndex: (args.length > 2 ? args[2] as num? : null)?.toInt() ?? 0,
          totalPages: (args.length > 3 ? args[3] as num? : null)?.toInt() ?? 0,
        ));
      },
    );
    controller.addJavaScriptHandler(
      handlerName: 'onTableOfContentsReady',
      callback: (args) {
        final completer = _pendingToc;
        _pendingToc = null;
        final json = args.isNotEmpty ? args[0] as String : '[]';
        completer?.complete(parseTableOfContents(json));
      },
    );
    controller.addJavaScriptHandler(
      handlerName: 'onSelectionChanged',
      callback: (args) {
        if (!_hasActiveSelection && mounted) {
          setState(() => _hasActiveSelection = true);
        }
        // 審查修正：同 onLocatorChanged，改用防禦性轉型取代直接強制轉型。
        num? argAt(int index) => args.length > index ? args[index] as num? : null;
        widget.onSelectionChanged?.call(EpubSelectionInfo(
          locatorJson: args.isNotEmpty ? args[0] as String : '',
          progression: argAt(1)?.toDouble() ?? 0.0,
          rect: PercentRect(
            left: argAt(2)?.toDouble() ?? 0.0,
            top: argAt(3)?.toDouble() ?? 0.0,
            right: argAt(4)?.toDouble() ?? 0.0,
            bottom: argAt(5)?.toDouble() ?? 0.0,
          ),
        ));
      },
    );
    controller.addJavaScriptHandler(
      handlerName: 'onSelectionCleared',
      callback: (args) {
        if (mounted) setState(() => _hasActiveSelection = false);
        widget.onSelectionCleared?.call();
      },
    );
    controller.addJavaScriptHandler(
      handlerName: 'onAnnotationActivated',
      callback: (args) {
        widget.onAnnotationActivated?.call(args[0] as String);
      },
    );
    await attachReaderView();
  }

  Future<WebResourceResponse?> _shouldInterceptRequest(
    InAppWebViewController controller,
    WebResourceRequest request,
  ) async {
    final path = request.url.path;
    if (path == '/book/current.epub') {
      final bytes = await loadBookBytes(widget.filePath);
      if (bytes == null) return null;
      return WebResourceResponse(contentType: 'application/epub+zip', data: bytes);
    }
    const foliateAssetsPrefix = '/assets/foliate/';
    if (path.startsWith(foliateAssetsPrefix)) {
      final relative = 'foliate/${path.substring(foliateAssetsPrefix.length)}';
      final bytes = await loadAndroidAsset(relative);
      if (bytes == null) return null;
      final contentType = path.endsWith('.js') ? 'text/javascript' : 'text/html';
      return WebResourceResponse(contentType: contentType, data: bytes);
    }
    const fontsPrefix = '/assets/fonts/';
    if (path.startsWith(fontsPrefix)) {
      final relative = 'assets/fonts/${path.substring(fontsPrefix.length)}';
      final bytes = await loadFlutterFontAsset(relative);
      if (bytes == null) return null;
      return WebResourceResponse(contentType: 'font/ttf', data: bytes);
    }
    return null;
  }

  @override
  void didUpdateWidget(covariant FoliateEpubReaderView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (foliatePreferencesChanged(oldWidget, widget)) {
      _evaluate(
        'window.applyPreferences(${jsonEncode(buildFoliatePreferencesMap(widget))})',
      );
    }
  }

  @override
  void dispose() {
    detachReaderView();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        InAppWebView(
          initialUrlRequest: URLRequest(url: WebUri.uri(_initialIndexUri)),
          initialSettings: InAppWebViewSettings(
            javaScriptEnabled: true,
            useShouldInterceptRequest: true,
          ),
          onWebViewCreated: _onWebViewCreated,
          shouldInterceptRequest: _shouldInterceptRequest,
        ),
        Positioned.fill(
          child: Column(
            children: List.generate(3, (row) {
              return Expanded(
                child: Row(
                  children: List.generate(3, (col) {
                    final index = row * 3 + col;
                    final action = widget.navZoneActions[index];
                    return Expanded(
                      child: GestureDetector(
                        key: Key('nav_zone_$index'),
                        behavior: HitTestBehavior.opaque,
                        onTap: () => widget.onZoneAction?.call(action),
                        onHorizontalDragStart: _hasActiveSelection ? null : (_) {},
                        onVerticalDragStart: _hasActiveSelection ? null : (_) {},
                        child: Container(
                          decoration: widget.showNavZoneDebugOverlay
                              ? BoxDecoration(
                                  border: Border.all(color: Colors.white24))
                              : null,
                          alignment: Alignment.center,
                          child: widget.showNavZoneDebugOverlay
                              ? Text(
                                  _zoneActionLabel(action),
                                  style: const TextStyle(
                                      color: Colors.white70, fontSize: 10),
                                )
                              : null,
                        ),
                      ),
                    );
                  }),
                ),
              );
            }),
          ),
        ),
      ],
    );
  }

  String _zoneActionLabel(ZoneAction action) {
    switch (action) {
      case ZoneAction.previousPage:
        return '上一頁';
      case ZoneAction.nextPage:
        return '下一頁';
      case ZoneAction.menu:
        return '選單';
      case ZoneAction.none:
        return '無動作';
    }
  }
}
```

- [ ] **Step 5：執行 Step 2 的純函式測試，確認通過**

Run: `flutter test test/reader/foliate_epub_reader_view_test.dart` → PASS（`buildFoliatePreferencesMap`／`foliatePreferencesChanged` 兩組測試）。

- [ ] **Step 6：依 Step 1 驗證紀錄，補上 9 宮格熱區測試**

若 Step 1 記錄結果為「可正常 pump」，於測試檔新增（沿用既有寫法，只是不再需要 mock `SystemChannels.platform_views`）：

```dart
  testWidgets('3×3 導航熱區：9 個 Key(nav_zone_\$index) 皆存在，點擊觸發對應 onZoneAction',
      (tester) async {
    final capturedActions = <ZoneAction>[];
    await tester.pumpWidget(MaterialApp(
      home: FoliateEpubReaderView(
        filePath: '/tmp/sample.epub',
        onPageRendered: _noop,
        onError: _noopError,
        navZoneActions: const [
          ZoneAction.previousPage, ZoneAction.none, ZoneAction.nextPage,
          ZoneAction.previousPage, ZoneAction.menu, ZoneAction.nextPage,
          ZoneAction.previousPage, ZoneAction.none, ZoneAction.nextPage,
        ],
        onZoneAction: capturedActions.add,
      ),
    ));
    await tester.pump();

    for (var index = 0; index < 9; index++) {
      expect(find.byKey(Key('nav_zone_$index')), findsOneWidget);
    }

    await tester.tap(find.byKey(const Key('nav_zone_2')));
    await tester.pump();
    expect(capturedActions, [ZoneAction.nextPage]);

    await tester.tap(find.byKey(const Key('nav_zone_4')));
    await tester.pump();
    expect(capturedActions, [ZoneAction.nextPage, ZoneAction.menu]);
  });

  testWidgets('showNavZoneDebugOverlay=true 時，格子顯示對應動作文字標籤',
      (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: FoliateEpubReaderView(
        filePath: '/tmp/sample.epub',
        onPageRendered: _noop,
        onError: _noopError,
        navZoneActions: const [
          ZoneAction.previousPage, ZoneAction.menu, ZoneAction.nextPage,
          ZoneAction.none, ZoneAction.none, ZoneAction.none,
          ZoneAction.none, ZoneAction.none, ZoneAction.none,
        ],
        showNavZoneDebugOverlay: true,
      ),
    ));
    await tester.pump();

    expect(find.text('上一頁'), findsWidgets);
    expect(find.text('選單'), findsWidgets);
    expect(find.text('下一頁'), findsWidgets);
    expect(find.text('無動作'), findsWidgets);
  });
```

若 Step 1 記錄結果為「拋出例外」，改記錄於本檔案「驗證紀錄」小節，說明無法保留這兩項既有 widget test，改列入 Task 7 真機驗證清單（9 宮格 tap 導覽、debug overlay 文字標籤皆已是真機肉眼可直接確認的簡單行為，改為人工驗證不損失有意義的自動化覆蓋）。

- [ ] **Step 7：執行測試確認通過（依 Step 6 實際採用的分支）**

Run: `flutter test test/reader/foliate_epub_reader_view_test.dart` → PASS。

- [ ] **Step 8：`flutter analyze` 確認乾淨**

Run: `flutter analyze`
Expected: `No issues found!`

- [ ] **Step 9：Commit**

```bash
git add app/lib/reader/foliate_epub_reader_view.dart app/test/reader/foliate_epub_reader_view_test.dart
git commit -m "feat(epic-18): FoliateEpubReaderView 改用 InAppWebView 取代 AndroidView，公開介面不變"
```

---

## Task 5：`main.js` JS 橋接改寫 + 新增 Android 專用選取偵測分支（ADR 0013 既定決策）

**Files:**
- Modify: `app/android/app/src/main/assets/foliate/main.js`

**Interfaces:**
- Consumes: Task 4 的 `InAppWebViewController.addJavaScriptHandler` 註冊（handler 名稱與參數列已在 Task 4 定案，本 Task 只需讓 `main.js` 呼叫端與之對齊）
- Produces: `main.js` 8 處橋接呼叫點全數改為 `window.flutter_inappwebview.callHandler(...)`；`load` 事件監聽器內新增 Android 專用的 `contextmenu`/`pointercancel` 選取偵測分支（ADR 0013「決策」段明確要求的既定架構，非本計畫視情況新增的選用項目）

**審查修正說明**：本 Task 原稿曾把 `contextmenu`/`pointercancel` 分支寫成「先真機驗證既有 `selectionchange` 是否已足夠，不足夠才新增」的條件式決策——但 ADR 0013（已採納）與 `issues.md` Issue 10 描述皆已明確定案「新增 Android 專用的 `contextmenu`/`pointercancel` 選取偵測分支，取代現有 iframe `selectionchange` 監聽器在 Android 平台完全不觸發的既有邏輯」；即使 Issue 8 Spike 的單一裝置測試結果顯示 `selectionchange` 在 `InAppWebView` 下似乎已可運作，這頂多是「這台測試裝置上够用」的證據，不足以支撐在計畫裡自行推翻一份已走完 SDD 流程、正式採納的 ADR——不同 Android WebView 版本/廠牌客製化/E-Ink 裝置（本專案明確的目標裝置類型，見 `docs/prd.md`）行為差異的風險並未被排除，且此偏離未經人類或另一份 ADR 正式核可。故本 Task 改回無條件實作 ADR 0013 既定的分支，真機驗證只用來確認「已實作的機制生效」，不做「是否要實作」的決策。

- [ ] **Step 1：機械式改寫 8 處 `window.FoliateBridge.xxx(...)` 呼叫，並在選取偵測邏輯中新增 Android 專用分支**

在 `main.js` 內，逐一替換（參數列完全不變，只換呼叫目標）：

1. `window.applyPreferences` 內完全沒有橋接呼叫，不需改動。
2. `openBook()` 內的 `view.addEventListener('relocate', () => { ... window.FoliateBridge.onPageRendered(resolvedWritingMode) ... }, { once: true })`：

```js
      window.flutter_inappwebview.callHandler('onPageRendered', resolvedWritingMode)
```

3. `openBook()` 第二個 `relocate` 監聽器：

```js
    view.addEventListener('relocate', (e) => {
      const { cfi, section, fraction, location } = e.detail
      window.flutter_inappwebview.callHandler(
        'onLocatorChanged',
        JSON.stringify({ cfi, index: section?.current ?? 0, fraction: fraction ?? 0 }),
        fraction ?? 0,
        location?.current ?? 0,
        location?.total ?? 0,
      )
    })
```

4. `show-annotation` 監聽器：

```js
    view.addEventListener('show-annotation', (e) => {
      const id = decorationIdByCfi.get(e.detail.value)
      if (id) window.flutter_inappwebview.callHandler('onAnnotationActivated', id)
    })
```

5-6. `selectionchange` 監聽器（`load` 事件內，選取變動＋清除兩處呼叫），**同時依 ADR 0013 新增 Android 專用 `contextmenu`/`pointercancel` 分支**——整段 `load` 事件監聽器改寫為：

```js
    view.addEventListener('load', (e) => {
      const doc = e.detail.doc
      const index = e.detail.index

      // 選取範圍即時回報（epic-17 Issue 8）：抽成共用函式，供既有
      // selectionchange 與下方 ADR 0013 既定的 Android 專用
      // contextmenu/pointercancel 分支共同呼叫，避免重複實作同一段
      // CFI/座標換算邏輯。'load' 事件對 look-ahead 預讀章節同樣會觸發，
      // 故 doc/index 皆從本次 'load' 呼叫的區域變數閉包讀取（見
      // spike-overlayer-annotations.md「已記錄的既有 API 落差」）。
      const reportSelection = async () => {
        const selection = doc.getSelection()
        if (!selection || selection.rangeCount === 0 || selection.isCollapsed) {
          window.flutter_inappwebview.callHandler('onSelectionCleared')
          return
        }
        const range = selection.getRangeAt(0)
        const rect = range.getClientRects()[0]
        if (!rect) return
        const cfi = view.getCFI(index, range)
        const progress = await view.getCFIProgress(cfi)
        const iframeRect = doc.defaultView.frameElement.getBoundingClientRect()
        const viewportRect = view.getBoundingClientRect()
        window.flutter_inappwebview.callHandler(
          'onSelectionChanged',
          JSON.stringify({ cfi, index, fraction: progress?.fraction ?? 0 }),
          progress?.fraction ?? 0,
          (iframeRect.left + rect.left - viewportRect.left) / viewportRect.width,
          (iframeRect.top + rect.top - viewportRect.top) / viewportRect.height,
          (iframeRect.left + rect.right - viewportRect.left) / viewportRect.width,
          (iframeRect.top + rect.bottom - viewportRect.top) / viewportRect.height,
        )
      }

      doc.addEventListener('selectionchange', reportSelection)

      // ADR 0013 既定決策（非本計畫視情況新增）：比照 anx-reader 已驗證的
      // 手法（見 tmp/epic-18/reviews/anx_reader_foliate_js_highlighting_
      // analysis.md 5 節）——contextmenu 在長按觸發原生選字/顯示控點時
      // 觸發，需 preventDefault() 避免原生選單彈出與既有 AnnotationToolbar
      // 衝突；pointercancel 在拖曳控點期間，原本的 pointer 手勢因系統選取
      // 手勢接管而觸發，兩者皆代表「選取狀態可能剛建立或變動」，作為
      // selectionchange 的主動觸發備援（不同 Android WebView 版本/廠牌
      // 客製化/E-Ink 裝置對 selectionchange 事件觸發時機的行為差異，比
      // 依賴單一被動事件更穩健）。
      doc.addEventListener('contextmenu', (evt) => {
        evt.preventDefault()
        reportSelection()
      })
      doc.addEventListener('pointercancel', () => reportSelection())
    })
```

7. `window.getTableOfContents()` 成功路徑：

```js
window.getTableOfContents = async function () {
  try {
    const items = view.book?.toc ?? []
    const entries = []
    for (const item of items) {
      entries.push(await buildTocEntry(item))
    }
    window.flutter_inappwebview.callHandler('onTableOfContentsReady', JSON.stringify(entries))
  } catch (e) {
    window.flutter_inappwebview.callHandler('onTableOfContentsReady', JSON.stringify([]))
  }
}
```

8. `openBook()` 的 `catch` 區塊：

```js
  } catch (e) {
    window.flutter_inappwebview.callHandler('onError', String((e && e.message) || e))
  }
```

- [ ] **Step 2：真機建置並確認基本開書流程未壞**

```bash
cd app
flutter run -d 3CEF42ECD491687
```

開啟一本流式 EPUB，確認：畫面成功渲染出書本內容（非空白/錯誤畫面）、翻頁正常、目錄可開啟、書籤/劃線清單若既有資料可正確顯示定位。若任一項失敗，先排查是否為 Step 1 的呼叫點改寫遺漏或參數順序誤植，修正後重新驗證，**不得帶著失敗結果進入 Step 3**。

- [ ] **Step 3：真機確認 Android 專用選取偵測分支確實生效（確認生效，非決定是否採用）**

長按書本內文任一段文字 2 秒以上，觀察原生選取控點是否出現；接著用手指拖曳其中一個控點，觀察選取範圍是否隨拖曳擴大/縮小，且 `AnnotationToolbar`（劃線顏色/底線/備註工具列）是否正確跟隨選取範圍附近顯示。Step 1 已無條件實作 `selectionchange`＋`contextmenu`＋`pointercancel` 三個監聽器（ADR 0013 既定決策），本 Step 純粹確認實作結果在真機上確實生效，不是「要不要寫這段程式碼」的決策點——若拖曳控點時選取範圍沒有反應，代表 Step 1 的實作有缺陷（例如 `contextmenu` 的 `preventDefault()` 時機不對、或 `reportSelection` 內的 CFI/座標計算邏輯有誤），需要除錯修正後重新驗證，而非回頭移除該分支。

把本 Step 的實際觀察結果（包含長按建立初始選取、拖曳控點調整範圍兩個子步驟各自是否成功）記錄於本文件「驗證紀錄」小節，供後續複查依據。

- [ ] **Step 4：真機完整驗證劃線建立流程**

拖曳選取控點調整範圍→放開→`AnnotationToolbar` 出現→選一個顏色建立劃線→確認畫面上出現對應顏色的高亮，且重新整理/重開該書後劃線仍在正確位置。

- [ ] **Step 5：Commit**

```bash
git add app/android/app/src/main/assets/foliate/main.js
git commit -m "feat(epic-18): main.js JS 橋接呼叫改為 flutter_inappwebview callHandler，並依 ADR 0013 新增 Android 專用 contextmenu/pointercancel 選取偵測分支"
```

---

## Task 6：移除舊有原生檔案與註冊

**Files:**
- Delete: `app/android/app/src/main/kotlin/cc/ugotit/elinkbook/FoliateEpubReaderView.kt`
- Delete: `app/android/app/src/main/kotlin/cc/ugotit/elinkbook/FoliateEpubReaderViewFactory.kt`
- Delete: `app/android/app/src/main/kotlin/cc/ugotit/elinkbook/FoliateLocatorCodec.kt`
- Delete: `app/android/app/src/main/kotlin/cc/ugotit/elinkbook/FoliateDecorationCodec.kt`
- Delete: `app/android/app/src/main/kotlin/cc/ugotit/elinkbook/FoliatePathValidator.kt`
- Delete: `app/android/app/src/test/kotlin/cc/ugotit/elinkbook/FoliateLocatorCodecTest.kt`
- Delete: `app/android/app/src/test/kotlin/cc/ugotit/elinkbook/FoliateDecorationCodecTest.kt`
- Delete: `app/android/app/src/test/kotlin/cc/ugotit/elinkbook/FoliatePathValidatorTest.kt`
- Modify: `app/android/app/src/main/kotlin/cc/ugotit/elinkbook/MainActivity.kt`

**Interfaces:**
- Consumes: Task 1（已涵蓋 3 份 JVM 測試的全部案例）、Task 2-5（已確認新架構完整可運作）
- Produces：無（純清理，不新增任何介面）

- [ ] **Step 1：確認 Task 2-5 已在真機驗證通過，且 Task 1 涵蓋 3 份 JVM 測試的全部既有案例**

比對 `app/test/reader/foliate_bridge_codec_test.dart` 測試數量與 3 份既有 JVM 測試（`FoliateLocatorCodecTest.kt` 10 案例、`FoliateDecorationCodecTest.kt` 8 案例、`FoliatePathValidatorTest.kt` 5 案例）逐一核對案例語意是否對應（不要求數量恰好一致，因為 Dart 版本合併了部分等效案例，例如 `isUnderline` 缺席測試——`FoliateDecorationCodecTest.kt` 的「缺少 id/tint 該筆略過」兩案例，因為 Dart `EpubDecoration` 建構子本身要求 `id`/`tint` 為必要參數，不可能建構出「缺少該欄位」的實例，故這兩案例在 Dart 版本天然不適用、不需要移植，型別系統本身已提供比原本 Kotlin `Map<String, Any?>` wire 格式更強的保證）。

- [ ] **Step 2：刪除 5 個 Kotlin 主程式檔案與 3 個 JVM 測試檔案**

```bash
git rm app/android/app/src/main/kotlin/cc/ugotit/elinkbook/FoliateEpubReaderView.kt
git rm app/android/app/src/main/kotlin/cc/ugotit/elinkbook/FoliateEpubReaderViewFactory.kt
git rm app/android/app/src/main/kotlin/cc/ugotit/elinkbook/FoliateLocatorCodec.kt
git rm app/android/app/src/main/kotlin/cc/ugotit/elinkbook/FoliateDecorationCodec.kt
git rm app/android/app/src/main/kotlin/cc/ugotit/elinkbook/FoliatePathValidator.kt
git rm app/android/app/src/test/kotlin/cc/ugotit/elinkbook/FoliateLocatorCodecTest.kt
git rm app/android/app/src/test/kotlin/cc/ugotit/elinkbook/FoliateDecorationCodecTest.kt
git rm app/android/app/src/test/kotlin/cc/ugotit/elinkbook/FoliatePathValidatorTest.kt
```

- [ ] **Step 3：移除 `MainActivity.kt` 內對已刪除 `FoliateEpubReaderViewFactory` 的註冊**

刪除 `configureFlutterEngine()` 內（`MainActivity.kt:119-125`）：

```kotlin
        flutterEngine
            .platformViewsController
            .registry
            .registerViewFactory(
                "cc.ugotit.elinkbook/foliate_epub_reader_view",
                FoliateEpubReaderViewFactory(flutterEngine.dartExecutor.binaryMessenger),
            )
```

`flutter_inappwebview` 套件本身透過 Flutter 外掛自動註冊機制掛載自己的 `PlatformView` 工廠，不需要應用程式端手動註冊。

- [ ] **Step 4：`./gradlew :app:testDebugUnitTest` 確認移除後仍全數通過**

```bash
cd app/android
./gradlew :app:testDebugUnitTest
```

Expected: 全數通過（移除的 3 份測試不再存在，其餘既有 JVM 測試，如 `EpubReaderView`／`PdfReaderView` 相關測試，不受影響）。

- [ ] **Step 5：`flutter build apk --debug` 確認整體可編譯**

```bash
cd ..
flutter build apk --debug
```

Expected: 建置成功。

- [ ] **Step 6：`flutter analyze` 與 `flutter test` 全專案確認**

```bash
flutter analyze
flutter test
```

Expected: `flutter analyze` 為 `No issues found!`；`flutter test` 全數通過。

- [ ] **Step 7：Commit**

```bash
git add app/android/app/src/main/kotlin/cc/ugotit/elinkbook/MainActivity.kt
git commit -m "refactor(epic-18): 移除舊有 FoliateEpubReaderView.kt 原生嵌入實作，改由 flutter_inappwebview 全權負責"
```

---

## Task 7：真機完整回歸驗證 + 更新追蹤文件

**Files:** 無（純驗證與文件更新）

**Interfaces:**
- Consumes: Task 1-6 全數完成
- Produces：`docs/epics/epic-18-reader-device-qa/issues.md` Issue 10 Status 更新；若 Task 4 Step 1 出現「無法保留既有 widget test」的結果，於 `design.md` 補記實際結果

- [ ] **Step 1：真機驗證核心缺陷已修復（Issue 10 驗收標準第 1 項）**

`flutter run -d 3CEF42ECD491687`，開啟流式 EPUB，長按選字→拖曳控點→放開→成功建立劃線（顏色/底線皆測試）。

- [ ] **Step 2：真機回歸既有功能，逐項確認無 regression**

- 換頁：9 宮格熱區 tap 導覽正常（左右翻頁、中央切換沉浸模式）。
- 沉浸模式：AppBar/頁尾（或 Issue 7 完成後的浮動疊加層）顯示/隱藏正常。
- TOC：目錄可開啟，點擊項目正確跳轉。
- 書籤：新增/刪除/點擊跳轉正常。
- 直排/橫排切換：`writingMode` 偏好切換後畫面正確重新排版。
- 欄數模式（Issue 6）：單欄/自動/雙欄三態切換正常。
- 音量鍵翻頁：進入流式 EPUB 閱讀畫面後，音量鍵可翻頁；離開閱讀畫面後，音量鍵恢復系統音量調整（驗證 Task 2/3 的 `attachReaderView`/`detachReaderView` 確實生效——這是本次遷移唯一有回歸風險的既有機制）。

- [ ] **Step 3：確認有作用中選取範圍時，9 宮格熱區不再攔截拖曳（Task 4 的 `_hasActiveSelection` 邏輯真機驗證）**

長按選字建立選取範圍後，在畫面上做水平/垂直滑動手勢（非長按選字），確認不會意外觸發 9 宮格的滑動翻頁攔截衝突；點擊空白處取消選取後，重新測試 9 宮格滑動熱區攔截是否恢復正常（避免無選取時的滑動被誤判為選字拖曳而不被攔截，導致 foliate-js 內建滑動翻頁/捲動被意外觸發）。

- [ ] **Step 4：更新 `docs/epics/epic-18-reader-device-qa/issues.md` Issue 10 狀態**

把 Status 從 `ready-for-agent`（Task 1 執行前的狀態）更新為完成摘要，格式比照既有 Issue 1/2/5/6/8 的完成摘要慣例，包含：實際採用的架構決策（Task 4 Step 1 的 widget test 可行性結論）、關聯 commit。

- [ ] **Step 5：若 Task 4 Step 1 的實際結果偏離「預期可正常 pump」，於 `design.md` 補記**

若 `InAppWebView` 無法在 `flutter_test` 下安全 pump（Task 4 Step 1 的第二種結果），屬於對既有測試策略假設的重要澄清，應比照本 Epic 既有慣例補記於 `design.md`，供後續查閱者理解實際採用的測試覆蓋範圍與原因。

---

## 驗證紀錄

> 執行 Task 4 Step 1、Task 5 Step 3 時，把實際觀察結果記錄於此，供後續複查依據。

- **Task 4 Step 1（`InAppWebView` 能否在 `flutter_test` 下 pump）**：（實作時填寫）
- **Task 5 Step 3（`selectionchange`＋`contextmenu`＋`pointercancel` 三個監聽器在真機上是否確實生效）**：（實作時填寫）

---

## Plan Self-Review Checklist

1. **Spec coverage**（對照 `issues.md` Issue 10 描述與驗收標準）：
   - `pubspec.yaml` 正式引入 `flutter_inappwebview` 依賴 → 已存在（Issue 8 Spike 已加入），本計畫不重複處理。
   - `AndroidView` 換 `InAppWebView`，公開介面不變 → Task 4。
   - JS↔Dart 橋接改為 `addJavaScriptHandler` → Task 4（Dart 端註冊）+ Task 5（`main.js` 呼叫端）。
   - `main.js` 8 處 `window.FoliateBridge.` 呼叫點改寫 → Task 5 Step 1（逐一列出全部 8 處）。
   - Android 專用選取偵測分支（`contextmenu`/`pointercancel`）→ Task 5 Step 1 無條件實作（ADR 0013 既定決策，審查修正：初版曾誤植為條件式備援，已改回），Step 3 僅做真機生效確認。
   - `WebViewAssetLoader`／`BookPathHandler`／`buildFontFaceCss()` 搬到 Dart 端 `shouldInterceptRequest` → Task 2（原生資源讀取）+ Task 3（Dart 資源載入）+ Task 4（`shouldInterceptRequest` 實作）。
   - `MainActivity.kt` 的 `FoliateEpubReaderViewFactory` 註冊移除 → Task 6 Step 3。
   - `ReaderViewAttachmentTracker` 對接確認，音量鍵翻頁不回歸 → Task 2 Step 3（新增 case）+ Task 3（Dart 呼叫）+ Task 4（`onWebViewCreated`/`dispose()` 呼叫時機）+ Task 7 Step 2（真機驗證）。
   - 真機回歸（換頁/熱區/沉浸模式/TOC/書籤/直排橫排/欄數模式/音量鍵）→ Task 7 Step 2。
   - `flutter analyze`／`flutter test`／`./gradlew :app:testDebugUnitTest` 全數通過 → Task 6 Step 4-6。
2. **Placeholder scan**：Task 5 的 Android 專用選取偵測分支已改為無條件實作（審查修正），不再是條件式待補內容；Task 4 Step 1／Task 6 Step 1／Task 7 Step 5 的「依實際結果決定」屬於刻意設計的真機驗證分支點（比照本 Epic Issue 8/2 既有的 mutation test／驗證優先慣例，且僅限於「測試策略如何調整」這類與架構決策無關的執行細節，不涉及推翻已採納的 ADR），非未定內容的佔位符。
3. **Type consistency**：`buildFoliatePreferencesMap`/`foliatePreferencesChanged`/`extractCfi`/`parseTableOfContents`/`argbToCssColor`/`buildDecorationEntries`/`isPathWithinRoot`/`buildFontFaceCss`/`loadAndroidAsset`/`loadFlutterFontAsset`/`loadBookBytes`/`attachReaderView`/`detachReaderView` 等函式名稱與簽章在 Task 1／3／4 之間完全一致，皆為公開頂層函式（非 class 方法），避免 Task 間耦合到彼此的私有實作細節。`FoliateEpubReaderView` 公開建構參數/callback/static helper 簽章在 Task 4 改寫前後逐一比對完全相同。
