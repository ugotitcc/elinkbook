# dict_reader 1.6.1 本地修補（elinkBook Issue 6a）

上游：https://github.com/mumu-lhl/dict_reader，MIT，版本 1.6.1。
本目錄是上游 `lib/` 的直接副本，只修改 `lib/src/dict_reader_base.dart` 的鍵索引：
(1) 鍵改為依區塊延遲載入（降低記憶體）、(2) 鍵的比對集中到 `_normKey`（套用
`KeyCaseSensitive`／`StripKey` 規則）。兩者是同一份鍵索引改寫的兩面，以下合併說明；
其餘程式碼逐字未改。

## 修補：鍵改為依區塊延遲載入

**問題：** 上游 `initDict()` 會把整份鍵索引讀進記憶體（`_keyList` 為
`(recordOffset, key)` 清單，另加一份排序後的 `_lookupKeyIndices`）。鍵的
常駐記憶體與筆數成正比。E-Ink 實機（Allwinner WAVE、armeabi-v7a）量測：

| 字典 | 筆數 | 上游版本查詢後穩態增量 |
|---|---|---|
| 教育部重編國語辭典（真實 CJK、UTF-16） | 163,085 | 45.8–47.6 MB |
| 合成 CJK、UTF-16 | 400,000 | **70.0–70.9 MB** |

驗收 25 要求「開啟 100 MB MDX 的記憶體增量小於 50 MB」，40 萬筆的情境
超出了門檻，且兩個 reader 同時開啟時會再翻倍。

**做法：**

- `_readKeys()` 改為 `_readKeyBlocks()`：只讀鍵區塊資訊（每塊的 head／tail
  與壓縮、解壓大小），不讀鍵區塊本身。
- 新增 `_KeyBlockInfo`（head、tail、壓縮大小、解壓大小、檔案位移）與
  `_keyBlockCache`（LRU，最多 8 塊）。
- `locate`／`locateAll`／`search`／`exist` 以二分搜尋找區塊，再解壓單一
  區塊後在區塊內二分／線性搜尋；`search` 與 `exist` 是同步 API，改用
  `RandomAccessFile` 的同步方法讀取（單一區塊，數十 KB）。
- `readWithOffset()` 等串流 API 以 `_KeyBlockCursor` 依序載入區塊，不再
  依賴完整鍵清單。
- `exportCache`／`importCache` 需要完整鍵清單，改為丟 `UnsupportedError`；
  elinkBook 沒有使用這兩個 API。

**鍵的比對（`_normKey`）：** 查詢字串與檔內的每一把鍵都先經過同一個正規化再比：

- `StripKey=Yes`：去掉空白、標點（Unicode `P` 類別）與全形空白。真實製作工具在
  這個旗標下，檔內存的鍵仍是原字串（例如 `a la carte`、`a-bomb`），但排序與比對
  以去除後的形式為準。若只對查詢字串去除、檔內鍵不處理（上一版與上游的行為），
  含空白或連字號的片語會永遠查不到（`strip-phrases.mdx` 測試重現過）。
- `KeyCaseSensitive=No`：折疊成小寫。真實字典（例如教育部辭典）的鍵在檔內以小寫
  排序，查 `Apple` 時若仍用大小寫敏感比對，會在同一個鍵區塊裡找不到 `apple`。

elinkBook 的 `MdxReader` 仍會先套用同一規則處理查詢字串（重複套用不影響結果），
但**不得**在 `meta.keyCaseSensitive == true` 時做去重（見 Issue 6a 審查 I-3）。

**仍然保留的排序假設（精確版）：**

- 區塊之間：檔內的鍵區塊依「正規化後的鍵」遞增排列，所以用各區塊 `tail` 的
  正規化值做二分搜尋找第一塊。這是 MDict 製作工具的共同慣例。
- 區塊內：**不**假設順序，一律線性掃描（一塊最多數千把鍵），因此區塊內的排序
  細節（例如同一個正規化鍵的大小寫變體交錯）不影響結果。
- 區塊邊界：查詢鍵不大於第一塊的 `head` 時，連前一塊一起掃；掃完後若該塊的
  `tail` 不大於查詢鍵就繼續下一塊（重複鍵跨塊）。
- 若某個字典的區塊之間也不是依正規化鍵排序，區塊二分搜尋仍可能漏掉；
  這類檔案目前沒有遇過，遇到時要改成逐塊掃描 head／tail。
- `search()`（前綴搜尋）在區塊內仍用二分搜尋，elinkBook 沒有使用；若要使用，
  需先確認區塊內順序。
- 對同一把鍵回傳相同記錄；重複鍵（同一詞多筆）全部回傳。

**記憶體與延遲（E-Ink 實機補測，Allwinner WAVE、armeabi-v7a、Android 12）：**

| 字典 | 筆數 | 上游穩態增量 | 修補後穩態增量 | 修補後 p50／p95 |
|---|---|---|---|---|
| 教育部重編國語辭典 | 163,085 | 45.8–47.6 MB | **37.7–38.8 MB** | 15.8–16.0／30.8–31.3 ms |
| 合成 CJK、UTF-16 | 400,000 | 70.0–70.9 MB | **39.1–42.0 MB** | 16.4–16.8／30.2–31.6 ms |

兩本都降到門檻 50 MB 以下。代價是每次查詢要多解壓一個鍵區塊，
p95 從約 3–4 ms 升到約 31 ms（仍在可接受範圍；查詢是使用者按下搜尋後才發生）。
穩態數字包含 500 次隨機查詢讓記錄區塊快取長大的量（快取上限 32 MB）。
原始 JSON：`.scratch/mdx_spike/report/wave_eink/6a_patched_*.json`（不進版控）。
桌面預檢（Windows）：40 萬筆檔案開啟 +1.2 MB、500 次查詢加 200 次讀內文後
穩態 +43.6 MB。

**驗證：** `app/test/dictionary/mdx_reader_test.dart`（含多區塊 fixture `multi-block.mdx`
與片語 fixture `strip-phrases.mdx`）、
`mdx_dictionary_provider_test.dart`、`mdx_importer_test.dart` 涵蓋
（含真實檔案 `tmp/dictionary/教育部重編國語辭典.mdx`，檔案存在時才跑）。
記憶體補測數據見 `docs/research/dictionary/DICTIONARY_FORMATS_AND_LICENSES.md`
「Issue 6a 補測」。

## 升級步驟

1. 以新版本覆蓋 `lib/`、`pubspec.yaml`、`LICENSE`。
2. 重新套用本文件描述的修補（`dict_reader_base.dart`）。
3. 執行 `flutter test test/dictionary` 與 E-Ink 記憶體量測。
