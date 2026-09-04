import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter_test/flutter_test.dart';
import 'package:elinkbook/library/txt_cover_generator.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  // 以下測試只驗證 PNG 檔案格式簽章與整張圖片 bytes 是否相等/不相等，刻意不做
  // 像素級的 Golden Image 比對——文字排版的實際渲染像素可能因執行平台（字型
  // 可用性等）而有差異，但背景色是先填滿整張畫布的純色矩形，足以保證「相同
  // 標題」與「不同標題」的整體 bytes 分別相等/不相等，不受平台間字型渲染差異
  // 影響，測試在任何平台上都應穩定通過。

  test('generateTxtCover 產生非空的 PNG bytes（含正確的 PNG 檔頭簽章）', () async {
    final bytes = await generateTxtCover('測試書名');

    expect(bytes, isNotEmpty);
    expect(
      bytes.sublist(0, 8),
      [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A],
      reason: 'PNG 檔案簽章（magic bytes）',
    );
  });

  test('相同書名產生相同背景色（可重現，非隨機）', () async {
    final bytes1 = await generateTxtCover('紅樓夢');
    final bytes2 = await generateTxtCover('紅樓夢');

    expect(bytes1, equals(bytes2));
  });

  test('不同書名（不同首字）產生不同背景色', () async {
    final bytes1 = await generateTxtCover('紅樓夢');
    final bytes2 = await generateTxtCover('三國演義');

    expect(bytes1, isNot(equals(bytes2)));
  });

  test('空字串書名不拋出例外，仍產生有效封面', () async {
    final bytes = await generateTxtCover('');

    expect(bytes, isNotEmpty);
  });

  group('E-Ink 模式（白底黑框黑字，Issue 8）', () {
    test('isEinkMode: true 時，四角為黑色邊框、邊框內側為白底', () async {
      final bytes = await generateTxtCover('測試書名', isEinkMode: true);

      // 邊框寬度 8px（見實作 _einkBorderWidth），採樣邊框實心區域內的像素
      // （2,2）而非最邊緣（0,0），避開抗鋸齒造成的邊界像素誤判。
      expect(await _pixelColor(bytes, 2, 2), const ui.Color(0xFF000000),
          reason: '左上角應為黑色邊框');
      expect(await _pixelColor(bytes, 397, 2), const ui.Color(0xFF000000),
          reason: '右上角應為黑色邊框');
      expect(await _pixelColor(bytes, 2, 397), const ui.Color(0xFF000000),
          reason: '左下角應為黑色邊框');
      expect(await _pixelColor(bytes, 397, 397), const ui.Color(0xFF000000),
          reason: '右下角應為黑色邊框');

      // (20,20) 遠離 8px 邊框範圍（0-8／392-400）與置中文字區域，應為白底。
      expect(await _pixelColor(bytes, 20, 20), const ui.Color(0xFFFFFFFF),
          reason: '邊框內側、文字區域外應為白底');
    });

    test('isEinkMode: true 時，中央文字區域包含黑色文字像素（非白底白字）', () async {
      // spec.md「寫死顏色遷移」txt_cover_generator.dart 部分明講：只換背景／
      // 外框、不換文字色的話會變成白底配白字，書名首字完全看不見——這是
      // 本工單要防的核心回歸（reviews/review-plan-issue-8.md C2）。
      final bytes = await generateTxtCover('測試書名', isEinkMode: true);

      // 沿畫布中心垂直掃描線（x=200）取樣，字型渲染的精確外形因平台而異，
      // 但只要書名首字真的是黑色，掃描線必定會穿過至少一個純黑像素；
      // 若文字誤留白色（白底白字回歸），這個範圍內不會有任何純黑像素。
      var hasBlackTextPixel = false;
      for (var y = 90; y <= 310; y += 5) {
        if (await _pixelColor(bytes, 200, y) == const ui.Color(0xFF000000)) {
          hasBlackTextPixel = true;
          break;
        }
      }
      expect(hasBlackTextPixel, isTrue,
          reason: 'E-Ink 模式下書名首字應為黑色，不可退化成白底白字');
    });

    test('isEinkMode: true 對同一書名兩次呼叫，輸出 bytes 相等（渲染穩定）', () async {
      final bytes1 = await generateTxtCover('紅樓夢', isEinkMode: true);
      final bytes2 = await generateTxtCover('紅樓夢', isEinkMode: true);

      expect(bytes1, equals(bytes2));
    });

    test('同一書名，isEinkMode: true 與 false 輸出 bytes 不相等（確認兩分支確實有差異）',
        () async {
      final einkBytes = await generateTxtCover('紅樓夢', isEinkMode: true);
      final normalBytes = await generateTxtCover('紅樓夢', isEinkMode: false);

      expect(einkBytes, isNot(equals(normalBytes)));
    });

    test('isEinkMode: false（既有行為）不受本次改動影響：角落像素非 E-Ink 黑色邊框',
        () async {
      final bytes = await generateTxtCover('紅樓夢', isEinkMode: false);

      // 既有 4 個測試已涵蓋色盤本身正確性（可重現／依書名不同而不同），
      // 這裡只補「不是 E-Ink 分支才會出現的黑色邊框」這個新增分支特有的
      // 區辨斷言，確認 false 分支未被新增的 E-Ink 邏輯誤觸發（審查修正
      // C1：先前版本誤比對純白色，即使誤觸發 E-Ink 分支仍會通過，見
      // reviews/review-plan-issue-8.md）。
      expect(await _pixelColor(bytes, 2, 2), isNot(const ui.Color(0xFF000000)));
    });
  });
}

/// 解碼 PNG bytes 並取出 (x, y) 位置的像素顏色，供大面積純色區塊（背景／
/// 邊框）與文字黑色像素掃描的採樣斷言使用。不做逐像素精確文字外形比對
/// （見上方檔案開頭註解）。
Future<ui.Color> _pixelColor(Uint8List pngBytes, int x, int y) async {
  final codec = await ui.instantiateImageCodec(pngBytes);
  final frame = await codec.getNextFrame();
  final image = frame.image;
  final byteData = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
  final bytes = byteData!.buffer.asUint8List();
  final offset = (y * image.width + x) * 4;
  return ui.Color.fromARGB(
    bytes[offset + 3],
    bytes[offset],
    bytes[offset + 1],
    bytes[offset + 2],
  );
}
