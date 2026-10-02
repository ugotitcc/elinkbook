# Issue 1：登錄機制與 5 項程式元件授權 實作計畫

> **給執行者：** 必要子技能：使用 `superpowers:subagent-driven-development`（建議）或 `superpowers:executing-plans` 逐 Task 執行本計畫。步驟使用 checkbox（`- [ ]`）語法追蹤進度；每完成一個 Step 就把它改為 `- [x]`。

**Goal：** 建立 `registerThirdPartyLicenses` 登錄機制，讓「關於 → 開源授權」頁能列出 foliate-js、zip.js、fflate、OpenCC、Readium kotlin-toolkit 這 5 項非 Dart 套件元件的授權全文。

**Architecture：** 新增 `app/lib/licenses/third_party_licenses.dart`，內含不可變資料類別 `ThirdPartyLicense`、常數清單 `kThirdPartyLicenses`、登錄函式 `registerThirdPartyLicenses`（對 Flutter 的 `LicenseRegistry.addLicense` 呼叫一次，逐筆讀 asset、產生 `LicenseEntryWithLineBreaks`）。授權全文以 asset 形式放在 `app/assets/licenses/`，`main.dart` 於 `WidgetsFlutterBinding.ensureInitialized()` 之後呼叫登錄。既有 `showLicensePage` 不需任何修改，自動列出。

**Tech Stack：** Flutter／Dart、`flutter_test`。指令一律在 `app/` 目錄下執行（下載授權檔的步驟除外，見 Task 1）。

**Spec：** `docs/epics/epic-55-third-party-licenses/spec.md`（介面與清單）、`design.md`（決策 Q1～Q6）、`issues.md` Issue 1。

## Global Constraints

- **語言**：文件、註解、測試名稱一律正體中文（zh-TW），禁止簡體中文；程式碼命名維持英文慣例。
- **授權文字來源**：一律取自各上游 LICENSE 原檔，**逐字不改寫**（design Q3）。
- **不動的東西**：`about_screen.dart`（沿用 `showLicensePage`，不新增畫面，Q2）、`fonts-cdn/` 內任何檔案、Flutter／Dart 套件授權（Flutter 自動收集）。
- **本 Issue 只登錄 5 項程式元件**；5 款字型是 Issue 2，本 Issue 不放字型 asset、清單不含字型。
- **公開 API 固定**（spec.md）：`ThirdPartyLicense({required packageName, required assetPath})`、`const List<ThirdPartyLicense> kThirdPartyLicenses`、`void registerThirdPartyLicenses({AssetBundle? bundle})`；`bundle` 預設 `rootBundle`。
- **asset 讀不到時略過該筆並繼續**，不讓整個授權頁失敗。
- **Windows 環境**：多數原始檔是 CRLF，用 Edit 工具編輯；`python` 在此環境不會實際執行，不可用來改檔案。指令為 bash 語法，用 Bash 工具（Git Bash）執行。
- **測試範圍**（CLAUDE.md）：單一 Task 只跑異動實際觸及的測試檔；完整 `flutter test`（無參數）只在最後一個 Task 跑一次（約 5～6 分鐘，用 `run_in_background`）。
- **提交前**：`flutter analyze` 必須是 "No issues found!"，並跑 `node tool/check_l10n_hardcoded_strings.js`。
- **Commit 結尾**必須帶 `Co-Authored-By: Claude Sonnet 5.5 <noreply@anthropic.com>`。
- **流程**：直接 TDD；程式審查先出報告（存於 `reviews/`，該目錄 gitignore、不進版控），審查者不直接改程式；審查摘要放進 `epic.md`。建議分支名 `epic-55/issue-1-license-registry`。

## Review Focus

以下是 spec 隱含、但規格測試要求沒明列、最可能咬到使用者的情況（依可能性排序）：

