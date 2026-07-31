# Epic 20 Issue 5 — 移除 `EpubReaderView.kt`／`readium-navigator` 依賴，`MainActivity` 改回 `FlutterActivity` 實作計劃

> **給執行者（agentic worker）的提示：** 建議使用 `superpowers:subagent-driven-development`（推薦）或 `superpowers:executing-plans` 逐工單執行本計劃。工單內的步驟以核取方塊（`- [ ]`）追蹤完成狀態。

**目標：** Issue 2-4 完成後，`EpubReaderView`（Readium FXL 路徑）已無任何路徑會被建構，是純粹的死碼；本工單清乾淨——刪除 Kotlin/Dart 檔案、移除 `readium-navigator` 依賴、`MainActivity` 退回 Flutter 預設的 `FlutterActivity`，並同步更新因此變得不準確的文件（範圍比 `issues.md` 原始描述更大，見下方查證）。

**依賴：** Issue 4（已合併，`main`——已確認 `reader_screen.dart` 不再有任何路徑建構 `EpubReaderView`）。

**架構（ADR 0017 決策 1／7、`spec.md`「移除項目」）：** 純刪除/簡化，不新增任何能力。`BookMetadataChannel.kt` 的 `readium-shared`／`readium-streamer` 依賴（ADR 0017 決策 2）**不**受影響，保留不動。

**已查證的關鍵技術事實（避免計劃內容基於臆測，皆已對照現況逐行確認）：**

- **Dart 端死碼盤點**（`reader_screen.dart`）：
  - `_epubReaderViewKey` 欄位（`:237`）、`_handleLayoutResolved()`（`:800-902`，已標註 `// ignore: unused_element`，內含唯一剩下的 `EpubReaderView.loadTableOfContents(_epubReaderViewKey)` 呼叫）、`_handleCharacterCountReady()`（`:907-913`，已標註 `// ignore: unused_element`）——三者皆為死碼，`_handleZoneAction()`（`:1962-1990`）等所有實際換頁/跳轉/decorations 呼叫點已在 Issue 2/4 全數改為無條件呼叫 `FoliateEpubReaderView`，逐行確認無任何遺漏的 `EpubReaderView.xxx(...)` 存活呼叫。
  - 多處**過時但仍存在**的說明文字（非 `ignore: unused_element` 標註、但內容已不準確）：`widget.isFixedLayout` 欄位文件（`:99-104`，「退回 Issue 3 之前的既有行為...建構 EpubReaderView」）、`_resolveEpubEngineDispatch()` 文件（`:288-296`，「一律視為固定版面（EpubReaderView／Readium）」）、`_handleZoneAction()` 文件（`:1927-1948`，描述一個已不存在的 `_dispatchedIsFixedLayout` 三元分派）——這些字面上沒有編譯錯誤，但會誤導後續維護者，本工單一併訂正（不要求逐字重寫，但須移除對「建構 EpubReaderView」這個已不成立行為的描述）。
