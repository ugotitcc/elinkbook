import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:elinkbook/reader/pdf_crop_frame_overlay.dart';
import 'package:elinkbook/reader/pdf_crop_rect.dart';

void main() {
  // 注意：測試中不使用 initialRect 為精確 (0,0,1,1) 的全頁矩形——
  // 四角控制點會落在 SizedBox 精確邊界上，Flutter 的
  // Size.contains() 使用嚴格小於（<），邊界上的點會被視為
  // 「不在盒子內」，導致 hit test 失敗、drag 手勢無法觸發。
  // 若需測試全頁裁切場景，請使用接近邊界但不精確落上的值
  // （例如 0.01 / 0.99）。
  Widget wrap(Widget child) => MaterialApp(
        home: Scaffold(body: SizedBox(width: 800, height: 1600, child: child)),
      );

  testWidgets('顯示確認/取消按鈕，點擊確認時回傳目前框選矩形', (tester) async {
    PdfCropRect? confirmed;
    await tester.pumpWidget(
      wrap(PdfCropFrameOverlay(
        initialRect: const PdfCropRect(left: 0.1, top: 0.1, right: 0.9, bottom: 0.9),
        onConfirm: (rect) => confirmed = rect,
        onCancel: () {},
      )),
    );

    expect(find.byKey(const Key('pdf_crop_frame_confirm')), findsOneWidget);
    expect(find.byKey(const Key('pdf_crop_frame_cancel')), findsOneWidget);

    await tester.tap(find.byKey(const Key('pdf_crop_frame_confirm')));
    await tester.pump();

    expect(confirmed, const PdfCropRect(left: 0.1, top: 0.1, right: 0.9, bottom: 0.9));
  });

  testWidgets('點擊取消時觸發 onCancel、不觸發 onConfirm', (tester) async {
    var cancelled = false;
    PdfCropRect? confirmed;
    await tester.pumpWidget(
      wrap(PdfCropFrameOverlay(
        initialRect: const PdfCropRect(left: 0, top: 0, right: 1, bottom: 1),
        onConfirm: (rect) => confirmed = rect,
        onCancel: () => cancelled = true,
      )),
    );

    await tester.tap(find.byKey(const Key('pdf_crop_frame_cancel')));
    await tester.pump();

    expect(cancelled, isTrue);
    expect(confirmed, isNull);
  });

  testWidgets('拖曳右下角控制點縮小裁切框後確認，回傳的矩形右/下邊界變小',
      (tester) async {
    PdfCropRect? confirmed;
    await tester.pumpWidget(
      wrap(PdfCropFrameOverlay(
        // 使用 0.01/0.99 而非精確 0/1，避免控制點落在容器邊界上
        // 導致 hit test 失敗（見 main() 頂部說明）
        initialRect: const PdfCropRect(left: 0.01, top: 0.01, right: 0.99, bottom: 0.99),
        onConfirm: (rect) => confirmed = rect,
        onCancel: () {},
      )),
    );

    final handle = find.byKey(const Key('pdf_crop_frame_handle_bottom_right'));
    expect(handle, findsOneWidget);
    await tester.drag(handle, const Offset(-100, -200));
    await tester.pump();

    await tester.tap(find.byKey(const Key('pdf_crop_frame_confirm')));
    await tester.pump();

    expect(confirmed, isNotNull);
    expect(confirmed!.right, lessThan(0.99));
    expect(confirmed!.bottom, lessThan(0.99));
  });

  testWidgets('裁切框不可拖曳縮小到零面積以下（最小尺寸防呆）', (tester) async {
    PdfCropRect? confirmed;
    await tester.pumpWidget(
      wrap(PdfCropFrameOverlay(
        initialRect: const PdfCropRect(left: 0.4, top: 0.4, right: 0.6, bottom: 0.6),
        onConfirm: (rect) => confirmed = rect,
        onCancel: () {},
      )),
    );

    final handle = find.byKey(const Key('pdf_crop_frame_handle_bottom_right'));
    await tester.drag(handle, const Offset(-1000, -1000));
    await tester.pump();

    await tester.tap(find.byKey(const Key('pdf_crop_frame_confirm')));
    await tester.pump();

    expect(confirmed!.right, greaterThan(confirmed!.left));
    expect(confirmed!.bottom, greaterThan(confirmed!.top));
  });

  testWidgets(
      '拖曳左上角控制點可獨立調整 top 與 left（Important 1 回歸測試：'
      '不得只有右下角一個控制點）', (tester) async {
    PdfCropRect? confirmed;
    await tester.pumpWidget(
      wrap(PdfCropFrameOverlay(
        initialRect: const PdfCropRect(left: 0.01, top: 0.01, right: 0.99, bottom: 0.99),
        onConfirm: (rect) => confirmed = rect,
        onCancel: () {},
      )),
    );

    final handle = find.byKey(const Key('pdf_crop_frame_handle_top_left'));
    expect(handle, findsOneWidget);
    await tester.drag(handle, const Offset(80, 120));
    await tester.pump();

    await tester.tap(find.byKey(const Key('pdf_crop_frame_confirm')));
    await tester.pump();

    expect(confirmed, isNotNull);
    expect(confirmed!.left, greaterThan(0.01),
        reason: '拖曳左上角控制點應能收窄 left 邊界');
    expect(confirmed!.top, greaterThan(0.01),
        reason: '拖曳左上角控制點應能收窄 top 邊界');
    expect(confirmed!.right, 0.99);
    expect(confirmed!.bottom, 0.99);
  });

  testWidgets('右上角／左下角控制點皆存在，且只調整各自對應的兩個邊界',
      (tester) async {
    PdfCropRect? confirmed;
    await tester.pumpWidget(
      wrap(PdfCropFrameOverlay(
        initialRect: const PdfCropRect(left: 0.01, top: 0.01, right: 0.99, bottom: 0.99),
        onConfirm: (rect) => confirmed = rect,
        onCancel: () {},
      )),
    );

    expect(find.byKey(const Key('pdf_crop_frame_handle_top_right')), findsOneWidget);
    expect(find.byKey(const Key('pdf_crop_frame_handle_bottom_left')), findsOneWidget);

    await tester.drag(
      find.byKey(const Key('pdf_crop_frame_handle_top_right')),
      const Offset(-80, 120),
    );
    await tester.pump();
    await tester.tap(find.byKey(const Key('pdf_crop_frame_confirm')));
    await tester.pump();

    expect(confirmed!.right, lessThan(0.99));
    expect(confirmed!.top, greaterThan(0.01));
    expect(confirmed!.left, 0.01);
    expect(confirmed!.bottom, 0.99);
  });

  testWidgets(
      'PdfCropFrameOverlay 包含 CustomPaint 遮罩層與帶背景之 Material 按鈕',
      (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 800,
            height: 1600,
            child: PdfCropFrameOverlay(
              initialRect: const PdfCropRect(
                  left: 0.2, top: 0.2, right: 0.8, bottom: 0.8),
              onConfirm: (_) {},
              onCancel: () {},
            ),
          ),
        ),
      ),
    );

    // 驗證存在 CustomPaint 遮罩層（取代舊版 Positioned.fromRect + Container）
    expect(find.byType(CustomPaint), findsWidgets);
    expect(find.byKey(const Key('pdf_crop_frame_confirm')), findsOneWidget);
    expect(find.byKey(const Key('pdf_crop_frame_cancel')), findsOneWidget);

    // 【重要】驗證確認按鈕被高對比 FAB 樣式 Material 包裹
    // IconButton 內部雖有 Material 祖先，但 elevation 為 0——
    // FAB 樣式的 Material elevation=6，以此區分兩者
    final confirmMaterialFinder = find.ancestor(
      of: find.byKey(const Key('pdf_crop_frame_confirm')),
      matching: find.byType(Material),
    );
    final confirmMaterials = confirmMaterialFinder
        .evaluate()
        .map((e) => e.widget as Material)
        .toList();
    expect(
      confirmMaterials.any((m) => m.elevation == 6),
      isTrue,
      reason: '確認按鈕的 Material 祖先中應有 elevation=6 的 FAB 樣式容器',
    );
  });
}
