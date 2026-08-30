# Epic 32 Issue 1：修復 ES 相容性掃描工具＋確認基準線 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 修復 `app/tool/check_foliate_es_compat.js` 內寫死的過時 Dart 檔案路徑，讓 Issue 2 需要的 ES 相容性掃描能正常執行；同時確認目前 repo 狀態的 `flutter analyze`／`flutter test` 基準線乾淨，供 Issue 2/3 事後比對零回歸。

**Architecture:** 單純的字串修復，不改動任何邏輯——`check_foliate_es_compat.js` 是純 Node.js 靜態掃描腳本，這次只改它讀取 Polyfill 來源的路徑字串（含相關的註解與錯誤訊息文字），使其對齊 `foliate_epub_reader_view.dart` 已改名為 `foliate_reader_view.dart` 的現況（ADR 0017／0023）。

**Tech Stack:** Node.js（純腳本，不需要 build）、Flutter（`flutter analyze`／`flutter test`）。

**Spec:** `docs/epics/epic-32-foliate-js-paginator-sync/design.md`（「先決條件：修復 ES 相容性掃描工具」）；工單描述見 `docs/epics/epic-32-foliate-js-paginator-sync/issues.md` Issue 1。

## Global Constraints

- 只改路徑字串，不動 `extractPolyfillSource()` 的正規表示式邏輯或任何掃描規則——已確認 `foliate_reader_view.dart` 第 68 行仍是 `const _esCompatPolyfillJs = '''` 這個三引號字串常數宣告，跟舊檔名時期完全相同的宣告方式，邏輯不需要變。
- 本工單**不**替換 `paginator.js`（那是 Issue 2 的事），這裡的 ES 掃描是針對**目前尚未同步**的 `paginator.js` 執行，純粹確認工具本身能正常跑，不是驗證上游新版行為。
- 不修改任何 vendored 檔案（`app/android/app/src/main/assets/foliate/` 下的檔案），符合 ADR 0011。

---

### Task 1: 修復路徑並確認基準線

**Files:**
- Modify: `app/tool/check_foliate_es_compat.js`（4 處字串，第 5／39／203／275 行）

**Interfaces:** 無（純腳本工具，無對外介面變動）。

- [x] **Step 1: 修復第 5 行的文件註解**

`app/tool/check_foliate_es_compat.js` 第 5 行目前內容：

```js
 * 而目前 lib/reader/foliate_epub_reader_view.dart 的 _esCompatPolyfillJs
```

改為：

```js
 * 而目前 lib/reader/foliate_reader_view.dart 的 _esCompatPolyfillJs
```

- [x] **Step 2: 修復第 39 行的 `POLYFILL_SOURCE_FILE` 路徑常數（唯一實際影響執行結果的一行）**

第 37-40 行目前內容：

```js
const POLYFILL_SOURCE_FILE = path.join(
  REPO_ROOT,
  'app', 'lib', 'reader', 'foliate_epub_reader_view.dart',
);
```

改為：

```js
const POLYFILL_SOURCE_FILE = path.join(
  REPO_ROOT,
  'app', 'lib', 'reader', 'foliate_reader_view.dart',
);
```

- [x] **Step 3: 修復第 203 行的錯誤訊息**

第 201-206 行目前內容：

```js
  if (!match) {
    throw new Error(
      '在 foliate_epub_reader_view.dart 找不到 _esCompatPolyfillJs 常數' +
      '——是不是被改名或搬移了？請同步更新這支腳本的 POLYFILL_SOURCE_FILE' +
      '/extractPolyfillSource() 邏輯。',
    );
  }
```

改為：

```js
  if (!match) {
    throw new Error(
      '在 foliate_reader_view.dart 找不到 _esCompatPolyfillJs 常數' +
      '——是不是被改名或搬移了？請同步更新這支腳本的 POLYFILL_SOURCE_FILE' +
      '/extractPolyfillSource() 邏輯。',
    );
  }
```

- [x] **Step 4: 修復第 275 行的錯誤訊息**

第 274-279 行目前內容：

```js
  console.error(
    '請至 app/lib/reader/foliate_epub_reader_view.dart 的 ' +
    '_esCompatPolyfillJs 補上對應的 polyfill（僅在缺席時才定義，比照既有' +
    '寫法），並用 Node.js + @xmldom/xmldom 對照未經修改的實際 epub.js 驗證' +
    '過缺席時會拋出例外、補上後可修復，再重新執行這支腳本確認乾淨。',
  );
```

改為：

```js
  console.error(
    '請至 app/lib/reader/foliate_reader_view.dart 的 ' +
    '_esCompatPolyfillJs 補上對應的 polyfill（僅在缺席時才定義，比照既有' +
    '寫法），並用 Node.js + @xmldom/xmldom 對照未經修改的實際 epub.js 驗證' +
    '過缺席時會拋出例外、補上後可修復，再重新執行這支腳本確認乾淨。',
  );
```

- [x] **Step 5: 執行掃描工具，確認能正常執行**

```bash
node app/tool/check_foliate_es_compat.js
```

Expected: 結束碼 `0`，不拋出 `ENOENT` 例外（可用 `echo $?` 確認，PowerShell 用 `$LASTEXITCODE`）。若結束碼非 `0` 但也不是例外崩潰，代表掃描到目前 `paginator.js`（尚未同步前的舊版本）有未防護的 API 用法——這種情況記錄下來即可，**不在本工單範圍內修復**（那屬於 Issue 2 換上新版 `paginator.js` 之後才需要處理的事；若舊版本本身就有缺口，屬於既有技術債，一併記錄在 Issue 1 完成摘要供之後參考，不阻塞本工單）。

- [x] **Step 6: 執行 `flutter analyze`，確認基準線乾淨**

```bash
cd app && flutter analyze
```

Expected: 「No issues found!」。

- [x] **Step 7: 執行 `flutter test`，記錄基準線測試總數**

```bash
flutter test
```

Expected: 全數通過，記下總測試數（例如「XXXX tests passed」字樣），供 Issue 2/3 完成後比對確認零回歸。

- [x] **Step 8: Commit**

```bash
git add app/tool/check_foliate_es_compat.js
git commit -m "fix(epic-32): 修復 check_foliate_es_compat.js 過時的 Dart 檔案路徑參照

foliate_epub_reader_view.dart 已在 ADR 0017/0023 統一 Foliate 格式時
改名為 foliate_reader_view.dart，掃描工具寫死的舊路徑導致執行時直接
拋出 ENOENT，Epic 32 Issue 2 需要的 ES 相容性掃描這步因此跑不動。"
```

- [x] **Step 9: 更新工單狀態**

在 `docs/epics/epic-32-foliate-js-paginator-sync/issues.md` Issue 1 的 `**Status:**` 那一行，改為記錄已完成，並補一段簡短總結：ES 掃描結束碼（Step 5 結果）、`flutter test` 測試總數（Step 7 結果）、若 Step 5 掃描到既有舊版 `paginator.js` 本身就有未防護 API（若有）的記錄。
