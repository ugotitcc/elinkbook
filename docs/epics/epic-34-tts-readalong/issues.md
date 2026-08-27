# Epic 34 — TTS 語音朗讀與同步高亮（Read-along）：工單清單 (Issues)

依 `spec.md`（Architecting，核心介面/型別唯一事實來源；已依 `/superpowers:receiving-code-review` 審查修訂）拆解為 8 個垂直切片工單（Issue 1～8），範圍為 Phase 0（相依性驗證）＋ Phase 1（Foliate MVP：EPUB／KF8／TXT／MD）。**Phase 2（雲端 API/快取）／Phase 3（端側神經語音，stretch goal）／Phase 4（PDF）刻意不在本次拆解範圍內**——依 `design.md`「分階段 Issue 藍圖」，這三個 Phase 都依賴 Phase 1 主幹穩定後才開工，現在拆會在 Phase 1 完成前就過時，待 Phase 1 全數完成、人類確認排入時程後，再另開一輪 `/to-issues`。Issue 9 為 2026-08-27 事後追加：Issue 2 合併後才發現 `ReaderScreen` 正式呼叫端接線缺口，補開一張獨立工單追蹤（詳見該工單「來源」欄位）。

每個 Issue 皆須包含所需的單元測試要求（依 `spec.md`「Testing Decisions」已與人類確認的測試縫隙分工）。

---

## Issue 1：套件相依性驗證 spike

**Status:** ready-for-agent

**依賴：** 無，可立即開始

**來源：** `spec.md`「Phase 0 前置技術驗證」、`design.md` 已拍板決策第 4／5 點。

**背景／需求：** `app/pubspec.yaml` 現有 `share_plus`/`file_picker`/`package_info_plus`/`win32` 版本鏈已有難以三方兼容的相依衝突先例（見該檔案第 40-49 行註解）。Phase 1 需要新增 `audio_service`／`just_audio`（或等效音訊播放套件）與現有 `flutter_inappwebview`／`pdfrx`／`sqflite` 相依鏈的相容性須在動工前確認，否則後續 Issue 可能中途卡在相依性衝突而返工。

**設計要點：**
- 執行 `flutter pub add --dry-run`（或等效試算）驗證 `audio_service`／`just_audio`（或 `audioplayers`）加入後與現有相依鏈無版本衝突；若有衝突，記錄可行的版本鎖定策略（比照現有 `share_plus: ^11.1.0` 註解的處理方式）。
- 盤點 `audio_service` 依專案實際 targetSdk（`flutter.targetSdkVersion`）觸發的 `AndroidManifest.xml` 宣告清單：
  - 前景服務型別 `android:foregroundServiceType="mediaPlayback"`
  - 權限 `FOREGROUND_SERVICE_MEDIA_PLAYBACK`
  - Android 13 起 `POST_NOTIFICATIONS` 執行期權限流程
  - Android 12 起 exported components 需明確標註 `android:exported`
- 確認 `flutter_tts`／`audio_service`／`sherpa_onnx`（Phase 3 才需要，僅先確認不影響本次）三者 minSdk 皆為 21，不會把專案現有 `minSdk=24`／Android 11 (API 30) 政策門檻往上拉（已於 Discovery 階段查證，本 Issue 只需覆核，不需重新調查）。
- 輸出一份檢查清單文件，供 Issue 2、Issue 7 直接引用，不需要各自重新調查。

**測試要求：** 本 Issue 無新增程式碼邏輯，`flutter analyze`／`flutter test` 基準線須維持不受影響（僅新增/鎖定 `pubspec.yaml` 相依版本）。

**驗收標準：**
- [ ] `flutter pub add --dry-run`（或等效試算）確認無相依衝突，或衝突已有明確版本鎖定策略記錄
- [ ] targetSdk manifest 宣告清單已文件化，供後續 Issue 引用
- [ ] `flutter analyze`／`flutter test` 基準線無回歸

---

## Issue 2：最小朗讀閉環——系統語音逐句朗讀＋手動播放/暫停

**Status:** ready-for-agent

**依賴：** Issue 1

**來源：** `spec.md`「Implementation Decisions」（`TtsProvider`／`TtsController`／`TtsTimeline`／朗讀段擷取／音訊管線）、User Story 1、2、26、27。

