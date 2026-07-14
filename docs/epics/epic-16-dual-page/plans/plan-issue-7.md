# Epic 16 Issue 7：真機驗證與收尾 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development（推薦）或 superpowers:executing-plans 逐 Task 執行本計劃。每個 Step 用 checkbox（`- [ ]`）追蹤，完成後即時勾選為 `[x]`（見 CLAUDE.md SDD 生命週期第 6 步）。

**Goal:** 完成 Epic 16（橫向雙頁顯示）的裝置端整合驗證與收尾——PDF 端到端組合設定持久化驗證（雙頁 3 欄位＋既有 Fit/濾鏡/裁切 5 欄位，共 8 欄位）、FR-41「頁間不留空白」PDF／EPUB FXL 兩條路線的明確視覺確認、裝置旋轉時 PDF／EPUB 兩條 `PlatformView` 皆不重建的驗證，並彙整全 Epic 最終驗收狀態供人類決定是否歸檔。

**Architecture:** 本 issue 不新增產品程式碼——唯一例外是 Task 3 為了取得「PlatformView 是否因旋轉重建」的可觀察證據，需要在 `PdfReaderView.kt`／`EpubReaderView.kt` 的 `openBook()` 加入暫時性 `Log.d` 插樁，驗證後全數還原，不隨本 issue commit（比照 Issue 1 spike 的既有插樁慣例，見 `reviews/spike-readium-spread.md`「插樁與執行細節」）。核心產出是一份 QA 報告（`docs/epics/epic-16-dual-page/reviews/qa-issue-7-report.md`）＋ `issues.md`／`docs/epics.md` 的最終狀態更新。

**Tech Stack:** Flutter `integration_test`（真機）＋ `flutter run -t <自訂 target>` 暫時性除錯進入點＋ Python（`fpdf2` + `Pillow`，產生本 issue 專用、不納入版本控制的雙色測試 PDF 與像素量測腳本）＋ `adb`（`screencap`／`logcat`／`push`）。

## Global Constraints

- **裝置限制**：本開發環境目前僅有一台真機可用（`9491G`，Android 15／API 35，device id `3CEF42ECD491687`，透過 `flutter devices` 確認；若執行時環境已更換，以當下 `flutter devices` 輸出為準，後續步驟一律以 `<device-id>` 表示）。
- **範圍依 `issues.md` Issue 7 原文的 5 個項目**：(1) PDF 組合持久化自動化測試、(2) FR-41 兩路線明確視覺確認、(3) 裝置旋轉不重建確認、(4) 彙整驗收狀態、(5) 若有落差另立 issue 追蹤。不擴大範圍去實作 FR-42 全螢幕沉浸顯示或 RTL 熱區鏡像等 `spec.md`「已知限制」中已明確記錄為「留待未來 Epic」的項目。
- **EPUB FXL 的 FR-41 確認不需要重新執行**：Issue 6 已完成的真機視覺驗收（`issues.md` Issue 6「真機視覺驗收（2026-07-14）」／`spec.md` 測試決策第 157 行）已明確得出「翻頁至內頁後左右兩頁正常顯示且無縫並排，FR-41 核心驗收點通過」的結論。本 issue Task 2 對 EPUB FXL 路線只需在 QA 報告中引用此既有結論並交叉核對來源，**不重複執行真機視覺測試**——重複執行對已有明確結論的項目是浪費，不是嚴謹。PDF 路線則是真正的驗證缺口：`issues.md` Issue 3 完成說明已明文承認「FR-41…無法透過 `integration_test` 自動化驗證…像素層級確認留給 Issue 7」，這才是本 issue Task 2 的實際工作範圍。
- **暫時性素材與程式碼一律不納入版本控制**：Task 2 產生的雙色測試 PDF 與像素量測腳本、Task 2/3 使用的 `flutter run` 暫時性除錯進入點檔案（`app/lib/dev_*.dart`）、Task 3 插樁用的 `Log.d` 語句，皆在驗證完成後刪除／還原，並以 `git status --short` 確認乾淨後才可進行該 Task 的 commit。
- **Task 3 的暫時性插樁比照 Issue 1 spike 的既有慣例**：改動最小、驗證後用 `git diff` 逐行確認已完全還原，不得留下任何插樁殘留。
- **若驗證發現需要後續處理的落差**（例如 FR-41 未達標、旋轉確實造成重建），依 `issues.md` 原文「比照既有慣例另立後續 issue 追蹤，不阻塞本 epic 合併」處理，不要求在本 issue 內就地修復；但若修復成本低且風險小（例如發現 `AndroidManifest.xml` 遺漏必要的 `configChanges` 屬性），可在 Task 3 內直接修正並如實記錄，不需要另立 issue（比照 `issues.md` Issue 6「Bugfix 紀錄」的既有先例）。
- **`docs/epics/epic-16-dual-page/reviews/` 目前未被加入根目錄 `.gitignore`**（與多數其他 Epic「reviews/ 整個 gitignore」的既有慣例不同；Issue 1 的兩份 spike 報告 `spike-readium-spread.md`／`spike-readium-spread-webview-count.md` 已是耐久證據並入版本控制的先例）：本 issue 的 QA 報告延續同一慣例，**需要** `git add`，不像 `epic-4-pdf-enhance` Issue 7 那樣自動被排除在外。
- **歸檔決策保留給人類**：依 `CLAUDE.md`「生命週期」第 7 點，Epic 歸檔一律由人類指定，Task 4 只負責把 `issues.md`／`docs/epics.md` 更新到「Epic 16 全部 Issue 皆已完成，可供人類決定是否歸檔」的乾淨狀態，**不自行執行歸檔搬移動作**。
- **本計劃所有 Shell 指令假設在 Git Bash（POSIX）環境下執行**（`grep`／`rm`／管線組合），與本 Epic 既有全部計劃（Issue 1/3/5/6/8/9）的既有慣例一致。若改在原生 PowerShell／`cmd.exe` 下執行，`grep` 需替換為 `Select-String`（PowerShell）或 `findstr`（`cmd.exe`），`rm` 需替換為 `Remove-Item`（PowerShell）或 `del`（`cmd.exe`）。

