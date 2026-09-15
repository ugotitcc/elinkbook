# OpenCC 原始字元對照表

`STCharacters.txt`（簡體→繁體，key=簡體字）／`TSCharacters.txt`（繁體→簡體，
key=繁體字）直接取自 [BYVoid/OpenCC](https://github.com/BYVoid/OpenCC)
專案的 `data/dictionary/` 目錄，授權 Apache-2.0（全文已 vendor 進本目錄的
`LICENSE`），不經修改、原樣 vendor 進本專案版控。

- 來源網址：
  - https://raw.githubusercontent.com/BYVoid/OpenCC/master/data/dictionary/STCharacters.txt
  - https://raw.githubusercontent.com/BYVoid/OpenCC/master/data/dictionary/TSCharacters.txt
  - https://raw.githubusercontent.com/BYVoid/OpenCC/master/LICENSE
- 下載日期：2026-09-15
- 用途：`app/tool/generate_conversion_dicts.js` 讀取這兩個檔案，產生
  `app/android/app/src/main/assets/foliate/text_conversion_dict.js` 與
  `app/lib/reader/text_conversion_dict.dart` 兩份供 App 使用的查找表
  （見 `docs/adr/0031-text-conversion-dual-runtime-dictionary-not-opencc-js.md`）。
- 更新方式：重新執行上方下載指令覆蓋這兩個檔案，再重跑
  `node app/tool/generate_conversion_dicts.js` 重新產生雙端查找表。
