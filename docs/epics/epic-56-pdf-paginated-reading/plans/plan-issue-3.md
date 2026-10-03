# Issue 3：幾何隔離與快取外擴 spike（需真機）實作計畫

> **給執行者：** 必要子技能：使用 `superpowers:executing-plans` 逐 Task 執行本計畫（本 Issue 是 spike，且需人類在真機上操作與觀察，不適合 subagent-driven）。步驟使用 checkbox（`- [ ]`）語法追蹤進度；每完成一個 Step 就把它改為 `- [x]`。標註「**【人類】**」的步驟必須由人類在真機上操作並回報數字，AI 不可自行填寫觀察值。

**Goal：** 用可丟棄的實驗程式在真機回答 `spec.md`「幾何隔離」的三個問題，並把結論（間距公式、快取外擴設定）補回 `spec.md`，實驗記錄寫入 `epic.md`。**本 Issue 沒有任何產品程式碼變更**，實驗程式碼不得進入 `main`。

**Architecture：** 實驗程式放在獨立的 spike 分支（`epic-56/issue-3-spike`，永不發 PR）：一支 Node 腳本產生含細格線的測試 PDF（含數千頁、混合尺寸）、一支純 Dart 腳本在電腦上先算出「理論所需間距」與 32 位元浮點精度表，再加一個獨立入口的 `PdfViewer` 實驗畫面（可調間距、快取外擴、Fit 模式，並用 HUD 顯示「可視矩形與快取矩形各與哪些頁相交」與「版面重算次數」）。最後只把文件（`spec.md`、`epic.md`、`issues.md`）以另一條 docs 分支發 PR。

**Tech Stack：** Flutter／Dart、`pdfrx` 2.4.7（`layoutPages`、`normalizeMatrix`、`verticalCacheExtent`／`horizontalCacheExtent`、`PdfViewerController`）、Node.js（產生測試 PDF）、`adb`。

**Spec：** `docs/epics/epic-56-pdf-paginated-reading/spec.md`（「幾何隔離（逐頁的 `layoutPages`）」，第 111～118 行）；工單見 `issues.md` Issue 3。

## 已查證的現況（本計畫的依據，執行者不必重查，但若不符請停下來回報）

- `pdfrx` 2.4.7 的 `PdfViewer` 在每次 `LayoutBuilder` 重建時呼叫 `_updateLayout(viewSize)`（`pdf_viewer.dart:604`、`759`），其中 `_relayoutPages()` 都會重新呼叫 `params.layoutPages(pages, params)`（`1167～1180`）；版面與上次相等（`PdfPageLayout.==` 比對全部矩形與文件尺寸）就不算「版面改變」。所以**視窗尺寸改變時 `layoutPages` 一定會被再呼叫**，但它**拿不到 `viewSize`**（簽章只有 `pages` 與 `params`）——元件必須自己用外層 `LayoutBuilder` 記下尺寸，讓 `layoutPages` 的閉包讀取。問題 3 的「是否重算版面」實際要驗的是：閉包讀到的尺寸是不是同一輪的新尺寸，以及隨之而來的 `sizeDelegate.onLayoutUpdate` 是否把視窗留在原單元。
- `normalizeMatrix` 簽章為 `Matrix4 Function(Matrix4 matrix, Size viewSize, PdfPageLayout layout, PdfViewerController? controller)`，**有** `viewSize`，所以平移鎖定（含縮放下限）可以依視窗尺寸即時計算；`controller.value = ...` 的 setter 一律以 `forceClamp: true` 走 `normalizeMatrix`。
- `PdfViewerController` 可讀 `layout`、`viewSize`、`visibleRect`、`value`（`Matrix4`）、`pageNumber`、`pageCount`。
- 快取外擴：`_getCacheExtentRect()` ＝ 可視矩形各邊再外擴「可視寬／高 × `horizontalCacheExtent`／`verticalCacheExtent`」（預設各 1.0）；它只決定哪些頁被預先渲染，不影響可見性（`spec.md` 已記，I-3 查證）。
- `vector_math` 的 `Matrix4` 以 `Float32List` 儲存（`matrix4.dart:10`），所以平移量（`ty ≈ -y × 縮放`）在大座標下只有約 24 位元有效精度；Dart 的 `double` 運算本身是 64 位元，不受影響。
- 專案已有 `app/lib/reader/pdf_paginated_rules.dart` 的 `fitBaseScale()`／`fitOrigin()`（Issue 1，已合併），實驗程式直接重用，不重寫縮放基準。
- 版面是**縱向疊放**，相鄰單元只在縱向相鄰，所以不變式只需處理縱向：可視矩形的縱向超出量 ＜ 單元間距。單元縮放後比可視高度矮時會被置中（letterbox），超出量最大發生在縮放＝基準時，為 `max(0, (可視高 ÷ 基準 − 單元高) ÷ 2)`；縮放大於基準或縱向已溢出時，可視矩形被鎖在單元內，超出量為 0。極端長寬比（例如橫放的寬扁頁放進直立螢幕）超出量可以非常大，這是需要用數字量化的重點。
- 所有 `.dart`／`.arb`／`.md` 原始檔為 CRLF（`core.autocrlf true`）。`Edit` 的定位字串只用**單行**。

## Global Constraints

- **語言**：文件、註解、測試名稱一律正體中文（zh-TW）；程式碼命名維持英文慣例。
- **實驗程式碼不進入 `main`**：spike 分支永不發 PR、不合併；`main` 只收文件變更（`spec.md`、`epic.md`、`issues.md`、`epics.md` 進度）。
- **觀察值不可捏造**：標【人類】的步驟，數字與觀察一律由人類在真機提供；沒有實測證據的格子留空並在 `epic.md` 註明「未測」，不可用推論補。
- **驗收**（`issues.md`）：`spec.md` 幾何隔離段落由「待決定」變成具體公式與設定，且三個問題各有實測證據。
- **提交前**（針對 docs 分支）：文件變更不需跑 `flutter test`；但 spike 分支若動到 `pubspec`／產品檔案就是違規（實驗只新增檔案，見 File Structure）。
- **Commit 不加 `Co-Authored-By` 或「Generated with」等署名行**（使用者 2026-10-03 指示）。
- **流程**：計畫先審查再動手；本 Issue 無程式審查（無產品程式碼），但 `spec.md` 的修訂須由使用者確認結論後才寫入。
- **發版限制**（`issues.md` 開頭）：本 Issue 不改產品行為，無發版影響。

## Review Focus

最可能讓結論失真或事後咬到使用者的情況（依可能性排序），每條都有對應的實驗步驟：

1. **極端長寬比的頁面放不下單一固定間距**：橫放寬扁頁、混在直式文件中的長頁（595×3000）、雙頁 spread（約 1190×842）在直立螢幕的 letterbox 超出量遠大於一般 A4。→ Task 2 的 `geometry_check.dart` 與 Task 4 的混合尺寸文件。
2. **大座標下 32 位元浮點對位誤差**：數千頁 × 大間距使 `ty` 超過 Float32 可精準表示的範圍，換頁後頁面邊緣模糊或平移時抖動。→ Task 2（ULP 表）、Task 6（真機看細格線）。
3. **旋轉／摺疊後 `layoutPages` 閉包讀到舊尺寸**，導致不變式在新尺寸下被破壞（鄰頁露出），或視窗跳離原單元。→ Task 6 旋轉測試。
4. **快取外擴 0 時換頁瞬間看到低解析預覽或空白**，在 E-Ink 上更明顯。→ Task 5。
5. **短文件（1～2 頁）與第一／最後一頁**：沒有鄰頁時間距公式不可出錯、掃描不可越界。→ Task 4（掃描涵蓋第 1 頁與最後一頁）。

