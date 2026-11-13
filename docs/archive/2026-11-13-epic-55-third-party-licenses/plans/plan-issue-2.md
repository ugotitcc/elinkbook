# Issue 2：登錄 5 款可下載字型的授權 實作計畫

> **給執行者：** 必要子技能：使用 `superpowers:subagent-driven-development`（建議）或 `superpowers:executing-plans` 逐 Task 執行本計畫。步驟使用 checkbox（`- [ ]`）語法追蹤進度；每完成一個 Step 就把它改為 `- [x]`。

**Goal：** 讓「關於 → 開源授權」頁額外列出 5 款可下載字型（思源黑體、思源宋體、原俠正楷、台灣圓體、源流明體）的 SIL OFL 1.1 授權全文，且不論字型是否已下載都顯示。

**Architecture：** 沿用 Issue 1 已合併的登錄機制，不新增任何程式邏輯：把 `fonts-cdn/fonts/licenses/` 的 5 份授權檔複製到 `app/assets/licenses/`（台灣圓體另在授權全文之後附加一段取自其 README 的來源說明），再在 `kThirdPartyLicenses` 追加 5 筆。`pubspec.yaml` 已用目錄形式宣告 `assets/licenses/`，不需修改。另加一組測試，保證 asset 副本與 `fonts-cdn` 原檔內容不會日後漂移（台灣圓體為「以原檔全文開頭」）。

**Tech Stack：** Flutter／Dart、`flutter_test`。指令一律在 `app/` 目錄下執行（複製授權檔的步驟除外，見 Task 1）。

**Spec：** `docs/epics/epic-55-third-party-licenses/spec.md`（授權清單表）、`design.md`（Q3～Q5；Q4 於本計畫審查後修訂，見 Task 1 Step 7）、`issues.md` Issue 2；Issue 1 計畫見 `plans/plan-issue-1.md`。

## Global Constraints

- **語言**：文件、註解、測試名稱一律正體中文（zh-TW），禁止簡體中文；程式碼命名維持英文慣例。
- **授權文字來源**：5 份字型授權由 `fonts-cdn/fonts/licenses/` 複製，**內容不得改寫**（design Q3）。
- **台灣圓體（design Q4 修訂）**：授權檔本身沒有「Copyright 年份 持有人」那一行，**仍不補寫、不猜測版權人姓名或年份**。但其 README「著作權與授權」段說明本字型改作自 Adobe／Google 的思源黑體（並取用小杉圓體部分中文字），所以 asset = `fonts-cdn` 原檔**逐字不動** + 空行 + 一段標明「非 SIL OFL 授權條款的一部分」的來源說明，內容只能是 README 原文（`https://github.com/max32002/TaiwanPearl/blob/master/README.md`，master 分支）。附加說明不得讓任何一行以 `Copyright` 開頭。
- **字型授權與是否已下載無關，永遠顯示**（design Q5）：登錄函式不得依賴字型管理或下載狀態。
- **不動的東西**：`fonts-cdn/` 內任何檔案（台灣圓體的說明只加在 `app/assets/` 副本）、`about_screen.dart`、`registerThirdPartyLicenses` 的實作、`pubspec.yaml`、字型管理畫面（不在每款字型旁加授權連結）。
- **清單順序與名稱固定**（spec.md 授權清單表）：思源黑體、思源宋體、原俠正楷、台灣圓體、源流明體，接在既有 5 項程式元件之後。
- **asset 檔名固定**（spec.md）：`font-source-han-sans.txt`、`font-source-han-serif.txt`、`font-guan-kiap-tsing-khai.txt`、`font-taiwan-pearl.txt`、`font-gen-ryu-min.txt`。
- **行尾（本 Issue 的特殊陷阱）**：本機 `core.autocrlf=true`，git 索引內都是 LF、Windows 工作目錄是 CRLF。所以「asset 與 `fonts-cdn` 原檔相同」的測試要先把 `\r\n` 正規化成 `\n` 再比，否則在不同平台／CI 上會誤判。
- **Windows 環境**：`python` 在此環境不會實際執行，不可用來改檔案；用 Edit 工具。指令為 bash 語法，用 Bash 工具（Git Bash）。
- **測試範圍**（CLAUDE.md）：單一 Task 只跑異動觸及的測試檔；完整 `flutter test`（無參數）只在最後一個 Task 跑一次（約 5～6 分鐘，用 `run_in_background`）。
- **提交前**：`flutter analyze` 必須是 "No issues found!"，並跑 `node tool/check_l10n_hardcoded_strings.js`。
- **Commit 結尾**必須帶 `Co-Authored-By: Claude Sonnet 5.5 <noreply@anthropic.com>`。
- **流程**：直接 TDD；程式審查先出報告（存於 `reviews/`，該目錄 gitignore、不進版控），審查者不直接改程式；審查摘要放進 `epic.md`。建議分支名 `epic-55/issue-2-font-licenses`（從最新 `main` 切出）。

