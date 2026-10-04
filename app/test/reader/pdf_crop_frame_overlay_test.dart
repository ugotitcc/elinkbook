import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:elinkbook/l10n/app_localizations.dart';
import 'package:elinkbook/reader/pdf_crop_frame_overlay.dart';
import 'package:elinkbook/reader/pdf_crop_rect.dart';

void main() {
  // 測試畫布固定為 800x1600、位於左上角，方便把像素座標換算成 0~1 比例
  Widget wrap(Widget child) => MaterialApp(
        locale: const Locale('zh', 'TW'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: Align(
            alignment: Alignment.topLeft,
            child: SizedBox(width: 800, height: 1600, child: child),
          ),
        ),
      );

  Future<void> pumpOverlay(
    WidgetTester tester, {
    ValueChanged<PdfCropRect>? onConfirm,
    VoidCallback? onCancel,
  }) async {
    await tester.pumpWidget(wrap(PdfCropFrameOverlay(
      onConfirm: onConfirm ?? (_) {},
      onCancel: onCancel ?? () {},
    )));
  }

  // 以手指從 [from] 拖到 [to]，模擬使用者直接拖拉框選
  Future<void> dragSelect(WidgetTester tester, Offset from, Offset to) async {
    await tester.dragFrom(from, to - from);
    await tester.pump();
  }

  final confirmFinder = find.byKey(const Key('pdf_crop_frame_confirm'));

  Future<PdfCropRect?> confirmAndGet(WidgetTester tester, List<PdfCropRect> out) async {
    await tester.tap(confirmFinder);
    await tester.pump();
    return out.isEmpty ? null : out.last;
  }

  testWidgets('進入時不顯示框，只顯示提示文字；確認鈕停用', (tester) async {
    final confirmed = <PdfCropRect>[];
    await pumpOverlay(tester, onConfirm: confirmed.add);

    expect(find.byKey(const Key('pdf_crop_frame_hint')), findsOneWidget);
    // 沒有任何四角控制點
    expect(find.byKey(const Key('pdf_crop_frame_handle_top_left')), findsNothing);
    expect(find.byKey(const Key('pdf_crop_frame_handle_bottom_right')), findsNothing);

    await tester.tap(confirmFinder);
    await tester.pump();
    expect(confirmed, isEmpty, reason: '尚未畫框時確認鈕應停用');
  });

  testWidgets('手指拖拉後確認，回傳對應比例的矩形；提示文字消失', (tester) async {
    final confirmed = <PdfCropRect>[];
    await pumpOverlay(tester, onConfirm: confirmed.add);

    await dragSelect(tester, const Offset(80, 160), const Offset(720, 1440));

    expect(find.byKey(const Key('pdf_crop_frame_hint')), findsNothing);
    final rect = await confirmAndGet(tester, confirmed);
    expect(rect, isNotNull);
    expect(rect!.left, closeTo(0.1, 1e-6));
    expect(rect.top, closeTo(0.1, 1e-6));
    expect(rect.right, closeTo(0.9, 1e-6));
    expect(rect.bottom, closeTo(0.9, 1e-6));
  });

  testWidgets('由右下往左上反向拖拉，矩形仍正規化為 left<right、top<bottom',
      (tester) async {
    final confirmed = <PdfCropRect>[];
    await pumpOverlay(tester, onConfirm: confirmed.add);

    await dragSelect(tester, const Offset(720, 1440), const Offset(80, 160));

    final rect = await confirmAndGet(tester, confirmed);
    expect(rect!.left, closeTo(0.1, 1e-6));
    expect(rect.top, closeTo(0.1, 1e-6));
    expect(rect.right, closeTo(0.9, 1e-6));
    expect(rect.bottom, closeTo(0.9, 1e-6));
  });

  testWidgets('再拖拉一次會取代舊框（只能重畫）', (tester) async {
    final confirmed = <PdfCropRect>[];
    await pumpOverlay(tester, onConfirm: confirmed.add);

    await dragSelect(tester, const Offset(80, 160), const Offset(720, 1440));
    await dragSelect(tester, const Offset(200, 400), const Offset(600, 1200));

    final rect = await confirmAndGet(tester, confirmed);
    expect(rect!.left, closeTo(0.25, 1e-6));
    expect(rect.top, closeTo(0.25, 1e-6));
    expect(rect.right, closeTo(0.75, 1e-6));
    expect(rect.bottom, closeTo(0.75, 1e-6));
  });

  testWidgets('拖出畫布邊界時座標被限制在 0～1', (tester) async {
    final confirmed = <PdfCropRect>[];
    await pumpOverlay(tester, onConfirm: confirmed.add);

    await tester.dragFrom(const Offset(400, 800), const Offset(1000, 2000));
    await tester.pump();

    final rect = await confirmAndGet(tester, confirmed);
    expect(rect!.left, closeTo(0.5, 1e-6));
    expect(rect.top, closeTo(0.5, 1e-6));
    expect(rect.right, 1.0);
    expect(rect.bottom, 1.0);
  });

  testWidgets('範圍太小（任一邊 < 0.05）視為無效：首次畫不出框、確認仍停用',
      (tester) async {
    final confirmed = <PdfCropRect>[];
    await pumpOverlay(tester, onConfirm: confirmed.add);

    // 寬 24px = 0.03 < 0.05
    await dragSelect(tester, const Offset(100, 100), const Offset(124, 900));

    expect(find.byKey(const Key('pdf_crop_frame_hint')), findsOneWidget);
    await tester.tap(confirmFinder);
    await tester.pump();
    expect(confirmed, isEmpty);
  });

  testWidgets('已有框時再拖出太小的範圍，保留上一個框', (tester) async {
    final confirmed = <PdfCropRect>[];
    await pumpOverlay(tester, onConfirm: confirmed.add);

    await dragSelect(tester, const Offset(80, 160), const Offset(720, 1440));
    await dragSelect(tester, const Offset(300, 300), const Offset(310, 900));

    final rect = await confirmAndGet(tester, confirmed);
    expect(rect!.left, closeTo(0.1, 1e-6));
    expect(rect.right, closeTo(0.9, 1e-6));
  });

  testWidgets('輕點（沒有拖拉）不產生框', (tester) async {
    final confirmed = <PdfCropRect>[];
    await pumpOverlay(tester, onConfirm: confirmed.add);

    await tester.tapAt(const Offset(400, 800));
    await tester.pump();

    expect(find.byKey(const Key('pdf_crop_frame_hint')), findsOneWidget);
    await tester.tap(confirmFinder);
    await tester.pump();
    expect(confirmed, isEmpty);
  });

  // 找出遮罩繪製層（CropOverlayPainter）；沒有框時不應存在
  final maskFinder = find.byWidgetPredicate(
      (w) => w is CustomPaint && w.painter is CropOverlayPainter);

  testWidgets('手指按下但尚未拖動時不繪製遮罩（輕點不得讓全螢幕變暗，審查 I-1）',
      (tester) async {
    await pumpOverlay(tester);

    final g = await tester.startGesture(const Offset(400, 800));
    await tester.pump();
    expect(maskFinder, findsNothing);
    await g.up();
    await tester.pump();
    expect(maskFinder, findsNothing);
  });

  testWidgets('已有框時手指按下不會讓既有框消失（審查 I-1）', (tester) async {
    await pumpOverlay(tester);
    await dragSelect(tester, const Offset(80, 160), const Offset(720, 1440));
    expect(maskFinder, findsOneWidget);

    final g = await tester.startGesture(const Offset(400, 800));
    await tester.pump();
    final painter =
        tester.widget<CustomPaint>(maskFinder).painter as CropOverlayPainter;
    expect(painter.cropRect, const Rect.fromLTRB(80, 160, 720, 1440));
    await g.up();
  });

  testWidgets('拖拉被系統中斷（cancel）時放棄這次選取，保留上一個框（審查 I-3）',
      (tester) async {
    final confirmed = <PdfCropRect>[];
    await pumpOverlay(tester, onConfirm: confirmed.add);
    await dragSelect(tester, const Offset(80, 160), const Offset(720, 1440));

    final g = await tester.startGesture(const Offset(200, 400));
    await g.moveTo(const Offset(600, 1200));
    await tester.pump();
    await g.cancel();
    await tester.pump();

    final rect = await confirmAndGet(tester, confirmed);
    expect(rect!.left, closeTo(0.1, 1e-6));
    expect(rect.right, closeTo(0.9, 1e-6));
  });

  testWidgets('尚未畫框時從停用的確認鈕上拖拉，不會穿透畫出框（審查 I-2）',
      (tester) async {
    await pumpOverlay(tester);

    final center = tester.getCenter(confirmFinder) + const Offset(-18, -18);
    final g = await tester.startGesture(center);
    await g.moveBy(const Offset(-200, -400));
    await tester.pump();
    await g.up();
    await tester.pump();

    expect(maskFinder, findsNothing);
    expect(find.byKey(const Key('pdf_crop_frame_hint')), findsOneWidget);
  });

  testWidgets('右上→左下、左下→右上拖拉皆正規化（審查 M-2）', (tester) async {
    final confirmed = <PdfCropRect>[];
    await pumpOverlay(tester, onConfirm: confirmed.add);

    await dragSelect(tester, const Offset(720, 160), const Offset(80, 1440));
    var rect = await confirmAndGet(tester, confirmed);
    expect(rect!.left, closeTo(0.1, 1e-6));
    expect(rect.top, closeTo(0.1, 1e-6));
    expect(rect.right, closeTo(0.9, 1e-6));
    expect(rect.bottom, closeTo(0.9, 1e-6));

    await dragSelect(tester, const Offset(160, 1280), const Offset(640, 320));
    rect = await confirmAndGet(tester, confirmed);
    expect(rect!.left, closeTo(0.2, 1e-6));
    expect(rect.top, closeTo(0.2, 1e-6));
    expect(rect.right, closeTo(0.8, 1e-6));
    expect(rect.bottom, closeTo(0.8, 1e-6));
  });

  testWidgets('點擊取消時觸發 onCancel、不觸發 onConfirm', (tester) async {
    var cancelled = false;
    final confirmed = <PdfCropRect>[];
    await pumpOverlay(
      tester,
      onConfirm: confirmed.add,
      onCancel: () => cancelled = true,
    );
    await dragSelect(tester, const Offset(80, 160), const Offset(720, 1440));

    await tester.tap(find.byKey(const Key('pdf_crop_frame_cancel')));
    await tester.pump();

    expect(cancelled, isTrue);
    expect(confirmed, isEmpty);
  });

  testWidgets('包含 CustomPaint 遮罩層與帶背景之 FAB 樣式 Material 按鈕',
      (tester) async {
    await pumpOverlay(tester);
    await dragSelect(tester, const Offset(160, 320), const Offset(640, 1280));

    expect(find.byType(CustomPaint), findsWidgets);
    expect(confirmFinder, findsOneWidget);
    expect(find.byKey(const Key('pdf_crop_frame_cancel')), findsOneWidget);

    // 確認按鈕被 elevation=6 的 FAB 樣式 Material 包裹（與 IconButton 內部 elevation 0 區分）
    final materials = find
        .ancestor(of: confirmFinder, matching: find.byType(Material))
        .evaluate()
        .map((e) => e.widget as Material)
        .toList();
    expect(materials.any((m) => m.elevation == 6), isTrue);
  });
}
