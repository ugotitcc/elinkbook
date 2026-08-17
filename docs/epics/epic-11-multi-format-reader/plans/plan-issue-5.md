# Issue 5：Markdown (MD) 合成書籍結構與閱讀 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development（建議）或 superpowers:executing-plans 逐 Task 執行本計畫。Step 前的 checkbox（`- [ ]`）用於追蹤進度。

**Goal:** 讓 elinkBook 能匯入並閱讀 Markdown（`.md`）檔案——解析 YAML Frontmatter 取得標題/作者/封面、依標題階層（H1-H6）自動產生巢狀目錄、程式碼區塊與表格在直排模式下維持橫排可橫向捲動，直排/橫排、劃線、書籤等體驗與既有 EPUB／TXT 完全一致。

**Architecture:** MD 沿用 Issue 4（TXT）已建立的「匯入時一次性合成為最小合法 EPUB3 結構」模式，共用同一套落地/清理/`contentFingerprint` 計算順序慣例，不重新設計；本 Issue 新增的技術難點集中在「Markdown → 章節/目錄結構」這一側：用 Dart 官方 `package:markdown` 解析 AST（而非自建解析器），依文件內出現過的最淺標題層級切分 XHTML 章節，依完整標題階層建構巢狀目錄樹。EPUB 容器骨架（container.xml／OPF／nav.xhtml 模板）從 `txt_epub_synthesizer.dart` 抽出為共用模組，避免與 MD 重複——這是本 Epic 第二次遇到同一份模板需求（Issue 4 對 Issue 3 也做過一次類似的 DRY 抽取，`content_uri_reader.dart`），抽取時機成熟。

**Tech Stack:** Flutter/Dart（`package:markdown` 官方套件，純 Dart AST 解析器，新增依賴；`package:yaml` 官方套件，目前僅為既有 transitive dependency，本 Issue 起升級為直接依賴；`package:archive` 既有依賴）；`readest/foliate-js` 既有 `epub.js`（本 Issue 完全不修改，只產生它能解析的合法輸入，比照 Issue 4 已驗證的合成策略）。

**Spec:** `docs/epics/epic-11-multi-format-reader/spec.md`「TXT／Markdown 合成書籍結構」「Out of Scope」；`docs/epics/epic-11-multi-format-reader/issues.md` Issue 5；`app/lib/library/txt_epub_synthesizer.dart`／`txt_chapter_splitter.dart`（Issue 4 既有實作，本 Issue 抽取共用部分／模仿既有模式）。

## Global Constraints

- 純 Dart-only 解析：`package:markdown`／`package:yaml` 皆為純 Dart、無原生 platform channel 依賴，符合 ADR 0023 決策 5。`content://` URI 讀取沿用既有共用 `readContentUriBytes()`（Issue 4 已抽出）。
- `CLAUDE.md` 兩層測試架構：純 Dart 解析/合成邏輯用 `flutter test`（Seam 1）；原生渲染是否真的成功須 `integration_test/` 真機驗證（Seam 2）。
- CPU 密集運算（Markdown 解析、章節切分、XML 組裝）須包裝於 `Isolate.run()` 背景執行，比照 Issue 4 既有作法；`generateTxtCover()`（`dart:ui`）依然只能在主 isolate 呼叫，維持 Issue 4 已建立的「合成與封面產生分開呼叫」紀律。
- `contentFingerprint` 對原始輸入檔案計算，不可用合成後的衍生檔案路徑計算（比照 Issue 3／4 已建立的同一原則）。
- 合成後的檔案副檔名須維持 `.md`（不可改為 `.epub`），供 `BookFormat.md` 正確分派——沿用 Issue 3 已修復的 WebView 快取副檔名感知機制，不需要任何進一步修改（`cacheFileExtension()` 從 `Book.filePath` 動態推導，對任意副檔名皆正確運作）。
- 所有回應/文件/程式註解使用正體中文（使用者全域 CLAUDE.md 規則）。
- **明確不在本 Issue 範圍**（issues.md Issue 5 已明訂）：MD 內嵌本機相對路徑圖片（例如 `![](./img/1.png)`）的優雅降級——單檔匯入不會一併帶入該圖片資源，比照瀏覽器/WebView 對缺失圖片資源的既有預設行為（顯示破圖、不中斷分頁），不額外開發。
- **設計取捨備忘（審查確認，見 reviews/review-issue-5-plan.md Minor #2）**：章節切分僅依標題階層進行，完全沒有標題的大型 Markdown 檔案會合成為單一大型 XHTML，不做 TXT 那種位元組門檻式次級分塊（`kTxtChunkMaxBytes`／`chunkByByteSize()`）。Markdown 筆記在實務上鮮少完全無標題，issues.md Issue 5 範圍本身也未要求此能力，維持 YAGNI，不預先實作。
- **已查證的關鍵技術事實**（供各 Task 撰寫依據，皆已用本次規劃階段對 `package:markdown`／`package:yaml` 官方原始碼交叉核對，非憑空假設）：
  1. **~~`package:markdown` 的 HTML 輸出預設就是合法 XHTML~~（本項查證有誤，見
     `reviews/review-issue-5.md` Critical #1，已於程式碼審查修復階段訂正）**：
     `html_renderer.dart` 確實會把套件自己產生的空元素（`<hr>`／`<br>`／
     `<img>` 等）以 `<tag ... />` 自我封閉輸出，但這僅涵蓋套件**自行產生**的
     標籤——原查證誤判了另一件事：CommonMark/GFM 規範定義的「raw HTML
     passthrough」（使用者輸入中「看起來像 HTML 標籤」的裸文字，例如手打
     `<br>` 換行或標題含 `<C>` 這類字元）並不會被跳脫，而是原樣輸出，
     `encodeHtml` 參數的跳脫範圍不含這類裸 HTML。已用分支上實際的
     `synthesizeMdBook()` 重現：僅需一般使用者手打的 `<br>` 就會讓合成出的
     章節 XHTML 解析失敗（`epub.js` 是以嚴格 `application/xhtml+xml` 模式
     載入章節）。修復方式：`md_epub_synthesizer.dart` 的 `_sectionXhtml()`
     改為對 `md.renderToHtml()` 的輸出先跑一次「HTML5 容錯解析（`package:
     html`）＋重新序列化為合法 XML」的正規化，不再直接信任原始字串。
  2. **表格語法（GFM）不是 CommonMark 核心的一部分**：必須使用 `md.ExtensionSet.gitHubWeb`（含 `TableSyntax()`／`FencedCodeBlockSyntax()`／`HeaderWithIdSyntax()` 等）才會把 `| a | b |` 語法解析為真正的 `<table>` 元素；若僅用預設的 `ExtensionSet.commonMark`，表格語法只會被當成一般段落文字輸出，範圍第 4 點要求的表格 CSS 覆蓋會完全沒有 `<table>` 元素可套用。
  3. **標題 id 不可依賴 `gitHubWeb` 內建的 `HeaderWithIdSyntax`／`generatedId` 自動產生機制**：該機制在「渲染階段」才透過 `HtmlRenderer.uniquifyId()` 對重複標題文字做去重（例如兩個都叫「概述」的標題，第二個會被重新命名為 `概述-1`），但本 Issue 需要在渲染**之前**就知道每個標題最終的 id 字串，才能組出目錄（`nav.xhtml`）指向該 id 的超連結——若沿用內建機制，規劃階段推算出的 id 與實際渲染結果可能不一致（尤其重複標題文字時）。故本 Issue 一律捨棄 `generatedId`／內建 slug id，改為在解析 AST 後自行走訪、依文件出現順序指派保證唯一的序號式 id（`heading_0001` 起算），並直接寫入 `element.attributes['id']`（同時清空 `element.generatedId = null`，避免渲染器同時寫出兩個 `id` 屬性）。
  4. **`Document.parse(String text)` 是可直接呼叫的公開 API**，內部會自動處理換行切割，不需要像 `txt_chapter_splitter.dart` 那樣自己先 `.split(RegExp(...))`；回傳的 `List<md.Node>` 是文件的**頂層區塊節點**（段落、標題、清單、程式碼區塊、表格皆為平行的頂層節點，標題不會巢狀在其他區塊節點內部）——這代表「依標題切分章節」只需要走訪這個頂層清單本身，不需要遞迴下鑽。
  5. **`renderToHtml(List<md.Node> nodes)` 是可直接呼叫的公開頂層函式**，可對「已解析、已被本 Issue 修改過標題 id」的節點子集合（例如切出來的其中一個章節）單獨渲染成 HTML 字串，不需要重新解析原始文字。

---

## Task 1：抽出共用 `epub_container_builder.dart`（DRY 重構，承接 Issue 4）

**背景**：`txt_epub_synthesizer.dart` 內的 `_containerXml`／`_contentOpf()`／`_navXhtml()`／`_escapeXml()` 是格式無關的 EPUB 容器骨架模板，MD 需要完全相同的一份。與其複製第二份，先抽出共用版本並回頭改用它（比照 Issue 4 Task 1 抽出 `content_uri_reader.dart` 的既有先例與理由）。

**Files:**
- Create: `app/lib/library/epub_container_builder.dart`
- Modify: `app/lib/library/txt_epub_synthesizer.dart`
- Test: `app/test/library/epub_container_builder_test.dart`

**Interfaces:**
- Produces：`String escapeXml(String text)`；`const String kEpubContainerXml`；`String buildEpubContentOpf({required String identifier, required String title, required String manifestItems, required String spineItems, String language = 'zh'})`；`String buildEpubNavXhtml(String navItems)`（供 Task 5 `md_epub_synthesizer.dart` 與本 Task 重構後的 `txt_epub_synthesizer.dart` 共用）。

- [ ] **Step 1：寫失敗測試**

```dart
// app/test/library/epub_container_builder_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:xml/xml.dart';
import 'package:elinkbook/library/epub_container_builder.dart';

void main() {
  test('escapeXml 跳脫 &/</> 三個保留字元', () {
    expect(escapeXml('A & B < C > D'), 'A &amp; B &lt; C &gt; D');
  });

  test('kEpubContainerXml 是良好格式 XML，rootfile 指向 OEBPS/content.opf', () {
    final doc = XmlDocument.parse(kEpubContainerXml);
    final rootfile = doc.findAllElements('rootfile').single;
    expect(rootfile.getAttribute('full-path'), 'OEBPS/content.opf');
    expect(rootfile.getAttribute('media-type'), 'application/oebps-package+xml');
  });

  test('buildEpubContentOpf 產生良好格式 XML，含 identifier/title/manifest/spine', () {
    final opf = buildEpubContentOpf(
      identifier: 'elinkbook-test-book1',
      title: '測試書名',
      manifestItems: '<item id="chap1" href="text/chap1.xhtml" media-type="application/xhtml+xml"/>\n',
      spineItems: '<itemref idref="chap1"/>\n',
    );
    final doc = XmlDocument.parse(opf);
    expect(doc.findAllElements('dc:identifier').single.innerText, 'elinkbook-test-book1');
    expect(doc.findAllElements('dc:title').single.innerText, '測試書名');
    expect(doc.findAllElements('dc:language').single.innerText, 'zh');
    expect(doc.findAllElements('item').where((e) => e.getAttribute('id') == 'chap1'), hasLength(1));
    expect(doc.findAllElements('itemref').single.getAttribute('idref'), 'chap1');
  });

  test('buildEpubContentOpf 的 title 正確跳脫特殊字元', () {
    final opf = buildEpubContentOpf(
      identifier: 'elinkbook-test-book2',
      title: 'A & B',
      manifestItems: '',
      spineItems: '',
    );
    final doc = XmlDocument.parse(opf);
    expect(doc.findAllElements('dc:title').single.innerText, 'A & B');
  });

  test('buildEpubNavXhtml 產生良好格式 XML，含 epub:type="toc"', () {
    final nav = buildEpubNavXhtml('<li><a href="text/chap1.xhtml">第一章</a></li>\n');
    final doc = XmlDocument.parse(nav);
    final navElement = doc.findAllElements('nav').single;
    expect(navElement.getAttribute('type', namespace: 'http://www.idpf.org/2007/ops'), 'toc');
    expect(doc.findAllElements('a').single.innerText, '第一章');
  });
}
```

