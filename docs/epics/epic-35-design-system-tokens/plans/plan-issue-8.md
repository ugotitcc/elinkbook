# Epic 35 — Issue 8：`txt_cover_generator.dart`（E-Ink 分支：白底黑框黑字）Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** `generateTxtCover()` 加一個 `isEinkMode` bool 參數，開啟時把 TXT／MD 匯入時動態產生的封面圖片改成 E-Ink 友善的白底＋黑色邊框＋黑色書名首字（現行寫死白字在白底上會看不見），關閉時維持既有 6 色輪替＋白字行為完全不變；並讓 `BookImportServiceImpl` 在 TXT／MD 匯入分支呼叫這個函式前，讀取使用者當下的 E-Ink 開關設定值傳進去。

**Architecture:** 分兩個 Task，依賴順序執行（Task 2 呼叫 Task 1 新增的參數）。Task 1 只碰 `txt_cover_generator.dart` 本體與其測試——純 `dart:ui` 函式，不涉及 `BuildContext`／`ElinkTokens`，白／黑色值直接寫死在函式內（跟函式既有的色盤寫死做法一致，`issues.md` Issue 8 已明文決議不傳 `ElinkTokens`）。Task 2 只碰 `BookImportServiceImpl` 建構子與其兩個呼叫端（TXT 分支、MD 分支）、`main.dart` 的接線、以及對應測試——建構子新增**可選**參數 `AppThemePreferences? themePreferences`，不改動 `BookImportService` 抽象介面／`importFiles()`／`importFolder()` 簽章，既有呼叫點（`library_screen_test.dart` 兩處、`main.dart` 一處）不受影響。

**（審查修正）`isEinkMode` 改採預設值，不用必要參數：** 初版計劃曾將 `generateTxtCover()` 的 `isEinkMode` 定為必要具名參數，代價是 Task 1 commit 當下 `book_import_service_impl.dart` 既有 2 個呼叫點會編譯失敗，讓儲存庫暫時處於無法編譯的狀態（見 `reviews/review-plan-issue-8.md` I2）。經審查指出這違反「每個 commit 都應維持可編譯」的基本工程紀律（影響 `git bisect`／CI 可用性），且原本想靠必要參數防範的「呼叫端忘記接線」風險，Task 2 自己的紅燈測試已能完全攔截（忘記接線時仍會退回預設 `false`，Task 2 新增的 E-Ink 測試會直接失敗）——必要參數帶來的保護其實是多餘的。改為 `{bool isEinkMode = false}` 預設值寫法後：Task 1 commit 時全專案維持可編譯、`flutter analyze` 乾淨，`book_import_service_impl.dart` 既有 2 個呼叫點與測試檔既有 4 個測試完全不需要異動，Task 2 才實際接上新行為。

**Tech Stack:** Flutter／Dart，`dart:ui`（`ui.PictureRecorder`／`ui.Canvas`／`ui.Paint`／`ui.ParagraphBuilder`，既有函式已在用）、`flutter_test`、`shared_preferences`（`AppThemePreferences` 既有包裝，`epic-3-fonts-layout` 已建立）。不新增任何 pub 套件依賴。

**Spec:** `docs/epics/epic-35-design-system-tokens/spec.md`（§「寫死顏色遷移」`txt_cover_generator.dart` 部分）；工單摘要見 `docs/epics/epic-35-design-system-tokens/issues.md` Issue 8。

## Global Constraints

