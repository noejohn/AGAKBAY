import 'dart:async';
import 'dart:convert';
import 'dart:io' show Platform;
import 'dart:math' as math;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter_map/flutter_map.dart' as fm;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:geolocator/geolocator.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:http/http.dart' as http;
import 'package:latlong2/latlong.dart' as ll;
import 'package:tunga/firebase_options.dart';
import 'package:tunga/screens/hike_room_screen.dart';
import 'package:tunga/screens/offline_map_example_screen.dart';
import 'package:tunga/services/activity_sync_service.dart';
import 'package:tunga/services/auth_database_service.dart';
import 'package:tunga/services/hike_room_service.dart';
import 'package:tunga/services/offline_activity_database.dart';
import 'package:tunga/widgets/offline_map_widget.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const TunGaApp());
}

class TunGaApp extends StatelessWidget {
  const TunGaApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Agakbay',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF0F5A3D),
          brightness: Brightness.dark,
        ),
        useMaterial3: true,
      ),
      home: const SplashScreen(),
    );
  }
}

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> {
  @override
  void initState() {
    super.initState();
    _loadAndNavigate();
  }

  Future<void> _loadAndNavigate() async {
    await Future<void>.delayed(const Duration(milliseconds: 1500));

    var firebaseReady = true;
    try {
      await Firebase.initializeApp(
        options: DefaultFirebaseOptions.currentPlatform,
      );
      ActivitySyncService.shared.startAutoSync();
    } catch (_) {
      firebaseReady = false;
    }

    if (!mounted) return;
    Navigator.of(context).pushReplacement(
      MaterialPageRoute<void>(
        builder: (context) => AuthGate(firebaseReady: firebaseReady),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Color(0xFF071B13), Color(0xFF03291B), Color(0xFF00140E)],
          ),
        ),
        child: const Center(child: BounceLoadingScreen()),
      ),
    );
  }
}

class AuthGate extends StatelessWidget {
  const AuthGate({super.key, required this.firebaseReady});

  final bool firebaseReady;

  @override
  Widget build(BuildContext context) {
    if (!firebaseReady) {
      return const Scaffold(
        body: Center(
          child: Text(
            'Unable to initialize Firebase. Please check your configuration.',
            textAlign: TextAlign.center,
          ),
        ),
      );
    }

    return StreamBuilder<User?>(
      stream: FirebaseAuth.instance.authStateChanges(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return Scaffold(
            body: Container(
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    Color(0xFF071B13),
                    Color(0xFF03291B),
                    Color(0xFF00140E),
                  ],
                ),
              ),
              child: const Center(child: BounceLoadingScreen()),
            ),
          );
        }

        if (snapshot.hasData && snapshot.data != null) {
          return const DashboardScreen();
        }

        return WelcomeScreen(firebaseReady: firebaseReady);
      },
    );
  }
}

class BounceLoadingScreen extends StatefulWidget {
  const BounceLoadingScreen({super.key});

  @override
  State<BounceLoadingScreen> createState() => _BounceLoadingScreenState();
}

class _BounceLoadingScreenState extends State<BounceLoadingScreen>
    with TickerProviderStateMixin {
  late List<AnimationController> _controllers;
  late List<Animation<double>> _animations;
  final String _text = 'AGAKBAY';

  @override
  void initState() {
    super.initState();
    _controllers = List.generate(
      _text.length,
      (index) => AnimationController(
        duration: const Duration(milliseconds: 600),
        vsync: this,
      )..repeat(),
    );

    _animations = List.generate(
      _text.length,
      (index) => Tween<double>(begin: 0, end: 1).animate(
        CurvedAnimation(
          parent: _controllers[index],
          curve: Interval(
            index * 0.1,
            math.min((index * 0.1) + 0.5, 1.0),
            curve: Curves.easeInOut,
          ),
        ),
      ),
    );
  }

  @override
  void dispose() {
    for (var controller in _controllers) {
      controller.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 120,
          height: 120,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            border: Border.all(
              color: Colors.white.withValues(alpha: 0.2),
              width: 2,
            ),
          ),
          child: ClipOval(
            child: Image.asset('assets/images/animal.png', fit: BoxFit.cover),
          ),
        ),
        const SizedBox(height: 40),
        Row(
          mainAxisSize: MainAxisSize.min,
          mainAxisAlignment: MainAxisAlignment.center,
          children: List.generate(
            _text.length,
            (index) => AnimatedBuilder(
              animation: _animations[index],
              builder: (context, child) {
                final bounce = _animations[index].value;
                final offset = (bounce - 0.5).abs() * 30;

                return Transform.translate(
                  offset: Offset(0, -offset),
                  child: Text(
                    _text[index],
                    style: const TextStyle(
                      fontSize: 48,
                      fontWeight: FontWeight.w800,
                      color: Colors.white,
                      letterSpacing: 2,
                    ),
                  ),
                );
              },
            ),
          ),
        ),
        const SizedBox(height: 20),
        Text(
          'Initializing...',
          style: TextStyle(
            fontSize: 14,
            color: Colors.white.withValues(alpha: 0.7),
            letterSpacing: 1.2,
          ),
        ),
      ],
    );
  }
}

class WelcomeScreen extends StatelessWidget {
  const WelcomeScreen({super.key, required this.firebaseReady});

