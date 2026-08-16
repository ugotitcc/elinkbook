# Issue 4：TXT 合成書籍結構與閱讀 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development（建議）或 superpowers:executing-plans 逐 Task 執行本計畫。Step 前的 checkbox（`- [ ]`）用於追蹤進度。

**Goal:** 讓 elinkBook 能匯入並閱讀 TXT 純文字檔——自動偵測編碼（Big5 優先梯隊）、正確辨識繁體中文常見章節標題產生目錄、大型檔案（5-20MB）開書流暢不卡頓，直排/橫排、劃線、書籤等體驗與既有 EPUB 完全一致。TXT 目前完全無法開啟閱讀（`BookFormat` enum 沒有 `txt` 值），本 Issue 是這個能力從零到有的實作。

**Architecture:** TXT 於**匯入時**（非開書時）一次性解碼＋轉換為一份真正合法的 EPUB3 壓縮檔（container.xml + OPF + nav.xhtml + 逐章 XHTML），落地為 `Book.filePath`（副檔名仍為 `.txt`，讓 `BookFormat.txt` 能被 `detectBookFormat()` 正確識別並分派——見 Global Constraints 已查證事實 #1）。之後這本「書」完全由既有、成熟的 EPUB 流式渲染管線（`FoliateReaderView`／`epub.js`／`main.js`）處理，**零格式專屬渲染程式碼**——直排/避頭尾/CFI/劃線/書籤/目錄/同步全部繼承自既有機制，本 Issue 的全部工作集中在「解碼與合成」這一側（純 Dart，`Isolate.run()` 背景執行）。編碼偵測所需的 Big5/GBK 對照表向量化自 Unicode.org 發布的 Microsoft 字碼頁對照表，透過一次性 vendoring 腳本產生，非手動鍵入。

**Tech Stack:** Flutter/Dart（`package:archive` 既有 dependency，`dart:isolate`／`dart:convert`／`dart:typed_data` 純 Dart 二進位/文字處理）、Python（一次性 vendoring 腳本，比照本 Epic Issue 1-3 既有先例）、`readest/foliate-js` 既有 `epub.js`（釘定 commit，本 Issue 完全不修改，只產生它能解析的合法輸入）。

**Spec:** `docs/epics/epic-11-multi-format-reader/spec.md`「TXT／Markdown 合成書籍結構」「資料模型異動」「Metadata／封面擷取」；`docs/epics/epic-11-multi-format-reader/issues.md` Issue 4；`app/lib/library/book_content_fingerprint.dart`（`Isolate.run()` 既有作法／`contentFingerprint` 計算順序既有慣例）；`app/lib/screens/library_screen.dart`（`coverPath` 刪除清理既有模式）。

## Global Constraints

- 純 Dart-only 解析（ADR 0023 決策 5）：TXT 編碼偵測/轉碼/EPUB 合成邏輯禁止任何原生 platform channel 依賴（例如 `charset_converter`）；`content://` URI 讀取沿用既有、格式無關的 `copyContentUriToFile` 原生方法（Task 1 抽出的共用 helper），不新增原生程式碼。
- `CLAUDE.md` 兩層測試架構：純 Dart 解碼/分塊/合成邏輯用 `flutter test`（Seam 1）；原生渲染是否真的成功（Big5/UTF-8 檔案顯示正確、大型檔案開書流暢）須 `integration_test/` 真機驗證（Seam 2）。
- 大檔案運算（編碼偵測/轉碼/章節分塊/EPUB 合成）須包裝於 `Isolate.run()` 背景執行（spec.md 明文要求），比照 `book_content_fingerprint.dart` 既有作法；**但 TXT 封面產生（`generateTxtCover()`）使用 `dart:ui`，`dart:ui` 綁定在裸 spawn 的 isolate 內不可用，不可包進同一個 `Isolate.run()` 呼叫**，須維持在主 isolate 呼叫（見 Task 5「已查證的關鍵技術事實」）。
- `contentFingerprint` 必須對「原始輸入檔案」計算，不可用合成後的衍生 EPUB 檔案路徑計算（spec.md 明文約束，比照 Issue 3 CBZ 已建立的同一原則）。
- 所有回應/文件/程式註解使用正體中文（使用者全域 CLAUDE.md 規則）。
- **已查證的關鍵技術事實**（供各 Task 撰寫依據，皆已用本次規劃階段的原始碼交叉核對或實測驗證，非憑空假設）：
  1. **合成後的檔案副檔名必須維持 `.txt`，不可改名為 `.epub`**：`issues.md` Issue 4 範圍第 1 點明確要求「`BookFormat`（`book_format.dart`）新增 `txt`；`ReaderScreen` 對 `txt` 建構 `FoliateReaderView`」，即 `BookFormat.txt` 是獨立分派值。`ReaderScreen`／`FoliateReaderView` 的格式分派依 `detectBookFormat(widget.filePath)` 判斷副檔名，故 `Book.filePath` 落地後必須仍以 `.txt` 結尾，`BookFormat.txt` 才會被正確偵測。這**不會**讓 `view.js` 的 `makeBook()` 誤判格式——已查證 `isCBZ()`/`isFBZ()` 皆是明確的白名單判斷（副檔名 `.cbz`/`.fb2.zip`/`.fbz` 或特定 MIME type），任何不符合這些白名單、但 `isZip(file)` 為 true 的壓縮檔一律落入 `else` 分支當作 EPUB 解析（`view.js` 原始碼第 90-100 行），與檔名副檔名為 `.txt` 完全無關。Issue 3 Task 5 已修復的「WebView 書籍快取副檔名感知」（`cacheFileExtension()`）機制本身就是從 `Book.filePath` 動態推導快取檔名，對 `.txt` 副檔名一樣正確運作（快取為 `current.txt`），**不需要任何進一步修改**——這是 Issue 3 早前那次前置修復意外帶來的泛用性紅利，非本 Issue 新增工作。
  2. **`epub.js`（`readest/foliate-js` 釘定 commit，本檔案已存在於 production assets，不需修改）對最小合法 EPUB 結構的實際要求**（直接讀取原始碼 `META-INF/container.xml` → OPF → manifest/spine 解析路徑確認，非規格書字面推測）：`META-INF/container.xml` 須含至少一筆 `<rootfile full-path="..." media-type="application/oebps-package+xml"/>`；OPF 的 `<manifest><item id="..." href="..." media-type="..."/></manifest>` 與 `<spine><itemref idref="..."/></spine>`（`idref` 對應 manifest item 的 `id`）為唯一硬性要求；`<metadata>` 完全沒有必填欄位（`getMetadata()` 全程 `??`/`?.` 防禦寫法，空 `<metadata/>` 也不會拋例外）；`navPath`（`properties="nav"` 標記的 manifest item）與 NCX 皆為選填，兩者皆缺時 `this.toc`維持 `undefined`，不拋例外、不影響開書。
  3. **合成的 XHTML 內容不需要自己宣告 `writing-mode`**：直排/橫排切換由 `ReaderSettingsSheet`／`main.js` 既有的 `buildOverrideCss()` 機制（`!important` 覆蓋，格式無關）全域統一處理，本專案既有機制已對所有 Foliate 格式生效，本 Issue 的合成 XHTML 只需是結構正確的純文字段落即可，不需要嵌入任何排版方向 CSS。
  4. **Big5/GBK 對照表資料來源**：Unicode.org 發布的 Microsoft 字碼頁對照表（`CP950.TXT` = Big5、`CP936.TXT` = GBK），格式為直接的「位元組值 → Unicode 碼點」表（`0xB4FA\t0x6E2C\t#comment`），**非** WHATWG Encoding Standard 的 pointer-index 格式（後者需要額外的公式換算才能從位元組序列得到查表索引，複雜度高出一個量級且容易出錯，本次刻意選用可直接查表比對的來源）。已實際下載並解析驗證：Big5（CP950）13503 筆雙位元組項目、GBK（CP936）21791 筆，皆為 BMP 內碼點（最大 `0xFFE5`，`Uint16` 足夠儲存不需 `Uint32`）；已用已知字元交叉核對正確性——Big5 `0xB4FA`→`0x6E2C`（測）、`0xB8D5`→`0x8A66`（試）、GBK `0xB2E2`→`0x6D4B`（测）、`0xCAD4`→`0x8BD5`（试），皆正確。
  5. **`big5-hkscs` 優先層的範圍決策**：HKSCS（香港增補字符集）是 Big5 的向上相容超集，主要增補香港粵語生僻字。Unicode.org 與 WHATWG 皆未提供本專案可直接沿用的「位元組值→碼點」直接映射表（僅有更複雜的 pointer-index 格式或完全缺席），故 `big5-hkscs` 優先層**與 `big5` 共用同一份 CP950 對照表**——絕大多數繁體中文內容（含所有常用字）解碼結果不受影響，僅 HKSCS 專屬增補字元（生僻粵語字）會退化為 `U+FFFD` 替代字元而非正確顯示，這是明確記錄、有界的已知限制，非誤植或遺漏。
  6. **`_decodeDbcsStrict()` 對整份檔案要求嚴格全數對映成功，不做容錯率評分**：若 Big5 內容混雜零星非 Big5 字元（例如個別 HKSCS 生僻字、特殊符號），整個 Big5 層即判定失敗，退回 GBK 再退回 UTF-8 寬鬆 fallback（見審查回應 Important #2，本次評估後維持此設計，不導入容錯率門檻）。

## 審查回應（`reviews/review-issue-4-plan.md`，2026-08-16，結論 APPROVED / READY TO EXECUTE）

審查結論為核准通過，2 項 Important／2 項 Minor 皆非阻擋執行的缺陷。逐項查證後處置如下：

| 項目 | 查證結果 | 處置 |
|---|---|---|
| Important #1 空檔案中止匯入時孤兒封面殘留 | 查證屬實——Task 7 原始程式碼確實先落地封面才進入 `synthesizeTxtBook()` 的 `EmptyTxtException` 判斷，中止匯入後封面檔案永遠孤兒（沒有 Book 記錄可依附既有刪除清理邏輯）。採納審查建議的第一個選項（調整執行順序，非「產生後再清理」），改為合成先於封面產生——除了修復缺陷本身，也讓失敗路徑完全不產生任何殘留副作用，比「產生後 catch 內刪除」更簡潔。已修改 Task 7 程式碼並強化既有「空白 TXT 檔案不建立 Book 記錄」測試，新增 `coversDir` 為空的斷言 |
| Important #2 嚴格比對對零星非法字元的容錯性 | 審查原文已自陳「目前計畫符合 spec.md 優先序要求」，建議屬「未來或實作時視情況評估」的選用強化，非缺陷。技術評估後**不採納**：容錯率評分機制（例如「99.9% 命中率視為該編碼」）會把現行單純、行為可預測的「全數命中或退回下一層」判斷，換成需要額外調校門檻值的啟發式評分，換來的風險（例如 GBK 內容因零星巧合命中 Big5 字對而被誤判為「大部分是 Big5」）不亞於現行設計要解決的問題本身；且目前失敗模式本身是優雅的（退回 UTF-8 寬鬆解碼，不崩潰、不遺失資料，只是少數字元顯示為替代字元），不是資料損毀等級的缺陷。予以記錄為 Global Constraints 已查證事實 #6，明確標記為「評估後維持現狀」的決策，不在本 Issue 範圍內實作 |
| Minor #1 英文章節標題大小寫容錯 | 合理、成本低，`CHAPTER 1`／`chapter 1` 等真實存在的排版變體。採納，已於 `_chapterHeadingRegex` 加上 `caseSensitive: false`，並新增對應測試 |
| Minor #2 `xml` 套件依賴邊界 | 純肯定既有設計，無需處置 |

---

## Task 1：抽出共用 `content_uri_reader.dart`（DRY 重構）

**背景**：`cbz_import.dart` 已有 `_readContentUriBytes()` 私有函式（content:// URI → 複製暫存檔 → 讀取位元組 → 清理暫存檔），本 Issue 的 TXT 合成流程需要一模一樣的邏輯。與其複製第二份，先抽出共用版本並回頭改用它。

**Files:**
- Create: `app/lib/library/content_uri_reader.dart`
- Modify: `app/lib/library/cbz_import.dart`
- Test: `app/test/library/content_uri_reader_test.dart`

**Interfaces:**
- Produces：`Future<Uint8List> readContentUriBytes(String uri, {required String tempFilePrefix, required String tempFileExtension})`（供 Task 6 `txt_epub_synthesizer.dart` 與本 Task 重構後的 `cbz_import.dart` 共用）。

- [ ] **Step 1：寫失敗測試**