- 本工單只碰 `app/lib/library/txt_cover_generator.dart`、`app/lib/library/book_import_service_impl.dart`、`app/lib/main.dart`（一行接線），及其對應測試檔 `app/test/library/txt_cover_generator_test.dart`、`app/test/library/book_import_service_test.dart`；不碰 `BookImportService` 抽象介面（`book_import_service.dart`）、`FakeBookImportService`（`app/test/support/fake_book_import_service.dart`，實作抽象介面而非繼承 `BookImportServiceImpl`，不受影響）、OPDS／WebDAV／雲端來源實作／書籍儲存 schema／閱讀進度持久化。
- **不傳 `ElinkTokens`**：`generateTxtCover()` 是離線產生 PNG 的 `dart:ui` 純函式，不在 widget tree 內、沒有 `BuildContext` 可取 `Theme.of(context)`；`isEinkMode` 為單純 bool 參數，白／黑色值直接寫死 `ui.Color`（跟函式既有的 `_palette` 色盤寫死做法一致），`issues.md` Issue 8 已明文決議此做法。
- **不改變 `BookImportService` 抽象介面**：`importFiles()`／`importFolder()` 方法簽章不動；`BookImportServiceImpl` 建構子新增的 `themePreferences` 為**可選**具名參數（預設值 `AppThemePreferences()`），現有 3 處呼叫點（`main.dart:77`、`library_screen_test.dart:841,1489`）不需要跟著改動即可通過編譯。
- 已產生的舊封面 PNG **不會**回頭重新產生——這是既有架構限制（`generateTxtCover()` 只在匯入當下呼叫一次、結果落地為本機檔案，非即時渲染），不在本工單修復範圍，不需要寫遷移腳本。
- 所有 Dart 原始碼註解使用正體中文。
- 每個 Task 完成後只跑該 Task 涉及檔案的測試（見各 Task「驗證」欄），不需要整套 `flutter test`；本計劃最後一個 Task（Task 2）完成時才跑一次完整 `flutter test`＋`flutter analyze`（見 `CLAUDE.md`「測試執行範圍」）。
- 每個 Task 的 Step 完成後，把本檔案對應的 `- [ ]` 改成 `- [x]`。
- 提交前 `flutter analyze` 須維持「No issues found!」（Task 2 統一驗證）。
- 計劃書內「改後」程式碼片段的換行/縮排以人工排版呈現，實際落地時以 `dart format` 自動排版結果為準，不需要逐字比對縮排。
- 所有指令皆在 `app/` 目錄下執行。
- 下方各 Task「Commit」步驟的 `Co-Authored-By`／`Claude-Session` 屬名反映本計劃撰寫當下的會話資訊；若實際執行本計劃的是另一個會話（session ID 不同），執行者應改用該會話當下收到的屬名指示，不要照抄這裡的字面值（`reviews/review-plan-issue-8.md` M3）。

## 動手改程式碼前的四點說明（`UI_DESIGN_RULES.md` 要求）

1. **改哪個 UI 元件**：不是畫面元件，是 TXT／MD 書籍匯入流程中「動態產生封面圖片」這個純函式 `generateTxtCover()`（`app/lib/library/txt_cover_generator.dart`），以及呼叫它的 `BookImportServiceImpl`（`app/lib/library/book_import_service_impl.dart`）TXT／MD 兩個匯入分支。
2. **為什麼要改**：這個函式目前不論主題設定為何，永遠輸出 6 色輪替背景＋白色書名首字。E-Ink 高對比模式下這個封面樣式沒有對應調整，`spec.md`「寫死顏色遷移」清單明確要求 E-Ink 模式下改為白底黑框黑字，確保封面在電子紙螢幕上可辨識。
3. **哪些畫面依賴它**：`LibraryScreen`（`library_screen.dart`）的書架格狀／列表檢視顯示 `Book.coverPath` 指向的封面圖片——TXT／MD 格式的書籍封面就是這裡動態產生的 PNG。使用者在「設定」畫面開啟 E-Ink 模式後，**新匯入**的 TXT／MD 書籍封面會採用新樣式（已匯入的舊書封面不受影響，見上方 Global Constraints）。
4. **是否影響 business logic**：不影響。不改變 `Book` 資料模型欄位、不改變匯入流程判斷邏輯（是否成功匯入、是否略過重複檔案、如何分類、指紋計算等完全不變），純粹是「同一個匯入步驟裡，產生的封面 PNG 該用哪一種視覺樣式」的選擇；`BookImportService` 抽象介面與既有呼叫點不受影響（見上方 Global Constraints）。

---

### Task 1：`generateTxtCover()` 加 `isEinkMode` 參數，E-Ink 分支白底黑框黑字

**Files:**
- Modify: `app/lib/library/txt_cover_generator.dart`（全檔，47 行）
- Test: `app/test/library/txt_cover_generator_test.dart`（全檔，43 行）

**Interfaces:**
- Consumes：無（純 `dart:ui` API，函式本身已完整獨立）。
- Produces：`Future<Uint8List> generateTxtCover(String title, {bool isEinkMode = false})`——`isEinkMode` 給預設值 `false`（見上方「審查修正」說明），既有呼叫端不傳這個參數時行為完全不變。`isEinkMode: true` 時背景改純白（`0xFFFFFFFF`）、新增 8px 黑色實線邊框（模組層級常數 `_einkBorderWidth`）、書名首字文字色改黑（`0xFF000000`，取代現行寫死白色）；`isEinkMode: false` 時完全維持現行 6 色輪替＋白字行為，不受影響。Task 2 依這個簽章串接 `AppThemePreferences.loadEinkMode()` 的回傳值。

