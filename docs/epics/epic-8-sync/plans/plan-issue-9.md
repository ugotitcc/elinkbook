# Epic 8 Issue 9 — `sync_reading_positions` Unique Index 修正 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 讓 PocketBase `sync_reading_positions` collection 真正強制「每個使用者對每本書（`book_fingerprint`）至多一筆紀錄」這個既有的資料模型假設——目前只是文件約定、完全沒有機制執行，讓 `SyncEngine._syncReadingPositions()` 的查詢在理論上（兩裝置同時首次推送同一本書、或本機同一本書匯入兩次）可能撞上重複列，導致衝突判定行為不穩定。

**Architecture:** 新增一支獨立、冪等的 PocketBase 升級 migration，對 `sync_reading_positions` 加上 `CREATE UNIQUE INDEX (user, book_fingerprint)`（比照 Issue 5 `1785801600_add_created_updated_autodate_fields.js` 已確立的「新檔案、不改舊 migration」模式）；`SyncEngine._syncReadingPositions()` 的既有查詢補上確定性 `sort`；新增一則真機 `integration_test`，直接對 PocketBase 驗證重複 (user, book_fingerprint) 會被伺服器拒絕。套用到既有測試實例前，必須先確認該實例目前沒有重複紀錄（已於撰寫本計畫時查證，見 Task 2）。

**Tech Stack:** PocketBase JS migration（v0.39.10 JSVM API）、Flutter/Dart、`package:pocketbase`、`flutter test`（純函式/mock）、`integration_test`（真機，連線 Issue 7 的 `pbdev.jigong.org` 測試實例）。

## Global Constraints

- **PocketBase 依檔名記錄已套用過的 migration，不會因檔案內容更新而重新執行**（見 `docker/pb_migrations/1785801600_add_created_updated_autodate_fields.js` 開頭說明，Issue 5 Task 6 審查已確立的教訓）——本 Issue **不修改**任何既有 migration 檔案，一律用新檔案。
- **套用 unique index 前，若 collection 內已有違反此約束的重複紀錄，migration 會直接失敗、且會讓 PocketBase 服務整個啟動失敗**（已於撰寫本計畫時用本機 PocketBase v0.39.10 binary 實測確認，見下方 Task 1 驗證記錄）——套用到 `pbdev.jigong.org` 前必須先確認乾淨。
- **`sync_reading_positions` 沒有 `client_id`／`deleted_at` 欄位**（Issue 5 已確立），本 Issue 不新增或修改任何欄位，只新增 index。
- PocketBase 測試帳號、base URL 沿用 Issue 2 起既有慣例：`http://pbdev.jigong.org`（Tailscale 專用網域，執行 `integration_test` 前裝置需先連上 Tailscale）、`epic8-issue2-test@example.com` / `epic8-test-password-123`。

## 與 issues.md 的落差說明（實作決策）

1. **Issue 9 原文建議的 unique index 名稱** `idx_sync_reading_positions_user_fp` **直接採用**，已於撰寫本計畫時實測驗證正確（見 Task 1）。
2. **`_syncReadingPositions()` 的 `sort` 值選用 `'created'`**（Issue 9 原文建議 `'created'` 或 `'-updated'` 二選一）：由於 unique index 套用後，`(user, book_fingerprint)` 理論上永遠最多 1 筆，`sort` 的實際效果只是「查詢行為本身不依賴未定義排序」這個防禦性語意，兩者皆可；選 `'created'` 是因為它是不會隨後續 `update` 操作變動的欄位，語意上更貼近「用建立時間排序、若真的出現非預期的重複資料時優先取最早的一筆」，比 `-updated` 更容易推理。
3. **本計畫額外新增 spec.md 文件更新**（Issue 9 原文未提及）：`docs/epics/epic-8-sync/spec.md`「PocketBase Collection Schema」是本 Epic 的唯一事實來源，`sync_reading_positions` 表格目前沒有記錄「至多一筆」這個約束的落地方式，僅 plan-issue-5.md 的 Global Constraints 段落提過。既然本 Issue 讓這個約束真正被強制執行，順手把 spec.md 的表格也補上這個事實，避免未來讀者只看 spec.md 看不到這個限制的存在。
4. **Issue 9 原文「新增測試驗證同一 (user, book_fingerprint) 嘗試建立第二筆會被 PocketBase 拒絕」這條驗收標準，只能用真機 `integration_test` 達成**，不是 `flutter test`：這是 PocketBase 伺服器端的 DB constraint，`MockClient` 沒有真正的 SQLite 引擎在背後執行，無法真實驗證「第二筆真的會被拒絕」，只能驗證「App 端有沒有正確處理伺服器回傳的錯誤」——但本 Issue 的範圍是「資料庫層級的約束是否存在」，不是「App 端錯誤處理邏輯」（`SyncEngine` 呼叫端目前也沒有針對這個特定 400 錯誤碼做任何特殊處理，衝突判定邏輯本身已經在 Issue 5 用 `perPage: 1` 查詢先避開了真正撞到 unique constraint 的情境——見 spec.md「同步引擎」步驟 1，`_syncReadingPositions()` 永遠是查詢在先、create/update 在後，不會出現「兩個 Dart 呼叫同時 create」的真實 race）。因此本計畫把這則驗收標準設計成一個獨立的、直接呼叫 `PocketBase` client（不經過 `SyncEngine`）的整合測試，純粹驗證 collection schema 層級的約束確實存在，見 Task 4。

