# Issue 8：閱讀器底部被狀態列/導航列遮蔽 — 實作計劃

**Goal:** 修正閱讀器畫面底部被 Android 狀態列或導航行動列遮蔽的問題

**根因分析（原始版本）：**
`ReaderScreen.build()` 回傳 `Scaffold`，其 `body` 直接放入 `Stack` 包含原生 `PlatformView`，但未處理系統 UI insets（`MediaQuery.viewPadding.bottom`）。導致 PlatformView 佔滿全高，底部內容被系統 UI 遮蔽。

Task 1（`SafeArea`）已於 `197a013` commit 落地，對流動式 EPUB／PDF 有效。但 `a2e1cc3`（加入 `Fit.CONTAIN`）之後，`9a1f0c8` commit 又針對固定版面（漫畫）額外注入了一段 WebView 內 JS/CSS（`applyFixedLayoutCssInjection()`），後續真機驗證發現漫畫版面「仍會被上下切到一些，橫放時更嚴重、不會自動縮放」——與流動式 EPUB／PDF 的行為不一致。以下為透過 `/diagnose` 對三種格式的縮放機制做架構比對後，重新確認的根因，取代原始版本殘留的部分結論。

---

## 修訂紀錄：固定版面（漫畫）縮放行為的迴歸

**根因（架構比對確認）：**

三種格式原本的縮放機制：

| 格式 | 縮放機制 | 是否受 `SafeArea` 約束 |
|---|---|---|
| 流動式 EPUB | ReadiumCSS 自動 reflow（WebView `onSizeChanged`） | 是——用容器真實測量尺寸 |
| PDF | `ImageView` 預設 `ScaleType.FIT_CENTER`，用真實 View 像素尺寸自動置中縮放 | 是——同上 |
| 固定版面 EPUB（漫畫，修正前） | 原生 `Fit.CONTAIN`（`a2e1cc3`）**再疊加** `applyFixedLayoutCssInjection()` 注入的 WebView JS/CSS（`9a1f0c8`） | **否**——強制 `html, body { width:100vw; height:100vh }` |

`applyFixedLayoutCssInjection()`（`EpubReaderView.kt`，`onPageLoaded()` 每次翻頁都呼叫一次）注入的 CSS 使用 WebView **內部視口單位**（`100vw`/`100vh`），這是跟 Flutter/`SafeArea` 給原生容器的真實測量尺寸完全獨立的另一套座標系統——PDF 的 `ImageView.FIT_CENTER`、EPUB 的 ReadiumCSS reflow 都是直接吃「容器的真實像素尺寸」（已被 `SafeArea` 排除系統列），漫畫這條路徑卻额外疊加一層跟原生 `Fit.CONTAIN` 互相打架的 WebView CSS 覆寫，且未隨旋轉正確重算，對應「上下切一點、橫放更嚴重、不會自動縮放」的症狀。

**修正：** 移除 `EpubReaderView.kt` 的 `applyFixedLayoutCssInjection()` 與其輔助函式 `findWebView()`，以及 `onPageLoaded()` 中對它的呼叫，讓固定版面 EPUB 完全依賴既有的 `Fit.CONTAIN`（原生機制，操作在已被 `SafeArea` 排除系統列的真實容器尺寸上），與流動式 EPUB／PDF 統一建立在同一套「原生 View 真實測量尺寸」縮放基礎上，不再自成一套顯示模式。`9a1f0c8` commit 同時加入的粗體字型 face 對應（獨立改動）不受影響、予以保留。

**結果：** 移除該注入後，真機用 WebView 遠端除錯（Chrome DevTools Protocol）實測，`/json` 列表回報固定版面頁面的 WebView 實際 Android View 高度仍是 `2401`px（幾乎等於整台裝置實體螢幕 2400px），跟同一台裝置上流動式 EPUB 的 WebView（正確地是 `2116`px，剛好貼齊狀態列/AppBar/Taskbar 讓出的可視範圍）形成鮮明對比——證明問題不是我們自己 Kotlin 包裝層的邏輯錯誤，而是更深一層：真機仍回報「仍會切到部分」，因而繼續往下追查，見下方「二次追查」。