- [ ] **Step 1：寫失敗測試（覆寫整份測試檔）**

`app/test/library/txt_cover_generator_test.dart` 既有 4 個測試**完全不需要修改**——`isEinkMode` 已於 Task 1 改採預設值 `false`（見上方「審查修正」），舊呼叫 `generateTxtCover(title)` 依然合法、行為不變。只需要：(1) 頂部新增 `dart:typed_data`／`dart:ui` 兩個 import；(2) 在既有 4 個測試之後、`main()` 的收尾 `}` 之前新增一個 `group` 涵蓋 E-Ink 分支；(3) 在檔案末尾新增一個私有像素採樣 helper。

**(1) 頂部新增 import** —— 在既有的 `import 'package:flutter_test/flutter_test.dart';` 之前新增：

```dart
import 'dart:typed_data';
import 'dart:ui' as ui;

```

**(2) 新增測試 group**（既有 4 個測試與 `main()` 收尾 `}` 之間，新增下列內容；相較初版計劃，本版依審查意見修正了 C1 誤比對白色的無效斷言、並新增 C2 要求的文字黑色像素驗證）：

```dart
  group('E-Ink 模式（白底黑框黑字，Issue 8）', () {
    test('isEinkMode: true 時，四角為黑色邊框、邊框內側為白底', () async {
      final bytes = await generateTxtCover('測試書名', isEinkMode: true);

      // 邊框寬度 8px（見實作 _einkBorderWidth），採樣邊框實心區域內的像素
      // （2,2）而非最邊緣（0,0），避開抗鋸齒造成的邊界像素誤判。
      expect(await _pixelColor(bytes, 2, 2), const ui.Color(0xFF000000),
          reason: '左上角應為黑色邊框');
      expect(await _pixelColor(bytes, 397, 2), const ui.Color(0xFF000000),
          reason: '右上角應為黑色邊框');
      expect(await _pixelColor(bytes, 2, 397), const ui.Color(0xFF000000),
          reason: '左下角應為黑色邊框');
      expect(await _pixelColor(bytes, 397, 397), const ui.Color(0xFF000000),
          reason: '右下角應為黑色邊框');

      // (20,20) 遠離 8px 邊框範圍（0-8／392-400）與置中文字區域，應為白底。
      expect(await _pixelColor(bytes, 20, 20), const ui.Color(0xFFFFFFFF),
          reason: '邊框內側、文字區域外應為白底');
    });

    test('isEinkMode: true 時，中央文字區域包含黑色文字像素（非白底白字）', () async {
      // spec.md「寫死顏色遷移」txt_cover_generator.dart 部分明講：只換背景／
      // 外框、不換文字色的話會變成白底配白字，書名首字完全看不見——這是
      // 本工單要防的核心回歸（reviews/review-plan-issue-8.md C2）。
      final bytes = await generateTxtCover('測試書名', isEinkMode: true);

      // 沿畫布中心垂直掃描線（x=200）取樣，字型渲染的精確外形因平台而異，
      // 但只要書名首字真的是黑色，掃描線必定會穿過至少一個純黑像素；
      // 若文字誤留白色（白底白字回歸），這個範圍內不會有任何純黑像素。
      var hasBlackTextPixel = false;
      for (var y = 90; y <= 310; y += 5) {
        if (await _pixelColor(bytes, 200, y) == const ui.Color(0xFF000000)) {
          hasBlackTextPixel = true;
          break;
        }
      }
      expect(hasBlackTextPixel, isTrue,
          reason: 'E-Ink 模式下書名首字應為黑色，不可退化成白底白字');
    });

    test('isEinkMode: true 對同一書名兩次呼叫，輸出 bytes 相等（渲染穩定）', () async {
      final bytes1 = await generateTxtCover('紅樓夢', isEinkMode: true);
      final bytes2 = await generateTxtCover('紅樓夢', isEinkMode: true);

      expect(bytes1, equals(bytes2));
    });

    test('同一書名，isEinkMode: true 與 false 輸出 bytes 不相等（確認兩分支確實有差異）',
        () async {
      final einkBytes = await generateTxtCover('紅樓夢', isEinkMode: true);
      final normalBytes = await generateTxtCover('紅樓夢', isEinkMode: false);

      expect(einkBytes, isNot(equals(normalBytes)));
    });

    test('isEinkMode: false（既有行為）不受本次改動影響：角落像素非 E-Ink 黑色邊框',
        () async {
      final bytes = await generateTxtCover('紅樓夢', isEinkMode: false);

      // 既有 4 個測試已涵蓋色盤本身正確性（可重現／依書名不同而不同），
      // 這裡只補「不是 E-Ink 分支才會出現的黑色邊框」這個新增分支特有的
      // 區辨斷言，確認 false 分支未被新增的 E-Ink 邏輯誤觸發（審查修正
      // C1：先前版本誤比對純白色，即使誤觸發 E-Ink 分支仍會通過，見
      // reviews/review-plan-issue-8.md）。
      expect(await _pixelColor(bytes, 2, 2), isNot(const ui.Color(0xFF000000)));
    });
  });
```

