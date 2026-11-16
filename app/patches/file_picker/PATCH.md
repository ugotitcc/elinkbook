# Local Patch: file_picker 11.0.3

## 問題

`file_picker` 11.0.3 在 AGP ≥ 9 時將 `isAgp9OrAbove` 判為 `true` 而跳過套用 Kotlin Gradle Plugin（`org.jetbrains.kotlin.android`），預期由 AGP 9 built-in Kotlin 編譯；但本專案因尚有其他外掛未遷移而保留 `android.builtInKotlin=false`，導致 `FilePickerPlugin` 未被編譯而建置失敗。

## 修正

將 `android/build.gradle` 的 `isAgp9OrAbove` 固定為 `false`，強制套用 KGP 編譯 Kotlin 原始碼：

```groovy
def isAgp9OrAbove = false // 本地修補：本專案 android.builtInKotlin=false，Kotlin 原始碼須由 KGP 編譯
```

## 檔案位置

- `android/build.gradle:26`

## 使用方式

透過 `pubspec.yaml` 的 `dependency_overrides` 套用：

```yaml
dependency_overrides:
  file_picker:
    path: patches/file_picker
```

## 移除條件

所有 KGP 外掛遷移完成並將 `app/android/gradle.properties` 改回 `android.builtInKotlin=true` 後，或 `file_picker` 升版後在 `builtInKotlin=false` 下也能編譯時，即可移除此本地修補。

## 參考

- Epic: `docs/epics/epic-66-windows-port/issues.md`（Issue 17）
- 建立日期: 2026-11-16
