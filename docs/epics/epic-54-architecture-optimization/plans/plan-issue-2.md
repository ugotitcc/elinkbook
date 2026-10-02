# Issue 2：雲端授權失效訊號對齊 實作計畫

> **給執行者：** 必要子技能：使用 `superpowers:subagent-driven-development`（建議）或 `superpowers:executing-plans` 逐 Task 執行本計畫。步驟使用 checkbox（`- [ ]`）語法追蹤進度；每完成一個 Step 就把它改為 `- [x]`。

**Goal：** 讓雲端匯入端（Google Drive／OneDrive）正確區分「雲端授權失效」（需要使用者重新連結）與「暫時性錯誤」（斷網、5xx），並讓下載佇列中因授權失效而失敗的項目顯示「需重新連結帳號」，而不是泛用的「失敗」。

**Architecture：** ① 新增 `cloud_import/cloud_auth_classifier.dart`，集中兩條規則：「token 端點回 400／401 → 授權被撤銷」與「資料 API 回 401 → 拋 `CloudAuthRequiredException`，其他非 200 → 一般例外」；兩個 OAuth client 與兩個 storage client 共用，OAuth client 不合併。② `ensureValidAccessToken` 簽章不變，`null` 專指「需重新連結」，網路例外與非 400／401 的失敗改為往上拋。③ `QueuedDownloadJob` 新增 `isAuthFailure(Object error)`，`DownloadQueueItem` 新增 `needsReauth`，`DownloadQueuePanel` 據此換狀態文字。

**Tech Stack：** Flutter／Dart、`flutter_test`、`package:http`（`MockClient`）、`flutter gen-l10n`。指令一律在 `app/` 目錄下執行。

**Spec：** 沒有獨立的 `spec.md`，設計依據是 2026-10-02 `/grill-with-docs` 的決策，記錄於 `docs/epics/epic-54-architecture-optimization/epic.md`「Issue 2 設計決策」與 `CONTEXT.md`「雲端授權失效」詞條。

## 與設計表的差異（動手前先讀）

1. **`isAuthFailure` 不能有「預設 false」。** 設計表寫「預設 `false`」，但 `QueuedDownloadJob` 的實作者都是 `implements`（`CloudDownloadJob`、`RemoteDownloadJob`、兩個測試假物件），Dart 的 `implements` 不繼承方法本體，預設值無從生效。改為**抽象方法**，`RemoteDownloadJob` 明確回傳 `false`，兩個測試假物件各補一個。
2. **瀏覽畫面的 widget 測試不翻轉。** 設計表寫「瀏覽畫面離線時顯示網路錯誤，不顯示 reauth」要翻轉現有行為的 widget 測試。實際上 `CloudBrowserScreen` 的程式碼完全不變，且它的測試用的是假的 `CloudStorageClient`（早已有 `_NetworkErrorCloudStorageClient` 涵蓋「一般例外 → 網路錯誤」與 `_ThrowingCloudStorageClient` 涵蓋「授權例外 → reauth」）。真正的行為變化發生在 OAuth client 與 storage client 之間，所以改在 **storage client 測試**驗證：「斷網時 `listFolder` 拋出的不是 `CloudAuthRequiredException`」。瀏覽畫面測試維持不動。

## Global Constraints

- **語言**：所有文件、註解、測試名稱一律正體中文（zh-TW），禁止簡體中文；程式碼命名維持英文慣例。
- **簽章不變**：`GoogleDriveOAuthClient.ensureValidAccessToken()`／`OneDriveOAuthClient.ensureValidAccessToken()` 維持 `Future<String?>`；`CloudStorageClient` 介面、`CloudAuthRequiredException` 的位置與型別不動。
- **不改的行為**：未連結（`loadTokens` 回 `null`）→ `null`；token 還有效 → 直接回傳；換發回 200 但回應內容缺欄位或解析失敗 → 維持回 `null`（本 Issue 不重新分類）；換發成功後寫回 repository 的邏輯不動；刻意不主動 `unlink`。
- **不動的東西**：兩個 OAuth client 的 `link()`／`_fetchEmail`／`unlink()`、`CloudBrowserScreen`（含 reauth 文字與 `Key`）、`CloudAccountSettingsScreen`、`DownloadQueueController` 的排程／重複偵測／取消邏輯、OPDS 下載流程。
- **不加按鈕**：佇列面板與瀏覽畫面都不加「前往重新連結」按鈕（另立後續 Issue）。
- **ARB**：新增 1 個鍵 `downloadQueueStatusNeedsReauth`，四份（`app_zh_TW.arb` 為 template 且需 `@` 描述、`app_zh.arb`、`app_en.arb`、`app_zh_CN.arb`）同步；改完跑 `flutter gen-l10n`，生成檔 `app/lib/l10n/app_localizations*.dart` 一併提交。
- **指令語法**：bash 語法，用 Bash 工具（Git Bash）執行。
- **Windows 環境**：`python` 在此環境不會實際執行，不可用來編輯檔案；用 Edit 工具。多數原始檔是 CRLF 換行，Edit 的定位字串不要含換行。
- **測試範圍**（CLAUDE.md）：單一 Task 只跑異動實際觸及的測試檔；完整 `flutter test`（無參數）只在最後一個 Task 跑一次（約 6 分鐘，用 `run_in_background`）。
- **提交前**：`flutter analyze` 必須是 "No issues found!"，並跑 `node tool/check_l10n_hardcoded_strings.js`。
- **Commit 結尾**必須帶 `Co-Authored-By: Claude Sonnet 5.5 <noreply@anthropic.com>`。
- **流程**：直接 TDD；程式審查先出報告（存於 `reviews/`，該目錄 gitignore、不進版控），審查者不直接改程式；審查摘要放進 `epic.md`。

## Review Focus

最可能咬到使用者的情況（依可能性排序），每條都有對應測試：