- **`app/test/reader/epub_reader_view_test.dart`**：整份測試檔案專測 `EpubReaderView`，直接刪除。
- **`app/test/screens/reader_screen_test.dart`**：`import 'package:elinkbook/reader/epub_reader_view.dart';`（`:9`）與 Issue 4 審查回應新增的 `expect(find.byType(EpubReaderView), findsNothing);`（`:3437`）在 `EpubReaderView` 類別刪除後會編譯失敗，必須移除／改寫；另有多處測試**描述字串**仍寫著「建構 EpubReaderView」（例如 `:406`／`:429`，但實際斷言已是 `find.byType(FoliateEpubReaderView)`），屬於誤導性但不影響編譯的既有落差，建議一併訂正測試標題。
- **Kotlin 端待刪除檔案**：`EpubReaderView.kt`（77KB）、`EpubReaderViewFactory.kt`（依賴 `androidx.fragment.app.FragmentActivity`，MainActivity 改回 `FlutterActivity` 後這個型別簽章本身就會編譯失敗，兩者必須同一批處理，不可分開）。
- **`ReaderViewAttachmentTracker.kt` 是共用元件，不可刪除**：已查證 `PdfReaderView.kt`／`MainActivity.kt` 也使用它（`elinkbook/volume_key` 頻道的 `attachReaderView`/`detachReaderView` case），`EpubReaderView.kt` 只是三個使用者之一。
- **`BookMetadataChannel.kt` 已查證只 import `org.readium.r2.shared.*`／`org.readium.r2.streamer.*`**，完全不 import `org.readium.r2.navigator.*`，移除 `readium-navigator` 依賴不影響它（ADR 0017 決策 2 的既有結論再次確認）。
- **`build.gradle.kts:65`** 是唯一要刪除的一行（`implementation("org.readium.kotlin-toolkit:readium-navigator:3.3.0")`），`:63-64` 的 `readium-shared`／`readium-streamer` 保留。`minSdk = 24`（`:40`）預期不受影響——`CLAUDE.md` 既有說明「由 Readium kotlin-toolkit〔要求 23〕與 integration_test 外掛〔要求 24〕疊加決定」，`readium-shared`/`readium-streamer` 屬同一個 `kotlin-toolkit` 系列，其 23 的門檻不因移除 `readium-navigator` 而消失，`integration_test` 的 24 仍是實際下限——本工單不預期需要調整 `minSdk`，Task 4 真機/建置驗證時順帶確認。
- **`MainActivity.kt` 現況已逐行確認**：`class MainActivity : FlutterFragmentActivity()` → 改 `FlutterActivity`；`import io.flutter.embedding.android.FlutterFragmentActivity`／`import androidx.fragment.app.commitNow`／`import org.readium.r2.navigator.epub.EpubNavigatorFragment` 三個 import 移除（改為 `import io.flutter.embedding.android.FlutterActivity`）；`onCreate(savedInstanceState: Bundle?)` 整個 override（`supportFragmentManager.fragmentFactory = EpubNavigatorFragment.createDummyFactory()` 起，處理 process death 後 `EpubNavigatorFragment` 還原崩潰的既有防呆）**整段刪除**（`FlutterActivity` 預設行為即可，不需要覆寫 `onCreate`）；`configureFlutterEngine()` 內 `registerViewFactory("cc.ugotit.elinkbook/epub_reader_view", EpubReaderViewFactory(this, ...))` 區塊移除（`this` 在改回 `FlutterActivity` 後也不再滿足 `EpubReaderViewFactory` 建構子要求的 `FragmentActivity` 型別，兩處變更互相依賴，必須同一個 commit 內完成，不可分階段）。
- **文件影響範圍比 `issues.md` 原始描述（僅提及「`MainActivity` 為何是 `FlutterFragmentActivity`」段落）更大**——已逐行核對 `CLAUDE.md` 全文，發現至少以下段落在本工單完成後會變得不準確，非本工單新造成、但屬於本工單刪除動作的直接後果，理應一併處理：
  - `:38`（`EpubReaderView` 條目本身，「僅供固定版面（FXL）EPUB 使用」）——類別已刪除，整條需移除或改寫為歷史說明。
  - `:39`（`FoliateEpubReaderView` 條目，「流式（reflowable）EPUB 使用」）——需改為「所有 EPUB 使用」。
  - `:41`（`PdfReaderView`/`EpubReaderView` 對稱包裝說明整段）——`EpubReaderView` 已不存在，這個「兩者對稱」的敘述基礎消失，需大幅簡化或移除，只保留 `PdfReaderView` 自身仍成立的部分。
  - `:45-47`（「`MainActivity` 為何是 `FlutterFragmentActivity`」整個子標題段落，`issues.md` 原始範圍已提及）——`MainActivity` 已不是 `FlutterFragmentActivity`，這個段落存在的理由本身消失，建議整段移除（而非改寫成「為何不是」，沒有維護價值）。
  - `:73`（「渲染架構已定案...FXL 用 Readium，流式用 foliate-js」）——需改為「FXL 與流式皆用 foliate-js」。
  - `:134-135`（「技術棧（已決策）」EPUB 雙引擎條目，含 FXL 用 Readium／流式用 foliate-js 兩個子項目）——需重寫為單引擎（foliate-js）架構，同時保留足夠的歷史脈絡（ADR 0011 Phase 1、ADR 0017 Phase 2 的演進，供後續讀者理解「為何看似只有一個引擎，過去卻分兩條路徑」），不是單純刪字。
  - `:132`（minSdk 理由）——內容預期仍成立（見上方查證），只需確認、不要求修改。