- [ ] **Step 2：`xml` 套件新增為 dev_dependency（若 Issue 4 尚未新增則本 Task 新增；若已存在則跳過本 Step）**

```bash
cd "U:/MyDeveloper/AI/elinkBook/app"
grep -n "^  xml:" pubspec.yaml
```

若無輸出，於 `dev_dependencies:` 區塊新增：

```yaml
  xml: ^6.6.1
```

並執行 `flutter pub get`。

- [ ] **Step 3：確認測試失敗**

```bash
flutter test test/library/epub_container_builder_test.dart
```

Expected：FAIL（`epub_container_builder.dart` 不存在，編譯錯誤）。

- [ ] **Step 4：實作**

```dart
// app/lib/library/epub_container_builder.dart
/// 格式無關的最小合法 EPUB3 容器骨架模板（供 TXT／MD 等「匯入時合成為
/// EPUB 結構」的格式共用，epic-11-multi-format-reader Issue 5 從
/// `txt_epub_synthesizer.dart` 抽出）。命名空間/必要屬性已對照真實
/// `epub.js` 解析原始碼核實（見 Issue 4 規劃階段查證：`META-INF/
/// container.xml` 須含 `<rootfile full-path="..." media-type=
/// "application/oebps-package+xml"/>`；OPF 的 `<manifest><item id=
/// "..." href="..." media-type="..."/></manifest>` 與 `<spine><itemref
/// idref="..."/></spine>`〔`idref` 對應 manifest item 的 `id`〕為唯一
/// 硬性要求；`<metadata>` 無必填欄位；nav/NCX 皆選填）。

String escapeXml(String text) =>
    text.replaceAll('&', '&amp;').replaceAll('<', '&lt;').replaceAll('>', '&gt;');

const String kEpubContainerXml = '''<?xml version="1.0" encoding="UTF-8"?>
<container version="1.0" xmlns="urn:oasis:names:tc:opendocument:xmlns:container">
  <rootfiles>
    <rootfile full-path="OEBPS/content.opf" media-type="application/oebps-package+xml"/>
  </rootfiles>
</container>
''';

String buildEpubContentOpf({
  required String identifier,
  required String title,
  required String manifestItems,
  required String spineItems,
  String language = 'zh',
}) =>
    '''<?xml version="1.0" encoding="UTF-8"?>
<package xmlns="http://www.idpf.org/2007/opf" version="3.0" unique-identifier="book-id">
  <metadata xmlns:dc="http://purl.org/dc/elements/1.1/">
    <dc:identifier id="book-id">$identifier</dc:identifier>
    <dc:title>${escapeXml(title)}</dc:title>
    <dc:language>$language</dc:language>
  </metadata>
  <manifest>
    <item id="nav" href="nav.xhtml" media-type="application/xhtml+xml" properties="nav"/>
$manifestItems  </manifest>
  <spine>
$spineItems  </spine>
</package>
''';

String buildEpubNavXhtml(String navItems) =>
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
```

- [ ] **Step 5：確認測試通過**

```bash
flutter test test/library/epub_container_builder_test.dart
```

Expected：PASS（5 個測試）。

- [ ] **Step 6：重構 `txt_epub_synthesizer.dart` 改用共用版本**

`app/lib/library/txt_epub_synthesizer.dart` 移除 `_escapeXml()`／`_containerXml`／`_contentOpf()`／`_navXhtml()` 四個私有定義，改為：

```dart
import 'epub_container_builder.dart';
```

並將 `_decodeAndSynthesize()` 內原本：

```dart
  archive.addFile(ArchiveFile.bytes('META-INF/container.xml', utf8.encode(_containerXml)));
```

改為：

```dart
  archive.addFile(ArchiveFile.bytes('META-INF/container.xml', utf8.encode(kEpubContainerXml)));
```

原本：

```dart
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
```

改為：

```dart
  archive.addFile(ArchiveFile.bytes('OEBPS/nav.xhtml', utf8.encode(buildEpubNavXhtml(navItems.toString()))));
  archive.addFile(ArchiveFile.bytes(
    'OEBPS/content.opf',
    utf8.encode(buildEpubContentOpf(
      identifier: 'elinkbook-txt-$bookId',
      title: title,
      manifestItems: manifestItems.toString(),
      spineItems: spineItems.toString(),
    )),
  ));
```

`_buildXhtmlBody()`／`_chapterXhtml()` 內原本呼叫 `_escapeXml(...)` 的兩處皆改為呼叫 `escapeXml(...)`（去除底線前綴，改用 import 進來的共用版本）。

- [ ] **Step 7：確認 TXT 既有測試仍通過（零回歸）**

```bash
flutter test test/library/txt_epub_synthesizer_test.dart test/library/book_import_service_test.dart
```

Expected：PASS，數量與重構前相同（純內部實作搬移，`synthesizeTxtBook()` 對外行為完全不變，含 `dc:identifier` 字面值 `elinkbook-txt-$bookId` 也維持不變）。

- [ ] **Step 8：`flutter analyze`**

```bash
flutter analyze
```

Expected：`No issues found!`

- [ ] **Step 9：Commit**

```bash
git add app/lib/library/epub_container_builder.dart app/lib/library/txt_epub_synthesizer.dart app/test/library/epub_container_builder_test.dart app/pubspec.yaml
git commit -m "refactor(epic-11): Issue 5——抽出共用 epub_container_builder.dart，txt_epub_synthesizer.dart 改用"
```

---

## Task 2：`BookFormat` 新增 `md`

**Files:**
- Modify: `app/lib/reader/book_format.dart`
- Modify: `app/lib/library/models/library_enums.dart`
- Test: `app/test/reader/book_format_test.dart`

**Interfaces:**
- Produces：`BookFormat.md`、`detectBookFormat('foo.md') == BookFormat.md`、`isFoliateFormat(BookFormat.md) == true`、`BookFileFormat.md`。

- [x] **Step 1：寫失敗測試**

於 `app/test/reader/book_format_test.dart`（Issue 3/4 已建立，見既有內容）追加：

```dart
  test('detectBookFormat 對 .md 副檔名回傳 BookFormat.md', () {
    expect(detectBookFormat('notes.md'), BookFormat.md);
    expect(detectBookFormat('NOTES.MD'), BookFormat.md);
  });

  test('isFoliateFormat 對 md 回傳 true', () {
    expect(isFoliateFormat(BookFormat.md), isTrue);
  });
```

- [x] **Step 2：確認測試失敗**

```bash
cd "U:/MyDeveloper/AI/elinkBook/app"
flutter test test/reader/book_format_test.dart
```

Expected：FAIL（`BookFormat.md` 未定義，編譯錯誤）。

- [x] **Step 3：實作**

```dart
/// 書籍檔案格式，依副檔名偵測。
enum BookFormat { epub, pdf, azw3, cbz, txt, md, unknown }

BookFormat detectBookFormat(String path) {
  final lowerPath = path.toLowerCase();
  if (lowerPath.endsWith('.epub')) return BookFormat.epub;
  if (lowerPath.endsWith('.pdf')) return BookFormat.pdf;
  if (lowerPath.endsWith('.azw3')) return BookFormat.azw3;
  if (lowerPath.endsWith('.cbz')) return BookFormat.cbz;
  if (lowerPath.endsWith('.txt')) return BookFormat.txt;
  if (lowerPath.endsWith('.md')) return BookFormat.md;
  return BookFormat.unknown;
}

bool isFoliateFormat(BookFormat format) =>
    format == BookFormat.epub ||
    format == BookFormat.azw3 ||
    format == BookFormat.cbz ||
    format == BookFormat.txt ||
    format == BookFormat.md;
```

（`detectBookFormat` doc comment／`isFoliateFormat` doc comment 內容維持既有文字，僅新增上述程式碼行，不需要額外修改註解本身）

`app/lib/library/models/library_enums.dart` 修改：

```dart
enum BookFileFormat { epub, pdf, txt, azw3, cbz, md }
```

- [x] **Step 4：確認測試通過**

```bash
flutter test test/reader/book_format_test.dart
```

Expected：PASS。

- [x] **Step 5：`flutter analyze` 確認 exhaustiveness 錯誤清單**

```bash
flutter analyze
```

Expected：出現數個 `non_exhaustive_switch_statement`（`reader_screen.dart` 內既有 `switch (format)` 語句缺少 `case BookFormat.md:`），記錄下來供 Task 7 使用（比照 Issue 3/4 既有方法論）。**不要在本 Task 修正**。

- [x] **Step 6：Commit**

```bash
git add app/lib/reader/book_format.dart app/lib/library/models/library_enums.dart app/test/reader/book_format_test.dart
git commit -m "feat(epic-11): Issue 5——BookFormat/BookFileFormat 新增 md"
```

---

## Task 3：YAML Frontmatter 解析

**Files:**
- Create: `app/lib/library/md_frontmatter.dart`
- Test: `app/test/library/md_frontmatter_test.dart`

**Interfaces:**
- Produces：`class MdFrontmatter { String? title; String? author; Uint8List? coverBytes; }`；`class MdParsedDocument { MdFrontmatter frontmatter; String body; }`；`MdParsedDocument parseMdFrontmatter(String content)`（供 Task 5 `md_epub_synthesizer.dart` 消費）。

- [ ] **Step 1：寫失敗測試**

```dart
// app/test/library/md_frontmatter_test.dart
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:elinkbook/library/md_frontmatter.dart';

