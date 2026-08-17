import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:elinkbook/library/md_frontmatter.dart';

void main() {
  test('正確解析含 title/author 的 Frontmatter，body 為其後內容', () {
    const content = '---\ntitle: 測試筆記\nauthor: 測試作者\n---\n# 標題\n內容';
    final result = parseMdFrontmatter(content);
    expect(result.frontmatter.title, '測試筆記');
    expect(result.frontmatter.author, '測試作者');
    expect(result.body.trim(), '# 標題\n內容');
  });

  test('沒有 Frontmatter 時，frontmatter 全為 null，body 為原始內容', () {
    const content = '# 標題\n沒有 frontmatter 的內容';
    final result = parseMdFrontmatter(content);
    expect(result.frontmatter.title, isNull);
    expect(result.frontmatter.author, isNull);
    expect(result.frontmatter.coverBytes, isNull);
    expect(result.body, content);
  });

  test('開頭是 --- 但找不到結尾 --- 時，視為沒有 Frontmatter', () {
    const content = '---\ntitle: 未閉合\n# 標題\n內容';
    final result = parseMdFrontmatter(content);
    expect(result.frontmatter.title, isNull);
    expect(result.body, content);
  });

  test('YAML 格式錯誤時降級為沒有 metadata，但仍剝離起訖線', () {
    const content = '---\ntitle: "未閉合的引號\n---\n內容';
    final result = parseMdFrontmatter(content);
    expect(result.frontmatter.title, isNull);
    expect(result.body.trim(), '內容');
  });

  test('cover 為 data: URI（base64）時正確解碼為位元組', () {
    final pngBytes = [0x89, 0x50, 0x4E, 0x47];
    final base64Data = base64Encode(pngBytes);
    final content = '---\ntitle: 有封面\ncover: data:image/png;base64,$base64Data\n---\n內容';
    final result = parseMdFrontmatter(content);
    expect(result.frontmatter.coverBytes, pngBytes);
  });

  test('cover 為相對路徑（非 data: URI）時忽略，coverBytes 為 null（本 Issue 明確排除範圍）', () {
    const content = '---\ntitle: 相對路徑封面\ncover: ./img/cover.png\n---\n內容';
    final result = parseMdFrontmatter(content);
    expect(result.frontmatter.coverBytes, isNull);
  });

  test('Frontmatter 只有部分欄位時，其餘欄位為 null', () {
    const content = '---\ntitle: 只有標題\n---\n內容';
    final result = parseMdFrontmatter(content);
    expect(result.frontmatter.title, '只有標題');
    expect(result.frontmatter.author, isNull);
  });

  test('含 UTF-8 BOM 開頭的 Frontmatter 亦能正常解析 (Ruling 2)', () {
    const content = '\uFEFF---\ntitle: BOM 標題\n---\n內容';
    final result = parseMdFrontmatter(content);
    expect(result.frontmatter.title, 'BOM 標題');
    expect(result.body.trim(), '內容');
  });
}
