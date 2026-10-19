// app/lib/dictionary/models/lookup_request.dart

/// 查詢請求。刻意只有一個詞，沒有前後文欄位：
/// 從型別上保證不可能把書中內容送出去。
///
/// 請勿在此加入任何其他欄位；`lookup_request_test.dart` 會擋下。
/// 宣告為 `final class`：其他檔案無法繼承它來夾帶前後文欄位。
final class LookupRequest {
  const LookupRequest(this.word);

  final String word;

  @override
  bool operator ==(Object other) =>
      identical(this, other) || (other is LookupRequest && other.word == word);

  @override
  int get hashCode => word.hashCode;
}
