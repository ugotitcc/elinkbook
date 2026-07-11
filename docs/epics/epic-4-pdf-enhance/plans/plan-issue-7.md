# Epic 4 Issue 7：真機驗證與收尾 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 完成 Epic 4（PDF 專業增強）的裝置端整合驗證與收尾——多欄位組合持久化的端到端驗證、NFR-1 基礎開啟效能量測、Issue 4 加粗濾鏡裝置矩陣缺口的正式收斂，並彙整全 epic 的最終驗收狀態。

**Architecture:** 本 issue 不新增產品程式碼，純粹是驗證與文件收斂性質（比照 `docs/archive/2026-07-07-epic-2-vertical-core/`「epic-3-fonts-layout Issue 6」既有模式，見 `tmp/epic-3/reviews/qa-issue-6-report.md` 的既有 QA 報告格式）。核心產出是一份 QA 報告（`docs/epics/epic-4-pdf-enhance/reviews/qa-issue-7-e2e-perf-report.md`，本目錄已列入 `.gitignore`，不進版控，僅供收尾決策參考）與 `issues.md`/`docs/epics.md` 的最終狀態更新。

**Tech Stack:** Flutter `integration_test`（真機）+ Python（`fpdf`/`Pillow`，用於產生本 issue 專用、不納入版本控制的 100MB+ 測試 PDF 素材）+ `adb`。

## Global Constraints

- **範圍排除 Issue 6**：依人類明確指示，Issue 6（手動選區裁切）已在其自身的 5 個任務＋whole-branch review 修復中經過多輪真機測試（21/21 → 22/22 整合測試皆通過），本 issue **不再重複驗證** Issue 6 的手動裁切互動邏輯。Task 1 的組合持久化驗證涉及 `pdfCropMode`/`pdfCropRect` 欄位時，僅使用簡單、非互動式的裁切模式（`none`/`autoDetect`）帶過，不驅動 `CropOverlayView` 的觸控互動。
- **裝置限制**：此開發環境全程僅有一台真機可用（`9491G`，Android 15／API 35，device id `3CEF42ECD491687`，透過 `flutter devices` 確認）。Issue 3-6 皆已多次記錄此限制。Issue 4 驗收標準要求的「API 24-30／API 31+ 裝置矩陣」在本 issue 內**依然無法**用真實裝置補齊——這是環境限制，不是可透過本 issue 的實作技巧解決的問題；Task 3 的產出是**正式收斂這個已知缺口的決策文件**，不是憑空生出一台裝置。
- **NFR-1 效能量測是「獨立驗證項」，不是自動化測試斷言**：依決策 #13（見 `design.md`），100MB+ PDF 基礎開啟效能（無濾鏡/無裁切）僅要求「產出明確結論（達標／未達標，記錄具體數字）」，不要求寫成會讓 `flutter test` failed/passed 的斷言（真機 debug build 的計時本身就有雜訊，寫成硬性斷言容易變成 flaky test）。Task 2 是量測＋記錄，不是新增自動化測試。
- **100MB+ 測試素材不納入版本控制**：比照 Issue 5/6 已建立的「暫時性測試素材，驗證後刪除，不進版控」慣例（見 `issues.md` Issue 5/6 完成說明），Task 2 產生的大型 PDF 檔案只存在於本機暫存目錄與裝置暫存空間，兩處在驗證完成後都要清除，絕不能被 `git add`。
- **`docs/epics/epic-4-pdf-enhance/reviews/` 已列入根目錄 `.gitignore`**（第 10 行 `docs/epics/epic-4-pdf-enhance/reviews/`）：本 issue 產出的 QA 報告寫入此目錄即可，不需要另外處理版控排除。
- **歸檔決策保留給人類**：依專案 SDD 生命週期規則（見 `CLAUDE.md`「生命週期」第 7 點），Epic 歸檔（搬移至 `docs/archive/`、更新 `docs/epics.md` 狀態為已歸檔）一律由人類指定，本 issue 的 Task 4 只負責把 `issues.md`／`docs/epics.md` 更新到「可供人類決定是否歸檔」的乾淨狀態，**不自行執行歸檔搬移動作**。
- **若發現需要後續處理的落差，另立 issue 追蹤、不阻塞本 epic 合併**（`issues.md` Issue 7 驗收標準原文）：比照 `epic-3-fonts-layout` Issue 6 發現 Issue 7/8/9 的既有模式（`tmp/epic-3/reviews/qa-issue-6-report.md` 可參考其報告格式），任何本 issue 過程中發現的新問題，記錄於 QA 報告與 `docs/epics.md` 備註即可，不要求當場修復。

