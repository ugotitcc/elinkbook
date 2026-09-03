# `epic-37-test-suite-flakiness` 全套測試套件既有不穩定性追蹤

**狀態：** 🟡 開發中 (Active)
**存放路徑：** `docs/epics/epic-37-test-suite-flakiness/`
**關聯 PRD 章節：** 無單一 FR，屬跨功能的測試基礎設施品質問題

## 開發記錄

2026-09-03 從 `epic-35-design-system-tokens` Issue 5 收尾階段的完整 `flutter test` 最終確認中發現：在 `.worktrees/epic-35-issue-5`（等同 `main` 於 `434fe70a` 的 `app/` 程式碼）跑不帶檔案路徑的完整 `flutter test`，1873 個測試中出現 29 個失敗，集中在 `app/test/screens/reader_screen_test.dart`（PDF 畫線手勢相關）與 `app/test/screens/remote_catalog_screen_test.dart`（遠端下載排隊相關）；隨即在 `main`（`cc07c4f7`，與 `434fe70a` 的 `app/` 程式碼完全相同，中間僅 docs 異動）跑同一份完整 `flutter test` 做基準對照，1898 個測試中也出現 1 個失敗（`app/test/reader/pdf_reader_view_test.dart`）。兩次個別單獨執行涉事測試檔皆 100% 全過，證實：**這是「跑全套規模」時才會出現的既有不穩定測試，不是 Issue 5 改動造成的迴歸**，但也不是全新現象——因為連 `main` 本身用同一種跑法都會出現失敗。經人類確認開立本 Epic 統一追蹤，之後再發現的同類全套測試不穩定案例，一律歸到這裡，不要分散到各功能 Epic。

拆為 3 個 Issue（見 `issues.md`）：Issue 1（`reader_screen_test.dart`）、Issue 2（`remote_catalog_screen_test.dart`）、Issue 3（`pdf_reader_view_test.dart`，唯一有完整例外堆疊可查的一筆）。三者目前皆為 `needs-info`——受限於發現當下的擷取方式（`epic-35-issue-5` 那次用 `tail -40` 只留下最後 40 行輸出，完整失敗清單已隨背景程序結束而遺失），尚未取得足夠資訊鎖定根因，見各 Issue 內「已知限制」段落（該段落後續已改寫為『原始觀察』）。

2026-09-03 Issue 1（`reader_screen_test.dart`）完成資訊補齊：未截斷重跑完整 `flutter test` 3 次＋單檔重跑 3 次，結果為「未重現」——3 次全套跑皆 1902 tests、0 失敗，跟 design.md 記錄的原始 29 個失敗完全不同，已更新 `issues.md` Issue 1 段落為 `ready-for-human`，交由人類決定是否需要更多次重跑或降低追蹤優先度。

2026-09-03 Issue 2（`remote_catalog_screen_test.dart`）完成資訊補齊：未截斷重跑完整 `flutter test` 3 次＋單檔重跑 3 次，3 次全套跑皆 1902 tests、0 失敗，3 次單檔重跑皆 26 tests、0 失敗，判定為未重現（跟 Issue 1 同款結果），已更新 `issues.md` Issue 2 段落與分流狀態為 `ready-for-human`。

2026-09-03 Issue 3（`pdf_reader_view_test.dart`）完成資訊補齊：未截斷重跑完整 `flutter test` 3 次（1902／1900／1902 tests）＋單檔重跑 3 次（9 tests 皆通過），判定為未重現（跟 Issue 1、Issue 2 同款結果），已更新 `issues.md` Issue 3 段落與分流狀態為 `ready-for-human`。Epic 37 三個 Issue 皆已完成資訊補齊，是否歸檔或針對個別 Issue 開後續工單由人類決定。**另記一筆值得注意的觀察：** 本次調查的全套重跑第 2 次出現 2 個「did not complete」型態的失敗，皆歸屬 `remote_catalog_screen_test.dart`（Issue 2 的檔案，已結案為未重現）——這代表 Issue 1／Issue 2 合計 6 次全套重跑都沒抓到之後，第 7 次全套重跑又重現了既有不穩定性，且失敗型態與 Issue 2 原本記錄的不同，值得人類評估是否重啟 Issue 2 或另立追蹤，本次未做進一步處理（不在本 Issue 3 範圍內，且不擅自修改已結案的 Issue 2 段落）。
