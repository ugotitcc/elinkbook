# ADR 0036：公開下載的 APK 用獨立的發佈金鑰，不沿用 Play 上傳金鑰

## 狀態

已採納（2026-10-01）

## 背景

App 同時走兩條散布路徑：Google Play（`.aab`，Play App Signing）與官網下載（APK，放在 GitHub Releases）。現有的上傳金鑰可以簽 APK，最省事。

但兩把金鑰的遺失後果不同：上傳金鑰遺失，可向 Google 申請重設；公開 APK 的簽章金鑰遺失，已安裝的使用者無法更新，只能解除安裝重裝。若共用同一把，重設上傳金鑰就會斷掉 APK 的更新鏈，一把金鑰出事也會同時影響兩條路徑。

## 決策

1. 另建「發佈金鑰」`elinkbook-release.jks`（alias `release`），**只簽公開下載的 APK**。
2. 「上傳金鑰」**只簽 `.aab`**。
3. 兩把金鑰各自備份。發佈金鑰至少保留兩份，其中一份離線。
4. 建置時用 `key.properties.upload`／`key.properties.release` 兩個檔案切換，不修改 `build.gradle.kts`。建完 APK 一律用 `apksigner` 比對指紋，抓出簽錯金鑰。

## 後果

- 商店版與 APK 版簽章不同，使用者無法互相覆蓋安裝，切換要先解除安裝。兩者的 applicationId 刻意維持同一個（`cc.ugotit.elinkbook`）：改後綴會動到建置設定與 OAuth，風險大於收益。
- 手動切換檔案有忘記換回的風險，SOP 以「建完立刻換回」與簽章指紋比對作為防線。
- 日後若上 F-Droid，會出現第三個簽章（F-Droid 自己的金鑰），三條路徑彼此都不能直接更新。