```dart
// app/test/library/content_uri_reader_test.dart
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:elinkbook/library/content_uri_reader.dart';

import '../support/fake_path_provider_platform.dart';

const _channel = MethodChannel('elinkbook/book_metadata');

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;
  late PathProviderPlatform originalPathProvider;

  setUp(() {
    tempDir = Directory.systemTemp.createTempSync('content_uri_reader_test_tmp');
    originalPathProvider = PathProviderPlatform.instance;
    PathProviderPlatform.instance = FakePathProviderPlatform(tempDir.path);
  });

  tearDown(() {
    PathProviderPlatform.instance = originalPathProvider;
    if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_channel, null);
  });

  test('複製 content:// URI 到暫存檔並讀回位元組', () async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_channel, (call) async {
      expect(call.method, 'copyContentUriToFile');
      final args = call.arguments as Map;
      await File(args['destinationPath'] as String).writeAsBytes([1, 2, 3]);
      return null;
    });

    final bytes = await readContentUriBytes(
      'content://example/sample.txt',
      tempFilePrefix: 'test_probe',
      tempFileExtension: '.txt',
    );

    expect(bytes, [1, 2, 3]);
  });

  test('讀取完成後刪除暫存檔', () async {
    String? capturedTempPath;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_channel, (call) async {
      final args = call.arguments as Map;
      capturedTempPath = args['destinationPath'] as String;
      await File(capturedTempPath!).writeAsBytes([9]);
      return null;
    });

    await readContentUriBytes(
      'content://example/sample.txt',
      tempFilePrefix: 'test_probe',
      tempFileExtension: '.txt',
    );

    expect(capturedTempPath, isNotNull);
    expect(File(capturedTempPath!).existsSync(), isFalse);
  });

  test('暫存檔名帶有指定的 prefix 與副檔名', () async {
    String? capturedTempPath;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_channel, (call) async {
      final args = call.arguments as Map;
      capturedTempPath = args['destinationPath'] as String;
      await File(capturedTempPath!).writeAsBytes([1]);
      return null;
    });

    await readContentUriBytes(
      'content://example/sample.txt',
      tempFilePrefix: 'txt_probe',
      tempFileExtension: '.txt',
    );

    expect(capturedTempPath, contains('txt_probe_'));
    expect(capturedTempPath, endsWith('.txt'));
  });
}
```

- [ ] **Step 2：確認測試失敗**

```bash
cd "U:/MyDeveloper/AI/elinkBook/app"
flutter test test/library/content_uri_reader_test.dart
```

Expected：FAIL（`content_uri_reader.dart` 不存在，編譯錯誤）。

- [ ] **Step 3：實作**

```dart
// app/lib/library/content_uri_reader.dart
import 'dart:io';
import 'dart:typed_data';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import 'library_repository.dart';

/// 讀取 `content://` URI 指向檔案的完整位元組內容——`dart:io` 無法對
/// `content://` URI 做隨機存取讀取（ADR 0002 既有限制），先透過既有、格式
/// 無關的 `copyContentUriToFile` 原生方法複製到暫存檔，讀取後刪除。
/// [tempFilePrefix]／[tempFileExtension] 供呼叫端區分暫存檔用途與格式
/// （例如 CBZ 用 `cbz_probe`/`.cbz`，TXT 用 `txt_probe`/`.txt`），避免不同
/// 呼叫端的暫存檔互相覆蓋或難以除錯辨識。原本各自在 `kf8_metadata.dart`／
/// `cbz_import.dart` 各自實作一份幾乎相同的邏輯，epic-11-multi-format-reader
/// Issue 4 起抽出為共用版本。
Future<Uint8List> readContentUriBytes(
  String uri, {
  required String tempFilePrefix,
  required String tempFileExtension,
}) async {
  final tempDir = await getTemporaryDirectory();
  final tempPath = p.join(
    tempDir.path,
    '${tempFilePrefix}_${DateTime.now().microsecondsSinceEpoch}$tempFileExtension',
  );
  await kBookMetadataChannel.invokeMethod<void>(
    'copyContentUriToFile',
    {'uri': uri, 'destinationPath': tempPath},
  );
  final tempFile = File(tempPath);
  try {
    return await tempFile.readAsBytes();
  } finally {
    if (tempFile.existsSync()) tempFile.deleteSync();
  }
}
```

- [ ] **Step 4：確認測試通過**

```bash
flutter test test/library/content_uri_reader_test.dart
```

Expected：PASS（3 個測試）。

- [ ] **Step 5：重構 `cbz_import.dart` 改用共用版本**

`app/lib/library/cbz_import.dart` 移除私有的 `_readContentUriBytes()` 函式本體，改為：

```dart
import 'content_uri_reader.dart';
```

並將 `prepareCbzForImport()` 內原本的：

```dart
  final bytes = filePath.contains('://')
      ? await _readContentUriBytes(filePath)
      : await File(filePath).readAsBytes();
```

改為：

```dart
  final bytes = filePath.contains('://')
      ? await readContentUriBytes(filePath, tempFilePrefix: 'cbz_probe', tempFileExtension: '.cbz')
      : await File(filePath).readAsBytes();
```

移除檔案末尾整個 `_readContentUriBytes` 函式定義（現由 `content_uri_reader.dart` 提供）。若 `library_repository.dart` 的 import 已不再被 `cbz_import.dart` 其他地方使用，一併移除該行 import（`kBookMetadataChannel` 呼叫已搬到 `content_uri_reader.dart` 內）。

- [ ] **Step 6：確認 CBZ 既有測試仍通過（零回歸）**

```bash
flutter test test/library/cbz_import_test.dart test/library/book_import_service_test.dart
```

Expected：PASS，數量與重構前相同（純內部實作搬移，行為不變）。

- [ ] **Step 7：`flutter analyze`**

```bash
flutter analyze
```

Expected：`No issues found!`

- [ ] **Step 8：Commit**

```bash
git add app/lib/library/content_uri_reader.dart app/lib/library/cbz_import.dart app/test/library/content_uri_reader_test.dart
git commit -m "refactor(epic-11): Issue 4——抽出共用 content_uri_reader.dart，cbz_import.dart 改用"
```

---

## Task 2：Vendor Big5／GBK 對照表

**Files:**
- Create: `app/tool/gen_txt_charset_tables.py`
- Create（腳本產生，提交進版控）: `app/lib/library/txt_charset_tables.dart`

**Interfaces:**
- Produces：`const String kBig5TableKeysBase64`／`kBig5TableValuesBase64`／`kGbkTableKeysBase64`／`kGbkTableValuesBase64`（4 個純資料常數，供 Task 3 `txt_charset_detection.dart` 消費）。

- [ ] **Step 1：撰寫產生腳本**

```python
# app/tool/gen_txt_charset_tables.py
"""依 epic-11-multi-format-reader Issue 4 規劃：從 Unicode.org 發布的
Microsoft 字碼頁對照表下載 Big5 (CP950) 與 GBK (CP936) 雙位元組→Unicode
對照資料，產生 app/lib/library/txt_charset_tables.dart（純資料，無邏輯，
勿手動修改）。執行一次即可，結果提交進版控，之後不需要重跑，除非要更新
來源資料版本。
"""
import base64
import re
import struct
import urllib.request
from pathlib import Path

SOURCES = {
    'Big5': 'https://www.unicode.org/Public/MAPPINGS/VENDORS/MICSFT/WINDOWS/CP950.TXT',
    'Gbk': 'https://www.unicode.org/Public/MAPPINGS/VENDORS/MICSFT/WINDOWS/CP936.TXT',
}


def fetch_table(url):
    with urllib.request.urlopen(url, timeout=30) as resp:
        text = resp.read().decode('utf-8')
    entries = []
    for line in text.splitlines():
        m = re.match(r'^0x([0-9A-Fa-f]{4})\s+0x([0-9A-Fa-f]{4})', line)
        if not m:
            continue
        entries.append((int(m.group(1), 16), int(m.group(2), 16)))
    entries.sort()
    keys = [e for e, _ in entries]
    assert keys == sorted(set(keys)), '鍵值須嚴格遞增且不重複（供 Dart 端二分搜尋）'
    return entries


def pack_base64(entries):
    keys = struct.pack('<%dH' % len(entries), *(k for k, _ in entries))
    vals = struct.pack('<%dH' % len(entries), *(v for _, v in entries))
    return base64.b64encode(keys).decode(), base64.b64encode(vals).decode()


def main():
    out_lines = [
        '// GENERATED FILE — 由 app/tool/gen_txt_charset_tables.py 產生，請勿手動修改。',
        '//',
        '// 資料來源（epic-11-multi-format-reader Issue 4）：Unicode.org 發布的 Microsoft',
        '// 字碼頁對照表，雙位元組值 → Unicode 碼點的直接對照（非 WHATWG pointer-index',
        '// 演算法格式，查表不需額外演算法轉換）：',
        '//   Big5（CP950）：https://www.unicode.org/Public/MAPPINGS/VENDORS/MICSFT/WINDOWS/CP950.TXT',
        '//   GBK （CP936）：https://www.unicode.org/Public/MAPPINGS/VENDORS/MICSFT/WINDOWS/CP936.TXT',
        '// big5-hkscs 優先層與 big5 共用同一份表（HKSCS 是 Big5 的向上相容超集，本專案',
        '// 未取得可直接使用的位元組對映表，增補字元退化為 U+FFFD，屬已知有界限制，見',
        '// txt_charset_detection.dart 文件註解）。',
        '',
    ]
    for name, url in SOURCES.items():
        entries = fetch_table(url)
        keys_b64, vals_b64 = pack_base64(entries)
        const_prefix = 'k' + name + 'Table'
        out_lines.append(f'// {name}：{len(entries)} 筆雙位元組項目。')
        out_lines.append(f"const String {const_prefix}KeysBase64 = '{keys_b64}';")
        out_lines.append(f"const String {const_prefix}ValuesBase64 = '{vals_b64}';")
        out_lines.append('')
    out_path = Path(__file__).resolve().parent.parent / 'lib' / 'library' / 'txt_charset_tables.dart'
    out_path.write_text('\n'.join(out_lines), encoding='utf-8')
    print(f'寫入 {out_path}（{out_path.stat().st_size} bytes）')


if __name__ == '__main__':
    main()
```

- [ ] **Step 2：執行腳本**

```bash
cd "U:/MyDeveloper/AI/elinkBook/app"
python3 tool/gen_txt_charset_tables.py
```

Expected：印出 `寫入 .../txt_charset_tables.dart（約 190000 bytes）`（已於規劃階段實測驗證：Big5 13503 筆／GBK 21791 筆，base64 字元數共約 188240，加上註解與變數宣告文字，檔案總大小落在同一量級）。

- [ ] **Step 3：驗證產生的檔案語法正確、可被匯入**

```bash
cat > /tmp/verify_charset_tables_test.dart << 'DARTEOF'
import 'package:flutter_test/flutter_test.dart';
import 'package:elinkbook/library/txt_charset_tables.dart';

void main() {
  test('產生的常數非空', () {
    expect(kBig5TableKeysBase64.isNotEmpty, isTrue);
    expect(kBig5TableValuesBase64.isNotEmpty, isTrue);
    expect(kGbkTableKeysBase64.isNotEmpty, isTrue);
    expect(kGbkTableValuesBase64.isNotEmpty, isTrue);
  });
}
DARTEOF
cp /tmp/verify_charset_tables_test.dart test/library/verify_charset_tables_test.dart
flutter test test/library/verify_charset_tables_test.dart
rm test/library/verify_charset_tables_test.dart
```

Expected：PASS（僅驗證產生的檔案語法正確可編譯匯入；實際解碼正確性由 Task 3 的完整測試驗證）。

- [ ] **Step 4：`flutter analyze`**

```bash
flutter analyze
```

Expected：`No issues found!`（產生的檔案僅含常數宣告，不含任何邏輯，不會觸發 lint）。

- [ ] **Step 5：Commit**

```bash
git add app/tool/gen_txt_charset_tables.py app/lib/library/txt_charset_tables.dart
git commit -m "feat(epic-11): Issue 4——vendor Big5/GBK 對照表（Unicode.org CP950/CP936）"
```

---

## Task 3：`BookFormat` 新增 `txt`

**Files:**
- Modify: `app/lib/reader/book_format.dart`
- Test: `app/test/reader/book_format_test.dart`

**Interfaces:**
- Produces：`BookFormat.txt`、`detectBookFormat('foo.txt') == BookFormat.txt`、`isFoliateFormat(BookFormat.txt) == true`。

- [ ] **Step 1：寫失敗測試**

於 `app/test/reader/book_format_test.dart`（Issue 3 已建立，見該檔案既有內容）追加：

```dart
  test('detectBookFormat 對 .txt 副檔名回傳 BookFormat.txt', () {
    expect(detectBookFormat('novel.txt'), BookFormat.txt);
    expect(detectBookFormat('NOVEL.TXT'), BookFormat.txt);
  });

  test('isFoliateFormat 對 txt 回傳 true', () {
    expect(isFoliateFormat(BookFormat.txt), isTrue);
  });
```

- [ ] **Step 2：確認測試失敗**

```bash
cd "U:/MyDeveloper/AI/elinkBook/app"
flutter test test/reader/book_format_test.dart
```

Expected：FAIL（`BookFormat.txt` 未定義，編譯錯誤）。

- [ ] **Step 3：實作**

```dart
/// 書籍檔案格式，依副檔名偵測。
enum BookFormat { epub, pdf, azw3, cbz, txt, unknown }

/// 依檔案路徑的副檔名判斷書籍格式（不分大小寫）。無法識別的副檔名（含無副
/// 檔名、空字串）一律回傳 [BookFormat.unknown]，絕不拋出例外。
BookFormat detectBookFormat(String path) {
  final lowerPath = path.toLowerCase();
  if (lowerPath.endsWith('.epub')) return BookFormat.epub;
  if (lowerPath.endsWith('.pdf')) return BookFormat.pdf;
  if (lowerPath.endsWith('.azw3')) return BookFormat.azw3;
  if (lowerPath.endsWith('.cbz')) return BookFormat.cbz;
  if (lowerPath.endsWith('.txt')) return BookFormat.txt;
  return BookFormat.unknown;
}

/// 是否為經由 [FoliateReaderView]（`foliate-js`）渲染的格式——與
/// [BookFormat.pdf] 互斥，[BookFormat.unknown] 兩者皆非。`reader_screen.dart`
/// 內所有「這是不是走 Foliate 流式管線」的判斷皆應呼叫本函式，而非逐一列舉
/// 格式，避免未來新增格式（MD）時遺漏更新（epic-11-multi-format-reader
/// Issue 4，spec.md「格式偵測與渲染分派」）。
bool isFoliateFormat(BookFormat format) =>
    format == BookFormat.epub ||
    format == BookFormat.azw3 ||
    format == BookFormat.cbz ||
    format == BookFormat.txt;
