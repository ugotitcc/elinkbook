# Task 3 報告：`LibraryScreen` 長按多選 + 批次移動分類

## 實作內容

依照 `.superpowers/sdd/task-3-brief.md` 的 Step 1-9，對 `app/lib/screens/library_screen.dart` 與
`app/test/screens/library_screen_test.dart` 進行整合：

- `_testBook` 輔助函式新增可選 `filePath` 參數（向後相容）。
- 新增 6 項選取模式相關 widget test。
- `_LibraryScreenState` 新增 `Set<String>? _selectedBookIds` 欄位，以及
  `_inSelectionMode` getter、`_enterSelectionMode`/`_exitSelectionMode`/
  `_toggleBookSelection`/`_onBookTap`/`_onBookLongPress`/
  `_moveSelectedBooksToGroup` 方法。
- `build()` 改用 `PopScope` 包裹 `Scaffold`：選取模式下攔截系統返回鍵，改為退出
  選取模式而非真的離開畫面。
- App Bar 拆成 `_buildNormalAppBar()`（一般瀏覽）與 `_buildSelectionAppBar()`
  （選取模式：顯示已選取數量、✕ 取消、移動到分類按鈕）。
- `_buildGroupTabs()` 在選取模式下停用「全部」/各分類 tab／「管理分類」的點擊。
- `_buildBookList()`、`_BookGridTile`、`_BookListTile` 皆加上
  `selectionMode`/`selected`/`onLongPress` 參數：
  - Grid tile：右上角疊加勾選圖示（`Icons.check_circle`/`Icons.radio_button_unchecked`），
    包在 `Colors.black45` 圓形底色 `Container` 內以確保對比度。
  - List tile：`leading` 用 `Row` 讓 `Checkbox` 與封面並列顯示，而非取代封面。
- `_moveSelectedBooksToGroup()` 在使用者選定目的分類後「立即」呼叫
  `_exitSelectionMode()`，再進入寫入迴圈（避免寫入期間重複點擊的競態）。

## 額外必要修正（brief 程式碼本身的佈局錯誤，非兩個已知修正之一）

`_BookListTile` 的 `leading` 用 `SizedBox(width: selectionMode ? 88 : 48, ...)` 包住
`Row(Checkbox + 48px 封面)`。`Checkbox` 預設點擊熱區為 48x48（`kMinInteractiveDimension`），
加上封面 48px，總寬 96px 超出 88px，導致 `RenderFlex overflowed by 8.0 pixels`
（`flutter test` 因此直接丟出例外，測試失敗）。

修正：在該 `Checkbox` 加上 `materialTapTargetSize: MaterialTapTargetSize.shrinkWrap`，
將熱區縮小為 40x40，使 40 + 48 = 88 恰好吻合，不再溢位。這是最小幅度的純佈局修正，
不影響任何 Key、行為或測試斷言。

## 測試結果

### Step 2：RED（新增測試先失敗）

```
cd app && flutter test test/screens/library_screen_test.dart
```

結果：15 個既有測試通過，新增的 6 項測試全部失敗（找不到
`Key('library_selection_app_bar')` 等元件，或 `pumpAndSettle` timeout）。

### Step 7：GREEN（實作完成後）

```
cd app && flutter test test/screens/library_screen_test.dart
```

結果：`00:19 +21: All tests passed!`（既有 15 項 + 新增 6 項，共 21 項全數通過，
輸出乾淨無警告/例外雜訊）。

### Step 8：完整測試套件

```
cd app && flutter test
```

結果：`00:19 +78: All tests passed!`（全專案 78 個測試全數通過，未破壞既有測試）。

```
cd app && flutter analyze
```

結果：`No issues found! (ran in 8.0s)`

## 變更檔案

- `app/lib/screens/library_screen.dart`
- `app/test/screens/library_screen_test.dart`

## Commit

（見下方 git log，commit 於本報告寫成後建立）

## 自我審查

- 9 個步驟皆已完成：測試擴充/新增 → 確認 RED → import → 狀態欄位與方法 →
  `build()`/`PopScope`/兩個 AppBar builder → `_buildGroupTabs()` 停用 →
  `_buildBookList()`/兩個 tile 類別 → 確認 GREEN → 完整套件與 analyze → commit。
- 所有 Key 字串與 brief 逐字一致：`library_selection_app_bar`、
  `library_selection_cancel_button`、`library_move_to_group_button`、
  `book_selection_indicator_<bookId>`、`library_group_tab_<name>` 等。
- 未新增任何 brief 未要求的功能：沒有批次刪除、沒有多選以外的分類 tab 互動變更、
  沒有新增公開建構參數。
- 兩個「已知的計畫審查修正」在 brief 程式碼中本就已正確體現，逐字轉錄即可：
  1. `_moveSelectedBooksToGroup()` 在迴圈前即呼叫 `_exitSelectionMode()`——已照抄。
  2. Grid tile 勾選圖示的黑底圓圈容器、List tile 的 `Row`（Checkbox + 封面並列）
     ——已照抄。
- 額外發現並修正一處 brief 程式碼本身的真實佈局錯誤（見上方「額外必要修正」），
  純屬版面像素調整，未變動任何行為/Key/測試斷言。
- 測試輸出乾淨：RED 與 GREEN 執行皆無非預期警告雜訊（修正 overflow 前的例外
  已排除）。
- 分支確認：工作目錄與分支在動手前、commit 前皆已用 `pwd` + `git branch --show-current`
  驗證為 `worktree-epic-1-issue-10-batch-group-move`，並非 `main`。

## 疑慮

無重大疑慮。唯一值得記錄的是上述「額外必要修正」——brief 程式碼本身存在一個
佈局像素計算錯誤，已用最小幅度方式修正並在程式碼中加註解說明原因，供後續審查者
理解為何與 brief 逐字稿有一行之差。

另外附註：本檔案（`task-3-report.md`）在動手前已存在，內容是與本任務無關的另一份
報告（`BookImportService`／Issue 8 匯入管線，屬於別的 task/epic），該報告內文自己
也註記這是路徑重複使用留下的殘留檔案；本次已依任務要求覆寫為此份報告。