void main() {
  test('正確解析含 title/author 的 Frontmatter，body 為其後內容', () {
    const content = '---\ntitle: 測試筆記\nauthor: 測試作者\n---\n# 標題\n內容';
    final result = parseMdFrontmatter(content);
    expect(result.frontmatter.title, '測試筆記');
    expect(result.frontmatter.author, '測試作者');
    expect(result.body.trim(), '# 標題\n內容');
  });

  test('沒有 Frontmatter 時，frontmatter 全為 null，body 為原始內容', () {
    const content = '# 標題\n沒有 frontmatter 的內容';
    final result = parseMdFrontmatter(content);
    expect(result.frontmatter.title, isNull);
    expect(result.frontmatter.author, isNull);
    expect(result.frontmatter.coverBytes, isNull);
    expect(result.body, content);
  });

  test('開頭是 --- 但找不到結尾 --- 時，視為沒有 Frontmatter', () {
    const content = '---\ntitle: 未閉合\n# 標題\n內容';
    final result = parseMdFrontmatter(content);
    expect(result.frontmatter.title, isNull);
    expect(result.body, content);
  });

  test('YAML 格式錯誤時降級為沒有 metadata，但仍剝離起訖線', () {
    const content = '---\ntitle: "未閉合的引號\n---\n內容';
    final result = parseMdFrontmatter(content);
    expect(result.frontmatter.title, isNull);
    expect(result.body.trim(), '內容');
  });

  test('cover 為 data: URI（base64）時正確解碼為位元組', () {
    final pngBytes = [0x89, 0x50, 0x4E, 0x47];
    final base64Data = base64Encode(pngBytes);
    final content = '---\ntitle: 有封面\ncover: data:image/png;base64,$base64Data\n---\n內容';
    final result = parseMdFrontmatter(content);
    expect(result.frontmatter.coverBytes, pngBytes);
  });

  test('cover 為相對路徑（非 data: URI）時忽略，coverBytes 為 null（本 Issue 明確排除範圍）', () {
    const content = '---\ntitle: 相對路徑封面\ncover: ./img/cover.png\n---\n內容';
    final result = parseMdFrontmatter(content);
    expect(result.frontmatter.coverBytes, isNull);
  });

  test('內容開頭帶 UTF-8 BOM（U+FEFF）時仍正確辨識 Frontmatter（審查修正，'
      '見 reviews/review-issue-5-plan.md Important #2——Windows 編輯器/'
      '匯出工具常見輸出，Dart String.trim() 不會移除 BOM）', () {
    const content = '\uFEFF---\ntitle: 有 BOM\n---\n內容';
    final result = parseMdFrontmatter(content);
    expect(result.frontmatter.title, '有 BOM');
    expect(result.body.trim(), '內容');
  });

  test('沒有 Frontmatter 但開頭帶 BOM 時，BOM 仍被剝除，不殘留於 body', () {
    const content = '\uFEFF# 標題\n內容';
    final result = parseMdFrontmatter(content);
    expect(result.frontmatter.title, isNull);
    expect(result.body, '# 標題\n內容');
  });

  test('Frontmatter 只有部分欄位時，其餘欄位為 null', () {
    const content = '---\ntitle: 只有標題\n---\n內容';
    final result = parseMdFrontmatter(content);
    expect(result.frontmatter.title, '只有標題');
    expect(result.frontmatter.author, isNull);
  });
}
```

- [ ] **Step 2：確認測試失敗**

```bash
cd "U:/MyDeveloper/AI/elinkBook/app"
flutter test test/library/md_frontmatter_test.dart
```

Expected：FAIL（`md_frontmatter.dart` 不存在，編譯錯誤）。

- [ ] **Step 3：`yaml` 套件由 transitive 升級為直接 dependency**

`app/pubspec.yaml` 的 `dependencies:` 區塊，緊接在既有 `archive: ^4.0.9` 之後新增：

```yaml
  # MD Frontmatter 解析（epic-11-multi-format-reader Issue 5）：由既有
  # transitive dependency（既有套件鏈間接引入）升級為正式 dependency，
  # 本 Issue 起成為正式匯入管線的執行期依賴。
  yaml: ^3.1.3
```

```bash
flutter pub get
```

- [ ] **Step 4：實作**

```dart
// app/lib/library/md_frontmatter.dart
import 'dart:convert';
import 'dart:typed_data';

import 'package:yaml/yaml.dart';

class MdFrontmatter {
  final String? title;
  final String? author;

  /// 僅支援 `data:` URI（例如 `data:image/png;base64,...`）——單檔匯入
  /// 無法存取相對路徑指向的外部圖片檔案（spec.md「Out of Scope」：MD
  /// 內嵌本機相對路徑圖片的優雅降級明確排除於本 Issue 範圍），故其他
  /// 型態的 `cover` 值一律忽略，`coverBytes` 為 `null`。
  final Uint8List? coverBytes;

  const MdFrontmatter({this.title, this.author, this.coverBytes});
}

class MdParsedDocument {
  final MdFrontmatter frontmatter;

  /// Frontmatter 區塊（含起訖 `---` 分隔線）之後的實際 Markdown 內容；
  /// 找不到合法 Frontmatter 區塊時為原始輸入內容全文。
  final String body;

  const MdParsedDocument({required this.frontmatter, required this.body});
}

/// 解析 [content] 開頭的 YAML Frontmatter 區塊（以 `---` 起訖，常見
/// Jekyll/Hugo 慣例）。找不到合法區塊（開頭非 `---`、或找不到對應的結尾
/// `---`）時，`frontmatter` 全為 null、`body` 為原始內容全文；YAML 內容
/// 本身格式錯誤時，`frontmatter` 全為 null 但仍剝離起訖線（比照常見 MD
/// 編輯器對錯誤 Frontmatter 的寬容態度，不中止匯入、不把原始 YAML 文字
/// 誤植入最終顯示內容）。
MdParsedDocument parseMdFrontmatter(String content) {
  // 部分 Windows 編輯器／匯出工具產生的 .md 檔案開頭帶 UTF-8 BOM
  // （U+FEFF）；Dart 的 String.trim() 不會移除它（Unicode White_Space
  // 屬性為 false），若不先剝除會讓下方 `lines.first.trim() != '---'`
  // 誤判為沒有 Frontmatter（審查修正，見
  // reviews/review-issue-5-plan.md Important #2）。
  final normalized = content.startsWith('\uFEFF') ? content.substring(1) : content;
  final lines = normalized.split(RegExp(r'\r\n|\r|\n'));
  if (lines.isEmpty || lines.first.trim() != '---') {
    return MdParsedDocument(frontmatter: const MdFrontmatter(), body: normalized);
  }
  var endIndex = -1;
  for (var i = 1; i < lines.length; i++) {
    if (lines[i].trim() == '---') {
      endIndex = i;
      break;
    }
  }
  if (endIndex == -1) {
    return MdParsedDocument(frontmatter: const MdFrontmatter(), body: normalized);
  }

  final yamlText = lines.sublist(1, endIndex).join('\n');
  final body = lines.sublist(endIndex + 1).join('\n');

  try {
    final doc = loadYaml(yamlText);
    if (doc is! YamlMap) {
      return MdParsedDocument(frontmatter: const MdFrontmatter(), body: body);
    }
    final title = doc['title']?.toString();
    final author = doc['author']?.toString();
    final coverValue = doc['cover']?.toString();
    final coverBytes =
        coverValue != null && coverValue.startsWith('data:') ? _decodeDataUri(coverValue) : null;
    return MdParsedDocument(
      frontmatter: MdFrontmatter(title: title, author: author, coverBytes: coverBytes),
      body: body,
    );
  } on YamlException {
    return MdParsedDocument(frontmatter: const MdFrontmatter(), body: body);
  }
}

Uint8List? _decodeDataUri(String value) {
  final commaIndex = value.indexOf(',');
  if (commaIndex == -1) return null;
  final meta = value.substring('data:'.length, commaIndex);
  if (!meta.contains('base64')) return null;
  try {
    return base64Decode(value.substring(commaIndex + 1));
  } on FormatException {
    return null;
  }
}
```

- [ ] **Step 5：確認測試通過**

```bash
flutter test test/library/md_frontmatter_test.dart
```

Expected：PASS（7 個測試）。

- [ ] **Step 6：`flutter analyze`**

```bash
flutter analyze
```

Expected：無新增 issue。

- [ ] **Step 7：Commit**

```bash
git add app/lib/library/md_frontmatter.dart app/test/library/md_frontmatter_test.dart app/pubspec.yaml app/pubspec.lock
git commit -m "feat(epic-11): Issue 5——YAML Frontmatter 解析 parseMdFrontmatter"
```

---

## Task 4：Markdown 解析與標題階層/章節切分

**Files:**
- Create: `app/lib/library/md_toc_builder.dart`
- Test: `app/test/library/md_toc_builder_test.dart`

**Interfaces:**
- Produces：`class MdHeading { int level; String text; String anchorId; int sectionIndex; }`；`class MdSection { String? title; List<md.Node> nodes; }`；`class MdParseResult { List<MdSection> sections; List<MdHeading> headings; }`；`MdParseResult parseMdIntoSections(String markdownBody)`（供 Task 5 `md_epub_synthesizer.dart` 消費）。

- [ ] **Step 1：`markdown` 套件新增為 dependency**

`app/pubspec.yaml` 的 `dependencies:` 區塊，緊接在 Task 3 新增的 `yaml: ^3.1.3` 之後新增：

```yaml
  # Markdown 解析（epic-11-multi-format-reader Issue 5）：Dart 官方純
  # Dart AST 解析器，用於 MD 匯入時的章節/標題階層抽取與 HTML 渲染，
  # 已查證預設輸出為合法 XHTML（見 Global Constraints 已查證事實 #1）。
  markdown: ^7.3.1
```

```bash
cd "U:/MyDeveloper/AI/elinkBook/app"
flutter pub get
```

- [ ] **Step 2：寫失敗測試**

```dart
// app/test/library/md_toc_builder_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:elinkbook/library/md_toc_builder.dart';

void main() {
  group('parseMdIntoSections：章節切分', () {
    test('無標題時回傳單一 section，title 為 null，headings 為空', () {
      final result = parseMdIntoSections('這是一段沒有標題的內容。\n\n第二段。');
      expect(result.sections, hasLength(1));
      expect(result.sections.single.title, isNull);
      expect(result.headings, isEmpty);
    });

    test('多個 H1 依序切分為多個 section', () {
      final result = parseMdIntoSections('# 第一章\n內容一\n\n# 第二章\n內容二');
      expect(result.sections, hasLength(2));
      expect(result.sections[0].title, '第一章');
      expect(result.sections[1].title, '第二章');
    });

    test('第一個標題之前的內容獨立成一個無標題的前言 section（比照 '
        'txt_chapter_splitter.dart 對前言的既有處置慣例：'
        '"if (matches.first.start > 0) { chapters.add(TxtChapter(...)); }"，'
        '前言獨立成一則 title 為 null 的章節，不與第一個標題章節合併）', () {
      final result = parseMdIntoSections('前言內容\n\n# 第一章\n內容一');
      expect(result.sections, hasLength(2));
      expect(result.sections[0].title, isNull);
      expect(result.sections[1].title, '第一章');
      expect(result.headings.single.sectionIndex, 1);
    });

    test('文件只用 H2 起始各段落時，切分基準是 H2（最淺標題層級），非強制 H1', () {
      final result = parseMdIntoSections('## 段落 A\n內容 A\n\n## 段落 B\n內容 B');
      expect(result.sections, hasLength(2));
      expect(result.sections[0].title, '段落 A');
      expect(result.sections[1].title, '段落 B');
    });

    test('H2/H3 巢狀於 H1 之下時不獨立成 section，仍在同一個 section 內', () {
      final result = parseMdIntoSections('# 第一章\n## 子章節 A\n內容\n## 子章節 B\n內容');
      expect(result.sections, hasLength(1));
      expect(result.sections.single.title, '第一章');
    });
  });

  group('parseMdIntoSections：標題階層與 id', () {
    test('每個標題皆取得唯一、依序編號的 anchorId', () {
      final result = parseMdIntoSections('# A\n## B\n# C');
      expect(result.headings.map((h) => h.anchorId).toSet(), hasLength(3));
      expect(result.headings.map((h) => h.anchorId), ['heading_0001', 'heading_0002', 'heading_0003']);
    });

    test('重複標題文字仍各自取得不同 anchorId（不依賴內建 slug 去重機制）', () {
      final result = parseMdIntoSections('# 概述\n內容一\n\n# 概述\n內容二');
      final ids = result.headings.map((h) => h.anchorId).toList();
      expect(ids[0], isNot(ids[1]));
      expect(result.headings[0].text, '概述');
      expect(result.headings[1].text, '概述');
    });

    test('標題層級（level）正確對應 H1-H6', () {
      final result = parseMdIntoSections('# H1\n## H2\n### H3\n#### H4\n##### H5\n###### H6');
      expect(result.headings.map((h) => h.level), [1, 2, 3, 4, 5, 6]);
    });

    test('標題所屬 sectionIndex 正確——巢狀子標題與其所屬頂層標題同一個 index', () {
      final result = parseMdIntoSections('# 第一章\n## 子章節\n# 第二章');
      expect(result.headings, hasLength(3));
      expect(result.headings[0].sectionIndex, 0); // 第一章
      expect(result.headings[1].sectionIndex, 0); // 子章節（仍在第一章的 section）
      expect(result.headings[2].sectionIndex, 1); // 第二章
    });
  });

  group('parseMdIntoSections：內容保留', () {
    test('每個 section 的 nodes 皆非空（切分後不遺漏內容節點）', () {
      final result = parseMdIntoSections('# 第一章\n第一段\n\n第二段\n\n# 第二章\n第三段');
      for (final section in result.sections) {
        expect(section.nodes, isNotEmpty);
      }
    });
  });
}
```

- [ ] **Step 3：確認測試失敗**

```bash
flutter test test/library/md_toc_builder_test.dart
```

Expected：FAIL（`md_toc_builder.dart` 不存在，編譯錯誤）。

- [ ] **Step 4：實作**

```dart
// app/lib/library/md_toc_builder.dart
import 'package:markdown/markdown.dart' as md;

