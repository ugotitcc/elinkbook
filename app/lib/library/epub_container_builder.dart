// app/lib/library/epub_container_builder.dart

/// 跳脫 XML 屬性或文字節點中的保留特殊字元（&, <, >）
String escapeXml(String text) =>
    text.replaceAll('&', '&amp;').replaceAll('<', '&lt;').replaceAll('>', '&gt;');

/// EPUB3 容器 meta 描述檔（META-INF/container.xml）
const String kEpubContainerXml = '''<?xml version="1.0" encoding="UTF-8"?>
<container version="1.0" xmlns="urn:oasis:names:tc:opendocument:xmlns:container">
  <rootfiles>
    <rootfile full-path="OEBPS/content.opf" media-type="application/oebps-package+xml"/>
  </rootfiles>
</container>
''';

/// 產生 EPUB3 的 Package Document（OEBPS/content.opf）
String buildEpubContentOpf({
  required String identifier,
  required String title,
  required String manifestItems,
  required String spineItems,
  String language = 'zh',
}) =>
    '''<?xml version="1.0" encoding="UTF-8"?>
<package xmlns="http://www.idpf.org/2007/opf" version="3.0" unique-identifier="book-id">
  <metadata xmlns:dc="http://purl.org/dc/elements/1.1/">
    <dc:identifier id="book-id">$identifier</dc:identifier>
    <dc:title>${escapeXml(title)}</dc:title>
    <dc:language>$language</dc:language>
  </metadata>
  <manifest>
    <item id="nav" href="nav.xhtml" media-type="application/xhtml+xml" properties="nav"/>
$manifestItems  </manifest>
  <spine>
$spineItems  </spine>
</package>
''';

/// 產生 EPUB3 的導覽文件（OEBPS/nav.xhtml，目錄）
String buildEpubNavXhtml(String navItems) =>
    '''<?xml version="1.0" encoding="UTF-8"?>
<html xmlns="http://www.w3.org/1999/xhtml" xmlns:epub="http://www.idpf.org/2007/ops">
<head><title>目錄</title></head>
<body>
<nav epub:type="toc">
<ol>
$navItems</ol>
</nav>
</body>
</html>
''';
