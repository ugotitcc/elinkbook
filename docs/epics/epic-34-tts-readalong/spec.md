# TTS 語音朗讀與同步高亮（Read-along）——規格文件（Spec）

**狀態：** 待人類審閱
**對應工單：** `epic-34-tts-readalong`
**依據：** `docs/epics/epic-34-tts-readalong/design.md`（Discovery 決策，含審查修訂）、`docs/adr/0026-tts-highlight-ephemeral-not-persisted.md`、`docs/research/tts_integration_architecture_research.md`（Foliate 篇）、`docs/research/pdf_tts_integration_architecture_research.md`（PDF 篇）
**測試縫隙（已與人類確認）：** 主要縫隙為 `ReaderScreen` widget test（比照現有劃線/備註/複製/PDF 搜尋的既有測試慣例）；`TtsProvider`／`TtsTimeline`／`TtsCacheManager` 為純 Dart 單元測試縫隙；`audio_service` 前景通知、App 背景 WebView JS 節流、真實音訊輸出時間為真機專屬縫隙（`app/integration_test/`）。

自本文件起，成為 `epic-34-tts-readalong` 核心介面/型別的唯一事實來源；後續 Scrum Master 階段（`issues.md`）與各 Issue 實作計畫須以本文件為準，若與 `design.md`／兩份研究報告的敘述有出入，以本文件為準。

---

## Problem Statement

elinkBook 使用者目前只能用眼睛閱讀。以下情境沒有被滿足：

- 通勤、做家事、運動等雙眼無法看螢幕的時段，想「聽」完一本正在讀的書，而不是被迫暫停閱讀進度。
- 長時間盯著螢幕（尤其 E-Ink 裝置對比度較低）導致眼睛疲勞，想改用耳朵休息一下但不中斷閱讀進度。
- 視力不佳或有閱讀障礙的使用者，需要語音輔助才能順暢消化文字內容。
- 使用者想「邊聽邊看」，讓畫面自動跟著朗讀進度移動，不用自己找剛剛念到哪裡。
- 在沒有網路的環境（例如許多 E-Ink 裝置沒有內建 Google Play 服務、或單純沒有行動網路），仍希望語音朗讀可以離線運作。

## Solution

為 elinkBook 加入語音朗讀（TTS）與朗讀同步高亮（Read-along）功能，分四個 Phase 漸進交付：

- **Phase 1**：EPUB／KF8／TXT／MD（統稱 Foliate 格式）支援系統原生語音朗讀，畫面即時以句級精度高亮朗讀中的文字，支援背景播放、通知欄與鎖定畫面控制、耳機線控。
- **Phase 2**：加入雲端 API 語音（使用者自備 Key）與朗讀語音離線快取，避免重複生成相同內容。
- **Phase 3（stretch goal）**：加入 100% 離線的端側神經語音引擎，供無網路環境使用。
- **Phase 4**：PDF 支援語音朗讀，播放/背景播放體驗與 Foliate 格式一致，高亮改用頁碼＋頁內文字座標定位。

TTS 朗讀高亮全程是暫態 UI 狀態（見 ADR 0026），不與使用者手動建立的劃線/書籤混淆；不修改任何 vendored `foliate-js` 原始碼，全部透過既有 `Overlayer`／`pageOverlaysBuilder` 基礎設施疊加。

## User Stories

### 基本播放控制（Phase 1）

1. 作為讀者，我想要點一個按鈕開始朗讀目前書籍，這樣我就不用自己找到「從哪裡開始念」。
2. 作為讀者，我想要暫停/繼續朗讀，這樣我臨時被打斷時不會漏掉內容。
3. 作為讀者，我想要跳到上一句/下一句，這樣我可以重聽剛剛沒聽清楚的句子，或跳過已經聽懂的內容。
4. 作為讀者，我想要調整朗讀語速，這樣我可以依自己習慣的速度聽書。
5. 作為讀者，我想在朗讀畫面看到一個精簡的迷你控制列（Mini Player），這樣不用離開閱讀畫面就能操作播放。

### 背景播放與系統整合（Phase 1）

6. 作為讀者，我想要把 App 切到背景或鎖定螢幕後朗讀繼續進行，這樣我可以邊聽邊做其他事。
7. 作為讀者，我想要在通知欄看到目前朗讀狀態與播放/暫停按鈕，這樣不用打開 App 就能控制。
8. 作為讀者，我想要在鎖定畫面直接控制播放，這樣手機放口袋也能操作。
9. 作為讀者，我想要用藍牙耳機或有線耳機的線控按鈕控制播放/暫停，這樣不用拿出手機。
10. 作為讀者，我想要耳機拔出時朗讀自動暫停，這樣不會在公共場合突然外放。

