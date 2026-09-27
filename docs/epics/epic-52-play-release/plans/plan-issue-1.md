# Issue 1：release 建置改用上傳金鑰簽章 實作計畫

> **給執行者（agentic worker）：** 必須使用子技能 superpowers:subagent-driven-development（建議）或 superpowers:executing-plans，逐一執行本計畫的 Task。步驟使用核取方塊（`- [ ]`），完成一個就改成 `- [x]`。

**目標：** `flutter build appbundle` 在有 `app/android/key.properties` 時用上傳金鑰簽章；沒有時退回 debug 簽章並印出警告；設定寫錯時建置直接失敗，錯誤訊息寫出原因。

**架構：** 只改 `app/android/app/build.gradle.kts`。檔案頂端讀取 `key.properties`，並在設定階段（configuration phase）檢查欄位；`android.signingConfigs` 只在檔案存在時建立 `release`；`buildTypes.release` 依檔案是否存在，選用 `release` 或 `debug` 簽章。另外新增 `app/android/key.properties.example` 當樣板。

**技術：** Gradle Kotlin DSL、Android Gradle Plugin、`java.util.Properties`、JDK `keytool`。

**規格：** `docs/epics/epic-52-play-release/issues.md` Issue 1、`docs/research/google_play_release_sop.md` 第 1.2、1.3、2.5 節。

## 全域限制

- `key.properties` 位置：`app/android/key.properties`（用 `rootProject.file("key.properties")` 取得，`rootProject` 是 `app/android/`）。
- 4 個欄位名稱固定：`storePassword`、`keyPassword`、`keyAlias`、`storeFile`。
- `storeFile` 要寫絕對路徑，並使用正斜線 `/`。
- 不改任何 `.gitignore`。`app/android/.gitignore` 已經忽略 `key.properties`、`**/*.jks`、`**/*.keystore`。
- 不刪除 `build.gradle.kts` 第 72 行 `applicationId` 的 TODO 註解（不在本 Issue 範圍）。
- 錯誤訊息用正體中文三段式：發生什麼、為什麼、要做什麼。不印出密碼。
- 本計畫的 shell 指令一律在 **Git Bash** 執行（repo 根目錄）。Claude Code 的 Bash 工具就是 Git Bash，裡面有 `grep`、`printf`、heredoc，可以直接用。如果執行環境只有 PowerShell（例如 Antigravity），不要把指令改寫成 PowerShell，改用 `& "C:\Program Files\Git\bin\bash.exe" -lc '<指令>'` 包起來執行，或先開一個 Git Bash 再照做。
- 每次執行指令都是新的 shell，變數和 `cd` 不會保留到下一次。所以本計畫的路徑都寫完整，每個指令區塊都要整塊一次執行，並在區塊結尾 `cd` 回 repo 根目錄。
- 真正的上傳金鑰（`C:/Users/huthief/.android-keys/elinkbook-upload.jks`）不在本計畫中產生或使用。驗證一律用暫存資料夾裡的測試金鑰。

## Review Focus