**背景／需求：** 這是整個 Epic 的最小可展示閉環：使用者在 Foliate 格式書籍（EPUB／KF8／TXT／MD）按下播放，聽到系統語音逐句朗讀，可暫停/繼續，章節唸完自動停止。不含同步高亮（Issue 3）、不含背景播放（Issue 7）、不含上一句/下一句與語速調整（Issue 5）——這些都是後續切片。

**設計要點：**
- 定義 `TtsProvider` 抽象介面與 `TtsSynthesisResult`／`TtsWordTiming` 型別（`spec.md`「Implementation Decisions」已列出核心契約），實作 `SystemTtsProvider`（呼叫 Android 原生 TextToSpeech 對應套件的**檔案合成 API**，非直接輸出喇叭的即時朗讀 API——音訊管線統一走檔案合成，見 `spec.md` 決策說明）。
- 實作 `TtsController` 最小狀態機：播放中/暫停/停止三態，`play()`／`pause()`；訂閱既有 `FoliateReaderView` 的章節載入完成事件，逐句消費朗讀段並自動接續播放至章節結束。
- 實作 `TtsTimeline` 正向查找（音訊播放位置 → 朗讀段，二分搜尋）。
- 朗讀段擷取：章節載入時一次性建立「句子 → CFI」對照表（`TreeWalker` 掃描章節純文字，**過濾 `<rt>` 注音節點**——不朗讀注音本身，對每句呼叫既有 `epubcfi.js` 的 `CFI.fromRange()`）。
- 暫存音訊檔生命週期：固定命名空間、以目前朗讀段索引覆寫（不逐段累積新檔案），綁定 `TtsController.dispose()`／切換書籍／播放自然結束時清除（`spec.md` 契約澄清）。
- **CBZ 排除**：`TtsController` 啟用判斷須排除 CBZ（純圖像格式，無文字節點），畫面上對應功能入口顯示為停用狀態並附上說明文字，不是靜默無反應。
- `ReaderScreen` 新增可選（nullable）建構參數注入 TTS 相關依賴（比照 `highlightsRepository`/`notesRepository` 既有模式），未提供時 TTS 功能不啟用，不影響現有畫面行為與既有測試。
- 本 Issue 先提供最基礎的播放/暫停按鈕（不要求完整 Mini Player 視覺——Issue 6 才做），只要求功能可用、可測試。

**測試要求：**
- 純 Dart 單元測試：`SystemTtsProvider`（用假的底層 API 驗證 `synthesize()` 回傳結構正確，不需真的呼叫系統 TTS）、`TtsTimeline` 正向查找邊界情況。
- **朗讀段擷取核心測試案例**：句子跨多個 DOM 節點（例如 `這是<em>重要</em>觀念。`）與含 `<ruby>`/`<rt>` 注音標籤的章節樣本須列入測試，驗證切句後產生的 CFI 能正確還原為合法 DOM Range（`spec.md` Testing Decisions 已載明）。
- `ReaderScreen` widget test（主要縫隙）：驗證播放/暫停狀態切換、章節唸完自動停止、CBZ 書籍功能入口停用狀態；比照既有 `reader_screen_test.dart` fake callback 注入模式。

**驗收標準：**
- [x] `TtsProvider`／`TtsSynthesisResult`／`TtsWordTiming` 型別與 `SystemTtsProvider` 實作完成，單元測試通過
- [x] `TtsController` 可播放/暫停，逐句自動接續至章節結束
- [x] 朗讀段擷取正確過濾 `<rt>` 注音節點，跨標籤句子測試通過
- [x] CBZ 書籍 TTS 入口為明確停用狀態（非靜默無反應）
- [x] `ReaderScreen` 既有 widget test 零回歸；新增測試涵蓋播放/暫停/CBZ 排除
- [x] `flutter analyze`／`flutter test` 全數通過
- [x] **（2026-08-27 補充，原驗收標準遺漏，已拆為獨立工單）** `ReaderScreen` 正式呼叫端接線缺口已記錄並拆分為 Issue 9，本 Issue 範圍維持「`ReaderScreen` 願意接受 `ttsProvider` 參數」即算完成，詳見 Issue 9

---

## Issue 3：同步高亮跟隨（Read-along）

**Status:** ready-for-agent