---

## 二次追查（`/diagnose`）：Readium 固定版面元件本身的版面尺寸機制

**根因（已取得 Readium 官方原始碼確認，非反編譯猜測）：**

透過 `raw.githubusercontent.com` 直接讀取 `readium/kotlin-toolkit` 3.3.0 tag 的原始碼，鎖定固定版面單頁排版所用的
`readium/navigator/src/main/res/layout/readium_navigator_fragment_fxllayout_single.xml`：

```xml
<org.readium.r2.navigator.epub.fxl.R2FXLLayout android:layout_width="match_parent" android:layout_height="match_parent">
    <ScrollView android:layout_width="match_parent" android:layout_height="match_parent" android:fillViewport="true">
        <RelativeLayout android:layout_width="match_parent" android:layout_height="wrap_content">
            <LinearLayout android:layout_width="wrap_content" android:layout_height="wrap_content">
                <org.readium.r2.navigator.R2BasicWebView
                    android:id="@+id/webViewSingle"
                    android:layout_width="0dp"
                    android:layout_height="wrap_content"
                    android:layout_weight="1" />
            </LinearLayout>
        </RelativeLayout>
    </ScrollView>
</org.readium.r2.navigator.epub.fxl.R2FXLLayout>
```

外層 `R2FXLLayout`／`ScrollView` 都是 `match_parent`，確實有正確吃到我們給的（已被 `SafeArea` 排除系統列的）真實容器高度——這部分沒問題。問題出在最內層的 `webViewSingle`：**`layout_height="wrap_content"`**，寬度靠 `layout_weight` 對齊可用寬度沒錯，但高度完全依內容在該寬度下的天然渲染高度撐開，不受外層容器高度限制；超出外層 `ScrollView` 可視範圍的部分變成「可捲動但預設不可見」的區域，而非被縮小以符合可視範圍。配合 `setupWebView()` 裡的 `useWideViewPort = true` + `loadWithOverviewMode = true`，WebView 實際上只做「縮放至符合可用寬度」，完全沒有做「同時符合可用高度」的判斷——也就是隻有 fit-by-width，沒有真正的 `Fit.CONTAIN`（同時滿足寬高、取較小縮放比）。這正好解釋：
- 「仍會切到部分」：內容天然高度（寬度已 fit）通常會超過扣掉狀態列/Taskbar 後的可視高度。
- 「橫放時更嚴重」：橫向可視高度更短，寬度 fit 出來的高度超出比例更大。
- 「不會自動縮放」：`wrap_content` 高度沒有任何機制隨容器可用高度重新計算縮放比。

這是 Readium 3.3.0 這份內建 XML 資源本身的行為，不在我們自己的原始碼樹裡，無法直接修改；`EpubPreferences.fit = Fit.CONTAIN`（`a2e1cc3` 設定）對單頁固定版面排版沒有實際約束到這個高度計算。

**修正（App 端補償，非改動 Readium 本身）：**
`EpubReaderView.kt` 新增 `applyFxlFitScale()`：在 `onPageLoaded()` 時，只要 `publication.metadata.layout == Layout.FIXED`，就用 `findViewByType<WebView>()` 找到內層 WebView，比較 `container.height`（Flutter 給定、已正確扣除系統列的真實可用高度）與 WebView 實際測量高度，算出縮小比例（`coerceAtMost(1f)`，只縮不放大），透過標準 `android.view.View` 的 `scaleX`/`scaleY`/`pivotX`/`pivotY`（`pivotY=0` 從頂端錨定）對 WebView 做等比縮放。

