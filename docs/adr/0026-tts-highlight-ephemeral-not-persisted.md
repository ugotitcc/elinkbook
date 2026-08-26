# ADR 0026：TTS 朗讀高亮採暫態 UI 狀態，不寫入 highlights/notes 資料表

## 狀態

已採納

## 背景

語音朗讀（TTS）功能規劃中（`epic-34-tts-readalong`，源自 `docs/research/tts_integration_architecture_research.md`／`docs/research/pdf_tts_integration_architecture_research.md` 兩份架構研究報告），朗讀進行中需要在畫面上即時高亮目前朗讀的文字段落（FR-46／FR-47）。

現有 `highlights`／`notes` 資料表（`app/lib/reader/highlight.dart`）是使用者手動建立、需要被查詢／管理／刪除的**持久化標記**：Foliate 格式（EPUB／KF8／TXT／MD）用 CFI 定位，PDF 用 `pdfPageIndex`＋`pdfRect`（`PercentRect`，單一矩形）定位，對應的是使用者「長按拖曳框選」這個既有互動。若直接重用這套模型儲存 TTS 播放中的高亮，會把兩個不同語意的東西混在一起：

- 使用者既有的「刪除該書所有劃線」一鍵批次操作，可能誤刪播放中的 TTS 高亮痕跡。
- TTS 高亮隨播放進度每幾百毫秒到數秒變動一次，若寫入資料庫會造成大量無意義的寫入與同步負載（`SyncEngine` 會把它當成真實使用者標記推送/合併）。
- PDF TTS 高亮需要逐行多矩形描邊一段可能跨行的文字，不符合 `PercentRect` 單一矩形的既有語意。

## 決策

TTS 朗讀高亮一律以**暫態 UI 狀態**實作，不寫入 `highlights`／`notes` 資料表，不參與同步：

- **Foliate 格式**：透過既有 `overlayer.js` 的 `Overlayer.add()`/`remove()`（`main.js` 既有 `view.addAnnotation()` pipeline）疊加，使用獨立 annotation key（例如 `"tts-current"`），與劃線/備註使用的 key 空間分開。
- **PDF**：透過既有 `pageOverlaysBuilder` hook（`pdf_reader_view.dart`）疊加一組逐行矩形（`CustomPaint`/`Positioned`），不落地任何資料表。

兩種座標系統（CFI／頁碼＋文字座標）雖然不同，但「暫態、不持久化」這個邊界原則一致，不需要因座標系不同而做出不同的持久化決策。

## 後果

- TTS 高亮不會出現在使用者的劃線/備註清單、統一側邊欄，也不受「刪除該書所有劃線/備註」等既有批次操作影響。
- 若日後需要「朗讀時使用者手動加註記」這類功能，需要另外設計一個明確的「使用者主動確認才轉存為持久化標記」步驟，不能假設 TTS 播放過程本身會留下持久化紀錄。
- App 意外中止（Crash／被系統殺掉）不會遺失任何資料，因為本來就沒有寫入——但也代表朗讀進度需要另外由 `TtsTimeline`／播放器自身的暫停位置狀態管理，不能依賴 highlights 表做為朗讀進度的還原依據。

## 曾考慮的替代方案

- **重用 `Highlight`/`PercentRect` 模型，額外加一個 `isTemporary`/`source` 欄位區分**：會混淆既有查詢/刪除/同步邏輯「`highlights` 表內容全部是使用者永久資料」的既有假設，且 PDF 端需要多矩形而非單一矩形，改動既有 schema 的風險與複雜度皆高於直接分離兩套機制，予以排除。
