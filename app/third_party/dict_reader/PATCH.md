# dict_reader 1.6.1 本地修補（elinkBook Issue 6a）

上游：https://github.com/mumu-lhl/dict_reader，MIT，版本 1.6.1。
本目錄是上游 `lib/` 的直接副本，只套用下列一項修補；其餘程式碼逐字未改。

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

**行為不變：** 對同一把鍵回傳相同記錄；重複鍵（同一詞多筆）全部回傳。
鍵的比較改為透過 `_compareKeys`、`_keysEqual`、`_keyStartsWith`：
檔頭 `KeyCaseSensitive=No` 時以 `toLowerCase()` 比對，否則用
`String.compareTo`。這是必要的：真實字典（例如教育部辭典）的鍵在檔內
以小寫排序，查 `Apple` 時若仍用大小寫敏感比對，會在同一個鍵區塊裡找不到
`apple`。elinkBook 的 `MdxReader` 仍會先折疊查詢字串（重複折疊不影響結果），
但**不得**在 `meta.keyCaseSensitive == true` 時做去重（見 Issue 6a 審查 I-3）。
鍵區塊在檔內本來就依字典排序排列，因此區塊二分搜尋與原本「全量排序後
二分搜尋」在合法檔案上結果一致。

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

**驗證：** `app/test/dictionary/mdx_reader_test.dart`、
`mdx_dictionary_provider_test.dart`、`mdx_importer_test.dart` 涵蓋
（含真實檔案 `tmp/dictionary/教育部重編國語辭典.mdx`，檔案存在時才跑）。
記憶體補測數據見 `docs/research/dictionary/DICTIONARY_FORMATS_AND_LICENSES.md`
「Issue 6a 補測」。

## 升級步驟

1. 以新版本覆蓋 `lib/`、`pubspec.yaml`、`LICENSE`。
2. 重新套用本文件描述的修補（`dict_reader_base.dart`）。
3. 執行 `flutter test test/dictionary` 與 E-Ink 記憶體量測。
