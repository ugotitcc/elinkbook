# Code Review：Issue 8 —— 大型 EPUB OOM 閃退修復（原生 `WebViewAssetLoader` 串流服務）

**審查範圍：** `83141d4..8c8a121`（分支 `feature/epic-20-issue-8-large-epub-oom-fix`，單一 commit）
**審查依據：** `docs/epics/epic-20-fxl-foliate-migration/plans/plan-issue-8.md`
**審查方式：** 讀取計劃全文 + 逐檔案 diff 閱讀 + 在既有 worktree（`.worktrees/feature/epic-20-issue-8-large-epub-oom-fix`，HEAD 已對齊 `8c8a121`）實際執行 `flutter analyze`／`flutter test`（唯讀，未變更本次審查所在 checkout 的任何 git 狀態）

---

## 優點（Strengths）

1. **Task 1（Kotlin 端）與計劃逐字對齊**：`ReaderResourceChannel.kt` 的 `copyToCache`、`cacheBookForServing` 分支、背景 `TaskQueue`（`makeBackgroundTaskQueue()` + 獨立 `MethodChannel` 實例）、整個 `when{...}`（含開啟輸入串流）納入同一個 try/catch、`readContentUri` 死碼移除，五項要求全部確認到位（`app/android/app/src/main/kotlin/cc/ugotit/elinkbook/ReaderResourceChannel.kt:43-120`）。`readAndroidAsset` 正確維持在主執行緒 channel 上，未被誤搬到背景 channel。
2. **每實例獨立快取子目錄 + 冷啟動保底清理（Task 4）確實落地**：`FoliateEpubReaderView.dispose()` 清理本實例子目錄，`MainActivity.onCreate()` 新增 `foliate_book_cache/` 整目錄保底清空（`MainActivity.kt:58-69`），確實回應計劃審查點出的螢幕轉場競態風險。
3. **意外抓到一個會讓整個功能直接壞掉的上游套件 bug**：`flutter_inappwebview_android` 1.1.3 的 `AndroidInternalStoragePathHandler.toMap()` 原始碼是 `return {...toMap(), 'directory': directory};`——自己呼叫自己，`InternalStoragePathHandler` 一旦被使用就會 `StackOverflowError`。實作者正確診斷出來，並以最小幅度的本地 patch 修正（`app/patches/flutter_inappwebview_android/lib/src/webview_asset_loader.dart:195-198`，改成手動組裝 `{'type': type, 'path': path, 'directory': directory}`）。這不在計劃範圍內，但若沒抓到，整個 Task 3 會在真機/整合測試上直接 crash——是紮實的除錯成果。
4. **另一個真實 bug 的正確修復**：`foliate_native_bridge.dart` 的 `allowedRoot` 改為先 `resolveSymbolicLinksSync()` 再比對（`:126-138`），修正 Android `/data/user/0` 是 `/data/data` symlink 導致 `isPathWithinRoot` 誤判合法檔案為越界的問題，並有清楚註解說明原因與查證來源（整合測試失敗診斷）。既有 `isPathWithinRoot` 驗證邏輯本身未被弱化或繞過。
5. **`/assets/foliate/*`／`/assets/fonts/*` 兩條既有 Dart callback 路徑完全未被觸碰**，`_shouldInterceptRequest` 手術式移除 `/book/current.epub` 分支，符合 Global Constraint。
6. **死碼清理徹底**：`loadBookBytes()`、`readContentUri` 皆已移除，全倉庫搜尋未發現殘留呼叫端。
7. **711/711 單元測試通過**，`app/test/reader/foliate_native_bridge_test.dart`、`foliate_epub_reader_view_test.dart`、`reader_screen_test.dart` 的既有測試依計劃 Task 5 Step 1 補上 mock 後仍全數綠燈，我在 worktree 內實際執行 `flutter test` 覆核，與 `issues.md` 宣稱的「711/711 單元測試通過」一致。

---

## 問題（Issues）

### 重要（Important，應該修正）

#### 1. 複製尚未完成時 dispose，快取目錄會洩漏（大檔案時可能是 200MB+）

**檔案：** `app/lib/reader/foliate_epub_reader_view.dart:322-338`（`_cacheBook()`）與 `:488-498`（`dispose()`）

計劃明確把這個情境點名為「不得省略」的邊界情況（plan-issue-8.md Task 3 Step 1 第 3 點），但實作只做對了一半：

