# Offline Map Support Integration Guide

This guide explains how to integrate offline map support into your Tunga hiking app.

## Features Implemented

### 1. **Offline Map Tile Caching**
   - Downloads OpenStreetMap tiles for offline use
   - Caches up to 5000 tiles
   - Auto-clears old cached data after 30 days
   - Supports zoom levels 5-18

### 2. **GPX Trail Caching**
   - Parses and caches GPX trail files
   - Calculates trail statistics (distance, elevation gain)
   - Stores trail metadata for quick retrieval
   - Supports multiple trails in cache

### 3. **Offline Map Display**
   - Flutter Map widget for offline rendering
   - Trail visualization with markers and polylines
   - Start/end/intermediate waypoint markers

### 4. **Offline Map Manager UI**
   - View cached map and trail sizes
   - Download map regions
   - Delete individual trails
   - Clear all caches
   - Network connectivity indicator

## Files Added

```
lib/
  services/
    offline_map_service.dart      # Map tile caching
    offline_trail_service.dart    # GPX parsing and caching
  widgets/
    offline_map_widget.dart       # Map display widget
    offline_map_manager.dart      # Cache management UI
```

## How to Use

### 1. Initialize Services at App Startup

In your `main.dart` or app initialization:

```dart
import 'package:tunga/services/offline_map_service.dart';
import 'package:tunga/services/offline_trail_service.dart';

// In your app init:
final offlineMapService = OfflineMapService();
final offlineTrailService = OfflineTrailService();

await offlineMapService.initialize();
await offlineTrailService.initialize();
```

### 2. Display Offline Maps

```dart
import 'package:tunga/widgets/offline_map_widget.dart';

// Use the widget
OfflineMapWidget(
  initialLatitude: 6.9271,
  initialLongitude: 121.7151,
  initialZoom: 12,
  markers: myMarkers,
  polylines: myPolylines,
)
```

### 3. Cache Trail Files

```dart
// From GPX file path
await offlineTrailService.cacheTrailFromFile(
  trailId: 'mt_apo',
  trailName: 'Mt. Apo',
  filePath: 'assets/trails/mt_apo.gpx',
  description: 'Mount Apo trail',
  difficulty: 4.5,
  duration: 8.0,
);

// Or from GPX content
await offlineTrailService.cacheTrailFromGpx(
  trailId: 'sample_trail',
  trailName: 'Sample Trail',
  gpxContent: gpxXmlString,
);
```

### 4. Retrieve Cached Trail Data

```dart
// Get specific trail
final trail = await offlineTrailService.getCachedTrail('mt_apo');
print('Trail distance: ${trail?.distance} km');
print('Elevation gain: ${trail?.elevationGain} m');

// Get all cached trails
final trails = await offlineTrailService.getAllCachedTrails();
```

### 5. Convert Trail to Map Display

```dart
import 'package:tunga/widgets/offline_map_widget.dart';

final trail = await offlineTrailService.getCachedTrail('mt_apo');
if (trail != null) {
  final trackPoints = trail.trackPoints
      .map((p) => {'latitude': p.latitude, 'longitude': p.longitude})
      .toList();

  final polyline = TrailPolylineConverter.convertToPolyline(trackPoints);
  final markers = TrailPolylineConverter.convertToMarkers(trackPoints);

  // Use in OfflineMapWidget
  OfflineMapWidget(
    initialLatitude: trail.trackPoints.first.latitude,
    initialLongitude: trail.trackPoints.first.longitude,
    polylines: [polyline],
    markers: markers,
  )
}
```

### 6. Manage Offline Cache

```dart
import 'package:tunga/widgets/offline_map_manager.dart';

// Add to settings/options screen
class SettingsScreen extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: OfflineMapManager(),
    );
  }
}
```

## Cache Statistics

```dart
// Check map cache size
final mapSizeMB = await offlineMapService.getCacheSizeInMB();
print('Map cache: ${mapSizeMB.toStringAsFixed(2)} MB');

// Check trail cache size
final trailSizeMB = await offlineTrailService.getCacheSizeInMB();
print('Trail cache: ${trailSizeMB.toStringAsFixed(2)} MB');

// Check network connection
final hasConnection = await offlineMapService.hasNetworkConnection();
```

## Clear Caches

```dart
// Clear map cache
await offlineMapService.clearCache();

// Clear trail cache
await offlineTrailService.clearCache();

// Delete specific trail
await offlineTrailService.deleteCachedTrail('trail_id');
```

## Pre-Download Map Regions

```dart
// Download map tiles for offline use
// Best done before hiking trips
final downloaded = await offlineMapService.preCacheTiles(
  bounds: {
    'minLat': 6.5,
    'maxLat': 7.5,
    'minLng': 121.0,
    'maxLng': 122.0,
  },
  zoomLevels: [10, 11, 12, 13],
  onProgress: (downloaded, total) {
    print('Cached: $downloaded / $total tiles');
  },
);
```

## Network Connectivity

The app automatically detects network availability and can show appropriate UI:

```dart
final hasConnection = await offlineMapService.hasNetworkConnection();

if (!hasConnection) {
  // Show offline mode UI
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(content: Text('Using cached maps - offline mode')),
  );
}
```

## Integration with Existing Dashboard

To add offline map management to your dashboard:

1. Add a "Settings" or "Offline Maps" tab to the bottom navigation
2. Use `OfflineMapManager` widget in that tab
3. Initialize services in the app's main widget

## GPX File Support

The app supports standard GPX files with:
- Track points (trkpt)
- Latitude/longitude coordinates
- Elevation data (optional)
- Timestamps (optional)

Example GPX structure:
```xml
<?xml version="1.0"?>
<gpx version="1.1">
  <trk>
    <trkseg>
      <trkpt lat="6.9271" lon="121.7151">
        <ele>1234.5</ele>
        <time>2024-01-01T08:00:00Z</time>
      </trkpt>
      <!-- more points -->
    </trkseg>
  </trk>
</gpx>
```

## Performance Tips

1. **Pre-download before hiking**: Download maps for your intended hiking area before going offline
2. **Limit zoom levels**: Cache only zoom levels 10-13 to save space
3. **Regional caching**: Download specific regions rather than entire areas
4. **Clear old caches**: Regularly clear old cached data to free space
5. **Use trail pre-caching**: Cache GPX files at trip planning time

## Troubleshooting

### Maps not displaying offline
- Ensure tiles were successfully downloaded
- Check available storage space
- Verify cache hasn't been cleared

### GPX files not parsing
- Ensure GPX file is valid XML
- Check file contains trkpt elements
- Verify coordinate format is correct

### Network detection not working
- Check device network settings
- Ensure connectivity check service has permissions

## Future Enhancements

Potential additions:
- Tile download progress UI
- Map region selection UI
- Offline routing/navigation
- Trail difficulty filtering
- Search within cached trails
- Estimated hike time calculation
