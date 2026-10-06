# Issue 15：integration 測試補多語系設定與回歸守衛 實作計畫

> **給執行者：** 必要子技能：使用 `superpowers:subagent-driven-development`（建議）或 `superpowers:executing-plans` 逐 Task 執行本計畫。步驟使用 checkbox（`- [ ]`）語法追蹤進度；每完成一個 Step 就把它改為 `- [x]`。

**Goal：** 讓 `integration_test/` 內所有 `MaterialApp` 都帶上多語系設定（`locale`／`localizationsDelegates`／`supportedLocales`），並把 `tool/check_l10n_hardcoded_strings.js` 的「測試端稽核」擴大到 `integration_test/`，使這個缺陷不會再無聲復發；再於真機逐檔執行，把補完後暴露的失敗分類記錄。

**Architecture：** 104 處 `MaterialApp(` 全部是同一種形態 `tester.pumpWidget(MaterialApp(home: X))`（其中 4 處多帶一個等於預設值的 `theme:`），所以用一次性 Node 腳本機械改寫成專案既有標準 `pumpLocalizedWidget(tester, X)`（`test/support/pump_localized_widget.dart`，epic-45 Issue 0 建立）。檢查腳本新增 `--integration-dir` 旗標並在最後一個 Task 才納入預設掃描（先加旗標、清完才啟用預設，每個 commit 都維持綠燈）。真機驗證只是「分類並記錄」，不要求全數通過。

**Tech Stack：** Flutter／Dart、`flutter_test`／`integration_test`、Node（檢查腳本與一次性 codemod）。指令一律在 `app/` 目錄下執行。

**Spec：** 沒有獨立 `spec.md`。缺陷描述見 `docs/epics/epic-54-architecture-optimization/issues.md` Issue 15 與 `epic.md`「Issue 15」段落；既有規則契約見 `docs/archive/` 內 `epic-45-interface-i18n` 的 `spec.md` §8（測試包裝器）與 §9（檢查腳本）；`app/tool/README.md` 的 `check_l10n_hardcoded_strings.js` 段落。

## Global Constraints

- **語言**：所有文件、註解、測試名稱一律正體中文（zh-TW），禁止簡體中文；程式碼命名維持英文慣例。
- **只改多語系設定**：除 `tester.pumpWidget(MaterialApp(home: …))` → `pumpLocalizedWidget(tester, …)` 之外，不改任何測試的斷言、流程、等待時間、素材；不改 `lib/`。
- **不放寬測試**：真機驗證時發現的失敗，**不得**為了通過而改斷言或加 `skip`；依 Task 4 的分類規則記錄。
- **locale 釘定為正體中文**：`pumpLocalizedWidget` 預設 `Locale('zh', 'TW')`，與既有單元測試一致。
- **預設主題等價性**：codemod 只在 `theme:` 恰為 `resolveThemeData(theme: AppTheme.light, isEinkMode: false)`（等於 `pumpLocalizedWidget` 的預設）時才省略；任何其他值一律列入「需手動處理」，不得自行猜測。
- **檢查腳本契約不變**：沒給任何旗標時行為由 Task 3 才改；`--lib-dir`／`--test-dir` 的既有語意、結束碼（0 乾淨／1 違規／2 設定錯誤或掃 0 個檔案）全部不動。
- **測試範圍**（CLAUDE.md）：單一 Task 只跑異動觸及的測試；完整 `flutter test`（無參數）只在最後一個 Task 跑一次（約 6 分鐘，用 `run_in_background`，**必須在 `app/` 目錄下執行**）。integration 測試不屬於 `flutter test`，只能在 Android 真機／模擬器上以 `flutter test integration_test/<檔案> -d <device-id>` 執行。
- **提交前**：`flutter analyze` 必須是 "No issues found!"（含 `integration_test/`），並跑 `node tool/check_l10n_hardcoded_strings.js`。
- **Windows 環境**：用 Bash 工具（Git Bash）；`python` 不可用（只是 Windows Store 殼，會靜默失敗）；多數原始檔是 CRLF，Edit 的定位字串不要含換行；一次性腳本用 Node，放 worktree 根目錄 `.scratch/`（untracked），提交一律用明確路徑 `git add`，不用 `git add -A`；**Bash 的 heredoc 對含反引號與引號的長內容會解析失敗，腳本改用 Write 工具建檔再執行**。本計畫所有指令以 Git Bash 為準（`$?`、`$(…)` 皆為 Bash 語法）；若改在 pwsh 執行，退出碼要用 `$LASTEXITCODE`（`$?` 只是布林）。
- **真機安全**：以 debug 版安裝時，若手機上已有簽章或版本不同的 `cc.ugotit.elinkbook`，Flutter 會**自動解除安裝舊版並清除其資料**（Issue 11 驗證時已發生兩次）。**第一次執行真機測試前必須先向使用者確認**目標裝置與是否接受清除該裝置上的 App。不得自行換裝置。
- **Commit 結尾**必須帶 `Co-Authored-By: Claude Sonnet 5.5 <noreply@anthropic.com>`。
- **流程**：計畫先審查再動手；程式審查先出報告（存於 `reviews/`，gitignore、不進版控），審查者不直接改程式；審查摘要放進 `epic.md`。

## 需使用者確認的前提（審查計畫時請回答）

