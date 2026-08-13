import 'package:flutter_test/flutter_test.dart';
import 'package:elinkbook/reader/epub_page_estimator.dart';

void main() {
  group('estimateCharsPerScreen', () {
    test(
        '參考情境（screenWidth=800/screenHeight=600，其餘皆用預設版面參數）'
        '換算出的每螢幕字元數（Issue 46：改用幾何模型，不再是舊版的 500 '
        '基準常數）', () {
      expect(
        EpubPageEstimator.estimateCharsPerScreen(
          screenWidth: 800,
          screenHeight: 600,
        ),
        1598,
      );
    });

    test('fontSize 加倍時，每行字數與每螢幕行數同時減少，可容納字元數大幅縮減', () {
      expect(
        EpubPageEstimator.estimateCharsPerScreen(
          screenWidth: 800,
          screenHeight: 600,
          fontSize: 2.0,
        ),
        391,
      );
    });

    test('lineHeight 加倍以上時，每螢幕行數依線性比例縮減，每行字數不受影響', () {
      expect(
        EpubPageEstimator.estimateCharsPerScreen(
          screenWidth: 800,
          screenHeight: 600,
          lineHeight: 3.0,
        ),
        517,
      );
    });

    test('lineHeight 為 0.0 時（epic-18-reader-device-qa Issue 25 行高滑桿範圍改為 '
        '0~3 後可選到的邊界值），不應除以零拋出 UnsupportedError，改箝制在 0.8'
        '（與 main.js:99 的 Math.max(0.8, prefs.lineHeight) 實際渲染下限一致，'
        '審查發現，2026-08-11：先前箝制在 0.1 會讓估算與實際渲染結果脫勾）',
        () {
      expect(
        () => EpubPageEstimator.estimateCharsPerScreen(
          screenWidth: 800,
          screenHeight: 600,
          lineHeight: 0.0,
        ),
        returnsNormally,
      );
      expect(
        EpubPageEstimator.estimateCharsPerScreen(
          screenWidth: 800,
          screenHeight: 600,
          lineHeight: 0.0,
        ),
        2021,
      );
    });

    test('fontSize 為 0.0 時，不應除以零拋出 UnsupportedError，改箝制在 0.1'
        '（審查發現，2026-08-11：與 lineHeight 為 0.0 是結構相同的失效模式，'
        '先前只有 lineHeight 有防護，fontSize 沒有）', () {
      expect(
        () => EpubPageEstimator.estimateCharsPerScreen(
          screenWidth: 800,
          screenHeight: 600,
          fontSize: 0.0,
        ),
        returnsNormally,
      );
      expect(
        EpubPageEstimator.estimateCharsPerScreen(
          screenWidth: 800,
          screenHeight: 600,
          fontSize: 0.0,
        ),
        20000,
      );
    });

    test('paragraphSpacing 為極端負值（-9.0）時，不應讓分母歸零拋出 '
        'UnsupportedError，改箝制在 0.0（審查發現，2026-08-11：'
        'paragraphSpacingFactor <= -9.0 會讓 1 + (paragraphSpacingFactor - 1) '
        '* 0.1 歸零）', () {
      expect(
        () => EpubPageEstimator.estimateCharsPerScreen(
          screenWidth: 800,
          screenHeight: 600,
          paragraphSpacing: -9.0,
        ),
        returnsNormally,
      );
      expect(
        EpubPageEstimator.estimateCharsPerScreen(
          screenWidth: 800,
          screenHeight: 600,
          paragraphSpacing: -9.0,
        ),
        1776,
      );
    });

    test(
        'marginLeft／marginRight 加倍時，可用寬度縮減、每行字數隨之減少'
        '（Issue 46：改讀真實 marginLeft/marginRight，取代已對 foliate-js 路徑'
        '失效的 pageMargins 欄位）', () {
      expect(
        EpubPageEstimator.estimateCharsPerScreen(
          screenWidth: 800,
          screenHeight: 600,
          marginLeft: 48,
          marginRight: 48,
        ),
        1496,
      );
    });

    test('marginTop／marginBottom 加倍時，可用高度縮減、每螢幕行數隨之減少'
        '（Issue 46 新增：舊版 pageMargins 是單一倍率、不區分上下左右，'
        '無法表達「只有上下邊距變動」這個情境）', () {
      expect(
        EpubPageEstimator.estimateCharsPerScreen(
          screenWidth: 800,
          screenHeight: 600,
          marginTop: 64,
          marginBottom: 32,
        ),
        1457,
      );
    });

    test(
        '相同版面參數下，螢幕尺寸加倍時可容納字元數應大幅增加（Issue 46 核心'
        '回歸測試：證明舊版公式「完全忽略螢幕尺寸」的精準度缺口已修復——'
        '手機與平板讀同一本書，在相同版面設定下不應估出相同頁數）', () {
      final reference = EpubPageEstimator.estimateCharsPerScreen(
        screenWidth: 800,
        screenHeight: 600,
      );
      final doubledScreen = EpubPageEstimator.estimateCharsPerScreen(
        screenWidth: 1600,
        screenHeight: 1200,
      );
      expect(doubledScreen, greaterThan(reference * 3));
      expect(doubledScreen, 6984);
    });

    test('letterSpacing 為正值時，每行可容納字元數減少、可容納字元數隨之縮減'
        '（epic-28-reader-settings-enhancements Issue 1 審查發現：新增字距'
        '選項後，估算公式原本完全沒有納入這個版面密度變數，與 lineHeight／'
        'paragraphSpacing 等既有欄位不一致）', () {
      expect(
        EpubPageEstimator.estimateCharsPerScreen(
          screenWidth: 800,
          screenHeight: 600,
          letterSpacing: 1.0,
        ),
        782,
      );
    });

    test('letterSpacing 為負值（滑桿允許的下限 -0.05）時，每行可容納字元數增加', () {
      expect(
        EpubPageEstimator.estimateCharsPerScreen(
          screenWidth: 800,
          screenHeight: 600,
          letterSpacing: -0.05,
        ),
        1666,
      );
    });

    test('letterSpacing 為極端負值（-9.0）時，不應讓每字元有效寬度歸零或變負值'
        '拋出例外，改箝制在 0.1（與 fontSize／lineHeight 既有防呆同一種'
        '失效模式）', () {
      expect(
        () => EpubPageEstimator.estimateCharsPerScreen(
          screenWidth: 800,
          screenHeight: 600,
          letterSpacing: -9.0,
        ),
        returnsNormally,
      );
      expect(
        EpubPageEstimator.estimateCharsPerScreen(
          screenWidth: 800,
          screenHeight: 600,
          letterSpacing: -9.0,
        ),
        15980,
      );
    });

    test('極端字體大小（超出可視寬度）時，結果被箝制在下限 50，不會估算出荒謬的總頁數', () {
      expect(
        EpubPageEstimator.estimateCharsPerScreen(
          screenWidth: 800,
          screenHeight: 600,
          fontSize: 50.0,
        ),
        50,
      );
    });
  });

  group('estimateTotalPages', () {
    test('字元數恰為整數倍時，總頁數為該倍數', () {
      expect(
        EpubPageEstimator.estimateTotalPages(
          totalCharacterCount: 1000,
          charsPerScreen: 500,
        ),
        2,
      );
    });

    test('字元數有餘數時，無條件進位', () {
      expect(
        EpubPageEstimator.estimateTotalPages(
          totalCharacterCount: 1001,
          charsPerScreen: 500,
        ),
        3,
      );
    });

    test('全書字元數為 0 時，至少回傳 1 頁', () {
      expect(
        EpubPageEstimator.estimateTotalPages(
          totalCharacterCount: 0,
          charsPerScreen: 500,
        ),
        1,
      );
    });
  });

  group('estimateCurrentPage', () {
    test('progression 為 null 時，回傳第 1 頁', () {
      expect(
        EpubPageEstimator.estimateCurrentPage(progression: null, totalPages: 10),
        1,
      );
    });

    test('progression 為 0.0 時，箝制在第 1 頁（不是第 0 頁）', () {
      expect(
        EpubPageEstimator.estimateCurrentPage(progression: 0.0, totalPages: 10),
        1,
      );
    });

    test('progression 為 0.5 時，回傳中間頁碼', () {
      expect(
        EpubPageEstimator.estimateCurrentPage(progression: 0.5, totalPages: 10),
        5,
      );
    });

    test('progression 為 1.0 時，回傳最後一頁', () {
      expect(
        EpubPageEstimator.estimateCurrentPage(progression: 1.0, totalPages: 10),
        10,
      );
    });
  });

  group('estimateProgression', () {
    test('目標頁碼換算成該頁區間中點的全書進度比例', () {
      expect(
        EpubPageEstimator.estimateProgression(targetPage: 5, totalPages: 10),
        0.45,
      );
    });

    test('第 1 頁換算出的比例仍在 [0,1] 範圍內', () {
      expect(
        EpubPageEstimator.estimateProgression(targetPage: 1, totalPages: 10),
        0.05,
      );
    });

    test('estimateProgression 與 estimateCurrentPage 互為反函式（往返後頁碼不變）', () {
      const totalPages = 10;
      for (var page = 1; page <= totalPages; page++) {
        final progression = EpubPageEstimator.estimateProgression(
          targetPage: page,
          totalPages: totalPages,
        );
        final roundTripPage = EpubPageEstimator.estimateCurrentPage(
          progression: progression,
          totalPages: totalPages,
        );
        expect(roundTripPage, page, reason: '第 $page 頁往返後應保持不變');
      }
    });
  });
}
