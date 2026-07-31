# Local Patch: flutter_inappwebview_android 1.1.3

## 問題

`flutter_inappwebview_android` 1.1.3 的 `AndroidInternalStoragePathHandler.toMap()` 存在無限遞迴 bug：

```dart
// 原始碼（有問題）
return {...toMap(), 'directory': directory};  // toMap() 呼叫自己
```

導致 `InternalStoragePathHandler` 一旦被使用就會 `StackOverflowError`。

## 修正

```dart
// 修正後
return {'type': type, 'path': path, 'directory': directory};
```

## 檔案位置

- `lib/src/webview_asset_loader.dart:195-198`

## 使用方式

透過 `pubspec.yaml` 的 `dependency_overrides` 套用：

```yaml
dependency_overrides:
  flutter_inappwebview_android:
    path: patches/flutter_inappwebview_android
```

## 移除條件

上游 `flutter_inappwebview_android` 發布包含修正的穩定版本後，升級並移除此目錄。

## 參考

- Issue: flutter_inappwebview_android#1982 (待確認)
- 建立日期: 2026-08-01
