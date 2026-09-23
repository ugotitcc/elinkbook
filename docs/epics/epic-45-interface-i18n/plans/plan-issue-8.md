# Epic 45 Issue 8：Markdown 匯出契約變更 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development（recommended）or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** `app/lib/reader/markdown_export.dart` 的 `generateMarkdownExport()` 新增 `required AppLocalizations l10n` 參數，函式內全部系統結構文字（標題／作者／進度／導出時間標籤、書籤/劃線備註區塊標題與空狀態文字、劃線樣式標籤、每筆劃線/備註的「位置」標題）改讀 `AppLocalizations`；日期格式改依目前介面語言（`DateFormat.yMd(l10n.localeName)`）而非固定 `y-m-d`。書名/作者/備註內容等使用者資料、`Bookmark.defaultName()` 產出的位置標籤本身（該函式所屬 `bookmark.dart` 模組的既有機制，不在本次變更範圍）不受影響。呼叫端 `NotesBottomSheet._exportMarkdown()` 改傳入 `AppLocalizations.of(context)!`。

**Architecture:** 沿用 Issue 7 已確立的純 Dart 單元測試取得 `AppLocalizations` 實例模式（`lookupAppLocalizations(Locale)`，`markdown_export_test.dart` 是 `test(...)` 非 `testWidgets(...)`，沒有 `BuildContext`）。核心發現：`notes_bottom_sheet.dart`（Issue 4 已在地化）的 `_highlightStyleLabel()` 與本檔案的同名私有函式輸出**完全相同的中文文字**（`螢光筆（黃）`／`螢光筆（粉）`／`螢光筆（藍）`／`底線`／`備註`），且 Issue 4 早已為它們建立 ARB key（`readerHighlightStyleYellow`／`Pink`／`Blue`／`Underline`／`readerNotesSheetNoteLabel`）——本 Issue 直接重用這 5 個既有 key，**不**依 `issues.md` 原始建議新增「劃線樣式標籤 4 個 key」（ARB key 是全域共用翻譯字典，重用不等於重新耦合兩個檔案的 Dart 函式本身；本檔案 `_highlightStyleLabel()` 仍是獨立私有函式，維持該函式既有 KDoc 記載的「兩個檔案的顯示標籤函式刻意不合併，各自消費端獨立」設計決策不變，只是兩者現在都指向同一組 ARB key）。另外通讀全函式後發現 `spec.md` §7 條列的字面值清單遺漏了一處：`'### 📌 $label（位置：${_positionLabel(item)}）'` 這行的「位置：」也是系統結構文字（不屬於 `_positionLabel()` 回傳值本身，是包住它的固定模板），一併納入為新 key `markdownExportAnnotationHeading(label, position)`（整行一個 key、2 個 placeholder，符合 i18n 慣例——不要把「位置：」單獨抽成碎片 key 再字串拼接，不同語言的詞序/標點規則不同，拼接碎片在其他語言下可能語序顛倒）。

實際新增 ARB key（9 個）：`markdownExportTitle(bookTitle)`／`markdownExportAuthorLabel(author)`／`markdownExportUnknownAuthor`／`markdownExportProgressLabel(percent)`／`markdownExportTimeLabel(time)`／`markdownExportBookmarksSection(count)`／`markdownExportNoBookmarks`／`markdownExportAnnotationsSection(count)`／`markdownExportNoAnnotations`；加上上述新發現的 `markdownExportAnnotationHeading(label, position)` 共 **10 個**。

**Tech Stack:** Flutter `flutter_localizations`／`intl`（ARB／`gen-l10n`；`DateFormat.yMd()` 日期在地化）。

**Spec:** `docs/epics/epic-45-interface-i18n/spec.md`（§7 Markdown 匯出契約變更、§7 純 Dart 單元測試取得 l10n 實例的既定作法）、`docs/epics/epic-45-interface-i18n/issues.md`（Issue 8 段落）。

## Global Constraints

- 異動前四份 ARB 檔案（`app_zh_TW.arb`／`app_zh_CN.arb`／`app_en.arb`／`app_zh.arb`）皆為 539 個 key，完全同步。新增 10 個 key 後為 549 個。
- **`DateFormat` 在純 Dart `test()` 環境下需要顯式初始化 locale 資料，否則拋出 `LocaleDataException`（已實測驗證）**：`app/test/reader/markdown_export_test.dart` 是純 `test()`（無 widget pump），不像 `testWidgets` 環境那樣由 `MaterialApp`／`GlobalMaterialLocalizations.delegate` 隱含初始化 `intl` 的 locale 符號資料。呼叫 `DateFormat.yMd('zh_TW')` 前必須先 `await initializeDateFormatting();`（`package:intl/date_symbol_data_local.dart`），否則測試會直接因 `LocaleDataException: Locale data has not been initialized` 失敗，與程式碼邏輯正確與否無關，純粹是測試環境設定缺漏——本計畫 Task 1 Step 2 已把這個 `setUpAll()` 納入初始的失敗測試中，Step 3 執行「確認測試失敗」時預期的失敗原因是「函式簽章尚未改」而非這個初始化例外。
- `DateFormat.yMd(locale)` 實測輸出格式（供撰寫斷言參照，已用 `flutter test` 實際驗證非憑空假設）：`zh_TW`／`zh_CN` 對 `DateTime(2026, 7, 18)` 皆輸出 `2026/7/18`；`en` 輸出 `7/18/2026`。
- 服務層/純函式分層：`markdown_export.dart` 本身**不**引用 `BuildContext`（延續既有「純函式，不涉及檔案 I/O」設計），`AppLocalizations l10n` 以參數形式傳入，呼叫端 `notes_bottom_sheet.dart._exportMarkdown()`（既有 State 方法、`context` 已可用）在方法最前面同步呼叫 `AppLocalizations.of(context)!` 取得後透傳——這是使用者點擊「導出為 Markdown」按鈕觸發的方法（`onPressed: _exportMarkdown`），不是 `initState()` 觸發，呼叫時機必然在 widget 已完整掛載之後，不受「`initState()` 存取 l10n 陷阱」鐵律限制，也不需要額外 `if (!mounted) return;` 防衛（比照 `library_group_management_dialog.dart._addGroup()` 既有先例：`final l10n = AppLocalizations.of(context)!;` 作為使用者觸發之 async 方法的第一行）。
- `Bookmark.defaultName()`（`app/lib/reader/bookmark.dart`）本身的輸出文字（例如 `'$percent% 處'`／`'第 N 頁'`／`'書籤'`）**不**在本 Issue 變更範圍——`spec.md` §7 明文排除，即使切換到英文介面，這部分文字仍會是既有中文（該函式所屬 `bookmark.dart` 模組的既有機制，留待該模組自己的未來工單評估是否 l10n 化）。
- 測試執行範圍：單一 Task 完成後只跑該 Task 觸及的測試檔；完整 `flutter test`／`flutter analyze` 僅在 Task 3（最後一個 Task）執行一次。
- Commit 訊息前綴統一 `feat(epic-45):`，Task 3 除外用 `docs(epic-45):`。

