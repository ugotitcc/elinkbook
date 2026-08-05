import 'package:flutter_test/flutter_test.dart';
import 'package:elinkbook/reader/epub_page_estimator.dart';

void main() {
  group('estimateCharsPerScreen', () {
    test('全部參數皆為 null 時，採用預設版面參數，回傳基準值', () {
      expect(EpubPageEstimator.estimateCharsPerScreen(), 500);
    });

    test('fontSize 加倍時，每螢幕可容納字元數依平方比例縮減', () {
      expect(
        EpubPageEstimator.estimateCharsPerScreen(fontSize: 2.0),
        125,
      );
    });

    test('lineHeight 加倍時，每螢幕可容納字元數依線性比例縮減', () {
      expect(
        EpubPageEstimator.estimateCharsPerScreen(lineHeight: 3.0),
        250,
      );
    });

    test('lineHeight 為 0.0 時（epic-18-reader-device-qa Issue 25 行高滑桿範圍改為 '
        '0~3 後可選到的邊界值），不應除以零拋出 UnsupportedError，改回傳箝制後的上限值',
        () {
      expect(
        () => EpubPageEstimator.estimateCharsPerScreen(lineHeight: 0.0),
        returnsNormally,
      );
      expect(
        EpubPageEstimator.estimateCharsPerScreen(lineHeight: 0.0),
        EpubPageEstimator.referenceCharsPerScreen * 4,
      );
    });

    test('pageMargins 加倍時，可容納字元數依較低權重縮減', () {
      expect(
        EpubPageEstimator.estimateCharsPerScreen(pageMargins: 2.0),
        417,
      );
    });

    test('極端字體大小時，結果被箝制在下限 50，不會估算出荒謬的總頁數', () {
      expect(
        EpubPageEstimator.estimateCharsPerScreen(fontSize: 10.0),
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