- **`docs/CONTEXT.md` 不存在，實際檔案是根目錄 `CONTEXT.md`**（`issues.md` 原始描述路徑有誤，已確認實際路徑）。內容比 `CLAUDE.md` 更廣泛地假設雙引擎架構仍然存在，已查證至少以下詞條需要更新：「雙頁 spread」（`:48`，「EPUB 固定版面的 spread 配對由 Readium 依 page-spread-left/right metadata 處理」——已由 foliate-js 接手，見 Issue 3）、「引擎分派判斷」（`:56`，仍描述「決定一本 EPUB 該用 Readium（FXL 路徑）或 foliate-js（流式路徑）」——epic-20 後這個判斷已不再決定引擎，只剩 UI 版面語意，見 Issue 2-4 的 `_dispatchedIsFixedLayout` 語意變化）、「Readium 內部版面渲染決策」（`:63-65`，整條詞目描述 `EpubNavigatorFragment`／`EpubReaderView.kt:819-853` 等即將刪除的 Kotlin 內部機制——整條詞目本身已無現實對應物，建議移除或明確標註為「historical，epic-20 前架構」）、「固定版面（FXL）熱區換頁機制」（`:76`，描述呼叫 Readium `goForward`/`goBackward` 的既有機制——FXL 現在跟流式共用同一套 Dart 端 `_ZoneOverlay`/`ZoneAction` 機制，不再有獨立的 Readium 版本）。
- **計劃審查發現（2026-07-31）：根目錄 `AGENTS.md` 同樣受影響，範圍比原本查證的 `CLAUDE.md`／`CONTEXT.md` 更嚴重**——已逐行核對確認：「唯一 Seam：ReaderScreen」段落（`:17-23`）描述 `ReaderScreen` 只分派到 `EpubReaderView`（Readium）／`PdfReaderView` 兩者，**完全沒有提及 `FoliateEpubReaderView`**（比 `CLAUDE.md`／`CONTEXT.md` 更過時，疑似從未隨 ADR 0011 的 reflowable 遷移更新過）；「Native 層」段落（`:27-31`）列出 `EpubReaderView.kt`+`EpubReaderViewFactory.kt`（即將刪除）與 `MainActivity.kt`「`FlutterFragmentActivity`，非預設 `FlutterActivity`，因 Readium Fragment 需要」（即將不成立）。**額外查證發現審查報告未提及的第三處**：「Gotchas」段落（`:97`）「Kotlin 端的 `EpubNavigatorFragment` 建構子是 `internal`，只能透過 Readium 的 `FragmentFactory` 建立」——本工單移除 `EpubNavigatorFragment` 全部使用後，這則 Gotcha 本身已無現實對應物，應一併移除，不只是改寫用詞。

## Global Constraints

- **本工單不改變任何執行期行為**——純刪除已死路徑與依賴、修正文件，任何真機可觀察的行為都不應該因本工單而改變（若真機驗證發現行為變化，代表刪錯東西，需回頭檢查）。
- `readium-shared`／`readium-streamer`／`BookMetadataChannel.kt`／`ReaderViewAttachmentTracker.kt` 一律保留不動。
- `MainActivity.kt` 的 `class MainActivity : FlutterFragmentActivity()` → `FlutterActivity` 與 `EpubReaderViewFactory` 註冊移除必須同一個 commit 完成（型別互相依賴，見上方查證）。
- `CONTEXT.md` 是 `domain-modeling` skill 維護的領域詞彙表——本工單對它的修改應聚焦在「移除對已刪除程式碼的具體引用」與「更正明顯不成立的技術事實陳述」，不需要對每個詞條做全面的措辭潤飾。

---

## 檔案結構

