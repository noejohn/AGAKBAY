import 'package:flutter/material.dart';
import 'package:tunga/services/offline_map_service.dart';
import 'package:tunga/services/offline_trail_service.dart';
import 'package:tunga/widgets/offline_map_widget.dart';

/// Example usage of offline map features in the Tunga app
class OfflineMapExampleScreen extends StatefulWidget {
  const OfflineMapExampleScreen({super.key});

  @override
  State<OfflineMapExampleScreen> createState() =>
      _OfflineMapExampleScreenState();
}

class _OfflineMapExampleScreenState extends State<OfflineMapExampleScreen> {
  late OfflineMapService _mapService;
  late OfflineTrailService _trailService;
  bool _isLoading = false;
  String _status = 'Initializing...';

  @override
  void initState() {
    super.initState();
    _mapService = OfflineMapService();
    _trailService = OfflineTrailService();
    _initializeServices();
  }

  Future<void> _initializeServices() async {
    try {
      setState(() => _status = 'Initializing services...');
      await _mapService.initialize();
      await _trailService.initialize();

      setState(() => _status = 'Ready to use offline maps');

      // Pre-cache a sample trail from assets
      await _cacheSampleTrail();
    } catch (e) {
      setState(() => _status = 'Error: $e');
    }
  }

  Future<void> _cacheSampleTrail() async {
    try {
      // This example assumes you have a GPX file in assets/trails/
      // In real implementation, you would use DefaultAssetBundle to load it
      setState(() {
        _isLoading = true;
        _status = 'Caching sample trail...';
      });

      // Example GPX content (simplified Mt. Apo trail)
      final gpxContent = '''<?xml version="1.0" encoding="UTF-8"?>
<gpx version="1.1" creator="Tunga App">
  <metadata>
    <name>Mt. Apo Trail</name>
    <desc>Mount Apo hiking trail in Davao</desc>
  </metadata>
  <trk>
    <name>Mt. Apo Summit Trail</name>
    <trkseg>
      <trkpt lat="6.9271" lon="121.7151">
        <ele>1235</ele>
        <time>2024-01-01T08:00:00Z</time>
      </trkpt>
      <trkpt lat="6.9285" lon="121.7165">
        <ele>1450</ele>
        <time>2024-01-01T09:15:00Z</time>
      </trkpt>
      <trkpt lat="6.9310" lon="121.7180">
        <ele>1850</ele>
        <time>2024-01-01T10:30:00Z</time>
      </trkpt>
      <trkpt lat="6.9340" lon="121.7200">
        <ele>2400</ele>
        <time>2024-01-01T12:00:00Z</time>
      </trkpt>
      <trkpt lat="6.9355" lon="121.7210">
        <ele>2956</ele>
        <time>2024-01-01T13:45:00Z</time>
      </trkpt>
    </trkseg>
  </trk>
</gpx>''';

      final trail = await _trailService.cacheTrailFromGpx(
        trailId: 'mt_apo_summit',
        trailName: 'Mt. Apo Summit Trail',
        gpxContent: gpxContent,
        description: 'Main trail to Mt. Apo summit',
        difficulty: 4.5,
        duration: 8.0,
      );

      setState(
        () => _status =
            'Cached trail: ${trail.name} (${trail.distance.toStringAsFixed(2)} km)',
      );
    } catch (e) {
      setState(() => _status = 'Error caching trail: $e');
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  Future<void> _displayCachedTrail() async {
    try {
      final trail = await _trailService.getCachedTrail('mt_apo_summit');

      if (trail == null) {
        setState(
          () => _status = 'Trail not found. Please cache a trail first.',
        );
        return;
      }

      if (!mounted) return;

      // Navigate to trail display screen
      Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (context) => TrailDisplayScreen(trail: trail),
        ),
      );
    } catch (e) {
      setState(() => _status = 'Error loading trail: $e');
    }
  }

  Future<void> _downloadMapTiles() async {
    try {
      setState(() {
        _isLoading = true;
        _status = 'Checking connection...';
      });

      final hasConnection = await _mapService.hasNetworkConnection();
      if (!hasConnection) {
        setState(() => _status = 'No internet connection');
        return;
      }

      setState(() => _status = 'Downloading map tiles...');

      // Download tiles for Mt. Apo region
      final downloaded = await _mapService.preCacheTiles(
        bounds: {
          'minLat': 6.8,
          'maxLat': 7.0,
          'minLng': 121.6,
          'maxLng': 121.8,
        },
        zoomLevels: [10, 11, 12, 13],
        onProgress: (downloaded, total) {
          setState(() => _status = 'Downloaded: $downloaded / $total tiles');
        },
      );

      setState(() => _status = 'Successfully downloaded $downloaded tiles');
    } catch (e) {
      setState(() => _status = 'Error downloading tiles: $e');
    } finally {
      setState(() => _isLoading = false);
    }
  }

