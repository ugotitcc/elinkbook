# Epic 55 — App 授權頁登錄第三方授權：工單清單 (Issues)

2 個 Issue。Issue 2 依賴 Issue 1 建立的登錄機制。

```
Issue 1（機制＋5 項程式元件）──> Issue 2（5 款字型）
```

---

## Issue 1：登錄機制與 5 項程式元件授權

**Status:** done

**依賴：** 無。

**What to build：**
- 依 `spec.md` 建立 `ThirdPartyLicense`、`kThirdPartyLicenses`、`registerThirdPartyLicenses`。
- 清單先放 5 項程式元件：foliate-js、zip.js、fflate、OpenCC、Readium kotlin-toolkit。
- 授權全文取自各上游 LICENSE 原檔，放進 `app/assets/licenses/`，並在 `pubspec.yaml` 宣告。
- `main.dart` 在 `WidgetsFlutterBinding.ensureInitialized()` 之後呼叫登錄函式。

**測試要求：**
- 登錄後 `LicenseRegistry.licenses` 讀到 5 筆，`packages` 與 `spec.md` 一致。
- 每筆授權全文非空。
- 注入一個讀不到某個 asset 的 bundle，其他 4 筆仍登錄成功。
- 既有的 `about_screen` 測試不受影響。

**驗收標準：** 真機開「關於 → 開源授權」，能找到這 5 項，點進去看得到授權全文；`flutter analyze` 乾淨；上述測試通過。

**Blocked by：** 無。

---

## Issue 2：登錄 5 款可下載字型的授權

**Status:** done

**依賴：** Issue 1。

**What to build：**
- 把 `fonts-cdn/fonts/licenses/` 的 5 份授權檔複製到 `app/assets/licenses/`，檔名見 `spec.md`。
- 在 `kThirdPartyLicenses` 加入 5 款字型。
- 台灣圓體照原檔顯示，不補寫版權行。

**測試要求：**
- `LicenseRegistry.licenses` 讀到 10 筆。
- 5 份字型 asset 與 `fonts-cdn/fonts/licenses/` 內對應檔案內容完全相同。

**驗收標準：** 真機開授權頁，能找到 5 款字型，且不必先下載字型；`flutter analyze` 乾淨；上述測試通過。

**Blocked by：** Issue 1。

---

## Issue 3：新增白鷺楷與獅尾B2加糖宋體兩款可下載字型

**Status:** done（2026-10-09：已上傳 R2、`verify_remote.mjs` 通過、TCL 14 真機驗證通過）

**依賴：** Issue 2。

**What to build：**
- `AppFont` 加 `bailuKai`、`sweiB2Sugar`（接在最後）；`familyName` 為 `BailuKai`、`SweiB2SugarCJKtc`。
- `fonts-cdn/fonts.json` 加 2 筆（發布路徑 `v1/`）；`font_download_catalog.dart` 同步。
- ARB（en／zh／zh_TW）加顯示名稱；授權頁登錄 2 款。
- 授權檔：`fonts-cdn/fonts/licenses/` 與 `app/assets/licenses/` 各 2 份。
- 文件：`CLAUDE.md`、`CONTEXT.md`、`docs/prd.md`、`fonts-cdn/README.md` 的字型清單與數量。

**驗收標準：**
- `flutter analyze` 乾淨；異動檔案相關測試通過；`check_manifest.mjs` 通過。
- 上傳 R2 後 `verify_remote.mjs` 通過。
- TCL 14 真機下載兩款字型並在閱讀器正確顯示（含直排）。

**Blocked by：** 白鷺楷 repo 補 OFL 授權（已完成）。
