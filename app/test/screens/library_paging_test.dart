import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:elinkbook/screens/library_paging.dart';

void main() {
  test('libraryPageSizeForOrientation：portrait 回傳 3，landscape 回傳 4', () {
    expect(libraryPageSizeForOrientation(Orientation.portrait), 3);
    expect(libraryPageSizeForOrientation(Orientation.landscape), 4);
  });

  test('libraryPageCount：itemCount 為 0 時回傳 1（避免空頁面／除以零）', () {
    expect(libraryPageCount(0, 3), 1);
    expect(libraryPageCount(0, 4), 1);
  });

  test('libraryPageCount：一般情況無條件進位', () {
    expect(libraryPageCount(10, 3), 4);
    expect(libraryPageCount(9, 3), 3);
    expect(libraryPageCount(1, 4), 1);
    expect(libraryPageCount(4, 4), 1);
    expect(libraryPageCount(5, 4), 2);
  });

  test('libraryClampPage：頁碼超出範圍時箝制在有效區間內', () {
    expect(libraryClampPage(5, 4), 3);
    expect(libraryClampPage(-1, 4), 0);
    expect(libraryClampPage(2, 4), 2);
    expect(libraryClampPage(0, 1), 0);
  });

  test('libraryClampPage：pageCount <= 0（異常輸入）時安全回傳 0，不拋例外（review-plan-issue-3.md M-1）', () {
    expect(libraryClampPage(5, 0), 0);
    expect(libraryClampPage(5, -1), 0);
  });

  test('libraryRecalculatePage：依全域 index 比例換算新頁碼（旋轉螢幕情境）', () {
    // 舊頁 2（0-based），舊每頁 3 項，第一項全域 index = 6；換算到新每頁 4 項
    // 應落在第 1 頁（0-based），6 ~/ 4 = 1。
    expect(
      libraryRecalculatePage(oldPage: 2, oldPageSize: 3, newPageSize: 4),
      1,
    );
    expect(
      libraryRecalculatePage(oldPage: 0, oldPageSize: 3, newPageSize: 4),
      0,
    );
    // 舊頁 1，舊每頁 4 項，第一項全域 index = 4；換算到新每頁 3 項，
    // 4 ~/ 3 = 1。
    expect(
      libraryRecalculatePage(oldPage: 1, oldPageSize: 4, newPageSize: 3),
      1,
    );
  });

  group('libraryRowsForHeight', () {
    test('一般情況：無條件捨去到能完整放下的列數', () {
      // 3 列總高度 = 3*100 + 2*10 = 320；4 列總高度 = 4*100 + 3*10 = 430；
      // availableHeight=350 能放下 3 列但放不下 4 列。
      expect(
        libraryRowsForHeight(
          availableHeight: 350,
          rowContentHeight: 100,
          rowSpacing: 10,
        ),
        3,
      );
    });

    test('邊界值：availableHeight 恰好等於 n 列總高度時回傳 n（不多算不少算）', () {
      // 2 列總高度 = 2*100 + 1*10 = 210，恰好等於 availableHeight。
      expect(
        libraryRowsForHeight(
          availableHeight: 210,
          rowContentHeight: 100,
          rowSpacing: 10,
        ),
        2,
      );
    });

    test('availableHeight 小於一列高度時保底回傳 1（不回傳 0，避免空白頁）', () {
      expect(
        libraryRowsForHeight(
          availableHeight: 50,
          rowContentHeight: 100,
          rowSpacing: 10,
        ),
        1,
      );
      expect(
        libraryRowsForHeight(
          availableHeight: 0,
          rowContentHeight: 100,
          rowSpacing: 10,
        ),
        1,
      );
      expect(
        libraryRowsForHeight(
          availableHeight: -20,
          rowContentHeight: 100,
          rowSpacing: 10,
        ),
        1,
      );
    });

    test('rowContentHeight <= 0（異常輸入防禦）安全回傳 1，不除以零', () {
      expect(
        libraryRowsForHeight(
          availableHeight: 500,
          rowContentHeight: 0,
          rowSpacing: 10,
        ),
        1,
      );
      expect(
        libraryRowsForHeight(
          availableHeight: 500,
          rowContentHeight: -5,
          rowSpacing: 10,
        ),
        1,
      );
    });
  });

  group('LibraryPagingCursor', () {
    test('初始 currentPage 為 0', () {
      final cursor = LibraryPagingCursor();
      expect(cursor.currentPage, 0);
    });

    test('clamp()：itemCount 在範圍內時回傳正確 pageCount／pageSize，頁碼維持不變', () {
      final cursor = LibraryPagingCursor();
      final result = cursor.clamp(itemCount: 10, orientation: Orientation.portrait);
      expect(result.pageCount, 4); // libraryPageCount(10, 3) = 4
      expect(result.pageSize, 3);
      expect(cursor.currentPage, 0);
    });

    test('clamp()：itemCount 縮小時箝制頁碼並回傳新 pageCount（越界情境）', () {
      final cursor = LibraryPagingCursor();
      cursor.clamp(itemCount: 10, orientation: Orientation.portrait); // pageSize=3, pageCount=4
      cursor.goToNextPage();
      cursor.goToNextPage();
      cursor.goToNextPage();
      expect(cursor.currentPage, 3); // 走到最後一頁（0-based）

      // 模擬刪書：itemCount 驟降為 2，合法頁碼只剩 0（pageCount=1）。
      final result = cursor.clamp(itemCount: 2, orientation: Orientation.portrait);
      expect(result.pageCount, 1);
      expect(cursor.currentPage, 0);
    });

    test(
      'clamp()：itemCount 為 0（空書庫）時回傳 pageCount 1，頁碼維持 0'
      '（review-plan-issue-6.md M-1）',
      () {
        final cursor = LibraryPagingCursor();
        final result = cursor.clamp(itemCount: 0, orientation: Orientation.portrait);
        expect(result.pageCount, 1); // libraryPageCount(0, 3) = 1
        expect(result.pageSize, 3);
        expect(cursor.currentPage, 0);
      },
    );

    test('applyOrientationChange()：方向未變時不觸發比例換算，回傳 false', () {
      final cursor = LibraryPagingCursor();
      cursor.clamp(itemCount: 10, orientation: Orientation.portrait);
      cursor.goToNextPage();
      expect(cursor.currentPage, 1);

      final changed = cursor.applyOrientationChange(Orientation.portrait);
      expect(changed, isFalse, reason: '方向沒變，不應該觸發比例換算');
      expect(cursor.currentPage, 1);
    });

    test('applyOrientationChange()：方向改變時依比例換算頁碼，回傳 true', () {
      final cursor = LibraryPagingCursor();
      cursor.clamp(itemCount: 10, orientation: Orientation.portrait); // pageSize=3
      cursor.goToNextPage();
      cursor.goToNextPage();
      expect(cursor.currentPage, 2); // 第一項全域 index = 6

      final changed = cursor.applyOrientationChange(Orientation.landscape); // newPageSize=4
      expect(changed, isTrue);
      expect(
        cursor.currentPage,
        1,
        reason:
            'libraryRecalculatePage(oldPage: 2, oldPageSize: 3, newPageSize: 4) = 6 ~/ 4 = 1',
      );
    });

    test(
      'applyOrientationChange()：冷啟動（尚未呼叫過 clamp()）時直接旋轉，'
      '不拋例外、頁碼維持 0、回傳 false（review-plan-issue-6.md M-1）',
      () {
        final cursor = LibraryPagingCursor();
        final changed = cursor.applyOrientationChange(Orientation.landscape);
        expect(changed, isFalse, reason: '_lastPageSize 尚未有值，沒有換算基準，不應該換算');
        expect(cursor.currentPage, 0);
      },
    );

    test('goToNextPage()／goToPreviousPage()：頁碼各自 +1／-1', () {
      final cursor = LibraryPagingCursor();
      cursor.goToNextPage();
      cursor.goToNextPage();
      expect(cursor.currentPage, 2);
      cursor.goToPreviousPage();
      expect(cursor.currentPage, 1);
    });

    test('resetToFirstPage()：頁碼歸零', () {
      final cursor = LibraryPagingCursor();
      cursor.clamp(itemCount: 10, orientation: Orientation.landscape);
      cursor.goToNextPage();
      cursor.resetToFirstPage();
      expect(cursor.currentPage, 0);
    });

    test(
      'review-plan-issue-3.md M-2 情境迴歸測試：clamp() 箝制後的頁碼才是 '
      'applyOrientationChange() 的換算基準，不會用到過期的越界頁碼',
      () {
        final cursor = LibraryPagingCursor();
        // 10 本書，portrait（pageSize=3，pageCount=4），走到最後一頁 page=3
        // （第一項全域 index = 9）。
        cursor.clamp(itemCount: 10, orientation: Orientation.portrait);
        cursor.goToNextPage();
        cursor.goToNextPage();
        cursor.goToNextPage();
        expect(cursor.currentPage, 3);

        // 模擬刪書：itemCount 驟降為 2（pageCount=1），build() 呼叫
        // clamp() 應把 currentPage 箝制回 0，而不是留著越界的 3。
        cursor.clamp(itemCount: 2, orientation: Orientation.portrait);
        expect(
          cursor.currentPage,
          0,
          reason: 'itemCount 縮小後應立即箝制，不殘留越界頁碼',
        );

        // 緊接著旋轉螢幕（portrait→landscape，pageSize 3→4）。若換算基準
        // 用的是箝制前的過期頁碼 3，libraryRecalculatePage(oldPage: 3,
        // oldPageSize: 3, newPageSize: 4) = 9 ~/ 4 = 2，會對這 2 本書
        // 而言算出一個同樣越界的頁碼；用箝制後的頁碼 0，結果應為 0。
        cursor.applyOrientationChange(Orientation.landscape);
        expect(
          cursor.currentPage,
          0,
          reason: '換算基準必須是 clamp() 箝制後的頁碼，不是過期的越界值',
        );
      },
    );
  });
}
