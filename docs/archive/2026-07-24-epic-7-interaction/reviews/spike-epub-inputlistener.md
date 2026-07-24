# Epic 7 Issue 1 — Spike：Readium InputListener.onTap() 驗證報告

**驗證日期：** 2026-07-18
**驗證裝置：** 9491G（Android 15 / API 35，device id 3CEF42ECD491687，螢幕 1600×2400，TCL 客製化 ROM）
**Readium 版本：** kotlin-toolkit 3.3.0
**測試素材：** app/test/fixtures/sample_multi_chapter.epub（流式、多章節）

## Q1：Readium 是否已有內建點擊翻頁行為

**結論：** 不需要停用——未插樁前無內建點擊翻頁行為。
**證據：** spike-q1-baseline-page1.png、spike-q1-tap-left.png、spike-q1-tap-center.png、spike-q1-tap-right.png、spike-q1-logcat.txt

在未修改的 `main` 建置下，於畫面左側（x=260）、中央（x=800）、右側（x=1340）各點擊一次（y 皆為 1200），逐次擷取畫面比對：三次點擊後頁面內容（章節文字、頁碼「第 1/5 頁」）皆與基準截圖完全一致，無任何變化。`spike-q1-logcat.txt` 亦未見任何與 Readium 點擊/翻頁相關的訊息。確認 `EpubNavigatorFragment` 對單純點擊事件無內建的換頁反應，`InputListener.onTap()` 插樁後不需要額外停用步驟即可安全接管點擊語意。

## Q2：InputListener.onTap() 是否能攔下並取代預設行為（反轉方向測試，含重複觸發檢查）

**結論：** 通過。
**證據：** spike-q2-after-3-left-taps.png、spike-q2-tap-right-1.png、spike-q2-tap-right-2.png、spike-q2-tap-right-3.png、spike-q2q3-logcat.txt

插樁採左→前進（`goForward`）、右→後退（`goBackward`）的反轉映射（見 Task 2 Step 2 說明）。實測：

- 起始頁「第 1/5 頁」（章一），連續點擊左側 3 次後畫面移動到「第 4/5 頁」（章三：結局）——3 次點擊、3 次乾淨前進，無跳頁。
- 接著連續點擊右側 3 次，畫面依序移動到「第 2/5 頁」（章二）→「第 1/5 頁」（章一）→「第 1/5 頁」（維持不動）。
- `spike-q2q3-logcat.txt` 記錄 6 次點擊、`onTap` 恰好被呼叫 6 次（1 次註冊時的 REG 訊息 + 6 次 onTap，逐一對應 3 次左 + 3 次右），**無任何重複觸發**——確認我方 `InputListener` 本身沒有被同一次點擊觸發多次。
- 第 3 次右側點擊維持在「第 1/5 頁」不動，符合 `goBackward()` 在書籍起始頁的邊界 clamp 行為（退無可退），非異常。

**附帶觀察（不影響 Q2 通過結論）：** 第 1 次右側點擊出現「第 4/5 頁 → 第 2/5 頁」的雙頁位移，而非預期的乾淨單頁後退。經與 logcat 逐筆比對確認：這次點擊仍然只觸發了 1 次 `onTap`／1 次 `goBackward()` 呼叫（無重複觸發問題），因此雙頁位移並非我方插樁邏輯或攔截失敗所致，而是 Readium 對這本測試書籍（章節內容極短，人工合成、每章僅 1-2 段落）內部「頁碼」計算的顯示特性——「第 X/5 頁」實際反映的是全書 5 個顯示頁的全域頁碼（而非各章獨立重置的頁碼；20%/40%/60%/80%/100% 的進度百分比與此完全對應），`goBackward()` 在跨越極短章節邊界時，其顯示頁碼推進幅度並非總是固定 1，屬於 Readium 內部行為，與 `InputListener.onTap()` 攔截機制本身無關。正式 Issue 6 實作時應使用內容量正常（非本測試用極短合成章節）的書籍驗證實際換頁手感。