---

### Task 1：端到端組合設定持久化驗證（自動化真機測試）

**Files:**
- Modify: `app/integration_test/reader_screen_test.dart`

**Interfaces:**
- Consumes：既有 `PdfReaderView`（Dart）完整欄位契約（`fitMode`／`contrast`／`brightness`／`boldStrength`／`cropMode`／`cropRect`，Issue 2-6 已建立）、`BookReaderPrefs` 全部 PDF 欄位、`BookReaderPrefsRepository.load`/`save`、本檔案既有輔助函式 `_stageAssetAsFile`／`_pumpUntil`／`_layoutSettingsButtonReady`／`_book`／`libraryRepository`（直接沿用，不重新宣告）。
- Produces：無（純驗證，不產生新的公開介面）。

本任務驗證的重點是「**多個欄位同時設定、同時持久化、同時正確載入**」——Issue 2-6 各自的既有測試都只驗證「調整單一欄位後關閉重開，該欄位被記住」，從未驗證多欄位組合情境下彼此是否互相干擾（例如某個分頁的 `_notifyChanged()` 呼叫是否不小心把另一分頁剛設定好的欄位清空——這正是 Issue 4/5 review 反覆抓到的「地雷」模式，這裡是最後一次系統性檢查）。

- [ ] **Step 1：撰寫測試**

在 `app/integration_test/reader_screen_test.dart` 檔案最後一個 `testWidgets` 之後、`}`（`main()` 結尾）之前新增：