1. **斷網時被當成要重新連結。** 這是本 Issue 的主因。→ Task 1 測「換發時 HTTP 呼叫拋例外 → `ensureValidAccessToken` 往上拋，不回 `null`」；Task 2 測「斷網時 `listFolder` 拋出的不是 `CloudAuthRequiredException`」。
2. **403／5xx 被誤判成授權失效。** Drive 對額度或速率限制回 403，必須維持一般錯誤。→ Task 2 保留並擴充「非 200 拋例外」測試：403 與 500 都不是 `CloudAuthRequiredException`；Task 1 測換發回 500／429 → 拋例外而非 `null`。
3. **被使用者取消的下載被標成需重新連結。** → Task 3 測「已取消的工作即使 `isAuthFailure` 為真也是 `cancelled` 且 `needsReauth == false`」。
4. **重試後旗標殘留。** 授權失效後重新連結、按重試成功，面板不該還顯示「需重新連結」。→ Task 3 測「重試成功後 `needsReauth` 重設為 `false`」。
5. **OPDS 下載工作的失敗被標成需重新連結。** → Task 3 測「`isAuthFailure` 回 `false` 的工作失敗時 `needsReauth == false`」，`RemoteDownloadJob` 明確回傳 `false`。
6. **ARB 鍵漏一份。** → Task 4 跑 `check_l10n_hardcoded_strings.js` 與 `flutter gen-l10n`（缺鍵會編譯失敗）。

## File Structure

| 檔案 | 動作 | 責任 |
|---|---|---|
| `app/lib/cloud_import/cloud_auth_classifier.dart` | 新增 | `isRefreshTokenRejected`、`throwCloudApiStatusError` 兩個函式 |
| `app/test/cloud_import/cloud_auth_classifier_test.dart` | 新增 | 分類規則純測試 |
| `app/lib/cloud_import/google_drive_oauth_client.dart`、`onedrive_oauth_client.dart` | 修改 | 換發段改用分類規則，斷網與其他失敗往上拋 |
| `app/test/cloud_import/google_drive_oauth_client_test.dart`、`onedrive_oauth_client_test.dart` | 修改 | 補斷網／500／429 測試 |
| `app/lib/cloud_import/google_drive_storage_client.dart`、`onedrive_storage_client.dart` | 修改 | 6 處非 200 判斷改呼叫 `throwCloudApiStatusError` |
| `app/test/cloud_import/google_drive_storage_client_test.dart`、`onedrive_storage_client_test.dart` | 修改 | 補 401 與斷網測試 |
| `app/lib/downloads/download_queue_controller.dart` | 修改 | `QueuedDownloadJob.isAuthFailure`、`DownloadQueueItem.needsReauth`、`_downloadOne` 設定與重設 |
| `app/lib/cloud_import/cloud_download_job.dart`、`app/lib/remote/remote_download_job.dart` | 修改 | 實作 `isAuthFailure` |
| `app/test/downloads/download_queue_controller_test.dart` | 修改 | 假物件補方法，新增 4 個測試 |
| `app/test/cloud_import/cloud_download_job_test.dart` | 新增 | `isAuthFailure` 判斷 |
| `app/lib/screens/widgets/download_queue_panel.dart` | 修改 | 失敗狀態依 `needsReauth` 換文字 |
| `app/test/screens/widgets/download_queue_panel_test.dart` | 修改 | 假物件補方法，新增 3 個測試 |
| `app/lib/l10n/app_{zh_TW,zh,en,zh_CN}.arb` 與生成檔 | 修改 | 新鍵 `downloadQueueStatusNeedsReauth` |
| `docs/epics/epic-54-architecture-optimization/{epic.md,issues.md}`、`docs/epics.md` | 修改 | 開發記錄、狀態 |

---

### Task 0：提交計畫、建立 worktree

**Files：**
- Commit：本計畫檔、`issues.md`、`epic.md`（設計決策）、`CONTEXT.md`（新詞條），在 `main` 上，純文件
- 建立 worktree：`.worktrees/epic-54-issue-2-cloud-reauth`

**Interfaces：**
- Consumes：無。
- Produces：後續 Task 都在 worktree 的分支 `epic-54/issue-2-cloud-reauth` 上進行與提交。

- [x] **Step 1：在 `main` 提交計畫與設計文件，並把 Issue 2 標為進行中**

先把 `docs/epics/epic-54-architecture-optimization/issues.md` 的 Issue 2 狀態改為「🟡 進行中（`plans/plan-issue-2.md`）」，再提交：

```bash
cd /c/Users/fycdc/AI/elinkBook
git status --short
git add CONTEXT.md docs/epics/epic-54-architecture-optimization/epic.md docs/epics/epic-54-architecture-optimization/issues.md docs/epics/epic-54-architecture-optimization/plans/plan-issue-2.md
git commit -m "docs(epic-54): Issue 2 設計決策、雲端授權失效詞條與實作計畫，標為進行中

Co-Authored-By: Claude Sonnet 5.5 <noreply@anthropic.com>"
```

Expected：`git status --short` 在 add 之前只有這四個檔案。

- [ ] **Step 2：推送 `main`（對外動作，須先取得使用者確認，不得自動推送）**

確認後：

```bash
git push origin main
```

若 push 被拒絕，**不要強制推送**：先 `git pull --no-rebase --no-edit`，再重新 `git push origin main`。

- [x] **Step 3：建立 worktree 與分支**

```bash
cd /c/Users/fycdc/AI/elinkBook
git worktree add .worktrees/epic-54-issue-2-cloud-reauth -b epic-54/issue-2-cloud-reauth main
cd .worktrees/epic-54-issue-2-cloud-reauth/app
flutter pub get
```

Expected：`Preparing worktree (new branch 'epic-54/issue-2-cloud-reauth')`。之後所有指令都在這個 worktree 的 `app/` 下執行。

---

### Task 1：分類規則與兩個 OAuth client

**Files：**
- Create: `app/lib/cloud_import/cloud_auth_classifier.dart`
- Create: `app/test/cloud_import/cloud_auth_classifier_test.dart`
- Modify: `app/lib/cloud_import/google_drive_oauth_client.dart`（`ensureValidAccessToken`，約 133–181 行）
- Modify: `app/lib/cloud_import/onedrive_oauth_client.dart`（`ensureValidAccessToken`，約 122–168 行）
- Test: `app/test/cloud_import/google_drive_oauth_client_test.dart`、`app/test/cloud_import/onedrive_oauth_client_test.dart`