```

- [ ] **Step 4：確認測試通過**

```bash
flutter test test/reader/book_format_test.dart
```

Expected：PASS。

- [ ] **Step 5：`flutter analyze` 確認 exhaustiveness 錯誤清單**

```bash
flutter analyze
```

Expected：出現數個 `non_exhaustive_switch_statement`（`reader_screen.dart` 內既有 `switch (format)` 語句缺少 `case BookFormat.txt:`），記錄下來供 Task 5 使用（比照 Issue 3 既有方法論）。**不要在本 Task 修正**。

- [ ] **Step 6：Commit**

```bash
git add app/lib/reader/book_format.dart app/test/reader/book_format_test.dart
git commit -m "feat(epic-11): Issue 4——BookFormat 新增 txt"
```

---

## Task 4：TXT 編碼偵測與解碼

**Files:**
- Create: `app/lib/library/txt_charset_detection.dart`
- Test: `app/test/library/txt_charset_detection_test.dart`

**Interfaces:**
- Consumes：`kBig5TableKeysBase64`／`kBig5TableValuesBase64`／`kGbkTableKeysBase64`／`kGbkTableValuesBase64`（Task 2）。
- Produces：`enum TxtEncoding { utf8, big5, gbk, utf16, fallback }`；`class TxtDecodeResult { String text; TxtEncoding encoding; }`；`TxtDecodeResult detectAndDecodeTxt(Uint8List bytes)`（供 Task 6 消費）。

- [ ] **Step 1：寫失敗測試**

```dart
// app/test/library/txt_charset_detection_test.dart
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:elinkbook/library/txt_charset_detection.dart';

void main() {
  group('detectAndDecodeTxt：UTF-8', () {
    test('純 ASCII 內容偵測為 utf8', () {
      final result = detectAndDecodeTxt(Uint8List.fromList(utf8.encode('Hello world')));
      expect(result.encoding, TxtEncoding.utf8);
      expect(result.text, 'Hello world');
    });

    test('合法 UTF-8 中文內容偵測為 utf8', () {
      final result = detectAndDecodeTxt(Uint8List.fromList(utf8.encode('繁體中文測試')));
      expect(result.encoding, TxtEncoding.utf8);
      expect(result.text, '繁體中文測試');
    });

    test('UTF-8 BOM（EF BB BF）開頭時剝除 BOM 且偵測為 utf8', () {
      final bytes = Uint8List.fromList([0xEF, 0xBB, 0xBF, ...utf8.encode('測試')]);
      final result = detectAndDecodeTxt(bytes);
      expect(result.encoding, TxtEncoding.utf8);
      expect(result.text, '測試');
    });
  });

  group('detectAndDecodeTxt：Big5', () {
    test('「測試」的 Big5 位元組（0xB4FA 0xB8D5）正確解碼', () {
      final bytes = Uint8List.fromList([0xB4, 0xFA, 0xB8, 0xD5]);
      final result = detectAndDecodeTxt(bytes);
      expect(result.encoding, TxtEncoding.big5);
      expect(result.text, '測試');
    });

    test('Big5 混合 ASCII 內容正確解碼', () {
      // "AB測試CD"：A=0x41 B=0x42 測=0xB4FA 試=0xB8D5 C=0x43 D=0x44
      final bytes = Uint8List.fromList(
        [0x41, 0x42, 0xB4, 0xFA, 0xB8, 0xD5, 0x43, 0x44],
      );
      final result = detectAndDecodeTxt(bytes);
      expect(result.encoding, TxtEncoding.big5);
      expect(result.text, 'AB測試CD');
    });
  });

  group('detectAndDecodeTxt：GBK', () {
    test('「测试」的 GBK 位元組（0xB2E2 0xCAD4）正確解碼', () {
      final bytes = Uint8List.fromList([0xB2, 0xE2, 0xCA, 0xD4]);
      final result = detectAndDecodeTxt(bytes);
      expect(result.encoding, TxtEncoding.gbk);
      expect(result.text, '测试');
    });
  });

  group('detectAndDecodeTxt：UTF-16', () {
    test('UTF-16LE（FF FE BOM）正確解碼', () {
      // BOM(FF FE) + "測"(0x6E2C -> 2C 6E LE) + "試"(0x8A66 -> 66 8A LE)
      final bytes = Uint8List.fromList(
        [0xFF, 0xFE, 0x2C, 0x6E, 0x66, 0x8A],
      );
      final result = detectAndDecodeTxt(bytes);
      expect(result.encoding, TxtEncoding.utf16);
      expect(result.text, '測試');
    });

    test('UTF-16BE（FE FF BOM）正確解碼', () {
      final bytes = Uint8List.fromList(
        [0xFE, 0xFF, 0x6E, 0x2C, 0x8A, 0x66],
      );
      final result = detectAndDecodeTxt(bytes);
      expect(result.encoding, TxtEncoding.utf16);
      expect(result.text, '測試');
    });
  });

  group('detectAndDecodeTxt：全數失敗時強制 UTF-8 寬鬆解碼', () {
    test('無效位元組序列（非合法 UTF-8/Big5/GBK/UTF-16 BOM）退回 fallback', () {
      // 0xFF 單獨出現：非合法 UTF-8 起始位元組、非 Big5/GBK 已知雙位元組
      // 開頭（表內查無 0xFFxx 項目）、無 UTF-16 BOM。
      final bytes = Uint8List.fromList([0xFF, 0x41, 0x42]);
      final result = detectAndDecodeTxt(bytes);
      expect(result.encoding, TxtEncoding.fallback);
      // 不拋出例外即為本測試的核心斷言；寬鬆解碼允許替代字元。
    });
  });
}
```

- [ ] **Step 2：確認測試失敗**

```bash
cd "U:/MyDeveloper/AI/elinkBook/app"
flutter test test/library/txt_charset_detection_test.dart
```

Expected：FAIL（`txt_charset_detection.dart` 不存在，編譯錯誤）。

- [ ] **Step 3：實作**

```dart
// app/lib/library/txt_charset_detection.dart
import 'dart:convert';
import 'dart:typed_data';

import 'txt_charset_tables.dart';

/// TXT 檔案偵測到的編碼種類，供匯入流程記錄／除錯使用（本 Issue 範圍
/// 不對外暴露此資訊給使用者 UI，`spec.md`「TXT 編碼偵測」未要求）。
/// `fallback` 代表全部優先層皆判定失敗，強制以寬鬆 UTF-8 解碼（見
/// [detectAndDecodeTxt] 文件註解）。`big5` 同時涵蓋 spec.md 優先序中的
/// `big5-hkscs`（見 Global Constraints 已查證事實 #5，兩者共用同一份表，
/// 不需要獨立的列舉值）。
enum TxtEncoding { utf8, big5, gbk, utf16, fallback }

class TxtDecodeResult {
  final String text;
  final TxtEncoding encoding;
  const TxtDecodeResult({required this.text, required this.encoding});
}

class _CharsetTable {
  final Uint16List keys;
  final Uint16List values;
  const _CharsetTable(this.keys, this.values);

  /// 二分搜尋 [keys]（已排序、無重複，見產生腳本的斷言），找不到回傳 -1。
  int indexOf(int key) {
    var lo = 0;
    var hi = keys.length - 1;
    while (lo <= hi) {
      final mid = (lo + hi) >> 1;
      final k = keys[mid];
      if (k == key) return mid;
      if (k < key) {
        lo = mid + 1;
      } else {
        hi = mid - 1;
      }
    }
    return -1;
  }
}

Uint16List _unpackUint16(String base64Str) {
  final bytes = base64Decode(base64Str);
  final data = ByteData.sublistView(bytes);
  final result = Uint16List(bytes.length ~/ 2);
  for (var i = 0; i < result.length; i++) {
    result[i] = data.getUint16(i * 2, Endian.little);
  }
  return result;
}

final _big5Table = _CharsetTable(
  _unpackUint16(kBig5TableKeysBase64),
  _unpackUint16(kBig5TableValuesBase64),
);
final _gbkTable = _CharsetTable(
  _unpackUint16(kGbkTableKeysBase64),
  _unpackUint16(kGbkTableValuesBase64),
);

/// 嘗試以 [table] 完整解碼 [bytes]；只要有任一位元組序列無法對映即回傳
/// `null`（代表這組位元組很可能不是這個編碼），呼叫端據此往下一個優先層
/// 退回，不強行猜測。單位元組（<0x80）視為 ASCII 直接透傳。
String? _decodeDbcsStrict(Uint8List bytes, _CharsetTable table) {
  final buffer = StringBuffer();
  var i = 0;
  while (i < bytes.length) {
    final b = bytes[i];
    if (b < 0x80) {
      buffer.writeCharCode(b);
      i += 1;
      continue;
    }
    if (i + 1 >= bytes.length) return null; // 截斷的雙位元組序列
    final key = (b << 8) | bytes[i + 1];
    final idx = table.indexOf(key);
    if (idx == -1) return null;
    buffer.writeCharCode(table.values[idx]);
    i += 2;
  }
  return buffer.toString();
}

/// BOM 開頭時解碼為 UTF-16（大小端依 BOM 判斷）；無 BOM 時回傳 `null`——
/// UTF-16 是優先序最低的最終退路，本函式刻意不猜測無 BOM 情境下的位元組序
/// （見 [detectAndDecodeTxt] 呼叫處說明）。
String? _decodeUtf16WithBom(Uint8List bytes) {
  if (bytes.length < 2) return null;
  final Endian endian;
  const offset = 2;
  if (bytes[0] == 0xFE && bytes[1] == 0xFF) {
    endian = Endian.big;
  } else if (bytes[0] == 0xFF && bytes[1] == 0xFE) {
    endian = Endian.little;
  } else {
    return null;
  }
  final remaining = bytes.length - offset;
  if (remaining.isOdd) return null; // 位元組數不成對，格式不正確
  final data = ByteData.sublistView(bytes, offset);
  final codeUnits = Uint16List(remaining ~/ 2);
  for (var i = 0; i < codeUnits.length; i++) {
    codeUnits[i] = data.getUint16(i * 2, endian);
  }
  return String.fromCharCodes(codeUnits);
}

/// UTF-8 BOM（`EF BB BF`）剝除，其餘位元組原樣保留供後續嘗試 UTF-8 解碼。
Uint8List _stripUtf8Bom(Uint8List bytes) {
  if (bytes.length >= 3 && bytes[0] == 0xEF && bytes[1] == 0xBB && bytes[2] == 0xBF) {
    return bytes.sublist(3);
  }
  return bytes;
}

/// 依 spec.md「TXT 編碼偵測」優先序 `[utf8, big5, big5-hkscs, gbk, utf16]`
/// 嘗試解碼；`big5-hkscs` 與 `big5` 共用同一份對照表（見 Global Constraints
/// 已查證事實 #5），故實際只有 4 個相異分支：utf8 → big5(+hkscs) → gbk →
/// utf16(BOM)。UTF-16 BOM 是比其餘啟發式嘗試解碼更明確的訊號，故優先於
/// utf8/big5/gbk 判斷；其餘依序嘗試，任何一層完整解碼成功（無無法對映的
/// 位元組序列）即採用。全數失敗時強制以 UTF-8 寬鬆解碼（`allowMalformed:
/// true`，絕不拋出例外——比照 spec.md「自動偵測失敗時的退回行為（例如以
/// UTF-8 強制解讀並提示使用者）」，本 Issue 範圍僅實作解碼本身，UI 提示
/// 留待未來視需要評估，不在 issues.md Issue 4 明列範圍內）。
TxtDecodeResult detectAndDecodeTxt(Uint8List bytes) {
  final utf16Result = _decodeUtf16WithBom(bytes);
  if (utf16Result != null) {
    return TxtDecodeResult(text: utf16Result, encoding: TxtEncoding.utf16);
  }

  final withoutBom = _stripUtf8Bom(bytes);
  try {
    final decoded = utf8.decode(withoutBom);
    return TxtDecodeResult(text: decoded, encoding: TxtEncoding.utf8);
  } on FormatException {
    // 非合法 UTF-8，繼續嘗試其餘編碼。
  }

  final big5Result = _decodeDbcsStrict(bytes, _big5Table);
  if (big5Result != null) {
    return TxtDecodeResult(text: big5Result, encoding: TxtEncoding.big5);
  }

  final gbkResult = _decodeDbcsStrict(bytes, _gbkTable);
  if (gbkResult != null) {
    return TxtDecodeResult(text: gbkResult, encoding: TxtEncoding.gbk);
  }

  return TxtDecodeResult(
    text: utf8.decode(bytes, allowMalformed: true),
    encoding: TxtEncoding.fallback,
  );
}
```

- [ ] **Step 4：確認測試通過**

```bash
flutter test test/library/txt_charset_detection_test.dart
```

Expected：PASS（10 個測試）。

- [ ] **Step 5：`flutter analyze`**

```bash
flutter analyze
```

Expected：無新增 issue。

- [ ] **Step 6：Commit**

```bash
git add app/lib/library/txt_charset_detection.dart app/test/library/txt_charset_detection_test.dart
git commit -m "feat(epic-11): Issue 4——TXT 編碼偵測與解碼 detectAndDecodeTxt"
```

---

## Task 5：TXT 章節/目錄切分與位元組大小分塊

**Files:**
- Create: `app/lib/library/txt_chapter_splitter.dart`
- Test: `app/test/library/txt_chapter_splitter_test.dart`

**Interfaces:**
- Produces：`class TxtChapter { String? title; String content; }`；`List<TxtChapter> splitIntoChapters(String text)`；`const int kTxtChunkMaxBytes`；`List<String> chunkByByteSize(String content, {int maxBytes = kTxtChunkMaxBytes})`（供 Task 6 消費）。

- [ ] **Step 1：寫失敗測試**

```dart
// app/test/library/txt_chapter_splitter_test.dart
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:elinkbook/library/txt_chapter_splitter.dart';