```dart
  testWidgets(
      'PDF 依序調整 Fit 模式/對比度/亮度/加粗/裁切模式後關閉重開，全部欄位皆正確記住並套用（組合持久化收尾驗證）',
      (tester) async {
    final samplePath = await _stageAssetAsFile(
        'test/fixtures/sample.pdf', 'sample_pdf_e2e_combo.pdf');
    addTearDown(() async {
      final file = File(samplePath);
      if (await file.exists()) await file.delete();
    });
    const bookId = 'b_pdf_e2e_combo';
    await libraryRepository.insertBook(_book(bookId, format: BookFileFormat.pdf));

    await tester.pumpWidget(
      MaterialApp(
        home: ReaderScreen(
          filePath: samplePath,
          bookId: bookId,
          prefsRepository: prefsRepository,
        ),
      ),
    );

    await _pumpUntil(
      tester,
      () => _layoutSettingsButtonReady(tester),
      timeout: const Duration(seconds: 10),
    );

    await tester.tap(find.byKey(const Key('reader_layout_settings_button')));
    await tester.pumpAndSettle();

    // 顯示分頁：Fit 模式改為 Fit Width。
    await tester.tap(find.byKey(const Key('pdf_settings_fit_mode_fit_width')));
    await tester.pump(const Duration(milliseconds: 500));

    // 濾鏡分頁：對比度／亮度／加粗強度皆各按一次「+」微調鈕，確保三個欄位
    // 都偏離預設值 0，才能有效驗證彼此不會互相清空。
    await tester.tap(find.byKey(const Key('pdf_settings_tab_filters')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('pdf_settings_contrast_increment')));
    await tester.pump(const Duration(milliseconds: 300));
    await tester.tap(find.byKey(const Key('pdf_settings_brightness_increment')));
    await tester.pump(const Duration(milliseconds: 300));
    await tester.tap(find.byKey(const Key('pdf_settings_bold_strength_increment')));
    await tester.pump(const Duration(milliseconds: 300));

    // 裁切分頁：切到智慧自動（不使用手動選區——依 Global Constraints，本
    // issue 不重複驗證 Issue 6 的觸控互動邏輯）。
    await tester.tap(find.byKey(const Key('pdf_settings_tab_crop')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('pdf_settings_crop_mode_auto')));
    await tester.pump(const Duration(seconds: 1));

    // 關閉設定，記錄目前畫面上 PdfReaderView 的完整生效值，作為「調整完成
    // 當下」的基準，稍後與「重開書後」比對。
    await tester.tap(find.byKey(const Key('pdf_settings_tab_display')));
    await tester.pumpAndSettle();

    final beforeClose = tester.widget<PdfReaderView>(find.byType(PdfReaderView));
    expect(beforeClose.fitMode, PdfFitMode.fitWidth);
    expect(beforeClose.contrast, greaterThan(0));
    expect(beforeClose.brightness, greaterThan(0));
    expect(beforeClose.boldStrength, greaterThan(0));
    expect(beforeClose.cropMode, PdfCropMode.autoDetect);

    // 從資料庫直接讀出持久化結果（不透過畫面重建，排除「畫面剛好還沒
    // rebuild」這種偽陽性）。
    final saved = await prefsRepository.load(bookId);
    expect(saved.pdfFitMode, PdfFitMode.fitWidth);
    expect(saved.pdfContrast, greaterThan(0));
    expect(saved.pdfBrightness, greaterThan(0));
    expect(saved.pdfBoldStrength, greaterThan(0));
    expect(saved.pdfCropMode, PdfCropMode.autoDetect);
    expect(saved.pdfCropRect, isNotNull,
        reason: '智慧自動裁切應已計算出矩形並隨其餘欄位一併持久化');

    // 關閉重開，驗證 initialPreferences 在「多欄位同時非 null」的情境下
    // 依然完整無遺漏地送出——這是本任務要補上的、Issue 2-6 各自單欄位
    // 測試從未涵蓋過的組合情境。
    await tester.pumpWidget(const MaterialApp(home: SizedBox.shrink()));
    await tester.pump();

    await tester.pumpWidget(
      MaterialApp(
        home: ReaderScreen(
          filePath: samplePath,
          bookId: bookId,
          prefsRepository: prefsRepository,
        ),
      ),
    );
    await _pumpUntil(
      tester,
      _loadingIndicatorGone,
      timeout: const Duration(seconds: 10),
    );
    await tester.pump(const Duration(seconds: 1));

    final afterReopen = tester.widget<PdfReaderView>(find.byType(PdfReaderView));
    expect(afterReopen.fitMode, beforeClose.fitMode,
        reason: '重開書後 fitMode 應與關閉前一致');
    expect(afterReopen.contrast, beforeClose.contrast,
        reason: '重開書後 contrast 應與關閉前一致');
    expect(afterReopen.brightness, beforeClose.brightness,
        reason: '重開書後 brightness 應與關閉前一致');
    expect(afterReopen.boldStrength, beforeClose.boldStrength,
        reason: '重開書後 boldStrength 應與關閉前一致');
    expect(afterReopen.cropMode, beforeClose.cropMode,
        reason: '重開書後 cropMode 應與關閉前一致');
    expect(afterReopen.cropRect, beforeClose.cropRect,
        reason: '重開書後 cropRect 應與關閉前一致，且不因重開書而重新計算'
            '（見 Issue 5 決策 #3：全書統一比例，不逐頁重算、不重開書重算）');

    expect(find.byKey(const Key('reader_error_text')), findsNothing);
  });
```

- [ ] **Step 2：螢幕截圖視覺比對（`issues.md` 原文標註本項為「人工視覺 QA」，本 epic 自 Issue 3 起確立的紀律：綠燈測試必要但不充分）**

真機執行本任務新增的測試前，先手動走一遍相同操作序列（開書 → 依序調整 Fit Width／對比度／亮度／加粗／智慧自動裁切 → 用 `adb -s <device-id> exec-out screencap -p > combo_result.png` 截圖），用 `Read` 工具實際檢視這張截圖，確認：