**Interfaces：**
- Consumes：`CloudAuthRequiredException`（`cloud_storage_client.dart`，無參數建構）。
- Produces（Task 2 依賴，名稱與型別必須一致）：

```dart
/// token 端點的回應狀態碼是否代表授權已被撤銷（400／401）。
bool isRefreshTokenRejected(int statusCode);

/// 資料 API 回傳非 200 時拋出：401 → CloudAuthRequiredException，其餘 → Exception。
Never throwCloudApiStatusError(String message, int statusCode);
```

- [x] **Step 1：寫失敗的分類規則測試**

建立 `app/test/cloud_import/cloud_auth_classifier_test.dart`：

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:elinkbook/cloud_import/cloud_auth_classifier.dart';
import 'package:elinkbook/cloud_import/cloud_storage_client.dart';

void main() {
  group('isRefreshTokenRejected', () {
    test('400 與 401 代表授權已被撤銷', () {
      expect(isRefreshTokenRejected(400), isTrue);
      expect(isRefreshTokenRejected(401), isTrue);
    });

    test('403、429、500、503 屬權限或暫時性限制，不算撤銷', () {
      expect(isRefreshTokenRejected(403), isFalse);
      expect(isRefreshTokenRejected(429), isFalse);
      expect(isRefreshTokenRejected(500), isFalse);
      expect(isRefreshTokenRejected(503), isFalse);
    });

    test('200 不算撤銷', () {
      expect(isRefreshTokenRejected(200), isFalse);
    });
  });

  group('throwCloudApiStatusError', () {
    test('401 拋出 CloudAuthRequiredException', () {
      expect(
        () => throwCloudApiStatusError('目錄讀取失敗', 401),
        throwsA(isA<CloudAuthRequiredException>()),
      );
    });

    test('403 與 500 拋出一般例外，訊息帶狀態碼，且不是 CloudAuthRequiredException', () {
      for (final code in [403, 500]) {
        expect(
          () => throwCloudApiStatusError('目錄讀取失敗', code),
          throwsA(
            predicate(
              (e) =>
                  e is Exception &&
                  e is! CloudAuthRequiredException &&
                  e.toString().contains('目錄讀取失敗（HTTP $code）'),
            ),
          ),
        );
      }
    });
  });
}
```

- [x] **Step 2：跑測試確認失敗**

Run: `flutter test test/cloud_import/cloud_auth_classifier_test.dart`
Expected：編譯失敗，`cloud_auth_classifier.dart` 不存在。

- [x] **Step 3：實作分類規則**

建立 `app/lib/cloud_import/cloud_auth_classifier.dart`：

```dart
import 'cloud_storage_client.dart';

/// 判斷換發 token 的回應狀態碼是否代表「授權已被撤銷」（`CONTEXT.md`
/// 「雲端授權失效」）。token 端點對撤銷的 refresh token 回 400
/// （`invalid_grant`），對無效用戶端憑證回 401；其餘（429、5xx 等）是
/// 暫時性錯誤，使用者重新連結也救不了，不能當成授權失效。
///
/// Google Drive 與 OneDrive 兩個 OAuth client 共用這條規則，避免兩邊的
/// 判斷再次分岔（兩個 client 本身刻意不合併）。
bool isRefreshTokenRejected(int statusCode) =>
    statusCode == 400 || statusCode == 401;