---

### Task 1: `markdown_export.dart`——`generateMarkdownExport()` 全面接上 `AppLocalizations`

**Files:**
- Modify: `app/lib/reader/markdown_export.dart`
- Modify: `app/lib/l10n/app_zh_TW.arb`／`app_zh_CN.arb`／`app_en.arb`／`app_zh.arb`
- Test: `app/test/reader/markdown_export_test.dart`

**Interfaces:**
- Consumes：既有 `l10n.readerHighlightStyleYellow`／`readerHighlightStylePink`／`readerHighlightStyleBlue`／`readerHighlightStyleUnderline`／`readerNotesSheetNoteLabel`（Issue 4 既有 key，重用不新增）。
- Produces：`generateMarkdownExport()` 簽章新增 `required AppLocalizations l10n`（放在具名參數第一個，供 Task 2 呼叫端對照）；10 個新 ARB key（詳見下方 Step 1）。

- [ ] **Step 1: 新增 ARB key（四語言）**

`app_zh_TW.arb` 找到既有檔尾（**是本專案的 template ARB，最後一個 key 帶有 `@layoutPresetNameDialogSaveButton` metadata 物件，與其餘三份無 `@` 區塊的 ARB 不同，勿套用其他三份的錨點**）：

```json
  "layoutPresetNameDialogSaveButton": "儲存",
  "@layoutPresetNameDialogSaveButton": {
    "description": "命名對話框的「儲存」按鈕文字"
  }
}
```

改為：

```json
  "layoutPresetNameDialogSaveButton": "儲存",
  "@layoutPresetNameDialogSaveButton": {
    "description": "命名對話框的「儲存」按鈕文字"
  },
  "markdownExportTitle": "# 閱讀筆記：《{bookTitle}》",
  "@markdownExportTitle": {
    "description": "Markdown 匯出檔案標題行，{bookTitle} 為使用者書名資料，不翻譯",
    "placeholders": {
      "bookTitle": {
        "type": "String"
      }
    }
  },
  "markdownExportAuthorLabel": "*   **作者**：{author}",
  "@markdownExportAuthorLabel": {
    "description": "Markdown 匯出的作者標籤行，{author} 為已解析好的作者字串（可能是使用者資料，也可能是 markdownExportUnknownAuthor 的在地化回退值）",
    "placeholders": {
      "author": {
        "type": "String"
      }
    }
  },
  "markdownExportUnknownAuthor": "未知作者",
  "@markdownExportUnknownAuthor": {
    "description": "Markdown 匯出時，書籍作者欄位為 null 的回退顯示文字"
  },
  "markdownExportProgressLabel": "*   **閱讀進度**：{percent}%",
  "@markdownExportProgressLabel": {
    "description": "Markdown 匯出的閱讀進度標籤行，{percent} 為 0-100 整數",
    "placeholders": {
      "percent": {
        "type": "int"
      }
    }
  },
  "markdownExportTimeLabel": "*   **導出時間**：{time}",
  "@markdownExportTimeLabel": {
    "description": "Markdown 匯出的導出時間標籤行，{time} 為依目前介面語言格式化後的日期字串（DateFormat.yMd）",
    "placeholders": {
      "time": {
        "type": "String"
      }
    }
  },
  "markdownExportBookmarksSection": "## 🔖 書籤清單 ({count})",
  "@markdownExportBookmarksSection": {
    "description": "Markdown 匯出的書籤清單區塊標題，{count} 為書籤本數",
    "placeholders": {
      "count": {
        "type": "int"
      }
    }
  },
  "markdownExportNoBookmarks": "*(尚未加入書籤)*",
  "@markdownExportNoBookmarks": {
    "description": "Markdown 匯出時，書籤清單為空的提示文字"
  },
  "markdownExportAnnotationsSection": "## ✏️ 劃線與個人備註 ({count})",
  "@markdownExportAnnotationsSection": {
    "description": "Markdown 匯出的劃線與個人備註區塊標題，{count} 為劃線/備註合併總筆數",
    "placeholders": {
      "count": {
        "type": "int"
      }
    }
  },
  "markdownExportNoAnnotations": "*(尚未加入任何劃線或備註)*",
  "@markdownExportNoAnnotations": {
    "description": "Markdown 匯出時，劃線與備註清單為空的提示文字"
  },
  "markdownExportAnnotationHeading": "### 📌 {label}（位置：{position}）",
  "@markdownExportAnnotationHeading": {
    "description": "Markdown 匯出的單筆劃線/備註標題行，{label} 為樣式標籤（螢光筆/底線/備註），{position} 為 Bookmark.defaultName() 產出的位置文字（該函式本身不在本 Issue 翻譯範圍，見 spec.md §7）",
    "placeholders": {
      "label": {
        "type": "String"
      },
      "position": {
        "type": "String"
      }
    }
  }
}
```

`app_zh_CN.arb` 找到既有檔尾：

```json
  "layoutPresetNameDialogSaveButton": "储存"
}
```

改為：