## File Structure（全部在 spike 分支，且皆為新增檔案）

| 檔案 | 動作 | 責任 |
|---|---|---|
| `app/tool/spike/make_spike_pdf.js` | 新增 | 產生測試 PDF（細格線、邊框、對角線、頁碼；`a4`／`mixed` 兩種尺寸剖面） |
| `app/tool/spike/geometry_check.dart`（以 `flutter test` 執行） | 新增 | 純 Dart：算各視窗×頁面×Fit 模式所需的最小間距、各間距候選在 N 頁下的 Float32 ULP 表 |
| `app/lib/spike/spike_main.dart` | 新增 | 實驗入口（`flutter run -t`） |
| `app/lib/spike/pdf_geometry_spike.dart` | 新增 | 實驗畫面：可調間距／快取外擴／Fit 模式、單元瞬間切換、HUD、不變式掃描 |
| `docs/epics/epic-56-pdf-paginated-reading/spec.md` | 修改（docs 分支） | 幾何隔離段落補具體公式與設定 |
| `docs/epics/epic-56-pdf-paginated-reading/epic.md` | 修改（docs 分支） | 實驗記錄（裝置、頁數、觀察結果） |
| `docs/epics/epic-56-pdf-paginated-reading/issues.md`、`docs/epics.md` | 修改（docs 分支） | 狀態與進度 |

---

### Task 0：建立 spike 分支並確認真機

**Files：** 無檔案變更。

- [ ] **Step 1：確認從最新 `main` 開 spike 分支**

在 `C:\Users\fycdc\AI\elinkBook`（主 checkout）執行：

```bash
git switch main && git pull
git switch -c epic-56/issue-3-spike
```

Expected：分支建立成功，工作樹乾淨。

- [ ] **Step 2：【人類】確認用於實驗的真機並記錄規格**

```bash
adb devices
adb shell getprop ro.product.model
adb shell getprop ro.build.version.release
adb shell wm size
adb shell wm density
```

記下：裝置型號、Android 版本、解析度與 density。**若有 E-Ink 裝置，Task 5 與 Task 6 必須在 E-Ink 裝置上至少做一輪**（`spec.md` 問題 2 的目的就是 E-Ink 渲染成本）；手邊只有一般手機時，在 `epic.md` 註明「E-Ink 未測」。

- [ ] **Step 3：確認套件名稱（後續 `run-as` 用）**

```bash
adb shell "pm list packages | grep elinkbook"
```

Expected：`package:cc.ugotit.elinkbook`（專案 debug 建置無 `applicationIdSuffix`）。若不同，後續指令的套件名一律替換。

---

### Task 1：測試 PDF 產生器

**Files：**
- Create：`app/tool/spike/make_spike_pdf.js`

**Interfaces：**
- Produces：`node tool/spike/make_spike_pdf.js <輸出檔> <頁數> <a4|mixed>`，並支援 `--check <檔>` 驗證 xref 位移。

`mixed` 剖面的頁面尺寸（pt）依頁碼循環：1 A4 直式 595×842、2 A4 橫式 842×595、3 雙頁 spread 1190×842、4 小頁 300×420、5 寬扁 1200×300、6～9 A4 直式、**每 10 頁一張長頁 595×3000**。

- [ ] **Step 1：寫入產生器**

```js
// 產生 spike 用測試 PDF：每頁有 50pt 細格線（0.25pt）、1pt 邊框、對角線與大頁碼。
// 細格線與邊框用來在真機上肉眼判斷浮點對位誤差（邊緣模糊、平移抖動）。
// 只用 ASCII，字串長度即位元組長度，xref 位移直接取字串長度。
const fs = require('fs');

function pageContent(no, w, h) {
  const L = ['0.25 w 0.6 G'];
  for (let x = 50; x < w; x += 50) L.push(`${x} 0 m ${x} ${h} l S`);
  for (let y = 50; y < h; y += 50) L.push(`0 ${y} m ${w} ${y} l S`);
  L.push('1 w 0 G');
  L.push(`0.5 0.5 ${w - 1} ${h - 1} re S`); // 邊框
  L.push(`0 0 m ${w} ${h} l S`); // 對角線
  L.push(`${w} 0 m 0 ${h} l S`);
  const size = Math.floor(Math.min(w, h) / 3);
  L.push(`BT /F1 ${size} Tf ${Math.round(w / 2 - size * 0.9)} ${Math.round(h / 2 - size / 3)} Td (${no}) Tj ET`);
  return L.join('\n');
}

function sizeFor(profile, i) {
  if (profile === 'a4') return [595, 842];
  const n = i + 1; // 1-based 頁碼
  if (n % 10 === 0) return [595, 3000];
  switch (n % 10) {
    case 2: return [842, 595];
    case 3: return [1190, 842];
    case 4: return [300, 420];
    case 5: return [1200, 300];
    default: return [595, 842];
  }
}

function buildPdf(count, profile) {
  const objs = [];
  const kids = [];
  for (let i = 0; i < count; i++) kids.push(`${4 + 2 * i} 0 R`);
  objs[1] = '<< /Type /Catalog /Pages 2 0 R >>';
  objs[2] = `<< /Type /Pages /Kids [${kids.join(' ')}] /Count ${count} >>`;
  objs[3] = '<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica >>';
  for (let i = 0; i < count; i++) {
    const [w, h] = sizeFor(profile, i);
    const stream = pageContent(i + 1, w, h);
    objs[4 + 2 * i] = `<< /Type /Page /Parent 2 0 R /MediaBox [0 0 ${w} ${h}] /Resources << /Font << /F1 3 0 R >> >> /Contents ${5 + 2 * i} 0 R >>`;
    objs[5 + 2 * i] = `<< /Length ${stream.length} >>\nstream\n${stream}\nendstream`;
  }
  let out = '%PDF-1.4\n';
  const offsets = [];
  for (let id = 1; id < objs.length; id++) {
    offsets[id] = out.length;
    out += `${id} 0 obj\n${objs[id]}\nendobj\n`;
  }
  const xrefPos = out.length;
  out += `xref\n0 ${objs.length}\n0000000000 65535 f \n`;
  for (let id = 1; id < objs.length; id++) {
    out += `${String(offsets[id]).padStart(10, '0')} 00000 n \n`;
  }
  out += `trailer\n<< /Size ${objs.length} /Root 1 0 R >>\nstartxref\n${xrefPos}\n%%EOF\n`;
  return out;
}

// 驗證：xref 表每個位移處必須以「<id> 0 obj」開頭，startxref 指向 "xref"。
function check(file) {
  const s = fs.readFileSync(file, 'latin1');
  const sx = Number(/startxref\n(\d+)\n%%EOF/.exec(s)[1]);
  if (!s.startsWith('xref', sx)) throw new Error('startxref 未指向 xref');
  const lines = s.slice(sx).split('\n');
  const total = Number(lines[1].split(' ')[1]);
  for (let id = 1; id < total; id++) {
    const off = Number(lines[2 + id].slice(0, 10));
    if (!s.startsWith(`${id} 0 obj`, off)) throw new Error(`物件 ${id} 位移錯誤`);
  }
  console.log(`OK：${file}，物件數 ${total - 1}`);
}

const args = process.argv.slice(2);
if (args[0] === '--check') {
  check(args[1]);
} else {
  const [file, count, profile] = args;
  if (!file || !count || !['a4', 'mixed'].includes(profile)) {
    console.error('用法：node make_spike_pdf.js <輸出檔> <頁數> <a4|mixed>｜--check <檔>');
    process.exit(1);
  }
  fs.writeFileSync(file, buildPdf(Number(count), profile), 'latin1');
  check(file);
}
```

