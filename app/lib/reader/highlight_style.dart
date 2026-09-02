import 'package:flutter/material.dart';

import '../theme/elink_tokens.dart';

/// 純備註（無劃線）的固定畫面指示色（design.md 決策 #2「淡灰底」，見
/// Global Constraints「純備註視覺簡化」）。不在 epic-35-design-system-tokens
/// 遷移範圍——`ElinkTokens` 未定義對應欄位，維持既有寫死值。
const noteOnlyTint = Color(0x73D1D5DB);

/// 劃線樣式（epic-6-annotations Issue 2，spec.md「劃線與備註模組」）：
/// 螢光筆三色（背景底色填滿）與底線（波浪底線，跟隨主題色）為 4 個互斥值，
/// 非「樣式＋顏色」兩個獨立維度——避免「底線＋顏色」這種 design.md 決策
/// #5 明確排除的無效狀態組合。持久化時使用 `.name`（比照既有
/// `PdfCropMode`/`WritingMode` 等列舉的既有慣例，見 book_reader_prefs.dart
/// 的 `Enum.values.byName()` 既有寫法）。
///
/// 【epic-35-design-system-tokens Issue 4】列舉不再攜帶編譯期色票常數——
/// 色值改由 [highlightStyleColor] 於執行期透過 `ElinkTokens` 解析，因為
/// `ElinkTokens` 只有 `Theme.of(context)` 才能取得，不可能收斂為列舉的
/// 編譯期欄位。**列舉成員名稱維持不變**（含 `highlighterPink` 即使視覺上
/// 對應綠色）——改名會讓 `Enum.values.byName()` 持久化的既有使用者資料
/// （劃線樣式）反序列化失敗；「這個樣式渲染出來是什麼顏色」跟「這個樣式的
/// 識別字串是什麼」是兩件事，不需要同步改。純 UI 顯示標籤（例如「螢光筆
/// （黃）」）不放在這個檔案——見 `notes_bottom_sheet.dart` 的
/// `_highlightStyleLabel()`。
enum HighlightStyle {
  highlighterYellow,
  highlighterPink,
  highlighterBlue,
  underline,
}

/// 依樣式解析出對應的 [ElinkTokens] 顏色（`highlighterPink` 對應
/// `tokens.highlightGreen`，語意變更，`DESIGN.md` §1.2 既有決策）。純函式，
/// 呼叫端自行從 `Theme.of(context).extension<ElinkTokens>()!` 取得
/// [tokens]。原生 Decoration API 需要的 `int` ARGB32 值由呼叫端自行呼叫
/// `.toARGB32()`（見 Global Constraints「色彩決策收斂在 Dart 端」）。
Color highlightStyleColor(
  HighlightStyle style, {
  required ElinkTokens tokens,
}) {
  switch (style) {
    case HighlightStyle.highlighterYellow:
      return tokens.highlightYellow;
    case HighlightStyle.highlighterPink:
      return tokens.highlightGreen;
    case HighlightStyle.highlighterBlue:
      return tokens.highlightBlue;
    case HighlightStyle.underline:
      return tokens.underlineColor;
  }
}