---

### Task 1：新增 unique index 升級 migration（含本機驗證）

**Files:**
- Create：`docker/pb_migrations/1785801700_add_reading_positions_unique_index.js`
- Create：`docs/epics/epic-8-sync/pb_migrations_example/1785801700_add_reading_positions_unique_index.js`（與上者逐 byte 相同，比照 Issue 5 兩份副本同步慣例）

**Interfaces:**
- Consumes：無（獨立 migration 檔案，PocketBase 啟動時自動掃描 `pb_migrations/` 目錄套用）。
- Produces：`sync_reading_positions` collection 的 `indexes` 陣列新增一筆
  `CREATE UNIQUE INDEX \`idx_sync_reading_positions_user_fp\` ON \`sync_reading_positions\` (\`user\`, \`book_fingerprint\`)`。供 Task 4 的整合測試驗證這個約束確實生效。

本 Task 沒有 Flutter/Dart 程式碼，驗證方式是實際下載 PocketBase 執行檔在本機跑過，不是 `flutter test`。

**Shell 相容性提醒**：以下所有指令（含 `&` 背景執行、`sleep`）假設在 POSIX-相容 shell 下執行（本專案 Bash 工具預設的 Git Bash，或 WSL）；Windows 原生 `cmd.exe`／PowerShell 對 `&`／`sleep` 的行為不同，不要直接貼過去跑。

- [x] **Step 1：下載本機測試用 PocketBase 執行檔**

在**任何暫存目錄**（例如系統暫存目錄，不要放進本 repo）下執行（Windows 範例，其他平台請對照 `pocketbase-self-hosting.md`「啟動方式」換成對應檔名）：

```bash
mkdir -p /tmp/pb-issue9-test/pb_migrations
cd /tmp/pb-issue9-test
curl -sSL -o pocketbase.zip https://github.com/pocketbase/pocketbase/releases/download/v0.39.10/pocketbase_0.39.10_windows_amd64.zip
unzip -o -q pocketbase.zip
```

Expected：目錄下出現 `pocketbase.exe`。

- [x] **Step 2：複製既有兩支 migration 進去，啟動一次確認乾淨基準**

```bash
cp <repo-root>/docker/pb_migrations/1785715200_create_sync_collections.js pb_migrations/
cp <repo-root>/docker/pb_migrations/1785801600_add_created_updated_autodate_fields.js pb_migrations/
./pocketbase.exe superuser upsert test@example.com TestPassw0rd123
./pocketbase.exe serve --http=127.0.0.1:8094 &
sleep 3
curl -sS http://127.0.0.1:8094/api/health
```

Expected：`{"message":"API is healthy.","code":200,"data":{}}`。

- [x] **Step 3：撰寫新的 migration 檔案**

Create `docker/pb_migrations/1785801700_add_reading_positions_unique_index.js`：

```javascript
/// @file 1785801700_add_reading_positions_unique_index.js
/// 對 `sync_reading_positions` 加上 unique index，強制「每個使用者對每
/// 本書（`book_fingerprint`）至多一筆紀錄」——這個約束原本只記載於
/// plan-issue-5.md 的 Global Constraints，完全沒有任何機制執行，理論上
/// 兩台裝置第一次同時推送同一本書、或本機同一本書匯入兩次，皆可能建出
/// 重複列，導致 `SyncEngine._syncReadingPositions()` 的
/// `getList(perPage: 1)` 查詢拿到不穩定的其中一筆、反覆誤判衝突（見
/// epic-8-sync issues.md Issue 9，2026-08-04 Issue 5 最終全分支審查
/// 發現）。
///
/// **套用前必須先確認 collection 內沒有既存的重複紀錄**——若已有重複，
/// 這支 migration 套用時會直接失敗（`UNIQUE constraint failed`），且
/// PocketBase 服務會啟動失敗、整個掛掉，不是優雅降級（已於撰寫本檔案
/// 時用本機 PocketBase v0.39.10 binary 實測確認）。確認/清理步驟見
/// `docs/epics/epic-8-sync/plans/plan-issue-9.md` Task 2。
///
/// 比照 `1785801600_add_created_updated_autodate_fields.js` 已確立的
/// 模式：新增獨立檔案而非修改舊的 `1785715200_...`（已套用過的環境不會
/// 因為舊檔案內容更新而重新執行）；down 只移除這個 migration 自己加的
/// 索引（用索引名稱字串比對，不會誤刪其他索引）。

migrate((app) => {
  const collection = app.findCollectionByNameOrId("sync_reading_positions");
  const indexName = "idx_sync_reading_positions_user_fp";
  const alreadyExists = collection.indexes.some((idx) => idx.includes(indexName));
  if (alreadyExists) return; // 冪等：已經套用過（例如已手動補過）就跳過

  collection.indexes.push(
    `CREATE UNIQUE INDEX \`${indexName}\` ON \`sync_reading_positions\` (\`user\`, \`book_fingerprint\`)`
  );
  app.save(collection);
}, (app) => {
  const collection = app.findCollectionByNameOrId("sync_reading_positions");
  const indexName = "idx_sync_reading_positions_user_fp";
  collection.indexes = collection.indexes.filter((idx) => !idx.includes(indexName));
  app.save(collection);
});
```

- [x] **Step 4：套用到本機測試實例，驗證正確建立**

```bash
# 先停掉上一步啟動的 serve（Ctrl+C 或關閉該背景行程），複製新檔案進去再重啟
cp <repo-root>/docker/pb_migrations/1785801700_add_reading_positions_unique_index.js pb_migrations/
./pocketbase.exe serve --http=127.0.0.1:8094 &
sleep 3
curl -sS http://127.0.0.1:8094/api/health
```

Expected：health check 正常（服務沒有因 migration 失敗而啟動失敗）。

再驗證 index 確實出現：

```bash
TOKEN=$(curl -sS -X POST http://127.0.0.1:8094/api/collections/_superusers/auth-with-password \
  -H "Content-Type: application/json" \
  -d '{"identity":"test@example.com","password":"TestPassw0rd123"}' | python3 -c "import sys,json; print(json.load(sys.stdin)['token'])")
