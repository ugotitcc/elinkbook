# TTS 語音朗讀與同步高亮（Read-along）——設計文件

**狀態：** 待人類審閱
**對應工單：** `epic-34-tts-readalong`（新 Epic）
**診斷依據：**
- `docs/research/tts_integration_architecture_research.md`（Foliate 格式篇——EPUB／KF8／CBZ／TXT／MD 架構研究）
- `docs/research/pdf_tts_integration_architecture_research.md`（PDF 篇——PDF 專屬定位/高亮差異）
- `/grill-with-docs`（`/grilling` ＋ `/domain-modeling`）Discovery 訪談，共 4 輪、12 題，人類逐題拍板
- `docs/prd.md` FR-45（TTS）／FR-46（Read-along 同步高亮）／FR-47（PDF TTS）／FR-48（簡繁轉換，跨功能聯動）

## 背景

elinkBook 已完成核心閱讀體驗（EPUB/KF8/CBZ/TXT/MD 統一走 `FoliateReaderView`，PDF 獨立走 `PdfReaderView`）。語音朗讀（TTS）與朗讀同步高亮（Read-along）是 PRD 中列為 P2／P3 的進階功能（FR-45～47），此前已委託兩輪獨立架構研究，分別涵蓋 Foliate 格式與 PDF 格式的技術方案。兩份報告的核心結論一致：**盡量重用既有基礎設施（`epubcfi.js`／`overlayer.js`／`pdfrx.loadStructuredText()`／`pageOverlaysBuilder`／`PdfThumbnailCache` pattern），不另建平行機制**。

本次 `/grill-with-docs` Discovery 訪談的目的，是在兩份報告已經給出的技術方案之上，把「範疇、時程、資料模型邊界、跨功能聯動、互動行為」這些報告未涵蓋或需要人類拍板的產品層決策定案，形成可以直接進入 Architecting／Scrum Master 階段的共識。

## 目標

Phase 1 完成後，EPUB／KF8／TXT／MD 支援系統原生語音朗讀＋句級同步高亮，並具備背景播放與快取；後續 Phase 依序擴充雲端 API、端側離線神經語音，以及 PDF 朗讀支援。具體範疇由下列拍板決策定義：

### 已拍板決策

1. **範疇與顆粒度**：一個 Epic（`epic-34-tts-readalong`）涵蓋 Foliate TTS（主幹）＋ PDF TTS（後段 Phase，依賴主幹完成），不拆成兩個 Epic——兩者共用 Provider／快取／播放／`audio_service` 背景播放這層架構，拆開會讓共用部分脫節。
2. **Provider 路線圖**（沿用兩份報告建議）：
   - Phase 1：僅 `SystemTtsProvider`（`flutter_tts`，Android 原生 TextToSpeech）。
   - Phase 2：加 `OpenAiCompatibleProvider`（使用者自備 API Key／自建服務）。
   - Phase 3：端側神經語音（Sherpa-ONNX + Kokoro-zh），**列為 stretch goal**——是否投入依 Phase 1/2 上線後的實際需求評估，不預設量化門檻、不是硬性承諾。
3. **資料模型邊界**：TTS 朗讀高亮是暫態 UI 狀態，Foliate（CFI／`Overlayer`）與 PDF（頁碼＋文字座標／`pageOverlaysBuilder`）皆不寫入 `highlights`／`notes` 資料表，正式記錄為 [ADR 0026](../../adr/0026-tts-highlight-ephemeral-not-persisted.md)。
4. **相依性風險前置驗證**：Phase 1 第一個 Issue 是獨立的套件相依性驗證 spike（見下方「分階段 Issue 藍圖」），須確認 `audio_service`／`just_audio`（或 `audioplayers`）／（Phase 3 才需要的）`sherpa_onnx` 與現有 `flutter_inappwebview`／`pdfrx`／`sqflite` 相依鏈無衝突後才繼續。`app/pubspec.yaml` 現有 `share_plus`/`file_picker`/`package_info_plus`/`win32` 版本鏈衝突史（見該檔案第 40-49 行註解）是這個 spike 存在的直接理由。
5. **Android 版本相容性**（已查證，非開放決策）：`flutter_tts`／`audio_service`／`sherpa_onnx` 三者 minSdk 皆為 21，不會把專案現有 `minSdk=24` 往上拉，Android 11 (API 30) 政策門檻可達成。真正要注意的是 `audio_service` 依專案 **targetSdk**（非 minSdk）觸發的 manifest 宣告——`foregroundServiceType="mediaPlayback"`、`FOREGROUND_SERVICE_MEDIA_PLAYBACK` 權限、Android 13 起 `POST_NOTIFICATIONS` 執行期權限流程——已列入相依性驗證 Issue 的檢查清單。
6. **PDF 多欄排版提示**：偵測到疑似多欄／複雜版面時，於 UI 提示使用者「此 PDF 排版較複雜，朗讀順序可能不完全正確」（簡單啟發式，不追求完美的版面重排序）。PDF 文字擷取順序不保證等於視覺閱讀順序，明確記錄為已知限制（FR-47 已載明，比照既有「PDF Page Label 尚未支援」先例）。
7. **簡繁轉換（FR-48）聯動**：TTS 朗讀「顯示層轉換後」的文字，畫面看到的字與耳朵聽到的字須一致。**待驗證技術假設**：若簡繁轉換是不改動 DOM 的純顯示層處理（例如 CSS/字型層級轉換），則朗讀文字抽取（`TreeWalker`）本來就會自動讀到轉換後的文字，不需要額外串接；此假設須在簡繁轉換功能實際設計/實作時明確確認其實作方式，若簡繁轉換改動 DOM 或發生在渲染前的文字層，則需要額外設計朗讀文字來源的選擇邏輯。
8. **手動導覽時的播放行為**：使用者朗讀中手動翻頁／捲動／跳章時，播放**自動暫停**（不嘗試偵測使用者意圖並自動跳讀接續，避免誤判；也不放任音訊與畫面各自前進、避免長期不同步）。使用者按下播放鍵恢復時，**從「畫面目前顯示的新位置」重新開始朗讀**，不回到暫停前的舊音訊位置——尊重使用者最後一次主動導覽的意圖。
9. **音訊合成一律走檔案管線**（審查澄清，非新決策）：兩份報告的 `TtsProvider.synthesize()` 契約已規定所有 Provider（含 Phase 1 `SystemTtsProvider`）皆回傳 `TtsSynthesisResult.audioFilePath`，代表 `flutter_tts` 端須採用 `synthesizeToFile()` 合成暫存音訊檔、統一交給 `just_audio`/`audioplayers` 播放，而非 `speak()` 直接輸出到系統喇叭——Phase 1～3 因此共用同一套播放器／`TtsTimeline`／`audio_service` 控制管線，不存在「部分 Provider 走檔案、部分不走」的架構分歧。暫存檔生命週期管理與合成延遲是否可接受，留待 `spec.md` 驗證（見「風險與待決事項」）。