1. **asset 在 `pubspec.yaml` 沒宣告或檔名拼錯**：授權頁會靜默少一項（因為讀不到就略過），使用者與測試都不易發現。→ Task 2 以真實 `rootBundle` 讀取每一筆清單項目，斷言 5 筆全在、全文含上游版權關鍵字。
2. **某個 asset 讀取丟出的不是 `FlutterError` 而是任意例外**（例如 `StateError`）：不能讓整個授權頁崩潰。→ Task 2 測試注入丟 `StateError` 的 bundle。
3. **asset 檔存在但內容是空白**（下載失敗留下空檔）：不應登錄一筆沒有內容的授權、讓使用者點進去看到空白。→ Task 2 測試：空白 asset 被略過。
4. **清單內 `packageName` 或 `assetPath` 重複**：重複會讓授權頁出現兩筆同名項目、或同一檔案被讀兩次。→ Task 2 純資料測試。
5. **授權全文含非 ASCII 字元或 CRLF**（Apache-2.0 全文、上游檔案換行不一）：不應亂碼或崩潰。→ Task 2 以真實 asset 讀取，OpenCC 全文需讀得出 "Apache License"。

## 檔案結構

| 動作 | 路徑 | 責任 |
|---|---|---|
| 新增 | `app/assets/licenses/foliate-js.txt` | foliate-js（MIT）授權全文 |
| 新增 | `app/assets/licenses/zip-js.txt` | zip.js（BSD-3-Clause）授權全文 |
| 新增 | `app/assets/licenses/fflate.txt` | fflate（MIT）授權全文 |
| 新增 | `app/assets/licenses/opencc.txt` | OpenCC（Apache-2.0）授權全文 |
| 新增 | `app/assets/licenses/readium-kotlin-toolkit.txt` | Readium kotlin-toolkit（BSD-3-Clause）授權全文 |
| 修改 | `app/pubspec.yaml` | 宣告 `assets/licenses/` |
| 新增 | `app/lib/licenses/third_party_licenses.dart` | 資料類別、清單、登錄函式 |
| 新增 | `app/test/licenses/third_party_licenses_test.dart` | 測試 |
| 修改 | `app/lib/main.dart` | 啟動時呼叫登錄 |
| 修改 | `docs/epics/epic-55-third-party-licenses/issues.md`、`docs/epics.md` | 進度 |

---

### Task 1：取得 5 份上游授權原檔並宣告 asset

**Files：**
- Create：`app/assets/licenses/foliate-js.txt`、`zip-js.txt`、`fflate.txt`、`opencc.txt`、`readium-kotlin-toolkit.txt`
- Modify：`app/pubspec.yaml`（`assets:` 區段，約第 200～225 行）

**Interfaces：**
- Produces：5 個 asset 路徑（Task 2 的清單引用）：`assets/licenses/foliate-js.txt`、`assets/licenses/zip-js.txt`、`assets/licenses/fflate.txt`、`assets/licenses/opencc.txt`、`assets/licenses/readium-kotlin-toolkit.txt`。

- [ ] **Step 1：建立分支並從上游下載授權原檔**

專案內的 foliate 是 `readest/foliate-js` 的釘定版本，授權取自該 fork 的 LICENSE（與 `johnfactotum/foliate-js` 同為 MIT／John Factotum）。

```bash
cd /c/Users/fycdc/AI/elinkBook
git checkout -b epic-55/issue-1-license-registry
mkdir -p app/assets/licenses
cd app/assets/licenses
curl -fsSL -o foliate-js.txt https://raw.githubusercontent.com/readest/foliate-js/main/LICENSE
curl -fsSL -o zip-js.txt https://raw.githubusercontent.com/gildas-lormeau/zip.js/master/LICENSE
curl -fsSL -o fflate.txt https://raw.githubusercontent.com/101arrowz/fflate/master/LICENSE
curl -fsSL -o opencc.txt https://raw.githubusercontent.com/BYVoid/OpenCC/master/LICENSE
curl -fsSL -o readium-kotlin-toolkit.txt https://raw.githubusercontent.com/readium/kotlin-toolkit/develop/LICENSE
```

`-f` 讓 HTTP 錯誤時直接失敗，避免把 404 頁面當授權存進去。若網路不通，改手動從各專案 GitHub 頁面複製原檔，**不得**憑記憶重打。

- [ ] **Step 2：核對內容與 design.md 記載的版權行一致**

```bash
cd /c/Users/fycdc/AI/elinkBook/app/assets/licenses
head -3 foliate-js.txt zip-js.txt fflate.txt readium-kotlin-toolkit.txt
head -2 opencc.txt
# 本機簽出在 Windows 是 CRLF、GitHub 下載是 LF，比對時須忽略行尾 CR
diff --strip-trailing-cr opencc.txt ../../tool/opencc_data/LICENSE && echo "OpenCC 與專案內既有副本相同"
wc -c *.txt
```