### 同步高亮（Phase 1）

11. 作為讀者，我想要畫面即時高亮目前正在朗讀的句子，這樣可以邊聽邊看、不會找不到進度。
12. 作為直排繁體中文讀者，我想要朗讀高亮在直排模式下也正確跟隨文字位置，這樣直排書籍朗讀體驗跟橫排一樣好。
13. 作為 E-Ink 裝置使用者，我想要朗讀高亮用靜態對比顯示、不要有漸變動畫，這樣螢幕不會因為頻繁刷新而產生殘影。
14. 作為 E-Ink 裝置使用者，我想要只有在高亮超出目前可視範圍時才觸發翻頁/捲動，這樣不會因為逐句捲動而讓螢幕一直刷新。

### 手動介入（Phase 1）

15. 作為讀者，我想要在朗讀中手動翻頁或捲動畫面時，播放自動暫停，這樣我瀏覽其他內容時不會有音訊在旁邊持續念不相關的段落。
16. 作為讀者，我想要在手動瀏覽後按下播放，朗讀從我現在看到的位置開始念，這樣不會被拉回舊的、我已經不在看的地方。

### 語音來源與自訂（Phase 2）

17. 作為讀者，我想要在系統原生語音之外，設定自己的雲端語音服務（例如自備 API Key），這樣可以用音質更好的語音朗讀。
18. 作為讀者，我想要已經朗讀過的內容不用等待重新生成，這樣重聽或快轉時不會卡頓。
19. 作為讀者，我想要離線也能聽已經快取過的內容，這樣沒有網路時仍可以繼續聽之前聽過的書。
20. 作為讀者，我想要能快轉到任意章節朗讀，這樣不用照順序從頭聽起。

### 端側離線語音（Phase 3，stretch goal）

21. 作為沒有穩定網路、又想要離線高品質語音的讀者，我想要有一個完全離線的神經網路語音選項，這樣不依賴雲端也能聽到自然的語音。

### PDF 朗讀（Phase 4）

22. 作為 PDF 讀者，我想要 PDF 也能語音朗讀，體驗跟 EPUB 朗讀一致（背景播放、鎖定畫面控制等），這樣不會因為格式不同而少一種功能。
23. 作為 PDF 讀者，我想要朗讀進行到不同頁時畫面自動翻到對應頁，這樣不用自己手動翻頁跟上進度。
24. 作為排版複雜（多欄/表格）PDF 的讀者，我想要在朗讀開始前知道這份 PDF 排版可能導致朗讀順序不完全正確，這樣我不會誤以為朗讀功能壞掉。

### 邊界與例外情境

25. 作為簡繁轉換使用者，我想要朗讀念出來的文字跟畫面顯示的繁簡版本一致，這樣耳朵聽到的跟眼睛看到的不會對不上。
26. 作為閱讀含注音標記書籍的讀者，我想要朗讀只念正文、跳過注音標記本身，這樣不會聽到重複或多餘的發音。
27. 作為 CBZ（純圖像漫畫）讀者，我想要清楚知道這個格式不支援朗讀（沒有文字可以念），這樣不會誤以為功能故障。
28. 作為讀者，我想要 App 從背景切回前景時，畫面高亮立刻跟上實際的朗讀進度，這樣不會有畫面卡在舊位置、音訊卻已經念到很後面的落差感。

## Implementation Decisions

### 模組劃分