- [ ] **Step 2：產生三份測試檔並驗證**

在 `app/` 目錄下：

```bash
node -e "require('fs').mkdirSync('build/spike',{recursive:true})"
node tool/spike/make_spike_pdf.js build/spike/spike_a4_3000.pdf 3000 a4
node tool/spike/make_spike_pdf.js build/spike/spike_mixed_300.pdf 300 mixed
node tool/spike/make_spike_pdf.js build/spike/spike_a4_2.pdf 2 a4
```

Expected：三行 `OK：...`。`build/` 已被 gitignore。

- [ ] **Step 3：Commit**

```bash
git add app/tool/spike/make_spike_pdf.js
git commit -m "spike(epic-56): 新增 Issue 3 測試 PDF 產生器（細格線、混合尺寸）"
```

---

### Task 2：純 Dart 幾何與浮點精度計算

**Files：**
- Create：`app/tool/spike/geometry_check.dart`（以 `flutter test` 執行）

**Interfaces：**
- Consumes：`fitBaseScale`（`app/lib/reader/pdf_paginated_rules.dart`）、`PdfFitMode`（`pdf_fit_mode.dart`）。
- Produces：兩張表（所需間距表、Float32 ULP 表），結果貼進 `epic.md`。

- [ ] **Step 1：寫入計算腳本**

```dart
// ignore_for_file: avoid_print
// spike 用：在電腦上先算出「理論所需間距」與「大座標下 Float32 精度」，
// 真機實驗再驗證這些數字。因為引用 dart:ui（pdf_paginated_rules.dart），純 dart run 不可用，
// 包成 flutter test 執行（在 app/ 目錄）：flutter test tool/spike/geometry_check.dart
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' show Size;

import 'package:flutter_test/flutter_test.dart';

import 'package:elinkbook/reader/pdf_fit_mode.dart';
import 'package:elinkbook/reader/pdf_paginated_rules.dart';

/// Float32 在 [x] 附近的相鄰可表示值間距（ULP）。
double ulp32(double x) {
  final f = Float32List(1)..[0] = x.abs();
  final bits = Int32List.view(f.buffer);
  final a = f[0];
  bits[0] = bits[0] + 1;
  return f[0] - a;
}

/// 縮放後內容比可視範圍矮時被置中，可視矩形在縱向超出單元的最大量
/// （文件座標，單側）；縱向已溢出時可視矩形被鎖在單元內，超出量為 0。
double verticalOvershoot(PdfFitMode mode, Size page, Size view) {
  final base = fitBaseScale(mode: mode, contentSize: page, viewSize: view);
  return math.max(0.0, (view.height / base - page.height) / 2);
}

void main() {
  test('spike：印出幾何與精度表', () {
  const views = <String, Size>{
    '手機直立 360x800': Size(360, 800),
    '手機橫放 800x360': Size(800, 360),
    '平板直立 800x1280': Size(800, 1280),
    '摺疊內屏 600x700': Size(600, 700),
    '極長螢幕 360x1000': Size(360, 1000),
  };
  const pages = <String, Size>{
    'A4 直 595x842': Size(595, 842),
    'A4 橫 842x595': Size(842, 595),
    'spread 1190x842': Size(1190, 842),
    '小頁 300x420': Size(300, 420),
    '寬扁 1200x300': Size(1200, 300),
    '長頁 595x3000': Size(595, 3000),
  };
  print('=== 表 1：縱向超出量（文件座標 pt）。間距必須大於此值 ===');
  for (final mode in PdfFitMode.values) {
    print('\n[${mode.name}]');
    print('視窗 \\ 頁面'.padRight(22) + pages.keys.map((k) => k.padRight(18)).join());
    for (final v in views.entries) {
      final row = pages.values
          .map((p) => verticalOvershoot(mode, p, v.value).toStringAsFixed(0).padRight(18))
          .join();
      print(v.key.padRight(22) + row);
    }
  }

  print('\n=== 表 2：Float32 精度（平移量 ty ≈ y × 縮放，單位邏輯像素的 ULP）===');
  print('間距候選 × 頁數 → 最後一頁 y（pt）、在縮放 1／4／8 下 ty 的 ULP');
  for (final gap in <double>[0, 1000, 4000, 20000, 100000]) {
    for (final n in <int>[300, 3000, 10000]) {
      final y = n * (842 + gap);
      final u = [1.0, 4.0, 8.0]
          .map((z) => ulp32(y * z).toStringAsExponential(2))
          .join(' / ');
      print('gap=${gap.toStringAsFixed(0).padLeft(6)}  n=${n.toString().padLeft(5)}  '
          'y=${y.toStringAsExponential(2)}  ULP(z=1/4/8)=$u');
    }
  }
  print('\n判讀：ULP 接近或超過 0.1 邏輯像素，肉眼可能看到邊緣模糊或抖動。');
  });
}
```

- [ ] **Step 2：執行並確認可編譯**

在 `app/` 目錄：

```bash
flutter test tool/spike/geometry_check.dart
```

Expected：印出表 1（三種 Fit 模式各一張）與表 2（15 行），結尾 `All tests passed!`。（純 `dart run` 不可用：腳本引用 `dart:ui`，已包成 flutter test。撰寫計畫時已實際執行驗證過此腳本能跑。）

- [ ] **Step 3：把輸出存檔，供 Task 7 貼入 `epic.md`**

```bash
flutter test tool/spike/geometry_check.dart > build/spike/geometry_check.txt
```

- [ ] **Step 4：從輸出得出「間距公式候選」**

閱讀表 1：記下每種 Fit 模式在最壞組合（通常是寬扁頁或 spread 放進直立螢幕）的超出量。得出兩個候選，寫在 `build/spike/notes.md`（不進版控）：
- **候選 F（固定大值）**：取表 1 全部格子的最大值再加 10% 餘裕，作為單一固定間距。
- **候選 A（依視窗與頁面自動）**：相鄰兩單元的間距 ＝ `max(超出量(前一單元), 超出量(後一單元)) + 50`，超出量用 `verticalOvershoot` 即時以視窗尺寸計算。

兩者在 Task 4～6 都要上機比較。

**撰寫計畫時的試算（執行者以自己重跑的輸出為準）**：表 1 最大值約 1517 pt（寬扁頁 1200×300 放進 360×1000 螢幕），所以候選 F 約為 1700 pt；表 2 顯示 3000 頁、間距 0 時 `ty` 的 ULP 已是 0.25 邏輯像素（縮放 1），間距 1700 約 0.5、間距 4000 約 1、間距 20000 約 4。也就是說**固定大間距在數千頁下很可能肉眼可見地抖動**，而間距 0 的 ULP 正是現有連續捲動模式在同頁數下已承受的基準。因此 Task 6 判斷「可接受」時，以「不比連續捲動在同頁數的表現更差」為準，並重點比較候選 A（平均間距小很多）與候選 F。

