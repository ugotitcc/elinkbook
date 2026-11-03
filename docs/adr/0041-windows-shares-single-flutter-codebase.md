# ADR 0041：Windows 版與 Android 共用同一份 Flutter 程式碼

## 狀態

已採納（2026-11-03）。對應 `epic-66-windows-port`。

## 背景

使用者要把現有功能移植到 Windows。做法有兩種：在 `app/` 加 `windows/` 平台資料夾，共用同一份 Dart 程式碼；或另開一個 Windows 專用 App，複製共用部分。

Android 的原生部分（`app/android/` 下 1,159 行 Kotlin、7 個 `elinkbook/*` MethodChannel）不能直接搬到 Windows。這些地方 Windows 要換做法，其他 Dart 程式碼大部分可以共用。

## 決策

1. 在 `app/` 加 `windows/`，與 Android 共用同一份 `lib/`。不另開專案。
2. 平台差異用平台判斷分流，不複製畫面或服務。不支援的功能照 `CONTEXT.md`「平台專屬功能」處理：直接隱藏入口。
3. 不改變 Android 的行為。Windows 專屬的替代實作（例如 metadata 解析、送書給 WebView）放在 Windows 分支，Android 路徑維持原樣，直到 Windows 實作被證實與 Android 結果一致。
4. 第一版在 Windows 隱藏：音量鍵翻頁、E-Ink 高對比與影像濾鏡、螢幕方向鎖定。延後：Google Drive／OneDrive 雲端匯入。TTS 只用 `flutter_tts`，不做背景播放與系統媒體控制。

## 替代方案與取捨

- **另開 Windows 專用 App**：被否決。兩邊的 bug 修正要各做一次，同步格式與資料庫版本也會分岔。
- **改寫成 Electron 或 Tauri**：被否決。會丟掉 `pdfrx`、`sqflite`、`flutter_secure_storage` 等現有相依，等於重寫。

## 後果

- 每個動到原生 channel 的 Issue，都要回答「Windows 怎麼辦」，並在 `epic-66` 追蹤。
- `flutter test` 本來就在 Windows 主機上執行，所以現有單元測試不會因為加了 `windows/` 而失效。但依賴 Android 平台的測試要加平台判斷。
- Windows 版的相依套件要和現有的 `win32` 版本鏈相容（見 `app/pubspec.yaml` 中 `share_plus` 的註解）。升級任何一個都要先確認這條鏈。