1. **採用 `pumpLocalizedWidget`，不另建 helper、也不在 104 處各自內嵌三個參數。** 專案 README 已寫「優先改用 `pumpLocalizedWidget()`」；104 處形態一致，機械改寫風險低。代價：該 helper 位於 `test/support/`，integration 測試要 `import '../test/support/pump_localized_widget.dart'`（integration 測試本來就在 import `../test/support/` 的其他檔案，無新依賴方向）。
2. **回歸守衛：新增 `--integration-dir`，清完後納入「無旗標」預設掃描，且不設白名單。** 現有白名單 `TEST_BARE_APP_ALLOW` 只服務 `app/test/`，integration 沒有刻意保留裸 `MaterialApp` 的案例（`manual_import_acceptance_test.dart` 的那一處也一併改）。
3. **完成標準不是「全部通過」。** 這批測試自多語系導入後從未在真機有效執行，補完 delegates 後很可能暴露其他失敗。本 Issue 的完成標準：(a) 104 處全部改完、`flutter analyze` 與檢查腳本乾淨；(b) 先前 5 個檔案（`fxl_bookmarks_test`、`epub_toc_test`、`reading_position_test`、`foliate_cbz_test`、`reader_screen_test`）不再卡在 `AppLocalizations.of(context)!` 的 null check；(c) 其餘每個檔案在真機上要嘛通過、要嘛有「已分類並記錄」的失敗。**與多語系無關的既存失敗不在本 Issue 修**，記進 `epic.md` 並建議另立工單；**只有判定為 Issue 11 造成的回歸（C 類）才在本 Issue 修。**
4. **真機驗證只用一台指定裝置，且不跑 `manual_import_acceptance_test.dart`。** 該檔是人工驗收（無自動斷言，需要人在系統檔案選擇器選檔），只改多語系設定、不在真機執行。其餘 32 個含 `MaterialApp` 的檔案逐檔執行，每次 `flutter test` 都會重新建置，預估總時間 40 分鐘以上；執行期間手機須保持接線、螢幕常亮。

## Review Focus

最可能咬到使用者的情況（依可能性排序），每條都有對應測試或驗證步驟：

1. **codemod 悄悄改變測試語意**（例如省略了不等於預設值的 `theme:`、吃掉 `home:` 以外的參數、`const` 範圍改變）。 → Task 2：codemod 對任何無法解析的形態一律「列入手動處理」不改；改寫後 `grep` 驗證 `MaterialApp(` 剩餘 0 處、`pumpWidget(` 剩餘非 `pumpLocalizedWidget` 的呼叫 0 處；先在 `smoke_test.dart`（含 `theme:` 與 `const`）與 `fxl_bookmarks_test.dart`（多行）試跑並人工審 diff。
2. **守衛掃到 0 個檔案卻被當成乾淨**（指錯目錄）。 → Task 1：`--integration-dir` 指向空目錄必須結束碼 2。
3. **守衛漏掉新增的裸 `MaterialApp`**（日後有人在 `integration_test/` 新增測試又寫裸 `MaterialApp`）。 → Task 1／3：單元測試植入一個缺參數的 `MaterialApp`，必須結束碼 1，輸出含 `integration_test/<檔案>:<行號>`；Task 3 確認預設無旗標也會掃 `integration_test/`。
4. **補完 delegates 後暴露的失敗被誤判為「既存」而不處理，或誤判為「Issue 11 回歸」而亂改。** → Task 4：用固定的 A／B／C／D 分類表，C 類（Issue 11 回歸）必須在 base（`bdff826c` 之前的 main）同機重現對照才能判定為既存；不得以推測定案。
5. **locale 釘定為正體中文後，原本假設英文或其他語言的斷言失敗。** → Task 4：D 類（斷言文字與 locale 不符）單獨分類，列出檔案與斷言，不自行改文字。
6. **真機掉線或安裝失敗造成假失敗。** → Task 4：每個檔案結果必須有 `+N -M` 的測試計數或 `exit` 碼證據；出現 `device … not found`、`log reader stopped`、`INSTALL_FAILED` 的記為「環境失敗，需重跑」，不納入分類。

## File Structure

| 檔案 | 動作 | 責任 |
|---|---|---|
| `app/tool/check_l10n_hardcoded_strings.js` | 修改 | `scanTestDir` 加 `allowMap` 參數；`checkTest` 加 `label`；新增 `--integration-dir`；Task 3 起無旗標預設含 `integration_test/` |
| `app/tool/test_check_l10n_hardcoded_strings.mjs` | 修改 | 新增 integration 掃描與 CLI 旗標的單元測試 |
| `app/tool/README.md` | 修改 | 文件化第三項檢查與新旗標 |
| `app/integration_test/*.dart`（33 個含 `MaterialApp` 的檔案） | 修改 | 104 處 `tester.pumpWidget(MaterialApp(home: X))` → `pumpLocalizedWidget(tester, X)`；加 import；移除因此不再使用的 import |
| `.scratch/codemod_integration_l10n.js`（worktree 根目錄，不進版控） | 新增 | 一次性改寫腳本 |
| `docs/epics/epic-54-architecture-optimization/{epic.md,issues.md}`、`docs/epics.md` | 修改 | 真機分類結果、狀態 |

---

### Task 0：提交計畫、建立 worktree、記錄基準

**Files：**
- Commit：本計畫檔（在 `main` 上，純文件）
- 建立 worktree：`.worktrees/epic-54-issue-15-integration-l10n`（`.worktrees/` 已 gitignore）

- [ ] **Step 1：提交計畫（在 `main`）**

```bash
git add docs/epics/epic-54-architecture-optimization/plans/plan-issue-15.md
git commit -m "docs(epic-54): Issue 15 實作計畫

Co-Authored-By: Claude Sonnet 5.5 <noreply@anthropic.com>"
```

- [ ] **Step 2：建立 worktree 與分支**

```bash
git worktree add .worktrees/epic-54-issue-15-integration-l10n -b epic-54/issue-15-integration-l10n
mkdir .worktrees/epic-54-issue-15-integration-l10n/.scratch
```

之後所有指令都在 `.worktrees/epic-54-issue-15-integration-l10n/app/` 下執行，先 `flutter pub get`。

- [ ] **Step 3：記錄基準**

```bash
node tool/test_check_l10n_hardcoded_strings.mjs
node tool/check_l10n_hardcoded_strings.js
grep -c "MaterialApp(" integration_test/*.dart | awk -F: '{s+=$2; if ($2>0) f++} END{print "MaterialApp( 共", s, "處，", f, "個檔案"}'
```