- Delete：`app/android/app/src/main/kotlin/cc/ugotit/elinkbook/EpubReaderView.kt`、`EpubReaderViewFactory.kt`、`app/lib/reader/epub_reader_view.dart`、`app/test/reader/epub_reader_view_test.dart`
- Modify：`app/android/app/build.gradle.kts`、`app/android/app/src/main/kotlin/cc/ugotit/elinkbook/MainActivity.kt`
- Modify：`app/lib/screens/reader_screen.dart`、`app/test/screens/reader_screen_test.dart`
- Modify：`CLAUDE.md`、`CONTEXT.md`、`AGENTS.md`

---

### Task 1：Dart 端刪除死碼、訂正過時說明文字

**Files:**
- Delete：`app/lib/reader/epub_reader_view.dart`、`app/test/reader/epub_reader_view_test.dart`
- Modify：`app/lib/screens/reader_screen.dart`、`app/test/screens/reader_screen_test.dart`

**Interfaces:**
- Consumes：Issue 2/4 已確認的「EPUB 一律建構 FoliateEpubReaderView」現況
- Produces：`reader_screen.dart` 不再 import／引用 `EpubReaderView`，`flutter analyze` 乾淨

- [x] **Step 1：刪除 `app/lib/reader/epub_reader_view.dart`、`app/test/reader/epub_reader_view_test.dart`**

- [x] **Step 2：`reader_screen.dart` 刪除死碼**

刪除 `_epubReaderViewKey` 欄位（`:237`）、`_handleLayoutResolved()`（`:800-902`）、`_handleCharacterCountReady()`（`:907-913`）三處，移除對應的 `import 'package:elinkbook/reader/epub_reader_view.dart';`。

- [x] **Step 3：`reader_screen.dart` 訂正過時說明文字**

依「已查證的關鍵技術事實」列出的三處（`widget.isFixedLayout` 欄位文件、`_resolveEpubEngineDispatch()` 文件、`_handleZoneAction()` 文件），移除對「建構 EpubReaderView」這個已不成立行為的描述，改為準確反映現況（`_dispatchedIsFixedLayout`／`_isFixedLayout` 現在只驅動 UI 版面語意，不再決定要建構哪個 widget）。順手 `grep -n "EpubReaderView" app/lib/screens/reader_screen.dart` 掃過其餘純歷史脈絡註解（例如「Epic 20 Issue 2：EPUB 一律使用 FoliateEpubReaderView」這類已經準確描述現況的既有註解），確認不需要更動、不誤刪有效的歷史脈絡說明。

- [x] **Step 4：`reader_screen_test.dart` 移除失效引用**

移除 `import 'package:elinkbook/reader/epub_reader_view.dart';`（`:9`）與 `expect(find.byType(EpubReaderView), findsNothing);`（`:3437`，Issue 4 審查回應新增，`EpubReaderView` 類別刪除後這個斷言本身已無意義，直接移除該行，保留同一測試其餘斷言）。`grep -n "EpubReaderView" app/test/screens/reader_screen_test.dart` 掃過其餘純測試標題/註解內的歷史提及（例如 `:406`／`:429` 測試描述字串仍寫「建構 EpubReaderView」），訂正為準確描述（`FoliateEpubReaderView`）。

執行 `flutter analyze` 確認乾淨（不應有任何 `EpubReaderView` 相關的 unresolved reference）。

---

### Task 2：Kotlin 端移除 `EpubReaderView.kt`／`readium-navigator`，`MainActivity` 改回 `FlutterActivity`

**Files:**
- Delete：`app/android/app/src/main/kotlin/cc/ugotit/elinkbook/EpubReaderView.kt`、`EpubReaderViewFactory.kt`
- Modify：`app/android/app/build.gradle.kts`、`app/android/app/src/main/kotlin/cc/ugotit/elinkbook/MainActivity.kt`

**Interfaces:**
- Consumes：無（純刪除）
- Produces：`./gradlew :app:compileDebugKotlin` 成功，`app-debug.apk` 建置成功且體積縮小

- [x] **Step 1：刪除 `EpubReaderView.kt`、`EpubReaderViewFactory.kt`**

- [x] **Step 2：`build.gradle.kts` 移除 `readium-navigator` 依賴**

刪除 `:65` 這一行（`implementation("org.readium.kotlin-toolkit:readium-navigator:3.3.0")`），確認 `:63-64` 的 `readium-shared`／`readium-streamer` 保留不動。

