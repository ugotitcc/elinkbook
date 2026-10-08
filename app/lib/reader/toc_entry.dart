import 'book_toc_item.dart';

/// EPUB 目錄樹狀清單的單一節點（epic-5-toc-pagination Issue 4，spec.md
/// 「目錄模組」）：原生端一次性讀取 `Publication.tableOfContents` 後序列化
/// 傳來，保留完整巢狀階層（[children]，不攤平）。
///
/// 刻意不覆寫 `==`/`hashCode`（維持預設的物件識別語意）——[TocNavigator]
/// 回傳的「目前章節路徑」與 UI 的展開狀態集合，判斷依據都是「是否為同一個
/// 節點物件參照」，只要 `entries` 樹狀結構本身在同一次 build 週期內沒有
/// 被重新解析成新物件，物件識別語意就足夠正確，不需要值相等語意。
///
/// 實作 [BookTocItem]（epic-24-pdf-engine-rebuild Issue 5）：[children]
/// 欄位型別 `List<TocEntry>` 透過 Dart 協變泛型滿足介面宣告的
/// `List<BookTocItem>`，不需要額外轉換；[stableId] 直接回傳
/// [locatorJson]，確保既有的 `Key('toc_entry_${entry.locatorJson}')` 等
/// 既有 Widget Key 命名（`toc_bottom_sheet.dart`）逐位元組不變。
class TocEntry implements BookTocItem {
  @override
  final String title;

  /// 原生端 `Locator.toJSON().toString()`，透過
  /// `Publication.locatorFromLink(Link)` 建構、保留錨點精度（非僅解析到
  /// resource 起始位置）。點選項目時原樣傳回原生端 `jumpToLocator` 還原。
  final String locatorJson;

  /// 全書閱讀進度比例（0.0-1.0），供換算估算頁碼。原生端優先取用
  /// [locatorJson] 對應 Locator 自身的 `totalProgression`；查無則退回比對
  /// `Publication.positions()`，仍查無時為 `null`（此時 UI 顯示佔位符，不
  /// 視為錯誤）。
  final double? progression;

  /// foliate 為目錄項指派的唯一整數 id（`progress.js assignIDs`，DFS 前序、
  /// 從 0 起）。`main.js buildTocEntry` 輸出；供 [TocNavigator] 與
  /// `EpubPositionInfo.tocItemId`（foliate 以 live DOM 判定的目前目錄項）
  /// 直接比對，免除同一 spine 多錨點時依 progression 猜測的不精確
  /// （epic-54 Issue 20）。舊資料或非 foliate 來源為 `null`。
  final int? tocId;

  @override
  final List<TocEntry> children;

  @override
  String get stableId => locatorJson;

  const TocEntry({
    required this.title,
    required this.locatorJson,
    this.progression,
    this.tocId,
    this.children = const [],
  });

  /// 遞迴解析原生端 `getTableOfContents` 回傳的巢狀 map 結構。缺失的
  /// `title`／`locatorJson` 以空字串防呆（不拋出例外），比照專案既有對
  /// MethodChannel 回傳資料的寬容解析慣例。
  factory TocEntry.fromWire(Map<Object?, Object?> map) {
    final rawChildren = map['children'] as List<Object?>? ?? const [];
    return TocEntry(
      title: map['title'] as String? ?? '',
      locatorJson: map['locatorJson'] as String? ?? '',
      progression: (map['progression'] as num?)?.toDouble(),
      tocId: (map['tocId'] as num?)?.toInt(),
      children: rawChildren
          .map((e) => TocEntry.fromWire(e as Map<Object?, Object?>))
          .toList(),
    );
  }
}
