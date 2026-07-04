# Review 報告：Issue 1 實作審查

本報告針對 `worktree-epic-0-issue-1` 分支上，初始化 Flutter 專案與最小導航外殼的實作進行審查與記錄。

- **專案名稱**：elinkBook
- **工作區路徑**：`docs/epics/epic-0-skeleton/reviews/review-issue-1.md`
- **對應計畫**：[plan-issue-1.md](../plans/plan-issue-1.md)
- **審查 Git 範圍**：`dd9b6d2` 到 `b36b844`
- **最新修正提交**：`5d5282a`（修正 `android:label` 大小寫）

---

## 審查結論

### 1. 優點 (Strengths)
- **與計畫高度對齊**：完全落實了 `plan-issue-1.md` 中的所有任務步驟，包括 Android `minSdk = 21` 與套件包名設定。
- **測試覆蓋率與質量佳**：針對 `LibraryScreen`、`SettingsScreen` 各自撰寫了獨立的 UI 測試，並有獨立的導航測試 `navigation_test.dart`。導航測試中使用了 `BackButton` 與 `pumpAndSettle()` 等待動畫，以提升測試強健度。
- **專案結構乾淨**：沒有遺留任何 `flutter create` 產生的預設計數器範例代碼，`main.dart` 順利將 `LibraryScreen` 作為首頁。

### 2. 發現的問題 (Issues)

#### Critical (Must Fix)
- 無

#### Important (Should Fix)
- 無

#### Minor (Nice to Have)
- **[待修正]** File: [AndroidManifest.xml](../../../../app/android/app/src/main/AndroidManifest.xml#L3)
  - **問題**：`android:label` 的值為 `"elinkbook"`。
  - **說明**：為符合 PRD 規格的名稱 `"elinkBook"`，並利於在 Android 裝置上顯示正確的大寫名稱，建議將其改為 `"elinkBook"`。
  - **修正狀態**：✅ 已修正（commit `5d5282a`），改為 `"elinkBook"`，`flutter analyze`/`flutter test` 皆重新驗證通過。

---

## 改進建議 (Recommendations)
1. **導航擴充性**：目前的導航直接使用 `Navigator.of(context).push(MaterialPageRoute(...))`。這在目前的最小導航殼中是足夠的（符合 YAGNI 原則）。不過，未來隨著畫面增加（例如開書畫面 `ReaderScreen` 等），可以考慮封裝一個簡單的 `AppRoutes` 類別或使用命名路由，以維持 `main.dart` 和各畫面的清晰度。
2. **國際化 (i18n)**：目前所有使用者可見文字皆以正體中文硬編碼（Hardcoded）在代碼中。雖然這符合目前的專案語言慣例，但隨著專案規模成長，未來可能需要導入 `flutter_localizations`。可在後續 Epic 規劃相關工作。

---

## 最終評估 (Assessment)

**Ready to merge: Yes**

**評估說明**：
實作程式碼乾淨且完全契合計畫，測試覆蓋完整。唯一的 Minor 建議（應用程式 Label 大小寫）已修正並重新驗證，無其他影響合併的阻礙。
