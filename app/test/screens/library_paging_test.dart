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
}