預期：單元測試印出「全部測試通過」；檢查腳本兩行 PASS（`app/lib` 與 `app/test`，此時尚未掃 `integration_test/`）；最後一行為 `MaterialApp( 共 104 處， 33 個檔案`。若數字不同，先查明原因（有人改過 `integration_test/`）再繼續，並更新本計畫與 `issues.md` 的數字。

---

### Task 1：檢查腳本新增 `--integration-dir`（不改預設行為）

**Files：**
- Modify：`app/tool/check_l10n_hardcoded_strings.js`
- Modify：`app/tool/test_check_l10n_hardcoded_strings.mjs`

**Interfaces：**
- Produces：`scanTestDir(testDir, allowMap = TEST_BARE_APP_ALLOW)`；`checkTest(testDir, label = 'test')`；CLI 旗標 `--integration-dir <目錄>`（只給此旗標時只做 integration 那項檢查）。

- [ ] **Step 1：寫失敗測試**

在 `app/tool/test_check_l10n_hardcoded_strings.mjs` 中，找到這一行（位於 `try { … }` 區塊末尾、`} finally {` 之前）：

```js
  assert.equal(cli('--lib-dir', emptyDir, '--test-dir', testDir).status, 2)
```

在它**之後**插入：

```js

  // ---- integration_test 掃描（epic-54 Issue 15）：同一套規則，但不套用 app/test 專屬白名單 ----
  const itDir = path.join(tmp, 'itdir')
  const writeIt = (rel, content) => {
    const full = path.join(itDir, rel)
    fs.mkdirSync(path.dirname(full), { recursive: true })
    fs.writeFileSync(full, content)
  }
  writeIt('ok_test.dart', FULL)
  const okIt = cli('--integration-dir', itDir)
  assert.equal(okIt.status, 0)
  assert.match(okIt.stdout, /掃描 1 個 integration 測試檔/)
  // 只給 --integration-dir 時不可順便掃預設的 lib／test
  assert.doesNotMatch(okIt.stdout, /個檔案，未發現/)
  assert.doesNotMatch(okIt.stdout, /個測試檔，所有/)

  // 植入一個缺 locale 的裸 MaterialApp：必須被抓到，輸出帶 integration_test/ 前綴與行號
  writeIt('bad_test.dart', dart('a();', 'tester.pumpWidget(MaterialApp(home: X()));'))
  const badIt = cli('--integration-dir', itDir)
  assert.equal(badIt.status, 1)
  assert.match(badIt.stderr, /integration_test\/bad_test\.dart:2/)
  assert.match(badIt.stderr, /locale/)
  // integration_test 不設白名單：提示不可指向 TEST_BARE_APP_ALLOW；app/test 端仍保留白名單提示
  assert.doesNotMatch(badIt.stderr, /TEST_BARE_APP_ALLOW/)
  assert.match(badIt.stderr, /不設白名單/)
  assert.match(cli('--test-dir', testDir).stderr, /TEST_BARE_APP_ALLOW/)
  // scanTestDir 傳入空白名單時，與 app/test 同名的白名單檔案不得被放行
  writeIt('screens/widgets/eb_sheet_shell_test.dart', 'MaterialApp(home: A());')
  const noAllow = scanTestDir(itDir, new Map())
  assert.ok(noAllow.violations.some((v) => v.file === 'screens/widgets/eb_sheet_shell_test.dart'))

  // 設定錯誤：缺參數、目錄不存在、掃 0 個檔案都不可被當成乾淨
  assert.equal(cli('--integration-dir').status, 2)
  assert.equal(cli('--integration-dir', path.join(tmp, 'nope')).status, 2)
  const emptyIt = cli('--integration-dir', emptyDir)
  assert.equal(emptyIt.status, 2)
  assert.match(emptyIt.stderr, /沒有找到任何 \.dart/)
  // 多個旗標一起給時各自檢查，結束碼取最嚴重者
  assert.equal(cli('--test-dir', testDir, '--integration-dir', itDir).status, 1)
  assert.equal(cli('--integration-dir', itDir, '--lib-dir', emptyDir).status, 2)
```

- [ ] **Step 2：跑測試確認失敗**

```bash
node tool/test_check_l10n_hardcoded_strings.mjs
```

預期：失敗（`--integration-dir` 尚未被識別，`okIt.status` 不是 0，或 `scanTestDir` 第二參數被忽略）。

- [ ] **Step 3：實作**

在 `app/tool/check_l10n_hardcoded_strings.js`：

1. `scanTestDir` 加第二個參數並改用它。把

```js
function scanTestDir(testDir) {
```

改為

```js
function scanTestDir(testDir, allowMap = TEST_BARE_APP_ALLOW) {
```

並把函式內 `const allow = TEST_BARE_APP_ALLOW.get(rel);` 改為

```js
    const allow = allowMap.get(rel);
```

2. `checkTest` 加 `label` 參數。把

```js
function checkTest(testDir) {
  if (!isDirectory(testDir)) {
    console.error(`掃描目錄不存在：${testDir}`);
    return 2;
  }
  const { scanned, violations } = scanTestDir(testDir);
```

改為

```js
function checkTest(testDir, label = 'test') {
  if (!isDirectory(testDir)) {
    console.error(`掃描目錄不存在：${testDir}`);
    return 2;
  }
  // integration_test 沒有刻意保留裸 MaterialApp 的案例，不套用 app/test 專屬白名單
  const { scanned, violations } = scanTestDir(
    testDir,
    label === 'test' ? TEST_BARE_APP_ALLOW : new Map(),
  );
```

並把同函式內的

```js
    console.log(`PASS：掃描 ${scanned} 個測試檔，所有 MaterialApp 皆帶 locale／localizationsDelegates／supportedLocales`);
```

改為

```js
    const kind = label === 'test' ? '' : ` ${label.replace(/_test$/, '')} `;
    console.log(`PASS：掃描 ${scanned} 個${kind}測試檔，所有 MaterialApp 皆帶 locale／localizationsDelegates／supportedLocales`);
```