---

### Task 1：PDF 端到端組合設定持久化驗證（自動化真機測試，8 欄位全覆蓋）

**Files:**
- Modify: `app/integration_test/reader_screen_test.dart`

**Interfaces:**
- Consumes：既有 `PdfReaderView`（Dart）完整欄位契約（`fitMode`／`contrast`／`brightness`／`boldStrength`／`cropMode`／`cropRect`／`dualPageMode`／`dualPageCoverAlone`／`dualPageDirection`，Issue 2-6 已建立）、`PdfSettingsSheet` 既有 Key 契約（`pdf_settings_tab_display`／`_filters`／`_crop`、`pdf_settings_fit_mode_fit_width`、`pdf_settings_dual_page_mode_always`、`pdf_settings_dual_page_cover_alone`、`pdf_settings_dual_page_direction_ltr`、`pdf_settings_contrast_increment`／`_brightness_increment`／`_bold_strength_increment`、`pdf_settings_crop_mode_auto`）、本檔案既有輔助函式 `_stageAssetAsFile`／`_pumpUntil`／`_layoutSettingsButtonReady`／`_loadingIndicatorGone`／`_book`／`libraryRepository`／`prefsManager`（直接沿用，不重新宣告，皆已在檔案開頭定義）。
- Produces：無（純驗證，不產生新的公開介面）。

既有的兩個相關測試——`reader_screen_test.dart` 第 1219 行「Fit 模式/對比度/亮度/加粗/裁切模式」組合測試（`epic-4-pdf-enhance` Issue 7 建立）與第 1335 行「封面獨立開關與頁面方向」測試（Issue 4 建立）——分別驗證了兩組欄位各自的組合持久化，但**從未在同一次操作序列中同時涵蓋全部 8 個欄位**，也就從未驗證過「調整雙頁相關欄位」與「調整既有 Fit/濾鏡/裁切欄位」彼此不會互相清空（`PdfSettingsSheet._notifyChanged()` 目前是單一 `_PdfSettingsSheetState` 統一持有全部本地狀態後一次送出，理論上不會重演 Issue 4/5 review 曾抓到的「地雷」模式，但本 issue 是這個假設在真機上的最後一次系統性覆核，不能只靠程式碼閱讀判斷）。本任務新增一個涵蓋全部 8 欄位的組合測試，不修改既有兩個測試。

- [ ] **Step 1：撰寫測試**

在 `app/integration_test/reader_screen_test.dart` 檔案最後一個 `testWidgets`（第 1502 行結尾 `});`）之後、`}`（`main()` 結尾，第 1503 行）之前新增：