class MdHeading {
  final int level;
  final String text;
  final String anchorId;
  final int sectionIndex;
  const MdHeading({
    required this.level,
    required this.text,
    required this.anchorId,
    required this.sectionIndex,
  });
}

class MdSection {
  /// `null` 代表這是唯一一個 section 且文件內完全沒有偵測到標題（見
  /// [parseMdIntoSections] 文件註解）。
  final String? title;
  final List<md.Node> nodes;
  const MdSection({this.title, required this.nodes});
}

class MdParseResult {
  final List<MdSection> sections;
  final List<MdHeading> headings;
  const MdParseResult({required this.sections, required this.headings});
}

int? _headingLevel(String tag) {
  if (tag.length != 2 || tag[0] != 'h') return null;
  final n = int.tryParse(tag[1]);
  return (n != null && n >= 1 && n <= 6) ? n : null;
}

String _textContent(md.Node node) {
  if (node is md.Text) return node.text;
  if (node is md.Element) {
    return (node.children ?? const <md.Node>[]).map(_textContent).join();
  }
  return '';
}

/// 解析 [markdownBody]（**不含** Frontmatter，呼叫端須先用
/// `parseMdFrontmatter()` 剝離）為 AST，依「文件內出現過的最淺標題層級」
/// 把頂層區塊節點切分成多個 [MdSection]（例如文件只用 H2 起始各段落時，
/// 切分基準是 H2，非強制 H1，見 Global Constraints 已查證事實 #4——頂層
/// 節點清單本身即為切分依據，不需遞迴）；完全沒有標題時回傳單一
/// section（`title: null`）。每個標題（含巢狀於 section 內、非切分層級
/// 的子標題）皆依文件出現順序指派唯一 `anchorId`（`heading_0001` 起算，
/// 見 Global Constraints 已查證事實 #3 對捨棄內建 slug id 機制的理由），
/// 並直接寫入該標題 Element 的 `attributes['id']`（同時清空
/// `generatedId`，避免渲染時重複輸出兩個 `id` 屬性）。
MdParseResult parseMdIntoSections(String markdownBody) {
  final document = md.Document(extensionSet: md.ExtensionSet.gitHubWeb);
  final topLevelNodes = document.parse(markdownBody);

  final topLevelLevels = topLevelNodes
      .map((n) => n is md.Element ? _headingLevel(n.tag) : null)
      .toList();
  int? minLevel;
  for (final level in topLevelLevels) {
    if (level == null) continue;
    if (minLevel == null || level < minLevel) minLevel = level;
  }

  final headings = <MdHeading>[];
  var headingCounter = 0;

  void assignHeadingIds(md.Node node, int sectionIndex) {
    if (node is md.Element) {
      final level = _headingLevel(node.tag);
      if (level != null) {
        headingCounter++;
        final id = 'heading_${headingCounter.toString().padLeft(4, '0')}';
        node.generatedId = null;
        node.attributes['id'] = id;
        headings.add(MdHeading(
          level: level,
          text: _textContent(node),
          anchorId: id,
          sectionIndex: sectionIndex,
        ));
      }
      for (final child in node.children ?? const <md.Node>[]) {
        assignHeadingIds(child, sectionIndex);
      }
    }
  }

  final sections = <MdSection>[];
  var currentNodes = <md.Node>[];
  String? currentTitle;
  var sectionIndex = -1;

  void flushSection() {
    if (currentNodes.isNotEmpty) {
      sections.add(MdSection(title: currentTitle, nodes: currentNodes));
    }
  }

  for (var i = 0; i < topLevelNodes.length; i++) {
    final node = topLevelNodes[i];
    final level = topLevelLevels[i];
    if (minLevel != null && level == minLevel) {
      flushSection();
      sectionIndex++;
      currentNodes = [node];
      currentTitle = _textContent(node);
    } else {
      if (sectionIndex == -1) sectionIndex = 0;
      currentNodes.add(node);
    }
    assignHeadingIds(node, sectionIndex);
  }
  flushSection();

  if (sections.isEmpty) {
    sections.add(MdSection(nodes: topLevelNodes));
  }

  return MdParseResult(sections: sections, headings: headings);
}
```

- [ ] **Step 5：確認測試通過**

```bash
flutter test test/library/md_toc_builder_test.dart
```

Expected：PASS（10 個測試）。

- [ ] **Step 6：`flutter analyze`**

```bash
flutter analyze
```

Expected：無新增 issue。

- [ ] **Step 7：Commit**

```bash
git add app/lib/library/md_toc_builder.dart app/test/library/md_toc_builder_test.dart app/pubspec.yaml app/pubspec.lock
git commit -m "feat(epic-11): Issue 5——Markdown 標題階層解析與章節切分 parseMdIntoSections"
```

---

## Task 5：MD → EPUB 合成（巢狀目錄樹＋程式碼/表格 CSS 覆蓋）

**Files:**
- Create: `app/lib/library/md_epub_synthesizer.dart`
- Test: `app/test/library/md_epub_synthesizer_test.dart`

**Interfaces:**
- Consumes：`parseMdFrontmatter`／`MdFrontmatter`（Task 3）；`parseMdIntoSections`／`MdHeading`／`MdSection`（Task 4）；`kEpubContainerXml`／`buildEpubContentOpf`／`buildEpubNavXhtml`／`escapeXml`（Task 1）；`readContentUriBytes`（Issue 4 既有）。
- Produces：`class MdSynthesisResult { Uint8List epubBytes; String? frontmatterTitle; String? frontmatterAuthor; Uint8List? frontmatterCoverBytes; }`；`class EmptyMdException implements Exception`；`Future<MdSynthesisResult> synthesizeMdBook(String filePath, String bookId, String fallbackTitle)`（供 Task 6 `book_import_service_impl.dart` 消費）。

- [ ] **Step 1：寫失敗測試**

```dart
// app/test/library/md_epub_synthesizer_test.dart
import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:xml/xml.dart';
import 'package:elinkbook/library/md_epub_synthesizer.dart';

import '../support/fake_path_provider_platform.dart';