```dart
Future<void> _cacheBook() async {
  try {
    final cacheFn = widget.cacheBookForServingFn ?? cacheBookForServing;
    final cachedPath = await cacheFn(widget.filePath, _instanceId);
    if (!mounted) return; // ← 217MB 檔案複製可能耗時數秒，需檢查 mounted
    if (cachedPath != null) {
      setState(() { _bookCacheDir = File(cachedPath).parent.path; });
    } else {
      widget.onError('無法快取書籍檔案');
    }
  } catch (e) {
    if (!mounted) return;
    widget.onError('快取書籍失敗: $e');
  }
}

@override
void dispose() {
  if (_bookCacheDir != null) {          // ← 只有「已經 setState 過」才會清理
    final cacheDir = Directory(_bookCacheDir!);
    if (cacheDir.existsSync()) {
      cacheDir.deleteSync(recursive: true);
    }
  }
  detachReaderView();
  super.dispose();
}
```

`mounted` 守衛本身正確避免了 `setState() after dispose()` 例外（這點做對了），但代價是：若使用者在原生複製尚未完成前就離開畫面（`dispose()` 先發生），此時 `_bookCacheDir` 仍是 `null`，`dispose()` 的清理條件不成立、什麼都不做。原生端的複製操作不受 Dart 生命週期影響，仍會在背景 `TaskQueue` 上跑完並把完整檔案寫入 `foliate_book_cache/<instanceId>/current.epub`。稍後 `_cacheBook()` 的 `await` 恢復執行，此時 `cachedPath` 已經拿到手（就在 `!mounted` 判斷式的同一個作用域內），但因為 `!mounted` 直接 `return`，這個已知路徑從未被用來清理——該子目錄成為孤兒，要等到下次 App 冷啟動（`MainActivity.onCreate()`）才會被清空。

**為何重要：** 這正是計劃 Task 5 Step 5 第 7 點要求真機驗證的「快速切換書籍」情境（開 A → 立即返回 → 開 B），且本專案目標族群含 E-Ink／儲存空間有限裝置。若使用者在單一 App session 內多次快速開啟又離開大型 EPUB（例如瀏覽書架時手滑點到大檔案又快速返回），每次都可能留下一份完整大小的孤兒複本，在下次冷啟動前持續佔用內部儲存空間，且沒有任何自動測試驗證此路徑。

**如何修正：** 在 `!mounted` 分支內，於 `return` 前用已經拿到的 `cachedPath` 主動清理：
```dart
if (!mounted) {
  if (cachedPath != null) {
    Directory(File(cachedPath).parent.path).deleteSync(recursive: true);
  }
  return;
}
```
（`catch` 區塊的 `!mounted` 分支不受影響，因為那個路徑本來就沒有 `cachedPath`。）

#### 2. `flutter analyze` 並非乾淨，與 `issues.md` 宣稱不符

`issues.md` 更新內容宣稱「`flutter analyze` 乾淨」，但實際在 worktree 執行：

```
info - The constant name 'IN_APP_WEBVIEW_STATIC_CHANNEL' isn't a lowerCamelCase identifier
  - patches\flutter_inappwebview_android\flutter_inappwebview_android-1.1.3\lib\src\in_app_webview\_static_channel.dart:3:7
info - The constant name 'IN_APP_WEBVIEW_STATIC_CHANNEL' isn't a lowerCamelCase identifier
  - patches\flutter_inappwebview_android\lib\src\in_app_webview\_static_channel.dart:3:7
2 issues found.
```

兩個 info 都來自新加入的 `app/patches/flutter_inappwebview_android/` 目錄（其中一個還是下面第 3 點提到的多餘重複複本）。CLAUDE.md 明訂「提交前必須乾淨（"No issues found!"）」。

**如何修正：** 在 `app/analysis_options.yaml` 為 `patches/**`（第三方 vendored 原始碼，非本專案程式碼）加上 `analyzer: exclude:`，比照一般專案對 vendored 依賴排除靜態分析的慣例。

#### 3. `app/patches/flutter_inappwebview_android/` 內有一份完整多餘的重複複本