- [ ] **Step 5：Commit**

```bash
git add app/tool/spike/geometry_check.dart
git commit -m "spike(epic-56): 新增 Issue 3 幾何與 Float32 精度計算腳本"
```

---

### Task 3：實驗畫面（HUD、可調參數、不變式掃描）

**Files：**
- Create：`app/lib/spike/spike_main.dart`
- Create：`app/lib/spike/pdf_geometry_spike.dart`

**Interfaces：**
- Consumes：`fitBaseScale`、`fitOrigin`（`pdf_paginated_rules.dart`）、`PdfFitMode`、`DualPageDirection.ltr`。
- Produces：`flutter run -t lib/spike/spike_main.dart --dart-define=SPIKE_DIR=<測試 PDF 所在目錄>` 啟動的實驗 App；三份測試檔在 App 內以晶片切換，**不必為換檔重啟或重新編譯**。

**實驗畫面的行為（驗收看這裡）：**
- 上方控制列：檔案（三份測試檔，點選即重載）、間距模式（`0`／`1000`／`4000`／`20000`／`自動`）、快取外擴（`0`／`1`）、Fit 模式（三種）、`◀`／`▶`（瞬間切到上／下一單元）、輸入頁碼＋「跳」、「連翻 20 頁」（每 400ms 一次，供量測記憶體）、「掃描」、「尺寸改變後主動回單元」開關（預設關，Task 6 Step 4 用）。
- HUD（半透明疊在畫面下方）：視窗尺寸（控制器讀到的與閉包讀到的）、目前單元、縮放、可視矩形、**可視矩形相交頁**、**快取矩形相交頁**、版面最大 y、`layoutPages` 被呼叫次數。可視矩形相交頁數 ＞ 1 時整排 HUD 變紅。
- 「掃描」：對第 1 頁、中間頁、倒數第二頁、最後一頁，在縮放＝基準與 2 倍基準兩種縮放下，把平移推到四個極端（用 ±1e9 讓 `normalizeMatrix` 夾到邊界），記錄可視矩形相交頁數的最大值；結果顯示在對話框並印到 `debugPrint`（`SPIKE-SWEEP` 前綴，方便 `adb logcat` 擷取）。

- [ ] **Step 1：入口**

```dart
// 實驗入口：flutter run -t lib/spike/spike_main.dart --dart-define=SPIKE_DIR=<測試 PDF 所在目錄>
// 此檔與整個 lib/spike/ 僅存在於 spike 分支，絕不進入 main。
import 'package:flutter/material.dart';

import 'pdf_geometry_spike.dart';

void main() {
  runApp(const MaterialApp(
    debugShowCheckedModeBanner: false,
    home: PdfGeometrySpike(),
  ));
}
```

- [ ] **Step 2：實驗畫面**

