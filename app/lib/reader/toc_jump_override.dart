/// 目錄跳轉後的「目前章節」覆寫（epic-66 Issue 20）。
///
/// 桌面寬度雙欄下，foliate 的 relocate range 涵蓋左右兩欄，`TOCProgress` 取
/// 「range 內最後一個目錄項」，且短章節會被補入前一節內容，所以從目錄跳到某章
/// 後回報的 `tocItemId` 可能是前一章或章內最後一節。這裡的規則：使用者從目錄
/// 主動跳轉後，在這次跳轉造成的位置回報期間，目前章節就是點選的那一項；
/// 使用者之後翻頁（位置再改變）就恢復使用 foliate 回報的判定。
///
/// 位置以 `EpubPositionInfo.positionKey` 比較（忽略 fraction 抖動）。
///
/// 雙欄跳轉會連續回報兩次：先落在目標（tocItem 正確），約 260ms 後 paginator
/// 補欄完成再回報一次（位置改成補入的前一節，tocItem 偏掉，Windows 實測）。
/// 所以落地後 [settleWindow] 內的位置變化視為排版穩定、不解除覆寫；超過這段
/// 時間才有位置變化，才當成使用者翻頁。
///
/// 已知限制：若跳轉目標就是目前位置而不產生任何 relocate，下一次翻頁的位置
/// 變化會被當成這次跳轉的回報，覆寫多撐一步才解除。
class TocJumpOverride {
  TocJumpOverride({
    DateTime Function() now = DateTime.now,
    this.settleWindow = const Duration(milliseconds: 1500),
  }) : _now = now;

  final DateTime Function() _now;
  final Duration settleWindow;

  int? _tocId;
  String? _beforeKey;
  String? _landedKey;
  DateTime? _landedAt;

  /// 目前有效的覆寫 tocId；沒有覆寫時為 `null`（注意 0 是合法 id）。
  int? get tocId => _tocId;

  /// 使用者從目錄點選項目、即將跳轉時呼叫。[currentKey] 是跳轉前的位置鍵。
  /// [tocId] 為 `null`（舊資料或節點缺 id）時不覆寫，維持原判定。
  void begin({required int? tocId, required String? currentKey}) {
    _tocId = tocId;
    _beforeKey = currentKey;
    _landedKey = null;
    _landedAt = null;
  }

  /// 每次收到位置回報時呼叫，[key] 為該次回報的位置鍵。
  void onPosition(String key) {
    if (_tocId == null) return;
    if (_landedKey == null) {
      // 還沒落地：與跳轉前相同的位置是舊回報，略過。
      if (key != _beforeKey) {
        _landedKey = key;
        _landedAt = _now();
      }
      return;
    }
    // 落地並度過排版穩定期後位置又變了：使用者翻頁，解除覆寫。
    if (key != _landedKey && _now().difference(_landedAt!) > settleWindow) {
      clear();
    }
  }

  void clear() {
    _tocId = null;
    _beforeKey = null;
    _landedKey = null;
    _landedAt = null;
  }
}