`app/patches/flutter_inappwebview_android/flutter_inappwebview_android-1.1.3/` 這個巢狀子目錄（231 個檔案、約 1.6MB）是整個未經修改的原始套件複本，與其外層真正被 `pubspec.yaml` `dependency_overrides` 指向使用的頂層檔案（`android/`、`lib/`、`pubspec.yaml` 等）完全重複——我用 `diff -rq` 逐檔比對確認兩者除了 `lib/src/webview_asset_loader.dart`（真正被 patch 的那一份）之外，其餘全部位元組級相同。這個巢狀複本沒有被任何建置流程引用（它自己的 `pubspec.yaml` 在更深一層，pub 不會讀到），純粹是已提交進版控的死重量，且是上面第 2 點兩個 lint info 其中一個的來源。

**為何重要：** 這份多餘複本讓這次 diff 膨脹了數萬行（`git diff --stat` 顯示 474 個檔案異動，其中絕大多數是這兩份重複的 vendored 套件複本），大幅增加審查與未來維護成本，也容易讓後續開發者誤改到不會生效的那一份。

**如何修正：** 刪除 `app/patches/flutter_inappwebview_android/flutter_inappwebview_android-1.1.3/` 整個巢狀子目錄，只保留頂層被實際使用的 patch 複本。

#### 4. ADR 0018 有一句關鍵論述已被本次實作推翻，但未同步更新

`docs/adr/0018-webviewassetloader-streaming-for-large-epub.md:22` 明文寫著選擇 `InternalStoragePathHandler` 方案的理由之一是「**且不需要 fork/patch 套件本身**」。但本次實作恰好因為 `flutter_inappwebview_android` 1.1.3 的 `toMap()` bug，被迫 fork/patch 了這個套件（見優點第 3 點）。ADR 作為「架構決策的唯一事實來源」，這句話現在是錯的，卻沒有任何 Addendum 或修訂記錄下這個事實已經改變。

**為何重要：** 未來若有人依據這份 ADR 評估「要不要升級/更換 `flutter_inappwebview` 相關依賴」，會被這句已經過期的論述誤導，以為目前架構乾淨、無 vendored patch 負擔。

**如何修正：** 在 ADR 0018 補一段 Addendum，記錄實際情況與 `app/patches/flutter_inappwebview_android/` 的存在、待上游修復後應移除的追蹤事項。

#### 5. 計劃 Task 5 Step 2（大型檔案整合測試）看起來完全沒做

`git diff 83141d4..8c8a121 -- app/integration_test/` 沒有任何輸出——`app/integration_test/` 目錄下沒有新增或調整任何檔案。計劃原文雖然用「新增一項測試...若不便長期存放...考慮...」這種留有彈性的措辭，但整體語意仍是「應該有」，而非可完全略過。目前這個 OOM 修復唯一的驗證證據是 `issues.md` 記載的人工真機測試（不會被 CI 執行、也不會在未來的迴歸中自動守住）。

**為何重要：** 本 Issue 存在的理由就是「大型 EPUB 開書會 OOM」，卻沒有任何自動化測試能在未來的重構/升級中攔住迴歸——例如將來有人不小心改回全檔讀取，或升級 `flutter_inappwebview` 版本改變了 `webViewAssetLoader` 行為，都不會被任何測試發現。

**如何修正：** 至少新增一項會員（動態產生一個大到足以驗證串流路徑、內容無意義的合法 EPUB，不需要真的 200MB，能驗證走的是串流路徑而非全檔讀取即可）整合測試，或明確記錄「刻意略過，理由是 XXX」而不是完全靜默不提。

#### 6. 新增的 `cacheBookForServingFn` 建構參數是死碼

`FoliateEpubReaderView` 新增了 `@visibleForTesting` 的 `cacheBookForServingFn` 建構參數（`foliate_epub_reader_view.dart:195-199,238,324`），用意是讓測試可以針對單一 widget 實例注入 mock。但實際三個測試檔（`foliate_epub_reader_view_test.dart`、`reader_screen_test.dart`）全部改用另一條路——直接覆寫全域頂層變數 `cacheBookForServing`（`foliate_native_bridge.dart:20-21`）。搜尋全倉庫，`cacheBookForServingFn` 除了宣告處以外沒有任何呼叫端傳入實際值。

**為何重要：** 同時存在「建構參數注入」與「全域可變變數覆寫」兩條平行的測試替身機制，卻只有一條真的被使用，違反 CLAUDE.md「不要有沒被要求的彈性/可配置性」與「Simplicity First」原則，也讓後續維護者困惑該用哪一條。

