import 'package:elinkbook/reader/epub_decoration.dart';
import 'package:elinkbook/reader/epub_position_info.dart';
import 'package:elinkbook/reader/foliate_bridge_codec.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('extractCfi', () {
    test('新格式 JSON 正確取出 cfi 欄位', () {
      const json =
          '{"cfi":"epubcfi(/6/8!/4[story-2-2],/60/3:32,/70/1:32)","index":3,"fraction":0.042091}';
      expect(extractCfi(json), 'epubcfi(/6/8!/4[story-2-2],/60/3:32,/70/1:32)');
    });

    test('舊格式 Readium Locator JSON 沒有 cfi 欄位，回傳 null（優雅退回）', () {
      const readiumLocatorJson =
          '{"href":"/OEBPS/chapter1.xhtml","type":"application/xhtml+xml",'
          '"title":"Chapter 1","locations":{"progression":0.42,"totalProgression":0.1}}';
      expect(extractCfi(readiumLocatorJson), isNull);
    });

    test('格式錯誤的字串回傳 null，不拋出例外', () {
      expect(extractCfi('not a json string'), isNull);
    });

    test('null 輸入回傳 null', () {
      expect(extractCfi(null), isNull);
    });

    test('cfi 欄位為 null 值時回傳 null', () {
      expect(extractCfi('{"cfi":null,"index":0,"fraction":0}'), isNull);
    });

    test('cfi 欄位為非字串型別時回傳 null', () {
      expect(extractCfi('{"cfi":12345,"index":0,"fraction":0}'), isNull);
    });
  });

  group('parseTableOfContents', () {
    test('解析扁平（無巢狀子項目）目錄陣列', () {
      const json = '['
          '{"title":"第一章","locatorJson":"{\\"cfi\\":\\"epubcfi(/6/4)\\",\\"index\\":0,\\"fraction\\":0.0}",'
          '"progression":0.0,"children":[]},'
          '{"title":"第二章","locatorJson":"{\\"cfi\\":\\"epubcfi(/6/6)\\",\\"index\\":1,\\"fraction\\":0.5}",'
          '"progression":0.5,"children":[]}'
          ']';
      final entries = parseTableOfContents(json);
      expect(entries.length, 2);
      expect(entries[0].title, '第一章');
      expect(entries[1].progression, 0.5);
    });

    test('解析含巢狀子項目的目錄陣列（round-trip 驗證巢狀結構保留）', () {
      const json = '['
          '{"title":"第一部","locatorJson":"","progression":null,'
          '"children":[{"title":"第一章",'
          '"locatorJson":"{\\"cfi\\":\\"epubcfi(/6/4)\\",\\"index\\":0,\\"fraction\\":0.0}",'
          '"progression":0.0,"children":[]}]}'
          ']';
      final entries = parseTableOfContents(json);
      expect(entries.length, 1);
      expect(entries[0].progression, isNull);
      expect(entries[0].children.length, 1);
      expect(entries[0].children[0].title, '第一章');
    });

    test('格式錯誤的 JSON 陣列字串回傳空清單，不拋出例外', () {
      expect(parseTableOfContents('not a json array'), isEmpty);
    });

    test('空陣列回傳空清單', () {
      expect(parseTableOfContents('[]'), isEmpty);
    });
  });

  group('argbToCssColor', () {
    test('完全不透明色值換算 alpha 為 1.0', () {
      expect(argbToCssColor(0xFFFF0000), 'rgba(255, 0, 0, 1.0)');
    });

    test('完全透明色值換算 alpha 為 0.0', () {
      expect(argbToCssColor(0x0000FF00), 'rgba(0, 255, 0, 0.0)');
    });

    test('半透明色值正確拆解 RGB 並換算 alpha 為 0-1 浮點數', () {
      // highlighterYellowTint = Color(0x73FDE047)，見 highlight_style.dart。
      expect(
        argbToCssColor(0x73FDE047),
        'rgba(253, 224, 71, ${0x73 / 255.0})',
      );
    });
  });

  group('buildDecorationEntries', () {
    test('新格式 locatorJson 正確轉換為 cfi／color／isUnderline', () {
      final entries = buildDecorationEntries([
        EpubDecoration.forHighlight(
          highlightId: 'h5',
          locatorJson: '{"cfi":"epubcfi(/6/8!/4[story-2-2])","index":3,"fraction":0.04}',
          tint: 0xFFFF0000,
          isUnderline: false,
        ),
      ]);
      expect(entries.length, 1);
      expect(entries[0]['id'], 'highlight:h5');
      expect(entries[0]['cfi'], 'epubcfi(/6/8!/4[story-2-2])');
      expect(entries[0]['color'], 'rgba(255, 0, 0, 1.0)');
      expect(entries[0]['isUnderline'], false);
    });

    test('isUnderline 預設為 false（forNote 不接受 isUnderline 參數）', () {
      final entries = buildDecorationEntries([
        EpubDecoration.forNote(
          noteId: 'n1',
          locatorJson: '{"cfi":"epubcfi(/6/4)","index":0,"fraction":0.0}',
          tint: 0x73D1D5DB,
        ),
      ]);
      expect(entries[0]['isUnderline'], false);
    });

    test('舊格式（Readium Locator JSON）locatorJson 該筆略過', () {
      final entries = buildDecorationEntries([
        EpubDecoration(
          id: 'highlight:1',
          locatorJson: '{"href":"/OEBPS/chapter1.xhtml","locations":{"progression":0.1}}',
          tint: 0xFFFF0000,
        ),
      ]);
      expect(entries, isEmpty);
    });

    test('多筆項目保留順序，單筆失敗不影響其餘', () {
      final entries = buildDecorationEntries([
        EpubDecoration.forHighlight(
          highlightId: 'h1',
          locatorJson: '{"cfi":"epubcfi(/6/4)","index":0,"fraction":0.0}',
          tint: 0xFFFF0000,
          isUnderline: false,
        ),
        EpubDecoration(
          id: 'highlight:h2',
          locatorJson: '{"href":"/OEBPS/chapter1.xhtml"}',
          tint: 0xFF00FF00,
        ),
        EpubDecoration.forNote(
          noteId: 'n1',
          locatorJson: '{"cfi":"epubcfi(/6/6)","index":1,"fraction":0.5}',
          tint: 0x73D1D5DB,
        ),
      ]);
      expect(entries.length, 2);
      expect(entries[0]['id'], 'highlight:h1');
      expect(entries[1]['id'], 'note:n1');
    });

    test('空清單回傳空清單', () {
      expect(buildDecorationEntries(const []), isEmpty);
    });

    test('重複 cfi 的兩筆項目皆原樣保留，本函式不去重（已知限制，記錄於 main.js window.setDecorations 註解）', () {
      const sameCfi = '{"cfi":"epubcfi(/6/4)","index":0,"fraction":0.0}';
      final entries = buildDecorationEntries([
        EpubDecoration.forHighlight(
          highlightId: 'h1', locatorJson: sameCfi, tint: 0xFFFF0000, isUnderline: false,
        ),
        EpubDecoration.forHighlight(
          highlightId: 'h2', locatorJson: sameCfi, tint: 0xFF0000FF, isUnderline: false,
        ),
      ]);
      expect(entries.length, 2);
      expect(entries[0]['cfi'], 'epubcfi(/6/4)');
      expect(entries[1]['cfi'], 'epubcfi(/6/4)');
    });
  });

  group('isPathWithinRoot', () {
    const allowedRoot = '/data/user/0/cc.ugotit.elinkbook/files';

    test('合法路徑——請求路徑就是允許根目錄本身', () {
      expect(isPathWithinRoot(allowedRoot, allowedRoot), isTrue);
    });

    test('合法路徑——請求路徑是允許根目錄底下的子路徑', () {
      expect(
        isPathWithinRoot('$allowedRoot/books/novel.epub', allowedRoot),
        isTrue,
      );
    });

    test('不合法——已正規化解析後的路徑落在允許根目錄之外', () {
      expect(
        isPathWithinRoot(
          '/data/user/0/cc.ugotit.elinkbook/other/secret.txt',
          allowedRoot,
        ),
        isFalse,
      );
    });

    test('不合法——同前綴但其實是完全不同的目錄（純 startsWith 會誤判的邊界情況）', () {
      expect(
        isPathWithinRoot('${allowedRoot}_evil/secret.txt', allowedRoot),
        isFalse,
      );
    });

    test('不合法——符號連結指向允許目錄外，模擬解析後的絕對路徑', () {
      expect(
        isPathWithinRoot(
          '/data/user/0/other_app/databases/secrets.db',
          allowedRoot,
        ),
        isFalse,
      );
    });

    test('審查修正——Windows 反斜線路徑正規化後仍正確判斷（開發機平台相容性）', () {
      const windowsRoot = r'C:\Users\dev\AppData\Local\Temp\app\files';
      expect(
        isPathWithinRoot(
          r'C:\Users\dev\AppData\Local\Temp\app\files\sample.epub',
          windowsRoot,
        ),
        isTrue,
      );
      expect(
        isPathWithinRoot(
          r'C:\Users\dev\AppData\Local\Temp\app\files_evil\secret.txt',
          windowsRoot,
        ),
        isFalse,
      );
    });
  });

  group('parseLocatorChanged', () {
    test('流式格式：position 帶 locationIndex/locationTotal，'
        'visualPageIndex/visualTotalPages 為 null', () {
      final info = parseLocatorChanged([
        '{"cfi":"epubcfi(/6/4)","index":0,"fraction":0.1}',
        '{"fraction":0.1,"locationIndex":9,"locationTotal":100,'
            '"visualPageIndex":null,"visualTotalPages":null}',
      ]);
      expect(info.locatorJson, '{"cfi":"epubcfi(/6/4)","index":0,"fraction":0.1}');
      expect(info.progression, 0.1);
      expect(info.locationIndex, 9);
      expect(info.locationTotal, 100);
      expect(info.visualPageIndex, isNull);
      expect(info.visualTotalPages, isNull);
    });

    test('FXL/CBZ 格式：position 帶 visualPageIndex/visualTotalPages，'
        'locationIndex/locationTotal 為 null', () {
      final info = parseLocatorChanged([
        '{"cfi":"epubcfi(/6/4)","index":0,"fraction":0.5}',
        '{"fraction":0.5,"locationIndex":null,"locationTotal":null,'
            '"visualPageIndex":3,"visualTotalPages":20}',
      ]);
      expect(info.locationIndex, isNull);
      expect(info.locationTotal, isNull);
      expect(info.visualPageIndex, 3);
      expect(info.visualTotalPages, 20);
    });

    test('args 只有 1 個元素（第二參數缺席）：位置欄位皆為 null，'
        'progression 退回 0.0，locatorJson 仍取自 args[0]', () {
      final info = parseLocatorChanged(['{"cfi":"epubcfi(/6/4)"}']);
      expect(info.locatorJson, '{"cfi":"epubcfi(/6/4)"}');
      expect(info.progression, 0.0);
      expect(info.locationIndex, isNull);
      expect(info.locationTotal, isNull);
      expect(info.visualPageIndex, isNull);
      expect(info.visualTotalPages, isNull);
    });

    test('args 為空清單：locatorJson 為空字串，位置欄位皆為 null', () {
      final info = parseLocatorChanged(const []);
      expect(info.locatorJson, '');
      expect(info.progression, 0.0);
      expect(info.locationIndex, isNull);
    });

    test('args[1] 格式錯誤（非合法 JSON）：位置欄位皆為 null，不拋出例外', () {
      final info = parseLocatorChanged([
        '{"cfi":"epubcfi(/6/4)"}',
        'not a json string',
      ]);
      expect(info.locationIndex, isNull);
      expect(info.locationTotal, isNull);
      expect(info.visualPageIndex, isNull);
      expect(info.visualTotalPages, isNull);
    });

    test('args[1] 違反互斥不變式（locationIndex/locationTotal 與 '
        'visualPageIndex/visualTotalPages 同時給值）：拋出 AssertionError', () {
      expect(
        () => parseLocatorChanged([
          '{"cfi":"epubcfi(/6/4)","index":0,"fraction":0.1}',
          '{"fraction":0.1,"locationIndex":9,"locationTotal":100,'
              '"visualPageIndex":3,"visualTotalPages":20}',
        ]),
        throwsA(isA<AssertionError>()),
      );
    });
  });

  group('EpubPositionInfo.displayPageIndex / displayTotalPages', () {
    test('流式格式（只有 locationIndex/locationTotal 有值）：'
        'display getter 退回採用 location 值', () {
      const info = EpubPositionInfo(
        locatorJson: '{}',
        locationIndex: 9,
        locationTotal: 100,
      );
      expect(info.displayPageIndex, 9);
      expect(info.displayTotalPages, 100);
    });

    test('FXL 格式（只有 visualPageIndex/visualTotalPages 有值）：'
        'display getter 優先採用 visual 值', () {
      const info = EpubPositionInfo(
        locatorJson: '{}',
        visualPageIndex: 3,
        visualTotalPages: 20,
      );
      expect(info.displayPageIndex, 3);
      expect(info.displayTotalPages, 20);
    });

    test('兩組皆為 null（尚未收到任何 relocate 事件）：display getter 回傳 null',
        () {
      const info = EpubPositionInfo(locatorJson: '{}');
      expect(info.displayPageIndex, isNull);
      expect(info.displayTotalPages, isNull);
    });
  });

  group('EpubPositionInfo 建構子互斥不變式', () {
    test('locationIndex/locationTotal 與 visualPageIndex/visualTotalPages '
        '同時非 null：拋出 AssertionError', () {
      expect(
        () => EpubPositionInfo(
          locatorJson: '{}',
          locationIndex: 1,
          locationTotal: 10,
          visualPageIndex: 2,
          visualTotalPages: 20,
        ),
        throwsA(isA<AssertionError>()),
      );
    });

    test('只有 locationIndex 非 null（另一組完全 null）：正常建構', () {
      expect(
        () => EpubPositionInfo(
          locatorJson: '{}',
          locationIndex: 1,
          visualPageIndex: null,
        ),
        returnsNormally,
      );
    });

    test('只有 visualPageIndex 非 null（另一組完全 null）：正常建構', () {
      expect(
        () => EpubPositionInfo(
          locatorJson: '{}',
          locationIndex: null,
          visualPageIndex: 2,
        ),
        returnsNormally,
      );
    });

    test('兩組皆為 null：正常建構', () {
      expect(
        () => const EpubPositionInfo(locatorJson: '{}'),
        returnsNormally,
      );
    });
  });
}