```json
  "layoutPresetNameDialogSaveButton": "储存",
  "markdownExportTitle": "# 阅读笔记：《{bookTitle}》",
  "markdownExportAuthorLabel": "*   **作者**：{author}",
  "markdownExportUnknownAuthor": "未知作者",
  "markdownExportProgressLabel": "*   **阅读进度**：{percent}%",
  "markdownExportTimeLabel": "*   **导出时间**：{time}",
  "markdownExportBookmarksSection": "## 🔖 书签清单 ({count})",
  "markdownExportNoBookmarks": "*(尚未加入书签)*",
  "markdownExportAnnotationsSection": "## ✏️ 划线与个人备注 ({count})",
  "markdownExportNoAnnotations": "*(尚未加入任何划线或备注)*",
  "markdownExportAnnotationHeading": "### 📌 {label}（位置：{position}）"
}
```

`app_en.arb` 找到既有檔尾：

```json
  "layoutPresetNameDialogSaveButton": "Save"
}
```

改為：

```json
  "layoutPresetNameDialogSaveButton": "Save",
  "markdownExportTitle": "# Reading Notes: {bookTitle}",
  "markdownExportAuthorLabel": "*   **Author**: {author}",
  "markdownExportUnknownAuthor": "Unknown Author",
  "markdownExportProgressLabel": "*   **Reading Progress**: {percent}%",
  "markdownExportTimeLabel": "*   **Export Time**: {time}",
  "markdownExportBookmarksSection": "## 🔖 Bookmarks ({count})",
  "markdownExportNoBookmarks": "*(No bookmarks yet)*",
  "markdownExportAnnotationsSection": "## ✏️ Highlights & Notes ({count})",
  "markdownExportNoAnnotations": "*(No highlights or notes yet)*",
  "markdownExportAnnotationHeading": "### 📌 {label} (Position: {position})"
}
```

`app_zh.arb`（內容與 `app_zh_TW.arb` 的值相同、不含 `@key` metadata）找到既有檔尾：

```json
  "layoutPresetNameDialogSaveButton": "儲存"
}
```

改為：

```json
  "layoutPresetNameDialogSaveButton": "儲存",
  "markdownExportTitle": "# 閱讀筆記：《{bookTitle}》",
  "markdownExportAuthorLabel": "*   **作者**：{author}",
  "markdownExportUnknownAuthor": "未知作者",
  "markdownExportProgressLabel": "*   **閱讀進度**：{percent}%",
  "markdownExportTimeLabel": "*   **導出時間**：{time}",
  "markdownExportBookmarksSection": "## 🔖 書籤清單 ({count})",
  "markdownExportNoBookmarks": "*(尚未加入書籤)*",
  "markdownExportAnnotationsSection": "## ✏️ 劃線與個人備註 ({count})",
  "markdownExportNoAnnotations": "*(尚未加入任何劃線或備註)*",
  "markdownExportAnnotationHeading": "### 📌 {label}（位置：{position}）"
}
```

- [ ] **Step 2: 修改既有測試（先改測試，確認會失敗）**

在 `app/test/reader/markdown_export_test.dart` 把整個檔案改為：

