import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:elinkbook/reader/pdf_crop_mapping.dart';
import 'package:elinkbook/reader/pdf_crop_rect.dart';

// Issue 44：裁切框的比例是相對「整個畫面」，PdfCropRect 要的是相對「頁面」，
// 需要換算。測試座標單位一律是像素。
void main() {
  PdfCropRect ratio(double l, double t, double r, double b) =>
      PdfCropRect(left: l, top: t, right: r, bottom: b);

  void expectRect(PdfCropRect? actual, PdfCropRect expected,
      {double tol = 1e-3}) {
    expect(actual, isNotNull);
    expect(actual!.left, closeTo(expected.left, tol));
    expect(actual.top, closeTo(expected.top, tol));
    expect(actual.right, closeTo(expected.right, tol));
    expect(actual.bottom, closeTo(expected.bottom, tol));
  }

  test('頁面填滿畫面：輸入等於輸出', () {
    const viewport = Size(800, 1600);
    final result = viewportRectToPageCropRect(
      viewportRect: ratio(0.1, 0.2, 0.9, 0.8),
      viewportSize: viewport,
      pageRectInViewport: Offset.zero & viewport,
    );
    expectRect(result, ratio(0.1, 0.2, 0.9, 0.8));
  });

  test('WAVE 真機實驗：拖滿整頁白紙，換算後應是整頁（0,0,1,1）', () {
    // 真機記錄：畫面 1404x1777，頁面左 137、右 1267、上 30、下 1745；
    // 使用者從頁面左上角拖到右下角，裁切層回報 (0.098, 0.031, 0.901, 0.980)
    const viewport = Size(1404, 1777);
    final result = viewportRectToPageCropRect(
      viewportRect: ratio(137 / 1404, 30 / 1777, 1267 / 1404, 1745 / 1777),
      viewportSize: viewport,
      pageRectInViewport: const Rect.fromLTRB(137, 30, 1267, 1745),
    );
    expectRect(result, ratio(0, 0, 1, 1));
  });

  test('框的一部分拖進灰邊：夾到頁面邊界', () {
    const viewport = Size(1000, 1000);
    final result = viewportRectToPageCropRect(
      viewportRect: ratio(0.0, 0.0, 0.5, 1.0), // 左側 100px 是灰邊
      viewportSize: viewport,
      pageRectInViewport: const Rect.fromLTRB(100, 0, 900, 1000),
    );
    expectRect(result, ratio(0, 0, 400 / 800, 1));
  });

  test('頁面被放大、只露出一部分：以未夾制的頁面矩形換算', () {
    const viewport = Size(1000, 1000);
    // 頁面寬 2000，左緣在畫面外 -500；畫面中 0～1000 對應頁面 0.25～0.75
    final result = viewportRectToPageCropRect(
      viewportRect: ratio(0, 0, 1, 1),
      viewportSize: viewport,
      pageRectInViewport: const Rect.fromLTRB(-500, 0, 1500, 1000),
    );
    expectRect(result, ratio(0.25, 0, 0.75, 1));
  });

  test('框完全在頁面外：回傳 null', () {
    const viewport = Size(1000, 1000);
    final result = viewportRectToPageCropRect(
      viewportRect: ratio(0.0, 0.2, 0.08, 0.8),
      viewportSize: viewport,
      pageRectInViewport: const Rect.fromLTRB(100, 0, 900, 1000),
    );
    expect(result, isNull);
  });

  test('與頁面的交集任一邊小於 0.05：回傳 null', () {
    const viewport = Size(1000, 1000);
    // 交集寬 20px，換成頁面比例 20/800 = 0.025
    final result = viewportRectToPageCropRect(
      viewportRect: ratio(0.08, 0.2, 0.12, 0.8),
      viewportSize: viewport,
      pageRectInViewport: const Rect.fromLTRB(100, 0, 900, 1000),
    );
    expect(result, isNull);
  });

  // 審查 I-1：已有生效中的裁切時，畫面顯示的是裁切後的頁面，換算結果是
  // 「相對已裁切頁面」，要合成回原始整頁座標。
  test('已有生效中裁切：框滿目前顯示的頁面，輸出等於原裁切', () {
    const viewport = Size(1000, 1000);
    final result = viewportRectToPageCropRect(
      viewportRect: ratio(0, 0, 1, 1),
      viewportSize: viewport,
      pageRectInViewport: Offset.zero & viewport,
      activeCrop: ratio(0.1, 0.1, 0.9, 0.9),
    );
    expectRect(result, ratio(0.1, 0.1, 0.9, 0.9));
  });

  test('已有生效中裁切：框左半，右邊界落在 0.1 + 0.5 × 0.8 = 0.5', () {
    const viewport = Size(1000, 1000);
    final result = viewportRectToPageCropRect(
      viewportRect: ratio(0, 0, 0.5, 1),
      viewportSize: viewport,
      pageRectInViewport: Offset.zero & viewport,
      activeCrop: ratio(0.1, 0.1, 0.9, 0.9),
    );
    expectRect(result, ratio(0.1, 0.1, 0.5, 0.9));
  });

  test('activeCrop 為 null（模式 none 但外部殘留舊矩形）：不合成，與無裁切相同', () {
    const viewport = Size(1000, 1000);
    final result = viewportRectToPageCropRect(
      viewportRect: ratio(0, 0, 0.5, 1),
      viewportSize: viewport,
      pageRectInViewport: Offset.zero & viewport,
      activeCrop: null,
    );
    expectRect(result, ratio(0, 0, 0.5, 1));
  });
}
