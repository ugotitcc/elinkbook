# Issue 7：線上查詞（萌典）、同意對話框、隱私更新 實作計畫

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 使用者在字典設定同意並開啟後，查中文詞時多一個「萌典」分段；未同意時完全不發網路請求；隱私頁同步更新。

**Architecture:** 新增 `MoedictProvider`（`OnlineDictionaryProvider` 的第一個實作）與 `DictionarySettingsRepository`（同意狀態，`shared_preferences`）。`DictionaryService` 注入這兩者，查詢時把線上分段排在本機分段之後，並與本機查詢同時進行。設定畫面補線上區塊，同意走獨立對話框。查詢面板只補兩則線上失敗訊息。

**Tech Stack:** Flutter、`http`（既有，`MockClient` 測試）、`connectivity_plus`（既有）、`shared_preferences`（既有）、`clock`（既有）、`gen-l10n`（四份 ARB）。不新增套件，不動 `pubspec.yaml`。

**Spec:** `docs/epics/epic-63-dictionary-lookup/spec.md` §3.2（`ProviderOutcome`）、§3.3（介面）、§3.4（查詢流程、線上條件）、§3.7（線上查詢區塊）；§9 驗收 7、8、9、10、15；萌典事實與隱私規則見 `docs/research/dictionary/DICTIONARY_FORMATS_AND_LICENSES.md` §6、§7；`issues.md` 的 Issue 7；上游延後項見 `plan-issue-4.md`、`plan-issue-5.md`、`plan-issue-6a.md` 尾端「交給後續 Issue」。

## Global Constraints

- 不新增套件；不動 `pubspec.yaml`、主資料庫（`version: 28`）、`main.js`、`sync_table_specs.dart`、`dictionary.db` 結構。
- 線上查詞預設關閉。未同意時，**不發出任何網路請求**。
- 請求只含詞：網址 `https://www.moedict.tw/uni/{詞}`，不帶 cookie、不帶自訂標頭、不帶書名／前後文／位置／裝置識別。
- 只送使用者選取、經 `normalizeLookupSelection` 去頭尾標點後的字串；不送候選詞（驗收 15）。
- 只接受 `https`。`AndroidManifest.xml` 有 `usesCleartextTraffic="true"`，所以 Dart 端要擋，重導向也不跟。
- 逾時 5 秒。萌典結果原文顯示，不做簡繁轉換、不刪減釋義（CC BY-ND 3.0 TW）。
- 字串一律走 `AppLocalizations`；新字串同時加進四份 ARB（`app_zh_TW.arb` 為範本，附 `@key` 說明）。
- 畫面不加 `AnimatedXxx`；E-Ink 用邊框不用陰影。
- 錯誤訊息三段式：發生什麼、為什麼、使用者要做什麼。
- 所有文件與註解用正體中文；commit 訊息不加 `Co-Authored-By`。
- 每個 Task 只跑觸及的測試檔；完整 `flutter test` 只在最後一個 Task 跑一次。

## Review Focus

1. **未同意零請求**：未同意時，查純中文、中英混合兩種選字，`MockClient` 呼叫次數都是 0（Task 3）。
2. **撤回同意立即生效**：查完一次後撤回同意，下一次查詢不再送請求。服務不可快取同意狀態（Task 3）。
3. **離線不拖慢本機結果**：離線時線上分段立刻回 `failed`（`offline`），不等 5 秒；本機結果照常（Task 3）。
4. **詞含特殊字元與非 `https` 重導向**：詞含 `/`、`?`、`#` 時網址仍只有一個路徑段；回 301／302 且 `Location` 為 `http://` 時不跟、回 `failed`（Task 1）。
5. **200 但不是萌典格式**：HTML 錯誤頁、空物件、`heteronyms` 為空，都回 `failed`（`unparseable`），不當掉（Task 1）。

## 已決定事項（spec 沒寫清楚，本計畫的選擇）