const _channel = MethodChannel('elinkbook/book_metadata');

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Archive decodeArchive(MdSynthesisResult result) => ZipDecoder().decodeBytes(result.epubBytes);

  String readEntry(Archive archive, String name) =>
      utf8.decode(archive.findFile(name)!.readBytes()!);

  test('合成結果為結構正確的 EPUB：container.xml 指向 OEBPS/content.opf', () async {
    final mdFile = File('${Directory.systemTemp.path}/synth_md_basic.md');
    await mdFile.writeAsBytes(utf8.encode('# 第一章\n內容一\n\n# 第二章\n內容二'));
    addTearDown(() => mdFile.delete());

    final result = await synthesizeMdBook(mdFile.path, 'book1', '備用標題');
    final archive = decodeArchive(result);

    expect(archive.findFile('mimetype'), isNotNull);
    final containerDoc = XmlDocument.parse(readEntry(archive, 'META-INF/container.xml'));
    expect(containerDoc.findAllElements('rootfile').single.getAttribute('full-path'), 'OEBPS/content.opf');
  });

  test('沒有 Frontmatter 時，OPF 的 dc:title 使用呼叫端傳入的備用標題', () async {
    final mdFile = File('${Directory.systemTemp.path}/synth_md_fallback_title.md');
    await mdFile.writeAsBytes(utf8.encode('# 內容\n沒有 frontmatter'));
    addTearDown(() => mdFile.delete());

    final result = await synthesizeMdBook(mdFile.path, 'book2', '備用標題');
    final archive = decodeArchive(result);
    final opfDoc = XmlDocument.parse(readEntry(archive, 'OEBPS/content.opf'));

    expect(opfDoc.findAllElements('dc:title').single.innerText, '備用標題');
    expect(result.frontmatterTitle, isNull);
  });

  test('有 Frontmatter 時，OPF 的 dc:title 優先使用 Frontmatter 標題', () async {
    final mdFile = File('${Directory.systemTemp.path}/synth_md_fm_title.md');
    await mdFile.writeAsBytes(
      utf8.encode('---\ntitle: Frontmatter 標題\nauthor: 作者甲\n---\n# 內容\n正文'),
    );
    addTearDown(() => mdFile.delete());

    final result = await synthesizeMdBook(mdFile.path, 'book3', '備用標題');
    final archive = decodeArchive(result);
    final opfDoc = XmlDocument.parse(readEntry(archive, 'OEBPS/content.opf'));

    expect(opfDoc.findAllElements('dc:title').single.innerText, 'Frontmatter 標題');
    expect(result.frontmatterTitle, 'Frontmatter 標題');
    expect(result.frontmatterAuthor, '作者甲');
  });

  test('多個 H1 各自產生獨立的 XHTML spine 項目與扁平目錄項', () async {
    final mdFile = File('${Directory.systemTemp.path}/synth_md_sections.md');
    await mdFile.writeAsBytes(utf8.encode('# 第一章\n內容一\n\n# 第二章\n內容二'));
    addTearDown(() => mdFile.delete());

    final result = await synthesizeMdBook(mdFile.path, 'book4', '備用標題');
    final archive = decodeArchive(result);
    final opfDoc = XmlDocument.parse(readEntry(archive, 'OEBPS/content.opf'));
    final navDoc = XmlDocument.parse(readEntry(archive, 'OEBPS/nav.xhtml'));

    expect(
      opfDoc.findAllElements('item').where((e) => e.getAttribute('href')?.startsWith('text/') ?? false),
      hasLength(2),
    );
    final links = navDoc.findAllElements('a').toList();
    expect(links.map((e) => e.innerText), ['第一章', '第二章']);
  });

  test('巢狀標題（H1 下有 H2）產生巢狀 <ol> 目錄結構', () async {
    final mdFile = File('${Directory.systemTemp.path}/synth_md_nested_toc.md');
    await mdFile.writeAsBytes(utf8.encode('# 第一章\n## 子章節 A\n內容\n## 子章節 B\n內容'));
    addTearDown(() => mdFile.delete());

    final result = await synthesizeMdBook(mdFile.path, 'book5', '備用標題');
    final archive = decodeArchive(result);
    final navDoc = XmlDocument.parse(readEntry(archive, 'OEBPS/nav.xhtml'));

    final topLevelOl = navDoc.findAllElements('nav').single.findElements('ol').single;
    final topLevelItems = topLevelOl.findElements('li');
    expect(topLevelItems, hasLength(1)); // 只有「第一章」在頂層
    final nestedOl = topLevelItems.single.findElements('ol').single;
    expect(nestedOl.findElements('li').map((e) => e.findElements('a').single.innerText),
        ['子章節 A', '子章節 B']);
  });

  test('章節內文含標題錨點 id，與目錄連結的 # 片段一致', () async {
    final mdFile = File('${Directory.systemTemp.path}/synth_md_anchor.md');
    await mdFile.writeAsBytes(utf8.encode('# 第一章\n內容'));
    addTearDown(() => mdFile.delete());

    final result = await synthesizeMdBook(mdFile.path, 'book6', '備用標題');
    final archive = decodeArchive(result);
    final navDoc = XmlDocument.parse(readEntry(archive, 'OEBPS/nav.xhtml'));
    final href = navDoc.findAllElements('a').single.getAttribute('href')!;
    final parts = href.split('#');
    expect(parts, hasLength(2));

    final chapterDoc = XmlDocument.parse(readEntry(archive, 'OEBPS/${parts[0]}'));
    final heading = chapterDoc.findAllElements('h1').single;
    expect(heading.getAttribute('id'), parts[1]);
  });

  test('程式碼區塊與表格的 XHTML 內含強制橫排的 <style> 規則', () async {
    final mdFile = File('${Directory.systemTemp.path}/synth_md_code_table.md');
    await mdFile.writeAsBytes(utf8.encode(
      '# 第一章\n```python\nprint(1)\n```\n\n| A | B |\n| --- | --- |\n| 1 | 2 |',
    ));
    addTearDown(() => mdFile.delete());

    final result = await synthesizeMdBook(mdFile.path, 'book7', '備用標題');
    final archive = decodeArchive(result);
    final opfDoc = XmlDocument.parse(readEntry(archive, 'OEBPS/content.opf'));
    final href = opfDoc
        .findAllElements('item')
        .firstWhere((e) => e.getAttribute('href')?.startsWith('text/') ?? false)
        .getAttribute('href')!;
    final chapterXhtmlRaw = readEntry(archive, 'OEBPS/$href');

    expect(chapterXhtmlRaw, contains('writing-mode: horizontal-tb'));
    expect(chapterXhtmlRaw, contains('direction: ltr'));
    final chapterDoc = XmlDocument.parse(chapterXhtmlRaw);
    expect(chapterDoc.findAllElements('pre'), isNotEmpty);
    expect(chapterDoc.findAllElements('table'), isNotEmpty);
  });

  test('XML 特殊字元（&/</>）在標題與內文中正確逸出，可被正常解析', () async {
    final mdFile = File('${Directory.systemTemp.path}/synth_md_escape.md');
    await mdFile.writeAsBytes(utf8.encode('# A&B<C>\n內容含 & < > 符號'));
    addTearDown(() => mdFile.delete());

    final result = await synthesizeMdBook(mdFile.path, 'book8', '備用標題');
    final archive = decodeArchive(result);
    final navDoc = XmlDocument.parse(readEntry(archive, 'OEBPS/nav.xhtml'));
    expect(navDoc.findAllElements('a').single.innerText, 'A&B<C>');
  });

  test('Frontmatter cover 為 data: URI 時正確回傳於 frontmatterCoverBytes', () async {
    final pngBytes = [0x89, 0x50, 0x4E, 0x47];
    final base64Data = base64Encode(pngBytes);
    final mdFile = File('${Directory.systemTemp.path}/synth_md_cover.md');
    await mdFile.writeAsBytes(
      utf8.encode('---\ntitle: 有封面\ncover: data:image/png;base64,$base64Data\n---\n# 內容\n正文'),
    );
    addTearDown(() => mdFile.delete());

    final result = await synthesizeMdBook(mdFile.path, 'book9', '備用標題');

    expect(result.frontmatterCoverBytes, pngBytes);
  });

  test('空白 Markdown 檔案（去除 Frontmatter 後無實際內容）拋出 EmptyMdException', () async {
    final mdFile = File('${Directory.systemTemp.path}/synth_md_empty.md');
    await mdFile.writeAsBytes(utf8.encode('---\ntitle: 空內容\n---\n   \n\n   '));
    addTearDown(() => mdFile.delete());

    expect(
      () => synthesizeMdBook(mdFile.path, 'book10', '備用標題'),
      throwsA(isA<EmptyMdException>()),
    );
  });

  group('content:// URI 支援', () {
    late Directory tempDir;
    late PathProviderPlatform originalPathProvider;

    setUp(() {
      tempDir = Directory.systemTemp.createTempSync('md_synth_test_tmp');
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
        await File(args['destinationPath'] as String).writeAsBytes(utf8.encode('# 內容\n正文'));
        return null;
      });

      final result = await synthesizeMdBook('content://example/note.md', 'book11', '備用標題');
      final archive = decodeArchive(result);

      expect(archive.findFile('OEBPS/content.opf'), isNotNull);
    });
  });
}
```

- [ ] **Step 2：確認測試失敗**

```bash
flutter test test/library/md_epub_synthesizer_test.dart
```

Expected：FAIL（`md_epub_synthesizer.dart` 不存在，編譯錯誤）。

- [ ] **Step 3：實作**

```dart
// app/lib/library/md_epub_synthesizer.dart
import 'dart:convert';
import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:markdown/markdown.dart' as md;

import 'content_uri_reader.dart';
import 'epub_container_builder.dart';
import 'md_frontmatter.dart';
import 'md_toc_builder.dart';

/// Markdown 檔案解碼後找不到任何非空白內容時拋出——沒有內容的書本質上
/// 無法開啟，呼叫端（book_import_service_impl.dart）應中止匯入、不建立
/// Book 記錄，比照 `EmptyTxtException`（epic-11 Issue 4）既有處置慣例。
class EmptyMdException implements Exception {
  final String message;
  const EmptyMdException(this.message);
  @override
  String toString() => 'EmptyMdException: $message';
}

class MdSynthesisResult {
  /// 合成後的 EPUB 壓縮檔完整位元組內容，供呼叫端落地為 `Book.filePath`
  /// 指向的衍生檔案（**檔名副檔名須維持 `.md`**，比照 Issue 4 TXT 的既有
  /// 限制理由：`BookFormat.md` 的分派依 `Book.filePath` 副檔名判斷）。
  final Uint8List epubBytes;

  /// Frontmatter 解析結果，供呼叫端決定書名/作者/封面（`null` 代表該欄位
  /// 未於 Frontmatter 指定，呼叫端應使用既有退回機制）。
  final String? frontmatterTitle;
  final String? frontmatterAuthor;
  final Uint8List? frontmatterCoverBytes;

  const MdSynthesisResult({
    required this.epubBytes,
    this.frontmatterTitle,
    this.frontmatterAuthor,
    this.frontmatterCoverBytes,
  });
}

/// 強制程式碼區塊與表格在直排模式下維持橫排、可橫向捲動（spec.md
/// 「TXT／Markdown 合成書籍結構」對 MD 的既有要求）——寫在每個章節 XHTML
/// 自己的 `<head>`，不依賴本專案既有的全域 `buildOverrideCss()` 機制
/// （後者由使用者版面設定驅動，此處是格式本身固有的排版規則，兩者概念
/// 不同，不應混用同一套注入路徑）。
const String _kCodeTableCss = '<style>'
    'pre, code, table { writing-mode: horizontal-tb; direction: ltr; } '
    'pre, table { overflow-x: auto; display: block; max-width: 100%; } '
    // GFM 表格在無邊框 CSS 時於部分 WebView 預設無格線可辨識（審查建議，
    // 見 reviews/review-issue-5-plan.md Minor #1），補上基礎格線樣式。
    'table { border-collapse: collapse; } '
    'th, td { border: 1px solid currentColor; padding: 4px 8px; }'
    '</style>';

class _TocNode {
  final MdHeading? heading;
  final List<_TocNode> children = [];
  _TocNode([this.heading]);
}

_TocNode _buildTocTree(List<MdHeading> headings) {
  final root = _TocNode();
  final stack = <_TocNode>[root];
  final levels = <int>[0];
  for (final heading in headings) {
    while (levels.last >= heading.level) {
      stack.removeLast();
      levels.removeLast();
    }
    final node = _TocNode(heading);
    stack.last.children.add(node);
    stack.add(node);
    levels.add(heading.level);
  }
  return root;
}

/// 遞迴渲染 [node] 的子節點為 `<li>` 序列（不含最外層 `<ol>`——最外層由
/// `buildEpubNavXhtml()` 既有模板提供，見呼叫處）；子節點自身若還有更深
/// 層的子節點，則巢狀輸出一層 `<ol>`。
String _renderTocChildren(_TocNode node, List<String> sectionHrefs) {
  final buffer = StringBuffer();
  for (final child in node.children) {
    final heading = child.heading!;
    final href = '${sectionHrefs[heading.sectionIndex]}#${heading.anchorId}';
    buffer.write('<li><a href="$href">${escapeXml(heading.text)}</a>');
    if (child.children.isNotEmpty) {
      buffer.writeln();
      buffer.writeln('<ol>');
      buffer.write(_renderTocChildren(child, sectionHrefs));
      buffer.writeln('</ol>');
    }
    buffer.writeln('</li>');
  }
  return buffer.toString();
}

String _sectionXhtml(List<md.Node> nodes) => '''<?xml version="1.0" encoding="UTF-8"?>
<html xmlns="http://www.w3.org/1999/xhtml">
<head><title>內容</title>
$_kCodeTableCss
</head>
<body>
${md.renderToHtml(nodes)}
</body>
</html>
''';

/// 純 CPU 運算（Frontmatter／Markdown 解析＋章節切分＋EPUB 結構產生），
/// 外包至 `Isolate.run()` 背景執行（見呼叫處 [synthesizeMdBook] 註解，
/// 比照 Issue 4 `_decodeAndSynthesize()` 既有作法）。頂層純函式、僅接受
/// 可跨 isolate 傳遞的 [Uint8List]／[String] 參數。
MdSynthesisResult _decodeAndSynthesize(Uint8List bytes, String bookId, String fallbackTitle) {
  final rawContent = utf8.decode(bytes, allowMalformed: true);
  final parsedDoc = parseMdFrontmatter(rawContent);
  final parseResult = parseMdIntoSections(parsedDoc.body);

  final hasContent = parseResult.sections.any((s) => s.nodes.isNotEmpty);
  if (!hasContent) {
    throw const EmptyMdException('Markdown 檔案內容為空');
  }

  final archive = Archive();
  archive.addFile(
    ArchiveFile.bytes('mimetype', utf8.encode('application/epub+zip'))
      ..compression = CompressionType.none,
  );
  archive.addFile(ArchiveFile.bytes('META-INF/container.xml', utf8.encode(kEpubContainerXml)));

  final sectionHrefs = <String>[];
  final manifestItems = StringBuffer();
  final spineItems = StringBuffer();

  for (var i = 0; i < parseResult.sections.length; i++) {
    final id = 'sec${(i + 1).toString().padLeft(4, '0')}';
    final href = 'text/$id.xhtml';
    sectionHrefs.add(href);
    archive.addFile(
      ArchiveFile.bytes('OEBPS/$href', utf8.encode(_sectionXhtml(parseResult.sections[i].nodes))),
    );
    manifestItems.writeln('<item id="$id" href="$href" media-type="application/xhtml+xml"/>');
    spineItems.writeln('<itemref idref="$id"/>');
  }

  final tocTree = _buildTocTree(parseResult.headings);
  final navItems = _renderTocChildren(tocTree, sectionHrefs);
  archive.addFile(ArchiveFile.bytes('OEBPS/nav.xhtml', utf8.encode(buildEpubNavXhtml(navItems))));

  final title = parsedDoc.frontmatter.title ?? fallbackTitle;
  archive.addFile(ArchiveFile.bytes(
    'OEBPS/content.opf',
    utf8.encode(buildEpubContentOpf(
      identifier: 'elinkbook-md-$bookId',
      title: title,
      manifestItems: manifestItems.toString(),
      spineItems: spineItems.toString(),
    )),
  ));

  return MdSynthesisResult(
    epubBytes: ZipEncoder().encodeBytes(archive),
    frontmatterTitle: parsedDoc.frontmatter.title,
    frontmatterAuthor: parsedDoc.frontmatter.author,
    frontmatterCoverBytes: parsedDoc.frontmatter.coverBytes,
  );
}