預期：
- `foliate-js.txt` 含 `Copyright (c) 2022 John Factotum`、`MIT License`
- `zip-js.txt` 含 `Copyright (c) 2023, Gildas Lormeau`、`BSD 3-Clause License`
- `fflate.txt` 含 `Copyright (c) 2026 Arjun Barrett`
- `readium-kotlin-toolkit.txt` 含 `Copyright (c) 2017, Readium`
- `opencc.txt` 開頭 `Apache License`；忽略行尾 CR 後與 `app/tool/opencc_data/LICENSE` 相同（若仍有實質差異，以上游現行版為準並在 commit 訊息註明，不要手改）
- 5 個檔案大小皆 > 0

任何一項不符就停下來，回報給人類，不要自行補寫。

- [ ] **Step 3：在 `pubspec.yaml` 宣告資源目錄**

在 `assets:` 清單中 `- assets/wifi_transfer/index.html` 那一行之後加入：

```yaml
    - assets/licenses/
```

目錄寫法會包含其下所有檔案（Issue 2 加字型授權時不用再改 pubspec）。

- [ ] **Step 4：確認 pubspec 可解析**

Run（在 `app/`）：`flutter pub get`
Expected：無錯誤、無「asset not found」警告。

- [ ] **Step 5：Commit**

```bash
cd /c/Users/fycdc/AI/elinkBook
git add app/assets/licenses app/pubspec.yaml
git commit -m "feat(licenses): 加入 5 項程式元件的上游授權原檔（epic-55 Issue 1）

Co-Authored-By: Claude Sonnet 5.5 <noreply@anthropic.com>"
```

---

### Task 2：`ThirdPartyLicense`、清單與 `registerThirdPartyLicenses`（TDD）

**Files：**
- Create：`app/lib/licenses/third_party_licenses.dart`
- Test：`app/test/licenses/third_party_licenses_test.dart`

**Interfaces：**
- Consumes：Task 1 的 5 個 asset 路徑。
- Produces：
  - `class ThirdPartyLicense { const ThirdPartyLicense({required String packageName, required String assetPath}); final String packageName; final String assetPath; }`
  - `const List<ThirdPartyLicense> kThirdPartyLicenses`
  - `void registerThirdPartyLicenses({AssetBundle? bundle})`
  - （Issue 2 與 Task 3 依賴以上簽章，不可更動。）

- [ ] **Step 1：寫會失敗的測試**

建立 `app/test/licenses/third_party_licenses_test.dart`：