**(3) 檔案末尾新增 helper**（`main()` 收尾 `}` 之後）：

```dart

/// 解碼 PNG bytes 並取出 (x, y) 位置的像素顏色，供大面積純色區塊（背景／
/// 邊框）與文字黑色像素掃描的採樣斷言使用。不做逐像素精確文字外形比對
/// （見上方檔案開頭註解）。
Future<ui.Color> _pixelColor(Uint8List pngBytes, int x, int y) async {
  final codec = await ui.instantiateImageCodec(pngBytes);
  final frame = await codec.getNextFrame();
  final image = frame.image;
  final byteData = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
  final bytes = byteData!.buffer.asUint8List();
  final offset = (y * image.width + x) * 4;
  return ui.Color.fromARGB(
    bytes[offset + 3],
    bytes[offset],
    bytes[offset + 1],
    bytes[offset + 2],
  );
}
```

- [ ] **Step 2：執行測試，確認失敗**

Run: `flutter test test/library/txt_cover_generator_test.dart`
Expected: FAIL（編譯錯誤：實作補上前，`generateTxtCover` 完全沒有 `isEinkMode` 這個具名參數——`isEinkMode` 本身是 Step 3 才新增的參數，新 `group` 裡任何一處 `isEinkMode: true`／`isEinkMode: false` 呼叫都會編譯失敗，導致整個測試檔無法執行；既有 4 個測試呼叫未變，本身沒有問題，只是被同一個檔案裡的編譯錯誤連帶擋下）。

- [ ] **Step 3：實作 `isEinkMode` 分支**

把 `app/lib/library/txt_cover_generator.dart` 整檔改為：

```dart
import 'dart:typed_data';
import 'dart:ui' as ui;

/// 依書名文字動態產生 TXT 書籍的封面圖片（FR-27：TXT 沒有內嵌封面或首頁可
/// 渲染，改用書名文字合成一張正方形封面）。純 `dart:ui` 實作，不呼叫任何
/// 原生 book_metadata channel；背景色由書名首字的 code unit 決定（同一本書
/// 每次產生的封面一致，非隨機）。[isEinkMode] 為 `true` 時改為 E-Ink 友善的
/// 白底黑框黑字樣式（`spec.md`「寫死顏色遷移」txt_cover_generator.dart
/// 部分）——這是離線產生 PNG 的 `dart:ui` 純函式，不在 widget tree 內、沒有
/// `BuildContext` 可取 `Theme.of(context)`，直接吃 bool 比傳遞 `ElinkTokens`
/// 更單純，白／黑色值就地寫死 `ui.Color`，跟本函式其餘色盤做法一致。
Future<Uint8List> generateTxtCover(
  String title, {
  bool isEinkMode = false,
}) async {
  const size = 400.0;
  final recorder = ui.PictureRecorder();
  final canvas = ui.Canvas(recorder, const ui.Rect.fromLTWH(0, 0, size, size));

  final backgroundPaint = ui.Paint()
    ..color = isEinkMode
        ? const ui.Color(0xFFFFFFFF)
        : _backgroundColorForTitle(title);
  canvas.drawRect(const ui.Rect.fromLTWH(0, 0, size, size), backgroundPaint);

  if (isEinkMode) {
    final borderPaint = ui.Paint()
      ..color = const ui.Color(0xFF000000)
      ..style = ui.PaintingStyle.stroke
      ..strokeWidth = _einkBorderWidth;
    canvas.drawRect(
      const ui.Rect.fromLTWH(
        _einkBorderWidth / 2,
        _einkBorderWidth / 2,
        size - _einkBorderWidth,
        size - _einkBorderWidth,
      ),
      borderPaint,
    );
  }

  final firstChar = title.isNotEmpty ? title.substring(0, 1) : '?';
  final paragraphBuilder = ui.ParagraphBuilder(
    ui.ParagraphStyle(textAlign: ui.TextAlign.center, fontSize: size * 0.4),
  )
    ..pushStyle(
      ui.TextStyle(
        color: isEinkMode
            ? const ui.Color(0xFF000000)
            : const ui.Color(0xFFFFFFFF),
      ),
    )
    ..addText(firstChar);
  final paragraph = paragraphBuilder.build()
    ..layout(const ui.ParagraphConstraints(width: size));
  canvas.drawParagraph(
    paragraph,
    ui.Offset(0, (size - paragraph.height) / 2),
  );

  final picture = recorder.endRecording();
  final image = await picture.toImage(size.toInt(), size.toInt());
  final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
  return byteData!.buffer.asUint8List();
}

/// E-Ink 模式外框寬度。`DESIGN.md`／`spec.md` 未指定精確數值，取與封面尺寸
/// （400×400）成比例、目視明顯可辨識的寬度；具體數值未經真機驗證，比照
/// Issue 3／Issue 7 既有慣例，留待下一輪真機驗證確認電子紙上的可辨識度。
const _einkBorderWidth = 8.0;

const _palette = [
  ui.Color(0xFF5C6BC0),
  ui.Color(0xFF26A69A),
  ui.Color(0xFFEF5350),
  ui.Color(0xFFFFA726),
  ui.Color(0xFF8D6E63),
  ui.Color(0xFF7E57C2),
];

ui.Color _backgroundColorForTitle(String title) {
  final index = title.isEmpty ? 0 : title.codeUnitAt(0) % _palette.length;
  return _palette[index];
}
```

