# Epic 6 Issue 3：PDF 劃線與備註 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 為 PDF 新增劃線（螢光筆黃/粉/藍、底線）與備註（可獨立於劃線存在）功能：長按頁面直接觸發拖曳框選矩形手勢（ADR 0008，不需先進入獨立模式）、劃線/備註疊加渲染於 PDF 頁面 Bitmap 之上、`refreshAnnotations()` method channel 讓原生端於資料變動後重繪，並讓 Issue 2 已建立的 `NotesBottomSheet`「✏️ 劃線與備註」分頁對 PDF 書籍也完整可用（完全複用其清單/合併顯示/批次刪除邏輯，不另外開發）。

**Architecture:** 複用 Issue 2 建立的 `highlights`／`notes` 表與 `HighlightsRepository`／`NotesRepository`，新增 PDF 專屬欄位（`pdf_page_index`／`pdf_rect_json`）並讓排序邏輯改用 `COALESCE(pdf_page_index, progression)`（比照 `bookmarks` 表既有先例）。長按拖曳框選的手勢辨識由 `PdfReaderView.dart` 既有的 `GestureDetector`（與水平滑動翻頁 `onHorizontalDragEnd` 同一個元件）以內建的 `onLongPressStart`／`onLongPressMoveUpdate`／`onLongPressEnd` 主導，由 Flutter 手勢競技場裁決長按 vs 滑動，原生端不再自行監聽觸控（審查修正，見 `tmp/epic-6/reviews/plan_issue_3_review.md` 1.1：原設計讓原生端在 `rootView` 上無條件攔截 `ACTION_DOWN`，會讓 Flutter 端既有翻頁手勢完全收不到事件）；Dart 端把觸點換算成相對 widget 自身尺寸的百分比，透過 `beginAnnotationSelection`／`updateAnnotationSelection`／`endAnnotationSelection` 三個新增 method call 通知原生端，另以 `Listener` 追蹤觸點數、多指觸碰時呼叫 `cancelAnnotationSelection`。`PdfReaderView.kt` 收到後：(a) 建立/更新一個新的 `HighlightSelectionOverlayView`（沿用/延伸 `CropOverlayView.kt` 的 FIT_CENTER letterbox 座標數學，抽出共用函式）即時繪製框選矩形，結束時把「相對目前顯示中 bitmap 內容範圍」的百分比矩形＋頁碼透過 `onSelectionRectComputed` 回報 Dart 端；(b) 新增 `refreshAnnotations` method channel 指令，Dart 端送入目前應顯示的完整標記清單（比照 EPUB `setDecorations` 整組送出慣例），原生端快取後於 `renderPageBitmap()` 內按頁碼疊加繪製（螢光筆/底線填色、純備註加繪手繪向量圖釘——E-Ink 對比度考量，見審查修正 2.2），天然支援雙頁/裁切/旋轉後的重繪（因為是在單頁 bitmap 產生當下疊加，不依賴 View 尺寸）。`PdfReaderView.dart` 新增對稱的 Dart 端 method channel 契約與 `refreshAnnotations` 靜態方法。`ReaderScreen` 整合：載入既有標記、顯示/隱藏浮動工具列（複用 Issue 2 的 `AnnotationToolbar`）、CRUD 呼叫、把 `_openNotesSheet` 對 PDF 開放。

**Tech Stack:** Flutter/Dart、`sqflite`、`sqflite_common_ffi`（測試）、Kotlin（`android.graphics.pdf.PdfRenderer`，不涉及 Readium）、JVM 單元測試（`org.junit`，`./gradlew testDebugUnitTest`，於 `app/android` 目錄執行）。

## Global Constraints

- 所有程式註解、文件、commit message 皆使用正體中文（zh-TW）。
- `ReaderScreen` 是本專案唯一的閱讀器 seam（`CLAUDE.md`），本 Issue 不新增第二個閱讀器入口。
- **SQLite schema migration**：目前資料庫 `version` 為 9（Issue 2 已建立 `highlights`／`notes` 表，僅含 EPUB 欄位），本 Issue 提升至 10，新增 `pdf_page_index INTEGER`／`pdf_rect_json TEXT` 兩個欄位到這兩張表。**onCreate／onUpgrade 分歧路徑（重要，避免 duplicate column 例外）**：`_createHighlightsTable`／`_createNotesTable`（全新安裝走的路徑）直接把這兩個新欄位內嵌進 `CREATE TABLE` 語句本身（一步到位，比照 `_createBookReaderPrefsTable` 已包含所有版本新增欄位的既有先例）；既有 v9 裝置（`highlights`/`notes` 表已存在但無 PDF 欄位）則需要一個新的 `_addPdfAnnotationColumns(db)` 用 `ALTER TABLE ADD COLUMN` 補上。這兩條路徑必須是 **if/else 互斥**（比照 `book_reader_prefs` 表 `if (oldVersion < 2) { 建表 } else { ALTER TABLE 系列 }` 的既有慣例），**不可**寫成兩個獨立的 `if (oldVersion < 9)`／`if (oldVersion < 10)`——否則 `oldVersion == 8`（跳級升級、`highlights`/`notes` 表本身也還不存在）的裝置會先在 `oldVersion < 9` 分支建立「已含 PDF 欄位」的最終版表，緊接著又落入 `oldVersion < 10` 分支對同一張表 `ALTER TABLE ADD COLUMN` 已存在的欄位，SQLite 會拋出 `duplicate column name` 例外。
- **長按/拖曳的手勢辨識改由 Flutter 端 `GestureDetector` 主導，原生端不再自行監聽 `rootView` 觸控（審查修正，見 `tmp/epic-6/reviews/plan_issue_3_review.md` 1.1，取代原本「原生端自建 Handler+ViewConfiguration 長按計時、`rootView.setOnTouchListener` 無條件回傳 `true` 攔截整個觸控序列」的設計）**：原設計會讓原生端在使用者每一次觸碰螢幕的 `ACTION_DOWN` 當下就無條件宣告「這次觸控歸我」，而 Android 的觸控分派契約規定——`OnTouchListener` 一旦在 `ACTION_DOWN` 回傳 `true`，同一觸控序列後續的 `ACTION_MOVE`/`ACTION_UP` 便只會送達該 View、不會再進入 Flutter 的手勢競技場，導致既有的水平滑動翻頁手勢（`PdfReaderView.dart` 的 `GestureDetector.onHorizontalDragEnd`）在一般閱讀情境下完全失效，且此問題並非僅在真機測試中才會顯現的機率性風險，而是每次觸碰都會發生的必然行為。反過來若改成「長按觸發前回傳 `false`，觸發後才回傳 `true`」也不可行——Android 的規則是「View 若在 `ACTION_DOWN` 當下未取得該序列（回傳 `false`），之後同一序列的事件不會再補送給它」，`rootView` 一旦在 `ACTION_DOWN` 選擇放行，就永遠不會再收到那次觸控接下來的 `ACTION_MOVE`/`ACTION_UP`，長按計時器即使之後真的觸發，也已經沒有後續事件可以用來追蹤拖曳或完成框選。**改採的正確架構**：長按與拖曳的辨識完全交給 `PdfReaderView.dart` 既有的 `GestureDetector`（與 `onHorizontalDragEnd` 同一個元件）新增的 `onLongPressStart`／`onLongPressMoveUpdate`／`onLongPressEnd` 三個內建回呼——這是 Flutter 手勢框架本來就設計用來裁決「同一觸點究竟是長按還是拖曳」的機制，由它在 Dart 層仲裁，原生端完全不需要猜測、也不需要佔用 `rootView` 的觸控序列。三個回呼各自把觸點位置換算成**相對 `PdfReaderView` 這個 widget 自身尺寸**（非 bitmap 內容範圍，見下方座標協定說明兩段式換算）的百分比（`xPct`/`yPct`，透過 `LayoutBuilder` 取得目前 `constraints.biggest`），分別呼叫 `beginAnnotationSelection`／`updateAnnotationSelection`／`endAnnotationSelection` 這三個新增的 outgoing method call 通知原生端；原生端收到後才建立/更新/結束疊加層，不再自行判斷「是否為長按」。
- **PDF 座標協定為兩段式換算（審查修正後定案）**：(1) Dart 端把觸點位置換算成相對 `PdfReaderView` widget 自身尺寸的百分比（`xPct`/`yPct`，與裝置像素密度無關，因為分子分母同單位相除）送給原生端；(2) 原生端收到後先乘上 `rootView` 目前量測到的寬高換算回 View 像素座標，再透過沿用/延伸 `CropOverlayView.kt` 既有的 FIT_CENTER letterbox 數學（`computeContentBounds()`，本計劃抽出為共用函式 `computeFitCenterContentBounds()`，以 `imageView.drawable` 的 intrinsic 尺寸——已反映目前生效的裁切狀態，若有——為基準）換算出「相對目前顯示中 bitmap 內容範圍」（而非整個原生 View 容器寬高）的最終百分比矩形（`left`/`top`/`right`/`bottom`，0.0–1.0），這組最終座標才是透過 `onSelectionRectComputed` 回報給 Dart 端、寫入資料庫的值。letterbox 換算必須留在原生端，因為只有原生端知道 bitmap 的實際像素尺寸；Dart 端不需要、也沒有管道取得這項資訊。**渲染回貼時直接以「最終百分比 × bitmap 自身寬高」換算像素座標**（不再重算 letterbox——因為 bitmap 本身沒有內部留白，留白只發生在 `ImageView` 用 `FIT_CENTER` 顯示 bitmap 到 View 的階段，`ImageView` 本身的縮放/置中會自動、成比例地把疊加內容一併帶到正確視覺位置），這也是本設計天然正確處理裝置旋轉／雙頁模式／已裁切頁面的關鍵——見下方「長按框選僅支援 PAGE_FIT」與「疊加繪製位置」。
- **長按框選僅支援 `fitMode == PAGE_FIT` 且雙頁模式未生效（本計劃書自行定案的範圍簡化，issues.md 驗收標準未要求涵蓋 `FIT_WIDTH`/`ACTUAL_SIZE`/雙頁情境，YAGNI）**：`FIT_WIDTH`/`ACTUAL_SIZE` 用 `Matrix` 縮放（非 `FIT_CENTER`），letterbox 數學不適用；雙頁模式下一次觸控可能落在拼接後的左頁或右頁、需要額外判斷觸點屬於哪一頁再換算，複雜度顯著提高且無明確驗收標準要求。此守衛收斂在原生端 `beginAnnotationSelection` 的 handler 內（`if (cropEditModeActive || fitMode != PdfFitMode.PAGE_FIT || dualPageEnabled) return` 靜默忽略，比照既有 `cropEditModeActive` 守衛風格）——Dart 端不重複判斷這些條件（避免與原生端狀態不同步），一律無條件送出三個手勢事件，由原生端這個唯一的權威來源決定是否真的生效。日後有需要時可再擴充，非本 Issue 範圍。
- **疊加繪製位置**：標記疊加繪製發生在 `renderPageBitmap(pageIndex)` 產生「單一頁面」的原始內容 bitmap 之後、回傳之前，逐頁繪製（單頁與雙頁模式皆呼叫此函式各自渲染每一頁）。這保證：(a) 雙頁模式下左右頁各自正確疊加（不需要處理拼接後座標）；(b) 旋轉/版面調整觸發的重新渲染會自動重算並重繪（因為整個 pipeline 本來就會重跑 `renderPageBitmap`），不需要額外的旋轉感知邏輯；(c) 已知限制：若使用者在「建立劃線之後」才變更裁切模式/裁切矩形，該筆劃線的百分比座標仍以建立當下的裁切狀態為準，可能與新裁切結果不再對齐——此為已知、可接受的範圍簡化（比照本專案既有先例，例如 EPUB 直排/橫排切換的劃線視覺一致性亦非像素級保證，見 spec.md Out of Scope），非本 Issue 修正範圍。
- **底線/純備註疊加樣式須依實際渲染尺寸縮放，不可用裝置 DP 密度（審查修正，見 review 2.1）**：`renderPageBitmap()` 產生的 bitmap 尺寸是頁面點數乘上 `PdfImageProcessor.pageRenderScale(density)` 決定的渲染縮放係數（常遠大於螢幕 DP），底線的 `strokeWidth` 與純備註釘標圖示的尺寸必須以這個 `scale` 為基準（例如 `2f * scale`），不可沿用畫面 DP 密度（`1f * density` 之類），否則在實際渲染出的高解析度 bitmap 上會顯得極細/極小。底線繪製點須為 `bottom - strokeWidth / 2`（而非直接畫在 `bottom` 上）——`Canvas.drawLine` 的筆畫以座標為中線向兩側延伸，若選取範圍恰好貼近頁面底部（`bottom` 接近 `bitmap.height`），畫在 `bottom` 上會有一半線寬被畫布邊界裁掉。
- **純備註畫面指示改用手繪向量圖釘，不使用系統 Emoji（審查修正，見 review 2.2）**：`design.md` 決策 #2 要求 PDF 純備註右上角疊加圖示釘標；系統 Emoji（例如 📌）透過 `Canvas.drawText` 繪製後，在 elinkBook 的核心場景之一——E-Ink 黑白螢幕——上會因失去色彩/漸層細節而模糊、對比度不足。比照本專案既有先例——`CropOverlayView.kt` 的裁切確認按鈕同樣是刻意手繪的黑底白勾（非圖示字型），其 KDoc 明確記載理由是「確保在 E-Ink 16 階灰階裝置...與一般彩色螢幕上都維持清楚可辨的對比度」——純備註釘標比照改為純黑白、高對比度的簡易向量圖釘（圓形釘頭＋三角釘尖，`Canvas.drawCircle`/`drawPath` 組成），不使用 `drawText` 畫 Emoji。
- **框選中縮放/平移直接取消（design.md 決策 #15、spec.md 審查修正 1.3）**：既然原生端不再持有整個觸控序列（見上方手勢辨識改由 Dart 主導），多指偵測改由 Dart 端負責——`PdfReaderView.dart` 用 `Listener(onPointerDown/onPointerUp/onPointerCancel)` 追蹤目前螢幕上的觸點數，偵測到第二指觸碰時呼叫新增的 `cancelAnnotationSelection` outgoing method call；原生端收到後（或收到 `nextPage`／`previousPage`／`jumpToPage` 指令時，邏輯不變）立即清除目前框選狀態（移除疊加層）並透過 `onSelectionCanceled` 通知 Dart 端收起浮動工具列，不嘗試重算矩形座標。
- **PDF 端不新增原生「點擊既有標記」互動（範圍界定，issues.md Issue 3「What to build」與驗收標準皆未提及此項，design.md 使用者流程步驟 3 的「點擊既有劃線/備註」在 PDF 端改為完全透過 Bottom Sheet 清單達成）**：使用者編輯/刪除既有 PDF 劃線/備註一律透過「✏️ 劃線與備註」分頁的清單項目操作（完整複用 Issue 2 邏輯，見 `notes_bottom_sheet.dart` 現況），原生端不需要偵測「點擊已疊加的標記矩形」並回報 Dart 端。
- **PDF 標記的原生端 wire 格式不含 id**（與 EPUB `EpubDecoration.toWire()` 的差異）：因為上一條「不新增點擊互動」的範圍界定，原生端永遠不需要把某個標記的 id 回報給 Dart 端，故 `refreshAnnotations` 的 wire 格式只需要 `pageIndex`/`left`/`top`/`right`/`bottom`/`tint`/`isUnderline`/`isNoteOnly`，不含 `id` 欄位。
- **色彩決策沿用 Issue 2 既有慣例**：三種螢光筆固定色票＋純備註灰色沿用 `highlight_style.dart` 既有常數；底線色沿用目前主題 `primary` 色，換算方式沿用既有 `highlightStyleTint()`／`Color.toARGB32()`。
- **`PercentRect` 複用**（Issue 2 `plan-issue-2.md` 已預留：「Issue 3...預期會有結構相同的座標傳遞需求，屆時可直接複用本類別」）：本 Issue 為其新增 `toJson()`/`fromJson()`（比照既有 `PdfCropRect` 的 JSON 序列化慣例）供資料庫持久化使用，不重新宣告一組同義欄位。
- **PDF 選字工具列複用 Issue 2 的 `AnnotationToolbar`**（design.md 明訂 EPUB／PDF 共用同一組 Widget，Issue 2 Task 6 KDoc 已預告）：不新增第二個工具列 Widget。
- **`NotesBottomSheet` 不需修改**：其「✏️ 劃線與備註」分頁已是格式無關的通用實作（依賴注入的 `highlightsRepository`／`notesRepository`／`onAnnotationSelected`／`onAnnotationsChanged`），本 Issue 只需要 `ReaderScreen._openNotesSheet` 對 PDF 也傳入這些依賴（Issue 2 Task 10 Step 10 已預留的擴充點：「PDF 支援留待 Issue 3 把這個條件式擴充為 `|| format == BookFormat.pdf`」）。
- **Kotlin JVM 單元測試指令慣例**：`./gradlew testDebugUnitTest --tests "cc.ugotit.elinkbook.<ClassName>"`（於 `app/android` 目錄執行，`gradlew`/`gradlew.bat` 為 `.gitignore` 排除產物，若尚不存在先於 `app/` 目錄執行一次 `flutter build apk --debug` 讓 Flutter 產生）。
- **兩層測試架構既有先例延伸**：涉及原生 method channel 雙向溝通的 Dart 測試比照 `epub_reader_view_test.dart`／Issue 2 Task 8 既有先例，用 `TestDefaultBinaryMessengerBinding` 同時驗證 outgoing／incoming method call；純 Kotlin 邏輯（觸控狀態機、bitmap 疊加繪製）不在 `app/test/` 撰寫測試（`_channel` 恆為 null，無法驅動），可獨立驗證的座標數學/資料解析抽成 `internal` 純函式後在 `app/android/app/src/test/` 撰寫 JVM 單元測試（比照既有 `PdfReaderViewTest.kt` 對 `isDualPageEnabled`/`pairIndices` 等純函式的既有先例），真正的手勢/繪製結果驗證留給 Task 11 `integration_test`。
- `flutter analyze` 全程必須保持 `No issues found!`；每個 Task 的最後一步皆須執行並確認。

---

### Task 1：`PercentRect` 新增 JSON 序列化

**Files:**
- Modify: `app/lib/reader/percent_rect.dart`
- Modify: `app/test/reader/percent_rect_test.dart`

**Interfaces:**
- Consumes: 無（Issue 2 已建立的 `PercentRect`）。
- Produces: `PercentRect.toJson() → String`／`PercentRect.fromJson(String) → PercentRect`，供 Task 2（`Highlight`/`Note` 新增 `pdfRect` 欄位持久化）消費。

- [x] **Step 1: 寫失敗測試**

於 `app/test/reader/percent_rect_test.dart` 檔案結尾（最後一個 `}` 之前）新增：