```dart
// ignore_for_file: avoid_print
import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:pdfrx/pdfrx.dart';

import '../reader/dual_page_direction.dart';
import '../reader/pdf_fit_mode.dart';
import '../reader/pdf_paginated_rules.dart';

const _spikeDir = String.fromEnvironment('SPIKE_DIR');

/// 三份測試檔（Task 1 產生）；在 App 內切換，免重啟。
const _spikeFiles = [
  'spike_mixed_300.pdf',
  'spike_a4_3000.pdf',
  'spike_a4_2.pdf',
];

/// 間距模式：固定值，或依視窗尺寸與頁面自動計算（候選 A）。
enum GapMode { g0, g1000, g4000, g20000, auto }

class PdfGeometrySpike extends StatefulWidget {
  const PdfGeometrySpike({super.key});

  @override
  State<PdfGeometrySpike> createState() => _PdfGeometrySpikeState();
}

class _PdfGeometrySpikeState extends State<PdfGeometrySpike> {
  final _controller = PdfViewerController();
  final _pageField = TextEditingController();
  String _currentFile = _spikeFiles.first;
  bool _recenterOnResize = false; // Task 6 Step 4 的試驗開關，預設關
  GapMode _gapMode = GapMode.g4000;
  double _cacheExtent = 1.0;
  PdfFitMode _fitMode = PdfFitMode.pageFit;
  int _unit = 1; // 目前單元（1-based 頁碼）
  int _layoutCalls = 0;
  Size? _capturedViewSize; // 外層 LayoutBuilder 記下的尺寸，供 layoutPages 閉包讀取
  Timer? _flipTimer;
  bool _ready = false;

  @override
  void initState() {
    super.initState();
    _controller.addListener(() {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _flipTimer?.cancel();
    _pageField.dispose();
    super.dispose();
  }

  // ── 幾何 ────────────────────────────────────────────────

  double _base(Size content, Size view) =>
      fitBaseScale(mode: _fitMode, contentSize: content, viewSize: view);

  /// 縱向超出量（與 geometry_check.dart 同一公式）。
  double _overshoot(Size page, Size view) {
    final base = _base(page, view);
    return math.max(0.0, (view.height / base - page.height) / 2);
  }

  double _gapBetween(PdfPage a, PdfPage b, Size view) {
    switch (_gapMode) {
      case GapMode.g0:
        return 0;
      case GapMode.g1000:
        return 1000;
      case GapMode.g4000:
        return 4000;
      case GapMode.g20000:
        return 20000;
      case GapMode.auto:
        final oa = _overshoot(Size(a.width, a.height), view);
        final ob = _overshoot(Size(b.width, b.height), view);
        return math.max(oa, ob) + 50;
    }
  }

  PdfPageLayout _layoutPages(List<PdfPage> pages, PdfViewerParams params) {
    _layoutCalls++;
    final view = _capturedViewSize ?? const Size(400, 800);
    final maxW = pages.map((p) => p.width).reduce(math.max);
    final rects = <Rect>[];
    var y = 0.0;
    for (var i = 0; i < pages.length; i++) {
      final p = pages[i];
      rects.add(Rect.fromLTWH((maxW - p.width) / 2, y, p.width, p.height));
      y += p.height;
      if (i + 1 < pages.length) y += _gapBetween(p, pages[i + 1], view);
    }
    return PdfPageLayout(pageLayouts: rects, documentSize: Size(maxW, y));
  }

  /// 平移鎖在目前單元內；縮放不得小於該單元的基準；比可視範圍小的維度置中。
  Matrix4 _normalize(
      Matrix4 m, Size view, PdfPageLayout layout, PdfViewerController? c) {
    final r = layout.pageLayouts[(_unit - 1).clamp(0, layout.pageLayouts.length - 1)];
    final base = _base(r.size, view);
    final z = math.max(m.getMaxScaleOnAxis(), base);
    var tx = m.storage[12];
    var ty = m.storage[13];
    final w = r.width * z;
    final h = r.height * z;
    if (w <= view.width) {
      tx = (view.width - w) / 2 - r.left * z;
    } else {
      tx = tx.clamp(view.width - r.right * z, -r.left * z).toDouble();
    }
    if (h <= view.height) {
      ty = (view.height - h) / 2 - r.top * z;
    } else {
      ty = ty.clamp(view.height - r.bottom * z, -r.top * z).toDouble();
    }
    return Matrix4(z, 0, 0, 0, 0, z, 0, 0, 0, 0, 1, 0, tx, ty, 0, 1);
  }

  /// 瞬間切到第 [n] 單元頂端、基準縮放（絕對跳轉語意）。
  void _gotoUnit(int n) {
    if (!_controller.isReady) return;
    final count = _controller.pageCount;
    _unit = n.clamp(1, count);
    final view = _controller.viewSize;
    final r = _controller.layout.pageLayouts[_unit - 1];
    final base = _base(r.size, view);
    final o = fitOrigin(
      contentSize: r.size,
      scale: base,
      viewSize: view,
      direction: DualPageDirection.ltr,
    );
    _controller.value = Matrix4(base, 0, 0, 0, 0, base, 0, 0, 0, 0, 1, 0,
        o.dx - r.left * base, o.dy - r.top * base, 0, 1);
    setState(() {});
  }

  // ── 觀測 ────────────────────────────────────────────────

  List<int> _pagesIntersecting(Rect rect) {
    if (!_controller.isReady) return const [];
    final rects = _controller.layout.pageLayouts;
    final hit = <int>[];
    for (var i = 0; i < rects.length; i++) {
      if (rects[i].overlaps(rect)) hit.add(i + 1);
    }
    return hit;
  }

  Rect get _cacheRect {
    final v = _controller.visibleRect;
    return Rect.fromLTRB(
      v.left - v.width * _cacheExtent,
      v.top - v.height * _cacheExtent,
      v.right + v.width * _cacheExtent,
      v.bottom + v.height * _cacheExtent,
    );
  }

  /// 不變式掃描：四個代表單元 × 兩種縮放 × 四個平移極端，回報可視矩形相交頁數的最大值。
  Future<void> _sweep() async {
    if (!_controller.isReady) return;
    final count = _controller.pageCount;
    // 必須涵蓋 mixed 剖面一個完整週期的所有尺寸（1 直式、2 橫式、3 spread、4 小頁、
    // 5 寬扁、10 長頁），否則超出量最大的寬扁頁不會被掃到，固定間距會「假通過」。
    final units = {
      1, 2, 3, 4, 5, 10,
      (count / 2).ceil(),
      math.max(1, count - 1),
      count,
    }.where((u) => u <= count).toList()
      ..sort();
    var worst = 0;
    final bad = <String>[];
    for (final u in units) {
      _gotoUnit(u);
      final view = _controller.viewSize;
      final r = _controller.layout.pageLayouts[u - 1];
      final base = _base(r.size, view);
      for (final z in [base, base * 2]) {
        for (final dx in [-1e9, 1e9]) {
          for (final dy in [-1e9, 1e9]) {
            _controller.value =
                Matrix4(z, 0, 0, 0, 0, z, 0, 0, 0, 0, 1, 0, dx, dy, 0, 1);
            final hit = _pagesIntersecting(_controller.visibleRect);
            if (hit.length > worst) worst = hit.length;
            if (hit.length > 1) {
              bad.add('單元$u z=${z.toStringAsFixed(3)} 相交=$hit');
            }
          }
        }
      }
    }
    final summary =
        '間距=${_gapMode.name} fit=${_fitMode.name} 視窗=${_controller.viewSize} '
        '最大相交頁數=$worst（1 為合格）\n${bad.take(8).join('\n')}';
    debugPrint('SPIKE-SWEEP $summary');
    _gotoUnit(_unit);
    if (!mounted) return;
    await showDialog<void>(
      context: context,
      builder: (_) => AlertDialog(content: Text(summary)),
    );
  }

  void _toggleFlip20() {
    if (_flipTimer != null) {
      _flipTimer!.cancel();
      setState(() => _flipTimer = null);
      return;
    }
    var n = 0;
    _flipTimer = Timer.periodic(const Duration(milliseconds: 400), (t) {
      _gotoUnit(_unit + 1);
      if (++n >= 20) {
        t.cancel();
        if (mounted) setState(() => _flipTimer = null);
      }
    });
    setState(() {});
  }

  // ── UI ──────────────────────────────────────────────────

  Widget _chips<T>(String label, List<T> values, T current, void Function(T) on,
      String Function(T) name) {
    return Wrap(spacing: 4, crossAxisAlignment: WrapCrossAlignment.center, children: [
      Text(label, style: const TextStyle(fontSize: 11)),
      for (final v in values)
        ChoiceChip(
          label: Text(name(v), style: const TextStyle(fontSize: 11)),
          visualDensity: VisualDensity.compact,
          selected: v == current,
          onSelected: (_) => setState(() {
            on(v);
            _ready = false;
          }),
        ),
    ]);
  }

  @override
  Widget build(BuildContext context) {
    if (_spikeDir.isEmpty) {
      return const Scaffold(
          body: Center(child: Text('請以 --dart-define=SPIKE_DIR=<目錄> 啟動')));
    }
    final ready = _controller.isReady;
    final visible = ready ? _pagesIntersecting(_controller.visibleRect) : const <int>[];
    final cached = ready ? _pagesIntersecting(_cacheRect) : const <int>[];
    final violated = visible.length > 1;
    return Scaffold(
      body: SafeArea(
        child: Column(children: [
          Padding(
            padding: const EdgeInsets.all(4),
            child: Column(children: [
              _chips<String>('檔案', _spikeFiles, _currentFile,
                  (v) {
                _currentFile = v;
                _unit = 1;
              }, (v) => v.replaceAll('spike_', '').replaceAll('.pdf', '')),
              _chips<GapMode>('間距', GapMode.values, _gapMode, (v) => _gapMode = v,
                  (v) => v.name.replaceFirst('g', '')),
              _chips<double>('快取外擴', const [0, 1], _cacheExtent,
                  (v) => _cacheExtent = v, (v) => v.toStringAsFixed(0)),
              _chips<bool>('尺寸改變後主動回單元', const [false, true], _recenterOnResize,
                  (v) => _recenterOnResize = v, (v) => v ? '開' : '關'),
              _chips<PdfFitMode>('Fit', PdfFitMode.values, _fitMode,
                  (v) => _fitMode = v, (v) => v.name),
              Row(children: [
                IconButton(onPressed: () => _gotoUnit(_unit - 1), icon: const Icon(Icons.chevron_left)),
                IconButton(onPressed: () => _gotoUnit(_unit + 1), icon: const Icon(Icons.chevron_right)),
                SizedBox(
                  width: 70,
                  child: TextField(
                    controller: _pageField,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(hintText: '頁碼', isDense: true),
                  ),
                ),
                TextButton(
                    onPressed: () => _gotoUnit(int.tryParse(_pageField.text) ?? _unit),
                    child: const Text('跳')),
                TextButton(onPressed: _toggleFlip20, child: Text(_flipTimer == null ? '連翻20頁' : '停止')),
                TextButton(onPressed: _sweep, child: const Text('掃描')),
              ]),
            ]),
          ),
          Expanded(
            child: LayoutBuilder(builder: (context, constraints) {
              // 與 PdfViewer 內部 LayoutBuilder 同一個盒子，layoutPages 閉包讀這個尺寸。
              _capturedViewSize = constraints.biggest;
              return Stack(children: [
                PdfViewer.file(
                  '$_spikeDir/$_currentFile',
                  key: ValueKey('$_currentFile-$_gapMode-$_cacheExtent-$_fitMode'),
                  controller: _controller,
                  params: PdfViewerParams(
                    margin: 0,
                    layoutPages: _layoutPages,
                    normalizeMatrix: _normalize,
                    horizontalCacheExtent: _cacheExtent,
                    verticalCacheExtent: _cacheExtent,
                    // Task 6 Step 4 的試驗：視窗尺寸改變後主動回到目前單元。
                    // pdfrx 文件明言此回呼可能在 build 期間被呼叫，不可同步改矩陣或 setState，
                    // 一律排到該幀之後。
                    onViewSizeChanged: (viewSize, oldViewSize, c) {
                      if (!_recenterOnResize) return;
                      WidgetsBinding.instance.addPostFrameCallback((_) {
                        if (mounted) _gotoUnit(_unit);
                      });
                    },
                    onViewerReady: (doc, c) {
                      if (!_ready) {
                        _ready = true;
                        WidgetsBinding.instance
                            .addPostFrameCallback((_) => _gotoUnit(_unit));
                      }
                    },
                  ),
                ),
                if (ready)
                  Positioned(
                    left: 0,
                    right: 0,
                    bottom: 0,
                    child: IgnorePointer(
                      child: Container(
                        color: (violated ? Colors.red : Colors.black).withValues(alpha: 0.7),
                        padding: const EdgeInsets.all(6),
                        child: Text(
                          '視窗(控制器)=${_controller.viewSize}  視窗(閉包)=$_capturedViewSize\n'
                          '單元=$_unit/${_controller.pageCount}  縮放=${_controller.currentZoom.toStringAsFixed(3)}\n'
                          '可視矩形=${_controller.visibleRect}\n'
                          '可視相交頁=$visible  快取相交頁=$cached\n'
                          '版面最大y=${_controller.layout.documentSize.height.toStringAsFixed(0)}  '
                          'layoutPages 呼叫=$_layoutCalls',
                          style: const TextStyle(color: Colors.white, fontSize: 10),
                        ),
                      ),
                    ),
                  ),
              ]);
            }),
          ),
        ]),
      ),
    );
  }
}
```

