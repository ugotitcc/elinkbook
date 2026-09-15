import 'package:flutter_test/flutter_test.dart';
import 'package:elinkbook/reader/text_conversion.dart';
import 'package:elinkbook/reader/text_conversion_mode.dart';
import 'package:elinkbook/reader/text_offset_map.dart';

void main() {
  group('convertText', () {
    test('original 模式原樣回傳', () {
      expect(convertText('国电脑', TextConversionMode.original), '国电脑');
    });

    test('toTraditional 轉換已知簡體字元', () {
      expect(convertText('国', TextConversionMode.toTraditional), '國');
      expect(convertText('电脑', TextConversionMode.toTraditional), '電腦');
    });

    test('toSimplified 轉換已知繁體字元', () {
      expect(convertText('國', TextConversionMode.toSimplified), '国');
      expect(convertText('電腦', TextConversionMode.toSimplified), '电脑');
    });

    test('多對一併字取首個候選字（真實 OpenCC 資料：「后」「干」案例）', () {
      // STCharacters.txt：后 -> 後 后（取「後」）；干 -> 幹 乾 干 榦（取「幹」）。
      expect(convertText('后', TextConversionMode.toTraditional), '後');
      expect(convertText('干', TextConversionMode.toTraditional), '幹');
    });

    test('查找表找不到的字元維持原樣', () {
      expect(
        convertText('ABC123', TextConversionMode.toTraditional),
        'ABC123',
      );
    });

    test('轉換不改變 UTF-16 長度與 code point 數量（ΔL=0，ADR 0030 核心不變量，審查修正 C-1）', () {
      const input = '国电脑后干发里';
      final converted =
          convertText(input, TextConversionMode.toTraditional);
      expect(converted.length, input.length,
          reason: 'UTF-16 code unit 長度不可改變（epubcfi.js Range offset 計算基準）');
      expect(converted.runes.length, input.runes.length,
          reason: 'Unicode code point 數量不可改變');
    });

    test('空字串原樣回傳（審查修正 I-1）', () {
      expect(convertText('', TextConversionMode.toTraditional), '');
      expect(convertText('', TextConversionMode.original), '');
    });

    test('英數/標點/中文混排字串只轉換中文部分（審查修正 I-1）', () {
      expect(
        convertText('Hello 电脑, 世界！123', TextConversionMode.toTraditional),
        'Hello 電腦, 世界！123',
      );
    });

    test('含代理對字元（輔助平面／emoji）的字串不拋例外、原樣保留（審查修正 I-1）', () {
      // '😀'（U+1F600）與 '𠗣'（U+205E3）皆需代理對編碼，兩者都不在查找表
      // 中（查找表已在生成階段排除 BMP↔輔助平面配對，見 Task 3），
      // convertText 走訪 runes 時須正確處理、不拋例外、原樣保留。
      const input = '国😀𠗣电';
      final converted = convertText(input, TextConversionMode.toTraditional);
      expect(converted, '國😀𠗣電');
      expect(converted.length, input.length);
    });

    test('toTraditional 片語轉換：台灣常用詞優先於單字元查找表（Issue 0b）', () {
      // TWPhrases.txt：內存 -> 記憶體。純字元轉換只會得到「內存」，
      // 缺少台灣在地化，須靠片語比對。
      expect(convertText('内存', TextConversionMode.toTraditional), '記憶體');
    });

    test('toTraditional 片語轉換：單字元長度的 TWPhrases 詞條（Issue 0b）', () {
      // TWPhrases.txt 有 12 條單字詞條，「硅」不在 STCharacters.txt 中，
      // 純字元查找表無法轉換，須靠片語字典（即使長度為 1）才能正確轉換。
      expect(convertText('硅', TextConversionMode.toTraditional), '矽');
    });

    test(
        'toSimplified 片語轉換：TSPhrases 直接對原文做最長匹配（Issue 0b，'
        '審查修正 C-1）', () {
      // TSPhrases.txt：一目瞭然 -> 一目了然。toSimplified 與 toTraditional
      // 的片語比對基準不同（見本檔案頂部 Architecture 說明）——TSPhrases
      // 的鍵是「原始輸入」的形態，直接對 input 做最長匹配，不對字元轉換
      // 後的中繼文字做。
      expect(
        convertText('一目瞭然', TextConversionMode.toSimplified),
        '一目了然',
      );
    });

    test(
        'toSimplified 片語轉換：TSPhrases 保護固定用語不被單字元規則誤轉'
        '（Issue 0b，審查修正 C-1 核心回歸案例）', () {
      // kT2sDict 對「乾」的單字元規則是「乾->干」（TSCharacters.txt：
      // 乾\t干 乾，取首個候選字）。若先對原文做字元轉換再比對片語（錯誤
      // 的兩階段設計），「乾隆」會在字元轉換階段就被誤轉成「干隆」，
      // TSPhrases 的「乾隆->乾隆」保護規則永遠比對不到，最終輸出錯字
      // 「干隆皇帝」。必須直接對原文「乾隆」做片語最長匹配才能正確保護
      // （見 reviews/review-plan-issue-0b.md Issue C-1，已用 opencc-js
      // 實際輸出驗證：tw2s('乾隆皇帝') === '乾隆皇帝'）。
      expect(
        convertText('乾隆皇帝', TextConversionMode.toSimplified),
        '乾隆皇帝',
      );
      expect(
        convertText('乾坤大挪移', TextConversionMode.toSimplified),
        '乾坤大挪移',
      );
    });

    test(
        'toSimplified：妥瑞氏症原樣保留，不套用大陸用語替換（Issue 0b，審查修正 '
        'I-1，ADR 0032 靈魂驗證案例）', () {
      // 「妥瑞氏症」在 OpenCC 的 tw2sp（含大陸用語）會被強制改寫為
      // 「抽动秽语综合征」，但本 Epic 採 tw2s（不套用大陸用語），必須
      // 忠實保留台灣慣用譯名。
      expect(
        convertText('妥瑞氏症', TextConversionMode.toSimplified),
        '妥瑞氏症',
      );
    });

    test('convertText 對片語轉換的輸出與 convertTextDetailed 一致（Issue 0b）', () {
      const input = '把内存清空';
      expect(
        convertText(input, TextConversionMode.toTraditional),
        convertTextDetailed(input, TextConversionMode.toTraditional).text,
      );
    });
  });

  group('convertTextDetailed（Issue 0b）', () {
    test('片語轉換長度改變時，產生正確的 TextOffsetMap', () {
      final result =
          convertTextDetailed('内存', TextConversionMode.toTraditional);
      expect(result.text, '記憶體');
      expect(result.offsetMap, isNotNull);
      expect(result.offsetMap!.entries, hasLength(1));
      final entry = result.offsetMap!.entries.single;
      expect(entry.origOffset, 0);
      expect(entry.origLen, 2);
      expect(entry.dispOffset, 0);
      expect(entry.dispLen, 3);
    });

    test('長度不變時，offsetMap 為 null（零開銷路徑）', () {
      final result =
          convertTextDetailed('国电脑', TextConversionMode.toTraditional);
      expect(result.text, '國電腦');
      expect(result.offsetMap, isNull);
    });

    test('original 模式：offsetMap 恆為 null', () {
      final result =
          convertTextDetailed('内存', TextConversionMode.original);
      expect(result.text, '内存');
      expect(result.offsetMap, isNull);
    });

    test('片語與前後文字混排時，offset 計算正確', () {
      // "把内存清空" -> "把記憶體清空"："内存"@origOffset=1,origLen=2 轉為
      // "記憶體"@dispOffset=1,dispLen=3；前後的「把」「清空」逐字元不變。
      final result =
          convertTextDetailed('把内存清空', TextConversionMode.toTraditional);
      expect(result.text, '把記憶體清空');
      final entry = result.offsetMap!.entries.single;
      expect(entry.origOffset, 1);
      expect(entry.origLen, 2);
      expect(entry.dispOffset, 1);
      expect(entry.dispLen, 3);
      // 原文「空」在 index 4，顯示文字中「空」在 index 5（多了一個字）。
      expect(origToDisplay(result.offsetMap, 4), 5);
    });

    test(
        '代理對字元位於片語前時，offset 以 UTF-16 code unit 正確計量'
        '（Issue 0b，審查修正 I-2）', () {
      // '𠮷'（U+20BB7）佔 2 個 UTF-16 code unit。"内存" 這個片語的
      // origOffset／dispOffset 必須是 2（UTF-16 offset）而非 1（code
      // point 索引）——Dart（runes）與 JS（Array.from）對代理對的正確
      // 處理，若把「code point 索引」與「UTF-16 offset」混淆會產生隱蔽
      // 的偏移 bug，此測試明確覆蓋這個邊界。
      final result =
          convertTextDetailed('𠮷内存', TextConversionMode.toTraditional);
      expect(result.text, '𠮷記憶體');
      expect(result.offsetMap, isNotNull);
      final entry = result.offsetMap!.entries.single;
      expect(entry.origOffset, 2);
      expect(entry.origLen, 2);
      expect(entry.dispOffset, 2);
      expect(entry.dispLen, 3);
    });
  });
}