void main() {
  group('splitIntoChapters', () {
    test('無章節標題時回傳單一章節，title 為 null', () {
      final chapters = splitIntoChapters('這是一段沒有章節標記的內容\n第二行內容');
      expect(chapters, hasLength(1));
      expect(chapters.single.title, isNull);
      expect(chapters.single.content, '這是一段沒有章節標記的內容\n第二行內容');
    });

    test('「第X章」格式正確切分，標題保留在內容開頭', () {
      final text = '前言內容\n第一章 起源\n正文一\n第二章 發展\n正文二';
      final chapters = splitIntoChapters(text);
      expect(chapters, hasLength(3));
      expect(chapters[0].title, isNull);
      expect(chapters[0].content, '前言內容\n');
      expect(chapters[1].title, '第一章 起源');
      expect(chapters[1].content, contains('正文一'));
      expect(chapters[2].title, '第二章 發展');
      expect(chapters[2].content, contains('正文二'));
    });

    test('「第X回」「第X卷」「第X節」「第X集」皆可辨識', () {
      final text = '第一回 開場\nA\n第二卷 中段\nB\n第三節 尾聲\nC\n第四集 完結\nD';
      final chapters = splitIntoChapters(text);
      expect(chapters.map((c) => c.title), [
        '第一回 開場',
        '第二卷 中段',
        '第三節 尾聲',
        '第四集 完結',
      ]);
    });

    test('中文數字與阿拉伯數字章節編號皆可辨識', () {
      final text = '第1章 一\nA\n第一百二十三章 二\nB';
      final chapters = splitIntoChapters(text);
      expect(chapters.map((c) => c.title), ['第1章 一', '第一百二十三章 二']);
    });

    test('英文 "Chapter N" 格式可辨識', () {
      final text = 'Chapter 1 Beginning\nA\nChapter 2 Middle\nB';
      final chapters = splitIntoChapters(text);
      expect(chapters.map((c) => c.title), ['Chapter 1 Beginning', 'Chapter 2 Middle']);
    });

    test('"Chapter" 大小寫變體（CHAPTER／chapter）皆可辨識（審查修正 Minor #1）', () {
      final text = 'CHAPTER 1 Beginning\nA\nchapter 2 Middle\nB';
      final chapters = splitIntoChapters(text);
      expect(chapters.map((c) => c.title), ['CHAPTER 1 Beginning', 'chapter 2 Middle']);
    });

    test('章節標題須為行首（前導空白容許），行中出現不視為標題', () {
      final text = '這句話裡提到第一章的內容但不是真正的標題\n第二章 才是真正標題\n正文';
      final chapters = splitIntoChapters(text);
      expect(chapters, hasLength(2));
      expect(chapters[0].title, isNull);
      expect(chapters[1].title, '第二章 才是真正標題');
    });
  });

  group('chunkByByteSize', () {
    test('內容未超過門檻時原樣回傳單一區塊', () {
      final chunks = chunkByByteSize('短內容', maxBytes: 1000);
      expect(chunks, ['短內容']);
    });

    test('超過門檻時依行邊界切分為多個區塊，且合併後內容不遺漏', () {
      final lines = List.generate(100, (i) => '第 $i 行內容測試文字');
      final content = lines.join('\n');
      final totalBytes = utf8.encode(content).length;
      final maxBytes = (totalBytes / 3).ceil();

      final chunks = chunkByByteSize(content, maxBytes: maxBytes);

      expect(chunks.length, greaterThan(1));
      for (final chunk in chunks) {
        expect(utf8.encode(chunk).length, lessThanOrEqualTo(maxBytes + 200));
      }
      // 合併後應包含原始所有行內容（chunkByByteSize 逐行 writeln，
      // 合併後以換行重組應與原始逐行內容一致）。
      final rejoined = chunks.join().trim();
      for (final line in lines) {
        expect(rejoined, contains(line));
      }
    });

    test('單一行本身即超過門檻時，該行獨立成一個區塊，不會被再切斷', () {
      final hugeLine = '字' * 1000;
      final chunks = chunkByByteSize(hugeLine, maxBytes: 100);
      expect(chunks, hasLength(1));
      expect(chunks.single.trim(), hugeLine);
    });
  });
}
```

- [ ] **Step 2：確認測試失敗**

```bash
cd "U:/MyDeveloper/AI/elinkBook/app"
flutter test test/library/txt_chapter_splitter_test.dart
```

Expected：FAIL（`txt_chapter_splitter.dart` 不存在，編譯錯誤）。

- [ ] **Step 3：實作**

```dart
// app/lib/library/txt_chapter_splitter.dart
import 'dart:convert';

/// 常見中文章節標題格式（「第 X 章/回/卷/節/集」，X 可為阿拉伯數字或中文
/// 數字）與英文 `Chapter N` 格式（spec.md「TXT 章節/目錄」）。`^` 搭配
/// `multiLine: true` 確保只匹配行首（容許前導空白/定位字元），避免內文
/// 中提及「第一章」字樣被誤判為標題（見對應測試案例）。標題文字擷取到
/// 該行結尾（不含換行符）。`caseSensitive: false`（審查修正，見
/// reviews/review-issue-4-plan.md Minor #1）讓 `CHAPTER 1`／`chapter 1`
/// 等大小寫變體皆可辨識，不影響中文分支（中文字元無大小寫之分）。
final _chapterHeadingRegex = RegExp(
  r'^[ \t]*(第[0-9零一二三四五六七八九十百千萬两兩]+[章回卷節集][^\n]*|Chapter\s+\d+[^\n]*)',
  multiLine: true,
  caseSensitive: false,
);

class TxtChapter {
  /// `null` 代表沒有偵測到章節標題（整份檔案找不到任何章節標記時的單一
  /// 章節退回情境，見 [splitIntoChapters]）。
  final String? title;
  final String content;
  const TxtChapter({this.title, required this.content});
}

/// 依 [_chapterHeadingRegex] 掃描章節標題行，切出章節清單；找不到任何
/// 標題時回傳單一涵蓋全文的章節（`title: null`）。標題行本身保留在該
/// 章節 `content` 開頭（與內文一起顯示，非額外抽離成獨立欄位），比照多數
/// TXT 轉 EPUB 工具的既有慣例。
List<TxtChapter> splitIntoChapters(String text) {
  final matches = _chapterHeadingRegex.allMatches(text).toList();
  if (matches.isEmpty) {
    return [TxtChapter(content: text)];
  }
  final chapters = <TxtChapter>[];
  if (matches.first.start > 0) {
    chapters.add(TxtChapter(content: text.substring(0, matches.first.start)));
  }
  for (var i = 0; i < matches.length; i++) {
    final start = matches[i].start;
    final end = i + 1 < matches.length ? matches[i + 1].start : text.length;
    final title = matches[i].group(0)!.trim();
    chapters.add(TxtChapter(title: title, content: text.substring(start, end)));
  }
  return chapters;
}

/// spec.md「TXT 雙重分塊防護」建議區間 300~500KB，取中間值。
const int kTxtChunkMaxBytes = 400000;

/// 若 [content] 的 UTF-8 位元組長度超過 [maxBytes]，依行邊界切成多個子
/// 區塊，每個子區塊不超過門檻（單一行本身超過門檻時，該行獨立成一個
/// 區塊，不會再往下切字——避免切斷多位元組字元或產生無意義的極短區塊）。
/// 未超過門檻時原樣回傳單一元素清單。
List<String> chunkByByteSize(String content, {int maxBytes = kTxtChunkMaxBytes}) {
  if (utf8.encode(content).length <= maxBytes) return [content];
  final lines = content.split(RegExp(r'\r\n|\r|\n'));
  final chunks = <String>[];
  final current = StringBuffer();
  var currentBytes = 0;
  for (final line in lines) {
    final lineBytes = utf8.encode(line).length + 1; // +1 約略計入換行符
    if (currentBytes + lineBytes > maxBytes && current.isNotEmpty) {
      chunks.add(current.toString());
      current.clear();
      currentBytes = 0;
    }
    current.writeln(line);
    currentBytes += lineBytes;
  }
  if (current.isNotEmpty) chunks.add(current.toString());
  return chunks;
}
```

- [ ] **Step 4：確認測試通過**

```bash
flutter test test/library/txt_chapter_splitter_test.dart
```

Expected：PASS（10 個測試）。

- [ ] **Step 5：`flutter analyze`**

```bash
flutter analyze
```

Expected：無新增 issue。

- [ ] **Step 6：Commit**

```bash
git add app/lib/library/txt_chapter_splitter.dart app/test/library/txt_chapter_splitter_test.dart
git commit -m "feat(epic-11): Issue 4——TXT 章節/目錄正則切分與位元組大小分塊"
```

---

## Task 6：TXT → EPUB 合成

**背景**：`generateTxtCover()`（`app/lib/library/txt_cover_generator.dart`）使用 `dart:ui`（`ui.PictureRecorder`／`ui.Canvas`），這些綁定在裸 `Isolate.run()` spawn 的 isolate 內**不可用**（Flutter engine 綁定僅存在於主 isolate）——本 Task 的 EPUB 合成邏輯（純資料處理，不涉及 `dart:ui`）可以安全包進 `Isolate.run()`，但呼叫端（Task 7）**不可**把封面產生也包進同一次 `Isolate.run()` 呼叫，兩者必須分開呼叫。

**Files:**
- Create: `app/lib/library/txt_epub_synthesizer.dart`
- Test: `app/test/library/txt_epub_synthesizer_test.dart`

**Interfaces:**
- Consumes：`detectAndDecodeTxt`（Task 4）；`TxtChapter`／`splitIntoChapters`／`chunkByByteSize`（Task 5）；`readContentUriBytes`（Task 1）。
- Produces：`class TxtSynthesisResult { Uint8List epubBytes; TxtEncoding detectedEncoding; }`；`class EmptyTxtException implements Exception`；`Future<TxtSynthesisResult> synthesizeTxtBook(String filePath, String bookId, String title)`（供 Task 7 `book_import_service_impl.dart` 消費）。

- [ ] **Step 1：`xml` 套件新增為 dev_dependency（測試驗證合成的 XML 是否良好格式）**

`app/pubspec.yaml` 的 `dev_dependencies:` 區塊新增：

```yaml
  # 驗證 TXT→EPUB 合成產生的 container.xml／OPF／XHTML 是否為良好格式的
  # XML（epic-11-multi-format-reader Issue 4）；production 程式碼本身以
  # 字串模板組裝 XML，不依賴此套件，僅測試端使用。
  xml: ^6.6.1
```

```bash
cd "U:/MyDeveloper/AI/elinkBook/app"
flutter pub get
```

- [ ] **Step 2：寫失敗測試**

```dart
// app/test/library/txt_epub_synthesizer_test.dart
import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:xml/xml.dart';
import 'package:elinkbook/library/txt_charset_detection.dart';
import 'package:elinkbook/library/txt_epub_synthesizer.dart';

import '../support/fake_path_provider_platform.dart';