curl -sS http://127.0.0.1:8094/api/collections/sync_reading_positions \
  -H "Authorization: $TOKEN" | python3 -c "import sys,json; print(json.load(sys.stdin)['indexes'])"
```

Expected：輸出包含
`CREATE UNIQUE INDEX \`idx_sync_reading_positions_user_fp\` ON \`sync_reading_positions\` (\`user\`, \`book_fingerprint\`)`。

- [x] **Step 5：驗證約束真的生效——建立同一 (user, book_fingerprint) 第二筆會被拒絕**

```bash
USERTOKEN_RESP=$(curl -sS -X POST http://127.0.0.1:8094/api/collections/users/records \
  -H "Content-Type: application/json" \
  -d '{"email":"u1@example.com","password":"UserPassw0rd123","passwordConfirm":"UserPassw0rd123"}')
UID1=$(echo "$USERTOKEN_RESP" | python3 -c "import sys,json; print(json.load(sys.stdin)['id'])")

curl -sS -X POST http://127.0.0.1:8094/api/collections/sync_reading_positions/records \
  -H "Authorization: $TOKEN" -H "Content-Type: application/json" \
  -d "{\"user\":\"$UID1\",\"book_fingerprint\":\"fp1\",\"pdf_page_index\":1,\"progress\":0.1}"

# 第二次，相同 user + book_fingerprint
curl -sS -w "\nHTTP %{http_code}\n" -X POST http://127.0.0.1:8094/api/collections/sync_reading_positions/records \
  -H "Authorization: $TOKEN" -H "Content-Type: application/json" \
  -d "{\"user\":\"$UID1\",\"book_fingerprint\":\"fp1\",\"pdf_page_index\":2,\"progress\":0.2}"
```

Expected：第一次 `HTTP 200`（含 `id`）；第二次 `HTTP 400`，body 含
`"code":"validation_not_unique"`。

- [x] **Step 6：驗證既有重複資料會讓 migration 套用失敗（確認 Global Constraints 的風險敘述屬實，非純理論）**

```bash
# 停掉 serve，清空 pb_data 重來一次乾淨環境
rm -rf pb_data
cp <repo-root>/docker/pb_migrations/1785715200_create_sync_collections.js pb_migrations/
cp <repo-root>/docker/pb_migrations/1785801600_add_created_updated_autodate_fields.js pb_migrations/
rm pb_migrations/1785801700_add_reading_positions_unique_index.js  # 先移除，等等再放回來
./pocketbase.exe superuser upsert test@example.com TestPassw0rd123
./pocketbase.exe serve --http=127.0.0.1:8094 &
sleep 3

# 建立同一個 (user, book_fingerprint) 的兩筆重複紀錄（此時還沒有 unique index，兩次都會成功）
TOKEN=$(curl -sS -X POST http://127.0.0.1:8094/api/collections/_superusers/auth-with-password \
  -H "Content-Type: application/json" \
  -d '{"identity":"test@example.com","password":"TestPassw0rd123"}' | python3 -c "import sys,json; print(json.load(sys.stdin)['token'])")
USERTOKEN_RESP=$(curl -sS -X POST http://127.0.0.1:8094/api/collections/users/records \
  -H "Content-Type: application/json" \
  -d '{"email":"u2@example.com","password":"UserPassw0rd123","passwordConfirm":"UserPassw0rd123"}')
UID2=$(echo "$USERTOKEN_RESP" | python3 -c "import sys,json; print(json.load(sys.stdin)['id'])")
curl -sS -X POST http://127.0.0.1:8094/api/collections/sync_reading_positions/records \
  -H "Authorization: $TOKEN" -H "Content-Type: application/json" \
  -d "{\"user\":\"$UID2\",\"book_fingerprint\":\"dup-fp\",\"pdf_page_index\":1,\"progress\":0.1}"
curl -sS -X POST http://127.0.0.1:8094/api/collections/sync_reading_positions/records \
  -H "Authorization: $TOKEN" -H "Content-Type: application/json" \
  -d "{\"user\":\"$UID2\",\"book_fingerprint\":\"dup-fp\",\"pdf_page_index\":2,\"progress\":0.2}"

# 停掉這個 serve，放回新的 migration 檔案，重啟
cp <repo-root>/docker/pb_migrations/1785801700_add_reading_positions_unique_index.js pb_migrations/
./pocketbase.exe serve --http=127.0.0.1:8095 2>&1 | grep -iE "error|failed"
```