/// 讀取 [filePath]（本機路徑或 `content://` URI）指向的 Markdown 檔案，
/// 解析 Frontmatter 與標題階層，合成一份最小合法 EPUB3 壓縮檔。[bookId]
/// 用於 OPF `dc:identifier`，[fallbackTitle] 於 Frontmatter 未指定標題時
/// 使用（呼叫端傳入依檔名推導的既有慣例，比照 Issue 4
/// `titleFromFileName()` 用法）。**MD 內容一律假設 UTF-8 編碼**（寬鬆解碼，
/// 不拋出例外）——不比照 TXT 的多編碼偵測梯隊，因 Markdown 是與現代
/// UTF-8-centric 工具鏈緊密綁定的格式，Big5 等舊編碼的 Markdown 檔案
/// 在實務上極為罕見，issues.md Issue 5 範圍本身也未要求此能力（YAGNI）。
/// CPU 密集運算外包至 `Isolate.run()`。
Future<MdSynthesisResult> synthesizeMdBook(
  String filePath,
  String bookId,
  String fallbackTitle,
) async {
  final bytes = filePath.contains('://')
      ? await readContentUriBytes(filePath, tempFilePrefix: 'md_probe', tempFileExtension: '.md')
      : await File(filePath).readAsBytes();
  return Isolate.run(() => _decodeAndSynthesize(bytes, bookId, fallbackTitle));
}
```

- [ ] **Step 4：確認測試通過**

```bash
flutter test test/library/md_epub_synthesizer_test.dart
```

Expected：PASS（11 個測試）。

- [ ] **Step 5：`flutter analyze`**

```bash
flutter analyze
```

Expected：無新增 issue。

- [ ] **Step 6：Commit**

```bash
git add app/lib/library/md_epub_synthesizer.dart app/test/library/md_epub_synthesizer_test.dart
git commit -m "feat(epic-11): Issue 5——MD 合成為最小合法 EPUB3 結構 synthesizeMdBook（巢狀目錄＋程式碼/表格 CSS）"
```

---

## Task 6：匯入管線接上 MD 合成

**Files:**
- Modify: `app/lib/library/book_import_service_impl.dart`
- Test: `app/test/library/book_import_service_test.dart`

**Interfaces:**
- Consumes：`synthesizeMdBook`／`MdSynthesisResult`／`EmptyMdException`（Task 5）。
- Produces：MD 書籍 `Book.isFixedLayout == false`、`Book.filePath` 指向落地後合成的 `.md` 檔案（`imported_books/` 既有目錄，`$id.md`）、`Book.contentFingerprint` 對原始輸入檔案計算。

- [ ] **Step 1：`detectBookFileFormat` 新增 `.md`**

`app/lib/library/book_import_service_impl.dart` 修改 `detectBookFileFormat()`：

```dart
BookFileFormat? detectBookFileFormat(String uriOrPath) {
  final name = _lastPathComponent(uriOrPath).toLowerCase();
  if (name.endsWith('.epub')) return BookFileFormat.epub;
  if (name.endsWith('.pdf')) return BookFileFormat.pdf;
  if (name.endsWith('.txt')) return BookFileFormat.txt;
  if (name.endsWith('.azw3')) return BookFileFormat.azw3;
  if (name.endsWith('.cbz')) return BookFileFormat.cbz;
  if (name.endsWith('.md')) return BookFileFormat.md;
  return null;
}
```

- [ ] **Step 2：寫失敗測試**

於 `app/test/library/book_import_service_test.dart` 頂部 import 區塊確認已有 `import 'package:archive/archive.dart' show ZipDecoder';`（Issue 4 已新增，若無則補上）。在既有 `group('TXT 匯入', () { ... });` 之後、`main()` 結尾 `}` 之前新增：

```dart
  group('MD 匯入', () {
    test('匯入有效 MD：format=md、isFixedLayout=false、filePath 指向合成後的 .md 檔案', () async {
      final mdFile = File('${Directory.systemTemp.path}/import_test.md');
      await mdFile.writeAsBytes(utf8.encode('# 第一章\n內容'));
      addTearDown(() => mdFile.delete());

      final result = await service.importFiles([mdFile.path], displayNames: ['notes.md']);

      expect(result.importedBooks, hasLength(1));
      final book = result.importedBooks.first;
      expect(book.format, BookFileFormat.md);
      expect(book.isFixedLayout, isFalse);
      expect(book.filePath, isNot(mdFile.path));
      expect(book.filePath, endsWith('.md'));
      expect(File(book.filePath).existsSync(), isTrue);
      final archive = ZipDecoder().decodeBytes(await File(book.filePath).readAsBytes());
      expect(archive.findFile('OEBPS/content.opf'), isNotNull);
    });

    test('Frontmatter 標題/作者正確寫入 Book，無 Frontmatter 時使用檔名標題', () async {
      final mdFile = File('${Directory.systemTemp.path}/import_test_fm.md');
      await mdFile.writeAsBytes(
        utf8.encode('---\ntitle: 我的筆記\nauthor: 作者甲\n---\n# 內容\n正文'),
      );
      addTearDown(() => mdFile.delete());

      final result = await service.importFiles([mdFile.path], displayNames: ['notes_fm.md']);

      final book = result.importedBooks.first;
      expect(book.title, '我的筆記');
      expect(book.author, '作者甲');
    });

    test('無 Frontmatter 封面時，封面退回依書名文字動態產生（比照 TXT 既有機制）', () async {
      final mdFile = File('${Directory.systemTemp.path}/import_test_cover_fallback.md');
      await mdFile.writeAsBytes(utf8.encode('# 內容\n正文'));
      addTearDown(() => mdFile.delete());

      final result = await service.importFiles([mdFile.path], displayNames: ['notes_cover.md']);

      final book = result.importedBooks.first;
      expect(book.coverPath, isNotNull);
      expect(File(book.coverPath!).existsSync(), isTrue);
    });

    test('Frontmatter 指定 data: URI 封面時，優先使用該封面而非動態產生', () async {
      final pngBytes = [0x89, 0x50, 0x4E, 0x47];
      final base64Data = base64Encode(pngBytes);
      final mdFile = File('${Directory.systemTemp.path}/import_test_cover_fm.md');
      await mdFile.writeAsBytes(
        utf8.encode('---\ntitle: 有封面\ncover: data:image/png;base64,$base64Data\n---\n# 內容\n正文'),
      );
      addTearDown(() => mdFile.delete());

      final result = await service.importFiles([mdFile.path], displayNames: ['notes_cover_fm.md']);

      final book = result.importedBooks.first;
      expect(await File(book.coverPath!).readAsBytes(), pngBytes);
    });

    test('contentFingerprint 對原始檔案計算，非合成後的 .md 檔案', () async {
      final mdFile = File('${Directory.systemTemp.path}/import_test_fingerprint.md');
      await mdFile.writeAsBytes(utf8.encode('# 內容\n正文'));
      addTearDown(() => mdFile.delete());

      final result = await service.importFiles([mdFile.path], displayNames: ['notes_fp.md']);

      final book = result.importedBooks.first;
      final expectedFingerprint =
          await computeBookContentFingerprint(mdFile.path, BookFileFormat.md);
      expect(book.contentFingerprint, expectedFingerprint);
    });

    test('空白 MD 檔案不建立 Book 記錄，且不留下孤兒封面檔案', () async {
      final mdFile = File('${Directory.systemTemp.path}/import_test_empty.md');
      await mdFile.writeAsBytes(utf8.encode('---\ntitle: 空內容\n---\n   \n\n   '));
      addTearDown(() => mdFile.delete());

      final result = await service.importFiles([mdFile.path], displayNames: ['empty.md']);

      expect(result.importedBooks, isEmpty);
      expect(coversDir.listSync(), isEmpty);
    });
  });
```

（`computeBookContentFingerprint`／`Uint8List`／`base64Encode` 的 import 已由既有測試檔案頂部涵蓋，若編譯時發現缺漏，依 Dart 編譯錯誤訊息補上對應 `dart:convert`／`dart:typed_data`／`package:elinkbook/library/book_content_fingerprint.dart` import）

- [ ] **Step 3：確認測試失敗**

```bash
cd "U:/MyDeveloper/AI/elinkBook/app"
flutter test test/library/book_import_service_test.dart
```

Expected：FAIL（`BookFileFormat.md` 分支尚未產生合成邏輯）。

- [ ] **Step 4：實作**

`app/lib/library/book_import_service_impl.dart` 頂部 import 新增：

```dart
import 'md_epub_synthesizer.dart';
```

在既有 `} else if (format == BookFileFormat.cbz) { ... }` 分支之後、`} else { ... }`（原生 `extractMetadata` 分支）之前新增：

```dart
    } else if (format == BookFileFormat.md) {
      // 合成必須先於封面產生執行——比照 Issue 4 Important #1 審查修正的
      // 既有教訓，避免中止匯入時在磁碟留下孤兒封面檔案。
      MdSynthesisResult synthesis;
      try {
        synthesis = await synthesizeMdBook(resolvedUri, id, fallbackTitle);
      } on EmptyMdException {
        return null;
      }
      isFixedLayout = false;
      bookFilePath = await _landMdEpub(synthesis.epubBytes, id);
      if (synthesis.frontmatterTitle != null && synthesis.frontmatterTitle!.isNotEmpty) {
        title = synthesis.frontmatterTitle!;
      }
      author = synthesis.frontmatterAuthor;
      // Frontmatter 未指定封面（或指定值無法解析，見 md_frontmatter.dart
      // 文件註解）時，退回比照 TXT 既有的「依書名文字動態生成封面」機制
      // （spec.md「TXT／Markdown 合成書籍結構」對 MD 的既定要求）。
      final coverBytes = synthesis.frontmatterCoverBytes ?? await generateTxtCover(title);
      coverPath = await _landCover(coverBytes, id);
    } else {
```

在既有 `_landTxtEpub()` 方法之後新增：

```dart
  /// 落地 MD 合成的 EPUB 壓縮檔位元組（epic-11-multi-format-reader
  /// Issue 5），比照 [_landTxtEpub] 既有的「以 book id 為鍵、獨立子目錄」
  /// 慣例，重用既有 `imported_books/` 目錄。**檔名副檔名須維持 `.md`**
  /// （理由同 `_landTxtEpub` 對 `.txt` 的既有限制）。
  Future<String> _landMdEpub(Uint8List bytes, String bookId) async {
    final dir = await _resolveImportedBooksDirectory();
    final file = File(p.join(dir.path, '$bookId.md'));
    await file.writeAsBytes(bytes, flush: true);
    return file.path;
  }
```

- [ ] **Step 5：確認測試通過**

```bash
flutter test test/library/book_import_service_test.dart
```

Expected：PASS（既有全部測試＋6 個新增 MD 測試）。

- [ ] **Step 6：`flutter analyze`**

```bash
flutter analyze
```

Expected：無新增 issue。

- [ ] **Step 7：Commit**

```bash
git add app/lib/library/book_import_service_impl.dart app/test/library/book_import_service_test.dart
git commit -m "feat(epic-11): Issue 5——匯入管線接上 MD 合成為 EPUB 結構"
```

---

## Task 7：`ReaderScreen` 分派邏輯擴充

**Files:**
- Modify: `app/lib/screens/reader_screen.dart`
- Test: `app/test/screens/reader_screen_test.dart`