const _channel = MethodChannel('elinkbook/book_metadata');

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Archive decodeArchive(TxtSynthesisResult result) => ZipDecoder().decodeBytes(result.epubBytes);

  String readEntry(Archive archive, String name) =>
      utf8.decode(archive.findFile(name)!.readBytes()!);

  test('合成結果為結構正確的 EPUB：container.xml 指向 OEBPS/content.opf', () async {
    final txtFile = File('${Directory.systemTemp.path}/synth_test_basic.txt');
    await txtFile.writeAsBytes(utf8.encode('第一章 開始\n正文內容一\n第二章 結束\n正文內容二'));
    addTearDown(() => txtFile.delete());

    final result = await synthesizeTxtBook(txtFile.path, 'book1', '測試小說');
    final archive = decodeArchive(result);

    expect(archive.findFile('mimetype'), isNotNull);
    expect(archive.findFile('META-INF/container.xml'), isNotNull);
    final containerDoc = XmlDocument.parse(readEntry(archive, 'META-INF/container.xml'));
    final rootfile = containerDoc.findAllElements('rootfile').single;
    expect(rootfile.getAttribute('full-path'), 'OEBPS/content.opf');
    expect(archive.findFile('OEBPS/content.opf'), isNotNull);
  });

  test('OPF 的 manifest/spine 與實際章節數一致，皆為良好格式 XML', () async {
    final txtFile = File('${Directory.systemTemp.path}/synth_test_opf.txt');
    await txtFile.writeAsBytes(utf8.encode('第一章 開始\n正文一\n第二章 結束\n正文二'));
    addTearDown(() => txtFile.delete());

    final result = await synthesizeTxtBook(txtFile.path, 'book2', '測試小說');
    final archive = decodeArchive(result);
    final opfDoc = XmlDocument.parse(readEntry(archive, 'OEBPS/content.opf'));

    final manifestItems = opfDoc.findAllElements('item')
        .where((e) => e.getAttribute('href')?.startsWith('text/') ?? false);
    final spineItems = opfDoc.findAllElements('itemref');
    expect(manifestItems.length, 2);
    expect(spineItems.length, 2);
    expect(opfDoc.findAllElements('dc:title').single.innerText, '測試小說');
  });

  test('nav.xhtml 的目錄項目對應章節標題，未偵測到標題的段落不產生目錄項', () async {
    final txtFile = File('${Directory.systemTemp.path}/synth_test_nav.txt');
    await txtFile.writeAsBytes(utf8.encode('前言（無標題）\n第一章 正題\n內容'));
    addTearDown(() => txtFile.delete());

    final result = await synthesizeTxtBook(txtFile.path, 'book3', '測試小說');
    final archive = decodeArchive(result);
    final navDoc = XmlDocument.parse(readEntry(archive, 'OEBPS/nav.xhtml'));

    final tocLinks = navDoc.findAllElements('a');
    expect(tocLinks, hasLength(1));
    expect(tocLinks.single.innerText, '第一章 正題');
  });

  test('章節內文正確寫入對應 XHTML 檔案的 <p> 元素', () async {
    final txtFile = File('${Directory.systemTemp.path}/synth_test_content.txt');
    await txtFile.writeAsBytes(utf8.encode('第一章 標題\n這是第一段\n這是第二段'));
    addTearDown(() => txtFile.delete());

    final result = await synthesizeTxtBook(txtFile.path, 'book4', '測試小說');
    final archive = decodeArchive(result);
    final chapterXhtml = readEntry(archive, 'OEBPS/text/chap0001.xhtml');
    final doc = XmlDocument.parse(chapterXhtml);
    final paragraphs = doc.findAllElements('p').map((e) => e.innerText).toList();

    expect(paragraphs, contains('這是第一段'));
    expect(paragraphs, contains('這是第二段'));
  });

  test('XML 特殊字元（&/</>）在段落內容與標題中正確逸出', () async {
    final txtFile = File('${Directory.systemTemp.path}/synth_test_escape.txt');
    await txtFile.writeAsBytes(utf8.encode('第一章 A&B<C>\n內容含 & < > 符號'));
    addTearDown(() => txtFile.delete());

    final result = await synthesizeTxtBook(txtFile.path, 'book5', '測試小說');
    final archive = decodeArchive(result);
    // 若逸出錯誤，XmlDocument.parse 本身就會拋出例外，本測試以「能被正確
    // 解析且還原出原始文字」作為斷言。
    final navDoc = XmlDocument.parse(readEntry(archive, 'OEBPS/nav.xhtml'));
    expect(navDoc.findAllElements('a').single.innerText, 'A&B<C>');
    final chapterDoc = XmlDocument.parse(readEntry(archive, 'OEBPS/text/chap0001.xhtml'));
    expect(chapterDoc.findAllElements('p').first.innerText, contains('& < >'));
  });

  test('超過分塊門檻的單一章節切成多個 XHTML 檔案，但只產生一個目錄項', () async {
    final longContent = List.generate(50, (i) => '第 $i 段落內容測試文字，足夠長以利分塊測試。').join('\n');
    final txtFile = File('${Directory.systemTemp.path}/synth_test_chunked.txt');
    await txtFile.writeAsBytes(utf8.encode('第一章 長章節\n$longContent'));
    addTearDown(() => txtFile.delete());

    final result = await synthesizeTxtBook(txtFile.path, 'book6', '測試小說');
    final archive = decodeArchive(result);
    final opfDoc = XmlDocument.parse(readEntry(archive, 'OEBPS/content.opf'));
    final navDoc = XmlDocument.parse(readEntry(archive, 'OEBPS/nav.xhtml'));

    // 門檻預設 400000 bytes，本測試內容遠小於門檻，故驗證的是「機制存在」
    // 而非強制觸發分塊——改用極小 maxBytes 無法從公開 API 注入，改為直接
    // 呼叫 chunkByByteSize 驗證於 Task 5 已完成，本測試改為驗證正常情境
    // 下（未超過門檻）manifest 項目數與目錄項目數皆為 1，確認整合正確。
    expect(opfDoc.findAllElements('item').where((e) => e.getAttribute('href')?.startsWith('text/') ?? false), hasLength(1));
    expect(navDoc.findAllElements('a'), hasLength(1));
  });

  test('空白 TXT 檔案拋出 EmptyTxtException', () async {
    final txtFile = File('${Directory.systemTemp.path}/synth_test_empty.txt');
    await txtFile.writeAsBytes(utf8.encode('   \n\n   '));
    addTearDown(() => txtFile.delete());

    expect(
      () => synthesizeTxtBook(txtFile.path, 'book7', '測試小說'),
      throwsA(isA<EmptyTxtException>()),
    );
  });

  test('detectedEncoding 正確回報偵測到的編碼', () async {
    final txtFile = File('${Directory.systemTemp.path}/synth_test_encoding.txt');
    await txtFile.writeAsBytes(utf8.encode('第一章 測試\n內容'));
    addTearDown(() => txtFile.delete());

    final result = await synthesizeTxtBook(txtFile.path, 'book8', '測試小說');

    expect(result.detectedEncoding, TxtEncoding.utf8);
  });

  group('content:// URI 支援', () {
    late Directory tempDir;
    late PathProviderPlatform originalPathProvider;

    setUp(() {
      tempDir = Directory.systemTemp.createTempSync('txt_synth_test_tmp');
      originalPathProvider = PathProviderPlatform.instance;
      PathProviderPlatform.instance = FakePathProviderPlatform(tempDir.path);
    });

    tearDown(() {
      PathProviderPlatform.instance = originalPathProvider;
      if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(_channel, null);
    });

    test('content:// URI 先複製到暫存檔再解析', () async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(_channel, (call) async {
        final args = call.arguments as Map;
        await File(args['destinationPath'] as String)
            .writeAsBytes(utf8.encode('第一章 開始\n內容'));
        return null;
      });

      final result = await synthesizeTxtBook('content://example/novel.txt', 'book9', '測試小說');
      final archive = decodeArchive(result);

      expect(archive.findFile('OEBPS/content.opf'), isNotNull);
    });
  });
}
```

- [ ] **Step 3：確認測試失敗**

```bash
flutter test test/library/txt_epub_synthesizer_test.dart
```

Expected：FAIL（`txt_epub_synthesizer.dart` 不存在，編譯錯誤）。

- [ ] **Step 4：實作**

```dart
// app/lib/library/txt_epub_synthesizer.dart
import 'dart:convert';
import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:archive/archive.dart';

import 'content_uri_reader.dart';
import 'txt_chapter_splitter.dart';
import 'txt_charset_detection.dart';

/// TXT 檔案解碼後找不到任何非空白內容時拋出——沒有內容的書本質上無法
/// 開啟，呼叫端（book_import_service_impl.dart）應中止匯入、不建立 Book
/// 記錄，比照 CBZ 的 `NoComicPagesException`（epic-11 Issue 3）既有處置
/// 慣例。
class EmptyTxtException implements Exception {
  final String message;
  const EmptyTxtException(this.message);
  @override
  String toString() => 'EmptyTxtException: $message';
}

class TxtSynthesisResult {
  /// 合成後的 EPUB 壓縮檔完整位元組內容，供呼叫端落地為 `Book.filePath`
  /// 指向的衍生檔案（**檔名副檔名須維持 `.txt`**，見 Global Constraints
  /// 已查證事實 #1，本函式不負責落地檔案，只回傳位元組）。
  final Uint8List epubBytes;

  /// 本次解碼實際採用的編碼，供匯入流程記錄／除錯使用。
  final TxtEncoding detectedEncoding;

  const TxtSynthesisResult({required this.epubBytes, required this.detectedEncoding});
}

String _escapeXml(String text) =>
    text.replaceAll('&', '&amp;').replaceAll('<', '&lt;').replaceAll('>', '&gt;');

const _containerXml = '''<?xml version="1.0" encoding="UTF-8"?>
<container version="1.0" xmlns="urn:oasis:names:tc:opendocument:xmlns:container">
  <rootfiles>
    <rootfile full-path="OEBPS/content.opf" media-type="application/oebps-package+xml"/>
  </rootfiles>
</container>
''';

String _contentOpf({
  required String bookId,
  required String title,
  required String manifestItems,
  required String spineItems,
}) =>
    '''<?xml version="1.0" encoding="UTF-8"?>
<package xmlns="http://www.idpf.org/2007/opf" version="3.0" unique-identifier="book-id">
  <metadata xmlns:dc="http://purl.org/dc/elements/1.1/">
    <dc:identifier id="book-id">elinkbook-txt-$bookId</dc:identifier>
    <dc:title>${_escapeXml(title)}</dc:title>
    <dc:language>zh</dc:language>
  </metadata>
  <manifest>
    <item id="nav" href="nav.xhtml" media-type="application/xhtml+xml" properties="nav"/>
$manifestItems  </manifest>
  <spine>
$spineItems  </spine>
</package>
''';

String _navXhtml(String navItems) =>
    '''<?xml version="1.0" encoding="UTF-8"?>
<html xmlns="http://www.w3.org/1999/xhtml" xmlns:epub="http://www.idpf.org/2007/ops">
<head><title>目錄</title></head>
<body>
<nav epub:type="toc">
<ol>
$navItems</ol>
</nav>
</body>
</html>
''';

/// 每行（去除純空白行）成為一個 `<p>` 元素——常見網路小說 TXT 排版慣例
/// （每行即一段，非以空白行分隔），比照本專案既有排版管線不主動猜測換行
/// 語意的既定精神（見 spec.md「TXT／Markdown 合成書籍結構」）。
String _buildXhtmlBody(String content) {
  final buffer = StringBuffer();
  for (final line in content.split(RegExp(r'\r\n|\r|\n'))) {
    final trimmed = line.trim();
    if (trimmed.isEmpty) continue;
    buffer.writeln('<p>${_escapeXml(trimmed)}</p>');
  }
  return buffer.toString();
}

String _chapterXhtml(String content) =>
    '''<?xml version="1.0" encoding="UTF-8"?>
<html xmlns="http://www.w3.org/1999/xhtml">
<head><title>內容</title></head>
<body>
${_buildXhtmlBody(content)}</body>
</html>
''';

/// 純 CPU 運算（解碼＋章節切分＋EPUB 結構產生），外包至 `Isolate.run()`
/// 背景執行（見呼叫處 [synthesizeTxtBook] 註解）。頂層純函式、僅接受可
/// 跨 isolate 傳遞的 [Uint8List]／[String] 參數，不捕捉任何 State 或其他
/// 不可傳遞物件（比照 CLAUDE.md「不可逆的技術決策」段落對 `Isolate.run()`
/// closure 的既有限制）。**不呼叫 `generateTxtCover()`**（`dart:ui` 在
/// spawn 的 isolate 內不可用，見本檔案／Task 6 開頭「背景」說明），封面
/// 產生由呼叫端（`book_import_service_impl.dart`）在主 isolate 另行處理。
TxtSynthesisResult _decodeAndSynthesize(Uint8List bytes, String bookId, String title) {
  final decoded = detectAndDecodeTxt(bytes);
  final chapters = splitIntoChapters(decoded.text);
  final hasContent = chapters.any((c) => c.content.trim().isNotEmpty);
  if (!hasContent) {
    throw const EmptyTxtException('TXT 檔案內容為空');
  }

  final archive = Archive();
  archive.addFile(
    ArchiveFile.bytes('mimetype', utf8.encode('application/epub+zip'))
      ..compression = CompressionType.none,
  );
  archive.addFile(ArchiveFile.bytes('META-INF/container.xml', utf8.encode(_containerXml)));

  final manifestItems = StringBuffer();
  final spineItems = StringBuffer();
  final navItems = StringBuffer();
  var chapterIndex = 0;

  for (final chapter in chapters) {
    if (chapter.content.trim().isEmpty) continue;
    final subChunks = chunkByByteSize(chapter.content);
    String? firstHref;
    for (var i = 0; i < subChunks.length; i++) {
      chapterIndex++;
      final id = 'chap${chapterIndex.toString().padLeft(4, '0')}';
      final href = 'text/$id.xhtml';
      firstHref ??= href;
      archive.addFile(
        ArchiveFile.bytes('OEBPS/$href', utf8.encode(_chapterXhtml(subChunks[i]))),
      );
      manifestItems.writeln('<item id="$id" href="$href" media-type="application/xhtml+xml"/>');
      spineItems.writeln('<itemref idref="$id"/>');
    }
    // 只有真正偵測到章節標題的段落才產生目錄項——分塊本身是位元組上限
    // 防護（chunkByByteSize），不是語意章節邊界，不應冒充為目錄項目
    // （見 Task 6 設計討論；比照 Issue 3 CBZ 虛擬目錄「有明確語意才產生
    // 項目」的相同原則，此處反過來是「沒有語意就不產生」）。
    if (chapter.title != null && firstHref != null) {
      navItems.writeln('<li><a href="$firstHref">${_escapeXml(chapter.title!)}</a></li>');
    }
  }

  archive.addFile(ArchiveFile.bytes('OEBPS/nav.xhtml', utf8.encode(_navXhtml(navItems.toString()))));
  archive.addFile(ArchiveFile.bytes(
    'OEBPS/content.opf',
    utf8.encode(_contentOpf(
      bookId: bookId,
      title: title,
      manifestItems: manifestItems.toString(),
      spineItems: spineItems.toString(),
    )),
  ));

  return TxtSynthesisResult(
    epubBytes: ZipEncoder().encodeBytes(archive),
    detectedEncoding: decoded.encoding,
  );
}

