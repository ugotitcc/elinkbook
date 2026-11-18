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
    VoidCallback? onRestore,
  }) async {
    await tester.pumpWidget(wrap(PdfCropFrameOverlay(
      onConfirm: onConfirm ?? (_) {},
      onCancel: onCancel ?? () {},
      onRestore: onRestore,
    )));
  }

  // 以手指從 [from] 拖到 [to]，模擬使用者直接拖拉框選
  Future<void> dragSelect(WidgetTester tester, Offset from, Offset to) async {
    await tester.dragFrom(from, to - from);
    // 放開後要等接力寬限期（250ms）才定案
    await tester.pump(const Duration(milliseconds: 300));
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
    await tester.pump(const Duration(milliseconds: 300));

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

  // ── Issue 44：WAVE 觸控驅動把一次連續拖拉拆成「接力」的多個 pointer ──
  // 真機記錄見 docs/epics/epic-54-architecture-optimization/repro/
  // issue-44-wave-pointer-log.txt：新 pointer 的 down 落在手指當下位置，
  // 距離上一個 pointer 最後位置 72～123px，間隔 36～61ms，有時比舊 pointer
  // 的 up 更早抵達（重疊）；另有數百 px 外的幽靈第二指。
  Future<void> expectRect(
      WidgetTester tester, List<PdfCropRect> confirmed, Rect px) async {
    final rect = await confirmAndGet(tester, confirmed);
    expect(rect, isNotNull);
    expect(rect!.left, closeTo(px.left / 800, 1e-6));
    expect(rect.top, closeTo(px.top / 1600, 1e-6));
    expect(rect.right, closeTo(px.right / 800, 1e-6));
    expect(rect.bottom, closeTo(px.bottom / 1600, 1e-6));
  }

  testWidgets('接力（先放開、60ms 後在 100px 外接續）：起點不變', (tester) async {
    final confirmed = <PdfCropRect>[];
    await pumpOverlay(tester, onConfirm: confirmed.add);

    final g1 = await tester.startGesture(const Offset(80, 160));
    await g1.moveTo(const Offset(400, 800));
    await tester.pump(const Duration(milliseconds: 16));
    await g1.up();
    await tester.pump(const Duration(milliseconds: 60));
    final g2 = await tester.startGesture(const Offset(470, 870)); // 約 99px 外
    await g2.moveTo(const Offset(720, 1440));
    await tester.pump(const Duration(milliseconds: 16));
    await g2.up();
    await tester.pump(const Duration(milliseconds: 300));

    await expectRect(tester, confirmed, const Rect.fromLTRB(80, 160, 720, 1440));
  });

  testWidgets('重疊交接（新 pointer 在舊 pointer 放開前抵達）：起點不變、框不被覆蓋',
      (tester) async {
    final confirmed = <PdfCropRect>[];
    await pumpOverlay(tester, onConfirm: confirmed.add);

    final g1 = await tester.startGesture(const Offset(80, 160));
    await g1.moveTo(const Offset(400, 800));
    await tester.pump(const Duration(milliseconds: 16));
    // 新 pointer 在舊 pointer 放開「之前」抵達（真機 id=27 與 id=28）
    final g2 = await tester.startGesture(const Offset(430, 830));
    await tester.pump(const Duration(milliseconds: 16));
    await g1.up();
    await tester.pump(const Duration(milliseconds: 20));
    // 舊 pointer 放開後，第三個 pointer 在附近按下（真機 id=29）
    final g3 = await tester.startGesture(const Offset(440, 840));
    await g2.moveTo(const Offset(720, 1440));
    await g2.up();
    await g3.moveTo(const Offset(720, 1440));
    await tester.pump(const Duration(milliseconds: 16));
    await g3.up();
    await tester.pump(const Duration(milliseconds: 300));

    await expectRect(tester, confirmed, const Rect.fromLTRB(80, 160, 720, 1440));
  });

  testWidgets('幽靈第二指（追蹤中在 500px 外按下）：忽略，不影響框', (tester) async {
    final confirmed = <PdfCropRect>[];
    await pumpOverlay(tester, onConfirm: confirmed.add);

    final g1 = await tester.startGesture(const Offset(80, 160));
    await g1.moveTo(const Offset(400, 800));
    await tester.pump(const Duration(milliseconds: 16));
    final ghost = await tester.startGesture(const Offset(100, 1500));
    await tester.pump(const Duration(milliseconds: 16));
    await ghost.up();
    await g1.moveTo(const Offset(720, 1440));
    await tester.pump(const Duration(milliseconds: 16));
    await g1.up();
    await tester.pump(const Duration(milliseconds: 300));

    await expectRect(tester, confirmed, const Rect.fromLTRB(80, 160, 720, 1440));
  });

  testWidgets('雙流（落後者卡住、領先者是真手指，距離超過 150px）：以持續移動者為準',
      (tester) async {
    final confirmed = <PdfCropRect>[];
    await pumpOverlay(tester, onConfirm: confirmed.add);

    // 真機 id=281／id=282：追蹤者停在原地，真手指在 180px 外持續移動
    final g1 = await tester.startGesture(const Offset(80, 160));
    await g1.moveTo(const Offset(400, 800));
    await tester.pump(const Duration(milliseconds: 16));
    final g2 = await tester.startGesture(const Offset(580, 800));
    for (var i = 0; i < 4; i++) {
      await g2.moveBy(const Offset(4, 4)); // 前幾步位移小，尚未升格
      await tester.pump(const Duration(milliseconds: 16));
    }
    await g1.up();
    await tester.pump(const Duration(milliseconds: 16));
    await g2.moveTo(const Offset(720, 1440));
    await tester.pump(const Duration(milliseconds: 16));
    await g2.up();
    await tester.pump(const Duration(milliseconds: 300));

    await expectRect(tester, confirmed, const Rect.fromLTRB(80, 160, 720, 1440));
  });

  testWidgets('遠處幽靈只在原地抖動（位移不足 8px）：不升格、不影響框', (tester) async {
    final confirmed = <PdfCropRect>[];
    await pumpOverlay(tester, onConfirm: confirmed.add);

    final g1 = await tester.startGesture(const Offset(80, 160));
    await g1.moveTo(const Offset(400, 800));
    await tester.pump(const Duration(milliseconds: 16));
    final ghost = await tester.startGesture(const Offset(100, 1500));
    for (var i = 0; i < 4; i++) {
      await ghost.moveBy(const Offset(1, 0)); // 共 4px
      await tester.pump(const Duration(milliseconds: 16));
    }
    await ghost.up();
    await g1.moveTo(const Offset(720, 1440));
    await tester.pump(const Duration(milliseconds: 16));
    await g1.up();
    await tester.pump(const Duration(milliseconds: 300));

    await expectRect(tester, confirmed, const Rect.fromLTRB(80, 160, 720, 1440));
  });

  // ── 框拖拉時跳動：兩條座標流輪流更新（真機 id=49／id=50）──
  // 新的那根（領頭）才是真手指；舊的那根快放開，位置會倒退。若誰動誰更新，
  // 框的角落會在兩條流之間來回跳。
  testWidgets('雙流輪流更新：只跟最新接手的領頭，舊流的倒退位置不影響框', (tester) async {
    final confirmed = <PdfCropRect>[];
    await pumpOverlay(tester, onConfirm: confirmed.add);

    final old = await tester.startGesture(const Offset(80, 160));
    await old.moveTo(const Offset(400, 800));
    await tester.pump(const Duration(milliseconds: 16));
    final lead = await tester.startGesture(const Offset(430, 830)); // 最新接手
    await lead.moveTo(const Offset(620, 1000));
    await tester.pump(const Duration(milliseconds: 10));
    await old.moveTo(const Offset(480, 900)); // 舊流倒退，不得更新框
    await tester.pump(const Duration(milliseconds: 10));
    await lead.moveTo(const Offset(700, 1400));
    await tester.pump(const Duration(milliseconds: 10));
    await old.moveTo(const Offset(477, 905)); // 舊流最後一次更新
    await tester.pump(const Duration(milliseconds: 10));
    await old.up();
    await lead.up();
    await tester.pump(const Duration(milliseconds: 300));

    await expectRect(tester, confirmed, const Rect.fromLTRB(80, 160, 700, 1400));
  });

  testWidgets('領頭是不動的幽靈（靠近按下就升格）：閒置超過 150ms 後真手指接手',
      (tester) async {
    final confirmed = <PdfCropRect>[];
    await pumpOverlay(tester, onConfirm: confirmed.add);

    final real = await tester.startGesture(const Offset(80, 160));
    await real.moveTo(const Offset(400, 800));
    await tester.pump(const Duration(milliseconds: 16));
    final ghost = await tester.startGesture(const Offset(420, 820)); // 近處、不動
    await tester.pump(const Duration(milliseconds: 200)); // 領頭閒置
    await real.moveTo(const Offset(720, 1440));
    await tester.pump(const Duration(milliseconds: 16));
    await ghost.up();
    await real.up();
    await tester.pump(const Duration(milliseconds: 300));

    await expectRect(tester, confirmed, const Rect.fromLTRB(80, 160, 720, 1440));
  });

  // ── 快速拖拉：放開後 68ms 內，新 pointer 落在 300px 外（真機 id=16→id=17）──
  testWidgets('寬限期內的新按下不論距離都是接力：不得重設起點', (tester) async {
    final confirmed = <PdfCropRect>[];
    await pumpOverlay(tester, onConfirm: confirmed.add);

    final g1 = await tester.startGesture(const Offset(80, 160));
    await g1.moveTo(const Offset(243, 399));
    await tester.pump(const Duration(milliseconds: 16));
    await g1.up();
    await tester.pump(const Duration(milliseconds: 68)); // 仍在 250ms 寬限期內
    final g2 = await tester.startGesture(const Offset(544, 437)); // 300px 外
    await g2.moveTo(const Offset(700, 1000));
    await tester.pump(const Duration(milliseconds: 16));
    await g2.up();
    await tester.pump(const Duration(milliseconds: 300));

    await expectRect(tester, confirmed, const Rect.fromLTRB(80, 160, 700, 1000));
  });

  testWidgets('靠近按下但不動的新 pointer 不搶領頭：舊的那根繼續更新框', (tester) async {
    final confirmed = <PdfCropRect>[];
    await pumpOverlay(tester, onConfirm: confirmed.add);

    final old = await tester.startGesture(const Offset(80, 160));
    await old.moveTo(const Offset(400, 800));
    await tester.pump(const Duration(milliseconds: 16));
    final still = await tester.startGesture(const Offset(420, 820)); // 近處、不動
    await tester.pump(const Duration(milliseconds: 10));
    await old.moveTo(const Offset(500, 900)); // 才 10ms，領頭規則會擋掉它
    await tester.pump(const Duration(milliseconds: 10));
    await old.moveTo(const Offset(600, 1000));
    await tester.pump(const Duration(milliseconds: 10));
    await still.up();
    await old.up();
    await tester.pump(const Duration(milliseconds: 300));

    await expectRect(tester, confirmed, const Rect.fromLTRB(80, 160, 600, 1000));
  });

  testWidgets('放開超過寬限期後再按下：視為新一次框選，取代舊框', (tester) async {
    final confirmed = <PdfCropRect>[];
    await pumpOverlay(tester, onConfirm: confirmed.add);

    await dragSelect(tester, const Offset(80, 160), const Offset(720, 1440));
    await dragSelect(tester, const Offset(200, 400), const Offset(600, 1200));

    await expectRect(tester, confirmed, const Rect.fromLTRB(200, 400, 600, 1200));
  });

  testWidgets('放開後立刻按確認：先定案再回傳（不必等寬限期）', (tester) async {
    final confirmed = <PdfCropRect>[];
    await pumpOverlay(tester, onConfirm: confirmed.add);

    final g = await tester.startGesture(const Offset(80, 160));
    await g.moveTo(const Offset(720, 1440));
    await g.up();
    await tester.pump(const Duration(milliseconds: 20));

    await expectRect(tester, confirmed, const Rect.fromLTRB(80, 160, 720, 1440));
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

  testWidgets('onRestore 為 null 時不顯示還原鈕', (tester) async {
    await pumpOverlay(tester);
    expect(find.byKey(const Key('pdf_crop_frame_restore')), findsNothing);
  });

  testWidgets(
      'onRestore 非 null 時顯示還原鈕，點擊呼叫 onRestore 且不呼叫 onCancel／onConfirm',
      (tester) async {
    var restored = false;
    var cancelled = false;
    final confirmed = <PdfCropRect>[];
    await pumpOverlay(
      tester,
      onConfirm: confirmed.add,
      onCancel: () => cancelled = true,
      onRestore: () => restored = true,
    );
    await dragSelect(tester, const Offset(80, 160), const Offset(720, 1440));

    final restoreFinder = find.byKey(const Key('pdf_crop_frame_restore'));
    expect(restoreFinder, findsOneWidget);
    await tester.tap(restoreFinder);
    await tester.pump();

    expect(restored, isTrue);
    expect(cancelled, isFalse);
    expect(confirmed, isEmpty);
  });

  testWidgets('三顆鈕由左至右為 cancel、restore、confirm', (tester) async {
    await pumpOverlay(tester, onRestore: () {});
    final cancelDx =
        tester.getCenter(find.byKey(const Key('pdf_crop_frame_cancel'))).dx;
    final restoreDx =
        tester.getCenter(find.byKey(const Key('pdf_crop_frame_restore'))).dx;
    final confirmDx = tester.getCenter(confirmFinder).dx;
    expect(cancelDx, lessThan(restoreDx));
    expect(restoreDx, lessThan(confirmDx));
  });

  testWidgets('X 鈕與還原鈕各有 tooltip 文字', (tester) async {
    await pumpOverlay(tester, onRestore: () {});
    expect(find.byTooltip('放棄裁切'), findsOneWidget);
    expect(find.byTooltip('還原先前裁切'), findsOneWidget);
  });
}
