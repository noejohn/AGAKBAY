import 'package:flutter/material.dart';
import '../services/offline_map_service.dart';
import '../services/offline_trail_service.dart';

/// Widget for managing offline map cache and trail downloads
class OfflineMapManager extends StatefulWidget {
  const OfflineMapManager({super.key});

  @override
  State<OfflineMapManager> createState() => _OfflineMapManagerState();
}

class _OfflineMapManagerState extends State<OfflineMapManager> {
  late OfflineMapService _mapService;
  late OfflineTrailService _trailService;
  double _mapCacheSizeMB = 0;
  double _trailCacheSizeMB = 0;
  List<String> _cachedTrails = [];
  bool _hasNetworkConnection = false;

  @override
  void initState() {
    super.initState();
    _mapService = OfflineMapService();
    _trailService = OfflineTrailService();
    _initializeServices();
  }

  Future<void> _initializeServices() async {
    await _mapService.initialize();
    await _trailService.initialize();
    await _refreshCacheInfo();
  }

  Future<void> _refreshCacheInfo() async {
    if (!mounted) return;

    try {
      final mapSize = await _mapService.getCacheSizeInMB();
      final trailSize = await _trailService.getCacheSizeInMB();
      final hasConnection = await _mapService.hasNetworkConnection();
      final trails = await _trailService.getAllCachedTrails();

      if (!mounted) return;

      setState(() {
        _mapCacheSizeMB = mapSize;
        _trailCacheSizeMB = trailSize;
        _hasNetworkConnection = hasConnection;
        _cachedTrails = trails.map((t) => t.id).toList();
      });
    } catch (e) {
      debugPrint('Error refreshing cache info: $e');
    }
  }

  Future<void> _clearMapCache() async {
    showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Clear Map Cache'),
        content: const Text(
          'This will remove all cached map tiles. You will need internet to view maps afterwards.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () async {
              final messenger = ScaffoldMessenger.of(context);
              Navigator.pop(context);
              await _mapService.clearCache();
              await _refreshCacheInfo();
              if (mounted) {
                messenger.showSnackBar(
                  const SnackBar(content: Text('Map cache cleared')),
                );
              }
            },
            child: const Text('Clear', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
  }

  Future<void> _clearTrailCache() async {
    showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Clear Trail Cache'),
        content: const Text(
          'This will remove all cached trails. You will need to download trails again.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () async {
              final messenger = ScaffoldMessenger.of(context);
              Navigator.pop(context);
              await _trailService.clearCache();
              await _refreshCacheInfo();
              if (mounted) {
                messenger.showSnackBar(
                  const SnackBar(content: Text('Trail cache cleared')),
                );
              }
            },
            child: const Text('Clear', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Network status
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: _hasNetworkConnection
                    ? Colors.green[50]
                    : Colors.orange[50],
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                  color: _hasNetworkConnection
                      ? Colors.green[300]!
                      : Colors.orange[300]!,
                ),
              ),
              child: Row(
                children: [
                  Icon(
                    _hasNetworkConnection ? Icons.cloud_done : Icons.cloud_off,
                    color: _hasNetworkConnection ? Colors.green : Colors.orange,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      _hasNetworkConnection
                          ? 'Connected to internet'
                          : 'No internet connection - using cached data',
                      style: TextStyle(
                        color: _hasNetworkConnection
                            ? Colors.green[900]
                            : Colors.orange[900],
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),

            // Map Cache Section
            Text('Map Cache', style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 12),
            _buildCacheCard(
              title: 'Cached Map Tiles',
              size: _mapCacheSizeMB,
              description: 'Downloaded map tiles for offline use',
              onClear: _clearMapCache,
            ),
            const SizedBox(height: 16),
            if (_hasNetworkConnection)
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: _showDownloadMapDialog,
                  icon: const Icon(Icons.download),
                  label: const Text('Download Map Region'),
                ),
              ),

            const SizedBox(height: 32),

            // Trail Cache Section
            Text('Trail Cache', style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 12),
            _buildCacheCard(
              title: 'Cached Trails',
              size: _trailCacheSizeMB,
              description: 'Downloaded trail GPX data',
              count: _cachedTrails.length,
              onClear: _clearTrailCache,
            ),
            const SizedBox(height: 16),
            if (_cachedTrails.isNotEmpty)
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Cached Trails (${_cachedTrails.length})',
                    style: Theme.of(context).textTheme.labelLarge,
                  ),
                  const SizedBox(height: 8),
                  ListView.builder(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    itemCount: _cachedTrails.length,
                    itemBuilder: (context, index) {
                      return ListTile(
                        leading: const Icon(
                          Icons.terrain,
                          color: Color(0xFF0F5A3D),
                        ),
                        title: Text(_cachedTrails[index]),
                        trailing: IconButton(
                          icon: const Icon(Icons.delete, color: Colors.red),
                          onPressed: () => _deleteTrail(_cachedTrails[index]),
                        ),
                      );
                    },
                  ),
                  const SizedBox(height: 16),
                ],
              ),

            const SizedBox(height: 24),

            // Settings Section
            Text(
              'Offline Settings',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: _refreshCacheInfo,
                icon: const Icon(Icons.refresh),
                label: const Text('Refresh Cache Info'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCacheCard({
    required String title,
    required double size,
    required String description,
    int? count,
    required VoidCallback onClear,
  }) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(title, style: Theme.of(context).textTheme.titleMedium),
                Text(
                  '${size.toStringAsFixed(2)} MB',
                  style: Theme.of(context).textTheme.labelLarge?.copyWith(
                    color: const Color(0xFF0F5A3D),
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(description, style: Theme.of(context).textTheme.bodySmall),
            if (count != null) ...[
              const SizedBox(height: 8),
              Text(
                'Items: $count',
                style: Theme.of(context).textTheme.labelSmall,
              ),
            ],
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton(
                onPressed: size > 0 ? onClear : null,
                child: const Text('Clear Cache'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showDownloadMapDialog() {
    showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Download Map Region'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Enter the bounding coordinates for the region you want to cache:',
              style: Theme.of(context).textTheme.bodyMedium,
            ),
            const SizedBox(height: 16),
            Text(
              'This feature requires network access and will download map tiles for offline use.',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: 16),
            const TextField(
              decoration: InputDecoration(
                labelText: 'Min Latitude',
                hintText: 'e.g., 9.0',
              ),
            ),
            const SizedBox(height: 12),
            const TextField(
              decoration: InputDecoration(
                labelText: 'Max Latitude',
                hintText: 'e.g., 10.0',
              ),
            ),
            const SizedBox(height: 12),
            const TextField(
              decoration: InputDecoration(
                labelText: 'Min Longitude',
                hintText: 'e.g., 121.0',
              ),
            ),
            const SizedBox(height: 12),
            const TextField(
              decoration: InputDecoration(
                labelText: 'Max Longitude',
                hintText: 'e.g., 122.0',
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('Map download feature coming soon'),
                ),
              );
            },
            child: const Text('Download'),
          ),
        ],
      ),
    );
  }

  Future<void> _deleteTrail(String trailId) async {
    await _trailService.deleteCachedTrail(trailId);
    await _refreshCacheInfo();
    if (mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Trail "$trailId" deleted')));
    }
  }
}