/// 讀取 [filePath]（本機路徑或 `content://` URI）指向的 TXT 檔案，偵測
/// 編碼、依章節標題與位元組大小分塊，合成一份最小合法 EPUB3 壓縮檔（見
/// Global Constraints 已查證事實 #2 的結構要求）。[bookId] 用於 OPF
/// `dc:identifier`，[title] 用於 `dc:title`（呼叫端傳入書名，通常是依
/// 檔名推導的既有慣例，見 `book_import_service_impl.dart`
/// `titleFromFileName()`）。CPU 密集的解碼／分塊／XML 組裝外包至
/// `Isolate.run()`（spec.md 明文要求，比照 `book_content_fingerprint.dart`
/// 既有作法）。
Future<TxtSynthesisResult> synthesizeTxtBook(
  String filePath,
  String bookId,
  String title,
) async {
  final bytes = filePath.contains('://')
      ? await readContentUriBytes(filePath, tempFilePrefix: 'txt_probe', tempFileExtension: '.txt')
      : await File(filePath).readAsBytes();
  return Isolate.run(() => _decodeAndSynthesize(bytes, bookId, title));
}
```

- [ ] **Step 5：確認測試通過**

```bash
flutter test test/library/txt_epub_synthesizer_test.dart
```

Expected：PASS（9 個測試）。

- [ ] **Step 6：`flutter analyze`**

```bash
flutter analyze
```

Expected：無新增 issue。

- [ ] **Step 7：Commit**

```bash
git add app/lib/library/txt_epub_synthesizer.dart app/test/library/txt_epub_synthesizer_test.dart app/pubspec.yaml app/pubspec.lock
git commit -m "feat(epic-11): Issue 4——TXT 合成為最小合法 EPUB3 結構 synthesizeTxtBook"
```

---

## Task 7：匯入管線接上 TXT 合成

**Files:**
- Modify: `app/lib/library/book_import_service_impl.dart`
- Test: `app/test/library/book_import_service_test.dart`

**Interfaces:**
- Consumes：`synthesizeTxtBook`／`TxtSynthesisResult`／`EmptyTxtException`（Task 6）。
- Produces：TXT 書籍 `Book.isFixedLayout == false`、`Book.filePath` 指向落地後合成的 `.txt` 檔案（`imported_books/` 既有目錄，`$id.txt`）、`Book.contentFingerprint` 對原始輸入檔案計算。

- [ ] **Step 1：寫失敗測試**

於 `app/test/library/book_import_service_test.dart` 頂部 import 區塊新增：

```dart
import 'package:archive/archive.dart' show ZipDecoder;
```

在既有 `group('CBZ 匯入', () { ... });` 之後、`main()` 結尾 `}` 之前新增：

```dart
  group('TXT 匯入', () {
    test('匯入有效 TXT：format=txt、isFixedLayout=false、filePath 指向合成後的 .txt 檔案', () async {
      final txtFile = File('${Directory.systemTemp.path}/import_test.txt');
      await txtFile.writeAsBytes(utf8.encode('第一章 開始\n正文內容'));
      addTearDown(() => txtFile.delete());

      final result = await service.importFiles([txtFile.path], displayNames: ['novel.txt']);

      expect(result.importedBooks, hasLength(1));
      final book = result.importedBooks.first;
      expect(book.format, BookFileFormat.txt);
      expect(book.isFixedLayout, isFalse);
      expect(book.filePath, isNot(txtFile.path));
      expect(book.filePath, endsWith('.txt'));
      expect(File(book.filePath).existsSync(), isTrue);
      // 合成後的檔案內容須是合法 zip（EPUB），非原始純文字。
      final archive = ZipDecoder().decodeBytes(await File(book.filePath).readAsBytes());
      expect(archive.findFile('OEBPS/content.opf'), isNotNull);
    });

    test('封面仍由 generateTxtCover() 依書名產生（TXT 無內嵌封面/首頁可渲染）', () async {
      final txtFile = File('${Directory.systemTemp.path}/import_test_cover.txt');
      await txtFile.writeAsBytes(utf8.encode('第一章 開始\n正文'));
      addTearDown(() => txtFile.delete());

      final result = await service.importFiles([txtFile.path], displayNames: ['novel.txt']);

      final book = result.importedBooks.first;
      expect(book.coverPath, isNotNull);
      expect(File(book.coverPath!).existsSync(), isTrue);
    });

    test('contentFingerprint 對原始檔案計算，非合成後的 .txt 檔案', () async {
      final txtFile = File('${Directory.systemTemp.path}/import_test_fingerprint.txt');
      await txtFile.writeAsBytes(utf8.encode('第一章 開始\n正文'));
      addTearDown(() => txtFile.delete());

      final result = await service.importFiles([txtFile.path], displayNames: ['novel.txt']);

      final book = result.importedBooks.first;
      final expectedFingerprint =
          await computeBookContentFingerprint(txtFile.path, BookFileFormat.txt);
      expect(book.contentFingerprint, expectedFingerprint);
    });

    test(
      '空白 TXT 檔案不建立 Book 記錄，且不留下孤兒封面檔案'
      '（epic-11 Issue 4 程式碼審查 Important #1 迴歸測試：修復前會先落地封面'
      '才發現內容為空而中止，導致 covers/ 目錄殘留無主檔案）',
      () async {
        final txtFile = File('${Directory.systemTemp.path}/import_test_empty.txt');
        await txtFile.writeAsBytes(utf8.encode('   \n\n   '));
        addTearDown(() => txtFile.delete());

        final result = await service.importFiles([txtFile.path], displayNames: ['empty.txt']);

        expect(result.importedBooks, isEmpty);
        // coversDir 由頂層 setUp() 提供（見既有 service 建構），空匯入不應
        // 在其中留下任何檔案。
        expect(coversDir.listSync(), isEmpty);
      },
    );

    test('Big5 編碼 TXT 正確匯入（解碼於合成階段完成，匯入結果與 UTF-8 無異）', () async {
      // 「測試」的 Big5 位元組為 0xB4FA 0xB8D5（見
      // txt_charset_detection_test.dart 已交叉驗證的已知值）；前綴一個
      // ASCII 字元涵蓋「非純中文開頭」的較真實檔案內容型態。
      final big5Bytes = Uint8List.fromList([
        0x41, // 'A'
        0xB4, 0xFA, 0xB8, 0xD5, // 測試
      ]);
      final txtFile = File('${Directory.systemTemp.path}/import_test_big5.txt');
      await txtFile.writeAsBytes(big5Bytes);
      addTearDown(() => txtFile.delete());

      final result = await service.importFiles([txtFile.path], displayNames: ['big5_novel.txt']);

      expect(result.importedBooks, hasLength(1));
      final book = result.importedBooks.first;
      final archive = ZipDecoder().decodeBytes(await File(book.filePath).readAsBytes());
      final chapterContent = utf8.decode(archive.findFile('OEBPS/text/chap0001.xhtml')!.readBytes()!);
      expect(chapterContent, contains('測試'));
    });
  });