**如何修正：** 二選一並移除死碼——若全域變數覆寫已足夠（目前看來確實如此，且已用 `tearDownAll` 妥善復原），移除 `cacheBookForServingFn` 建構參數；若認為每實例注入比較乾淨，改讓測試改用它，並移除全域變數覆寫機制。

#### 7. 缺少直接針對 `mounted` 守衛/dispose 競態的單元測試

計劃把「`Future` 完成時必須先檢查 `mounted`」列為「Flutter 非同步生命週期標準陷阱，不得省略」的高風險項目，但現有測試（`foliate_epub_reader_view_test.dart`）沒有任何一個案例模擬「`_cacheBook()` 尚未完成時就 dispose widget」並斷言不拋例外、也不留下孤兒目錄。若當初有這樣一個測試，很可能會直接抓到上方第 1 點的洩漏問題。同樣地，`cachedPath == null → widget.onError(...)` 這條失敗路徑也沒有測試覆蓋。

**如何修正：** 補一個測試：注入一個回傳 `Future` 但長時間不 complete 的 `cacheBookForServing`，`pumpWidget` 後立刻 `pumpWidget(SizedBox())` 移除該 widget（觸發 dispose），再讓 Future resolve，斷言沒有例外拋出、且（若採用上方修正方案）快取目錄確實被清理。

### 次要（Minor，錦上添花）

1. **`MainActivity.kt:8` import 順序不一致**：`import java.io.File` 被插在 `android.webkit.WebView`（`:4`）與 `androidx.activity.result.contract.ActivityResultContracts`（原本緊接在後）之間，打斷了原本 `android.*` → `androidx.*` 的分組慣例。純風格問題，不影響功能。
2. **`app/patches/flutter_inappwebview_android/README.md` 是原封不動照抄上游的通用說明**，完全沒有提到「這是本地 patch」「為什麼 patch」「上游修復後如何移除」——這些資訊目前只寫在 `pubspec.yaml` 的一則簡短註解裡。建議在 patch 目錄新增一份簡短的 `PATCH.md`（或擴充 README），記錄 diff 內容、對應的上游版本、追蹤 issue 連結，方便未來升級版本時知道要重新套用同一個修正。
3. **全域可變函數變數作為測試替身**（`cacheBookForServing`，`foliate_native_bridge.dart:20-21`）雖然有用 `tearDownAll` 妥善復原、目前沒有觀察到跨測試污染，但這種 process-global mutable state 的模式本質上比較脆弱（例如未來若某測試忘記在 `tearDownAll` 復原，會靜默影響同一個 test isolate 內其他測試檔）。非阻塞項，僅供未來重構參考。

---

## 建議（Recommendations）

1. 上方 Important #1（dispose 洩漏）與 #6（死碼參數）建議一併處理，因為移除 `cacheBookForServingFn` 死碼、修正 `!mounted` 分支的清理邏輯，兩者改動範圍都很小、風險低。
2. Important #2／#3（analyze 不乾淨／重複 vendored 複本）建議在合併前一次處理掉——刪除多餘複本、排除 `patches/**` 靜態分析，這兩者都是機械式清理，不涉及邏輯風險。
3. Important #4（ADR 過期論述）與 #5（缺整合測試）技術風險較低，但建議在合併後盡快補上，避免累積成「大家都知道但沒人寫下來」的隱性技術債。

---

## 結論（Assessment）

**是否可合併？** 修正後可合併

**理由：** 核心修復思路正確、Task 1-4 對照計劃逐項確認到位，且過程中額外揪出兩個會直接讓功能崩潰／誤判的真實 bug（上游套件 `toMap()` 無限遞迴、`isPathWithinRoot` symlink 誤判），品質紮實；711 個單元測試全數通過，真機也已驗證 217MB 檔案不再 OOM。但存在一個具體、可重現、且正是計劃自己點名要處理的邊界情況缺口（複製中途 dispose 導致快取目錄洩漏，Important #1），加上 `flutter analyze` 實際不乾淨、`app/patches/` 內有一份完全多餘的重複複本、以及 ADR 過期論述未同步——這些都不是「重新設計」等級的問題，修正成本低，但在合併前處理完會讓這個修復更站得住腳。

---

## 複審（第二輪，commit `a8c8140`）