/// 雲端硬碟資料 API（目錄、下載、縮圖）回傳非 200 時拋出對應例外：401
/// 代表 access token 被伺服器拒絕，拋出 [CloudAuthRequiredException] 讓
/// 呼叫端提示重新連結；其餘（403 額度／速率限制、5xx 等）維持一般例外。
/// 例外訊息格式沿用既有的「<message>（HTTP <狀態碼>）」。
Never throwCloudApiStatusError(String message, int statusCode) {
  if (statusCode == 401) throw CloudAuthRequiredException();
  throw Exception('$message（HTTP $statusCode）');
}
```

- [x] **Step 4：跑測試確認通過**

Run: `flutter test test/cloud_import/cloud_auth_classifier_test.dart`
Expected：5 個測試通過。

- [x] **Step 5：寫失敗的 OAuth client 測試（Google）**

在 `app/test/cloud_import/google_drive_oauth_client_test.dart` 第 107 行（`回傳 null` 的撤銷測試結尾 `});`）之後、`group(` 之前插入。需要在檔案最上方補 `import 'dart:io';`（用於 `SocketException`）。

```dart
  group('換發失敗的分類（epic-54 Issue 2）', () {
    Future<GoogleDriveOAuthClient> clientWith(MockClient mockClient) async {
      await accountRepository.link(
        CloudProvider.googleDrive,
        CloudAccountTokens(
          accessToken: 'expiring-token',
          refreshToken: 'refresh-1',
          email: 'reader@example.com',
          expiresAt: DateTime.now().add(const Duration(seconds: 10)),
        ),
      );
      return GoogleDriveOAuthClient(
        accountRepository: accountRepository,
        httpClient: mockClient,
      );
    }

    test('換發時斷網：往上拋出例外，不回傳 null（不能當成要重新連結）', () async {
      final client = await clientWith(
        MockClient((request) async => throw const SocketException('offline')),
      );

      await expectLater(
        client.ensureValidAccessToken(),
        throwsA(isA<SocketException>()),
      );
    });

    test('換發回 401：視為授權已被撤銷，回傳 null', () async {
      final client = await clientWith(
        MockClient((request) async => http.Response('', 401)),
      );

      expect(await client.ensureValidAccessToken(), isNull);
    });

    for (final code in [429, 500, 503]) {
      test('換發回 $code：屬暫時性，拋出例外而非回傳 null', () async {
        final client = await clientWith(
          MockClient((request) async => http.Response('', code)),
        );

        await expectLater(
          client.ensureValidAccessToken(),
          throwsA(isA<Exception>()),
        );
      });
    }
  });
```

- [x] **Step 6：跑測試確認失敗**

Run: `flutter test test/cloud_import/google_drive_oauth_client_test.dart`
Expected：新增的「斷網」與「429／500／503」共 4 個測試失敗（目前都回 `null`）；「401」測試通過（目前非 200 一律回 `null`）；既有測試仍通過。

- [x] **Step 7：改 `GoogleDriveOAuthClient.ensureValidAccessToken`**

在 `google_drive_oauth_client.dart` 頂端補 `import 'cloud_auth_classifier.dart';`。把第 141–154 行：

```dart
    http.Response response;
    try {
      response = await _httpClient.post(
        Uri.parse(_tokenEndpoint),
        body: _tokenRequestBody({
          'refresh_token': tokens.refreshToken,
          'client_id': CloudOAuthConfig.googleClientId,
          'grant_type': 'refresh_token',
        }),
      );
    } catch (_) {
      return null;
    }
    if (response.statusCode != 200) return null;
```

改為：

```dart
    // 網路例外不攔截，直接往上拋：斷網是暫時性的，不能當成「授權已被
    // 撤銷」而要求使用者重新連結（CONTEXT.md「雲端授權失效」）。
    final response = await _httpClient.post(
      Uri.parse(_tokenEndpoint),
      body: _tokenRequestBody({
        'refresh_token': tokens.refreshToken,
        'client_id': CloudOAuthConfig.googleClientId,
        'grant_type': 'refresh_token',
      }),
    );
    if (isRefreshTokenRejected(response.statusCode)) return null;
    if (response.statusCode != 200) {
      throw Exception('Google Drive 授權續期失敗（HTTP ${response.statusCode}）');
    }
```

並把方法上方 doc comment（第 127–132 行）改為：

```dart
  /// 回傳目前有效的 access token；已過期或 60 秒內即將過期時，先用
  /// refresh token 靜默換發新的並更新儲存值。回傳 `null` 專指「需要重新
  /// 連結」：未連結（[CloudAccountRepository.loadTokens] 回傳 `null`，不發
  /// 出任何網路請求），或換發被伺服器拒絕（400／401，通常代表授權已被撤
  /// 銷，見 [isRefreshTokenRejected]）。斷網與其他暫時性失敗（429、5xx）
  /// 改為拋出例外，由呼叫端歸為一般網路錯誤。刻意不主動呼叫 [unlink]，
  /// 保留使用者手動決定是否解除連結的空間（`spec.md`「帳號模組」）。
```

- [x] **Step 8：跑 Google OAuth 測試確認通過**

Run: `flutter test test/cloud_import/google_drive_oauth_client_test.dart`
Expected：全部通過（既有測試含「400 invalid_grant → null」仍綠）。

- [x] **Step 9：OneDrive 同樣處理（先測試、後實作）**

在 `app/test/cloud_import/onedrive_oauth_client_test.dart` 補 `import 'dart:io';`，並在最後一個測試（第 139 行 `});`）之後、檔尾 `}` 之前插入與 Step 5 相同的 `group`，把 `CloudProvider.googleDrive` 改為 `CloudProvider.oneDrive`、`GoogleDriveOAuthClient` 改為 `OneDriveOAuthClient`、`Future<GoogleDriveOAuthClient> clientWith` 改為 `Future<OneDriveOAuthClient> clientWith`。

Run: `flutter test test/cloud_import/onedrive_oauth_client_test.dart`
Expected：「斷網」與「429／500／503」4 個測試失敗。

然後在 `onedrive_oauth_client.dart` 頂端補 `import 'cloud_auth_classifier.dart';`，把第 130–141 行：

```dart
    http.Response response;
    try {
      response = await _httpClient.post(Uri.parse(_tokenEndpoint), body: {
        'refresh_token': tokens.refreshToken,
        'client_id': CloudOAuthConfig.oneDriveClientId,
        'grant_type': 'refresh_token',
        'scope': _filesReadScope,
      });
    } catch (_) {
      return null;
    }
    if (response.statusCode != 200) return null;
```

改為：

```dart
    // 網路例外不攔截，直接往上拋（理由同 GoogleDriveOAuthClient）。
    final response = await _httpClient.post(Uri.parse(_tokenEndpoint), body: {
      'refresh_token': tokens.refreshToken,
      'client_id': CloudOAuthConfig.oneDriveClientId,
      'grant_type': 'refresh_token',
      'scope': _filesReadScope,
    });
    if (isRefreshTokenRejected(response.statusCode)) return null;
    if (response.statusCode != 200) {
      throw Exception('OneDrive 授權續期失敗（HTTP ${response.statusCode}）');
    }
```

doc comment（第 117–121 行）同 Step 7 的語意改寫（把 `GoogleDriveOAuthClient` 的說明換成 OneDrive 版本，保留「比照 Issue 1 既定設計」的出處）。

Run: `flutter test test/cloud_import/onedrive_oauth_client_test.dart`
Expected：全部通過。

- [x] **Step 10：分析並提交**

```bash
flutter analyze
git add lib/cloud_import test/cloud_import
git commit -m "feat(cloud-import): 換發 token 時區分授權撤銷與暫時性失敗（epic-54 Issue 2）