```dart
  test('toJson／fromJson round-trip 保留所有欄位', () {
    const rect = PercentRect(left: 0.1, top: 0.2, right: 0.3, bottom: 0.4);
    final restored = PercentRect.fromJson(rect.toJson());
    expect(restored, rect);
  });
```

- [x] **Step 2: 執行測試確認失敗**

Run: `flutter test test/reader/percent_rect_test.dart`
Expected: FAIL（`toJson`/`fromJson` 尚不存在，編譯錯誤）

- [x] **Step 3: 實作**

`app/lib/reader/percent_rect.dart` 頂部新增：

```dart
import 'dart:convert';
```

在建構子之後（`==` 運算子之前）新增：

```dart
  /// 序列化為 JSON 字串，供 `highlights.pdf_rect_json`／`notes.pdf_rect_json`
  /// （TEXT 欄位）儲存使用，比照既有 `PdfCropRect.toJson()` 慣例。
  String toJson() => jsonEncode({
        'left': left,
        'top': top,
        'right': right,
        'bottom': bottom,
      });

  /// 對應 [toJson] 的還原方法。
  factory PercentRect.fromJson(String json) {
    final map = jsonDecode(json) as Map<String, dynamic>;
    return PercentRect(
      left: (map['left'] as num).toDouble(),
      top: (map['top'] as num).toDouble(),
      right: (map['right'] as num).toDouble(),
      bottom: (map['bottom'] as num).toDouble(),
    );
  }
```

- [x] **Step 4: 執行測試確認通過**

Run: `flutter test test/reader/percent_rect_test.dart`
Expected: PASS

- [x] **Step 5: 執行 `flutter analyze` 確認乾淨**

Run: `flutter analyze`
Expected: `No issues found!`

- [x] **Step 6: Commit**

```bash
git add app/lib/reader/percent_rect.dart app/test/reader/percent_rect_test.dart
git commit -m "feat(epic-6): PercentRect 新增 JSON 序列化供 PDF 劃線座標持久化"
```

---

### Task 2：`Highlight`／`Note` 新增 PDF 欄位

**Files:**
- Modify: `app/lib/reader/highlight.dart`
- Modify: `app/lib/reader/note.dart`
- Modify: `app/test/reader/highlight_test.dart`
- Modify: `app/test/reader/note_test.dart`
- Modify: `app/test/support/fake_highlights_repository.dart`
- Modify: `app/test/support/fake_notes_repository.dart`

**Interfaces:**
- Consumes: Task 1 的 `PercentRect.toJson()`/`fromJson()`。
- Produces: `Highlight`/`Note` 新增 `pdfPageIndex: int?`／`pdfRect: PercentRect?` 欄位，供 Task 4（排序）、Task 5（wire 格式）、Task 10（`ReaderScreen`）消費。

- [x] **Step 1: 寫失敗測試（`highlight_test.dart` 新增案例）**

於 `app/test/reader/highlight_test.dart` 頂部新增 import：

```dart
import 'package:elinkbook/reader/percent_rect.dart';
```

於檔案結尾（最後一個 `}` 之前）新增：

```dart
  test('toMap／fromMap round-trip 保留 PDF 欄位（pdfPageIndex／pdfRect）', () {
    const highlight = Highlight(
      bookId: 'b1',
      style: HighlightStyle.underline,
      pdfPageIndex: 3,
      pdfRect: PercentRect(left: 0.1, top: 0.2, right: 0.3, bottom: 0.4),
    );
    final map = highlight.toMap();
    expect(map['pdf_page_index'], 3);
    expect(map['pdf_rect_json'], isNotNull);

    final restored = Highlight.fromMap({
      'id': 1,
      'book_id': 'b1',
      'style': 'underline',
      'epub_locator_json': null,
      'progression': null,
      'pdf_page_index': map['pdf_page_index'],
      'pdf_rect_json': map['pdf_rect_json'],
    });
    expect(restored.pdfPageIndex, 3);
    expect(restored.pdfRect, const PercentRect(left: 0.1, top: 0.2, right: 0.3, bottom: 0.4));
  });

  test('fromMap 缺少 pdf_page_index／pdf_rect_json 鍵時（EPUB 既有資料列）視為 null', () {
    final restored = Highlight.fromMap({
      'id': 1,
      'book_id': 'b1',
      'style': 'underline',
      'epub_locator_json': '{"href":"/c1.xhtml"}',
      'progression': 0.1,
    });
    expect(restored.pdfPageIndex, isNull);
    expect(restored.pdfRect, isNull);
  });
```

- [x] **Step 2: 執行測試確認失敗**

Run: `flutter test test/reader/highlight_test.dart`
Expected: FAIL（`Highlight` 尚無 `pdfPageIndex`/`pdfRect` 建構參數，編譯錯誤）

- [x] **Step 3: 修改 `Highlight`**

`app/lib/reader/highlight.dart` 頂部新增：

```dart
import 'percent_rect.dart';
```

整個類別改為：

```dart
/// 單一劃線（epic-6-annotations Issue 2/3，spec.md「劃線與備註模組」）：
/// 標記書中「一段選取範圍」，定位精度高於書籤（EPUB：Locator JSON，含
/// 選取範圍本身；PDF：頁碼＋頁內矩形座標，Issue 3 新增）。建立後不可
/// 改色/改樣式（spec.md 決策），需要改色時刪除重建。[epubLocatorJson]／
/// [progression] 與 [pdfPageIndex]／[pdfRect] 互斥，一筆劃線只會用到其中
/// 一組（依書籍格式而定，比照 [Bookmark] 既有的欄位語意）。
class Highlight {
  /// SQLite 自動指派的 rowid，新增前（尚未寫入資料庫）為 null。
  final int? id;
  final String bookId;
  final HighlightStyle style;
  final String? epubLocatorJson;
  final double? progression;
  final int? pdfPageIndex;
  final PercentRect? pdfRect;

  const Highlight({
    this.id,
    required this.bookId,
    required this.style,
    this.epubLocatorJson,
    this.progression,
    this.pdfPageIndex,
    this.pdfRect,
  });

  /// 供 [HighlightsRepository.insert] 使用；刻意不含 `id`，比照
  /// `Bookmark.toMap()` 既有慣例（新增一律交由 SQLite `AUTOINCREMENT`
  /// 指派）。
  Map<String, Object?> toMap() {
    return {
      'book_id': bookId,
      'style': style.name,
      'epub_locator_json': epubLocatorJson,
      'progression': progression,
      'pdf_page_index': pdfPageIndex,
      'pdf_rect_json': pdfRect?.toJson(),
    };
  }

  factory Highlight.fromMap(Map<String, Object?> map) {
    final pdfRectJson = map['pdf_rect_json'] as String?;
    return Highlight(
      id: map['id'] as int?,
      bookId: map['book_id'] as String,
      style: HighlightStyle.values.byName(map['style'] as String),
      epubLocatorJson: map['epub_locator_json'] as String?,
      progression: (map['progression'] as num?)?.toDouble(),
      pdfPageIndex: map['pdf_page_index'] as int?,
      pdfRect: pdfRectJson == null ? null : PercentRect.fromJson(pdfRectJson),
    );
  }

  @override
  bool operator ==(Object other) =>
      other is Highlight &&
      other.id == id &&
      other.bookId == bookId &&
      other.style == style &&
      other.epubLocatorJson == epubLocatorJson &&
      other.progression == progression &&
      other.pdfPageIndex == pdfPageIndex &&
      other.pdfRect == pdfRect;

  @override
  int get hashCode => Object.hash(
        id,
        bookId,
        style,
        epubLocatorJson,
        progression,
        pdfPageIndex,
        pdfRect,
      );

  @override
  String toString() =>
      'Highlight(id: $id, bookId: $bookId, style: $style, epubLocatorJson: $epubLocatorJson, progression: $progression, pdfPageIndex: $pdfPageIndex, pdfRect: $pdfRect)';
}
```

- [x] **Step 4: 執行測試確認通過**

Run: `flutter test test/reader/highlight_test.dart`
Expected: PASS（含既有 Issue 2 測試不受影響）

- [x] **Step 5: 寫失敗測試（`note_test.dart` 新增案例）**

於 `app/test/reader/note_test.dart` 頂部新增 import：

```dart
import 'package:elinkbook/reader/percent_rect.dart';
```

於檔案結尾（最後一個 `}` 之前）新增：

```dart
  test('toMap／fromMap round-trip 保留 PDF 欄位（pdfPageIndex／pdfRect）', () {
    const note = Note(
      bookId: 'b1',
      text: '重點',
      pdfPageIndex: 2,
      pdfRect: PercentRect(left: 0.05, top: 0.1, right: 0.5, bottom: 0.15),
    );
    final map = note.toMap();
    expect(map['pdf_page_index'], 2);
    expect(map['pdf_rect_json'], isNotNull);

    final restored = Note.fromMap({
      'id': 1,
      'book_id': 'b1',
      'text': '重點',
      'epub_locator_json': null,
      'progression': null,
      'highlight_id': null,
      'pdf_page_index': map['pdf_page_index'],
      'pdf_rect_json': map['pdf_rect_json'],
    });
    expect(restored.pdfPageIndex, 2);
    expect(restored.pdfRect, const PercentRect(left: 0.05, top: 0.1, right: 0.5, bottom: 0.15));
  });

  test('copyWith 只更新 text，PDF 欄位保留原值', () {
    const original = Note(
      id: 1,
      bookId: 'b1',
      text: '舊文字',
      pdfPageIndex: 4,
      pdfRect: PercentRect(left: 0, top: 0, right: 1, bottom: 1),
    );
    final updated = original.copyWith(text: '新文字');
    expect(updated.pdfPageIndex, 4);
    expect(updated.pdfRect, const PercentRect(left: 0, top: 0, right: 1, bottom: 1));
  });
```

- [x] **Step 6: 執行測試確認失敗**

Run: `flutter test test/reader/note_test.dart`
Expected: FAIL（`Note` 尚無 `pdfPageIndex`/`pdfRect` 建構參數，編譯錯誤）

- [x] **Step 7: 修改 `Note`**

`app/lib/reader/note.dart` 頂部新增：

```dart
import 'percent_rect.dart';
```

整個類別改為：

```dart
/// 單一備註（epic-6-annotations Issue 2/3，spec.md「劃線與備註模組」）：
/// 自由文字內容，可獨立於劃線存在。[highlightId] 為 null 代表純備註
/// （無劃線），非 null 代表依附於某一筆 [Highlight]（見 spec.md「資料
/// 模型關聯」——`notes.highlight_id REFERENCES highlights(id) ON DELETE
/// SET NULL`，批次刪除劃線後此欄位由資料庫自動退化為 null）。
/// [epubLocatorJson]／[progression] 與 [pdfPageIndex]／[pdfRect]（Issue 3
/// 新增）互斥，比照 [Highlight] 的既有欄位語意。
class Note {
  final int? id;
  final String bookId;
  final String text;
  final String? epubLocatorJson;
  final double? progression;
  final int? highlightId;
  final int? pdfPageIndex;
  final PercentRect? pdfRect;

  const Note({
    this.id,
    required this.bookId,
    required this.text,
    this.epubLocatorJson,
    this.progression,
    this.highlightId,
    this.pdfPageIndex,
    this.pdfRect,
  });

  Map<String, Object?> toMap() {
    return {
      'book_id': bookId,
      'text': text,
      'epub_locator_json': epubLocatorJson,
      'progression': progression,
      'highlight_id': highlightId,
      'pdf_page_index': pdfPageIndex,
      'pdf_rect_json': pdfRect?.toJson(),
    };
  }

  factory Note.fromMap(Map<String, Object?> map) {
    final pdfRectJson = map['pdf_rect_json'] as String?;
    return Note(
      id: map['id'] as int?,
      bookId: map['book_id'] as String,
      text: map['text'] as String,
      epubLocatorJson: map['epub_locator_json'] as String?,
      progression: (map['progression'] as num?)?.toDouble(),
      highlightId: map['highlight_id'] as int?,
      pdfPageIndex: map['pdf_page_index'] as int?,
      pdfRect: pdfRectJson == null ? null : PercentRect.fromJson(pdfRectJson),
    );
  }

  Note copyWith({String? text}) {
    return Note(
      id: id,
      bookId: bookId,
      text: text ?? this.text,
      epubLocatorJson: epubLocatorJson,
      progression: progression,
      highlightId: highlightId,
      pdfPageIndex: pdfPageIndex,
      pdfRect: pdfRect,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is Note &&
      other.id == id &&
      other.bookId == bookId &&
      other.text == text &&
      other.epubLocatorJson == epubLocatorJson &&
      other.progression == progression &&
      other.highlightId == highlightId &&
      other.pdfPageIndex == pdfPageIndex &&
      other.pdfRect == pdfRect;

  @override
  int get hashCode => Object.hash(
        id,
        bookId,
        text,
        epubLocatorJson,
        progression,
        highlightId,
        pdfPageIndex,
        pdfRect,
      );

  @override
  String toString() =>
      'Note(id: $id, bookId: $bookId, text: $text, epubLocatorJson: $epubLocatorJson, progression: $progression, highlightId: $highlightId, pdfPageIndex: $pdfPageIndex, pdfRect: $pdfRect)';
}
```

- [x] **Step 8: 執行測試確認通過**

Run: `flutter test test/reader/note_test.dart`
Expected: PASS

- [x] **Step 9: 更新測試 Fake（`FakeHighlightsRepository`／`FakeNotesRepository`）**

`app/test/support/fake_highlights_repository.dart` 的 `insert` 方法內，`_storage.add(Highlight(...))` 補上兩個新欄位：

```dart
  @override
  Future<int> insert(Highlight highlight) async {
    final id = _nextId++;
    _storage.add(Highlight(
      id: id,
      bookId: highlight.bookId,
      style: highlight.style,
      epubLocatorJson: highlight.epubLocatorJson,
      progression: highlight.progression,
      pdfPageIndex: highlight.pdfPageIndex,
      pdfRect: highlight.pdfRect,
    ));
    return id;
  }
```

`listByBook` 的排序改為 PDF/EPUB 共通的位置鍵（比照 Task 4 稍後對正式 Repository 的同一種修正，Fake 亦須同步以維持測試行為一致）：

```dart
  @override
  Future<List<Highlight>> listByBook(String bookId) async {
    final list = _storage.where((h) => h.bookId == bookId).toList();
    list.sort((a, b) => _positionOf(a).compareTo(_positionOf(b)));
    return list;
  }

  double _positionOf(Highlight h) =>
      (h.pdfPageIndex?.toDouble()) ?? h.progression ?? 0;
```

`app/test/support/fake_notes_repository.dart` 同步修改：

```dart
  @override
  Future<int> insert(Note note) async {
    final id = _nextId++;
    _storage.add(Note(
      id: id,
      bookId: note.bookId,
      text: note.text,
      epubLocatorJson: note.epubLocatorJson,
      progression: note.progression,
      highlightId: note.highlightId,
      pdfPageIndex: note.pdfPageIndex,
      pdfRect: note.pdfRect,
    ));
    return id;
  }

  @override
  Future<List<Note>> listByBook(String bookId) async {
    final list = _storage.where((n) => n.bookId == bookId).toList();
    list.sort((a, b) => _positionOf(a).compareTo(_positionOf(b)));
    return list;
  }

  double _positionOf(Note n) => (n.pdfPageIndex?.toDouble()) ?? n.progression ?? 0;
```

`copyWith` 呼叫（`updateText` 方法內）不需改動——`Note.copyWith` 已於 Step 7 保留 `pdfPageIndex`/`pdfRect`。

- [x] **Step 10: 執行全專案測試確認通過**

Run: `flutter test`
Expected: 全數 PASS（Fake 修改不影響既有依賴它們的 Issue 1/2 測試——排序鍵在 EPUB-only 情境下 `pdfPageIndex` 恆 null，退回 `progression`，行為與修改前一致）

- [x] **Step 11: 執行 `flutter analyze` 確認乾淨**

Run: `flutter analyze`
Expected: `No issues found!`

- [x] **Step 12: Commit**

```bash
git add app/lib/reader/highlight.dart app/lib/reader/note.dart app/test/reader/highlight_test.dart app/test/reader/note_test.dart app/test/support/fake_highlights_repository.dart app/test/support/fake_notes_repository.dart
git commit -m "feat(epic-6): Highlight／Note 新增 PDF 頁碼與矩形座標欄位"
```

---

### Task 3：SQLite `highlights`／`notes` 表新增 PDF 欄位（v9→v10）

**Files:**
- Modify: `app/lib/library/sqlite_library_repository.dart`
- Modify: `app/test/library/sqlite_library_repository_test.dart`

**Interfaces:**
- Consumes: Task 2 的 `Highlight`/`Note` PDF 欄位。
- Produces: `highlights`／`notes` 表新增 `pdf_page_index`/`pdf_rect_json` 欄位，供 Task 4 的 Repository 消費。

- [x] **Step 1: 寫失敗測試**

於 `app/test/library/sqlite_library_repository_test.dart` 檔案結尾（最後一個 `}` 之前）新增：

```dart
  test('全新安裝的 highlights／notes 表含 PDF 欄位（version 10 起 onCreate 已含括）',
      () async {
    await repository.insertBook(_book('b_pdf_highlight'));
    final highlightId = await repository.database.insert('highlights', {
      'book_id': 'b_pdf_highlight',
      'style': 'underline',
      'pdf_page_index': 2,
      'pdf_rect_json': '{"left":0.1,"top":0.2,"right":0.3,"bottom":0.4}',
    });
    expect(highlightId, greaterThan(0));

    final noteId = await repository.database.insert('notes', {
      'book_id': 'b_pdf_highlight',
      'text': '心得',
      'pdf_page_index': 2,
      'pdf_rect_json': '{"left":0.1,"top":0.2,"right":0.3,"bottom":0.4}',
      'highlight_id': highlightId,
    });
    expect(noteId, greaterThan(0));
  });