- [ ] **Step 3：編譯並修正 API 差異**

這是 spike，API 名稱以實際 `pdfrx` 2.4.7 為準；若有編譯錯誤（例如 `isReady`、`currentZoom`、`withValues` 的名稱），依錯誤訊息就地修正，修正不得改變上述行為。

```bash
cd app
flutter analyze lib/spike
```

Expected：`No issues found!`（`ignore_for_file` 已壓掉 `avoid_print`）。若 `flutter analyze` 對 `lib/spike` 以外的檔案報錯，表示動到產品檔案，立即停止並回報。

- [ ] **Step 4：Commit**

```bash
git add app/lib/spike
git commit -m "spike(epic-56): 新增 Issue 3 幾何實驗畫面（HUD、間距／快取外擴可調、不變式掃描）"
```

---

### Task 4：【人類】問題 1——可視矩形不變式需要多大間距

**Files：** 無檔案變更；產出為 Task 7 要貼入 `epic.md` 的表格。

- [ ] **Step 1：把測試 PDF 送進真機並啟動實驗 App**

以下指令在 PowerShell 與 Git Bash 都可用（含 `|` 的 Android 端指令整串用雙引號，交給裝置上的 shell 執行）。在 `app/` 目錄、以 debug 建置（`run-as` 只對 debug 建置有效）：

```bash
adb push build/spike/spike_a4_3000.pdf /data/local/tmp/
adb push build/spike/spike_mixed_300.pdf /data/local/tmp/
adb push build/spike/spike_a4_2.pdf /data/local/tmp/
flutter run -t lib/spike/spike_main.dart -d <裝置ID> --dart-define=SPIKE_DIR=/data/user/0/cc.ugotit.elinkbook/files
```

第一次安裝完成後，另開終端機把檔案複製進 App 私有目錄：

```bash
adb shell "run-as cc.ugotit.elinkbook mkdir -p files"
adb shell "run-as cc.ugotit.elinkbook cp /data/local/tmp/spike_a4_3000.pdf files/"
adb shell "run-as cc.ugotit.elinkbook cp /data/local/tmp/spike_mixed_300.pdf files/"
adb shell "run-as cc.ugotit.elinkbook cp /data/local/tmp/spike_a4_2.pdf files/"
```

**若 `cp` 報 `Permission denied`**（Android 10+ 的 SELinux 可能禁止 App 讀 `/data/local/tmp`；部分精簡系統也沒有 `cp`），改推到 App 專屬外存目錄，並用該目錄當 `SPIKE_DIR` 重新執行 `flutter run`：

```bash
adb push build/spike/spike_a4_3000.pdf /sdcard/Android/data/cc.ugotit.elinkbook/files/
adb push build/spike/spike_mixed_300.pdf /sdcard/Android/data/cc.ugotit.elinkbook/files/
adb push build/spike/spike_a4_2.pdf /sdcard/Android/data/cc.ugotit.elinkbook/files/
flutter run -t lib/spike/spike_main.dart -d <裝置ID> --dart-define=SPIKE_DIR=/storage/emulated/0/Android/data/cc.ugotit.elinkbook/files
```

（不要用 PowerShell 的 `cat file | adb shell ...` 傳二進位檔：管線會把位元組當文字處理而損毀。）

啟動後按 `R`（大寫）熱重啟。Expected：畫面出現控制列（檔案、間距、快取外擴、Fit 晶片）、PDF 第 1 頁（整頁置中）與 HUD。**之後換測試檔一律點「檔案」晶片切換，不必重啟。** 若顯示「請以 --dart-define=SPIKE_DIR=…」表示目錄未帶入；若畫面空白，確認 `SPIKE_DIR` 下確有該檔。

- [ ] **Step 2：【人類】用混合尺寸文件掃描各間距**

載入 `spike_mixed_300.pdf`。對下列組合各按一次「掃描」並記錄對話框的「最大相交頁數」：

- 間距：`0`、`1000`、`4000`、`20000`、`自動`（5 種）
- Fit：`pageFit`、`fitWidth`、`actualSize`（3 種）
- 螢幕方向：直立、橫放（2 種）

共 30 格。每格記錄：最大相交頁數（1 為合格）、若不合格列出的單元與頁碼。同時留存日誌：PowerShell 用 `adb logcat -s flutter | Select-String SPIKE-SWEEP`，Git Bash 用 `adb logcat -s flutter | grep SPIKE-SWEEP`（本機端過濾；若要在裝置端過濾則 `adb shell "logcat -s flutter | grep SPIKE-SWEEP"`）。

- [ ] **Step 3：【人類】對照電腦計算**

把 Task 2 的表 1 與本步的實測並排，確認：實測不合格的格子，是否都落在表 1「超出量 ＞ 間距」的位置（例如寬扁頁放進直立螢幕）。若實測與計算矛盾（計算說合格、實測不合格，或相反），把矛盾的格子單獨記下，這代表 `layoutPages`／`normalizeMatrix` 的實際行為與推導不同，必須在 `epic.md` 說明。

- [ ] **Step 4：【人類】邊界文件**

點「檔案」晶片切到 `a4_2`（2 頁）與只有第 1 頁／最後一頁的情形：對 `自動` 間距與 `4000` 各按一次「掃描」。Expected：不崩潰、最大相交頁數 1；記錄結果。