```dart
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:elinkbook/l10n/app_localizations.dart';
import 'package:elinkbook/reader/annotation_list_item.dart';
import 'package:elinkbook/reader/bookmark.dart';
import 'package:elinkbook/reader/highlight.dart';
import 'package:elinkbook/reader/highlight_style.dart';
import 'package:elinkbook/reader/markdown_export.dart';
import 'package:elinkbook/reader/note.dart';

void main() {
  setUpAll(() async {
    // DateFormat.yMd() 在純 test() 環境（無 MaterialApp/widget pump）下
    // 需要顯式初始化 locale 符號資料，否則拋出 LocaleDataException（見
    // plan-issue-8.md Global Constraints，已實測驗證）。
    await initializeDateFormatting();
  });

  group('generateMarkdownExport', () {
    test('有書籤、有劃線、有依附備註時，輸出格式包含三個段落與正確筆數', () {
      final l10n = lookupAppLocalizations(const Locale('zh', 'TW'));
      final result = generateMarkdownExport(
        l10n: l10n,
        bookTitle: '紅樓夢',
        bookAuthor: '曹雪芹',
        progress: 0.35,
        exportTime: DateTime(2026, 7, 18),
        bookmarks: const [
          Bookmark(
            id: 'bm1',
            bookId: 'b1',
            name: '第二章 (35%)',
            epubLocatorJson: '{}',
            progression: 0.35,
          ),
        ],
        annotations: [
          AnnotationListItem(
            highlight: const Highlight(
              id: 'h1',
              bookId: 'b1',
              style: HighlightStyle.highlighterYellow,
              epubLocatorJson: '{}',
              progression: 0.2,
            ),
            note: const Note(
              id: 'n1',
              bookId: 'b1',
              text: '黛玉名句',
              epubLocatorJson: '{}',
              progression: 0.2,
              highlightId: 'h1',
            ),
          ),
        ],
      );

      expect(result, contains('# 閱讀筆記：《紅樓夢》'));
      expect(result, contains('**作者**：曹雪芹'));
      expect(result, contains('**閱讀進度**：35%'));
      expect(result, contains('**導出時間**：2026/7/18'));
      expect(result, contains('## 🔖 書籤清單 (1)'));
      expect(result, contains('*   第二章 (35%)'));
      expect(result, contains('## ✏️ 劃線與個人備註 (1)'));
      expect(result, contains('### 📌 螢光筆（黃）（位置：20% 處）'));
      expect(result, contains('> 黛玉名句'));
    });

    test('只有書籤時，劃線與備註段落顯示空狀態文字，作者缺省時顯示「未知作者」', () {
      final l10n = lookupAppLocalizations(const Locale('zh', 'TW'));
      final result = generateMarkdownExport(
        l10n: l10n,
        bookTitle: '書籤書',
        progress: 0.5,
        exportTime: DateTime(2026, 1, 1),
        bookmarks: const [
          Bookmark(id: 'bm2', bookId: 'b1', name: '第 3 頁', pdfPageIndex: 2),
        ],
        annotations: const [],
      );

      expect(result, contains('**作者**：未知作者'));
      expect(result, contains('## 🔖 書籤清單 (1)'));
      expect(result, contains('*   第 3 頁'));
      expect(result, contains('## ✏️ 劃線與個人備註 (0)'));
      expect(result, contains('*(尚未加入任何劃線或備註)*'));
    });

    test('只有劃線、無依附備註時，該筆項目不含引言區塊', () {
      final l10n = lookupAppLocalizations(const Locale('zh', 'TW'));
      final result = generateMarkdownExport(
        l10n: l10n,
        bookTitle: '劃線書',
        progress: 0.1,
        exportTime: DateTime(2026, 1, 1),
        bookmarks: const [],
        annotations: [
          AnnotationListItem(
            highlight: const Highlight(
              id: 'h2',
              bookId: 'b1',
              style: HighlightStyle.underline,
              pdfPageIndex: 4,
            ),
          ),
        ],
      );

      expect(result, contains('## 🔖 書籤清單 (0)'));
      expect(result, contains('*(尚未加入書籤)*'));
      expect(result, contains('### 📌 底線（位置：第 5 頁）'));
      expect(result, isNot(contains('> ')));
    });

    test('只有純備註（無劃線）時，標籤顯示「備註」', () {
      final l10n = lookupAppLocalizations(const Locale('zh', 'TW'));
      final result = generateMarkdownExport(
        l10n: l10n,
        bookTitle: '備註書',
        progress: 0.6,
        exportTime: DateTime(2026, 1, 1),
        bookmarks: const [],
        annotations: [
          AnnotationListItem(
            note: const Note(id: 'n2', bookId: 'b1', text: '單純心得', progression: 0.6),
          ),
        ],
      );

      expect(result, contains('### 📌 備註（位置：60% 處）'));
      expect(result, contains('> 單純心得'));
    });

    test('書籤與劃線備註皆為空時，兩段落皆顯示空狀態文字', () {
      final l10n = lookupAppLocalizations(const Locale('zh', 'TW'));
      final result = generateMarkdownExport(
        l10n: l10n,
        bookTitle: '空書',
        progress: 0.0,
        exportTime: DateTime(2026, 1, 1),
        bookmarks: const [],
        annotations: const [],
      );

      expect(result, contains('## 🔖 書籤清單 (0)'));
      expect(result, contains('*(尚未加入書籤)*'));
      expect(result, contains('## ✏️ 劃線與個人備註 (0)'));
      expect(result, contains('*(尚未加入任何劃線或備註)*'));
    });

    test('英文介面下，系統結構文字與導出時間格式皆正確切換（書名/作者/位置標籤等使用者資料或既有機制產出文字不受影響）', () {
      final l10n = lookupAppLocalizations(const Locale('en'));
      final result = generateMarkdownExport(
        l10n: l10n,
        bookTitle: '紅樓夢',
        bookAuthor: '曹雪芹',
        progress: 0.35,
        exportTime: DateTime(2026, 7, 18),
        bookmarks: const [
          Bookmark(
            id: 'bm1',
            bookId: 'b1',
            name: '第二章 (35%)',
            epubLocatorJson: '{}',
            progression: 0.35,
          ),
        ],
        annotations: [
          AnnotationListItem(
            highlight: const Highlight(
              id: 'h1',
              bookId: 'b1',
              style: HighlightStyle.highlighterYellow,
              epubLocatorJson: '{}',
              progression: 0.2,
            ),
          ),
        ],
      );

      expect(result, contains('# Reading Notes: 紅樓夢'));
      expect(result, contains('**Author**: 曹雪芹'));
      expect(result, contains('**Reading Progress**: 35%'));
      expect(result, contains('**Export Time**: 7/18/2026'));
      expect(result, contains('## 🔖 Bookmarks (1)'));
      expect(result, contains('*   第二章 (35%)'));
      expect(result, contains('## ✏️ Highlights & Notes (1)'));
      // Bookmark.defaultName() 本身不在本 Issue 翻譯範圍（spec.md §7），
      // 「20% 處」在英文介面下仍是既有中文——這是刻意行為，不是遺漏。
      expect(result, contains('### 📌 Highlighter (Yellow) (Position: 20% 處)'));
    });

    test('英文介面下，作者缺省與書籤/劃線備註皆為空時，回退文字與空狀態文字皆正確切換', () {
      final l10n = lookupAppLocalizations(const Locale('en'));
      final result = generateMarkdownExport(
        l10n: l10n,
        bookTitle: 'Empty Book',
        progress: 0.0,
        exportTime: DateTime(2026, 1, 1),
        bookmarks: const [],
        annotations: const [],
      );

      expect(result, contains('**Author**: Unknown Author'));
      expect(result, contains('## 🔖 Bookmarks (0)'));
      expect(result, contains('*(No bookmarks yet)*'));
      expect(result, contains('## ✏️ Highlights & Notes (0)'));
      expect(result, contains('*(No highlights or notes yet)*'));
    });

    test('簡體中文介面下，系統結構文字、導出時間格式與純備註標籤皆正確切換', () {
      final l10n = lookupAppLocalizations(const Locale('zh', 'CN'));
      final result = generateMarkdownExport(
        l10n: l10n,
        bookTitle: '红楼梦',
        bookAuthor: '曹雪芹',
        progress: 0.35,
        exportTime: DateTime(2026, 7, 18),
        bookmarks: const [
          Bookmark(
            id: 'bm1',
            bookId: 'b1',
            name: '第二章 (35%)',
            epubLocatorJson: '{}',
            progression: 0.35,
          ),
        ],
        annotations: [
          AnnotationListItem(
            note: const Note(
              id: 'n2',
              bookId: 'b1',
              text: '单纯心得',
              progression: 0.6,
            ),
          ),
        ],
      );

      expect(result, contains('# 阅读笔记：《红楼梦》'));
      expect(result, contains('**作者**：曹雪芹'));
      expect(result, contains('**导出时间**：2026/7/18'));
      expect(result, contains('## 🔖 书签清单 (1)'));
      expect(result, contains('*   第二章 (35%)'));
      expect(result, contains('## ✏️ 划线与个人备注 (1)'));
      // Bookmark.defaultName() 本身不在本 Issue 翻譯範圍（spec.md §7），
      // 是寫死在 bookmark.dart 的繁體字面值，zh_CN 介面下仍是「處」而非
      // 簡體「处」——這是刻意行為，不是遺漏（比照上方英文測試同一原則）。
      expect(result, contains('### 📌 备注（位置：60% 處）'));
      expect(result, contains('> 单纯心得'));
    });
  });

  group('sanitizeMarkdownFileName', () {
    test('移除檔案系統不安全字元', () {
      expect(sanitizeMarkdownFileName('紅樓夢/夢?'), '紅樓夢_夢_');
    });

    test('清理後為空字串時回退為 book', () {
      expect(sanitizeMarkdownFileName('///'), 'book');
    });
  });
}
```

