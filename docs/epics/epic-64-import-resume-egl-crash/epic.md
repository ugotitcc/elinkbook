# `epic-64-import-resume-egl-crash` （缺陷）從系統檔案選擇器返回時 EGL context 遺失，Impeller 在 raster 執行緒 abort

**狀態：** 🟡 開發中 (Active)
**存放路徑：** `docs/epics/epic-64-import-resume-egl-crash/`
**關聯 PRD 章節：** 無（穩定性）；來源：`epic-63-dictionary-lookup` Issue 8 真機驗收的附帶觀察

## 背景

2026-10-22 在電子紙（Mobiscribe WAVE，Allwinner，Android 12／SDK 31，4 GB）驗收字典功能時，使用者匯入 Markdown 書籍（`e8_cedict.md`，80 位元組）數次遇到「畫面先黑掉，接著 App 直接退出」。同一晚 23:41、23:55、23:56 各發生一次，三次 logcat 痕跡一致。

## 已知事實（來自 logcat，2026-10-22）

三次都發生在「開啟系統檔案選擇器（`OPEN_DOCUMENT` / DocumentsUI）→ 返回 App」之後約 6～9 秒：

```
W FilePickerUtils: Custom file type 'azw3' is unsupported and will not be filtered.
I ActivityTaskManager: START u0 {act=android.intent.action.OPEN_DOCUMENT ... cmp=com.android.documentsui/.picker.PickActivity} ...
（返回 App 後）
E libEGL  : eglMakeCurrentImpl:1038 error 3002 (EGL_BAD_ACCESS)
E flutter : [ERROR:flutter/impeller/toolkit/egl/egl.cc(56)] EGL Error: Bad Access (12290) ...
E flutter : [ERROR:flutter/shell/gpu/gpu_surface_gl_impeller.cc(76)] Could not make the context current to acquire the frame.
E flutter : [ERROR:flutter/impeller/renderer/backend/gles/pipeline_library_gles.cc(251)] ... Could not build pipeline vertex descriptors.
E flutter : [ERROR:flutter/impeller/renderer/backend/gles/render_pass_gles.cc(264)] ... Could not create a complete framebuffer: Unknown error code: 0
F flutter : [FATAL:flutter/impeller/renderer/backend/gles/render_pass_gles.cc(692)] Check failed: result. Must be able to encode GL commands without error.
F libc    : Fatal signal 6 (SIGABRT), code -6 (SI_TKILL) in tid 13820 (1.raster), pid 13788 (gotit.elinkbook)
```

- 三次的 pid／tid：13788／13820（23:41:43）、15421／16464（23:55:20）、16656／16838（23:56:38）。
- 之後 `ActivityManager: Force finishing activity cc.ugotit.elinkbook/.MainActivity`，行程死亡。
- 同一份 log 中，EGL context 遺失（`EGL_BAD_ACCESS`）在 16:18 也出現過三次（未 abort），所以「context 遺失」在這台裝置會反覆發生，只有部分情況演變成 Impeller 的 FATAL。
- 檔案選擇器在這台機器上極慢：23:55 那次 `Displayed com.android.documentsui/.picker.PickActivity: +1m0s872ms`，23:56 那次 `+34s688ms`；返回後約 6 秒就 abort。
- 與字典功能無關：`feat/epic-63-issue-8` 分支相對 `d7d13e12` 只改了 `app/lib/licenses/third_party_licenses.dart`（+14／−1，靜態字串清單），沒有動任何渲染、匯入或 WebView 程式。
- 崩潰檔案只有 80 位元組，與檔案大小或內容無關（同晚另一次匯入 135 位元組的 `e8_chinese.md` 成功）。
- 執行環境：debug APK、Flutter 3.41.9 stable（Dart 3.11.5）、Impeller GLES backend（專案沒有設定 `io.flutter.embedding.android.EnableImpeller`，使用預設值）。

## 尚未確認

- release 版是否同樣發生（目前只有 debug 版的 log）。
- `main`（未含 Issue 8 文件／授權改動的基準）是否同樣發生——依上列 diff 推論會，但**未實測**。
- 觸發條件是否只限「SAF 檔案選擇器」：其他離開前景再回來的路徑（分享面板、系統設定、電源鍵）尚未測試。
- 關閉 Impeller（manifest `io.flutter.embedding.android.EnableImpeller=false`）是否能避開。
- 是否與這台裝置的 GPU 驅動／E-Ink 刷新機制有關（Allwinner + Impeller GLES）。

## 目標

從系統檔案選擇器返回 App 時，不論 EGL context 是否遺失，App 都不得 abort；最壞情況是重繪失敗一次、下一帧恢復，而不是整個行程結束。

## 處理方式