  test('既有 version 9 裝置升級到 version 10，highlights／notes 表正確補上 PDF 欄位（ALTER TABLE 路徑）',
      () async {
    final tempDir = await Directory.systemTemp
        .createTemp('elinkbook_migration_v9_to_v10_test');
    addTearDown(() => tempDir.delete(recursive: true));
    final dbPath = p.join(tempDir.path, 'test.db');

    // 模擬「已存在於 version 9」的舊資料庫：手動以 version 9 當時的完整
    // schema 建立（highlights/notes 已存在但無 PDF 欄位），不透過
    // SqliteLibraryRepository.open()（該方法目前的 onCreate 已經是
    // version 10 的最終 schema），比照 v8→v9 遷移測試既有寫法。
    final oldDb = await databaseFactory.openDatabase(
      dbPath,
      options: OpenDatabaseOptions(
        version: 9,
        onConfigure: (db) async {
          await db.execute('PRAGMA foreign_keys = ON');
        },
        onCreate: (db, version) async {
          await db.execute('CREATE TABLE groups (name TEXT PRIMARY KEY)');
          await db.insert('groups', {'name': '未分類'});
          await db.execute('''
            CREATE TABLE books (
              id TEXT PRIMARY KEY,
              title TEXT NOT NULL,
              author TEXT,
              format TEXT NOT NULL,
              filePath TEXT NOT NULL,
              source TEXT NOT NULL,
              coverPath TEXT,
              progress REAL NOT NULL DEFAULT 0,
              epubLocator TEXT,
              pdfPageIndex INTEGER,
              totalCharacterCount INTEGER,
              groupName TEXT NOT NULL DEFAULT '未分類',
              createTime INTEGER NOT NULL,
              lastReadTime INTEGER NOT NULL
            )
          ''');
          await db.execute('''
            CREATE TABLE highlights (
              id INTEGER PRIMARY KEY AUTOINCREMENT,
              book_id TEXT NOT NULL REFERENCES books(id) ON DELETE CASCADE,
              style TEXT NOT NULL,
              epub_locator_json TEXT,
              progression REAL
            )
          ''');
          await db.execute('''
            CREATE TABLE notes (
              id INTEGER PRIMARY KEY AUTOINCREMENT,
              book_id TEXT NOT NULL REFERENCES books(id) ON DELETE CASCADE,
              text TEXT NOT NULL,
              epub_locator_json TEXT,
              progression REAL,
              highlight_id INTEGER REFERENCES highlights(id) ON DELETE SET NULL
            )
          ''');
        },
      ),
    );
    await oldDb.insert('books', {
      'id': 'b1',
      'title': '既有書籍',
      'format': 'pdf',
      'filePath': 'content://example/b1',
      'source': 'local',
      'progress': 0.0,
      'groupName': '未分類',
      'createTime': 1000,
      'lastReadTime': 1000,
    });
    final existingHighlightId = await oldDb.insert('highlights', {
      'book_id': 'b1',
      'style': 'underline',
      'epub_locator_json': null,
      'progression': 0.1,
    });
    await oldDb.close();

    // 重新以目前版本開啟同一個檔案，觸發 onUpgrade（oldVersion=9 →
    // newVersion=10），驗證 highlights／notes 表確實補上 PDF 欄位、既有
    // 資料列不受影響、且新欄位可正常寫入。
    final upgraded = await SqliteLibraryRepository.open(dbPath);
    addTearDown(() => upgraded.close());

    final existingRows = await upgraded.database
        .query('highlights', where: 'id = ?', whereArgs: [existingHighlightId]);
    expect(existingRows.single['progression'], 0.1);
    expect(existingRows.single['pdf_page_index'], isNull);

    final newHighlightId = await upgraded.database.insert('highlights', {
      'book_id': 'b1',
      'style': 'highlighterYellow',
      'pdf_page_index': 5,
      'pdf_rect_json': '{"left":0,"top":0,"right":1,"bottom":1}',
    });
    expect(newHighlightId, greaterThan(0));

    final newNoteId = await upgraded.database.insert('notes', {
      'book_id': 'b1',
      'text': '升級後新增的 PDF 備註',
      'pdf_page_index': 5,
      'pdf_rect_json': '{"left":0,"top":0,"right":1,"bottom":1}',
      'highlight_id': null,
    });
    expect(newNoteId, greaterThan(0));
  });
```

- [x] **Step 2: 執行測試確認失敗**

Run: `flutter test test/library/sqlite_library_repository_test.dart`
Expected: FAIL（`no such column: pdf_page_index`，因為 schema 尚未更新且 `version` 仍為 9）

- [x] **Step 3: 實作 schema migration**

`app/lib/library/sqlite_library_repository.dart` 的 `version: 9,` 改為：

```dart
      version: 10,
```

`_createHighlightsTable`／`_createNotesTable` 的 `CREATE TABLE` 語句各自補上兩個新欄位（一步到位，全新安裝走此路徑，見 Global Constraints）：

```dart
  static Future<void> _createHighlightsTable(Database db) async {
    // 劃線（epic-6-annotations Issue 2/3，spec.md「劃線與備註模組」），與
    // books 表以 book_id 外鍵關聯（比照 bookmarks 既有關聯模式）。
    // pdf_page_index／pdf_rect_json（Issue 3 新增）與
    // epub_locator_json／progression（Issue 2）互斥，依書籍格式擇一填入。
    await db.execute('''
      CREATE TABLE highlights (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        book_id TEXT NOT NULL REFERENCES books(id) ON DELETE CASCADE,
        style TEXT NOT NULL,
        epub_locator_json TEXT,
        progression REAL,
        pdf_page_index INTEGER,
        pdf_rect_json TEXT
      )
    ''');
  }

  static Future<void> _createNotesTable(Database db) async {
    // 備註（epic-6-annotations Issue 2/3，spec.md「資料模型關聯」）：
    // highlight_id 為可空外鍵，ON DELETE SET NULL——批次刪除劃線後，
    // 依附的備註自動退化為純備註（highlight_id 變 null），不需應用層
    // 判斷邏輯。建表順序刻意晚於 _createHighlightsTable（程式碼可讀性
    // 慣例，非技術硬性要求，見 spec.md 審查修正 1.1）。
    await db.execute('''
      CREATE TABLE notes (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        book_id TEXT NOT NULL REFERENCES books(id) ON DELETE CASCADE,
        text TEXT NOT NULL,
        epub_locator_json TEXT,
        progression REAL,
        highlight_id INTEGER REFERENCES highlights(id) ON DELETE SET NULL,
        pdf_page_index INTEGER,
        pdf_rect_json TEXT
      )
    ''');
  }
```

新增 ALTER TABLE 輔助函式（既有裝置升級路徑），放在 `_createNotesTable` 之後：

```dart
  static Future<void> _addPdfAnnotationColumns(Database db) async {
    // epic-6-annotations Issue 3：PDF 專屬的劃線/備註定位欄位，補追加到
    // 既有（version 9 起已存在）的 highlights／notes 兩張表。只有
    // oldVersion == 9（表已存在但無這兩欄位）的裝置會走到這個函式，見
    // onUpgrade 的 if/else 互斥結構。
    await db.execute('ALTER TABLE highlights ADD COLUMN pdf_page_index INTEGER');
    await db.execute('ALTER TABLE highlights ADD COLUMN pdf_rect_json TEXT');
    await db.execute('ALTER TABLE notes ADD COLUMN pdf_page_index INTEGER');
    await db.execute('ALTER TABLE notes ADD COLUMN pdf_rect_json TEXT');
  }
```

`onUpgrade` 內原本的：

```dart
        if (oldVersion < 9) {
          // epic-6-annotations Issue 2：劃線／備註功能新增的兩張全新
          // 資料表。與 bookmarks 表（oldVersion < 8）比照同一原則——
          // 任何 oldVersion < 9 的裝置都必然還沒有這兩張表，無條件建立
          // 即可，不需要判斷「表是否已存在」。順序先建 highlights 再建
          // notes（notes.highlight_id 參照 highlights，見 spec.md「資料
          // 模型關聯」審查修正 1.1 的程式碼可讀性慣例）。
          await _createHighlightsTable(db);
          await _createNotesTable(db);
        }
```

改為 if/else 互斥結構（**重要**：不可寫成兩個獨立的 `if`，見 Global Constraints）：

```dart
        if (oldVersion < 9) {
          // epic-6-annotations Issue 2：劃線／備註功能新增的兩張全新
          // 資料表。與 bookmarks 表（oldVersion < 8）比照同一原則——
          // 任何 oldVersion < 9 的裝置都必然還沒有這兩張表，無條件建立
          // 即可，不需要判斷「表是否已存在」。順序先建 highlights 再建
          // notes（notes.highlight_id 參照 highlights，見 spec.md「資料
          // 模型關聯」審查修正 1.1 的程式碼可讀性慣例）。_createHighlightsTable／
          // _createNotesTable 已是 version 10 的最終欄位組合（含 Issue 3
          // 的 PDF 欄位），一步到位，故此分支之後不需要再跑
          // _addPdfAnnotationColumns（否則會對剛建好、已有該欄位的表
          // ALTER TABLE，拋出 duplicate column name 例外）。
          await _createHighlightsTable(db);
          await _createNotesTable(db);
        } else if (oldVersion < 10) {
          // epic-6-annotations Issue 3：oldVersion 為 9 的裝置，
          // highlights／notes 表已存在（上方 if 分支已處理過），但欄位
          // 版本停留在 Issue 2（無 PDF 欄位），僅需 ALTER TABLE 補上。
          await _addPdfAnnotationColumns(db);
        }
```

- [x] **Step 4: 執行測試確認通過**

Run: `flutter test test/library/sqlite_library_repository_test.dart`
Expected: PASS（全部測試綠燈，含既有 v1→v9 系列遷移測試不受影響）

- [x] **Step 5: 執行全專案測試確認通過**

Run: `flutter test`
Expected: 全數 PASS

- [x] **Step 6: 執行 `flutter analyze` 確認乾淨**

Run: `flutter analyze`
Expected: `No issues found!`

- [x] **Step 7: Commit**

```bash
git add app/lib/library/sqlite_library_repository.dart app/test/library/sqlite_library_repository_test.dart
git commit -m "feat(epic-6): highlights／notes 表新增 PDF 欄位與 v9→v10 schema migration"
```

---

### Task 4：Repository 排序改用 `COALESCE` + `mergeAnnotations` 支援 PDF 位置排序

**Files:**
- Modify: `app/lib/reader/highlights_repository.dart`
- Modify: `app/lib/reader/notes_repository.dart`
- Modify: `app/lib/reader/annotation_list_item.dart`
- Modify: `app/test/reader/highlights_repository_test.dart`
- Modify: `app/test/reader/notes_repository_test.dart`
- Modify: `app/test/reader/annotation_list_item_test.dart`

**Interfaces:**
- Consumes: Task 2／Task 3 的 PDF 欄位。
- Produces: `HighlightsRepository.listByBook`／`NotesRepository.listByBook` 依 `COALESCE(pdf_page_index, progression)` 排序；`mergeAnnotations` 正確依 PDF 頁碼或 EPUB 進度排序（**修正一個真實缺陷**：目前 `AnnotationListItem._position` 只讀 `progression`，PDF 項目的 `progression` 恆為 null，會導致所有 PDF 劃線/備註在清單中排序鍵皆為 0、無法正確依頁碼排序）。

- [x] **Step 1: 寫失敗測試（`highlights_repository_test.dart` 新增案例）**

於 `app/test/reader/highlights_repository_test.dart` 檔案結尾（最後一個 `}` 之前）新增：

```dart
  test('listByBook 對 PDF 劃線依 pdf_page_index 由小到大排序', () async {
    await repository.insert(const Highlight(
        bookId: 'b1', style: HighlightStyle.underline, pdfPageIndex: 5));
    await repository.insert(const Highlight(
        bookId: 'b1', style: HighlightStyle.underline, pdfPageIndex: 1));

    final list = await repository.listByBook('b1');
    expect(list.map((h) => h.pdfPageIndex).toList(), [1, 5]);
  });
```

- [x] **Step 2: 執行測試確認失敗**

Run: `flutter test test/reader/highlights_repository_test.dart`
Expected: FAIL（目前 `orderBy: 'progression ASC'`，`pdf_page_index` 非 null 但 `progression` 皆為 null，SQLite 排序 null 值視為相等，兩筆順序不保證為 `[1, 5]`——依插入順序恰好可能巧合通過，需以 3 筆以上或明確反向插入順序驗證；比照上方寫法先插入頁碼較大者，若排序邏輯錯誤會得到 `[5, 1]`）

- [x] **Step 3: 修正 `HighlightsRepository.listByBook`**

`app/lib/reader/highlights_repository.dart` 的 `listByBook` 方法改為：

```dart
  /// 依書中位置順序排序：EPUB 用 `progression` 比例、PDF 用
  /// `pdf_page_index`（Issue 3 新增），兩者互斥、一本書只會用到其中一組
  /// （比照 `BookmarksRepository.listByBook` 既有的 `COALESCE` 慣例）。
  Future<List<Highlight>> listByBook(String bookId) async {
    final rows = await _db.query(
      'highlights',
      where: 'book_id = ?',
      whereArgs: [bookId],
      orderBy: 'COALESCE(pdf_page_index, progression) ASC',
    );
    return rows.map(Highlight.fromMap).toList();
  }
```

- [x] **Step 4: 執行測試確認通過**

Run: `flutter test test/reader/highlights_repository_test.dart`
Expected: PASS（含既有 EPUB 排序測試不受影響——`pdf_page_index` 恆 null 時 `COALESCE` 退回 `progression`，行為與修改前等價）

- [x] **Step 5: 寫失敗測試（`notes_repository_test.dart` 新增案例）**

於 `app/test/reader/notes_repository_test.dart` 檔案結尾（最後一個 `}` 之前）新增：

```dart
  test('listByBook 對 PDF 備註依 pdf_page_index 由小到大排序', () async {
    await notesRepository.insert(const Note(bookId: 'b1', text: 'B', pdfPageIndex: 5));
    await notesRepository.insert(const Note(bookId: 'b1', text: 'A', pdfPageIndex: 1));

    final list = await notesRepository.listByBook('b1');
    expect(list.map((n) => n.text).toList(), ['A', 'B']);
  });
```

- [x] **Step 6: 執行測試確認失敗**

Run: `flutter test test/reader/notes_repository_test.dart`
Expected: FAIL（同上，`orderBy: 'progression ASC'` 對 PDF 資料無法正確排序）

- [x] **Step 7: 修正 `NotesRepository.listByBook`**

`app/lib/reader/notes_repository.dart` 的 `listByBook` 方法改為：

```dart
  /// 依書中位置順序排序，比照 [HighlightsRepository.listByBook] 的
  /// `COALESCE` 慣例（Issue 3 新增）。
  Future<List<Note>> listByBook(String bookId) async {
    final rows = await _db.query(
      'notes',
      where: 'book_id = ?',
      whereArgs: [bookId],
      orderBy: 'COALESCE(pdf_page_index, progression) ASC',
    );
    return rows.map(Note.fromMap).toList();
  }
```

- [x] **Step 8: 執行測試確認通過**

Run: `flutter test test/reader/notes_repository_test.dart`
Expected: PASS

- [x] **Step 9: 寫失敗測試（`annotation_list_item_test.dart` 新增案例）**

於 `app/test/reader/annotation_list_item_test.dart` 檔案結尾（最後一個 `}` 之前）新增：

```dart
  test('PDF 項目依 pdfPageIndex 由小到大排序（修正 progression 恆為 null 時排序鍵失效的缺陷）',
      () {
    final highlights = [
      const Highlight(id: 1, bookId: 'b1', style: HighlightStyle.underline, pdfPageIndex: 9),
      const Highlight(id: 2, bookId: 'b1', style: HighlightStyle.underline, pdfPageIndex: 0),
    ];
    final notes = [
      const Note(id: 5, bookId: 'b1', text: '純備註', pdfPageIndex: 4),
    ];
    final items = mergeAnnotations(highlights, notes);
    expect(items.map((i) => i.highlight?.id ?? -i.note!.id!).toList(), [2, -5, 1]);
  });
```

- [x] **Step 10: 執行測試確認失敗**

Run: `flutter test test/reader/annotation_list_item_test.dart`
Expected: FAIL（`_position` 只讀 `progression`，PDF 項目排序鍵恆為 0，無法區分順序）

- [x] **Step 11: 修正 `AnnotationListItem._position`**

`app/lib/reader/annotation_list_item.dart` 的 `_position` getter 改為：

```dart
  /// 排序鍵：PDF 用 `pdfPageIndex`、EPUB 用 `progression`，兩者互斥（Issue 3
  /// 修正——原本只讀 `progression`，PDF 項目的 `progression` 恆為 null，
  /// 會導致所有 PDF 劃線/備註排序鍵皆為 0、清單順序失去意義）。
  double get _position =>
      (highlight?.pdfPageIndex ?? note?.pdfPageIndex)?.toDouble() ??
      highlight?.progression ??
      note?.progression ??
      0;
```

- [x] **Step 12: 執行測試確認通過**

Run: `flutter test test/reader/annotation_list_item_test.dart`
Expected: PASS（含既有 EPUB 排序測試不受影響）

- [x] **Step 13: 執行全專案測試 + `flutter analyze` 確認乾淨**

Run: `flutter test`
Expected: 全數 PASS

Run: `flutter analyze`
Expected: `No issues found!`

- [x] **Step 14: Commit**

```bash
git add app/lib/reader/highlights_repository.dart app/lib/reader/notes_repository.dart app/lib/reader/annotation_list_item.dart app/test/reader/highlights_repository_test.dart app/test/reader/notes_repository_test.dart app/test/reader/annotation_list_item_test.dart
git commit -m "fix(epic-6): Repository／mergeAnnotations 排序改用 COALESCE 支援 PDF 頁碼"
```

---

### Task 5：`PdfSelectionInfo`／`PdfAnnotationDecoration` Dart 值物件

**Files:**
- Create: `app/lib/reader/pdf_selection_info.dart`
- Create: `app/lib/reader/pdf_annotation_decoration.dart`
- Test: `app/test/reader/pdf_selection_info_test.dart`
- Test: `app/test/reader/pdf_annotation_decoration_test.dart`

**Interfaces:**
- Consumes: Task 1 的 `PercentRect`。
- Produces: `PdfSelectionInfo`（`pageIndex`/`rect`）；`PdfAnnotationDecoration`（`pageIndex`/`rect`/`tint`/`isUnderline`/`isNoteOnly`，`toWire()`，`forHighlight`/`forNote` 具名建構子），供 Task 6（`PdfReaderView.dart`）與 Task 10（`ReaderScreen`）消費。

- [x] **Step 1: 寫失敗測試（`pdf_selection_info_test.dart`）**

建立 `app/test/reader/pdf_selection_info_test.dart`：

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:elinkbook/reader/pdf_selection_info.dart';
import 'package:elinkbook/reader/percent_rect.dart';

void main() {
  test('兩個欄位值完全相同的 PdfSelectionInfo 視為相等', () {
    const a = PdfSelectionInfo(
      pageIndex: 3,
      rect: PercentRect(left: 0.1, top: 0.2, right: 0.3, bottom: 0.4),
    );
    const b = PdfSelectionInfo(
      pageIndex: 3,
      rect: PercentRect(left: 0.1, top: 0.2, right: 0.3, bottom: 0.4),
    );
    expect(a, b);
    expect(a.hashCode, b.hashCode);
  });
}
```

- [x] **Step 2: 執行測試確認失敗**

Run: `flutter test test/reader/pdf_selection_info_test.dart`
Expected: FAIL（`pdf_selection_info.dart` 尚不存在，編譯錯誤）