- [ ] **Step 3: 執行測試確認失敗**

Run: `cd app && flutter test test/reader/markdown_export_test.dart`
Expected: 編譯錯誤——`generateMarkdownExport()` 目前簽章沒有 `l10n` 具名參數，呼叫端會報 `The named parameter 'l10n' isn't defined`。

- [ ] **Step 4: 執行 `flutter gen-l10n` 確認 ARB 語法正確**

Run: `cd app && flutter gen-l10n`
Expected: 無錯誤輸出，`lib/l10n/app_localizations.dart` 新增 10 個對應方法/getter（含 `String markdownExportTitle(String bookTitle);` 等位置參數簽章）。

- [ ] **Step 5: 修改 `generateMarkdownExport()` 與兩個私有 helper**

把 `app/lib/reader/markdown_export.dart` 整個檔案改為：

```dart
import 'package:intl/intl.dart';

import '../l10n/app_localizations.dart';
import 'annotation_list_item.dart';
import 'bookmark.dart';
import 'bookmark_position_context.dart';
import 'highlight_style.dart';

/// 產生本書的 Markdown 筆記匯出內容（epic-6-annotations Issue 5，
/// spec.md／`prototype/index.html` `exportMarkdown()` 格式骨架）。純函式，
/// 不涉及檔案 I/O、不依賴 `BuildContext`——呼叫端（`NotesBottomSheet`）負責
/// 解析 [l10n]、寫檔與觸發分享（epic-45-interface-i18n Issue 8：[l10n] 用於
/// 在地化系統結構文字，書名/作者本身與 [Bookmark.defaultName] 產出的位置
/// 標籤維持不譯，見 spec.md §7）。
///
/// 與原型格式的刻意差異：本專案 [Highlight]／[Note] 從未儲存被選取的
/// 原文文字，劃線/備註條目改顯示「樣式標籤＋位置標籤」而非引用原文；
/// 位置標籤直接複用 [Bookmark.defaultName]（`chapterTitle` 留空，天然
/// 回退為進度百分比／頁碼），見 plan-issue-5.md Global Constraints。
String generateMarkdownExport({
  required AppLocalizations l10n,
  required String bookTitle,
  String? bookAuthor,
  required double progress,
  required DateTime exportTime,
  required List<Bookmark> bookmarks,
  required List<AnnotationListItem> annotations,
}) {
  final buffer = StringBuffer();
  buffer.writeln(l10n.markdownExportTitle(bookTitle));
  buffer.writeln(
    l10n.markdownExportAuthorLabel(bookAuthor ?? l10n.markdownExportUnknownAuthor),
  );
  buffer.writeln(l10n.markdownExportProgressLabel((progress * 100).round()));
  buffer.writeln(l10n.markdownExportTimeLabel(_formatDate(exportTime, l10n)));
  buffer.writeln();

  buffer.writeln(l10n.markdownExportBookmarksSection(bookmarks.length));
  if (bookmarks.isEmpty) {
    buffer.writeln(l10n.markdownExportNoBookmarks);
    buffer.writeln();
  } else {
    for (final bookmark in bookmarks) {
      buffer.writeln('*   ${bookmark.name}');
    }
    buffer.writeln();
  }

  buffer.writeln(l10n.markdownExportAnnotationsSection(annotations.length));
  if (annotations.isEmpty) {
    buffer.writeln(l10n.markdownExportNoAnnotations);
  } else {
    for (final item in annotations) {
      final highlight = item.highlight;
      final label = highlight != null
          ? _highlightStyleLabel(highlight.style, l10n)
          : l10n.readerNotesSheetNoteLabel;
      buffer.writeln(
        l10n.markdownExportAnnotationHeading(label, _positionLabel(item)),
      );
      final note = item.note;
      if (note != null) {
        buffer.writeln('> ${note.text}');
      }
      buffer.writeln();
    }
  }

  return buffer.toString();
}

/// 供匯出檔名使用，移除 Android 檔案系統不接受的字元；清理後為空字串時
/// 回退為 `book`，避免產生副檔名前無主檔名的檔案（例如 `.md`）。
String sanitizeMarkdownFileName(String title) {
  final sanitized = title.replaceAll(RegExp(r'[\\/:*?"<>|]'), '_').trim();
  return sanitized.isEmpty || RegExp(r'^_+$').hasMatch(sanitized)
      ? 'book'
      : sanitized;
}

/// 【私有，本檔案唯一消費端】劃線樣式的顯示標籤，委派給與
/// `notes_bottom_sheet.dart` 內部同名私有函式**相同**的 ARB key
/// （`readerHighlightStyleYellow` 等，epic-45-interface-i18n Issue 4 既有）
/// ——兩個檔案仍各自維持獨立的 Dart 函式（不抽出共用），沿用
/// `notes_bottom_sheet.dart` 既有 KDoc 記載的「純 UI 顯示標籤不放在領域
/// 模型檔案、收斂在消費端自己的私有函式」設計原則，本檔案延續同一原則、
/// 對稱處理；但底層翻譯文字改指向同一組全域 ARB key，避免兩處各自維護
/// 一份意義相同的翻譯字典（Issue 8 修訂，見 plan-issue-8.md）。
String _highlightStyleLabel(HighlightStyle style, AppLocalizations l10n) {
  switch (style) {
    case HighlightStyle.highlighterYellow:
      return l10n.readerHighlightStyleYellow;
    case HighlightStyle.highlighterPink:
      return l10n.readerHighlightStylePink;
    case HighlightStyle.highlighterBlue:
      return l10n.readerHighlightStyleBlue;
    case HighlightStyle.underline:
      return l10n.readerHighlightStyleUnderline;
  }
}

/// 複用 [Bookmark.defaultName] 換算劃線/備註的位置標籤——`pdfPageIndex`／
/// `progression` 與 [Bookmark]／[Highlight]／[Note] 三者欄位語意/命名完全
/// 一致，直接透傳即可，不重新實作換算邏輯。`chapterTitle` 刻意留空：
/// 逐筆劃線/備註即時反查所在章節需要額外貫穿 `TocEntry` 清單，超出本工單
/// 範疇，`Bookmark.defaultName` 對 `chapterTitle == null` 已有既定、已測試
/// 的百分比／頁碼回退行為（見 `bookmark.dart`）。[Bookmark.defaultName] 本身
/// 的輸出文字不在 Issue 8 翻譯範圍內（spec.md §7），故此函式不需要 [l10n]。
String _positionLabel(AnnotationListItem item) {
  final pdfPageIndex = item.highlight?.pdfPageIndex ?? item.note?.pdfPageIndex;
  final progression = item.highlight?.progression ?? item.note?.progression;
  return Bookmark.defaultName(BookmarkPositionContext(
    pdfPageIndex: pdfPageIndex,
    progression: progression,
  ));
}

/// 依目前介面語言格式化導出時間（epic-45-interface-i18n Issue 8，
/// `spec.md` §7：改用 `DateFormat.yMd(l10n.localeName)` 取代原本固定的
/// `y-m-d` 手動拼接）。本函式不依賴 `BuildContext`，用 [l10n] 的
/// `localeName`（已是 `Intl.canonicalizedLocale()` 正規化後的格式，例如
/// `zh_TW`）取得目前語言，比照 `sync_settings_screen.dart._formatLastSyncedAt()`
/// 既有的 `DateFormat.yMd(locale)` 模式，唯一差異是那裡用
/// `Localizations.localeOf(context)`（有 context 可用），這裡沒有 context。
String _formatDate(DateTime date, AppLocalizations l10n) {
  return DateFormat.yMd(l10n.localeName).format(date);
}
```