```dart
  testWidgets(
      'PDF 依序調整雙頁模式/封面獨立/方向/Fit模式/濾鏡/裁切模式後關閉重開，8 個欄位皆正確記住並套用、彼此不互相清空（Issue 7 收尾組合驗證）',
      (tester) async {
    final samplePath = await _stageAssetAsFile(
        'test/fixtures/sample.pdf', 'sample_pdf_issue7_combo.pdf');
    addTearDown(() async {
      final file = File(samplePath);
      if (await file.exists()) await file.delete();
    });
    const bookId = 'b_pdf_issue7_combo';
    await libraryRepository.insertBook(_book(bookId, format: BookFileFormat.pdf));

    await tester.pumpWidget(
      MaterialApp(
        home: ReaderScreen(
          filePath: samplePath,
          bookId: bookId,
          prefsManager: prefsManager,
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

    // 顯示分頁（預設開啟）：依序調整雙頁模式／封面獨立／方向／Fit 模式，
    // 皆偏離各自的預設值（auto/true/rtl/pageFit），確保稍後能有效驗證
    // 「非預設值」也被正確持久化，而非巧合地與預設值相同。
    await tester.ensureVisible(
        find.byKey(const Key('pdf_settings_dual_page_mode_always')));
    await tester.tap(find.byKey(const Key('pdf_settings_dual_page_mode_always')));
    await tester.pump(const Duration(milliseconds: 300));

    await tester.ensureVisible(
        find.byKey(const Key('pdf_settings_dual_page_cover_alone')));
    await tester.tap(find.byKey(const Key('pdf_settings_dual_page_cover_alone')));
    await tester.pump(const Duration(milliseconds: 300));

    await tester.ensureVisible(
        find.byKey(const Key('pdf_settings_dual_page_direction_ltr')));
    await tester.tap(find.byKey(const Key('pdf_settings_dual_page_direction_ltr')));
    await tester.pump(const Duration(milliseconds: 300));

    await tester.tap(find.byKey(const Key('pdf_settings_fit_mode_fit_width')));
    await tester.pump(const Duration(milliseconds: 500));

    // 濾鏡分頁：對比度／亮度／加粗強度皆各按一次「+」微調鈕，確保三個欄位
    // 都偏離預設值 0。
    await tester.tap(find.byKey(const Key('pdf_settings_tab_filters')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('pdf_settings_contrast_increment')));
    await tester.pump(const Duration(milliseconds: 300));
    await tester.tap(find.byKey(const Key('pdf_settings_brightness_increment')));
    await tester.pump(const Duration(milliseconds: 300));
    await tester.tap(find.byKey(const Key('pdf_settings_bold_strength_increment')));
    await tester.pump(const Duration(milliseconds: 300));

    // 裁切分頁：切到智慧自動（不使用手動選區——本 issue 不重複驗證 Issue 6
    // 的觸控互動邏輯，比照 epic-4-pdf-enhance Issue 7 的既有 Global
    // Constraints 慣例）。
    await tester.tap(find.byKey(const Key('pdf_settings_tab_crop')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('pdf_settings_crop_mode_auto')));
    await tester.pump(const Duration(seconds: 1));

    // 切回顯示分頁讓畫面穩定，再讀取目前生效值作為「調整完成當下」的基準。
    await tester.tap(find.byKey(const Key('pdf_settings_tab_display')));
    await tester.pumpAndSettle();

    final beforeClose = tester.widget<PdfReaderView>(find.byType(PdfReaderView));
    expect(beforeClose.dualPageMode, DualPageMode.always);
    expect(beforeClose.dualPageCoverAlone, isFalse);
    expect(beforeClose.dualPageDirection, DualPageDirection.ltr);
    expect(beforeClose.fitMode, PdfFitMode.fitWidth);
    expect(beforeClose.contrast, greaterThan(0));
    expect(beforeClose.brightness, greaterThan(0));
    expect(beforeClose.boldStrength, greaterThan(0));
    expect(beforeClose.cropMode, PdfCropMode.autoDetect);

    // 從資料庫直接讀出持久化結果（不透過畫面重建，排除「畫面剛好還沒
    // rebuild」這種偽陽性）。
    final saved = (await prefsManager.load(bookId)).bookPrefs;
    expect(saved.dualPageMode, DualPageMode.always);
    expect(saved.dualPageCoverAlone, isFalse);
    expect(saved.dualPageDirection, DualPageDirection.ltr);
    expect(saved.pdfFitMode, PdfFitMode.fitWidth);
    expect(saved.pdfContrast, greaterThan(0));
    expect(saved.pdfBrightness, greaterThan(0));
    expect(saved.pdfBoldStrength, greaterThan(0));
    expect(saved.pdfCropMode, PdfCropMode.autoDetect);
    expect(saved.pdfCropRect, isNotNull,
        reason: '智慧自動裁切應已計算出矩形並隨其餘 7 個欄位一併持久化');

    // 關閉重開，驗證 initialPreferences 在「8 個欄位同時非 null」的情境下
    // 依然完整無遺漏地送出——這是本任務要補上的、Issue 2-6 各自單欄位/半組
    // 測試從未涵蓋過的完整組合情境。
    await tester.pumpWidget(const MaterialApp(home: SizedBox.shrink()));
    await tester.pump();

    await tester.pumpWidget(
      MaterialApp(
        home: ReaderScreen(
          filePath: samplePath,
          bookId: bookId,
          prefsManager: prefsManager,
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
    expect(afterReopen.dualPageMode, beforeClose.dualPageMode,
        reason: '重開書後 dualPageMode 應與關閉前一致');
    expect(afterReopen.dualPageCoverAlone, beforeClose.dualPageCoverAlone,
        reason: '重開書後 dualPageCoverAlone 應與關閉前一致');
    expect(afterReopen.dualPageDirection, beforeClose.dualPageDirection,
        reason: '重開書後 dualPageDirection 應與關閉前一致');
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
        reason: '重開書後 cropRect 應與關閉前一致，且不因重開書而重新計算');

    expect(find.byKey(const Key('reader_error_text')), findsNothing);
  });
```

- [ ] **Step 2：真機執行自動化測試**

Run: `cd app && flutter devices`（確認裝置 id，本環境預期為 `3CEF42ECD491687`）
Run: `cd app && flutter test integration_test/reader_screen_test.dart -d <device-id>`
Expected: 全數 PASS（既有測試 + 本任務新增的 1 個）。

若失敗，**依失敗的欄位判斷是否為「地雷」模式重演**（某個分頁的 `_notifyChanged()` 未把其餘分頁已設定的欄位原樣帶回）——若是，這是需要建立後續 issue 追蹤的真實缺陷（見 Global Constraints「若驗證發現需要後續處理的落差」），不要為了讓測試通過而弱化斷言內容。

- [ ] **Step 3：`flutter analyze` 與完整測試套件**

Run: `cd app && flutter analyze`
Expected: `No issues found!`

Run: `cd app && flutter test`
Expected: 全數 PASS，無回歸。

- [ ] **Step 4：Commit**

```bash
git add app/integration_test/reader_screen_test.dart
git commit -m "test(epic-16): Issue 7 PDF 8 欄位組合持久化收尾驗證（雙頁模式/封面獨立/方向 + Fit/濾鏡/裁切）"
```

---

### Task 2：FR-41 核心驗收確認——PDF 路線真機像素量測 + EPUB FXL 路線既有結論引用

**Files:**
- Create（暫時性、不納入版本控制）：本機暫存目錄下的雙色測試 PDF 與像素量測腳本、`app/lib/dev_fr41_pdf_harness.dart`
- Create: `docs/epics/epic-16-dual-page/reviews/qa-issue-7-report.md`（新建，**需要** `git add`，見 Global Constraints）

**Interfaces:**
- Consumes：`PdfReaderView`（Dart）既有欄位契約。
- Produces：QA 報告內的 FR-41 兩路線結論段落。