- **同意與開啟合成一個狀態。** spec §3.4 寫「已同意且已開啟」兩個條件。本計畫只存一個值 `onlineConsentAt`（`DateTime?`）：有值＝已同意且開啟；`null`＝關閉。開關打開要先同意；開關關閉就清掉，下次打開要重新同意。原因：隱私上關閉等於撤回，沒有「同意了但關著」這種狀態需要保存。
- **送出的字串**是 `NormalizedSelection.text`（去頭尾標點、漢字間空白已移除），不是選取的原始字元。`「相濡以沫」` 送 `相濡以沫`。萌典對帶標點的詞回 404，送原始字元沒有好處。
- **線上分段何時出現：** 選字類型為 CJK 或混合（spec §3.4）。純拉丁字母的選字不出現線上分段，也不出現 `skipped`。
- **線上條件不滿足的三種結果：** 未同意→`skipped`（面板顯示「線上查詢已關閉」＋設定入口）；離線→`failed`／`offline`；請求出錯→`failed`／其他錯誤碼。
- **本機與線上同時進行。** `lookup` 先啟動線上 Future，再逐本查本機，最後一起等。離線檢查用 `connectivity_plus`，只擋「完全沒有連線」，其餘交給 5 秒逾時。
- **萌典詞條對應：** 每個 `heteronym` 一筆 `DictionaryEntry`（`sourceId = 'moedict'`、`headword = title`、`bodyKind = plainText`）。`pronunciation` 為 `bopomofo` 與 `pinyin` 各自做空白正規化（`trim().replaceAll(RegExp(r'\s+'), ' ')`，保留音節間的單一空格），兩者都有時以 ` ／ ` 相連；只有一個就只放一個；都沒有或正規化後為空字串時為 `null`。萌典拼音已是聲調符號，`pinyinToneMarks` 對它是原樣通過。`body` 每個 `definitions` 項目一段：`type`（有值時）加兩個半形空白再接 `def`，其後依序為每個 `example` 字串、每個 `quote` 字串，各一行、縮排兩個半形空白（先例句、後書證，與萌典 JSON 欄位順序一致）；定義超過一個時前綴 `1. `、`2. `。`def` 文字不改動。
- **來源標示**是固定常數字串，放在 `MoedictProvider.attribution`，不走 l10n（法定標示，各語系一致）；設定畫面也引用同一個常數。
- **不做快取與重試。** 研究文件建議快取與重試上限；Phase 1 每次選字最多一次請求，沒有迴圈風險。列入「交給後續」。
- **`DictionarySettingsRepository` 放進 `ReaderFeatureDependencies`**（`required`，ADR 0037），設定畫面的 `settings` 參數也改為 `required`，既有呼叫端與測試一併更新。

## l10n 鍵名與文案（四份 ARB 統一）

| 鍵名 | zh-TW 文案 |
|---|---|
| `dictionaryOnlineSectionTitle` | 線上查詞（萌典） |
| `dictionaryOnlineDescription` | 開啟後，查中文詞時會多一個「萌典」分段。只會把你選取的那個詞送到 www.moedict.tw。不會送出書名、前後文、位置或裝置識別。預設關閉。 |
| `dictionaryOnlineStatusOff` | 尚未同意 |
| `dictionaryOnlineStatusOn(date)` | 已於 {date} 同意（`date` 為 `YYYY-MM-DD`） |
| `dictionaryOnlineSaveFailed` | 無法儲存線上查詞設定：裝置儲存空間寫入失敗。請確認剩餘空間後再試一次。 |
| `dictionaryOnlineConsentTitle` | 開啟線上查詞？ |
| `dictionaryOnlineConsentBody` | 會送出：你選取的那個詞。\n送到：萌典（www.moedict.tw），由第三方營運。\n不會送出：書名、前後文、位置、裝置識別。\n你可以隨時在「設定 → 閱讀 → 字典」關閉。 |
| `dictionaryOnlineConsentAgree` | 同意並開啟 |
| `dictionaryOnlineConsentCancel` | 取消 |
| `dictionaryLookupOnlineFailed` | 萌典暫時查不到：連線逾時或服務沒有回應。請確認網路後再查一次，或改用本機字典。 |
| `dictionaryLookupOnlineUnparseable` | 無法解析萌典的回應：回傳的格式本 App 看不懂。請稍後再試；一直發生時請到意見反應回報。 |

既有的 `dictionaryLookupOnlineDisabled`（線上查詢已關閉）與 `dictionaryLookupOpenSettings` 沿用。

## 檔案結構

| 動作 | 路徑 | 責任 |
|---|---|---|
| 修改 | `app/lib/dictionary/providers/online_dictionary_provider.dart` | 介面補 `displayName` |
| 建立 | `app/lib/dictionary/providers/moedict_provider.dart` | 萌典請求、解析、錯誤分類 |
| 建立 | `app/lib/dictionary/dictionary_settings_repository.dart` | 同意狀態的讀寫 |
| 修改 | `app/lib/dictionary/dictionary_service.dart` | 線上分段 |
| 建立 | `app/lib/screens/dictionary_online_consent_dialog.dart` | 同意對話框 |
| 修改 | `app/lib/screens/dictionary_settings_screen.dart` | 線上區塊 |
| 修改 | `app/lib/screens/widgets/dictionary_lookup_sheet.dart` | 依 `errorCode` 選失敗訊息 |
| 修改 | `app/lib/screens/reader_feature_dependencies.dart`、`app/lib/main.dart`、`app/lib/screens/settings_scaffold.dart`、`app/lib/screens/reader_screen.dart` | 注入與接線 |
| 修改 | `app/lib/l10n/app_{zh_TW,zh_CN,zh,en}.arb` | 文案 |
| 修改 | `site/privacy.html` | 隱私更新 |
| 建立 | `app/test/support/fake_dictionary_settings_repository.dart` | 記憶體版 repository |
| 建立／修改 | `app/test/dictionary/{moedict_provider,dictionary_settings_repository,dictionary_service}_test.dart`、`app/test/screens/{dictionary_online_consent_dialog,dictionary_settings_screen}_test.dart`、`app/test/screens/widgets/dictionary_lookup_sheet_test.dart`、`app/test/support/fake_reader_feature_dependencies.dart` | 測試 |

