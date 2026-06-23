import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';

/// Service for managing offline map support
class OfflineMapService {
  static const String tileUrlTemplate =
      'https://tile.openstreetmap.org/{z}/{x}/{y}.png';

  late Directory _offlineMapDir;
  bool _isInitialized = false;

  static Future<Directory> getTileCacheDirectory() async {
    final cacheDir = await getApplicationCacheDirectory();
    return Directory('${cacheDir.path}/offline_maps');
  }

  static String tilePath(String cacheDirectoryPath, int x, int y, int z) {
    return '$cacheDirectoryPath/$z/$x/$y.png';
  }

  /// Initialize the offline map service
  Future<void> initialize() async {
    if (_isInitialized) return;

    try {
      _offlineMapDir = await getTileCacheDirectory();

      if (!await _offlineMapDir.exists()) {
        await _offlineMapDir.create(recursive: true);
      }

      _isInitialized = true;
    } catch (e) {
      debugPrint('Error initializing offline map service: $e');
    }
  }

  /// Get cached tile or fetch from network
  Future<File> getTile(int x, int y, int z) async {
    if (!_isInitialized) await initialize();

    try {
      final file = File(tilePath(_offlineMapDir.path, x, y, z));
      if (await file.exists()) {
        return file;
      }

      final response = await http.get(Uri.parse(_generateTileUrl(x, y, z)));
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw HttpException(
          'Tile request failed with status ${response.statusCode}',
          uri: Uri.parse(_generateTileUrl(x, y, z)),
        );
      }

      await file.parent.create(recursive: true);
      return file.writeAsBytes(response.bodyBytes, flush: true);
    } catch (e) {
      debugPrint('Error getting tile: $e');
      rethrow;
    }
  }

  /// Pre-download map tiles for offline use
  /// [bounds] should be a map with keys: 'minLat', 'maxLat', 'minLng', 'maxLng'
  /// [zoomLevels] list of zoom levels to cache (e.g., [10, 11, 12, 13])
  Future<int> preCacheTiles({
    required Map<String, double> bounds,
    required List<int> zoomLevels,
    void Function(int downloaded, int total)? onProgress,
  }) async {
    if (!_isInitialized) await initialize();

    int totalDownloaded = 0;
    int totalTiles = 0;

    try {
      for (final z in zoomLevels) {
        final tiles = _getTilesForBounds(
          bounds['minLat']!,
          bounds['maxLat']!,
          bounds['minLng']!,
          bounds['maxLng']!,
          z,
        );

        totalTiles += tiles.length;

        for (final tile in tiles) {
          try {
            await getTile(tile['x']!, tile['y']!, z);
            totalDownloaded++;
            onProgress?.call(totalDownloaded, totalTiles);
          } catch (e) {
            debugPrint('Failed to cache tile: $e');
          }
        }
      }
    } catch (e) {
      debugPrint('Error pre-caching tiles: $e');
    }

    return totalDownloaded;
  }

  /// Generate tile URL for OpenStreetMap
  String _generateTileUrl(int x, int y, int z) {
    return tileUrlTemplate
        .replaceAll('{z}', z.toString())
        .replaceAll('{x}', x.toString())
        .replaceAll('{y}', y.toString());
  }

  /// Get tiles that cover a geographic bounding box
  List<Map<String, int>> _getTilesForBounds(
    double minLat,
    double maxLat,
    double minLng,
    double maxLng,
    int z,
  ) {
    final tiles = <Map<String, int>>[];
    final minTile = _latLngToTile(maxLat, minLng, z);
    final maxTile = _latLngToTile(minLat, maxLng, z);

    for (int x = minTile['x']!; x <= maxTile['x']!; x++) {
      for (int y = minTile['y']!; y <= maxTile['y']!; y++) {
        tiles.add({'x': x, 'y': y});
      }
    }

    return tiles;
  }

  /// Convert latitude/longitude to tile coordinates
  Map<String, int> _latLngToTile(double lat, double lng, int z) {
    final n = math.pow(2, z).toInt();
    final x = (((lng + 180) / 360) * n).floor();
    final latRad = lat * (math.pi / 180);
    final y =
        (((1 - math.log(math.tan(latRad) + 1 / math.cos(latRad)) / math.pi) /
                    2) *
                n)
            .floor();

    return {'x': x, 'y': y};
  }

  /// Check if tile is cached
  Future<bool> isTileCached(int x, int y, int z) async {
    if (!_isInitialized) await initialize();

    try {
      return File(tilePath(_offlineMapDir.path, x, y, z)).exists();
    } catch (e) {
      return false;
    }
  }

  /// Get cache size in MB
  Future<double> getCacheSizeInMB() async {
    if (!_isInitialized) await initialize();

    try {
      if (!await _offlineMapDir.exists()) {
        return 0.0;
      }

      int totalSize = 0;
      await for (final file in _offlineMapDir.list(recursive: true)) {
        if (file is File) {
          totalSize += await file.length();
        }
      }

      return totalSize / (1024 * 1024); // Convert to MB
    } catch (e) {
      debugPrint('Error getting cache size: $e');
      return 0.0;
    }
  }

  /// Clear offline map cache
  Future<void> clearCache() async {
    if (!_isInitialized) await initialize();

    try {
      if (await _offlineMapDir.exists()) {
        await _offlineMapDir.delete(recursive: true);
      }
      await _offlineMapDir.create(recursive: true);
    } catch (e) {
      debugPrint('Error clearing cache: $e');
    }
  }

  /// Check network connectivity
  Future<bool> hasNetworkConnection() async {
    try {
      final result = await InternetAddress.lookup('google.com');
      return result.isNotEmpty && result[0].rawAddress.isNotEmpty;
    } catch (_) {
      return false;
    }
  }
}