`pdf_dual_page_test.dart` 目前只驗證翻頁步進的索引邏輯（`onPageChanged` 回報值），從未驗證拼接後的畫面本身是否真的無縫——這正是 `issues.md` Issue 3 完成說明明文承認的缺口。本任務用一份左右頁各為單一鮮明對比色的專屬測試 PDF，讓「拼接處是否有間隙」可以用像素量測直接驗證，而非僅憑肉眼主觀判斷。

- [ ] **Step 0：安裝 Python 依賴**

```bash
pip install fpdf2 pillow
```

Expected：成功安裝（或確認已安裝），供 Step 1 的 `fpdf` 與 Step 5 的 `PIL`（Pillow）匯入使用。

- [ ] **Step 1：產生雙色測試 PDF（本機，Python）**

在 scratchpad 目錄（或任何本機暫存位置，確保不在 `app/` 或任何會被 `git add` 的路徑下）執行：

```python
# generate_fr41_gap_test_pdf.py
# 產生一份 2 頁的測試 PDF：第 0 頁純紅、第 1 頁純藍，頁面尺寸與既有
# sample_dual_page.pdf 一致（300x400pt）。搭配 dualPageCoverAlone=false，
# 第一個 spread 即為 [0,1]（紅/藍相鄰），拼接處若有間隙/留白，會在紅藍
# 交界處產生一段非紅非藍的像素帶，可用程式量測偵測。驗證後即刪除，
# 不納入版本控制。
from fpdf import FPDF

PAGE_SIZE = (300, 400)  # pt

pdf = FPDF(unit="pt", format=PAGE_SIZE)

pdf.add_page()
pdf.set_fill_color(255, 0, 0)
pdf.rect(0, 0, PAGE_SIZE[0], PAGE_SIZE[1], style="F")

pdf.add_page()
pdf.set_fill_color(0, 0, 255)
pdf.rect(0, 0, PAGE_SIZE[0], PAGE_SIZE[1], style="F")

pdf.output("fr41_gap_test.pdf")
```

Run: `python generate_fr41_gap_test_pdf.py`
Expected: 產生 `fr41_gap_test.pdf`（2 頁）。

- [ ] **Step 2：推送至真機**

```bash
adb devices  # 確認 device id
adb -s <device-id> push fr41_gap_test.pdf /sdcard/Android/data/cc.ugotit.elinkbook/files/fr41_gap_test.pdf
```

Expected: `push` 指令成功回報已傳輸的位元組數。

- [ ] **Step 3：建立暫時性 `flutter run` 除錯進入點**

在 `app/lib/` 新建（**暫時性、驗證後刪除、不納入版本控制**）：

```dart
// app/lib/dev_fr41_pdf_harness.dart
// 暫時性 flutter run 除錯進入點，僅供 Issue 7 Task 2 FR-41 PDF 路線像素
// 量測驗證使用，驗證後刪除，不納入版本控制。直接以 dualPageMode: always
// + dualPageCoverAlone: false 開啟第一個 spread（紅頁/藍頁相鄰），持續
// 顯示於畫面上供 adb screencap 擷取。
import 'package:flutter/material.dart';

import 'reader/dual_page_direction.dart';
import 'reader/dual_page_mode.dart';
import 'reader/pdf_fit_mode.dart';
import 'reader/pdf_reader_view.dart';

void main() {
  runApp(MaterialApp(
    home: Scaffold(
      backgroundColor: Colors.black,
      body: PdfReaderView(
        filePath:
            '/sdcard/Android/data/cc.ugotit.elinkbook/files/fr41_gap_test.pdf',
        onPageRendered: () {},
        onError: (message) => debugPrint('FR41_HARNESS_ERROR: $message'),
        fitMode: PdfFitMode.pageFit,
        dualPageMode: DualPageMode.always,
        dualPageCoverAlone: false,
        dualPageDirection: DualPageDirection.ltr,
        isLandscape: true,
      ),
    ),
  ));
}
```

- [ ] **Step 4：執行並截圖**

```bash
cd app
flutter run -t lib/dev_fr41_pdf_harness.dart -d <device-id>
```

待畫面穩定顯示紅藍雙頁拼接畫面後（不要中斷 `flutter run` 程序），另開一個終端機視窗執行：

```bash
adb -s <device-id> exec-out screencap -p > fr41_screenshot.png
```

Expected: 產生 `fr41_screenshot.png`。截圖完成後回到 `flutter run` 終端機按 `q` 結束程序。

用 `Read` 工具實際檢視 `fr41_screenshot.png`，確認畫面上確實可見紅、藍兩個色塊左右並排，沒有整片異常色彩或渲染失敗的跡象（若截圖本身就異常，代表測試素材或 harness 有問題，需排查後重新截圖，不進入 Step 5 的量測）。

- [ ] **Step 5：像素量測分析（本機，Python + Pillow）**