## 非目標

- **不在本次規劃單詞級（word-level）高亮**：僅 Readest 部分公開資料提及、未查證到官方明確規格，FR-46 也僅要求句級精度，Phase 1～3 皆以句級高亮為準；若未來引擎精確度足夠且有明確需求，另立獨立評估。
- **不承諾解決 PDF 多欄/表格/頁首頁尾的朗讀順序問題**——只做使用者可見的提示，不投入版面重排序工程（見「已拍板決策」第 6 點）。
- **不在 Phase 1～3 為端側神經語音設定硬性上線承諾**——Phase 3 明確是 stretch goal（見「已拍板決策」第 2 點）。
- **不修改任何 vendored `foliate-js` 原始碼**——TTS 高亮全部透過既有 `Overlayer.add()`/`remove()` 與 `view.addAnnotation()` pipeline，比照劃線/備註功能的既有整合方式（符合 ADR 0011／0013 vendoring 原則）。
- **CBZ 不適用**——純圖像格式，無文字節點可朗讀，兩份報告與 FR-45 皆已明確排除。
- **不順便處理簡繁轉換（FR-48）本身的實作**——僅記錄第 7 點的聯動假設與待驗證項目，簡繁轉換是獨立功能、獨立 Epic。

## 整體機制

架構細節（Provider 抽象層、CFI↔TTS Timeline↔繁中直排對齊、`Overlayer` 高亮重用、E-Ink 安全視窗策略、PDF 頁碼＋文字座標定位、`pageOverlaysBuilder` 高亮疊加、模組劃分、Dart 領域模型、JS Bridge 契約）**完整定義於兩份研究報告，本文件不重複**，僅在此列出兩份報告與本次拍板決策的對應關係，供後續 Architecting（`spec.md`）階段直接引用：

| 主題 | 對應章節 |
| --- | --- |
| Provider 抽象與三合一融合架構 | Foliate 篇 §1、§2、§4 |
| CFI ↔ TTS Timeline 對齊、句子切分、Ruby 過濾 | Foliate 篇 §3.1、§3.3 |
| `Overlayer` 高亮重用（不竄改 DOM） | Foliate 篇 §3.2、§5.2 |
| E-Ink 安全視窗策略 | Foliate 篇 §3.4 |
| Dart 領域模型（`TtsProvider`／`TtsSynthesisResult`／`TtsWordTiming`） | Foliate 篇 §5.1（PDF 篇共用，不重複定義） |
| PDF 文字擷取／`loadStructuredText()` | PDF 篇 §2.1 |
| PDF 高亮渲染／`pageOverlaysBuilder` | PDF 篇 §2.2（**持久化邊界已被 ADR 0026 取代/固化，PDF 篇原文亦已提出相同結論**） |
| PDF 閱讀順序風險 | PDF 篇 §2.3 |
| PDF 分段單位／TOC 分組 | PDF 篇 §2.4 |
| PDF 效能／Lazy 擷取 | PDF 篇 §2.5 |

## 分階段 Issue 藍圖（供 Scrum Master 階段細化，非最終工單）