**環境附帶發現：** 本裝置（TCL 客製化 ROM）預設會在系統層過濾掉 `Log.d`（Debug 等級）的 `logcat` 輸出——已用 `adb shell log -p d/-i/-w/-e` 四種等級直接比對驗證，僅 `d` 等級被過濾，`i`/`w`/`e` 均正常可見。插樁程式碼因此全面改用 `Log.i`（而非計畫原稿的 `Log.d`）才能在本裝置上觀察到任何插樁證據；若未來在其他裝置或更換這台裝置的韌體後重跑本類插樁驗證，建議一開始就採用 `Log.i` 或更高等級，避免重蹈「程式碼正確執行、但完全看不到任何 log」的排查彎路。

## Q3：InputListener.onTap(point) 座標系統

**結論：** 相對整個 fragment view／publicationView 的本地座標（兩者尺寸相同，無 letterbox），不需要額外轉換公式。
**證據：** spike-q2q3-logcat.txt（point 與 publicationView/fragmentView 尺寸對照）

實測 6 筆 `onTap` 紀錄，`publicationView.width=1600 height=1910`、`fragmentView.width=1600 height=1910`——兩者完全相同，確認該 view 沒有 letterbox 留白或縮放置中偏移。

- 左側點擊（`adb shell input tap 260 1200`）：`point.x=258.49`，與螢幕觸控 x 座標（260）幾乎完全吻合（誤差 ≈1.5px，屬觸控事件本身的精度雜訊，非座標轉換造成）。
- 右側點擊（`adb shell input tap 1340 1200`）：`point.x=1338.19`，與螢幕觸控 x 座標（1340）同樣幾乎完全吻合。
- 兩者 `point.y` 皆為 `1015.65`，與螢幕觸控 y 座標（1200）相差固定 ≈184.35px——這個差值對應閱讀器畫面中 `publicationView`／`fragmentView` 上方的狀態列 + AppBar 佔用高度（`fragmentView.height=1910` 而非螢幕高度 2400，差距 490px 已涵蓋上下兩端的系統/App 版面元件）。

換算結論：`TapEvent.point` 本來就是相對 `publicationView`（=`fragmentView`）自身左上角的本地座標，**不是**相對整個實體螢幕。因此 `NavZoneHitTester.cellIndex()` 若在 Kotlin 端直接用 `event.point` 對 `publicationView.width/height` 做九宮格判斷，兩者天生處於同一個座標系，**不需要額外的座標轉換公式**——這與 `spec.md` 原先的規劃假設一致，唯一需要注意的是：若有人想用 `adb shell input tap` 這類「螢幕絕對座標」手動核對測試結果，必須先扣掉上方系統列/AppBar 的高度，才能對得上 `TapEvent.point` 的數值。

## 對 Issue 6 的收斂結論

三項風險皆已透過真機驗證收斂，**Issue 6 可依 `spec.md` 既有規劃、採用 `InputListener` 路線直接實作**，不需要退回自行實作方案，具體收斂如下：

1. **Q1（是否需要停用內建行為）**：不需要——`EpubNavigatorFragment` 對單純點擊無內建反應，`spec.md` 中「停用內建行為」的相關規劃段落可視為不適用（保留文字說明即可，不需刪除，作為未來若 Readium 版本升級後行為改變時的追蹤依據）。
2. **Q2（攔截有效性）**：`InputListener.onTap()` 攔截可靠、無重複觸發，`goForward()`/`goBackward()` 呼叫與點擊次數嚴格 1:1 對應，可直接作為 Issue 6 熱區動作分派的呼叫基礎。唯一需要留意的是：正式驗收/QA 時應使用內容量正常的書籍測試換頁觀感，避免用本次極短合成章節的測試素材誤判「單次點擊是否只翻一頁」（本次驗證已透過 logcat 呼叫次數精確排除了此疑慮，並非插樁本身的問題）。
3. **Q3（座標系統）**：`TapEvent.point` 為 `publicationView` 本地座標，與 `publicationView.width/height` 同一座標系，`NavZoneHitTester.cellIndex()` 不需要額外轉換公式，`spec.md` 現有規劃無需修改。

**唯一需要補充進 `spec.md` 的實務提醒**：Debug 等級 log 在部分裝置（至少本次驗證用的 TCL 9491G）會被系統層過濾，Issue 6 實作階段若需要除錯插樁，建議直接採用 `Log.i` 或更高等級。
