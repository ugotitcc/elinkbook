import 'book_reader_prefs.dart';
import 'reading_defaults.dart';
import 'text_conversion_mode.dart';

/// 解析單一書籍實際生效的簡繁顯示轉換模式（FR-48）：[book] 的單書覆寫值
/// 存在時優先採用，否則回退 [global] 的全域預設值。
///
/// 獨立頂層純函式（不併入 `ReaderPrefsManagerImpl.resolve()`／
/// `ResolvedPreferences`）——Issue 2-5 的呼叫點（JS DOM Walker 偏好注入、
/// 目錄/書籤/劃線清單、書架畫面、全文檢索結果清單、TTS 朗讀段）多數不持有
/// 完整 `ResolvedPreferences`，只持有 [BookReaderPrefs]／[ReadingDefaults]，
/// 比照既有 `resolveZoneActions()` 頂層純函式先例。此簽章為 Issue 1-5 共用
/// 的固定介面，不得更動參數順序或型別。
TextConversionMode resolveTextConversion(
  BookReaderPrefs book,
  ReadingDefaults global,
) {
  return book.textConversionOverride ?? global.textConversion;
}