Co-Authored-By: Claude Sonnet 5.5 <noreply@anthropic.com>"
```

Expected：`No issues found!`

---

### Task 2：兩個 storage client 的 401 對應

**Files：**
- Modify: `app/lib/cloud_import/google_drive_storage_client.dart`（第 64–66、116–118、149–151 行）
- Modify: `app/lib/cloud_import/onedrive_storage_client.dart`（第 57–59、116–118、149–151 行）
- Test: `app/test/cloud_import/google_drive_storage_client_test.dart`、`app/test/cloud_import/onedrive_storage_client_test.dart`

**Interfaces：**
- Consumes：Task 1 的 `throwCloudApiStatusError(String message, int statusCode)`。
- Produces：無新介面；行為是 `listFolder`／`downloadFile`／`fetchThumbnail` 遇 401 拋 `CloudAuthRequiredException`，遇其他非 200 拋一般例外。

- [x] **Step 1：寫失敗的 Google storage client 測試**

在 `google_drive_storage_client_test.dart` 補 `import 'dart:io';`，並把最後一個測試（第 138–144 行 `HTTP 非 200 回應時拋出例外`）替換為下列 group（原測試的 403 案例已被涵蓋，刪除並於開發記錄列出對應）：

```dart
  group('非 200 回應的分類（epic-54 Issue 2）', () {
    GoogleDriveStorageClient clientReturning(int status) =>
        GoogleDriveStorageClient(
          oauthClient: oauthClient,
          httpClient: MockClient((request) async => http.Response('', status)),
        );

    final entry = const CloudFileEntry(
      id: 'file-1',
      name: 'a.epub',
      isFolder: false,
      format: BookFileFormat.epub,
    );

    test('listFolder 回 401：拋出 CloudAuthRequiredException', () async {
      await expectLater(
        clientReturning(401).listFolder(),
        throwsA(isA<CloudAuthRequiredException>()),
      );
    });

    test('downloadFile 回 401：拋出 CloudAuthRequiredException，且不留目的檔', () async {
      final dir = Directory.systemTemp.createTempSync('gdrive_401_test');
      addTearDown(() => dir.deleteSync(recursive: true));
      final path = '${dir.path}/out.epub';

      await expectLater(
        clientReturning(401).downloadFile(entry, path),
        throwsA(isA<CloudAuthRequiredException>()),
      );
      expect(File(path).existsSync(), isFalse);
    });

    test('fetchThumbnail 回 401：拋出 CloudAuthRequiredException', () async {
      await expectLater(
        clientReturning(401).fetchThumbnail('https://example.com/t'),
        throwsA(isA<CloudAuthRequiredException>()),
      );
    });

    for (final code in [403, 500]) {
      test('listFolder 回 $code：拋出一般例外，不是 CloudAuthRequiredException',
          () async {
        await expectLater(
          clientReturning(code).listFolder(),
          throwsA(
            predicate((e) => e is Exception && e is! CloudAuthRequiredException),
          ),
        );
      });
    }

    test('換發 token 時斷網：listFolder 拋出的不是 CloudAuthRequiredException', () async {
      final expiringRepository = FakeCloudAccountRepository();
      await expiringRepository.link(
        CloudProvider.googleDrive,
        CloudAccountTokens(
          accessToken: 'expiring-token',
          refreshToken: 'refresh-1',
          email: 'reader@example.com',
          expiresAt: DateTime.now().add(const Duration(seconds: 10)),
        ),
      );
      final offlineOauth = GoogleDriveOAuthClient(
        accountRepository: expiringRepository,
        httpClient: MockClient(
          (request) async => throw const SocketException('offline'),
        ),
      );
      final client = GoogleDriveStorageClient(oauthClient: offlineOauth);

      await expectLater(
        client.listFolder(),
        throwsA(
          predicate((e) => e is Exception && e is! CloudAuthRequiredException),
        ),
      );
    });
  });
```

- [x] **Step 2：跑測試確認失敗**

Run: `flutter test test/cloud_import/google_drive_storage_client_test.dart`
Expected：3 個 401 測試失敗（目前拋一般 `Exception`）；其餘通過。

- [x] **Step 3：改 `GoogleDriveStorageClient`**

頂端補 `import 'cloud_auth_classifier.dart';`。三處改法：

```dart
      if (response.statusCode != 200) {
        throw Exception('Google Drive 目錄讀取失敗（HTTP ${response.statusCode}）');
      }
```
→
```dart
      if (response.statusCode != 200) {
        throwCloudApiStatusError('Google Drive 目錄讀取失敗', response.statusCode);
      }
```

```dart
      if (response.statusCode != 200) {
        throw Exception('Google Drive 下載失敗（HTTP ${response.statusCode}）');
      }
```
→
```dart
      if (response.statusCode != 200) {
        throwCloudApiStatusError('Google Drive 下載失敗', response.statusCode);
      }
```

```dart
    if (response.statusCode != 200) {
      throw Exception('縮圖載入失敗（HTTP ${response.statusCode}）');
    }
```
→
```dart
    if (response.statusCode != 200) {
      throwCloudApiStatusError('縮圖載入失敗', response.statusCode);
    }
```

類別 doc comment 第 15–16 行補一句：「API 回 401 同樣拋出 [CloudAuthRequiredException]（見 `cloud_auth_classifier.dart`）。」

- [x] **Step 4：跑 Google storage 測試確認通過**

Run: `flutter test test/cloud_import/google_drive_storage_client_test.dart`
Expected：全部通過（`downloadFile` 的 catch 區塊會在 401 時刪除目的檔，「不留目的檔」斷言成立）。

- [x] **Step 5：OneDrive 同樣處理**

在 `onedrive_storage_client_test.dart` 補 `import 'dart:io';`，把第 196 行起的 `HTTP 非 200 回應時拋出例外` 測試替換為與 Step 1 相同的 group：`GoogleDriveStorageClient` → `OneDriveStorageClient`、`GoogleDriveOAuthClient` → `OneDriveOAuthClient`、`CloudProvider.googleDrive` → `CloudProvider.oneDrive`、暫存目錄名稱改 `onedrive_401_test`。

Run: `flutter test test/cloud_import/onedrive_storage_client_test.dart`
Expected：3 個 401 測試失敗。

再在 `onedrive_storage_client.dart` 頂端補 `import 'cloud_auth_classifier.dart';`，三處改法：

```dart
        throw Exception('OneDrive 目錄讀取失敗（HTTP ${response.statusCode}）');
```
→
```dart
        throwCloudApiStatusError('OneDrive 目錄讀取失敗', response.statusCode);
```

```dart
        throw Exception('OneDrive 下載失敗（HTTP ${response.statusCode}）');
```
→
```dart
        throwCloudApiStatusError('OneDrive 下載失敗', response.statusCode);
```

```dart
      throw Exception('縮圖載入失敗（HTTP ${response.statusCode}）');