```dart
import 'dart:convert';
import 'dart:typed_data';

import 'package:elinkbook/licenses/third_party_licenses.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

/// 假 bundle：[texts] 內有的路徑回傳該文字，[throwing] 內的路徑丟出例外，
/// 其餘路徑視為找不到（丟出 FlutterError，與真實 bundle 行為一致）。
class _FakeBundle extends AssetBundle {
  _FakeBundle(this.texts, {this.throwing = const {}});

  final Map<String, String> texts;
  final Set<String> throwing;

  @override
  Future<ByteData> load(String key) async {
    if (throwing.contains(key)) throw StateError('模擬讀取失敗：$key');
    final text = texts[key];
    if (text == null) throw FlutterError('Unable to load asset: $key');
    final bytes = Uint8List.fromList(utf8.encode(text));
    return ByteData.sublistView(bytes);
  }

  @override
  Future<T> loadStructuredData<T>(
    String key,
    Future<T> Function(String value) parser,
  ) async => parser(await loadString(key));
}

/// 讀出目前登錄的所有授權項目。
Future<List<LicenseEntry>> _readAllLicenses() => LicenseRegistry.licenses.toList();

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    // 清掉其他登錄（含 Flutter 自帶的），只留本測試登錄的。
    LicenseRegistry.reset();
  });

  tearDown(() {
    // 還原全域狀態，避免本檔登錄的 collector 殘留影響後續測試。
    LicenseRegistry.reset();
  });

  group('kThirdPartyLicenses 清單', () {
    test('Issue 1 範圍：5 項程式元件，順序與名稱符合 spec', () {
      expect(
        kThirdPartyLicenses.map((l) => l.packageName).toList(),
        [
          'foliate-js',
          'zip.js',
          'fflate',
          'OpenCC',
          'Readium kotlin-toolkit',
        ],
      );
    });

    test('packageName 與 assetPath 皆不重複', () {
      final names = kThirdPartyLicenses.map((l) => l.packageName).toSet();
      final paths = kThirdPartyLicenses.map((l) => l.assetPath).toSet();
      expect(names.length, kThirdPartyLicenses.length);
      expect(paths.length, kThirdPartyLicenses.length);
    });
  });

  group('registerThirdPartyLicenses', () {
    test('以真實 rootBundle 登錄：5 筆、packages 與清單一致、全文含上游版權關鍵字', () async {
      registerThirdPartyLicenses();

      final entries = await _readAllLicenses();

      expect(
        entries.map((e) => e.packages.single).toList(),
        kThirdPartyLicenses.map((l) => l.packageName).toList(),
      );
      final textByPackage = {
        for (final e in entries)
          e.packages.single: e.paragraphs.map((p) => p.text).join('\n'),
      };
      // 每筆全文非空，且含上游原檔的關鍵字（證明 asset 路徑與內容正確）
      expect(textByPackage['foliate-js'], contains('John Factotum'));
      expect(textByPackage['zip.js'], contains('Gildas Lormeau'));
      expect(textByPackage['fflate'], contains('Arjun Barrett'));
      expect(textByPackage['OpenCC'], contains('Apache License'));
      expect(textByPackage['Readium kotlin-toolkit'], contains('Readium'));
      for (final text in textByPackage.values) {
        expect(text.trim(), isNotEmpty);
      }
    });

    test('某個 asset 讀不到時，其他 4 筆仍登錄成功', () async {
      final texts = {
        for (final l in kThirdPartyLicenses) l.assetPath: '${l.packageName} 授權全文',
      }..remove(kThirdPartyLicenses[1].assetPath); // 拿掉 zip.js

      registerThirdPartyLicenses(bundle: _FakeBundle(texts));

      final entries = await _readAllLicenses();
      expect(
        entries.map((e) => e.packages.single).toList(),
        ['foliate-js', 'fflate', 'OpenCC', 'Readium kotlin-toolkit'],
      );
    });

    test('某個 asset 丟出非 FlutterError 的任意例外，也只略過該筆', () async {
      final texts = {
        for (final l in kThirdPartyLicenses) l.assetPath: '${l.packageName} 授權全文',
      };

      registerThirdPartyLicenses(
        bundle: _FakeBundle(
          texts,
          throwing: {kThirdPartyLicenses[0].assetPath},
        ),
      );

      final entries = await _readAllLicenses();
      expect(entries.length, 4);
      expect(entries.map((e) => e.packages.single), isNot(contains('foliate-js')));
    });

    test('asset 內容是空白時略過，不登錄空授權', () async {
      final texts = {
        for (final l in kThirdPartyLicenses) l.assetPath: '${l.packageName} 授權全文',
        kThirdPartyLicenses[2].assetPath: '  \n\t\n',
      };

      registerThirdPartyLicenses(bundle: _FakeBundle(texts));

      final entries = await _readAllLicenses();
      expect(entries.length, 4);
      expect(entries.map((e) => e.packages.single), isNot(contains('fflate')));
    });

    test('授權全文保留中文與段落分隔', () async {
      // LicenseEntryWithLineBreaks 會把「同段內的單一換行」折成空格，
      // 只有空行才是段落分隔，所以用空行測試段落保留。
      final texts = {
        for (final l in kThirdPartyLicenses) l.assetPath: '第一段\n\n第二段 版權所有',
      };

      registerThirdPartyLicenses(bundle: _FakeBundle(texts));

      final entries = await _readAllLicenses();
      final joined = entries.first.paragraphs.map((p) => p.text).join('\n');
      expect(joined, contains('第一段\n第二段 版權所有'));
    });
  });
}
```

- [ ] **Step 2：跑測試確認失敗**

Run（在 `app/`）：`flutter test test/licenses/third_party_licenses_test.dart`
Expected：編譯失敗，`Target of URI doesn't exist: 'package:elinkbook/licenses/third_party_licenses.dart'`。

- [ ] **Step 3：寫最小實作**

建立 `app/lib/licenses/third_party_licenses.dart`：