Expected：兩次建立重複紀錄皆 `HTTP 200`（此時還沒有 index）；套用新 migration 重啟後，輸出包含
`failed to apply migration 1785801700_...: ... UNIQUE constraint failed`，且服務**無法**成功啟動（`curl` 打不通，非 200）。

這一步驗證了 Global Constraints 描述的風險是真實的，不是理論假設——如果 Task 2 沒有先確認/清理 `pbdev.jigong.org` 上的重複資料，直接把這支 migration 複製過去會讓那個持續運作中的測試實例整個掛掉。

- [x] **Step 7：清理本機測試環境**

```bash
# 停掉所有背景的 pocketbase.exe process
rm -rf /tmp/pb-issue9-test
```

- [x] **Step 8：複製到 docs 對照副本，`flutter analyze`（確認沒有動到任何 Dart 檔案）+ Commit**

```bash
cp docker/pb_migrations/1785801700_add_reading_positions_unique_index.js docs/epics/epic-8-sync/pb_migrations_example/1785801700_add_reading_positions_unique_index.js
diff docker/pb_migrations/1785801700_add_reading_positions_unique_index.js docs/epics/epic-8-sync/pb_migrations_example/1785801700_add_reading_positions_unique_index.js && echo "IDENTICAL"
git add docker/pb_migrations/1785801700_add_reading_positions_unique_index.js docs/epics/epic-8-sync/pb_migrations_example/1785801700_add_reading_positions_unique_index.js
git commit -m "feat(epic-8-sync): Issue 9 Task 1 — sync_reading_positions unique index migration"
```

Expected：`diff` 無輸出（`IDENTICAL`）。

---

### Task 2：確認並套用到 `pbdev.jigong.org` 既有測試實例

**Files:** 無程式碼變更——這是一次性的維運操作，記錄過程於本檔案供未來追溯，不新增任何 repo 內檔案。

**Interfaces:**
- Consumes：Task 1 的 migration 檔案內容（作為要透過 Admin API 手動套用的目標 schema）。
- Produces：`pbdev.jigong.org` 上 `sync_reading_positions` collection 的 `indexes` 陣列新增 Task 1 定義的那一筆 unique index。供 Task 4 的真機整合測試驗證。

依 Global Constraints，套用前必須先確認沒有重複紀錄。**2026-08-04 撰寫本計畫時已查證一次**：透過 Admin API 查詢 `pbdev.jigong.org` 的 `sync_reading_positions`，`totalItems: 0`（因為 Issue 5/6 的整合測試皆在 `tearDown`/`addTearDown` 清空這個帳號底下的紀錄），當下沒有任何重複。**但執行本 Task 時務必重新查一次**——距離撰寫計畫到實際執行可能有時間差，其間可能有其他 Issue 的真機測試留下未清理的資料。

- [x] **Step 1：取得 superuser 認證**

Superuser email／密碼**不落地存放在版本控制內**（見 `pocketbase-self-hosting.md`「首次啟動」段落），需要時向人類詢問。取得後：

```bash
TOKEN=$(curl -sS -X POST http://pbdev.jigong.org/api/collections/_superusers/auth-with-password \
  -H "Content-Type: application/json" \
  -d '{"identity":"<superuser email>","password":"<superuser password>"}' | python3 -c "import sys,json; print(json.load(sys.stdin)['token'])")
echo "token acquired: ${TOKEN:0:10}..."
```

Expected：能取得非空 token（不要把完整 token 印出到任何會落地存檔的地方）。

- [x] **Step 2：查詢是否有重複紀錄**

```bash
curl -sS -G http://pbdev.jigong.org/api/collections/sync_reading_positions/records \
  -H "Authorization: $TOKEN" --data-urlencode "perPage=500" | python3 -c "
import sys, json
d = json.load(sys.stdin)
items = d['items']
print('total records:', d['totalItems'])
seen = {}
for it in items:
    key = (it['user'], it['book_fingerprint'])
    seen.setdefault(key, []).append(it['id'])
dupes = [(k, v) for k, v in seen.items() if len(v) > 1]
print('duplicate groups:', len(dupes))
for d2 in dupes:
    print(d2)
"
```

Expected（依 2026-08-04 查證結果）：`total records: 0`，`duplicate groups: 0`。