- [ ] **Step 5：決定問題 1 的結論**

依 Step 2 的 30 格結果，**由人類選擇**（AI 只整理選項，不替人決定）：

- 若 `自動` 全部合格而固定值有不合格 → 結論「間距依視窗與頁面計算：`max(超出量(前), 超出量(後)) + 50`」。
- 若某個固定值在 30 格全部合格 → 結論「固定間距＝該值」，並在 Task 6 對照 Float32 後再定。
- 兩者皆可 → 以 Task 6 的浮點結果決定（間距越小，座標越小，精度越好）。

---

### Task 5：【人類】問題 2——快取外擴 0 對比預設

**Files：** 無檔案變更。

- [ ] **Step 1：【人類】量測基準記憶體（外擴 1）**

點「檔案」晶片切到 `a4_3000`，間距**一律選 `自動`**（固定大間距如 4000 會把鄰頁推到快取矩形之外，外擴 1 形同無效，比較會得出「外擴沒有價值」的誤導結論），快取外擴選 `1`，Fit 選 `pageFit`。**先守衛**：跳到第 100 頁，確認 HUD「快取相交頁」包含鄰頁（例如 `[99,100,101]`）、「可視相交頁」只有 `[100]`；若快取相交頁只有 `[100]`，表示間距超過快取上限，此組比較無效，停止並回報（見下方 Step 5 的間距上限）。守衛通過後，App 停在第 1 頁時：

```bash
adb shell "dumpsys meminfo cc.ugotit.elinkbook | grep -E 'Graphics|Native Heap|TOTAL PSS'"
```

記錄三個數字。按「連翻 20 頁」等它跑完（約 8 秒），再量一次。

- [ ] **Step 2：【人類】同樣流程，快取外擴 0**

切換為 `0`（畫面會重載文件，間距仍為 `自動`），重複 Step 1 的兩次量測。兩組之間**只能有快取外擴不同**，其他條件（檔案、間距、Fit、起始頁、螢幕方向）完全相同。

- [ ] **Step 3：【人類】換頁觀感（慢動作錄影）**

用 `adb shell screenrecord --time-limit 15 /sdcard/spike_cache1.mp4` 錄影，錄影期間連點 `▶` 10 次（每次間隔約 1 秒）；改外擴 0 再錄 `/sdcard/spike_cache0.mp4`。`adb pull` 取回後逐格播放，記錄：換頁後「目標頁完整清晰」需要幾格（以錄影幀率換算毫秒）、期間是否出現空白或低解析預覽。**E-Ink 裝置另用肉眼記錄**「換頁後是否先看到模糊再變清晰」「殘影程度」。若無法逐格播放，至少用肉眼分級（無／輕微／明顯）。

- [ ] **Step 4：【人類】HUD 佐證**

在外擴 `1`（間距 `自動`）時於第 100 頁，HUD 的「快取相交頁」應包含鄰頁（例如 `[99,100,101]`）而「可視相交頁」只有 `[100]`（Step 1 的守衛已確認一次，這裡留存截圖）；外擴 `0` 時兩者相同。這同時佐證「外擴不影響可見性」。另外，**刻意再做一組對照**：間距 `4000`、外擴 `1`，確認快取相交頁退化為只有 `[100]`，記下這個事實（固定大間距與預渲染互斥）。

- [ ] **Step 5：決定問題 2 的結論**

**由人類選擇**：
- 若外擴 1 的記憶體增量可接受（寫下數字），且外擴 0 換頁出現可感知的空白／低解析 → 結論「保留預設外擴 1，間距須落在可視矩形之外、快取矩形之內」；
- 若外擴 1 在 E-Ink 上記憶體或渲染成本明顯過高，且外擴 0 的換頁延遲可接受 → 結論「外擴 0」；
- 其他情況 → 寫下數字，由人類裁示。

注意：若選「外擴 1」，間距還須滿足「**鄰頁落在快取矩形之內**」才能被預渲染。幾何推導（置中、縮放＝基準時）：可視高在文件座標為 `H = 視窗高 ÷ 基準`，單元上下各有超出量 `o = (H − 單元高) ÷ 2`；快取矩形底端 ＝ 單元底端 ＋ `o` ＋ `H × 外擴`；下一單元頂端 ＝ 單元底端 ＋ 間距。故鄰頁被預渲染的條件為 **間距 ＜ o ＋ H × 外擴**，與不變式要求的 **間距 ＞ o** 合起來，間距必須落在 **（o，o ＋ H × 外擴）** 之間。例：A4 直式在 360×800 螢幕，o ≈ 240、H ≈ 1322，外擴 1 時間距上限 ≈ 1562 pt。這與固定大間距（4000、20000）互斥，只有依視窗自動計算（o ＋ 50）能同時滿足。Step 5 的結論須同時給出間距上限，並以 HUD 實測校對上述公式。

---

### Task 6：【人類】問題 3——大座標浮點精度與視窗尺寸改變

**Files：** 無檔案變更。

- [ ] **Step 1：【人類】在 3000 頁文件上看細格線**

載入 `spike_a4_3000.pdf`，Fit＝`actualSize`（縮放 1，最容易看出邊緣對位），依序用「跳」到第 `1`、`1500`、`3000` 頁。每個位置：
1. 拖曳平移，觀察 50pt 細格線與邊框是否抖動、閃爍或粗細不均；
2. 雙指放大到約 4 倍，再觀察一次；
3. 用 HUD 記下「版面最大y」與該頁的可視矩形數值。

分別用間距 `4000`、`20000`、`自動` 各做一輪（`0` 不必，已知會失敗）。記錄分級：無／輕微／明顯，並說明現象（模糊、跳動、位置偏移）。

- [ ] **Step 2：【人類】與 Task 2 表 2 對照**

把各組合的觀察分級與表 2 的 ULP 數字並排。得出「在哪個 `y × 縮放` 量級開始肉眼可見」，寫成一句結論，例如「`ty` 超過 X 時 ULP 約 Y 邏輯像素開始可見」。若全部都「無」，寫明「在 3000 頁、間距 Z 下未見」，並注意這**不代表**一萬頁安全——Task 2 的表 2 仍要保留供參。

- [ ] **Step 3：【人類】旋轉／視窗尺寸改變**

在 `spike_mixed_300.pdf`、間距 `自動`、Fit＝`pageFit` 下：

1. 在第 3 頁（spread 尺寸頁）直立 → 旋轉為橫放 → 再旋轉回直立；
2. 在第 50 頁重複；
3. 若有摺疊裝置，開合一次。

每次旋轉後記錄：HUD「視窗(控制器)」與「視窗(閉包)」是否一致；`layoutPages 呼叫` 增加多少；單元是否仍是原頁；可視相交頁是否為 1（紅色 HUD 表示不合格）；再按一次「掃描」是否合格。**若「視窗(閉包)」比「視窗(控制器)」晚一輪**（暫時不一致），記下持續多久、是否需要元件主動觸發重算。

- [ ] **Step 4：【人類】主動觸發重算的必要性**

若 Step 3 出現舊尺寸造成的不合格，試驗最小補救：把控制列的「尺寸改變後主動回單元」晶片切到「開」（實驗畫面已內建，於 `onViewSizeChanged` 以 `addPostFrameCallback` 排到該幀之後才呼叫 `_gotoUnit`；pdfrx 文件明言此回呼可能在 build 期間被呼叫，同步改矩陣或 `setState` 會拋例外），再旋轉一次，確認是否排除。**這只用來回答「是否需要由元件主動觸發」，不要保留為產品設計**；把結果記下。

