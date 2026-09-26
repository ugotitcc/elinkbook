import 'app_font.dart';

/// 字型下載服務的基底網址（epic-49，見 docs/adr/0035-downloadable-fonts-via-r2-worker.md）。
///
/// Issue 2 部署的 Cloudflare Worker（`workers.dev` 網址）。日後改用自訂網域時，
/// 舊網址仍會保留，已安裝的舊版 App 不受影響。
/// 必須以斜線結尾，[Uri.resolve] 才會把發布路徑接在後面而不是取代最後一段。
const String kFontDownloadBaseUrl = 'https://elinkbook-fonts.huthief.workers.dev/';

/// 一款可下載字型的發布資訊。數值必須和 repo 根目錄 `fonts-cdn/fonts.json` 一致
/// （Issue 4 有 Dart 測試比對）；已發布的路徑永遠不覆蓋，改版時改用新的版本路徑。
class FontDownloadSpec {
  /// 相對於基底網址的發布路徑，也是本機存放目錄下的相對路徑，例如 `v1/SourceHanSansTC-VF.ttf`。
  final String publishPath;

  /// 檔案位元組大小；伺服器沒回傳 Content-Length 時用來計算進度，也用於畫面顯示。
  final int sizeBytes;

  /// 檔案內容的 SHA-256（小寫十六進位），下載完成後必須相符才算成功。
  final String sha256;

  const FontDownloadSpec({
    required this.publishPath,
    required this.sizeBytes,
    required this.sha256,
  });
}

/// 回傳 [font] 的發布資訊。用 exhaustive switch：新增或恢復字型時少寫一項就會編譯失敗。
FontDownloadSpec fontDownloadSpecOf(AppFont font) {
  switch (font) {
    case AppFont.sourceHanSans:
      return const FontDownloadSpec(
        publishPath: 'v1/SourceHanSansTC-VF.ttf',
        sizeBytes: 36034016,
        sha256: '1a273a56aa47250c7af95e461ee0c8236c60d7141e14a37bd18baccb1e851b19',
      );
    case AppFont.sourceHanSerif:
      return const FontDownloadSpec(
        publishPath: 'v1/SourceHanSerifTC-VF.ttf',
        sizeBytes: 59898316,
        sha256: '71354ed752104c8a3cbcff18943c6110d179d01cc6eaaf1aff7ea14c4a447879',
      );
    case AppFont.guanKiapTsingKhai:
      return const FontDownloadSpec(
        publishPath: 'v1/GuanKiapTsingKhai.ttf',
        sizeBytes: 14675776,
        sha256: '758632243c499e431fd0c847f5e8c431acf59a9b41a26237a819466139994d38',
      );
    case AppFont.taiwanPearl:
      return const FontDownloadSpec(
        publishPath: 'v1/TaiwanPearl-Regular.ttf',
        sizeBytes: 21704488,
        sha256: '51b3c9a4ab1b6b45dcdad7c5ae93386aea399fd3dabb85d2ac41110dc57f211d',
      );
    case AppFont.genRyuMinTW:
      return const FontDownloadSpec(
        publishPath: 'v1/GenRyuMinTW-Regular.ttf',
        sizeBytes: 15976964,
        sha256: '9178c199d633075b8bb91902216c3e1bc977a11fde12471a2c9a250434402927',
      );
  }
}