**審查範圍：** `8c8a121..a8c8140`（`chore(epic-20): code review fixes for Issue 8`，單一 commit，回應本檔案第一輪報告）
**審查方式：** 讀取第一輪報告全文 + 逐檔案 `git diff 8c8a121..a8c8140` 閱讀 + 在既有 worktree（`.worktrees/feature/epic-20-issue-8-large-epub-oom-fix`，HEAD 已對齊 `a8c8140`，未移動本次審查所在 checkout 的任何 git 狀態）實際執行 `flutter pub get`／`flutter analyze`／`flutter test`

### 逐項複審結果

#### Important #1（複製中途 dispose 快取目錄洩漏）—— **已修正（Fixed）**

`app/lib/reader/foliate_epub_reader_view.dart` 的 `_cacheBook()`（worktree 內對應行號約 314-338）：`!mounted` 分支內新增了完全依照上一輪建議實作的清理邏輯——用已經拿到的 `cachedPath`（而非依賴要等 `setState` 才會賦值的 `_bookCacheDir`）組出 `Directory(File(cachedPath).parent.path)`，`existsSync()` 為真時 `deleteSync(recursive: true)`，清理後才 `return`：

```dart
if (!mounted) {
  // 217MB 檔案複製可能耗時數秒，若使用者已離開畫面，需主動清理快取
  if (cachedPath != null) {
    final cacheDir = Directory(File(cachedPath).parent.path);
    if (cacheDir.existsSync()) {
      cacheDir.deleteSync(recursive: true);
    }
  }
  return;
}
```

邏輯正確：不再依賴「已經 `setState` 過」這個前提，直接用複製完成後拿到的路徑清理，涵蓋了「複製尚未完成就 dispose」的原始洩漏情境。`dispose()`（約 488-498 行）本身的既有清理邏輯（依 `_bookCacheDir`）未受影響，兩者互補、無重疊風險（`_bookCacheDir` 只有在 `mounted` 仍為真時才會被設定，兩個清理路徑互斥）。

驗證方式：讀取程式碼確認邏輯正確；另見下方 Important #7，該項的第一個新測試雖然執行到了這段程式碼，但因使用不存在於磁碟上的假路徑，實際上未能驗證 `deleteSync` 真的被呼叫到（測試品質缺口，另行記錄）。

#### Important #2（`flutter analyze` 不乾淨）—— **已修正（Fixed）**

`app/analysis_options.yaml` 新增：

```yaml
analyzer:
  exclude:
    - patches/**
```

在 worktree（HEAD `a8c8140`）內實際執行 `flutter analyze`，結果：

```
Analyzing app...
No issues found! (ran in 3.4s)
```

與 `issues.md` 宣稱一致，問題解除。

#### Important #3（`flutter_inappwebview_android-1.1.3` 重複複本）—— **已修正（Fixed）**

`git diff --stat 8c8a121..a8c8140` 顯示 236 個檔案異動、30872 行刪除，逐一核對皆為 `app/patches/flutter_inappwebview_android/flutter_inappwebview_android-1.1.3/` 巢狀子目錄下的檔案。實際檢查 worktree 內 `app/patches/flutter_inappwebview_android/` 目錄結構，確認巢狀子目錄已完全消失，只剩頂層被 `pubspec.yaml` `dependency_overrides` 實際指向的複本（`android/`、`lib/`、`test/` 等），另新增了下方 Minor #2 提到的 `PATCH.md`。

#### Important #4（ADR 0018 過期論述）—— **已修正（Fixed）**

`docs/adr/0018-webviewassetloader-streaming-for-large-epub.md` 新增「Addendum（2026-08-01，Issue 8 實作後修訂）」章節，內容準確描述了 `toMap()` 無限遞迴 bug、本地 patch 位置與套用方式、以及移除條件（上游修復後升級並刪除 `app/patches/`）。內容與實際程式碼（`PATCH.md`、`pubspec.yaml` 註解）一致，日期與本次修正 commit 日期（2026-08-01）吻合。原本「不需要 fork/patch 套件本身」那句過期論述雖未直接刪除/改寫（Addendum 是新增章節而非就地修訂），但已透過 Addendum 清楚點名並修正認知落差，達成第一輪報告要求的效果。

#### Important #5（大型檔案整合測試缺失）—— **未修正（Not Fixed）**