缺陷修復。先以 `/diagnose` 建立可控重現（開選擇器 → 返回 → 記 red/green），再決定修法（例如：關閉 Impeller 走 Skia、升級／更換 Flutter 引擎、或在原生端處理 surface 重建）。是否要寫 `plan-issue-N.md` 由人類在診斷後決定；保留程式審查（報告存 `reviews/`，不進版控）。

## 診斷結果（2026-10-23，WAVE，Flutter 3.47.4，Impeller GLES）

**症狀範圍比原本以為的大：** 不只檔案選擇器。**任何「離開 App 再回來」都會中**（選擇器、Home、切換 App），前提是**同一個行程之前開過閱讀器（`InAppWebView` 平台檢視）**。行程活著但畫面永久全黑／全白，或 Impeller `FATAL` → SIGABRT。

**證據：**
- 使用者手動重現三次：選擇器關閉後 1 毫秒內 raster 執行緒 `EGL_BAD_ACCESS`（no current context）。
- 自動化重現腳本 `repro/wave_egl_seq.ps1`（步驟 R=開關閱讀器、P=選擇器、H=Home、F=補畫面）。修法前：`HRH` 紅燈 2/2、`PRP` 紅燈 1/1、`RPRP` 紅燈 2/2；`RP`、`RRRRP`、`PPPPPP`（沒開過閱讀器）、`HRFH` 全綠。
- 這台 GPU 是 PowerVR Rogue GE8300；引擎原始碼 `android_surface_gl_impeller.cc` 的 `ShouldClearContextBetweenFrames()` 註解描述同一類驅動競爭條件（PowerVR Rogue GE8320，Activity 切換＋平台檢視期間的 `eglMakeCurrent`），但只對 Android ≤ 10 的 MT6762／MT6765 開啟，不涵蓋 WAVE（Android 12，`sun50iw10p1`）。

**根因（推論，由 A/B 支持，未用引擎偵錯器直接證實）：** 有平台檢視時 Flutter 把 raster 執行緒併進主執行緒，要送出若干個畫面才拆開。電子紙閒置時幾乎不出畫面，閱讀器關閉後併合狀態一直留著；此時畫面表面重建（`RecreateOnscreenSurfaceAndMakeOnscreenContextCurrent`）在主執行緒把 EGL context 設成 current，之後 raster 執行緒 `eglMakeCurrent` 得到 `EGL_BAD_ACCESS`。A/B：`HRH` 紅燈 2/2，同序列在關閉閱讀器後人為補約 16 個畫面（`HRFH`）綠燈 2/2。

**修法：** `lib/reader/platform_view_frame_flush.dart` 的 `flushFramesAfterPlatformViewRemoved()`：`FoliateReaderView` 與 `MdxEntryView` 的 `dispose()` 後補送 12 個畫面，補完停止。修法後同一台 WAVE：`HRH` 綠 2/2、`PRP` 綠 1/1、反覆「開閱讀器＋選擇器」8 輪綠 1/1。

**已排除的方向：**
- 關閉 Impeller：這版 Android 引擎已移除 Skia（`SLIMPELLER`），`enable-impeller=false` 旗標被忽略。
- `RenderMode.texture`：選擇器返回 3 次正常，但「Recents 滑掉再開」與先開過閱讀器的行程重開仍出現 `EGL_BAD_ACCESS` 白畫面；且冷啟動期間畫面全白。已還原。
- `--enable-hcpp-and-surface-control`：log 顯示仍是 `legacy platform view rendering strategy`，旗標無效，不算有效 A/B。
- `ImpellerBackend=vulkan`：引擎只在 debug／profile 接受，release 不可用。

**限制：**
- 只在 debug 版、`adb` 自動化操作下驗證；**尚未由使用者在 WAVE 手動重複原本會黑的操作確認**。
- 字典面板的 `MdxEntryView` 補畫面同一個機制，但沒有單獨用 loop 驗證。
- 沒有量測 release 版；補畫面是否造成電子紙多餘刷新（閃爍）要用眼睛看。
- 這是繞過引擎／驅動問題的 App 層緩解，不是根治。根治需要引擎把這類 GPU（Allwinner／PowerVR Rogue）加進 `ShouldClearContextBetweenFrames()`，或改用自編引擎；可考慮向 Flutter 回報。

## 開發記錄

**2026-10-23** 診斷、重現腳本、修法與驗證，見上方「診斷結果」。待使用者手動驗證。

**2026-10-23** 登錄 Epic。來源：`epic-63-dictionary-lookup` Issue 8 Task 5 真機驗收（2026-10-22 23:41～23:56 三次）。尚未診斷，尚未寫任何程式。issue 見 `issues.md`。