```
→
```dart
      throwCloudApiStatusError('縮圖載入失敗', response.statusCode);
```

Run: `flutter test test/cloud_import/onedrive_storage_client_test.dart`
Expected：全部通過。

- [x] **Step 6：分析並提交**

```bash
flutter analyze
git add lib/cloud_import test/cloud_import
git commit -m "feat(cloud-import): 雲端硬碟 API 回 401 時拋出 CloudAuthRequiredException（epic-54 Issue 2）

Co-Authored-By: Claude Sonnet 5.5 <noreply@anthropic.com>"
```

Expected：`No issues found!`

---

### Task 3：下載佇列的 `needsReauth`

**Files：**
- Modify: `app/lib/downloads/download_queue_controller.dart`
- Modify: `app/lib/cloud_import/cloud_download_job.dart`
- Modify: `app/lib/remote/remote_download_job.dart`
- Create: `app/test/cloud_import/cloud_download_job_test.dart`
- Modify: `app/test/downloads/download_queue_controller_test.dart`
- Modify: `app/test/screens/widgets/download_queue_panel_test.dart`（只補假物件的方法，使其編譯；面板行為測試在 Task 4）

**Interfaces：**
- Consumes：`CloudAuthRequiredException`（`cloud_storage_client.dart`）。
- Produces（Task 4 依賴）：

```dart
abstract class QueuedDownloadJob {
  // ...既有成員不變...
  /// [download] 等階段拋出的 [error] 是否代表「需要使用者重新連結帳號」。
  bool isAuthFailure(Object error);
}

class DownloadQueueItem {
  // ...既有欄位不變...
  /// 狀態為 failed 且失敗原因是授權失效時為 true；其他情況一律 false。
  bool needsReauth;   // 預設 false，非 final
}
```

- [x] **Step 1：寫失敗的控制器測試**

在 `download_queue_controller_test.dart` 的 `FakeQueuedDownloadJob` 加上：建構子參數 `this.authFailurePredicate`、欄位與方法：

```dart
  /// 判斷哪些例外算「授權失效」；預設 null 代表一律不是。
  bool Function(Object error)? authFailurePredicate;

  @override
  bool isAuthFailure(Object error) => authFailurePredicate?.call(error) ?? false;
```

（建構子的具名參數清單加 `this.authFailurePredicate,`。）並在檔尾 `main()` 內、`retry() 可在失敗後…` 測試之後新增：

```dart
  group('授權失效標示（epic-54 Issue 2）', () {
    test('download() 拋出的例外被 isAuthFailure 判為真：failed 且 needsReauth', () async {
      final controller = DownloadQueueController(onDuplicateConfirm: (_) async => false);
      final job = FakeQueuedDownloadJob(
        id: 'book-1',
        downloadError: StateError('auth'),
        authFailurePredicate: (e) => e is StateError,
      );

      controller.enqueueJobs([job]);
      await pumpEventQueue();

      final item = controller.items.single;
      expect(item.status, DownloadItemStatus.failed);
      expect(item.needsReauth, isTrue);
    });

    test('isAuthFailure 為假的失敗（例如 OPDS 下載）：failed 但 needsReauth 為 false', () async {
      final controller = DownloadQueueController(onDuplicateConfirm: (_) async => false);
      final job = FakeQueuedDownloadJob(id: 'book-1', downloadError: StateError('x'));

      controller.enqueueJobs([job]);
      await pumpEventQueue();

      final item = controller.items.single;
      expect(item.status, DownloadItemStatus.failed);
      expect(item.needsReauth, isFalse);
    });

    test('已被使用者取消的工作：即使 isAuthFailure 為真，也是 cancelled 且 needsReauth 為 false', () async {
      final controller = DownloadQueueController(onDuplicateConfirm: (_) async => false);
      final completer = Completer<void>();
      final job = FakeQueuedDownloadJob(
        id: 'book-1',
        pendingCompleter: completer,
        authFailurePredicate: (_) => true,
      );

      controller.enqueueJobs([job]);
      await pumpEventQueue();
      controller.cancel('book-1');
      completer.complete();
      await pumpEventQueue();

      final item = controller.items.single;
      expect(item.status, DownloadItemStatus.cancelled);
      expect(item.needsReauth, isFalse);
    });

    test('授權失效後重試成功：needsReauth 重設為 false', () async {
      final controller = DownloadQueueController(onDuplicateConfirm: (_) async => false);
      final job = FakeQueuedDownloadJob(
        id: 'book-1',
        downloadError: StateError('auth'),
        authFailurePredicate: (e) => e is StateError,
      );
      controller.enqueueJobs([job]);
      await pumpEventQueue();
      expect(controller.items.single.needsReauth, isTrue);

      job.downloadError = null;
      await controller.retry('book-1');

      final item = controller.items.single;
      expect(item.status, DownloadItemStatus.done);
      expect(item.needsReauth, isFalse);
    });
  });
```

- [x] **Step 2：跑測試確認失敗**

Run: `flutter test test/downloads/download_queue_controller_test.dart`
Expected：編譯失敗（`needsReauth` 與 `isAuthFailure` 不存在）。

- [x] **Step 3：實作控制器與介面**

在 `download_queue_controller.dart`：

`DownloadQueueItem` 加欄位與建構子參數：

```dart
  /// 狀態為 [DownloadItemStatus.failed] 且失敗原因是「雲端授權失效」（見
  /// `CONTEXT.md`）時為 true，供面板顯示「需重新連結帳號」；其餘一律
  /// false。重試時會先重設。
  bool needsReauth;

  DownloadQueueItem({
    required this.id,
    required this.name,
    this.status = DownloadItemStatus.pending,
    this.progress,
    this.needsReauth = false,
  });
```

`QueuedDownloadJob` 在 `import` 方法之後加：

```dart
  /// [download] 等階段拋出的 [error] 是否代表「需要使用者重新連結帳號」
  /// （雲端授權失效，見 `CONTEXT.md`）。控制器不認得個別來源的例外型別，
  /// 由各來源自己判斷；不涉及帳號的來源（例如 OPDS 遠端書庫）回傳 `false`。
  bool isAuthFailure(Object error);