---

### Task 1：`MoedictProvider`

**Files:**
- Modify: `app/lib/dictionary/providers/online_dictionary_provider.dart`
- Create: `app/lib/dictionary/providers/moedict_provider.dart`
- Test: `app/test/dictionary/moedict_provider_test.dart`

**Interfaces:**
- Consumes: `LookupRequest(word)`、`ProviderOutcome`、`OutcomeStatus`、`DictionaryEntry`、`EntryBodyKind`。
- Produces:
  - `OnlineDictionaryProvider` 新增 `String get displayName;`
  - `class MoedictProvider implements OnlineDictionaryProvider`
    - `MoedictProvider({required http.Client client, Uri? baseUri, Duration timeout = const Duration(seconds: 5)})`；`baseUri` 預設 `https://www.moedict.tw/uni`。
    - `static const String attribution = '資料來源：教育部《重編國語辭典修訂本》（CC BY-ND 3.0 TW），經由萌典提供';`
    - `id == 'moedict'`、`displayName == '萌典'`。
  - 錯誤碼（`ProviderOutcome.errorCode`，Task 3、4 依賴）：`insecureUrl`、`timeout`、`network`、`httpError`、`unparseable`。

- [ ] **Step 1: 寫失敗測試** `moedict_provider_test.dart`，用 `MockClient`。測試名稱與斷言：
  - `請求網址只含詞`：查 `相濡以沫`，`request.url.toString() == 'https://www.moedict.tw/uni/%E7%9B%B8%E6%BF%A1%E4%BB%A5%E6%B2%AB'`；`request.method == 'GET'`；`request.headers` 不含 `cookie`、`authorization`（大小寫不拘）。
  - `詞含 / ? # 時仍是單一路徑段`：查 `a/b?c#d 手機`，`request.url.pathSegments` 長度 2，第二段解碼後等於原字串；`request.url.query` 與 `fragment` 皆為空。
  - `拒絕非 https`：`baseUri: Uri.parse('http://www.moedict.tw/uni')`，結果 `failed`／`insecureUrl`，`MockClient` 呼叫次數 0。
  - `不跟重導向`：回 301，`location: http://evil.example/`，結果 `failed`／`httpError`，呼叫次數 1；另外斷言送出的 `Request.followRedirects == false`。
  - `逾時`：handler 回傳永不完成的 Future，`timeout: Duration(milliseconds: 20)`，結果 `failed`／`timeout`。
  - `連線例外`：handler 丟 `http.ClientException('x')`，結果 `failed`／`network`。
  - `404 是查無`：結果 `notFound`，`entries` 為空。
  - `500 與 429`：結果 `failed`／`httpError`。
  - `正常回應`：用 `相濡以沫` 的真實形狀（`title`、一個 `heteronyms` 項目含 `bopomofo`、`pinyin`、一個只有 `def` 的 `definitions`）。斷言：`found`、一筆 entry、`headword == '相濡以沫'`、`pronunciation == 'ㄒㄧㄤ ㄖㄨˊ ㄧˇ ㄇㄛˋ ／ xiāng rú yǐ mò'`、`body == def 原文`（逐字相等）、`bodyKind == plainText`、`outcome.attribution == MoedictProvider.attribution`。
  - `多定義與例句`：兩個定義，第一個有 `type: '名'`、`example: ['例一']`；斷言 `body == '1. 名  def1\n  例一\n2. def2'`（`名` 與 `def1` 之間是兩個半形空白）。
  - `例句與書證並存`：單一定義同時有 `example: ['例一']`、`quote: ['書證一']`；斷言 `body == '名  def1\n  例一\n  書證一'`（只有一個定義時不加編號；先例句、後書證）。
  - `缺欄位不當掉`：沒有 `title`（headword 退回 `request.word`）、沒有 `pinyin`／`bopomofo`（`pronunciation == null`）、定義裡 `example` 是數字（略過）。
  - `無法解析`：以下四種都回 `failed`／`unparseable`：HTML 字串、空物件 `{}`、`{"heteronyms": []}`、`heteronyms` 有項目但都沒有 `definitions`。

