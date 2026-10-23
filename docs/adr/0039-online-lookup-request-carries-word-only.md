# ADR 0039：線上查詢請求型別只帶一個詞

## 狀態

已採納（2026-10-22）。對應 `epic-63-dictionary-lookup` Issue 3（服務契約）、Issue 7（萌典與同意）。

## 背景

線上查詞會把使用者的文字送到第三方（萌典，`www.moedict.tw`）。技術上，若請求型別帶著「選取的詞＋前後文＋書名／位置」，消歧品質會更好——同樣的「水」在《紅樓夢》與水利工程書裡意思不同。

但本專案的隱私立場是「只送選取的那個詞」：書名、前後文、閱讀位置、裝置識別都不送。這件事不能只靠呼叫端自律（任何一次重構都可能讓某個呼叫端「順手」把 context 傳進來），而且 `AndroidManifest.xml` 開了 `usesCleartextTraffic="true"`，還要額外保證只走 `https`。

## 決策

1. `LookupRequest`（`app/lib/dictionary/models/lookup_request.dart`）**只有 `word` 一個欄位**，並宣告為 `final class`：其他檔案不能繼承或實作它來夾帶欄位。
2. 以測試固定這個型別：`app/test/dictionary/lookup_request_test.dart::型別只有 word 一個欄位，防止日後加前後文欄位`（檢查欄位集合）與 `::是 final class，其他檔案無法繼承或實作它來夾帶前後文欄位`。任何人加欄位都會先看到紅燈。
3. `DictionaryService` 只把正規化後的原字串放進請求（`dictionary_service_test.dart::送出的是 normalizeLookupSelection 後的字串`），候選鏈只用於本機查詢，不送給線上（`::不送候選詞：中文選字時線上 provider 只被呼叫一次`）。
4. `MoedictProvider` 的網址只由詞組成（`https://www.moedict.tw/uni/{詞}`），拒絕非 `https`、不跟重導向，且不帶 cookie 或自訂識別標頭（`moedict_provider_test.dart::請求網址只含詞`、`::拒絕非 https`、`::不跟重導向`）。
5. 同意狀態存 `shared_preferences`（`onlineConsentAt`），有值＝已同意且開啟；未同意時 `DictionaryService` 不建立線上分段、不發出任何請求（`dictionary_service_test.dart::未同意：純中文選字回 skipped，網路呼叫 0`、`::未同意：真 MoedictProvider 不發出任何 HTTP 請求`）。
6. 授權頁與資料來源標示（`app/assets/licenses/moedict-data.txt`）與同意對話框說明同一組事實：只送選取的詞、送去哪裡、不送什麼。

## 替代方案與取捨

- **送前後文以提高消歧品質**：被否決。這會讓第三方取得書中內容片段，與「預設關閉、需明確同意、只送一個詞」的承諾不一致；且同意對話框與隱私頁都得重新設計成「可能送出書籍內容」，使用者的同意成本變高。
- **只送詞，但把型別留成可擴充的 map／可選欄位**：被否決。可選欄位等於為未來的情境化查詞留後門，測試也無法從型別上保證；寧可現在限制死。
- **另建一個 `ContextualLookupRequest` 與第二套同意流程**：保留為未來選項，不在 Phase 1。若日後真的要做情境化查詞，必須是另一個型別、另一套同意與隱私說明，**不與 `LookupRequest` 共用**；`epic.md` §11 對「把前後文送去 AI 服務」也採同一立場（獨立型別、獨立同意流程）。

## 後果

- 查詢消歧只能靠詞本身與候選鏈；同詞多義時顯示該詞的所有釋義，不試圖用上下文挑選。
- 隱私保證是「型別層級」的：即使呼叫端想多送，也編譯不過。審查時不需要逐條追呼叫端。
- 搜尋品質的改進空間受限；若日後要做情境化查詞，成本是一個新型別、一套新同意流程、以及同意對話框與隱私頁的改版。
- 這個決定的測試（`lookup_request_test.dart`）同時是守衛：未來若有人加欄位，CI 會失敗而不是悄無聲息地擴大送出範圍。