- 畫面沒有因為多個濾鏡疊加而出現明顯異常（例如色彩完全跑掉、畫面全黑/全白、裁切範圍與濾鏡效果互相打架導致內容消失）
- 加粗效果（Issue 4 已驗證的「筆畫變粗變黑」）與對比度/亮度調整同時可見、沒有互相抵消或蓋掉彼此的視覺效果

若發現任何視覺異常，記錄在 Task 4 彙整的 QA 報告中，並依 Global Constraints 決定是否需要另立後續 issue 追蹤（不要求當場修復）。

- [ ] **Step 3：真機執行自動化測試**

Run: `cd app && flutter devices`（確認裝置 id，本環境預期為 `3CEF42ECD491687`）
Run: `cd app && flutter test integration_test/reader_screen_test.dart -d <device-id>`
Expected: 全數 PASS（既有 22 個測試 + 本任務新增的 1 個）。

若失敗，**依失敗的欄位判斷是否為既有「地雷」模式重演**（某個分頁的 `_notifyChanged()` 未把其餘分頁已設定的欄位原樣帶回）——若是，這是一個需要建立後續 issue 追蹤的真實缺陷（見 Global Constraints「若發現需要後續處理的落差」），不要為了讓測試通過而弱化斷言內容。

- [ ] **Step 4：`flutter analyze` 與完整測試套件**

Run: `cd app && flutter analyze`
Expected: `No issues found!`

Run: `cd app && flutter test`
Expected: 全數 PASS，無回歸。

- [ ] **Step 5：Commit**

```bash
git add app/integration_test/reader_screen_test.dart
git commit -m "test(epic-4): Issue 7 端到端組合設定持久化收尾驗證（Fit/對比度/亮度/加粗/裁切同時生效且重開書後一致）"
```

---

### Task 2：NFR-1 基礎開啟效能量測（100MB+ PDF，無濾鏡/無裁切）

**Files:**
- Create（暫時性、不納入版本控制）：本機暫存目錄下的 100MB+ 測試 PDF
- Modify: `docs/epics/epic-4-pdf-enhance/reviews/qa-issue-7-e2e-perf-report.md`（新建，本目錄已列入 `.gitignore`）

**Interfaces:**
- Consumes：`ReaderScreen(filePath: <裝置端絕對路徑>, bookId, prefsRepository)`——`filePath` 直接指向裝置檔案系統路徑，不透過 Flutter asset（100MB+ 素材不應打包進 App，見 Global Constraints）。
- Produces：QA 報告內的一段效能量測結論。

- [ ] **Step 1：產生 100MB+ 測試 PDF（本機，Python）**

在 scratchpad 目錄（或任何本機暫存位置，確保不在 `app/` 或任何會被 `git add` 的路徑下）執行：

```python
# generate_large_test_pdf.py
# 產生一份 100MB+ 的測試 PDF：每頁塞入一張隨機雜訊 JPEG（不可壓縮，確保
# 檔案大小可預期地隨頁數線性成長），純粹用於量測「基礎開啟時間」，不需要
# 有意義的視覺內容。驗證完成後即刪除，不納入版本控制。
import io
import random
from fpdf import FPDF
from PIL import Image

PAGE_COUNT = 60
IMG_SIZE = (1600, 2000)  # 單張隨機雜訊 JPEG 未壓縮前約 9.6MB，JPEG 品質 95
                          # 壓縮後仍可達每頁約 1.7-2MB，60 頁可達 100MB+

pdf = FPDF(unit="pt", format=(IMG_SIZE[0], IMG_SIZE[1]))
random.seed(42)  # 固定 seed，確保每次產生的檔案大小可預期、可重現

for page in range(PAGE_COUNT):
    pdf.add_page()
    noise = Image.frombytes(
        "RGB", IMG_SIZE,
        bytes(random.getrandbits(8) for _ in range(IMG_SIZE[0] * IMG_SIZE[1] * 3)),
    )
    buf = io.BytesIO()
    noise.save(buf, format="JPEG", quality=95)
    buf.seek(0)
    pdf.image(buf, x=0, y=0, w=IMG_SIZE[0], h=IMG_SIZE[1], type="JPEG")
    print(f"page {page + 1}/{PAGE_COUNT} done")

pdf.output("large_test.pdf")
```