- [ ] **Step 4：執行測試，確認通過**

Run: `flutter test test/library/txt_cover_generator_test.dart`
Expected: PASS（9 個測試全過：既有 4 個＋新增 5 個）。

- [ ] **Step 5：Commit**

```bash
git add app/lib/library/txt_cover_generator.dart app/test/library/txt_cover_generator_test.dart
git commit -m "$(cat <<'EOF'
feat(epic-35): Issue 8 — generateTxtCover 加 isEinkMode 參數，E-Ink 模式改白底黑框黑字

Co-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_019sQtaEfjhZd2MD4vgFzBw3
EOF
)"
```

---

### Task 2：`BookImportServiceImpl` 串接 E-Ink 封面樣式（TXT／MD 兩個匯入分支＋`main.dart` 接線）

**Files:**
- Modify: `app/lib/library/book_import_service_impl.dart`（建構子、TXT 分支原 L286-289、MD 分支原 L339-349）
- Modify: `app/lib/main.dart`（L77，`importService` 建構呼叫）
- Test: `app/test/library/book_import_service_test.dart`（頂部 import／`setUp()`，及新增一個 `group`）

**Interfaces:**
- Consumes：Task 1 產出的 `Future<Uint8List> generateTxtCover(String title, {bool isEinkMode = false})`；既有 `AppThemePreferences.loadEinkMode()`（`app/lib/theme/app_theme_preferences.dart`，回傳 `Future<bool>`，未儲存過時預設 `false`，已存在、本工單不改動；類別非 `final`／`sealed`，可被子類別覆寫，見下方 1b 的 I1 修正測試）。
- Produces：`BookImportServiceImpl` 建構子新增可選具名參數 `AppThemePreferences? themePreferences`（不傳時退回 `AppThemePreferences()`，行為與現行完全一致）；`BookImportService` 抽象介面（`importFiles()`／`importFolder()`）簽章不變，供後續 Issue／既有呼叫端沿用。

- [ ] **Step 1：寫失敗測試**

**1a. 頂部 import 與 `setUp()`** —— `app/test/library/book_import_service_test.dart` 目前不涉及 `shared_preferences`（TXT／MD 分支尚未讀取 E-Ink 設定），本工單讓這兩個分支在每次匯入時都會呼叫 `AppThemePreferences.loadEinkMode()`，因此**所有**既有 TXT／MD 匯入測試都需要一個已初始化的 `SharedPreferences` 模擬替身，否則會撞上 `MissingPluginException`（比照 `epic-35` Issue 4 收尾階段修正的同一種教訓：新依賴要在 `setUp()` 層級一次補齊，不要等全套測試才發現）。在檔案頂部 import 區塊（原第 1-16 行）新增一行：