- **`TtsProvider`（抽象介面）**：代表一種語音來源。三種實作對應 Phase 1～3：系統原生（呼叫 Android `TextToSpeech`）、雲端 API（OpenAI-compatible，使用者自備 Key/URL）、端側神經語音（Sherpa-ONNX + Kokoro-zh，Phase 3）。核心契約（沿用兩份研究報告的領域模型，此處僅摘錄決策相關欄位）：

  ```dart
  abstract class TtsProvider {
    Future<List<TtsVoice>> getAvailableVoices();
    Future<TtsSynthesisResult> synthesize(String text, {required TtsVoice voice, double speed, double pitch});
  }
  class TtsSynthesisResult {
    final String audioFilePath; // 所有 Provider 皆回傳檔案路徑，見下方「音訊管線」決策
    final List<TtsWordTiming> wordTimings;
    final Duration totalDuration;
  }
  ```

  **音訊管線統一為檔案合成**：所有 Provider（含系統原生）一律先合成為暫存音訊檔（Android 端 `TextToSpeech` 對應套件的檔案合成 API，而非直接輸出到喇叭的即時朗讀 API），再交給統一的 Dart 端音訊播放器播放。三個 Phase 因此共用同一套播放器／`TtsTimeline`／背景播放控制管線，不存在「部分 Provider 走檔案、部分不走」的分歧。合成延遲是否落在可接受範圍，須在對應 Issue 實作前以實測數據驗證。

  **暫存檔生命週期（`TtsController` 契約）**：Phase 1（`TtsCacheManager` 尚未存在）採固定命名空間、以目前朗讀段索引覆寫（不逐段累積新檔案），避免跳句/跳章時在暫存目錄留下孤立檔案；清理時機綁定 `TtsController` 生命週期——`dispose()`、切換書籍、播放自然結束皆須清除目前暫存檔。Phase 2 起改由 `TtsCacheManager` 依快取 Key 管理生命週期，不再是「單一暫存檔覆寫」模式。

  **語速調整的生效時機（契約澄清）**：`synthesize()` 的 `speed` 參數只決定「下一段尚未合成的朗讀段」用什麼語速合成；使用者在播放中調整語速時，**目前正在播放的段落**改用播放器的執行期變速（不重新合成、不中斷播放），只有後續段落才會用新的 `speed` 值呼叫 `synthesize()`。兩者不可混用同一套機制，否則會出現「調速後要等目前句念完才生效」的延遲體感。

- **`TtsController`**：朗讀狀態機的核心協調者。持有目前 Provider、播放狀態（播放中/暫停/停止）、目前朗讀段。訂閱既有 `FoliateReaderView`／`PdfReaderView` 已經在發出的位置變化事件（例如 EPUB 端既有的 relocate 類事件、PDF 端既有的頁面變化 callback），用來偵測「使用者手動導覽」並觸發自動暫停（User Story 15）；也監聽 App 生命週期事件，在從背景恢復前景時，主動重新送出目前播放位置對應的高亮/翻頁指令給畫面層（User Story 28，對應 `review-design.md` Important #3）。

  **Audio Focus 中斷處理（`review-spec.md` Important #3）**：`audio_service` 底層處理 Android MediaSession，但「收到系統音訊焦點變更事件後要怎麼反應」是應用層政策，須由 `TtsController` 明確定義：
  - **暫時失去焦點**（`AUDIOFOCUS_LOSS_TRANSIENT`，例如來電、導航語音、系統通知音）：暫停播放；焦點恢復（`AUDIOFOCUS_GAIN`）時自動恢復播放，不需要使用者手動介入。
  - **永久失去焦點**（`AUDIOFOCUS_LOSS`，例如使用者開啟其他音樂/Podcast App 佔用喇叭）：暫停播放並釋放音訊硬體佔用，**不**自動恢復，等同使用者手動暫停——避免兩個 App 搶著自動恢復播放互相打斷。

- **`TtsTimeline`**：管理「音訊播放位置 → 朗讀段」的正向查找（沿用既有 Provider 篇二分搜尋設計），**新增**「畫面目前位置 → 朗讀段」的反向查找介面（`lookupSegmentByCfi`／PDF 端 `lookupSegmentByPage`），供 User Story 16「從畫面新位置繼續朗讀」使用（對應審查 Important #2）。

- **朗讀段擷取**：
  - Foliate 格式：章節載入時一次性建立「句子 → CFI」對照表（`TreeWalker` 掃過章節純文字，過濾 `<rt>` 注音節點，對每句呼叫既有 `epubcfi.js` 的 `CFI.fromRange()`）。
  - PDF：對目前頁呼叫既有 `pdfrx.loadStructuredText()`，切句後產生「頁碼＋文字範圍」定位（延遲擷取，僅在使用者實際朗讀到/預先載入該頁時才呼叫，避免拖慢開書速度）。

- **高亮渲染（不新建平行機制，重用既有基礎設施，見 ADR 0026）**：
  - Foliate 格式：透過既有 `Overlayer.add()`/`remove()`（`view.addAnnotation()` pipeline）疊加，使用獨立的 annotation key（與劃線/備註的 key 空間分開），不寫入任何資料表。
  - PDF：透過既有 `pageOverlaysBuilder` hook 疊加一組逐行矩形（取自 `PdfPageText.charRects.boundingRect()`／`PdfRect.toRectInDocument()`），同樣不寫入任何資料表；雙頁模式下自動獲得「座標歸屬單一頁面」的既有正確性保證，不需額外處理。