原本考慮改呼叫 Readium 自己提供、專門處理手勢縮放的 `R2FXLLayout.setScale()` public API，但反編譯／編譯錯誤確認該類別在 Kotlin 模組層級宣告為 `internal`（javap 看到的 `public` 只是 JVM bytecode 可見度，Kotlin 編譯器仍會擋下跨模組引用），因此改用 `View` 基底類別本身就公開的縮放屬性，純視覺變形、不觸碰 Readium 內部狀態。

**驗證結果（真機，第一版）：**
- 修正前：漫畫封面頁滿版貼齊螢幕邊緣，最下面一列內容明顯被裝置常駐 Taskbar 遮住一截。
- 修正後：同一頁完整置中顯示、四邊有正確的留白（letterbox），不再被 Taskbar 遮蔽；旋轉裝置至橫向後同樣完整置中顯示（寬度較窄一側出現留白，符合 `Fit.CONTAIN` 的等比縮放語意）。
- **但**使用者後續真機測試翻到書中其他頁，回報「仍有部份切到」，見下方第二輪修正。

---

## 三次追查（`/diagnose`）：殘留裁切與旋轉不重算

**使用者提問：**「是否評估上下多留一項空白？還是因為計算後小數點再換算大小造成落差？」

**回覆／根因：** 不是四捨五入（那頂多次像素等級，不會有肉眼可見的裁切），也不該用固定留白去補（治標、留多少沒有穩定答案）。實際是兩個獨立的時機問題：

1. **`onPageLoaded()` 觸發時，WebView 的 `wrap_content` 高度可能還沒完全撐開**（內部圖片解碼/reflow 可能還在進行），當下讀到的高度偏小，算出來的縮放比例就偏大（縮得不夠），畫面上殘留一小截裁切。
2. **旋轉裝置後畫面沒有重新計算縮放**——`MainActivity` 宣告了 `android:configChanges="orientation|screenSize|..."`，旋轉不會重建 Activity／Fragment，`onPageLoaded()` 不會再次觸發，先前算好的縮放比例是舊方向的數值，套用在新方向 WebView 的天然高度上會算錯。

**修正：** 把 `applyFxlFitScale()` 從「`onPageLoaded()` 當下算一次（或後續版本改成有限次數重試）」，改為在 `container`（穩定存在、不隨翻頁/換頁面 Fragment 重建）上掛一個 `ViewTreeObserver.OnGlobalLayoutListener`：只要 View 樹的量測/版面發生變化就會觸發（旋轉造成 `container` 尺寸改變、WebView 內容延遲撐高、換頁換成新的 WebView 實例……皆包含在內），每次觸發都重新尋找目前的 WebView、重新計算縮放比。`scaleX`/`scaleY` 只是繪製階段變形、不會觸發新的 layout pass，因此監聽器不會自我觸發無限迴圈。監聽器在 `dispose()` 中移除，避免 View 生命週期外洩漏。

**驗證結果（真機，此輪）：**
- 漫畫封面頁：直向完整置中顯示，四邊留白正確；旋轉至橫向後**立即**重新等比縮放，四邊留白正確（含先前橫向測試中仍略微裁切的頂部標題文字，這次完整可見），無需使用者手動介入。
- 差異對照：`adb shell dumpsys activity --view-hierarchy` 確認 WebView 原生量測邊界維持 `0,0-1600,2401`（未受 `scaleX`/`scaleY` 影響，符合 Android 對 scale 變形的既有行為——純繪製階段效果，不影響量測結果），螢幕截圖確認實際顯示結果正確收斂。
- **但**只用封面頁驗證不夠：使用者提供實際 `葬送的芙莉蓮 11.epub`，指出「封面算第一頁的話，第 7, 8, 9 頁會出現切到的情況」，且再次回報「旋轉螢幕時不會重新縮放」——見下方第四輪修正。

---

## 四次追查（`/diagnose`）：翻到特定頁仍會裁切——同時存在多個 WebView

