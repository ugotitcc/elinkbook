# ADR 0023：格式擴充統一走 Foliate 管線，TXT 路線正式改弦更張（`epic-11-multi-format-reader`）

## 狀態

已採納

## 背景

`docs/prd.md` FR-01 現行僅列 ePub3/PDF/TXT 為 P0 格式；`epic-11-txt-engine`（Backlog，尚未開始 Discovery）原案是為 TXT 打造一套獨立的「自訂輕量直排 CJK 排版引擎」，`CLAUDE.md` 明文排除 WebView/Readium 路線，理由是「純文字沒有 HTML/CSS 那層需要重新實作」。

2026-08-16 引入外部研究報告《elinkBook 全格式閱讀擴充綜合研究報告》（`docs/research/comprehensive_format_expansion_research.md`），評估將支援格式擴充至 KF8(AZW3)、CBZ、TXT、MD（MOBI／FB2 經 `/grill-with-docs` 討論後排除於本次範圍，因繁中市場流通度低）。報告核心論點：TXT／MD 皆可預處理後併入既有 `readest/foliate-js`（釘定 commit）管線，復用已被 `epic-17-epub-render-migration`／`epic-20-fxl-foliate-migration` 兩輪 Epic 打磨成熟的直排／避頭尾／CFI／劃線／書籤／目錄機制，而非重造一套獨立的排版與定位系統。

`/grill-with-docs`（`/grilling` + `/domain-modeling`）逐項確認：(1) PRD 需先修訂納入新格式（P1）；(2) 沿用 `epic-11` 編號，slug 改為 `epic-11-multi-format-reader`；(3) 格式範圍收斂為 KF8/CBZ/TXT/MD；(4) **TXT 技術路線改採 Foliate 管線，正式推翻 `epic-11` 原案**——此即本 ADR 的核心決策；(5) Readium 完全退場不併入本次範圍。

## 決策

1. **TXT 全面改走 Foliate（WebView）管線，`epic-11-txt-engine` 的「自訂輕量直排引擎」原案正式作廢**。理由：`epic-11` 尚未開始 Discovery，改弦更張成本最低；MD 本來就必須走 Foliate（HTML 衍生格式無回頭路），TXT 若維持獨立引擎會讓兩個高度相似的「純文字類」格式各自維護一套完全不同的渲染/定位/劃線程式碼。
2. **`FoliateEpubReaderView` 泛化重構為 `FoliateReaderView`**，服務全部經 Foliate 管線渲染的格式（EPUB／KF8／CBZ／TXT／MD，統稱「Foliate 格式」，見 `CONTEXT.md`）。`CLAUDE.md` 架構描述於 `epic-11-multi-format-reader` Architecting 階段一併更新。
3. **TXT／MD 於匯入時落地轉換為合成 EPUB／XHTML 相容結構**（「合成書籍結構」，衍生檔案存於 App 私有目錄，`Book.filePath` 改指向合成檔案），比照既有 `coverPath` 衍生檔案慣例。原始檔案僅匯入當下讀取一次。
4. **`Book.isFixedLayout` 欄位語意由「EPUB 專屬」廣義化為跨格式通用旗標**：EPUB／KF8 依書本 metadata 判斷、CBZ 恆為 `true`（無流式變體）、TXT／MD 合成後恆為 `false`（合成結構本質流式）、PDF 維持 `null`（不適用）。CBZ 直接復用既有 `isFixedLayout=true` 分派路徑與 `FxlSettingsSheet`，不新增平行欄位。
5. **新格式的 metadata／封面擷取一律純 Dart 實作**（`archive`＋`xml`＋自建 Big5 對照表），不引入原生 platform channel 依賴（例如 `charset_converter`）。理由：保留未來 `epic-13-ios` 移植彈性，且與現有純 Dart 分派邏輯一致。
6. **KF8 新增 DRM 偵測**：解析 PDB／EXTH 標頭加密旗標，偵測到即回傳友善錯誤訊息，不嘗試解密（呼應「不支援解 DRM」既有產品定位）。
7. **CBZ 復用既有 `FxlSettingsSheet` 並擴充**，不另建獨立漫畫設定面板；不支援劃線/備註（比照既有 FXL 圖像無文字節點的既定限制）。
8. **Readium 完全退場（`BookMetadataChannel.kt` 遷移純 Dart）不併入本次範圍**，另立獨立技術債 Epic。
9. **MOBI／FB2 排除於本次範圍**，列為未來獨立 Backlog（不開 Issue）。