```

`_downloadOne` 開頭 `item.status = DownloadItemStatus.downloading;` 之前加 `item.needsReauth = false;`；把 `} catch (_) {` 區塊改為：

```dart
    } catch (e) {
      if (tempPath != null) await _deleteIfExists(tempPath);
      if (job.isCancelled) {
        item.status = DownloadItemStatus.cancelled;
      } else {
        item.status = DownloadItemStatus.failed;
        item.needsReauth = job.isAuthFailure(e);
      }
      notifyListeners();
    }
```

- [x] **Step 4：實作兩個 job**

`cloud_download_job.dart` 在 `import` 方法之後加（`CloudAuthRequiredException` 已由 `cloud_storage_client.dart` 的 import 取得）：

```dart
  @override
  bool isAuthFailure(Object error) => error is CloudAuthRequiredException;
```

`remote_download_job.dart` 在 `import` 方法之後加：

```dart
  /// OPDS 遠端書庫用 HTTP Basic Auth 或匿名，沒有「重新連結帳號」的概念
  /// （與雲端匯入的 OAuth 不同，見 `CONTEXT.md`「遠端書庫」）。
  @override
  bool isAuthFailure(Object error) => false;
```

- [x] **Step 5：補面板測試假物件的方法（使其編譯）**

這裡先填 `false` 只是讓 Task 3 能獨立通過編譯與測試；Task 4 Step 1 會刻意把它改成 `error is _AuthFailure`，這是兩步切分，不是遺漏。

在 `download_queue_panel_test.dart` 的 `_FakeQueuedDownloadJob` 加：

```dart
  @override
  bool isAuthFailure(Object error) => false;
```

- [x] **Step 6：寫 `CloudDownloadJob.isAuthFailure` 測試**

建立 `app/test/cloud_import/cloud_download_job_test.dart`：

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:elinkbook/cloud_import/cloud_download_job.dart';
import 'package:elinkbook/cloud_import/cloud_storage_client.dart';
import 'package:elinkbook/library/models/library_enums.dart';

import '../support/fake_book_import_service.dart';
import '../support/fake_cloud_storage_client.dart';
import '../support/fake_fingerprint_computer.dart';
import '../support/fake_library_repository.dart';

void main() {
  CloudDownloadJob makeJob() => CloudDownloadJob(
        entry: const CloudFileEntry(
          id: 'file-1',
          name: 'a.epub',
          isFolder: false,
          format: BookFileFormat.epub,
        ),
        client: FakeCloudStorageClient(),
        importService: FakeBookImportService(),
        libraryRepository: FakeLibraryRepository(),
        computeFingerprintFn: FakeFingerprintComputer().call,
        source: BookSource.googleDrive,
      );

  test('isAuthFailure 只對 CloudAuthRequiredException 為真', () {
    final job = makeJob();

    expect(job.isAuthFailure(CloudAuthRequiredException()), isTrue);
    expect(job.isAuthFailure(Exception('HTTP 500')), isFalse);
    expect(job.isAuthFailure(StateError('x')), isFalse);
  });
}
```

- [x] **Step 7：跑測試確認通過**

Run: `flutter test test/downloads/download_queue_controller_test.dart test/cloud_import/cloud_download_job_test.dart test/screens/widgets/download_queue_panel_test.dart`
Expected：全部通過。

- [x] **Step 8：分析並提交**

```bash
flutter analyze
git add lib/downloads lib/cloud_import lib/remote test/downloads test/cloud_import test/screens/widgets
git commit -m "feat(downloads): 下載佇列標示需重新連結帳號的失敗項目（epic-54 Issue 2）

Co-Authored-By: Claude Sonnet 5.5 <noreply@anthropic.com>"
```

Expected：`No issues found!`

---

### Task 4：面板文字與 ARB

**Files：**
- Modify: `app/lib/l10n/app_zh_TW.arb`（第 2480 行 `downloadQueueStatusFailed` 之後）、`app_zh.arb`（第 544 行之後）、`app_en.arb`（第 544 行之後）、`app_zh_CN.arb`（第 544 行之後）
- Modify（生成）: `app/lib/l10n/app_localizations*.dart`
- Modify: `app/lib/screens/widgets/download_queue_panel.dart`（`_statusLabel` 的 `failed` 分支，約 178–179 行）
- Test: `app/test/screens/widgets/download_queue_panel_test.dart`

**Interfaces：**
- Consumes：Task 3 的 `DownloadQueueItem.needsReauth`、`QueuedDownloadJob.isAuthFailure`。
- Produces：`AppLocalizations.downloadQueueStatusNeedsReauth`（`String` getter）。

- [x] **Step 1：寫失敗的面板測試**

在 `download_queue_panel_test.dart` 的 `_FakeQueuedDownloadJob`：把 `isAuthFailure` 改為 `bool isAuthFailure(Object error) => error is _AuthFailure;`，在類別後加 `class _AuthFailure implements Exception {}`，並在 `completeDownload()` 之後加：

```dart
  void failDownload(Object error) {
    if (!_downloadCompleter.isCompleted) _downloadCompleter.completeError(error);
  }
```

於 `main()` 內新增三個測試（放在「下載成功完成後…」之後）：