並把同函式結尾的白名單提示（原本無條件輸出）

```js
  console.error('若確屬刻意的裸 MaterialApp（例如驗證無 AppLocalizations 的 fallback），加進腳本的 TEST_BARE_APP_ALLOW 並註明理由。');
```

改為只對 `app/test` 提示白名單，integration_test 改提示不設白名單：

```js
  if (label === 'test') {
    console.error('若確屬刻意的裸 MaterialApp（例如驗證無 AppLocalizations 的 fallback），加進腳本的 TEST_BARE_APP_ALLOW 並註明理由。');
  } else {
    console.error(`${label} 不設白名單：所有 MaterialApp 都必須帶多語系設定（改用 pumpLocalizedWidget）。`);
  }
```

並把

```js
    console.error(`  test/${v.file}:${v.line}  ${v.note ?? `缺少 ${v.missing.join('／')}`}`);
```

改為

```js
    console.error(`  ${label}/${v.file}:${v.line}  ${v.note ?? `缺少 ${v.missing.join('／')}`}`);
```

3. `main` 加入新旗標（本 Task **不**改無旗標的預設行為）。把整個 `main` 函式改為：

```js
function main(argv) {
  const libOpt = parseDirOption(argv, '--lib-dir');
  const testOpt = parseDirOption(argv, '--test-dir');
  const integrationOpt = parseDirOption(argv, '--integration-dir');
  if (libOpt === null || testOpt === null || integrationOpt === null) return 2;
  const anyFlag = libOpt !== undefined || testOpt !== undefined || integrationOpt !== undefined;
  const runLib = libOpt !== undefined || !anyFlag;
  const runTest = testOpt !== undefined || !anyFlag;
  // Task 3 之前，無旗標的預設不含 integration_test（目前還有 104 處待修）
  const runIntegration = integrationOpt !== undefined;
  let exit = 0;
  // 結束碼取最大值：2（設定錯誤）優先於 1（有違規）優先於 0
  if (runLib) exit = Math.max(exit, checkLib(libOpt ?? path.resolve(__dirname, '..', 'lib')));
  if (runTest) exit = Math.max(exit, checkTest(testOpt ?? path.resolve(__dirname, '..', 'test')));
  if (runIntegration) exit = Math.max(exit, checkTest(integrationOpt, 'integration_test'));
  return exit;
}
```

同時把檔案頂端 CLI 說明（約第 12～13 行）補上一行：

```js
//   node app/tool/check_l10n_hardcoded_strings.js --integration-dir <目錄>  # 只做 integration_test 的 MaterialApp 檢查
```

- [ ] **Step 4：跑測試確認通過**

```bash
node tool/test_check_l10n_hardcoded_strings.mjs
node tool/check_l10n_hardcoded_strings.js
node tool/check_l10n_hardcoded_strings.js --integration-dir integration_test; echo "exit=$?"
```

預期：單元測試通過；第二行（無旗標）仍兩行 PASS，行為與 Task 0 基準相同；第三行**預期失敗**，`exit=1`，列出 104 處 `integration_test/<檔案>:<行號>  缺少 locale／localizationsDelegates／supportedLocales`（這是真實現況，用來確認守衛有效，Task 2 後才會變乾淨）。

- [ ] **Step 5：提交**

```bash
git add tool/check_l10n_hardcoded_strings.js tool/test_check_l10n_hardcoded_strings.mjs
git commit -m "feat(epic-54): l10n 檢查腳本新增 --integration-dir（Issue 15 Task 1）

Co-Authored-By: Claude Sonnet 5.5 <noreply@anthropic.com>"
```

---

### Task 2：codemod——104 處改用 `pumpLocalizedWidget`

**Files：**
- Create（`.scratch/`，不提交）：`.scratch/codemod_integration_l10n.js`
- Modify：`app/integration_test/` 內 33 個含 `MaterialApp(` 的檔案

**Interfaces：**
- Consumes：`pumpLocalizedWidget(WidgetTester tester, Widget home, {Locale locale = const Locale('zh','TW'), AppTheme theme = AppTheme.light, bool isEinkMode = false, GlobalKey<NavigatorState>? navigatorKey, List<NavigatorObserver> navigatorObservers = const [], MediaQueryData? mediaQueryData})`（`test/support/pump_localized_widget.dart`，回傳 `Future<void>`，內部只做 `tester.pumpWidget`，與原寫法等價）。

- [ ] **Step 1：寫 codemod**

用 Write 工具建立 `.scratch/codemod_integration_l10n.js`（worktree 根目錄下）：