- [x] **Step 3：`MainActivity.kt` 改回 `FlutterActivity`**——**實作偏離**：發現 `registerForActivityResult`（`epic-1` Issue 8 資料夾匯入功能）依賴 `FragmentActivity` 家族，`FlutterActivity` 不支援，若照字面執行會讓資料夾匯入功能消失（違反 Global Constraint「不改變執行期行為」），故保留 `class MainActivity : FlutterFragmentActivity()` 不變；僅移除下方 Readium Fragment 相關 import／`onCreate` override／PlatformView 註冊。

- `class MainActivity : FlutterFragmentActivity()` → `class MainActivity : FlutterActivity()`（**未執行，見上方偏離說明**）
- 移除 `import io.flutter.embedding.android.FlutterFragmentActivity`／`import androidx.fragment.app.commitNow`／`import org.readium.r2.navigator.epub.EpubNavigatorFragment`，新增 `import io.flutter.embedding.android.FlutterActivity`
- 整個 `onCreate(savedInstanceState: Bundle?)` override 刪除（處理 `EpubNavigatorFragment` process-death 還原崩潰的既有防呆，隨 Fragment 機制一併移除；若刪除後 `Bundle` import 變成未使用，一併移除）
- `configureFlutterEngine()` 內移除 `registerViewFactory("cc.ugotit.elinkbook/epub_reader_view", EpubReaderViewFactory(this, flutterEngine.dartExecutor.binaryMessenger))` 這個區塊

- [x] **Step 4：建置驗證**

```bash
cd "U:/MyDeveloper/AI/elinkBook/app"
./gradlew :app:compileDebugKotlin
flutter build apk --debug
```

確認編譯成功，順手比對本次移除前後的 `app-debug.apk` 體積（觀察性質，非硬性門檻，見驗收標準）。

---

### Task 3：文件更新（`CLAUDE.md`、`CONTEXT.md`、`AGENTS.md`）

**Files:**
- Modify：`CLAUDE.md`、`CONTEXT.md`、`AGENTS.md`

**Interfaces:**
- Consumes：Task 1/2 已完成的實際刪除範圍
- Produces：三份文件不再描述已刪除的雙引擎 FXL 架構

- [x] **Step 1：`CLAUDE.md` 依「已查證的關鍵技術事實」列出的 7 處逐一訂正**

`:38`（`EpubReaderView` 條目移除/改寫）、`:39`（`FoliateEpubReaderView` 條目改為「所有 EPUB 使用」）、`:41`（`PdfReaderView`/`EpubReaderView` 對稱包裝整段簡化，只保留 `PdfReaderView` 自身仍成立部分）、`:45-47`（「`MainActivity` 為何是 `FlutterFragmentActivity`」整段移除）、`:73`（改為「FXL 與流式皆用 foliate-js」）、`:134-135`（EPUB 雙引擎條目重寫為單引擎架構，保留 ADR 0011/0017 的演進脈絡供讀者理解歷史）、`:132`（minSdk 理由，僅確認仍成立，不預期需要修改文字）。

- [x] **Step 2：`CONTEXT.md` 依「已查證的關鍵技術事實」列出的 4 處詞條逐一訂正**

「雙頁 spread」（`:48`，spread 配對機制改為 foliate-js）、「引擎分派判斷」（`:56`，訂正為「決定 UI 版面語意」而非「決定引擎」）、「Readium 內部版面渲染決策」（`:63-65`，整條詞目移除或標註為 historical）、「固定版面（FXL）熱區換頁機制」（`:76`，改為描述現行的 Dart 端 `_ZoneOverlay`/`ZoneAction` 共用機制，不再是 Readium 專屬）。

- [x] **Step 3：`AGENTS.md` 依「已查證的關鍵技術事實」列出的 3 處逐一訂正**（計劃審查發現，2026-07-31）