```dart
  testWidgets('授權失效造成的失敗顯示「需重新連結帳號」並保留重試鈕', (tester) async {
    final controller = DownloadQueueController(onDuplicateConfirm: (_) async => false);
    final job = _FakeQueuedDownloadJob(id: 'book-4', name: '測試書籍4');
    await pumpPanel(tester, controller);

    controller.enqueueJobs([job]);
    await tester.pump();
    job.failDownload(_AuthFailure());
    await tester.pump();
    await tester.pump();

    expect(find.text('需重新連結帳號'), findsOneWidget);
    expect(find.text('失敗'), findsNothing);
    expect(
      find.byKey(const Key('sources_download_queue_retry_book-4')),
      findsOneWidget,
    );
  });

  testWidgets('一般失敗仍顯示「失敗」，不顯示需重新連結', (tester) async {
    final controller = DownloadQueueController(onDuplicateConfirm: (_) async => false);
    final job = _FakeQueuedDownloadJob(id: 'book-5', name: '測試書籍5');
    await pumpPanel(tester, controller);

    controller.enqueueJobs([job]);
    await tester.pump();
    job.failDownload(StateError('network'));
    await tester.pump();
    await tester.pump();

    expect(find.text('失敗'), findsOneWidget);
    expect(find.text('需重新連結帳號'), findsNothing);
  });

  testWidgets('英文介面下授權失效顯示對應英文', (tester) async {
    final controller = DownloadQueueController(onDuplicateConfirm: (_) async => false);
    final job = _FakeQueuedDownloadJob(id: 'book-6', name: 'Test Book');
    await pumpPanel(tester, controller, locale: const Locale('en'));

    controller.enqueueJobs([job]);
    await tester.pump();
    job.failDownload(_AuthFailure());
    await tester.pump();
    await tester.pump();

    expect(find.text('Account needs reconnecting'), findsOneWidget);
  });
```

- [x] **Step 2：跑測試確認失敗**

Run: `flutter test test/screens/widgets/download_queue_panel_test.dart`
Expected：「需重新連結帳號」兩個測試失敗（目前顯示「失敗」）。

- [x] **Step 3：新增四份 ARB 的鍵**

`app_zh_TW.arb`（template，需 `@` 描述），緊接 `downloadQueueStatusFailed` 區塊（第 2483 行 `},`）之後：

```json
  "downloadQueueStatusNeedsReauth": "需重新連結帳號",
  "@downloadQueueStatusNeedsReauth": {
    "description": "項目狀態標籤：下載失敗的原因是雲端匯入來源帳號授權失效（見 CONTEXT.md「雲端授權失效」），使用者需到設定重新連結帳號後按重試"
  },
```

`app_zh.arb`、`app_zh_CN.arb`、`app_en.arb` 緊接 `"downloadQueueStatusFailed": ...,` 那一行之後各加一行：

```json
  "downloadQueueStatusNeedsReauth": "需重新連結帳號",
```
（`app_zh_CN.arb`：`"需重新连接账号"`，用字對齊該檔既有的「连接」「账」（檔內沒有「帐」）；`app_en.arb`：`"Account needs reconnecting"`。）

- [x] **Step 4：重新產生 l10n**

Run: `flutter gen-l10n`
Expected：無錯誤；`git status` 顯示 `app/lib/l10n/app_localizations*.dart` 有變動（只新增該鍵）。

- [x] **Step 5：改面板**

`download_queue_panel.dart` 的 `_statusLabel`：

```dart
      case DownloadItemStatus.failed:
        return l10n.downloadQueueStatusFailed;
```
→
```dart
      case DownloadItemStatus.failed:
        return item.needsReauth
            ? l10n.downloadQueueStatusNeedsReauth
            : l10n.downloadQueueStatusFailed;
```

- [x] **Step 6：跑測試與守衛**

```bash
flutter test test/screens/widgets/download_queue_panel_test.dart
node tool/check_l10n_hardcoded_strings.js
```
Expected：面板測試全部通過；腳本兩行 PASS。

- [x] **Step 7：分析並提交**

```bash
flutter analyze
git add lib/l10n lib/screens/widgets test/screens/widgets
git commit -m "feat(downloads): 面板對授權失效的失敗項目顯示需重新連結帳號（epic-54 Issue 2）

Co-Authored-By: Claude Sonnet 5.5 <noreply@anthropic.com>"
```

Expected：`No issues found!`

---

### Task 5：記錄、全套測試、準備 PR

**Files：**
- Modify: `docs/epics/epic-54-architecture-optimization/epic.md`（開發記錄）、`issues.md`、`docs/epics.md`

**Interfaces：**
- Consumes：Task 1–4 全部完成。
- Produces：可發 PR 的分支。

- [x] **Step 1：確認 `lib/` 沒有殘留舊的「一律回 null」路徑**

用 Grep 在 `app/lib/cloud_import/` 搜尋 `HTTP \$\{response.statusCode\}`，預期只剩 `cloud_auth_classifier.dart` 與兩個 OAuth client 的「授權續期失敗」兩處；搜尋 `catch (_) {\n      return null;` 於兩個 OAuth client 的換發段，預期已不存在（`_fetchEmail` 與 200 回應解析失敗的 `return null` 是刻意保留的，不在範圍內）。

- [x] **Step 2：跑完整 `flutter test`**

Run（`run_in_background`，約 6 分鐘）: `flutter test`
Expected：全部通過、1 略過。若 `test/downloads/download_queue_controller_test.dart` 出現固定輪數 `pumpEventQueue()` 造成的偶發失敗（Issue 4 已記錄的既有不穩定測試），單獨重跑該檔確認，再重跑全套，並在記錄中註明。

- [x] **Step 3：更新開發記錄**

在 `epic.md` 開發記錄末尾新增「Issue 2 實作完成」段落，寫明：與設計表的兩處差異（見本計畫開頭）；測試數量（新增、刪除並對應：Google／OneDrive storage client 的 `HTTP 非 200 回應時拋出例外` 各 1 個被 group 內的 403 案例取代）；驗證結果（`flutter analyze`、`check_l10n_hardcoded_strings.js`、全套測試數字）；待真機確認項目：真實 Google／OneDrive 帳號被撤銷授權後，瀏覽顯示「請重新連結」、下載佇列顯示「需重新連結帳號」，以及飛航模式下瀏覽顯示網路錯誤而非重新連結。`issues.md` 與 `docs/epics.md` 的 Issue 2 標為「待發 PR」。

- [x] **Step 4：提交並請求程式審查**

```bash
git add ../docs
git commit -m "docs(epic-54): Issue 2 實作記錄，準備程式審查

Co-Authored-By: Claude Sonnet 5.5 <noreply@anthropic.com>"
```

程式審查依 CLAUDE.md 慣例：獨立審查員先出報告到 `reviews/review-code-issue-2.md`，不直接改程式；發 PR 前須取得使用者確認。
