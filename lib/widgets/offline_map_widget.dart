import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:tunga/services/offline_map_service.dart';

/// Widget for displaying offline maps with cached tiles.
class OfflineMapWidget extends StatefulWidget {
  final double initialLatitude;
  final double initialLongitude;
  final double initialZoom;
  final List<Marker>? markers;
  final List<Polyline>? polylines;
  final VoidCallback? onMapReady;
  final bool showScaleLayer;
  final bool allowNetworkFallback;

  const OfflineMapWidget({
    super.key,
    required this.initialLatitude,
    required this.initialLongitude,
    this.initialZoom = 13,
    this.markers,
    this.polylines,
    this.onMapReady,
    this.showScaleLayer = true,
    this.allowNetworkFallback = true,
  });

  @override
  State<OfflineMapWidget> createState() => _OfflineMapWidgetState();
}

class _OfflineMapWidgetState extends State<OfflineMapWidget> {
  late MapController _mapController;
  String? _tileCacheDirectoryPath;

  @override
  void initState() {
    super.initState();
    _mapController = MapController();
    _loadTileCacheDirectory();
  }

  Future<void> _loadTileCacheDirectory() async {
    final directory = await OfflineMapService.getTileCacheDirectory();
    if (!mounted) return;
    setState(() {
      _tileCacheDirectoryPath = directory.path;
    });
  }

  @override
  void dispose() {
    _mapController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      color: const Color(0xFF07110D),
      child: FlutterMap(
        mapController: _mapController,
        options: MapOptions(
          initialCenter: LatLng(
            widget.initialLatitude,
            widget.initialLongitude,
          ),
          initialZoom: widget.initialZoom,
          maxZoom: 18,
          minZoom: 5,
          interactionOptions: const InteractionOptions(
            flags: InteractiveFlag.all,
          ),
          onMapReady: widget.onMapReady,
        ),
        children: [
          TileLayer(
            urlTemplate: OfflineMapService.tileUrlTemplate,
            userAgentPackageName: 'com.example.tunga',
            tileProvider: _tileCacheDirectoryPath == null
                ? widget.allowNetworkFallback
                      ? NetworkTileProvider()
                      : BlankTileProvider()
                : OfflineFirstTileProvider(
                    cacheDirectoryPath: _tileCacheDirectoryPath!,
                    allowNetworkFallback: widget.allowNetworkFallback,
                  ),
            additionalOptions: const {
              'maxZoom': '19',
              'attribution': 'OpenStreetMap contributors',
            },
          ),
          if (widget.markers != null) MarkerLayer(markers: widget.markers!),
          if (widget.polylines != null)
            PolylineLayer(polylines: widget.polylines!),
          if (widget.showScaleLayer)
            SimpleAttributionWidget(
              source: Text(
                'OpenStreetMap contributors',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: Colors.black,
                  backgroundColor: Colors.white70,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class BlankTileProvider extends TileProvider {
  @override
  ImageProvider getImage(TileCoordinates coordinates, TileLayer options) {
    return _TransparentTile.imageProvider;
  }
}

class OfflineFirstTileProvider extends TileProvider {
  final String cacheDirectoryPath;
  final bool allowNetworkFallback;

  OfflineFirstTileProvider({
    required this.cacheDirectoryPath,
    this.allowNetworkFallback = true,
    super.headers,
  });

  @override
  ImageProvider getImage(TileCoordinates coordinates, TileLayer options) {
    final z =
        (options.zoomOffset +
                (options.zoomReverse
                    ? options.maxZoom - coordinates.z.toDouble()
                    : coordinates.z.toDouble()))
            .round();
    final x = coordinates.x;
    final y = options.tms ? ((1 << z) - 1) - coordinates.y : coordinates.y;
    final cachedTile = File(
      OfflineMapService.tilePath(cacheDirectoryPath, x, y, z),
    );

    if (cachedTile.existsSync()) {
      return FileImage(cachedTile);
    }

    if (!allowNetworkFallback) {
      return _TransparentTile.imageProvider;
    }

    return NetworkImage(getTileUrl(coordinates, options), headers: headers);
  }
}

class _TransparentTile {
  static final ImageProvider imageProvider = MemoryImage(
    Uint8List.fromList(_bytes),
  );

  static const List<int> _bytes = [
    137,
    80,
    78,
    71,
    13,
    10,
    26,
    10,
    0,
    0,
    0,
    13,
    73,
    72,
    68,
    82,
    0,
    0,
    0,
    1,
    0,
    0,
    0,
    1,
    8,
    6,
    0,
    0,
    0,
    31,
    21,
    196,
    137,
    0,
    0,
    0,
    11,
    73,
    68,
    65,
    84,
    120,
    156,
    99,
    0,
    1,
    0,
    0,
    5,
    0,
    1,
    13,
    10,
    45,
    180,
    0,
    0,
    0,
    0,
    73,
    69,
    78,
    68,
    174,
    66,
    96,
    130,
  ];
}

/// Helper class to convert trail points to Polyline for map display.
class TrailPolylineConverter {
  /// Convert list of track points to a Polyline.
  static Polyline convertToPolyline(
    List<Map<String, double>> trackPoints, {
    Color color = const Color(0xFF0F5A3D),
    double strokeWidth = 3.0,
  }) {
    final points = trackPoints
        .map((point) => LatLng(point['latitude']!, point['longitude']!))
        .toList();

    return Polyline(points: points, color: color, strokeWidth: strokeWidth);
  }

  /// Convert trail points to markers (start, end, and intermediate points).
  static List<Marker> convertToMarkers(
    List<Map<String, double>> trackPoints, {
    bool showStartEndOnly = true,
    int intermediatePointInterval = 10,
  }) {
    if (trackPoints.isEmpty) return [];

    final markers = <Marker>[];

    final startPoint = trackPoints.first;
    markers.add(
      Marker(
        point: LatLng(startPoint['latitude']!, startPoint['longitude']!),
        child: const Icon(Icons.location_on, color: Colors.green, size: 30),
        rotate: true,
      ),
    );

    if (!showStartEndOnly) {
      for (
        int i = intermediatePointInterval;
        i < trackPoints.length - 1;
        i += intermediatePointInterval
      ) {
        final point = trackPoints[i];
        markers.add(
          Marker(
            point: LatLng(point['latitude']!, point['longitude']!),
            child: const Icon(Icons.place, color: Colors.blue, size: 20),
          ),
        );
      }
    }

    final endPoint = trackPoints.last;
    markers.add(
      Marker(
        point: LatLng(endPoint['latitude']!, endPoint['longitude']!),
        child: const Icon(Icons.location_on, color: Colors.red, size: 30),
      ),
    );

    return markers;
  }
}