- [ ] **Step 6: 執行測試確認通過**

Run: `cd app && flutter test test/reader/markdown_export_test.dart`
Expected: 全數 PASS（既有 7 個測試＋本 Task 新增 3 個（英文正常路徑／英文空狀態與無作者回退／簡體中文）＝10 個）。

- [ ] **Step 7: `flutter analyze` 確認本檔案乾淨**

Run: `cd app && flutter analyze lib/reader/markdown_export.dart test/reader/markdown_export_test.dart`
Expected: `No issues found!`

- [ ] **Step 8: Commit**

```bash
git add app/lib/reader/markdown_export.dart app/test/reader/markdown_export_test.dart \
  app/lib/l10n/app_zh_TW.arb app/lib/l10n/app_zh_CN.arb app/lib/l10n/app_en.arb app/lib/l10n/app_zh.arb \
  app/lib/l10n/app_localizations.dart app/lib/l10n/app_localizations_en.dart app/lib/l10n/app_localizations_zh.dart
git commit -m "feat(epic-45): markdown_export.dart generateMarkdownExport() 接上 AppLocalizations"
```

---

### Task 2: `notes_bottom_sheet.dart`——呼叫端傳入 `l10n`

**Files:**
- Modify: `app/lib/screens/notes_bottom_sheet.dart`
- Test: `app/test/screens/notes_bottom_sheet_test.dart`

**Interfaces:**
- Consumes：Task 1 的 `generateMarkdownExport({required AppLocalizations l10n, ...})`。
- Produces：無新增公開介面（`_exportMarkdown()` 為既有私有方法，外部呼叫端不受影響）。

- [ ] **Step 1: 修改 `_exportMarkdown()`**

在 `app/lib/screens/notes_bottom_sheet.dart` 找到既有：

```dart
  Future<void> _exportMarkdown() async {
    try {
      final markdown = generateMarkdownExport(
        bookTitle: widget.bookTitle,
        bookAuthor: widget.bookAuthor,
        progress: widget.bookProgress,
        exportTime: DateTime.now(),
        bookmarks: _bookmarks,
        annotations: mergeAnnotations(_highlights, _notes),
      );
```

改為：

```dart
  Future<void> _exportMarkdown() async {
    // 由 IconButton onPressed 觸發（使用者操作，widget 必然已完整掛載），
    // 不受「initState() 存取 l10n 陷阱」鐵律限制，比照
    // library_group_management_dialog.dart._addGroup() 既有先例，在方法
    // 最前面同步取得即可，不需要額外 mounted 防衛（epic-45-interface-i18n
    // Issue 8）。
    final l10n = AppLocalizations.of(context)!;
    try {
      final markdown = generateMarkdownExport(
        l10n: l10n,
        bookTitle: widget.bookTitle,
        bookAuthor: widget.bookAuthor,
        progress: widget.bookProgress,
        exportTime: DateTime.now(),
        bookmarks: _bookmarks,
        annotations: mergeAnnotations(_highlights, _notes),
      );
```

（`AppLocalizations` 已是本檔案既有 import——`build()` 內第 189 行已呼叫 `AppLocalizations.of(context)!`，不需新增 import。）

- [ ] **Step 2: 既有測試零回歸確認**

`test/screens/notes_bottom_sheet_test.dart` 的 `_pumpSheet()` helper 本身已在 Issue 4 完整配置 `locale: const Locale('zh', 'TW')`／`localizationsDelegates`／`supportedLocales`（見該檔案第 41-46 行），不需要額外遷移。既有「點擊導出為 Markdown 按鈕後，正確寫入暫存檔案並呼叫 SharePlatform.share」測試斷言的匯出內容字串（`'# 閱讀筆記：《測試書籍》'`／`'**作者**：測試作者'`／`'**閱讀進度**：42%'`／`'*   第一章'`）與 Task 1 新 ARB key 的 `zh_TW` 譯文逐字相同，不需修改。