```js
// 一次性：tester.pumpWidget(MaterialApp(home: X)) → pumpLocalizedWidget(tester, X)
// 只處理「MaterialApp 只有 home（以及等於預設值的 theme）」的形態；其餘一律列入手動處理，不改。
const fs = require('fs');

const DEFAULT_THEME = 'theme: resolveThemeData(theme: AppTheme.light, isEinkMode: false)';
const IMPORT = "import '../test/support/pump_localized_widget.dart';";

function skipString(src, i) {
  const q = src[i];
  if (src.startsWith(q.repeat(3), i)) return src.indexOf(q.repeat(3), i + 3) + 2;
  let j = i + 1;
  while (j < src.length && src[j] !== q) { if (src[j] === '\\') j++; j++; }
  return j;
}
function matchParen(src, open) {
  let depth = 0;
  for (let i = open; i < src.length; i++) {
    const c = src[i];
    if (c === "'" || c === '"') { i = skipString(src, i); continue; }
    if (c === '/' && src[i + 1] === '/') { const nl = src.indexOf('\n', i); i = nl === -1 ? src.length : nl; continue; }
    if ('([{'.includes(c)) depth++;
    else if (')]}'.includes(c)) { depth--; if (depth === 0) return i; }
  }
  return -1;
}
function splitArgs(body) {
  const args = [];
  let depth = 0, start = 0;
  for (let i = 0; i < body.length; i++) {
    const c = body[i];
    if (c === "'" || c === '"') { i = skipString(body, i); continue; }
    if (c === '/' && body[i + 1] === '/') { const nl = body.indexOf('\n', i); i = nl === -1 ? body.length : nl; continue; }
    if ('([{'.includes(c)) depth++;
    else if (')]}'.includes(c)) depth--;
    else if (c === ',' && depth === 0) { args.push(body.slice(start, i)); start = i + 1; }
  }
  if (body.slice(start).trim()) args.push(body.slice(start));
  return args.map((a) => a.trim());
}

const path = require('path');
// 不帶參數時掃描 integration_test/*.dart（不依賴 shell 的命令代換，Bash／pwsh 皆可）
const targets = process.argv.slice(2).length
  ? process.argv.slice(2)
  : fs.readdirSync('integration_test').filter((f) => f.endsWith('.dart')).map((f) => path.join('integration_test', f));
const manual = [];
let total = 0;
for (const file of targets) {
  const raw = fs.readFileSync(file, 'utf8');
  const crlf = raw.includes('\r\n');
  let src = raw.replace(/\r\n/g, '\n');
  const re = /tester\.pumpWidget\(\s*(const\s+)?MaterialApp\(/g;
  let out = '', last = 0, m, changed = 0;
  while ((m = re.exec(src)) !== null) {
    const line = src.slice(0, m.index).split('\n').length;
    const pumpOpen = m.index + 'tester.pumpWidget'.length;
    const pumpClose = matchParen(src, pumpOpen);
    const appOpen = m.index + m[0].length - 1;
    const appClose = matchParen(src, appOpen);
    const between = src.slice(appClose + 1, pumpClose).trim();
    if (pumpClose < 0 || appClose < 0 || (between !== '' && between !== ',')) {
      manual.push(`${file}:${line}（pumpWidget 內不只一個 MaterialApp）`); continue;
    }
    const args = splitArgs(src.slice(appOpen + 1, appClose));
    const homeArg = args.find((a) => /^home\s*:/.test(a));
    const themeArg = args.find((a) => /^theme\s*:/.test(a));
    const others = args.filter((a) => a !== homeArg && a !== themeArg);
    if (!homeArg || others.length > 0) { manual.push(`${file}:${line}（除 home／theme 外還有：${others.map((o) => o.slice(0, 30)).join('、')}）`); continue; }
    if (themeArg && themeArg.replace(/\s+/g, ' ') !== DEFAULT_THEME) { manual.push(`${file}:${line}（theme 不是預設值：${themeArg.slice(0, 60)}）`); continue; }
    let home = homeArg.replace(/^home\s*:\s*/, '');
    if (m[1] && !/^const\s/.test(home)) home = 'const ' + home;
    const multiline = src.slice(pumpOpen, pumpClose).includes('\n');
    const lineStart = src.lastIndexOf('\n', m.index) + 1;
    const indent = /^\s*/.exec(src.slice(lineStart))[0];
    let replacement;
    if (!multiline) {
      replacement = `pumpLocalizedWidget(tester, ${home})`;
    } else {
      // home 原本比 pumpWidget( 深兩層（MaterialApp、home），新位置只深一層：續行各減 2 格縮排
      const dedented = home.split('\n').map((l, i) => (i === 0 ? l : l.replace(/^ {2}/, ''))).join('\n');
      replacement = `pumpLocalizedWidget(\n${indent}  tester,\n${indent}  ${dedented},\n${indent})`;
    }
    out += src.slice(last, m.index) + replacement;
    last = pumpClose + 1;
    changed++;
  }
  out += src.slice(last);
  if (changed && !out.includes(IMPORT)) {
    const imports = [...out.matchAll(/^import [^\n]+;\n/gm)];
    const at = imports.length ? imports[imports.length - 1].index + imports[imports.length - 1][0].length : 0;
    out = out.slice(0, at) + IMPORT + '\n' + out.slice(at);
  }
  total += changed;
  if (changed) fs.writeFileSync(file, crlf ? out.replace(/\n/g, '\r\n') : out);
  console.log(`${file}: 改寫 ${changed} 處`);
}
console.log('合計改寫 ' + total + ' 處');
if (manual.length) { console.log('需手動處理：'); manual.forEach((x) => console.log('  ' + x)); }
```

- [ ] **Step 2：先在兩個代表性檔案試跑並人工審 diff**

```bash
node ../.scratch/codemod_integration_l10n.js integration_test/smoke_test.dart integration_test/fxl_bookmarks_test.dart
git diff integration_test/smoke_test.dart integration_test/fxl_bookmarks_test.dart
```

審查要點：`smoke_test.dart`（含 `theme: resolveThemeData(…)` 與 `const MaterialApp`）— 結果應為 `pumpLocalizedWidget(tester, …)`，**`theme:` 已消失**且語意等價（預設值相同）；`fxl_bookmarks_test.dart`（多行、含 `isFixedLayout: true`）— 縮排正確、`await` 保留、`home` 內容原樣。兩個檔案各自多一行 `import '../test/support/pump_localized_widget.dart';`。**diff 不對就停下修腳本，不要硬往下跑。**

- [ ] **Step 3：全量改寫其餘檔案**

```bash
node ../.scratch/codemod_integration_l10n.js
```

不帶參數時腳本掃描 `integration_test/*.dart` 全部 40 個檔案（不含 `MaterialApp(` 的檔案與 Step 2 已改過的兩個檔案顯示 0 處，也不會被改寫）。預期：每檔列出改寫處數，合計加上 Step 2 的處數 = 104；「需手動處理」清單為空。若清單非空，逐處手動依同樣規則改（把 `MaterialApp(home: X)` 換成 `pumpLocalizedWidget(tester, X)`，theme 非預設值時保留成 `pumpLocalizedWidget(tester, X, theme: AppTheme.…, isEinkMode: …)` 並在 `epic.md` 記錄該處）。