**若這次查到的 `duplicate groups` 不是 0**：對每組重複，保留 `updated` 最新的一筆，其餘用
`curl -X DELETE http://pbdev.jigong.org/api/collections/sync_reading_positions/records/<id> -H "Authorization: $TOKEN"`
刪除，刪除後重新查一次確認 `duplicate groups: 0` 才能進行下一步。

- [x] **Step 3：透過 Admin API 直接套用 unique index**（比照 Issue 5 修補 `created`／`updated` 欄位時已驗證過的做法——直接呼叫 Admin API，不透過檔案部署／重啟容器，因為既有測試實例的 migration 檔案部署機制不在本 repo 範圍內，見 `pocketbase-self-hosting.md`「測試環境」段落）

```bash
python3 <<'PYEOF'
import json, urllib.request

TOKEN = "<上一步取得的 token>"
BASE = "http://pbdev.jigong.org"

req = urllib.request.Request(f"{BASE}/api/collections/sync_reading_positions", headers={"Authorization": TOKEN})
with urllib.request.urlopen(req) as resp:
    col = json.load(resp)

index_name = "idx_sync_reading_positions_user_fp"
already = any(index_name in idx for idx in col["indexes"])
if already:
    print("already applied, skipping")
else:
    col["indexes"].append(
        f"CREATE UNIQUE INDEX `{index_name}` ON `sync_reading_positions` (`user`, `book_fingerprint`)"
    )
    data = json.dumps({"indexes": col["indexes"]}).encode()
    req2 = urllib.request.Request(f"{BASE}/api/collections/sync_reading_positions", data=data, method="PATCH",
                                   headers={"Authorization": TOKEN, "Content-Type": "application/json"})
    with urllib.request.urlopen(req2) as resp2:
        result = json.load(resp2)
    print("applied, indexes now:", result["indexes"])
PYEOF
```

Expected：輸出 `applied, indexes now: [...]`，內含剛新增的 index 字串。

- [x] **Step 4：驗證約束確實生效**

```bash
USERTOKEN=$(curl -sS -X POST http://pbdev.jigong.org/api/collections/users/auth-with-password \
  -H "Content-Type: application/json" \
  -d '{"identity":"epic8-issue2-test@example.com","password":"epic8-test-password-123"}' | python3 -c "import sys,json; print(json.load(sys.stdin)['token'])")
USERID=$(curl -sS http://pbdev.jigong.org/api/collections/users/auth-refresh -X POST -H "Authorization: $USERTOKEN" | python3 -c "import sys,json; print(json.load(sys.stdin)['record']['id'])")

curl -sS -X POST http://pbdev.jigong.org/api/collections/sync_reading_positions/records \
  -H "Authorization: $USERTOKEN" -H "Content-Type: application/json" \
  -d "{\"user\":\"$USERID\",\"book_fingerprint\":\"issue9-verify-fp\",\"pdf_page_index\":1,\"progress\":0.1}"

curl -sS -w "\nHTTP %{http_code}\n" -X POST http://pbdev.jigong.org/api/collections/sync_reading_positions/records \
  -H "Authorization: $USERTOKEN" -H "Content-Type: application/json" \
  -d "{\"user\":\"$USERID\",\"book_fingerprint\":\"issue9-verify-fp\",\"pdf_page_index\":2,\"progress\":0.2}"

# 清理驗證用的紀錄（一行處理完，不需要手動逐一複製 id）
curl -sS -G http://pbdev.jigong.org/api/collections/sync_reading_positions/records \
  -H "Authorization: $TOKEN" --data-urlencode "filter=book_fingerprint = \"issue9-verify-fp\"" \
  | python3 -c "import sys, json; [print(it['id']) for it in json.load(sys.stdin)['items']]" \
  | xargs -I {} curl -sS -X DELETE http://pbdev.jigong.org/api/collections/sync_reading_positions/records/{} -H "Authorization: $TOKEN"
```

Expected：第一次 `HTTP 200`；第二次 `HTTP 400`（`validation_not_unique`）。驗證完畢後務必清理掉這筆測試資料，避免污染共用測試帳號（比照既有 `clearRemoteData()` 慣例）。

- [x] **Step 5：記錄套用結果**

在本檔案（`plan-issue-9.md`）文末「審查修正紀錄」段落新增一筆記錄（Task 5 撰寫時一併處理，見下）；本 Step 本身不需要 commit（沒有程式碼異動），但確保 Task 2 的執行者已經口頭/訊息告知後續 Task 的執行者「`pbdev.jigong.org` 已套用」，避免重複套用時的困惑（雖然 Admin API 這個寫法本身是冪等的，重複執行會被 Step 3 的 `already` 判斷跳過）。

---

### Task 3：`SyncEngine._syncReadingPositions()` 查詢補上確定性 `sort`

**Files:**
- Modify：`app/lib/sync/sync_engine.dart`
- Test：`app/test/sync/sync_engine_test.dart`

**Interfaces:**
- Consumes：無（純粹修改既有方法內一次 API 呼叫的參數）。
- Produces：`_syncReadingPositions()` 的 `getList()` 呼叫新增 `sort: 'created'`；不改變回傳型別或任何呼叫端契約。