```dart
import 'package:flutter/services.dart';
import 'package:flutter/foundation.dart';

/// 一筆第三方授權：顯示名稱（授權頁的套件標題）與授權全文的 asset 路徑。
///
/// 授權全文取自各上游 LICENSE 原檔，不改寫（epic-55 design Q3）。
class ThirdPartyLicense {
  const ThirdPartyLicense({required this.packageName, required this.assetPath});

  /// 授權頁上顯示的套件名稱。
  final String packageName;

  /// 授權全文的 asset 路徑（需已在 pubspec.yaml 宣告）。
  final String assetPath;
}

/// 要登錄的授權清單。
///
/// 這些元件不是 Dart 套件，Flutter 不會自動收集它們的授權，
/// 但各授權都要求散布時保留版權與授權聲明。
const List<ThirdPartyLicense> kThirdPartyLicenses = [
  // foliate-js 與其內附的 zip.js、fflate：位於 android/app/src/main/assets/foliate/
  ThirdPartyLicense(
    packageName: 'foliate-js',
    assetPath: 'assets/licenses/foliate-js.txt',
  ),
  ThirdPartyLicense(
    packageName: 'zip.js',
    assetPath: 'assets/licenses/zip-js.txt',
  ),
  ThirdPartyLicense(
    packageName: 'fflate',
    assetPath: 'assets/licenses/fflate.txt',
  ),
  // OpenCC 簡繁字元對照表：編進 text_conversion_dict.js
  ThirdPartyLicense(
    packageName: 'OpenCC',
    assetPath: 'assets/licenses/opencc.txt',
  ),
  // Readium kotlin-toolkit：readium-shared／readium-streamer 兩個 Android 相依
  ThirdPartyLicense(
    packageName: 'Readium kotlin-toolkit',
    assetPath: 'assets/licenses/readium-kotlin-toolkit.txt',
  ),
];

/// 把 [kThirdPartyLicenses] 登錄到 Flutter 的 [LicenseRegistry]，
/// 授權頁（showLicensePage）會自動列出。
///
/// 只呼叫一次 [LicenseRegistry.addLicense]；每筆授權讀一次 asset。
/// asset 讀不到（任何例外）或內容為空白時略過該筆並繼續，
/// 不讓整個授權頁失敗。[bundle] 預設為 [rootBundle]，測試時可注入。
void registerThirdPartyLicenses({AssetBundle? bundle}) {
  final assetBundle = bundle ?? rootBundle;
  LicenseRegistry.addLicense(() async* {
    for (final license in kThirdPartyLicenses) {
      final String text;
      try {
        text = await assetBundle.loadString(license.assetPath);
      } catch (_) {
        continue; // 讀不到就略過這一筆
      }
      if (text.trim().isEmpty) continue; // 空檔不登錄
      yield LicenseEntryWithLineBreaks([license.packageName], text);
    }
  });
}
```

注意：`LicenseRegistry`、`LicenseEntryWithLineBreaks` 在 `package:flutter/foundation.dart`，`AssetBundle`／`rootBundle` 在 `package:flutter/services.dart`；兩者都需 import（上方已列）。

- [ ] **Step 4：跑測試確認通過**

Run：`flutter test test/licenses/third_party_licenses_test.dart`
Expected：全部 PASS（共 7 個測試）。

若「真實 rootBundle」那條失敗且訊息為找不到 asset，回頭檢查 Task 1 的 pubspec 宣告與檔名。

- [ ] **Step 5：analyze 與 commit**

```bash
cd /c/Users/fycdc/AI/elinkBook/app
flutter analyze   # 預期 No issues found!
cd ..
git add app/lib/licenses app/test/licenses
git commit -m "feat(licenses): 加入第三方授權登錄機制與 5 項程式元件清單（epic-55 Issue 1）

Co-Authored-By: Claude Sonnet 5.5 <noreply@anthropic.com>"
```

---

### Task 3：`main.dart` 呼叫登錄、回歸驗證、進度更新

**Files：**
- Modify：`app/lib/main.dart:86`（`WidgetsFlutterBinding.ensureInitialized();` 之後）
- Modify：`docs/epics/epic-55-third-party-licenses/issues.md`（Issue 1 的 Status）、`docs/epics.md`（備註）

**Interfaces：**
- Consumes：Task 2 的 `registerThirdPartyLicenses()`。

- [ ] **Step 1：在 `main.dart` 加 import 與呼叫**

`main.dart` 的內部 import 全部是相對路徑（沒有任何 `package:elinkbook/`），比照辦理。在 `import 'library/sqlite_library_repository.dart';` 之後、`import 'reader/book_reader_prefs_repository.dart';` 之前加入：

