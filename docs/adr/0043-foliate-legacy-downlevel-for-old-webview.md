# ADR 0043：舊版 WebView（Chrome 83）改載入降級後的 foliate-js 副本

## 狀態

已採納（2026-11-13）。對應分支 `fix/webview-83-legacy-foliate`。

## 背景

iReader Ocean 4 Plus（SmartOS 4，Android 11）的系統 WebView 固定是 Chrome 83.0.4103.120，使用者無法升級。症狀有三個：

1. 開書逾時，Console Log 只有 `開書逾時 沒有任何階段記錄`。
2. 匯入 EPUB 沒有封面，Log 顯示 `extractMetadata … TimeoutException after 0:00:30`。
3. 匯入像是延遲一本：選第二本時，第一本才出現在書架。

三者同一個根因。釘定的 `readest/foliate-js` 使用私有方法（`#foo()`），Chrome 84 才支援，Chrome 83 解析時直接拋 `SyntaxError`，整份 JS 載入失敗。EPUB 匯入的書名／封面／版面偵測，用的是 headless WebView 載入同一份 foliate-js 的探針（`android_epub_metadata.dart`）。探針載入失敗就乾等 30 秒逾時，且探針以 `runSerialized` 排隊執行，才有「延遲一本」的現象。開書前的版面偵測（`detectAndCacheEpubLayout`）也走這個探針，所以閱讀器根本沒機會建立。

`esCompatPolyfillJs` 只能補執行期 API，補不了語法錯誤。

## 決策

1. **不修改釘定的 vendor 檔案**，另外產生降級副本到 `app/android/app/src/main/assets/foliate/legacy/`。
2. **降級工具放在 `app/tool/foliate_legacy/`**：pnpm + esbuild，目標 `chrome83`。遇到無法降級的語法（例如頂層 `await`）會直接報錯。降級結果一併進版控，App 建置不需要 Node。
3. **執行期分流**：`foliate/index.html` 與探針頁（`androidProbeHtml`）看 `navigator.userAgent` 的 Chrome 主版號，低於 84 才載入 `legacy/`，其他裝置載入原始檔案，行為不變。探針頁同時去掉 Chrome 89 才支援的頂層 `await`，改為 async 函式與動態 `import()`。
4. **補執行期缺口**：`esCompatPolyfillJs` 補 `ParentNode.replaceChildren`（Chrome 86，`paginator.js` 渲染頁首頁尾使用）。降級時把 CSS `:is(#header, #footer)`（Chrome 88）改寫成等價選擇器。
5. **守衛**：`test/reader/foliate_legacy_assets_test.dart` 擋「忘了重新產生降級副本」與「載入分流被改掉」。`check_foliate_es_compat.js` 納入 `replaceChildren`，並略過 `legacy/`。

## 後果

- **升級釘定版本或修改 `foliate/*.js` 後，必須重跑降級**：`cd app/tool/foliate_legacy && pnpm install && pnpm build`，並一併 commit。細節見 `app/tool/README.md`。
- APK 多約 0.9 MB 的靜態資產。
- 已知限制：`paginator.js` 的 `@container` 與 CSS 巢狀寫法 Chrome 83 不支援，規則會被略過。目前真機實測直排與更換字型正常；若之後發現欄數異常，需另外處理。
- 降級只處理語法與已知的 API。若 foliate-js 之後引進其他 Chrome 83 沒有的 API，要補在 `esCompatPolyfillJs`。
- Log 內每次開書都有 `載入錯誤 HOST_LOOKUP net::ERR_NAME_NOT_RESOLVED`，已查明是 `appassets.androidplatform.net/favicon.ico`（子資源，非主頁面）沒被攔截而去解析網域，無害，維持現狀。

## 這台機器怎麼驗證（重要）

- **adb 不能用。** Ocean 4 Plus 的 USB 只被電腦認成 MTP；SmartOS 4 沒有開發者選項（連點版本號碼無反應），`adb devices` 是空的。
- **WebView 不能升級。** 手動安裝 Google 的 Android System WebView 91 APK 可以裝上，但系統仍使用 83（廠商鎖死）。
- 驗證流程：建置 `arm64-v8a` release APK，用 USB 檔案傳輸複製到機器，手動安裝；每次換檔名，避免裝到舊檔。再從「設定 → 閱讀器 Console Log」拍照回報。
- 診斷訣竅：在 `ReaderConsoleLog` 加帶標記的暫時 Log（診斷完用 `grep` 清掉）。`OpenBookTrace` 的階段記錄與逾時摘要可直接判斷卡在哪一關。
- 已在 Ocean 4 Plus（Chrome 83.0.4103.120）實測：開書成功、匯入有封面、下載字型／更換字型／直排正常。

## 替代方案與取捨

- **要求使用者升級 WebView**：行不通。這台廠商鎖死，裝了也不生效。
- **宣告不支援 WebView 83 以下**：工作量最小，但這台 Ocean 4 Plus 就用不了，與「支援 E-Ink 閱讀器」的產品方向衝突。
- **直接修改釘定的 vendor 檔案**：每次升級釘定版本都要重做，且違反 [ADR 0011](0011-epub-reflowable-migrate-to-foliate-js.md) 的「不修改釘定版本」原則。