  Future<void> _showCacheStats() async {
    try {
      final mapSize = await _mapService.getCacheSizeInMB();
      final trailSize = await _trailService.getCacheSizeInMB();
      final trails = await _trailService.getAllCachedTrails();

      if (!mounted) return;

      showDialog<void>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Cache Statistics'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Map tiles: ${mapSize.toStringAsFixed(2)} MB'),
              Text('Trail data: ${trailSize.toStringAsFixed(2)} MB'),
              Text('Cached trails: ${trails.length}'),
              const SizedBox(height: 12),
              if (trails.isNotEmpty) ...[
                const Text('Trails:'),
                ...trails.map(
                  (t) => Text(
                    '  • ${t.name}: ${t.distance.toStringAsFixed(2)} km',
                  ),
                ),
              ],
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Close'),
            ),
          ],
        ),
      );
    } catch (e) {
      setState(() => _status = 'Error getting stats: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    const accentColor = Color(0xFF7FE0A9);
    const statusBackground = Color(0xFF12231A);
    const statusBorder = Color(0xFF2F8C5A);
    const statusText = Color(0xFFF0FFF7);
    const secondaryText = Color(0xFFC4D3C9);

    return Scaffold(
      appBar: AppBar(title: const Text('Offline Maps Demo'), centerTitle: true),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16.0),
        child: SafeArea(
          top: false,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: statusBackground,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: statusBorder),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _isLoading
                        ? const SizedBox(
                            width: 22,
                            height: 22,
                            child: CircularProgressIndicator(
                              strokeWidth: 2.4,
                              color: accentColor,
                            ),
                          )
                        : const Icon(
                            Icons.offline_pin,
                            color: accentColor,
                            size: 24,
                          ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'Status',
                            style: TextStyle(
                              color: secondaryText,
                              fontWeight: FontWeight.w700,
                              fontSize: 12,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            _status,
                            style: const TextStyle(
                              color: statusText,
                              fontSize: 14,
                              height: 1.35,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 24),
              Text('Actions', style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 12),
              _buildActionButton(
                onPressed: _isLoading ? null : _cacheSampleTrail,
                icon: Icons.download,
                label: 'Cache Sample Trail',
              ),
              _buildActionButton(
                onPressed: _isLoading ? null : _displayCachedTrail,
                icon: Icons.map,
                label: 'Display Cached Trail',
              ),
              _buildActionButton(
                onPressed: _isLoading ? null : _downloadMapTiles,
                icon: Icons.cloud_download,
                label: 'Download Map Region',
              ),
              _buildActionButton(
                onPressed: _isLoading ? null : _showCacheStats,
                icon: Icons.info,
                label: 'View Cache Stats',
              ),
              const SizedBox(height: 24),
              Text(
                'Cached Content',
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: 12),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Text(
                  'Sample trail: Mt. Apo Summit Trail\nMap region: Mt. Apo area\nOffline mode: enabled after caching',
                  style: TextStyle(fontSize: 13, height: 1.7),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildActionButton({
    required VoidCallback? onPressed,
    required IconData icon,
    required String label,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: SizedBox(
        width: double.infinity,
        height: 54,
        child: ElevatedButton.icon(
          onPressed: onPressed,
          icon: Icon(icon),
          label: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis),
        ),
      ),
    );
  }
}

/// Screen to display a cached trail on an offline map
class TrailDisplayScreen extends StatefulWidget {
  final CachedTrail trail;

  const TrailDisplayScreen({super.key, required this.trail});

  @override
  State<TrailDisplayScreen> createState() => _TrailDisplayScreenState();
}

class _TrailDisplayScreenState extends State<TrailDisplayScreen> {
  @override
  Widget build(BuildContext context) {
    final trackPoints = widget.trail.trackPoints;

    if (trackPoints.isEmpty) {
      return Scaffold(
        appBar: AppBar(title: const Text('Trail')),
        body: const Center(child: Text('No track points found')),
      );
    }

    // Convert track points to map format
    final mapPoints = trackPoints
        .map<Map<String, double>>(
          (p) => {'latitude': p.latitude, 'longitude': p.longitude},
        )
        .toList(growable: false);

    // Create polyline and markers
    final polyline = TrailPolylineConverter.convertToPolyline(mapPoints);
    final markers = TrailPolylineConverter.convertToMarkers(mapPoints);

    return Scaffold(
      appBar: AppBar(title: Text(widget.trail.name), centerTitle: true),
      body: Column(
        children: [
          Expanded(
            flex: 2,
            child: OfflineMapWidget(
              initialLatitude: trackPoints.first.latitude,
              initialLongitude: trackPoints.first.longitude,
              initialZoom: 12,
              markers: markers,
              polylines: [polyline],
            ),
          ),
          Expanded(
            flex: 1,
            child: Container(
              color: Colors.grey[100],
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      widget.trail.name,
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                    const SizedBox(height: 12),
                    _buildTrailStat(
                      'Distance',
                      '${widget.trail.distance.toStringAsFixed(2)} km',
                      Icons.straighten,
                    ),
                    _buildTrailStat(
                      'Elevation Gain',
                      '${widget.trail.elevationGain.toStringAsFixed(0)} m',
                      Icons.trending_up,
                    ),
                    if (widget.trail.difficulty != null)
                      _buildTrailStat(
                        'Difficulty',
                        '${widget.trail.difficulty}/5.0',
                        Icons.star,
                      ),
                    if (widget.trail.duration != null)
                      _buildTrailStat(
                        'Estimated Duration',
                        '${widget.trail.duration?.toStringAsFixed(1)} hours',
                        Icons.access_time,
                      ),
                    if (widget.trail.description.isNotEmpty) ...[
                      const SizedBox(height: 12),
                      Text(
                        'Description',
                        style: Theme.of(context).textTheme.labelMedium,
                      ),
                      const SizedBox(height: 4),
                      Text(widget.trail.description),
                    ],
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTrailStat(String label, String value, IconData icon) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        children: [
          Icon(icon, color: const Color(0xFF0F5A3D), size: 20),
          const SizedBox(width: 12),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: const TextStyle(fontSize: 12, color: Colors.grey),
              ),
              Text(value, style: const TextStyle(fontWeight: FontWeight.bold)),
            ],
          ),
        ],
      ),
    );
  }
}