**Interfaces:**
- Consumes：`BookFormat.md`（Task 2）。

- [ ] **Step 1：寫失敗測試（防禦性 `_dispatchedIsFixedLayout` 分派）**

於 `app/test/screens/reader_screen_test.dart` 找到既有「TXT 書籍 isFixedLayout: null...」測試附近，追加同構測試：

```dart
    testWidgets(
      'MD 書籍 isFixedLayout: null 時，防禦性視為 false 並建構 FoliateReaderView，'
      '不永遠停留載入中畫面（epic-11 Issue 5，比照 Issue 2 C2／Issue 3 Important #1／'
      'Issue 4 同構情境；正常匯入流程下 Book.isFixedLayout 必為 false，本測試涵蓋'
      '邊界防禦）',
      (tester) async {
        final repository = FakeLibraryRepository();
        await tester.pumpWidget(MaterialApp(home: ReaderScreen(
          filePath: 'test/fixtures/sample_synth.md', bookId: 'b1',
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

（`test/fixtures/sample_synth.md`：widget test 專用，內容為已合成過的最小合法 EPUB 結構、僅副檔名為 `.md`，比照 Issue 4 `sample_synth.txt` 既有模式，本測試只驗證 Dart 端分派邏輯與 widget 樹建構，不要求真正被 WebView 渲染成功——Task 9 會產生此 fixture）

- [ ] **Step 2：實作 `_resolveEpubEngineDispatch()`**

`app/lib/screens/reader_screen.dart` 修改（緊接在既有 txt 分支之後、`if (format != BookFormat.epub) return;` 之前）：

```dart
    if (format == BookFormat.md) {
      // MD 合成後恆為流式（無 FXL 變體，spec.md「TXT／Markdown 合成書籍
      // 結構」），Book.isFixedLayout 理論上匯入時必定已寫入 false
      // （book_import_service_impl.dart），此處防禦性補上與上方
      // azw3/cbz/txt 分支相同邏輯的 null-safety 修正（比照 Issue 2 C2／
      // Issue 3 Important #1／Issue 4 的既有教訓）。
      _dispatchedIsFixedLayout = false;
      return;
    }
    if (format != BookFormat.epub) return;
```

- [ ] **Step 3：`_writeCurrentPosition()` merged case**

```dart
      case BookFormat.epub:
      case BookFormat.azw3:
      case BookFormat.cbz:
      case BookFormat.txt:
      case BookFormat.md:
        final info = _epubPositionInfo;