```dart
import 'licenses/third_party_licenses.dart';
```

在 `WidgetsFlutterBinding.ensureInitialized();` 之後立刻加入：

```dart
  // epic-55：登錄非 Dart 套件元件（foliate-js 等）的授權，授權頁才會列出。
  registerThirdPartyLicenses();
```

- [ ] **Step 2：跑異動觸及的測試**

```bash
cd /c/Users/fycdc/AI/elinkBook/app
flutter test test/licenses/third_party_licenses_test.dart test/screens/about_screen_test.dart
```

Expected：全部 PASS（about_screen 既有測試不受影響）。

- [ ] **Step 3：analyze 與字串守衛**

```bash
flutter analyze   # 預期 No issues found!
node tool/check_l10n_hardcoded_strings.js
```

Expected：兩者皆乾淨（本 Issue 沒有新增畫面字串；`packageName` 是專有名詞、不屬於 UI Widget 字串參數）。

- [ ] **Step 4：跑完整測試（本計畫最後一個 Task，只跑這一次）**

Run（`run_in_background`）：`flutter test`
Expected：全數通過（Issue 6 合併時為 3336 個，本 Issue 新增 7 個）。有失敗就回報，不要修改不相關測試。

- [ ] **Step 5：真機驗收（交人類）**

`flutter build apk --debug`、安裝後開「關於 → 開源授權」，確認：
1. 列表中找得到 foliate-js、zip.js、fflate、OpenCC、Readium kotlin-toolkit 5 項。
2. 點進每一項都看得到授權全文，且無亂碼。

此步需實機，由人類確認；回報結果前不要勾選本步驟。

- [ ] **Step 6：更新進度並 commit**

- `issues.md` 的 Issue 1 `**Status:**` 改為 `done`（人類確認真機驗收後）。
- `docs/epics.md` 的 epic-55 備註改為「Issue 1 已完成」（只寫精簡摘要，不寫歷程）。
- `docs/epics/epic-55-third-party-licenses/epic.md` 的「開發記錄」加一則 Issue 1 完成記錄與程式審查摘要（完整歷程寫在 `epic.md`，不寫進 `docs/epics.md`）。

```bash
cd /c/Users/fycdc/AI/elinkBook
git add app/lib/main.dart docs/epics/epic-55-third-party-licenses/issues.md docs/epics/epic-55-third-party-licenses/epic.md docs/epics.md docs/epics/epic-55-third-party-licenses/plans/plan-issue-1.md
git commit -m "feat(licenses): 啟動時登錄第三方授權，更新 epic-55 進度（Issue 1）

Co-Authored-By: Claude Sonnet 5.5 <noreply@anthropic.com>"
```

---

## 自我審查

- **Spec 覆蓋**：`ThirdPartyLicense`／`kThirdPartyLicenses`／`registerThirdPartyLicenses`（Task 2）、5 份授權 asset 與 pubspec（Task 1）、`main.dart` 呼叫（Task 3）；測試要求 4 條——5 筆且 packages 一致、全文非空、單筆讀不到其餘仍登錄、about_screen 不受影響——全部有對應（Task 2／Task 3 Step 2）。驗收的真機項目在 Task 3 Step 5。
- **佔位掃描**：無 TBD；所有程式碼步驟皆附完整程式碼。
- **型別一致**：`packageName`／`assetPath`／`kThirdPartyLicenses`／`registerThirdPartyLicenses({AssetBundle? bundle})` 在 Task 2、3 與 spec.md 一致。
- **計畫審查修訂**（`reviews/review-plan-issue-1.md`）：採納 I-1（`diff --strip-trailing-cr`）、I-2（測試加 `tearDown`）、M-1（段落測試改用空行）、M-2（`main.dart` 用相對路徑 import）、M-3（Step 6 納入 `epic.md`）。**不採納 M-4**（為 `ThirdPartyLicense` 補 `==`／`hashCode`／`toString`）：沒有任何程式碼或測試比較這個物件，屬於投機的彈性，違反 CLAUDE.md「Simplicity First」；spec.md 也已固定介面。
- **與 spec 的細微補充**：空白 asset 內容略過（spec 只寫「讀不到」；此為 Review Focus 第 3 點的防護，行為不衝突）。