- [x] **Step 3: 實作 `PdfSelectionInfo`**

建立 `app/lib/reader/pdf_selection_info.dart`：

```dart
import 'percent_rect.dart';

/// [PdfReaderView] 使用者長按拖曳框選劃線範圍完成時回報的資訊
/// （epic-6-annotations Issue 3）。[rect] 為框選矩形相對「目前顯示中
/// bitmap 內容範圍」的百分比值（見 plan-issue-3.md Global Constraints
/// 「PDF 座標協定」），[pageIndex] 為框選發生的頁碼（0-indexed）。
class PdfSelectionInfo {
  final int pageIndex;
  final PercentRect rect;

  const PdfSelectionInfo({required this.pageIndex, required this.rect});

  @override
  bool operator ==(Object other) =>
      other is PdfSelectionInfo && other.pageIndex == pageIndex && other.rect == rect;

  @override
  int get hashCode => Object.hash(pageIndex, rect);

  @override
  String toString() => 'PdfSelectionInfo(pageIndex: $pageIndex, rect: $rect)';
}
```

- [x] **Step 4: 執行測試確認通過**

Run: `flutter test test/reader/pdf_selection_info_test.dart`
Expected: PASS

- [x] **Step 5: 寫失敗測試（`pdf_annotation_decoration_test.dart`）**

建立 `app/test/reader/pdf_annotation_decoration_test.dart`：

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:elinkbook/reader/pdf_annotation_decoration.dart';
import 'package:elinkbook/reader/percent_rect.dart';

void main() {
  test('forHighlight／forNote 產生正確的 wire 格式', () {
    const rect = PercentRect(left: 0.1, top: 0.2, right: 0.3, bottom: 0.4);

    final highlight = PdfAnnotationDecoration.forHighlight(
      pageIndex: 2,
      rect: rect,
      tint: 0x73FDE047,
      isUnderline: false,
    );
    expect(highlight.toWire(), {
      'pageIndex': 2,
      'left': 0.1,
      'top': 0.2,
      'right': 0.3,
      'bottom': 0.4,
      'tint': 0x73FDE047,
      'isUnderline': false,
      'isNoteOnly': false,
    });

    final note = PdfAnnotationDecoration.forNote(pageIndex: 5, rect: rect, tint: 0x73D1D5DB);
    expect(note.toWire()['isNoteOnly'], isTrue);
    expect(note.toWire()['isUnderline'], isFalse);
  });
}
```

- [x] **Step 6: 執行測試確認失敗**

Run: `flutter test test/reader/pdf_annotation_decoration_test.dart`
Expected: FAIL（`pdf_annotation_decoration.dart` 尚不存在，編譯錯誤）

- [x] **Step 7: 實作 `PdfAnnotationDecoration`**

建立 `app/lib/reader/pdf_annotation_decoration.dart`：

```dart
import 'percent_rect.dart';

/// 單筆「劃線/純備註」的原生疊加樣式資訊（epic-6-annotations Issue 3），
/// 供 [PdfReaderView.refreshAnnotations] 一次性送出目前應顯示的完整標記
/// 清單（非增量 diff，比照 EPUB `EpubDecoration`／`setDecorations` 整組
/// 送出慣例）。與 [EpubDecoration] 的差異：PDF 端不支援點擊既有標記互動
/// （見 plan-issue-3.md Global Constraints），故 wire 格式不含 `id`
/// 欄位；改以 `pageIndex`＋`rect` 定位。[isNoteOnly] 為 true 時原生端
/// 額外於矩形右上角疊加 📌 圖示（design.md 決策 #2，PDF 純備註畫面指示）。
class PdfAnnotationDecoration {
  final int pageIndex;
  final PercentRect rect;
  final int tint;
  final bool isUnderline;
  final bool isNoteOnly;

  const PdfAnnotationDecoration({
    required this.pageIndex,
    required this.rect,
    required this.tint,
    this.isUnderline = false,
    this.isNoteOnly = false,
  });

  factory PdfAnnotationDecoration.forHighlight({
    required int pageIndex,
    required PercentRect rect,
    required int tint,
    required bool isUnderline,
  }) {
    return PdfAnnotationDecoration(
      pageIndex: pageIndex,
      rect: rect,
      tint: tint,
      isUnderline: isUnderline,
    );
  }

  factory PdfAnnotationDecoration.forNote({
    required int pageIndex,
    required PercentRect rect,
    required int tint,
  }) {
    return PdfAnnotationDecoration(pageIndex: pageIndex, rect: rect, tint: tint, isNoteOnly: true);
  }

  Map<String, Object?> toWire() => {
        'pageIndex': pageIndex,
        'left': rect.left,
        'top': rect.top,
        'right': rect.right,
        'bottom': rect.bottom,
        'tint': tint,
        'isUnderline': isUnderline,
        'isNoteOnly': isNoteOnly,
      };
}
```

- [x] **Step 8: 執行測試確認通過**

Run: `flutter test test/reader/pdf_annotation_decoration_test.dart`
Expected: PASS

- [x] **Step 9: 執行 `flutter analyze` 確認乾淨**

Run: `flutter analyze`
Expected: `No issues found!`

- [x] **Step 10: Commit**

```bash
git add app/lib/reader/pdf_selection_info.dart app/lib/reader/pdf_annotation_decoration.dart app/test/reader/pdf_selection_info_test.dart app/test/reader/pdf_annotation_decoration_test.dart
git commit -m "feat(epic-6): 新增 PdfSelectionInfo／PdfAnnotationDecoration 型別"
```

---

### Task 6：`PdfReaderView.dart` 新增手勢驅動的選取/標記 method channel 契約

**Files:**
- Modify: `app/lib/reader/pdf_reader_view.dart`
- Modify: `app/test/reader/pdf_reader_view_test.dart`

**Interfaces:**
- Consumes: Task 5 的 `PdfSelectionInfo`／`PdfAnnotationDecoration`。
- Produces: `PdfReaderView` 的 `GestureDetector` 新增 `onLongPressStart`／`onLongPressMoveUpdate`／`onLongPressEnd`（與既有 `onHorizontalDragEnd` 同一個元件，由 Flutter 手勢競技場裁決長按 vs 水平滑動，見 Global Constraints「長按/拖曳的手勢辨識改由 Flutter 端 GestureDetector 主導」審查修正），觸發 `beginAnnotationSelection`／`updateAnnotationSelection`／`endAnnotationSelection` 三個新增 outgoing method call；外層新增 `Listener` 追蹤觸點數，多指觸碰時觸發 `cancelAnnotationSelection`。`onSelectionRectComputed`／`onSelectionCanceled` 建構參數（incoming）與 `PdfReaderView.refreshAnnotations(key, List<PdfAnnotationDecoration>)` 靜態方法（outgoing）維持不變，供 Task 10（`ReaderScreen`）消費；`PdfReaderView.kt`（Task 7/8/9）為其原生對應端。

- [x] **Step 1: 寫失敗測試（擴充 `pdf_reader_view_test.dart`）**

於 `app/test/reader/pdf_reader_view_test.dart` 頂部新增 import：

```dart
import 'package:elinkbook/reader/pdf_annotation_decoration.dart';
import 'package:elinkbook/reader/pdf_selection_info.dart';
import 'package:elinkbook/reader/percent_rect.dart';
```

於檔案結尾（最後一個 `}` 之前）新增：

```dart
  testWidgets('收到原生端 onSelectionRectComputed 事件時正確解析 PdfSelectionInfo',
      (tester) async {
    PdfSelectionInfo? received;
    final binaryMessenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    MethodChannel? instanceChannel;

    binaryMessenger.setMockMethodCallHandler(SystemChannels.platform_views,
        (call) async {
      if (call.method == 'create') {
        final id = (call.arguments as Map<Object?, Object?>)['id'] as int;
        instanceChannel =
            MethodChannel('cc.ugotit.elinkbook/pdf_reader_view_$id');
        binaryMessenger.setMockMethodCallHandler(
            instanceChannel!, (call) async => null);
        return 0;
      }
      return null;
    });

    await tester.pumpWidget(MaterialApp(
      home: PdfReaderView(
        filePath: '/tmp/sample.pdf',
        onPageRendered: _noop,
        onError: _noopError,
        onSelectionRectComputed: (info) => received = info,
      ),
    ));
    await tester.pumpAndSettle();

    final codec = instanceChannel!.codec;
    final data = codec.encodeMethodCall(const MethodCall('onSelectionRectComputed', {
      'pageIndex': 2,
      'left': 0.1,
      'top': 0.2,
      'right': 0.3,
      'bottom': 0.4,
    }));
    await binaryMessenger.handlePlatformMessage(instanceChannel!.name, data, (_) {});

    expect(
      received,
      const PdfSelectionInfo(
        pageIndex: 2,
        rect: PercentRect(left: 0.1, top: 0.2, right: 0.3, bottom: 0.4),
      ),
    );
  });

  testWidgets('收到原生端 onSelectionCanceled 事件時觸發 callback', (tester) async {
    var canceled = false;
    final binaryMessenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    MethodChannel? instanceChannel;

    binaryMessenger.setMockMethodCallHandler(SystemChannels.platform_views,
        (call) async {
      if (call.method == 'create') {
        final id = (call.arguments as Map<Object?, Object?>)['id'] as int;
        instanceChannel =
            MethodChannel('cc.ugotit.elinkbook/pdf_reader_view_$id');
        binaryMessenger.setMockMethodCallHandler(
            instanceChannel!, (call) async => null);
        return 0;
      }
      return null;
    });

    await tester.pumpWidget(MaterialApp(
      home: PdfReaderView(
        filePath: '/tmp/sample.pdf',
        onPageRendered: _noop,
        onError: _noopError,
        onSelectionCanceled: () => canceled = true,
      ),
    ));
    await tester.pumpAndSettle();

    final codec = instanceChannel!.codec;
    final data = codec.encodeMethodCall(const MethodCall('onSelectionCanceled', null));
    await binaryMessenger.handlePlatformMessage(instanceChannel!.name, data, (_) {});

    expect(canceled, isTrue);
  });

  testWidgets('refreshAnnotations 呼叫 invokeMethod 並帶上序列化後的標記清單',
      (tester) async {
    final key = GlobalKey<State<PdfReaderView>>();
    final binaryMessenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    final instanceCalls = <MethodCall>[];

    binaryMessenger.setMockMethodCallHandler(SystemChannels.platform_views,
        (call) async {
      if (call.method == 'create') {
        final id = (call.arguments as Map<Object?, Object?>)['id'] as int;
        binaryMessenger.setMockMethodCallHandler(
          MethodChannel('cc.ugotit.elinkbook/pdf_reader_view_$id'),
          (call) async {
            instanceCalls.add(call);
            return null;
          },
        );
        return 0;
      }
      return null;
    });

    await tester.pumpWidget(MaterialApp(
      home: PdfReaderView(
        key: key,
        filePath: '/tmp/sample.pdf',
        onPageRendered: _noop,
        onError: _noopError,
      ),
    ));
    await tester.pumpAndSettle();

    PdfReaderView.refreshAnnotations(key, [
      PdfAnnotationDecoration.forHighlight(
        pageIndex: 1,
        rect: const PercentRect(left: 0, top: 0, right: 1, bottom: 0.1),
        tint: 0x73FDE047,
        isUnderline: false,
      ),
    ]);

    final call = instanceCalls.firstWhere((c) => c.method == 'refreshAnnotations');
    final annotations = call.arguments['annotations'] as List;
    expect(annotations.single['pageIndex'], 1);
    expect(annotations.single['isNoteOnly'], isFalse);
  });

  testWidgets(
      '長按拖曳觸發 beginAnnotationSelection／updateAnnotationSelection／endAnnotationSelection，'
      '座標為相對 widget 自身尺寸的百分比（審查修正 1.1：手勢辨識改由 Flutter 端主導）',
      (tester) async {
    final binaryMessenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    final instanceCalls = <MethodCall>[];

    binaryMessenger.setMockMethodCallHandler(SystemChannels.platform_views,
        (call) async {
      if (call.method == 'create') {
        final id = (call.arguments as Map<Object?, Object?>)['id'] as int;
        binaryMessenger.setMockMethodCallHandler(
          MethodChannel('cc.ugotit.elinkbook/pdf_reader_view_$id'),
          (call) async {
            instanceCalls.add(call);
            return null;
          },
        );
        return 0;
      }
      return null;
    });

    await tester.pumpWidget(MaterialApp(
      home: Center(
        child: SizedBox(
          width: 200,
          height: 100,
          child: PdfReaderView(
            filePath: '/tmp/sample.pdf',
            onPageRendered: _noop,
            onError: _noopError,
          ),
        ),
      ),
    ));
    await tester.pumpAndSettle();

    final topLeft = tester.getTopLeft(find.byType(PdfReaderView));
    final gesture = await tester.startGesture(topLeft + const Offset(20, 10));
    // 等待超過長按判定門檻（Flutter 預設 500ms），期間手指未移動，
    // GestureDetector 的 LongPressGestureRecognizer 應會勝出競技場。
    await tester.pump(const Duration(milliseconds: 700));
    await gesture.moveBy(const Offset(60, 30));
    await tester.pump();
    await gesture.up();
    await tester.pump();

    final begin =
        instanceCalls.firstWhere((c) => c.method == 'beginAnnotationSelection');
    expect((begin.arguments as Map)['xPct'] as double, closeTo(20 / 200, 0.02));
    expect((begin.arguments as Map)['yPct'] as double, closeTo(10 / 100, 0.02));

    final update = instanceCalls
        .firstWhere((c) => c.method == 'updateAnnotationSelection');
    expect((update.arguments as Map)['xPct'] as double, closeTo(80 / 200, 0.02));
    expect((update.arguments as Map)['yPct'] as double, closeTo(40 / 100, 0.02));

    expect(instanceCalls.any((c) => c.method == 'endAnnotationSelection'), isTrue);
  });

  testWidgets('第二指觸碰時觸發 cancelAnnotationSelection（審查修正 1.1：多指偵測改由 Dart 端負責）',
      (tester) async {
    final binaryMessenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    final instanceCalls = <MethodCall>[];

    binaryMessenger.setMockMethodCallHandler(SystemChannels.platform_views,
        (call) async {
      if (call.method == 'create') {
        final id = (call.arguments as Map<Object?, Object?>)['id'] as int;
        binaryMessenger.setMockMethodCallHandler(
          MethodChannel('cc.ugotit.elinkbook/pdf_reader_view_$id'),
          (call) async {
            instanceCalls.add(call);
            return null;
          },
        );
        return 0;
      }
      return null;
    });

    await tester.pumpWidget(MaterialApp(
      home: Center(
        child: SizedBox(
          width: 200,
          height: 100,
          child: PdfReaderView(
            filePath: '/tmp/sample.pdf',
            onPageRendered: _noop,
            onError: _noopError,
          ),
        ),
      ),
    ));
    await tester.pumpAndSettle();

    final topLeft = tester.getTopLeft(find.byType(PdfReaderView));
    final first = await tester.startGesture(topLeft + const Offset(20, 10));
    final second = await tester.startGesture(topLeft + const Offset(100, 60));
    await tester.pump();

    expect(instanceCalls.any((c) => c.method == 'cancelAnnotationSelection'), isTrue);

    await first.up();
    await second.up();
  });
```

- [x] **Step 2: 執行測試確認失敗**

Run: `flutter test test/reader/pdf_reader_view_test.dart`
Expected: FAIL（`onSelectionRectComputed`/`onSelectionCanceled` 建構參數、`refreshAnnotations` 靜態方法、`onLongPressStart`/`onLongPressMoveUpdate`/`onLongPressEnd`/`Listener` 觸控回呼皆尚不存在，編譯錯誤）

- [x] **Step 3: 擴充 `PdfReaderView`**

`app/lib/reader/pdf_reader_view.dart` 頂部新增 import：

```dart
import 'pdf_annotation_decoration.dart';
import 'pdf_selection_info.dart';
import 'percent_rect.dart';
```

`class PdfReaderView` 內，`onCropRectSelected` 欄位之後新增：

```dart
  /// 使用者長按拖曳框選劃線範圍完成時觸發（epic-6-annotations Issue 3，
  /// ADR 0008）。呼叫端負責顯示 `AnnotationToolbar` 供選色/畫底線/加備註。
  final ValueChanged<PdfSelectionInfo>? onSelectionRectComputed;

  /// 框選狀態被原生端取消時觸發（縮放/平移手勢開始、或觸發翻頁/跳頁，
  /// 見 plan-issue-3.md Global Constraints）。呼叫端負責收起浮動工具列。
  final VoidCallback? onSelectionCanceled;
```

建構子新增對應具名參數：

```dart
  const PdfReaderView({
    super.key,
    required this.filePath,
    required this.onPageRendered,
    required this.onError,
    this.onNextPage,
    this.onPreviousPage,
    this.onPageChanged,
    this.fitMode,
    this.contrast,
    this.brightness,
    this.boldStrength,
    this.cropMode,
    this.cropRect,
    this.onCropRectComputed,
    this.cropEditModeActive = false,
    this.onCropRectSelected,
    this.dualPageMode = DualPageMode.auto,
    this.dualPageCoverAlone = true,
    this.dualPageDirection = DualPageDirection.rtl,
    this.isLandscape = false,
    this.initialPageIndex,
    this.onSelectionRectComputed,
    this.onSelectionCanceled,
  });
```

`jumpToPage` 靜態方法之後（`class PdfReaderView` 結尾之前）新增：

```dart
  /// 把目前應顯示的完整標記清單一次性送給原生端（比照 EPUB
  /// `EpubReaderView.setDecorations` 整組送出慣例，非增量 diff），供原生
  /// 端重繪 Bitmap 快取上的劃線/備註疊加。呼叫時機：初次載入既有標記、
  /// 以及任何劃線/備註 CRUD 完成後。
  static void refreshAnnotations(
    GlobalKey<State<PdfReaderView>> key,
    List<PdfAnnotationDecoration> annotations,
  ) {
    final state = key.currentState;
    if (state is _PdfReaderViewState) {
      state._channel?.invokeMethod('refreshAnnotations', {
        'annotations': annotations.map((a) => a.toWire()).toList(),
      });
    }
  }
```

`_handleMethodCall` 的 `switch` 內，`case 'onCropRectSelected':` 分支之後新增：

```dart
      case 'onSelectionRectComputed':
        final args = call.arguments as Map<Object?, Object?>;
        widget.onSelectionRectComputed?.call(PdfSelectionInfo(
          pageIndex: args['pageIndex'] as int,
          rect: PercentRect(
            left: (args['left'] as num).toDouble(),
            top: (args['top'] as num).toDouble(),
            right: (args['right'] as num).toDouble(),
            bottom: (args['bottom'] as num).toDouble(),
          ),
        ));
        break;
      case 'onSelectionCanceled':
        widget.onSelectionCanceled?.call();
        break;