## Review Focus

以下是 spec 隱含、規格測試要求沒明列、最可能咬到使用者的情況（依可能性排序）：

1. **日後有人更新 `fonts-cdn/` 的授權檔，asset 副本沒跟著更新**：授權頁會顯示過期的授權文字。→ Task 1 的「asset 與原檔內容相同」測試，任何一邊改了就紅燈（台灣圓體：asset 必須以原檔全文開頭）。
2. **行尾 CRLF／LF 不同導致比對在 Windows 與 CI 結果不一致**：測試可能在開發機綠、在別處紅（或反過來）。→ Task 1 測試先正規化行尾再比，註解說明原因。
3. **台灣圓體被誤補版權人或年份，或被誤判為空而略過**：原檔沒有版權行，附加的只能是 README 來源說明。→ Task 2 測試：該筆存在、含 OFL 條款文字與來源說明、且不含「Copyright 年份」格式的版權行（忽略大小寫）。
4. **含中文的授權檔（原俠正楷的 Reserved Font Name「原俠」）讀出亂碼**：→ Task 2 以真實 `rootBundle` 讀取，斷言全文含 `原俠`。
5. **Issue 1 的測試寫死 5 筆／4 筆，加了字型後會誤紅或失去意義**：→ Task 2 把這些斷言改成由 `kThirdPartyLicenses.length` 推導，並把清單順序測試更新為 10 項。

## 檔案結構

| 動作 | 路徑 | 責任 |
|---|---|---|
| 新增 | `app/assets/licenses/font-source-han-sans.txt` | 思源黑體授權（複製自 `SourceHanSans-LICENSE.txt`） |
| 新增 | `app/assets/licenses/font-source-han-serif.txt` | 思源宋體授權（複製自 `SourceHanSerif-LICENSE.txt`） |
| 新增 | `app/assets/licenses/font-guan-kiap-tsing-khai.txt` | 原俠正楷授權（複製自 `GuanKiapTsingKhai-LICENSE.txt`） |
| 新增 | `app/assets/licenses/font-taiwan-pearl.txt` | 台灣圓體授權：`TaiwanPearl-LICENSE.txt` 原文 + README 來源說明 |
| 新增 | `app/assets/licenses/font-gen-ryu-min.txt` | 源流明體授權（複製自 `GenRyuMin-LICENSE.txt`） |
| 修改 | `app/lib/licenses/third_party_licenses.dart` | 清單追加 5 筆字型 |
| 修改 | `app/test/licenses/third_party_licenses_test.dart` | 新增一致性測試、更新 Issue 1 的數量斷言 |
| 修改 | `docs/epics/epic-55-third-party-licenses/design.md`、`spec.md` | Q4 與台灣圓體 asset 的描述修訂 |
| 修改 | `docs/epics/epic-55-third-party-licenses/issues.md`、`epic.md`、`docs/epics.md` | 進度 |

---

### Task 1：複製 5 份字型授權檔，並加上「與原檔一致」測試

**Files：**
- Create：`app/assets/licenses/font-source-han-sans.txt`、`font-source-han-serif.txt`、`font-guan-kiap-tsing-khai.txt`、`font-taiwan-pearl.txt`、`font-gen-ryu-min.txt`
- Test：`app/test/licenses/third_party_licenses_test.dart`（新增 `import 'dart:io';` 與一個 group）

**Interfaces：**
- Produces（Task 2 的清單引用）：5 個 asset 路徑 `assets/licenses/font-source-han-sans.txt`、`assets/licenses/font-source-han-serif.txt`、`assets/licenses/font-guan-kiap-tsing-khai.txt`、`assets/licenses/font-taiwan-pearl.txt`、`assets/licenses/font-gen-ryu-min.txt`。