- **Phase 0（新增，對應已拍板決策第 4 點）**：套件相依性驗證 spike——`flutter pub add --dry-run`（或等效試算）確認 `audio_service`/`just_audio`（或 `audioplayers`）與現有相依鏈無衝突；盤點 `audio_service` 於專案實際 targetSdk 下需要的 manifest 宣告清單。**Phase 1 其餘 Issue 依賴本 Issue 通過**。
- **Phase 1（Foliate MVP，對應 Foliate 篇 §6 Phase 1）**：`TtsProvider` 介面＋`SystemTtsProvider`、`audio_service` 背景播放與控制欄、句級 `Overlayer` 高亮（含手動導覽自動暫停行為，已拍板決策第 8 點）、Reader 底部 Mini 控制列。完成後 EPUB／KF8／TXT／MD 一併可用（同一套 `FoliateReaderView`/CFI/Overlayer 路徑）。
- **Phase 2（分塊快取與雲端 API，對應 Foliate 篇 §6 Phase 2）**：`TtsCacheManager`（含快取上限與 LRU 淘汰策略，見「風險與待決事項」）、`OpenAiCompatibleProvider`、背景預生成、章節尋軌與鎖定畫面完整控制。
- **Phase 3（端側神經語音，stretch goal，對應 Foliate 篇 §6 Phase 3）**：`sherpa_onnx` 整合、繁中直排注音/標點停頓調優、E-Ink 深度最佳化。**是否啟動視 Phase 1/2 實際需求評估**。
- **Phase 4（PDF TTS，對應 PDF 篇 §4，依賴 Phase 1～2 主幹穩定）**：`PdfPageTextCache`、`PdfTtsSegment` 切分與逐頁擷取、`pageOverlaysBuilder` TTS 高亮疊加層（暫態，符合 ADR 0026）、多欄/複雜版面偵測提示（已拍板決策第 6 點）。Mini Player／鎖定畫面控制／Provider 選擇等 UI 層直接重用 Phase 1～2 產出，不重新設計。

## 測試策略

留待 Architecting（`spec.md`）與 Scrum Master（`issues.md`）階段依每個 Issue 的垂直切片定義單元測試/整合測試要求，比照本專案既有兩層測試架構（`app/test/` 純 Dart／widget test；`app/integration_test/` 真機驗證）。此處先列出設計層級須被驗證覆蓋的關鍵行為，供後續階段對照不遺漏：

- 句級高亮不偏移，直排／橫排切換後仍正確跟隨。
- 手動導覽觸發自動暫停；恢復播放從新畫面位置開始，不回跳舊音訊位置。
- TTS 高亮不寫入 `highlights`/`notes` 資料表、不出現在既有劃線/備註清單與同步流程中（ADR 0026 驗證點）。
- 相依性驗證 spike 的 `flutter analyze`／`flutter test` 基準線不受影響。
- 朗讀跨頁觸發安全視窗翻頁時，翻頁本身正常繪製，但句級高亮切換不得觸發整頁閃爍/重繪（E-Ink 模式下沿用 Foliate 篇 §3.4 既有的「停用漸變動畫、句級靜態高亮」結論；專案目前無獨立的 E-Ink「刷新控制器」元件，只有 `isEinkMode` 偏好旗標＋各畫面自行實作的靜態渲染，此驗證點是確保 TTS 高亮沿用既有做法，不是要新建協同機制）。

## 風險與待決事項

- **簡繁轉換聯動的技術假設**（已拍板決策第 7 點）須在簡繁轉換功能設計時重新確認，目前僅為推論。
- **Phase 3 端側神經語音**的實際投入時機未定，需要 Phase 1/2 上線後的使用數據或使用者回饋佐證。
- **PDF 多欄偵測啟發式**的準確度未經驗證，Phase 4 開工時需要用真實 PDF 樣本校準，避免誤報過多打擾未使用多欄排版的一般 PDF。
- **音訊合成暫存檔生命週期與延遲**（審查 review-design.md Important #1 殘留項）：`synthesizeToFile()` 的合成延遲是否落在可接受範圍（例如 <200ms）、暫存檔何時清理（播放完成／App 關閉／快取上限觸發），須在 `spec.md` 階段以實測數據拍板，不能只憑推論。
- **手動導覽恢復播放的反向索引契約**（審查 Important #2）：`TtsTimeline`／`SentenceCfiIndexer` 目前只設計「時間→段落」正向查找，已拍板決策第 8 點「從畫面新位置繼續朗讀」需要「位置→段落」反向查找（例如 `lookupSegmentByCfi(String visibleCfi)`／PDF 端 `lookupSegmentByPage(int pageIndex)`），`spec.md` 領域模型須明確補上此介面契約。
- **App 背景/前景切換時的高亮同步落差**（審查 Important #3）：Android 背景時 `InAppWebView` 的 JS 執行/計時器可能被系統節流，但 `audio_service` 前景服務讓音訊照常播放，導致背景播放一段時間後畫面高亮落後於實際播放進度。`spec.md` 須規範「App 從背景恢復前景（`AppLifecycleState.resumed`）時，`TtsController` 主動向 WebView 重送一次目前最新播放位置的高亮/翻頁指令」的同步協議，兩份研究報告皆未涵蓋此情境（假設 WebView 全程活躍）。
