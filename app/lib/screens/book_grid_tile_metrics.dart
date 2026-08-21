import 'package:flutter/painting.dart' show TextScaler;

/// 分類拼貼格（`_GroupGridTile`）與書籍格（`_BookGridTile`）共用的文字說明區
/// 固定高度基準值（epic-18-reader-device-qa Issue 42，epic-26-architecture-
/// hardening Issue 8 從 `library_screen.dart` 抽出）：兩者原本文字說明區
/// 行數不同（前者 1 行、後者 2 行），導致封面 Expanded 吃到的剩餘高度不同，
/// 橫屏下兩者同列時封面底部邊界因此錯開（真機回報，已用 widget test 精確
/// 量測相差 14px）。固定高度取書籍格 2 行文字（書名＋進度）所需的自然高度
/// 為準，分類拼貼格的 1 行文字說明包進同樣高度的容器（會留一點點底部空白，
/// 換取跨 cell 對齊），是本修法必然的取捨。
///
/// 【程式碼審查修正】這是基準值（1.0 倍系統字級下的高度），實際使用時一律
/// 要經過 [gridTileFooterHeight] 換算成當下系統字級對應的高度，不可直接
/// 當作固定像素值使用——否則使用者放大系統字級時，書籍格的 2 行文字會被
/// 這個寫死的高度截斷，觸發 `RenderFlex` 溢位（審查發現：修法前文字說明區
/// 是自然高度、不會有這個風險，此為修法本身新引入、需要一併防護的技術債）。
const kGridTileFooterHeightAtScale1 = 34.0;
const kGridTileFooterTitleFontSize = 12.0;
const kGridTileFooterProgressFontSize = 10.0;

/// 【/diagnose 第七輪：Air Reader C 真機回報】上面 34.0 這個基準值原本是
/// 直接整體丟進 `textScaler.scale(34.0)`，但 `_BookGridTile` 實際渲染的
/// 兩行文字（書名 12px＋進度 10px）是各自獨立呼叫 `scale(12)`／
/// `scale(10)`——兩者只有在縮放曲線是「線性」（`scale(x) = x * 固定倍率`）
/// 時才恆等。真機使用者手動調大系統字級後，Android 會套用「非線性字級
/// 縮放」（避免超大字級把版面撐爆，對數值較大的輸入相對縮放得較保守），
/// `scale(34)` 因此比 `scale(12) + scale(10)` 縮放得少，容器高度不夠、
/// 觸發 RenderFlex 溢位。`flutter_test` 套件的 `TestPlatformDispatcher.
/// scaleFontSize` 寫死是線性乘法，先前的 widget test（`TextScaler.
/// linear(1.5)`）測不出這個落差。修法：改成對書名／進度兩個實際字級分別
/// 呼叫 `scale()` 後再相加，比對真正 Text 元件的縮放方式，
/// [kGridTileFooterLineHeightFactor] 則是由 34.0 這個既有校準值反推出來、
/// 與縮放曲線無關的固定行高比例常數，確保系統字級 1.0 倍時仍與原本行為
/// 完全一致。
const kGridTileFooterLineHeightFactor = kGridTileFooterHeightAtScale1 /
    (kGridTileFooterTitleFontSize + kGridTileFooterProgressFontSize);

/// 依 [scaler]（呼叫端傳入 `MediaQuery.textScalerOf(context)`）換算文字
/// 說明區的實際像素高度（epic-26-architecture-hardening Issue 8）。刻意
/// 接受 [TextScaler] 而非 `BuildContext`——讓這段縮放數學可以完全脫離
/// widget 樹，用純 `test()` 直接驗證（見 `book_grid_tile_metrics_test.dart`），
/// 不需要 `testWidgets()`。
double gridTileFooterHeight(TextScaler scaler) {
  return (scaler.scale(kGridTileFooterTitleFontSize) +
          scaler.scale(kGridTileFooterProgressFontSize)) *
      kGridTileFooterLineHeightFactor;
}