```python
# measure_fr41_gap.py
# 讀入 fr41_screenshot.png，沿螢幕水平中線採樣像素，找出紅色頁尾與藍色
# 頁首的交界，驗證轉換是否「銳利」（無明顯非紅非藍的間隙色帶），作為
# FR-41「頁間不留空白」的量化證據。驗證後即刪除，不納入版本控制。
from PIL import Image

img = Image.open("fr41_screenshot.png").convert("RGB")
width, height = img.size
y = height // 2


def classify(pixel):
    r, g, b = pixel
    # 相對主導比例判定（而非絕對數值閾值），對截圖亮度/色彩偏移（例如
    # 護眼模式、色彩校正）更穩健：只要求該色通道明顯壓過其餘兩個通道，
    # 不要求達到某個絕對亮度數值。
    if r > 80 and r > g * 2 and r > b * 2:
        return "RED"
    if b > 80 and b > r * 2 and b > g * 2:
        return "BLUE"
    return "OTHER"


row = [classify(img.getpixel((x, y))) for x in range(width)]
red_positions = [i for i, c in enumerate(row) if c == "RED"]
blue_positions = [i for i, c in enumerate(row) if c == "BLUE"]

if not red_positions or not blue_positions:
    print(f"FAIL: 未偵測到紅色或藍色像素（width={width}），截圖可能有誤，"
          "需人工檢視 fr41_screenshot.png")
else:
    red_end = red_positions[-1]
    blue_start = blue_positions[0]
    gap_px = blue_start - red_end - 1
    print(f"width={width} red_end={red_end} blue_start={blue_start} "
          f"gap_px={gap_px}")
    print("PASS: 間隙 <= 3px（螢幕採樣/反鋸齒誤差範圍內）" if gap_px <= 3
          else "FAIL: 間隙 > 3px，可能存在真實可見留白")
```

Run: `python measure_fr41_gap.py`
Expected: 輸出 `gap_px` 數值與 PASS/FAIL 判讀。把完整輸出記錄下來，供 Step 6 寫入 QA 報告。

- [ ] **Step 6：撰寫 QA 報告，記錄 PDF 與 EPUB FXL 兩路線結論**

新建 `docs/epics/epic-16-dual-page/reviews/qa-issue-7-report.md`，內容至少包含：

```markdown
# Epic 16 Issue 7 — 真機驗證與收尾 QA 報告

## FR-41「頁間不留空白」核心驗收確認

### PDF 路線（本 issue 首次量化驗證）
- 測試素材：2 頁雙色測試 PDF（第 0 頁純紅 RGB(255,0,0)、第 1 頁純藍
  RGB(0,0,255)），`dualPageMode=always`／`dualPageCoverAlone=false`／
  `fitMode=pageFit`，橫向。
- 量測方式：`adb screencap` 截圖 + 沿螢幕水平中線像素採樣，量測紅色頁尾
  與藍色頁首的交界間隙（`measure_fr41_gap.py`）。
- 結果：<依 Step 5 實際輸出的 gap_px 數值與 PASS/FAIL 填入>
- 結論：<PASS：拼接處無可見間隙，FR-41 於 PDF 路線通過 / FAIL：偵測到
  約 N px 的間隙，需另立後續 issue 追蹤>

### EPUB FXL 路線（引用 Issue 6 既有結論，不重複執行）
- 依 `issues.md` Issue 6「真機視覺驗收（2026-07-14）」：`applyFxlFitScale()`
  的 `translationX` 重複疊加 bug 修正後，人類於真機以真實漫畫素材重新
  驗證，「封面頁正常顯示、翻頁至內頁後左右兩頁正常顯示且無縫並排，
  FR-41 核心驗收點通過」。
- 結論：PASS（沿用 Issue 6 結論，本 issue 不重複執行）。
```

- [ ] **Step 7：清理暫時性檔案**

```bash
rm app/lib/dev_fr41_pdf_harness.dart
adb -s <device-id> shell rm /sdcard/Android/data/cc.ugotit.elinkbook/files/fr41_gap_test.pdf
rm fr41_gap_test.pdf fr41_screenshot.png generate_fr41_gap_test_pdf.py measure_fr41_gap.py
```

Run: `cd U:\MyDeveloper\AI\elinkBook && git status --short`
Expected：確認 `app/lib/dev_fr41_pdf_harness.dart` 不再出現於輸出中；`docs/epics/epic-16-dual-page/reviews/qa-issue-7-report.md` 為唯一新增的未追蹤檔案。

- [ ] **Step 8：Commit**

```bash
git add docs/epics/epic-16-dual-page/reviews/qa-issue-7-report.md
git commit -m "docs(epic-16): Issue 7 FR-41 核心驗收確認（PDF 像素量測 + EPUB FXL 引用 Issue 6 結論）"
```

---

### Task 3：裝置旋轉行為確認——PDF／EPUB 兩條 `PlatformView` 皆不因旋轉重建

**Files:**
- Modify（暫時性插樁，驗證後還原）：`app/android/app/src/main/kotlin/cc/ugotit/elinkbook/PdfReaderView.kt`、`app/android/app/src/main/kotlin/cc/ugotit/elinkbook/EpubReaderView.kt`
- Create（暫時性、不納入版本控制）：`app/lib/dev_rotation_pdf_harness.dart`、`app/lib/dev_rotation_epub_harness.dart`
- Modify: `docs/epics/epic-16-dual-page/reviews/qa-issue-7-report.md`（補上本 Task 結果段落）

**Interfaces:**
- Consumes：`ReaderScreen(filePath, bookId, prefsManager)` 既有公開建構參數。
- Produces：QA 報告內的裝置旋轉確認結論段落。

`spec.md`「方向偵測契約」第 4 點要求「本 epic 實作時須以真機旋轉驗證兩個 View 皆不重建（沒有黑屏或重新 `openBook`）」，但目前只有 `pdf_dual_page_test.dart` 的旋轉測試明確註記「PlatformView 是否因旋轉重建屬 Issue 7 的真機視覺驗證範圍，本測試只驗證 preferences 傳遞路徑不出錯」——真正的重建驗證從未在真機上執行過。本任務用暫時性 `Log.d` 插樁在 `openBook()` 起始處留下標記，若旋轉後標記重新出現，代表原生端確實重新開書（重建），這是比「肉眼看有沒有黑屏閃爍」更可靠的證據。

