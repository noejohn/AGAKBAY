import 'package:flutter/material.dart';
import '../services/offline_map_service.dart';
import '../services/offline_trail_service.dart';
import '../widgets/offline_map_manager.dart';

/// Settings screen with offline map management
class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  late OfflineMapService _mapService;
  late OfflineTrailService _trailService;
  bool _initialized = false;

  @override
  void initState() {
    super.initState();
    _mapService = OfflineMapService();
    _trailService = OfflineTrailService();
    _initialize();
  }

  Future<void> _initialize() async {
    try {
      await _mapService.initialize();
      await _trailService.initialize();
      if (mounted) {
        setState(() => _initialized = true);
      }
    } catch (e) {
      debugPrint('Error initializing services: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Settings'),
        centerTitle: true,
        elevation: 0,
      ),
      body: _initialized
          ? SingleChildScrollView(
              child: Column(
                children: [
                  // Offline Maps Section
                  Padding(
                    padding: const EdgeInsets.all(16.0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            const Icon(Icons.map, color: Color(0xFF0F5A3D)),
                            const SizedBox(width: 12),
                            Text(
                              'Offline Maps & Trails',
                              style: Theme.of(context).textTheme.titleLarge,
                            ),
                          ],
                        ),
                        const SizedBox(height: 16),
                        Container(
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(12),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withValues(alpha: 0.05),
                                blurRadius: 8,
                              ),
                            ],
                          ),
                          child: OfflineMapManager(),
                        ),
                      ],
                    ),
                  ),
                  const Divider(height: 32),

                  // App Settings Section
                  Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16.0,
                      vertical: 8.0,
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            const Icon(
                              Icons.settings,
                              color: Color(0xFF0F5A3D),
                            ),
                            const SizedBox(width: 12),
                            Text(
                              'App Settings',
                              style: Theme.of(context).textTheme.titleLarge,
                            ),
                          ],
                        ),
                        const SizedBox(height: 16),
                        _buildSettingTile(
                          icon: Icons.notifications,
                          title: 'Notifications',
                          subtitle: 'Manage app notifications',
                          onTap: () {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text(
                                  'Notification settings coming soon',
                                ),
                              ),
                            );
                          },
                        ),
                        _buildSettingTile(
                          icon: Icons.location_on,
                          title: 'Location',
                          subtitle: 'GPS and location permissions',
                          onTap: () {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text('Location settings coming soon'),
                              ),
                            );
                          },
                        ),
                        _buildSettingTile(
                          icon: Icons.dark_mode,
                          title: 'Theme',
                          subtitle: 'Dark mode and appearance',
                          onTap: () {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text('Theme settings coming soon'),
                              ),
                            );
                          },
                        ),
                      ],
                    ),
                  ),
                  const Divider(height: 32),

                  // About Section
                  Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16.0,
                      vertical: 8.0,
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            const Icon(Icons.info, color: Color(0xFF0F5A3D)),
                            const SizedBox(width: 12),
                            Text(
                              'About',
                              style: Theme.of(context).textTheme.titleLarge,
                            ),
                          ],
                        ),
                        const SizedBox(height: 16),
                        _buildSettingTile(
                          icon: Icons.help,
                          title: 'Help & Support',
                          subtitle: 'Get help with the app',
                          onTap: () {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(content: Text('Help coming soon')),
                            );
                          },
                        ),
                        _buildSettingTile(
                          icon: Icons.privacy_tip,
                          title: 'Privacy Policy',
                          subtitle: 'Read our privacy policy',
                          onTap: () {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text('Privacy policy coming soon'),
                              ),
                            );
                          },
                        ),
                        _buildSettingTile(
                          icon: Icons.description,
                          title: 'Terms of Service',
                          subtitle: 'Read our terms of service',
                          onTap: () {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text('Terms coming soon'),
                              ),
                            );
                          },
                        ),
                        const SizedBox(height: 16),
                        Center(
                          child: Text(
                            'Version 1.0.0',
                            style: Theme.of(context).textTheme.labelSmall,
                          ),
                        ),
                        const SizedBox(height: 24),
                      ],
                    ),
                  ),
                ],
              ),
            )
          : const Center(child: CircularProgressIndicator()),
    );
  }

  Widget _buildSettingTile({
    required IconData icon,
    required String title,
    required String subtitle,
    required VoidCallback onTap,
  }) {
    return ListTile(
      leading: Icon(icon, color: const Color(0xFF0F5A3D)),
      title: Text(title),
      subtitle: Text(subtitle),
      trailing: const Icon(Icons.arrow_forward_ios, size: 16),
      onTap: onTap,
      dense: true,
    );
  }
}