- [x] **Step 1：撰寫失敗測試**

在 `app/test/sync/sync_engine_test.dart` 的「閱讀位置同步（epic-8-sync Issue 5）」`group` 內（找到既有的 b20 測試，即
`test('本機閱讀位置有異動、遠端無既有紀錄時，直接推送（create）...` 那一則，插入在它之後、b21 測試之前）新增：

```dart

    test('查詢既有閱讀位置紀錄時，帶上確定性排序（epic-8-sync Issue 9，防禦性語意：unique index 生效前後皆不依賴未定義排序）',
        () async {
      await libraryRepository.insertBook(_testBook(
        'b28',
        contentFingerprint: 'fp-28',
        positionUpdatedAt: 5000,
        progress: 0.4,
      ));

      String? capturedSort;
      final mockClient = MockClient((request) async {
        if (request.method == 'GET' &&
            request.url.path == '/api/collections/sync_reading_positions/records') {
          capturedSort = request.url.queryParameters['sort'];
          return http.Response(
            jsonEncode({'items': [], 'page': 1, 'perPage': 1, 'totalItems': 0}),
            200,
            headers: {'content-type': 'application/json'},
          );
        }
        if (request.url.path == '/api/batch') {
          return http.Response(jsonEncode([]), 200,
              headers: {'content-type': 'application/json'});
        }
        return http.Response(
          jsonEncode({'items': [], 'page': 1, 'perPage': 1000, 'totalItems': 0}),
          200,
          headers: {'content-type': 'application/json'},
        );
      });

      final engine = SyncEngine(
        db: libraryRepository.database,
        accountRepository: accountRepository,
        metadataRepository: metadataRepository,
        clientFactory: (baseUrl) => PocketBase(baseUrl, httpClientFactory: () => mockClient),
      );

      await engine.runCheckpoint();

      expect(capturedSort, 'created');
    });
```

- [x] **Step 2：執行測試，確認因目前查詢沒有帶 `sort` 而失敗**

Run（於 `app/` 目錄下）：

```bash
flutter test test/sync/sync_engine_test.dart --plain-name "查詢既有閱讀位置紀錄時，帶上確定性排序"
```

Expected：FAIL，`capturedSort` 為 `null`，斷言 `expect(capturedSort, 'created')` 失敗。

- [x] **Step 3：`_syncReadingPositions()` 的 `getList()` 呼叫補上 `sort`**

`app/lib/sync/sync_engine.dart` 內，找到：

```dart
      final result = await pb.collection('sync_reading_positions').getList(
            filter: pb.filter('book_fingerprint = {:fp}', {'fp': fingerprint}),
            perPage: 1,
            headers: headers,
          );
```

改為：

```dart
      // epic-8-sync Issue 9：加上確定性排序（'created'，不受後續 update
      // 影響的欄位）——unique index 套用後 (user, book_fingerprint)
      // 理論上至多 1 筆，這裡純粹是防禦性語意：查詢行為本身不依賴
      // PocketBase 未指定 sort 時的預設排序保證（見 issues.md Issue 9）。
      final result = await pb.collection('sync_reading_positions').getList(
            filter: pb.filter('book_fingerprint = {:fp}', {'fp': fingerprint}),
            perPage: 1,
            sort: 'created',
            headers: headers,
          );
```

- [x] **Step 4：執行測試，確認通過**

Run：

```bash
flutter test test/sync/sync_engine_test.dart
```

Expected：PASS（Issue 5 既有全部測試＋本 Task 新增 1 則測試皆通過）。

- [x] **Step 5：`flutter analyze` + Commit**

```bash
flutter analyze
git add lib/sync/sync_engine.dart test/sync/sync_engine_test.dart
git commit -m "feat(epic-8-sync): Issue 9 Task 3 — _syncReadingPositions() 查詢補上確定性排序"
```

Expected：`flutter analyze` 顯示 "No issues found!"。

---

### Task 4：真機整合測試——驗證 unique index 確實拒絕重複紀錄

**Files:**
- Modify：`app/integration_test/sync_engine_test.dart`

**Interfaces:**
- Consumes：Task 2 已套用到 `pbdev.jigong.org` 的 unique index（本測試的前提條件，若 Task 2 尚未執行，本測試會失敗於「第二次建立不應該成功卻成功了」）。
- Produces：無新的程式碼介面——這是一則獨立、直接呼叫 `PocketBase` client（不經過 `SyncEngine`）的驗證測試，純粹確認 collection schema 層級的約束存在。

**注意**：比照既有慣例，執行前裝置需先連上 Tailscale；使用同一個測試帳號 `epic8-issue2-test@example.com`；測試開頭／結尾清空該帳號在 `sync_reading_positions` collection 下的紀錄。

- [x] **Step 1：撰寫真機測試**

在既有 `testWidgets(...)` 測試之後、檔案結尾 `}` 之前新增：

