# Epic 27 Issue 9 — 流式 EPUB 長按選字／劃線時容易誤觸翻頁 實作計畫

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 修復流式 EPUB（含 KF8／TXT／MD，皆共用 `FoliateReaderView`）長按選字／拖曳劃線時容易誤觸翻頁的問題，尤其是螢幕右側／上側邊緣。實作 `issues.md` Issue 9 定案的「最小可行修復範圍」兩項：(1) `tap_zone_detector.dart` 補上 `onPointerMove` 熔斷機制；(2) `main.js` 為 `<foliate-paginator>` 開啟 `no-swipe` 屬性、停用其內建滑動翻頁。

**Architecture:** 兩個根因互相獨立、分別對應兩個檔案，可拆成 2 個互不依賴的 Task：

1. **根因 A（Flutter 側時序競賽，主因）**：`TapZoneDetector`（`app/lib/reader/tap_zone_detector.dart`）目前只在 `onPointerUp` 那一瞬間比對「放開位置」與「按下位置」的距離，中途手指移動多遠都不影響最終判定——只要放開時剛好落在按下點 `tapSlop` 範圍內就算「快速點擊」。這讓「先拖曳一小段選字、再把手指移回附近才放開」這類真實劃線手勢，仍可能在放開瞬間被誤判成翻頁點擊。修法是在 `onPointerMove` 就即時偵測位移是否超過 `tapSlop`，一旦超過就永久清空本次按壓的追蹤狀態，使後續無論怎麼移動，`onPointerUp` 都不會再判定為點擊。`TapZoneDetector` 是 PDF／EPUB 共用元件，此修改對兩種格式同時生效。
2. **根因 B（`paginator.js` 內建滑動翻頁與選字手勢搶touch，次因）**：`paginator.js`（vendored、依 ADR 0011 不可修改內容）已原生支援 `no-swipe` 屬性——設定後會完全略過內建滑動翻頁與放開時的 `snap()` 翻頁判定。已查證全專案目前從未設定過這個屬性，也沒有任何功能依賴滑動翻頁（PRD／CLAUDE.md 的導覽模型只講 3×3 熱區＋音量鍵）。修法是在 `main.js` 的 `openBook()` 內，`await view.open(book)` 成功後立即對 `view.renderer` 設定 `no-swipe` 屬性——這裡是既有程式碼已經無條件呼叫 `view.renderer.setAttribute('flow', ...)` 的同一個位置（`main.js:886-889`），確認 `view.renderer` 在此刻已就緒、且流式與 FXL 書籍皆會執行到這裡。

**Tech Stack:** Flutter/Dart（Task 1）、原生 JavaScript（Task 2，vendored `foliate-js` 執行環境，`flutter_inappwebview` 承載）。無新增依賴。

**Spec:** `docs/epics/epic-27-reader-device-compat/issues.md`「Issue 9」、`docs/epics/epic-27-reader-device-compat/reviews/bugfix-repro.md`「Issue 9」（根因診斷）。

## 設計決策（回應 `issues.md` Issue 9 留給實作者定案的範圍問題）

1. **本計畫只做 Solution 第 1、2 項（`no-swipe` ＋ `onPointerMove` 熔斷），不做第 3-5 項**（`tapMaxDurationMs` 收斂、選取清除 Grace Period、直排安全邊距）。理由：`issues.md` 已明文這兩項是「最小可行修復範圍」，其餘 3 項需要真機驗證才能定案數值或判斷是否還需要，貿然一次全做會讓本計畫無法在 `flutter test` 環境下建立可靠的紅燈/綠燈基準（時間門檻類的改動只能靠真機手感判斷對錯）。
2. **`no-swipe` 屬性無條件設定，不區分 FXL／流式**：`view.renderer` 在 `view.open(book)` 之後對兩種書籍皆已就緒；`no-swipe` 只是一個屬性字串，即使書籍走 `foliate-fxl` 元素（其 `observedAttributes` 不含 `no-swipe`）也只是被忽略、不會拋例外（與呼叫一個該元素不存在的「方法」不同，`setAttribute` 對任何元素永遠安全）。不寫額外的 `isFixedLayout` 分支判斷，維持最簡實作。
3. **`onPointerMove` 熔斷機制同時讓 PDF 端的 3×3 熱區受益**（`pdf_reader_view.dart` 共用同一個 `TapZoneDetector`），這是修 Task 1 的自然結果，不需要也不應該為 PDF 另外寫一份重複邏輯——不在本計畫另立 Task，維持單一元件、單一防呆點。