**依賴：** Issue 2

**來源：** `spec.md`「Implementation Decisions」（高亮渲染）、ADR 0026、User Story 11、12。

**背景／需求：** 朗讀進行中，畫面即時高亮目前朗讀的句子，直排/橫排皆須正確跟隨。這是 TTS 與純文字朗讀 App 的核心差異化功能。

**設計要點：**
- 高亮渲染重用既有 `Overlayer.add()`/`remove()`（`view.addAnnotation()` pipeline），使用獨立 annotation key（與劃線/備註的 key 空間分開），**不寫入任何資料表**（ADR 0026 驗證點）。
- 朗讀段切換時（非每次音訊 tick），呼叫既有 `CFI.toRange()` 換回 DOM Range 交給 `Overlayer`；播放結束或朗讀段切換時清除前一個高亮。
- 直排（`vertical-rl`）模式下沿用 `Overlayer.highlight()` 既有的 `vertical`/`writingMode` 參數，不需要另外處理矩形轉向邏輯。
- 不修改任何 vendored `foliate-js` 原始碼（符合 ADR 0011／0013）。

**測試要求：**
- `ReaderScreen` widget test：斷言 fake `FoliateReaderView` 收到正確的高亮指令參數（segment CFI、`vertical` 旗標）；直排與橫排皆須驗證跟隨正確。
- 跨標籤句子（Issue 2 已建立測試樣本）驗證高亮能正確渲染，不只是 CFI 能還原。

**驗收標準：**
- [ ] 朗讀時畫面即時高亮目前朗讀句，直排/橫排皆正確跟隨
- [ ] 高亮不寫入 `highlights`/`notes` 資料表、不出現在既有劃線/備註清單（ADR 0026 驗證點）
- [ ] 播放結束/朗讀段切換時正確清除前一個高亮，無殘留
- [ ] `flutter analyze`／`flutter test` 全數通過，既有劃線/備註測試零回歸

---

## Issue 4：手動導覽自動暫停與恢復播放

**Status:** ready-for-agent

**依賴：** Issue 3

**來源：** `design.md`／`spec.md` 已拍板決策第 8 點、`review-design.md` Important #2（反向索引契約）、User Story 15、16。

**背景／需求：** 使用者朗讀中手動翻頁/捲動/跳章時，播放自動暫停；恢復播放時從畫面目前顯示的新位置重新開始朗讀，不回到暫停前的舊音訊位置。

**設計要點：**
- `TtsController` 訂閱既有 `FoliateReaderView` 的位置變化事件（relocate 類事件），偵測到非 TTS 自身觸發的位置變化時自動呼叫 `pause()`。
- `TtsTimeline` 新增反向查找介面：`lookupSegmentByCfi(String visibleCfi)`，依畫面目前可視位置反查對應或緊隨其後的第一個朗讀段。
- 播放鍵恢復邏輯：不回到暫停前的音訊位置，改為呼叫 `lookupSegmentByCfi()` 取得新位置對應的朗讀段，從該段重新開始合成/播放。
- **手動導覽觸發暫停時須清除舊高亮**（審查 `review-issues.md` Important #1）：偵測到手動導覽事件觸發自動暫停時，`TtsController` 主動清除畫面上的暫態高亮，不留殘影；否則使用者翻到很遠的頁面又翻回原頁面時，會看到一個過期的高亮（Issue 3 的驗收標準只涵蓋「播放結束/朗讀段切換」，字面上不含「暫停」這個情況）。待使用者按下播放鍵時，再由 `lookupSegmentByCfi()` 於新位置重新繪製高亮。

**測試要求：**
- 純 Dart 單元測試：`lookupSegmentByCfi()` 邊界情況（段落交界、目前位置早於/晚於全部已知段落）。
- `ReaderScreen` widget test：模擬手動翻頁事件觸發自動暫停；模擬翻頁後按播放，驗證朗讀從新位置的對應段落開始，而非舊音訊位置。

**驗收標準：**
- [ ] 朗讀中手動翻頁/捲動時播放自動暫停，且畫面舊高亮同步清除、不留殘影
- [ ] 按播放鍵後從畫面新位置對應的朗讀段開始，不回跳舊位置
- [ ] `lookupSegmentByCfi()` 邊界情況測試通過
- [ ] `flutter analyze`／`flutter test` 全數通過