Run: `python generate_large_test_pdf.py`
Expected: 產生 `large_test.pdf`，檢查檔案大小：

```bash
ls -la large_test.pdf
```

Expected: 檔案大小 ≥ 100MB（105000000 bytes 以上）。若不足，調高 `PAGE_COUNT` 或 `IMG_SIZE` 後重新產生。

- [ ] **Step 2：推送至真機**

```bash
adb devices  # 確認 device id
adb -s <device-id> push large_test.pdf /sdcard/Android/data/cc.ugotit.elinkbook/files/large_test.pdf
```

Expected: `push` 指令成功回報已傳輸的位元組數，與本機檔案大小相符。

（`/sdcard/Android/data/cc.ugotit.elinkbook/files/` 是本 App 的專屬外部檔案目錄，API 30+ 裝置上 App 存取自己專屬目錄不需要額外的儲存權限，`adb push` 到這個路徑不需要 root。）

- [ ] **Step 3：撰寫暫時性量測用 `integration_test`**

在 `app/integration_test/` 建立一個**暫時性、驗證後刪除、不納入版本控制**的測試檔（比照 Issue 5/6 已建立的暫時性視覺驗證檔案慣例）：

```dart
// app/integration_test/_perf_check_large_pdf.dart
// 暫時性效能量測專用檔案，僅供 Issue 7 NFR-1 基礎開啟效能量測使用，
// 驗證後即刪除，不納入版本控制／不隨本 issue 提交。
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:elinkbook/library/sqlite_library_repository.dart';
import 'package:elinkbook/reader/book_reader_prefs_repository.dart';
import 'package:elinkbook/screens/reader_screen.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('NFR-1 量測：100MB+ PDF 基礎開啟時間（無濾鏡/無裁切）',
      (tester) async {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    final libraryRepository =
        await SqliteLibraryRepository.open(inMemoryDatabasePath);
    final prefsRepository = BookReaderPrefsRepository(libraryRepository.database);

    final stopwatch = Stopwatch()..start();

    await tester.pumpWidget(
      MaterialApp(
        home: ReaderScreen(
          filePath:
              '/sdcard/Android/data/cc.ugotit.elinkbook/files/large_test.pdf',
          bookId: 'b_perf_large',
          prefsRepository: prefsRepository,
        ),
      ),
    );

    final deadline = DateTime.now().add(const Duration(seconds: 30));
    while (find.byKey(const Key('reader_loading_indicator')).evaluate().isNotEmpty) {
      if (DateTime.now().isAfter(deadline)) {
        fail('等待逾時（30 秒）：載入指示器未消失');
      }
      await tester.pump(const Duration(milliseconds: 50));
    }

    stopwatch.stop();
    expect(find.byKey(const Key('reader_error_text')), findsNothing,
        reason: '大型 PDF 應能成功開啟，不應觸發 onError');

    // 印出實測結果供人工記錄至 QA 報告（本測試刻意不對耗時做 pass/fail
    // 斷言，見 plan-issue-7.md Global Constraints「NFR-1 效能量測是獨立
    // 驗證項」）。
    // ignore: avoid_print
    print('NFR-1_ELAPSED_MS=${stopwatch.elapsedMilliseconds}');

    await libraryRepository.close();
  });
}
```

- [ ] **Step 4：真機執行並記錄結果**

Run: `cd app && flutter test integration_test/_perf_check_large_pdf.dart -d <device-id>`
Expected: 測試 PASS（無 onError、30 秒內載入完成），終端機輸出包含一行 `NFR-1_ELAPSED_MS=<數字>`。

**重複執行 3 次**（真機 debug build 首次冷啟動可能包含額外的 JIT/資源初始化成本，多次量測取得較穩定的數字），記錄每次的 `NFR-1_ELAPSED_MS` 數值。

- [ ] **Step 5：撰寫 QA 報告，記錄結論**