```dart
import 'package:shared_preferences/shared_preferences.dart';
```

（審查修正 M2：字母序 `sh` 排在 `sq` 之前，放在既有 `package:path_provider_platform_interface/path_provider_platform_interface.dart` 之後、`package:sqflite_common_ffi/sqflite_ffi.dart` 之前，維持 `package:` 群組內字母序。）

同一個 import 區塊再新增一行，供 I1 測試使用的 `AppThemePreferences` 子類別參照：

```dart
import 'package:elinkbook/theme/app_theme_preferences.dart';
```

（放在既有 `package:elinkbook/library/...`／`package:elinkbook/library/sqlite_library_repository.dart` 之後，維持 `package:elinkbook/...` 群組內字母序。）

在 `setUp()`（原第 35-53 行）最前面新增一行：

```dart
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    repository = await SqliteLibraryRepository.open(inMemoryDatabasePath);
```

（其餘既有內容原樣保留不動。）

**1b. 新增測試 group** —— 在 MD 匯入 `group`（原第 1042-1125 行）結束的 `});` 之後、`group('遠端書架參數擴充（epic-30）', ...)`（原第 1127 行）之前，插入：

```dart
  group('E-Ink 模式封面（Issue 8）', () {
    test('E-Ink 模式開啟時，TXT 匯入封面為白底黑框', () async {
      SharedPreferences.setMockInitialValues({'app_eink_mode': true});
      final txtFile =
          File('${Directory.systemTemp.path}/import_test_eink_txt.txt');
      await txtFile.writeAsBytes(utf8.encode('第一章 開始\n正文'));
      addTearDown(() => txtFile.delete());

      final result =
          await service.importFiles([txtFile.path], displayNames: ['eink_novel.txt']);
      final book = result.importedBooks.first;
      final coverBytes = await File(book.coverPath!).readAsBytes();

      expect(await _pixelColor(coverBytes, 2, 2), const ui.Color(0xFF000000),
          reason: 'E-Ink 模式封面左上角應為黑色邊框');
    });

    test('E-Ink 模式開啟時，MD 匯入封面（無 Frontmatter 封面）同樣為白底黑框', () async {
      SharedPreferences.setMockInitialValues({'app_eink_mode': true});
      final mdFile =
          File('${Directory.systemTemp.path}/import_test_eink_md.md');
      await mdFile.writeAsBytes(utf8.encode('# 內容\n正文'));
      addTearDown(() => mdFile.delete());

      final result =
          await service.importFiles([mdFile.path], displayNames: ['eink_notes.md']);
      final book = result.importedBooks.first;
      final coverBytes = await File(book.coverPath!).readAsBytes();

      expect(await _pixelColor(coverBytes, 2, 2), const ui.Color(0xFF000000),
          reason: 'E-Ink 模式封面左上角應為黑色邊框');
    });

    test('E-Ink 模式關閉（預設）時，TXT 匯入封面維持既有 6 色輪替＋白字行為', () async {
      // 不設定 app_eink_mode，AppThemePreferences.loadEinkMode() 依既有邏輯
      // 預設回傳 false。
      final txtFile =
          File('${Directory.systemTemp.path}/import_test_noeink_txt.txt');
      await txtFile.writeAsBytes(utf8.encode('第一章 開始\n正文'));
      addTearDown(() => txtFile.delete());

      final result =
          await service.importFiles([txtFile.path], displayNames: ['novel.txt']);
      final book = result.importedBooks.first;
      final coverBytes = await File(book.coverPath!).readAsBytes();

      expect(
        await _pixelColor(coverBytes, 2, 2),
        isNot(const ui.Color(0xFF000000)),
        reason: '非 E-Ink 模式不應出現 E-Ink 分支才有的黑色邊框',
      );
    });

    test(
        'BookImportServiceImpl 建構子接收自訂 themePreferences 時，'
        '匯入確實使用該實例的 loadEinkMode()（而非忽略參數改建構預設實例）', () async {
      // 審查修正 I1：不設定 app_eink_mode（全域 SharedPreferences 維持預設
      // false），改用 _FixedEinkModePreferences（見下方 1c）固定回傳 true。
      // 若 BookImportServiceImpl 建構子筆誤忽略傳入的 themePreferences、
      // 改用預設 AppThemePreferences() 讀取全域設定，這裡會讀到 false，
      // 封面就不會是 E-Ink 樣式——這則測試才會抓到那個回歸；純靠
      // SharedPreferences.setMockInitialValues() 無法區分兩者（見
      // reviews/review-plan-issue-8.md I1）。
      final customService = BookImportServiceImpl(
        repository: repository,
        coversDirectory: coversDir,
        importedBooksDirectory: importedBooksDir,
        themePreferences: _FixedEinkModePreferences(true),
      );
      final txtFile =
          File('${Directory.systemTemp.path}/import_test_custom_prefs.txt');
      await txtFile.writeAsBytes(utf8.encode('第一章 開始\n正文'));
      addTearDown(() => txtFile.delete());

      final result = await customService.importFiles(
        [txtFile.path],
        displayNames: ['custom_prefs.txt'],
      );
      final book = result.importedBooks.first;
      final coverBytes = await File(book.coverPath!).readAsBytes();

      expect(await _pixelColor(coverBytes, 2, 2), const ui.Color(0xFF000000),
          reason: '注入的 themePreferences 固定回傳 true，封面應為 E-Ink 黑框樣式');
    });
  });

```