- [ ] **Step 2: 執行確認失敗**
  Run: `cd app && flutter test test/dictionary/moedict_provider_test.dart`
  Expected: FAIL（找不到 `moedict_provider.dart`）。

- [ ] **Step 3: 實作** `MoedictProvider.lookup(LookupRequest) → Future<ProviderOutcome>`。網址用 `baseUri.replace(pathSegments: [...baseUri.pathSegments.where((s) => s.isNotEmpty), request.word])`（保證 `/` 被編成 `%2F`）。用 `http.Request('GET', uri)..followRedirects = false` 經 `client.send` 送出，再 `http.Response.fromStream`；整段包 `.timeout(timeout)`。解碼用 `utf8.decode(bytes)` 與 `jsonDecode`，任何解碼或型別錯誤都歸 `unparseable`。不加任何標頭。`OnlineDictionaryProvider` 補 `displayName`，並更新 repo 內既有實作或測試替身（`grep -rn "OnlineDictionaryProvider" app/lib app/test`）。

- [ ] **Step 4: 執行確認通過**
  Run: `cd app && flutter test test/dictionary/moedict_provider_test.dart test/dictionary/dictionary_interfaces_test.dart`
  Expected: PASS。

- [ ] **Step 5: Commit**
  ```bash
  git add app/lib/dictionary/providers app/test/dictionary
  git commit -m "feat(epic-63): Issue 7 萌典 provider（https 限定、5 秒逾時、寬鬆解析）"
  ```

---

### Task 2：`DictionarySettingsRepository`

**Files:**
- Create: `app/lib/dictionary/dictionary_settings_repository.dart`
- Create: `app/test/support/fake_dictionary_settings_repository.dart`
- Test: `app/test/dictionary/dictionary_settings_repository_test.dart`

**Interfaces:**
- Produces:
  - `abstract class DictionarySettingsRepository { Future<DateTime?> loadOnlineConsentAt(); Future<void> saveOnlineConsentAt(DateTime? at); }`（`null` 代表關閉並清除）
  - `class SharedPreferencesDictionarySettingsRepository implements DictionarySettingsRepository`，鍵名 `dictionary_online_consent_at`，值為 UTC 的 ISO 8601 字串。
  - 測試替身 `FakeDictionarySettingsRepository({DateTime? consentAt})`：公開欄位 `consentAt`、`loadCount`、`saveCount`；`failOnSave` 為真時 `saveOnlineConsentAt` 丟 `StateError`。

- [ ] **Step 1: 寫失敗測試**（`SharedPreferences.setMockInitialValues`）：
  - `預設為 null`。
  - `存入後讀回同一時刻`（`DateTime.utc(2026, 10, 21, 8)`，`isAtSameMomentAs`）。
  - `存 null 會移除鍵`：`prefs.containsKey('dictionary_online_consent_at') == false`。
  - `壞字串視為 null`：預先放 `'not-a-date'`，讀回 `null`（比照 `AppLocalePreferences`）。

- [ ] **Step 2: 執行確認失敗**
  Run: `cd app && flutter test test/dictionary/dictionary_settings_repository_test.dart`
  Expected: FAIL。

- [ ] **Step 3: 實作**上述介面與替身。壞字串用 `DateTime.tryParse`，失敗回 `null`。

- [ ] **Step 4: 執行確認通過**（同 Step 2 指令）Expected: PASS。

- [ ] **Step 5: Commit**
  ```bash
  git add app/lib/dictionary/dictionary_settings_repository.dart app/test/support/fake_dictionary_settings_repository.dart app/test/dictionary/dictionary_settings_repository_test.dart
  git commit -m "feat(epic-63): Issue 7 線上查詞同意狀態儲存"
  ```

---

### Task 3：`DictionaryService` 線上分段

**Files:**
- Modify: `app/lib/dictionary/dictionary_service.dart`
- Test: `app/test/dictionary/dictionary_service_test.dart`

**Interfaces:**
- Consumes: Task 1 的 `OnlineDictionaryProvider.displayName`、錯誤碼；Task 2 的 `DictionarySettingsRepository`。
- Produces: `DictionaryService` 的三個建構子（預設、`lazy`、`fromProvider`）各自新增三個選填具名參數：
  - `OnlineDictionaryProvider? onlineProvider`
  - `DictionarySettingsRepository? settings`
  - `Future<bool> Function()? isNetworkAvailable`（`null` 視為有網路）
  - `onlineProvider` 或 `settings` 任一為 `null` 時，行為與現在完全相同（既有測試不改）。
  - 新增錯誤碼 `offline`。`lookupInSource` 不變，只查本機。

