/// 雲端匯入來源帳號的 provider（epic-29-cloud-import，spec.md「帳號模組」）：
/// 與 `CONTEXT.md`「雲端匯入來源帳號」對應，語意上與 `epic-30`「遠端書庫」
/// （Calibre／OPDS，`RemoteServerProfile`）完全獨立，不共用型別。[oneDrive]
/// 目前僅預留資料結構，實際串接留給 Issue 2。
enum CloudProvider { googleDrive, oneDrive }
