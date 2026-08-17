import 'package:flutter_test/flutter_test.dart';
import 'package:xml/xml.dart';
import 'package:elinkbook/library/epub_container_builder.dart';

void main() {
  test('escapeXml 跳脫 &/</> 三個保留字元', () {
    expect(escapeXml('A & B < C > D'), 'A &amp; B &lt; C &gt; D');
  });

  test('kEpubContainerXml 是良好格式 XML，rootfile 指向 OEBPS/content.opf', () {
    final doc = XmlDocument.parse(kEpubContainerXml);
    final rootfile = doc.findAllElements('rootfile').single;
    expect(rootfile.getAttribute('full-path'), 'OEBPS/content.opf');
    expect(rootfile.getAttribute('media-type'), 'application/oebps-package+xml');
  });

  test('buildEpubContentOpf 產生良好格式 XML，含 identifier/title/manifest/spine', () {
    final opf = buildEpubContentOpf(
      identifier: 'elinkbook-test-book1',
      title: '測試書名',
      manifestItems: '<item id="chap1" href="text/chap1.xhtml" media-type="application/xhtml+xml"/>\n',
      spineItems: '<itemref idref="chap1"/>\n',
    );
    final doc = XmlDocument.parse(opf);
    expect(doc.findAllElements('dc:identifier').single.innerText, 'elinkbook-test-book1');
    expect(doc.findAllElements('dc:title').single.innerText, '測試書名');
    expect(doc.findAllElements('dc:language').single.innerText, 'zh');
    expect(doc.findAllElements('item').where((e) => e.getAttribute('id') == 'chap1'), hasLength(1));
    expect(doc.findAllElements('itemref').single.getAttribute('idref'), 'chap1');
  });

  test('buildEpubContentOpf 的 title 正確跳脫特殊字元', () {
    final opf = buildEpubContentOpf(
      identifier: 'elinkbook-test-book2',
      title: 'A & B',
      manifestItems: '',
      spineItems: '',
    );
    final doc = XmlDocument.parse(opf);
    expect(doc.findAllElements('dc:title').single.innerText, 'A & B');
  });

  test('buildEpubNavXhtml 產生良好格式 XML，含 epub:type="toc"', () {
    final nav = buildEpubNavXhtml('<li><a href="text/chap1.xhtml">第一章</a></li>\n');
    final doc = XmlDocument.parse(nav);
    final navElement = doc.findAllElements('nav').single;
    expect(navElement.getAttribute('type', namespace: 'http://www.idpf.org/2007/ops'), 'toc');
    expect(doc.findAllElements('a').single.innerText, '第一章');
  });
}