  final bool firebaseReady;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Color(0xFF071B13), Color(0xFF03291B), Color(0xFF00140E)],
          ),
        ),
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 28.0),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Spacer(flex: 2),
                Container(
                  width: 132,
                  height: 132,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: Colors.white.withValues(alpha: 0.2),
                      width: 2,
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.35),
                        blurRadius: 20,
                        offset: const Offset(0, 10),
                      ),
                    ],
                  ),
                  child: ClipOval(
                    child: Image.asset(
                      'assets/images/animal.png',
                      fit: BoxFit.cover,
                    ),
                  ),
                ),
                const SizedBox(height: 24),
                Text(
                  'Agakbay',
                  style: Theme.of(context).textTheme.headlineLarge?.copyWith(
                    fontWeight: FontWeight.w800,
                    letterSpacing: 1.4,
                    color: Colors.white,
                  ),
                ),
                const SizedBox(height: 10),
                Text(
                  'EXPLORE PEAKS. TRACK ADVENTURES.',
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: Colors.white70,
                    letterSpacing: 1.7,
                    height: 1.4,
                  ),
                ),
                const SizedBox(height: 34),
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(24),
                    border: Border.all(
                      color: Colors.white.withValues(alpha: 0.14),
                    ),
                  ),
                  child: Column(
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          _InfoChip(
                            icon: Icons.location_on_rounded,
                            label: 'Trail Maps',
                          ),
                          _InfoChip(
                            icon: Icons.hiking_rounded,
                            label: 'Track Hikes',
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          _InfoChip(
                            icon: Icons.timeline_rounded,
                            label: 'Progress',
                          ),
                          _InfoChip(
                            icon: Icons.nature_rounded,
                            label: 'Explore',
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                const Spacer(flex: 2),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: () {
                      Navigator.of(context).push(
                        MaterialPageRoute<void>(
                          builder: (context) =>
                              LoginScreen(firebaseReady: firebaseReady),
                        ),
                      );
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF57B772),
                      foregroundColor: Colors.black,
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                      ),
                      elevation: 6,
                    ),
                    child: const Text(
                      'GET STARTED',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        letterSpacing: 1.6,
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 24),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key, required this.firebaseReady});

  final bool firebaseReady;

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _authDatabaseService = AuthDatabaseService();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _obscurePassword = true;
  bool _isSubmitting = false;

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  void _openForgotPassword() {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (context) => ForgotPasswordScreen(
          authDatabaseService: _authDatabaseService,
          initialEmail: _emailController.text.trim(),
        ),
      ),
    );
  }

  Future<void> _handleLogin() async {
    if (!widget.firebaseReady) {
      _showSnackBar('Firebase is not configured yet.');
      return;
    }

    final email = _emailController.text.trim();
    final password = _passwordController.text;

    if (email.isEmpty) {
      _showSnackBar('Please enter your email.');
      return;
    }
    if (!email.contains('@')) {
      _showSnackBar('Please enter a valid email.');
      return;
    }
    if (password.isEmpty) {
      _showSnackBar('Please enter your password.');
      return;
    }

    setState(() => _isSubmitting = true);
    try {
      await _authDatabaseService.signInUser(email: email, password: password);
      if (!mounted) {
        return;
      }
      Navigator.of(context).pushReplacement(
        MaterialPageRoute<void>(builder: (context) => const DashboardScreen()),
      );
    } on FirebaseAuthException catch (error) {
      final message = switch (error.code) {
        'wrong-password' => 'Wrong password.',
        'user-not-found' => 'Email not found.',
        'invalid-email' => 'Invalid email address.',
        'invalid-credential' => 'Wrong email or password.',
        'too-many-requests' => 'Too many attempts. Try again later.',
        _ => error.message ?? 'Login failed. Please try again.',
      };
      _showSnackBar(message);
    } catch (error) {
      _showSnackBar('Login failed: $error');
    } finally {
      if (mounted) {
        setState(() => _isSubmitting = false);
      }
    }
  }

  void _showSnackBar(String message) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Color(0xFF04140E), Color(0xFF072519), Color(0xFF03110C)],
          ),
        ),
        child: Stack(
          children: [
            Positioned(
              top: 90,
              left: 0,
              right: 0,
              child: IgnorePointer(
                child: Container(
                  height: 130,
                  margin: const EdgeInsets.symmetric(horizontal: 60),
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: RadialGradient(
                      colors: [
                        const Color(0xFFB4CD3A).withValues(alpha: 0.55),
                        const Color(0xFFB4CD3A).withValues(alpha: 0.0),
                      ],
                    ),
                  ),
                ),
              ),
            ),
            SafeArea(
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final keyboardInset = MediaQuery.of(
                    context,
                  ).viewInsets.bottom;
                  final keyboardOpen = keyboardInset > 0;

                  return SingleChildScrollView(
                    physics: keyboardOpen
                        ? const ClampingScrollPhysics()
                        : const NeverScrollableScrollPhysics(),
                    padding: EdgeInsets.fromLTRB(
                      24,
                      20,
                      24,
                      20 + keyboardInset,
                    ),
                    child: ConstrainedBox(
                      constraints: BoxConstraints(
                        minHeight: constraints.maxHeight - 40,
                      ),
                      child: Center(
                        child: ConstrainedBox(
                          constraints: const BoxConstraints(maxWidth: 520),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Container(
                                width: 106,
                                height: 106,
                                padding: const EdgeInsets.all(8),
                                decoration: BoxDecoration(
                                  borderRadius: BorderRadius.circular(30),
                                  gradient: const LinearGradient(
                                    begin: Alignment.topLeft,
                                    end: Alignment.bottomRight,
                                    colors: [
                                      Color(0xFF38D86E),
                                      Color(0xFF2CB95F),
                                    ],
                                  ),
                                  boxShadow: [
                                    BoxShadow(
                                      color: const Color(
                                        0xFF38D86E,
                                      ).withValues(alpha: 0.35),
                                      blurRadius: 24,
                                      offset: const Offset(0, 12),
                                    ),
                                  ],
                                ),
                                child: ClipRRect(
                                  borderRadius: BorderRadius.circular(24),
                                  child: Image.asset(
                                    'assets/images/animal.png',
                                    fit: BoxFit.cover,
                                  ),
                                ),
                              ),
                              const SizedBox(height: 18),
                              Text(
                                'Agakbay',
                                style: Theme.of(context).textTheme.displaySmall
                                    ?.copyWith(
                                      color: Colors.white,
                                      fontWeight: FontWeight.w800,
                                    ),
                              ),
                              const SizedBox(height: 8),
                              Text(
                                'EXPLORE PEAKS. TRACK ADVENTURES.',
                                textAlign: TextAlign.center,
                                style: Theme.of(context).textTheme.bodyMedium
                                    ?.copyWith(
                                      color: Colors.white.withValues(
                                        alpha: 0.68,
                                      ),
                                      letterSpacing: 1.4,
                                    ),
                              ),
                              const SizedBox(height: 34),
                              Text(
                                'Welcome Back!',
                                style: Theme.of(context)
                                    .textTheme
                                    .headlineMedium
                                    ?.copyWith(
                                      color: Colors.white,
                                      fontWeight: FontWeight.w700,
                                    ),
                              ),
                              const SizedBox(height: 10),
                              Text(
                                'Login to continue your adventure.',
                                textAlign: TextAlign.center,
                                style: Theme.of(context).textTheme.titleMedium
                                    ?.copyWith(color: const Color(0xFF82CFA5)),
                              ),
                              if (!widget.firebaseReady) ...[
                                const SizedBox(height: 14),
                                Container(
                                  width: double.infinity,
                                  padding: const EdgeInsets.all(12),
                                  decoration: BoxDecoration(
                                    color: const Color(
                                      0xFF5D1D1D,
                                    ).withValues(alpha: 0.35),
                                    borderRadius: BorderRadius.circular(12),
                                    border: Border.all(
                                      color: const Color(
                                        0xFFFF6A6A,
                                      ).withValues(alpha: 0.6),
                                    ),
                                  ),
                                  child: const Text(
                                    'Firebase is not configured yet. Database sign up will fail until setup is completed.',
                                    style: TextStyle(
                                      color: Colors.white,
                                      fontSize: 13,
                                      height: 1.35,
                                    ),
                                  ),
                                ),
                              ],
                              const SizedBox(height: 30),
                              _AuthInput(
                                hint: 'Email',
                                icon: Icons.email_outlined,
                                controller: _emailController,
                                keyboardType: TextInputType.emailAddress,
                                textInputAction: TextInputAction.next,
                              ),
                              const SizedBox(height: 16),
                              _AuthInput(
                                hint: 'Password',
                                icon: Icons.lock_outline_rounded,
                                controller: _passwordController,
                                obscureText: _obscurePassword,
                                textInputAction: TextInputAction.done,
                                suffix: IconButton(
                                  onPressed: () {
                                    setState(
                                      () =>
                                          _obscurePassword = !_obscurePassword,
                                    );
                                  },
                                  icon: Icon(
                                    _obscurePassword
                                        ? Icons.visibility_outlined
                                        : Icons.visibility_off_outlined,
                                    color: Colors.white.withValues(alpha: 0.66),
                                  ),
                                ),
                              ),
                              Align(
                                alignment: Alignment.centerRight,
                                child: TextButton(
                                  onPressed: _openForgotPassword,
                                  child: const Text(
                                    'Forgot Password?',
                                    style: TextStyle(
                                      color: Color(0xFF57C97D),
                                      fontWeight: FontWeight.w500,
                                    ),
                                  ),
                                ),
                              ),
                              const SizedBox(height: 10),
                              SizedBox(
                                width: double.infinity,
                                child: ElevatedButton(
                                  onPressed: _isSubmitting
                                      ? null
                                      : _handleLogin,
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: const Color(0xFF45D972),
                                    foregroundColor: Colors.black,
                                    padding: const EdgeInsets.symmetric(
                                      vertical: 18,
                                    ),
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(18),
                                    ),
                                    elevation: 0,
                                  ),
                                  child: _isSubmitting
                                      ? const SizedBox(
                                          width: 24,
                                          height: 24,
                                          child: CircularProgressIndicator(
                                            strokeWidth: 2.4,
                                            color: Colors.black,
                                          ),
                                        )
                                      : const Text(
                                          'LOGIN',
                                          style: TextStyle(
                                            fontWeight: FontWeight.w800,
                                            fontSize: 20,
                                            letterSpacing: 1.8,
                                          ),
                                        ),
                                ),
                              ),
                              const SizedBox(height: 22),
                              Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Text(
                                    "Don't have an account? ",
                                    style: TextStyle(
                                      color: Colors.white.withValues(
                                        alpha: 0.6,
                                      ),
                                      fontSize: 18,
                                    ),
                                  ),
                                  TextButton(
                                    onPressed: () {
                                      Navigator.of(context).push(
                                        MaterialPageRoute<void>(
                                          builder: (context) => SignUpScreen(
                                            firebaseReady: widget.firebaseReady,
                                          ),
                                        ),
                                      );
                                    },
                                    style: TextButton.styleFrom(
                                      padding: EdgeInsets.zero,
                                      minimumSize: Size.zero,
                                      tapTargetSize:
                                          MaterialTapTargetSize.shrinkWrap,
                                    ),
                                    child: const Text(
                                      'Sign Up',
                                      style: TextStyle(
                                        color: Color(0xFF4FD972),
                                        fontWeight: FontWeight.w700,
                                        fontSize: 18,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _NearbyTrail {
  const _NearbyTrail({
    required this.placeId,
    required this.name,
    required this.address,
    required this.location,
    double? distanceKm,
    int? elevationMasl,
    String? provinceOrCity,
    String? difficulty,
    String? status,
    String? description,
    this.imageUrl,
  }) : distanceKm = distanceKm ?? 0,
       elevationMasl = elevationMasl ?? 0,
       provinceOrCity = provinceOrCity ?? 'Mindanao',
       difficulty = difficulty ?? 'Moderate',
       status = status ?? 'Open',
       description = description ?? '';

  final String placeId;
  final String name;
  final String address;
  final LatLng location;
  final double distanceKm;
  final int elevationMasl;
  final String provinceOrCity;
  final String difficulty;
  final String status;
  final String description;
  final String? imageUrl;
}

class _CompletedHikeSession {
  const _CompletedHikeSession({
    required this.trail,
    required this.completedAt,
    required this.distanceKm,
    required this.duration,
    required this.elevationGainMasl,
    required this.maxElevationMasl,
    required this.checkpointsReached,
    required this.totalCheckpoints,
    required this.reachedSummit,
  });

  final _NearbyTrail trail;
  final DateTime completedAt;
  final double distanceKm;
  final Duration duration;
  final int elevationGainMasl;
  final int maxElevationMasl;
  final int checkpointsReached;
  final int totalCheckpoints;
  final bool reachedSummit;
}

class _LiveHikeResult {
  const _LiveHikeResult({
    required this.distanceKm,
    required this.duration,
    required this.elevationGainMasl,
    required this.maxElevationMasl,
    required this.checkpointsReached,
    required this.totalCheckpoints,
    required this.reachedSummit,
    required this.trackPoints,
    required this.routePoints,
    required this.peakLocation,
    required this.startedAt,
    required this.endedAt,
  });

  final double distanceKm;
  final Duration duration;
  final int elevationGainMasl;
  final int maxElevationMasl;
  final int checkpointsReached;
  final int totalCheckpoints;
  final bool reachedSummit;
  final List<_TrailTrackPoint> trackPoints;
  final List<LatLng> routePoints;
  final LatLng peakLocation;
  final DateTime startedAt;
  final DateTime endedAt;
}

class _TrailTrackPoint {
  const _TrailTrackPoint({
    required this.lat,
    required this.lon,
    required this.timestamp,
    this.altitudeMasl,
    this.accuracyMeters,
    this.speedMps,
  });

  final double lat;
  final double lon;
  final DateTime timestamp;
  final double? altitudeMasl;
  final double? accuracyMeters;
  final double? speedMps;
}

class _CommunityTrailData {
  const _CommunityTrailData({
    required this.mountainKey,
    required this.status,
    required this.points,
    required this.qualityScore,
    required this.submissionCount,
    this.source,
    this.updatedAt,
  });

  final String mountainKey;
  final String status;
  final List<LatLng> points;
  final double qualityScore;
  final int submissionCount;
  final String? source;
  final DateTime? updatedAt;
}

class _MountainRouteOption {
  const _MountainRouteOption({
    required this.assetPath,
    required this.routeName,
    required this.jumpOffLabel,
    required this.startPoint,
  });

  final String assetPath;
  final String routeName;
  final String jumpOffLabel;
  final LatLng startPoint;
}

class _GpxRoutePreview {
  const _GpxRoutePreview({required this.startPoint});

  final LatLng startPoint;
}

class _CommunityPost {
  const _CommunityPost({
    required this.id,
    required this.authorId,
    required this.authorName,
    required this.content,
    required this.mountainName,
    required this.likeCount,
    required this.commentCount,
    required this.createdAt,
  });

  final String id;
  final String authorId;
  final String authorName;
  final String content;
  final String mountainName;
  final int likeCount;
  final int commentCount;
  final DateTime? createdAt;
}

enum _HikeWeatherRisk { good, caution, unsafe }

class _HikeWeatherForecast {
  const _HikeWeatherForecast({
    required this.date,
    required this.summary,
    required this.adviceTitle,
    required this.adviceDetail,
    required this.risk,
    required this.weatherCode,
    required this.conditionType,
    this.temperatureMinC,
    this.temperatureMaxC,
    this.rainChancePercent,
    this.precipitationMm,
    this.windSpeedKmh,
    this.periodOutlooks = const <_HikeWeatherPeriodOutlook>[],
  });

  final DateTime date;
  final String summary;
  final String adviceTitle;
  final String adviceDetail;
  final _HikeWeatherRisk risk;
  final int weatherCode;
  final String conditionType;
  final double? temperatureMinC;
  final double? temperatureMaxC;
  final int? rainChancePercent;
  final double? precipitationMm;
  final double? windSpeedKmh;
  final List<_HikeWeatherPeriodOutlook> periodOutlooks;
}

class _HikeWeatherPeriodOutlook {
  const _HikeWeatherPeriodOutlook({
    required this.label,
    required this.timeRange,
    required this.summary,
    required this.temperatureLabel,
    required this.rainChancePercent,
    required this.risk,
    required this.weatherCode,
  });

  final String label;
  final String timeRange;
  final String summary;
  final String temperatureLabel;
  final int? rainChancePercent;
  final _HikeWeatherRisk risk;
  final int weatherCode;
}

class _WeatherForecastException implements Exception {
  const _WeatherForecastException(this.message);

  final String message;
}

class _HourlyWeatherPeriod {
  const _HourlyWeatherPeriod(
    this.label,
    this.timeRange,
    this.startHour,
    this.endHour,
  );

  final String label;
  final String timeRange;
  final int startHour;
  final int endHour;
}

class _WeekdayLabel extends StatelessWidget {
  const _WeekdayLabel(this.label);

  final String label;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Text(
        label,
        textAlign: TextAlign.center,
        style: TextStyle(
          color: Colors.white.withValues(alpha: 0.52),
          fontSize: 8,
          fontWeight: FontWeight.w800,
        ),
      ),
    );
  }
}

enum _NearbyAnchorMode { nearMe, nearSearch }

enum _MarkerStatusFilter { all, open, closed }

class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key});

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  static const MethodChannel _configChannel = MethodChannel(
    'com.example.tunga/config',
  );
  static const LatLng _fallbackCenter = LatLng(8.0, 125.0);
  static final LatLngBounds _mindanaoBounds = LatLngBounds(
    southwest: LatLng(4.3, 121.0),
    northeast: LatLng(10.7, 126.7),
  );
  GoogleMapController? _mapController;
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseAuth _firebaseAuth = FirebaseAuth.instance;
  final HikeRoomService _hikeRoomService = HikeRoomService();
  final TextEditingController _searchController = TextEditingController();
  final TextEditingController _communityComposerController =
      TextEditingController();
  String _mapsApiKey = '';
  String _weatherApiKey = '';
  String _accountType = 'hiker';
  LatLng _currentCenter = _fallbackCenter;
  LatLng? _myLocationCenter;
  _NearbyTrail? _searchedTrailAnchor;
  _NearbyAnchorMode _nearbyAnchorMode = _NearbyAnchorMode.nearMe;
  String? _locationMessage;
  String? _nearbyTrailsMessage;
  bool _locationGranted = false;
  bool _isSearching = false;
  bool _isLoadingNearbyTrails = false;
  _MarkerStatusFilter _markerStatusFilter = _MarkerStatusFilter.all;
  int _selectedNavIndex = 0;
  int _communityFeedFilterIndex = 0;
  Marker? _searchMarker;
  List<_NearbyTrail> _nearbyTrails = const [];
  final Map<String, _NearbyTrail> _trailLibrary = <String, _NearbyTrail>{};
  final Set<String> _completedTrailIds = <String>{};
  final List<_CompletedHikeSession> _completedHikeSessions =
      <_CompletedHikeSession>[];
  final Map<String, _CommunityTrailData> _communityTrailCache =
      <String, _CommunityTrailData>{};
  final Map<String, double> _roadDistanceKmCache = <String, double>{};
  final Set<String> _roadDistanceUnavailable = <String>{};
  final Map<String, int> _elevationMaslCache = <String, int>{};
  final Map<String, List<_MountainRouteOption>> _mountainRouteOptionsCache =
      <String, List<_MountainRouteOption>>{};

  @override
  void initState() {
    super.initState();
    unawaited(_initializeDashboard());
  }

  @override
  void dispose() {
    _searchController.dispose();
    _communityComposerController.dispose();
    _mapController?.dispose();
    super.dispose();
  }

  Future<void> _initializeDashboard() async {
    try {
      final profile = await _hikeRoomService.getCurrentUserProfile();
      final accountType = _hikeRoomService.accountTypeFromProfile(profile);
      if (mounted) {
        setState(() => _accountType = accountType);
      }
    } catch (_) {
      _accountType = 'hiker';
    }
    await _loadMapsApiKey();
    await _loadCurrentLocation();
    if (_nearbyTrails.isEmpty) {
      await _refreshNearbyTrailsForActiveAnchor();
    }
  }

  Future<void> _loadMapsApiKey() async {
    if (_mapsApiKey.isNotEmpty) {
      return;
    }
    try {
      final key = await _configChannel.invokeMethod<String>('getMapsApiKey');
      if (key != null && key.trim().isNotEmpty) {
        _mapsApiKey = key.trim();
      }
    } catch (_) {
      // Ignore platform read errors; nearby trails will show setup guidance.
    }
  }

  Future<void> _loadWeatherApiKey() async {
    if (_weatherApiKey.isNotEmpty) {
      return;
    }
    try {
      final key = await _configChannel.invokeMethod<String>('getWeatherApiKey');
      if (key != null && key.trim().isNotEmpty) {
        _weatherApiKey = key.trim();
        return;
      }
    } catch (_) {
      // Fall back to the maps key for older builds without WEATHER_API_KEY.
    }
    await _loadMapsApiKey();
    _weatherApiKey = _mapsApiKey;
  }

  Future<void> _loadCurrentLocation() async {
    try {
      final serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        if (!mounted) {
          return;
        }
        setState(() {
          _locationMessage =
              'Location service is off. Turn it on to center map.';
          _locationGranted = false;
        });
        return;
      }

      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }

      if (permission == LocationPermission.denied ||
          permission == LocationPermission.deniedForever) {
        if (!mounted) {
          return;
        }
        setState(() {
          _locationMessage = 'Location permission denied.';
          _locationGranted = false;
        });
        return;
      }

      final position = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
        ),
      );
      final target = LatLng(position.latitude, position.longitude);
      final inMindanao = _isInMindanaoBounds(target);

      if (!mounted) {
        return;
      }
      setState(() {
        _locationGranted = true;
        if (inMindanao) {
          _myLocationCenter = target;
          _currentCenter = target;
          _locationMessage = null;
        } else {
          _locationMessage =
              'Your location is outside Mindanao. Showing Mindanao map.';
        }
      });
      if (inMindanao) {
        await _mapController?.animateCamera(
          CameraUpdate.newCameraPosition(
            CameraPosition(target: target, zoom: 13.8),
          ),
        );
      }
    } catch (_) {
      if (!mounted) {
        return;
      }
      setState(() {
        _locationMessage = 'Unable to fetch current location.';
        _locationGranted = false;
      });
    } finally {
      if (mounted) {
        unawaited(_refreshNearbyTrailsForActiveAnchor());
      }
    }
  }

  Future<void> _zoomIn() async {
    await _mapController?.animateCamera(CameraUpdate.zoomIn());
  }

  Future<void> _zoomOut() async {
    await _mapController?.animateCamera(CameraUpdate.zoomOut());
  }

  Future<void> _searchOnMap() async {
    final query = _searchController.text.trim();
    if (query.isEmpty) {
      setState(() {
        _locationMessage = 'Type a place or mountain name to search.';
      });
      return;
    }

    FocusScope.of(context).unfocus();
    setState(() {
      _isSearching = true;
    });

    try {
      unawaited(_refreshMyLocationForDistance());
      final result = await _searchMountainInMindanao(query);

      if (!mounted) {
        return;
      }

      if (result == null) {
        setState(() {
          _locationMessage =
              'No matching place in Mindanao for "$query". Try a more exact name.';
        });
        return;
      }
      final resolvedTrail = result;
      final resolvedTarget = resolvedTrail.location;
      final resolvedName = resolvedTrail.name;
      _rememberTrail(resolvedTrail);

      setState(() {
        _searchedTrailAnchor = resolvedTrail;
        _nearbyAnchorMode = _NearbyAnchorMode.nearSearch;
        _currentCenter = resolvedTarget;
        _locationMessage = null;
        _searchMarker = Marker(
          markerId: const MarkerId('search_result'),
          position: resolvedTarget,
          icon: BitmapDescriptor.defaultMarkerWithHue(
            BitmapDescriptor.hueGreen,
          ),
          infoWindow: InfoWindow(
            title: resolvedName.isEmpty ? query : resolvedName,
          ),
          onTap: () {
            _openMountainDetailsCard(resolvedTrail);
          },
        );
      });

      unawaited(_refreshNearbyTrailsForActiveAnchor());

      await _mapController?.animateCamera(
        CameraUpdate.newCameraPosition(
          CameraPosition(target: resolvedTarget, zoom: 13.8),
        ),
      );
    } catch (_) {
      if (!mounted) {
        return;
      }
      setState(() {
        _locationMessage = 'Search failed. Please try again.';
      });
    } finally {
      if (mounted) {
        setState(() {
          _isSearching = false;
        });
      }
    }
  }

  Future<_NearbyTrail?> _searchMountainInMindanao(String query) async {
    await _loadMapsApiKey();
    if (_mapsApiKey.isNotEmpty) {
      try {
        final googleResult = await _searchPlaceInMindanaoWithPlaces(query);
        if (googleResult != null) {
          return googleResult;
        }
      } catch (_) {
        // Fallback to Nominatim below.
      }
    }
    return _searchPlaceInMindanaoWithNominatim(query);
  }

  Future<_NearbyTrail?> _searchPlaceInMindanaoWithPlaces(String query) async {
    final queryVariants = <String>{
      query,
      '$query, Mindanao, Philippines',
      '$query, Philippines',
      if (query.toLowerCase().startsWith('mt '))
        query.replaceFirst(RegExp(r'^mt\s+', caseSensitive: false), 'Mount '),
      if (query.toLowerCase().startsWith('mt. '))
        query.replaceFirst(RegExp(r'^mt\.\s+', caseSensitive: false), 'Mount '),
    };

    for (final candidate in queryVariants) {
      final uri = Uri.https(
        'maps.googleapis.com',
        '/maps/api/place/textsearch/json',
        {
          'query': candidate,
          'location': '${_currentCenter.latitude},${_currentCenter.longitude}',
          'radius': '50000',
          'region': 'ph',
          'key': _mapsApiKey,
        },
      );

      final response = await http.get(uri).timeout(const Duration(seconds: 10));
      if (response.statusCode != 200) {
        continue;
      }

      final decoded = jsonDecode(response.body);
      if (decoded is! Map<String, dynamic>) {
        continue;
      }
      final status = decoded['status']?.toString() ?? '';
      if (status == 'REQUEST_DENIED' ||
          status == 'INVALID_REQUEST' ||
          status == 'OVER_QUERY_LIMIT') {
        throw Exception(status);
      }

      final results = decoded['results'];
      if (results is! List) {
        continue;
      }

      for (final item in results) {
        if (item is! Map<String, dynamic>) {
          continue;
        }
        final geometry = item['geometry'];
        if (geometry is! Map<String, dynamic>) {
          continue;
        }
        final location = geometry['location'];
        if (location is! Map<String, dynamic>) {
          continue;
        }

        final lat = _parseCoordinate(location['lat']);
        final lon = _parseCoordinate(location['lng']);
        if (lat == null || lon == null) {
          continue;
        }

        final point = LatLng(lat, lon);
        if (!_isInMindanaoBounds(point)) {
          continue;
        }
        final baseTrail = _trailFromPlacesItem(
          item: item,
          point: point,
          userCenter: _currentCenter,
          fallbackName: query,
        );
        return _resolveTrailElevation(baseTrail);
      }
    }
    return null;
  }

  Future<_NearbyTrail?> _searchPlaceInMindanaoWithNominatim(
    String query,
  ) async {
    final queryVariants = <String>{
      query,
      '$query, Mindanao, Philippines',
      '$query, Philippines',
      if (query.toLowerCase().startsWith('mt '))
        query.replaceFirst(RegExp(r'^mt\s+', caseSensitive: false), 'Mount '),
      if (query.toLowerCase().startsWith('mt. '))
        query.replaceFirst(RegExp(r'^mt\.\s+', caseSensitive: false), 'Mount '),
    };

    for (final candidate in queryVariants) {
      final uri = Uri.https('nominatim.openstreetmap.org', '/search', {
        'q': candidate,
        'format': 'jsonv2',
        'limit': '8',
        'countrycodes': 'ph',
        'viewbox':
            '${_mindanaoBounds.southwest.longitude},${_mindanaoBounds.northeast.latitude},${_mindanaoBounds.northeast.longitude},${_mindanaoBounds.southwest.latitude}',
        'bounded': '1',
      });

      final response = await http
          .get(
            uri,
            headers: const {
              'User-Agent': 'Agakbay/1.0',
              'Accept': 'application/json',
            },
          )
          .timeout(const Duration(seconds: 10));

      if (response.statusCode != 200) {
        continue;
      }

      final decoded = jsonDecode(response.body);
      if (decoded is! List) {
        continue;
      }

      for (final item in decoded) {
        if (item is! Map) {
          continue;
        }
        final lat = double.tryParse(item['lat']?.toString() ?? '');
        final lon = double.tryParse(item['lon']?.toString() ?? '');
        if (lat == null || lon == null) {
          continue;
        }

        final point = LatLng(lat, lon);
        if (!_isInMindanaoBounds(point)) {
          continue;
        }
        final displayName = item['display_name']?.toString() ?? query;
        final address = item['display_name']?.toString() ?? '';
        final elevation = await _fetchElevationMasl(point);
        final provinceOrCity = _extractProvinceOrCity(address);
        return _NearbyTrail(
          placeId:
              'nominatim_${point.latitude.toStringAsFixed(5)}_${point.longitude.toStringAsFixed(5)}',
          name: displayName.split(',').first.trim(),
          address: address,
          location: point,
          distanceKm: _distanceBetweenKm(_currentCenter, point),
          elevationMasl: elevation,
          provinceOrCity: provinceOrCity,
          difficulty: _difficultyFromElevation(elevation),
          status: 'Open',
          description: _buildMountainDescription(
            name: displayName.split(',').first.trim(),
            provinceOrCity: provinceOrCity,
            difficulty: _difficultyFromElevation(elevation),
            elevationMasl: elevation,
          ),
          imageUrl: null,
        );
      }
    }

    return null;
  }

  Future<void> _loadNearbyTrails(LatLng center) async {
    if (_isLoadingNearbyTrails || !mounted) {
      return;
    }
    setState(() {
      _isLoadingNearbyTrails = true;
      _nearbyTrailsMessage = null;
    });

    try {
      await _loadMapsApiKey();
      final isNearSearch =
          _nearbyAnchorMode == _NearbyAnchorMode.nearSearch &&
          _searchedTrailAnchor != null;
      final maxDistanceKm = isNearSearch ? 30.0 : 10.0;
      final searchAnchorName = _searchedTrailAnchor?.name;
      final searchAnchor = _searchedTrailAnchor;

      List<_NearbyTrail> trails = const <_NearbyTrail>[];
      if (_mapsApiKey.isNotEmpty) {
        trails = await _fetchNearbyTrailsByDistance(
          center,
          maxDistanceKm: maxDistanceKm,
          searchAnchorName: searchAnchorName,
        );
      }
      if (trails.isEmpty && _mapsApiKey.isNotEmpty) {
        trails = await _fetchNearbyTrailsFromPlaces(
          center,
          maxDistanceKm: maxDistanceKm,
          searchAnchorName: searchAnchorName,
        );
      }
      if (trails.isEmpty) {
        trails = await _fetchNearbyTrailsFromNominatim(
          center,
          maxDistanceKm: maxDistanceKm,
          searchAnchorName: searchAnchorName,
        );
      }
      if (isNearSearch && searchAnchor != null) {
        trails = trails.where((trail) {
          return !_isSameTrailIdentity(trail, searchAnchor);
        }).toList()..sort((a, b) => a.distanceKm.compareTo(b.distanceKm));
        trails = <_NearbyTrail>[searchAnchor, ...trails];
        unawaited(_resolveRoadDistanceForTrail(searchAnchor));
      }

      _rememberTrails(trails);
      if (!mounted) {
        return;
      }
      setState(() {
        _nearbyTrails = trails;
        if (trails.isEmpty) {
          _nearbyTrailsMessage = 'No nearby mountains found in this area.';
        }
      });
    } catch (_) {
      if (!mounted) {
        return;
      }
      setState(() {
        _nearbyTrails = const [];
        _nearbyTrailsMessage = 'Nearby mountains unavailable right now.';
      });
    } finally {
      if (mounted) {
        setState(() {
          _isLoadingNearbyTrails = false;
        });
      }
    }
  }

  Future<void> _refreshNearbyTrailsForActiveAnchor() async {
    unawaited(_refreshMyLocationForDistance());
    final center = _activeNearbyCenter();
    await _loadNearbyTrails(center);
  }

  Future<void> _refreshMyLocationForDistance() async {
    try {
      final serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        return;
      }
      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      if (permission == LocationPermission.denied ||
          permission == LocationPermission.deniedForever) {
        return;
      }

      final position = await _getBestCurrentPositionForDistance();
      if (position == null) {
        return;
      }

      if (!mounted) {
        return;
      }
      setState(() {
        _myLocationCenter = LatLng(position.latitude, position.longitude);
      });
      if (_nearbyAnchorMode == _NearbyAnchorMode.nearSearch &&
          _searchedTrailAnchor != null) {
        unawaited(_resolveRoadDistanceForTrail(_searchedTrailAnchor!));
      }
    } catch (_) {
      // Keep existing location when refresh fails.
    }
  }

  Future<void> _resolveRoadDistanceForTrail(_NearbyTrail trail) async {
    final origin = _myLocationCenter;
    if (origin == null) {
      return;
    }
    if (mounted) {
      setState(() {
        _roadDistanceUnavailable.remove(trail.placeId);
      });
    }
    await _loadMapsApiKey();
    if (_mapsApiKey.isEmpty) {
      return;
    }
    final km = await _fetchDrivingDistanceKm(origin, trail.location);
    if (!mounted) {
      return;
    }
    if (km == null) {
      setState(() {
        _roadDistanceUnavailable.add(trail.placeId);
      });
      return;
    }
    setState(() {
      _roadDistanceKmCache[trail.placeId] = km;
      _roadDistanceUnavailable.remove(trail.placeId);
    });
  }

  Future<double?> _fetchDrivingDistanceKm(
    LatLng origin,
    LatLng destination,
  ) async {
    try {
      final uri =
          Uri.https('maps.googleapis.com', '/maps/api/distancematrix/json', {
            'origins': '${origin.latitude},${origin.longitude}',
            'destinations': '${destination.latitude},${destination.longitude}',
            'mode': 'driving',
            'units': 'metric',
            'key': _mapsApiKey,
          });
      final response = await http.get(uri).timeout(const Duration(seconds: 5));
      if (response.statusCode != 200) {
        return null;
      }
      final decoded = jsonDecode(response.body);
      if (decoded is! Map<String, dynamic>) {
        return null;
      }
      if ((decoded['status']?.toString() ?? '') != 'OK') {
        return null;
      }
      final rows = decoded['rows'];
      if (rows is! List || rows.isEmpty) {
        return null;
      }
      final row = rows.first;
      if (row is! Map<String, dynamic>) {
        return null;
      }
      final elements = row['elements'];
      if (elements is! List || elements.isEmpty) {
        return null;
      }
      final element = elements.first;
      if (element is! Map<String, dynamic>) {
        return null;
      }
      if ((element['status']?.toString() ?? '') != 'OK') {
        return null;
      }
      final distance = element['distance'];
      if (distance is! Map<String, dynamic>) {
        return null;
      }
      final meters = (distance['value'] as num?)?.toDouble();
      if (meters == null || meters <= 0) {
        return null;
      }
      return meters / 1000;
    } catch (_) {
      return null;
    }
  }

  Future<Position?> _getBestCurrentPositionForDistance() async {
    Position? best;

    void consider(Position candidate) {
      if (best == null || candidate.accuracy < best!.accuracy) {
        best = candidate;
      }
    }

    try {
      final quickFix = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.bestForNavigation,
        ),
      ).timeout(const Duration(seconds: 4));
      consider(quickFix);
    } catch (_) {
      // Ignore and continue with stream-based sampling.
    }

    if (best != null && best!.accuracy <= 50) {
      return best;
    }

    try {
      final stream =
          Geolocator.getPositionStream(
            locationSettings: const LocationSettings(
              accuracy: LocationAccuracy.bestForNavigation,
              distanceFilter: 0,
            ),
          ).timeout(
            const Duration(seconds: 3),
            onTimeout: (sink) {
              sink.close();
            },
          );

      await for (final sample in stream) {
        consider(sample);
        if (best != null && best!.accuracy <= 50) {
          break;
        }
      }
    } catch (_) {
      // Keep the best fix we already have.
    }

    return best;
  }

  LatLng _activeNearbyCenter() {
    if (_nearbyAnchorMode == _NearbyAnchorMode.nearSearch &&
        _searchedTrailAnchor != null) {
      return _searchedTrailAnchor!.location;
    }
    return _myLocationCenter ?? _currentCenter;
  }

  String _nearbyAnchorLabel() {
    if (_nearbyAnchorMode == _NearbyAnchorMode.nearSearch &&
        _searchedTrailAnchor != null) {
      return 'Near: ${_searchedTrailAnchor!.name}';
    }
    return 'Near: My Location';
  }

  void _setNearbyAnchorMode(_NearbyAnchorMode mode) {
    if (mode == _NearbyAnchorMode.nearSearch && _searchedTrailAnchor == null) {
      return;
    }
    if (_nearbyAnchorMode == mode) {
      return;
    }
    setState(() {
      _nearbyAnchorMode = mode;
    });
    unawaited(_refreshNearbyTrailsForActiveAnchor());
  }

  Future<List<_NearbyTrail>> _fetchNearbyTrailsFromPlaces(
    LatLng center, {
    required double maxDistanceKm,
    String? searchAnchorName,
  }) async {
    final queries = <String>[
      'mountain',
      'hiking trail',
      'mountain peak',
      if (searchAnchorName != null && searchAnchorName.trim().isNotEmpty)
        'mountain near $searchAnchorName',
    ];
    final byId = <String, _NearbyTrail>{};

    for (final query in queries) {
      final uri =
          Uri.https('maps.googleapis.com', '/maps/api/place/textsearch/json', {
            'query': '$query in Mindanao',
            'location': '${center.latitude},${center.longitude}',
            'radius': '50000',
            'region': 'ph',
            'key': _mapsApiKey,
          });

      final response = await http.get(uri).timeout(const Duration(seconds: 10));
      if (response.statusCode != 200) {
        continue;
      }

      final decoded = jsonDecode(response.body);
      if (decoded is! Map<String, dynamic>) {
        continue;
      }
      final status = decoded['status']?.toString() ?? '';
      if (status == 'REQUEST_DENIED' ||
          status == 'INVALID_REQUEST' ||
          status == 'OVER_QUERY_LIMIT') {
        throw Exception(status);
      }

      final results = decoded['results'];
      if (results is! List) {
        continue;
      }

      for (final item in results) {
        if (item is! Map<String, dynamic>) {
          continue;
        }
        final placeId = item['place_id']?.toString();
        if (placeId == null || placeId.isEmpty || byId.containsKey(placeId)) {
          continue;
        }

        final geometry = item['geometry'];
        if (geometry is! Map<String, dynamic>) {
          continue;
        }
        final location = geometry['location'];
        if (location is! Map<String, dynamic>) {
          continue;
        }
        final lat = _parseCoordinate(location['lat']);
        final lon = _parseCoordinate(location['lng']);
        if (lat == null || lon == null) {
          continue;
        }

        final point = LatLng(lat, lon);
        if (!_isInMindanaoBounds(point)) {
          continue;
        }
        final distanceKm =
            Geolocator.distanceBetween(
              center.latitude,
              center.longitude,
              point.latitude,
              point.longitude,
            ) /
            1000;
        if (distanceKm > maxDistanceKm) {
          continue;
        }

        byId[placeId] = _trailFromPlacesItem(
          item: item,
          point: point,
          userCenter: center,
          fallbackName: 'Unknown mountain',
        );
      }
    }

    final baseTrails = byId.values.toList()
      ..sort((a, b) => a.distanceKm.compareTo(b.distanceKm));
    return _applyBatchElevations(baseTrails);
  }

  Future<List<_NearbyTrail>> _fetchNearbyTrailsByDistance(
    LatLng center, {
    required double maxDistanceKm,
    String? searchAnchorName,
  }) async {
    final keywords = <String>[
      'mountain',
      'mountain peak',
      'hiking trail',
      if (searchAnchorName != null && searchAnchorName.trim().isNotEmpty)
        'mountain near $searchAnchorName',
    ];
    final byId = <String, _NearbyTrail>{};

    for (final keyword in keywords) {
      final uri = Uri.https(
        'maps.googleapis.com',
        '/maps/api/place/nearbysearch/json',
        {
          'location': '${center.latitude},${center.longitude}',
          'rankby': 'distance',
          'keyword': keyword,
          'region': 'ph',
          'key': _mapsApiKey,
        },
      );

      final response = await http.get(uri).timeout(const Duration(seconds: 10));
      if (response.statusCode != 200) {
        continue;
      }
      final decoded = jsonDecode(response.body);
      if (decoded is! Map<String, dynamic>) {
        continue;
      }
      final status = decoded['status']?.toString() ?? '';
      if (status == 'REQUEST_DENIED' ||
          status == 'INVALID_REQUEST' ||
          status == 'OVER_QUERY_LIMIT') {
        throw Exception(status);
      }
      final results = decoded['results'];
      if (results is! List) {
        continue;
      }

      for (final item in results) {
        if (item is! Map<String, dynamic>) {
          continue;
        }
        final placeId = item['place_id']?.toString();
        if (placeId == null || placeId.isEmpty || byId.containsKey(placeId)) {
          continue;
        }

        final geometry = item['geometry'];
        if (geometry is! Map<String, dynamic>) {
          continue;
        }
        final location = geometry['location'];
        if (location is! Map<String, dynamic>) {
          continue;
        }
        final lat = _parseCoordinate(location['lat']);
        final lon = _parseCoordinate(location['lng']);
        if (lat == null || lon == null) {
          continue;
        }
        final point = LatLng(lat, lon);
        if (!_isInMindanaoBounds(point)) {
          continue;
        }
        final distanceKm = _distanceBetweenKm(center, point);
        if (distanceKm > maxDistanceKm) {
          continue;
        }

        byId[placeId] = _trailFromPlacesItem(
          item: item,
          point: point,
          userCenter: center,
          fallbackName: 'Unknown mountain',
        );
      }
    }

    final trails = byId.values.toList()
      ..sort((a, b) => a.distanceKm.compareTo(b.distanceKm));
    if (trails.isEmpty) {
      return const <_NearbyTrail>[];
    }
    return _applyBatchElevations(trails);
  }

  Future<List<_NearbyTrail>> _fetchNearbyTrailsFromNominatim(
    LatLng center, {
    required double maxDistanceKm,
    String? searchAnchorName,
  }) async {
    final byKey = <String, _NearbyTrail>{};
    final latDelta = maxDistanceKm / 111.0;
    final lonBase = math.max(
      0.2,
      111.0 * math.cos(center.latitude * math.pi / 180.0).abs(),
    );
    final lonDelta = maxDistanceKm / lonBase;
    final left = center.longitude - lonDelta;
    final right = center.longitude + lonDelta;
    final top = center.latitude + latDelta;
    final bottom = center.latitude - latDelta;
    final viewbox = '$left,$top,$right,$bottom';
    final queries = <String>[
      'mountain',
      'peak',
      if (searchAnchorName != null && searchAnchorName.trim().isNotEmpty)
        'mountain near $searchAnchorName',
    ];

    for (final query in queries) {
      final uri = Uri.https('nominatim.openstreetmap.org', '/search', {
        'q': '$query, Mindanao, Philippines',
        'format': 'jsonv2',
        'limit': '30',
        'countrycodes': 'ph',
        'viewbox': viewbox,
        'bounded': '1',
      });

      final response = await http
          .get(
            uri,
            headers: const {
              'User-Agent': 'Agakbay/1.0',
              'Accept': 'application/json',
            },
          )
          .timeout(const Duration(seconds: 10));
      if (response.statusCode != 200) {
        continue;
      }

      final decoded = jsonDecode(response.body);
      if (decoded is! List) {
        continue;
      }

      for (final item in decoded) {
        if (item is! Map) {
          continue;
        }
        final lat = double.tryParse(item['lat']?.toString() ?? '');
        final lon = double.tryParse(item['lon']?.toString() ?? '');
        if (lat == null || lon == null) {
          continue;
        }
        final point = LatLng(lat, lon);
        if (!_isInMindanaoBounds(point)) {
          continue;
        }
        final distanceKm = _distanceBetweenKm(center, point);
        if (distanceKm > maxDistanceKm) {
          continue;
        }

        final displayName = item['display_name']?.toString().trim();
        final name = (displayName == null || displayName.isEmpty)
            ? 'Unknown mountain'
            : displayName.split(',').first.trim();
        final placeId = item['place_id']?.toString();
        final key = placeId == null || placeId.isEmpty
            ? 'nominatim_${point.latitude.toStringAsFixed(5)}_${point.longitude.toStringAsFixed(5)}'
            : 'nominatim_$placeId';
        if (byKey.containsKey(key)) {
          continue;
        }
        byKey[key] = _NearbyTrail(
          placeId: key,
          name: name,
          address: displayName ?? '',
          location: point,
          distanceKm: distanceKm,
          elevationMasl: 0,
          provinceOrCity: _extractProvinceOrCity(displayName ?? ''),
          difficulty: 'Moderate',
          status: 'Open',
          description: _buildMountainDescription(
            name: name,
            provinceOrCity: _extractProvinceOrCity(displayName ?? ''),
            difficulty: 'Moderate',
            elevationMasl: 0,
          ),
          imageUrl: null,
        );
      }
    }

    final trails = byKey.values.toList()
      ..sort((a, b) => a.distanceKm.compareTo(b.distanceKm));
    if (trails.isEmpty) {
      return const <_NearbyTrail>[];
    }
    return _applyBatchElevations(trails.take(30).toList());
  }

  String _buildGooglePhotoUrl(String photoReference) {
    return Uri.https('maps.googleapis.com', '/maps/api/place/photo', {
      'maxwidth': '600',
      'photo_reference': photoReference,
      'key': _mapsApiKey,
    }).toString();
  }

  _NearbyTrail _trailFromPlacesItem({
    required Map<String, dynamic> item,
    required LatLng point,
    required LatLng userCenter,
    required String fallbackName,
  }) {
    final placeId =
        item['place_id']?.toString() ??
        'place_${point.latitude.toStringAsFixed(5)}_${point.longitude.toStringAsFixed(5)}';
    final name = item['name']?.toString().trim().isNotEmpty == true
        ? item['name'].toString().trim()
        : fallbackName;
    final address = item['formatted_address']?.toString() ?? '';
    final provinceOrCity = _extractProvinceOrCity(address);
    final distanceKm = _distanceBetweenKm(userCenter, point);
    final elevationMasl = 0;
    final difficulty = 'Moderate';
    final status = _statusFromPlacesItem(item);

    final photos = item['photos'];
    String? imageUrl;
    if (photos is List && photos.isNotEmpty) {
      final firstPhoto = photos.first;
      if (firstPhoto is Map<String, dynamic>) {
        final photoRef = firstPhoto['photo_reference']?.toString();
        if (photoRef != null && photoRef.isNotEmpty) {
          imageUrl = _buildGooglePhotoUrl(photoRef);
        }
      }
    }

    return _NearbyTrail(
      placeId: placeId,
      name: name,
      address: address,
      location: point,
      distanceKm: distanceKm,
      elevationMasl: elevationMasl,
      provinceOrCity: provinceOrCity,
      difficulty: difficulty,
      status: status,
      description: _buildMountainDescription(
        name: name,
        provinceOrCity: provinceOrCity,
        difficulty: difficulty,
        elevationMasl: elevationMasl,
      ),
      imageUrl: imageUrl,
    );
  }

  Future<List<_NearbyTrail>> _applyBatchElevations(
    List<_NearbyTrail> trails,
  ) async {
    if (trails.isEmpty) {
      return trails;
    }

    final elevations = await _fetchElevationMaslBatch(
      trails.map((trail) => trail.location).toList(),
    );

    return List<_NearbyTrail>.generate(trails.length, (index) {
      final base = trails[index];
      final elevation = index < elevations.length ? elevations[index] : 0;
      final difficulty = _difficultyFromElevation(elevation);

      return _NearbyTrail(
        placeId: base.placeId,
        name: base.name,
        address: base.address,
        location: base.location,
        distanceKm: base.distanceKm,
        elevationMasl: elevation,
        provinceOrCity: base.provinceOrCity,
        difficulty: difficulty,
        status: base.status,
        description: _buildMountainDescription(
          name: base.name,
          provinceOrCity: base.provinceOrCity,
          difficulty: difficulty,
          elevationMasl: elevation,
        ),
        imageUrl: base.imageUrl,
      );
    });
  }

  Future<int> _fetchElevationMasl(LatLng point) async {
    return _fetchAccurateElevationMasl(point);
  }

  String _elevationCacheKey(LatLng point) {
    return '${point.latitude.toStringAsFixed(5)},${point.longitude.toStringAsFixed(5)}';
  }

  Future<_NearbyTrail> _resolveTrailElevation(_NearbyTrail trail) async {
    final key = _elevationCacheKey(trail.location);
    final cached = _elevationMaslCache[key];
    if (cached != null) {
      return _withTrailElevation(trail, cached);
    }
    final elevation = await _fetchAccurateElevationMasl(trail.location);
    _elevationMaslCache[key] = elevation;
    return _withTrailElevation(trail, elevation);
  }

  _NearbyTrail _withTrailElevation(_NearbyTrail trail, int elevationMasl) {
    final difficulty = _difficultyFromElevation(elevationMasl);
    return _NearbyTrail(
      placeId: trail.placeId,
      name: trail.name,
      address: trail.address,
      location: trail.location,
      distanceKm: trail.distanceKm,
      elevationMasl: elevationMasl,
      provinceOrCity: trail.provinceOrCity,
      difficulty: difficulty,
      status: trail.status,
      description: _buildMountainDescription(
        name: trail.name,
        provinceOrCity: trail.provinceOrCity,
        difficulty: difficulty,
        elevationMasl: elevationMasl,
      ),
      imageUrl: trail.imageUrl,
    );
  }

  Future<int> _fetchAccurateElevationMasl(LatLng point) async {
    final key = _elevationCacheKey(point);
    final cached = _elevationMaslCache[key];
    if (cached != null) {
      return cached;
    }

    await _loadMapsApiKey();
    if (_mapsApiKey.isNotEmpty) {
      final googleElevation = await _fetchGoogleElevationMasl(point);
      if (googleElevation != null) {
        _elevationMaslCache[key] = googleElevation;
        return googleElevation;
      }
    }

    final elevations = await _fetchElevationMaslBatch([point]);
    final fallback = elevations.isEmpty ? 0 : elevations.first;
    _elevationMaslCache[key] = fallback;
    return fallback;
  }

  Future<int?> _fetchGoogleElevationMasl(LatLng point) async {
    try {
      final uri = Uri.https('maps.googleapis.com', '/maps/api/elevation/json', {
        'locations': '${point.latitude},${point.longitude}',
        'key': _mapsApiKey,
      });
      final response = await http.get(uri).timeout(const Duration(seconds: 5));
      if (response.statusCode != 200) {
        return null;
      }
      final decoded = jsonDecode(response.body);
      if (decoded is! Map<String, dynamic>) {
        return null;
      }
      if ((decoded['status']?.toString() ?? '') != 'OK') {
        return null;
      }
      final results = decoded['results'];
      if (results is! List || results.isEmpty) {
        return null;
      }
      final first = results.first;
      if (first is! Map<String, dynamic>) {
        return null;
      }
      final rawElevation = first['elevation'];
      if (rawElevation is! num) {
        return null;
      }
      return rawElevation.round();
    } catch (_) {
      return null;
    }
  }

  Future<List<int>> _fetchElevationMaslBatch(List<LatLng> points) async {
    if (points.isEmpty) {
      return const [];
    }

    try {
      final latitudes = points
          .map((point) => point.latitude.toString())
          .join(',');
      final longitudes = points
          .map((point) => point.longitude.toString())
          .join(',');

      final uri = Uri.https('api.open-meteo.com', '/v1/elevation', {
        'latitude': latitudes,
        'longitude': longitudes,
      });

      final response = await http.get(uri).timeout(const Duration(seconds: 4));
      if (response.statusCode != 200) {
        return List<int>.filled(points.length, 0);
      }

      final decoded = jsonDecode(response.body);
      if (decoded is! Map<String, dynamic>) {
        return List<int>.filled(points.length, 0);
      }

      final rawElevations = decoded['elevation'];
      if (rawElevations is List) {
        final values = rawElevations
            .map((value) => value is num ? value.round() : 0)
            .toList();
        if (values.length < points.length) {
          values.addAll(List<int>.filled(points.length - values.length, 0));
        }
        return values;
      }

      if (rawElevations is num) {
        return List<int>.filled(points.length, rawElevations.round());
      }

      return List<int>.filled(points.length, 0);
    } catch (_) {
      return List<int>.filled(points.length, 0);
    }
  }

  String _extractProvinceOrCity(String address) {
    if (address.trim().isEmpty) {
      return 'Mindanao';
    }
    final parts = address
        .split(',')
        .map((part) => part.trim())
        .where((part) => part.isNotEmpty)
        .toList();
    for (final part in parts) {
      final lower = part.toLowerCase();
      if (lower.contains('city') || lower.contains('province')) {
        return part;
      }
    }
    if (parts.length >= 2) {
      return parts[parts.length - 2];
    }
    return parts.first;
  }

  String _difficultyFromElevation(int elevationMasl) {
    if (elevationMasl <= 0) {
      return 'Unknown';
    }
    if (elevationMasl >= 2200) {
      return 'Hard';
    }
    if (elevationMasl >= 1200) {
      return 'Moderate';
    }
    return 'Easy';
  }

  String _statusFromPlacesItem(Map<String, dynamic> item) {
    final openingHours = item['opening_hours'];
    if (openingHours is Map<String, dynamic>) {
      final openNow = openingHours['open_now'];
      if (openNow is bool) {
        return openNow ? 'Open' : 'Closed';
      }
    }
    final businessStatus = item['business_status']?.toString().toUpperCase();
    if (businessStatus == 'CLOSED_TEMPORARILY' ||
        businessStatus == 'CLOSED_PERMANENTLY') {
      return 'Closed';
    }
    return 'Open';
  }

  String _buildMountainDescription({
    required String name,
    required String provinceOrCity,
    required String difficulty,
    required int elevationMasl,
  }) {
    final elevationText = elevationMasl > 0
        ? '$elevationMasl MASL'
        : 'unknown elevation';
    return '$name is located near $provinceOrCity at $elevationText. '
        'This trail is rated $difficulty and is popular for hiking adventures.';
  }

  Future<void> _focusTrail(_NearbyTrail trail) async {
    setState(() {
      _searchMarker = Marker(
        markerId: MarkerId('trail_${trail.placeId}'),
        position: trail.location,
        icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueGreen),
        infoWindow: InfoWindow(title: trail.name, snippet: trail.address),
        onTap: () {
          _openMountainDetailsCard(trail);
        },
      );
      _currentCenter = trail.location;
      _locationMessage = null;
    });
    await _mapController?.animateCamera(
      CameraUpdate.newCameraPosition(
        CameraPosition(target: trail.location, zoom: 13.8),
      ),
    );
  }

  Future<void> _focusTrailAndOpenDetails(
    _NearbyTrail trail, {
    Duration? delayBeforeDetails,
  }) async {
    _rememberTrail(trail);
    await _focusTrail(trail);
    if (delayBeforeDetails != null) {
      await Future<void>.delayed(delayBeforeDetails);
    }
    if (!mounted) {
      return;
    }
    await _openMountainDetailsCard(trail);
  }

  void _rememberTrail(_NearbyTrail trail) {
    _trailLibrary[trail.placeId] = trail;
  }

  void _rememberTrails(Iterable<_NearbyTrail> trails) {
    for (final trail in trails) {
      _rememberTrail(trail);
    }
  }

  void _showDashboardSnackBar(String message) {
    if (!mounted) {
      return;
    }
    final messenger = ScaffoldMessenger.of(context);
    messenger.hideCurrentSnackBar();
    messenger.showSnackBar(SnackBar(content: Text(message)));
  }

  String _communityDisplayName() {
    final user = _firebaseAuth.currentUser;
    if (user == null) {
      return 'Guest Hiker';
    }
    final displayName = user.displayName?.trim() ?? '';
    if (displayName.isNotEmpty) {
      return displayName;
    }
    final email = user.email?.trim() ?? '';
    if (email.contains('@')) {
      return email.split('@').first;
    }
    return 'Hiker';
  }

  String _communityAvatarSeed(String name) {
    final trimmed = name.trim();
    if (trimmed.isEmpty) {
      return '?';
    }
    return trimmed[0].toUpperCase();
  }

  _CommunityPost _communityPostFromSnapshot(
    DocumentSnapshot<Map<String, dynamic>> snapshot,
  ) {
    final data = snapshot.data() ?? <String, dynamic>{};
    final createdAtRaw = data['createdAt'];
    DateTime? createdAt;
    if (createdAtRaw is Timestamp) {
      createdAt = createdAtRaw.toDate();
    }
    return _CommunityPost(
      id: snapshot.id,
      authorId: data['authorId']?.toString() ?? '',
      authorName: data['authorName']?.toString().trim().isNotEmpty == true
          ? data['authorName'].toString().trim()
          : 'Hiker',
      content: data['content']?.toString() ?? '',
      mountainName: data['mountainName']?.toString() ?? '',
      likeCount: data['likeCount'] is num
          ? (data['likeCount'] as num).toInt()
          : 0,
      commentCount: data['commentCount'] is num
          ? (data['commentCount'] as num).toInt()
          : 0,
      createdAt: createdAt,
    );
  }

  Stream<QuerySnapshot<Map<String, dynamic>>> _communityPostsStream() {
    return _firestore
        .collection('community_posts')
        .orderBy('createdAt', descending: true)
        .limit(80)
        .snapshots();
  }

  Future<void> _createCommunityPost(String content) async {
    final user = _firebaseAuth.currentUser;
    if (user == null) {
      _showDashboardSnackBar('Please sign in to create a post.');
      return;
    }
    final text = content.trim();
    if (text.isEmpty) {
      _showDashboardSnackBar('Write something before posting.');
      return;
    }
    try {
      await _firestore.collection('community_posts').add({
        'authorId': user.uid,
        'authorName': _communityDisplayName(),
        'content': text,
        'mountainName': _searchedTrailAnchor?.name ?? '',
        'likeCount': 0,
        'commentCount': 0,
        'createdAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      });
    } catch (_) {
      _showDashboardSnackBar('Failed to publish post.');
    }
  }

  Future<void> _toggleCommunityPostLike(_CommunityPost post) async {
    final user = _firebaseAuth.currentUser;
    if (user == null) {
      _showDashboardSnackBar('Please sign in to like posts.');
      return;
    }
    final postRef = _firestore.collection('community_posts').doc(post.id);
    final likeRef = postRef.collection('likes').doc(user.uid);
    try {
      await _firestore.runTransaction((tx) async {
        final postSnap = await tx.get(postRef);
        if (!postSnap.exists) {
          return;
        }
        final likeSnap = await tx.get(likeRef);
        final current = (postSnap.data()?['likeCount'] is num)
            ? (postSnap.data()!['likeCount'] as num).toInt()
            : 0;
        if (likeSnap.exists) {
          tx.delete(likeRef);
          tx.update(postRef, {
            'likeCount': current > 0 ? current - 1 : 0,
            'updatedAt': FieldValue.serverTimestamp(),
          });
        } else {
          tx.set(likeRef, {
            'userId': user.uid,
            'createdAt': FieldValue.serverTimestamp(),
          });
          tx.update(postRef, {
            'likeCount': current + 1,
            'updatedAt': FieldValue.serverTimestamp(),
          });
        }
      });
    } catch (_) {
      _showDashboardSnackBar('Unable to update like.');
    }
  }

  Future<void> _addCommunityComment(String postId, String content) async {
    final user = _firebaseAuth.currentUser;
    if (user == null) {
      _showDashboardSnackBar('Please sign in to comment.');
      return;
    }
    final text = content.trim();
    if (text.isEmpty) {
      return;
    }
    final postRef = _firestore.collection('community_posts').doc(postId);
    try {
      await _firestore.runTransaction((tx) async {
        final postSnap = await tx.get(postRef);
        if (!postSnap.exists) {
          return;
        }
        final current = (postSnap.data()?['commentCount'] is num)
            ? (postSnap.data()!['commentCount'] as num).toInt()
            : 0;
        final commentRef = postRef.collection('comments').doc();
        tx.set(commentRef, {
          'authorId': user.uid,
          'authorName': _communityDisplayName(),
          'content': text,
          'createdAt': FieldValue.serverTimestamp(),
        });
        tx.update(postRef, {
          'commentCount': current + 1,
          'updatedAt': FieldValue.serverTimestamp(),
        });
      });
    } catch (_) {
      _showDashboardSnackBar('Unable to post comment.');
    }
  }

  Future<void> _openCommunityPostDetails(_CommunityPost post) async {
    final commentController = TextEditingController();
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) {
        return FractionallySizedBox(
          heightFactor: 0.9,
          child: Container(
            decoration: const BoxDecoration(
              color: Color(0xFF02130E),
              borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
            ),
            child: Column(
              children: [
                const SizedBox(height: 10),
                Container(
                  width: 44,
                  height: 4,
                  decoration: BoxDecoration(
                    color: Colors.white24,
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 8, 8),
                  child: Row(
                    children: [
                      const Expanded(
                        child: Text(
                          'Post Details',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 20,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                      IconButton(
                        onPressed: () => Navigator.of(sheetContext).pop(),
                        icon: const Icon(
                          Icons.close_rounded,
                          color: Colors.white70,
                        ),
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: ListView(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                    children: [
                      _communityPostCard(post, showCommentAction: false),
                      const SizedBox(height: 12),
                      const Text(
                        'Comments',
                        style: TextStyle(
                          color: Color(0xFF7CF9A2),
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 8),
                      StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                        stream: _firestore
                            .collection('community_posts')
                            .doc(post.id)
                            .collection('comments')
                            .orderBy('createdAt', descending: false)
                            .limit(200)
                            .snapshots(),
                        builder: (context, snapshot) {
                          if (snapshot.connectionState ==
                              ConnectionState.waiting) {
                            return const Padding(
                              padding: EdgeInsets.symmetric(vertical: 16),
                              child: Center(
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: Color(0xFF7CF9A2),
                                ),
                              ),
                            );
                          }
                          final docs = snapshot.data?.docs ?? const [];
                          if (docs.isEmpty) {
                            return Text(
                              'No comments yet.',
                              style: TextStyle(
                                color: Colors.white.withValues(alpha: 0.75),
                              ),
                            );
                          }
                          return Column(
                            children: docs.map((doc) {
                              final data = doc.data();
                              final author =
                                  data['authorName']?.toString() ?? 'Hiker';
                              final content = data['content']?.toString() ?? '';
                              DateTime? createdAt;
                              if (data['createdAt'] is Timestamp) {
                                createdAt = (data['createdAt'] as Timestamp)
                                    .toDate();
                              }
                              return Container(
                                width: double.infinity,
                                margin: const EdgeInsets.only(bottom: 8),
                                padding: const EdgeInsets.all(10),
                                decoration: BoxDecoration(
                                  color: Colors.white.withValues(alpha: 0.04),
                                  borderRadius: BorderRadius.circular(10),
                                ),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      author,
                                      style: const TextStyle(
                                        color: Colors.white,
                                        fontWeight: FontWeight.w700,
                                      ),
                                    ),
                                    const SizedBox(height: 4),
                                    Text(
                                      content,
                                      style: const TextStyle(
                                        color: Colors.white,
                                      ),
                                    ),
                                    if (createdAt != null) ...[
                                      const SizedBox(height: 4),
                                      Text(
                                        _formatDate(createdAt),
                                        style: TextStyle(
                                          color: Colors.white.withValues(
                                            alpha: 0.6,
                                          ),
                                          fontSize: 11,
                                        ),
                                      ),
                                    ],
                                  ],
                                ),
                              );
                            }).toList(),
                          );
                        },
                      ),
                    ],
                  ),
                ),
                SafeArea(
                  top: false,
                  minimum: const EdgeInsets.fromLTRB(12, 8, 12, 12),
                  child: Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: commentController,
                          maxLines: 2,
                          minLines: 1,
                          style: const TextStyle(color: Colors.white),
                          decoration: InputDecoration(
                            hintText: 'Add a comment...',
                            hintStyle: TextStyle(
                              color: Colors.white.withValues(alpha: 0.6),
                            ),
                            filled: true,
                            fillColor: Colors.white.withValues(alpha: 0.07),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                              borderSide: BorderSide.none,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      SizedBox(
                        height: 46,
                        child: ElevatedButton(
                          onPressed: () async {
                            final text = commentController.text.trim();
                            if (text.isEmpty) {
                              return;
                            }
                            commentController.clear();
                            await _addCommunityComment(post.id, text);
                          },
                          style: ElevatedButton.styleFrom(
                            foregroundColor: Colors.black,
                            backgroundColor: const Color(0xFF53D97A),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                          ),
                          child: const Text('Post'),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
    commentController.dispose();
  }

  String _normalizeTokenString(String value) {
    return value
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9]+'), '_')
        .replaceAll(RegExp(r'_+'), '_')
        .replaceAll(RegExp(r'^_|_$'), '');
  }

  String _mountainKeyForTrail(_NearbyTrail trail) {
    final nameKey = _normalizeTokenString(trail.name);
    final areaKey = _normalizeTokenString(trail.provinceOrCity);
    if (areaKey.isEmpty) {
      return nameKey;
    }
    return '${nameKey}__$areaKey';
  }

  String _normalizeTokenWords(String value) {
    return value.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]+'), ' ').trim();
  }

  Set<String> _mountainTokens(String mountainName) {
    const ignoredTokens = <String>{
      'mount',
      'mountain',
      'mt',
      'peak',
      'trail',
      'site',
      'route',
      'hike',
      'wikiloc',
    };
    return _normalizeTokenWords(mountainName)
        .split(' ')
        .where((token) => token.length >= 3 && !ignoredTokens.contains(token))
        .toSet();
  }

  double _scoreGpxAssetForMountain(
    String assetPath,
    Set<String> mountainTokens,
  ) {
    final fileName = assetPath.split('/').last.replaceAll('.gpx', '');
    final normalizedAsset = _normalizeTokenWords(fileName);
    final assetTokens = normalizedAsset
        .split(' ')
        .where((token) => token.length >= 3)
        .toSet();
    var score = 0.0;
    for (final token in mountainTokens) {
      if (assetTokens.contains(token)) {
        score += 2;
      } else if (normalizedAsset.contains(token)) {
        score += 1;
      }
    }
    return score;
  }

  List<String> _matchingGpxAssetsForMountain(
    List<String> gpxAssets,
    String mountainName,
  ) {
    final tokens = _mountainTokens(mountainName);
    if (tokens.isEmpty) {
      return const <String>[];
    }
    final ranked =
        gpxAssets
            .map(
              (asset) =>
                  MapEntry(asset, _scoreGpxAssetForMountain(asset, tokens)),
            )
            .where((entry) => entry.value >= 2)
            .toList()
          ..sort((a, b) => b.value.compareTo(a.value));
    return ranked.map((entry) => entry.key).toList();
  }

  _GpxRoutePreview? _parseGpxRoutePreview(String gpxRaw) {
    final trkPointRegex = RegExp(
      r'<trkpt\b[^>]*\blat="([^"]+)"[^>]*\blon="([^"]+)"[^>]*>',
      caseSensitive: false,
    );
    LatLng? start;
    LatLng? end;
    for (final match in trkPointRegex.allMatches(gpxRaw)) {
      final lat = double.tryParse(match.group(1) ?? '');
      final lon = double.tryParse(match.group(2) ?? '');
      if (lat == null || lon == null) {
        continue;
      }
      start ??= LatLng(lat, lon);
      end = LatLng(lat, lon);
    }
    if (start != null && end != null) {
      return _GpxRoutePreview(startPoint: start);
    }

    final rtePointRegex = RegExp(
      r'<rtept\b[^>]*\blat="([^"]+)"[^>]*\blon="([^"]+)"[^>]*/?>',
      caseSensitive: false,
    );
    for (final match in rtePointRegex.allMatches(gpxRaw)) {
      final lat = double.tryParse(match.group(1) ?? '');
      final lon = double.tryParse(match.group(2) ?? '');
      if (lat == null || lon == null) {
        continue;
      }
      start ??= LatLng(lat, lon);
      end = LatLng(lat, lon);
    }
    if (start != null && end != null) {
      return _GpxRoutePreview(startPoint: start);
    }
    return null;
  }

  String _titleCaseWords(String value) {
    final words = value
        .split(' ')
        .where((word) => word.trim().isNotEmpty)
        .toList();
    return words
        .map(
          (word) => word.length == 1
              ? word.toUpperCase()
              : '${word[0].toUpperCase()}${word.substring(1)}',
        )
        .join(' ');
  }

  String _routeNameFromAssetPath(String assetPath, String mountainName) {
    final fileName = assetPath.split('/').last.replaceAll('.gpx', '');
    final normalized = _normalizeTokenWords(fileName);
    if (normalized.contains('sibulan') || normalized.contains('sta cruz')) {
      return 'Sibulan / Sta. Cruz Trail';
    }
    if (normalized.contains('kapatagan') ||
        normalized.contains('mainit') ||
        normalized.contains('digos')) {
      return 'Kapatagan Trail';
    }
    if (normalized.contains('mandarangan') ||
        normalized.contains('mandangan') ||
        normalized.contains('kidapawan') ||
        normalized.contains('ilomavis') ||
        normalized.contains('agco')) {
      return 'Mandarangan (Kidapawan) Trail';
    }
    if (normalized.contains('magpet') || normalized.contains('bongolanon')) {
      return 'Magpet (Bongolanon) Trail';
    }
    if (normalized.contains('venado')) {
      return 'Lake Venado Trail';
    }

    final mountainTokens = _mountainTokens(mountainName);
    final remainingTokens = normalized
        .split(' ')
        .where(
          (token) =>
              token.length >= 3 &&
              !mountainTokens.contains(token) &&
              token != 'trail' &&
              token != 'route' &&
              token != 'day' &&
              token != 'gpx',
        )
        .toList();
    if (remainingTokens.isNotEmpty) {
      return '${_titleCaseWords(remainingTokens.join(' '))} Trail';
    }
    return '${_titleCaseWords(mountainName)} Trail';
  }

  String _jumpOffLabelFromRouteName(String routeName) {
    final lower = routeName.toLowerCase();
    if (lower.contains('sibulan')) {
      return 'Baruring / Sibulan (Sta. Cruz)';
    }
    if (lower.contains('kapatagan')) {
      return 'Mainit / Kapatagan (Digos)';
    }
    if (lower.contains('mandarangan')) {
      return 'Ilomavis / Lake Agco (Kidapawan)';
    }
    if (lower.contains('magpet')) {
      return 'Bongolanon (Magpet)';
    }
    if (lower.contains('venado')) {
      return 'Lake Venado side';
    }
    return 'See route briefing';
  }

  String _formatLatLngCompact(LatLng point) {
    return '${point.latitude.toStringAsFixed(5)}, ${point.longitude.toStringAsFixed(5)}';
  }

  Future<List<_MountainRouteOption>> _loadMountainRouteOptions(
    _NearbyTrail trail,
  ) async {
    final cacheKey = _normalizeTokenString(trail.name);
    if (_mountainRouteOptionsCache.containsKey(cacheKey)) {
      return _mountainRouteOptionsCache[cacheKey]!;
    }

    try {
      final manifest = await AssetManifest.loadFromAssetBundle(rootBundle);
      final allAssets = manifest.listAssets();
      final gpxAssets = allAssets
          .where(
            (asset) =>
                asset.startsWith('assets/trails/') &&
                asset.toLowerCase().endsWith('.gpx'),
          )
          .toList();
      if (gpxAssets.isEmpty) {
        _mountainRouteOptionsCache[cacheKey] = const <_MountainRouteOption>[];
        return const <_MountainRouteOption>[];
      }

      final matchedAssets = _matchingGpxAssetsForMountain(
        gpxAssets,
        trail.name,
      );
      final options = <_MountainRouteOption>[];
      for (final asset in matchedAssets) {
        try {
          final gpxRaw = await rootBundle.loadString(asset);
          final preview = _parseGpxRoutePreview(gpxRaw);
          if (preview == null) {
            continue;
          }
          final routeName = _routeNameFromAssetPath(asset, trail.name);
          options.add(
            _MountainRouteOption(
              assetPath: asset,
              routeName: routeName,
              jumpOffLabel: _jumpOffLabelFromRouteName(routeName),
              startPoint: preview.startPoint,
            ),
          );
        } catch (_) {
          // Skip unreadable GPX files.
        }
      }

      final deduped = <String, _MountainRouteOption>{};
      for (final option in options) {
        deduped[option.routeName.toLowerCase()] = option;
      }
      final sorted = deduped.values.toList()
        ..sort((a, b) => a.routeName.compareTo(b.routeName));
      _mountainRouteOptionsCache[cacheKey] = sorted;
      return sorted;
    } catch (_) {
      return const <_MountainRouteOption>[];
    }
  }

  Future<List<LatLng>> _loadRoomRoutePoints(
    _MountainRouteOption? selectedRoute,
    _CommunityTrailData? communityTrail,
  ) async {
    if (selectedRoute != null) {
      try {
        final gpxRaw = await rootBundle.loadString(selectedRoute.assetPath);
        final points = <LatLng>[];
        final pointRegex = RegExp(
          r'<(?:trkpt|rtept)\b[^>]*\blat="([^"]+)"[^>]*\blon="([^"]+)"[^>]*>',
          caseSensitive: false,
        );
        for (final match in pointRegex.allMatches(gpxRaw)) {
          final lat = double.tryParse(match.group(1) ?? '');
          final lon = double.tryParse(match.group(2) ?? '');
          if (lat != null && lon != null) {
            points.add(LatLng(lat, lon));
          }
        }
        if (points.length >= 2) {
          return _downsampleRoomRoute(points);
        }
      } catch (_) {
        // A community route can still be used as the fallback.
      }
    }
    if (communityTrail != null && communityTrail.points.length >= 2) {
      return _downsampleRoomRoute(communityTrail.points);
    }
    return const <LatLng>[];
  }

  List<LatLng> _downsampleRoomRoute(List<LatLng> points) {
    const maxPoints = 1200;
    if (points.length <= maxPoints) return List<LatLng>.from(points);
    final result = <LatLng>[];
    final step = (points.length - 1) / (maxPoints - 1);
    for (var index = 0; index < maxPoints; index++) {
      result.add(points[(index * step).round().clamp(0, points.length - 1)]);
    }
    result[result.length - 1] = points.last;
    return result;
  }

  Future<void> _createHikeRoomForMountain(
    _NearbyTrail trail,
    _MountainRouteOption? selectedRoute,
    _CommunityTrailData? communityTrail,
  ) async {
    final routePoints = await _loadRoomRoutePoints(
      selectedRoute,
      communityTrail,
    );
    if (routePoints.length < 2) {
      _showDashboardSnackBar(
        'This mountain needs a mapped trail route before a room can be created.',
      );
      return;
    }
    try {
      await _hikeRoomService.createRoom(
        mountainName: trail.name,
        mountainPlaceId: trail.placeId,
        mountainLatitude: trail.location.latitude,
        mountainLongitude: trail.location.longitude,
        routeName: selectedRoute?.routeName ?? 'Community ${trail.name} Trail',
        jumpOffLabel: selectedRoute?.jumpOffLabel ?? 'Community route',
        routeAssetPath: selectedRoute?.assetPath ?? '',
        routePoints: routePoints
            .map((point) => HikeRoomRoutePoint(point.latitude, point.longitude))
            .toList(growable: false),
      );
      if (!mounted) return;
      Navigator.of(context).pop();
      await Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => HikeRoomScreen(onStartHiking: _startHikingFromRoom),
        ),
      );
    } catch (error) {
      _showDashboardSnackBar(
        error
            .toString()
            .replaceFirst('Bad state: ', '')
            .replaceFirst('Invalid argument(s): ', ''),
      );
    }
  }

  Future<void> _startHikingFromRoom(HikeRoom room) async {
    if (room.routePoints.length < 2) {
      _showDashboardSnackBar('This room does not have a usable trail route.');
      return;
    }
    final trail = _NearbyTrail(
      placeId: room.mountainPlaceId.isEmpty
          ? 'hike_room_${room.id}'
          : room.mountainPlaceId,
      name: room.mountainName,
      address: 'Route shared by ${room.guideName}',
      location: LatLng(room.mountainLatitude, room.mountainLongitude),
      provinceOrCity: 'Hike room',
      status: 'Open',
      description: 'Shared ${room.routeName} route.',
    );
    final sharedRoute = _CommunityTrailData(
      mountainKey: room.id,
      status: 'verified',
      points: room.routePoints
          .map((point) => LatLng(point.latitude, point.longitude))
          .toList(growable: false),
      qualityScore: 1,
      submissionCount: 1,
      source: 'hike_room',
    );
    final session = await Navigator.of(context).push<_LiveHikeResult>(
      MaterialPageRoute<_LiveHikeResult>(
        builder: (_) => _HikingModeScreen(
          trail: trail,
          mapsApiKey: _mapsApiKey,
          communityTrail: sharedRoute,
          preferredGpxAssetPath: room.routeAssetPath.isEmpty
              ? null
              : room.routeAssetPath,
          selectedRouteLabel: room.routeName,
        ),
      ),
    );
    if (!mounted || session == null) return;
    setState(() {
      _rememberTrail(trail);
      _completedTrailIds.add(trail.placeId);
      _completedHikeSessions.insert(
        0,
        _CompletedHikeSession(
          trail: trail,
          completedAt: DateTime.now(),
          distanceKm: session.distanceKm,
          duration: session.duration,
          elevationGainMasl: session.elevationGainMasl,
          maxElevationMasl: session.maxElevationMasl,
          checkpointsReached: session.checkpointsReached,
          totalCheckpoints: session.totalCheckpoints,
          reachedSummit: session.reachedSummit,
        ),
      );
    });
    _showDashboardSnackBar('${room.mountainName} hike saved to My Hikes.');
    unawaited(_submitTrailRouteIfAccepted(trail, session));
  }

  List<Map<String, double>> _encodeRoutePoints(List<LatLng> points) {
    return points
        .map(
          (point) => <String, double>{
            'lat': point.latitude,
            'lon': point.longitude,
          },
        )
        .toList();
  }

  List<Map<String, dynamic>> _encodeTrackPoints(List<_TrailTrackPoint> points) {
    return points
        .map(
          (point) => <String, dynamic>{
            'lat': point.lat,
            'lon': point.lon,
            'ts': point.timestamp.toUtc().toIso8601String(),
            if (point.altitudeMasl != null) 'alt': point.altitudeMasl,
            if (point.accuracyMeters != null) 'acc': point.accuracyMeters,
            if (point.speedMps != null) 'spd': point.speedMps,
          },
        )
        .toList();
  }

  List<LatLng> _decodeLatLngList(dynamic raw) {
    if (raw is! List) {
      return const <LatLng>[];
    }
    final points = <LatLng>[];
    for (final item in raw) {
      if (item is GeoPoint) {
        points.add(LatLng(item.latitude, item.longitude));
        continue;
      }
      if (item is Map) {
        final lat = _parseCoordinate(item['lat']);
        final lon = _parseCoordinate(item['lon']);
        if (lat != null && lon != null) {
          points.add(LatLng(lat, lon));
        }
      }
    }
    return points;
  }

  Future<_CommunityTrailData?> _fetchCommunityTrail(
    _NearbyTrail trail, {
    bool forceRefresh = false,
  }) async {
    final key = _mountainKeyForTrail(trail);
    if (!forceRefresh && _communityTrailCache.containsKey(key)) {
      return _communityTrailCache[key];
    }
    try {
      final snapshot = await _firestore
          .collection('mountain_trails')
          .doc(key)
          .get();
      if (!snapshot.exists) {
        return null;
      }
      final data = snapshot.data();
      if (data == null) {
        return null;
      }
      final points = _decodeLatLngList(data['routePoints']);
      final status = (data['status']?.toString() ?? 'none').toLowerCase();
      final qualityScore = (data['qualityScore'] is num)
          ? (data['qualityScore'] as num).toDouble()
          : 0.0;
      final submissionCount = (data['submissionCount'] is num)
          ? (data['submissionCount'] as num).toInt()
          : 0;
      final updatedAtRaw = data['updatedAt'];
      DateTime? updatedAt;
      if (updatedAtRaw is Timestamp) {
        updatedAt = updatedAtRaw.toDate();
      }
      final communityTrail = _CommunityTrailData(
        mountainKey: key,
        status: status,
        points: points,
        qualityScore: qualityScore,
        submissionCount: submissionCount,
        source: data['source']?.toString(),
        updatedAt: updatedAt,
      );
      _communityTrailCache[key] = communityTrail;
      return communityTrail;
    } catch (_) {
      return null;
    }
  }

  Future<bool> _askSubmitTrailRoute(_NearbyTrail trail) async {
    final accepted = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          backgroundColor: const Color(0xFF072117),
          title: const Text(
            'Submit Route?',
            style: TextStyle(color: Colors.white),
          ),
          content: Text(
            'Share your ${trail.name} hike route to improve community trails?',
            style: TextStyle(color: Colors.white.withValues(alpha: 0.86)),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: const Text('Not Now'),
            ),
            ElevatedButton(
              onPressed: () => Navigator.of(dialogContext).pop(true),
              child: const Text('Submit'),
            ),
          ],
        );
      },
    );
    return accepted == true;
  }

  Future<void> _submitTrailRouteIfAccepted(
    _NearbyTrail trail,
    _LiveHikeResult hikeResult,
  ) async {
    if (_firebaseAuth.currentUser == null) {
      return;
    }
    final shouldSubmit = await _askSubmitTrailRoute(trail);
    if (!shouldSubmit || !mounted) {
      return;
    }
    try {
      final mountainKey = _mountainKeyForTrail(trail);
      final routePoints = hikeResult.routePoints;
      final trackPoints = hikeResult.trackPoints;
      if (routePoints.length < 2 || trackPoints.length < 2) {
        _showDashboardSnackBar('Route too short to submit.');
        return;
      }

      final estimatedQuality = _estimateSubmissionQuality(hikeResult);
      await OfflineActivityDatabase.instance.queueTrailSubmission({
        'mountainKey': mountainKey,
        'mountainName': trail.name,
        'provinceOrCity': trail.provinceOrCity,
        'submittedBy': _firebaseAuth.currentUser!.uid,
        'status': 'pending',
        'qualityScore': estimatedQuality,
        'source': 'mobile_hike_tracking',
        'distanceKm': hikeResult.distanceKm,
        'durationSeconds': hikeResult.duration.inSeconds,
        'elevationGainMasl': hikeResult.elevationGainMasl,
        'maxElevationMasl': hikeResult.maxElevationMasl,
        'reachedSummit': hikeResult.reachedSummit,
        'peak': {
          'lat': hikeResult.peakLocation.latitude,
          'lon': hikeResult.peakLocation.longitude,
        },
        'routePoints': _encodeRoutePoints(routePoints),
        'trackPoints': _encodeTrackPoints(trackPoints),
        'startedAt': hikeResult.startedAt.toUtc().toIso8601String(),
        'endedAt': hikeResult.endedAt.toUtc().toIso8601String(),
      });
      _showDashboardSnackBar(
        'Trail route saved. It will upload automatically when online.',
      );
      unawaited(ActivitySyncService.shared.syncPendingActivities());
    } catch (_) {
      _showDashboardSnackBar('Unable to save the trail submission locally.');
    }
  }

  double _estimateSubmissionQuality(_LiveHikeResult hikeResult) {
    var score = 0.0;
    if (hikeResult.distanceKm >= 2) {
      score += 0.2;
    }
    if (hikeResult.distanceKm >= 5) {
      score += 0.2;
    }
    if (hikeResult.duration.inMinutes >= 45) {
      score += 0.2;
    }
    if (hikeResult.elevationGainMasl >= 250) {
      score += 0.2;
    }
    if (hikeResult.reachedSummit) {
      score += 0.2;
    }
    return score.clamp(0.0, 1.0);
  }

  String _formatDuration(Duration duration) {
    final hours = duration.inHours;
    final minutes = duration.inMinutes.remainder(60);
    final seconds = duration.inSeconds.remainder(60);
    if (hours > 0) {
      return '${hours}h ${minutes.toString().padLeft(2, '0')}m';
    }
    if (minutes > 0) {
      return '${minutes}m ${seconds.toString().padLeft(2, '0')}s';
    }
    return '${seconds}s';
  }

  String _formatDate(DateTime dateTime) {
    final year = dateTime.year.toString().padLeft(4, '0');
    final month = dateTime.month.toString().padLeft(2, '0');
    final day = dateTime.day.toString().padLeft(2, '0');
    final hour = dateTime.hour.toString().padLeft(2, '0');
    final minute = dateTime.minute.toString().padLeft(2, '0');
    return '$year-$month-$day $hour:$minute';
  }

  double _distanceBetweenKm(LatLng from, LatLng to) {
    return Geolocator.distanceBetween(
          from.latitude,
          from.longitude,
          to.latitude,
          to.longitude,
        ) /
        1000;
  }

  double? _parseCoordinate(dynamic value) {
    if (value is num) {
      return value.toDouble();
    }
    return double.tryParse(value?.toString() ?? '');
  }

  String _distanceLabel(double km) {
    if (km < 0.1) {
      return '< 100 m away';
    }
    if (km < 1) {
      return '${(km * 1000).round()} m away';
    }
    if (km >= 100) {
      return '${km.toStringAsFixed(1)} km away';
    }
    if (km >= 10) {
      return '${km.toStringAsFixed(1)} km away';
    }
    return '${km.toStringAsFixed(1)} km away';
  }

  double? _displayDistanceKm(_NearbyTrail trail) {
    final roadKm = _roadDistanceKmCache[trail.placeId];
    if (roadKm != null) {
      return roadKm;
    }
    final myLocation = _myLocationCenter;
    if (myLocation != null) {
      return _distanceBetweenKm(myLocation, trail.location);
    }
    return null;
  }

  String _displayDistanceText(_NearbyTrail trail) {
    final km = _displayDistanceKm(trail);
    final isNearSearchAnchor =
        _nearbyAnchorMode == _NearbyAnchorMode.nearSearch &&
        _isSearchAnchorTrail(trail);
    final hasRoadDistance = _roadDistanceKmCache.containsKey(trail.placeId);
    final roadUnavailable = _roadDistanceUnavailable.contains(trail.placeId);
    if (km == null) {
      if (isNearSearchAnchor) {
        if (_myLocationCenter == null) {
          return 'Distance unavailable (enable location)';
        }
        if (roadUnavailable) {
          return 'Road distance unavailable';
        }
        return 'Calculating road distance...';
      }
      return 'Location unavailable';
    }
    if (isNearSearchAnchor) {
      if (hasRoadDistance) {
        return '${_distanceLabel(km)} from you (road)';
      }
      return 'Approx. ${_distanceLabel(km)} from you';
    }
    return _distanceLabel(km);
  }

  bool _isSearchAnchorTrail(_NearbyTrail trail) {
    final anchor = _searchedTrailAnchor;
    if (anchor == null) {
      return false;
    }
    return _isSameTrailIdentity(trail, anchor);
  }

  bool _isSameTrailIdentity(_NearbyTrail first, _NearbyTrail second) {
    if (first.placeId == second.placeId) {
      return true;
    }
    final sameName =
        _normalizeTokenWords(first.name) == _normalizeTokenWords(second.name);
    if (!sameName) {
      return false;
    }
    final distanceKm = _distanceBetweenKm(first.location, second.location);
    return distanceKm <= 2.5;
  }

  Future<_HikeWeatherForecast> _fetchHikeWeatherForecast(
    _NearbyTrail trail,
    DateTime date,
  ) async {
    await _loadWeatherApiKey();
    final today = _dateOnly(DateTime.now());
    final selectedDate = _dateOnly(date);
    final lastForecastDate = today.add(const Duration(days: 9));

    if (selectedDate.isBefore(today)) {
      throw const _WeatherForecastException(
        'Choose today or a future hike date.',
      );
    }
    if (selectedDate.isAfter(lastForecastDate)) {
      throw _WeatherForecastException(
        'Forecasts are available until ${_formatHikeDate(lastForecastDate)}.',
      );
    }
    if (_weatherApiKey.isEmpty) {
      throw const _WeatherForecastException(
        'Weather API key is missing. Check android/local.properties.',
      );
    }

    try {
      final forecastDays = await _fetchGoogleWeatherForecastDays(trail);
      if (forecastDays.isEmpty) {
        throw const _WeatherForecastException(
          'Weather forecast is unavailable for this hike date.',
        );
      }

      Map<String, dynamic>? selectedDay;
      for (final item in forecastDays) {
        if (item is! Map<String, dynamic>) {
          continue;
        }
        final displayDate = _googleDisplayDate(item['displayDate']);
        if (displayDate != null && _isSameDate(displayDate, selectedDate)) {
          selectedDay = item;
          break;
        }
      }
      if (selectedDay == null) {
        throw const _WeatherForecastException(
          'Weather forecast is unavailable for this hike date.',
        );
      }

      final daytimeForecast = selectedDay['daytimeForecast'];
      final nighttimeForecast = selectedDay['nighttimeForecast'];
      final primaryForecast = daytimeForecast is Map<String, dynamic>
          ? daytimeForecast
          : nighttimeForecast is Map<String, dynamic>
          ? nighttimeForecast
          : null;
      if (primaryForecast == null) {
        throw const _WeatherForecastException(
          'Weather forecast is unavailable for this hike date.',
        );
      }

      final condition = primaryForecast['weatherCondition'];
      final conditionMap = condition is Map<String, dynamic> ? condition : null;
      final description = conditionMap?['description'];
      final descriptionMap = description is Map<String, dynamic>
          ? description
          : null;
      final summary =
          descriptionMap?['text']?.toString().trim().isNotEmpty == true
          ? descriptionMap!['text'].toString().trim()
          : 'Forecast available';
      final conditionType = conditionMap?['type']?.toString() ?? '';
      final weatherCode = _weatherCodeFromGoogleCondition(conditionType);
      final tempMax = _googleTemperatureDegrees(selectedDay['maxTemperature']);
      final tempMin = _googleTemperatureDegrees(selectedDay['minTemperature']);
      final precipitationData = primaryForecast['precipitation'];
      final precipitationMap = precipitationData is Map<String, dynamic>
          ? precipitationData
          : null;
      final probability = precipitationMap?['probability'];
      final probabilityMap = probability is Map<String, dynamic>
          ? probability
          : null;
      final qpf = precipitationMap?['qpf'];
      final qpfMap = qpf is Map<String, dynamic> ? qpf : null;
      final wind = primaryForecast['wind'];
      final windMap = wind is Map<String, dynamic> ? wind : null;
      final windSpeedData = windMap?['speed'];
      final periodOutlooks = await _fetchGoogleWeatherPeriodOutlooks(
        trail,
        selectedDate,
      );
      final risk = _hikeWeatherRisk(
        weatherCode: weatherCode,
        rainChancePercent: _googleInt(probabilityMap?['percent']),
        precipitationMm: _googleDouble(qpfMap?['quantity']),
        windSpeedKmh: _googleSpeedKmh(windSpeedData),
      );

      return _HikeWeatherForecast(
        date: selectedDate,
        summary: summary,
        adviceTitle: _weatherAdviceTitle(risk),
        adviceDetail: _weatherAdviceDetail(risk),
        risk: risk,
        weatherCode: weatherCode,
        conditionType: conditionType,
        temperatureMinC: tempMin,
        temperatureMaxC: tempMax,
        rainChancePercent: _googleInt(probabilityMap?['percent']),
        precipitationMm: _googleDouble(qpfMap?['quantity']),
        windSpeedKmh: _googleSpeedKmh(windSpeedData),
        periodOutlooks: periodOutlooks,
      );
    } on _WeatherForecastException {
      rethrow;
    } catch (_) {
      throw const _WeatherForecastException(
        'Weather forecast is unavailable right now.',
      );
    }
  }

  Future<List<dynamic>> _fetchGoogleWeatherForecastDays(
    _NearbyTrail trail,
  ) async {
    final forecastDays = <dynamic>[];
    String? pageToken;

    for (var page = 0; page < 3; page++) {
      final query = <String, String>{
        'key': _weatherApiKey,
        'location.latitude': trail.location.latitude.toStringAsFixed(6),
        'location.longitude': trail.location.longitude.toStringAsFixed(6),
        'days': '10',
      };
      if (pageToken != null) {
        query['pageToken'] = pageToken;
      }
      final uri = Uri.https(
        'weather.googleapis.com',
        '/v1/forecast/days:lookup',
        query,
      );

      final response = await http.get(uri).timeout(const Duration(seconds: 8));
      final decoded = jsonDecode(response.body);
      if (decoded is! Map<String, dynamic>) {
        throw const _WeatherForecastException(
          'Weather forecast is unavailable right now.',
        );
      }
      if (response.statusCode != 200) {
        final reason = decoded['reason']?.toString().trim();
        throw _WeatherForecastException(
          reason == null || reason.isEmpty
              ? 'Weather forecast is unavailable right now.'
              : reason,
        );
      }

      final pageForecastDays = decoded['forecastDays'];
      if (pageForecastDays is List) {
        forecastDays.addAll(pageForecastDays);
      }

      final nextPageToken = decoded['nextPageToken']?.toString().trim();
      if (nextPageToken == null ||
          nextPageToken.isEmpty ||
          forecastDays.length >= 10) {
        break;
      }
      pageToken = nextPageToken;
    }

    return forecastDays;
  }

  Future<List<_HikeWeatherPeriodOutlook>> _fetchGoogleWeatherPeriodOutlooks(
    _NearbyTrail trail,
    DateTime selectedDate,
  ) async {
    final hourlyForecasts = await _fetchGoogleWeatherForecastHours(
      trail,
      selectedDate,
    );
    if (hourlyForecasts.isEmpty) {
      return const <_HikeWeatherPeriodOutlook>[];
    }

    final periods = <_HourlyWeatherPeriod>[
      const _HourlyWeatherPeriod('Early AM', '6-8 AM', 6, 8),
      const _HourlyWeatherPeriod('Midday', '10 AM-12 PM', 10, 12),
      const _HourlyWeatherPeriod('Afternoon', '1-5 PM', 13, 17),
      const _HourlyWeatherPeriod('Evening', '6-9 PM', 18, 21),
    ];

    final outlooks = <_HikeWeatherPeriodOutlook>[];
    for (final period in periods) {
      final periodHours = hourlyForecasts.where((item) {
        final displayDateTime = _googleDisplayDateTime(item['displayDateTime']);
        if (displayDateTime == null ||
            !_isSameDate(displayDateTime, selectedDate)) {
          return false;
        }
        return displayDateTime.hour >= period.startHour &&
            displayDateTime.hour <= period.endHour;
      }).toList();
      if (periodHours.isEmpty) {
        continue;
      }

      final mostImportantHour = _mostImportantHourlyForecast(periodHours);
      final condition = mostImportantHour['weatherCondition'];
      final conditionMap = condition is Map<String, dynamic> ? condition : null;
      final description = conditionMap?['description'];
      final descriptionMap = description is Map<String, dynamic>
          ? description
          : null;
      final summary =
          descriptionMap?['text']?.toString().trim().isNotEmpty == true
          ? descriptionMap!['text'].toString().trim()
          : 'Forecast available';
      final conditionType = conditionMap?['type']?.toString() ?? '';
      final weatherCode = _weatherCodeFromGoogleCondition(conditionType);
      final rainChance = periodHours
          .map(_googleHourlyRainChance)
          .whereType<int>()
          .fold<int?>(null, (maxValue, value) {
            if (maxValue == null || value > maxValue) {
              return value;
            }
            return maxValue;
          });
      final precipitation = periodHours
          .map(_googleHourlyPrecipitationMm)
          .whereType<double>()
          .fold<double?>(null, (total, value) => (total ?? 0) + value);
      final windSpeed = periodHours
          .map(_googleHourlyWindSpeedKmh)
          .whereType<double>()
          .fold<double?>(null, (maxValue, value) {
            if (maxValue == null || value > maxValue) {
              return value;
            }
            return maxValue;
          });
      final risk = _hikeWeatherRisk(
        weatherCode: weatherCode,
        rainChancePercent: rainChance,
        precipitationMm: precipitation,
        windSpeedKmh: windSpeed,
      );

      outlooks.add(
        _HikeWeatherPeriodOutlook(
          label: period.label,
          timeRange: period.timeRange,
          summary: summary,
          temperatureLabel: _googleHourlyTemperatureRangeLabel(periodHours),
          rainChancePercent: rainChance,
          risk: risk,
          weatherCode: weatherCode,
        ),
      );
    }

    return outlooks;
  }

  Future<List<Map<String, dynamic>>> _fetchGoogleWeatherForecastHours(
    _NearbyTrail trail,
    DateTime selectedDate,
  ) async {
    final hourlyForecasts = <Map<String, dynamic>>[];
    String? pageToken;
    var foundSelectedDate = false;

    for (var page = 0; page < 12; page++) {
      final query = <String, String>{
        'key': _weatherApiKey,
        'location.latitude': trail.location.latitude.toStringAsFixed(6),
        'location.longitude': trail.location.longitude.toStringAsFixed(6),
        'hours': '240',
      };
      if (pageToken != null) {
        query['pageToken'] = pageToken;
      }

      final uri = Uri.https(
        'weather.googleapis.com',
        '/v1/forecast/hours:lookup',
        query,
      );
      final response = await http.get(uri).timeout(const Duration(seconds: 8));
      final decoded = jsonDecode(response.body);
      if (decoded is! Map<String, dynamic>) {
        return hourlyForecasts;
      }
      if (response.statusCode != 200) {
        return hourlyForecasts;
      }

      final pageHours = decoded['forecastHours'];
      if (pageHours is List) {
        for (final item in pageHours) {
          if (item is! Map<String, dynamic>) {
            continue;
          }
          final displayDateTime = _googleDisplayDateTime(
            item['displayDateTime'],
          );
          if (displayDateTime == null) {
            continue;
          }
          if (_isSameDate(displayDateTime, selectedDate)) {
            foundSelectedDate = true;
            hourlyForecasts.add(item);
          } else if (foundSelectedDate &&
              displayDateTime.isAfter(selectedDate)) {
            return hourlyForecasts;
          }
        }
      }

      final nextPageToken = decoded['nextPageToken']?.toString().trim();
      if (nextPageToken == null || nextPageToken.isEmpty) {
        break;
      }
      pageToken = nextPageToken;
    }

    return hourlyForecasts;
  }

  Map<String, dynamic> _mostImportantHourlyForecast(
    List<Map<String, dynamic>> hours,
  ) {
    return hours.reduce((best, current) {
      final bestScore = _hourlyWeatherRiskScore(best);
      final currentScore = _hourlyWeatherRiskScore(current);
      return currentScore > bestScore ? current : best;
    });
  }

  int _hourlyWeatherRiskScore(Map<String, dynamic> hour) {
    final condition = hour['weatherCondition'];
    final conditionMap = condition is Map<String, dynamic> ? condition : null;
    final weatherCode = _weatherCodeFromGoogleCondition(
      conditionMap?['type']?.toString() ?? '',
    );
    final rainChance = _googleHourlyRainChance(hour) ?? 0;
    final thunderChance = _googleInt(hour['thunderstormProbability']) ?? 0;
    return weatherCode + rainChance + (thunderChance * 2);
  }

  DateTime? _googleDisplayDate(dynamic value) {
    if (value is! Map<String, dynamic>) {
      return null;
    }
    final year = _googleInt(value['year']);
    final month = _googleInt(value['month']);
    final day = _googleInt(value['day']);
    if (year == null || month == null || day == null) {
      return null;
    }
    return DateTime(year, month, day);
  }

  DateTime? _googleDisplayDateTime(dynamic value) {
    if (value is! Map<String, dynamic>) {
      return null;
    }
    final year = _googleInt(value['year']);
    final month = _googleInt(value['month']);
    final day = _googleInt(value['day']);
    final hour = _googleInt(value['hours']) ?? 0;
    final minute = _googleInt(value['minutes']) ?? 0;
    if (year == null || month == null || day == null) {
      return null;
    }
    return DateTime(year, month, day, hour, minute);
  }

  double? _googleTemperatureDegrees(dynamic value) {
    if (value is! Map<String, dynamic>) {
      return null;
    }
    return _googleDouble(value['degrees']);
  }

  double? _googleSpeedKmh(dynamic value) {
    if (value is! Map<String, dynamic>) {
      return null;
    }
    final speed = _googleDouble(value['value']);
    if (speed == null) {
      return null;
    }
    final unit = value['unit']?.toString().toUpperCase() ?? '';
    if (unit.contains('MILES_PER_HOUR')) {
      return speed * 1.609344;
    }
    if (unit.contains('METERS_PER_SECOND')) {
      return speed * 3.6;
    }
    return speed;
  }

  double? _googleHourlyTemperatureC(Map<String, dynamic> hour) {
    return _googleTemperatureDegrees(hour['temperature']);
  }

  int? _googleHourlyRainChance(Map<String, dynamic> hour) {
    final precipitation = hour['precipitation'];
    final precipitationMap = precipitation is Map<String, dynamic>
        ? precipitation
        : null;
    final probability = precipitationMap?['probability'];
    final probabilityMap = probability is Map<String, dynamic>
        ? probability
        : null;
    return _googleInt(probabilityMap?['percent']);
  }

  double? _googleHourlyPrecipitationMm(Map<String, dynamic> hour) {
    final precipitation = hour['precipitation'];
    final precipitationMap = precipitation is Map<String, dynamic>
        ? precipitation
        : null;
    final qpf = precipitationMap?['qpf'];
    final qpfMap = qpf is Map<String, dynamic> ? qpf : null;
    return _googleDouble(qpfMap?['quantity']);
  }

  double? _googleHourlyWindSpeedKmh(Map<String, dynamic> hour) {
    final wind = hour['wind'];
    final windMap = wind is Map<String, dynamic> ? wind : null;
    return _googleSpeedKmh(windMap?['speed']);
  }

  String _googleHourlyTemperatureRangeLabel(List<Map<String, dynamic>> hours) {
    final temperatures = hours
        .map(_googleHourlyTemperatureC)
        .whereType<double>()
        .toList();
    if (temperatures.isEmpty) {
      return 'Temp n/a';
    }
    final minTemp = temperatures.reduce(math.min).round();
    final maxTemp = temperatures.reduce(math.max).round();
    if (minTemp == maxTemp) {
      return '${maxTemp}C';
    }
    return '$minTemp-$maxTemp C';
  }

  double? _googleDouble(dynamic value) {
    if (value is num) {
      return value.toDouble();
    }
    return double.tryParse(value?.toString() ?? '');
  }

  int? _googleInt(dynamic value) {
    final parsed = _googleDouble(value);
    return parsed?.round();
  }

  int _weatherCodeFromGoogleCondition(String conditionType) {
    final type = conditionType.toUpperCase();
    if (type.contains('THUNDER')) {
      return 95;
    }
    if (type.contains('HEAVY') && type.contains('RAIN')) {
      return 65;
    }
    if (type.contains('SHOWERS')) {
      return type.contains('HEAVY') ? 82 : 80;
    }
    if (type.contains('RAIN')) {
      return 63;
    }
    if (type.contains('DRIZZLE')) {
      return 53;
    }
    if (type.contains('SNOW') || type.contains('ICE')) {
      return 71;
    }
    if (type.contains('FOG') || type.contains('HAZE')) {
      return 45;
    }
    if (type.contains('CLOUD')) {
      return type.contains('PARTLY') ? 2 : 3;
    }
    if (type.contains('CLEAR') || type.contains('SUNNY')) {
      return 0;
    }
    return 3;
  }

  _HikeWeatherRisk _hikeWeatherRisk({
    required int weatherCode,
    required int? rainChancePercent,
    required double? precipitationMm,
    required double? windSpeedKmh,
  }) {
    final rainChance = rainChancePercent ?? 0;
    final precipitation = precipitationMm ?? 0;
    final windSpeed = windSpeedKmh ?? 0;
    final stormy = weatherCode >= 95;
    final heavyRain =
        weatherCode == 65 || weatherCode == 67 || weatherCode == 82;

    if (stormy ||
        heavyRain ||
        rainChance >= 80 ||
        precipitation >= 20 ||
        windSpeed >= 45) {
      return _HikeWeatherRisk.unsafe;
    }
    if (_isWetWeatherCode(weatherCode) ||
        rainChance >= 50 ||
        precipitation >= 5 ||
        windSpeed >= 30) {
      return _HikeWeatherRisk.caution;
    }
    return _HikeWeatherRisk.good;
  }

  bool _isWetWeatherCode(int weatherCode) {
    return (weatherCode >= 51 && weatherCode <= 67) ||
        (weatherCode >= 71 && weatherCode <= 86) ||
        weatherCode >= 95;
  }

  String _weatherAdviceTitle(_HikeWeatherRisk risk) {
    return switch (risk) {
      _HikeWeatherRisk.good => 'Good for hiking',
      _HikeWeatherRisk.caution => 'Use caution',
      _HikeWeatherRisk.unsafe => 'Not recommended',
    };
  }

  String _weatherAdviceDetail(_HikeWeatherRisk risk) {
    return switch (risk) {
      _HikeWeatherRisk.good => 'Conditions look manageable for a planned hike.',
      _HikeWeatherRisk.caution =>
        'Trail may be slippery. Bring rain gear and check updates before leaving.',
      _HikeWeatherRisk.unsafe =>
        'Weather may be risky for hiking. Consider choosing another date.',
    };
  }

  DateTime _dateOnly(DateTime date) {
    return DateTime(date.year, date.month, date.day);
  }

  bool _isSameDate(DateTime first, DateTime second) {
    return first.year == second.year &&
        first.month == second.month &&
        first.day == second.day;
  }

  int _daysInMonth(DateTime month) {
    return DateTime(month.year, month.month + 1, 0).day;
  }

  bool _monthHasForecastableDates(
    DateTime month,
    DateTime firstDate,
    DateTime lastDate,
  ) {
    final monthStart = DateTime(month.year, month.month);
    final monthEnd = DateTime(month.year, month.month, _daysInMonth(month));
    return !monthEnd.isBefore(firstDate) && !monthStart.isAfter(lastDate);
  }

  String _formatHikeDate(DateTime date) {
    const months = <String>[
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'May',
      'Jun',
      'Jul',
      'Aug',
      'Sep',
      'Oct',
      'Nov',
      'Dec',
    ];
    return '${months[date.month - 1]} ${date.day}, ${date.year}';
  }

  String _formatMonthYear(DateTime date) {
    const months = <String>[
      'January',
      'February',
      'March',
      'April',
      'May',
      'June',
      'July',
      'August',
      'September',
      'October',
      'November',
      'December',
    ];
    return '${months[date.month - 1]} ${date.year}';
  }

  String _distanceContextLabel() {
    if (_myLocationCenter != null) {
      return 'from your location';
    }
    return '(enable location for distance)';
  }

  bool _isInMindanaoBounds(LatLng point) {
    return point.latitude >= _mindanaoBounds.southwest.latitude &&
        point.latitude <= _mindanaoBounds.northeast.latitude &&
        point.longitude >= _mindanaoBounds.southwest.longitude &&
        point.longitude <= _mindanaoBounds.northeast.longitude;
  }

  bool _matchesMarkerFilter(_NearbyTrail trail) {
    switch (_markerStatusFilter) {
      case _MarkerStatusFilter.all:
        return true;
      case _MarkerStatusFilter.open:
        return trail.status.trim().toLowerCase() == 'open';
      case _MarkerStatusFilter.closed:
        return trail.status.trim().toLowerCase() == 'closed';
    }
  }

  Set<Marker> _buildMapMarkers() {
    final markers = <Marker>{
      for (final trail in _nearbyTrails)
        if (_matchesMarkerFilter(trail))
          Marker(
            markerId: MarkerId('nearby_${trail.placeId}'),
            position: trail.location,
            infoWindow: InfoWindow(title: trail.name, snippet: trail.address),
            onTap: () {
              _openMountainDetailsCard(trail);
            },
          ),
    };

    if (_searchMarker != null) {
      markers.add(_searchMarker!);
    }

    return markers;
  }

  @override
  Widget build(BuildContext context) {
    final keyboardOpen = MediaQuery.of(context).viewInsets.bottom > 0;
    return Scaffold(
      body: _buildActiveTab(keyboardOpen),
      bottomNavigationBar: keyboardOpen ? null : _buildBottomNavigationBar(),
    );
  }

  Widget _buildActiveTab(bool keyboardOpen) {
    switch (_selectedNavIndex) {
      case 1:
        return _buildMyHikesTab();
      case 2:
        return _buildCommunityPlaceholderTab();
      case 3:
        return _buildProfileTab();
      case 0:
      default:
        return _buildExploreTab(keyboardOpen);
    }
  }

  Widget _buildBottomNavigationBar() {
    return BottomNavigationBar(
      currentIndex: _selectedNavIndex,
      onTap: (index) {
        setState(() {
          _selectedNavIndex = index;
        });
      },
      type: BottomNavigationBarType.fixed,
      backgroundColor: const Color(0xFF02130E),
      selectedItemColor: const Color(0xFF53D97A),
      unselectedItemColor: Colors.white70,
      items: const [
        BottomNavigationBarItem(
          icon: Icon(Icons.explore_rounded),
          label: 'Explore',
        ),
        BottomNavigationBarItem(
          icon: Icon(Icons.hiking_rounded),
          label: 'My Hikes',
        ),
        BottomNavigationBarItem(
          icon: Icon(Icons.forum_outlined),
          label: 'Community',
        ),
        BottomNavigationBarItem(
          icon: Icon(Icons.person_outline_rounded),
          label: 'Profile',
        ),
      ],
    );
  }

  Widget _buildCommunityPlaceholderTab() {
    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xFF041A12), Color(0xFF032418), Color(0xFF00130D)],
        ),
      ),
      child: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(
                  Icons.forum_outlined,
                  size: 54,
                  color: Color(0xFF53D97A),
                ),
                const SizedBox(height: 12),
                const Text(
                  'Community',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 28,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'Coming soon. You can tell me what to put inside next.',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.75),
                    fontSize: 14,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildExploreTab(bool keyboardOpen) {
    return Stack(
      children: [
        Positioned.fill(
          child: GoogleMap(
            initialCameraPosition: CameraPosition(
              target: _currentCenter,
              zoom: 7.2,
            ),
            onMapCreated: (controller) {
              _mapController = controller;
            },
            cameraTargetBounds: CameraTargetBounds(_mindanaoBounds),
            minMaxZoomPreference: const MinMaxZoomPreference(6.7, 19),
            myLocationEnabled: _locationGranted,
            myLocationButtonEnabled: false,
            scrollGesturesEnabled: true,
            zoomGesturesEnabled: true,
            zoomControlsEnabled: false,
            mapToolbarEnabled: false,
            compassEnabled: false,
            markers: _buildMapMarkers(),
          ),
        ),
        Positioned.fill(
          child: IgnorePointer(
            child: Container(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    const Color(0xFF04140E).withValues(alpha: 0.45),
                    Colors.transparent,
                    const Color(0xFF03110C).withValues(alpha: 0.68),
                  ],
                  stops: const [0, 0.35, 1],
                ),
              ),
            ),
          ),
        ),
        SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 88),
            child: Column(
              children: [
                Row(
                  children: [
                    _circleButton(icon: Icons.menu),
                    const SizedBox(width: 10),
                    const Text(
                      'Agakbay',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 30,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const Spacer(),
                    _circleButton(icon: Icons.notifications_none_rounded),
                  ],
                ),
                const SizedBox(height: 12),
                Container(
                  height: 48,
                  padding: const EdgeInsets.symmetric(horizontal: 14),
                  decoration: BoxDecoration(
                    color: const Color(0xFF021710).withValues(alpha: 0.8),
                    borderRadius: BorderRadius.circular(18),
                    border: Border.all(
                      color: Colors.white.withValues(alpha: 0.18),
                    ),
                  ),
                  child: Row(
                    children: [
                      const Icon(
                        Icons.search_rounded,
                        color: Colors.white70,
                        size: 22,
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: TextField(
                          controller: _searchController,
                          textInputAction: TextInputAction.search,
                          onSubmitted: (_) => _searchOnMap(),
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 16,
                          ),
                          decoration: InputDecoration(
                            isCollapsed: true,
                            hintText: 'Search place or mountain...',
                            hintStyle: TextStyle(
                              color: Colors.white.withValues(alpha: 0.75),
                              fontSize: 16,
                            ),
                            border: InputBorder.none,
                          ),
                        ),
                      ),
                      Material(
                        color: Colors.transparent,
                        child: InkWell(
                          onTap: _isSearching ? null : _searchOnMap,
                          borderRadius: BorderRadius.circular(16),
                          child: SizedBox(
                            width: 32,
                            height: 32,
                            child: Center(
                              child: _isSearching
                                  ? const SizedBox(
                                      width: 16,
                                      height: 16,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                        color: Color(0xFF7CF9A2),
                                      ),
                                    )
                                  : const Icon(
                                      Icons.arrow_forward_rounded,
                                      color: Color(0xFF7CF9A2),
                                      size: 20,
                                    ),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 10),
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: [
                      _filterChip(
                        'All',
                        isActive:
                            _markerStatusFilter == _MarkerStatusFilter.all,
                        onTap: () {
                          setState(() {
                            _markerStatusFilter = _MarkerStatusFilter.all;
                          });
                        },
                      ),
                      _filterChip(
                        'Open',
                        isActive:
                            _markerStatusFilter == _MarkerStatusFilter.open,
                        onTap: () {
                          setState(() {
                            _markerStatusFilter = _MarkerStatusFilter.open;
                          });
                        },
                      ),
                      _filterChip(
                        'Closed',
                        isActive:
                            _markerStatusFilter == _MarkerStatusFilter.closed,
                        onTap: () {
                          setState(() {
                            _markerStatusFilter = _MarkerStatusFilter.closed;
                          });
                        },
                      ),
                      _filterChip(
                        'My Location',
                        onTap: () {
                          setState(() {
                            _nearbyAnchorMode = _NearbyAnchorMode.nearMe;
                          });
                          unawaited(_loadCurrentLocation());
                        },
                      ),
                    ],
                  ),
                ),
                if (_locationMessage != null) ...[
                  const SizedBox(height: 8),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: const Color(0xFF361515).withValues(alpha: 0.75),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: const Color(0xFFFF7A7A).withValues(alpha: 0.7),
                      ),
                    ),
                    child: Text(
                      _locationMessage!,
                      style: const TextStyle(color: Colors.white),
                    ),
                  ),
                ],
                if (!keyboardOpen) ...[
                  const Spacer(),
                  Align(
                    alignment: Alignment.centerRight,
                    child: Column(
                      children: [
                        _controlButton(
                          icon: Icons.my_location_rounded,
                          onTap: _loadCurrentLocation,
                        ),
                        const SizedBox(height: 8),
                        _controlButton(icon: Icons.add, onTap: _zoomIn),
                        const SizedBox(height: 8),
                        _controlButton(icon: Icons.remove, onTap: _zoomOut),
                      ],
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
        if (!keyboardOpen)
          Positioned(
            left: 16,
            right: 16,
            bottom: 12,
            child: _buildNearbyBottomCard(),
          ),
      ],
    );
  }

  Widget _buildNearbyBottomCard() {
    return ConstrainedBox(
      constraints: const BoxConstraints(maxHeight: 330),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.fromLTRB(14, 14, 14, 10),
        decoration: BoxDecoration(
          color: const Color(0xFF02130E).withValues(alpha: 0.9),
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: Colors.white.withValues(alpha: 0.12)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                const Text(
                  'Nearby Trails',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 19,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const Spacer(),
                Material(
                  color: Colors.transparent,
                  child: InkWell(
                    onTap: _openNearbyTrailsSheet,
                    borderRadius: BorderRadius.circular(8),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 4,
                        vertical: 2,
                      ),
                      child: Text(
                        _nearbyTrails.isEmpty
                            ? 'View All'
                            : 'View All (${_nearbyTrails.length})',
                        style: const TextStyle(
                          color: Color(0xFF7CF9A2),
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Align(
              alignment: Alignment.centerLeft,
              child: Text(
                _nearbyAnchorLabel(),
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.7),
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                _nearbyAnchorChip(
                  label: 'Near Me',
                  isActive: _nearbyAnchorMode == _NearbyAnchorMode.nearMe,
                  onTap: () {
                    _setNearbyAnchorMode(_NearbyAnchorMode.nearMe);
                  },
                ),
                const SizedBox(width: 8),
                _nearbyAnchorChip(
                  label: 'Near Search',
                  isActive: _nearbyAnchorMode == _NearbyAnchorMode.nearSearch,
                  isEnabled: _searchedTrailAnchor != null,
                  onTap: () {
                    _setNearbyAnchorMode(_NearbyAnchorMode.nearSearch);
                  },
                ),
              ],
            ),
            const SizedBox(height: 12),
            _nearbyTrailsListContent(),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  // ignore: unused_element
  Widget _buildCommunityTab() {
    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xFF041A12), Color(0xFF032418), Color(0xFF00130D)],
        ),
      ),
      child: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
              child: Row(
                children: [
                  _circleButton(icon: Icons.menu),
                  const Spacer(),
                  const Text(
                    'Agakbay',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 28,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const Spacer(),
                  _circleButton(icon: Icons.notifications_none_rounded),
                ],
              ),
            ),
            const SizedBox(height: 10),
            const Text(
              'Community',
              style: TextStyle(
                color: Colors.white,
                fontSize: 36,
                fontWeight: FontWeight.w800,
              ),
            ),
            Text(
              'Share your hikes. Inspire others.',
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.72),
                fontSize: 14,
              ),
            ),
            const SizedBox(height: 12),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Container(
                padding: const EdgeInsets.all(4),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Row(
                  children: [
                    Expanded(child: _communityFeedChip('All Posts', 0)),
                    Expanded(child: _communityFeedChip('Following', 1)),
                    Expanded(child: _communityFeedChip('My Posts', 2)),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 10),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.06),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(
                    color: Colors.white.withValues(alpha: 0.08),
                  ),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _communityComposerController,
                        minLines: 1,
                        maxLines: 3,
                        style: const TextStyle(color: Colors.white),
                        decoration: InputDecoration(
                          hintText: "What's on your trail today?",
                          hintStyle: TextStyle(
                            color: Colors.white.withValues(alpha: 0.62),
                          ),
                          border: InputBorder.none,
                          isCollapsed: true,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    SizedBox(
                      height: 42,
                      child: ElevatedButton(
                        onPressed: () async {
                          final content = _communityComposerController.text
                              .trim();
                          if (content.isEmpty) {
                            return;
                          }
                          _communityComposerController.clear();
                          await _createCommunityPost(content);
                        },
                        style: ElevatedButton.styleFrom(
                          foregroundColor: Colors.black,
                          backgroundColor: const Color(0xFF53D97A),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10),
                          ),
                        ),
                        child: const Text(
                          'Post',
                          style: TextStyle(fontWeight: FontWeight.w700),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 8),
            Expanded(
              child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                stream: _communityPostsStream(),
                builder: (context, snapshot) {
                  if (snapshot.connectionState == ConnectionState.waiting) {
                    return const Center(
                      child: CircularProgressIndicator(
                        strokeWidth: 2.2,
                        color: Color(0xFF7CF9A2),
                      ),
                    );
                  }
                  final docs = snapshot.data?.docs ?? const [];
                  var posts = docs
                      .map(_communityPostFromSnapshot)
                      .where((post) => post.content.trim().isNotEmpty)
                      .toList();
                  if (_communityFeedFilterIndex == 2) {
                    final uid = _firebaseAuth.currentUser?.uid;
                    posts = uid == null
                        ? <_CommunityPost>[]
                        : posts.where((post) => post.authorId == uid).toList();
                  } else if (_communityFeedFilterIndex == 1) {
                    final uid = _firebaseAuth.currentUser?.uid;
                    posts = uid == null
                        ? posts
                        : posts.where((post) => post.authorId != uid).toList();
                  }

                  if (posts.isEmpty) {
                    final emptyText = _communityFeedFilterIndex == 2
                        ? 'You have no posts yet.'
                        : _communityFeedFilterIndex == 1
                        ? 'No following feed yet.'
                        : 'No posts yet. Be the first to share.';
                    return Center(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 22),
                        child: Text(
                          emptyText,
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            color: Colors.white.withValues(alpha: 0.74),
                          ),
                        ),
                      ),
                    );
                  }

                  return ListView.builder(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 96),
                    itemCount: posts.length,
                    itemBuilder: (_, index) => _communityPostCard(posts[index]),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _communityFeedChip(String label, int index) {
    final isActive = _communityFeedFilterIndex == index;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () {
          setState(() {
            _communityFeedFilterIndex = index;
          });
        },
        borderRadius: BorderRadius.circular(10),
        child: Container(
          alignment: Alignment.center,
          padding: const EdgeInsets.symmetric(vertical: 9),
          decoration: BoxDecoration(
            color: isActive ? const Color(0xFF53D97A) : Colors.transparent,
            borderRadius: BorderRadius.circular(10),
          ),
          child: Text(
            label,
            style: TextStyle(
              color: isActive ? Colors.black : Colors.white70,
              fontWeight: FontWeight.w700,
              fontSize: 12,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildMyHikesTab() {
    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xFF041A12), Color(0xFF032418), Color(0xFF00130D)],
        ),
      ),
      child: SafeArea(
        child: Column(
          children: [
            const SizedBox(height: 14),
            const Text(
              'My Hikes',
              style: TextStyle(
                color: Colors.white,
                fontSize: 28,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 10),
            Expanded(
              child: _completedHikeSessions.isEmpty
                  ? Center(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 24),
                        child: Text(
                          'No completed hikes yet. Start a hike from Explore.',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            color: Colors.white.withValues(alpha: 0.75),
                          ),
                        ),
                      ),
                    )
                  : ListView.separated(
                      padding: const EdgeInsets.fromLTRB(16, 0, 16, 96),
                      itemCount: _completedHikeSessions.length,
                      separatorBuilder: (_, _) => const SizedBox(height: 10),
                      itemBuilder: (_, index) {
                        final session = _completedHikeSessions[index];
                        return _completedHikeCard(session);
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildProfileTab() {
    final user = _firebaseAuth.currentUser;
    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xFF041A12), Color(0xFF032418), Color(0xFF00130D)],
        ),
      ),
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Profile',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 30,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 16),
              Text(
                _communityDisplayName(),
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 20,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                user?.email ?? 'No email',
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.72),
                  fontSize: 14,
                ),
              ),
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: () async {
                    await Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (context) =>
                            HikeRoomScreen(onStartHiking: _startHikingFromRoom),
                      ),
                    );
                  },
                  icon: const Icon(Icons.groups_rounded),
                  label: const Text('Hike SOS Room'),
                  style: ElevatedButton.styleFrom(
                    foregroundColor: const Color(0xFF03150E),
                    backgroundColor: const Color(0xFFFFD76A),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 10),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: () {
                    Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (context) => const OfflineMapExampleScreen(),
                      ),
                    );
                  },
                  icon: const Icon(Icons.map_rounded),
                  label: const Text('Offline Maps'),
                  style: ElevatedButton.styleFrom(
                    foregroundColor: const Color(0xFF03150E),
                    backgroundColor: const Color(0xFF53D97A),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 10),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: () async {
                    await _firebaseAuth.signOut();
                  },
                  icon: const Icon(Icons.logout_rounded),
                  label: const Text('Sign Out'),
                  style: ElevatedButton.styleFrom(
                    foregroundColor: Colors.white,
                    backgroundColor: const Color(0xFF3A1515),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _circleButton({required IconData icon}) {
    return Container(
      width: 44,
      height: 44,
      decoration: BoxDecoration(
        color: const Color(0xFF02150E).withValues(alpha: 0.75),
        shape: BoxShape.circle,
        border: Border.all(color: Colors.white.withValues(alpha: 0.16)),
      ),
      child: Icon(icon, color: Colors.white, size: 24),
    );
  }

  Widget _filterChip(
    String label, {
    bool isActive = false,
    VoidCallback? onTap,
  }) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(24),
        child: Container(
          margin: const EdgeInsets.only(right: 8),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          decoration: BoxDecoration(
            color: isActive
                ? const Color(0xFF53D97A)
                : const Color(0xFF041B13).withValues(alpha: 0.78),
            borderRadius: BorderRadius.circular(24),
            border: Border.all(
              color: isActive
                  ? Colors.transparent
                  : Colors.white.withValues(alpha: 0.18),
            ),
          ),
          child: Text(
            label,
            style: TextStyle(
              color: isActive ? Colors.black : Colors.white,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ),
    );
  }

  Widget _controlButton({
    required IconData icon,
    required Future<void> Function() onTap,
  }) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          width: 42,
          height: 42,
          decoration: BoxDecoration(
            color: const Color(0xFF041B13).withValues(alpha: 0.9),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: Colors.white.withValues(alpha: 0.18)),
          ),
          child: Icon(icon, color: Colors.white, size: 24),
        ),
      ),
    );
  }

  Widget _nearbyAnchorChip({
    required String label,
    required bool isActive,
    required VoidCallback onTap,
    bool isEnabled = true,
  }) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: isEnabled ? onTap : null,
        borderRadius: BorderRadius.circular(18),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
          decoration: BoxDecoration(
            color: isActive
                ? const Color(0xFF53D97A)
                : Colors.white.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(18),
            border: Border.all(
              color: isActive
                  ? Colors.transparent
                  : Colors.white.withValues(alpha: isEnabled ? 0.18 : 0.08),
            ),
          ),
          child: Text(
            label,
            style: TextStyle(
              color: isActive
                  ? Colors.black
                  : isEnabled
                  ? Colors.white
                  : Colors.white54,
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ),
    );
  }

  Widget _communityPostCard(
    _CommunityPost post, {
    bool showCommentAction = true,
  }) {
    final user = _firebaseAuth.currentUser;
    final likeDocStream = user == null
        ? null
        : _firestore
              .collection('community_posts')
              .doc(post.id)
              .collection('likes')
              .doc(user.uid)
              .snapshots();
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              CircleAvatar(
                radius: 16,
                backgroundColor: const Color(0xFF0A3A28),
                child: Text(
                  _communityAvatarSeed(post.authorName),
                  style: const TextStyle(
                    color: Color(0xFF7CF9A2),
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      post.authorName,
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    Text(
                      post.createdAt == null
                          ? 'Just now'
                          : _formatDate(post.createdAt!),
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.62),
                        fontSize: 11,
                      ),
                    ),
                  ],
                ),
              ),
              if (post.mountainName.trim().isNotEmpty)
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    post.mountainName,
                    style: const TextStyle(
                      color: Color(0xFF7CF9A2),
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            post.content,
            style: const TextStyle(color: Colors.white, height: 1.35),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              if (likeDocStream == null)
                _communityActionText(
                  icon: Icons.favorite_border_rounded,
                  label: '${post.likeCount}',
                  color: Colors.white70,
                  onTap: () => _toggleCommunityPostLike(post),
                )
              else
                StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
                  stream: likeDocStream,
                  builder: (context, snapshot) {
                    final liked = snapshot.data?.exists == true;
                    return _communityActionText(
                      icon: liked
                          ? Icons.favorite_rounded
                          : Icons.favorite_border_rounded,
                      label: '${post.likeCount}',
                      color: liked ? const Color(0xFF53D97A) : Colors.white70,
                      onTap: () => _toggleCommunityPostLike(post),
                    );
                  },
                ),
              const SizedBox(width: 14),
              if (showCommentAction)
                _communityActionText(
                  icon: Icons.chat_bubble_outline_rounded,
                  label: '${post.commentCount}',
                  color: Colors.white70,
                  onTap: () => unawaited(_openCommunityPostDetails(post)),
                )
              else
                Row(
                  children: [
                    const Icon(
                      Icons.chat_bubble_outline_rounded,
                      color: Colors.white70,
                      size: 18,
                    ),
                    const SizedBox(width: 4),
                    Text(
                      '${post.commentCount}',
                      style: const TextStyle(color: Colors.white70),
                    ),
                  ],
                ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _communityActionText({
    required IconData icon,
    required String label,
    required Color color,
    required VoidCallback onTap,
  }) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
          child: Row(
            children: [
              Icon(icon, color: color, size: 18),
              const SizedBox(width: 4),
              Text(label, style: TextStyle(color: color)),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _openNearbyTrailsSheet() async {
    if (_isLoadingNearbyTrails) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Loading nearby trails...')));
      return;
    }

    if (_nearbyTrails.isEmpty) {
      await _refreshNearbyTrailsForActiveAnchor();
    }

    if (!mounted) {
      return;
    }

    if (_nearbyTrails.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(_nearbyTrailsMessage ?? 'No nearby trails found.'),
        ),
      );
      return;
    }

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) {
        return DraggableScrollableSheet(
          initialChildSize: 0.72,
          minChildSize: 0.45,
          maxChildSize: 0.95,
          expand: false,
          builder: (context, scrollController) {
            return Container(
              decoration: const BoxDecoration(
                color: Color(0xFF02130E),
                borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
              ),
              child: Column(
                children: [
                  const SizedBox(height: 10),
                  Container(
                    width: 44,
                    height: 4,
                    decoration: BoxDecoration(
                      color: Colors.white24,
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 12, 8, 8),
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(
                            'All Nearby Trails',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 20,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                        IconButton(
                          onPressed: () {
                            Navigator.of(sheetContext).pop();
                          },
                          icon: const Icon(
                            Icons.close_rounded,
                            color: Colors.white70,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: Text(
                        '${_nearbyTrails.length} trails found ${_distanceContextLabel()}',
                        style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.72),
                          fontSize: 13,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 10),
                  Expanded(
                    child: ListView.separated(
                      controller: scrollController,
                      padding: const EdgeInsets.fromLTRB(16, 0, 16, 18),
                      itemCount: _nearbyTrails.length,
                      separatorBuilder: (_, _) => const SizedBox(height: 8),
                      itemBuilder: (_, index) {
                        final trail = _nearbyTrails[index];
                        return _nearbyTrailCard(
                          trail,
                          onTap: () {
                            Navigator.of(sheetContext).pop();
                            unawaited(
                              _focusTrailAndOpenDetails(
                                trail,
                                delayBeforeDetails: const Duration(
                                  milliseconds: 220,
                                ),
                              ),
                            );
                          },
                        );
                      },
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  Widget _nearbyTrailsListContent() {
    if (_isLoadingNearbyTrails) {
      return const SizedBox(
        height: 74,
        child: Center(
          child: CircularProgressIndicator(
            strokeWidth: 2.2,
            color: Color(0xFF7CF9A2),
          ),
        ),
      );
    }

    if (_nearbyTrailsMessage != null) {
      return _nearbyMessageCard(_nearbyTrailsMessage!);
    }

    if (_nearbyTrails.isEmpty) {
      return _nearbyMessageCard('No nearby mountains yet.');
    }

    final visibleTrails = _nearbyTrails.take(2).toList();
    return Column(
      children: [
        for (var index = 0; index < visibleTrails.length; index++) ...[
          _nearbyTrailCard(visibleTrails[index]),
          if (index != visibleTrails.length - 1) const SizedBox(height: 8),
        ],
      ],
    );
  }

  Widget _nearbyMessageCard(String message) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Text(
        message,
        style: TextStyle(color: Colors.white.withValues(alpha: 0.88)),
      ),
    );
  }

  Widget _nearbyTrailCard(_NearbyTrail trail, {VoidCallback? onTap}) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap ?? () => unawaited(_focusTrailAndOpenDetails(trail)),
        borderRadius: BorderRadius.circular(14),
        child: Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.06),
            borderRadius: BorderRadius.circular(14),
          ),
          child: Row(
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(10),
                child: Container(
                  width: 70,
                  height: 50,
                  color: const Color(0xFF0F2A1E),
                  child: _trailImage(trail),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      trail.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      _displayDistanceText(trail),
                      style: const TextStyle(
                        color: Color(0xFF7CF9A2),
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    if (trail.address.isNotEmpty)
                      Text(
                        trail.address,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.72),
                          fontSize: 12,
                        ),
                      ),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right_rounded, color: Colors.white70),
            ],
          ),
        ),
      ),
    );
  }

  Widget _trailImage(_NearbyTrail trail) {
    if (trail.imageUrl == null || trail.imageUrl!.isEmpty) {
      return const Icon(Icons.terrain_rounded, color: Color(0xFF7CF9A2));
    }
    return Image.network(
      trail.imageUrl!,
      fit: BoxFit.cover,
      errorBuilder: (_, _, _) {
        return const Icon(Icons.terrain_rounded, color: Color(0xFF7CF9A2));
      },
      loadingBuilder: (context, child, loadingProgress) {
        if (loadingProgress == null) {
          return child;
        }
        return const Center(
          child: SizedBox(
            width: 16,
            height: 16,
            child: CircularProgressIndicator(
              strokeWidth: 2,
              color: Color(0xFF7CF9A2),
            ),
          ),
        );
      },
    );
  }

  Widget _completedHikeCard(
    _CompletedHikeSession session, {
    VoidCallback? onTap,
  }) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.06),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: Colors.white.withValues(alpha: 0.12)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      session.trail.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 17,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: session.reachedSummit
                          ? const Color(0xFF53D97A).withValues(alpha: 0.22)
                          : Colors.white.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: Text(
                      session.reachedSummit ? 'Summit' : 'Ended',
                      style: TextStyle(
                        color: session.reachedSummit
                            ? const Color(0xFF7CF9A2)
                            : Colors.white70,
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              Text(
                _formatDate(session.completedAt),
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.65),
                  fontSize: 12,
                ),
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: Text(
                      'Distance: ${session.distanceKm.toStringAsFixed(2)} km',
                      style: const TextStyle(color: Colors.white),
                    ),
                  ),
                  Expanded(
                    child: Text(
                      'Time: ${_formatDuration(session.duration)}',
                      style: const TextStyle(color: Colors.white),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              Row(
                children: [
                  Expanded(
                    child: Text(
                      'Gain: ${session.elevationGainMasl} m',
                      style: const TextStyle(color: Colors.white),
                    ),
                  ),
                  Expanded(
                    child: Text(
                      'Peak: ${session.maxElevationMasl} MASL',
                      style: const TextStyle(color: Colors.white),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              Text(
                'Checkpoints reached: ${session.checkpointsReached}/${session.totalCheckpoints}',
                style: const TextStyle(color: Color(0xFF7CF9A2), fontSize: 12),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _openMountainDetailsCard(_NearbyTrail trail) async {
    _rememberTrail(trail);
    final communityTrail = await _fetchCommunityTrail(trail);
    final routeOptions = await _loadMountainRouteOptions(trail);
    if (!mounted) {
      return;
    }
    var sheetActive = true;
    var selectedHikeDate = _dateOnly(DateTime.now());
    var visibleHikeMonth = DateTime(
      selectedHikeDate.year,
      selectedHikeDate.month,
    );
    _HikeWeatherForecast? hikeWeatherForecast;
    String? hikeWeatherError;
    var isHikeWeatherLoading = false;
    var hasRequestedInitialHikeWeather = false;
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) {
        var hasCompletedBefore = _completedTrailIds.contains(trail.placeId);
        _MountainRouteOption? selectedRoute = routeOptions.isNotEmpty
            ? routeOptions.first
            : null;
        final trailStatus = (communityTrail?.status ?? 'none').toLowerCase();
        final mappedRouteCount = routeOptions.length;
        final hasMappedRoutes = mappedRouteCount > 0;
        final trailStatusLabel = switch (trailStatus) {
          'verified' => 'Verified',
          'provisional' => 'Provisional',
          _ =>
            hasMappedRoutes ? 'Mapped ($mappedRouteCount routes)' : 'No Data',
        };
        final trailStatusColor = switch (trailStatus) {
          'verified' => const Color(0xFF53D97A),
          'provisional' => const Color(0xFFFFD76A),
          _ => hasMappedRoutes ? const Color(0xFF84E6A2) : Colors.white70,
        };
        Future<void> loadHikeWeather(
          StateSetter sheetSetState,
          DateTime date,
        ) async {
          sheetSetState(() {
            isHikeWeatherLoading = true;
            hikeWeatherError = null;
          });
          try {
            final forecast = await _fetchHikeWeatherForecast(trail, date);
            if (!mounted || !sheetActive) {
              return;
            }
            sheetSetState(() {
              hikeWeatherForecast = forecast;
              isHikeWeatherLoading = false;
            });
          } on _WeatherForecastException catch (error) {
            if (!mounted || !sheetActive) {
              return;
            }
            sheetSetState(() {
              hikeWeatherError = error.message;
              hikeWeatherForecast = null;
              isHikeWeatherLoading = false;
            });
          } catch (_) {
            if (!mounted || !sheetActive) {
              return;
            }
            sheetSetState(() {
              hikeWeatherError = 'Weather forecast is unavailable right now.';
              hikeWeatherForecast = null;
              isHikeWeatherLoading = false;
            });
          }
        }

        Future<void> selectHikeDate(
          StateSetter sheetSetState,
          DateTime date,
        ) async {
          final today = _dateOnly(DateTime.now());
          final lastForecastDate = today.add(const Duration(days: 9));
          final picked = _dateOnly(date);
          if (picked.isBefore(today) ||
              picked.isAfter(lastForecastDate) ||
              !sheetActive) {
            return;
          }
          sheetSetState(() {
            selectedHikeDate = picked;
            visibleHikeMonth = DateTime(picked.year, picked.month);
            hikeWeatherForecast = null;
            hikeWeatherError = null;
          });
          await loadHikeWeather(sheetSetState, selectedHikeDate);
        }

        return StatefulBuilder(
          builder: (context, sheetSetState) {
            if (!hasRequestedInitialHikeWeather) {
              hasRequestedInitialHikeWeather = true;
              unawaited(
                Future<void>.microtask(
                  () => loadHikeWeather(sheetSetState, selectedHikeDate),
                ),
              );
            }
            return Container(
              height: MediaQuery.of(context).size.height * 0.88,
              decoration: const BoxDecoration(
                color: Color(0xFF02130E),
                borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const SizedBox(height: 10),
                  Center(
                    child: Container(
                      width: 46,
                      height: 4,
                      decoration: BoxDecoration(
                        color: Colors.white24,
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(16),
                      child: SizedBox(
                        height: 220,
                        width: double.infinity,
                        child: trail.imageUrl == null || trail.imageUrl!.isEmpty
                            ? Container(
                                color: const Color(0xFF0F2A1E),
                                child: const Icon(
                                  Icons.terrain_rounded,
                                  color: Color(0xFF7CF9A2),
                                  size: 70,
                                ),
                              )
                            : Image.network(
                                trail.imageUrl!,
                                fit: BoxFit.cover,
                                errorBuilder: (_, _, _) {
                                  return Container(
                                    color: const Color(0xFF0F2A1E),
                                    child: const Icon(
                                      Icons.terrain_rounded,
                                      color: Color(0xFF7CF9A2),
                                      size: 70,
                                    ),
                                  );
                                },
                              ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 14),
                  Expanded(
                    child: SingleChildScrollView(
                      padding: const EdgeInsets.fromLTRB(16, 0, 16, 18),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            trail.name,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 32,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                          const SizedBox(height: 3),
                          Text(
                            '${trail.elevationMasl} MASL',
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 20,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            trail.provinceOrCity,
                            style: TextStyle(
                              color: Colors.white.withValues(alpha: 0.82),
                              fontSize: 16,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 10,
                              vertical: 6,
                            ),
                            decoration: BoxDecoration(
                              color: Colors.white.withValues(alpha: 0.06),
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: Text(
                              'Trail Data: $trailStatusLabel',
                              style: TextStyle(
                                color: trailStatusColor,
                                fontWeight: FontWeight.w700,
                                fontSize: 12,
                              ),
                            ),
                          ),
                          const SizedBox(height: 14),
                          if (routeOptions.isNotEmpty) ...[
                            const Text(
                              'Available Trail Routes',
                              style: TextStyle(
                                color: Color(0xFF7CF9A2),
                                fontSize: 14,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            const SizedBox(height: 8),
                            for (final route in routeOptions) ...[
                              Material(
                                color: Colors.transparent,
                                child: InkWell(
                                  onTap: () {
                                    sheetSetState(() {
                                      selectedRoute = route;
                                    });
                                  },
                                  borderRadius: BorderRadius.circular(12),
                                  child: Container(
                                    width: double.infinity,
                                    margin: const EdgeInsets.only(bottom: 8),
                                    padding: const EdgeInsets.all(12),
                                    decoration: BoxDecoration(
                                      color:
                                          selectedRoute?.assetPath ==
                                              route.assetPath
                                          ? const Color(0xFF103827)
                                          : Colors.white.withValues(
                                              alpha: 0.04,
                                            ),
                                      borderRadius: BorderRadius.circular(12),
                                      border: Border.all(
                                        color:
                                            selectedRoute?.assetPath ==
                                                route.assetPath
                                            ? const Color(0xFF53D97A)
                                            : Colors.white.withValues(
                                                alpha: 0.12,
                                              ),
                                      ),
                                    ),
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          route.routeName,
                                          style: const TextStyle(
                                            color: Colors.white,
                                            fontWeight: FontWeight.w700,
                                          ),
                                        ),
                                        const SizedBox(height: 4),
                                        Text(
                                          'Jump-off: ${route.jumpOffLabel}',
                                          style: TextStyle(
                                            color: Colors.white.withValues(
                                              alpha: 0.82,
                                            ),
                                            fontSize: 12,
                                          ),
                                        ),
                                        const SizedBox(height: 2),
                                        Text(
                                          'Start point: ${_formatLatLngCompact(route.startPoint)}',
                                          style: TextStyle(
                                            color: Colors.white.withValues(
                                              alpha: 0.65,
                                            ),
                                            fontSize: 11,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ] else ...[
                            Container(
                              width: double.infinity,
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                color: Colors.white.withValues(alpha: 0.05),
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: Text(
                                'No mapped trail routes found for this mountain yet.',
                                style: TextStyle(
                                  color: Colors.white.withValues(alpha: 0.82),
                                  fontSize: 12,
                                ),
                              ),
                            ),
                          ],
                          const SizedBox(height: 6),
                          Container(
                            width: double.infinity,
                            padding: const EdgeInsets.all(14),
                            decoration: BoxDecoration(
                              color: const Color(0xFF042117),
                              borderRadius: BorderRadius.circular(14),
                              border: Border.all(
                                color: Colors.white.withValues(alpha: 0.12),
                              ),
                            ),
                            child: Row(
                              children: [
                                Icon(
                                  trail.status == 'Open'
                                      ? Icons.check_circle_rounded
                                      : Icons.cancel_rounded,
                                  color: trail.status == 'Open'
                                      ? const Color(0xFF53D97A)
                                      : const Color(0xFFFF8A8A),
                                ),
                                const SizedBox(width: 10),
                                Text(
                                  trail.status == 'Open'
                                      ? 'OPEN FOR HIKING'
                                      : 'CURRENTLY CLOSED',
                                  style: TextStyle(
                                    color: trail.status == 'Open'
                                        ? const Color(0xFF53D97A)
                                        : const Color(0xFFFF8A8A),
                                    fontSize: 16,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 14),
                          _hikeWeatherCard(
                            selectedDate: selectedHikeDate,
                            visibleMonth: visibleHikeMonth,
                            firstDate: _dateOnly(DateTime.now()),
                            lastDate: _dateOnly(
                              DateTime.now(),
                            ).add(const Duration(days: 9)),
                            forecast: hikeWeatherForecast,
                            errorMessage: hikeWeatherError,
                            isLoading: isHikeWeatherLoading,
                            onPreviousMonth: () {
                              final firstDate = _dateOnly(DateTime.now());
                              final lastDate = firstDate.add(
                                const Duration(days: 9),
                              );
                              final previousMonth = DateTime(
                                visibleHikeMonth.year,
                                visibleHikeMonth.month - 1,
                              );
                              if (_monthHasForecastableDates(
                                previousMonth,
                                firstDate,
                                lastDate,
                              )) {
                                sheetSetState(() {
                                  visibleHikeMonth = previousMonth;
                                });
                              }
                            },
                            onNextMonth: () {
                              final firstDate = _dateOnly(DateTime.now());
                              final lastDate = firstDate.add(
                                const Duration(days: 9),
                              );
                              final nextMonth = DateTime(
                                visibleHikeMonth.year,
                                visibleHikeMonth.month + 1,
                              );
                              if (_monthHasForecastableDates(
                                nextMonth,
                                firstDate,
                                lastDate,
                              )) {
                                sheetSetState(() {
                                  visibleHikeMonth = nextMonth;
                                });
                              }
                            },
                            onSelectDate: (date) =>
                                unawaited(selectHikeDate(sheetSetState, date)),
                            onCheckWeather: () => unawaited(
                              loadHikeWeather(sheetSetState, selectedHikeDate),
                            ),
                          ),
                          const SizedBox(height: 14),
                          Row(
                            children: [
                              Expanded(
                                child: _detailStatCard(
                                  label: 'Difficulty',
                                  value: trail.difficulty,
                                ),
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: _detailStatCard(
                                  label: 'Distance',
                                  value: _displayDistanceText(trail),
                                ),
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: _detailStatCard(
                                  label: 'Status',
                                  value: trail.status,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 14),
                          const Text(
                            'Description',
                            style: TextStyle(
                              color: Color(0xFF7CF9A2),
                              fontSize: 14,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            trail.description,
                            style: TextStyle(
                              color: Colors.white.withValues(alpha: 0.9),
                              height: 1.4,
                            ),
                          ),
                          const SizedBox(height: 14),
                          Container(
                            width: double.infinity,
                            padding: const EdgeInsets.all(14),
                            decoration: BoxDecoration(
                              color: Colors.white.withValues(alpha: 0.04),
                              borderRadius: BorderRadius.circular(14),
                              border: Border.all(
                                color: Colors.white.withValues(alpha: 0.1),
                              ),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                _detailRow(
                                  'Province/City',
                                  trail.provinceOrCity,
                                ),
                                const SizedBox(height: 8),
                                _detailRow(
                                  'Elevation (MASL)',
                                  trail.elevationMasl.toString(),
                                ),
                                const SizedBox(height: 8),
                                _detailRow('Address', trail.address),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  SafeArea(
                    top: false,
                    minimum: const EdgeInsets.fromLTRB(16, 8, 16, 14),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (_accountType == 'tour_guide') ...[
                          SizedBox(
                            height: 52,
                            width: double.infinity,
                            child: OutlinedButton.icon(
                              onPressed: () => _createHikeRoomForMountain(
                                trail,
                                selectedRoute,
                                communityTrail,
                              ),
                              icon: const Icon(Icons.groups_rounded),
                              label: Text(
                                selectedRoute == null
                                    ? 'Create Room for ${trail.name}'
                                    : 'Create Room: ${selectedRoute!.routeName}',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                              style: OutlinedButton.styleFrom(
                                foregroundColor: const Color(0xFFFFD76A),
                                side: const BorderSide(
                                  color: Color(0xFFFFD76A),
                                ),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(16),
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(height: 8),
                        ],
                        SizedBox(
                          height: 52,
                          width: double.infinity,
                          child: ElevatedButton.icon(
                            onPressed: () async {
                              final communityTrail = await _fetchCommunityTrail(
                                trail,
                              );
                              if (!mounted) {
                                return;
                              }
                              final session = await Navigator.of(this.context)
                                  .push<_LiveHikeResult>(
                                    MaterialPageRoute<_LiveHikeResult>(
                                      builder: (_) => _HikingModeScreen(
                                        trail: trail,
                                        mapsApiKey: _mapsApiKey,
                                        communityTrail: communityTrail,
                                        preferredGpxAssetPath:
                                            selectedRoute?.assetPath,
                                        selectedRouteLabel:
                                            selectedRoute?.routeName,
                                      ),
                                    ),
                                  );
                              if (!mounted || session == null) {
                                return;
                              }
                              setState(() {
                                _rememberTrail(trail);
                                _completedTrailIds.add(trail.placeId);
                                _completedHikeSessions.insert(
                                  0,
                                  _CompletedHikeSession(
                                    trail: trail,
                                    completedAt: DateTime.now(),
                                    distanceKm: session.distanceKm,
                                    duration: session.duration,
                                    elevationGainMasl:
                                        session.elevationGainMasl,
                                    maxElevationMasl: session.maxElevationMasl,
                                    checkpointsReached:
                                        session.checkpointsReached,
                                    totalCheckpoints: session.totalCheckpoints,
                                    reachedSummit: session.reachedSummit,
                                  ),
                                );
                              });
                              sheetSetState(() => hasCompletedBefore = true);
                              _showDashboardSnackBar(
                                '${trail.name} hike saved to My Hikes.',
                              );
                              unawaited(
                                _submitTrailRouteIfAccepted(trail, session),
                              );
                            },
                            icon: Icon(
                              hasCompletedBefore
                                  ? Icons.check_circle_rounded
                                  : Icons.hiking_rounded,
                            ),
                            label: Text(
                              hasCompletedBefore
                                  ? 'Start Hiking Again'
                                  : 'Start Hiking',
                              style: const TextStyle(
                                fontWeight: FontWeight.w800,
                                letterSpacing: 0.2,
                              ),
                            ),
                            style: ElevatedButton.styleFrom(
                              foregroundColor: Colors.black,
                              backgroundColor: hasCompletedBefore
                                  ? const Color(0xFF61DF86)
                                  : const Color(0xFF53D97A),
                              elevation: 0,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(16),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    ).whenComplete(() {
      sheetActive = false;
    });
  }

  Widget _detailStatCard({required String label, required String value}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 12),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.7),
              fontSize: 12,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            value,
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }

  Widget _hikeWeatherCard({
    required DateTime selectedDate,
    required DateTime visibleMonth,
    required DateTime firstDate,
    required DateTime lastDate,
    required _HikeWeatherForecast? forecast,
    required String? errorMessage,
    required bool isLoading,
    required VoidCallback onPreviousMonth,
    required VoidCallback onNextMonth,
    required ValueChanged<DateTime> onSelectDate,
    required VoidCallback onCheckWeather,
  }) {
    final riskColor = forecast == null
        ? const Color(0xFF7CF9A2)
        : _weatherRiskColor(forecast.risk);
    final canGoPrevious = _monthHasForecastableDates(
      DateTime(visibleMonth.year, visibleMonth.month - 1),
      firstDate,
      lastDate,
    );
    final canGoNext = _monthHasForecastableDates(
      DateTime(visibleMonth.year, visibleMonth.month + 1),
      firstDate,
      lastDate,
    );

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFF042117),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: riskColor.withValues(alpha: 0.34)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Select Hike Date',
            style: TextStyle(
              color: Colors.white,
              fontSize: 13,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 8),
          _hikeDateCalendar(
            visibleMonth: visibleMonth,
            selectedDate: selectedDate,
            firstDate: firstDate,
            lastDate: lastDate,
            canGoPrevious: canGoPrevious,
            canGoNext: canGoNext,
            onPreviousMonth: onPreviousMonth,
            onNextMonth: onNextMonth,
            onSelectDate: onSelectDate,
          ),
          const SizedBox(height: 12),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: const Color(0xFF031B13),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      width: 38,
                      height: 38,
                      decoration: BoxDecoration(
                        color: riskColor.withValues(alpha: 0.16),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Icon(
                        forecast == null
                            ? Icons.calendar_month_rounded
                            : _weatherConditionIcon(forecast.weatherCode),
                        color: riskColor,
                        size: 22,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'Weather Forecast',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 15,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            _formatHikeDate(selectedDate),
                            style: TextStyle(
                              color: Colors.white.withValues(alpha: 0.68),
                              fontSize: 12,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                if (isLoading) ...[
                  Row(
                    children: [
                      const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Color(0xFF53D97A),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Text(
                        'Checking mountain weather...',
                        style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.82),
                        ),
                      ),
                    ],
                  ),
                ] else if (forecast != null) ...[
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      Icon(
                        _weatherConditionIcon(forecast.weatherCode),
                        color: riskColor,
                        size: 42,
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          _temperatureRangeLabel(forecast),
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 22,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                      ),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          _weatherInlineMetric(
                            'Rain',
                            _rainChanceLabel(forecast),
                          ),
                          const SizedBox(height: 2),
                          _weatherInlineMetric(
                            'Precip',
                            _precipitationLabel(forecast),
                          ),
                          const SizedBox(height: 2),
                          _weatherInlineMetric(
                            'Wind',
                            _windSpeedLabel(forecast),
                          ),
                        ],
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(
                    forecast.summary,
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.88),
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  if (forecast.periodOutlooks.isNotEmpty) ...[
                    const SizedBox(height: 10),
                    Column(
                      children: [
                        for (final outlook in forecast.periodOutlooks) ...[
                          _weatherPeriodOutlookRow(outlook),
                          if (outlook != forecast.periodOutlooks.last)
                            const SizedBox(height: 6),
                        ],
                      ],
                    ),
                  ],
                  const SizedBox(height: 10),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: riskColor.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Icon(
                              _weatherRiskIcon(forecast.risk),
                              color: riskColor,
                              size: 18,
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                forecast.adviceTitle,
                                style: TextStyle(
                                  color: riskColor,
                                  fontSize: 13,
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 3),
                        Text(
                          forecast.adviceDetail,
                          style: TextStyle(
                            color: Colors.white.withValues(alpha: 0.82),
                            height: 1.25,
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                  ),
                ] else ...[
                  if (errorMessage != null) ...[
                    Text(
                      errorMessage,
                      style: const TextStyle(
                        color: Color(0xFFFFD76A),
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 10),
                  ],
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton.icon(
                      onPressed: onCheckWeather,
                      icon: const Icon(Icons.cloud_sync_rounded),
                      label: const Text('Check Weather'),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: const Color(0xFF7CF9A2),
                        side: BorderSide(
                          color: const Color(
                            0xFF7CF9A2,
                          ).withValues(alpha: 0.55),
                        ),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _hikeDateCalendar({
    required DateTime visibleMonth,
    required DateTime selectedDate,
    required DateTime firstDate,
    required DateTime lastDate,
    required bool canGoPrevious,
    required bool canGoNext,
    required VoidCallback onPreviousMonth,
    required VoidCallback onNextMonth,
    required ValueChanged<DateTime> onSelectDate,
  }) {
    final firstDay = DateTime(visibleMonth.year, visibleMonth.month);
    final daysInMonth = _daysInMonth(visibleMonth);
    final leadingSlots = firstDay.weekday % 7;
    final totalSlots = leadingSlots + daysInMonth;
    final rowCount = (totalSlots / 7).ceil();

    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: const Color(0xFF031B13),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
      ),
      child: Column(
        children: [
          Row(
            children: [
              _calendarNavButton(
                icon: Icons.chevron_left_rounded,
                enabled: canGoPrevious,
                onPressed: onPreviousMonth,
              ),
              Expanded(
                child: Center(
                  child: Text(
                    _formatMonthYear(visibleMonth),
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 13,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
              ),
              _calendarNavButton(
                icon: Icons.chevron_right_rounded,
                enabled: canGoNext,
                onPressed: onNextMonth,
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: const [
              _WeekdayLabel('SUN'),
              _WeekdayLabel('MON'),
              _WeekdayLabel('TUE'),
              _WeekdayLabel('WED'),
              _WeekdayLabel('THU'),
              _WeekdayLabel('FRI'),
              _WeekdayLabel('SAT'),
            ],
          ),
          const SizedBox(height: 4),
          for (var row = 0; row < rowCount; row++) ...[
            Row(
              children: [
                for (var col = 0; col < 7; col++)
                  _calendarDayCell(
                    slot: row * 7 + col,
                    leadingSlots: leadingSlots,
                    visibleMonth: visibleMonth,
                    daysInMonth: daysInMonth,
                    selectedDate: selectedDate,
                    firstDate: firstDate,
                    lastDate: lastDate,
                    onSelectDate: onSelectDate,
                  ),
              ],
            ),
          ],
          const SizedBox(height: 6),
          Align(
            alignment: Alignment.centerLeft,
            child: Text(
              'Available through ${_formatHikeDate(lastDate)}',
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.56),
                fontSize: 10,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _calendarNavButton({
    required IconData icon,
    required bool enabled,
    required VoidCallback onPressed,
  }) {
    return SizedBox(
      width: 28,
      height: 28,
      child: IconButton(
        onPressed: enabled ? onPressed : null,
        icon: Icon(icon, size: 18),
        padding: EdgeInsets.zero,
        color: const Color(0xFF7CF9A2),
        disabledColor: Colors.white.withValues(alpha: 0.18),
      ),
    );
  }

  Widget _calendarDayCell({
    required int slot,
    required int leadingSlots,
    required DateTime visibleMonth,
    required int daysInMonth,
    required DateTime selectedDate,
    required DateTime firstDate,
    required DateTime lastDate,
    required ValueChanged<DateTime> onSelectDate,
  }) {
    final dayNumber = slot - leadingSlots + 1;
    if (dayNumber < 1 || dayNumber > daysInMonth) {
      return const Expanded(child: SizedBox(height: 30));
    }

    final date = DateTime(visibleMonth.year, visibleMonth.month, dayNumber);
    final isEnabled = !date.isBefore(firstDate) && !date.isAfter(lastDate);
    final isSelected = _isSameDate(date, selectedDate);
    final isToday = _isSameDate(date, _dateOnly(DateTime.now()));

    return Expanded(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 1, vertical: 1),
        child: InkWell(
          onTap: isEnabled ? () => onSelectDate(date) : null,
          borderRadius: BorderRadius.circular(9),
          child: Container(
            height: 30,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: isSelected
                  ? const Color(0xFF53D97A)
                  : isToday
                  ? const Color(0xFF53D97A).withValues(alpha: 0.16)
                  : Colors.transparent,
              borderRadius: BorderRadius.circular(9),
              border: isToday && !isSelected
                  ? Border.all(
                      color: const Color(0xFF53D97A).withValues(alpha: 0.55),
                    )
                  : null,
            ),
            child: Text(
              dayNumber.toString(),
              style: TextStyle(
                color: !isEnabled
                    ? Colors.white.withValues(alpha: 0.18)
                    : isSelected
                    ? const Color(0xFF02130E)
                    : Colors.white,
                fontSize: 11,
                fontWeight: isSelected || isToday
                    ? FontWeight.w900
                    : FontWeight.w600,
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _weatherInlineMetric(String label, String value) {
    return Text(
      '$label  $value',
      style: TextStyle(
        color: Colors.white.withValues(alpha: 0.72),
        fontSize: 10,
        fontWeight: FontWeight.w700,
      ),
    );
  }

  Widget _weatherPeriodOutlookRow(_HikeWeatherPeriodOutlook outlook) {
    final riskColor = _weatherRiskColor(outlook.risk);
    final rainText = outlook.rainChancePercent == null
        ? ''
        : ' · ${outlook.rainChancePercent}% rain';

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.055),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            _weatherConditionIcon(outlook.weatherCode),
            color: riskColor,
            size: 18,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${outlook.label} (${outlook.timeRange})',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 12,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  '${outlook.summary}, ${outlook.temperatureLabel}$rainText',
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.74),
                    fontSize: 11,
                    height: 1.25,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Color _weatherRiskColor(_HikeWeatherRisk risk) {
    return switch (risk) {
      _HikeWeatherRisk.good => const Color(0xFF53D97A),
      _HikeWeatherRisk.caution => const Color(0xFFFFD76A),
      _HikeWeatherRisk.unsafe => const Color(0xFFFF7A7A),
    };
  }

  IconData _weatherRiskIcon(_HikeWeatherRisk risk) {
    return switch (risk) {
      _HikeWeatherRisk.good => Icons.check_circle_rounded,
      _HikeWeatherRisk.caution => Icons.warning_amber_rounded,
      _HikeWeatherRisk.unsafe => Icons.report_rounded,
    };
  }

  IconData _weatherConditionIcon(int weatherCode) {
    if (weatherCode == 0 || weatherCode == 1) {
      return Icons.wb_sunny_rounded;
    }
    if (weatherCode == 2 ||
        weatherCode == 3 ||
        weatherCode == 45 ||
        weatherCode == 48) {
      return Icons.cloud_rounded;
    }
    if (weatherCode >= 95) {
      return Icons.thunderstorm_rounded;
    }
    if (_isWetWeatherCode(weatherCode)) {
      return Icons.water_drop_rounded;
    }
    return Icons.cloud_queue_rounded;
  }

  String _temperatureRangeLabel(_HikeWeatherForecast forecast) {
    final min = forecast.temperatureMinC;
    final max = forecast.temperatureMaxC;
    if (min != null && max != null) {
      return '${min.round()}C - ${max.round()}C';
    }
    if (max != null) {
      return '${max.round()}C max';
    }
    if (min != null) {
      return '${min.round()}C min';
    }
    return 'Temp n/a';
  }

  String _rainChanceLabel(_HikeWeatherForecast forecast) {
    final rainChance = forecast.rainChancePercent;
    if (rainChance == null) {
      return 'Rain n/a';
    }
    return '$rainChance% rain';
  }

  String _precipitationLabel(_HikeWeatherForecast forecast) {
    final precipitation = forecast.precipitationMm;
    if (precipitation == null) {
      return 'Precip n/a';
    }
    return '${precipitation.toStringAsFixed(1)} mm';
  }

  String _windSpeedLabel(_HikeWeatherForecast forecast) {
    final windSpeed = forecast.windSpeedKmh;
    if (windSpeed == null) {
      return 'Wind n/a';
    }
    return '${windSpeed.round()} km/h';
  }

  Widget _detailRow(String label, String value) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 120,
          child: Text(
            label,
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.78),
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            value.isEmpty ? '-' : value,
            style: const TextStyle(color: Colors.white),
          ),
        ),
      ],
    );
  }
}

class _HikeCheckpoint {
  const _HikeCheckpoint({
    required this.name,
    required this.location,
    required this.routeProgressMeters,
    this.isSummit = false,
  });

  final String name;
  final LatLng location;
  final double routeProgressMeters;
  final bool isSummit;
}

class _ResolvedHikeTarget {
  const _ResolvedHikeTarget({required this.target, required this.fromPeakData});

  final LatLng target;
  final bool fromPeakData;
}

class _GpxWaypoint {
  const _GpxWaypoint({
    required this.name,
    required this.location,
    this.elevationMasl,
  });

  final String name;
  final LatLng location;
  final int? elevationMasl;
}

class _ParsedGpxTrail {
  const _ParsedGpxTrail({
    required this.assetPath,
    required this.points,
    required this.waypoints,
    required this.summitLocation,
    required this.peakElevationMasl,
  });

  final String assetPath;
  final List<LatLng> points;
  final List<_GpxWaypoint> waypoints;
  final LatLng summitLocation;
  final int? peakElevationMasl;
}

class _HikingModeScreen extends StatefulWidget {
  const _HikingModeScreen({
    required this.trail,
    required this.mapsApiKey,
    this.communityTrail,
    this.preferredGpxAssetPath,
    this.selectedRouteLabel,
  });

  final _NearbyTrail trail;
  final String mapsApiKey;
  final _CommunityTrailData? communityTrail;
  final String? preferredGpxAssetPath;
  final String? selectedRouteLabel;

  @override
  State<_HikingModeScreen> createState() => _HikingModeScreenState();
}

class _HikingModeScreenState extends State<_HikingModeScreen> {
  StreamSubscription<Position>? _positionSubscription;
  StreamSubscription<List<ConnectivityResult>>? _connectivitySubscription;
  Timer? _elapsedTimer;
  final DateTime _startedAt = DateTime.now();
  final List<LatLng> _trackPoints = <LatLng>[];
  final List<_TrailTrackPoint> _rawTrackPoints = <_TrailTrackPoint>[];
  final Set<String> _reachedCheckpoints = <String>{};
  final OfflineActivityDatabase _activityDatabase =
      OfflineActivityDatabase.instance;

  late List<_HikeCheckpoint> _checkpoints;
  OfflineActivity? _offlineActivity;
  List<LatLng> _plannedRoutePoints = <LatLng>[];
  List<double> _routeProgressMeters = <double>[];
  double _routeTotalMeters = 0;
  int _activeRouteIndex = 0;
  DateTime? _lastRouteRefreshAt;
  LatLng? _hikeTarget;
  bool _usingResolvedPeak = false;
  bool _usingGpxTrail = false;
  bool _usingCommunityTrail = false;
  String? _gpxTrailAssetPath;
  List<_GpxWaypoint> _gpxWaypoints = const <_GpxWaypoint>[];
  double _trailJoinDistanceMeters = 0;
  int? _resolvedPeakMasl;
  double? _currentElevationAccuracyMeters;
  Position? _lastPosition;
  LatLng? _currentLocation;
  double _trackedDistanceMeters = 0;
  double? _startElevationMasl;
  double _currentElevationMasl = 0;
  double _maxElevationMasl = 0;
  bool _initializing = true;
  bool _ending = false;
  bool _sendingSos = false;
  bool _hasNetworkConnection = true;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _checkpoints = const <_HikeCheckpoint>[];
    unawaited(_startConnectivityMonitor());
    _elapsedTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) {
        return;
      }
      final activity = _offlineActivity;
      if (activity != null && _elapsed.inSeconds % 10 == 0) {
        unawaited(_saveOfflineHikeStats());
      }
      setState(() {
        // Rebuild every second so elapsed time updates smoothly.
      });
    });
    unawaited(_startTracking());
  }

  @override
  void dispose() {
    _elapsedTimer?.cancel();
    _positionSubscription?.cancel();
    _connectivitySubscription?.cancel();
    super.dispose();
  }

  Future<void> _startConnectivityMonitor() async {
    final connectivity = Connectivity();
    final initialResults = await connectivity.checkConnectivity();
    _updateNetworkState(initialResults);
    _connectivitySubscription = connectivity.onConnectivityChanged.listen(
      _updateNetworkState,
    );
  }

  void _updateNetworkState(List<ConnectivityResult> results) {
    if (!mounted) return;
    final hasConnection = !results.contains(ConnectivityResult.none);
    if (_hasNetworkConnection == hasConnection) {
      return;
    }
    setState(() {
      _hasNetworkConnection = hasConnection;
    });
  }

  Future<void> _startTracking() async {
    try {
      final serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        if (!mounted) {
          return;
        }
        setState(() {
          _initializing = false;
          _errorMessage = 'Location service is off.';
        });
        return;
      }

      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      if (permission == LocationPermission.denied ||
          permission == LocationPermission.deniedForever) {
        if (!mounted) {
          return;
        }
        setState(() {
          _initializing = false;
          _errorMessage = 'Location permission denied.';
        });
        return;
      }

      final initialPosition = await Geolocator.getCurrentPosition(
        locationSettings: _hikeLocationSettings(foreground: false),
      );

      if (!mounted) {
        return;
      }

      final startPoint = LatLng(
        initialPosition.latitude,
        initialPosition.longitude,
      );
      final communityTrail = widget.communityTrail;
      if (communityTrail != null &&
          (communityTrail.status == 'verified' ||
              communityTrail.status == 'provisional') &&
          communityTrail.points.length >= 2) {
        _initializeFromCommunityTrail(communityTrail);
        await _connectStartToGpxTrail(startPoint);
      } else {
        final gpxTrail = await _loadGpxTrailForMountain();
        if (gpxTrail != null && gpxTrail.points.length >= 2) {
          _initializeFromGpxTrail(gpxTrail);
          await _connectStartToGpxTrail(startPoint);
        } else {
          final targetResolution = await _resolveHikeTarget();
          _hikeTarget = targetResolution.target;
          _usingResolvedPeak = targetResolution.fromPeakData;
          _resolvedPeakMasl = await _fetchElevationMasl(_hikeTarget!);
          await _refreshRouteAndCheckpoints(startPoint, force: true);
        }
      }
      _offlineActivity = await _activityDatabase.createActivity(
        activityType: 'hike',
        startedAt: _startedAt,
      );
      _updateFromPosition(initialPosition, isInitial: true);

      _positionSubscription =
          Geolocator.getPositionStream(
            locationSettings: _hikeLocationSettings(),
          ).listen(
            (position) => _updateFromPosition(position),
            onError: (_) {
              if (!mounted) {
                return;
              }
              setState(() {
                _errorMessage =
                    'Live tracking interrupted. Trying to reconnect...';
              });
            },
          );

      setState(() {
        _initializing = false;
        _errorMessage = null;
      });
    } catch (_) {
      if (!mounted) {
        return;
      }
      setState(() {
        _initializing = false;
        _errorMessage = 'Unable to start live hiking mode.';
      });
    }
  }

  LocationSettings _hikeLocationSettings({bool foreground = true}) {
    if (Platform.isAndroid) {
      return AndroidSettings(
        accuracy: LocationAccuracy.bestForNavigation,
        distanceFilter: 5,
        intervalDuration: const Duration(seconds: 5),
        foregroundNotificationConfig: foreground
            ? const ForegroundNotificationConfig(
                notificationTitle: 'Agakbay hiking mode',
                notificationText: 'Tracking Offline - GPS Active',
                notificationChannelName: 'Hiking tracking',
                enableWakeLock: true,
                setOngoing: true,
              )
            : null,
      );
    }
    return const LocationSettings(
      accuracy: LocationAccuracy.bestForNavigation,
      distanceFilter: 5,
    );
  }

  Future<void> _refreshRouteAndCheckpoints(
    LatLng start, {
    bool force = false,
  }) async {
    if (_usingGpxTrail) {
      return;
    }
    if (!force && _lastRouteRefreshAt != null) {
      final elapsed = DateTime.now().difference(_lastRouteRefreshAt!);
      if (elapsed < const Duration(seconds: 45)) {
        return;
      }
    }

    final destination = _hikeTarget ?? widget.trail.location;
    final route = await _fetchWalkingRoute(start, destination);
    if (!mounted) {
      return;
    }

    final nextRoutePoints = route.length >= 2
        ? route
        : <LatLng>[start, destination];
    final nextProgress = _buildRouteProgress(nextRoutePoints);
    final nextTotal = nextProgress.isEmpty ? 0.0 : nextProgress.last;
    setState(() {
      _plannedRoutePoints = nextRoutePoints;
      _routeProgressMeters = nextProgress;
      _routeTotalMeters = nextTotal;
      _checkpoints = _buildCheckpointsFromRoute();
      _activeRouteIndex = _findNearestRouteIndex(start);
      _lastRouteRefreshAt = DateTime.now();
    });
  }

  Future<_ParsedGpxTrail?> _loadGpxTrailForMountain() async {
    final preferredAsset = widget.preferredGpxAssetPath?.trim();
    if (preferredAsset != null && preferredAsset.isNotEmpty) {
      try {
        final gpxRaw = await rootBundle.loadString(preferredAsset);
        final parsed = _parseGpx(preferredAsset, gpxRaw);
        if (parsed != null && parsed.points.length >= 2) {
          return parsed;
        }
      } catch (_) {
        // Fall back to auto-matching.
      }
    }

    final directCandidates = _gpxCandidatePathsForTrail(widget.trail.name);
    for (final candidate in directCandidates) {
      try {
        final gpxRaw = await rootBundle.loadString(candidate);
        final parsed = _parseGpx(candidate, gpxRaw);
        if (parsed != null && parsed.points.length >= 2) {
          return parsed;
        }
      } catch (_) {
        // try next candidate
      }
    }

    try {
      final manifest = await AssetManifest.loadFromAssetBundle(rootBundle);
      final allAssets = manifest.listAssets();
      final gpxAssets = allAssets
          .where(
            (asset) =>
                asset.startsWith('assets/trails/') &&
                asset.toLowerCase().endsWith('.gpx'),
          )
          .toList();
      if (gpxAssets.isEmpty) {
        return null;
      }
      final selectedAsset = _selectBestGpxAsset(gpxAssets, widget.trail.name);
      if (selectedAsset == null) {
        return null;
      }
      final gpxRaw = await rootBundle.loadString(selectedAsset);
      final parsed = _parseGpx(selectedAsset, gpxRaw);
      if (parsed == null || parsed.points.length < 2) {
        return null;
      }
      return parsed;
    } catch (_) {
      return null;
    }
  }

  List<String> _gpxCandidatePathsForTrail(String trailName) {
    final normalized = _normalizeTrailTokenString(trailName);
    final rawTokens = normalized
        .split(' ')
        .where((token) => token.isNotEmpty)
        .toList();
    final tokens = rawTokens
        .where((token) => token != 'trail' && token != 'site')
        .toList();

    final candidates = <String>{
      'assets/trails/${rawTokens.join('_')}.gpx',
      'assets/trails/${tokens.join('_')}.gpx',
    };

    if (tokens.length >= 2) {
      candidates.add('assets/trails/${tokens.take(2).join('_')}.gpx');
    }
    if (tokens.isNotEmpty) {
      candidates.add('assets/trails/${tokens.first}.gpx');
      candidates.add('assets/trails/${tokens.last}.gpx');
    }
    if (tokens.contains('apo')) {
      candidates.add('assets/trails/mt_apo.gpx');
      candidates.add('assets/trails/mount_apo.gpx');
      candidates.add('assets/trails/apo.gpx');
    }

    return candidates.where((path) => !path.contains('__')).toList();
  }

  String? _selectBestGpxAsset(List<String> gpxAssets, String trailName) {
    final normalizedTrail = _normalizeTrailTokenString(trailName);
    final trailTokens = normalizedTrail
        .split(' ')
        .where((token) => token.length >= 3)
        .toSet();
    String? bestAsset;
    var bestScore = -1.0;
    for (final asset in gpxAssets) {
      final fileName = asset.split('/').last.replaceAll('.gpx', '');
      final normalizedAsset = _normalizeTrailTokenString(fileName);
      final assetTokens = normalizedAsset
          .split(' ')
          .where((token) => token.length >= 3)
          .toSet();

      var score = 0.0;
      for (final token in trailTokens) {
        if (assetTokens.contains(token)) {
          score += 2;
        } else if (normalizedAsset.contains(token)) {
          score += 1;
        }
      }
      if (normalizedAsset == normalizedTrail) {
        score += 6;
      } else if (normalizedAsset.contains(normalizedTrail) ||
          normalizedTrail.contains(normalizedAsset)) {
        score += 3;
      }
      if (score > bestScore) {
        bestScore = score;
        bestAsset = asset;
      }
    }
    if (bestScore < 2) {
      return null;
    }
    return bestAsset;
  }

  String _normalizeTrailTokenString(String value) {
    return value.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]+'), ' ').trim();
  }

  _ParsedGpxTrail? _parseGpx(String assetPath, String gpxRaw) {
    final trackPoints = <LatLng>[];
    LatLng? highestPoint;
    int? highestElevationMasl;

    final trkPointRegex = RegExp(
      r'<trkpt\b[^>]*\blat="([^"]+)"[^>]*\blon="([^"]+)"[^>]*>([\s\S]*?)</trkpt>',
      caseSensitive: false,
    );
    for (final match in trkPointRegex.allMatches(gpxRaw)) {
      final lat = double.tryParse(match.group(1) ?? '');
      final lon = double.tryParse(match.group(2) ?? '');
      if (lat != null && lon != null) {
        final point = LatLng(lat, lon);
        trackPoints.add(point);
        final body = match.group(3) ?? '';
        final eleMatch = RegExp(
          r'<ele[^>]*>\s*([^<]+)\s*</ele>',
          caseSensitive: false,
        ).firstMatch(body);
        final eleRaw = eleMatch?.group(1);
        final ele = eleRaw == null ? null : double.tryParse(eleRaw.trim());
        if (ele != null) {
          final rounded = ele.round();
          if (highestElevationMasl == null || rounded > highestElevationMasl) {
            highestElevationMasl = rounded;
            highestPoint = point;
          }
        }
      }
    }

    if (trackPoints.isEmpty) {
      final trkSelfClosingRegex = RegExp(
        r'<trkpt\b[^>]*\blat="([^"]+)"[^>]*\blon="([^"]+)"[^>]*/>',
        caseSensitive: false,
      );
      for (final match in trkSelfClosingRegex.allMatches(gpxRaw)) {
        final lat = double.tryParse(match.group(1) ?? '');
        final lon = double.tryParse(match.group(2) ?? '');
        if (lat != null && lon != null) {
          trackPoints.add(LatLng(lat, lon));
        }
      }
    }

    if (trackPoints.length < 2) {
      final routePoints = <LatLng>[];
      final rtePointRegex = RegExp(
        r'<rtept\b[^>]*\blat="([^"]+)"[^>]*\blon="([^"]+)"[^>]*/?>',
        caseSensitive: false,
      );
      for (final match in rtePointRegex.allMatches(gpxRaw)) {
        final lat = double.tryParse(match.group(1) ?? '');
        final lon = double.tryParse(match.group(2) ?? '');
        if (lat != null && lon != null) {
          routePoints.add(LatLng(lat, lon));
        }
      }
      if (routePoints.length < 2) {
        return null;
      }
      trackPoints.clear();
      trackPoints.addAll(routePoints);
    }

    final waypoints = <_GpxWaypoint>[];
    final waypointRegex = RegExp(
      r'<wpt\b[^>]*\blat="([^"]+)"[^>]*\blon="([^"]+)"[^>]*>([\s\S]*?)</wpt>',
      caseSensitive: false,
    );
    for (final match in waypointRegex.allMatches(gpxRaw)) {
      final lat = double.tryParse(match.group(1) ?? '');
      final lon = double.tryParse(match.group(2) ?? '');
      final body = match.group(3) ?? '';
      if (lat == null || lon == null) {
        continue;
      }
      final nameMatch = RegExp(
        r'<name[^>]*>([\s\S]*?)</name>',
        caseSensitive: false,
      ).firstMatch(body);
      final rawName = (nameMatch?.group(1) ?? '').trim();
      if (rawName.isEmpty) {
        continue;
      }
      final eleMatch = RegExp(
        r'<ele[^>]*>\s*([^<]+)\s*</ele>',
        caseSensitive: false,
      ).firstMatch(body);
      final eleValue = double.tryParse((eleMatch?.group(1) ?? '').trim());
      waypoints.add(
        _GpxWaypoint(
          name: _decodeBasicXmlEntities(rawName),
          location: LatLng(lat, lon),
          elevationMasl: eleValue?.round(),
        ),
      );
    }

    LatLng summitLocation = trackPoints.last;
    int? summitElevation = highestElevationMasl;
    for (final waypoint in waypoints) {
      final lower = waypoint.name.toLowerCase();
      if (lower.contains('summit') || lower.contains('peak')) {
        summitLocation = waypoint.location;
        summitElevation = waypoint.elevationMasl ?? summitElevation;
        break;
      }
    }
    if (summitElevation == null && highestPoint != null) {
      summitLocation = highestPoint;
      summitElevation = highestElevationMasl;
    }

    return _ParsedGpxTrail(
      assetPath: assetPath,
      points: trackPoints,
      waypoints: waypoints,
      summitLocation: summitLocation,
      peakElevationMasl: summitElevation,
    );
  }

  String _decodeBasicXmlEntities(String value) {
    return value
        .replaceAll('&amp;', '&')
        .replaceAll('&quot;', '"')
        .replaceAll('&apos;', "'")
        .replaceAll('&lt;', '<')
        .replaceAll('&gt;', '>');
  }

  void _initializeFromGpxTrail(_ParsedGpxTrail gpxTrail) {
    final progress = _buildRouteProgress(gpxTrail.points);
    final total = progress.isEmpty ? 0.0 : progress.last;
    _hikeTarget = gpxTrail.summitLocation;
    _resolvedPeakMasl = gpxTrail.peakElevationMasl;
    _usingGpxTrail = true;
    _usingResolvedPeak = true;
    _gpxTrailAssetPath = gpxTrail.assetPath;
    _gpxWaypoints = gpxTrail.waypoints;
    _trailJoinDistanceMeters = 0;
    _plannedRoutePoints = gpxTrail.points;
    _routeProgressMeters = progress;
    _routeTotalMeters = total;
    _checkpoints = _buildCheckpointsFromGpxWaypoints(_gpxWaypoints);
    _activeRouteIndex = 0;
    _lastRouteRefreshAt = DateTime.now();
  }

  void _initializeFromCommunityTrail(_CommunityTrailData communityTrail) {
    final points = communityTrail.points;
    final progress = _buildRouteProgress(points);
    final total = progress.isEmpty ? 0.0 : progress.last;
    _hikeTarget = points.last;
    _usingCommunityTrail = true;
    _usingGpxTrail = false;
    _usingResolvedPeak = false;
    _gpxTrailAssetPath = null;
    _gpxWaypoints = const <_GpxWaypoint>[];
    _trailJoinDistanceMeters = 0;
    _plannedRoutePoints = points;
    _routeProgressMeters = progress;
    _routeTotalMeters = total;
    _checkpoints = _buildCheckpointsFromRoute();
    _activeRouteIndex = 0;
    _lastRouteRefreshAt = DateTime.now();
  }

  Future<void> _connectStartToGpxTrail(LatLng start) async {
    if ((!_usingGpxTrail && !_usingCommunityTrail) ||
        _plannedRoutePoints.length < 2) {
      return;
    }
    final nearestIndex = _findNearestRouteIndex(start);
    final nearestPoint = _plannedRoutePoints[nearestIndex];
    final joinDistance = Geolocator.distanceBetween(
      start.latitude,
      start.longitude,
      nearestPoint.latitude,
      nearestPoint.longitude,
    );

    if (!mounted) {
      return;
    }

    // Already on/very near the mapped trail.
    if (joinDistance <= 60) {
      setState(() {
        _trailJoinDistanceMeters = joinDistance;
        _activeRouteIndex = nearestIndex;
      });
      return;
    }

    final connector = await _fetchWalkingRoute(start, nearestPoint);
    if (!mounted) {
      return;
    }
    final connectorPoints = connector.length >= 2
        ? connector
        : <LatLng>[start, nearestPoint];
    final suffix = _plannedRoutePoints.sublist(nearestIndex);

    final merged = <LatLng>[...connectorPoints];
    if (suffix.isNotEmpty) {
      final lastConnector = merged.last;
      final firstSuffix = suffix.first;
      final gap = Geolocator.distanceBetween(
        lastConnector.latitude,
        lastConnector.longitude,
        firstSuffix.latitude,
        firstSuffix.longitude,
      );
      if (gap <= 6) {
        merged.addAll(suffix.skip(1));
      } else {
        merged.addAll(suffix);
      }
    }
    if (merged.length < 2) {
      return;
    }

    final mergedProgress = _buildRouteProgress(merged);
    final mergedTotal = mergedProgress.isEmpty ? 0.0 : mergedProgress.last;

    setState(() {
      _trailJoinDistanceMeters = joinDistance;
      _plannedRoutePoints = merged;
      _routeProgressMeters = mergedProgress;
      _routeTotalMeters = mergedTotal;
      _checkpoints = _buildCheckpointsFromGpxWaypoints(_gpxWaypoints);
      _activeRouteIndex = 0;
      _lastRouteRefreshAt = DateTime.now();
    });
  }

  List<_HikeCheckpoint> _buildCheckpointsFromGpxWaypoints(
    List<_GpxWaypoint> waypoints,
  ) {
    LatLng peakLocation = _hikeTarget ?? widget.trail.location;
    for (final waypoint in waypoints) {
      final lower = waypoint.name.toLowerCase();
      if (lower.contains('summit') || lower.contains('peak')) {
        peakLocation = waypoint.location;
        _resolvedPeakMasl = waypoint.elevationMasl ?? _resolvedPeakMasl;
        break;
      }
    }

    final peakIndex = _findNearestRouteIndex(peakLocation);
    final peakProgress = peakIndex < _routeProgressMeters.length
        ? _routeProgressMeters[peakIndex]
        : _routeTotalMeters;
    return <_HikeCheckpoint>[
      _HikeCheckpoint(
        name: 'Peak',
        location: peakLocation,
        routeProgressMeters: peakProgress,
        isSummit: true,
      ),
    ];
  }

  Future<_ResolvedHikeTarget> _resolveHikeTarget() async {
    final fallback = widget.trail.location;
    final resolvedPeak = await _findPeakInOsm();
    if (resolvedPeak == null) {
      return _ResolvedHikeTarget(target: fallback, fromPeakData: false);
    }
    final toFallbackMeters = Geolocator.distanceBetween(
      fallback.latitude,
      fallback.longitude,
      resolvedPeak.latitude,
      resolvedPeak.longitude,
    );
    if (toFallbackMeters > 30000) {
      return _ResolvedHikeTarget(target: fallback, fromPeakData: false);
    }
    return _ResolvedHikeTarget(target: resolvedPeak, fromPeakData: true);
  }

  Future<LatLng?> _findPeakInOsm() async {
    final center = widget.trail.location;
    final south = (center.latitude - 0.25).toStringAsFixed(6);
    final north = (center.latitude + 0.25).toStringAsFixed(6);
    final west = (center.longitude - 0.25).toStringAsFixed(6);
    final east = (center.longitude + 0.25).toStringAsFixed(6);
    final query = '${widget.trail.name} peak, Mindanao, Philippines';

    try {
      final uri = Uri.https('nominatim.openstreetmap.org', '/search', {
        'q': query,
        'format': 'jsonv2',
        'limit': '12',
        'bounded': '1',
        'viewbox': '$west,$north,$east,$south',
      });
      final response = await http
          .get(
            uri,
            headers: const {
              'User-Agent': 'Agakbay/1.0',
              'Accept': 'application/json',
            },
          )
          .timeout(const Duration(seconds: 10));
      if (response.statusCode != 200) {
        return null;
      }
      final decoded = jsonDecode(response.body);
      if (decoded is! List) {
        return null;
      }

      Map<String, dynamic>? best;
      var bestScore = -1.0;
      for (final item in decoded) {
        if (item is! Map<String, dynamic>) {
          continue;
        }
        final lat = double.tryParse(item['lat']?.toString() ?? '');
        final lon = double.tryParse(item['lon']?.toString() ?? '');
        if (lat == null || lon == null) {
          continue;
        }
        final name =
            item['name']?.toString() ?? item['display_name']?.toString() ?? '';
        final itemClass = item['class']?.toString().toLowerCase() ?? '';
        final itemType = item['type']?.toString().toLowerCase() ?? '';
        final distKm =
            Geolocator.distanceBetween(
              center.latitude,
              center.longitude,
              lat,
              lon,
            ) /
            1000;
        if (distKm > 30) {
          continue;
        }
        var score = 0.0;
        if (itemClass == 'natural' && itemType == 'peak') {
          score += 8;
        }
        if (itemType.contains('peak') || name.toLowerCase().contains('peak')) {
          score += 2;
        }
        if (_isLikelyPeakName(name, widget.trail.name)) {
          score += 3;
        }
        score -= distKm / 6;
        if (score > bestScore) {
          bestScore = score;
          best = item;
        }
      }

      if (best == null) {
        return null;
      }
      final lat = double.tryParse(best['lat']?.toString() ?? '');
      final lon = double.tryParse(best['lon']?.toString() ?? '');
      if (lat == null || lon == null) {
        return null;
      }
      return LatLng(lat, lon);
    } catch (_) {
      return null;
    }
  }

  bool _isLikelyPeakName(String value, String trailName) {
    final normalizedValue = value.toLowerCase();
    final normalizedTrail = trailName.toLowerCase();
    final parts = normalizedTrail
        .split(RegExp(r'[^a-z0-9]+'))
        .where((p) => p.length >= 3)
        .toList();
    if (parts.isEmpty) {
      return normalizedValue.contains(normalizedTrail);
    }
    var matches = 0;
    for (final part in parts) {
      if (normalizedValue.contains(part)) {
        matches++;
      }
    }
    return matches >= (parts.length == 1 ? 1 : 2);
  }

  Future<List<LatLng>> _fetchWalkingRoute(
    LatLng origin,
    LatLng destination,
  ) async {
    final osrmRoute = await _fetchOsrmWalkingRoute(origin, destination);
    if (osrmRoute.length >= 2) {
      return osrmRoute;
    }
    if (widget.mapsApiKey.trim().isEmpty) {
      return const <LatLng>[];
    }
    try {
      final uri =
          Uri.https('maps.googleapis.com', '/maps/api/directions/json', {
            'origin': '${origin.latitude},${origin.longitude}',
            'destination': '${destination.latitude},${destination.longitude}',
            'mode': 'walking',
            'alternatives': 'false',
            'region': 'ph',
            'key': widget.mapsApiKey,
          });
      final response = await http.get(uri).timeout(const Duration(seconds: 10));
      if (response.statusCode != 200) {
        return const <LatLng>[];
      }
      final decoded = jsonDecode(response.body);
      if (decoded is! Map<String, dynamic>) {
        return const <LatLng>[];
      }
      final status = decoded['status']?.toString() ?? '';
      if (status != 'OK') {
        return const <LatLng>[];
      }
      final routes = decoded['routes'];
      if (routes is! List || routes.isEmpty) {
        return const <LatLng>[];
      }
      final route0 = routes.first;
      if (route0 is! Map<String, dynamic>) {
        return const <LatLng>[];
      }
      final overview = route0['overview_polyline'];
      if (overview is! Map<String, dynamic>) {
        return const <LatLng>[];
      }
      final encoded = overview['points']?.toString() ?? '';
      if (encoded.isEmpty) {
        return const <LatLng>[];
      }
      return _decodePolyline(encoded);
    } catch (_) {
      return const <LatLng>[];
    }
  }

  Future<List<LatLng>> _fetchOsrmWalkingRoute(
    LatLng origin,
    LatLng destination,
  ) async {
    try {
      final coordinates =
          '${origin.longitude},${origin.latitude};${destination.longitude},${destination.latitude}';
      final uri =
          Uri.https('router.project-osrm.org', '/route/v1/foot/$coordinates', {
            'overview': 'full',
            'alternatives': 'false',
            'steps': 'false',
            'geometries': 'geojson',
          });
      final response = await http.get(uri).timeout(const Duration(seconds: 10));
      if (response.statusCode != 200) {
        return const <LatLng>[];
      }
      final decoded = jsonDecode(response.body);
      if (decoded is! Map<String, dynamic>) {
        return const <LatLng>[];
      }
      final code = decoded['code']?.toString() ?? '';
      if (code != 'Ok') {
        return const <LatLng>[];
      }
      final routes = decoded['routes'];
      if (routes is! List || routes.isEmpty) {
        return const <LatLng>[];
      }
      final route0 = routes.first;
      if (route0 is! Map<String, dynamic>) {
        return const <LatLng>[];
      }
      final geometry = route0['geometry'];
      if (geometry is! Map<String, dynamic>) {
        return const <LatLng>[];
      }
      final coordinatesJson = geometry['coordinates'];
      if (coordinatesJson is! List) {
        return const <LatLng>[];
      }
      final points = <LatLng>[];
      for (final pair in coordinatesJson) {
        if (pair is List && pair.length >= 2) {
          final lon = (pair[0] is num)
              ? (pair[0] as num).toDouble()
              : double.tryParse(pair[0].toString());
          final lat = (pair[1] is num)
              ? (pair[1] as num).toDouble()
              : double.tryParse(pair[1].toString());
          if (lat != null && lon != null) {
            points.add(LatLng(lat, lon));
          }
        }
      }
      return points;
    } catch (_) {
      return const <LatLng>[];
    }
  }

  Future<int?> _fetchElevationMasl(LatLng point) async {
    try {
      final uri = Uri.https('api.open-meteo.com', '/v1/elevation', {
        'latitude': point.latitude.toString(),
        'longitude': point.longitude.toString(),
      });
      final response = await http.get(uri).timeout(const Duration(seconds: 6));
      if (response.statusCode != 200) {
        return null;
      }
      final decoded = jsonDecode(response.body);
      if (decoded is! Map<String, dynamic>) {
        return null;
      }
      final raw = decoded['elevation'];
      if (raw is List && raw.isNotEmpty && raw.first is num) {
        return (raw.first as num).round();
      }
      if (raw is num) {
        return raw.round();
      }
      return null;
    } catch (_) {
      return null;
    }
  }

  List<LatLng> _decodePolyline(String encoded) {
    final points = <LatLng>[];
    var index = 0;
    var lat = 0;
    var lng = 0;

    while (index < encoded.length) {
      var result = 1;
      var shift = 0;
      var b = 0;
      do {
        b = encoded.codeUnitAt(index++) - 63 - 1;
        result += b << shift;
        shift += 5;
      } while (b >= 0x1f);
      lat += (result & 1) != 0 ? ~(result >> 1) : result >> 1;

      result = 1;
      shift = 0;
      do {
        b = encoded.codeUnitAt(index++) - 63 - 1;
        result += b << shift;
        shift += 5;
      } while (b >= 0x1f);
      lng += (result & 1) != 0 ? ~(result >> 1) : result >> 1;

      points.add(LatLng(lat / 1e5, lng / 1e5));
    }
    return points;
  }

  List<double> _buildRouteProgress(List<LatLng> routePoints) {
    if (routePoints.isEmpty) {
      return const <double>[];
    }
    final progress = <double>[0];
    var total = 0.0;
    for (var i = 1; i < routePoints.length; i++) {
      final prev = routePoints[i - 1];
      final curr = routePoints[i];
      total += Geolocator.distanceBetween(
        prev.latitude,
        prev.longitude,
        curr.latitude,
        curr.longitude,
      );
      progress.add(total);
    }
    return progress;
  }

  int _suggestCampCount() {
    final difficulty = widget.trail.difficulty.toLowerCase();
    if (difficulty.contains('hard') ||
        widget.trail.elevationMasl >= 2200 ||
        _routeTotalMeters >= 11000) {
      return 2;
    }
    if (difficulty.contains('moderate') ||
        widget.trail.elevationMasl >= 1200 ||
        _routeTotalMeters >= 5500) {
      return 1;
    }
    return 0;
  }

  LatLng _pointAtRouteProgress(double progressMeters) {
    if (_plannedRoutePoints.isEmpty || _routeProgressMeters.isEmpty) {
      return widget.trail.location;
    }
    if (progressMeters <= 0) {
      return _plannedRoutePoints.first;
    }
    if (progressMeters >= _routeTotalMeters) {
      return _plannedRoutePoints.last;
    }
    for (var i = 1; i < _routeProgressMeters.length; i++) {
      final prevProgress = _routeProgressMeters[i - 1];
      final nextProgress = _routeProgressMeters[i];
      if (progressMeters <= nextProgress) {
        final segment = nextProgress - prevProgress;
        final t = segment <= 0
            ? 0.0
            : (progressMeters - prevProgress) / segment;
        final from = _plannedRoutePoints[i - 1];
        final to = _plannedRoutePoints[i];
        return LatLng(
          from.latitude + ((to.latitude - from.latitude) * t),
          from.longitude + ((to.longitude - from.longitude) * t),
        );
      }
    }
    return _plannedRoutePoints.last;
  }

  List<_HikeCheckpoint> _buildCheckpointsFromRoute() {
    final campCount = _suggestCampCount();
    final peakLocation = _hikeTarget ?? widget.trail.location;
    final checkpoints = <_HikeCheckpoint>[];
    if (campCount >= 1) {
      final camp1Progress = _routeTotalMeters * 0.45;
      checkpoints.add(
        _HikeCheckpoint(
          name: 'Camp 1',
          location: _pointAtRouteProgress(camp1Progress),
          routeProgressMeters: camp1Progress,
        ),
      );
    }
    if (campCount >= 2) {
      final camp2Progress = _routeTotalMeters * 0.75;
      checkpoints.add(
        _HikeCheckpoint(
          name: 'Camp 2',
          location: _pointAtRouteProgress(camp2Progress),
          routeProgressMeters: camp2Progress,
        ),
      );
    }
    checkpoints.add(
      _HikeCheckpoint(
        name: 'Peak',
        location: peakLocation,
        routeProgressMeters: _routeTotalMeters,
        isSummit: true,
      ),
    );
    return checkpoints;
  }

  void _updateFromPosition(Position position, {bool isInitial = false}) {
    if (!mounted) {
      return;
    }

    final currentPoint = LatLng(position.latitude, position.longitude);
    var segmentMeters = 0.0;
    var shouldPersistPoint = false;
    final previous = _lastPosition;
    if (previous != null) {
      segmentMeters = Geolocator.distanceBetween(
        previous.latitude,
        previous.longitude,
        position.latitude,
        position.longitude,
      );
    }

    setState(() {
      if (!isInitial && segmentMeters >= 2 && segmentMeters <= 250) {
        _trackedDistanceMeters += segmentMeters;
      }

      if (_trackPoints.isEmpty) {
        _trackPoints.add(currentPoint);
      } else {
        final latestPoint = _trackPoints.last;
        final spacingMeters = Geolocator.distanceBetween(
          latestPoint.latitude,
          latestPoint.longitude,
          currentPoint.latitude,
          currentPoint.longitude,
        );
        if (spacingMeters >= 3) {
          _trackPoints.add(currentPoint);
        }
      }
      if (_rawTrackPoints.isEmpty) {
        shouldPersistPoint = true;
        _rawTrackPoints.add(
          _TrailTrackPoint(
            lat: position.latitude,
            lon: position.longitude,
            timestamp: position.timestamp.toUtc(),
            altitudeMasl: position.altitude.isFinite ? position.altitude : null,
            accuracyMeters: position.accuracy.isFinite
                ? position.accuracy
                : null,
            speedMps: position.speed.isFinite ? position.speed : null,
          ),
        );
      } else {
        final latestRaw = _rawTrackPoints.last;
        final rawSpacingMeters = Geolocator.distanceBetween(
          latestRaw.lat,
          latestRaw.lon,
          position.latitude,
          position.longitude,
        );
        if (rawSpacingMeters >= 2) {
          shouldPersistPoint = true;
          _rawTrackPoints.add(
            _TrailTrackPoint(
              lat: position.latitude,
              lon: position.longitude,
              timestamp: position.timestamp.toUtc(),
              altitudeMasl: position.altitude.isFinite
                  ? position.altitude
                  : null,
              accuracyMeters: position.accuracy.isFinite
                  ? position.accuracy
                  : null,
              speedMps: position.speed.isFinite ? position.speed : null,
            ),
          );
        }
      }

      _lastPosition = position;
      _currentLocation = currentPoint;
      _activeRouteIndex = _findNearestRouteIndex(currentPoint);

      final altitude = position.altitude;
      final altitudeAccuracy = position.altitudeAccuracy;
      if (altitude.isFinite &&
          altitude.abs() < 12000 &&
          altitudeAccuracy.isFinite &&
          altitudeAccuracy > 0 &&
          altitudeAccuracy <= 60) {
        _currentElevationMasl = altitude;
        _currentElevationAccuracyMeters = altitudeAccuracy;
        _startElevationMasl ??= altitude;
        if (altitude > _maxElevationMasl) {
          _maxElevationMasl = altitude;
        }
      }

      for (final checkpoint in _checkpoints) {
        if (_reachedCheckpoints.contains(checkpoint.name)) {
          continue;
        }
        final alongRouteMeters =
            checkpoint.routeProgressMeters -
            (_activeRouteIndex < _routeProgressMeters.length
                ? _routeProgressMeters[_activeRouteIndex]
                : 0);
        final directMeters = Geolocator.distanceBetween(
          currentPoint.latitude,
          currentPoint.longitude,
          checkpoint.location.latitude,
          checkpoint.location.longitude,
        );
        final threshold = checkpoint.isSummit ? 160.0 : 120.0;
        if (alongRouteMeters <= threshold || directMeters <= threshold) {
          _reachedCheckpoints.add(checkpoint.name);
        }
      }
    });

    if (shouldPersistPoint) {
      unawaited(_persistOfflineHikePoint(position));
    }

    final nearestRouteMeters = _distanceToNearestRouteMeters(currentPoint);
    if (!_usingGpxTrail && !_usingCommunityTrail && nearestRouteMeters > 150) {
      unawaited(_refreshRouteAndCheckpoints(currentPoint));
    }
  }

  Future<void> _persistOfflineHikePoint(Position position) async {
    final activity = _offlineActivity;
    if (activity == null) {
      return;
    }

    await _activityDatabase.insertPoint(
      OfflineActivityPoint(
        activityId: activity.id,
        latitude: position.latitude,
        longitude: position.longitude,
        timestamp: position.timestamp,
        altitudeMeters: position.altitude.isFinite ? position.altitude : null,
        accuracyMeters: position.accuracy.isFinite ? position.accuracy : null,
        speedMps: position.speed.isFinite && position.speed >= 0
            ? position.speed
            : null,
        distanceFromStartMeters: _trackedDistanceMeters,
      ),
    );
    await _saveOfflineHikeStats();
  }

  Future<void> _saveOfflineHikeStats({DateTime? endedAt}) async {
    final activity = _offlineActivity;
    if (activity == null) {
      return;
    }

    final duration = (endedAt ?? DateTime.now()).difference(_startedAt);
    final averageSpeedMps = duration.inSeconds <= 0
        ? 0.0
        : _trackedDistanceMeters / duration.inSeconds;
    await _activityDatabase.updateActivity(
      id: activity.id,
      endedAt: endedAt,
      durationSeconds: duration.inSeconds,
      movingDurationSeconds: duration.inSeconds,
      distanceMeters: _trackedDistanceMeters,
      elevationGainMeters: _elevationGainMasl.toDouble(),
      averageSpeedMps: averageSpeedMps,
    );
    final updated = await _activityDatabase.getActivity(activity.id);
    if (updated != null) {
      _offlineActivity = updated;
    }
  }

  String _sosSenderName() {
    final user = FirebaseAuth.instance.currentUser;
    final displayName = user?.displayName?.trim();
    if (displayName != null && displayName.isNotEmpty) {
      return displayName;
    }
    final email = user?.email?.trim();
    if (email != null && email.isNotEmpty) {
      return email;
    }
    return 'Hiker';
  }

  String _buildSosPayload(LatLng location) {
    return jsonEncode({
      'type': 'SOS',
      'sender': _sosSenderName(),
      'trail': widget.trail.name,
      'lat': double.parse(location.latitude.toStringAsFixed(6)),
      'lon': double.parse(location.longitude.toStringAsFixed(6)),
      'timestamp': DateTime.now().toUtc().toIso8601String(),
    });
  }

  Future<void> _showSosConfirmation() async {
    final location = _currentLocation;
    final messenger = ScaffoldMessenger.of(context);
    if (location == null) {
      messenger.showSnackBar(
        const SnackBar(content: Text('Waiting for GPS before sending SOS.')),
      );
      return;
    }

    await HapticFeedback.heavyImpact();
    if (!mounted) return;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Send SOS Alert?'),
        content: Text(
          'This will prepare an emergency SOS with your identity and GPS coordinates.\n\n'
          'Hiker: ${_sosSenderName()}\n'
          'Trail: ${widget.trail.name}\n'
          'Latitude: ${location.latitude.toStringAsFixed(6)}\n'
          'Longitude: ${location.longitude.toStringAsFixed(6)}\n\n'
          'Bluetooth/LoRa transmission will be connected in the next step.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancel'),
          ),
          FilledButton.icon(
            onPressed: () => Navigator.pop(dialogContext, true),
            icon: const Icon(Icons.sos_rounded),
            label: const Text('Send SOS'),
            style: FilledButton.styleFrom(
              backgroundColor: const Color(0xFFD84334),
              foregroundColor: Colors.white,
            ),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      await _prepareSosPayload(location);
    }
  }

  Future<void> _prepareSosPayload(LatLng location) async {
    final messenger = ScaffoldMessenger.of(context);
    setState(() => _sendingSos = true);
    await HapticFeedback.vibrate();

    final payload = _buildSosPayload(location);
    debugPrint('Prepared LoRa SOS payload: $payload');

    var sentToRoom = false;
    try {
      final roomService = HikeRoomService();
      final room = await roomService.getActiveRoom();
      if (room != null && room.status == HikeRoomStatus.active) {
        await roomService.sendSos(
          roomId: room.id,
          latitude: location.latitude,
          longitude: location.longitude,
        );
        sentToRoom = true;
      }
    } catch (error) {
      debugPrint('Unable to send SOS to hike room: $error');
    }

    if (!mounted) return;
    setState(() => _sendingSos = false);
    messenger.showSnackBar(
      SnackBar(
        content: Text(
          sentToRoom
              ? 'SOS sent to your Tour Guide through the hike room.'
              : 'No active internet room received the SOS. Heltec/LoRa is not connected yet.',
        ),
        backgroundColor: const Color(0xFFD84334),
      ),
    );
  }

  int _findNearestRouteIndex(LatLng point) {
    if (_plannedRoutePoints.isEmpty) {
      return 0;
    }
    var bestIndex = 0;
    var bestDistance = double.infinity;
    for (var i = 0; i < _plannedRoutePoints.length; i++) {
      final routePoint = _plannedRoutePoints[i];
      final distance = Geolocator.distanceBetween(
        point.latitude,
        point.longitude,
        routePoint.latitude,
        routePoint.longitude,
      );
      if (distance < bestDistance) {
        bestDistance = distance;
        bestIndex = i;
      }
    }
    return bestIndex;
  }

  double _distanceToNearestRouteMeters(LatLng point) {
    if (_plannedRoutePoints.isEmpty) {
      return 0;
    }
    final nearestIndex = _findNearestRouteIndex(point);
    final nearest = _plannedRoutePoints[nearestIndex];
    return Geolocator.distanceBetween(
      point.latitude,
      point.longitude,
      nearest.latitude,
      nearest.longitude,
    );
  }

  double? _remainingRouteDistanceKm() {
    if (_routeProgressMeters.isNotEmpty &&
        _activeRouteIndex >= 0 &&
        _activeRouteIndex < _routeProgressMeters.length) {
      final meters =
          _routeTotalMeters - _routeProgressMeters[_activeRouteIndex];
      if (meters <= 0) {
        return 0;
      }
      return meters / 1000;
    }
    final current = _currentLocation;
    final target = _hikeTarget;
    if (current == null || target == null) {
      return null;
    }
    final meters = Geolocator.distanceBetween(
      current.latitude,
      current.longitude,
      target.latitude,
      target.longitude,
    );
    return meters / 1000;
  }

  Duration get _elapsed => DateTime.now().difference(_startedAt);

  int get _elevationGainMasl {
    final start = _startElevationMasl;
    if (start == null) {
      return 0;
    }
    final gain = _maxElevationMasl - start;
    if (gain <= 0) {
      return 0;
    }
    return gain.round();
  }

  String _durationLabel(Duration duration) {
    final hours = duration.inHours;
    final minutes = duration.inMinutes.remainder(60);
    final seconds = duration.inSeconds.remainder(60);
    if (hours > 0) {
      return '${hours}h ${minutes.toString().padLeft(2, '0')}m';
    }
    return '${minutes}m ${seconds.toString().padLeft(2, '0')}s';
  }

  ll.LatLng _offlineLatLng(LatLng point) {
    return ll.LatLng(point.latitude, point.longitude);
  }

  List<ll.LatLng> _offlineLatLngList(List<LatLng> points) {
    return points.map(_offlineLatLng).toList(growable: false);
  }

  List<fm.Marker> _buildOfflineHikeMarkers() {
    final destination = _hikeTarget ?? widget.trail.location;
    final markers = <fm.Marker>[
      fm.Marker(
        point: _offlineLatLng(destination),
        width: 42,
        height: 42,
        child: const Icon(
          Icons.flag_circle_rounded,
          color: Color(0xFF7CF9A2),
          size: 38,
        ),
      ),
    ];
    final current = _currentLocation;
    if (current != null) {
      markers.add(
        fm.Marker(
          point: _offlineLatLng(current),
          width: 42,
          height: 42,
          child: const Icon(
            Icons.my_location_rounded,
            color: Color(0xFF2CA9FF),
            size: 34,
          ),
        ),
      );
    }
    return markers;
  }

  List<fm.Polyline> _buildOfflineHikePolylines() {
    final polylines = <fm.Polyline>[];
    if (_plannedRoutePoints.length >= 2) {
      polylines.add(
        fm.Polyline(
          points: _offlineLatLngList(_plannedRoutePoints),
          color: const Color(0xFF00E5FF),
          strokeWidth: 4,
        ),
      );
      if (_activeRouteIndex < _plannedRoutePoints.length - 1) {
        polylines.add(
          fm.Polyline(
            points: _offlineLatLngList(
              _plannedRoutePoints.sublist(_activeRouteIndex),
            ),
            color: const Color(0xFF7CF9A2),
            strokeWidth: 5,
          ),
        );
      }
    }

    if (_trackPoints.length >= 2) {
      polylines.add(
        fm.Polyline(
          points: _offlineLatLngList(_trackPoints),
          color: const Color(0xFF2CA9FF),
          strokeWidth: 5,
        ),
      );
    }
    return polylines;
  }

  Future<void> _endHike() async {
    if (_ending) {
      return;
    }
    setState(() => _ending = true);

    final endedAt = DateTime.now();
    final offlineActivity = _offlineActivity;
    if (offlineActivity != null) {
      await _saveOfflineHikeStats(endedAt: endedAt);
      await _activityDatabase.updateActivity(
        id: offlineActivity.id,
        status: ActivityStatus.finished,
        endedAt: endedAt,
      );
      unawaited(ActivitySyncService.shared.syncPendingActivities());
    }

    final result = _LiveHikeResult(
      distanceKm: _trackedDistanceMeters / 1000,
      duration: _elapsed,
      elevationGainMasl: _elevationGainMasl,
      maxElevationMasl:
          _maxElevationMasl.round() >
              (_resolvedPeakMasl ?? widget.trail.elevationMasl)
          ? _maxElevationMasl.round()
          : (_resolvedPeakMasl ?? widget.trail.elevationMasl),
      checkpointsReached: _reachedCheckpoints.length,
      totalCheckpoints: _checkpoints.length,
      reachedSummit: _reachedCheckpoints.contains('Peak'),
      trackPoints: List<_TrailTrackPoint>.from(_rawTrackPoints),
      routePoints: List<LatLng>.from(_plannedRoutePoints),
      peakLocation: _hikeTarget ?? widget.trail.location,
      startedAt: _startedAt,
      endedAt: endedAt,
    );
    if (!mounted) {
      return;
    }
    Navigator.of(context).pop(result);
  }

  Widget _metricCard(String label, String value) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.white.withValues(alpha: 0.12)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              label,
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.7),
                fontSize: 11,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              value,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 16,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final peakMasl = _resolvedPeakMasl ?? widget.trail.elevationMasl;
    final cameraTarget = _currentLocation ?? widget.trail.location;
    final remainingDistanceKm = _remainingRouteDistanceKm();
    final currentElevationText = _currentElevationAccuracyMeters == null
        ? '${_currentElevationMasl.round()} MASL'
        : '${_currentElevationMasl.round()} MASL (+/-${_currentElevationAccuracyMeters!.round()}m)';
    final trackingStatusText = _hasNetworkConnection
        ? 'GPS Active - map online'
        : 'Offline GPS Active - tracking locally';
    final trackingStatusColor = _hasNetworkConnection
        ? const Color(0xFF7CCBFF)
        : const Color(0xFF7CF9A2);

    return Scaffold(
      backgroundColor: const Color(0xFF04140E),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
          child: Column(
            children: [
              Row(
                children: [
                  IconButton(
                    onPressed: () => Navigator.of(context).pop(),
                    icon: const Icon(Icons.arrow_back_rounded),
                    color: Colors.white,
                  ),
                  const SizedBox(width: 4),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Hiking Mode',
                          style: TextStyle(
                            color: Color(0xFF7CF9A2),
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                            letterSpacing: 0.8,
                          ),
                        ),
                        Text(
                          widget.trail.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 18,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        Text(
                          _usingCommunityTrail
                              ? 'Trail source: Community (${widget.communityTrail?.status ?? 'unknown'})'
                              : _usingGpxTrail
                              ? () {
                                  final label = widget.selectedRouteLabel
                                      ?.trim();
                                  final source =
                                      (label != null && label.isNotEmpty)
                                      ? label
                                      : (_gpxTrailAssetPath?.split('/').last ??
                                            'mapped');
                                  if (_trailJoinDistanceMeters > 60) {
                                    return 'Trail source: GPX ($source) | Connected from your location';
                                  }
                                  return 'Trail source: GPX ($source)';
                                }()
                              : _usingResolvedPeak
                              ? 'Target: mapped mountain peak'
                              : 'Target: selected place (peak data unavailable)',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: Colors.white.withValues(alpha: 0.7),
                            fontSize: 11,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  _metricCard(
                    'To Mountain',
                    remainingDistanceKm == null
                        ? '--'
                        : '${remainingDistanceKm.toStringAsFixed(2)} km',
                  ),
                  const SizedBox(width: 8),
                  _metricCard(
                    'Distance Hiked',
                    '${(_trackedDistanceMeters / 1000).toStringAsFixed(2)} km',
                  ),
                  const SizedBox(width: 8),
                  _metricCard('Elapsed', _durationLabel(_elapsed)),
                ],
              ),
              const SizedBox(height: 10),
              Expanded(
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(16),
                  child: Stack(
                    children: [
                      OfflineMapWidget(
                        key: ValueKey(
                          '${cameraTarget.latitude},${cameraTarget.longitude},${_trackPoints.length},$_hasNetworkConnection',
                        ),
                        initialLatitude: cameraTarget.latitude,
                        initialLongitude: cameraTarget.longitude,
                        initialZoom: 15,
                        markers: _buildOfflineHikeMarkers(),
                        polylines: _buildOfflineHikePolylines(),
                        showScaleLayer: false,
                        allowNetworkFallback: _hasNetworkConnection,
                      ),
                      Positioned(
                        top: 10,
                        left: 10,
                        right: 10,
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 8,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.black.withValues(alpha: 0.62),
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(
                              color: trackingStatusColor.withValues(
                                alpha: 0.55,
                              ),
                            ),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                Icons.gps_fixed_rounded,
                                color: trackingStatusColor,
                                size: 18,
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  trackingStatusText,
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontWeight: FontWeight.w700,
                                    fontSize: 12,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                      if (_initializing)
                        Container(
                          color: Colors.black45,
                          alignment: Alignment.center,
                          child: const CircularProgressIndicator(
                            color: Color(0xFF7CF9A2),
                          ),
                        ),
                      if (_errorMessage != null)
                        Positioned(
                          top: 58,
                          left: 10,
                          right: 10,
                          child: Container(
                            padding: const EdgeInsets.all(10),
                            decoration: BoxDecoration(
                              color: const Color(
                                0xFF3A1616,
                              ).withValues(alpha: 0.9),
                              borderRadius: BorderRadius.circular(10),
                              border: Border.all(
                                color: const Color(
                                  0xFFFF8A8A,
                                ).withValues(alpha: 0.7),
                              ),
                            ),
                            child: Text(
                              _errorMessage!,
                              style: const TextStyle(color: Colors.white),
                            ),
                          ),
                        ),
                      Positioned(
                        left: 10,
                        right: 10,
                        bottom: 10,
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 8,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.black.withValues(alpha: 0.55),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Row(
                            children: [
                              Expanded(
                                child: Text(
                                  'Current Elev: $currentElevationText',
                                  style: const TextStyle(color: Colors.white),
                                ),
                              ),
                              Expanded(
                                child: Text(
                                  'Peak: $peakMasl MASL',
                                  textAlign: TextAlign.right,
                                  style: const TextStyle(color: Colors.white),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  Expanded(
                    child: FilledButton.icon(
                      onPressed: (_sendingSos || _ending)
                          ? null
                          : _showSosConfirmation,
                      icon: const Icon(Icons.warning_amber_rounded),
                      label: Text(
                        _sendingSos ? 'Sending...' : 'SOS',
                        style: const TextStyle(
                          fontWeight: FontWeight.w900,
                          letterSpacing: 0.6,
                        ),
                      ),
                      style: FilledButton.styleFrom(
                        backgroundColor: const Color(0xFFD84334),
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: ElevatedButton.icon(
                      onPressed: _ending ? null : _endHike,
                      icon: const Icon(Icons.stop_circle_outlined),
                      label: Text(
                        _ending ? 'Saving...' : 'End Hike',
                        style: const TextStyle(
                          fontWeight: FontWeight.w800,
                          letterSpacing: 0.4,
                        ),
                      ),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF26352D),
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class ForgotPasswordScreen extends StatefulWidget {
  const ForgotPasswordScreen({
    super.key,
    required this.authDatabaseService,
    this.initialEmail = '',
  });

  final AuthDatabaseService authDatabaseService;
  final String initialEmail;

  @override
  State<ForgotPasswordScreen> createState() => _ForgotPasswordScreenState();
}

class _ForgotPasswordScreenState extends State<ForgotPasswordScreen> {
  late final TextEditingController _emailController;
  bool _isSubmitting = false;

  @override
  void initState() {
    super.initState();
    _emailController = TextEditingController(text: widget.initialEmail);
  }

  @override
  void dispose() {
    _emailController.dispose();
    super.dispose();
  }

  Future<void> _sendResetEmail() async {
    final email = _emailController.text.trim();
    if (email.isEmpty) {
      _showSnackBar('Enter your registered email.');
      return;
    }
    if (!email.contains('@')) {
      _showSnackBar('Enter a valid email address.');
      return;
    }

    setState(() => _isSubmitting = true);
    try {
      await widget.authDatabaseService.sendPasswordResetEmail(email);
      if (!mounted) {
        return;
      }
      _showSnackBar(
        'Password reset email sent. Check your inbox and spam folder.',
      );
      Navigator.of(context).pop();
    } on FirebaseAuthException catch (error) {
      if (!mounted) {
        return;
      }
      final message = switch (error.code) {
        'invalid-email' => 'Invalid email address.',
        'too-many-requests' => 'Too many attempts. Try again in a few minutes.',
        _ => 'If this email is registered, a password reset link will be sent.',
      };
      _showSnackBar(message);
    } catch (error) {
      _showSnackBar('Unable to send reset email: $error');
    } finally {
      if (mounted) {
        setState(() => _isSubmitting = false);
      }
    }
  }

  void _showSnackBar(String message) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Color(0xFF04140E), Color(0xFF072519), Color(0xFF03110C)],
          ),
        ),
        child: SafeArea(
          child: LayoutBuilder(
            builder: (context, constraints) {
              final keyboardInset = MediaQuery.of(context).viewInsets.bottom;

              return SingleChildScrollView(
                padding: EdgeInsets.fromLTRB(24, 16, 24, 20 + keyboardInset),
                child: ConstrainedBox(
                  constraints: BoxConstraints(minHeight: constraints.maxHeight),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      IconButton(
                        onPressed: () => Navigator.of(context).pop(),
                        icon: const Icon(Icons.arrow_back_rounded),
                        color: Colors.white,
                      ),
                      const SizedBox(height: 12),
                      Text(
                        'Forgot Password',
                        style: Theme.of(context).textTheme.headlineMedium
                            ?.copyWith(
                              color: Colors.white,
                              fontWeight: FontWeight.w800,
                            ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Enter your registered email. We will send a secure reset link.',
                        style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                          color: const Color(0xFF82CFA5),
                          height: 1.4,
                        ),
                      ),
                      const SizedBox(height: 24),
                      _AuthInput(
                        hint: 'Email Address',
                        icon: Icons.email_outlined,
                        controller: _emailController,
                        keyboardType: TextInputType.emailAddress,
                        textInputAction: TextInputAction.done,
                      ),
                      const SizedBox(height: 20),
                      SizedBox(
                        width: double.infinity,
                        child: ElevatedButton(
                          onPressed: _isSubmitting ? null : _sendResetEmail,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFF45D972),
                            foregroundColor: Colors.black,
                            padding: const EdgeInsets.symmetric(vertical: 18),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(18),
                            ),
                          ),
                          child: _isSubmitting
                              ? const SizedBox(
                                  width: 24,
                                  height: 24,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2.4,
                                    color: Colors.black,
                                  ),
                                )
                              : const Text(
                                  'SEND RESET LINK',
                                  style: TextStyle(
                                    fontWeight: FontWeight.w800,
                                    letterSpacing: 1.2,
                                  ),
                                ),
                        ),
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
      ),
    );
  }
}

class SignUpScreen extends StatefulWidget {
  const SignUpScreen({super.key, required this.firebaseReady});

  final bool firebaseReady;

  @override
  State<SignUpScreen> createState() => _SignUpScreenState();
}

class _SignUpScreenState extends State<SignUpScreen> {
  final _authDatabaseService = AuthDatabaseService();
  final _fullNameController = TextEditingController();
  final _usernameController = TextEditingController();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();

  bool _obscurePassword = true;
  bool _obscureConfirmPassword = true;
  bool _isSubmitting = false;
  String _selectedAccountType = 'hiker';

  @override
  void dispose() {
    _fullNameController.dispose();
    _usernameController.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    _confirmPasswordController.dispose();
    super.dispose();
  }

  Future<void> _handleSaveAndVerify() async {
    final fullName = _fullNameController.text.trim();
    final username = _usernameController.text.trim();
    final email = _emailController.text.trim();
    final password = _passwordController.text;
    final confirmPassword = _confirmPasswordController.text;

    if (fullName.isEmpty ||
        username.isEmpty ||
        email.isEmpty ||
        password.isEmpty ||
        confirmPassword.isEmpty) {
      _showSnackBar('Please complete all fields.');
      return;
    }

    final emailRegex = RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$');
    if (!emailRegex.hasMatch(email)) {
      _showSnackBar('Please enter a valid email address.');
      return;
    }

    if (password.length < 8) {
      _showSnackBar('Password must be at least 8 characters.');
      return;
    }

    if (password != confirmPassword) {
      _showSnackBar('Password and Confirm Password do not match.');
      return;
    }

    if (!widget.firebaseReady) {
      _showSnackBar(
        'Firebase is not configured yet. Run FlutterFire setup first.',
      );
      return;
    }

    setState(() => _isSubmitting = true);

    try {
      await _authDatabaseService.signUpUser(
        fullName: fullName,
        username: username,
        email: email,
        password: password,
        accountType: _selectedAccountType,
      );

      if (!mounted) {
        return;
      }
      Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (context) => EmailVerificationScreen(
            email: email,
            authDatabaseService: _authDatabaseService,
          ),
        ),
      );
    } on FirebaseAuthException catch (error) {
      final message = switch (error.code) {
        'email-already-in-use' => 'This email is already registered.',
        'invalid-email' => 'Invalid email address.',
        'weak-password' => 'Password is too weak.',
        _ => error.message ?? 'Sign up failed. Please try again.',
      };
      _showSnackBar(message);
    } catch (error) {
      _showSnackBar('Sign up failed: $error');
    } finally {
      if (mounted) {
        setState(() => _isSubmitting = false);
      }
    }
  }

  void _showSnackBar(String message) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  Widget _accountTypeSelector() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: Colors.white.withValues(alpha: 0.12)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Choose account type',
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.82),
              fontSize: 13,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: _accountTypeOption(
                  value: 'hiker',
                  title: 'Hiker',
                  icon: Icons.hiking_rounded,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _accountTypeOption(
                  value: 'tour_guide',
                  title: 'Tour Guide',
                  icon: Icons.emoji_people_rounded,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _accountTypeOption({
    required String value,
    required String title,
    required IconData icon,
  }) {
    final isSelected = _selectedAccountType == value;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: _isSubmitting
            ? null
            : () {
                setState(() {
                  _selectedAccountType = value;
                });
              },
        borderRadius: BorderRadius.circular(14),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 160),
          height: 64,
          padding: const EdgeInsets.symmetric(horizontal: 10),
          decoration: BoxDecoration(
            color: isSelected
                ? const Color(0xFF53D97A).withValues(alpha: 0.18)
                : Colors.white.withValues(alpha: 0.04),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: isSelected
                  ? const Color(0xFF53D97A)
                  : Colors.white.withValues(alpha: 0.1),
            ),
          ),
          child: Row(
            children: [
              Icon(
                icon,
                color: isSelected ? const Color(0xFF53D97A) : Colors.white70,
                size: 22,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: isSelected ? const Color(0xFF7CF9A2) : Colors.white,
                    fontSize: 13,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Color(0xFF04140E), Color(0xFF072519), Color(0xFF03110C)],
          ),
        ),
        child: SafeArea(
          child: LayoutBuilder(
            builder: (context, constraints) {
              final keyboardInset = MediaQuery.of(context).viewInsets.bottom;

              return SingleChildScrollView(
                padding: EdgeInsets.fromLTRB(24, 16, 24, 20 + keyboardInset),
                child: ConstrainedBox(
                  constraints: BoxConstraints(minHeight: constraints.maxHeight),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      IconButton(
                        onPressed: () => Navigator.of(context).pop(),
                        icon: const Icon(Icons.arrow_back_rounded),
                        color: Colors.white,
                      ),
                      const SizedBox(height: 8),
                      Center(
                        child: Container(
                          width: 88,
                          height: 88,
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(24),
                            gradient: const LinearGradient(
                              colors: [Color(0xFF38D86E), Color(0xFF2CB95F)],
                            ),
                          ),
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(18),
                            child: Image.asset(
                              'assets/images/animal.png',
                              fit: BoxFit.cover,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 18),
                      Center(
                        child: Text(
                          'Create Agakbay Account',
                          style: Theme.of(context).textTheme.headlineSmall
                              ?.copyWith(
                                fontWeight: FontWeight.w800,
                                color: Colors.white,
                              ),
                        ),
                      ),
                      const SizedBox(height: 8),
                      Center(
                        child: Text(
                          'Fill in your details to get started.',
                          style: Theme.of(context).textTheme.bodyLarge
                              ?.copyWith(color: const Color(0xFF82CFA5)),
                        ),
                      ),
                      const SizedBox(height: 28),
                      _accountTypeSelector(),
                      const SizedBox(height: 14),
                      _AuthInput(
                        hint: 'Full Name',
                        icon: Icons.person_outline_rounded,
                        controller: _fullNameController,
                        textInputAction: TextInputAction.next,
                      ),
                      const SizedBox(height: 14),
                      _AuthInput(
                        hint: 'Username',
                        icon: Icons.alternate_email_rounded,
                        controller: _usernameController,
                        textInputAction: TextInputAction.next,
                      ),
                      const SizedBox(height: 14),
                      _AuthInput(
                        hint: 'Email Address',
                        icon: Icons.email_outlined,
                        controller: _emailController,
                        keyboardType: TextInputType.emailAddress,
                        textInputAction: TextInputAction.next,
                      ),
                      const SizedBox(height: 14),
                      _AuthInput(
                        hint: 'Password',
                        icon: Icons.lock_outline_rounded,
                        controller: _passwordController,
                        obscureText: _obscurePassword,
                        textInputAction: TextInputAction.next,
                        suffix: IconButton(
                          onPressed: () {
                            setState(
                              () => _obscurePassword = !_obscurePassword,
                            );
                          },
                          icon: Icon(
                            _obscurePassword
                                ? Icons.visibility_outlined
                                : Icons.visibility_off_outlined,
                            color: Colors.white.withValues(alpha: 0.66),
                          ),
                        ),
                      ),
                      const SizedBox(height: 14),
                      _AuthInput(
                        hint: 'Confirm Password',
                        icon: Icons.lock_reset_rounded,
                        controller: _confirmPasswordController,
                        obscureText: _obscureConfirmPassword,
                        textInputAction: TextInputAction.done,
                        suffix: IconButton(
                          onPressed: () {
                            setState(
                              () => _obscureConfirmPassword =
                                  !_obscureConfirmPassword,
                            );
                          },
                          icon: Icon(
                            _obscureConfirmPassword
                                ? Icons.visibility_outlined
                                : Icons.visibility_off_outlined,
                            color: Colors.white.withValues(alpha: 0.66),
                          ),
                        ),
                      ),
                      const SizedBox(height: 22),
                      SizedBox(
                        width: double.infinity,
                        child: ElevatedButton(
                          onPressed: _isSubmitting
                              ? null
                              : _handleSaveAndVerify,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFF45D972),
                            foregroundColor: Colors.black,
                            padding: const EdgeInsets.symmetric(vertical: 18),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(18),
                            ),
                          ),
                          child: _isSubmitting
                              ? const SizedBox(
                                  width: 24,
                                  height: 24,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2.4,
                                    color: Colors.black,
                                  ),
                                )
                              : const Text(
                                  'SAVE & VERIFY EMAIL',
                                  style: TextStyle(
                                    fontWeight: FontWeight.w800,
                                    letterSpacing: 1.2,
                                  ),
                                ),
                        ),
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
      ),
    );
  }
}

class EmailVerificationScreen extends StatefulWidget {
  final String email;
  final AuthDatabaseService authDatabaseService;

  const EmailVerificationScreen({
    super.key,
    required this.email,
    required this.authDatabaseService,
  });

  @override
  State<EmailVerificationScreen> createState() =>
      _EmailVerificationScreenState();
}

class _EmailVerificationScreenState extends State<EmailVerificationScreen> {
  Timer? _timer;
  int _secondsLeft = 45;
  bool _checkingVerification = false;

  @override
  void initState() {
    super.initState();
    _startResendTimer();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Verification email sent to ${widget.email}. Open your inbox and click the verify link.',
          ),
        ),
      );
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  void _startResendTimer() {
    _timer?.cancel();
    setState(() => _secondsLeft = 45);
    _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (_secondsLeft <= 1) {
        timer.cancel();
        setState(() => _secondsLeft = 0);
      } else {
        setState(() => _secondsLeft -= 1);
      }
    });
  }

  Future<void> _checkVerification() async {
    if (_checkingVerification) {
      return;
    }
    setState(() => _checkingVerification = true);
    try {
      final verified = await widget.authDatabaseService
          .reloadAndCheckEmailVerified();
      if (!mounted) {
        return;
      }
      if (verified) {
        _showSnackBar('Email verified successfully.');
        Navigator.of(context).popUntil((route) => route.isFirst);
      } else {
        _showSnackBar('Not verified yet. Check your email and tap the link.');
      }
    } catch (error) {
      _showSnackBar('Verification check failed: $error');
    } finally {
      if (mounted) {
        setState(() => _checkingVerification = false);
      }
    }
  }

  Future<void> _resendVerificationEmail() async {
    if (_secondsLeft > 0) {
      return;
    }
    try {
      await widget.authDatabaseService.resendVerificationEmail();
      _showSnackBar('Verification email resent.');
      _startResendTimer();
    } catch (error) {
      _showSnackBar('Unable to resend verification email: $error');
    }
  }

  void _showSnackBar(String message) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Color(0xFF04140E), Color(0xFF072519), Color(0xFF03110C)],
          ),
        ),
        child: SafeArea(
          child: LayoutBuilder(
            builder: (context, constraints) {
              final keyboardInset = MediaQuery.of(context).viewInsets.bottom;
              return SingleChildScrollView(
                padding: EdgeInsets.fromLTRB(24, 20, 24, 20 + keyboardInset),
                child: ConstrainedBox(
                  constraints: BoxConstraints(minHeight: constraints.maxHeight),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      IconButton(
                        onPressed: () => Navigator.of(context).pop(),
                        icon: const Icon(Icons.arrow_back_rounded),
                        color: Colors.white,
                      ),
                      const SizedBox(height: 10),
                      Text(
                        'Verify Your Email',
                        style: Theme.of(context).textTheme.headlineMedium
                            ?.copyWith(
                              color: Colors.white,
                              fontWeight: FontWeight.w800,
                            ),
                      ),
                      const SizedBox(height: 10),
                      Text(
                        'Click the verification link sent to:',
                        style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                          color: const Color(0xFF82CFA5),
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        widget.email,
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w700,
                          fontSize: 17,
                        ),
                      ),
                      const SizedBox(height: 30),
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.05),
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(
                            color: Colors.white.withValues(alpha: 0.15),
                          ),
                        ),
                        child: Text(
                          'After tapping the link in your email, return here and press "I HAVE VERIFIED".',
                          style: TextStyle(
                            color: Colors.white.withValues(alpha: 0.85),
                            height: 1.4,
                          ),
                        ),
                      ),
                      const SizedBox(height: 14),
                      Row(
                        children: [
                          Text(
                            _secondsLeft > 0
                                ? 'Resend email in $_secondsLeft s.'
                                : 'Didn\'t receive the code?',
                            style: TextStyle(
                              color: Colors.white.withValues(alpha: 0.66),
                              fontSize: 15,
                            ),
                          ),
                          const SizedBox(width: 8),
                          TextButton(
                            onPressed: _secondsLeft > 0
                                ? null
                                : _resendVerificationEmail,
                            child: const Text('Resend'),
                          ),
                        ],
                      ),
                      const SizedBox(height: 20),
                      SizedBox(
                        width: double.infinity,
                        child: ElevatedButton(
                          onPressed: _checkingVerification
                              ? null
                              : _checkVerification,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFF45D972),
                            foregroundColor: Colors.black,
                            padding: const EdgeInsets.symmetric(vertical: 18),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(18),
                            ),
                          ),
                          child: _checkingVerification
                              ? const SizedBox(
                                  width: 24,
                                  height: 24,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2.4,
                                    color: Colors.black,
                                  ),
                                )
                              : const Text(
                                  'I HAVE VERIFIED',
                                  style: TextStyle(
                                    fontWeight: FontWeight.w800,
                                    letterSpacing: 1.4,
                                  ),
                                ),
                        ),
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
      ),
    );
  }
}

class _AuthInput extends StatelessWidget {
  final String hint;
  final IconData icon;
  final Widget? suffix;
  final bool obscureText;
  final TextEditingController? controller;
  final TextInputType? keyboardType;
  final TextInputAction? textInputAction;

  const _AuthInput({
    required this.hint,
    required this.icon,
    this.suffix,
    this.obscureText = false,
    this.controller,
    this.keyboardType,
    this.textInputAction,
  });

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      obscureText: obscureText,
      keyboardType: keyboardType,
      textInputAction: textInputAction,
      style: const TextStyle(color: Colors.white, fontSize: 21),
      cursorColor: const Color(0xFF45D972),
      decoration: InputDecoration(
        hintText: hint,
        hintStyle: TextStyle(color: Colors.white.withValues(alpha: 0.58)),
        prefixIcon: Icon(icon, color: const Color(0xFF4FD972), size: 25),
        suffixIcon: suffix,
        filled: true,
        fillColor: Colors.white.withValues(alpha: 0.04),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(18),
          borderSide: BorderSide(color: Colors.white.withValues(alpha: 0.24)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(18),
          borderSide: const BorderSide(color: Color(0xFF4FD972)),
        ),
      ),
    );
  }
}

class _InfoChip extends StatelessWidget {
  final IconData icon;
  final String label;

  const _InfoChip({required this.icon, required this.label});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 142,
      padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 12),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        children: [
          Icon(icon, color: const Color(0xFF86FFBC), size: 18),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              label,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
