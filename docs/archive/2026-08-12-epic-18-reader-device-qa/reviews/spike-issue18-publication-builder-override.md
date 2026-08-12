# Issue 18 Spike 報告：`Publication.Builder` 重建 `metadata.layout` 後 `EpubNavigatorFragment` 渲染行為驗證

- **驗證日期**：2026-07-30
- **測試裝置**：`3CEF42ECD491687` (9491G, Android 15, API 35)
- **測試書籍**：Issue 15 驗收時已知會被誤判為流式的漫畫 EPUB（已套用「強制 FXL」）
- **結論**：**GO ✅**

---

## 1. 驗證範圍摘要

本 Spike 驗證 Issue 16/17 的替代方案：不再只覆寫 `EpubReaderView.kt` 的 `isFixedLayout` 檢查點（Issue 17 已證明無效），而是用 `Publication.Builder` 重建整個 `Publication` 物件，將 `metadata.layout` 強制設為 `Layout.FIXED`，讓 `EpubNavigatorFragment` 收到的 metadata 本身就標記為 FXL。

核心假設：若重建後的 `Publication` 物件被傳入 `EpubNavigatorFactory`，Readium 官方元件會根據這個被修改過的 metadata 判斷為 FXL，進而渲染成雙頁並排。

---

## 2. Task 1：基準觀察（修改前）

### 2.1 執行方式
1. 於 `main` 分支建置 debug APK 並安裝至真機。
2. 開啟已套用「強制 FXL」的漫畫 EPUB。
3. 裝置轉橫向，確認「雙頁模式」設為「永遠雙頁」。
4. 觀察畫面渲染行為。

### 2.2 觀察結果
- 畫面**只顯示一頁（固定在左邊）**
- 翻頁行為為一頁一頁切換，非兩頁一組（spread）切換
- **Issue 16 症狀確認重現**

---

## 3. Task 2：`Publication.Builder` 重建後驗證

### 3.1 硬編碼變更
於 `app/android/app/src/main/kotlin/cc/ugotit/elinkbook/EpubReaderView.kt` 進行 5 處暫時修改：

| 位置 | 變更 |
|------|------|
| `:165` 新增欄位 | `private var spikeEffectivePublication: Publication? = null` |
| `:924-934` `attachNavigator()` 內 | 用 `Publication.Builder` 重建 `Publication`，將 `metadata.layout` 設為 `Layout.FIXED`，存入 `spikeEffectivePublication`；`EpubNavigatorFactory` 改接收重建後的物件 |
| `:502` `applyFxlFitScale()` | `publication?.metadata?.layout` → `spikeEffectivePublication?.metadata?.layout` |
| `:1009` tap 熱區監聽器註冊 | `openedPublication.metadata.layout` → `spikeEffectivePublication?.metadata?.layout` |
| `:1210` `reportLayoutResolved()` | `publication?.metadata?.layout` → `spikeEffectivePublication?.metadata?.layout` |

**`Publication.Builder` 實作細節**：

```kotlin
@OptIn(org.readium.r2.shared.InternalReadiumApi::class)
val effectivePublication = Publication.Builder(
    manifest = openedPublication.manifest.copy(
        metadata = openedPublication.manifest.metadata.copy(
            layout = Layout.FIXED,
        ),
    ),
    container = openedPublication.container,
    servicesBuilder = Publication.ServicesBuilder(),
).build()
```

- `manifest`：從原始 `Publication` 複製，僅修改 `metadata.layout`
- `container`：沿用原始 `Publication` 的 container（需 `@OptIn(InternalReadiumApi::class)`）
- `servicesBuilder`：**新建空的 `ServicesBuilder()`**（原始的 `servicesBuilder` 為 private 無法存取）

### 3.2 執行方式
1. 套用上述 5 處硬編碼。
2. 重新建置 debug APK 並安裝至真機。
3. 重複 Task 1 的觀察步驟。