---

## Issue 5：上一句/下一句/語速調整控制

**Status:** ready-for-agent

**依賴：** Issue 2

**來源：** `spec.md` User Story 3、4；語速調整生效時機契約澄清（`review-spec.md` Minor #2）。

**背景／需求：** 使用者想要跳到上一句/下一句重聽或跳過內容，並調整朗讀語速。

**設計要點：**
- `TtsController` 新增 `nextSegment()`／`previousSegment()`：中止目前播放，從指定朗讀段重新開始（比照 Issue 4 的「從指定段落開始」邏輯，可重用同一段程式碼路徑）。
- 語速調整：`synthesize()` 的 `speed` 參數只決定**下一段**尚未合成的朗讀段用什麼語速；**目前正在播放的段落**改用播放器的執行期變速（不重新合成、不中斷播放）。兩者不可混用同一套機制，否則會出現「調速後要等目前句念完才生效」的延遲體感。

**測試要求：**
- 純 Dart 單元測試：`TtsController.nextSegment()`/`previousSegment()` 狀態轉換正確性。
- `ReaderScreen` widget test：驗證上一句/下一句按鈕觸發正確的段落跳轉；語速調整時斷言「目前段落」呼叫播放器變速 API，而非重新觸發 `synthesize()`。

**驗收標準：**
- [ ] 上一句/下一句正確跳轉並開始播放對應段落
- [ ] 語速調整對目前播放段落即時生效（播放器變速），下一段才用新語速合成
- [ ] `flutter analyze`／`flutter test` 全數通過

---

## Issue 6：Mini Player 完整 UI

**Status:** ready-for-agent

**依賴：** Issue 2、Issue 5

**來源：** `spec.md`「Implementation Decisions」（`ReaderScreen` 整合）、User Story 5；`review-spec.md` Minor #1（版面層級）。

**背景／需求：** 把 Issue 2/5 用簡易按鈕做出來的播放/暫停/上一句/下一句/語速控制，整合進正式的 Reader 底部 Mini Player 元件。

**設計要點：**
- Mini Player 掛載於既有 Reader 底部工具列體系（比照既有 FAB／底部工具列的疊加方式）。
- 與既有底部導覽列/目錄側邊欄的顯示/隱藏連動，避免互相遮擋；具體堆疊層級與版面調整依實際畫面測試決定。
- 整合 Issue 2（播放/暫停）、Issue 5（上一句/下一句/語速）的既有邏輯，本 Issue 只做 UI 整合，不新增播放邏輯。
- **單一事實來源**（審查 `review-issues.md` Minor #1）：Mini Player 嚴格訂閱 `TtsController` 暴露的播放狀態（Stream／`ValueListenable`），不自行維護一份私有狀態變數——這樣使用者在 Issue 7 的背景通知欄按下播放/暫停後切回前景，Mini Player 的圖示/進度會自動保持一致，不需要額外寫同步邏輯。

**測試要求：**
- `ReaderScreen` widget test：Mini Player 各按鈕正確觸發對應的 `TtsController` 方法；與底部導覽列同時顯示時的版面不互相遮擋（可用 widget tree 結構斷言，不需要視覺回歸測試）。

**驗收標準：**
- [ ] Mini Player 正式 UI 完成，整合播放/暫停/上一句/下一句/語速控制
- [ ] 與既有底部導覽列/目錄側邊欄顯示連動正常，無遮擋
- [ ] `flutter analyze`／`flutter test` 全數通過，既有底部工具列相關測試零回歸

---

## Issue 7：背景播放與系統整合（`audio_service`）

**Status:** ready-for-agent

**依賴：** Issue 2

**來源：** `spec.md` User Story 6、7、8、9、10、28；`review-design.md` Important #3（前景恢復同步）；`review-spec.md` Important #3（Audio Focus 中斷處理）。

**背景／需求：** 這是本輪範圍內內容最多的一個 Issue（Discovery 階段已與人類確認保留為單一切片，不再拆分）：App 切到背景/鎖定螢幕後朗讀繼續、通知欄與鎖定畫面播放控制、耳機線控、耳機拔出自動暫停、App 從背景恢復前景時畫面高亮重新同步、系統音訊焦點（來電/其他音樂 App）中斷時的行為。