新建 `docs/epics/epic-4-pdf-enhance/reviews/qa-issue-7-e2e-perf-report.md`，內容比照 `tmp/epic-3/reviews/qa-issue-6-report.md` 的既有格式（表格化的驗證項目 + 結論），至少包含：

- 三次量測的原始數字（`NFR-1_ELAPSED_MS`）
- 平均值／中位數
- **明確結論**：與 2000ms 門檻比較，達標／未達標
- **重要限制務必如實記錄**：debug build（`flutter test integration_test` 預設走 debug build，非 release/profile build）的效能數字通常明顯劣於正式發佈版本，此數字僅供「基礎功能不會嚴重卡死」的粗略參考，不代表使用者實際體感效能；若要取得正式 NFR-1 驗收等級的數字，需改用 `flutter build apk --release` 產出的正式建置版本重新量測——記錄此為本次量測範圍的已知限制，不在本 issue 範圍內另外執行 release build 量測（除非達標門檻本身在 debug build 下就已經明顯超標，那種情況下才需要進一步用 release build 排除「只是 debug 建置較慢」的可能性）。

- [ ] **Step 6：清理暫時性檔案**

```bash
rm app/integration_test/_perf_check_large_pdf.dart
adb -s <device-id> shell rm /sdcard/Android/data/cc.ugotit.elinkbook/files/large_test.pdf
rm large_test.pdf  # 本機暫存的 100MB+ 檔案，確認已刪除
```

Run: `cd U:\MyDeveloper\AI\elinkBook && git status --short`
Expected：確認 `app/integration_test/_perf_check_large_pdf.dart` 不再出現於 `git status` 輸出中（未被追蹤、已刪除）。

（本任務不需要 commit 任何程式碼異動——QA 報告位於已被 `.gitignore` 排除的 `reviews/` 目錄，測試檔案已清理，唯一需要保留的產出是 QA 報告本身，留在本機供 Task 4 彙整參考。）

---

### Task 3：Issue 4 加粗效能裝置矩陣缺口的正式收斂（決策文件，非程式碼）

**Files:**
- Modify: `docs/epics/epic-4-pdf-enhance/issues.md`（Issue 4 區塊）
- Modify: `docs/epics.md`（若決定新增 Backlog 追蹤項）

**Interfaces:**
- Consumes：無
- Produces：無（純文件決策）

`issues.md` 對 Issue 7 的驗收標準要求「若 Issue 4 階段未能涵蓋完整裝置矩陣，本 issue 需補齊」——但依 Global Constraints，本開發環境全程只有一台 API 35 裝置可用，物理上無法在本 issue 內生出一台 API 24-30 或其他 API 31+ 裝置。本任務的產出是**誠實地正式收斂這個缺口**，而不是假裝已經補齊。

- [ ] **Step 1：確認目前環境確實沒有其他可用裝置**

Run: `flutter devices`
Expected：確認輸出中僅有 `9491G (API 35)` 一台 Android 實體裝置（加上桌面/瀏覽器等非 Android 目標，這些不適用於本驗證）。若此時環境剛好新增了其他 Android 裝置，才需要實際執行 Issue 4 驗收標準要求的加粗效能複驗（拖動加粗強度滑桿、觀察是否卡頓/崩潰），並將結果補進 `issues.md` Issue 4 區塊。

- [ ] **Step 2：在 `issues.md` Issue 4 區塊補上正式收斂備註**

在 `docs/epics/epic-4-pdf-enhance/issues.md` 現有的 Issue 4 完成說明段落最後（原文已有「僅在 API 35 真機驗證，未涵蓋 API 24-30 裝置」的既有備註）追加一句：

```
（Issue 7 收尾時再次確認：本開發環境全程僅有此台 API 35 裝置可用，無法在
epic 合併前補齊 API 24-30／其他 API 31+ 裝置的複驗，正式收斂為已知、
已記錄的殘留風險，不阻塞本 epic 合併——若未來取得額外測試裝置，應優先
執行此複驗。）
```

- [ ] **Step 3：於 `docs/epics.md` 新增一筆 Backlog 追蹤項**（若尚未存在對應項目）

