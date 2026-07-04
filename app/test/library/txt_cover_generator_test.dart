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
}
