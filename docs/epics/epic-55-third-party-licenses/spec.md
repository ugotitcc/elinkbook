# Epic 55 — App 授權頁登錄第三方授權：規格

## 檔案

| 路徑 | 用途 |
|---|---|
| `app/assets/licenses/*.txt` | 10 份授權全文，取自上游原檔 |
| `app/lib/licenses/third_party_licenses.dart` | 登錄函式與授權清單 |
| `app/lib/main.dart` | 在 `WidgetsFlutterBinding.ensureInitialized()` 之後呼叫登錄函式 |
| `app/pubspec.yaml` | 宣告 `assets/licenses/` |
| `app/test/licenses/third_party_licenses_test.dart` | 測試 |

## 介面

```dart
/// 一筆第三方授權：顯示名稱（授權頁的套件標題）與授權全文的 asset 路徑。
class ThirdPartyLicense {
  const ThirdPartyLicense({required this.packageName, required this.assetPath});
  final String packageName;
  final String assetPath;
}

/// 要登錄的授權清單。
const List<ThirdPartyLicense> kThirdPartyLicenses = [ ... ];

/// 把 [kThirdPartyLicenses] 登錄到 Flutter 的 [LicenseRegistry]。
/// 授權頁（showLicensePage）會自動列出。
void registerThirdPartyLicenses({AssetBundle? bundle});
```

- `registerThirdPartyLicenses` 呼叫一次 `LicenseRegistry.addLicense`。每筆授權讀一次 asset，產生一個 `LicenseEntryWithLineBreaks([packageName], text)`。
- `bundle` 預設 `rootBundle`，測試時可注入。
- asset 讀不到時，略過該筆並繼續，不讓整個授權頁失敗。

## 授權清單（10 項）

| packageName | 授權 | asset |
|---|---|---|
| foliate-js | MIT | `assets/licenses/foliate-js.txt` |
| zip.js | BSD-3-Clause | `assets/licenses/zip-js.txt` |
| fflate | MIT | `assets/licenses/fflate.txt` |
| OpenCC | Apache-2.0 | `assets/licenses/opencc.txt` |
| Readium kotlin-toolkit | BSD-3-Clause | `assets/licenses/readium-kotlin-toolkit.txt` |
| 思源黑體 | SIL OFL 1.1 | `assets/licenses/font-source-han-sans.txt` |
| 思源宋體 | SIL OFL 1.1 | `assets/licenses/font-source-han-serif.txt` |
| 原俠正楷 | SIL OFL 1.1 | `assets/licenses/font-guan-kiap-tsing-khai.txt` |
| 台灣圓體 | SIL OFL 1.1 | `assets/licenses/font-taiwan-pearl.txt` |
| 源流明體 | SIL OFL 1.1 | `assets/licenses/font-gen-ryu-min.txt` |

字型的 5 份由 `fonts-cdn/fonts/licenses/` 複製；其中台灣圓體在授權全文之後附加一段 README 來源說明，其餘 4 份逐位元組相同。其餘 5 份取自上游 LICENSE。

## 測試

- 登錄後，`LicenseRegistry.licenses` 能讀到 10 筆，每筆的 `packages` 與上表一致。
- 每筆授權全文非空。
- 4 份字型 asset 與 `fonts-cdn/fonts/licenses/` 內對應檔案內容完全相同；台灣圓體 asset 以原檔全文開頭並附來源說明。
- 某個 asset 讀不到時，其他 9 筆仍然登錄成功。