- [ ] **Step 4：驗證沒有殘留**

```bash
grep -n "MaterialApp(" integration_test/*.dart | grep -v "^integration_test/[a-z_]*\.dart:[0-9]*:\s*//" ; echo "(上面為空表示 MaterialApp( 已全數移除；註解內的字樣可忽略)"
grep -c "pumpLocalizedWidget(tester" integration_test/*.dart | awk -F: '{s+=$2} END{print "pumpLocalizedWidget 共", s, "處"}'
grep -n "tester.pumpWidget(" integration_test/*.dart | head -3; echo "(上面為空表示沒有殘留的裸 pumpWidget)"
```

預期：`MaterialApp(` 無殘留（`flutter_test_config.dart` 的註解文字不含 `MaterialApp(`）；`pumpLocalizedWidget` 共 104 處；沒有殘留的 `tester.pumpWidget(`。

- [ ] **Step 5：用 analyzer 收尾**

```bash
flutter analyze 2>&1 | tail -20
```

預期可能出現 `unused_import`（`app_theme.dart`、`app_theme_data.dart`，原本只為了 `resolveThemeData`／`AppTheme`）。逐一刪除報告中的未使用 import，直到 `No issues found!`。**只刪 analyzer 明確標示未使用的 import**，不要順手整理其他。

- [ ] **Step 6：檢查腳本對 integration_test 通過**

```bash
node tool/check_l10n_hardcoded_strings.js --integration-dir integration_test; echo "exit=$?"
```

預期：`PASS：掃描 40 個 integration 測試檔，所有 MaterialApp 皆帶 locale／localizationsDelegates／supportedLocales`，`exit=0`（40 = `integration_test/` 全部檔案，含不含 `MaterialApp` 的 7 個）。

- [ ] **Step 7：提交**

```bash
git add integration_test
git status --short | grep -v "^M \|scratch"
git commit -m "fix(epic-54): integration_test 104 處 MaterialApp 改用 pumpLocalizedWidget（Issue 15 Task 2）

33 個檔案缺 locale／localizationsDelegates／supportedLocales，ReaderScreen 的
AppLocalizations.of(context)! 取到 null；改用 epic-45 的標準包裝器。

Co-Authored-By: Claude Sonnet 5.5 <noreply@anthropic.com>"
```

---

### Task 3：守衛納入預設掃描、更新文件

**Files：**
- Modify：`app/tool/check_l10n_hardcoded_strings.js`
- Modify：`app/tool/test_check_l10n_hardcoded_strings.mjs`
- Modify：`app/tool/README.md`

- [ ] **Step 1：寫失敗測試（無旗標預設含 integration_test）**

預設目錄是 `app/lib`、`app/test`、`app/integration_test`（以 `__dirname/..` 解析），所以「無旗標預設」是對**真實**專案目錄的整合檢查。在 `test_check_l10n_hardcoded_strings.mjs` 的 `try { … }` 區塊之後、`console.log('check_l10n_hardcoded_strings：全部測試通過')` 之前，新增：

```js

// ---- 無旗標預設：lib、test、integration_test 三項都檢查（epic-54 Issue 15）----
const defaultRun = spawnSync('node', [SCRIPT], { encoding: 'utf8' })
assert.equal(defaultRun.status, 0, defaultRun.stderr)
assert.match(defaultRun.stdout, /個檔案，未發現/)
assert.match(defaultRun.stdout, /個測試檔，所有/)
assert.match(defaultRun.stdout, /個 integration 測試檔，所有/)
```

- [ ] **Step 2：跑測試確認失敗**

```bash
node tool/test_check_l10n_hardcoded_strings.mjs
```

預期：失敗於 `個 integration 測試檔，所有`（預設尚未掃 integration）。

- [ ] **Step 3：實作**

在 `main` 中把

```js
  // Task 3 之前，無旗標的預設不含 integration_test（目前還有 104 處待修）
  const runIntegration = integrationOpt !== undefined;
```

改為

```js
  const runIntegration = integrationOpt !== undefined || !anyFlag;
```

並把

```js
  if (runIntegration) exit = Math.max(exit, checkTest(integrationOpt, 'integration_test'));
```

改為

```js
  if (runIntegration) {
    exit = Math.max(
      exit,
      checkTest(integrationOpt ?? path.resolve(__dirname, '..', 'integration_test'), 'integration_test'),
    );
  }
```

同時更新檔案頂端說明（第 6 行附近「掃描 app/test/**/*.dart」）：補上「與 `app/integration_test/**/*.dart`」。

- [ ] **Step 4：更新 `app/tool/README.md`**

把 `check_l10n_hardcoded_strings.js` 段落的「兩項檢查」改為「三項檢查」，新增第 3 點：

```md
3. **integration 測試端稽核**：掃描 `app/integration_test/**/*.dart`，規則同第 2 項，但**沒有白名單**
   （integration 測試沒有刻意保留裸 `MaterialApp` 的案例）。integration 測試在真機上執行，缺
   `localizationsDelegates` 時 `AppLocalizations.of(context)!` 會 Null check 崩潰；這批測試曾因為
   這項檢查只涵蓋 `app/test/` 而長期無聲壞掉（`epic-54` Issue 15）。一律用
   `pumpLocalizedWidget(tester, home)`（`import '../test/support/pump_localized_widget.dart'`）。
```

並在指令範例區補上 `--integration-dir <目錄>` 一行，結束碼與輸出範例補 `integration_test/<檔案>:<行號>  缺少 locale…`。

- [ ] **Step 5：跑測試與全部檢查**

```bash
node tool/test_check_l10n_hardcoded_strings.mjs
node tool/check_l10n_hardcoded_strings.js
```

預期：單元測試通過；檢查腳本輸出**三行 PASS**（lib、test、integration）。

- [ ] **Step 6：提交**