**設計要點：**
- 整合 `audio_service`，依 Issue 1 盤點的 targetSdk manifest 清單補齊宣告（`foregroundServiceType="mediaPlayback"`、對應權限、通知執行期權限流程）。
- 通知欄與鎖定畫面顯示目前朗讀狀態與播放/暫停控制；耳機線控（藍牙/有線）對應播放/暫停；耳機拔出時自動暫停（Android 系統既有的 `ACTION_AUDIO_BECOMING_NOISY` 廣播事件）。
- **App 前景恢復重新同步**（`review-design.md` Important #3）：`TtsController` 監聽 `AppLifecycleState.resumed`，App 從背景切回前景時，主動向畫面重送一次目前最新播放位置對應的高亮/翻頁指令——Android 背景時 WebView 的 JS 執行/計時器可能被系統節流，但 `audio_service` 前景服務讓音訊照常播放，若不主動重新同步，畫面高亮會落後於實際播放進度。
- **Audio Focus 中斷處理**（`review-spec.md` Important #3）：
  - 暫時失去焦點（`AUDIOFOCUS_LOSS_TRANSIENT`，來電/導航語音/系統通知音）：暫停播放，焦點恢復時自動恢復播放。
  - 永久失去焦點（`AUDIOFOCUS_LOSS`，使用者開啟其他音樂/Podcast App）：暫停播放並釋放音訊硬體佔用，**不**自動恢復，等同使用者手動暫停。

**測試要求**（分兩層，審查 `review-issues.md` Important #2——耳機拔插、實體來電這類系統廣播無法在 CI／`flutter test` 中物理重現，須明確分流）：
- **自動化層**：`ReaderScreen` widget test，向 `TtsController` 注入模擬的廣播/MediaSession 回呼（`AUDIOFOCUS_LOSS`/`AUDIOFOCUS_LOSS_TRANSIENT`/`ACTION_AUDIO_BECOMING_NOISY`/`AppLifecycleState.resumed` 等 fake 事件源），驗證狀態機暫停/恢復邏輯正確，不依賴真實系統廣播。
- **手動真機驗收清單**（`app/integration_test/` 涵蓋不到的部分，合併前須人工執行並記錄於對應 review 報告）：
  - 實體藍牙耳機連線中途拔除／有線耳機拔出，朗讀自動暫停。
  - 實體電話撥入（暫時失焦），通話結束後朗讀自動恢復。
  - 切換至 YouTube／其他音樂 App 播放（永久失焦），朗讀暫停且不自動恢復。
  - `audio_service` 前景通知與鎖定畫面控制項正確顯示與可操作。
  - App 背景一段時間後前景恢復時，畫面高亮正確重新同步至目前實際播放進度。

**驗收標準：**
- [ ] 背景播放與通知欄/鎖定畫面控制正常運作（真機驗證）
- [ ] 耳機線控與耳機拔出自動暫停正常（真機驗證）
- [ ] App 前景恢復時畫面高亮正確重新同步（真機驗證）
- [ ] Audio Focus 暫時/永久失去焦點的行為符合設計要點（真機驗證）
- [ ] `flutter analyze`／`flutter test` 全數通過

---

## Issue 8：E-Ink 安全視窗與靜態高亮策略

**Status:** ready-for-agent

**依賴：** Issue 3

**來源：** `spec.md` User Story 13、14；`design.md`／Foliate 篇研究報告 §3.4。

**背景／需求：** E-Ink 螢幕無法承受逐句捲動造成的頻繁刷新殘影，須採「句級靜態高亮＋安全視窗翻頁」策略。

**設計要點：**
- E-Ink 高對比模式下，朗讀高亮停用漸變動畫，採靜態對比顯示。
- 安全視窗判斷：畫面中央劃出安全區域（例如可視範圍 20%～80%），朗讀高亮只要還落在此區域內就不觸發捲動/翻頁；只有高亮超出安全視窗時，才觸發一次性整頁翻頁或跳躍捲動。
- 朗讀跨頁觸發安全視窗翻頁時，翻頁本身正常繪製，但句級高亮切換不得觸發整頁閃爍/重繪——專案目前無獨立的 E-Ink「刷新控制器」元件，只有 `isEinkMode` 偏好旗標＋各畫面自行實作的靜態渲染，本 Issue 確保 TTS 高亮沿用既有做法，不新建協同機制。