`git diff 8c8a121..a8c8140 -- app/integration_test` 與 `git diff 8c8a121..a8c8140 -- docs/epics/epic-20-fxl-foliate-migration/issues.md` 皆無輸出——`app/integration_test/` 目錄完全未變動，`issues.md` 也未新增任何「刻意略過、理由是 XXX」的說明。commit message（`git show a8c8140`）逐項列出本次處理的項目（Important #1、#2、#3、#4、#6、#7 + Minor 一項），未提及 #5，證實這是刻意暫緩而非遺漏。此項目在合併前仍是缺口：本 Issue 存在的理由（大型 EPUB OOM）目前唯一的迴歸防線是人工真機測試，沒有任何自動化測試能在未來重構/升級中攔住迴歸。

#### Important #6（`cacheBookForServingFn` 死碼參數）—— **已修正（Fixed）**

`FoliateEpubReaderView` 的 `cacheBookForServingFn` 建構參數與對應欄位、`_cacheBook()` 內的 `widget.cacheBookForServingFn ?? cacheBookForServing` 三讀取點皆已移除，改為直接讀取全域變數 `cacheBookForServing`。全倉庫 `grep -r cacheBookForServingFn` 無任何匹配（含測試檔），確認死碼與其唯一測試路徑的分歧已一併清除，未留下孤兒 import（`@visibleForTesting` 的匯入需求已隨參數移除，`flutter analyze` 乾淨佐證未留下未使用的 import）。

#### Important #7（缺少 mounted 守衛/dispose 競態單元測試）—— **部分修正（Partially Fixed）**

`app/test/reader/foliate_epub_reader_view_test.dart` 新增 `mounted guard / dispose race` group，兩個測試：

1. `cache failure calls onError`：注入回傳 `null` 的 `cacheBookForServing`，斷言 `onError` 收到 `'無法快取書籍檔案'`。**這個測試是有效的**，補上了第一輪報告點名「`cachedPath == null → onError`」這條先前完全沒有覆蓋的路徑。

2. `dispose during cache does not leak cache directory`：用 `Completer<String?>` 讓 `cacheBookForServing` 保持 pending，`pumpWidget` 掛載 widget 後立刻 `pumpWidget` 替換整棵樹（觸發 dispose），再 `completer.complete('/fake/cache/dir/current.epub')` 讓 `_cacheBook()` 恢復執行，最後只斷言「`await tester.pump()` 不拋出例外」。

   **問題：** 這個測試名稱承諾「不洩漏快取目錄」，但斷言完全沒有驗證目錄真的被刪除——`completer.complete()` 傳入的 `'/fake/cache/dir/current.epub'` 是一個從未在磁碟上實際建立的假路徑。`_cacheBook()` 內的清理邏輯是 `if (cacheDir.existsSync()) { cacheDir.deleteSync(...); }`，由於 `/fake/cache/dir` 根本不存在，`existsSync()` 恆為 `false`，`deleteSync()` 這一行**從未被執行到**。也就是說，這個測試唯一驗證的是「`!mounted` 分支不會拋例外」——而這在修正前的舊程式碼（單純 `if (!mounted) return;`，完全沒有清理邏輯）一樣不會拋例外，因為舊程式碼根本沒有嘗試操作檔案系統。換言之，**若把 Important #1 的修正整個復原（退回成第一輪報告點名的有洩漏版本），這個測試依然會通過**——它沒有能力偵測自己宣稱要防護的迴歸。

   **正確做法應該是**：用 `Directory.systemTemp.createTempSync()` 建立一個真實存在的暫存目錄（內含一個假檔案），把它的路徑餵給 completer，dispose 完成、`pump()` 之後斷言 `!tempDir.existsSync()`——這樣才能真正驗證 `deleteSync` 有被呼叫到、且清理了正確的路徑。

   實測驗證：在 worktree 內執行 `flutter test`，這兩個新測試確實都通過（見下方「驗證證據」），但如上所述，測試 2 的通過本身不能作為 Important #1 修正正確性的獨立佐證——Important #1 的正確性是我透過直接閱讀程式碼邏輯確認的，不是這個測試證明的。

**判定為部分修正**：測試數量、group 命名、測試 1 的有效性都達到第一輪報告的要求；但測試 2 存在斷言薄弱、無法偵測目標迴歸的實質缺口，未達到「能真正攔住這個 bug 重新出現」的測試目的。

### Minor #1（`MainActivity.kt` import 順序）—— **未修正（Not Fixed）**