## Global Constraints

- 只修改 `app/lib/reader/tap_zone_detector.dart`、`app/test/reader/tap_zone_detector_test.dart`、`app/android/app/src/main/assets/foliate/main.js` 三個檔案。
- **不修改 `paginator.js` 任何一行**（vendored、ADR 0011）。
- 不在本計畫處理 `issues.md` Issue 9 Solution 第 3-5 項（見上方設計決策 1）。
- **已知局限（誠實記錄，非遺漏）**：Task 2（`main.js` 的 `no-swipe` 設定）無法透過 `flutter test` 自動化驗證——本專案沒有針對 `main.js` 這類 vendored 執行環境膠水程式碼的 JS 測試框架接入 CI（`app/tool/check_foliate_es_compat.js` 是靜態掃描較新 ES API 用法，不是行為測試），比照 `plan-issue-1.md` 對「無法在 `flutter test` 純 Dart 環境重現」的既有處理方式，改用下方 Task 2 Step 2 的具體人工驗證程序（Chrome DevTools 遠端偵錯），不是自動化測試的替代品，而是本計畫承認的已知局限。
- Task 1 每個 Step 完成後跑 `flutter analyze`，維持乾淨。
- 兩個 Task 互不依賴，可依任意順序完成；下方依「可自動化 TDD 循環」優先排序，Task 1 在前。

---

### Task 1：`TapZoneDetector` 新增 `onPointerMove` 熔斷機制

**Files:**
- Modify: `app/lib/reader/tap_zone_detector.dart`
- Test: `app/test/reader/tap_zone_detector_test.dart`

**Interfaces:**
- Consumes: 無新增——沿用既有建構參數 `onTap`/`child`/`nowMs`/`tapMaxDurationMs`/`tapSlop`（`tap_zone_detector.dart:43-56`）。
- Produces: 無新增對外介面，`TapZoneDetector` 建構子簽章不變，純粹是 `_TapZoneDetectorState` 內部新增一個 `Listener.onPointerMove` 回呼。

- [x] **Step 1：寫失敗測試——拖曳中途超過容許位移範圍後，即使放開時位置回到容許範圍內，仍不應觸發 `onTap`**

編輯 `app/test/reader/tap_zone_detector_test.dart`，於既有第 4 則測試（`onPointerCancel` 那則，第 74-97 行）之後新增：

```dart
  testWidgets(
      '拖曳中途超過容許位移範圍後，即使放開時位置回到容許範圍內，仍不觸發 onTap（epic-27-reader-device-compat Issue 9：模擬選字/劃線手勢中途小幅拖曳後手指移回原點附近才放開）',
      (tester) async {
    var tapped = false;
    var fakeNowMs = 1000;
    await tester.pumpWidget(wrap(
      onTap: () => tapped = true,
      nowMs: () => fakeNowMs,
      tapSlop: 18.0,
    ));

    final gesture = await tester.startGesture(const Offset(50, 50));
    fakeNowMs += 50;
    await gesture.moveTo(const Offset(50, 90)); // 位移 40px > 18px，途中已超過容許範圍
    fakeNowMs += 50;
    await gesture.moveTo(const Offset(50, 52)); // 放開前移回幾乎原點，此刻與按下點僅距 2px < 18px
    await gesture.up();
    await tester.pump();

    expect(tapped, isFalse,
        reason: '目前實作只在 onPointerUp 那一瞬間比較距離，中途曾超過 tapSlop '
            '這件事沒有被記住，放開時位置又落回容許範圍內會被誤判為一次快速點擊'
            '——這正是使用者真機回報「劃線時容易誤觸翻頁」的其中一種真實手勢形狀，'
            '本測試在加入 onPointerMove 熔斷前應為 FAIL（tapped 會是 true）');
  });
```

- [x] **Step 2：執行測試確認失敗**

執行：`cd app && flutter test test/reader/tap_zone_detector_test.dart --plain-name "拖曳中途超過容許位移範圍"`
預期：FAIL（`tapped` 為 `true`，因為目前 `onPointerUp` 只看放開當下的距離，2px < 18px 會判定為有效點擊）。