- [ ] **Step 1：從最新 main 建立分支**

```bash
cd /c/Users/fycdc/AI/elinkBook
git checkout main && git pull
git checkout -b epic-55/issue-2-font-licenses

# 先把計畫草稿納入版控，避免 untracked 檔案在後續操作中遺失勾選進度
git add docs/epics/epic-55-third-party-licenses/plans/plan-issue-2.md
git commit -m "docs(epic-55): 加入 Issue 2 實作計畫

Co-Authored-By: Claude Sonnet 5.5 <noreply@anthropic.com>"
```

- [ ] **Step 2：寫會失敗的一致性測試**

在 `app/test/licenses/third_party_licenses_test.dart` 最上方的 import 區加入 `import 'dart:io';`（排在 `import 'dart:convert';` 之後），並在 `main()` 內、`group('registerThirdPartyLicenses', ...)` 之後加入：

```dart
  group('字型授權 asset 與 fonts-cdn 原檔一致', () {
    // asset 檔名（不含 .txt） -> fonts-cdn/fonts/licenses/ 內的原檔名（不含 .txt）。
    // 這張對照表刻意獨立於 kThirdPartyLicenses，讓本 group 在清單尚未加入字型時就能先紅燈。
    // 台灣圓體另有附加的 README 來源說明，不在此表，見下方獨立測試。
    const fontLicenseSources = {
      'font-source-han-sans': 'SourceHanSans-LICENSE',
      'font-source-han-serif': 'SourceHanSerif-LICENSE',
      'font-guan-kiap-tsing-khai': 'GuanKiapTsingKhai-LICENSE',
      'font-gen-ryu-min': 'GenRyuMin-LICENSE',
    };

    // git 索引內是 LF，但 Windows（autocrlf=true）工作目錄是 CRLF；
    // 比對前統一成 LF，避免在不同平台或 CI 上誤判。
    String normalize(String s) => s.replaceAll('\r\n', '\n');

    for (final entry in fontLicenseSources.entries) {
      test('${entry.key}.txt 內容與 fonts-cdn 的 ${entry.value}.txt 相同', () {
        // flutter test 的工作目錄是 app/，字型授權原檔在 repo 根目錄的 fonts-cdn/
        final asset = File('assets/licenses/${entry.key}.txt');
        final source = File('../fonts-cdn/fonts/licenses/${entry.value}.txt');

        expect(asset.existsSync(), isTrue, reason: '${asset.path} 不存在');
        expect(source.existsSync(), isTrue, reason: '${source.path} 不存在');
        expect(
          normalize(asset.readAsStringSync()),
          normalize(source.readAsStringSync()),
        );
      });
    }

    test('font-taiwan-pearl.txt 以 fonts-cdn 的 TaiwanPearl-LICENSE.txt 全文開頭，並附 README 來源說明', () {
      final asset = File('assets/licenses/font-taiwan-pearl.txt');
      final source = File('../fonts-cdn/fonts/licenses/TaiwanPearl-LICENSE.txt');

      expect(asset.existsSync(), isTrue, reason: '${asset.path} 不存在');
      expect(source.existsSync(), isTrue, reason: '${source.path} 不存在');
      final assetText = normalize(asset.readAsStringSync());
      final sourceText = normalize(source.readAsStringSync());

      // 授權原文逐字不動（design Q3），說明只能附加在後面
      expect(assetText.startsWith(sourceText), isTrue);
      final note = assetText.substring(sourceText.length);
      expect(note, contains('來源說明'));
      expect(note, contains('非 SIL OFL 授權條款的一部分'));
      expect(note, contains('改造Adobe和Google所開發、發表的「思源黑體」字型'));
      expect(
        note,
        contains('https://github.com/max32002/TaiwanPearl/blob/master/README.md'),
      );
    });
  });
```

- [ ] **Step 3：跑測試確認失敗**

Run（在 `app/`）：`flutter test test/licenses/third_party_licenses_test.dart --plain-name "字型授權 asset"`
Expected：5 個測試 FAIL（4 款相同性測試＋台灣圓體 1 個），原因是 `assets/licenses/font-*.txt 不存在`。

