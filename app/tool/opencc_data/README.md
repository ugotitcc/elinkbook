# OpenCC 原始字元對照表

`STCharacters.txt`（簡體→繁體，key=簡體字）／`TSCharacters.txt`（繁體→簡體，
key=繁體字）直接取自 [BYVoid/OpenCC](https://github.com/BYVoid/OpenCC)
專案的 `data/dictionary/` 目錄，授權 Apache-2.0（全文已 vendor 進本目錄的
`LICENSE`），不經修改、原樣 vendor 進本專案版控。

- 來源網址：
  - https://raw.githubusercontent.com/BYVoid/OpenCC/master/data/dictionary/STCharacters.txt
  - https://raw.githubusercontent.com/BYVoid/OpenCC/master/data/dictionary/TSCharacters.txt
  - https://raw.githubusercontent.com/BYVoid/OpenCC/master/data/dictionary/TWPhrases.txt
  - https://raw.githubusercontent.com/BYVoid/OpenCC/master/data/dictionary/TSPhrases.txt
  - https://raw.githubusercontent.com/BYVoid/OpenCC/master/LICENSE
- 下載日期：2026-09-15
- 用途：`app/tool/generate_conversion_dicts.js` 讀取這兩個檔案，產生
  `app/android/app/src/main/assets/foliate/text_conversion_dict.js` 與
  `app/lib/reader/text_conversion_dict.dart` 兩份供 App 使用的查找表
  （見 `docs/adr/0031-text-conversion-dual-runtime-dictionary-not-opencc-js.md`）。
- 更新方式：重新執行上方下載指令覆蓋這兩個檔案，再重跑
  `node app/tool/generate_conversion_dicts.js` 重新產生雙端查找表。

## `TWPhrases.txt`／`TSPhrases.txt`（epic-42-text-conversion Issue 0b，2026-09-15）

簡轉繁（`toTraditional`）採 `STCharacters.txt` + `TWPhrases.txt`（台灣在地化片語，
817 條）；繁轉簡（`toSimplified`）採 `TSCharacters.txt` + `TSPhrases.txt`
（片語消歧，477 條）。**刻意排除** `STPhrases.txt`（簡轉繁片語消歧，約
49,000 條，處理「幹/乾/干」這類依詞境選字，規模過大且非本 Epic 動機所在）
與 `TWVariantsRev.txt`／`TWVariantsRevPhrases.txt`（台灣異體字正規化，
`TWVariantsRev.txt` 甚至不是原始檔案，而是 OpenCC 自己用 `reverse.py` +
人工消歧義註記從 `TWVariants.txt` 動態產生的衍生檔案，正確重現其演算法的
成本與這兩個字典帶來的實際轉換品質提升不成比例）。這兩個排除項若未來要
重新評估，須另立 ADR，不是本 Issue 的「留待未來」既定計畫（比照
[ADR 0030](../../../adr/0030-text-conversion-character-level-for-cfi-safety.md)
排除詞彙轉換的先例，本 Epic 對「明確排除」一貫用同一個嚴謹度處理）。