**1c. 新增像素採樣 helper** —— 在檔案最末（原第 1292 行 `main()` 的收尾 `}` 之後）新增：

```dart

/// 解碼 PNG bytes 並取出 (x, y) 位置的像素顏色。用途與寫法比照
/// txt_cover_generator_test.dart 的同名 private helper（各測試檔自成一體，
/// 不跨檔案共用這個小型私有函式）。
Future<ui.Color> _pixelColor(Uint8List pngBytes, int x, int y) async {
  final codec = await ui.instantiateImageCodec(pngBytes);
  final frame = await codec.getNextFrame();
  final image = frame.image;
  final byteData = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
  final bytes = byteData!.buffer.asUint8List();
  final offset = (y * image.width + x) * 4;
  return ui.Color.fromARGB(
    bytes[offset + 3],
    bytes[offset],
    bytes[offset + 1],
    bytes[offset + 2],
  );
}

/// 供上方 I1 修正測試使用：固定回傳 [_value] 的 `AppThemePreferences` 子類別，
/// 用來證明 `BookImportServiceImpl` 真的把建構子收到的 `themePreferences`
/// 存起來使用，而不是忽略參數、內部自行改建構一個預設實例（後者剛好也會
/// 讀到同一份全域 `SharedPreferences` 模擬狀態，單純用
/// `SharedPreferences.setMockInitialValues()` 測不出兩者差異）。
class _FixedEinkModePreferences extends AppThemePreferences {
  _FixedEinkModePreferences(this._value);
  final bool _value;

  @override
  Future<bool> loadEinkMode() async => _value;
}
```

這個 helper 用到 `dart:ui`（`ui.Color`／`ui.instantiateImageCodec`），在檔案頂部 import 區塊新增：

```dart
import 'dart:ui' as ui;
```

（放在 `import 'dart:typed_data';` 之後、`import 'package:archive/archive.dart';` 之前，維持 `dart:` 群組內字母序。）

- [ ] **Step 2：執行測試，確認失敗**

Run: `flutter test test/library/book_import_service_test.dart`
Expected: FAIL——`book_import_service_impl.dart` 尚未修改，`BookImportServiceImpl` 建構子還沒有 `themePreferences` 具名參數，新增的 I1 測試（`BookImportServiceImpl(..., themePreferences: _FixedEinkModePreferences(true))`）會編譯失敗，導致整個測試檔無法執行；即使先忽略這個編譯錯誤單看邏輯，其餘 3 個 E-Ink 測試也會是行為紅燈——TXT／MD 分支尚未讀取 `loadEinkMode()`，封面永遠是既有 6 色輪替樣式，斷言黑色邊框的地方會失敗。

- [ ] **Step 3：實作串接**

在 `app/lib/library/book_import_service_impl.dart` 頂部 import 區塊（原第 1-17 行）新增一行相對匯入，放在既有相對匯入群組最前面（`'..'` 字串序在字母序中排在 `'book_content_fingerprint.dart'` 之前）：

```dart
import '../theme/app_theme_preferences.dart';
```

建構子（原第 58-71 行）改為：

```dart
class BookImportServiceImpl implements BookImportService {
  BookImportServiceImpl({
    required LibraryRepository repository,
    Directory? coversDirectory,
    Directory? importedBooksDirectory,
    AppThemePreferences? themePreferences,
  })  : _repository = repository,
        _coversDirectory = coversDirectory,
        _importedBooksDirectory = importedBooksDirectory,
        _themePreferences = themePreferences ?? AppThemePreferences();

  // 使用 kBookMetadataChannel（library_repository.dart）作為共用通道名稱。

  final LibraryRepository _repository;
  final Directory? _coversDirectory;
  final Directory? _importedBooksDirectory;
  final AppThemePreferences _themePreferences;
```

