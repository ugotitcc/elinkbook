import 'dart:math' as math;

import 'text_conversion_dict.dart';
import 'text_conversion_mode.dart';
import 'text_offset_map.dart';

/// 片語比對時，單一詞條 code point 數的安全上限——必須與
/// `app/tool/generate_conversion_dicts.js` 的 `MAX_PHRASE_KEY_LENGTH`、
/// `text-conversion.js` 的 `MAX_PHRASE_KEY_LENGTH` 保持一致（目前皆為
/// 16）。目前已知最長詞條為 `TWPhrases.txt` 的 15 碼，留有餘裕；
/// `assertMaxPhraseKeyLength()`（生成腳本）是唯一防線，若字典來源檔未來
/// 新增更長詞條，生成階段會立刻拋例外中止，而非讓這裡靜默漏未比對到。
const int kMaxPhraseKeyLength = 16;

/// 依 [mode] 對 [input] 做簡繁字元/片語轉換，回傳最終顯示文字，與（若有
/// 任何區段長度改變）對應的 [TextOffsetMap]。
///
/// **`toTraditional` 與 `toSimplified` 的片語比對基準不同，兩者不對稱**
/// （2026-09-15 依 `reviews/review-plan-issue-0b.md` Issue C-1 修訂——先前
/// 草稿誤將兩者套用相同的兩階段設計，已對照真實 OpenCC
/// `conversionChain` 設定與 `opencc-js` 實際輸出推翻，見
/// `docs/epics/epic-42-text-conversion/plans/plan-issue-0b.md` Self-Review
/// 「關鍵技術驗證」）：
/// - **`toTraditional`（兩階段）**：**Stage 1** 逐 code point 以 [kS2tDict]
///   （Issue 0 既有，生成階段已保證 ΔL=0）轉換出「中繼文字」，與 [input]
///   在 code point 索引與 UTF-16 offset 上完全對齊；**Stage 2** 在中繼
///   文字上做 [kS2twpPhraseDict]（`TWPhrases`）最長匹配（由長至短嘗試，
///   長度上限 [kMaxPhraseKeyLength]）——`TWPhrases.txt` 的鍵是「單字元
///   轉換後」的繁體形態（例如鍵是「內存」不是「内存」），必須先做 Stage 1
///   才能命中。
/// - **`toSimplified`（單一階段）**：直接對**原始輸入** [input] 做
///   [kTw2sPhraseDict]（`TSPhrases`）最長匹配，找不到片語才逐 code point
///   退回 [kT2sDict] 單字元轉換——`TSPhrases.txt` 的鍵是**原始（未字元
///   轉換）**的繁體形態，且常用來保護固定用語不被單字元規則誤轉（例如
///   `TSCharacters.txt` 把「乾」轉成「干」，但「乾隆\t乾隆」這條 `TSPhrases`
///   規則保護「乾隆」這個詞不被誤轉成「干隆」）。若先做字元轉換再比對
///   片語（`toTraditional` 的做法），片語字典的鍵永遠比對不到，繁轉簡
///   消歧功能會被架構性地閹割掉。
({String text, TextOffsetMap? offsetMap}) convertTextDetailed(
  String input,
  TextConversionMode mode,
) {
  if (mode == TextConversionMode.original || input.isEmpty) {
    return (text: input, offsetMap: null);
  }

  final units = input.runes.map(String.fromCharCode).toList(growable: false);

  final List<String> matchUnits;
  final Map<String, String> charDict;
  final Map<String, String> phraseDict;
  if (mode == TextConversionMode.toTraditional) {
    charDict = kS2tDict;
    phraseDict = kS2twpPhraseDict;
    // Stage 1：先逐字元轉換出中繼文字，片語比對對中繼文字做（見上方
    // 文件註解）。
    matchUnits = units.map((ch) => charDict[ch] ?? ch).toList(growable: false);
  } else {
    charDict = kT2sDict;
    phraseDict = kTw2sPhraseDict;
    // toSimplified：片語比對直接對原始輸入做，不做字元轉換的中繼文字
    // （見上方文件註解，審查修正 C-1）。
    matchUnits = units;
  }

  final buffer = StringBuffer();
  final builder = OffsetMapBuilder();
  var origOffset = 0;
  var dispOffset = 0;
  var i = 0;

  while (i < matchUnits.length) {
    final maxLen = math.min(kMaxPhraseKeyLength, matchUnits.length - i);
    String? matchedValue;
    var matchedLen = 0;
    for (var len = maxLen; len >= 1; len--) {
      final candidate = matchUnits.sublist(i, i + len).join();
      final value = phraseDict[candidate];
      if (value != null) {
        matchedValue = value;
        matchedLen = len;
        break;
      }
    }

    final consumedCount = matchedValue != null ? matchedLen : 1;
    final origSegment = matchUnits.sublist(i, i + consumedCount).join();
    // toTraditional：origSegment 已是 Stage 1 轉換後的中繼文字，找不到
    // 片語時直接沿用。toSimplified：origSegment 是原始未轉換文字，找不到
    // 片語時才在此對單一 code point 套用 charDict。
    final dispSegment = matchedValue ??
        (mode == TextConversionMode.toTraditional
            ? origSegment
            : (charDict[origSegment] ?? origSegment));

    buffer.write(dispSegment);
    if (dispSegment.length != origSegment.length) {
      builder.addSegment(
        origOffset: origOffset,
        origLen: origSegment.length,
        dispOffset: dispOffset,
        dispLen: dispSegment.length,
      );
    }
    origOffset += origSegment.length;
    dispOffset += dispSegment.length;
    i += consumedCount;
  }

  return (text: buffer.toString(), offsetMap: builder.build());
}

/// 依 [mode] 對 [input] 做簡繁字元/片語轉換，只回傳顯示文字（不需要
/// [TextOffsetMap] 的既有呼叫端使用，例如目錄/書籤/劃線清單、書架書名、
/// 搜尋結果摘要片段、TTS 朗讀段——這些情境不涉及 DOM Range／CFI 座標
/// 換算）。此簽章為 Issue 0 定案的固定介面，不得更動參數順序或型別
/// （Issue 1-5 直接依賴）。
String convertText(String input, TextConversionMode mode) =>
    convertTextDetailed(input, mode).text;