```

`_PdfReaderViewState` 內，`MethodChannel? _channel;` 之後新增兩個欄位：

```dart
  // 長按拖曳框選手勢的相對定位/多指偵測狀態（epic-6-annotations Issue 3；
  // 審查修正，見 plan-issue-3.md Global Constraints「長按/拖曳的手勢辨識
  // 改由 Flutter 端 GestureDetector 主導」）。
  Size? _lastMeasuredSize;
  int _activeAnnotationPointerCount = 0;
```

`build()` 方法整個改為：

```dart
  @override
  Widget build(BuildContext context) {
    return Listener(
      onPointerDown: _handleAnnotationPointerDown,
      onPointerUp: _handleAnnotationPointerUp,
      onPointerCancel: _handleAnnotationPointerUp,
      child: LayoutBuilder(
        builder: (context, constraints) {
          _lastMeasuredSize = constraints.biggest;
          return GestureDetector(
            onHorizontalDragEnd: (details) {
              if (details.primaryVelocity == null) return;
              if (details.primaryVelocity! < 0) {
                // 向左滑動 → 下一頁
                nextPage();
              } else if (details.primaryVelocity! > 0) {
                // 向右滑動 → 上一頁
                previousPage();
              }
            },
            onLongPressStart: _handleLongPressStart,
            onLongPressMoveUpdate: _handleLongPressMoveUpdate,
            onLongPressEnd: _handleLongPressEnd,
            child: AndroidView(
              viewType: 'cc.ugotit.elinkbook/pdf_reader_view',
              onPlatformViewCreated: _onPlatformViewCreated,
            ),
          );
        },
      ),
    );
  }

  /// 長按拖曳框選劃線範圍的手勢辨識（epic-6-annotations Issue 3，ADR
  /// 0008；審查修正 1.1）：與既有 `onHorizontalDragEnd` 掛在同一個
  /// `GestureDetector`，由 Flutter 的手勢競技場自行裁決「這根手指是要
  /// 長按還是要水平滑動翻頁」，原生端不再自己監聽 `rootView` 觸控、也不
  /// 需要猜測——這正是 Flutter 手勢框架設計來解決這種同一觸點多種可能
  /// 手勢的機制。三個回呼把觸點位置換算成相對本 widget 自身尺寸
  /// （[_lastMeasuredSize]，由外層 `LayoutBuilder` 提供）的百分比後送給
  /// 原生端；原生端收到後再自行換算為相對 bitmap 內容範圍的最終座標
  /// （見 plan-issue-3.md Global Constraints「PDF 座標協定」的兩段式
  /// 換算說明），本端不需要知道、也沒有管道取得 letterbox 換算所需的
  /// bitmap 實際像素尺寸。是否真的允許框選（`fitMode`／裁切/雙頁狀態）
  /// 一律交由原生端這個唯一權威來源判斷，本端無條件送出事件。
  void _handleLongPressStart(LongPressStartDetails details) {
    final size = _lastMeasuredSize;
    if (size == null || size.width <= 0 || size.height <= 0) return;
    _channel?.invokeMethod('beginAnnotationSelection', {
      'xPct': details.localPosition.dx / size.width,
      'yPct': details.localPosition.dy / size.height,
    });
  }

  void _handleLongPressMoveUpdate(LongPressMoveUpdateDetails details) {
    final size = _lastMeasuredSize;
    if (size == null || size.width <= 0 || size.height <= 0) return;
    _channel?.invokeMethod('updateAnnotationSelection', {
      'xPct': details.localPosition.dx / size.width,
      'yPct': details.localPosition.dy / size.height,
    });
  }

  void _handleLongPressEnd(LongPressEndDetails details) {
    _channel?.invokeMethod('endAnnotationSelection');
  }

  /// 多指偵測（design.md 決策 #15、spec.md 審查修正 1.3；審查修正 1.1
  /// 後改由 Dart 端負責，見 Global Constraints）：原生端不再持有觸控
  /// 序列，無法自行偵測第二指觸碰，改由本 widget 用 [Listener] 追蹤目前
  /// 螢幕上的觸點數，偵測到超過一指時通知原生端取消目前框選狀態。
  /// [_handleAnnotationPointerUp] 同時作為 `onPointerUp`／`onPointerCancel`
  /// 的處理函式（Dart 函式參數型別逆變允許以 `PointerEvent` 版本同時
  /// 賦值給 `PointerUpListener`／`PointerCancelListener` 兩種型別的參數，
  /// 不需要分別宣告兩份幾乎相同的方法）。
  void _handleAnnotationPointerDown(PointerDownEvent event) {
    _activeAnnotationPointerCount++;
    if (_activeAnnotationPointerCount > 1) {
      _channel?.invokeMethod('cancelAnnotationSelection');
    }
  }

  void _handleAnnotationPointerUp(PointerEvent event) {
    if (_activeAnnotationPointerCount > 0) _activeAnnotationPointerCount--;
  }
```

- [x] **Step 4: 執行測試確認通過**

Run: `flutter test test/reader/pdf_reader_view_test.dart`
Expected: PASS（含既有 Issue 1-4 相關測試不受影響）

- [x] **Step 5: 執行全專案測試 + `flutter analyze` 確認乾淨**

Run: `flutter test`
Expected: 全數 PASS

Run: `flutter analyze`
Expected: `No issues found!`

- [x] **Step 6: Commit**

```bash
git add app/lib/reader/pdf_reader_view.dart app/test/reader/pdf_reader_view_test.dart
git commit -m "feat(epic-6): PdfReaderView.dart 改由 Flutter GestureDetector 驅動長按框選手勢"
```

---

### Task 7：原生端共用座標數學 + `HighlightSelectionOverlayView` 繪製元件

**Files:**
- Modify: `app/android/app/src/main/kotlin/cc/ugotit/elinkbook/CropOverlayView.kt`
- Create: `app/android/app/src/main/kotlin/cc/ugotit/elinkbook/PdfContentBounds.kt`
- Create: `app/android/app/src/main/kotlin/cc/ugotit/elinkbook/HighlightSelectionOverlayView.kt`
- Test: `app/android/app/src/test/kotlin/cc/ugotit/elinkbook/PdfContentBoundsTest.kt`

**Interfaces:**
- Consumes: 無新增 Dart 型別依賴。
- Produces: 頂層函式 `computeFitCenterContentBounds(viewWidth, viewHeight, contentWidthPx, contentHeightPx): RectF`（`CropOverlayView`／`HighlightSelectionOverlayView` 共用）；`HighlightSelectionOverlayView`（`updateRect`/`currentRelativeRect`），供 Task 8（`PdfReaderView.kt` 框選狀態機）消費。

- [x] **Step 1: 抽出共用座標數學（`PdfContentBounds.kt`）**

建立 `app/android/app/src/main/kotlin/cc/ugotit/elinkbook/PdfContentBounds.kt`：

```kotlin
package cc.ugotit.elinkbook

import android.graphics.RectF

/**
 * FIT_CENTER letterbox 數學：內容依長寬比置中縮放至剛好完整顯示於容器內，
 * 多餘空間留白（epic-6-annotations Issue 3，抽出自
 * `CropOverlayView.computeContentBounds()`，供新增的
 * `HighlightSelectionOverlayView` 共用，見 plan-issue-3.md Task 7）。
 * [contentWidthPx]／[contentHeightPx] 是目前顯示中內容（PDF 頁面渲染出的
 * bitmap，可能已反映裁切狀態）的像素尺寸；回傳值是該內容在
 * `viewWidth`×`viewHeight` 容器內的實際顯示範圍。
 */
internal fun computeFitCenterContentBounds(
    viewWidth: Int,
    viewHeight: Int,
    contentWidthPx: Int,
    contentHeightPx: Int,
): RectF {
    if (viewWidth <= 0 || viewHeight <= 0 || contentWidthPx <= 0 || contentHeightPx <= 0) {
        return RectF(0f, 0f, viewWidth.toFloat(), viewHeight.toFloat())
    }
    val viewRatio = viewWidth.toFloat() / viewHeight.toFloat()
    val contentRatio = contentWidthPx.toFloat() / contentHeightPx.toFloat()
    return if (contentRatio > viewRatio) {
        // 內容較「寬」：滿版寬度，上下留白
        val displayHeight = viewWidth / contentRatio
        val top = (viewHeight - displayHeight) / 2f
        RectF(0f, top, viewWidth.toFloat(), top + displayHeight)
    } else {
        // 內容較「高」：滿版高度，左右留白
        val displayWidth = viewHeight * contentRatio
        val left = (viewWidth - displayWidth) / 2f
        RectF(left, 0f, left + displayWidth, viewHeight.toFloat())
    }
}
```

- [x] **Step 2: 寫 JVM 單元測試（`PdfContentBoundsTest.kt`）**

建立 `app/android/app/src/test/kotlin/cc/ugotit/elinkbook/PdfContentBoundsTest.kt`：

```kotlin
package cc.ugotit.elinkbook

import org.junit.Assert.assertEquals
import org.junit.Test

class PdfContentBoundsTest {

    @Test
    fun `內容比容器寬時，上下留白、滿版寬度`() {
        val bounds = computeFitCenterContentBounds(
            viewWidth = 200, viewHeight = 200, contentWidthPx = 400, contentHeightPx = 100,
        )
        // displayHeight = viewWidth / contentRatio = 200 / 4 = 50；
        // top = (viewHeight - displayHeight) / 2 = (200 - 50) / 2 = 75（審查修正：
        // 原始期望值 50f/100f 算式有誤，見 Task 7 實作報告）。
        assertEquals(0f, bounds.left)
        assertEquals(200f, bounds.right)
        assertEquals(75f, bounds.top)
        assertEquals(125f, bounds.bottom)
    }

    @Test
    fun `內容比容器高時，左右留白、滿版高度`() {
        val bounds = computeFitCenterContentBounds(
            viewWidth = 200, viewHeight = 200, contentWidthPx = 100, contentHeightPx = 400,
        )
        // displayWidth = viewHeight * contentRatio = 200 * 0.25 = 50；
        // left = (viewWidth - displayWidth) / 2 = (200 - 50) / 2 = 75（審查修正：
        // 原始期望值 50f/150f 算式有誤，見 Task 7 實作報告）。
        assertEquals(75f, bounds.left)
        assertEquals(125f, bounds.right)
        assertEquals(0f, bounds.top)
        assertEquals(200f, bounds.bottom)
    }

    @Test
    fun `容器或內容尺寸為 0 時，退回整個容器範圍（避免除以零）`() {
        val bounds = computeFitCenterContentBounds(
            viewWidth = 200, viewHeight = 100, contentWidthPx = 0, contentHeightPx = 0,
        )
        assertEquals(0f, bounds.left)
        assertEquals(0f, bounds.top)
        assertEquals(200f, bounds.right)
        assertEquals(100f, bounds.bottom)
    }
}
```

Run: `cd app/android && ./gradlew testDebugUnitTest --tests "cc.ugotit.elinkbook.PdfContentBoundsTest"`
Expected: PASS（一次到位，無紅燈階段——本 Step 目的是為 Step 1 已抽出的純函式立即補上驗證，比照本檔案既有 `isDualPageEnabled` 等純函式的測試風格）

- [x] **Step 3: `CropOverlayView.kt` 改用共用函式（避免程式碼重複）**

`app/android/app/src/main/kotlin/cc/ugotit/elinkbook/CropOverlayView.kt` 的 `computeContentBounds` 方法整段改為：

```kotlin
    /**
     * FIT_CENTER letterbox 數學：委派給共用函式
     * [computeFitCenterContentBounds]（epic-6-annotations Issue 3 抽出，見
     * `PdfContentBounds.kt`），本類別不再自行重複實作同一段數學。
     */
    private fun computeContentBounds(viewWidth: Int, viewHeight: Int): RectF =
        computeFitCenterContentBounds(viewWidth, viewHeight, pageWidthPx, pageHeightPx)
```

Run: `cd app/android && ./gradlew testDebugUnitTest`
Expected: BUILD SUCCESSFUL（既有 Kotlin 單元測試不受影響——本次是純委派重構，行為不變）

- [x] **Step 4: 實作 `HighlightSelectionOverlayView`**

建立 `app/android/app/src/main/kotlin/cc/ugotit/elinkbook/HighlightSelectionOverlayView.kt`：

```kotlin
package cc.ugotit.elinkbook

import android.content.Context
import android.graphics.Canvas
import android.graphics.Color
import android.graphics.Paint
import android.graphics.PointF
import android.graphics.RectF
import android.view.View

/**
 * 長按拖曳框選劃線範圍時的視覺回饋疊加層（epic-6-annotations Issue 3，
 * ADR 0008：長按直接觸發，不比照 `CropOverlayView` 的「先進入模式」既有
 * 慣例）。純粹負責繪製目前框選矩形，**完全不處理觸控事件**——長按/拖曳
 * 的辨識由 Flutter 端 `PdfReaderView.dart` 的 `GestureDetector` 主導，
 * 本疊加層只在原生端收到 Dart 送來的 `beginAnnotationSelection`／
 * `updateAnnotationSelection` method call 時才被建立/更新（見
 * plan-issue-3.md Task 8，審查修正 1.1：原生端不再自行監聽 `rootView`
 * 觸控，也就不存在「疊加層何時才被加入畫面、能否收到原始觸控序列」的
 * 問題——本類別的職責單純只是「畫出目前的矩形」，狀態從何而來與本類別
 * 無關）。
 *
 * [contentWidthPx]／[contentHeightPx] 為目前顯示中 bitmap 的像素尺寸
 * （呼叫端傳入 `imageView.drawable` 的 intrinsic 尺寸，已反映目前生效的
 * 裁切狀態，見 plan-issue-3.md Global Constraints「長按框選僅支援
 * PAGE_FIT」），用於計算 FIT_CENTER letterbox 後內容在本 View 內的實際
 * 顯示範圍 [contentBounds]。
 */
class HighlightSelectionOverlayView(
    context: Context,
    private val contentWidthPx: Int,
    private val contentHeightPx: Int,
) : View(context) {

    private val density = context.resources.displayMetrics.density
    private val fillPaint = Paint().apply {
        color = Color.argb(90, 255, 213, 79)
        style = Paint.Style.FILL
    }
    private val borderPaint = Paint().apply {
        color = Color.argb(220, 255, 179, 0)
        style = Paint.Style.STROKE
        strokeWidth = 2f * density
    }

    private var contentBounds = RectF()
    private var rectPx = RectF()

    override fun onSizeChanged(w: Int, h: Int, oldw: Int, oldh: Int) {
        super.onSizeChanged(w, h, oldw, oldh)
        contentBounds = computeFitCenterContentBounds(w, h, contentWidthPx, contentHeightPx)
    }

    /**
     * 由 `PdfReaderView` 收到 Dart 端 `beginAnnotationSelection`／
     * `updateAnnotationSelection` method call 後，依目前 anchor（長按
     * 起點）／drag（目前觸點）座標呼叫，皆為 View 像素座標。矩形永遠
     * clamp 在 [contentBounds] 內（不允許框選延伸到 letterbox 留白區域）。
     */
    fun updateRect(anchorPx: PointF, currentPx: PointF) {
        if (contentBounds.width() <= 0f || contentBounds.height() <= 0f) return
        val left = minOf(anchorPx.x, currentPx.x).coerceIn(contentBounds.left, contentBounds.right)
        val right = maxOf(anchorPx.x, currentPx.x).coerceIn(contentBounds.left, contentBounds.right)
        val top = minOf(anchorPx.y, currentPx.y).coerceIn(contentBounds.top, contentBounds.bottom)
        val bottom = maxOf(anchorPx.y, currentPx.y).coerceIn(contentBounds.top, contentBounds.bottom)
        rectPx = RectF(left, top, right, bottom)
        invalidate()
    }

    override fun onDraw(canvas: Canvas) {
        super.onDraw(canvas)
        canvas.drawRect(rectPx, fillPaint)
        canvas.drawRect(rectPx, borderPaint)
    }

    /**
     * 換算目前框選矩形為相對 [contentBounds] 的百分比值（0.0-1.0），供
     * `PdfReaderView` 送給 Dart 端（見 spec.md 座標協定）。[contentBounds]
     * 尚未量測完成（極早期 layout 尚未跑過 `onSizeChanged`）時回傳全零矩形，
     * 呼叫端須視為退化案例（見 Task 8 `finishHighlightSelection` 的最小
     * 尺寸檢查，全零矩形必然小於門檻、會被當成取消處理）。
     *
     * 【審查修正】回傳型別必須是 `internal fun`，不能是 `public`（Kotlin
     * 編譯錯誤：public 函式不可暴露 internal 型別 `PercentRectPx`）——
     * 本函式僅供同模組 Task 8 的 `PdfReaderView.kt` 消費，符合其實際使用
     * 範圍，見 Task 7 實作報告。
     */
    internal fun currentRelativeRect(): PercentRectPx {
        if (contentBounds.width() <= 0f || contentBounds.height() <= 0f) {
            return PercentRectPx(0f, 0f, 0f, 0f)
        }
        return PercentRectPx(
            left = (rectPx.left - contentBounds.left) / contentBounds.width(),
            top = (rectPx.top - contentBounds.top) / contentBounds.height(),
            right = (rectPx.right - contentBounds.left) / contentBounds.width(),
            bottom = (rectPx.bottom - contentBounds.top) / contentBounds.height(),
        )
    }
}