- [ ] **Step 4：複製 4 份授權檔，並產生台灣圓體（原文＋來源說明）**

```bash
cd /c/Users/fycdc/AI/elinkBook
SRC=fonts-cdn/fonts/licenses
DST=app/assets/licenses
cp "$SRC/SourceHanSans-LICENSE.txt"     "$DST/font-source-han-sans.txt"
cp "$SRC/SourceHanSerif-LICENSE.txt"    "$DST/font-source-han-serif.txt"
cp "$SRC/GuanKiapTsingKhai-LICENSE.txt" "$DST/font-guan-kiap-tsing-khai.txt"
cp "$SRC/GenRyuMin-LICENSE.txt"         "$DST/font-gen-ryu-min.txt"
```

`cp` 是逐位元組複製，不改寫內容（design Q3）。不要用編輯器重新存檔。

台灣圓體：先建立 `$TEMP/make_taiwan_pearl.js`（用 Write 工具寫檔，避免 shell 引號衝突），內容如下。原檔轉成 LF 後原文逐字保留，再附加說明；說明文字只准用 README 原文，**不得新增版權人姓名或年份**：

```js
// 產生 app/assets/licenses/font-taiwan-pearl.txt：原授權全文 + README 來源說明
const fs = require('fs');
const src = fs
  .readFileSync('fonts-cdn/fonts/licenses/TaiwanPearl-LICENSE.txt', 'utf8')
  .replace(/\r\n/g, '\n');
const note = [
  '',
  '----------------------------------------------------------------------',
  '來源說明（取自台灣圓體 README「著作權與授權」，非 SIL OFL 授權條款的一部分）',
  '',
  '台灣圓體基於思源黑體與小杉圓體，大多的字是思源黑體為主，有部份的中文使用小杉圓體的中文字。',
  '本字型是基於 SIL Open Font License 1.1 改造Adobe和Google所開發、發表的「思源黑體」字型。',
  '',
  'https://github.com/max32002/TaiwanPearl/blob/master/README.md',
  '',
].join('\n');
// 原檔結尾本來就是單一換行；這裡保持恰好一個換行再接說明
fs.writeFileSync(
  'app/assets/licenses/font-taiwan-pearl.txt',
  src.replace(/\n*$/, '\n') + note,
);
```

```bash
cd /c/Users/fycdc/AI/elinkBook
node "$TEMP/make_taiwan_pearl.js"
tail -12 app/assets/licenses/font-taiwan-pearl.txt
ls -l app/assets/licenses
```

若一致性測試因 `startsWith` 紅燈，先檢查原檔結尾是否有多餘空行（`od -c` 看最後幾個位元組），**不要**改測試去遷就。

- [ ] **Step 5：跑測試確認通過，並抽查內容**

```bash
cd app
flutter test test/licenses/third_party_licenses_test.dart --plain-name "字型授權 asset"
head -4 assets/licenses/font-taiwan-pearl.txt
```

Expected：5 個測試 PASS；台灣圓體開頭仍是 `This Font Software is licensed under the SIL Open Font License, Version 1.1.`（原文不動），結尾多出「來源說明」段。

- [ ] **Step 6：Commit**

```bash
cd /c/Users/fycdc/AI/elinkBook
git add app/assets/licenses app/test/licenses
git commit -m "feat(licenses): 加入 5 款字型授權檔（台灣圓體附 README 來源說明）與 fonts-cdn 一致性測試（epic-55 Issue 2）

Co-Authored-By: Claude Sonnet 5.5 <noreply@anthropic.com>"
```

- [ ] **Step 7：修訂 design.md 與 spec.md 的 Q4／台灣圓體描述，並 commit**

`design.md` 的 Q4 列改為：

```
| Q4 | 台灣圓體缺版權行 | 授權檔照原檔逐字顯示，不補寫、不猜測版權人姓名或年份；另在其後附加一段取自台灣圓體 README「著作權與授權」的來源說明（改作自 Adobe／Google 的思源黑體），並標明非 OFL 條款的一部分 | 版權人要有依據；README 是上游自己的說明（2026-10-02 Issue 2 計畫審查後修訂，原決定為「照原檔顯示、不補寫」） |
```

同檔「已確認的事實」中「台灣圓體：授權檔**沒有版權行**…」那一條，補一句「其 README 有來源說明（改作自思源黑體，並取用小杉圓體），見 Q4」。