```

- [ ] **Step 4：`_buildAppBarActions()` merged case**

```dart
    switch (format) {
      case BookFormat.epub:
      case BookFormat.azw3:
      case BookFormat.cbz:
      case BookFormat.txt:
      case BookFormat.md:
        return [
```

（MD 恆為流式，會真的顯示這組 AppBar 按鈕，比照 TXT 既有行為——需要目錄/版面設定/筆記按鈕）

- [ ] **Step 5：`_buildNativeView()` merged case**

```dart
      case BookFormat.epub:
      case BookFormat.azw3:
      case BookFormat.cbz:
      case BookFormat.txt:
      case BookFormat.md:
        return FoliateReaderView(
```

（`isComicBookHint: format == BookFormat.cbz` 對 `BookFormat.md` 天然為 `false`，不需額外修改內部參數列）

- [ ] **Step 6：`flutter analyze`（確認 Task 2 記錄的 exhaustiveness 錯誤清單清空）**

```bash
cd "U:/MyDeveloper/AI/elinkBook/app"
flutter analyze
```

Expected：`reader_screen.dart` 相關的 `non_exhaustive_switch_statement` 全部消失；整體回報 `No issues found!`。

- [ ] **Step 7：確認 `_handleZoneAction()` 無需修改**

```bash
grep -n "isFoliateFormat(format)" "U:/MyDeveloper/AI/elinkBook/app/lib/screens/reader_screen.dart"
```

Expected：兩處呼叫維持不動——`isFoliateFormat()` 已於 Task 2 擴大涵蓋 `md`，這條路徑自動正確運作。

- [ ] **Step 8：確認測試通過（待 Task 9 fixture 就緒後）**

```bash
flutter test test/screens/reader_screen_test.dart --plain-name "MD 書籍"
```

Expected：PASS（若此時 `sample_synth.md` 尚未產生，本 Step 會先 FAIL 於檔案不存在，屬預期中的暫時狀態，Task 7/9 建議依序緊接執行，commit 一併留到 Task 9 Step 5，比照 Issue 4 Task 8/9 既有處置模式）。

---

## Task 8：檔案選擇器新增 `.md`

**Files:**
- Modify: `app/lib/screens/library_screen.dart`
- Modify: `app/integration_test/manual_import_acceptance_test.dart`

- [ ] **Step 1：修改**

`app/lib/screens/library_screen.dart`：

```dart
        allowedExtensions: ['epub', 'pdf', 'txt', 'cbz', 'azw3', 'md'],
```

`app/integration_test/manual_import_acceptance_test.dart`：

```dart
                          allowedExtensions: ['epub', 'pdf', 'txt', 'azw3', 'cbz', 'md'],
```

- [ ] **Step 2：`flutter analyze`**

```bash
cd "U:/MyDeveloper/AI/elinkBook/app"
flutter analyze
```

Expected：無新增 issue（純字串陣列常數異動，已確認 `app/test/` 下無任何既有測試斷言這個常數的確切內容）。

- [ ] **Step 3：Commit**

```bash
git add app/lib/screens/library_screen.dart app/integration_test/manual_import_acceptance_test.dart
git commit -m "feat(epic-11): Issue 5——檔案選擇器新增 .md 副檔名"
```

---

## Task 9：真機測試 fixture 產生

**Files:**
- Create: `app/test/fixtures/sample_synth.md`（widget test 用，已合成的最小 EPUB，供 Task 7 使用）
- Create: `app/test/fixtures/sample.md`（真機整合測試用，含 Frontmatter／巢狀標題／程式碼區塊／表格的原始 Markdown）
- Modify: `app/pubspec.yaml`（新增這兩個 asset）

- [ ] **Step 1：撰寫並執行 fixture 產生腳本**

```bash
cat > "U:/MyDeveloper/AI/elinkBook/tmp_generate_md_fixtures.py" << 'PYEOF'
import zipfile

# sample_synth.md：widget test 專用，內容是最小合法 EPUB 結構、僅副檔名
# 為 .md（比照 Task 7 widget test 說明：只需 FoliateReaderView 能建構，
# 不要求真正能被 WebView 渲染成功）。
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
    <dc:identifier id="book-id">elinkbook-md-fixture</dc:identifier>
    <dc:title>Fixture</dc:title>
    <dc:language>zh</dc:language>
  </metadata>
  <manifest>
    <item id="nav" href="nav.xhtml" media-type="application/xhtml+xml" properties="nav"/>
    <item id="sec0001" href="text/sec0001.xhtml" media-type="application/xhtml+xml"/>
  </manifest>
  <spine>
    <itemref idref="sec0001"/>
  </spine>
</package>
'''

NAV_XHTML = '''<?xml version="1.0" encoding="UTF-8"?>
<html xmlns="http://www.w3.org/1999/xhtml" xmlns:epub="http://www.idpf.org/2007/ops">
<head><title>目錄</title></head>
<body><nav epub:type="toc"><ol><li><a href="text/sec0001.xhtml">第一章</a></li></ol></nav></body>
</html>
'''

SECTION_XHTML = '''<?xml version="1.0" encoding="UTF-8"?>
<html xmlns="http://www.w3.org/1999/xhtml">
<head><title>內容</title></head>
<body><h1 id="heading_0001">第一章</h1><p>固定測試內容。</p></body>
</html>
'''

with zipfile.ZipFile(
    'U:/MyDeveloper/AI/elinkBook/app/test/fixtures/sample_synth.md', 'w', zipfile.ZIP_DEFLATED
) as zf:
    zf.writestr('mimetype', 'application/epub+zip')
    zf.writestr('META-INF/container.xml', CONTAINER_XML)
    zf.writestr('OEBPS/content.opf', CONTENT_OPF)
    zf.writestr('OEBPS/nav.xhtml', NAV_XHTML)
    zf.writestr('OEBPS/text/sec0001.xhtml', SECTION_XHTML)

# sample.md：真機整合測試用，真實原始 Markdown（未經任何本專案程式碼
# 處理），含 Frontmatter、巢狀標題、程式碼區塊、表格，驗證端到端合成與
# 渲染流程。
sample_md = '''---
title: 真機測試筆記
author: 測試作者
---

# 第一章 起源

這是第一章的內文。

## 子章節 A

這是子章節內容，含 `inline code`。

```python
print("hello world")
```

| 欄位 | 值 |
| --- | --- |
| A | 1 |
| B | 2 |

# 第二章 結局

這是第二章的內文。
'''
with open('U:/MyDeveloper/AI/elinkBook/app/test/fixtures/sample.md', 'w', encoding='utf-8') as f:
    f.write(sample_md)

print('已產生 sample_synth.md／sample.md')
PYEOF
python3 "U:/MyDeveloper/AI/elinkBook/tmp_generate_md_fixtures.py"
rm "U:/MyDeveloper/AI/elinkBook/tmp_generate_md_fixtures.py"
```

- [ ] **Step 2：驗證 `sample.md` 能被 `synthesizeMdBook()` 正確合成（不拋出例外，章節數與 Frontmatter 皆符合預期）**

```bash
cd "U:/MyDeveloper/AI/elinkBook/app"
cat > /tmp/verify_md_fixture_test.dart << 'DARTEOF'
import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:elinkbook/library/md_epub_synthesizer.dart';

void main() {
  test('sample.md 正確合成，Frontmatter 與雙章節結構符合預期', () async {
    final result = await synthesizeMdBook('test/fixtures/sample.md', 'fixture_check', '備用標題');
    expect(result.frontmatterTitle, '真機測試筆記');
    expect(result.frontmatterAuthor, '測試作者');
    final archive = ZipDecoder().decodeBytes(result.epubBytes);
    final chapterItems =
        archive.files.where((f) => f.name.startsWith('OEBPS/text/') && f.name.endsWith('.xhtml'));
    expect(chapterItems, hasLength(2));
  });
}
DARTEOF
cp /tmp/verify_md_fixture_test.dart test/library/verify_md_fixture_test.dart
flutter test test/library/verify_md_fixture_test.dart
rm test/library/verify_md_fixture_test.dart
```

Expected：PASS（確認 fixture 內容能被本 Issue 實作正確處理，非產生腳本錯誤導致的損毀檔案）。

- [ ] **Step 3：`pubspec.yaml` 新增 asset**

`app/pubspec.yaml` 的 `assets:` 清單，緊接在 `- test/fixtures/sample_utf8_chapters.txt` 之後新增：

```yaml
    - test/fixtures/sample_synth.md
    - test/fixtures/sample.md
```

```bash
flutter pub get
```

- [ ] **Step 4：重新確認 Task 7 的 widget test 通過**

```bash
flutter test test/screens/reader_screen_test.dart --plain-name "MD 書籍"
```

Expected：PASS。

- [ ] **Step 5：Commit（涵蓋 Task 7 與本 Task）**

```bash
cd "U:/MyDeveloper/AI/elinkBook"
git add app/lib/screens/reader_screen.dart app/test/screens/reader_screen_test.dart \
  app/test/fixtures/sample_synth.md app/test/fixtures/sample.md app/pubspec.yaml
git commit -m "feat(epic-11): Issue 5——ReaderScreen 分派邏輯擴充涵蓋 MD，新增測試 fixture"
```

---

## Task 10：真機 `integration_test`

**Files:**
- Create: `app/integration_test/foliate_md_test.dart`

**Interfaces:**
- Consumes：`sample.md`（Task 9）；`BookImportServiceImpl`／`ReaderScreen`（既有，Task 6/7 已擴充支援 md）。

- [ ] **Step 1：確認可用裝置**

```bash
cd "U:/MyDeveloper/AI/elinkBook/app"
flutter devices
```

- [ ] **Step 2：撰寫測試**

```dart
// app/integration_test/foliate_md_test.dart
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
import 'package:elinkbook/reader/foliate_reader_view.dart';
import 'package:elinkbook/reader/reader_prefs_manager_impl.dart';
import 'package:elinkbook/reader/reading_position_repository.dart';
import 'package:elinkbook/screens/reader_screen.dart';

/// 把 Flutter asset 複製為裝置暫存目錄中的真實檔案，回傳其絕對路徑
/// （比照 foliate_kf8_test.dart／foliate_cbz_test.dart／foliate_txt_test.dart
/// 既有 helper）。
Future<String> _stageAssetAsFile(String assetPath, String fileName) async {
  final bytes = await rootBundle.load(assetPath);
  final tempDir = await getTemporaryDirectory();
  final file = File('${tempDir.path}/$fileName');
  await file.writeAsBytes(bytes.buffer.asUint8List(), flush: true);
  return file.path;
}

/// 持續 pump，直到載入指示器消失或逾時（比照既有斷言方式）。
Future<void> _pumpUntilLoaded(WidgetTester tester) async {
  final deadline = DateTime.now().add(const Duration(seconds: 20));
  while (find.byKey(const Key('reader_loading_indicator')).evaluate().isNotEmpty) {
    if (DateTime.now().isAfter(deadline)) fail('等待逾時：載入指示器未消失');
    await tester.pump(const Duration(milliseconds: 50));
  }
  await tester.pump(const Duration(seconds: 1));
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
    '透過 BookImportService 匯入 MD（含 Frontmatter／巢狀標題／程式碼區塊／'
    '表格）並經 ReaderScreen 開啟，成功渲染無錯誤，Frontmatter 標題正確寫入、'
    '目錄正確產生',
    (tester) async {
      sqfliteFfiInit();
      databaseFactory = databaseFactoryFfi;
      final libraryRepository = await SqliteLibraryRepository.open(inMemoryDatabasePath);
      addTearDown(() => libraryRepository.close());
      final prefsManager = ReaderPrefsManagerImpl(
        BookReaderPrefsRepository(libraryRepository.database),
        ReadingPositionRepository(libraryRepository.database),
      );
      final importService = BookImportServiceImpl(repository: libraryRepository);

      final samplePath =
          await _stageAssetAsFile('test/fixtures/sample.md', 'foliate_md_integration.md');
      addTearDown(() async {
        final file = File(samplePath);
        if (await file.exists()) await file.delete();
      });

      final result = await importService.importFiles([samplePath], displayNames: ['sample.md']);
      expect(result.importedBooks, hasLength(1));
      final book = result.importedBooks.single;
      expect(book.title, '真機測試筆記');
      expect(book.isFixedLayout, isFalse);

      final readerKey = GlobalKey<State<ReaderScreen>>();
      await tester.pumpWidget(
        MaterialApp(
          home: ReaderScreen(
            key: readerKey,
            filePath: book.filePath,
            bookId: book.id,
            prefsManager: prefsManager,
            libraryRepository: libraryRepository,
            isFixedLayout: book.isFixedLayout,
          ),
        ),
      );
      await _pumpUntilLoaded(tester);

      expect(find.byKey(const Key('reader_error_text')), findsNothing);

      final toc = await FoliateReaderView.loadTableOfContents(
        (readerKey.currentState! as dynamic).foliateEpubReaderViewKeyForTest,
      );
      // 見下方「注意」段落——若 ReaderScreen 未暴露對應測試出口，改用
      // Task 10 Step 3 提供的 static helper 呼叫方式。
      expect(toc.map((e) => e.title), ['第一章 起源', '第二章 結局']);
    },
  );
}
```

**注意**：本測試存取目錄的方式須比照 Issue 4 `foliate_txt_test.dart` 已建立的 `ReaderScreen.loadTableOfContentsForTest()` static helper 模式（`reader_screen.dart` 若尚未有這個 helper，代表 Issue 4 執行時已經新增過，直接沿用；若確認不存在，比照 Issue 4 Task 10 的既有程式碼新增）。上方程式碼片段中透過 `dynamic` 存取私有欄位的寫法僅為示意、**不可直接採用**，正式實作時請改為：

```dart
      final toc = await ReaderScreen.loadTableOfContentsForTest(readerKey);
      expect(toc.map((e) => e.title), ['第一章 起源', '第二章 結局']);
```

- [ ] **Step 3：確認 `ReaderScreen.loadTableOfContentsForTest()` 存在**

```bash
grep -n "loadTableOfContentsForTest" "U:/MyDeveloper/AI/elinkBook/app/lib/screens/reader_screen.dart"
```

Expected：找到 Issue 4 Task 10 新增的既有定義（`static Future<List<TocEntry>> loadTableOfContentsForTest(GlobalKey<State<ReaderScreen>> key)`）。若無輸出（代表 Issue 4 執行時未採用該 helper 命名或未新增），比照以下程式碼於 `reader_screen.dart` 補上（新增位置：緊接在既有 `static void openPdfToc(...)` 方法之後，`ReaderScreen` class 結尾 `}` 之前）：

```dart
  /// 供真機整合測試讀取目前書籍目錄（epic-11-multi-format-reader
  /// Issue 4/5），比照既有 [triggerZoneAction] 強型別 static helper 模式。
  /// [key] 對應的 State 若尚未掛載，回傳空清單。
  static Future<List<TocEntry>> loadTableOfContentsForTest(
    GlobalKey<State<ReaderScreen>> key,
  ) async {
    final state = key.currentState;
    if (state is! _ReaderScreenState) return const [];
    return FoliateReaderView.loadTableOfContents(state._foliateEpubReaderViewKey);
  }
```

- [ ] **Step 4：真機執行**

```bash
flutter test integration_test/foliate_md_test.dart -d <device-id>
```

Expected：1/1 PASS。若目錄斷言失敗，優先檢查 `md_toc_builder.dart` 的巢狀切分邏輯是否正確把子章節排除在頂層目錄之外（`sample.md` 的目錄應只有「第一章 起源」「第二章 結局」兩個頂層項目，「子章節 A」是巢狀項目不會出現在這個扁平斷言中，若測試改為檢查完整巢狀結構需相應調整）。

- [ ] **Step 5：Commit**

```bash
cd "U:/MyDeveloper/AI/elinkBook"
git add app/integration_test/foliate_md_test.dart app/lib/screens/reader_screen.dart
git commit -m "test(epic-11): Issue 5——MD 真機整合測試，涵蓋 Frontmatter/巢狀目錄/開書渲染"
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

Expected：全數通過（既有 1383 + 本 Issue 新增測試，具體數字以實際輸出為準）。

- [ ] **Step 3：真機整合測試回歸（確認未破壞既有 KF8/CBZ/TXT 整合測試）**

```bash
flutter test integration_test/foliate_kf8_test.dart integration_test/foliate_cbz_test.dart integration_test/foliate_txt_test.dart integration_test/foliate_md_test.dart -d <device-id>
```

Expected：全數 PASS。

- [ ] **Step 4：手動驗收（比照 issues.md Issue 5 驗收標準逐項確認）**

- 真機匯入 MD 檔案正確渲染，Frontmatter 標題/封面正確顯示：於裝置上實際透過圖書庫匯入畫面選取 `sample.md`，人工確認書架上顯示「真機測試筆記」與正確封面。
- 程式碼區塊與表格在直排模式下維持橫排、可橫向捲動閱讀：開啟該書後切換為直排，人工確認程式碼區塊與表格未被直排排版拉伸/破版，可正常橫向捲動。
- 標題階層目錄正確產生；直排/橫排切換、劃線、書籤功能與其他格式一致：人工操作既有 UI 逐一確認（皆為既有機制直接繼承）。
- 刪除書籍後對應合成檔案從磁碟移除：於圖書庫刪除該書，確認 `imported_books/$id.md` 消失——**沿用既有通用刪除邏輯，不需要新程式碼**（比照 Issue 3/4 已驗證的相同結論）。

- [ ] **Step 5：更新 `issues.md`／`docs/epics.md`（人類確認驗收通過後，比照 Issue 2-4 既有流程另行處理，不在本計畫任務範圍內）**

---

## Self-Review（spec 覆蓋檢查）

逐項比對 `issues.md` Issue 5「範圍」1-6 點：
1. `BookFormat`／`BookFileFormat` 新增 `md`；`ReaderScreen` 對 `md` 建構 `FoliateReaderView` → Task 2／Task 7 ✓
2. YAML Frontmatter 解析：抽取標題／作者／封面；未指定封面時退回動態生成封面機制 → Task 3（解析）／Task 6（退回機制接線）✓
3. 依標題階層（H1-H6）自動生成目錄 → Task 4（階層/id 抽取）／Task 5（巢狀 `<ol>` 樹渲染）✓
4. `<pre><code>` 與表格強制注入 `writing-mode: horizontal-tb; direction: ltr;` 並提供橫向捲動 → Task 5（`_kCodeTableCss`）✓
5. 沿用 Issue 4 建立的合成書籍結構落地轉換／檔案命名／刪除清理／`contentFingerprint` 計算順序模式，不重新設計 → Task 1（共用容器模板抽取）／Task 6（沿用 `_landTxtEpub` 同構命名慣例、`resolvedUri` 計算指紋順序、既有通用刪除邏輯自動涵蓋）✓
6. `Book.isFixedLayout` 對 MD 合成後恆為 `false` → Task 6（匯入寫入）／Task 7（`ReaderScreen` 防禦分派）✓

明確排除範圍（MD 內嵌本機相對路徑圖片的優雅降級）：Task 5／Task 3 皆已明確記錄「僅支援 `data:` URI，其餘一律忽略」的範圍邊界，未額外開發，符合 issues.md 明訂排除項。

`Placeholder` 掃描：全文搜尋 "TBD"/"待補"/"依需求調整" 等字樣——無。所有程式碼區塊皆為可直接套用的完整程式碼；Task 10 的 `ReaderScreen.loadTableOfContentsForTest()` 依賴 Issue 4 執行時的既有產物，已提供「若不存在則新增」的完整備援程式碼，非留白。

型別一致性檢查：`MdFrontmatter`／`MdParsedDocument`（Task 3 定義）→ `md_epub_synthesizer.dart`（Task 5 消費，欄位名 `title`/`author`/`coverBytes`/`body` 一致）；`MdHeading`／`MdSection`／`MdParseResult`（Task 4 定義，`MdHeading` 含 `level`/`text`/`anchorId`/`sectionIndex` 四欄位）→ `md_epub_synthesizer.dart`（Task 5 消費於 `_buildTocTree()`／`_renderTocChildren()`，欄位存取一致）；`kEpubContainerXml`／`buildEpubContentOpf`／`buildEpubNavXhtml`／`escapeXml`（Task 1 定義）→ `txt_epub_synthesizer.dart`（Task 1 內重構）與 `md_epub_synthesizer.dart`（Task 5，具名參數 `identifier`/`title`/`manifestItems`/`spineItems` 一致）；`MdSynthesisResult`／`EmptyMdException`／`synthesizeMdBook`（Task 5 定義）→ `book_import_service_impl.dart`（Task 6 消費，欄位/例外型別一致）——皆一致。