### 3.3 觀察結果
- 畫面**呈現雙頁並排（FXL）效果** ✅
- 翻頁行為正常
- 熱區翻頁正常
- **核心假設成立**

### 3.4 Service Loss 驗證

因 `servicesBuilder` 使用新建的空物件（原始的為 private 無法存取），可能存在服務遺失風險：

| 功能 | 結果 | 備註 |
|------|------|------|
| 翻頁 | ✅ 正常 | — |
| 熱區翻頁 | ✅ 正常 | — |
| 進度條 | ⚠️ 不可見 | 需進一步確認是否為 Service Loss 導致 |
| 頁數呈現 | ⚠️ 模式不同 | 與預期的 1,3-2,5-4 呈現方式有差異 |

---

## 4. 綜合決策判定：GO ✅

| 判定條件 | 實測證據 | 結果 |
|----------|---------|------|
| `Publication.Builder` 重建 `metadata.layout = Layout.FIXED` 後，`EpubNavigatorFragment` 是否跟著渲染成 FXL（雙頁並排） | 畫面呈現雙頁並排效果，翻頁正常 | ✅ 通過 |

**結論**：`EpubNavigatorFragment` 會根據傳入的 `Publication` 物件的 `metadata.layout` 決定渲染模式。透過 `Publication.Builder` 重建物件並強制設定 `metadata.layout = Layout.FIXED`，可以讓 Readium 官方元件正確判斷為 FXL，進而渲染成雙頁並排。

---

## 5. 附帶發現

### 5.1 `Publication.Builder` API 實際簽名

Readium kotlin-toolkit 3.3.0 的 `Publication.Builder` 實際簽名為：

```kotlin
Publication.Builder(manifest: Manifest, container: Container<Resource>, servicesBuilder: ServicesBuilder)
```

- **不是** `Publication.Builder(publication, json)` — 原始假設錯誤
- `container` 標記為 `@InternalReadiumApi`，需 `@OptIn` 才能存取
- `servicesBuilder` 為 private 屬性，無法從既有 `Publication` 取得，只能新建

### 5.2 Service Loss 風險

使用新建的 `ServicesBuilder()` 可能遺失原始物件的服務（如 `positions()`）。本 Spike 觀察到進度條不可見、頁數呈現模式異常，可能與此有關。正式實作時需評估是否需要複製原始的 `servicesBuilder`（但因其為 private，可能需要反射或其他方式）。

### 5.3 使用者額外需求

使用者於真機驗證時提出：「請比照現有（或PDF）有一個可以指定封面為單頁顯示功能」。此為新功能需求，建議另立 Issue 處理。

---

## 6. 建議下一步

**GO 後的正式實作方向：**

1. **將 `Publication.Builder` 重建邏輯納入正式實作**：在 `attachNavigator()` 中，偵測到「強制 FXL」偏好時，用 `Publication.Builder` 重建物件。
2. **評估 Service Loss 影響**：確認進度條、頁數呈現等問題是否因 `ServicesBuilder()` 空物件導致，若有需要，評估是否用反射取得原始 `servicesBuilder` 或僅複製必要的服務。
3. **封面單頁顯示功能**：依使用者需求，新增「封面獨立顯示」開關（比照 PDF 既有功能）。
4. **更新 Issue 16 狀態**：Issue 16 的根因已確認（Readium 獨立判讀 metadata），替代方案已驗證可行（`Publication.Builder` 重建），可進入正式實作。

---

## 7. 相關文件

- `docs/epics/epic-18-reader-device-qa/plans/plan-issue-18.md` — 本 Spike 計劃
- `docs/epics/epic-18-reader-device-qa/design.md` — Issue 16/17/18 Discovery
- `docs/epics/epic-18-reader-device-qa/issues.md` — Issue 16/17/18 狀態
- `docs/epics/epic-18-reader-device-qa/reviews/spike-issue16-fxl-metadata-override.md` — Issue 17 Spike 報告（格式參考）
