/// 單筆「劃線/純備註」的原生疊加樣式資訊（epic-6-annotations Issue 2），
/// 供 [EpubReaderView.setDecorations] 一次性送出目前應顯示的完整標記
/// 清單（非增量 diff，比照既有 `setPreferences`「整組送出目前狀態」
/// 慣例）。[id] 一律由 [forHighlight]／[forNote] 這兩個具名建構子產生
/// （審查修正：原本由呼叫端〔ReaderScreen〕直接手動字串拼接
/// `'highlight:${h.id}'`，散落各處且缺乏型別安全，收斂為本類別自己的
/// 具名建構子，搭配 [decodeAnnotationId] 做反向解析，兩者對稱維護在
/// 同一個檔案）。[tint] 為完整 ARGB 色值（見 highlight_style.dart「色彩
/// 決策收斂在 Dart 端」），原生端不需維護色彩對照表。[isUnderline] 為
/// true 時原生端套用 `Decoration.Style.Underline`，否則套用
/// `Style.Highlight`（螢光筆三色與純備註灰底皆屬此類）。
class EpubDecoration {
  final String id;
  final String locatorJson;
  final int tint;
  final bool isUnderline;

  const EpubDecoration({
    required this.id,
    required this.locatorJson,
    required this.tint,
    this.isUnderline = false,
  });

  factory EpubDecoration.forHighlight({
    required int highlightId,
    required String locatorJson,
    required int tint,
    required bool isUnderline,
  }) {
    return EpubDecoration(
      id: 'highlight:$highlightId',
      locatorJson: locatorJson,
      tint: tint,
      isUnderline: isUnderline,
    );
  }

  factory EpubDecoration.forNote({
    required int noteId,
    required String locatorJson,
    required int tint,
  }) {
    return EpubDecoration(id: 'note:$noteId', locatorJson: locatorJson, tint: tint);
  }

  Map<String, Object?> toWire() => {
        'id': id,
        'locatorJson': locatorJson,
        'tint': tint,
        'isUnderline': isUnderline,
      };
}

/// 標記種類，對應 [EpubDecoration.id] 的字串前綴（`"highlight"`／
/// `"note"`）。
enum AnnotationKind { highlight, note }

/// 解析原生端 `onAnnotationActivated` 回傳的標記 id 字串（見
/// [EpubDecoration.forHighlight]/[EpubDecoration.forNote] 的編碼慣例），
/// 供 `ReaderScreen` 反查是哪一張表的哪一筆資料庫記錄（審查修正：原本
/// `decorationId.split(':')` 與 `parts[1]` 這種型別不安全的字串操作直接
/// 寫在 `ReaderScreen` 內，收斂為單一、集中管理的解析函式）。格式不符
/// （前綴非 `highlight`/`note`、或 id 部分不是合法整數）時回傳 `null`，
/// 不拋出例外——理論上不會發生（id 皆由本檔案的具名建構子產生），但呼叫
/// 端仍須以「查無對應記錄」的靜默忽略原則處理，見 spec.md 既有慣例。
DecodedAnnotationId? decodeAnnotationId(String encoded) {
  final parts = encoded.split(':');
  if (parts.length != 2) return null;
  final id = int.tryParse(parts[1]);
  if (id == null) return null;
  final AnnotationKind? kind = switch (parts[0]) {
    'highlight' => AnnotationKind.highlight,
    'note' => AnnotationKind.note,
    _ => null,
  };
  if (kind == null) return null;
  return (kind: kind, id: id);
}

/// [decodeAnnotationId] 的回傳型別（Dart 3 record），比宣告一個只有兩個
/// 唯讀欄位的小型 class 更精簡。
typedef DecodedAnnotationId = ({AnnotationKind kind, int id});
