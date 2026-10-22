// app/lib/dictionary/mdx_companion_files.dart

/// 使用者在選檔器選到的一個檔案。
class PickedFile {
  const PickedFile({
    required this.path,
    required this.name,
    required this.size,
  });

  final String path;
  final String name;
  final int size;
}

/// 一本 MDX 與它的附屬檔案。
class MdxGroup {
  const MdxGroup({required this.mdx, this.mdd, this.css = const []});

  final PickedFile mdx;

  /// 主檔名相同的 `.mdd`；沒有則為 `null`。
  final PickedFile? mdd;

  /// 同一批選到的所有 `.css`（是否被詞條引用在抽樣後才比對，這裡不過濾）。
  final List<PickedFile> css;
}

/// 多選檔案的分組結果。
class CompanionPlan {
  const CompanionPlan({
    required this.groups,
    required this.others,
    required this.unmatchedCompanions,
  });

  final List<MdxGroup> groups;

  /// 非 MDX 系列的檔案，交給一般匯入器。
  final List<PickedFile> others;

  /// 沒有任何 `.mdx` 可附加的 `.mdd`／`.css`。
  final List<PickedFile> unmatchedCompanions;
}

String _ext(String name) {
  final dot = name.lastIndexOf('.');
  return dot < 0 ? '' : name.substring(dot).toLowerCase();
}

String _stem(String name) {
  final dot = name.lastIndexOf('.');
  return (dot < 0 ? name : name.substring(0, dot)).toLowerCase();
}

/// 把一批檔案分成 MDX 組、一般檔、無主的附屬檔。副檔名與主檔名皆不分大小寫。
CompanionPlan planCompanions(List<PickedFile> files) {
  final mdxFiles = <PickedFile>[];
  final mddFiles = <PickedFile>[];
  final cssFiles = <PickedFile>[];
  final others = <PickedFile>[];
  for (final f in files) {
    switch (_ext(f.name)) {
      case '.mdx':
        mdxFiles.add(f);
      case '.mdd':
        mddFiles.add(f);
      case '.css':
        cssFiles.add(f);
      default:
        others.add(f);
    }
  }

  final usedMdd = <PickedFile>{};
  final groups = <MdxGroup>[];
  for (final mdx in mdxFiles) {
    PickedFile? mdd;
    for (final candidate in mddFiles) {
      if (!usedMdd.contains(candidate) &&
          _stem(candidate.name) == _stem(mdx.name)) {
        mdd = candidate;
        usedMdd.add(candidate);
        break;
      }
    }
    groups.add(MdxGroup(mdx: mdx, mdd: mdd, css: List.unmodifiable(cssFiles)));
  }

  final unmatched = <PickedFile>[
    for (final f in files)
      if (_ext(f.name) == '.mdd' && !usedMdd.contains(f)) f,
    if (mdxFiles.isEmpty) ...cssFiles,
  ];
  // 維持使用者選檔的原順序。
  unmatched.sort((a, b) => files.indexOf(a).compareTo(files.indexOf(b)));
  return CompanionPlan(
    groups: groups,
    others: others,
    unmatchedCompanions: unmatched,
  );
}

final linkTagPattern = RegExp(r'<link\b[^>]*>', caseSensitive: false);
final hrefAttrPattern = RegExp(
  '''href\\s*=\\s*(?:"([^"]*)"|'([^']*)'|([^\\s>]+))''',
  caseSensitive: false,
);

/// 從 href 屬性值取出小寫檔名（去掉查詢字串、錨點與路徑）。
String extractFileNameFromHref(String hrefValue) {
  final clean = hrefValue.split(RegExp(r'[?#]')).first;
  return clean.split(RegExp(r'[/\\]')).last.toLowerCase();
}

/// 從 HTML 的 `<link href="x.css">` 取出被引用的樣式表檔名（不含路徑、
/// 轉小寫、去重）。`@import` 不算。
Set<String> extractReferencedCssNames(Iterable<String> bodies) {
  final names = <String>{};
  for (final body in bodies) {
    for (final tag in linkTagPattern.allMatches(body)) {
      final href = hrefAttrPattern.firstMatch(tag.group(0)!);
      if (href == null) continue;
      final value = href.group(1) ?? href.group(2) ?? href.group(3) ?? '';
      // 只留檔名，去掉查詢字串、錨點與路徑。
      final name = extractFileNameFromHref(value);
      if (name.endsWith('.css')) names.add(name);
    }
  }
  return names;
}

/// 回傳 [referenced] 中 [present] 沒有的檔名（不分大小寫比對，
/// 維持 [referenced] 的順序與原寫法）。
List<String> missingCss({
  required Iterable<String> referenced,
  required Iterable<String> present,
}) {
  final have = {for (final p in present) p.toLowerCase()};
  return [
    for (final r in referenced)
      if (!have.contains(r.toLowerCase())) r,
  ];
}