## 曾考慮的替代方案

- **維持 `epic-11` 原案，TXT 用自訂輕量排版引擎，MD 另開一條路線**：會讓「純文字」與「輕量標記文字」兩個高度相似格式各自維護一套排版/定位/劃線系統，長期維護成本更高，予以排除。
- **CBZ 另建獨立 `isComic` 欄位＋獨立設定面板**：需要新欄位又要維護兩條與 `isFixedLayout`／`FxlSettingsSheet` 平行的判斷邏輯，不算真正復用既有分派路徑，予以排除。
- **TXT/MD 開書時即時轉換（不落地存檔）**：省磁碟空間，但大檔案每次開書都要重跑一次 Isolate 轉換，且需另外處理「原始檔案異動後是否重新轉換」的邊界情況；落地轉檔可直接復用 `coverPath` 既有慣例、且原始檔案事後被外部修改的機率低，予以排除。
- **沿用 `charset_converter` 等原生套件做編碼偵測**：省去自建 Big5 對照表，但引入原生 platform channel 依賴，与專案「純 Dart 跨平台」既有原則（`pdfrx` FFI／`foliate-js` WebView 皆不依賴額外原生解析套件）不一致，且對 `epic-13-ios` 移植不利，予以排除。
- **本次一併完成 Readium 退場（`BookMetadataChannel.kt` 遷移純 Dart）**：與新格式上線這條關鍵路徑無必要關聯（新格式反正無從選擇，Readium 完全不支援），併入只會擴大範圍、拖慢交付，予以排除，另立獨立 Epic。

## 後果

- `docs/prd.md` FR-01 及相關 FR 需修訂，新增 KF8/CBZ/MD（P1），Success Criteria 不對 CBZ 套用「零排版缺陷」硬指標。
- `docs/epics.md` 的 `epic-11-txt-engine` 條目需重新命名為 `epic-11-multi-format-reader`，範圍描述同步更新。
- `app/lib/reader/foliate_epub_reader_view.dart`／class 名稱於 `epic-11-multi-format-reader` Architecting 階段泛化重構，`CLAUDE.md`「`ReaderScreen`」架構小節同步更新。
- `Book.isFixedLayout` 欄位註解（`app/lib/library/models/book.dart:41-50`）需更新，移除「PDF/TXT 恆為 null」中「TXT」的部分（TXT 合成後改為 `false`），並新增 CBZ／KF8 語意說明。
- 需查證並 vendor 額外的 `foliate-js` 資產（目前僅 `epub.js`/`view.js`/`paginator.js`/`fixed-layout.js` 等已 vendor）：CBZ 需要 `comic-book.js`；KF8 解析所需的確切檔案（`mobi.js`/`fflate.js` 或其他）留待 Architecting 階段對照 upstream `readest/foliate-js` 釘定 commit 實際檔案結構查證。
- `pubspec.yaml` 需新增 `archive`（由 dev_dependencies 升為正式 dependencies）與 `xml` 依賴；不新增任何原生 platform channel 套件。
- 既有 `epic-11-txt-engine` 在 `docs/epics.md` 的敘述文字（「自訂輕量排版引擎，後續評估 Rust/C++ 共用核心」）作廢，需更新。

## 相關佐證

- `docs/research/comprehensive_format_expansion_research.md`（外部研究報告，本次決策的技術輸入）
- `docs/adr/0011-epub-reflowable-migrate-to-foliate-js.md`／`0017-fxl-migrate-to-foliate-js.md`（Foliate 管線既有成熟度的先例佐證）
- `CLAUDE.md`「TXT：自訂的輕量直排 CJK 排版引擎」段落（本 ADR 推翻的原始決策文字，因原決策無獨立 ADR，僅存在於 `CLAUDE.md`/`docs/epics.md` 敘述文字，故無 `superseded by` 可標記，僅在此文字說明取代關係）
- `app/lib/library/models/book.dart`（`isFixedLayout` 欄位現行語意）
- `CONTEXT.md`「固定版面（Fixed-Layout, FXL）」／「Foliate 格式」／「合成書籍結構」詞條
