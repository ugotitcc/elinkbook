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