```dart

  testWidgets(
      'sync_reading_positions unique index：同一 (user, book_fingerprint) 嘗試建立第二筆會被 PocketBase 拒絕'
      '（epic-8-sync Issue 9）', (tester) async {
    final pb = PocketBase(testBaseUrl);
    final authData = await pb.collection('users').authWithPassword(testEmail, testPassword);
    await clearRemoteData(pb);
    addTearDown(() => clearRemoteData(pb));

    final fingerprint =
        'integration-test-unique-index-fingerprint-${DateTime.now().microsecondsSinceEpoch}';

    final first = await pb.collection('sync_reading_positions').create(body: {
      'user': authData.record.id,
      'book_fingerprint': fingerprint,
      'pdf_page_index': 1,
      'progress': 0.1,
    });
    expect(first.id, isNotEmpty);

    await expectLater(
      pb.collection('sync_reading_positions').create(body: {
        'user': authData.record.id,
        'book_fingerprint': fingerprint,
        'pdf_page_index': 2,
        'progress': 0.2,
      }),
      throwsA(
        isA<ClientException>().having(
          (e) => e.response['data'],
          'validation errors',
          predicate<Map<String, dynamic>?>(
            (data) =>
                data != null &&
                (data['book_fingerprint']?['code'] == 'validation_not_unique' ||
                    data['user']?['code'] == 'validation_not_unique'),
          ),
        ),
      ),
      reason: '同一 (user, book_fingerprint) 的第二筆建立應被 unique index 拒絕（Issue 9）',
    );
  });
```

- [x] **Step 2：確認裝置已連上 Tailscale、Task 2 已套用到 `pbdev.jigong.org`，於真實裝置/模擬器上執行**

Run：

```bash
flutter devices
flutter test integration_test/sync_engine_test.dart -d <device-id> --plain-name "sync_reading_positions unique index"
```

Expected：PASS——代表 `pbdev.jigong.org` 上的 unique index 確實拒絕了重複的 (user, book_fingerprint) 組合。

**若失敗**（第二次建立沒有拋出例外）：代表 Task 2 尚未執行，或 Admin API 套用時失敗，回頭確認 Task 2 Step 3-4。

- [x] **Step 3：Commit**

```bash
git add integration_test/sync_engine_test.dart
git commit -m "test(epic-8-sync): Issue 9 Task 4 — 真機驗證 sync_reading_positions unique index"
```

---

### Task 5：更新 spec.md／pocketbase-self-hosting.md／issues.md

**Files:**
- Modify：`docs/epics/epic-8-sync/spec.md`
- Modify：`docs/epics/epic-8-sync/pocketbase-self-hosting.md`
- Modify：`docs/epics/epic-8-sync/issues.md`
- Modify：`docs/epics/epic-8-sync/plans/plan-issue-9.md`（本檔案，勾選 checkbox＋補「審查修正紀錄」）

**Interfaces:** 無程式碼變更，純文件同步。

- [x] **Step 1：`spec.md` 補上 unique index 事實**

`docs/epics/epic-8-sync/spec.md`「PocketBase Collection Schema」段落，`sync_reading_positions` 表格（`| _(updated／created)_ | ... |` 那一列）之後新增一行：

```markdown
| _(unique index)_ | _(user, book_fingerprint)_ | 強制「每個使用者對每本書至多一筆」，2026-08-04 epic-8-sync Issue 9 補上（見 `docker/pb_migrations/1785801700_add_reading_positions_unique_index.js`） |
```

- [x] **Step 2：`pocketbase-self-hosting.md` 補上第 3 支 migration 的說明**

`docs/epics/epic-8-sync/pocketbase-self-hosting.md`「既有部署升級」段落（提到
`1785801600_add_created_updated_autodate_fields.js` 那一段）結尾新增：

```markdown

**Unique index（Issue 9）**：另外複製
`pb_migrations_example/1785801700_add_reading_positions_unique_index.js`
到同一個 `pb_migrations/` 目錄下，強制「每個使用者對每本書至多一筆閱讀
位置紀錄」——套用前請先確認 `sync_reading_positions` 沒有既存的重複
（同一 `user` + `book_fingerprint`）紀錄，否則這支 migration 會套用
失敗、導致 PocketBase 服務整個啟動失敗。
```

同時在 `sync_reading_positions` 表格下方（提到 `created`／`updated` 需要
Autodate 型別那段說明）結尾補一句：

```markdown
另外需要對 `(user, book_fingerprint)` 建立 unique index，強制「每個
使用者對每本書至多一筆」——批次建立指令碼已包含這個修正（見上方「既有
部署升級」段落）。
```

- [x] **Step 3：`issues.md` Issue 9 勾選驗收標準、標記完成**

`docs/epics/epic-8-sync/issues.md` 的「Issue 9」段落：

- `**Status:** needs-triage` 改為 `**Status:** done`。
- 4 個驗收標準 checkbox 全部改為 `- [x]`，並在最後一項後方補上：
  `（PR #<實際 PR 編號>，2026-08-XX；本機用 PocketBase v0.39.10 binary 驗證 migration 正確套用/冪等/失敗情境三種行為，`pbdev.jigong.org` 已透過 Admin API 套用並驗證，見 `plans/plan-issue-9.md`)`（`<實際 PR 編號>`／日期請在真正開 PR 後填入實際值，不要照抄本計畫文字）。