TXT 分支（原第 269-289 行內的最後 4 行，`isFixedLayout = false;` 開始）改為：

```dart
      isFixedLayout = false;
      bookFilePath = await _landTxtEpub(synthesis.epubBytes, id);
      final isEinkMode = await _themePreferences.loadEinkMode();
      final coverBytes =
          await generateTxtCover(fallbackTitle, isEinkMode: isEinkMode);
      coverPath = await _landCover(coverBytes, id);
```

MD 分支（原第 330-349 行內，`isFixedLayout = false;` 開始到 `coverPath = await _landCover(coverBytes, id);` 結束）改為：

```dart
      isFixedLayout = false;
      bookFilePath = await _landMdEpub(synthesis.epubBytes, id);
      if (synthesis.frontmatterTitle != null && synthesis.frontmatterTitle!.isNotEmpty) {
        title = synthesis.frontmatterTitle!;
      }
      author = synthesis.frontmatterAuthor;
      // Frontmatter 未指定封面（或指定值無法解析，見 md_frontmatter.dart
      // 文件註解）時，退回比照 TXT 既有的「依書名文字動態生成封面」機制
      // （spec.md「TXT／Markdown 合成書籍結構」對 MD 的既定要求）。
      // 審查修正 M1：loadEinkMode() 刻意寫在 ?? 右側才 await，讓已有
      // Frontmatter 封面（frontmatterCoverBytes != null）時完全不觸發這次
      // Preferences 讀取（?? 是短路求值，左側非 null 時右側整段不會執行）。
      final coverBytes = synthesis.frontmatterCoverBytes ??
          await generateTxtCover(
            title,
            isEinkMode: await _themePreferences.loadEinkMode(),
          );
      coverPath = await _landCover(coverBytes, id);
```

在 `app/lib/main.dart` 第 77 行，把：

```dart
  final importService = BookImportServiceImpl(repository: repository);
```

改為：

```dart
  final importService = BookImportServiceImpl(
    repository: repository,
    themePreferences: themePreferences,
  );
```

（`themePreferences` 為 `main.dart` 第 71 行已建構好的既有實例，`AppThemePreferences` 已在檔案頂部 import，不需要新增 import。）

- [ ] **Step 4：執行測試，確認通過**

Run: `flutter test test/library/book_import_service_test.dart`
Expected: PASS（全部既有測試＋新增 4 個測試通過：E-Ink 開啟 TXT／E-Ink 開啟 MD／E-Ink 關閉 TXT／自訂 `themePreferences` 注入）。

- [ ] **Step 5：全專案完整驗證（本計劃最後一個 Task，比照 `CLAUDE.md`「測試執行範圍」）**

Run: `flutter analyze`
Expected: `No issues found!`

Run: `flutter test`
Expected: 全數通過，無回歸（`library_screen_test.dart` 兩處既有的 `BookImportServiceImpl(repository: repository)` 呼叫因新參數為可選，預期不受影響；`SharedPreferences.setMockInitialValues({})` 已在該檔案第 81 行的全域 `setUp()` 涵蓋，不需要額外修改）。

- [ ] **Step 6：Commit**

```bash
git add app/lib/library/book_import_service_impl.dart app/lib/main.dart app/test/library/book_import_service_test.dart
git commit -m "$(cat <<'EOF'
feat(epic-35): Issue 8 — BookImportServiceImpl 串接 E-Ink 封面樣式

TXT／MD 匯入分支呼叫 generateTxtCover() 前讀取 AppThemePreferences.loadEinkMode()，
E-Ink 模式開啟時新匯入的書籍封面改為白底黑框黑字。

Co-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_019sQtaEfjhZd2MD4vgFzBw3
EOF
)"
```

---

## 收尾備註（供 Issue 收尾時填寫，執行前留空）

- 全部 Task 完成後，比照既有慣例（Issue 2／3／5／7）在 `issues.md` Issue 8 補記完成狀態、commit 範圍。
- `_einkBorderWidth`（8px）為未經真機驗證的具體詮釋值，建議與 Issue 3／Issue 7 已記錄的其餘未驗證視覺細節一併排入下一輪真機驗證。