- [x] **Step 3：實作 `onPointerMove` 熔斷**

編輯 `app/lib/reader/tap_zone_detector.dart`，於 class doc 註解最後一段（第 35-41 行，說明 `tapMaxDurationMs`/`tapSlop` 為呼叫端注入參數那段）之後、`class TapZoneDetector extends StatefulWidget {` 之前，新增一段文件註解：

```dart
///
/// [onPointerMove] 熔斷（Epic 27 Issue 9）：原本只有 [onPointerUp] 會比較
/// 「放開位置」與「按下位置」的距離，中途手指移動多遠都不影響最終判定——
/// 只要放開時剛好落在按下點 [tapSlop] 範圍內就算一次有效點擊。真實的
/// 選字/劃線手勢常見「先小幅拖曳、放開前又移回附近」，會被誤判成一次快速
/// 點擊而觸發翻頁（真機回報，尤其在螢幕右側/上側邊緣最明顯，見
/// `docs/epics/epic-27-reader-device-compat/reviews/bugfix-repro.md`
/// Issue 9）。改為在 [onPointerMove] 就即時偵測位移是否已超過 [tapSlop]，
/// 一旦超過就永久清空本次按壓的追蹤狀態（等同於 [onPointerCancel] 的
/// 清空邏輯）——之後不論手指怎麼移動，[onPointerUp] 都不會再判定為點擊，
/// 不需要額外記一個「是否已熔斷」的旗標，直接複用「[_downPosition] 是否
/// 為 null」這個既有判斷式。
```

於 `_TapZoneDetectorState.build()`（第 66-96 行）的 `Listener(...)` 中，`onPointerDown` 與 `onPointerUp` 之間新增 `onPointerMove`：

```dart
    return Listener(
      behavior: HitTestBehavior.translucent,
      onPointerDown: (event) {
        _downPosition = event.position;
        _downTimeMs = widget.nowMs();
      },
      onPointerMove: (event) {
        final downPosition = _downPosition;
        if (downPosition == null) return;
        final distance = (event.position - downPosition).distance;
        if (distance > widget.tapSlop) {
          // 位移已超過容許範圍，永久作廢本次按壓——即使之後手指移回附近
          // 才放開，onPointerUp 也不會再誤判為一次快速點擊（Epic 27
          // Issue 9）。
          _downPosition = null;
          _downTimeMs = null;
        }
      },
      onPointerUp: (event) {
```

（`onPointerUp`／`onPointerCancel` 本體不變，維持原樣。）

- [x] **Step 4：執行測試確認通過**

執行：`cd app && flutter test test/reader/tap_zone_detector_test.dart`
預期：全數 5 則測試 PASS（含 Step 1 新增的測試，以及既有 4 則零回歸）。

- [x] **Step 5：執行完整分析與全專案測試，確認零回歸**

執行：`cd app && flutter analyze && flutter test`
預期：`flutter analyze` "No issues found!"；`flutter test` 全數 PASS，零回歸。`TapZoneDetector` 被 `foliate_reader_view.dart`／`pdf_reader_view.dart` 共用，需特別留意兩邊既有的 nav-zone 相關測試（例如 `pdf_reader_view_nav_zone_test.dart`、`reader_screen_test.dart` 內熱區點擊相關測試）維持通過——這些既有測試的手勢都是「按下後不移動」或「一次到位的長距離移動」，不涉及「先超過 slop 再移回」這種形狀，理論上不受影響，仍建議全專案跑一次確認。

- [x] **Step 6：Commit**

```bash
git add app/lib/reader/tap_zone_detector.dart app/test/reader/tap_zone_detector_test.dart
git commit -m "fix(epic-27): Issue 9——TapZoneDetector 新增 onPointerMove 熔斷，避免劃線手勢誤觸翻頁"
```

---

### Task 2：`main.js` 為 `<foliate-paginator>` 開啟 `no-swipe` 屬性

**Files:**
- Modify: `app/android/app/src/main/assets/foliate/main.js`
- Test: 無自動化測試（見 Global Constraints「已知局限」），改用下方 Step 2 人工驗證程序。