- **`TtsCacheManager`（Phase 2）**：以「書籍 → 章節/頁 → 朗讀段」為分塊粒度的音訊快取，音訊檔與時間戳原子綁定（一份音訊對應一份時間戳資料）。Cache Key 由文字內容＋語音設定（Provider/語速/音調）共同決定，設定變更視為快取失效。**新增一張 SQLite 資料表**追蹤快取中繼資料（書籍/段落識別、檔案路徑、最後存取時間），供 LRU 淘汰使用；淘汰上限與觸發時機（例如「書籍刪除」或「使用者手動清除快取」）於對應 Issue 落地時定案。此表與現有 `highlights`/`notes`/`bookmarks` 表完全獨立，不共用 schema。

- **`PdfPageTextCache`（Phase 4）**：比照既有 `PdfThumbnailCache<T>` 的純 Dart LRU 快取 pattern，快取 `loadStructuredText()` 結果，避免重複 FFI 呼叫拖慢效能（呼應 PDF 100MB+ 開啟 <2 秒的既有 NFR）。

- **`ReaderScreen` 整合**：比照 `highlightsRepository`/`notesRepository` 既有的可選（nullable）建構參數模式，新增可選的 TTS 相關依賴注入參數（例如 Provider 工廠、快取管理器），未提供時 TTS 功能不啟用，不影響現有畫面行為；Widget test 可選擇性省略以維持既有測試不受影響。Mini Player 為新增的畫面元件，掛載於既有 Reader 底部工具列體系（比照既有 FAB／底部工具列的疊加方式），須與既有底部導覽列/目錄側邊欄的顯示/隱藏連動，避免互相遮擋——具體堆疊層級（Z-index）與版面調整由對應 Issue 的實作計畫決定，本規格不預先鎖定視覺細節。

- **PDF 多欄/複雜版面偵測**：簡單啟發式（例如同一頁文字 bounding box 在 x 軸方向的分布是否呈現明顯雙峰群聚），偵測到疑似多欄時於朗讀開始前提示使用者「此 PDF 排版較複雜，朗讀順序可能不完全正確」（User Story 24）。不追求版面重排序，準確度未經驗證，需以真實 PDF 樣本校準（避免對單欄 PDF 誤報）。

- **簡繁轉換聯動**：TTS 從既有 `TreeWalker` 抽取 DOM 文字朗讀；若簡繁轉換（FR-48，獨立 Epic）是不改動 DOM 的純顯示層轉換，兩者自動一致，不需要額外串接（User Story 25）。此為待驗證假設，須在簡繁轉換功能實際設計時確認其實作方式；若該功能改動 DOM，則需要在 `TtsController` 補上朗讀文字來源的選擇邏輯。

- **Android 平台整合（`audio_service`）**：背景播放依專案實際 targetSdk 觸發的 manifest 宣告（前景服務型別 `mediaPlayback`、對應權限、Android 13 起的通知執行期權限）須於 Phase 0 相依性驗證 Issue 中盤點並落實；三個候選套件（`flutter_tts`／`audio_service`／`sherpa_onnx`）已查證 minSdk 皆為 21，不影響專案現有 `minSdk=24`／Android 11 (API 30) 政策門檻。

### Phase 0 前置技術驗證（非使用者功能，實作前置條件）

Phase 1 開工前，須先完成一次獨立的套件相依性驗證（`audio_service`/`just_audio`（或等效音訊播放套件）與現有 `flutter_inappwebview`/`pdfrx`/`sqflite` 相依鏈相容性），因專案 `pubspec.yaml` 已有 `share_plus`/`file_picker`/`package_info_plus`/`win32` 版本鏈衝突的先例。此驗證結果直接影響 Phase 1 各 Issue 是否能順利開工，不屬於使用者可見功能，但列為 Phase 1 的硬性前置依賴。

## Testing Decisions

**好測試的判斷標準**：只驗證外部可觀察行為（畫面狀態、bridge 呼叫參數、Repository 讀寫結果），不斷言內部私有實作細節（例如不斷言 `TtsController` 內部私有欄位、不斷言 JS 檔案的私有函式呼叫次序）。既有專案測試慣例（`reader_screen_test.dart` 對劃線/複製/PDF 搜尋的測試方式）已充分示範這個原則，TTS 測試延續同一套風格。