**回饋建構的驗證迴圈：** 這次直接用使用者提供的實際檔案（`tmp/葬送的芙莉蓮 11.epub`）`adb push` 到裝置，用 Chrome DevTools Protocol 監看目前顯示的 XHTML resource URL、搭配 `adb shell input swipe` 逐頁往前推進，精準定位到第 7 頁（`p-006.xhtml`，封面算第 1 頁）並截圖——這頁確實完整重現使用者回報的裁切（底部整排面板被裁掉，跟第一輪修正前的症狀一樣）。

**根因：** `adb shell dumpsys activity --view-hierarchy` 檢查發現，**同時存在 3 個 `R2BasicWebView` 實例**（各自的 `R2FXLLayout` 父容器橫向並排、由外層 `R2ViewPager` 位移決定哪一個落在可視範圍）——這是 Readium 為了讓翻頁動畫流暢，預先把目前頁的前後相鄰頁面都準備好的正常機制。但先前 `applyFxlFitScale()` 用的是 `findViewByType`（單數，只回傳 View 樹中第一個符合型別的節點），只會處理到排序最前面的那個 WebView，並不保證是使用者實際翻到、目前正顯示的那一頁。**封面頁剛好是第一個載入的 WebView（在樹裡排序自然靠前），所以第一輪測試看起來完全修好了；翻到第 7-9 頁後，「目前顯示的那一頁」在樹裡的排序不再是第一個，就完全沒被套用縮放，重新表現出跟修正前一樣的裁切。**

**修正：** 新增 `findViewsByType`（複數）取代 `findViewByType`，回傳 View 樹中所有符合型別的節點；`applyFxlFitScale()`／`applyFontWeightCascade()` 都改成對「找到的每一個 WebView」個別套用邏輯，不論最終哪一個落在可視範圍內都已經處理過。

---

## 五次追查（`/diagnose`）：改成處理全部 WebView 後，部分頁面改成頂端裁切

**症狀：** 套用上述修正後，第 7 頁不再底部裁切，但變成**頂端**被裁切、底部反而多出一截不成比例的空白。

**根因：** 反編譯／檢視 Readium 內建 XML（`RelativeLayout` 包一層 `LinearLayout[android:layout_centerInParent="true"]` 再包 WebView）本身就會依內容高度把 WebView 在 `RelativeLayout` 內垂直置中——也就是說 WebView 進入 `applyFxlFitScale()` 時，它的 `top` 量測值本來就可能不是 0（可能已經是負值，取決於這一頁天然高度與 `RelativeLayout` 可用高度的差異）。先前用 `pivotY=0` 縮放，是以 WebView *自己* 那個（已經帶著 Readium 內部置中位移的）左上角為錨點縮放——縮放後這個位移原封不動保留在畫面上，導致縮小後的內容仍然頂端出畫面，底部則多出「被吃掉的縮放比例」對應的空白。這解釋了為什麼不同頁面表現不一致：每一頁的天然高度不同，Readium 內部置中算出來的位移量也不同。

**修正：** 不再依賴 pivot 的相對位移語意，改用 `View.getLocationOnScreen()` 直接量出 WebView 與 `container` 目前實際的螢幕座標差，反推出「讓縮放後的內容剛好置中在 container 裡」所需要的 `translationX`／`translationY` 補償值——不論 Readium 自己的置中邏輯把 WebView 的原始 layout 位置擺在哪裡，都能算出正確的最終位置，不需要猜測或校正它的內部位移規則。縮放比例同時也改成 `min(可用寬度/內容寬度, 可用高度/內容高度)`（真正的雙軸 `Fit.CONTAIN`），取代先前只看高度的算法，避免極端寬高比頁面在另一軸溢出。