/** 原生端內部使用的百分比矩形值物件（0.0-1.0），對應 Dart `PercentRect`。*/
internal data class PercentRectPx(val left: Float, val top: Float, val right: Float, val bottom: Float)
```

- [x] **Step 5: 編譯驗證**

Run: `cd app && flutter build apk --debug`
Expected: 建置成功（Kotlin 編譯通過）

- [x] **Step 6: 執行 `flutter analyze` 確認 Dart 端未受影響**

Run: `flutter analyze`
Expected: `No issues found!`

- [x] **Step 7: Commit**

```bash
git add app/android/app/src/main/kotlin/cc/ugotit/elinkbook/CropOverlayView.kt app/android/app/src/main/kotlin/cc/ugotit/elinkbook/PdfContentBounds.kt app/android/app/src/main/kotlin/cc/ugotit/elinkbook/HighlightSelectionOverlayView.kt app/android/app/src/test/kotlin/cc/ugotit/elinkbook/PdfContentBoundsTest.kt
git commit -m "feat(epic-6): 抽出共用 letterbox 座標函式並新增 HighlightSelectionOverlayView"
```

---

### Task 8：`PdfReaderView.kt` 接收 Dart 端手勢事件的框選狀態機 + 取消機制

**Files:**
- Modify: `app/android/app/src/main/kotlin/cc/ugotit/elinkbook/PdfReaderView.kt`
- Modify: `app/android/app/src/test/kotlin/cc/ugotit/elinkbook/PdfReaderViewTest.kt`

**Interfaces:**
- Consumes: Task 6 的 Dart 端 outgoing method call（`beginAnnotationSelection`／`updateAnnotationSelection`／`endAnnotationSelection`／`cancelAnnotationSelection`）；Task 7 的 `HighlightSelectionOverlayView`。
- Produces: `isAnnotationSelectionEligible` 純函式（`internal`，JVM 單元測試涵蓋，比照 `isDualPageEnabled` 既有先例）；原生端狀態機透過 `channel` 送出 `onSelectionRectComputed`／`onSelectionCanceled`（Task 6 已定義的 Dart 端 incoming 端點），供 Task 9 沿用同一組 `highlightSelectionOverlayView`／`highlightAnchor`／`highlightSelectionActive` 欄位。**審查修正（Task 8 實作發現，見 Task 8 實作報告）**：`pageAnnotations: List<PdfAnnotationOverlay>` 欄位**不**在本 Task 宣告——`PdfAnnotationOverlay` 型別要到 Task 9 Step 3 才定義，若本 Task 提前宣告會因前向參照未定義型別而編譯失敗，與本 Task 自身 Step 8/9（`flutter build apk --debug`／`./gradlew testDebugUnitTest` 皆須成功）互相矛盾。`pageAnnotations` 欄位改移入 Task 9（與 `PdfAnnotationOverlay` 型別同一 Task 一併宣告，見 Task 9 Step 3 之前新增的欄位宣告步驟），Task 8 本身只新增 `highlightSelectionOverlayView`／`highlightAnchor`／`highlightSelectionActive` 三個欄位。

**審查修正說明（見 `tmp/epic-6/reviews/plan_issue_3_review.md` 1.1）**：原設計由原生端 `rootView.setOnTouchListener` 自建 `Handler`+`ViewConfiguration` 長按計時器、對 `ACTION_DOWN` 無條件回傳 `true` 攔截整個觸控序列。這會讓原生端在使用者每一次觸碰螢幕時都搶先宣告獨佔該次觸控，導致 Flutter 端既有的水平滑動翻頁手勢（`onHorizontalDragEnd`）完全收不到事件、在一般閱讀情境下失效——這不是機率性的真機風險，而是必然發生的行為。而「長按觸發前回傳 false、觸發後才回傳 true」在 Android 的觸控分派模型下也不可行：`View` 若在 `ACTION_DOWN` 當下放棄該序列（回傳 `false`），後續同一序列的 `ACTION_MOVE`/`ACTION_UP` 便不會再送達，等長按計時器事後觸發時已經沒有辦法收集拖曳/放開的事件了。因此本 Task 改為完全移除原生端的觸控監聽/長按計時邏輯，長按與拖曳的辨識改由 Task 6 的 Flutter 端 `GestureDetector` 主導，原生端只被動接收 Dart 送來的四個 method call，語意與原本的觸控狀態機一一對應（`beginAnnotationSelection` ≈ 原長按計時器觸發、`updateAnnotationSelection` ≈ 原 `ACTION_MOVE`、`endAnnotationSelection` ≈ 原 `ACTION_UP`、`cancelAnnotationSelection` ≈ 原 `ACTION_POINTER_DOWN`/`ACTION_CANCEL`），`beginHighlightSelection`／`finishHighlightSelection`／`cancelHighlightSelection`／`removeHighlightSelectionOverlay` 這幾個核心方法的內部邏輯不變，只是觸發來源從觸控事件改為 method call。

- [x] **Step 1: 新增 import**

`app/android/app/src/main/kotlin/cc/ugotit/elinkbook/PdfReaderView.kt` 頂部新增：

```kotlin
import android.graphics.PointF
```

- [x] **Step 2: 新增狀態機欄位**

於 `cropOverlayView` 欄位之後新增：

```kotlin
    // 長按拖曳框選劃線範圍的狀態（epic-6-annotations Issue 3，ADR
    // 0008）。與 cropOverlayView／cropEditModeActive 刻意獨立——劃線框選
    // 不是「先進入模式」，而是 Dart 端 GestureDetector 判定長按後隨時可能
    // 觸發（見審查修正 1.1：觸發時機/獨佔判斷改由 Dart 端 GestureDetector
    // 負責，原生端不再自行監聽 rootView 觸控）。
    private var highlightSelectionOverlayView: HighlightSelectionOverlayView? = null
    private var highlightAnchor: PointF? = null
    private var highlightSelectionActive: Boolean = false
```

**審查修正**：本 Step 刻意不宣告 `pageAnnotations: List<PdfAnnotationOverlay>` 欄位——`PdfAnnotationOverlay` 型別要到 Task 9 Step 3 才定義，本 Task 提前宣告會因前向參照未定義型別而編譯失敗（見上方 Interfaces 段落審查修正說明）。`pageAnnotations` 欄位改於 Task 9 與 `PdfAnnotationOverlay` 型別同時宣告。

- [x] **Step 3: 於 `companion object` 新增 `isAnnotationSelectionEligible` 純函式**

於 `companion object` 內（`previousPageStep` 之後）新增：

```kotlin
        /**
         * 目前狀態是否允許開始長按框選劃線範圍（epic-6-annotations
         * Issue 3，plan-issue-3.md Global Constraints「長按框選僅支援
         * PAGE_FIT」）：裁切編輯模式中、非 PAGE_FIT 顯示模式、或雙頁模式
         * 生效中皆不允許——這三項條件的判斷收斂在原生端這個唯一權威來源，
         * Dart 端（Task 6）無條件送出手勢事件，不重複判斷，避免兩端狀態
         * 不同步。抽成 `internal` 純函式，可脫離真機直接以 JVM 單元測試
         * 涵蓋，比照 `isDualPageEnabled` 既有先例。
         */
        internal fun isAnnotationSelectionEligible(
            fitMode: PdfFitMode,
            dualPageEnabled: Boolean,
            cropEditModeActive: Boolean,
        ): Boolean {
            return !cropEditModeActive && fitMode == PdfFitMode.PAGE_FIT && !dualPageEnabled
        }
```

- [x] **Step 4: 寫失敗測試（`isAnnotationSelectionEligible`，擴充 `PdfReaderViewTest.kt`）**

於 `app/android/app/src/test/kotlin/cc/ugotit/elinkbook/PdfReaderViewTest.kt` 檔案結尾（最後一個 `}` 之前）新增：

```kotlin
    // ---- isAnnotationSelectionEligible（epic-6-annotations Issue 3）----

    @Test
    fun `isAnnotationSelectionEligible PAGE_FIT、非裁切、非雙頁時允許框選`() {
        val eligible = PdfReaderView.isAnnotationSelectionEligible(
            fitMode = PdfReaderView.PdfFitMode.PAGE_FIT,
            dualPageEnabled = false,
            cropEditModeActive = false,
        )
        assertEquals(true, eligible)
    }

    @Test
    fun `isAnnotationSelectionEligible 非 PAGE_FIT 時不允許框選`() {
        val eligible = PdfReaderView.isAnnotationSelectionEligible(
            fitMode = PdfReaderView.PdfFitMode.FIT_WIDTH,
            dualPageEnabled = false,
            cropEditModeActive = false,
        )
        assertEquals(false, eligible)
    }

    @Test
    fun `isAnnotationSelectionEligible 雙頁模式生效時不允許框選`() {
        val eligible = PdfReaderView.isAnnotationSelectionEligible(
            fitMode = PdfReaderView.PdfFitMode.PAGE_FIT,
            dualPageEnabled = true,
            cropEditModeActive = false,
        )
        assertEquals(false, eligible)
    }

    @Test
    fun `isAnnotationSelectionEligible 裁切編輯模式中不允許框選`() {
        val eligible = PdfReaderView.isAnnotationSelectionEligible(
            fitMode = PdfReaderView.PdfFitMode.PAGE_FIT,
            dualPageEnabled = false,
            cropEditModeActive = true,
        )
        assertEquals(false, eligible)
    }
```

Run: `cd app/android && ./gradlew testDebugUnitTest --tests "cc.ugotit.elinkbook.PdfReaderViewTest"`
Expected: FAIL（`isAnnotationSelectionEligible` 尚不存在，編譯錯誤）

- [x] **Step 5: 執行測試確認通過**

Run: `cd app/android && ./gradlew testDebugUnitTest --tests "cc.ugotit.elinkbook.PdfReaderViewTest"`
Expected: PASS（含既有 `isDualPageEnabled` 等測試不受影響）

- [x] **Step 6: 新增 `onMethodCall` 分支與狀態機方法**

`onMethodCall` 的 `when (call.method)` 內，`"exitCropEditMode" -> { ... }` 分支之後新增：

```kotlin
            "beginAnnotationSelection" -> {
                val xPct = (call.argument<Number>("xPct"))?.toFloat()
                val yPct = (call.argument<Number>("yPct"))?.toFloat()
                if (xPct != null && yPct != null) handleBeginAnnotationSelection(xPct, yPct)
                result.success(null)
            }
            "updateAnnotationSelection" -> {
                val xPct = (call.argument<Number>("xPct"))?.toFloat()
                val yPct = (call.argument<Number>("yPct"))?.toFloat()
                if (xPct != null && yPct != null) handleUpdateAnnotationSelection(xPct, yPct)
                result.success(null)
            }
            "endAnnotationSelection" -> {
                finishHighlightSelection()
                result.success(null)
            }
            "cancelAnnotationSelection" -> {
                cancelHighlightSelection()
                result.success(null)
            }
```

在 `exitCropEditMode()` 方法之後新增：

```kotlin
    /**
     * Dart 端 `GestureDetector.onLongPressStart` 觸發時呼叫（
     * epic-6-annotations Issue 3，審查修正 1.1）。[xPct]／[yPct] 為相對
     * `PdfReaderView` widget 自身尺寸的百分比（Task 6），本函式先確認
     * 目前狀態允許框選（[isAnnotationSelectionEligible]），再換算成
     * `rootView` 目前量測到的像素座標，交給 [beginHighlightSelection]。
     */
    private fun handleBeginAnnotationSelection(xPct: Float, yPct: Float) {
        if (!isAnnotationSelectionEligible(fitMode, dualPageEnabled, cropEditModeActive)) return
        beginHighlightSelection(xPct * rootView.width, yPct * rootView.height)
    }

    /** Dart 端 `GestureDetector.onLongPressMoveUpdate` 觸發時呼叫，換算
     * 方式同 [handleBeginAnnotationSelection]；框選未進行中時靜默忽略
     * （例如上一次 [handleBeginAnnotationSelection] 因不符資格而未建立
     * 疊加層）。*/
    private fun handleUpdateAnnotationSelection(xPct: Float, yPct: Float) {
        val anchor = highlightAnchor ?: return
        highlightSelectionOverlayView?.updateRect(
            anchor,
            PointF(xPct * rootView.width, yPct * rootView.height),
        )
    }

    /** 建立疊加層並開始追蹤拖曳矩形。*/
    private fun beginHighlightSelection(x: Float, y: Float) {
        val bitmapWidth = imageView.drawable?.intrinsicWidth ?: return
        val bitmapHeight = imageView.drawable?.intrinsicHeight ?: return
        val anchor = PointF(x, y)
        highlightAnchor = anchor
        highlightSelectionActive = true
        val overlay = HighlightSelectionOverlayView(context, bitmapWidth, bitmapHeight)
        highlightSelectionOverlayView = overlay
        rootView.addView(
            overlay,
            FrameLayout.LayoutParams(FrameLayout.LayoutParams.MATCH_PARENT, FrameLayout.LayoutParams.MATCH_PARENT),
        )
        overlay.updateRect(anchor, anchor)
    }

    /**
     * Dart 端 `GestureDetector.onLongPressEnd` 觸發時呼叫：換算目前框選
     * 矩形為百分比值回報 Dart 端。矩形太小（例如長按後幾乎未拖曳就放開）
     * 視為使用者放棄，等同取消，不建立退化的零面積劃線。框選未進行中時
     * （[highlightSelectionOverlayView] 為 null）靜默忽略。
     */
    private fun finishHighlightSelection() {
        val relative = highlightSelectionOverlayView?.currentRelativeRect()
        val pageIndex = currentPageIndex
        removeHighlightSelectionOverlay()
        if (relative == null) return
        val minFraction = 0.01f
        if ((relative.right - relative.left) < minFraction || (relative.bottom - relative.top) < minFraction) {
            channel.invokeMethod("onSelectionCanceled", null)
            return
        }
        channel.invokeMethod(
            "onSelectionRectComputed",
            mapOf(
                "pageIndex" to pageIndex,
                "left" to relative.left.toDouble(),
                "top" to relative.top.toDouble(),
                "right" to relative.right.toDouble(),
                "bottom" to relative.bottom.toDouble(),
            ),
        )
    }

    /** Dart 端偵測到第二指觸碰（`cancelAnnotationSelection`）、或收到
     * 翻頁/跳頁指令時呼叫（呼叫點見下方 Step 7 於 nextPage()／
     * previousPage()／jumpToPage() 開頭新增的呼叫）。*/
    private fun cancelHighlightSelection() {
        if (highlightSelectionActive) {
            removeHighlightSelectionOverlay()
            channel.invokeMethod("onSelectionCanceled", null)
        }
    }

    private fun removeHighlightSelectionOverlay() {
        highlightSelectionOverlayView?.let { rootView.removeView(it) }
        highlightSelectionOverlayView = null
        highlightAnchor = null
        highlightSelectionActive = false
    }
```

- [x] **Step 7: 於 `nextPage`／`previousPage`／`jumpToPage` 新增取消呼叫、`dispose()` 清理疊加層**

三個換頁方法開頭（`if (cropEditModeActive) return` 之前）各自新增 `cancelHighlightSelection()`（此為新增，非既有程式碼——`nextPage()`/`previousPage()`/`jumpToPage()` 本身是本檔案既有方法，但呼叫 `cancelHighlightSelection()` 這一行是本 Task 才新增的行為，語意對應 spec.md 審查修正 1.3「縮放/平移手勢開始、或收到翻頁/跳頁指令時取消目前框選狀態」）：

```kotlin
    private fun nextPage() {
        cancelHighlightSelection()
        if (cropEditModeActive) return
        val step = nextPageStep(currentPageIndex, dualPageEnabled, dualPageCoverAlone)
        val newIndex = currentPageIndex + step
        if (newIndex < totalPages) {
            currentPageIndex = newIndex
            renderCurrentSpread()
            notifyPageChanged()
        }
    }

    private fun previousPage() {
        cancelHighlightSelection()
        if (cropEditModeActive) return
        val step = previousPageStep(currentPageIndex, dualPageEnabled, dualPageCoverAlone)
        val newIndex = currentPageIndex - step
        if (newIndex >= 0) {
            currentPageIndex = newIndex
            renderCurrentSpread()
            notifyPageChanged()
        }
    }

    private fun jumpToPage(pageIndex: Int) {
        cancelHighlightSelection()
        if (cropEditModeActive) return
        if (pageIndex !in 0 until totalPages) return
        if (pageIndex == currentPageIndex) return
        currentPageIndex = pageIndex
        renderCurrentSpread()
        notifyPageChanged()
    }
```

`dispose()` 內、`cropOverlayView?.let { rootView.removeView(it) }` 之前新增一行：

```kotlin
        removeHighlightSelectionOverlay()
```

- [x] **Step 8: 編譯驗證**

Run: `cd app && flutter build apk --debug`
Expected: 建置成功

- [x] **Step 9: 執行既有 Kotlin 單元測試確認無回歸**

Run: `cd app/android && ./gradlew testDebugUnitTest`
Expected: BUILD SUCCESSFUL（`PdfReaderViewTest`／`PdfContentBoundsTest` 皆通過；`PdfAnnotationOverlayTest` 待 Task 9 建立後才存在，本 Task 尚未執行到不影響）

- [x] **Step 10: 執行 `flutter analyze` 確認 Dart 端未受影響**

Run: `flutter analyze`
Expected: `No issues found!`

- [x] **Step 11: Commit**

```bash
git add app/android/app/src/main/kotlin/cc/ugotit/elinkbook/PdfReaderView.kt app/android/app/src/test/kotlin/cc/ugotit/elinkbook/PdfReaderViewTest.kt
git commit -m "feat(epic-6): PdfReaderView.kt 改為接收 Dart 端手勢事件驅動框選狀態機"
```

---

### Task 9：`refreshAnnotations` 原生端處理 + Bitmap 疊加渲染

**Files:**
- Modify: `app/android/app/src/main/kotlin/cc/ugotit/elinkbook/PdfReaderView.kt`
- Test: `app/android/app/src/test/kotlin/cc/ugotit/elinkbook/PdfAnnotationOverlayTest.kt`

**Interfaces:**
- Consumes: Task 6 的 Dart 端 `refreshAnnotations` wire 格式（見 `PdfAnnotationDecoration.toWire()`）。
- Produces: `PdfAnnotationOverlay`（`internal data class`，`parsePdfAnnotationOverlays` 純函式可獨立單元測試）；原生端於 `renderPageBitmap()` 疊加繪製劃線/底線/純備註三種樣式。

- [x] **Step 1: 寫失敗測試（`PdfAnnotationOverlayTest.kt`）**

建立 `app/android/app/src/test/kotlin/cc/ugotit/elinkbook/PdfAnnotationOverlayTest.kt`：

```kotlin
package cc.ugotit.elinkbook

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

class PdfAnnotationOverlayTest {

    // 【審查修正，Task 9 實作發現】parsePdfAnnotationOverlays 宣告於
    // PdfReaderView 的 companion object 內，從外部類別呼叫時必須加上
    // `PdfReaderView.` 前綴（Kotlin 不會自動把 companion object 成員
    // 帶入其他檔案的呼叫範圍），比照本檔案既有 isDualPageEnabled／
    // pairIndices 等測試呼叫的既有慣例。

    @Test
    fun `正確解析完整欄位的單筆標記`() {
        val list = PdfReaderView.parsePdfAnnotationOverlays(listOf(
            mapOf(
                "pageIndex" to 3,
                "left" to 0.1,
                "top" to 0.2,
                "right" to 0.3,
                "bottom" to 0.4,
                "tint" to 0x73FDE047,
                "isUnderline" to false,
                "isNoteOnly" to false,
            ),
        ))
        assertEquals(1, list.size)
        assertEquals(3, list.single().pageIndex)
        assertEquals(0x73FDE047, list.single().tint)
    }

    @Test
    fun `缺少必要數值欄位的項目略過、不影響其餘項目`() {
        val list = PdfReaderView.parsePdfAnnotationOverlays(listOf(
            mapOf("pageIndex" to 1, "left" to 0.0, "top" to 0.0, "right" to 1.0), // 缺 bottom/tint
            mapOf(
                "pageIndex" to 2, "left" to 0.0, "top" to 0.0, "right" to 1.0, "bottom" to 1.0,
                "tint" to 0x73D1D5DB,
            ),
        ))
        assertEquals(1, list.size)
        assertEquals(2, list.single().pageIndex)
    }