- [ ] **Step 1: 寫失敗測試**（`dictionary_service_test.dart` 新 group「線上分段」；用 Task 2 的替身與一個計數用的假 `OnlineDictionaryProvider`，另有一組用真 `MoedictProvider`＋`MockClient` 驗證網路呼叫次數）：
  - `未同意：純中文選字回 skipped，網路呼叫 0`；`未同意：中英混合選字同樣 skipped，呼叫 0`。
  - `未同意：純拉丁選字沒有線上分段`（`outcomes` 不含 `moedict`），呼叫 0。
  - `已同意：線上分段排在本機之後`，順序為本機依優先順序、最後 `moedict`。
  - `送出的是 normalizeLookupSelection 後的字串`：選 `「相濡以沫」`，假 provider 收到的 `request.word == '相濡以沫'`；選 `ran` 之類的拉丁字不呼叫。
  - `不送候選詞`：中文選字時假 provider 只被呼叫一次。
  - `撤回後立即生效`：先已同意查一次（呼叫 1），把 `settings.consentAt = null`，再查一次呼叫數仍為 1、結果為 `skipped`。
  - `離線：不呼叫 provider，回 failed／offline`，且 `isNetworkAvailable` 為 `false` 時整個 `lookup` 在 1 秒內完成（假 provider 若被呼叫就會 `Completer` 卡住，藉此證明沒呼叫）。
  - `本機與線上互不影響`：假 provider 丟例外→線上 `failed`／`network`、本機 `found`；本機來源丟例外→本機 `failed`、線上 `found`。
  - `選取無效時不查線上`：`LookupRejected`，呼叫 0，`settings.loadCount == 0`。
  - `沒有本機字典但已同意`：`LookupCompleted.hasEnabledDictionary == false`、`outcomes` 只有 `moedict`。
  - `沒有本機字典且未同意：不附 skipped`：選中文詞，`outcomes` 為空、`hasEnabledDictionary == false`（面板才會顯示「尚未匯入字典」），網路呼叫 0。
  - `有本機字典且未同意：附 skipped`：`outcomes` 最後一筆是 `moedict`／`skipped`。

- [ ] **Step 2: 執行確認失敗**
  Run: `cd app && flutter test test/dictionary/dictionary_service_test.dart`
  Expected: FAIL（新參數不存在）。

- [ ] **Step 3: 實作** `lookup`：選字通過後，若 `charType != SelectionCharType.latin` 且 `onlineProvider != null && settings != null`，先呼叫私有 `Future<ProviderOutcome> _lookupOnline(LookupRequest)` 取得 Future（不 await），逐本查完本機後再 await 並附加在 `outcomes` 最後。例外：結果為 `skipped`（未同意）且沒有任何啟用中的本機字典時，不附加，讓 `outcomes` 維持為空，面板才能顯示「尚未匯入字典」（spec §3.4）。`_lookupOnline` 永不丟例外：每次呼叫都重新讀 `settings.loadOnlineConsentAt()`（不快取）；`null`→`skipped`（`providerId = provider.id`、`displayName = provider.displayName`）；`isNetworkAvailable` 回 `false`→`failed`／`offline`；其餘呼叫 `provider.lookup`，例外→`failed`／`network`。

- [ ] **Step 4: 執行確認通過**（同 Step 2 指令）Expected: PASS。

- [ ] **Step 5: Commit**
  ```bash
  git add app/lib/dictionary/dictionary_service.dart app/test/dictionary/dictionary_service_test.dart
  git commit -m "feat(epic-63): Issue 7 DictionaryService 線上分段（未同意零請求、與本機並行）"
  ```

---

### Task 4：查詢面板的線上失敗訊息

**Files:**
- Modify: `app/lib/screens/widgets/dictionary_lookup_sheet.dart`（`_outcomeBody` 的 `failed` 分支）
- Modify: 四份 ARB（`dictionaryLookupOnlineFailed`、`dictionaryLookupOnlineUnparseable`，文案見上表）
- Test: `app/test/screens/widgets/dictionary_lookup_sheet_test.dart`

**Interfaces:**
- Consumes: Task 1 的錯誤碼。
- Produces: `failed` 分段依 `errorCode` 選文案：`unparseable`→`dictionaryLookupOnlineUnparseable`；`timeout`／`network`／`httpError`／`offline`／`insecureUrl`→`dictionaryLookupOnlineFailed`；其他（含 `null`、`localLookupFailed`、`mdxUnavailable`）→維持現有 `dictionaryLookupFailed`。Key 沿用 `dictionary_lookup_failed`。

- [ ] **Step 1: 寫失敗測試**：
  - `unparseable 顯示無法解析訊息`、`offline 顯示線上失敗訊息`（`find.text` 對應 zh-TW 文案）。
  - `localLookupFailed 仍顯示原本訊息`（回歸）。
  - `萌典 found 分段的頁尾顯示來源標示`：`outcome.attribution` 為 `MoedictProvider.attribution`，`find.textContaining('CC BY-ND 3.0 TW')` 有一個。
  - `線上 skipped 且 onOpenSettings 存在時顯示設定連結`（回歸，既有案例若已涵蓋就不重寫）。