- [ ] **Step 1：加入暫時性插樁——`PdfReaderView.kt`**

找到 `app/android/app/src/main/kotlin/cc/ugotit/elinkbook/PdfReaderView.kt:417`：

```kotlin
    private fun openBook(path: String?, initialPreferences: Map<String, Any?>?) {
        if (path == null) {
```

改為：

```kotlin
    private fun openBook(path: String?, initialPreferences: Map<String, Any?>?) {
        android.util.Log.d("Q7-ROTATE-CHECK", "PdfReaderView.openBook() called") // 暫時性插樁，驗證後移除
        if (path == null) {
```

- [ ] **Step 2：加入暫時性插樁——`EpubReaderView.kt`**

找到 `app/android/app/src/main/kotlin/cc/ugotit/elinkbook/EpubReaderView.kt:591`：

```kotlin
    private fun openBook(path: String?, initialPreferences: Map<String, Any?>?) {
        if (path == null) {
```

改為：

```kotlin
    private fun openBook(path: String?, initialPreferences: Map<String, Any?>?) {
        android.util.Log.d("Q7-ROTATE-CHECK", "EpubReaderView.openBook() called") // 暫時性插樁，驗證後移除
        if (path == null) {
```

- [ ] **Step 3：編譯確認**

```bash
cd app/android
./gradlew :app:compileDebugKotlin
```

Expected: `BUILD SUCCESSFUL`。

- [ ] **Step 4：建立暫時性 `flutter run` 除錯進入點——PDF**

在 `app/lib/` 新建（**暫時性、驗證後刪除、不納入版本控制**）：

```dart
// app/lib/dev_rotation_pdf_harness.dart
// 暫時性 flutter run 除錯進入點，僅供 Issue 7 Task 3 PDF 路線裝置旋轉
// 不重建驗證使用，驗證後刪除，不納入版本控制。使用獨立暫存資料庫路徑，
// 避免污染真實 App 的圖書庫資料。
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';

import 'library/sqlite_library_repository.dart';
import 'reader/book_reader_prefs_repository.dart';
import 'reader/reader_prefs_manager_impl.dart';
import 'screens/reader_screen.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final tempDir = await getTemporaryDirectory();
  final repository =
      await SqliteLibraryRepository.open('${tempDir.path}/dev_rotation.db');
  final prefsManager =
      ReaderPrefsManagerImpl(BookReaderPrefsRepository(repository.database));
  runApp(MaterialApp(
    home: ReaderScreen(
      filePath:
          '/sdcard/Android/data/cc.ugotit.elinkbook/files/fr41_gap_test.pdf',
      bookId: 'dev_rotation_pdf',
      prefsManager: prefsManager,
    ),
  ));
}
```

（本 harness 沿用 Task 2 推送到裝置的 `fr41_gap_test.pdf`，若該檔案已於 Task 2 Step 7 清理，需重新執行 Task 2 Step 1-2 產生並推送一次；或改用任意已在裝置上的 PDF 路徑亦可，本測試不關心內容，只關心 `openBook()` 呼叫次數。）

- [ ] **Step 5：建立暫時性 `flutter run` 除錯進入點——EPUB**

在 `app/lib/` 新建（**暫時性、驗證後刪除、不納入版本控制**）：

```dart
// app/lib/dev_rotation_epub_harness.dart
// 暫時性 flutter run 除錯進入點，僅供 Issue 7 Task 3 EPUB FXL 路線裝置
// 旋轉不重建驗證使用，驗證後刪除，不納入版本控制。
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';

import 'library/sqlite_library_repository.dart';
import 'reader/book_reader_prefs_repository.dart';
import 'reader/reader_prefs_manager_impl.dart';
import 'screens/reader_screen.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final tempDir = await getTemporaryDirectory();
  final repository = await SqliteLibraryRepository.open(
      '${tempDir.path}/dev_rotation_epub.db');
  final prefsManager =
      ReaderPrefsManagerImpl(BookReaderPrefsRepository(repository.database));
  runApp(MaterialApp(
    home: ReaderScreen(
      filePath:
          '/sdcard/Android/data/cc.ugotit.elinkbook/files/dev_rotation.epub',
      bookId: 'dev_rotation_epub',
      prefsManager: prefsManager,
    ),
  ));
}
```

推送既有的固定版面測試 fixture 至裝置（內容不重要，只需要是合法 FXL EPUB）：

```bash
adb -s <device-id> push app/test/fixtures/sample_fixed_layout.epub /sdcard/Android/data/cc.ugotit.elinkbook/files/dev_rotation.epub
```

- [ ] **Step 6：執行並旋轉裝置，觀察 logcat——PDF**

```bash
adb -s <device-id> logcat -c   # 清空既有 log
cd app
flutter run -t lib/dev_rotation_pdf_harness.dart -d <device-id>
```

待畫面顯示 PDF 內容後（不要中斷 `flutter run` 程序），另開一個終端機視窗執行：

```bash
adb -s <device-id> logcat -d | grep "Q7-ROTATE-CHECK"
```

Expected：此時應恰好看到 **1 筆** `PdfReaderView.openBook() called`（首次開書）。記錄這筆時間戳。

接著手動旋轉裝置（實體翻轉，或 `adb -s <device-id> shell settings put system accelerometer_rotation 0 && adb -s <device-id> shell settings put system user_rotation 1` 切換為橫向，稍候後再切回 `user_rotation 0` 恢復直向），每次旋轉後間隔至少 2 秒再重新執行：

