# 交接：PDF 逐頁換頁後畫面「再閃一下」（WAVE ELINK）

> 本文件給「接得上實機的那台電腦」上的 Claude Code／工程師接手。上一段工作在沒有裝置的機器完成，
> **還沒改任何產品程式**，只做了診斷。請從「接下來要做的事」開始。
> 分支：`fix/pdf-page-turn-flicker`（從 `main` a9d52159 切出，之後修法也放這條分支與 PR，不另開文件分支）。

## 1. 症狀（使用者原話與確認）

- 「PDF 換頁閱讀時畫面顯示完成後，都會再閃一下」——**每次**換頁都會。
- 裝置：**WAVE ELINK（E-Ink）**。
- 翻頁模式：**逐頁**（`PdfPageTurnMode.paginated`，epic-56）。
- **沒有**開加粗（`pdfBoldStrength = 0`）。
- 閱讀時**工具列（上下黑色列）是收起來的**。
- 尚未確認：單頁或雙頁、有沒有開裁切／對比、是否 E-Ink 模式（`isEinkMode`）、翻回已看過的頁是否也閃。

## 2. 已排除

| 假設 | 結果 | 依據 |
|---|---|---|
| 加粗／裁切的覆蓋圖非同步才就緒 | **不是這次的原因** | 使用者沒開加粗。測試環境雖能重現（加粗 0.5 時換頁後 80～530ms 又變一次，翻回已算過的頁只變一次），但那是另一個情境 |
| 工具列進度滑桿圓點動畫 | **不是這次的原因** | 測試環境量到：工具列顯示時，換頁後 `ReaderFooter` 的 `Slider` 圓點約 250ms 內滑 6 格。但使用者的工具列是收起的，滑桿不在畫面上 |
| 邊角常駐頁尾／頁首文字 | **PDF 不適用** | `reader_screen.dart` 約 2646 行：邊角頁尾文字只在 `format.usesFoliate` 時顯示，PDF 沒有 |

所以：**工具列收起時，除了 PDF 頁面本身，`ReaderScreen` 沒有其他東西會更新。** 嫌疑回到頁面繪製流程與裝置顯示。

## 3. 假設（由高到低），每個都附可驗證的預測

**H1：`pdfrx` 先畫低解析度預覽、再換成高解析度影像**（最優先）
- 依據：`PdfViewerParams.onePassRenderingSizeThreshold` 預設 2000（頁面像素寬或高超過就分多次渲染）；WAVE 為高解析度 E-Ink，頁面像素很可能超過 2000。另有 `pageImageCachingDelay`（20ms）、`partialImageLoadingDelay`（0ms）。專案目前只設了 `onePassRenderingScaleThreshold: 200/72`（`lib/reader/pdf_fit_size_delegate.dart:89`），沒動 `onePassRenderingSizeThreshold`。
- 預測：日誌會看到同一頁被 paint 兩次，第二次在換頁後數十～數百 ms；**翻回已看過（已快取）的頁不閃**；把 `onePassRenderingSizeThreshold` 調大到超過裝置頁面像素後，閃動消失。

**H2：`onPageChanged` → `ReaderScreen.setState` → 重建 `PdfReaderView`，導致 `pdfrx` 重新排版／重繪頁面**
- 依據：每次 `build()` 都新建 `PdfViewerParams` 與 closure（`onViewerReady`、`onViewSizeChanged` 等，`pdf_reader_view.dart` 約 1716～1800 行）。
- 預測：每次換頁 `PdfReaderView.build()`／`didUpdateWidget` 被呼叫不只一次，或 `pdfrx` 在 `didUpdateWidget` 判定需要重新載入；頁面 paint 次數 ≥ 2 且第二次緊接在 `onPageChanged` 之後。

**H3：E-Ink 裝置／系統層的整頁刷新（與程式無關）**
- 依據：epic-56 spec 明確排除「E-Ink 整頁黑白閃爍清屏（裝置相關，另立工單）」。
- 預測：App 日誌顯示只 paint 一次、沒有任何額外重繪，閃動仍在；關閉 App 的 E-Ink 模式後仍閃；其他 App（如系統內建閱讀器）換頁也有同樣的閃。

**H4：其他**（`onReadingActivity`、書籤星號狀態等造成的重建）——預測：日誌會顯示換頁後 `ReaderScreen.build` 多次但頁面 paint 只有一次。

## 4. 接下來要做的事

### 步驟 A：不改程式的對照實驗（5 分鐘，先做）

在 WAVE 上逐項試，記錄「閃／不閃」：

1. **翻到全新的頁**（沒看過）vs **翻回剛看過的頁**：後者不閃 → 強烈指向 H1。
2. 用**進度跳頁**（輸入頁碼）換頁 vs 點熱區換頁：兩者都閃 → 與換頁方式無關。
3. 關閉 App 的 **E-Ink 模式**後再換頁：還是閃 → 更像 H3 或 H1。
4. 換頁後**什麼都不碰**，用手機慢動作錄影，看閃動是「換頁後立刻」還是「過一會兒」，記下大概幾毫秒。
5. 把頁面縮放換成其他 Fit 模式（頁寬／真實比例）再試。

### 步驟 B：加暫時 debug 日誌，在 WAVE 上量

全部以 `[DEBUG-pdfflash]` 開頭，之後一個 `grep` 就能清乾淨（診斷流程要求）。用 `Stopwatch` 取相對毫秒。