比照 `docs/epics.md` 現有的 `epic-15-storage-permission` 這類「非獨立 Epic、但需要記錄追蹤的技術債」條目格式，在 `docs/epics.md` 的表格中新增一列（置於現有列表最後、`epic-15-storage-permission` 之後）：

```markdown
| `epic-4-pdf-enhance`（技術債）加粗濾鏡裝置矩陣複驗 | ⚪ 未開始 (Backlog) | N/A | FR-11 | Issue 4 驗收標準要求 API 24-30／API 31+ 裝置矩陣複驗加粗（型態學膨脹）效能與穩定性，全程開發環境僅有 API 35 裝置可用，Issue 7 收尾時正式記錄為已知殘留風險。待未來取得額外測試裝置（尤其 API 24-30 範圍，`minSdk=24`）時執行 |
```

- [ ] **Step 4：Commit**

```bash
git add docs/epics/epic-4-pdf-enhance/issues.md docs/epics.md
git commit -m "docs(epic-4): Issue 7 正式收斂 Issue 4 加粗效能裝置矩陣缺口為已知殘留風險"
```

---

### Task 4：彙整全 epic 驗收狀態、更新 `issues.md`／`docs/epics.md`

**Files:**
- Modify: `docs/epics/epic-4-pdf-enhance/issues.md`（Issue 7 區塊、標題整體狀態）
- Modify: `docs/epics.md`

**Interfaces:**
- Consumes：Task 1-3 的產出（測試結果、QA 報告、Task 3 的收斂決策）
- Produces：無

- [ ] **Step 1：把 Task 1-3 的結果彙整進 `docs/epics/epic-4-pdf-enhance/reviews/qa-issue-7-e2e-perf-report.md`**

在 Task 2 Step 5 已建立的 QA 報告檔案中，補上 Task 1（組合持久化）與 Task 3（裝置矩陣收斂）的結果段落，讓這份報告成為本 issue 的完整交付紀錄（比照 `tmp/epic-3/reviews/qa-issue-6-report.md` 的「結論」表格彙整格式，一列一個驗證項目 + 狀態 + 備註）。

- [ ] **Step 2：更新 `docs/epics/epic-4-pdf-enhance/issues.md`——Issue 7 標題與完成說明**

把 Issue 7 的標題與 `**Status:**` 段落改為完成狀態，比照 Issue 3-6 既有的完成說明風格：涵蓋 Task 1 的組合持久化測試結果、Task 2 的 NFR-1 量測結論（含 debug build 限制的誠實說明）、Task 3 的裝置矩陣缺口正式收斂決定、以及本 issue 過程中若有發現的任何新問題（若有，需註明已建立哪個後續 issue 追蹤）。

- [ ] **Step 3：更新 `docs/epics.md`——Epic 4 狀態列**

把 `docs/epics.md` 中 `epic-4-pdf-enhance` 那一列的備註更新為「Issue 1-7 已完成並合併回 main」，並保留既有備註中仍然有效的技術細節（對比度/亮度 bug 修復、加粗統一演算法、智慧自動裁切、手動選區裁切與其 whole-branch review 修復）；新增一句總結本次 Issue 7 收尾的結論（NFR-1 量測結果、裝置矩陣已知限制）。**狀態燈號本身維持 `🟡 開發中 (Active)`，不要自行改成 `🟢 已歸檔 (Archived)`**——依 Global Constraints，歸檔動作需要人類明確指定，本步驟只負責把狀態列更新到「所有 Issue 皆已完成，可供人類決定何時歸檔」的乾淨狀態。

- [ ] **Step 4：`flutter analyze` 與完整測試套件最終確認**

Run: `cd app && flutter analyze`
Expected: `No issues found!`

Run: `cd app && flutter test`
Expected: 全數 PASS。

- [ ] **Step 5：Commit**

```bash
git add docs/epics/epic-4-pdf-enhance/issues.md docs/epics.md
git commit -m "docs(epic-4): Issue 7 彙整驗收狀態，Epic 4 Issue 1-7 全數完成"
```