`spec.md` 第 50 行「字型的 5 份由 `fonts-cdn/fonts/licenses/` 逐位元組複製。」改為「字型的 5 份由 `fonts-cdn/fonts/licenses/` 複製；其中台灣圓體在授權全文之後附加一段 README 來源說明，其餘 4 份逐位元組相同。」；第 56 行測試敘述改為「4 份字型 asset 與 `fonts-cdn` 對應檔案內容完全相同；台灣圓體 asset 以原檔全文開頭並附來源說明」。

```bash
git add docs/epics/epic-55-third-party-licenses/design.md docs/epics/epic-55-third-party-licenses/spec.md
git commit -m "docs(epic-55): 台灣圓體附加 README 來源說明，修訂 Q4 與規格

Co-Authored-By: Claude Sonnet 5.5 <noreply@anthropic.com>"
```

---

### Task 2：把 5 款字型加進授權清單（TDD）

**Files：**
- Modify：`app/lib/licenses/third_party_licenses.dart`（`kThirdPartyLicenses` 末尾）
- Test：`app/test/licenses/third_party_licenses_test.dart`（更新 Issue 1 的 5 處斷言、新增字型內容測試）

**Interfaces：**
- Consumes：Task 1 的 5 個 asset 路徑；Issue 1 的 `ThirdPartyLicense`、`kThirdPartyLicenses`、`registerThirdPartyLicenses`（簽章不變）。
- Produces：`kThirdPartyLicenses` 共 10 筆，順序為 foliate-js、zip.js、fflate、OpenCC、Readium kotlin-toolkit、思源黑體、思源宋體、原俠正楷、台灣圓體、源流明體。

- [ ] **Step 1：更新並新增測試（先紅燈）**

在 `app/test/licenses/third_party_licenses_test.dart` 做以下修改：

(a) 清單順序測試，改名並擴成 10 項（取代原本 `'Issue 1 範圍：5 項程式元件，順序與名稱符合 spec'` 整個 test）：

```dart
    test('10 項：5 項程式元件加 5 款字型，順序與名稱符合 spec', () {
      expect(kThirdPartyLicenses.map((l) => l.packageName).toList(), [
        'foliate-js',
        'zip.js',
        'fflate',
        'OpenCC',
        'Readium kotlin-toolkit',
        '思源黑體',
        '思源宋體',
        '原俠正楷',
        '台灣圓體',
        '源流明體',
      ]);
    });
```

(b) 真實 `rootBundle` 測試：把測試名稱改為 `'以真實 rootBundle 登錄：10 筆、packages 與清單一致、全文含上游版權關鍵字'`，並在既有 `expect(textByPackage['Readium kotlin-toolkit'], contains('Readium'));` 之後、`for (final text in textByPackage.values)` 之前加入：

```dart
      // 5 款字型：皆為 SIL OFL 1.1，並含各自上游的版權關鍵字
      for (final font in ['思源黑體', '思源宋體', '原俠正楷', '台灣圓體', '源流明體']) {
        expect(
          textByPackage[font],
          contains('SIL Open Font License'),
          reason: '$font 授權全文應含 OFL 條款',
        );
      }
      expect(textByPackage['思源黑體'], contains('Adobe'));
      expect(textByPackage['思源宋體'], contains('Adobe'));
      expect(textByPackage['源流明體'], contains('Adobe'));
      expect(textByPackage['原俠正楷'], contains('Tony Huang'));
      // 中文 Reserved Font Name 要能正確讀出（UTF-8）
      expect(textByPackage['原俠正楷'], contains('原俠'));
```

(c) 緊接著新增台灣圓體專屬測試（放在同一個 group 內）：

```dart
    test('台灣圓體：原檔沒有版權行，不補寫版權人／年份；僅附 README 來源說明', () async {
      registerThirdPartyLicenses();

      final entries = await _readAllLicenses();
      final text = entries
          .firstWhere((e) => e.packages.single == '台灣圓體')
          .paragraphs
          .map((p) => p.text)
          .join('\n');

      expect(text, contains('SIL Open Font License'));
      expect(text, contains('改造Adobe和Google所開發、發表的「思源黑體」字型'));
      // 沒有「Copyright 2022」或「Copyright (c) 2022」這種「版權年份＋持有人」行。
      // 注意不能檢查「以 Copyright 開頭」：OFL 條款本文的「Copyright Holder...」
      // 本來就會換行後出現在行首。
      expect(
        RegExp(
          r'^\s*Copyright\s+(\(c\)\s*)?\d{4}',
          multiLine: true,
          caseSensitive: false,
        ).hasMatch(text),
        isFalse,
      );
    });
```