```bash
git add tool/check_l10n_hardcoded_strings.js tool/test_check_l10n_hardcoded_strings.mjs tool/README.md
git commit -m "feat(epic-54): l10n 檢查腳本預設納入 integration_test（Issue 15 Task 3）

Co-Authored-By: Claude Sonnet 5.5 <noreply@anthropic.com>"
```

---

### Task 4：真機逐檔驗證與分類（不改程式，除 C 類）

**Files：** 僅在判定為 C 類時修改 `lib/` 或測試；其餘只更新文件。

- [ ] **Step 1：向使用者確認裝置（必做，不可略過）**

詢問使用者：目標裝置是哪一台（`adb devices -l` 的序號）、是否接受 Flutter 在簽章／版本不符時解除安裝該裝置上既有的 `cc.ugotit.elinkbook` 並清除資料。**得到明確回答前不得執行任何 `flutter test integration_test/…`。** 確認裝置穩定：

```bash
"$LOCALAPPDATA/Android/Sdk/platform-tools/adb.exe" devices -l
```

必須看到序號後面標示 `device`（不是空白、`unauthorized`、`offline`）。

- [ ] **Step 2：建立執行腳本並逐檔執行**

用 Write 工具建立 `.scratch/run_integration.sh`：

```bash
#!/usr/bin/env bash
# 用法：bash ../.scratch/run_integration.sh <device-id>   （在 app/ 目錄下執行）
DEVICE="$1"
OUT=../.scratch/it_results
mkdir -p "$OUT"
: > "$OUT/summary.txt"
for f in $(grep -l "pumpLocalizedWidget" integration_test/*.dart | sort); do
  name=$(basename "$f" .dart)
  [ "$name" = "manual_import_acceptance_test" ] && continue   # 人工驗收，不跑
  echo "=== $name ===" >> "$OUT/summary.txt"
  flutter test "$f" -d "$DEVICE" > "$OUT/$name.log" 2>&1
  echo "exit=$?" >> "$OUT/summary.txt"
  grep -E "All tests passed|Some tests failed|\+[0-9]+ -[0-9]+|Build failed|not found|log reader stopped|INSTALL_FAILED" "$OUT/$name.log" | tail -n 3 | cut -c1-160 >> "$OUT/summary.txt"
done
echo DONE >> "$OUT/summary.txt"
```

腳本只跑含 `pumpLocalizedWidget` 的檔案：33 個含 `MaterialApp` 的檔案扣掉 `manual_import_acceptance_test` = 32 個。`integration_test/` 其餘 7 個檔案不含 `MaterialApp`，不受本 Issue 影響也不在腳本內：`flutter_test_config.dart`（全域設定檔），以及 6 個無 UI 的測試（`book_metadata_channel_test`、`content_indexing_end_to_end_test`、`foliate_content_indexer_test`、`pdf_content_uri_metadata_test`、`sync_account_test`、`sync_engine_test`）；40 = 33 + 7。

在 `app/` 目錄下以背景方式執行（預估 40 分鐘以上，**期間手機保持接線、螢幕亮著**）：

```bash
bash ../.scratch/run_integration.sh <device-id>
```

- [ ] **Step 3：先排除環境失敗**

```bash
grep -l "not found\|log reader stopped\|INSTALL_FAILED\|Unable to start the app" ../.scratch/it_results/*.log
```

列出的檔案屬於「環境失敗」（掉線、安裝失敗），**不分類**，確認 `adb devices -l` 穩定後單獨重跑這些檔案，直到沒有環境失敗為止。

- [ ] **Step 4：對每個失敗的檔案分類**

對 `summary.txt` 中 `exit` 非 0 的每個檔案，讀其 `.log` 的第一個例外（`grep -n "EXCEPTION CAUGHT\|Expected\|Actual\|The following"`），依下表分類，並記錄「檔案、測試名、例外摘要」：

| 類別 | 判斷 | 處理 |
|---|---|---|
| A. 仍是多語系 null check | 例外仍是 `AppLocalizations.of(context)!`／`Null check` 且發生在 `_buildBody` 或其他 `AppLocalizations.of(context)!` | 本 Issue 的缺陷沒修乾淨：回 Task 2 檢查該檔案的 `pumpLocalizedWidget` 是否真的被使用（可能有未涵蓋的 `MaterialApp` 來源，例如 `ReaderScreen` 之外自行建構的 Navigator 路由） |
| B. 與多語系、Issue 11 都無關的既存失敗 | 例外與依賴組、`AppLocalizations` 都無關（逾時、WebView、檔案權限、素材缺失等），且**在 base 上同機同樣失敗**（見下方對照規則） | **不修**，記進 `epic.md`，建議另立工單 |
| C. Issue 11 造成的回歸 | 例外與 `ReaderFeatureDependencies`、`StateError('ReaderFeatureDependencies 缺少 …')`、`isFixedLayout`／`libraryRepository` 偵測相關，**且在 base 上通過** | **本 Issue 修**：先寫一個能重現的失敗測試（單元測試優先），再修 `lib/` |
| D. 斷言與 locale 不符 | 失敗的 `find.text('…')` 文字與正體中文介面不符（例如斷言英文） | 不自行改文字；記錄檔案與斷言，交使用者決定 |
| E. 通過 | `+N: All tests passed!` | 無 |

**base 對照規則（B／C 的判定依據，不得以推測定案）：** 判定 B 或 C 之前，必須在 Issue 11 之前的 `main`（`bdff826c`）、**同一台裝置**上執行同一個測試檔。base 上這些測試因缺 delegates 會先卡在 null check，所以對照前須先對該檔案套用本 Task 2 的 codemod（只改多語系設定），才看得到「沒有 Issue 11 時的真實結果」。標準步驟如下；兩個 worktree 都是 `.worktrees/` 底下的兄弟目錄，所以從 base worktree 的 `app/` 指向 Issue 15 worktree 的相對路徑是 `../../epic-54-issue-15-integration-l10n/…`（**不是** `../../.worktrees/…`）：

