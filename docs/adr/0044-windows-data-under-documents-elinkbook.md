# ADR 0044：Windows 版把「文件」資料夾內的資料收進上層目錄 `文件\elinkbook`，不遷移舊資料

## 狀態

已採納（2026-11-13）。對應 `epic-66-windows-port` Issue 29；取代 [ADR 0043](0043-windows-installer-inno-setup-unsigned-per-user.md) 決策 5 中「以固定名稱清單刪除『文件』資料夾內項目」的做法。

## 背景

Windows 版所有用 `getApplicationDocumentsDirectory()` 的地方，都把檔案直接放在使用者的「文件」資料夾根目錄：`library.db`、`dictionary.db`、`covers`、`imported_books`、`cloud_import_books`、`remote_books`、`wifi_transfer_uploads`、`update_staging`。使用者看不出這些屬於哪個 App，與自己的檔案混在一起；ADR 0043 的解除安裝因此只能以通用名稱（`covers`、`imported_books`）逐項刪除，有誤刪使用者同名資料夾的風險。Android 的同一個函式回傳 App 私有空間，沒有這個問題。

資料庫（`library.db`）存的是**絕對路徑**：`Book.filePath`（匯入的複本）與 `Book.coverPath`。

## 決策

1. **只改 Windows**，用集中函式 `appDocumentsDirectory()` 取代所有直接呼叫 `getApplicationDocumentsDirectory()` 的地方：Windows 回傳 `<文件>\elinkbook`（不存在就建立），其他平台原樣回傳 `getApplicationDocumentsDirectory()`，Android 行為完全不變。
2. **`%APPDATA%\cc.ugotit\elinkbook` 維持原位**（`webview_data`、`downloaded-fonts`、`dictionaries`）：瀏覽器引擎資料體積大、屬於 App 內部，不適合搬進使用者的「文件」。
3. **不遷移舊資料**：不寫自動遷移、App 內也不偵測或提示舊位置的項目。理由：Windows 版目前只有作者的兩台電腦有資料；而資料庫存絕對路徑，光搬檔案救不回既有的書（路徑仍指向舊位置），要保留閱讀進度、劃線就得另寫一次性的資料庫路徑改寫，工作量與資料遺失風險都遠大於重新匯入。升級後書架為空，需要的書重新匯入，舊位置的項目由使用者手動刪除。
4. **解除安裝選「是」只刪兩個明確屬於本 App 的資料夾**：`<文件>\elinkbook` 與 `%APPDATA%\cc.ugotit\elinkbook`。移除 ADR 0043 原本對「文件」根目錄通用名稱的逐項刪除。

## 替代方案與取捨

- **自動遷移（搬檔案加改資料庫路徑）**：被否決。見決策 3。若日後 Windows 版有外部使用者再議，須先複製、驗證後才改資料庫路徑、失敗則保持原狀。
- **把資料庫改存相對路徑**：被否決。要動所有讀寫路徑的程式，且 Android 不需要。
- **把 `%APPDATA%` 那三項也搬進 `文件\elinkbook`**：被否決。見決策 2。
- **維持固定名稱清單**：被否決。名單必須與 App 實際建立的項目同步，而且永遠有誤刪使用者同名資料夾的風險。

## 後果

- 升級到這個版本的 Windows 使用者（目前只有作者）書架會是空的；舊位置的項目不會被讀取、也不會被刪除，直到使用者手動處理。
- 之後在 Windows 新增任何要放在「文件」的資料，都必須走 `appDocumentsDirectory()`，否則會再次散落在根目錄；不要再新增直接呼叫 `getApplicationDocumentsDirectory()` 的地方。
- 解除安裝的刪除範圍從一長串名稱變成兩個資料夾，不再有清單與程式不同步的問題。