**測試縫隙分工**（已於 Discovery 後段與人類確認，見上方「測試縫隙」段落）：

1. **`ReaderScreen` widget test（主要縫隙）**：驗證播放/暫停/上一句/下一句、Mini Player UI 狀態、高亮跟隨（斷言 fake `FoliateReaderView`/`PdfReaderView` 收到的高亮指令參數）、手動導覽觸發自動暫停、恢復播放從新位置開始、App 生命週期切換時的重新同步指令。比照 `reader_screen_test.dart` 既有的 fake callback 注入模式（例如既有的 `onSelectionChanged`/`onCopyPressed` 測試寫法）。
2. **純 Dart 單元測試**：
   - `TtsProvider` 各實作：用假的底層 API（比照專案既有 Fake Repository 慣例）驗證 `synthesize()` 回傳結構正確，不需要真的呼叫系統 TTS。
   - `TtsTimeline`：驗證正向（時間→段落）與新增的反向（位置→段落）查找在邊界情況（段落交界、超出範圍）下的正確性。
   - **朗讀段擷取（`review-spec.md` Important #2）**：句子跨多個 DOM 節點（例如 `這是<em>重要</em>觀念。`，或含 `<ruby>`/`<rt>` 注音標籤）的章節樣本須列入核心測試案例，驗證切句後產生的 CFI 能正確還原為合法 DOM Range 並被既有 `Overlayer` 渲染，不只測試單一 TextNode 內的簡單句子。
   - `TtsCacheManager`：比照 `highlights_repository_test.dart` 的 `sqflite_common_ffi` 記憶體資料庫寫法，驗證快取寫入/命中/LRU 淘汰邏輯。
3. **`app/integration_test/`（真機專屬）**：`audio_service` 前景通知與鎖定畫面控制項是否正確顯示與可操作、App 背景一段時間後前景恢復時高亮是否正確重新同步（驗證審查 Important #3 的修正）、真實裝置上朗讀音訊與畫面高亮的實際延遲是否在可接受範圍。

## Out of Scope

- **單詞級（word-level）高亮**：僅 Readest 部分公開資料提及、未查證到官方明確規格；FR-46 僅要求句級精度。
- **PDF 多欄/表格/頁首頁尾朗讀順序的完整解決方案**：只做使用者提示（User Story 24），不投入版面重排序工程。
- **Phase 3 端側神經語音的硬性交付承諾**：明確是 stretch goal，是否投入依 Phase 1/2 實際需求評估。
- **修改任何 vendored `foliate-js` 原始碼**：全部透過既有 `Overlayer`/`view.addAnnotation()` pipeline 整合（符合 ADR 0011／0013）。
- **CBZ 語音朗讀**：純圖像格式，無文字節點可朗讀。
- **簡繁轉換（FR-48）本身的實作**：僅記錄與 TTS 的聯動假設，簡繁轉換是獨立功能、獨立 Epic。
- **iOS／桌面平台**：比照專案既定政策「手機優先，Android 先於 iOS」，桌面版屬 `epic-13` 範圍，皆不在本 Epic 內。
- **手寫/自由繪圖標註**：與 TTS 無關，既有 PDF 閱讀器範圍已明確排除。

## Further Notes

- 兩份研究報告（`docs/research/tts_integration_architecture_research.md`／`pdf_tts_integration_architecture_research.md`）保有完整的架構論證細節（Provider 業界比較矩陣、CFI↔時間軸對齊機制、直排繁中排版細節、E-Ink 最佳化原理），本規格文件不重複這些論證，僅摘錄成為決策的部分；實作與審查時若對某個決策的「為什麼」有疑問，回頭查兩份報告對應章節（`design.md`「整體機制」表格已列出章節對應關係）。
- Phase 4（PDF TTS）依賴 Phase 1～2 的 Provider／快取／播放主幹先穩定，`issues.md` 拆解時應明確標註此依賴順序，Mini Player／鎖定畫面控制／Provider 選擇等 UI 層直接重用 Phase 1～2 產出，不重新設計。
- 本文件尚未包含 Scrum Master 階段的垂直切片工單拆解（`issues.md`）——依專案既有 SDD 流程，那是下一個獨立階段，不在本次 `/to-spec` 範圍內。
