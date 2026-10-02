import 'cloud_storage_client.dart';

/// 判斷換發 token 的回應狀態碼是否代表「授權已被撤銷」（`CONTEXT.md`
/// 「雲端授權失效」）。token 端點對撤銷的 refresh token 回 400
/// （`invalid_grant`），對無效用戶端憑證回 401；其餘（429、5xx 等）是
/// 暫時性錯誤，使用者重新連結也救不了，不能當成授權失效。
///
/// Google Drive 與 OneDrive 兩個 OAuth client 共用這條規則，避免兩邊的
/// 判斷再次分岔（兩個 client 本身刻意不合併）。
bool isRefreshTokenRejected(int statusCode) =>
    statusCode == 400 || statusCode == 401;

/// 雲端硬碟資料 API（目錄、下載、縮圖）回傳非 200 時拋出對應例外：401
/// 代表 access token 被伺服器拒絕，拋出 [CloudAuthRequiredException] 讓
/// 呼叫端提示重新連結；其餘（403 額度／速率限制、5xx 等）維持一般例外。
/// 例外訊息格式沿用既有的「`message`（HTTP `statusCode`）」。
Never throwCloudApiStatusError(String message, int statusCode) {
  if (statusCode == 401) throw CloudAuthRequiredException();
  throw Exception('$message（HTTP $statusCode）');
}