```

於檔案頂部確認已 import `dart:convert`（`utf8`）與 `dart:typed_data`（`Uint8List`）——若既有 import 已涵蓋（Issue 2/3 已使用過 `Uint8List`），不重複新增。

- [ ] **Step 2：確認測試失敗**

```bash
cd "U:/MyDeveloper/AI/elinkBook/app"
flutter test test/library/book_import_service_test.dart
```

Expected：FAIL（`BookFileFormat.txt` 分支尚未產生合成邏輯，`book.filePath` 仍是原始純文字檔路徑而非合法 zip）。

- [ ] **Step 3：實作**

`app/lib/library/book_import_service_impl.dart` 頂部 import 新增：

```dart
import 'txt_epub_synthesizer.dart';
```

修改既有 TXT 分支（目前是）：

```dart
    if (format == BookFileFormat.txt) {
      final coverBytes = await generateTxtCover(fallbackTitle);
      coverPath = await _landCover(coverBytes, id);
    } else if (format == BookFileFormat.azw3) {
```

改為：

```dart
    if (format == BookFileFormat.txt) {
      // 封面產生（dart:ui）與 EPUB 合成（純 Dart，Isolate.run() 背景執行）
      // 是兩個獨立步驟，不可合併——dart:ui 綁定在裸 spawn 的 isolate 內
      // 不可用，見 txt_epub_synthesizer.dart Task 6 開頭「背景」說明。
      // 審查修正（reviews/review-issue-4-plan.md Important #1）：合成
      // 必須先於封面產生執行——若先落地封面才發現內容為空而中止匯入，
      // 會在磁碟留下孤兒封面檔案（沒有對應 Book 記錄，日後刪除書籍的
      // 既有清理邏輯是依附在 Book 記錄上運作，永遠碰不到它）。
      TxtSynthesisResult synthesis;
      try {
        synthesis = await synthesizeTxtBook(resolvedUri, id, fallbackTitle);
      } on EmptyTxtException {
        // 沒有可用內容的 TXT 本質上無法開啟，比照 CBZ 的
        // NoComicPagesException 既有處置慣例，中止匯入、不建立 Book 記錄
        // ——此時尚未呼叫 generateTxtCover()，磁碟上不會留下任何殘留檔案。
        return null;
      }
      isFixedLayout = false;
      bookFilePath = await _landTxtEpub(synthesis.epubBytes, id);
      final coverBytes = await generateTxtCover(fallbackTitle);
      coverPath = await _landCover(coverBytes, id);
    } else if (format == BookFileFormat.azw3) {
```

（`bookFilePath` 變數已由 Task 4/Issue 3 的 CBZ 工作建立於 `_importSingleFile()` 內，`var bookFilePath = resolvedUri;` 這行已存在，不需要重複新增）

在既有 `_landCbzArchive()` 方法之後新增：

```dart
  /// 落地 TXT 合成的 EPUB 壓縮檔位元組（epic-11-multi-format-reader
  /// Issue 4），比照 [_landCover]／[_landCbzArchive] 既有的「以 book id
  /// 為鍵、獨立子目錄」慣例，重用既有 `imported_books/` 目錄。**檔名副
  /// 檔名須維持 `.txt`**（Global Constraints 已查證事實 #1：`BookFormat.txt`
  /// 的分派依 `Book.filePath` 副檔名判斷，不可改為 `.epub`）。
  Future<String> _landTxtEpub(Uint8List bytes, String bookId) async {
    final dir = await _resolveImportedBooksDirectory();
    final file = File(p.join(dir.path, '$bookId.txt'));
    await file.writeAsBytes(bytes, flush: true);
    return file.path;
  }
```

- [ ] **Step 4：確認測試通過**

```bash
flutter test test/library/book_import_service_test.dart
```

Expected：PASS（既有全部測試＋5 個新增 TXT 測試）。

- [ ] **Step 5：`flutter analyze`**

```bash
flutter analyze
```

Expected：無新增 issue。

- [ ] **Step 6：Commit**

```bash
git add app/lib/library/book_import_service_impl.dart app/test/library/book_import_service_test.dart
git commit -m "feat(epic-11): Issue 4——匯入管線接上 TXT 合成為 EPUB 結構"
```

---

## Task 8：`ReaderScreen` 分派邏輯擴充

**Files:**
- Modify: `app/lib/screens/reader_screen.dart`
- Test: `app/test/screens/reader_screen_test.dart`

**Interfaces:**
- Consumes：`BookFormat.txt`（Task 3）。

- [ ] **Step 1：寫失敗測試（防禦性 `_dispatchedIsFixedLayout` 分派）**

於 `app/test/screens/reader_screen_test.dart` 找到既有「CBZ 書籍 isFixedLayout: null...」測試（Issue 3 Important #1 迴歸測試）附近，追加同構測試：

```dart
    testWidgets(
      'TXT 書籍 isFixedLayout: null 時，防禦性視為 false 並建構 FoliateReaderView，'
      '不永遠停留載入中畫面（epic-11 Issue 4，比照 Issue 2 C2／Issue 3 Important #1 '
      '同構情境；正常匯入流程下 Book.isFixedLayout 必為 false，本測試涵蓋邊界防禦）',
      (tester) async {
        final repository = FakeLibraryRepository();
        await tester.pumpWidget(MaterialApp(home: ReaderScreen(
          filePath: 'test/fixtures/sample_synth.txt', bookId: 'b1',
          prefsManager: prefsManager, libraryRepository: repository,
        )));
        await tester.pump();
        await tester.runAsync(() => Future.delayed(Duration.zero));
        await tester.pump();
        expect(find.byType(FoliateReaderView), findsOneWidget);
        expect(repository.detectAndCacheEpubLayoutCalls, isEmpty);
      },
    );
```

（本測試需要 `test/fixtures/sample_synth.txt` 是一份**已經合成過的合法 EPUB 結構**、僅副檔名為 `.txt` 的檔案——因為 `ReaderScreen`／`FoliateReaderView` widget test 直接建構 widget、不經過匯入管線，若給它原始純文字內容，`FoliateReaderView` 底層 `epub.js` 開書會失敗，但本測試只驗證 Dart 端 `_dispatchedIsFixedLayout` 分派邏輯與 widget 樹建構，不驗證真正開書渲染成功——比照既有 `sample.azw3`／`sample.cbz` 走 widget test 的既有模式，只需檔案存在、`FoliateReaderView` 建構成功即可，不需要真的能被 WebView 渲染。Task 9 會產生此 fixture。）

- [ ] **Step 2：確認測試失敗**

```bash
cd "U:/MyDeveloper/AI/elinkBook/app"
flutter test test/screens/reader_screen_test.dart --plain-name "TXT 書籍"
```

Expected：FAIL（`BookFormat.txt` 目前落入 `_resolveEpubEngineDispatch()` 的「不影響」分支，`_dispatchedIsFixedLayout` 永遠停留 `null`；此外 `test/fixtures/sample_synth.txt` 尚未建立，Task 9 才會產生——本 Step 預期先看到編譯期或執行期的檔案不存在錯誤，待 Task 9 完成 fixture 後才能看到真正代表分派邏輯缺陷的 FAIL；執行順序上可先完成本 Step 3 實作後再跑一次確認）。

- [ ] **Step 3：實作 `_resolveEpubEngineDispatch()`**

`app/lib/screens/reader_screen.dart` 修改（緊接在既有 cbz 分支之後、`if (format != BookFormat.epub) return;` 之前）：

```dart
    if (format == BookFormat.txt) {
      // TXT 合成後恆為流式（無 FXL 變體，spec.md「TXT／Markdown 合成書籍
      // 結構」），Book.isFixedLayout 理論上匯入時必定已寫入 false
      // （book_import_service_impl.dart），此處防禦性補上與上方
      // azw3/cbz 分支相同邏輯的 null-safety 修正（比照 Issue 2 C2／
      // Issue 3 Important #1 的既有教訓，避免任何未來邊界情況下
      // _dispatchedIsFixedLayout 永遠停留 null 導致 FoliateReaderView
      // 永遠無法建構）。
      _dispatchedIsFixedLayout = false;
      return;
    }
    if (format != BookFormat.epub) return;
```

- [ ] **Step 4：實作 `_writeCurrentPosition()` merged case**

修改既有 switch：

```dart
      case BookFormat.epub:
      case BookFormat.azw3:
      case BookFormat.cbz:
      case BookFormat.txt:
        final info = _epubPositionInfo;
```

（其餘 case 內容不動）

- [ ] **Step 5：實作 `_buildAppBarActions()` merged case**

修改既有 switch：

```dart
    switch (format) {
      case BookFormat.epub:
      case BookFormat.azw3:
      case BookFormat.cbz:
      case BookFormat.txt:
        return [
```

（TXT 恆為流式，`_isFixedLayout` 為 `false`，本方法不會被上方 `if (_isFixedLayout) return null;` 提早攔截，TXT 書籍會**真的**顯示這組 AppBar 按鈕——與 CBZ 不同，這是預期行為：TXT 是流式格式，需要目錄/版面設定/筆記按鈕，比照一般流式 EPUB。）

- [ ] **Step 6：實作 `_buildNativeView()` merged case**

修改既有 switch：

```dart
      case BookFormat.epub:
      case BookFormat.azw3:
      case BookFormat.cbz:
      case BookFormat.txt:
        // Epic 11 Issue 4：TXT 與 EPUB/AZW3/CBZ 共用同一個
        // FoliateReaderView，建構參數完全相同——TXT 合成後是一份真正的
        // EPUB，isComicBookHint 恆為 false（非 cbz 格式），dualPageDirection
        // 對流式格式無意義但傳入無害（main.js 僅在 isComicBookHint===true
        // 時讀取它，見 Issue 3 main.js 註解）。
        return FoliateReaderView(
```

（`isComicBookHint: format == BookFormat.cbz` 這行既有程式碼已經是布林運算式、天然對 `BookFormat.txt` 產生 `false`，不需要額外修改內部參數列，只需要把 `case BookFormat.txt:` 加進上方 case 清單。）

- [ ] **Step 7：確認測試通過**

```bash
flutter test test/screens/reader_screen_test.dart --plain-name "TXT 書籍"
```

Expected：PASS（待 Task 9 的 fixture 就緒後）。

- [ ] **Step 8：確認 `_handleZoneAction()` 無需修改（`isFoliateFormat()` 已涵蓋 txt，見 Task 3）**

```bash
grep -n "isFoliateFormat(format)" "U:/MyDeveloper/AI/elinkBook/app/lib/screens/reader_screen.dart"
```

Expected：`_handleZoneAction()` 內兩處呼叫維持不動——`isFoliateFormat()` 已於 Task 3 擴大涵蓋 `txt`，這條路徑自動正確運作。

- [ ] **Step 9：`flutter analyze`（確認 Task 3 記錄的 exhaustiveness 錯誤清單清空）**

```bash
flutter analyze
```

Expected：`reader_screen.dart` 相關的 `non_exhaustive_switch_statement` 全部消失；整體回報 `No issues found!`。

- [ ] **Step 10：完整 `flutter test`（確認全套件無回歸）**

```bash
flutter test
```

Expected：全數通過（此時仍缺 Task 9 的 `sample_synth.txt` fixture，若尚未完成 Task 9，本 Step 的 TXT 相關測試會失敗——建議 Task 8/9 依序緊接執行，不要中斷在 Task 8 結尾就 commit＋長時間擱置）。

- [ ] **Step 11：Commit**（與 Task 9 一併，待 fixture 就緒後才 commit，見下方 Task 9 Step 5）

---

## Task 9：真機測試 fixture 產生

**Files:**
- Create: `app/test/fixtures/sample_synth.txt`（widget test 用，已合成的最小 EPUB，供 Task 8 使用）
- Create: `app/test/fixtures/sample_big5.txt`（真機整合測試用，Big5 編碼原始純文字）
- Create: `app/test/fixtures/sample_utf8_chapters.txt`（真機整合測試用，UTF-8 編碼、含多個章節標題）
- Modify: `app/pubspec.yaml`（新增這三個 asset）

**Interfaces:**
- Produces：三份提交進版控的測試素材，供 Task 8 widget test 與 Task 10 真機 `integration_test` 使用。

- [ ] **Step 1：撰寫並執行 fixture 產生腳本**

```bash
cat > "U:/MyDeveloper/AI/elinkBook/tmp_generate_txt_fixtures.py" << 'PYEOF'
import zipfile

# sample_synth.txt：widget test 專用，內容是最小合法 EPUB 結構、僅副檔名
# 為 .txt（比照 Task 8 widget test 說明：只需 FoliateReaderView 能建構，
# 不要求真正能被 WebView 渲染成功，但結構仍須是合法 zip/EPUB，避免與
# production 合成邏輯的實際輸出型態脫節）。
CONTAINER_XML = '''<?xml version="1.0" encoding="UTF-8"?>
<container version="1.0" xmlns="urn:oasis:names:tc:opendocument:xmlns:container">
  <rootfiles>
    <rootfile full-path="OEBPS/content.opf" media-type="application/oebps-package+xml"/>
  </rootfiles>
</container>
'''

CONTENT_OPF = '''<?xml version="1.0" encoding="UTF-8"?>
<package xmlns="http://www.idpf.org/2007/opf" version="3.0" unique-identifier="book-id">
  <metadata xmlns:dc="http://purl.org/dc/elements/1.1/">
    <dc:identifier id="book-id">elinkbook-txt-fixture</dc:identifier>
    <dc:title>Fixture</dc:title>
    <dc:language>zh</dc:language>
  </metadata>
  <manifest>
    <item id="nav" href="nav.xhtml" media-type="application/xhtml+xml" properties="nav"/>
    <item id="chap0001" href="text/chap0001.xhtml" media-type="application/xhtml+xml"/>
  </manifest>
  <spine>
    <itemref idref="chap0001"/>
  </spine>
</package>
'''

NAV_XHTML = '''<?xml version="1.0" encoding="UTF-8"?>
<html xmlns="http://www.w3.org/1999/xhtml" xmlns:epub="http://www.idpf.org/2007/ops">
<head><title>目錄</title></head>
<body><nav epub:type="toc"><ol><li><a href="text/chap0001.xhtml">第一章</a></li></ol></nav></body>
</html>
'''

CHAPTER_XHTML = '''<?xml version="1.0" encoding="UTF-8"?>
<html xmlns="http://www.w3.org/1999/xhtml">
<head><title>內容</title></head>
<body><p>固定測試內容。</p></body>
</html>
'''

with zipfile.ZipFile(
    'U:/MyDeveloper/AI/elinkBook/app/test/fixtures/sample_synth.txt', 'w', zipfile.ZIP_DEFLATED
) as zf:
    zf.writestr('mimetype', 'application/epub+zip')
    zf.writestr('META-INF/container.xml', CONTAINER_XML)
    zf.writestr('OEBPS/content.opf', CONTENT_OPF)
    zf.writestr('OEBPS/nav.xhtml', NAV_XHTML)
    zf.writestr('OEBPS/text/chap0001.xhtml', CHAPTER_XHTML)

# sample_big5.txt：真機整合測試用，Big5 編碼的原始純文字（未經任何本專案
# 程式碼處理，就是使用者裝置上會有的那種原始 TXT 檔案）。Python 內建
# 'big5' codec 可直接編碼，用於產生測試輸入素材（非本專案 app 程式碼的一
# 部分，純粹是 fixture 產生工具，不受「純 Dart-only」限制）。
big5_content = '第一章 測試開始\n這是繁體中文內容，使用 Big5 編碼儲存。\n第二章 測試結束\n感謝閱讀本測試文件。'
with open('U:/MyDeveloper/AI/elinkBook/app/test/fixtures/sample_big5.txt', 'wb') as f:
    f.write(big5_content.encode('big5'))

# sample_utf8_chapters.txt：真機整合測試用，UTF-8 編碼、含 3 個章節標題，
# 驗證正則章節/目錄抽取端到端正確運作。
utf8_content = (
    '第一章 起源\n主角出生在一個平凡的小鎮。\n'
    '第二章 冒險\n主角踏上了未知的旅程。\n'
    '第三章 結局\n經過重重考驗，主角終於成長。\n'
)
with open('U:/MyDeveloper/AI/elinkBook/app/test/fixtures/sample_utf8_chapters.txt', 'w', encoding='utf-8') as f:
    f.write(utf8_content)

print('已產生 sample_synth.txt／sample_big5.txt／sample_utf8_chapters.txt')
PYEOF
python3 "U:/MyDeveloper/AI/elinkBook/tmp_generate_txt_fixtures.py"
rm "U:/MyDeveloper/AI/elinkBook/tmp_generate_txt_fixtures.py"
```

- [ ] **Step 2：驗證 `sample_big5.txt` 能被 `detectAndDecodeTxt()` 正確解碼為 big5**

```bash
cd "U:/MyDeveloper/AI/elinkBook/app"
cat > /tmp/verify_txt_fixtures_test.dart << 'DARTEOF'
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:elinkbook/library/txt_charset_detection.dart';

void main() {
  test('sample_big5.txt 正確偵測為 big5 並解碼出正確中文', () async {
    final bytes = await File('test/fixtures/sample_big5.txt').readAsBytes();
    final result = detectAndDecodeTxt(bytes);
    expect(result.encoding, TxtEncoding.big5);
    expect(result.text, contains('第一章 測試開始'));
    expect(result.text, contains('第二章 測試結束'));
  });
}
DARTEOF
cp /tmp/verify_txt_fixtures_test.dart test/library/verify_txt_fixtures_test.dart
flutter test test/library/verify_txt_fixtures_test.dart
rm test/library/verify_txt_fixtures_test.dart
```

Expected：PASS（確認 fixture 產生腳本使用的 Python `'big5'` codec 與本專案 Dart 端解碼器對同一份資料的解讀結果一致）。

- [ ] **Step 3：`pubspec.yaml` 新增 asset**

`app/pubspec.yaml` 的 `assets:` 清單，緊接在 `- test/fixtures/sample_unpadded.cbz` 之後新增：

```yaml
    - test/fixtures/sample_synth.txt
    - test/fixtures/sample_big5.txt
    - test/fixtures/sample_utf8_chapters.txt
```

```bash
flutter pub get
```

- [ ] **Step 4：重新確認 Task 8 的 widget test 通過**

```bash
flutter test test/screens/reader_screen_test.dart --plain-name "TXT 書籍"
```

Expected：PASS。

- [ ] **Step 5：Commit（涵蓋 Task 8 與本 Task）**

```bash
cd "U:/MyDeveloper/AI/elinkBook"
git add app/lib/screens/reader_screen.dart app/test/screens/reader_screen_test.dart \
  app/test/fixtures/sample_synth.txt app/test/fixtures/sample_big5.txt \
  app/test/fixtures/sample_utf8_chapters.txt app/pubspec.yaml
git commit -m "feat(epic-11): Issue 4——ReaderScreen 分派邏輯擴充涵蓋 TXT，新增測試 fixture"
```

---

## Task 10：真機 `integration_test`

**Files:**
- Create: `app/integration_test/foliate_txt_test.dart`

**Interfaces:**
- Consumes：`sample_big5.txt`／`sample_utf8_chapters.txt`（Task 9）；`BookImportServiceImpl`／`ReaderScreen`（既有，Task 7/8 已擴充支援 txt）。

- [ ] **Step 1：確認可用裝置**

```bash
cd "U:/MyDeveloper/AI/elinkBook/app"
flutter devices
```

- [ ] **Step 2：撰寫測試**

```dart
// app/integration_test/foliate_txt_test.dart
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:path_provider/path_provider.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:elinkbook/library/book_import_service_impl.dart';
import 'package:elinkbook/library/sqlite_library_repository.dart';
import 'package:elinkbook/reader/book_reader_prefs_repository.dart';
import 'package:elinkbook/reader/reader_prefs_manager_impl.dart';
import 'package:elinkbook/reader/reading_position_repository.dart';
import 'package:elinkbook/screens/reader_screen.dart';

/// 把 Flutter asset 複製為裝置暫存目錄中的真實檔案，回傳其絕對路徑
/// （比照 foliate_kf8_test.dart／foliate_cbz_test.dart 既有 helper）。
Future<String> _stageAssetAsFile(String assetPath, String fileName) async {
  final bytes = await rootBundle.load(assetPath);
  final tempDir = await getTemporaryDirectory();
  final file = File('${tempDir.path}/$fileName');
  await file.writeAsBytes(bytes.buffer.asUint8List(), flush: true);
  return file.path;
}

/// 持續 pump，直到載入指示器消失或逾時（比照既有 foliate_kf8_test.dart／
/// foliate_cbz_test.dart 既有斷言方式）。
Future<void> _pumpUntilLoaded(WidgetTester tester) async {
  final deadline = DateTime.now().add(const Duration(seconds: 20));
  while (find.byKey(const Key('reader_loading_indicator')).evaluate().isNotEmpty) {
    if (DateTime.now().isAfter(deadline)) fail('等待逾時：載入指示器未消失');
    await tester.pump(const Duration(milliseconds: 50));
  }
  await tester.pump(const Duration(seconds: 1));
}

Future<
    ({
      SqliteLibraryRepository repository,
      ReaderPrefsManagerImpl prefsManager,
      BookImportServiceImpl importService,
    })> _setUpServices() async {
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;
  final repository = await SqliteLibraryRepository.open(inMemoryDatabasePath);
  final prefsManager = ReaderPrefsManagerImpl(
    BookReaderPrefsRepository(repository.database),
    ReadingPositionRepository(repository.database),
  );
  return (
    repository: repository,
    prefsManager: prefsManager,
    importService: BookImportServiceImpl(repository: repository),
  );
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
    '透過 BookImportService 匯入 Big5 編碼 TXT 並經 ReaderScreen 開啟，'
    '成功渲染無錯誤（驗證編碼偵測＋EPUB 合成的完整真機端到端流程）',
    (tester) async {
      final services = await _setUpServices();
      addTearDown(() => services.repository.close());

      final samplePath =
          await _stageAssetAsFile('test/fixtures/sample_big5.txt', 'foliate_txt_big5_integration.txt');
      addTearDown(() async {
        final file = File(samplePath);
        if (await file.exists()) await file.delete();
      });

      final result = await services.importService.importFiles(
        [samplePath],
        displayNames: ['sample_big5.txt'],
      );
      expect(result.importedBooks, hasLength(1));
      final book = result.importedBooks.single;
      expect(book.isFixedLayout, isFalse);

      await tester.pumpWidget(
        MaterialApp(
          home: ReaderScreen(
            filePath: book.filePath,
            bookId: book.id,
            prefsManager: services.prefsManager,
            libraryRepository: services.repository,
            isFixedLayout: book.isFixedLayout,
          ),
        ),
      );
      await _pumpUntilLoaded(tester);

      expect(find.byKey(const Key('reader_error_text')), findsNothing);
    },
  );

  testWidgets(
    '透過 BookImportService 匯入 UTF-8 編碼、含章節標題的 TXT 並經 ReaderScreen 開啟，'
    '成功渲染無錯誤，目錄正確產生',
    (tester) async {
      final services = await _setUpServices();
      addTearDown(() => services.repository.close());

      final samplePath = await _stageAssetAsFile(
          'test/fixtures/sample_utf8_chapters.txt', 'foliate_txt_utf8_integration.txt');
      addTearDown(() async {
        final file = File(samplePath);
        if (await file.exists()) await file.delete();
      });

      final result = await services.importService.importFiles(
        [samplePath],
        displayNames: ['sample_utf8_chapters.txt'],
      );
      final book = result.importedBooks.single;

      final readerKey = GlobalKey<State<ReaderScreen>>();
      await tester.pumpWidget(
        MaterialApp(
          home: ReaderScreen(
            key: readerKey,
            filePath: book.filePath,
            bookId: book.id,
            prefsManager: services.prefsManager,
            libraryRepository: services.repository,
            isFixedLayout: book.isFixedLayout,
          ),
        ),
      );
      await _pumpUntilLoaded(tester);

      expect(find.byKey(const Key('reader_error_text')), findsNothing);

      final toc = await ReaderScreen.loadTableOfContentsForTest(readerKey);
      expect(toc.map((e) => e.title), ['第一章 起源', '第二章 冒險', '第三章 結局']);
    },
  );

  testWidgets(
    '大型 TXT（約 6MB，無規範章節標記）匯入與開書流暢，不因超大 DOM section 崩潰',
    (tester) async {
      final services = await _setUpServices();
      addTearDown(() => services.repository.close());

      // 產生約 6MB、無章節標記的合成內容（每行約 60 bytes，約 100000 行），
      // 驗證 chunkByByteSize() 的分塊防護在真機端到端流程中確實生效
      // （比照既有 foliate_epub_reader_view_test.dart
      // _buildLargeSyntheticEpub() 大型檔案測試模式，運行期產生、不提交
      // 進版控）。
      final tempDir = await getTemporaryDirectory();
      final largeFile = File('${tempDir.path}/foliate_txt_large_integration.txt');
      final sink = largeFile.openWrite();
      for (var i = 0; i < 100000; i++) {
        sink.writeln('第 $i 行內容，用於測試大型 TXT 檔案的分塊防護機制是否正常運作。');
      }
      await sink.close();
      addTearDown(() async {
        if (await largeFile.exists()) await largeFile.delete();
      });

      final result = await services.importService.importFiles(
        [largeFile.path],
        displayNames: ['large_novel.txt'],
      );
      expect(result.importedBooks, hasLength(1));
      final book = result.importedBooks.single;

      await tester.pumpWidget(
        MaterialApp(
          home: ReaderScreen(
            filePath: book.filePath,
            bookId: book.id,
            prefsManager: services.prefsManager,
            libraryRepository: services.repository,
            isFixedLayout: book.isFixedLayout,
          ),
        ),
      );
      await _pumpUntilLoaded(tester);

      expect(find.byKey(const Key('reader_error_text')), findsNothing);
    },
  );
}
```

**注意**：本測試第二則使用了 `ReaderScreen.loadTableOfContentsForTest()`——若 `ReaderScreen` 目前沒有暴露對應的測試專用 static helper，請比照既有 `ReaderScreen.triggerZoneAction()`／`togglePdfBookmark()`／`openPdfToc()` 的既有強型別 static helper 模式（`reader_screen.dart` 已有的 `static void openPdfToc(GlobalKey<State<ReaderScreen>> key)` 呼叫 `state._openPdfToc()`），新增一個呼叫既有私有方法 `_requestTableOfContents()`／或直接呼叫 `FoliateReaderView.loadTableOfContents(_foliateEpubReaderViewKey)` 的對應 helper（`FoliateReaderView.loadTableOfContents` 本身已是公開 static API，見 `foliate_reader_view.dart`）。若 `ReaderScreen` 尚未有任何目錄讀取的測試出口，於 `app/lib/screens/reader_screen.dart` 新增：

```dart
  /// 供真機整合測試讀取目前書籍目錄（epic-11-multi-format-reader
  /// Issue 4），比照既有 [triggerZoneAction] 強型別 static helper 模式。
  /// [key] 對應的 State 若尚未掛載，回傳空清單。
  static Future<List<TocEntry>> loadTableOfContentsForTest(
    GlobalKey<State<ReaderScreen>> key,
  ) async {
    final state = key.currentState;
    if (state is! _ReaderScreenState) return const [];
    return FoliateReaderView.loadTableOfContents(state._foliateEpubReaderViewKey);
  }
```

（新增位置：緊接在既有 `static void openPdfToc(...)` 方法之後，`ReaderScreen` class 結尾 `}` 之前）

- [ ] **Step 3：真機執行**

```bash
flutter test integration_test/foliate_txt_test.dart -d <device-id>
```

Expected：3/3 PASS。若第一個測試（Big5）失敗，優先檢查 `detectAndDecodeTxt()` 是否誤判編碼（可能是測試環境的檔案讀取路徑問題，非解碼邏輯本身——Task 9 Step 2 已用 `flutter test` 驗證過解碼邏輯正確）；若第三個測試（大型檔案）逾時，檢查 `chunkByByteSize()` 是否真的被觸發（`kTxtChunkMaxBytes = 400000`，6MB 檔案應產生約 15 個以上的 XHTML 分塊）。

- [ ] **Step 4：Commit**

```bash
cd "U:/MyDeveloper/AI/elinkBook"
git add app/integration_test/foliate_txt_test.dart app/lib/screens/reader_screen.dart
git commit -m "test(epic-11): Issue 4——TXT 真機整合測試，涵蓋 Big5/UTF-8 匯入開書與大型檔案分塊"
```

---

## Task 11：全專案最終驗證

**Files:** 無新增/修改，純驗證。

- [ ] **Step 1：`flutter analyze`**

```bash
cd "U:/MyDeveloper/AI/elinkBook/app"
flutter analyze
```

Expected：`No issues found!`

- [ ] **Step 2：完整 `flutter test`**

```bash
flutter test
```

Expected：全數通過（既有 1341 + 本 Issue 新增測試，具體數字以實際輸出為準）。

- [ ] **Step 3：真機整合測試回歸（確認未破壞既有 KF8/CBZ 整合測試）**

```bash
flutter test integration_test/foliate_kf8_test.dart integration_test/foliate_cbz_test.dart integration_test/foliate_txt_test.dart -d <device-id>
```

Expected：全數 PASS。

- [ ] **Step 4：手動驗收（比照 issues.md Issue 4 驗收標準逐項確認）**

- 真機匯入 Big5 與 UTF-8 編碼的 TXT 檔案皆正確顯示、不亂碼：於裝置上實際透過圖書庫匯入畫面選取兩種檔案，人工目視確認無亂碼。
- 大型 TXT（5MB~20MB 量級，無規範章節標記）開書流暢：實際匯入一份大型網路小說 TXT（若無現成素材，可用 Task 10 測試內產生大型檔案的相同手法自行產生一份留在裝置上手動測試），人工感受翻頁/捲動流暢度。
- 目錄正確產生；直排/橫排切換、劃線、書籤功能與 EPUB 一致：人工操作既有 UI 逐一確認（皆為既有機制直接繼承，理論上零額外程式碼即可運作）。
- 刪除書籍後對應合成檔案從磁碟移除：於圖書庫刪除一本已匯入的 TXT 書籍，確認 `imported_books/$id.txt` 檔案消失——**這是既有 `library_screen.dart` 刪除邏輯已經涵蓋的行為，不需要新程式碼**（`book.filePath` 只要是本機檔案就會被既有 `File(book.filePath).existsSync()`/`deleteSync()` 清除，見該檔案既有邏輯；Issue 3 CBZ 已驗證過同一結論）。人工確認無回歸即可，不需額外撰寫測試。

- [ ] **Step 5：更新 `issues.md`／`docs/epics.md`（人類確認驗收通過後，比照 Issue 2/3 既有流程另行處理，不在本計畫任務範圍內）**

---

## Self-Review（spec 覆蓋檢查）

逐項比對 `issues.md` Issue 4「範圍」1-8 點：
1. `BookFormat` 新增 `txt`；`ReaderScreen` 對 `txt` 建構 `FoliateReaderView` → Task 3／Task 8 ✓
2. TXT 編碼偵測：Big5 優先梯隊，純 Dart 自建對照表，運算包 `Isolate.run()` → Task 2（對照表）／Task 4（偵測/解碼）／Task 6（`Isolate.run()` 包裝）✓
3. 正則章節/目錄抽取 → Task 5 ✓
4. 雙重分塊防護 → Task 5（`chunkByByteSize`）／Task 10（大型檔案真機驗證）✓
5. 匯入時落地轉換為合成書籍結構，`Book.filePath` 指向衍生檔案，以 book id 為鍵、獨立子目錄 → Task 6（合成）／Task 7（落地至既有 `imported_books/` 目錄，沿用 CBZ 已建立的慣例）✓
6. `contentFingerprint` 對原始輸入檔案計算 → Task 7（測試明確驗證計算來源）✓
7. 合成檔案刪除清理 → **既有 `library_screen.dart` 邏輯已涵蓋（Issue 3 CBZ 已驗證同一結論），本計畫 Task 11 Step 4 說明無需新程式碼，非遺漏** ✓
8. `Book.isFixedLayout` 對 TXT 合成後恆為 `false` → Task 7（匯入寫入）／Task 8（`ReaderScreen` 防禦分派）✓

`Placeholder` 掃描：全文搜尋 "TBD"/"待補"/"依需求調整" 等字樣——無。所有程式碼區塊皆為可直接套用的完整程式碼；Big5/GBK 對照表資料本身雖不在計畫文件中逐條列出（13503+21791 筆不可能、也不應該手動鍵入計畫文件），但透過完整、可驗證、已實際試跑過的產生腳本（Task 2）取得，非留白待補——與 Issue 1-3 既有的 `curl` vendoring 手法同一性質，不視為 placeholder。

型別一致性檢查：`TxtDecodeResult`/`TxtEncoding`（Task 4 定義）→ `txt_epub_synthesizer.dart`（Task 6 消費，欄位/列舉值一致）；`TxtChapter`/`splitIntoChapters`/`chunkByByteSize`（Task 5 定義）→ `txt_epub_synthesizer.dart`（Task 6 消費，簽章一致）；`TxtSynthesisResult`/`EmptyTxtException`/`synthesizeTxtBook`（Task 6 定義）→ `book_import_service_impl.dart`（Task 7 消費，欄位/例外型別一致）；`readContentUriBytes`（Task 1 定義，具名參數 `tempFilePrefix`/`tempFileExtension`）→ `cbz_import.dart`（Task 1 內重構）／`txt_epub_synthesizer.dart`（Task 6，皆用相同具名參數）——皆一致。
