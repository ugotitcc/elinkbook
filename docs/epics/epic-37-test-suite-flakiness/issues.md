# Epic 37 — 全套測試套件既有不穩定性追蹤：工單清單 (Issues)

依 `design.md`「排除迴歸的驗證方法與結果」拆解為 Issue 1-3，一個檔案一個 Issue（三者程式碼領域互不相關，判斷是各自獨立的根因）。三者彼此獨立，可任意順序或平行開始；但依 `design.md`「下一步」，每個 Issue 開始排查前都必須先補做一次未截斷的完整重跑取得完整資訊，目前都卡在這一步之前，皆為 `needs-info`。

---

## Issue 1：`reader_screen_test.dart` 全套規模下偶發失敗（PDF 畫線手勢相關）

**Status:** `needs-info`

**依賴：** 無

**目前已知資訊（不完整，見「已知限制」）：** `feat/epic-35-issue-5` 分支完整 `flutter test` 執行中，以下測試出現 `[E]`／「Test failed」明確標記：
- 「PDF：框選矩形命中既有畫線時，工具列顯示刪除按鈕，點擊後刪除該畫線」
- 「PDF 原地長按既有標記（退化選取，epic-25-annotation-interaction-qa Issue 6）PDF：退化選取命中既有劃線時，顯示工具列且帶刪除鈕（epic-25 Issue 6）」（此筆在最後 40 行片段中只看到測試名稱重新開始執行，未能確認是否也標記失敗，需重新驗證）

同一個檔案單獨執行（`flutter test test/screens/reader_screen_test.dart`，於 `main`）100% 全過，代表問題只在全套規模一起跑時出現。

**已知限制：** 發現當下的執行指令是 `flutter test 2>&1 | tail -40`，只保留了最後 40 行輸出；背景程序結束後完整輸出已遺失，無法確認 29 個失敗裡實際歸屬本檔案的確切筆數與各自例外堆疊。

**下一步：** 用 `flutter test test/screens/reader_screen_test.dart > <log> 2>&1`（不接 `tail`）搭配完整 `flutter test`（不帶檔案路徑、同樣不截斷）各跑數次，比對「單檔跑」與「全套跑」的差異、以及全套跑重複執行時失敗的是否為同一批測試，確認是否為決定性失敗（可排查根因）還是純計時類不穩定。

---

## Issue 2：`remote_catalog_screen_test.dart` 全套規模下偶發失敗（遠端下載排隊相關）

**Status:** `needs-info`

**依賴：** 無

**目前已知資訊（不完整，見「已知限制」）：** `feat/epic-35-issue-5` 分支完整 `flutter test` 執行的最後 40 行輸出裡，本檔案的多筆測試（例如「下載與匯入 多選批次下載時逐項序列進行，非平行」「下載與匯入 下載失敗時顯示失敗狀態並可手動重試」等）反覆出現在進度輸出中；`flutter test` 預設會平行跑多個測試檔，同一測試名稱重複出現在進度行不必然代表失敗（可能只是其所在檔案的分片尚未輪到下一筆），**目前無法從留存片段確認本檔案實際有幾筆真正失敗、是哪幾筆**。

同一個檔案單獨執行（`flutter test test/screens/remote_catalog_screen_test.dart`，於 `main`）100% 全過。

**已知限制：** 同 Issue 1，發現當下的執行指令被 `tail -40` 截斷，完整失敗清單與例外堆疊已遺失。

**下一步：** 同 Issue 1，先用不截斷的方式重跑取得本檔案在全套規模下的確切失敗清單與例外堆疊，再判斷是否為決定性失敗。

---

## Issue 3：`pdf_reader_view_test.dart` 全套規模下偶發失敗（平台通道位元組讀取次數斷言）

**Status:** `needs-info`

**依賴：** 無

**目前已知資訊（三者中唯一有完整例外堆疊的一筆，來自 `main` 分支未截斷的完整 `flutter test` 存檔輸出）：**

測試：「content:// URI 開書透過平台通道一次性讀取全部位元組」（`app/test/reader/pdf_reader_view_test.dart:162`）

```
Expected: <1>
  Actual: <0>

#4      main.<anonymous closure> (file:///U:/MyDeveloper/AI/elinkBook/app/test/reader/pdf_reader_view_test.dart:162:5)
<asynchronous suspension>
#5      testWidgets.<anonymous closure>.<anonymous closure> (package:flutter_test/src/widget_tester.dart:192:15)
```

斷言「預期為 1、實際為 0」——形式上像是斷言某個 mock／平台通道方法被呼叫的次數，在全套規模下該次呼叫沒有發生（次數變成 0）。與 `CLAUDE.md`「`content://` URI 存取走原生端 `ReaderResourceChannel.kt` 串流複製到本機暫存檔後再開啟」這個既有機制的呼叫時機有關，但尚未查證是測試本身的等待時機不足（例如缺少對應的 `pumpAndSettle`／非同步等待），還是全套規模下真的有平台通道呼叫被跳過。

**下一步：** 讀取 `app/test/reader/pdf_reader_view_test.dart` L140-170 附近的測試內容與其 mock 設置，確認斷言對象的呼叫時機依賴；用不截斷方式重跑完整 `flutter test` 數次，確認這筆失敗是否每次都重現在同一位置（決定性）。