- [ ] **Step 2: 執行確認失敗**
  Run: `cd app && flutter test test/screens/widgets/dictionary_lookup_sheet_test.dart`
  Expected: FAIL（新訊息不存在）。

- [ ] **Step 3: 實作**：ARB 四份加鍵；`failed` 分支依 `errorCode` 選字串。

- [ ] **Step 4: 執行確認通過**（同 Step 2 指令；另跑 `cd app && node tool/check_l10n_hardcoded_strings.js`）Expected: PASS，腳本無輸出錯誤。

- [ ] **Step 5: Commit**
  ```bash
  git add app/lib/screens/widgets/dictionary_lookup_sheet.dart app/lib/l10n app/test/screens/widgets/dictionary_lookup_sheet_test.dart
  git commit -m "feat(epic-63): Issue 7 查詢面板線上失敗與無法解析訊息"
  ```

---

### Task 5：同意對話框

**Files:**
- Create: `app/lib/screens/dictionary_online_consent_dialog.dart`
- Modify: 四份 ARB（`dictionaryOnlineConsent*` 四個鍵）
- Test: `app/test/screens/dictionary_online_consent_dialog_test.dart`

**Interfaces:**
- Produces: `Future<bool> showDictionaryOnlineConsentDialog(BuildContext context, {required bool isEinkMode})`；按「同意並開啟」回 `true`，按「取消」、點外面、返回鍵一律回 `false`。Key：`dictionary_online_consent_dialog`、`dictionary_online_consent_agree`、`dictionary_online_consent_cancel`。E-Ink 時 `AnimationStyle.noAnimation`（比照 `dictionary_import_dialog.dart:61`）。

- [ ] **Step 1: 寫失敗測試**：
  - `顯示四項說明`：`find.textContaining('www.moedict.tw')`、`'書名、前後文、位置、裝置識別'`、`'隨時'` 各一個。
  - `同意回 true`、`取消回 false`、`點對話框外回 false`（`barrierDismissible` 預設行為；結果用 `await` 取得）。
  - `E-Ink 模式不使用動畫`：`isEinkMode: true` 時，開啟後一次 `pump()` 就能找到對話框（無轉場）。

- [ ] **Step 2: 執行確認失敗**
  Run: `cd app && flutter test test/screens/dictionary_online_consent_dialog_test.dart`
  Expected: FAIL。

- [ ] **Step 3: 實作**函式：`showDialog<bool>`，`AlertDialog` 兩個 `TextButton`；回傳 `result ?? false`。

- [ ] **Step 4: 執行確認通過**（同 Step 2 指令）Expected: PASS。

- [ ] **Step 5: Commit**
  ```bash
  git add app/lib/screens/dictionary_online_consent_dialog.dart app/lib/l10n app/test/screens/dictionary_online_consent_dialog_test.dart
  git commit -m "feat(epic-63): Issue 7 線上查詞同意對話框"
  ```

---

### Task 6：設定畫面線上區塊與依賴注入

**Files:**
- Modify: `app/lib/screens/dictionary_settings_screen.dart`（新增 `required DictionarySettingsRepository settings`；`_buildBody` 外層加固定在底部的線上區塊）
- Modify: `app/lib/screens/reader_feature_dependencies.dart`（新增 `required DictionarySettingsRepository dictionarySettings`）
- Modify: `app/lib/screens/settings_scaffold.dart:270`、`app/lib/screens/reader_screen.dart:1960`（兩處建構 `DictionarySettingsScreen` 時傳 `settings`）
- Modify: `app/test/support/fake_reader_feature_dependencies.dart`（預設 `FakeDictionarySettingsRepository()`）、`app/test/screens/dictionary_settings_screen_test.dart` 既有建構處
- Modify: 四份 ARB（`dictionaryOnlineSectionTitle`、`Description`、`StatusOff`、`StatusOn`、`SaveFailed`）；`@dictionaryOnlineStatusOn` 須宣告 `"placeholders": {"date": {"type": "String"}}`，四份都要有
- Test: `app/test/screens/dictionary_settings_screen_test.dart`、`app/test/support/fake_reader_feature_dependencies_test.dart`