```bash
# 1. 在主 repo 根目錄建立 base 對照專用 worktree（不要動主工作區與 Issue 15 worktree）
git worktree add .worktrees/base-bdff826c bdff826c
# 2. 在該 worktree 的 app/ 取依賴，並對目標檔案套用本 Issue 的 codemod
( cd .worktrees/base-bdff826c/app && flutter pub get && node ../../epic-54-issue-15-integration-l10n/.scratch/codemod_integration_l10n.js integration_test/<目標測試檔>.dart )
# 3. 同一台裝置執行對照，輸出存檔供記錄
( cd .worktrees/base-bdff826c/app && flutter test integration_test/<目標測試檔>.dart -d <device-id> > ../../epic-54-issue-15-integration-l10n/.scratch/it_results/base_<目標測試檔>.log 2>&1 )
# 4. 記錄結果後清理（--force 會丟棄該 worktree 內被 codemod 改過的檔案，這是預期的）
git worktree remove --force .worktrees/base-bdff826c
```

對照結果必須寫進記錄。

- [ ] **Step 5：確認先前 5 個檔案不再卡在 null check**

```bash
for t in fxl_bookmarks_test epub_toc_test reading_position_test foliate_cbz_test reader_screen_test; do echo "$t: $(grep -c 'Null check operator' ../.scratch/it_results/$t.log) 次 null check"; done
```

預期：全部為 `0 次`（不一定通過，但不得再出現這個例外）。

- [ ] **Step 6：記錄結果**

在 `docs/epics/epic-54-architecture-optimization/epic.md` 新增「Issue 15 真機驗證結果」段落：裝置、日期、32 個檔案各自的 `+N -M`、分類表（每個失敗：檔案、測試名、類別、例外摘要、base 對照結果）、被判為 B 的清單（建議另立工單）、被判為 D 的清單（待使用者決定）。C 類若有，另列修復 commit。

- [ ] **Step 7：提交文件（以及 C 類修復，若有）**

```bash
git add docs/epics/epic-54-architecture-optimization/epic.md
git commit -m "docs(epic-54): Issue 15 真機驗證結果與失敗分類

Co-Authored-By: Claude Sonnet 5.5 <noreply@anthropic.com>"
```

---

### Task 5：收尾、完整測試、更新狀態

**Files：** Modify：`docs/epics/epic-54-architecture-optimization/{epic.md,issues.md}`、`docs/epics.md`

- [ ] **Step 1：完整測試（只在此處跑一次）**

```bash
flutter analyze
node tool/check_l10n_hardcoded_strings.js
node tool/test_check_l10n_hardcoded_strings.mjs
flutter test
```

`flutter test` 以 `run_in_background` 執行（約 6 分鐘），**必須在 `app/` 目錄下**。預期：`flutter analyze` 乾淨；檢查腳本三行 PASS；單元測試通過；`flutter test` 只允許出現已知的既存失敗 `pdf_reader_view_filters_test`（bold overlay 多頁案例，已在乾淨 `main` 確認），其餘 0 失敗。本 Issue 只動 `integration_test/` 與 `tool/`，不應影響 `flutter test` 結果；若出現新失敗，先查明原因。

- [ ] **Step 2：更新狀態**

`issues.md` Issue 15 狀態改為「🟡 實作完成，待程式審查」；`docs/epics.md` 備註同步；`epic.md` 記錄最終驗證數字（分支名、`flutter analyze` 結果、檢查腳本三行 PASS、`flutter test` 通過／略過／失敗數）。

- [ ] **Step 3：提交並交給程式審查**

```bash
git add docs
git commit -m "docs(epic-54): Issue 15 實作完成，待程式審查

Co-Authored-By: Claude Sonnet 5.5 <noreply@anthropic.com>"
```

審查者先產出報告，存於 `docs/epics/epic-54-architecture-optimization/reviews/review-code-issue-15.md`（gitignore），不得直接改程式；審查完成後由人類決定發 PR 與合併。

---

## Self-Review

**Spec 對照（Issue 15 的工單文字）：** 33 檔／104 處改用帶多語系的包裝（Task 2）；檢查腳本擴大到 `integration_test/` 作為回歸守衛（Task 1、3）；真機驗證並分類補完後暴露的其他失敗（Task 4）；依賴 Issue 11 合併（已合併，PR #327）；補完後可能暴露其他失敗的風險由前提 3 與 Task 4 分類表承接。

**佔位符掃描：** codemod 與檢查腳本的修改都給了完整程式碼；Task 3 Step 4 的 README 文字給了完整新增內容；Task 4 的分類表是判斷規則，不是程式碼佔位。

**型別／命名一致：** `scanTestDir(testDir, allowMap)`、`checkTest(testDir, label)`、旗標 `--integration-dir`、label 字串 `'integration_test'` 在 Task 1、3 一致；`pumpLocalizedWidget(tester, home)` 簽名與 `test/support/pump_localized_widget.dart` 現況一致；codemod 的 `DEFAULT_THEME` 與 4 處實際出現的字串（`resolveThemeData(theme: AppTheme.light, isEinkMode: false)`）一致。

**Review Focus：** 6 條皆有對應（1→Task 2 Step 2/4；2→Task 1 Step 1 的空目錄；3→Task 1 Step 1 的 `bad_test.dart`／Task 3 Step 1；4→Task 4 Step 4 的 A/B/C 與 base 對照規則；5→Task 4 的 D 類；6→Task 4 Step 3）。

**已知風險：** codemod 的縮排處理（續行減 2 格）只在「`pumpWidget(` 換行＋`MaterialApp(` 換行＋`home:` 換行」的標準三層形態下正確，Task 2 Step 2 的人工審 diff 是煞車；真機驗證耗時長且依賴 USB 連線穩定（Issue 11 驗證時中斷過三次）；補完 delegates 後的失敗數量無法預知，可能需要拆出多張後續工單。