`git diff 8c8a121..a8c8140 -- app/android/app/src/main/kotlin/cc/ugotit/elinkbook/MainActivity.kt` 無輸出，檔案完全未變動。純風格問題，非阻塞，但確認未處理。

### Minor #2（`patches/` README 未記錄本地 patch 緣由）—— **已修正（Fixed，改用替代方案）**

`README.md` 本身確實未變動（`git diff` 無輸出），但新增的 `app/patches/flutter_inappwebview_android/PATCH.md`（42 行）完整記錄了問題描述、修正內容、檔案位置、`dependency_overrides` 使用方式、移除條件、以及參考資訊。第一輪報告原文即建議「新增一份簡短的 `PATCH.md`（或擴充 README）」，兩種做法皆可接受，`PATCH.md` 已達成同等效果。

小觀察（非新問題，僅供留意）：`PATCH.md` 內「Issue: flutter_inappwebview_android#1982 (待確認)」這個 issue 編號本身標註了「待確認」，屬於誠實揭露不確定性，沒有被當作既定事實陳述，可接受，但未來若確認無效仍需回頭更新。

### Minor #3（全域可變函數變數作為測試替身）—— **未修正（Not Fixed，符合預期）**

第一輪報告已明確標註此項「非阻塞」，本次修正也未處理（`foliate_native_bridge.dart` 的 `cacheBookForServing` 全域變數機制維持原樣）。不影響合併判斷。

### 本次修正引入的新問題

**Important（新）：無。**

**Minor（新）：**

1. **`foliate_epub_reader_view_test.dart` 新增的 `dispose during cache does not leak cache directory` 測試斷言薄弱，實質上是空測試（vacuous test）。** 詳見上方 Important #7。建議後續（不阻塞本次合併，但應盡快補上）改用真實建立的暫存目錄取代 `/fake/cache/dir/current.epub`，並在斷言中確認目錄已被刪除，這樣才能讓測試真正對 Important #1 的迴歸提供保護。

未發現其他新引入的邏輯錯誤、死碼或不一致；`cacheBookForServingFn` 移除後全倉庫搜尋無殘留呼叫端，`flutter analyze` 乾淨，`flutter test` 全數通過（含新增測試）。

### 驗證證據

在 `.worktrees/feature/epic-20-issue-8-large-epub-oom-fix`（HEAD 已對齊 `a8c8140`，未移動本次審查所在 checkout 的任何 git 狀態）內實際執行：

```
$ flutter pub get
Got dependencies!

$ flutter analyze
Analyzing app...
No issues found! (ran in 3.4s)

$ flutter test
...
00:34~00:41 +713: All tests passed!
```

- `flutter analyze` 確認乾淨，與 Important #2 修正一致。
- 全套測試數量由第一輪報告記載的 711 個增加為 **713 個，全數通過**——恰好對應 Important #7 新增的兩個測試（`cache failure calls onError`、`dispose during cache does not leak cache directory`）。重複執行兩次，結果一致（無 flaky 跡象）。
- 未執行真機/整合測試（`app/integration_test/` 本次未變動，且需要實體裝置/模擬器，超出本次唯讀複審環境範圍）。

### 結論（Assessment）

**是否可合併？** 修正後可合併

**理由：** 第一輪報告列出的 7 項 Important 問題中，5 項（#1、#2、#3、#4、#6）已完整且正確修正，並經 `flutter analyze`／`flutter test` 實測核實；#7 部分修正——新增的兩個測試中，`cache failure calls onError` 有效，但 `dispose during cache does not leak cache directory` 斷言薄弱，未能真正驗證 Important #1 的修正是否有效防護迴歸（Important #1 本身的程式碼邏輯經人工閱讀確認是正確的，只是測試沒有跟上）；#5（大型檔案整合測試）維持未修正，是本次唯一完全沒有動作的 Important 項目。Minor 項目中僅 #1（import 順序）維持未修正，屬於單純風格問題。整體而言核心風險（記憶體 OOM 修復本身、快取目錄洩漏的程式邏輯、`flutter analyze` 乾淨、重複 vendored 複本、ADR 文件同步）都已確實到位，剩餘缺口（#5 缺整合測試、#7 測試斷言薄弱、Minor #1 風格）屬於可在合併後以極低成本追蹤處理的技術債，不構成阻擋合併的理由，但建議在合併前，或合併後的極短期內，把 Important #7 的第二個測試改為使用真實暫存目錄，讓它真正具備迴歸防護能力。