**Interfaces:**
- Consumes: 無（純 JS 內部改動，不涉及 Dart↔JS 橋接介面，不新增/修改任何 `window.*` 函式或 `addJavaScriptHandler` 契約）。
- Produces: 無新增介面。

- [x] **Step 1：編輯 `main.js`，設定 `no-swipe` 屬性**

編輯 `app/android/app/src/main/assets/foliate/main.js`，找到 `openBook()` 函式內（約第 885-889 行）：

```javascript
    await view.open(book)
    view.renderer.setAttribute(
      'flow',
      initialPrefs.pageTurnMode === 'scroll' ? 'scrolled' : 'paginated',
    )
```

改為（新增 `no-swipe` 屬性設定，緊接在 `view.open(book)` 之後）：

```javascript
    await view.open(book)
    // epic-27-reader-device-compat Issue 9：停用 paginator.js（FXL 為
    // foliate-fxl，兩者皆讀取同一個 view.renderer 參照）內建的滑動翻頁與
    // 放開時的 snap() 翻頁判定（paginator.js:2186/2499/2558 皆讀取此
    // 屬性）。已查證全專案目前從未設定過這個屬性，也沒有任何功能依賴滑動
    // 翻頁——本產品的導覽模型只有 3×3 熱區與音量鍵（見 CLAUDE.md／
    // prd.md）。不設定此屬性時，長按選字/拖曳劃線手勢會與 paginator.js
    // 內建的滑動翻頁搶同一組觸控事件，選取確立前的最初幾個 touchmove
    // 影格若被 main.js 自己的 longPressGate 攔截器放行，會被 paginator.js
    // 記錄成滑動位移，放開手指時可能誤判翻頁（見
    // docs/epics/epic-27-reader-device-compat/reviews/bugfix-repro.md
    // Issue 9 根因 B）。`setAttribute` 對任何自訂元素皆安全（不像呼叫該
    // 元素不存在的方法會拋例外），故不需要依 view.isFixedLayout 另外判斷。
    view.renderer.setAttribute('no-swipe', '')
    view.renderer.setAttribute(
      'flow',
      initialPrefs.pageTurnMode === 'scroll' ? 'scrolled' : 'paginated',
    )
```

- [x] **Step 2：人工驗證（已知局限，見 Global Constraints——無法透過 `flutter test` 自動化）**

1. 執行 `cd app && flutter run -d <device-id>`（真實 Android 裝置或模擬器），開啟任一流式 EPUB。
2. 在電腦瀏覽器開啟 `chrome://inspect`，找到該裝置上執行中的 WebView（`flutter_inappwebview` 預設可被遠端偵錯），點擊「inspect」開啟 DevTools。
3. 在 DevTools 的 Console 執行：
   ```javascript
   document.getElementById('view').renderer.getAttribute('no-swipe')
   ```
4. 預期回傳空字串 `''`（代表屬性已設定），而非 `null`。
5. 接著在裝置上實際測試：於螢幕右上角區域長按選字，確認不再意外觸發翻頁；用手指快速滑動螢幕，確認滑動不再造成翻頁（3×3 熱區點擊翻頁與音量鍵翻頁應維持正常）。

- [x] **Step 3：Commit**

```bash
git add app/android/app/src/main/assets/foliate/main.js
git commit -m "fix(epic-27): Issue 9——main.js 為 paginator 開啟 no-swipe，停用內建滑動翻頁"
```

---

## 完成後的驗證（對照 `issues.md` Issue 9 驗收標準）

- [x] `flutter analyze`：全專案 "No issues found!"
- [x] `flutter test`：全專案通過，零回歸
- [x] （人工，見 Task 2 Step 2）真機或模擬器上，於流式 EPUB 螢幕右上角區域反覆長按選字/拖曳劃線，確認不再誤觸翻頁；一般點擊熱區翻頁、音量鍵翻頁維持正常。
- [x] `issues.md` Issue 9 的 Solution 第 3-5 項（`tapMaxDurationMs` 收斂、Grace Period、直排安全邊距）**不在本計畫範圍**——若上述人工驗證後仍有殘留的誤觸情況，需回頭在 `issues.md` 追加後續工單，比照 `epic-25` Issue 1 模式安排真機診斷校準，不在本計畫内處理。