```bash
adb -s <device-id> logcat -d | grep "Q7-ROTATE-CHECK"
```

Expected：旋轉前後 `Q7-ROTATE-CHECK` 的筆數應維持在 **1 筆**（不應因旋轉而新增）。若筆數增加，代表 `PdfReaderView` 確實因旋轉被重建，這是需要記錄的真實缺陷。

同時用肉眼觀察畫面本身：旋轉瞬間是否有明顯黑屏閃爍，記錄觀察結果。

回到 `flutter run` 終端機按 `q` 結束程序。

- [ ] **Step 7：執行並旋轉裝置，觀察 logcat——EPUB**

重複 Step 6 的流程，改用：

```bash
adb -s <device-id> logcat -c
cd app
flutter run -t lib/dev_rotation_epub_harness.dart -d <device-id>
```

Expected：同樣應維持 **1 筆** `EpubReaderView.openBook() called`，旋轉前後不新增。

- [ ] **Step 8：還原暫時性插樁**

把 Step 1、Step 2 新增的兩行 `android.util.Log.d(...)` 註解刪除，確認 `PdfReaderView.kt`／`EpubReaderView.kt` 回到插樁前的原始內容。

Run: `git diff app/android/app/src/main/kotlin/cc/ugotit/elinkbook/PdfReaderView.kt app/android/app/src/main/kotlin/cc/ugotit/elinkbook/EpubReaderView.kt`
Expected：無任何差異輸出（完全還原）。

- [ ] **Step 9：清理暫時性檔案**

```bash
rm app/lib/dev_rotation_pdf_harness.dart app/lib/dev_rotation_epub_harness.dart
adb -s <device-id> shell rm /sdcard/Android/data/cc.ugotit.elinkbook/files/dev_rotation.epub
```

Run: `cd U:\MyDeveloper\AI\elinkBook && git status --short`
Expected：`app/lib/dev_rotation_pdf_harness.dart`／`dev_rotation_epub_harness.dart` 不再出現；`PdfReaderView.kt`／`EpubReaderView.kt` 不再顯示為已修改。

- [ ] **Step 10：把結果補進 QA 報告**

在 `docs/epics/epic-16-dual-page/reviews/qa-issue-7-report.md` 新增一段：

```markdown
## 裝置旋轉行為確認（PlatformView 是否因旋轉重建）

- 驗證方式：於 `openBook()` 起始處加入暫時性 `Log.d` 插樁，清空 logcat
  後開書、旋轉裝置多次，比對插樁筆數是否維持為 1（驗證後已還原插樁，
  見 `plans/plan-issue-7.md` Task 3）。
- PDF 路線：<依 Step 6 實際觀察填入：openBook 筆數是否維持 1、有無黑屏>
- EPUB FXL 路線：<依 Step 7 實際觀察填入>
- 結論：<PASS：兩條 PlatformView 皆不因旋轉重建，符合 spec.md「方向偵測
  契約」第 4 點 / FAIL：發現重建情形，已另立 issue-<N> 追蹤>
```

- [ ] **Step 11：`flutter analyze` 與完整測試套件最終確認**

Run: `cd app && flutter analyze`
Expected: `No issues found!`

Run: `cd app && flutter test`
Expected: 全數 PASS。

- [ ] **Step 12：Commit**

```bash
git add docs/epics/epic-16-dual-page/reviews/qa-issue-7-report.md
git commit -m "docs(epic-16): Issue 7 裝置旋轉行為確認（PDF/EPUB PlatformView 皆不因旋轉重建）"
```

（本次 commit 不應包含任何 `app/android/`／`app/lib/dev_*.dart` 的變更——Step 8-9 已確認插樁與暫時性檔案皆已清理乾淨。）

---

### Task 4：彙整全 Epic 驗收狀態，更新 `issues.md`／`docs/epics.md`

**Files:**
- Modify: `docs/epics/epic-16-dual-page/issues.md`（Issue 7 區塊）
- Modify: `docs/epics.md`

**Interfaces:**
- Consumes：Task 1-3 的產出（測試結果、QA 報告）
- Produces：無

- [ ] **Step 1：更新 `docs/epics/epic-16-dual-page/issues.md`——Issue 7 標題與完成說明**

把 Issue 7 的 `**Status:**`（現為 `ready-for-agent`）改為完成狀態，比照 Issue 3-6、Issue 9 既有的完成說明風格，內容需涵蓋：
- Task 1 的 8 欄位組合持久化測試結果（測試名稱、PASS/FAIL）
- Task 2 的 FR-41 兩路線結論（PDF 路線的 `gap_px` 量測數字與判讀、EPUB FXL 路線引用 Issue 6 結論）
- Task 3 的裝置旋轉確認結論（PDF／EPUB 是否皆不重建）
- 若本 issue 過程中發現任何新問題，需註明已建立哪個後續 issue 追蹤（若無發現，明確寫「無」，不要含糊帶過）
- 引用 QA 報告路徑 `reviews/qa-issue-7-report.md` 供後續追溯

- [ ] **Step 2：更新 `docs/epics.md`——Epic 16 狀態列**

在 `docs/epics.md` 的 `epic-16-dual-page` 那一列備註最後，新增一句總結 Issue 7 收尾的結論（FR-41 兩路線確認結果、裝置旋轉確認結果），並註明：**Epic 16 全部 9 個 Issue（Issue 1-9）皆已完成**。狀態燈號本身維持 `🟡 開發中 (Active)`，**不要自行改成 `🟢 已歸檔 (Archived)`**——依 Global Constraints，歸檔動作需要人類明確指定，本步驟只負責把狀態列更新到「所有 Issue 皆已完成，可供人類決定何時歸檔」的乾淨狀態。