- [ ] **Step 3: 新增英文介面端到端整合測試**

僅靠「`l10n` 是 non-nullable 必要參數、漏傳會編譯失敗」不足以證明呼叫端**真的**從 `context` 解析 `l10n`——實作者仍可能寫成 `final l10n = lookupAppLocalizations(const Locale('zh', 'TW'));`（硬編碼、不讀 `context`），這樣一樣能編譯通過，且因為既有測試預設 locale 就是 `zh_TW`，一樣會全數綠燈。需要一個非預設語系的端到端測試才能真正驗證「畫面在英文介面下，匯出檔案內容也確實是英文」。在 `app/test/screens/notes_bottom_sheet_test.dart`，緊接在既有「點擊導出為 Markdown 按鈕後，正確寫入暫存檔案並呼叫 SharePlatform.share」測試（第 679-755 行）之後，新增（完整比照該測試已驗證過的 `runAsync`/Zone 處理方式，`FakePathProviderPlatform` 建構子需要 `tempDir.path` 參數，不可省略）：

```dart
  testWidgets('英文介面下點擊導出為 Markdown，寫出檔案內容確實切換為英文（驗證呼叫端真正從 context 解析 l10n，而非寫死語系）', (
    tester,
  ) async {
    final tempDir = (await tester.runAsync(
      () => Directory.systemTemp.createTemp('markdown_export_en_test'),
    ))!;
    addTearDown(() => tester.runAsync(() => tempDir.delete(recursive: true)));

    final originalPathProvider = PathProviderPlatform.instance;
    final originalSharePlatform = SharePlatform.instance;
    PathProviderPlatform.instance = FakePathProviderPlatform(tempDir.path);
    final fakeShare = FakeSharePlatform();
    SharePlatform.instance = fakeShare;
    addTearDown(() {
      PathProviderPlatform.instance = originalPathProvider;
      SharePlatform.instance = originalSharePlatform;
    });

    final repository = FakeBookmarksRepository();
    await repository.insert(
      const Bookmark(id: 'bm13', bookId: 'b1', name: 'Chapter 1', progression: 0.1),
    );

    await _pumpSheet(
      tester,
      repository: repository,
      bookTitle: 'Test Book',
      bookAuthor: 'Test Author',
      bookProgress: 0.42,
      locale: const Locale('en'),
    );

    await tester.runAsync(() async {
      await tester.tap(find.byKey(const Key('notes_sheet_export_markdown')));
      final deadline = DateTime.now().add(const Duration(seconds: 5));
      while (fakeShare.lastParams == null &&
          DateTime.now().isBefore(deadline)) {
        await Future<void>.delayed(const Duration(milliseconds: 20));
      }
    });
    await tester.pump();

    expect(fakeShare.lastParams, isNotNull);
    final files = fakeShare.lastParams!.files;
    expect(files, hasLength(1));
    final exportedFile = File(files!.single.path);
    final content = await tester.runAsync(() => exportedFile.readAsString());
    expect(content, contains('# Reading Notes: Test Book'));
    expect(content, contains('**Author**: Test Author'));
    expect(content, contains('**Reading Progress**: 42%'));
    expect(content, contains('*   Chapter 1'));
  });
```

- [ ] **Step 4: 執行測試確認通過**

Run: `cd app && flutter test test/screens/notes_bottom_sheet_test.dart`
Expected: 全數 PASS（既有測試零回歸＋本 Task 新增英文整合測試 1 個）。

- [ ] **Step 5: `flutter analyze` 確認乾淨**

Run: `cd app && flutter analyze lib/screens/notes_bottom_sheet.dart test/screens/notes_bottom_sheet_test.dart`
Expected: `No issues found!`

- [ ] **Step 6: Commit**

```bash
git add app/lib/screens/notes_bottom_sheet.dart app/test/screens/notes_bottom_sheet_test.dart
git commit -m "feat(epic-45): notes_bottom_sheet.dart 呼叫 generateMarkdownExport() 時傳入 l10n"
```

---

### Task 3: 最終驗證與文件收尾

**Files:**
- Modify: `docs/epics/epic-45-interface-i18n/issues.md`（標記 Issue 8 為 completed，記錄實際執行範圍修正）
- Modify: `docs/epics/epic-45-interface-i18n/epic.md`（新增 Issue 8 完成記錄）
- Modify: `docs/epics.md`（更新 epic-45 備註）

**Interfaces:**
- Consumes：Task 1-2 全部完成的狀態。
- Produces：Issue 8 完整收尾，供人類決定發 PR／合併。

- [ ] **Step 1: 執行完整 `flutter analyze`**

Run: `cd app && flutter analyze`
Expected: `No issues found!`

- [ ] **Step 2: 執行完整 `flutter test`**

Run: `cd app && flutter test`
Expected: 全數通過，較 Issue 7 收尾時記錄的測試總數增加（本 Issue 新增測試數＝Task 1 Step 2（英文正常路徑 1 個＋英文空狀態/無作者回退 1 個＋簡體中文 1 個＝3 個）＋Task 2 Step 3（英文端到端整合測試 1 個）＝4 個），無既有測試因本 Issue 回歸。

- [ ] **Step 3: 確認 ARB key 數量與四語言同步**

Run（分別對四份檔案執行，確認皆為 549）：
```bash
cd app && node -e "const d=JSON.parse(require('fs').readFileSync('lib/l10n/app_zh_TW.arb','utf8')); console.log(Object.keys(d).filter(k=>!k.startsWith('@')).length);"
node -e "const d=JSON.parse(require('fs').readFileSync('lib/l10n/app_zh_CN.arb','utf8')); console.log(Object.keys(d).filter(k=>!k.startsWith('@')).length);"
node -e "const d=JSON.parse(require('fs').readFileSync('lib/l10n/app_en.arb','utf8')); console.log(Object.keys(d).filter(k=>!k.startsWith('@')).length);"
node -e "const d=JSON.parse(require('fs').readFileSync('lib/l10n/app_zh.arb','utf8')); console.log(Object.keys(d).filter(k=>!k.startsWith('@')).length);"
```
Expected: 四份輸出皆為 `549`（539 + 10 新增 key；排除 `@key` metadata 條目的精確計數方式，比照 `reviews/review-issue-7.md` 訂正過的正確算法，不用容易誤算的 grep `'": "'` 計數法）。

