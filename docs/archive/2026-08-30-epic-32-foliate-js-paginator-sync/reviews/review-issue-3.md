# Epic 32 Issue 3 — 真機重測報告

**測試日期**：2026-08-25  
**測試裝置**：
- TCL 14 吋 (`3CEF42ECD491687` / 9491G)
- ViWoods AiPaper Reader C (`SCAB1102M00640` / AiPaper Reader C)
**對應同步 commit**：`769aba7`（chore(epic-32): 同步 paginator.js 至上游 6c6a491）

---

## 1. Epic 18 Issue 47（長按選字前幾影格畫面不暴跳）

橫排長按 / 橫排拖曳 / 直排長按 / 直排拖曳 各自 PASS
---

## 2. Epic 25 Issue 1（畫線選取已確立時不誤觸跳頁）

PASS

---

## 3. Epic 27 Issue 9（no-swipe 屬性正確阻止滑動手勢）

PASS

---

## 4. 直排連續翻頁 smoke test

是

---

## 5. 總結與判定

- **Epic 18 Issue 47（長按選字前幾影格畫面不暴跳）**：✅ **PASS**（橫排長按、橫排拖曳、直排長按、直排拖曳皆平穩無暴跳）
- **Epic 25 Issue 1（畫線選取確立後不誤觸跳頁）**：✅ **PASS**（TCL 14 吋與 ViWoods AiPaper Reader C 慢速/快速拖曳皆未誤觸跳頁）
- **Epic 27 Issue 9（no-swipe 屬性阻止滑動手勢）**：✅ **PASS**（右上角長按/滑動不誤翻頁，3×3 熱區與實體音量鍵翻頁正常）
- **直排連續翻頁 smoke test**：✅ **PASS**（連續前翻 5 次 + 後翻 5 次精確逐字回到原文字錨點）

**判定結果**：4 項真機驗證全數通過，無任何回歸現象。判定為 **Branch A：放行**，接續執行 Task 7 文件收尾。
