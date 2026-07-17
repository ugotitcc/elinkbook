import 'package:flutter/material.dart';

/// 螢光筆固定色票（design.md 決策 #5），色值換算自
/// `prototype/index.html` 既有 `.highlight-yellow`/`-pink`/`-blue` 的
/// CSS `rgba(..., 0.45)`（45% 透明度 ≈ 0x73/0xFF）。宣告在列舉之前，
/// 供下方列舉建構子直接參照（Dart 頂層宣告不受檔案內文字順序限制）。
const highlighterYellowTint = Color(0x73FDE047);
const highlighterPinkTint = Color(0x73F472B6);
const highlighterBlueTint = Color(0x7360A5FA);

/// 純備註（無劃線）的固定畫面指示色（design.md 決策 #2「淡灰底」，見
/// Global Constraints「純備註視覺簡化」）。
const noteOnlyTint = Color(0x73D1D5DB);

/// 劃線樣式（epic-6-annotations Issue 2，spec.md「劃線與備註模組」）：
/// 螢光筆三色（背景底色填滿）與底線（波浪底線，固定主題 primary 色）為
/// 4 個互斥值，非「樣式＋顏色」兩個獨立維度——避免「底線＋顏色」這種
/// design.md 決策 #5 明確排除的無效狀態組合。持久化時使用 `.name`（比照
/// 既有 `PdfCropMode`/`WritingMode` 等列舉的既有慣例，見
/// book_reader_prefs.dart 的 `Enum.values.byName()` 既有寫法）。
///
/// 【審查修正】[fixedTint] 由列舉本身攜帶固定色票（螢光筆三色），
/// `underline` 為 `null`（其色值是執行期才知道的目前主題 primary
/// 色，非編譯期常數，不可能收斂為列舉欄位）——取代原本 `highlightStyleTint`
/// 對 4 個值各自 `switch` 一次的寫法，把「這個樣式對應哪個固定色票」這件
/// 事收斂成列舉自身的資料，而非外部函式的重複分支邏輯。純 UI 顯示標籤
/// （例如「螢光筆（黃）」）刻意不放在這個檔案——`reader/` 目錄下的其他
/// 列舉（`BookFormat`／`WritingMode`／`PdfCropMode` 等）皆不含 UI 顯示
/// 字串，是純格式無關的領域模型；標籤是唯一消費端 `NotesBottomSheet`
/// 自己的呈現邏輯，收斂在該檔案內的私有函式（見 Task 7），避免領域模型
/// 檔案摻雜 UI 層級的字串常數。
enum HighlightStyle {
  highlighterYellow(highlighterYellowTint),
  highlighterPink(highlighterPinkTint),
  highlighterBlue(highlighterBlueTint),
  underline(null);

  /// 固定色票；`null` 代表色值需由呼叫端於執行期決定（僅 `underline`
  /// 如此，見 [highlightStyleTint]）。
  final Color? fixedTint;

  const HighlightStyle(this.fixedTint);
}

/// 依樣式＋目前主題 primary 色，換算成原生 Decoration API 所需的完整
/// ARGB `int` 色值（Dart `Color.toARGB32()`〔審查修正：`Color.value` 已於
/// Flutter SDK deprecated，`toARGB32()` 是行為完全相同的替代方法〕與 Android
/// `Color` int 皆為 `0xAARRGGBB` 版面，可直接透傳給原生端，見 Global
/// Constraints「色彩決策收斂在 Dart 端」）。純函式，不依賴 `BuildContext`
/// ——呼叫端自行讀取 `Theme.of(context).colorScheme.primary` 後傳入，維持
/// 本函式可獨立單元測試。實作本身不再需要 `switch`——[HighlightStyle.fixedTint]
/// 非 null 時直接採用，僅 `underline`（`fixedTint == null`）才退回呼叫端
/// 傳入的 [primaryColor]。
int highlightStyleTint(HighlightStyle style, {required Color primaryColor}) {
  return (style.fixedTint ?? primaryColor).toARGB32();
}