1. **Windows 反斜線路徑**：`.properties` 格式把 `\` 當跳脫字元，`storeFile=C:\Users\huthief\...` 讀進來會變成 `C:Usershuthief...`。使用者預期看到「找不到檔案」並附上解析後的路徑，而不是看不懂的錯誤。Task 1 情境 C 會用這個路徑確認錯誤訊息印出解析後的路徑，而且 `key.properties.example` 寫明要用正斜線。例外：路徑裡出現小寫 `\u`（例如 `C:\upload\...`）時，Java 在讀檔階段就會丟出 `Malformed \uxxxx encoding`，不會走到我們的訊息。這種路徑很少見，本計畫不另外處理，靠 example 檔的正斜線規則預防。
2. **欄位值只有空白**：`storePassword=   ` 要當成缺少欄位，不能拿空白當密碼。Task 1 情境 B 用只有空白的值測試，情境 B2 測整行不存在。
3. **debug 建置不受影響**：`key.properties` 寫錯時，`flutter run`（debug）也會失敗，因為檢查在設定階段執行。這是刻意的：設定錯了應該馬上知道。Task 1 情境 B 的預期結果寫明這一點。
4. **錯誤訊息不能洩漏密碼**：任何錯誤訊息只能出現欄位名稱和檔案路徑。Task 1 每個失敗情境都要確認輸出裡沒有測試密碼字串。
5. **`key.properties.example` 不能被忽略**：它要能進版控。Task 1 Step 7 用 `git check-ignore` 確認。

---

### Task 1：`build.gradle.kts` 讀取 `key.properties` 並設定 release 簽章

**Files:**
- Modify: `app/android/app/build.gradle.kts`（第 1～3 行 import、第 48 行之後新增讀檔區塊、第 93～99 行 `buildTypes`）
- Create: `app/android/key.properties.example`

**Interfaces:**
- Consumes：無。
- Produces：Gradle 變數 `keystoreProperties: Properties?`（`null` 表示沒有 `key.properties`）；`signingConfigs` 內名為 `release` 的簽章設定（只在檔案存在時建立）。Task 2 用 `flutter build appbundle` 驗證這些行為。

這個 Issue 改的是 Gradle 設定，沒有單元測試框架可用。每個情境改用 `./gradlew :app:signingReport` 驗證：它會跑完整的設定階段，並列出每個 variant 用哪個金鑰檔，比完整建置快很多。

- [x] **Step 1：開分支並準備測試金鑰**

```bash
git switch main && git pull
git switch -c epic-52/issue-1-release-signing
```

產生一把只給測試用的金鑰，放在 repo 外面：

```bash
mkdir -p "C:/Users/huthief/AppData/Local/Temp/epic52-keys"
keytool -genkeypair -v -keystore "C:/Users/huthief/AppData/Local/Temp/epic52-keys/test-upload.jks" -keyalg RSA -keysize 2048 -validity 1 -alias upload -storepass testpass123 -keypass testpass123 -dname "CN=Epic52 Test, O=elinkBook Test, C=TW"
```

預期：`C:/Users/huthief/AppData/Local/Temp/epic52-keys/test-upload.jks` 建立完成。

後面所有步驟都直接寫這個完整路徑，不用變數。原因是每次執行指令都是新的 shell，變數不會保留。

- [x] **Step 2：記錄修改前的行為（紅燈）**

確認 `app/android/key.properties` 不存在：

```bash
ls app/android/key.properties
```

預期：`No such file or directory`。

建立一個指向測試金鑰的 `key.properties`：

```bash
cat > app/android/key.properties <<EOF
storePassword=testpass123
keyPassword=testpass123
keyAlias=upload
storeFile=C:/Users/huthief/AppData/Local/Temp/epic52-keys/test-upload.jks
EOF
cd app/android && ./gradlew :app:signingReport 2>&1 | grep -A4 "Variant: release$"; cd ../..
```

預期（紅燈）：`Store:` 那一行指向 `debug.keystore`，不是 `test-upload.jks`。這證明目前的設定會忽略 `key.properties`。

刪除這個檔案：

```bash
rm app/android/key.properties
```

- [x] **Step 3：新增 import 與讀檔區塊**

在 `app/android/app/build.gradle.kts` 第 3 行 `import java.util.Date` 之後加入：

```kotlin
import java.util.Properties
```

在第 48 行 `val oneDriveOAuthScheme = "msal$rawOneDriveOAuthClientId"` 之後、`android {` 之前加入：

```kotlin

// epic-52-play-release Issue 1：release 建置的上傳金鑰設定。
//
// 讀取 app/android/key.properties（rootProject 是 app/android/）。這個檔案
// 含密碼，已由 app/android/.gitignore 排除，不進版控；樣板見
// key.properties.example。三種情況：
// 1. 檔案不存在：release 退回 debug 簽章並印出警告，讓沒有金鑰的環境
//    （例如只跑測試）仍能執行 `flutter run --release`。
// 2. 檔案存在但欄位缺少或空白：直接讓建置失敗。這代表發布者想正式簽章
//    卻設定錯了，不能默默改用 debug 簽章，否則上傳到 Play 才會被拒收。
// 3. 檔案存在且欄位齊全：release 用上傳金鑰簽章（見下方 signingConfigs）。
//
// 用 UTF-8 Reader 讀檔：Properties.load(InputStream) 固定用 ISO-8859-1 解碼，
// 路徑含中文時會變成亂碼。
val keystorePropertiesFile = rootProject.file("key.properties")
val keystoreProperties: Properties? = if (keystorePropertiesFile.isFile) {
    Properties().apply { keystorePropertiesFile.reader(Charsets.UTF_8).use { load(it) } }
} else null

if (keystoreProperties != null) {
    // 只有空白的值也當成缺少，避免拿空白字串當密碼。
    val missingKeys = listOf("storePassword", "keyPassword", "keyAlias", "storeFile")
        .filter { keystoreProperties.getProperty(it).isNullOrBlank() }
    if (missingKeys.isNotEmpty()) {
        throw GradleException(
            "release 簽章設定不完整：${keystorePropertiesFile.absolutePath} 缺少欄位 " +
                "${missingKeys.joinToString("、")}。" +
                "這個檔案存在時，4 個欄位都必須填寫。" +
                "請參考 key.properties.example 補齊欄位；不打算正式簽章時，直接刪除這個檔案。"
        )
    }
}
```

- [x] **Step 4：新增 `signingConfigs` 並改寫 `buildTypes`**

在 `android {` 區塊內、`defaultConfig {` 之前加入：

```kotlin
    signingConfigs {
        if (keystoreProperties != null) {
            create("release") {
                // project.file() 以 app/android/app/ 為基準解析相對路徑，所以
                // key.properties 的 storeFile 規定寫絕對路徑。
                // Properties 只會去掉值前面的空白，後面的空白要自己去掉。
                // 密碼不做 trim，因為空白可能是密碼的一部分。
                val uploadKeystore = project.file(keystoreProperties.getProperty("storeFile").trim())
                if (!uploadKeystore.exists()) {
                    throw GradleException(
                        "找不到上傳金鑰檔：${uploadKeystore.absolutePath}。" +
                            "key.properties 的 storeFile 指向的檔案不存在。" +
                            "請改成金鑰檔的絕對路徑，並使用正斜線 /（例如 C:/Users/huthief/.android-keys/elinkbook-upload.jks）。"
                    )
                }
                storeFile = uploadKeystore
                storePassword = keystoreProperties.getProperty("storePassword")
                keyAlias = keystoreProperties.getProperty("keyAlias").trim()
                keyPassword = keystoreProperties.getProperty("keyPassword")
            }
        }
    }

```

把第 93～99 行：

```kotlin
    buildTypes {
        release {
            // TODO: Add your own signing config for the release build.
            // Signing with the debug keys for now, so `flutter run --release` works.
            signingConfig = signingConfigs.getByName("debug")
        }
    }
```

改成：

```kotlin
    buildTypes {
        release {
            signingConfig = if (keystoreProperties != null) {
                signingConfigs.getByName("release")
            } else {
                // 用 quiet 層級：flutter build 在非 verbose 模式會帶 -q 呼叫 Gradle，
                // warn 層級的訊息會被隱藏，quiet 層級才看得到。
                project.logger.quiet(
                    "警告：找不到 ${keystorePropertiesFile.absolutePath}，release 建置改用 debug 金鑰簽章。" +
                        "這個版本不能上傳到 Google Play。" +
                        "要正式發布時，請依 docs/research/google_play_release_sop.md 第 1.3 節建立 key.properties。"
                )
                signingConfigs.getByName("debug")
            }
        }
    }
```

- [x] **Step 5：建立 `key.properties.example`**

建立 `app/android/key.properties.example`：

```properties
# release 上傳金鑰設定樣板（epic-52-play-release Issue 1）。
#
# 使用方式：複製成同一個資料夾的 key.properties，再填入真正的值。
# key.properties 含密碼，已由 app/android/.gitignore 排除，絕對不能進版控。
# 詳細步驟見 docs/research/google_play_release_sop.md 第 1.2、1.3 節。
#
# 規則：
# - 4 個欄位都要填。檔案存在但缺欄位時，建置會直接失敗。
# - storeFile 要寫絕對路徑，並使用正斜線 /。
#   .properties 格式會把反斜線 \ 當成跳脫字元，寫 C:\Users\... 會讀錯。
# - 不打算正式簽章時，不要建立 key.properties；release 會自動改用 debug 金鑰。
storePassword=<store password>
keyPassword=<key password>
keyAlias=upload
storeFile=C:/Users/huthief/.android-keys/elinkbook-upload.jks
```

- [x] **Step 6：逐一確認 5 個情境（綠燈）**

每個情境結束都要刪除 `app/android/key.properties`。

**情境 A：沒有 `key.properties`**

```bash
cd app/android && ./gradlew :app:signingReport 2>&1 | grep -E "警告：找不到|Variant: release$" -A4; cd ../..
```

預期：出現「警告：找不到 …key.properties，release 建置改用 debug 金鑰簽章」；`Variant: release` 的 `Store:` 指向 `debug.keystore`。

**情境 B：欄位只有空白**

```bash
printf 'storePassword=   \nkeyPassword=testpass123\nkeyAlias=upload\nstoreFile=C:/Users/huthief/AppData/Local/Temp/epic52-keys/test-upload.jks\n' > app/android/key.properties
cd app/android && ./gradlew :app:signingReport 2>&1 | tee /tmp/epic52-b.log | grep "release 簽章設定不完整"; cd ../..
grep -c "testpass123" /tmp/epic52-b.log
rm app/android/key.properties
```

`storePassword=` 後面有 3 個空白，用來確認「只有空白」會被當成缺少。

預期：建置失敗，錯誤訊息包含「缺少欄位 storePassword」；`grep -c` 印出 `0`（錯誤輸出裡沒有密碼）。這個失敗發生在設定階段，所以此時 `flutter run`（debug）也會失敗，這是預期行為。

**情境 B2：整行不存在**

Issue 1 的驗收標準分開寫了「欄位缺少」和「只有空白」。程式碼裡兩者走同一條路（`getProperty` 回傳 `null` 時，`isNullOrBlank()` 也是 `true`），這裡仍實際確認一次。

```bash
printf 'storePassword=testpass123\nkeyAlias=upload\nstoreFile=C:/Users/huthief/AppData/Local/Temp/epic52-keys/test-upload.jks\n' > app/android/key.properties
cd app/android && ./gradlew :app:signingReport 2>&1 | tee /tmp/epic52-b2.log | grep "release 簽章設定不完整"; cd ../..
grep -c "testpass123" /tmp/epic52-b2.log
rm app/android/key.properties
```

預期：建置失敗，錯誤訊息包含「缺少欄位 keyPassword」；`grep -c` 印出 `0`。

**情境 C：`storeFile` 用反斜線路徑**

這裡故意用真實路徑的反斜線寫法。`.properties` 會把 `\U`、`\h` 這類組合的反斜線吃掉，讀進來變成 `C:Usershuthief.android-keyselinkbook-upload.jks`。

```bash
cat > app/android/key.properties <<'EOF'
storePassword=testpass123
keyPassword=testpass123
keyAlias=upload
storeFile=C:\Users\huthief\.android-keys\elinkbook-upload.jks
EOF
cd app/android && ./gradlew :app:signingReport 2>&1 | tee /tmp/epic52-c.log | grep "找不到上傳金鑰檔"; cd ../..
grep -c "testpass123" /tmp/epic52-c.log
rm app/android/key.properties
```

預期：建置失敗，錯誤訊息包含「找不到上傳金鑰檔：」加上解析後的完整路徑，以及「使用正斜線 /」的提示；`grep -c` 印出 `0`。

**情境 D：正確設定**

```bash
cat > app/android/key.properties <<EOF
storePassword=testpass123
keyPassword=testpass123
keyAlias=upload
storeFile=C:/Users/huthief/AppData/Local/Temp/epic52-keys/test-upload.jks
EOF
cd app/android && ./gradlew :app:signingReport 2>&1 | grep -A4 "Variant: release$"; cd ../..
```

預期：`Store:` 指向 `test-upload.jks`，`Alias: upload`；輸出沒有「警告：找不到」。**這個檔案留著給 Task 2 用，先不要刪除。**

- [x] **Step 7：確認 git 狀態**

```bash
git check-ignore -v app/android/key.properties
git check-ignore -v app/android/key.properties.example; echo "exit=$?"
git status --short
```

預期：
- 第一行輸出包含 `app/android/.gitignore` 和 `key.properties`。
- 第二個指令沒有輸出，`exit=1`（example 檔沒有被忽略）。
- `git status` 只列出 `app/android/app/build.gradle.kts` 和 `app/android/key.properties.example`，沒有 `key.properties`。

- [x] **Step 8：Commit**

```bash
git add app/android/app/build.gradle.kts app/android/key.properties.example
git commit -m "feat(android): release 建置改用 key.properties 上傳金鑰簽章（epic-52 Issue 1）"
```

---

### Task 2：完整建置驗證與收尾

**Files:**
- Modify：`docs/epics/epic-52-play-release/issues.md`（Issue 1 的 Status）
- Modify：`docs/epics/epic-52-play-release/epic.md`（開發記錄）

**Interfaces:**
- Consumes：Task 1 的 `release` 簽章設定；Task 1 情境 D 留下的 `app/android/key.properties`。
- Produces：無。

- [ ] **Step 1：用測試金鑰建置 `.aab` 並確認簽章**

```bash
cd app
flutter build appbundle --release --dart-define-from-file=config/cloud_oauth.json
keytool -printcert -jarfile build/app/outputs/bundle/release/app-release.aab | grep "CN="
cd ..
```

預期：建置成功；輸出包含 `CN=Epic52 Test, O=elinkBook Test, C=TW`。這裡比對 `CN=`，不比對 `Owner`／`擁有者`，因為那個標籤會隨 JDK 語系改變。

- [ ] **Step 2：刪除 `key.properties`，確認退回 debug 簽章**

```bash
rm app/android/key.properties
cd app
rm -f build/app/outputs/bundle/release/app-release.aab
flutter build appbundle --release --dart-define-from-file=config/cloud_oauth.json 2>&1 | grep "警告：找不到"
ls build/app/outputs/bundle/release/app-release.aab
keytool -printcert -jarfile build/app/outputs/bundle/release/app-release.aab | grep "CN="
cd ..
```

先刪掉 Step 1 的 `.aab`，確保後面檢查的是這次新建置的檔案。

預期：
- 印出「警告：找不到 …」。
- `ls` 找得到 `app-release.aab`（這次真的有產出新檔案）。
- 輸出包含 `CN=Android Debug`。

如果看不到警告：在 `flutter build appbundle` 後面加 `-v` 重跑一次。有 `-v` 才看得到，代表 `logger.quiet` 仍被 Flutter 過濾，記進 `epic.md`，但不算失敗，因為 Task 1 情境 A 已經用 Gradle 直接確認過警告。

- [ ] **Step 3：分析與測試**

```bash
cd app
flutter analyze
flutter test
cd ..
```

預期：`flutter analyze` 顯示 `No issues found!`；`flutter test` 全部通過。這個 Issue 沒有改 Dart 程式碼，全套測試是計畫最後一個 Task 的例行確認。

- [ ] **Step 4：刪除測試金鑰**

```bash
rm -rf "C:/Users/huthief/AppData/Local/Temp/epic52-keys" /tmp/epic52-b.log /tmp/epic52-b2.log /tmp/epic52-c.log
ls app/android/key.properties
```

預期：最後一行印出 `No such file or directory`。

- [ ] **Step 5：更新進度文件**

`docs/epics/epic-52-play-release/issues.md` Issue 1 的 `**Status:** open` 改成 `**Status:** completed`。

`docs/epics/epic-52-play-release/epic.md` 最後加入：

```markdown

**YYYY-MM-DD Issue 1 完成**：`build.gradle.kts` 讀取 `app/android/key.properties` 設定 release 簽章；檔案不存在時退回 debug 簽章並警告，欄位缺少或金鑰檔不存在時建置失敗。新增 `key.properties.example`。以測試金鑰驗證 5 個情境（A、B、B2、C、D）與完整 `.aab` 建置。
```

`YYYY-MM-DD` 換成當天日期。

- [ ] **Step 6：Commit**

```bash
git add docs/epics/epic-52-play-release/issues.md docs/epics/epic-52-play-release/epic.md
git commit -m "docs(epic-52): 記錄 Issue 1 完成"
```