**測試要求：**
- `ReaderScreen` widget test：驗證高亮在安全視窗範圍內時不觸發翻頁/捲動指令；超出範圍時才觸發；E-Ink 模式下高亮渲染不含動畫參數。

**驗收標準：**
- [ ] E-Ink 模式下朗讀高亮為靜態對比、無漸變動畫
- [ ] 安全視窗範圍內不觸發不必要的翻頁/捲動
- [ ] 超出安全視窗時正確觸發一次性翻頁/捲動
- [ ] `flutter analyze`／`flutter test` 全數通過

---

## Issue 9：`ReaderScreen` 正式接線——真實 `SystemTtsProvider` 注入開書流程

**Status:** ready-for-agent

**依賴：** Issue 2

**來源：** `reviews/review-issue-2-code.md`（真機驗證前發現的接線缺口）、`issues.md` Issue 2 驗收標準補充（2026-08-27）。

**背景／需求：** Issue 2 完成了 `TtsController`／`SystemTtsProvider`／播放狀態機，`ReaderScreen` 也新增了可選（nullable）的 `ttsProvider` 建構參數與最小播放/暫停按鈕，且功能本身測試皆已通過。但 PR [#190](https://git.jigong.org/huthief/elinkBook/pulls/190) 合併後才發現：唯一實際建構 `ReaderScreen` 的正式呼叫端 `app/lib/screens/library_screen.dart`（`_openBook()`）從未傳入這個參數，比照的 `bookmarksRepository`/`highlightsRepository`/`notesRepository` 既有模式都有從 `main.dart` 一路往下傳到 `library_screen.dart` 再進 `ReaderScreen`，唯獨 TTS 這次少了這一段。結果是：使用者裝上正式 APK 開書，完全看不到朗讀播放鈕，功能雖已合併卻無法展示、也無法真機驗證。

**設計要點：**
- 比照 `bookmarksRepository`/`highlightsRepository`/`notesRepository` 既有的「App 級依賴逐層往下傳」模式，在建構這些 repository 的同一處（`main.dart`／`ReaderFeatureRepositories` 或等效聚合點）新增建構一個 `SystemTtsProvider(flutterTts: FlutterTts())`，往下傳到 `library_screen.dart` 的 `_openBook()`，再傳入 `ReaderScreen(ttsProvider: ...)`。
- 確認建構時機與生命週期：是否要單例（App 啟動時建構一次、跨書共用）或比照既有 repository 模式決定；若 `flutter_tts` 底層資源需要在 App 層級管理，一併確認是否需要 dispose 掛勾。
- CBZ 排除、播放按鈕停用狀態等邏輯已在 Issue 2 的 `ReaderScreen` 內處理完成，本 Issue 不重複實作——只需確保正式呼叫端「一律」傳入同一個 provider（不依書籍格式做條件式判斷要不要傳，格式排除交給 `ReaderScreen` 內部既有邏輯）。
- 不涉及任何 UI 視覺變更（沿用 Issue 2 既有的陽春播放/暫停按鈕，正式 Mini Player UI 是 Issue 6 的範圍）。

**測試要求：**
- widget test：驗證 `library_screen.dart` 建構 `ReaderScreen` 時傳入的 `ttsProvider` 非 `null`（可能需要新增或調整 `library_screen_test.dart` 既有斷言方式）。
- 真機手動驗證（比照 Issue 2「測試策略總結」第 4 點端到端驗收）：安裝正式建置的 APK，開啟一本 EPUB／KF8／TXT／MD 書籍，確認能看到播放鈕、按下後聽到朗讀、可暫停/繼續。

**驗收標準：**
- [x] `library_screen.dart` 開書流程實際建構 `SystemTtsProvider` 並傳入 `ReaderScreen.ttsProvider`
- [ ] 真機安裝後開啟 Foliate 格式書籍能看到並使用朗讀播放/暫停按鈕，CBZ 書籍維持明確停用狀態
- [x] 既有 `library_screen_test.dart`／`reader_screen_test.dart` 零回歸
- [x] `flutter analyze`／`flutter test` 全數通過