1. `lib/reader/pdf_reader_view.dart` `_handlePageChanged`（約 1328 行）：印頁碼。
2. 同檔 `build()` 與 `didUpdateWidget`：印呼叫次數。
3. 同檔 `PdfViewerParams`（約 1720 行）加 `pagePaintCallbacks: [(canvas, pageRect, page) { ... 印 page.pageNumber 與 pageRect.size ... }]`。簽章已確認：`void Function(ui.Canvas canvas, Rect pageRect, PdfPage page)`。**每次 `pdfrx` 繪製頁面都會呼叫**，所以同一頁換頁後被呼叫幾次、間隔多久，就是答案。
4. `lib/screens/reader_screen.dart` PDF 的 `onPageChanged`／`_handlePageRendered`（約 1466 行）：印呼叫與 `setState`。
5. 同時印裝置的頁面像素：`pageRect.size * devicePixelRatio`，用來驗證 H1 的 2000 門檻。

收日誌：`adb logcat -s flutter` 過濾 `DEBUG-pdfflash`，或 `flutter logs`。換頁 3～5 次（含翻回已看過的頁），把日誌貼回對話。

### 步驟 C：修法與回歸測試（確認根因後）

- H1 成立：調整 `onePassRenderingSizeThreshold`（透過 `PdfViewerParams`），或讓逐頁模式在換頁完成前就備妥高解析度影像。**注意取捨**：門檻調大會增加記憶體與渲染時間，要在 WAVE 上量。
- H2 成立：讓 `PdfViewerParams` 的 closure 穩定（提到 State 欄位），避免每次 `build` 都產生新物件觸發重繪。
- H3 成立：這不是程式問題，記錄到 epic-56 後續項目（已排除的範圍），不要硬修。
- 回歸測試：用 `probes/` 底下的探針改寫——「換頁後畫面（逐幀雜湊）只能變 1 次」。**測試環境只能驗證 Flutter 層的重繪次數，驗證不了 E-Ink 的實際顯示**，修好仍要回 WAVE 肉眼確認。

## 5. 手上的重現工具（測試環境，不需要裝置）

`probes/` 內兩支探針（副檔名為 `.dart.txt`，避免被 `flutter test` 與 `flutter analyze` 掃到；要用時複製到 `app/test/` 並改成 `.dart`）：

- `probe_pdf_view_frames.dart.txt`：單獨的 `PdfReaderView`，逐幀擷取畫面縮圖雜湊，比較各組態（預設／加粗／裁切／捲動／雙頁）換頁後畫面變化次數。已知結果：逐頁預設只變 1 次；加粗 0.5 變 2 次。
- `probe_reader_screen_frames.dart.txt`：完整 `ReaderScreen`（含工具列、E-Ink），把畫面分成上／中／下三段雜湊。已知結果：工具列顯示時，下方滑桿圓點約 250ms 內變 6 次。

**已知限制**：這兩支探針在無頭測試環境跑，只看得到 Flutter 畫了幾次，**看不到 E-Ink 面板的實際刷新**。另外我沒能在測試裡把工具列收起來（點中央沒有觸發，原因未查），所以「工具列收起」的狀態沒量到。

## 6. 在接得上裝置的電腦上跑之前（環境坑）

出自專案記憶 `reference_android-integration-test-env`，2026-11-10 實測：

- **螢幕必須亮著**：熄屏時 WebView 不繪製。跑之前 `adb shell input keyevent KEYCODE_WAKEUP`，並 `adb shell svc power stayon usb`，結束後 `adb shell settings put global stay_on_while_plugged_in 0` 還原。
- **JDK**：`app/android/gradle.properties:5` 寫死 `C:\Program Files\Microsoft\jdk-17.0.21.21-hotspot`（舊電腦路徑），新電腦要裝同版本 JDK 17，Android Studio 內建的 JDK 25 不能用。
- **adb 不一定在 PATH**：Windows 預設在 `C:\Users\<使用者>\AppData\Local\Android\Sdk\platform-tools\adb.exe`；Git Bash 要加 `MSYS_NO_PATHCONV=1`。
- **絕不用 `flutter install`**（會解除安裝並清資料）。建置後用 `adb install -r`：
  `flutter build apk --debug --target-platform android-arm`（WAVE 是 arm 32 位元才需要這個旗標，請先確認裝置 ABI：`adb shell getprop ro.product.cpu.abi`）。
- debug 版（JIT）的效能與 release 不同，**閃動的時序可能不一樣**；若 debug 版量不到，改用 `--release` 或 `--profile` 再量。
- Gradle／Kotlin daemon 約吃 2.7 GB，記憶體不足時背景指令會被中止。

## 7. 其他需要知道的專案規則

- 回覆與文件一律正體中文。
- 提交前：`flutter analyze` 必須乾淨；有動畫面字串跑 `node tool/check_l10n_hardcoded_strings.js`。
- 測試只跑這次異動觸及的檔案，不重跑整套（整套約 5 分鐘）。
- commit 不加 Co-Authored-By。
- 清掉所有 `[DEBUG-pdfflash]` 再提交：`grep -rn "DEBUG-pdfflash" app/lib` 應為空。
- 診斷在 Gitea（`git.jigong.org/huthief/elinkBook`），PR 用 Gitea API，不是 `gh`。
- 另一個還沒回答的小問題：`fix/foliate-resume-exact-page` 遠端分支已合併、尚未刪除。