**Interfaces:**
- Consumes: Task 2 的 repository；Task 5 的 `showDictionaryOnlineConsentDialog`；Task 1 的 `MoedictProvider.attribution`。
- Produces: 區塊 Key：`dictionary_online_section`、`dictionary_online_switch`（`SwitchListTile`）、`dictionary_online_status`（狀態文字）、`dictionary_online_attribution`（顯示 `MoedictProvider.attribution`）。區塊在字典清單為空、載入失敗、正常三種狀態都要顯示。行為：
  - 載入：`initState` 讀 `loadOnlineConsentAt()`；讀取失敗視為 `null`。
  - 開關打開：先 `showDictionaryOnlineConsentDialog`；回 `true` 才 `saveOnlineConsentAt(clock.now())`，成功後更新畫面；回 `false` 開關維持關。
  - 開關關閉：`saveOnlineConsentAt(null)`。
  - 儲存失敗：開關維持原值，在區塊內顯示 `dictionaryOnlineSaveFailed`（Key `dictionary_online_save_error`），不丟例外。
  - 防連點：State 內 `bool _savingConsent`，對話框開啟與儲存期間為 `true`，此時 `SwitchListTile.onChanged` 設為 `null`。
  - 日期字串用 `consentAt.toLocal().toIso8601String().substring(0, 10)`。

- [ ] **Step 1: 寫失敗測試**（畫面測試；`FakeDictionarySettingsRepository`）：
  - `預設顯示關閉與尚未同意`：開關 `value == false`，`dictionary_online_status` 文字為「尚未同意」。
  - `打開開關先跳同意對話框；取消後仍是關閉、repository.saveCount == 0`。
  - `同意後開關為開、狀態顯示日期、repository.consentAt 有值`（用 `withClock(Clock.fixed(DateTime.utc(2026, 10, 21, 12)))`，正午在所有時區的本機日期都是同一天；狀態文字含 `2026-10-21`）。
  - `連點開關不會重複跳對話框`：對話框開啟期間與儲存期間，開關 `onChanged` 為 `null`。
  - `已同意時關閉開關：consentAt 變 null，且不跳對話框`。
  - `儲存失敗：開關維持、顯示 dictionary_online_save_error`（`failOnSave = true`）。
  - `空清單與載入失敗時區塊仍在`（`FakeDictionaryManager` 設為空清單／丟例外）。
  - `顯示來源標示 MoedictProvider.attribution`。
  - `fake_reader_feature_dependencies_test.dart`：`dictionarySettings` 欄位存在且為預設替身。
  - 現有 `dictionary_settings_screen_test.dart` 全部案例補上 `settings:` 參數後仍通過。

- [ ] **Step 2: 執行確認失敗**
  Run: `cd app && flutter test test/screens/dictionary_settings_screen_test.dart test/support/fake_reader_feature_dependencies_test.dart`
  Expected: FAIL。

- [ ] **Step 3: 實作**上述行為與注入。`ReaderFeatureDependencies` 新欄位照 `dictionaryManager` 的註解風格寫。`grep -rn "DictionarySettingsScreen(\|ReaderFeatureDependencies(" app/lib app/test` 找全呼叫端。

- [ ] **Step 4: 執行確認通過**
  Run: `cd app && flutter test test/screens/dictionary_settings_screen_test.dart test/support/fake_reader_feature_dependencies_test.dart test/screens/settings_scaffold_test.dart && node tool/check_l10n_hardcoded_strings.js`
  Expected: PASS；腳本無錯誤。若 `settings_scaffold_test.dart` 不存在，改跑 `grep -rln "settings_dictionary_button" app/test` 找到的檔案。

- [ ] **Step 5: Commit**
  ```bash
  git add app/lib app/test
  git commit -m "feat(epic-63): Issue 7 字典設定畫面線上查詞區塊與同意流程"
  ```

---

### Task 7：`main.dart` 接線與隱私頁

**Files:**
- Modify: `app/lib/main.dart`（約 148 行 `DictionaryService.fromProvider` 與約 384 行 `readerFeatures`）
- Modify: `site/privacy.html`

**Interfaces:**
- Consumes: Task 1、2、3、6。
- Produces: 正式環境的線上查詞可用。

- [ ] **Step 1: 接線** `main.dart`：建構 `SharedPreferencesDictionarySettingsRepository`；建構專用的 `http.Client()` 給 `MoedictProvider`；`DictionaryService.fromProvider(..., onlineProvider: moedict, settings: dictionarySettings, isNetworkAvailable: () async => (await Connectivity().checkConnectivity()).any((r) => r != ConnectivityResult.none))`；把同一個 `dictionarySettings` 放進 `readerFeatures` 的 `dictionarySettings:`。

- [ ] **Step 2: 更新 `site/privacy.html`**：先讀整頁。在「二、…利用」的「6. Google 使用者資料」之後新增 `<h3>7. 字典查詢與線上查詞 (Dictionary Lookup，選用功能)</h3>`，內容必須包含：
  - 本機字典完全離線，不連網。
  - 線上查詞（萌典）為選用，**預設關閉**，需先在 APP 內同意才會啟用。
  - 啟用後，查中文詞時只會把**你選取的那個詞**以 HTTPS 送到 `www.moedict.tw`。不會送出書名、前後文、閱讀位置、裝置識別或帳號。
  - 萌典由第三方志工營運，ugotit.cc 不經營該服務、不會收到查詢內容；萌典如何處理連線紀錄，適用其自身政策。
  - 停用方式：「設定 → 閱讀 → 字典」關閉開關，關閉後立即停止送出。
  - 結果的資料來源標示：教育部《重編國語辭典修訂本》（CC BY-ND 3.0 TW）。
  - 同時把頁首「最後修訂日期」改為執行當日。