- [x] **Step 4：勾選本計畫全部 checkbox，新增審查修正紀錄段落**

把 Task 1-5 目前所有 `- [ ]` 改為 `- [x]`；在檔案最後新增：

```markdown

## 執行紀錄

- Task 1：本機 PocketBase v0.39.10 binary 驗證 migration 正確套用、冪等
  （已有欄位時跳過）、既有重複資料會讓服務啟動失敗三種情境，見對話
  紀錄。
- Task 2：`pbdev.jigong.org` 於 2026-08-XX 套用（填入實際執行日期），
  套用前查證當下 `sync_reading_positions` 為 0 筆、無重複。
```

- [x] **Step 5：`flutter analyze`（確認前面 Task 的 Dart 變更仍乾淨）+ Commit**

```bash
flutter analyze
git add ../docs/epics/epic-8-sync/spec.md ../docs/epics/epic-8-sync/pocketbase-self-hosting.md ../docs/epics/epic-8-sync/issues.md ../docs/epics/epic-8-sync/plans/plan-issue-9.md
git commit -m "docs(epic-8-sync): Issue 9 收尾——更新 spec.md／自架文件／issues.md"
```

（`../docs/...` 路徑相對於 `app/` 執行目錄；也可以在 repo 根目錄下用
`git add docs/...` 加入，兩種寫法皆可，只要全部檔案都進同一個 commit。）

---

## Self-Review Notes

- **issues.md 驗收標準覆蓋檢查**：「已確認 `pbdev.jigong.org` 上沒有既存重複紀錄，或已妥善清理」→ Task 2 Step 2（含撰寫計畫時已查證一次的紀錄，執行時要求重新查一次）。「新增的 unique index migration 正確套用（本機／測試實例皆驗證過）」→ Task 1（本機三種情境）＋ Task 2（`pbdev.jigong.org` 實際套用＋驗證）。「`_syncReadingPositions()` 的查詢補上確定性排序」→ Task 3。「新增測試驗證『同一 (user, book_fingerprint) 嘗試建立第二筆會被 PocketBase 拒絕』」→ Task 4（真機整合測試，理由見文件開頭「與 issues.md 的落差說明」第 4 點：這條驗收標準的本質是資料庫層級約束，只有真機整合測試能驗證）。
- **與 spec.md 的一致性檢查**：spec.md 目前完全沒有記錄「至多一筆」這個約束的落地機制——Task 5 補上，避免 spec.md 作為「唯一事實來源」卻遺漏這個重要限制。
- **型別一致性檢查**：Task 3 只新增一個具名參數 `sort: 'created'` 給既有的 `getList()` 呼叫，不影響 `_syncReadingPositions()` 的回傳型別（仍是 Issue 5 定案的 `({Map<String, String> positionsToConfirm, Set<String> dirtyFingerprints, Set<String> deferredBookIds})`），不影響任何呼叫端。Task 4 的整合測試直接使用 `package:pocketbase` 的 `PocketBase`／`ClientException` 型別，與既有 `integration_test/sync_engine_test.dart` 檔案已經匯入的型別一致，不需要新增 import（`PocketBase`／`ClientException` 皆來自既有的 `import 'package:pocketbase/pocketbase.dart';`）。
- **本 Issue 刻意不做的事**：不修改任何既有 migration 檔案（`1785715200_...`／`1785801600_...`）；不對 `SyncEngine` 的衝突判定邏輯（`resolveReadingPositionAction()`）做任何修改（unique index 是資料庫層級的保險，不改變既有的衝突偵測語意）；不新增追蹤欄位或對照表判斷「重複紀錄應該保留哪一筆」的自動清理邏輯（Task 2 若真的查到重複資料，人工決定保留哪一筆並手動刪除，YAGNI——這個情境理論上不該發生，真的發生時人工介入判斷比自動化規則更安全）。
- **Placeholder 掃描**：全文無 TBD/TODO；Task 5 Step 3 的「PR #<實際 PR 編號>」與「2026-08-XX」刻意保留為待實際執行時填入的欄位（非程式碼，是文件收尾步驟本身要求填入實際值的欄位，不是遺漏的空白）。

## 執行紀錄

- Task 1：本機 PocketBase v0.39.10 binary 驗證 migration 正確套用、冪等（已有欄位時跳過）、既有重複資料會讓服務啟動失敗三種情境，見對話紀錄。
- Task 2：`pbdev.jigong.org` 於 2026-08-04 套用，套用前查證當下 `sync_reading_positions` 為 0 筆、無重複。
- Task 3：`_syncReadingPositions()` 的 `getList()` 補上 `sort: 'created'`，19/19 測試通過。
- Task 4：真機整合測試驗證 unique index 拒絕重複紀錄，在 Android 15 實機通過。
- Task 5：更新 spec.md／pocketbase-self-hosting.md／issues.md，Issue 9 標記為 done。