    @Test
    fun `isUnderline／isNoteOnly 缺席時預設為 false`() {
        val list = PdfReaderView.parsePdfAnnotationOverlays(listOf(
            mapOf(
                "pageIndex" to 0, "left" to 0.0, "top" to 0.0, "right" to 1.0, "bottom" to 1.0,
                "tint" to 1,
            ),
        ))
        assertTrue(!list.single().isUnderline)
        assertTrue(!list.single().isNoteOnly)
    }
}
```

- [x] **Step 2: 執行測試確認失敗**

Run: `cd app/android && ./gradlew testDebugUnitTest --tests "cc.ugotit.elinkbook.PdfAnnotationOverlayTest"`
Expected: FAIL（`PdfAnnotationOverlay`/`parsePdfAnnotationOverlays` 尚不存在，編譯錯誤）

- [x] **Step 3: 實作 `PdfAnnotationOverlay` 與解析函式**

`app/android/app/src/main/kotlin/cc/ugotit/elinkbook/PdfReaderView.kt` 的 `companion object` 內（`previousPageStep` 之後）新增：

```kotlin
        /**
         * 原生端內部使用的單筆標記疊加資料（epic-6-annotations Issue 3）。
         * 對應 Dart `PdfAnnotationDecoration.toWire()`。
         */
        internal data class PdfAnnotationOverlay(
            val pageIndex: Int,
            val left: Float,
            val top: Float,
            val right: Float,
            val bottom: Float,
            val tint: Int,
            val isUnderline: Boolean,
            val isNoteOnly: Boolean,
        )

        /**
         * 解析 Dart 端 `refreshAnnotations` 送來的標記清單。單筆缺少必要
         * 數值欄位時該筆略過，不影響其餘項目解析（比照本檔案既有
         * `parseCropRect` 對非致命錯誤的處理原則）。抽成 `internal` 純
         * 函式，可脫離真機直接以 JVM 單元測試涵蓋（比照
         * `isDualPageEnabled` 等既有先例）。
         */
        internal fun parsePdfAnnotationOverlays(list: List<Map<String, Any?>>): List<PdfAnnotationOverlay> {
            return list.mapNotNull { entry ->
                val pageIndex = entry["pageIndex"] as? Int ?: return@mapNotNull null
                val left = (entry["left"] as? Number)?.toFloat() ?: return@mapNotNull null
                val top = (entry["top"] as? Number)?.toFloat() ?: return@mapNotNull null
                val right = (entry["right"] as? Number)?.toFloat() ?: return@mapNotNull null
                val bottom = (entry["bottom"] as? Number)?.toFloat() ?: return@mapNotNull null
                val tint = (entry["tint"] as? Number)?.toInt() ?: return@mapNotNull null
                val isUnderline = entry["isUnderline"] as? Boolean ?: false
                val isNoteOnly = entry["isNoteOnly"] as? Boolean ?: false
                PdfAnnotationOverlay(pageIndex, left, top, right, bottom, tint, isUnderline, isNoteOnly)
            }
        }
```

**審查修正（原規劃在 Task 8 宣告本欄位，Task 8 實作時發現會前向參照尚未定義的 `PdfAnnotationOverlay` 型別而編譯失敗，改移至此處與型別同時宣告，見 Task 8 實作報告）**：於 `cropOverlayView` 欄位之後（Task 8 已新增的 `highlightSelectionOverlayView`／`highlightAnchor`／`highlightSelectionActive` 三個欄位之後）新增：

```kotlin
    // Dart 端送來的目前應顯示標記清單（Issue 3 `refreshAnnotations`），
    // 依 pageIndex 分組供 renderPageBitmap() 逐頁疊加繪製。
    private var pageAnnotations: List<PdfAnnotationOverlay> = emptyList()
```

- [x] **Step 4: 執行測試確認通過**

Run: `cd app/android && ./gradlew testDebugUnitTest --tests "cc.ugotit.elinkbook.PdfAnnotationOverlayTest"`
Expected: PASS

- [x] **Step 5: 於 `onMethodCall` 新增 `refreshAnnotations` 分支**

`onMethodCall` 的 `when (call.method)` 內，`"exitCropEditMode" -> { ... }` 分支之後新增：

```kotlin
            "refreshAnnotations" -> {
                @Suppress("UNCHECKED_CAST")
                val list = call.argument<List<Map<String, Any?>>>("annotations") ?: emptyList()
                pageAnnotations = parsePdfAnnotationOverlays(list)
                renderCurrentSpread()
                result.success(null)
            }
```

- [x] **Step 6: 於 `renderPageBitmap` 疊加繪製標記**

`renderPageBitmap(pageIndex: Int): Bitmap` 方法內，`page.render(bitmap, null, matrix, PdfRenderer.Page.RENDER_MODE_FOR_DISPLAY)` 之後、`return bitmap` 之前新增（`scale` 為該方法內既有的區域變數，緊接在 `page.render(...)` 之前已計算好，直接沿用，不重複計算）：

```kotlin
            drawAnnotationOverlays(bitmap, pageIndex, scale)
```

在 `renderPageBitmap` 方法之後新增：

```kotlin
    /**
     * 於 [bitmap] 上疊加繪製 [pageIndex] 這一頁的所有劃線/備註（
     * epic-6-annotations Issue 3）。刻意放在 `renderPageBitmap()` 內、單頁
     * 內容渲染完成後立即繪製（而非等拼接/加粗/fit/濾鏡都套用完才疊加）：
     * (a) 雙頁模式下左右頁各自呼叫本函式一次，天然正確疊加、不需處理拼接
     * 後的座標換算；(b) 旋轉/裁切/版面調整觸發的重新渲染會自動重跑整個
     * pipeline、連帶重繪標記，不需要額外的旋轉感知邏輯；(c) 百分比座標
     * 直接乘上 [bitmap] 自身寬高即為疊加位置——因為框選當下的座標協定
     * 本來就是「相對目前顯示中 bitmap 內容範圍」（見 plan-issue-3.md
     * Global Constraints「PDF 座標協定」），bitmap 本身不含 letterbox
     * 留白，留白只發生在 ImageView 用 FIT_CENTER 顯示 bitmap 到 View
     * 的階段，該階段的縮放/置中會自動、成比例地把已疊加好的內容一併帶到
     * 正確視覺位置。
     *
     * 【審查修正，見 review 2.1】底線粗細／釘標尺寸須以 [scale]（即
     * `PdfImageProcessor.pageRenderScale(density)`，本方法渲染 bitmap 時
     * 實際採用的縮放係數）為基準，不可用畫面 DP 密度——`bitmap` 的實際
     * 像素尺寸是頁面點數乘上 [scale] 決定的，常遠大於螢幕 DP，用 DP
     * 密度換算會讓筆畫在高解析度 bitmap 上顯得極細/極小。底線繪製點為
     * `bottom - strokeWidth / 2`（而非直接畫在 `bottom`）——`Canvas.drawLine`
     * 的筆畫以座標為中線向兩側延伸，選取範圍貼近頁面底部時，若畫在
     * `bottom` 上，一半線寬會被畫布邊界裁掉。
     */
    private fun drawAnnotationOverlays(bitmap: Bitmap, pageIndex: Int, scale: Float) {
        val matching = pageAnnotations.filter { it.pageIndex == pageIndex }
        if (matching.isEmpty()) return
        val canvas = android.graphics.Canvas(bitmap)
        for (ann in matching) {
            val left = ann.left * bitmap.width
            val top = ann.top * bitmap.height
            val right = ann.right * bitmap.width
            val bottom = ann.bottom * bitmap.height
            if (ann.isUnderline) {
                // 底線樣式：PDF 點陣圖無文字層可錨定，改繪製矩形底部的
                // 一條實色線段（design.md 決策 #5 的視覺意圖延伸，不同於
                // EPUB 端 Readium Decoration.Style.Underline 的文字級底線）。
                val paint = android.graphics.Paint().apply {
                    color = ann.tint
                    style = android.graphics.Paint.Style.STROKE
                    strokeWidth = 2f * scale
                    strokeCap = android.graphics.Paint.Cap.ROUND
                }
                val lineY = bottom - paint.strokeWidth / 2
                canvas.drawLine(left, lineY, right, lineY, paint)
            } else {
                // 螢光筆三色／純備註灰底皆屬此類（tint 本身已含透明度）。
                val fillPaint = android.graphics.Paint().apply {
                    color = ann.tint
                    style = android.graphics.Paint.Style.FILL
                }
                canvas.drawRect(left, top, right, bottom, fillPaint)
            }
            if (ann.isNoteOnly) {
                drawNoteOnlyMarker(canvas, right, top, scale)
            }
        }
    }

    /**
     * 【審查修正，見 review 2.2】純備註畫面指示（design.md 決策 #2）改用
     * 純黑白、高對比度的手繪向量圖釘（圓形釘頭＋三角釘尖），不使用系統
     * Emoji（原本的 `canvas.drawText("📌", ...)`）——elinkBook 的核心場景
     * 之一是 E-Ink 黑白螢幕，系統 Emoji 經點陣化後會因失去色彩/漸層細節
     * 而模糊、對比度不足。比照本檔案 `CropOverlayView.kt` 既有先例——裁切
     * 確認按鈕同樣是刻意手繪的黑底白勾（非圖示字型），理由記載於其
     * KDoc：「確保在 E-Ink 16 階灰階裝置...與一般彩色螢幕上都維持清楚
     * 可辨的對比度」。[right]／[top] 為該筆標記矩形的右上角像素座標，圖釘
     * 錨點置於此角落內側一點的位置。
     */
    private fun drawNoteOnlyMarker(canvas: android.graphics.Canvas, right: Float, top: Float, scale: Float) {
        val markerRadius = 5f * scale
        val markerCx = right - markerRadius - 2f * scale
        val markerCy = top + markerRadius + 2f * scale
        val fillPaint = android.graphics.Paint().apply {
            color = android.graphics.Color.BLACK
            style = android.graphics.Paint.Style.FILL
            isAntiAlias = true
        }
        val outlinePaint = android.graphics.Paint().apply {
            color = android.graphics.Color.WHITE
            style = android.graphics.Paint.Style.STROKE
            strokeWidth = 1f * scale
            isAntiAlias = true
        }
        val pinPath = android.graphics.Path().apply {
            moveTo(markerCx - markerRadius, markerCy)
            lineTo(markerCx, markerCy + markerRadius * 2.2f)
            lineTo(markerCx + markerRadius, markerCy)
            close()
        }
        canvas.drawPath(pinPath, fillPaint)
        canvas.drawPath(pinPath, outlinePaint)
        canvas.drawCircle(markerCx, markerCy, markerRadius, fillPaint)
        canvas.drawCircle(markerCx, markerCy, markerRadius, outlinePaint)
    }
```

- [x] **Step 7: 編譯驗證**

Run: `cd app && flutter build apk --debug`
Expected: 建置成功

- [x] **Step 8: 執行既有 Kotlin 單元測試確認無回歸**

Run: `cd app/android && ./gradlew testDebugUnitTest`
Expected: BUILD SUCCESSFUL（`PdfReaderViewTest`／`PdfContentBoundsTest`／`PdfAnnotationOverlayTest` 皆通過）

- [x] **Step 9: 執行 `flutter analyze` 確認 Dart 端未受影響**

Run: `flutter analyze`
Expected: `No issues found!`

- [x] **Step 10: Commit**

```bash
git add app/android/app/src/main/kotlin/cc/ugotit/elinkbook/PdfReaderView.kt app/android/app/src/test/kotlin/cc/ugotit/elinkbook/PdfAnnotationOverlayTest.kt
git commit -m "feat(epic-6): PdfReaderView.kt 新增 refreshAnnotations 與 Bitmap 疊加繪製"
```

---

### Task 10：`ReaderScreen` 整合接線

**Files:**
- Modify: `app/lib/screens/reader_screen.dart`
- Modify: `app/test/screens/reader_screen_test.dart`

**Interfaces:**
- Consumes: Task 1-9 的全部型別與原生端實作。
- Produces: `ReaderScreen` 對 PDF 完成 Issue 3 端到端接線，`highlightsRepository`/`notesRepository` 對 PDF 書籍同樣生效（複用 Issue 2 已有的可選具名參數，不新增建構參數）。

- [x] **Step 1: 寫失敗測試**

於 `app/test/screens/reader_screen_test.dart` 檔案結尾（最後一個 `}` 之前）新增：

```dart
  testWidgets(
      'PDF 書籍提供 highlightsRepository／notesRepository 後，ReaderScreen 建構不受影響、仍正常顯示',
      (tester) async {
    final bookmarksRepository = FakeBookmarksRepository();
    final highlightsRepository = FakeHighlightsRepository();
    final notesRepository = FakeNotesRepository();

    await tester.pumpWidget(MaterialApp(
      home: ReaderScreen(
        filePath: 'test/fixtures/sample.pdf',
        bookId: 'b1',
        prefsManager: FakeReaderPrefsManager(),
        bookmarksRepository: bookmarksRepository,
        highlightsRepository: highlightsRepository,
        notesRepository: notesRepository,
      ),
    ));
    await tester.pump();

    // 原生 PlatformView 在 app/test/ 環境下不會真正建立（_channel 恆為
    // null，見既有兩層測試架構慣例），選取觸發後的浮動工具列顯示效果留
    // 給 Task 11 integration_test 驗證；本測試只驗證建構參數可正確傳入
    // 不崩潰，且未觸發選取時不顯示浮動工具列（既有行為零回歸）。
    expect(find.byType(AnnotationToolbar), findsNothing);
  });

  testWidgets('PDF 書籍未提供 highlightsRepository／notesRepository 時建構不受影響（既有呼叫端零回歸）',
      (tester) async {
    final bookmarksRepository = FakeBookmarksRepository();
    await tester.pumpWidget(MaterialApp(
      home: ReaderScreen(
        filePath: 'test/fixtures/sample.pdf',
        bookId: 'b1',
        prefsManager: FakeReaderPrefsManager(),
        bookmarksRepository: bookmarksRepository,
      ),
    ));
    await tester.pump();

    expect(find.byType(AnnotationToolbar), findsNothing);
  });
```

（`FakeBookmarksRepository`／`FakeHighlightsRepository`／`FakeNotesRepository`／`FakeReaderPrefsManager`／`AnnotationToolbar` 皆已由既有 import 涵蓋，見 Issue 1/2 既有測試檔頂部 import 清單，本次無需新增 import。）

- [x] **Step 2: 執行測試確認失敗**

Run: `flutter test test/screens/reader_screen_test.dart`
Expected: 目前應已可通過建構（`highlightsRepository`/`notesRepository` 參數 Issue 2 已存在）——**先執行一次確認此假設成立**；若確實已通過，本 Step 記錄「測試先行通過，Step 3 起的接線是行為擴充而非讓編譯通過」，繼續往下實作 PDF 選取/CRUD/清單流程本身（後續整合測試留給 Task 11 覆蓋，本 Task Step 1 的兩個測試主要作用是防止建構期間拋出例外的回歸網）。

- [x] **Step 3: 擴充 `ReaderScreen` import**

`app/lib/screens/reader_screen.dart` 頂部新增：

```dart
import '../reader/pdf_annotation_decoration.dart';
import '../reader/pdf_selection_info.dart';
```

- [x] **Step 4: 新增 State 欄位**

`_ReaderScreenState` 內，`_pendingHighlightIdForSelection`（EPUB，Issue 2 新增）欄位之後新增：

```dart
  // PDF 劃線／備註目前選取狀態（epic-6-annotations Issue 3），由原生端
  // onSelectionRectComputed 回報；非 null 時於 body Stack 顯示
  // AnnotationToolbar。與 EPUB 的 _currentSelection 並存但不會同時非
  // null（同一次只會開啟一種格式的書籍）。
  PdfSelectionInfo? _currentPdfSelection;
  int? _pendingPdfHighlightIdForSelection;
```

- [x] **Step 5: 新增 PDF 選取事件／CRUD 處理方法**

在 `_showAnnotationActionDialog` 方法之後（EPUB 相關方法群結尾）新增：

```dart
  void _handlePdfSelectionRectComputed(PdfSelectionInfo info) {
    if (!mounted) return;
    setState(() {
      _currentPdfSelection = info;
      _pendingPdfHighlightIdForSelection = null;
    });
  }

  void _handlePdfSelectionCanceled() {
    if (!mounted) return;
    setState(() {
      _currentPdfSelection = null;
      _pendingPdfHighlightIdForSelection = null;
    });
  }

  Future<void> _handlePdfHighlightStyleSelected(HighlightStyle style) async {
    final selection = _currentPdfSelection;
    final repository = widget.highlightsRepository;
    if (selection == null || repository == null) return;
    final id = await repository.insert(Highlight(
      bookId: widget.bookId,
      style: style,
      pdfPageIndex: selection.pageIndex,
      pdfRect: selection.rect,
    ));
    _pendingPdfHighlightIdForSelection = id;
    await _reloadPdfAnnotationsAndSync();
  }

  Future<void> _handlePdfNotePressed() async {
    final selection = _currentPdfSelection;
    final repository = widget.notesRepository;
    if (selection == null || repository == null) return;
    final text = await showNoteTextDialog(context, title: '新增備註');
    if (text == null) return;
    await repository.insert(Note(
      bookId: widget.bookId,
      text: text,
      pdfPageIndex: selection.pageIndex,
      pdfRect: selection.rect,
      highlightId: _pendingPdfHighlightIdForSelection,
    ));
    await _reloadPdfAnnotationsAndSync();
    if (!mounted) return;
    setState(() {
      _currentPdfSelection = null;
      _pendingPdfHighlightIdForSelection = null;
    });
  }

  /// 重新查詢本書全部劃線/備註並送給原生端重繪 Bitmap 疊加（PDF 版本，
  /// 比照 EPUB 的 [_reloadAnnotationsAndRefreshDecorations]）。共用同一組
  /// [_highlights]／[_notes] state 欄位——單一 ReaderScreen 會話只會載入
  /// 其中一種格式的書籍，不會同時混用。
  Future<void> _reloadPdfAnnotationsAndSync() async {
    final highlightsRepository = widget.highlightsRepository;
    final notesRepository = widget.notesRepository;
    if (highlightsRepository == null || notesRepository == null) return;
    final highlights = await highlightsRepository.listByBook(widget.bookId);
    final notes = await notesRepository.listByBook(widget.bookId);
    if (!mounted) return;
    setState(() {
      _highlights = highlights;
      _notes = notes;
    });
    _sendPdfAnnotationsToNative();
  }

  void _sendPdfAnnotationsToNative() {
    if (!mounted) return;
    final primaryColor = Theme.of(context).colorScheme.primary;
    final annotations = <PdfAnnotationDecoration>[
      for (final highlight in _highlights)
        if (highlight.pdfPageIndex != null && highlight.pdfRect != null)
          PdfAnnotationDecoration.forHighlight(
            pageIndex: highlight.pdfPageIndex!,
            rect: highlight.pdfRect!,
            tint: highlightStyleTint(highlight.style, primaryColor: primaryColor),
            isUnderline: highlight.style == HighlightStyle.underline,
          ),
      for (final note in _notes)
        if (note.highlightId == null && note.pdfPageIndex != null && note.pdfRect != null)
          PdfAnnotationDecoration.forNote(
            pageIndex: note.pdfPageIndex!,
            rect: note.pdfRect!,
            tint: noteOnlyTint.toARGB32(),
          ),
    ];
    PdfReaderView.refreshAnnotations(_pdfReaderViewKey, annotations);
  }

  // 浮動工具列估計高度／與選取範圍的間距，PDF 版本（比照 EPUB 的
  // _annotationToolbarHeight／_annotationToolbarGap 既有常數值，兩者刻意
  // 保持相同數值，故不重複宣告，直接複用）。

  /// PDF 版本的浮動工具列定位計算，邏輯與 EPUB 的 [_annotationToolbarTop]
  /// 完全相同（皆為「優先貼在選取範圍上方，空間不足時貼下方」），但參數
  /// 型別不同（[PdfSelectionInfo] 而非 [EpubSelectionInfo]），故獨立宣告
  /// 一份而非嘗試合併兩者呼叫端（Surgical Changes 原則：不更動 Issue 2
  /// 已驗證穩定的 [_annotationToolbarTop] 本體）。
  double _pdfAnnotationToolbarTop(PdfSelectionInfo selection, Size size) {
    final topAboveSelection =
        selection.rect.top * size.height - _annotationToolbarHeight - _annotationToolbarGap;
    if (topAboveSelection >= 0) return topAboveSelection;
    final belowSelection = selection.rect.bottom * size.height + _annotationToolbarGap;
    return belowSelection.clamp(0.0, size.height - _annotationToolbarHeight);
  }