「唯一 Seam：ReaderScreen」段落（`:17-23`）——`ReaderScreen` 分派清單改為 `FoliateEpubReaderView`（所有 EPUB）／`PdfReaderView`，「兩者是對稱的 PlatformView 包裝」這句連帶不成立（`FoliateEpubReaderView` 不是傳統 `AndroidView`/`PlatformView`，見 `CLAUDE.md` 既有準確說明可直接參考用詞），需一併訂正、不能只換類別名稱。「Native 層」段落（`:27-31`）——移除 `EpubReaderView.kt`+`EpubReaderViewFactory.kt` 條目，`MainActivity.kt` 的說明文字改為不提 `FlutterFragmentActivity`/Readium Fragment。「Gotchas」段落（`:97`）——移除 `EpubNavigatorFragment` 建構子那條，本工單完成後已無現實對應物（不是改寫用詞，是整行移除）。

執行完 Step 1-3 後，`grep -rn "EpubReaderView\|FlutterFragmentActivity" CLAUDE.md CONTEXT.md AGENTS.md` 應只剩存在於 ADR/歷史脈絡說明中的提及（例如「ADR 0011/0017 演進脈絡」段落刻意保留的歷史敘述），不應再有描述「現行架構如此」語氣的殘留。

---

### Task 4：真機驗證、文件更新、送出 PR

**Files:**
- Modify：`docs/epics/epic-20-fxl-foliate-migration/design.md`、`issues.md`、`docs/epics.md`

**Interfaces:**
- Consumes：Task 1-3 已完成
- Produces：合併回 `main` 的乾淨基礎（無 Readium EPUB 渲染路徑殘留）

- [x] **Step 1：全套測試**

```bash
cd "U:/MyDeveloper/AI/elinkBook/app"
flutter analyze
flutter test
./gradlew :app:compileDebugKotlin
```

須為 0 issues／全部通過／編譯成功，且不得比 Issue 4 合併後的基準測試數少（回歸檢查——測試數應略為減少，因為刪除了整份 `epub_reader_view_test.dart`，這是預期中的減少，非回歸；記錄刪除前後的實際數字）。

- [x] **Step 2：建置並安裝至真機（`3CEF42ECD491687`）**

```bash
flutter build apk --debug
adb -s 3CEF42ECD491687 install -r build/app/outputs/flutter-apk/app-debug.apk
```

- [x] **Step 3：真機完整回歸測試（驗收標準要求的全項目）**

用 `tmp/一弦定音.epub`（FXL）與一本流式 EPUB（沿用既有測試素材）：開書、翻頁、雙頁、書籤、目錄、進度/跳頁、劃線/備註（僅流式書籍，FXL 已於 Issue 4 確認結構性不支援）、版面設定，皆須正常運作、與 Issue 4 合併後的行為完全一致（本工單不改變任何執行期行為，見 Global Constraints）。

- [x] **Step 4：依結果更新 `design.md`／`issues.md`／`docs/epics.md`**

- [x] **Step 5：Commit（於獨立 feature branch，比照 Issue 2-4 branch 命名慣例 `feature/epic-20-issue-5-*`）**

- [x] **Step 6：送出 code review（`superpowers:requesting-code-review`），依審查結果修正後開 PR**

---

## 相關佐證

- `docs/epics/epic-20-fxl-foliate-migration/spec.md`「移除項目」
- `docs/adr/0017-fxl-migrate-to-foliate-js.md` 決策 1／2／7
- `tmp/epic-20/issue2-implementation-review.md`（`EpubReaderView` 靜默死路徑的原始發現）
- `app/lib/screens/reader_screen.dart:99-104,237,288-296,800-902,907-913,1927-1948`
- `app/android/app/src/main/kotlin/cc/ugotit/elinkbook/MainActivity.kt`（`onCreate`／`configureFlutterEngine` 現況）、`BookMetadataChannel.kt`（Readium import 確認）、`ReaderViewAttachmentTracker.kt`（共用元件確認）、`PdfReaderView.kt`（`ReaderViewAttachmentTracker` 另一個使用者）
- `app/android/app/build.gradle.kts:40,63-65`
- `CLAUDE.md:38-47,73,132-139`
- `CONTEXT.md:48,56,63-65,76`
- `AGENTS.md:17-23,27-31,97`（計劃審查發現，2026-07-31）
- `tmp/epic-20/plan_issue_5_review_report.md`（計劃審查報告，AGENTS.md 發現來源）
