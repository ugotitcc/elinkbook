// Copyright (c) 2024 elinkBook. All rights reserved.
// Use of this source code is governed by a MIT-style license that can be
// found in the LICENSE file.

import 'package:flutter_test/flutter_test.dart';
import 'package:elinkbook/remote/remote_catalog_dependencies.dart';
import 'package:elinkbook/remote/opds_client.dart';

import '../support/fake_fingerprint_computer.dart';
import '../support/fake_opds_client.dart';
import '../support/fake_remote_thumbnail_cache.dart';

void main() {
  test('RemoteCatalogDependencies 原樣持有三個注入的依賴', () {
    final thumbnailCache = FakeRemoteThumbnailCache();
    Future<String> computeFingerprint(String path, dynamic format) async =>
        'test-fingerprint';
    OpdsClient createClient() => FakeOpdsClient();

    final dependencies = RemoteCatalogDependencies(
      computeFingerprint: computeFingerprint,
      thumbnailCache: thumbnailCache,
      createOpdsClient: createClient,
    );

    expect(dependencies.computeFingerprint, same(computeFingerprint));
    expect(dependencies.thumbnailCache, same(thumbnailCache));
    expect(dependencies.createOpdsClient, same(createClient));
  });
}
