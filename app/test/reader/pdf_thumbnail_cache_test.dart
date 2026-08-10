import 'package:flutter_test/flutter_test.dart';
import 'package:elinkbook/reader/pdf_thumbnail_cache.dart';

class _FakeImage {
  bool disposed = false;
  void dispose() => disposed = true;
}

void main() {
  PdfThumbnailCache<_FakeImage> makeCache({required int maxSize}) {
    return PdfThumbnailCache<_FakeImage>(
      maxSize: maxSize,
      dispose: (image) => image.dispose(),
    );
  }

  test('get() 對不存在的鍵回傳 null', () {
    final cache = makeCache(maxSize: 3);
    expect(cache.get(0), isNull);
  });

  test('put() 後 get() 可取回同一個值', () {
    final cache = makeCache(maxSize: 3);
    final image = _FakeImage();
    cache.put(0, image);
    expect(cache.get(0), same(image));
  });

  test('超過 maxSize 時，最舊未被 get() 觸碰過的項目會被 dispose 並移除', () {
    final cache = makeCache(maxSize: 2);
    final img0 = _FakeImage();
    final img1 = _FakeImage();
    final img2 = _FakeImage();
    cache.put(0, img0);
    cache.put(1, img1);
    cache.put(2, img2); // 超過上限 2，應淘汰最舊的 img0。

    expect(img0.disposed, isTrue);
    expect(cache.get(0), isNull);
    expect(cache.length, 2);
  });

  test('get() 會將項目標記為最近使用，延後其被淘汰的順序', () {
    final cache = makeCache(maxSize: 2);
    final img0 = _FakeImage();
    final img1 = _FakeImage();
    final img2 = _FakeImage();
    cache.put(0, img0);
    cache.put(1, img1);
    cache.get(0); // touch img0，img1 變成最舊。
    cache.put(2, img2); // 應淘汰 img1，不是 img0。

    expect(img1.disposed, isTrue);
    expect(img0.disposed, isFalse);
    expect(cache.get(0), same(img0));
  });

  test('put() 對已存在的鍵覆寫時，舊值會被 dispose', () {
    final cache = makeCache(maxSize: 3);
    final oldImg = _FakeImage();
    final newImg = _FakeImage();
    cache.put(0, oldImg);
    cache.put(0, newImg);

    expect(oldImg.disposed, isTrue);
    expect(cache.get(0), same(newImg));
  });

  test('contains() 正確反映鍵是否存在', () {
    final cache = makeCache(maxSize: 3);
    expect(cache.contains(0), isFalse);
    cache.put(0, _FakeImage());
    expect(cache.contains(0), isTrue);
  });

  test('clear() 釋放所有項目並清空', () {
    final cache = makeCache(maxSize: 3);
    final img0 = _FakeImage();
    final img1 = _FakeImage();
    cache.put(0, img0);
    cache.put(1, img1);
    cache.clear();

    expect(img0.disposed, isTrue);
    expect(img1.disposed, isTrue);
    expect(cache.length, 0);
  });
}
