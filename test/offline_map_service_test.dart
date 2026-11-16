import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:tunga/services/offline_map_service.dart';

class _FakePathProviderPlatform extends PathProviderPlatform {
  _FakePathProviderPlatform(this.cachePath);

  final String cachePath;

  @override
  Future<String?> getApplicationCachePath() async => cachePath;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('OfflineMapService tile cache', () {
    late Directory temporaryDirectory;
    late PathProviderPlatform originalPathProvider;

    setUp(() async {
      originalPathProvider = PathProviderPlatform.instance;
      temporaryDirectory = await Directory.systemTemp.createTemp(
        'offline_map_service_test_',
      );
      PathProviderPlatform.instance =
          _FakePathProviderPlatform(temporaryDirectory.path);
    });

    tearDown(() async {
      PathProviderPlatform.instance = originalPathProvider;
      if (await temporaryDirectory.exists()) {
        await temporaryDirectory.delete(recursive: true);
      }
    });

    test('tilePath builds the zoom/x/y PNG path', () {
      expect(
        OfflineMapService.tilePath('/cache/offline_maps', 12, 34, 8),
        '/cache/offline_maps/8/12/34.png',
      );
    });

    test('isTileCached reports whether the matching tile file exists', () async {
      final service = OfflineMapService();

      expect(await service.isTileCached(12, 34, 8), isFalse);

      final tile = File(
        OfflineMapService.tilePath(
          '${temporaryDirectory.path}/offline_maps',
          12,
          34,
          8,
        ),
      );
      await tile.parent.create(recursive: true);
      await tile.writeAsBytes([1, 2, 3]);

      expect(await service.isTileCached(12, 34, 8), isTrue);
      expect(await service.isTileCached(12, 35, 8), isFalse);
    });
  });
}