- [ ] **Step 3: 確認**
  Run: `cd app && flutter analyze && node tool/check_l10n_hardcoded_strings.js`
  Expected: `No issues found!`；腳本無錯誤。再人工開 `site/privacy.html` 確認新段落格式與其他 `<h3>` 一致。

- [ ] **Step 4: Commit**
  ```bash
  git add app/lib/main.dart site/privacy.html
  git commit -m "feat(epic-63): Issue 7 接線線上查詞並更新隱私頁"
  ```

---

### Task 8：全套驗證與真機確認

- [ ] **Step 1: 靜態檢查**
  Run: `cd app && flutter analyze && node tool/check_l10n_hardcoded_strings.js && node tool/check_integration_keys.js`
  Expected: `No issues found!`；兩支腳本無錯誤。

- [ ] **Step 2: 完整測試（本計畫唯一一次）**
  Run: `cd app && flutter test`
  Expected: 全數通過。有失敗就修，並在此註明哪個檔案、原因。

- [ ] **Step 3: 驗收對照**（逐項填寫結果）
  - 驗收 7：Task 3「未同意零請求」。
  - 驗收 8：Task 1「請求網址只含詞」。
  - 驗收 9：Task 1「正常回應」、Task 4「頁尾來源標示」。
  - 驗收 10：Task 1「拒絕非 https」「不跟重導向」。
  - 驗收 15：Task 3「不送候選詞」。
  - 回歸：驗收 27（既有測試）、28（主庫仍是 `version: 28`）、29（`main.js` 無改動）：`git diff main --stat -- app/android/app/src/main/assets/foliate/main.js` 為空。

- [ ] **Step 4: 真機確認（請人類執行或在場）**，裝置：WAVE E-Ink 機。
  1. 設定 → 閱讀 → 字典：開關預設關。打開，跳同意對話框，同意後開關為開。
  2. 在 EPUB 選 `相濡以沫`，點查字典：本機分段之後出現「萌典」分段，頁尾有 CC BY-ND 3.0 TW 標示。
  3. 關閉開關，再查同一詞：萌典分段顯示「線上查詢已關閉」與「前往字典設定」，點連結進設定畫面。
  4. 開飛航模式，再開啟線上查詞後查詞：本機結果在 1 秒內出現，萌典分段顯示失敗訊息，不卡面板。
  5. 面板與設定區塊在 E-Ink 模式下沒有動畫、用邊框。

- [ ] **Step 5: 回報**：把結果寫進 `reviews/`（不進版控）。通過後等人類決定合併，之後才更新 `issues.md` 狀態與 `docs/epics.md` 備註。

---

## 交給人類

- **Google Play 資料安全表單**需同步更新（隱私頁已改，表單要手動填）。
- 驗收 31（沒有取自 AGPL／GPL 專案的程式碼）由人類在 Issue 8 最終確認。

## 交給後續 Issue

- **Issue 8：** 若 App 內另有隱私頁或授權頁，補萌典資料來源與 CC BY-ND 3.0 TW；`docs/prd.md` 字典 FR 條目。
- **後續優化（不在 Phase 1）：** 萌典結果快取與重試上限；自訂線上網址；萌典釋義中的交叉參照連結。

---

## 自我檢查

- **Spec 覆蓋：** §3.3 `OnlineDictionaryProvider`、`MoedictProvider`（Task 1）；§3.4 線上條件、`skipped`、只送原字串（Task 3）；§3.7 線上區塊（Task 6）；§7 同意對話框與隱私（Task 5、7）；驗收 7（Task 3）、8（Task 1）、9（Task 1、4）、10（Task 1）、15（Task 3）。
- **與 spec 的差異：** 「已同意」與「已開啟」合成一個狀態（見已決定事項）。
- **型別一致：** `onlineConsentAt`／`loadOnlineConsentAt`／`saveOnlineConsentAt` 只在 Task 2 定義，Task 3、6 使用同名；錯誤碼 `insecureUrl`／`timeout`／`network`／`httpError`／`unparseable` 在 Task 1 定義，`offline` 在 Task 3 定義，Task 4 對照表涵蓋全部六個；`MoedictProvider.attribution` 在 Task 1 定義，Task 4、6 引用。
- **比例：** 程式碼區塊只有簽章、指令與固定值，沒有函式本體。
