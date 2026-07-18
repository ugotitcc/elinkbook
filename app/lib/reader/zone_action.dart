/// 熱區動作：使用者點擊 3×3 導航熱區某一格時觸發的行為
/// （design.md 決策 #8）。
enum ZoneAction { previousPage, nextPage, menu, none }

/// 驗證自訂熱區設定是否合法：長度需固定為 9，且至少 1 格為
/// [ZoneAction.menu]——避免使用者設定出沒有任何格子能退出沉浸模式的死鎖
/// 組合（design.md 決策 #7）。`NavZoneSettingsScreen`（Issue 3）儲存自訂
/// 設定前呼叫。
bool isValidCustomZoneConfig(List<ZoneAction> actions) =>
    actions.length == 9 && actions.contains(ZoneAction.menu);