**驗證結果（真機，最終版，使用者提供的實際檔案）：**
- 第 7 頁（`p-006.xhtml`）：完整可見，四邊留白正確，與使用者原始截圖回報的裁切位置完全一致的內容，現在完整顯示無裁切
- 第 15 頁（`p-015.xhtml`，隨機再抽測的另一頁）：同樣完整可見、四邊留白正確
- 同一頁旋轉至橫向：立即重新置中，四邊留白正確，無需使用者手動介入
- `flutter test integration_test/epub_reader_view_test.dart` 真機 9/9 全過

---

### Task 1: 在 ReaderScreen 加入 SafeArea 處理

**Files:**
- Modify: `app/lib/screens/reader_screen.dart`

**Description:**
在 `_buildBody()` 回傳的 `Stack` 外層包裝 `SafeArea`，讓原生視圖避開系統 UI 佔用區域。

- [ ] **Step 1: 修改 `_buildBody()` 方法**

```dart
// Before (lines 252-261):
return Stack(
  children: [
    _buildNativeView(format),
    if (_state == _RenderState.loading)
      const Center(
        key: Key('reader_loading_indicator'),
        child: CircularProgressIndicator(),
      ),
  ],
);

// After:
return SafeArea(
  child: Stack(
    children: [
      _buildNativeView(format),
      if (_state == _RenderState.loading)
        const Center(
          key: Key('reader_loading_indicator'),
          child: CircularProgressIndicator(),
        ),
    ],
  ),
);
```

**備註：**
- `SafeArea` 會自動讀取 `MediaQuery.viewPadding` 並加入適當 padding
- AppBar 已由 `Scaffold` 處理，只需處理 body 區域
- 直排/橫排模式下，`SafeArea` 會依方向自動調整

---

### Task 2: 確認 EpubReaderView/PdfReaderView 高度計算

**Files:**
- Verify: `app/lib/reader/epub_reader_view.dart`
- Verify: `app/lib/reader/pdf_reader_view.dart`

**Description:**
確認原生視圖的 `AndroidView` 會正確適應 `SafeArea` 提供的約束。

- [ ] **Step 1: 確認 AndroidView 使用 `hitTestBehavior: HitTestBehavior.translucent`**

```dart
// epub_reader_view.dart 和 pdf_reader_view.dart 的 build() 方法：
return AndroidView(
  viewType: 'cc.ugotit.elinkbook/epub_reader_view', // 或 pdf_reader_view
  onPlatformViewCreated: _onPlatformViewCreated,
  hitTestBehavior: HitTestBehavior.translucent, // 確保正確接收手勢
);
```

---

### Task 3: 建立整合測試

**Files:**
- Create: `app/integration_test/reader_insets_test.dart`

**Description:**
驗證在不同螢幕尺寸下，閱讀器內容不被系統 UI 遮蔽。

- [ ] **Step 1: 測試 SafeArea 正確套用**

```dart
testWidgets('閱讀器內容不被系統 UI 遮蔽', (tester) async {
  // 設定模擬的 viewPadding（模擬狀態列和導航列）
  tester.binding.window.viewPaddingTestValue = const FakeViewPadding(
    top: 24, // 狀態列高度
    bottom: 48, // 導航列高度
  );
  
  // 載入閱讀器
  await tester.pumpWidget(MaterialApp(
    home: ReaderScreen(
      filePath: samplePath,
      bookId: 'test_book',
      prefsRepository: prefsRepository,
    ),
  ));
  
  // 確認內容區域有適當的 padding
  final safeArea = find.byType(SafeArea);
  expect(safeArea, findsOneWidget);
  
  // 恢復
  tester.binding.window.clearViewPaddingTestValue();
});
```

---

### 驗收標準
- 書籍內容完整顯示，不被系統 UI 遮蔽
- 直排/橫排模式下皆正常
- `flutter test` 通過、`flutter analyze` 乾淨
- 固定版面（漫畫）真機驗證：直向與橫向皆能自動置中縮放、不被上下系統列裁切，行為與流動式 EPUB／PDF 一致（不再是獨立的顯示模式）