- [ ] **Step 4: 確認 `reader_screen.dart`／`bookmark.dart` 零異動**

Run: `git diff main -- app/lib/screens/reader_screen.dart app/lib/reader/bookmark.dart`
Expected: 空 diff——本 Issue 未修改 `reader_screen.dart`，也未修改 `Bookmark.defaultName()` 本身（`spec.md` §7 明文排除）。

（前提是本 Issue 在獨立分支 `feat/epic-45-issue-8` 上開發，`main` 尚未快轉合併——比照 Issue 6/7 既定流程。若不慎直接在 `main` 上逐步 commit，`git diff main` 會因為 working tree 已與 `main` HEAD 同步而恆為空 diff、無法反映真實變更，此時改用 `git diff <本 Task 系列第一個 commit 的父 commit 的 SHA> -- ...` 或 `git diff origin/main -- ...`。）

- [ ] **Step 5: 更新 `issues.md`**

在 Issue 8 段落（`## Issue 8：Markdown 匯出契約變更` 之後）新增：

```markdown
**Status:** completed

**實際執行範圍修正記錄（認領時通讀全函式）**：原文建議新增「劃線樣式標籤 4 個 key」，實際查證 `notes_bottom_sheet.dart`（Issue 4 已在地化）內同名私有函式輸出文字與本檔案完全相同，且 Issue 4 已建立對應 ARB key（`readerHighlightStyleYellow`／`Pink`／`Blue`／`Underline`／`readerNotesSheetNoteLabel`），本 Issue 直接重用，不重複新增。另外發現 `spec.md` §7 條列清單遺漏 `'### 📌 $label（位置：...）'` 這行的「位置：」系統結構文字，補上新 key `markdownExportAnnotationHeading(label, position)`。實際新增 ARB key 為 9 個（`markdownExportTitle`／`markdownExportAuthorLabel`／`markdownExportUnknownAuthor`／`markdownExportProgressLabel`／`markdownExportTimeLabel`／`markdownExportBookmarksSection`／`markdownExportNoBookmarks`／`markdownExportAnnotationsSection`／`markdownExportNoAnnotations`）加上新發現的 `markdownExportAnnotationHeading` 共 10 個，重用既有 5 個 key。ARB 由 539 個 key 增至 549 個。
```

（若 `Status:` 欄位已存在則直接改值為 `completed`，不重複新增欄位。）

- [ ] **Step 6: 更新 `epic.md`**

在 `docs/epics/epic-45-interface-i18n/epic.md` 檔尾新增：

```markdown

**<今日日期> 完成 Issue 8 實作（`plans/plan-issue-8.md` 3 個 Task 全數落地）**：Markdown 匯出契約變更——`generateMarkdownExport()` 新增 `required AppLocalizations l10n` 參數，系統結構文字（標題／作者／進度／導出時間標籤、書籤/劃線備註區塊標題與空狀態文字、每筆劃線/備註的「位置」標題模板）全面改讀 ARB key，日期格式改用 `DateFormat.yMd(l10n.localeName)` 依目前介面語言格式化（不再固定 `y-m-d`）；書名/作者等使用者資料與 `Bookmark.defaultName()` 產出的位置標籤本身（該函式既有機制，`spec.md` §7 明文排除）不受影響。**範圍修正**：劃線樣式標籤（`螢光筆（黃/粉/藍）`／`底線`／`備註`）發現與 `notes_bottom_sheet.dart`（Issue 4）輸出文字完全相同且已有對應 ARB key，直接重用不重複新增；另發現 `spec.md` §7 遺漏「位置：」這行系統結構文字，補上新 key `markdownExportAnnotationHeading`。呼叫端 `notes_bottom_sheet.dart._exportMarkdown()`（使用者點擊觸發，非 `initState()`，不受 l10n 陷阱鐵律限制）改傳入 `AppLocalizations.of(context)!`，既有測試因 `_pumpSheet()` 早已配置在地化 delegate（Issue 4）而零遷移成本、零回歸；另新增一個英文介面端到端整合測試，實際驗證匯出檔案內容隨介面語言切換（純靠型別系統無法排除呼叫端誤寫死語系的風險，見 `reviews/review-plan-issue-8.md` I-3）。純 Dart 單元測試沿用 Issue 7 確立的 `lookupAppLocalizations(Locale)` 模式，並補齊簡體中文與英文空狀態/無作者回退案例（`reviews/review-plan-issue-8.md` I-2）；另實測發現並記錄一個測試環境陷阱——`DateFormat.yMd()` 在純 `test()` 環境需要顯式 `await initializeDateFormatting();`，否則拋出 `LocaleDataException`（與程式邏輯無關，純測試環境設定）。ARB 新增 10 個 key（539→549）。驗證結果：`flutter analyze` 乾淨（`No issues found!`）、全套 `flutter test` 通過（本 Issue 觸及的測試檔全數綠燈）。下一步：認領 Issue 9（收斂清理——其餘邊角測試檔遷移）或 Issue 10（防遺漏稽核腳本）。
```

- [ ] **Step 7: 更新 `docs/epics.md`**

找到 `epic-45-interface-i18n` 該列，把備註欄位：

```
| 46 | `epic-45-interface-i18n` 多語系介面（正體中文／簡體中文／英文，FR-49） | 🟡 開發中 (Active) | Issue 0-7 已完成，待認領 Issue 8 |
```

改為：

```
| 46 | `epic-45-interface-i18n` 多語系介面（正體中文／簡體中文／英文，FR-49） | 🟡 開發中 (Active) | Issue 0-8 已完成，待認領 Issue 9 |
```

- [ ] **Step 8: Commit**

```bash
git add docs/epics/epic-45-interface-i18n/issues.md docs/epics/epic-45-interface-i18n/epic.md docs/epics.md
git commit -m "docs(epic-45): 標記 Issue 8 為 completed，記錄實際執行範圍修正並更新 epic.md/epics.md"
```
