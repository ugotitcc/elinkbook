# Epic 16 Issue 7 — 真機驗證與收尾 QA 報告

## FR-41「頁間不留空白」核心驗收確認

### PDF 路線（本 issue 首次量化驗證）
- 測試素材：2 頁雙色測試 PDF（第 0 頁純紅 RGB(255,0,0)、第 1 頁純藍 RGB(0,0,255)），`dualPageMode=always`／`dualPageCoverAlone=false`／`fitMode=pageFit`，橫向。
- 量測方式：`adb screencap` 截圖 + 沿螢幕水平中線像素採樣，量測紅色頁尾與藍色頁首的交界間隙（`measure_fr41_gap.py`）。
- 結果：`width=2400 red_end=1199 blue_start=1200 gap_px=0` (PASS)
- 結論：PASS：拼接處無可見間隙，FR-41 於 PDF 路線通過。

### EPUB FXL 路線（引用 Issue 6 既有結論，不重複執行）
- 依 `issues.md` Issue 6「真機視覺驗收（2026-07-14）」：`applyFxlFitScale()` 的 `translationX` 重複疊加 bug 修正後，人類於真機以真實漫畫素材重新驗證，「封面頁正常顯示、翻頁至內頁後左右兩頁正常顯示且無縫並排，FR-41 核心驗收點通過」。
- 結論：PASS（沿用 Issue 6 結論，本 issue 不重複執行）。