```

- [x] **Step 6: 於 `_handlePageRendered` 觸發初始標記載入**

`_handlePageRendered` 方法改為：

```dart
  void _handlePageRendered() {
    if (!mounted) return;
    setState(() => _state = _RenderState.rendered);
    // epic-6-annotations Issue 3：PDF 書籍開啟成功後載入既有劃線/備註並
    // 送給原生端渲染。與 EPUB 的觸發點（_handleLayoutResolved，見 Issue 2
    // Task 10 Step 7）刻意不同——PDF 沒有對應的版面解析回呼，本方法
    // （onPageRendered）是 PDF 開書成功的既有訊號，兩種格式共用同一個
    // _annotationsLoaded 旗標（單一書籍只會是其中一種格式，不會重複觸發）。
    if (detectBookFormat(widget.filePath) == BookFormat.pdf &&
        !_annotationsLoaded &&
        widget.highlightsRepository != null &&
        widget.notesRepository != null) {
      _annotationsLoaded = true;
      _reloadPdfAnnotationsAndSync();
    }
  }
```

- [x] **Step 7: 於 `_buildNativeView` 的 PDF 分支接上新回呼**

`_buildNativeView` 的 `case BookFormat.pdf:` 分支，`onPageChanged: (info) { ... },` 之後（`return PdfReaderView(...)` 結尾的 `)` 之前）新增：

```dart
          onSelectionRectComputed: _handlePdfSelectionRectComputed,
          onSelectionCanceled: _handlePdfSelectionCanceled,
        );
```

- [x] **Step 8: 於 `_buildBody` 疊加 PDF 版本的 `AnnotationToolbar`**

`_buildBody` 方法內 `LayoutBuilder` 的 `builder` 中，`final selection = _currentSelection;` 之後新增：

```dart
        final pdfSelection = _currentPdfSelection;
```

`if (selection != null) Positioned(...)` 區塊之後（`if (_state == _RenderState.loading)` 之前）新增：

```dart
            if (pdfSelection != null)
              Positioned(
                left: (pdfSelection.rect.left * size.width).clamp(0.0, size.width),
                top: _pdfAnnotationToolbarTop(pdfSelection, size),
                child: AnnotationToolbar(
                  onStyleSelected: _handlePdfHighlightStyleSelected,
                  onNotePressed: _handlePdfNotePressed,
                ),
              ),
```

- [x] **Step 9: 於 `_openNotesSheet` 擴充 PDF 支援**

`_openNotesSheet` 方法內，`NotesBottomSheet(` 建構呼叫改為：

```dart
      builder: (_) => NotesBottomSheet(
        bookId: widget.bookId,
        bookmarksRepository: repository,
        currentPosition: positionContext,
        highlightsRepository: (format == BookFormat.epub && !_isFixedLayout) ||
                format == BookFormat.pdf
            ? widget.highlightsRepository
            : null,
        notesRepository: (format == BookFormat.epub && !_isFixedLayout) ||
                format == BookFormat.pdf
            ? widget.notesRepository
            : null,
        onAnnotationSelected: (item) {
          Navigator.of(context).pop();
          final locatorJson = item.highlight?.epubLocatorJson ?? item.note?.epubLocatorJson;
          final pdfPageIndex = item.highlight?.pdfPageIndex ?? item.note?.pdfPageIndex;
          if (locatorJson != null) {
            EpubReaderView.jumpToLocator(_epubReaderViewKey, locatorJson);
          } else if (pdfPageIndex != null) {
            PdfReaderView.jumpToPage(_pdfReaderViewKey, pdfPageIndex);
          }
        },
        onAnnotationsChanged: format == BookFormat.pdf
            ? _reloadPdfAnnotationsAndSync
            : _reloadAnnotationsAndRefreshDecorations,
        onBookmarkSelected: (bookmark) {
          Navigator.of(context).pop();
          if (bookmark.epubLocatorJson != null) {
            EpubReaderView.jumpToLocator(
              _epubReaderViewKey,
              bookmark.epubLocatorJson!,
            );
          } else if (bookmark.pdfPageIndex != null) {
            PdfReaderView.jumpToPage(_pdfReaderViewKey, bookmark.pdfPageIndex!);
          }
        },
      ),
```

（原本 `format == BookFormat.epub && !_isFixedLayout ? widget.highlightsRepository : null` 這行是 Issue 2 已預留的擴充點，本 Step 依其註解指示擴充為涵蓋 `format == BookFormat.pdf`。）

- [x] **Step 10: 執行測試確認通過**

Run: `flutter test test/screens/reader_screen_test.dart`
Expected: PASS（全部測試綠燈，含既有測試不受影響）

Run: `flutter test`
Expected: 全專案測試皆 PASS（確認本次跨檔案修改無回歸）。

- [x] **Step 11: 執行 `flutter analyze` 確認乾淨**

Run: `flutter analyze`
Expected: `No issues found!`

- [x] **Step 12: Commit**

```bash
git add app/lib/screens/reader_screen.dart app/test/screens/reader_screen_test.dart
git commit -m "feat(epic-6): ReaderScreen 接上 PDF 劃線/備註端到端流程"
```

---

### Task 11：integration_test（真機）＋ 手勢驅動流程的人工驗證清單

**Files:**
- Create: `app/integration_test/pdf_highlights_notes_test.dart`

**Interfaces:**
- Consumes: Task 1-10 的全部型別（`HighlightsRepository`／`NotesRepository`／`ReaderScreen`／`NotesBottomSheet`）。
- Produces: 無新增 Dart 型別；驗證 repository 驅動的端到端流程（清單顯示、跳轉、編輯、刪除），比照 Issue 2 `epub_highlights_notes_test.dart` 既有結構，改用 `sample.pdf`／`sample_dual_page.pdf` 既有測試 fixture。

- [ ] **Step 1: 撰寫 integration_test**

建立 `app/integration_test/pdf_highlights_notes_test.dart`：

```dart
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:path_provider/path_provider.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:elinkbook/library/models/book.dart';
import 'package:elinkbook/library/models/library_enums.dart';
import 'package:elinkbook/library/sqlite_library_repository.dart';
import 'package:elinkbook/reader/book_reader_prefs_repository.dart';
import 'package:elinkbook/reader/bookmarks_repository.dart';
import 'package:elinkbook/reader/epub_character_count_repository.dart';
import 'package:elinkbook/reader/highlight.dart';
import 'package:elinkbook/reader/highlight_style.dart';
import 'package:elinkbook/reader/highlights_repository.dart';
import 'package:elinkbook/reader/note.dart';
import 'package:elinkbook/reader/notes_repository.dart';
import 'package:elinkbook/reader/percent_rect.dart';
import 'package:elinkbook/reader/reader_prefs_manager_impl.dart';
import 'package:elinkbook/reader/reading_position_repository.dart';
import 'package:elinkbook/screens/notes_bottom_sheet.dart';
import 'package:elinkbook/screens/reader_screen.dart';

Future<String> _stageAssetAsFile(String assetPath, String fileName) async {
  final bytes = await rootBundle.load(assetPath);
  final tempDir = await getTemporaryDirectory();
  final file = File('${tempDir.path}/$fileName');
  await file.writeAsBytes(bytes.buffer.asUint8List(), flush: true);
  return file.path;
}

Future<void> _pumpUntilLoaded(WidgetTester tester) async {
  final deadline = DateTime.now().add(const Duration(seconds: 10));
  while (find.byKey(const Key('reader_loading_indicator')).evaluate().isNotEmpty) {
    if (DateTime.now().isAfter(deadline)) fail('等待逾時：載入指示器未消失');
    await tester.pump(const Duration(milliseconds: 50));
  }
  await tester.pump(const Duration(seconds: 1));
}

Future<void> _pumpUntilNotesButtonEnabled(WidgetTester tester) async {
  final deadline = DateTime.now().add(const Duration(seconds: 10));
  while (true) {
    final finder = find.byKey(const Key('reader_notes_button'));
    if (finder.evaluate().isNotEmpty &&
        tester.widget<IconButton>(finder).onPressed != null) {
      return;
    }
    if (DateTime.now().isAfter(deadline)) {
      fail('等待逾時：筆記按鈕未轉為可點擊狀態');
    }
    await tester.pump(const Duration(milliseconds: 100));
  }
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  // 【真機人工驗證清單，本測試無法自動涵蓋】
  // 比照 epic-6-annotations Issue 2 integration_test 既有先例：Flutter
  // integration_test 對原生 View 的觸控事件模擬並不可靠，本專案既有慣例
  // 是原生手勢功能一律另外以真實裝置人工驗證，不嘗試以
  // tester.longPress/drag 模擬。以下項目須另外以真實裝置人工驗證：
  //   1. 長按 PDF 頁面直接觸發拖曳框選矩形手勢（不需先進入獨立模式，
  //      ADR 0008），放開後浮動工具列正確定位於選取矩形上方。
  //   2. 長按框選與既有水平滑動翻頁手勢實際共存不衝突（審查修正 1.1後：
  //      長按/拖曳辨識已改由 Flutter 端 GestureDetector 主導、與
  //      onHorizontalDragEnd 同一個手勢競技場仲裁，架構上已不存在原生端
  //      無條件攔截 ACTION_DOWN 的問題；此項為對「按構造正確」的實機
  //      體感確認，非未知風險排查——若真的發現翻頁手勢仍受影響，代表
  //      實作與計劃書不一致，須回頭檢查 Task 6/8 是否正確落實）。
  //   3. 框選進行中第二指觸碰螢幕，驗證框選狀態正確取消、浮動工具列收起
  //      （Dart 端 Listener 偵測多指觸碰，見 Global Constraints）。
  //   4. 點擊螢光筆三色/底線按鈕，建立劃線後 Bitmap 正確疊加渲染；純
  //      備註淡灰底＋右上角黑白向量圖釘視覺可辨識，尤其在 E-Ink 高對比
  //      模式下確認清晰不模糊（審查修正 2.2）。
  //   5. 刪除劃線/備註後（單筆或批次），驗證 refreshAnnotations() 確實
  //      觸發原生端重繪、無殘留視覺。
  //   6. 裝置旋轉後，驗證既有劃線座標仍正確對應頁面實際內容（letterbox-
  //      aware 座標基準驗證，見 plan-issue-3.md Global Constraints「PDF
  //      座標協定」）。
  //   7. 已裁切（crop）頁面上長按框選，驗證矩形相對「裁切後內容範圍」
  //      計算正確（非整個原生 View）。
  // 本檔案改為驗證「repository 驅動」的部分：預先透過 Repository 寫入
  // 劃線/備註資料（模擬手勢建立後的最終資料狀態），驗證 NotesBottomSheet
  // 清單顯示、跳轉、編輯、刪除的端到端流程。

  testWidgets('PDF：預先寫入劃線＋依附備註，NotesBottomSheet 正確顯示合併清單並可跳轉/刪除',
      (tester) async {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    final libraryRepository = await SqliteLibraryRepository.open(inMemoryDatabasePath);
    addTearDown(() => libraryRepository.close());
    final prefsManager = ReaderPrefsManagerImpl(
      BookReaderPrefsRepository(libraryRepository.database),
      ReadingPositionRepository(libraryRepository.database),
      EpubCharacterCountRepository(libraryRepository.database),
    );
    final bookmarksRepository = BookmarksRepository(libraryRepository.database);
    final highlightsRepository = HighlightsRepository(libraryRepository.database);
    final notesRepository = NotesRepository(libraryRepository.database);

    final samplePath = await _stageAssetAsFile('test/fixtures/sample.pdf', 'pdf_highlights_notes.pdf');
    addTearDown(() async {
      final file = File(samplePath);
      if (await file.exists()) await file.delete();
    });

    await libraryRepository.insertBook(Book(
      id: 'b_highlights_pdf',
      title: '劃線測試書',
      format: BookFileFormat.pdf,
      filePath: samplePath,
      source: BookSource.local,
      createTime: DateTime.now(),
      lastReadTime: DateTime.now(),
    ));

    const rect = PercentRect(left: 0.1, top: 0.1, right: 0.6, bottom: 0.2);
    final highlightId = await highlightsRepository.insert(const Highlight(
      bookId: 'b_highlights_pdf',
      style: HighlightStyle.highlighterYellow,
      pdfPageIndex: 0,
      pdfRect: rect,
    ));
    await notesRepository.insert(Note(
      bookId: 'b_highlights_pdf',
      text: '這段很重要',
      pdfPageIndex: 0,
      pdfRect: rect,
      highlightId: highlightId,
    ));
    await notesRepository.insert(const Note(
      bookId: 'b_highlights_pdf',
      text: '純備註內容',
      pdfPageIndex: 1,
      pdfRect: PercentRect(left: 0.0, top: 0.3, right: 0.4, bottom: 0.4),
    ));

    await tester.pumpWidget(
      MaterialApp(
        home: ReaderScreen(
          filePath: samplePath,
          bookId: 'b_highlights_pdf',
          prefsManager: prefsManager,
          bookmarksRepository: bookmarksRepository,
          highlightsRepository: highlightsRepository,
          notesRepository: notesRepository,
        ),
      ),
    );
    await _pumpUntilLoaded(tester);
    await _pumpUntilNotesButtonEnabled(tester);

    await tester.tap(find.byKey(const Key('reader_notes_button')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('notes_sheet_tab_annotations')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('notes_sheet_annotation_list')), findsOneWidget);
    expect(find.text('這段很重要'), findsOneWidget);
    expect(find.text('純備註內容'), findsOneWidget);

    // 點選合併項目後 Bottom Sheet 應關閉（跳轉本身的原生渲染結果無法在
    // widget test 層級斷言，比照既有先例的既定限制）。
    await tester.tap(find.text('這段很重要'));
    await tester.pumpAndSettle();
    expect(find.byType(NotesBottomSheet), findsNothing);
    expect(find.byKey(const Key('reader_error_text')), findsNothing);

    // 重新開啟，驗證單筆刪除（劃線+備註一併消失）持久化生效。
    await tester.tap(find.byKey(const Key('reader_notes_button')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('notes_sheet_tab_annotations')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(Key('notes_sheet_annotation_delete_h${highlightId}_n1')));
    await tester.pumpAndSettle();

    expect(await highlightsRepository.listByBook('b_highlights_pdf'), isEmpty);
    expect(find.text('這段很重要'), findsNothing);
    expect(find.text('純備註內容'), findsOneWidget);
  });
}
```

- [ ] **Step 2: 記錄待執行狀態**

本測試需在真實 Android 裝置/模擬器上執行（`flutter test integration_test/pdf_highlights_notes_test.dart -d <device-id>`）；比照 Issue 1/2 先例，若撰寫當下無可用裝置，於 `issues.md` Issue 3 驗收標準對應項目註記「測試檔已撰寫，尚待裝置就緒後實際執行」，並列出上方 Step 1 註解中的「真機人工驗證清單」7 項供人工測試時對照。

- [ ] **Step 3: 若有裝置可用，執行驗證**

Run: `flutter devices`（確認是否有可用裝置/模擬器）
若有：Run: `flutter test integration_test/pdf_highlights_notes_test.dart -d <device-id>`
Expected: PASS；並依上方「真機人工驗證清單」逐項人工操作確認，額外聚焦 Issue 2 未曾驗證過的項目：長按與水平滑動翻頁實際共存（清單項目 2，審查修正 1.1 後為構造性驗證而非未知風險排查）、多指取消（項目 3）、裁切後座標基準（項目 7）。
若無：跳過本步驟，維持 Step 2 的註記狀態。

- [ ] **Step 4: Commit**

```bash
git add app/integration_test/pdf_highlights_notes_test.dart
git commit -m "test(epic-6): 新增 PDF 劃線/備註真機整合測試（尚待真機執行驗證）"
```

---

## 完成後的整體驗證

- [ ] Run: `flutter test`（全專案）
  Expected: 全數 PASS，無回歸。
- [ ] Run: `flutter analyze`
  Expected: `No issues found!`
- [ ] Run: `cd app && flutter build apk --debug`
  Expected: 建置成功。
- [ ] Run: `cd app/android && ./gradlew testDebugUnitTest`
  Expected: BUILD SUCCESSFUL（`PdfReaderViewTest`／`PdfContentBoundsTest`／`PdfAnnotationOverlayTest` 皆通過，既有 `EpubFxlScalerTest`／`PdfImageProcessorTest`／`EpubReaderViewDualPageTest`／`EpubCharacterCounterTest` 不受影響）。
- [ ] 依 `issues.md` Issue 3 驗收標準逐項核對，勾選已完成項目；真機相關項目（長按與翻頁手勢共存、Bitmap 疊加視覺、多指取消、裁切後座標基準、裝置旋轉）維持標註「測試檔已撰寫，尚待裝置就緒後實際執行」，repository 驅動的端到端流程（清單顯示、跳轉、編輯、刪除）若已於真機執行並通過，於 `issues.md` 註明。
