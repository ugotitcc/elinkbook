# Domain Docs（領域文件）

工程相關的 skills 在探索本儲存庫程式碼時，應如何消化這裡的領域文件說明。

## 開始探索前，請先讀這些

- 根目錄的 **[CONTEXT.md](./CONTEXT.md)**：包含全專案共用的通用語言與限制。
- **`docs/adr/`**：閱讀與你即將處理的區域有關的 ADR。

## 檔案結構

單一情境（Single-context）儲存庫：

```
/
├── CONTEXT.md
├── docs/adr/
└── docs/prd.md
```

## 使用詞彙表中的用語

當你的輸出提到某個領域概念時，請使用 [CONTEXT.md](./CONTEXT.md) 中定義的用語。在此之前，請沿用 `docs/prd.md` 中已建立的詞彙（例如 CFI、直排/橫排、避頭尾）。

## 標記 ADR 衝突

若你的輸出與既有的 ADR 相牴觸，請明確指出，而非默默覆蓋原有決策。