- [ ] **Step 5：決定問題 3 的結論**

**由人類確認**以下三點（各有證據才算）：
1. 大座標精度：可接受的最大 `y × 縮放` 量級，或「單一固定間距在 N 頁下是否可用」；
2. 視窗尺寸改變時 `layoutPages` 是否會用新尺寸重算（Step 3）；
3. 是否需要元件主動觸發（Step 4）。

---

### Task 7：把結論寫回文件並發 docs PR

**Files：**
- Modify：`docs/epics/epic-56-pdf-paginated-reading/spec.md`（第 111～118 行「幾何隔離」）
- Modify：`docs/epics/epic-56-pdf-paginated-reading/epic.md`（開發記錄）
- Modify：`docs/epics/epic-56-pdf-paginated-reading/issues.md`（Issue 3 狀態、後續 Issue 的依賴說明如需）
- Modify：`docs/epics.md`（第 57 列進度）

- [ ] **Step 1：從 `main` 開 docs 分支（不要從 spike 分支開）**

```bash
git switch main
git switch -c epic-56/issue-3-spike-results
```

spike 分支保留在本機（記下最後 commit SHA 供 `epic.md` 引用），**不推到遠端、不發 PR**；若使用者希望留存可另行推送，但絕不合併。

- [ ] **Step 2：改寫 `spec.md`「幾何隔離」段落**

把第 117 行（「具體間距公式…決定後把結論與公式補回本檔案。」）整段換成由實測結論填寫的具體內容，格式如下（`〔 〕`內由 Task 4～6 的人類結論填入，**不得留空或保留佔位符**；若某題無結論，改寫成「未決：原因」並回報給使用者，不可帶著佔位符合併）：

```markdown
- **間距公式（Issue 3 spike 實測決定）**：〔固定 N pt ／ 相鄰單元間距＝max(縱向超出量(前), 縱向超出量(後)) + 50，其中縱向超出量＝max(0, (可視高 ÷ 基準縮放 − 單元高) ÷ 2)〕。實測依據：〔30 格掃描結果摘要，最壞組合與間距〕。
- **快取外擴**：〔保留預設 1.0 ／ 設為 0〕。實測依據：〔記憶體差、換頁觀感、E-Ink 觀察〕。〔若保留 1.0：間距上限＝…〕
- **座標精度**：〔在 3000 頁、間距 … 下未見／於 … 以上開始可見；結論〕。Matrix4 為 Float32 儲存，`ty ≈ y × 縮放`。
- **視窗尺寸改變**：`pdfrx` 每次 `LayoutBuilder` 重建都會重新呼叫 `layoutPages`，但閉包拿不到 `viewSize`，元件需自行以外層 `LayoutBuilder` 記下尺寸。〔是否需要主動觸發：…〕
```

並把本檔「Further Notes」中「③ 逐頁幾何與瞬間換頁（含 spike…）」的 spike 描述同步更正為「spike 已完成（Issue 3）」。

- [ ] **Step 3：寫入 `epic.md` 實驗記錄**

在「開發記錄」最後加一節，含：實驗日期；裝置（型號、Android 版本、解析度、是否 E-Ink）；測試檔（`spike_a4_3000.pdf` 3000 頁 A4、`spike_mixed_300.pdf` 300 頁混合、`spike_a4_2.pdf`）與產生指令；`geometry_check` 的可行執行指令與表 1、表 2 全文（來自 `build/spike/geometry_check.txt`）；Task 4 的 30 格結果表、Task 5 的記憶體與換頁觀感表、Task 6 的精度與旋轉觀察；三個問題的結論；spike 分支名稱與最後 commit SHA。**標【人類】的觀察值只貼人類提供的數字，沒測的格子寫「未測」。**

- [ ] **Step 4：更新 `issues.md` 與 `docs/epics.md`**

（修改 `docs/epics.md` 時先讀第 57 列既有內容，維持表格欄位數與 `|` 分隔格式，只改最後一欄進度文字。）

`issues.md` Issue 3 的 `**Status:**` 改為 `done（PR #<待發 PR 後填>）`——**先寫 `in-review`，PR 合併後再改 `done（PR #N）`**，與 Issue 1、2 的慣例一致。`docs/epics.md` 第 57 列進度改為「Issue 1、2 已合併；Issue 3 spike 完成、待合併」。

- [ ] **Step 5：【人類】確認 `spec.md` 修訂內容**

把 Step 2 的改寫內容給使用者看，確認三個結論無誤、沒有留佔位符，再提交。

- [ ] **Step 6：Commit、推送、發 PR**

```bash
git add docs/epics/epic-56-pdf-paginated-reading docs/epics.md
git commit -m "docs(epic-56): Issue 3 幾何 spike 結論補回 spec.md，並記錄實驗"
git push -u origin epic-56/issue-3-spike-results
```

PR 以 Gitea API 建立（token 讀自 `C:\Users\fycdc\.gitea_token`，不得顯示明文）；標題「docs(epic-56): Issue 3 幾何隔離與快取外擴 spike 結論」，內文說明：無產品程式碼、實驗程式碼留在未合併的 spike 分支、列出三個問題的結論。PR 描述不加署名行。

- [ ] **Step 7：合併後更新進度**

PR 合併後切回 `main`、`pull`，把 `issues.md` Issue 3 改為 `done（PR #N）`、`epic.md` 記錄合併 commit，`docs/epics.md` 第 57 列改為「Issue 1～3 已合併」，另開一個小 docs commit。Issue 4 的計畫可在此之後撰寫，並以 `spec.md` 的新結論為依據。

---

## 自我審查記錄

- **Spec／工單覆蓋**：問題 1（Task 2＋4）、問題 2（Task 5）、問題 3 的精度（Task 2＋6）與尺寸改變（Task 6）皆有對應；驗收「`spec.md` 由待決定變具體公式」＝Task 7 Step 2；`epic.md` 實驗記錄（裝置、頁數、觀察）＝Task 7 Step 3。
- **審查修訂（review-plan-issue-3.md）**：C-1（掃描取樣補齊 mixed 剖面全部尺寸）、I-1（Task 5 一律用自動間距、加守衛與正確的間距上限公式）、I-2（App 內切換測試檔）、I-3（`onViewSizeChanged` 非同步）、I-4／M-1／M-2／M-3（指令引號、外存替代路徑、跨平台建目錄、看板格式）已全數處理。
- **佔位符**：Task 7 Step 2 的 `〔 〕` 是**執行時由人類結論填入**的欄位，已在該步驟明文要求不得帶佔位符合併；其餘步驟皆有實際程式碼或指令。
- **型別一致**：`GapMode`、`_gotoUnit`、`_normalize`、`_pagesIntersecting`、`_sweep` 在 Task 3 內自洽；`verticalOvershoot` 與 `_overshoot` 公式相同（已於兩處註明）。
- **風險**：Task 3 的程式碼未在撰寫計畫時編譯（spike，pdfrx 部分 API 名稱如 `isReady`／`currentZoom` 以實際為準），Step 3 已要求依編譯結果就地修正；Task 2 的 `dart:ui` 在純 `dart run` 下可能不可用，已附 `flutter test` 替代作法。
