import 'package:flutter_test/flutter_test.dart';
import 'package:pdfrx/pdfrx.dart';
import 'package:elinkbook/reader/pdf_search_geometry.dart';
import 'package:elinkbook/reader/pdf_search_match.dart';
import 'package:elinkbook/reader/percent_rect.dart';

void main() {
  group('pdfRectToPercentRect', () {
    test('頁面正中央的矩形換算為 0.25-0.75 範圍（US Letter 612x792）', () {
      // PDF points：頁面 612x792，矩形涵蓋 [153,594]x[153,198]（水平置中
      // 1/4~3/4，垂直置中一小段）。
      const rect = PdfRect(153, 594, 459, 198);
      final result = pdfRectToPercentRect(rect: rect, pageWidth: 612, pageHeight: 792);
      expect(result.left, closeTo(0.25, 0.001));
      expect(result.right, closeTo(0.75, 0.001));
      // PDF top=594（距離底部較遠，即視覺上較高）換算後 percent top 應較小。
      expect(result.top, closeTo(1 - 594 / 792, 0.001));
      expect(result.bottom, closeTo(1 - 198 / 792, 0.001));
      expect(result.top, lessThan(result.bottom));
    });

    test('頁面最頂端的矩形換算後 top 趨近 0', () {
      const rect = PdfRect(0, 792, 100, 770);
      final result = pdfRectToPercentRect(rect: rect, pageWidth: 612, pageHeight: 792);
      expect(result.top, closeTo(0.0, 0.001));
    });

    test('頁面最底端的矩形換算後 bottom 趨近 1', () {
      const rect = PdfRect(0, 22, 100, 0);
      final result = pdfRectToPercentRect(rect: rect, pageWidth: 612, pageHeight: 792);
      expect(result.bottom, closeTo(1.0, 0.001));
    });

    test('左邊界矩形換算後 left 為 0', () {
      const rect = PdfRect(0, 700, 50, 680);
      final result = pdfRectToPercentRect(rect: rect, pageWidth: 612, pageHeight: 792);
      expect(result.left, 0.0);
    });

    // 審查修正（review-plan-issue-6.md Minor #2）：少數 PDF 字型的字元
    // bounding box 可能微幅超出頁面邊界（例如 top 略大於 pageHeight），
    // 換算結果須夾在 [0, 1] 範圍內，避免下游疊加渲染產生輕微溢出。
    test('PDF 矩形頂端座標超出頁面邊界時，換算結果夾在 0-1 範圍內', () {
      const rect = PdfRect(0, 800, 100, 770); // top=800 > pageHeight=792。
      final result = pdfRectToPercentRect(rect: rect, pageWidth: 612, pageHeight: 792);
      expect(result.top, 0.0);
    });

    test('PDF 矩形左側座標為負值時，換算結果夾在 0-1 範圍內', () {
      const rect = PdfRect(-1.5, 700, 50, 680); // left=-1.5 略小於 0。
      final result = pdfRectToPercentRect(rect: rect, pageWidth: 612, pageHeight: 792);
      expect(result.left, 0.0);
    });
  });

  group('percentRectToPdfRect', () {
    test('與 pdfRectToPercentRect 互為反函式（US Letter 612x792）', () {
      const original = PdfRect(153, 594, 459, 198);
      final percent = pdfRectToPercentRect(rect: original, pageWidth: 612, pageHeight: 792);
      final restored = percentRectToPdfRect(rect: percent, pageWidth: 612, pageHeight: 792);
      expect(restored.left, closeTo(original.left, 0.001));
      expect(restored.right, closeTo(original.right, 0.001));
      expect(restored.top, closeTo(original.top, 0.001));
      expect(restored.bottom, closeTo(original.bottom, 0.001));
    });

    test('換算結果一律滿足 PdfRect 的 top >= bottom（不觸發 assert）', () {
      const rect = PercentRect(left: 0.1, top: 0.2, right: 0.5, bottom: 0.4);
      final result = percentRectToPdfRect(rect: rect, pageWidth: 612, pageHeight: 792);
      expect(result.top, greaterThanOrEqualTo(result.bottom),
          reason: 'PercentRect.top（螢幕座標，數值較小）換算回 PdfRect 後，'
              '必須對應到較大的 top 值（PDF 座標左下角原點、Y 軸向上），'
              '否則 PdfRect 建構子的 assert(top >= bottom) 會直接拋出例外。');
    });

    test('頁面正中央的百分比矩形換算回 PDF points 座標正確', () {
      const rect = PercentRect(left: 0.25, top: 0.25, right: 0.75, bottom: 0.75);
      final result = percentRectToPdfRect(rect: rect, pageWidth: 612, pageHeight: 792);
      expect(result.left, closeTo(153, 0.001));
      expect(result.right, closeTo(459, 0.001));
      expect(result.top, closeTo(594, 0.001));
      expect(result.bottom, closeTo(198, 0.001));
    });
  });

  // 審查修正（review-plan-issue-6.md Minor #1）：驗證 PdfSearchMatch 的值
  // 相等性，與同為值物件的既有 PercentRect／PdfPageInfo 慣例一致。
  group('PdfSearchMatch 值相等性', () {
    test('欄位皆相同的兩個實例視為相等', () {
      const rectA = PercentRect(left: 0.1, top: 0.2, right: 0.3, bottom: 0.4);
      const rectB = PercentRect(left: 0.1, top: 0.2, right: 0.3, bottom: 0.4);
      const a = PdfSearchMatch(pageIndex: 0, text: 'foo', rect: rectA);
      const b = PdfSearchMatch(pageIndex: 0, text: 'foo', rect: rectB);
      expect(a, b);
      expect(a.hashCode, b.hashCode);
    });

    test('任一欄位不同則視為不相等', () {
      const rect = PercentRect(left: 0.1, top: 0.2, right: 0.3, bottom: 0.4);
      const a = PdfSearchMatch(pageIndex: 0, text: 'foo', rect: rect);
      const b = PdfSearchMatch(pageIndex: 1, text: 'foo', rect: rect);
      expect(a == b, isFalse);
    });
  });
}