- [ ] **Step 3：`flutter analyze` 與完整測試套件最終確認**

Run: `cd app && flutter analyze`
Expected: `No issues found!`

Run: `cd app && flutter test`
Expected: 全數 PASS。

- [ ] **Step 4：Commit**

```bash
git add docs/epics/epic-16-dual-page/issues.md docs/epics.md
git commit -m "docs(epic-16): Issue 7 彙整驗收狀態，Epic 16 Issue 1-9 全數完成"
```

---

## Self-Review（撰寫計劃時的自我檢查）

**Spec 覆蓋度**：`issues.md` Issue 7「描述」列出的 5 個項目逐一對應：Task 1（端到端組合持久化）、Task 2（FR-41 兩路線確認）、Task 3（裝置旋轉行為確認）、Task 4（彙整驗證紀錄並更新 `issues.md`／`docs/epics.md`）；「若發現落差另立 issue」屬於執行時依實際結果決定的動作，已在 Global Constraints 與 Task 4 Step 1 中明確要求記錄，非本計劃遺漏。

**占位符掃描**：全文無 TBD/待補字樣；Task 2 Step 6、Task 3 Step 10、Task 4 Step 1-2 要求「依實際結果填入」，這是驗收/文件步驟本質使然（真機量測與旋轉觀察結果需要實際執行才能得知，比照 `epic-4-pdf-enhance` Issue 7 計劃 Self-Review 對同類段落的既有認定），不是遺漏程式碼——所有涉及程式碼/腳本的步驟皆已提供完整可執行內容。

**型別一致性**：`PdfReaderView` 8 個欄位（`dualPageMode`／`dualPageCoverAlone`／`dualPageDirection`／`fitMode`／`contrast`／`brightness`／`boldStrength`／`cropMode`／`cropRect`，共 9 個含 `cropRect`）在 Task 1 的 `beforeClose`／`saved`／`afterReopen` 三段斷言中欄位名稱與既有兩個測試（第 1219、1335 行）逐字一致；`PdfSettingsSheet` 的 Key 命名（`pdf_settings_dual_page_mode_always`／`_cover_alone`／`_direction_ltr`／`_fit_mode_fit_width`／`_tab_filters`／`_contrast_increment`／`_brightness_increment`／`_bold_strength_increment`／`_tab_crop`／`_crop_mode_auto`／`_tab_display`）皆已對照 `app/lib/screens/pdf_settings_sheet.dart` 現行原始碼逐一核對存在。Task 3 的插樁位置（`PdfReaderView.kt:417`／`EpubReaderView.kt:591`）與周邊程式碼皆已實際讀取確認。

## 審查修正紀錄（`tmp/epic-16/reviews/plan-issue-7-review.md`）

- **Important（確認屬實，已修正）**：Task 2 的 `generate_fr41_gap_test_pdf.py`／`measure_fr41_gap.py` 依賴 `fpdf2`／`Pillow`，計劃原先未提供安裝指令。已於 Task 2 新增 Step 0：`pip install fpdf2 pillow`。
- **Important（確認屬實，已修正）**：Task 2 Step 5 量測腳本的 `classify()` 原用絕對數值閾值（`r > 180` 等），在螢幕亮度/色彩偏移（護眼模式、色彩校正）情境下可能誤判。已改為相對主導比例判定（`r > 80 and r > g * 2 and r > b * 2`），對截圖亮度偏移更穩健，且經驗算確認不會誤傷正確分類（純紅/純藍正確判定，灰階間隙像素正確排除為 OTHER）。
- **Important（部分採納）**：審查指出 Windows 環境下 `grep`／`rm` 在原生 PowerShell/`cmd.exe` 不可用。查證後，本 Epic 既有全部計劃（Issue 1/3/5/6/8/9）與本次會談實際執行紀錄皆一致假設 Git Bash（POSIX）為執行環境，`grep`／`rm`／管線組合在此環境下皆可正常運作，非本計劃獨有的不相容之處；審查建議「逐一改寫每條指令為多平台版本」與此既有慣例不一致、也會為一次性驗證任務增加不成比例的維護負擔，故不逐條改寫。改為在 Global Constraints 新增一行明確聲明 Shell 假設，並列出 PowerShell／`cmd.exe` 對應指令供不使用 Git Bash 的執行者參考，兼顧審查提出的可攜性疑慮與既有慣例一致性。
- **Minor（不採納）**：審查建議 Task 1 對 `saved.pdfCropRect` 額外加上 `isA<Rect>()` 檢查。查證後，本欄位型別為 `PdfCropRect?`（非 `Rect`，審查意見的型別名稱與本 codebase 不符），Dart 靜態型別系統已在編譯期保證 `saved.pdfCropRect` 的型別，執行期 `isA<>()` 檢查相對於既有 `isNotNull` 不提供額外資訊；更深入的矩形數值正確性驗證屬於 Issue 5 既有測試（智慧自動裁切演算法）的職責範圍，本任務是欄位持久化組合測試，不重複驗證演算法正確性，且與本次合併的兩個既有測試的既有斷言風格一致。不採納。

## Execution Handoff

Plan complete and saved to `docs/epics/epic-16-dual-page/plans/plan-issue-7.md`。兩種執行方式：

1. **Subagent-Driven（推薦）**——每個 Task 交給一個全新 subagent 執行，Task 之間逐一審查，快速迭代。
2. **Inline Execution**——在本次會談中依 Task 順序批次執行，設檢查點逐一確認。

要採用哪一種方式？