(d) 「某個 asset 讀不到」測試：名稱改為 `'某個 asset 讀不到時，其他筆仍登錄成功'`，並把寫死的預期清單

```dart
      expect(entries.map((e) => e.packages.single).toList(), [
        'foliate-js',
        'fflate',
        'OpenCC',
        'Readium kotlin-toolkit',
      ]);
```

改為由清單推導：

```dart
      expect(
        entries.map((e) => e.packages.single).toList(),
        kThirdPartyLicenses
            .map((l) => l.packageName)
            .where((n) => n != 'zip.js')
            .toList(),
      );
```

(e) 「丟出任意例外」與「空白內容」兩個測試中的 `expect(entries.length, 4);` 各改為 `expect(entries.length, kThirdPartyLicenses.length - 1);`（共 2 處）。

- [ ] **Step 2：跑測試確認失敗**

Run：`flutter test test/licenses/third_party_licenses_test.dart`
Expected：清單順序、真實 `rootBundle`、台灣圓體 3 個測試 FAIL（目前清單只有 5 筆）；其餘 PASS。

- [ ] **Step 3：在清單末尾追加 5 筆字型**

在 `app/lib/licenses/third_party_licenses.dart` 的 `kThirdPartyLicenses` 中，`Readium kotlin-toolkit` 那一筆之後、`];` 之前加入：

```dart
  // 5 款可下載字型（SIL OFL 1.1）：字型檔不在 APK 內，由使用者在字型管理下載；
  // 但授權是靜態資訊，與是否已下載無關，永遠顯示（epic-55 design Q5）。
  // 台灣圓體的上游授權檔沒有版權行，原文照顯示、不補寫；asset 末尾另附
  // README 的來源說明（design Q4 修訂版）。
  ThirdPartyLicense(
    packageName: '思源黑體',
    assetPath: 'assets/licenses/font-source-han-sans.txt',
  ),
  ThirdPartyLicense(
    packageName: '思源宋體',
    assetPath: 'assets/licenses/font-source-han-serif.txt',
  ),
  ThirdPartyLicense(
    packageName: '原俠正楷',
    assetPath: 'assets/licenses/font-guan-kiap-tsing-khai.txt',
  ),
  ThirdPartyLicense(
    packageName: '台灣圓體',
    assetPath: 'assets/licenses/font-taiwan-pearl.txt',
  ),
  ThirdPartyLicense(
    packageName: '源流明體',
    assetPath: 'assets/licenses/font-gen-ryu-min.txt',
  ),
```

同時把該檔 `kThirdPartyLicenses` 上方文件註解的「這些元件不是 Dart 套件」之後補一句「（含 5 款可下載字型）」；其餘不動。

- [ ] **Step 4：跑測試確認通過**

Run：`flutter test test/licenses/third_party_licenses_test.dart test/screens/about_screen_test.dart`
Expected：全部 PASS（`about_screen` 既有測試不受影響）。

- [ ] **Step 5：analyze、字串守衛與 commit**

```bash
cd /c/Users/fycdc/AI/elinkBook/app
flutter analyze   # 預期 No issues found!
node tool/check_l10n_hardcoded_strings.js
cd ..
git add app/lib/licenses app/test/licenses
git commit -m "feat(licenses): 授權頁登錄 5 款可下載字型的 SIL OFL 授權（epic-55 Issue 2）

Co-Authored-By: Claude Sonnet 5.5 <noreply@anthropic.com>"
```

`packageName` 是專有名詞常數、不是 Widget 字串參數，字串守衛預期乾淨；若守衛誤報，回報給人類，不要為了過守衛改成 l10n 鍵（spec 把名稱固定為這 5 個中文字型名）。

---

### Task 3：完整驗證、真機驗收與進度更新

**Files：**
- Modify：`docs/epics/epic-55-third-party-licenses/issues.md`（Issue 2 Status）、`epic.md`（開發記錄）、`docs/epics.md`（備註）

