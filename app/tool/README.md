# `app/tool/`

開發輔助腳本，不屬於 App 本身，不會被打包進 APK。

## `check_foliate_es_compat.js`

靜態掃描 `app/android/app/src/main/assets/foliate/`（`readest/foliate-js`
釘定版本，見 ADR 0011）是否使用了較新的 ES 內建方法（`Object.groupBy`／
`Array.prototype.at`／`Array.prototype.findLastIndex` 等），而
`app/lib/reader/foliate_epub_reader_view.dart` 的 `_esCompatPolyfillJs`
還沒有對應的 polyfill。

**背景**：這份釘定的 vendor 程式碼在兩次真機 `/diagnose` 中都發現無條件呼叫
了較新的 ES 內建方法，較舊的 Android System WebView（例如 Chromium 91 的
Mobiscribe WAVE）不支援，導致開書失敗或整個卡在載入指示器（且部分裝置的
WebView 建置沒開遠端除錯，完全看不到例外訊息，非常難排查）。這支腳本讓
「升級釘定版本時上游引進了新的、目前完全沒設防的 ES 內建方法」這件事可以
提早在開發階段被發現，不必每次都等真機回報才後知後覺。

### 何時該執行

- **每次升級 `foliate/` 目錄下的釘定版本（bump commit）之後**，一定要跑一次。
- 平常開發不需要跑（純 Dart/Flutter 改動不會觸發這裡的邏輯）。
- 目前**沒有接進 CI**（這個 repo 尚未設定任何 CI pipeline）——純粹是一支
  可手動執行的獨立腳本，之後若要接進 CI，直接把下面的執行指令包進
  workflow 步驟即可。

### 執行方式

不需要 `npm install`，只用 Node.js 內建模組（`fs`／`path`）：

```bash
node app/tool/check_foliate_es_compat.js
```

- 結束碼 `0`：乾淨，目前找到的每個較新 API 用法都已有對應 polyfill 防護。
- 結束碼 `1`：找到至少一個尚未防護的用法，會印出檔案/行號與建議修法。

### 找到問題時怎麼修

1. 到 `app/lib/reader/foliate_epub_reader_view.dart` 的 `_esCompatPolyfillJs`
   補上對應的 polyfill（僅在缺席時才定義，比照既有寫法，不覆蓋原生實作）。
2. 用 Node.js + `@xmldom/xmldom`（或視情況調整）對照未經修改的實際
   `epub.js`/`epubcfi.js`/`paginator.js` 驗證：缺席時真的會拋出例外、補上
   polyfill 後可修復（比照 epic-19 兩輪 `/diagnose` 紀錄的既有作法）。
3. 重新執行這支腳本確認乾淨。
4. 補上/更新 `app/test/reader/foliate_epub_reader_view_test.dart` 裡驗證
   `initialUserScripts` 內容的既有測試，涵蓋新補上的 polyfill 名稱。

### 已知限制

純文字 regex 掃描，不是真的解析/執行 JavaScript，會有誤判空間（例如某個
變數剛好呼叫了 `.at(...)` 但其實跟 `Array.prototype.at`／
`String.prototype.at` 無關）。設計上寧可偶爾多提醒一次、也不要漏掉真正的
風險，故不追求零誤判；`RISKY_APIS` 清單本身也需要在發現新的較新 ES 內建
方法時手動擴充維護。

## `test_section_progress_density.js`

驗證 `progress.js` 的 `SectionProgress`（epic-26-architecture-hardening
Issue 11：已渲染 section 密度校正流式頁碼估算）純邏輯正確性——已知密度
換算、未知 section 最近鄰外插與 tie-break、清空快取退回統一常數、非線性
section 忽略共 5 項情境。`progress.js` 零 DOM 依賴，腳本用 Node.js 內建
`node:assert/strict` 直接執行，不需要任何測試框架。

### 何時該執行

- 每次修改 `progress.js` 的 `SectionProgress` 之後。
- 升級 `foliate/` 目錄下的釘定版本（bump commit）之後，若上游改動了
  `progress.js` 的既有邏輯，用這支腳本確認密度校正邏輯與新版上游程式碼
  仍相容。

### 執行方式

```bash
node app/tool/test_section_progress_density.mjs
```

- 結束碼 `0`：5 項情境全數通過。
- 非 `0`：斷言失敗或拋出例外，會印出對應的錯誤訊息與堆疊。
