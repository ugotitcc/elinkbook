# Readium FXL 第一頁獨立成頁（Single Cover Spread）可行性分析與技術評估報告

- **評估日期**：2026-07-30
- **主題**：分析 Readium 是否可透過 `Spread` Enum 強制在 FXL EPUB 時將第一頁獨立成頁，或是否有其他方式達成。
- **核心結論**：
  1. **無法**單靠 `Spread` Enum 達成（`Spread` Enum 僅控制全域雙頁/單頁視圖開關，缺乏頁面級別控制）。
  2. **最佳可行方案**：在解析開啟 EPUB 後，動態覆寫 `Publication.readingOrder[0].properties` 中的 `page` 屬性為 `Page.CENTER`（相當於 EPUB `page-spread-center` 語意），利用 Readium 原生 Spread Builder 自動將第一頁排版為獨立 Spread。

---

## 1. 問題脈絡與需求

在 Fixed-Layout (FXL) EPUB 電子書（如漫畫、繪本、畫冊）啟用雙頁模式（`Spread.ALWAYS`）時，常見需求為「封面/第一頁必須單獨獨立成頁（Single Page Spread），從第二頁開始才兩兩並排」。

使用者詢問：
> Readium 可否強制透過 `Spread` Enum 強制在 FXL EPUB 時將第一頁獨立成頁？或有其他方式能達到讓第一頁獨立成頁？

---

## 2. Readium 機制剖析與可行性檢視

### 2.1 `Spread` Enum 的機制與局限

在 Readium (Readium Kotlin Toolkit) 中，`org.readium.r2.navigator.preferences.Spread` 提供以下選項：
- `NEVER`：全域單頁模式。
- `ALWAYS`：全域雙頁模式。
- `AUTO`：依裝置尺寸/方向自動選擇單/雙頁。

**限制分析**：
- `Spread` Enum 為**全域渲染偏好（Global Preference）**，控制整個 Navigator 是否一次載入並排兩個頁面 Slot。
- `Spread` Enum 並未設計 `ALWAYS_EXCEPT_FIRST` 或 `FIRST_SINGLE` 等頁面層級枚舉值。
- 因此，**無法單靠改變 `Spread` Enum 讓 Readium 自動將第一頁獨立成頁**。

### 2.2 Readium 如何決定頁面是否併為跨頁 (Spread)？

Readium 決定 `readingOrder` 中哪兩頁併為同一個 Spread 的核心邏輯依賴於 **EPUB OPF / Spine 中的頁面佈局宣告 (`page-spread-*`)**：
1. **`page-spread-center` / `Page.CENTER`**：宣告該頁面必須單獨居中占據一個 Spread（單頁 Spread, Length=1）。
2. **`page-spread-left` / `page-spread-right`**：宣告該頁面在雙頁組合中的左/右位置。
3. **無宣告（default）**：在 `Spread.ALWAYS` 模式下，Readium 的 Spread Builder 會依照頁面順序每 2 頁兩兩劃分為同一個 Spread（例如 `[Page 0, Page 1]`, `[Page 2, Page 3]`）。

---

## 3. 可行解決方案評估

### 方案 1：動態覆寫 `Publication.readingOrder[0]` 頁面屬性（最推薦 ⭐⭐⭐⭐⭐）

在 EPUB 檔被 Readium 開啟、產生 `Publication` 物件後，在傳給 `EpubNavigatorFragment` 前，直接將第一頁的 link 屬性覆寫為 `Page.CENTER`。

#### 實作範例 (Kotlin)：
```kotlin
import org.readium.r2.shared.publication.Publication
import org.readium.r2.shared.publication.presentation.Page
import org.readium.r2.shared.publication.presentation.presentation

fun applyFirstPageCenterOverride(publication: Publication) {
    val firstLink = publication.readingOrder.firstOrNull() ?: return
    
    // 將第一頁的 page 屬性設為 CENTER (即 EPUB page-spread-center 語意)
    val updatedProperties = firstLink.properties.copy(
        presentation = firstLink.properties.presentation.copy(
            page = Page.CENTER
        )
    )
    
    publication.readingOrder[0] = firstLink.copy(properties = updatedProperties)
}
```

#### 方案評估：
- **相容性**：完全相容 Readium 原生 Spread Builder，不修改 Readium SDK 核心。
- **視覺與操作**：Readium 自動將 Page 0 歸為單頁 Spread，手勢滑動、翻頁動畫、頁數計算完全正常，無過渡瑕疵。

---

### 方案 2：EPUB 檔案解析層注入 (Publication Transformer / Fetcher)

在載入 EPUB 檔案時，攔截 `content.opf` 解析過程，在 `<spine>` 內的第一個 `<itemref>` 上注入 `properties="page-spread-center"`：

```xml
<spine page-progression-direction="rtl">
    <!-- 動態注入 properties="page-spread-center" -->
    <itemref idref="cover" properties="page-spread-center" />
    <itemref idref="page001" />
</spine>
```

#### 方案評估：
- **相容性**：從檔案數據層達成符合標準 EPUB 3 FXL 規範。
- **實作成本**：需要實作 XML/Fetcher 攔截器，相對方案 1 較為繁瑣。

---

### 方案 3：Native App 層 Layout 物理強制裁切 (UI Layer Workaround)

若採用自訂 `ViewPager` / `ViewGroup` 容器（例如 `EpubReaderView.kt`）：
- 在 `currentPageIndex == 0` 時，強制可視區域平分比例失效，硬性隱藏次要 View，只顯現 Page 0。

#### 方案評估：
- **相容性與品質**：**不推薦**。底層 Readium 仍認為 Page 0 與 Page 1 在同一個 Spread，滑動拖曳時會有畫面殘影或雙頁同時滑動的視覺缺陷。

---

## 4. 結論與行動建議

1. **結論**：`Spread` Enum 無法達成第一頁單頁需求。
2. **推薦行動方案**：採用 **方案 1（動態覆寫 `Publication.readingOrder[0]` 的 `Page.CENTER` 屬性）**。此方式程式碼量最少、維護成本最低，且為符合 Readium 原生架構的最佳實踐。