- [ ] **Step 1：跑完整測試（本計畫最後一個 Task，只跑這一次）**

Run（在 `app/`，`run_in_background`）：`flutter test`
Expected：全數通過（Issue 1 合併時為 3343 過、1 略過；本 Issue 新增 6 個：5 個一致性〔4 款相同＋台灣圓體以原檔開頭〕＋1 個台灣圓體內容）。有失敗就回報，不要修改不相關測試。

- [ ] **Step 2：真機驗收（交人類）**

`flutter build apk --debug` 安裝後：
1. 開「關於 → 開源授權」，找得到思源黑體、思源宋體、原俠正楷、台灣圓體、源流明體（共 10 項，含 Issue 1 的 5 項）。
2. **先確認字型管理裡這 5 款都「未下載」的情況下**也能看到（驗證 Q5：與下載狀態無關）。
3. 點進原俠正楷，授權全文中文「原俠」正常顯示；點進台灣圓體，開頭直接是 OFL 條款（沒有版權行），捲到最後有「來源說明」段，中文無亂碼。

此步需實機，由人類確認；確認前不要勾選本步驟。

- [ ] **Step 3：更新進度並 commit**

- `issues.md`：Issue 2 `**Status:**` 改為 `done`。
- `docs/epics.md`：epic-55 備註改為「全數完成，待歸檔」（只寫精簡摘要）。
- `epic.md`「開發記錄」加一則 Issue 2 完成記錄（含程式審查摘要；若有 PR 編號，合併後再補）。
- 歸檔由人類指定，不要自行搬移目錄。

```bash
cd /c/Users/fycdc/AI/elinkBook
git add docs
git commit -m "docs(epic-55): Issue 2 真機驗收通過，更新進度

Co-Authored-By: Claude Sonnet 5.5 <noreply@anthropic.com>"
git push -u origin epic-55/issue-2-font-licenses
```

---

## 自我審查

- **Spec 覆蓋**：5 份字型授權 asset（Task 1）、清單加 5 筆且名稱／順序／路徑與 spec 表一致（Task 2）、`pubspec.yaml` 不需改（Issue 1 已用目錄宣告）；測試要求兩條——`LicenseRegistry.licenses` 讀到 10 筆（Task 2 (b)）、5 份 asset 與 `fonts-cdn` 內容相同（Task 1）——都有對應；驗收標準的真機項目在 Task 3 Step 2。design 的 Q3（授權原文不改寫：4 份用 `cp`、台灣圓體原文逐字保留）、Q4（修訂版：原文不動＋附 README 來源說明，Task 1 Step 4／7、Task 2 (c)）、Q5（與下載狀態無關，Task 3 Step 2 實機驗證；登錄函式本就不依賴字型 store）皆落實。
- **佔位掃描**：無 TBD；所有程式碼步驟皆附完整程式碼與指令。
- **型別一致**：沿用 Issue 1 的 `ThirdPartyLicense(packageName, assetPath)`、`kThirdPartyLicenses`、`registerThirdPartyLicenses({AssetBundle? bundle})`，未更動簽章；asset 路徑在 Task 1、Task 2 與 spec.md 一致。
- **計畫審查修訂**（`reviews/review-plan-issue-2.md`）：採納 M-2（`cp` 路徑加雙引號）、M-3（Task 1 Step 1 先 commit 計畫草稿）；M-1 **部分採納**——只加 `caseSensitive: false`，**不採**改成 `^\s*Copyright\b`：原檔第 63、69 行本來就以 `Copyright Holder` 開頭（另有 2 行含 `copyright`／`COPYRIGHT`），該正則會命中 4 行，讓測試在原檔上紅燈，所以保留「Copyright＋年份」的判斷。另依人類指示（附 README 連結）與選擇，台灣圓體改為附加 README 來源說明（見 Global Constraints）。
- **與 spec 的一處說明**：spec 寫「逐位元組複製」。實際測試比對時先把 CRLF 正規化成 LF，因為 git 索引是 LF、Windows 工作目錄是 CRLF（兩邊在同一台機器上被同樣轉換，但跨平台／CI 不保證）；`cp` 本身仍是逐位元組複製。這個差異是 Task 1 測試的刻意設計，不改變「內容不改寫」的要求。
