import 'package:flutter_test/flutter_test.dart';
import 'package:elinkbook/reader/text_offset_map.dart';

void main() {
  group('offsetMap 為 null／空時的零開銷路徑', () {
    test('offsetMap 為 null 時，origToDisplay／displayToOrig 皆原樣回傳', () {
      expect(origToDisplay(null, 5), 5);
      expect(displayToOrig(null, 5), 5);
    });

    test('entries 為空的 TextOffsetMap 視同 null，原樣回傳', () {
      const map = TextOffsetMap([]);
      expect(origToDisplay(map, 5), 5);
      expect(displayToOrig(map, 5), 5);
    });

    test('OffsetMapBuilder 沒有任何區段時 build() 回傳 null', () {
      final builder = OffsetMapBuilder();
      expect(builder.build(), isNull);
    });
  });

  group('單一區段（模擬「abc內存def」轉換為「abc記憶體def」）', () {
    // 內存@origOffset=3,origLen=2 -> 記憶體@dispOffset=3,dispLen=3，
    // delta=+1，accumDelta=0（唯一一個區段）。
    late TextOffsetMap map;

    setUp(() {
      final builder = OffsetMapBuilder();
      builder.addSegment(origOffset: 3, origLen: 2, dispOffset: 3, dispLen: 3);
      map = builder.build()!;
    });

    test('origToDisplay：區段之前的 offset 原樣回傳', () {
      expect(origToDisplay(map, 0), 0);
      expect(origToDisplay(map, 2), 2);
    });

    test('origToDisplay：區段起點對應到顯示區段起點', () {
      expect(origToDisplay(map, 3), 3);
    });

    test('origToDisplay：區段內部依比例位移', () {
      expect(origToDisplay(map, 4), 4);
    });

    test('origToDisplay：區段之後的 offset 加上累計 delta', () {
      // 原文第 5 個 code unit 是 "d"，顯示文字對應到索引 6。
      expect(origToDisplay(map, 5), 6);
    });

    test('displayToOrig：區段之前的 offset 原樣回傳', () {
      expect(displayToOrig(map, 2), 2);
    });

    test('displayToOrig：floor 貼齊區段起點（選取起點用）', () {
      expect(displayToOrig(map, 4, snapPolicy: 'floor'), 3);
      expect(displayToOrig(map, 5, snapPolicy: 'floor'), 3);
    });

    test('displayToOrig：ceil 貼齊區段終點（選取終點用）', () {
      expect(displayToOrig(map, 4, snapPolicy: 'ceil'), 5);
      expect(displayToOrig(map, 3, snapPolicy: 'ceil'), 5);
    });

    test('displayToOrig：區段之後的 offset 減去累計 delta', () {
      expect(displayToOrig(map, 6), 5);
    });
  });

  group('多區段（驗證 accumDelta 正確累加）', () {
    // 第一段：origOffset=0,origLen=2 -> dispOffset=0,dispLen=3（delta=+1）。
    // 第二段：origOffset=10,origLen=3 -> dispOffset=11,dispLen=2（delta=-1，
    // accumDelta 必須是第一段的 delta=+1，而非 0）。
    late TextOffsetMap map;

    setUp(() {
      final builder = OffsetMapBuilder();
      builder.addSegment(origOffset: 0, origLen: 2, dispOffset: 0, dispLen: 3);
      builder.addSegment(origOffset: 10, origLen: 3, dispOffset: 11, dispLen: 2);
      map = builder.build()!;
    });

    test('第二段的 accumDelta 正確反映第一段的 delta', () {
      expect(map.entries[1].accumDelta, 1);
    });

    test('origToDisplay：兩段之後的 offset 套用兩段的總 delta（抵銷為 0）', () {
      expect(origToDisplay(map, 13), 13);
    });

    test('displayToOrig：兩段之後的 offset 正確還原（總 delta 抵銷為 0）', () {
      expect(displayToOrig(map, 13), 13);
    });
  });

  group('縮短區段（模擬「公共汽車」(4) 轉換為「公車」(2)，審查修正 C-2）', () {
    // origOffset=0,origLen=4（"公共汽車"）-> dispOffset=0,dispLen=2
    // （"公車"），delta=-2，accumDelta=0。TWPhrases.txt 實際存在 237 條
    // 這類長度減少的詞彙（如「公共汽車」「方便面」「可執行文件」）。
    late TextOffsetMap map;

    setUp(() {
      final builder = OffsetMapBuilder();
      builder.addSegment(origOffset: 0, origLen: 4, dispOffset: 0, dispLen: 2);
      map = builder.build()!;
    });

    test('origToDisplay：區段內未超出顯示詞長度時正常對應', () {
      expect(origToDisplay(map, 0), 0);
      expect(origToDisplay(map, 1), 1);
    });

    test(
        'origToDisplay：區段內超出顯示詞長度時必須夾住在顯示詞尾（審查修正 '
        'C-2 核心案例）', () {
      // 修正前會回傳 2、3——超出顯示文字「公車」實際長度 2 的有效範圍，
      // 在 live DOM 對長度僅 2 的文字節點呼叫 range.setEnd(node, 3) 會
      // 直接拋出 IndexSizeError。修正後皆夾住在 dispLen=2。
      expect(origToDisplay(map, 2), 2);
      expect(origToDisplay(map, 3), 2);
    });

    test('origToDisplay：維持弱單調遞增，不因夾住而在區段邊界前後產生數值倒退', () {
      // 修正前：origOffset=3 -> 3、origOffset=4（區段之後）-> 2，數值倒退
      // （單調性破壞，$x_1 \\le x_2$ 卻 $f(x_1) > f(x_2)$）。修正後兩者
      // 皆為 2，不倒退。
      final beforeBoundary = origToDisplay(map, 3);
      final afterBoundary = origToDisplay(map, 4);
      expect(afterBoundary, greaterThanOrEqualTo(beforeBoundary));
      expect(afterBoundary, 2);
    });

    test('displayToOrig：floor／ceil 在夾住後的顯示區段內仍正確框住整個原文區段', () {
      expect(displayToOrig(map, 1, snapPolicy: 'floor'), 0);
      expect(displayToOrig(map, 1, snapPolicy: 'ceil'), 4);
    });

    test('displayToOrig：區段之後的 offset 正確還原', () {
      expect(displayToOrig(map, 2), 4);
    });
  });
}
