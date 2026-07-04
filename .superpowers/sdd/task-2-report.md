# Task 2 實作報告：TXT 封面產生器（純 Dart，`dart:ui`）

## 概要

成功實作 `generateTxtCover` 函數及其完整測試套件。此函數根據書名文字動態產生 TXT 書籍的正方形封面圖片（400×400px PNG），背景色由書名首字的 code unit 決定（保證重現性），白色文字顯示首字。

## 實作檔案

### 建立檔案

1. **實作檔案：**`app/lib/library/txt_cover_generator.dart`
   - `generateTxtCover(String title): Future<Uint8List>` ── 非同步生成 PNG bytes
   - `_backgroundColorForTitle(String title): ui.Color` ── 私有輔助函數，根據書名首字決定背景色
   - `_palette: const List<ui.Color>` ── 6 色調色盤，提供色彩多樣性且避免碰撞

2. **測試檔案：**`app/test/library/txt_cover_generator_test.dart`
   - 4 個測試用例，共 58 行
   - 不做像素級 Golden Image 比對（避免平台間字型渲染差異），只驗證 PNG 簽章、相同書名重現性、不同書名差異性、空字串容錯

## 測試執行結果

### RED 狀態（測試執行前，實作檔案不存在）

```
test/library/txt_cover_generator_test.dart:2:8: Error: Error when reading 'lib/library/txt_cover_generator.dart': 系統找不到指定的檔案。
import 'package:elinkbook/library/txt_cover_generator.dart';
       ^
```

預期編譯錯誤 ✓

### GREEN 狀態（實作完成後，所有測試通過）

```
00:00 +0: loading U:/MyDeveloper/AI/elinkBook/.claude/worktrees/epic-1-issue-4-book-import-service/app/test/library/txt_cover_generator_test.dart
00:00 +0: generateTxtCover 產生非空的 PNG bytes（含正確的 PNG 檔頭簽章）
00:00 +1: 相同書名產生相同背景色（可重現，非隨機）
00:00 +2: 不同書名（不同首字）產生不同背景色
00:00 +3: 空字串書名不拋出例外，仍產生有效封面
00:00 +4: All tests passed!
```

所有 4 個測試用例 ✓ 通過

## 靜態分析結果

```
Analyzing app...                                                
No issues found! (ran in 2.5s)
```

無任何警告或錯誤 ✓

## 提交資訊

```
commit eed3d17
Author: Hu Yen-Chuan <huthief@gmail.com>
Date:   Sat Jul 4 2026

    Add pure-Dart TXT cover generator using dart:ui
    
    Co-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>
```

## 實作詳解

### 核心邏輯

1. **畫布建立：** 使用 `ui.PictureRecorder` 錄製繪圖指令，建立 400×400px 的正方形畫布
2. **背景填色：** 使用 `_backgroundColorForTitle()` 計算的顏色填滿整個矩形
3. **文字渲染：** 
   - 取書名首字（空字串則用「?」）
   - 使用 `ui.ParagraphBuilder` 建立段落，字體大小為 160px（畫布的 40%）
   - 文字對齐至中心，垂直居中於畫布
   - 白色（`0xFFFFFFFF`）文字
4. **PNG 轉換：** 透過 `toImage()` 轉為點陣圖，再用 `toByteData(format: ui.ImageByteFormat.png)` 導出 PNG bytes

### 色盤設計

6 色調色盤基於 Material Design 顏色系統：
- `0xFF5C6BC0`（深藍）
- `0xFF26A69A`（深青綠）
- `0xFFEF5350`（深紅）
- `0xFFFFA726`（深橙）
- `0xFF8D6E63`（褐）
- `0xFF7E57C2`（深紫）

通過 `codeUnitAt(0) % 6` 計算，確保同一本書每次產生相同背景色。

## 自我審查

### 完整性

- [x] 4 個測試用例全部實作
- [x] 所有測試通過（00:00 +4）
- [x] 靜態分析無警告
- [x] 提交成功

### 程式碼品質

- [x] 完全符合 brief 規格
- [x] 符合既有程式碼風格
- [x] 充分的文件註解（Dart doc）
- [x] 無多餘程式碼
- [x] 異常處理得當（空字串用「?」替代）

### 測試穩健性

- [x] PNG 簽章驗證──與平台無關
- [x] 重現性驗證──相同書名總是生成相同 bytes
- [x] 差異性驗證──紅樓夢（U+7D05）與三國演義（U+4E09）的 code unit 對 6 取餘數確實不同，無碰撞風險
- [x] 容錯驗證──空字串不拋例外，產生有效封面

### 技術考量

- [x] 純 `dart:ui` 實作，不涉及平台 channel
- [x] 非同步設計（回傳 `Future<Uint8List>`），符合呼叫端預期
- [x] 固定大小（400×400px），足夠支援後續的書架視圖縮略圖顯示

## 所有步驟完成

- [x] Step 1：撰寫測試
- [x] Step 2：執行測試確認失敗
- [x] Step 3：實作 `generateTxtCover`
- [x] Step 4：執行測試確認通過
- [x] Step 5：靜態分析確認無警告
- [x] Step 6：Commit

## 無任何問題或疑慮

此實作已完全按照 brief 規格進行，測試穩定，程式碼品質良好，準備好供 Task 3（`BookImportServiceImpl`）呼叫。
