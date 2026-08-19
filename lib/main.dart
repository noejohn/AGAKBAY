import 'dart:async';
import 'dart:convert';
import 'dart:io' show File, Platform;
import 'dart:math' as math;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:firebase_app_check/firebase_app_check.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter_map/flutter_map.dart' as fm;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:geolocator/geolocator.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:http/http.dart' as http;
import 'package:image_picker/image_picker.dart';
import 'package:latlong2/latlong.dart' as ll;
import 'package:tunga/firebase_options.dart';
import 'package:tunga/screens/agak_companion_screen.dart';
import 'package:tunga/screens/kyrielle_companion_chat_screen.dart';
import 'package:tunga/screens/agak_emotion_showcase_screen.dart';
import 'package:tunga/screens/agak_scheduled_hikes_screen.dart';
import 'package:tunga/screens/hike_room_screen.dart';
import 'package:tunga/screens/onboarding/onboarding_flow_screen.dart';
import 'package:tunga/services/activity_sync_service.dart';
import 'package:tunga/services/auth_database_service.dart';
import 'package:tunga/services/hike_room_service.dart';
import 'package:tunga/services/onboarding_service.dart';
import 'package:tunga/models/agak_mountain.dart';
import 'package:tunga/models/agak_recommendation.dart';
import 'package:tunga/services/agak_behavior_database.dart';
import 'package:tunga/services/agak_controller.dart';
import 'package:tunga/services/agak_packing_list.dart';
import 'package:tunga/services/weather_service.dart' show WeatherService;
import 'package:tunga/services/agak_tip_bus.dart';
import 'package:tunga/services/agak_emotion_selector.dart';
import 'package:tunga/services/gemini_client.dart';
import 'package:tunga/services/offline_activity_database.dart';
import 'package:tunga/widgets/agak_floating_companion.dart';
import 'package:tunga/widgets/agak_theme.dart';
import 'package:tunga/widgets/agak_tip_popup.dart';
import 'package:tunga/widgets/offline_map_widget.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const TunGaApp());
}

class TunGaApp extends StatelessWidget {
  const TunGaApp({super.key});

  @override
  Widget build(BuildContext context) {
    final baseTheme = ThemeData(
      colorScheme: ColorScheme.fromSeed(
        seedColor: const Color(0xFF97070A),
        brightness: Brightness.light,
      ),
      scaffoldBackgroundColor: const Color(0xFFFDF8DC),
      useMaterial3: true,
    );
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Agakbay',
      theme: baseTheme.copyWith(
        textTheme: GoogleFonts.manropeTextTheme(baseTheme.textTheme),
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
      // Registering the Android app for Play Integrity (Firebase Console
      // → App Check) is a manual step outside this code — until that's
      // done, activation here is harmless (tokens just won't attest
      // successfully yet). No Cloud Function enforces App Check yet either
      // (see functions/index.js); that's a deliberate later step, since
      // turning on enforcement before real traffic reliably produces valid
      // tokens would lock out genuine users.
      try {
        await FirebaseAppCheck.instance.activate(
          androidProvider: AndroidProvider.playIntegrity,
          appleProvider: AppleProvider.deviceCheck,
        );
      } catch (_) {
        // Non-fatal — App Check is defense-in-depth, not required for the
        // app to function.
      }
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
        decoration: BoxDecoration(gradient: AgakColors.screenBackground),
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
              decoration: BoxDecoration(gradient: AgakColors.screenBackground),
              child: const Center(child: BounceLoadingScreen()),
            ),
          );
        }

        if (snapshot.hasData && snapshot.data != null) {
          return FutureBuilder<bool>(
            future: OnboardingService().hasCompletedOnboarding(
              snapshot.data!.uid,
            ),
            builder: (context, onboardingSnapshot) {
              if (onboardingSnapshot.connectionState ==
                  ConnectionState.waiting) {
                return Scaffold(
                  body: Container(
                    decoration: BoxDecoration(
                      gradient: AgakColors.screenBackground,
                    ),
                    child: const Center(child: BounceLoadingScreen()),
                  ),
                );
              }
              if (onboardingSnapshot.data == false) {
                return const OnboardingFlowScreen();
              }
              return const DashboardScreen();
            },
          );
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
              color: AgakColors.ink.withValues(alpha: 0.2),
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
                      color: AgakColors.ink,
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
            color: AgakColors.ink.withValues(alpha: 0.7),
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
        decoration: BoxDecoration(gradient: AgakColors.screenBackground),
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
                      color: AgakColors.ink.withValues(alpha: 0.2),
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
                    color: AgakColors.ink,
                  ),
                ),
                const SizedBox(height: 10),
                Text(
                  'EXPLORE PEAKS. TRACK ADVENTURES.',
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: AgakColors.ink.withValues(alpha: 0.7),
                    letterSpacing: 1.7,
                    height: 1.4,
                  ),
                ),
                const SizedBox(height: 34),
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.55),
                    borderRadius: BorderRadius.circular(24),
                    border: Border.all(
                      color: AgakColors.ink.withValues(alpha: 0.14),
                    ),
                  ),
                  child: const Column(
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
                      SizedBox(height: 12),
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
                      backgroundColor: AgakColors.maroon,
                      foregroundColor: AgakColors.cream,
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
      final credential = await _authDatabaseService.signInUser(
        email: email,
        password: password,
      );
      if (!mounted) {
        return;
      }
      final onboarded = await OnboardingService().hasCompletedOnboarding(
        credential.user!.uid,
      );
      if (!mounted) {
        return;
      }
      Navigator.of(context).pushReplacement(
        MaterialPageRoute<void>(
          builder: (context) => onboarded
              ? const DashboardScreen()
              : const OnboardingFlowScreen(),
        ),
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

  Future<void> _handleGoogleSignIn() async {
    if (!widget.firebaseReady) {
      _showSnackBar('Firebase is not configured yet.');
      return;
    }
    setState(() => _isSubmitting = true);
    try {
      final credential = await _authDatabaseService.signInWithGoogle();
      if (!mounted) {
        return;
      }
      final onboarded = await OnboardingService().hasCompletedOnboarding(
        credential.user!.uid,
      );
      if (!mounted) {
        return;
      }
      Navigator.of(context).pushReplacement(
        MaterialPageRoute<void>(
          builder: (context) => onboarded
              ? const DashboardScreen()
              : const OnboardingFlowScreen(),
        ),
      );
    } on FirebaseAuthException catch (error) {
      if (error.code == 'sign-in-canceled') {
        return;
      }
      _showSnackBar(error.message ?? 'Google sign-in failed. Please try again.');
    } catch (error) {
      _showSnackBar('Google sign-in failed: $error');
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
        decoration: BoxDecoration(gradient: AgakColors.screenBackground),
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
                        AgakColors.gold.withValues(alpha: 0.55),
                        AgakColors.gold.withValues(alpha: 0.0),
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
                                      AgakColors.olive,
                                      AgakColors.maroon,
                                    ],
                                  ),
                                  boxShadow: [
                                    BoxShadow(
                                      color: AgakColors.maroon.withValues(
                                        alpha: 0.35,
                                      ),
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
                                      color: AgakColors.ink,
                                      fontWeight: FontWeight.w800,
                                    ),
                              ),
                              const SizedBox(height: 8),
                              Text(
                                'EXPLORE PEAKS. TRACK ADVENTURES.',
                                textAlign: TextAlign.center,
                                style: Theme.of(context).textTheme.bodyMedium
                                    ?.copyWith(
                                      color: AgakColors.ink.withValues(
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
                                      color: AgakColors.ink,
                                      fontWeight: FontWeight.w700,
                                    ),
                              ),
                              const SizedBox(height: 10),
                              Text(
                                'Login to continue your adventure.',
                                textAlign: TextAlign.center,
                                style: Theme.of(context).textTheme.titleMedium
                                    ?.copyWith(color: AgakColors.maroon),
                              ),
                              if (!widget.firebaseReady) ...[
                                const SizedBox(height: 14),
                                Container(
                                  width: double.infinity,
                                  padding: const EdgeInsets.all(12),
                                  decoration: BoxDecoration(
                                    color: AgakColors.maroon.withValues(
                                      alpha: 0.1,
                                    ),
                                    borderRadius: BorderRadius.circular(12),
                                    border: Border.all(
                                      color: AgakColors.maroon.withValues(
                                        alpha: 0.5,
                                      ),
                                    ),
                                  ),
                                  child: const Text(
                                    'Firebase is not configured yet. Database sign up will fail until setup is completed.',
                                    style: TextStyle(
                                      color: AgakColors.maroon,
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
                                    color: AgakColors.ink.withValues(
                                      alpha: 0.66,
                                    ),
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
                                      color: AgakColors.olive,
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
                                    backgroundColor: AgakColors.maroon,
                                    foregroundColor: AgakColors.cream,
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
                                            color: AgakColors.cream,
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
                              const SizedBox(height: 16),
                              Row(
                                children: [
                                  Expanded(
                                    child: Divider(
                                      color: AgakColors.ink.withValues(
                                        alpha: 0.18,
                                      ),
                                    ),
                                  ),
                                  Padding(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 10,
                                    ),
                                    child: Text(
                                      'OR',
                                      style: TextStyle(
                                        color: AgakColors.ink.withValues(
                                          alpha: 0.5,
                                        ),
                                        fontSize: 13,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                  ),
                                  Expanded(
                                    child: Divider(
                                      color: AgakColors.ink.withValues(
                                        alpha: 0.18,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 16),
                              SizedBox(
                                width: double.infinity,
                                child: OutlinedButton.icon(
                                  onPressed: _isSubmitting
                                      ? null
                                      : _handleGoogleSignIn,
                                  icon: const Icon(
                                    Icons.g_mobiledata_rounded,
                                    size: 26,
                                  ),
                                  label: const Text('Sign in with Google'),
                                  style: OutlinedButton.styleFrom(
                                    foregroundColor: AgakColors.ink,
                                    padding: const EdgeInsets.symmetric(
                                      vertical: 16,
                                    ),
                                    side: BorderSide(
                                      color: AgakColors.ink.withValues(
                                        alpha: 0.3,
                                      ),
                                    ),
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(18),
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
                                      color: AgakColors.ink.withValues(
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
                                        color: AgakColors.olive,
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

class _TrailRecordingDetails {
  const _TrailRecordingDetails({
    required this.trailName,
    required this.stationNames,
    required this.recordedAt,
  });

  final String trailName;
  final List<String> stationNames;
  final DateTime recordedAt;
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

class _MountainOrganizer {
  const _MountainOrganizer({
    required this.id,
    required this.name,
    required this.contact,
    required this.description,
    required this.source,
    required this.verified,
    this.isExternalSuggestion = false,
  });

  final String id;
  final String name;
  final String contact;
  final String description;
  final String source;
  final bool verified;
  final bool isExternalSuggestion;
}

class _AssistantMessage {
  const _AssistantMessage({required this.role, required this.text});

  final String role;
  final String text;
}

class _HikeAssistantScreen extends StatefulWidget {
  const _HikeAssistantScreen({
    // ignore: unused_element_parameter
    super.key,
    this.initialTrail,
    required this.searchMountainInMindanao,
    required this.fetchMountainOrganizers,
  });

  final _NearbyTrail? initialTrail;
  final Future<_NearbyTrail?> Function(String query) searchMountainInMindanao;
  final Future<List<_MountainOrganizer>> Function(_NearbyTrail trail)
  fetchMountainOrganizers;

  @override
  State<_HikeAssistantScreen> createState() => _HikeAssistantScreenState();
}

class _HikeAssistantScreenState extends State<_HikeAssistantScreen> {
  final TextEditingController _questionController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  final List<_AssistantMessage> _messages = [];
  bool _isSearching = false;
  String _aiApiKey = '';

  @override
  void initState() {
    super.initState();
    _loadAiApiKey();
    _addAssistantMessage(
      'Hi! Ask me anything about a hike — elevation, difficulty, weather, '
      'gear, or organizers for a specific mountain.',
    );
  }

  @override
  void dispose() {
    _questionController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  void _addAssistantMessage(String text) {
    _messages.add(const _AssistantMessage(role: 'assistant', text: ''));
    final lastIndex = _messages.length - 1;
    _messages[lastIndex] = _AssistantMessage(role: 'assistant', text: text);
  }

  Future<void> _sendQuestion() async {
    final question = _questionController.text.trim();
    if (question.isEmpty) {
      return;
    }

    await _loadAiApiKey();

    setState(() {
      _messages.add(_AssistantMessage(role: 'user', text: question));
      _questionController.clear();
      _isSearching = true;
    });
    _scrollToBottom();

    final answer = await _buildAssistantResponse(question);
    if (!mounted) {
      return;
    }

    setState(() {
      _messages.add(_AssistantMessage(role: 'assistant', text: answer));
      _isSearching = false;
    });
    _scrollToBottom();
  }

  Future<String> _buildAssistantResponse(String question) {
    return _answerHikeAssistantQuestion(
      question: question,
      initialTrail: widget.initialTrail,
      searchMountainInMindanao: widget.searchMountainInMindanao,
      fetchMountainOrganizers: widget.fetchMountainOrganizers,
      aiApiKey: _aiApiKey,
      systemInstruction:
          'You are a friendly, knowledgeable hiking assistant '
          'for hikers in Mindanao, Philippines. Answer '
          'whatever the user actually asks — trail '
          'difficulty, elevation, weather, safety, gear, or '
          'general hiking advice — using your own knowledge. '
          'Only talk about organizers/guides when the user '
          'asks about finding one or contact info is provided '
          'to you.',
    );
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scrollController.hasClients) {
        return;
      }
      _scrollController.animateTo(
        _scrollController.position.maxScrollExtent,
        duration: const Duration(milliseconds: 250),
        curve: Curves.easeOut,
      );
    });
  }

  Future<void> _loadAiApiKey() async {
    if (_aiApiKey.isNotEmpty) {
      return;
    }
    _aiApiKey = await loadGeminiApiKey();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Hike Assistant'),
        backgroundColor: const Color(0xFF02130E),
      ),
      backgroundColor: const Color(0xFF02130E),
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: ListView.builder(
                controller: _scrollController,
                padding: const EdgeInsets.all(16),
                itemCount: _messages.length,
                itemBuilder: (context, index) {
                  final message = _messages[index];
                  final isUser = message.role == 'user';
                  return Container(
                    margin: const EdgeInsets.only(bottom: 12),
                    alignment: isUser
                        ? Alignment.centerRight
                        : Alignment.centerLeft,
                    child: Container(
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: isUser
                            ? const Color(0xFF53D97A)
                            : const Color(0xFF041B13).withValues(alpha: 0.95),
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(
                          color: isUser
                              ? const Color(0xFF53D97A)
                              : Colors.white.withValues(alpha: 0.12),
                        ),
                      ),
                      child: Text(
                        message.text,
                        style: TextStyle(
                          color: isUser ? Colors.black : Colors.white,
                          height: 1.4,
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
            if (_isSearching)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 10),
                child: CircularProgressIndicator(color: Color(0xFF7CF9A2)),
              ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                color: const Color(0xFF02130E),
                border: Border(
                  top: BorderSide(color: Colors.white.withValues(alpha: 0.08)),
                ),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _questionController,
                      textInputAction: TextInputAction.send,
                      onSubmitted: (_) => _sendQuestion(),
                      style: const TextStyle(color: Colors.white),
                      decoration: InputDecoration(
                        isDense: true,
                        hintText:
                            'Ask about organizers, trails, or this mountain...',
                        hintStyle: TextStyle(
                          color: Colors.white.withValues(alpha: 0.55),
                        ),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(16),
                          borderSide: BorderSide(
                            color: Colors.white.withValues(alpha: 0.14),
                          ),
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(16),
                          borderSide: BorderSide(
                            color: Colors.white.withValues(alpha: 0.14),
                          ),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(16),
                          borderSide: const BorderSide(
                            color: Color(0xFF53D97A),
                          ),
                        ),
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 14,
                          vertical: 12,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Material(
                    color: const Color(0xFF53D97A),
                    borderRadius: BorderRadius.circular(16),
                    child: InkWell(
                      onTap: _isSearching ? null : _sendQuestion,
                      borderRadius: BorderRadius.circular(16),
                      child: const Padding(
                        padding: EdgeInsets.all(12),
                        child: Icon(
                          Icons.send_rounded,
                          color: Colors.black,
                          size: 22,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Whether [normalizedQuestion] is asking about weather/conditions — the
/// trigger for pulling a live GPS + weather snapshot into the answer
/// instead of letting the AI guess or say it has no real-time data, and
/// for skipping the free-text mountain-name search below (a weather
/// question like "what is the weather today" has no mountain name in it,
/// and searching Places/Nominatim for the whole sentence risks fuzzy-
/// matching an unrelated place, e.g. it previously matched PAGASA's
/// office off the word "weather").
bool _isWeatherQuestion(String normalizedQuestion) {
  const weatherWords = [
    'weather',
    'rain',
    'rainy',
    'raining',
    'forecast',
    'storm',
    'stormy',
    'typhoon',
    'sunny',
    'cloudy',
    'temperature',
    'hot',
    'cold',
    'humid',
    'climate',
    'condition',
  ];
  return weatherWords.any(normalizedQuestion.contains);
}

/// Whether [normalizedQuestion] is asking about the hiker's current
/// whereabouts — same rationale as [_isWeatherQuestion]: it both triggers
/// the dedicated GPS-classification context and skips the free-text
/// mountain-name search, which has nothing useful to match against a
/// "where am I" question.
bool _isLocationQuestion(String normalizedQuestion) {
  const locationPhrases = [
    'where am i',
    "where's this",
    'where is this',
    'what trail am i on',
    'which trail am i on',
    'my current location',
    'my location',
    'what is my location',
    "what's my location",
  ];
  return locationPhrases.any(normalizedQuestion.contains);
}

/// Shared "modern, on-palette" confirm/cancel dialog — cream card, rounded
/// corners, a tinted icon roundel, and a two-button row. Top-level (not a
/// State method) so any screen can show a real confirmation instead of a
/// default gray `AlertDialog`, without duplicating this layout per call
/// site. Returns true only when the hiker tapped the confirm action.
Future<bool> _showAgakConfirmDialog(
  BuildContext context, {
  required IconData icon,
  required String title,
  required String message,
  required String cancelLabel,
  required String confirmLabel,
  IconData? confirmIcon,
  Color iconColor = AgakColors.maroon,
  Color confirmColor = AgakColors.maroon,
}) async {
  final result = await showDialog<bool>(
    context: context,
    barrierColor: Colors.black.withValues(alpha: 0.55),
    builder: (dialogContext) {
      return Dialog(
        backgroundColor: Colors.transparent,
        insetPadding: const EdgeInsets.symmetric(horizontal: 28),
        child: Container(
          padding: const EdgeInsets.fromLTRB(24, 28, 24, 20),
          decoration: BoxDecoration(
            color: AgakColors.cream,
            borderRadius: BorderRadius.circular(28),
            border: Border.all(color: AgakColors.ink.withValues(alpha: 0.08)),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.28),
                blurRadius: 30,
                offset: const Offset(0, 14),
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 64,
                height: 64,
                decoration: BoxDecoration(
                  color: iconColor.withValues(alpha: 0.12),
                  shape: BoxShape.circle,
                ),
                child: Icon(icon, color: iconColor, size: 32),
              ),
              const SizedBox(height: 16),
              Text(
                title,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: AgakColors.ink,
                  fontSize: 18,
                  fontWeight: FontWeight.w900,
                ),
              ),
              const SizedBox(height: 10),
              Text(
                message,
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: AgakColors.ink.withValues(alpha: 0.7),
                  fontSize: 13.5,
                  height: 1.45,
                ),
              ),
              const SizedBox(height: 24),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => Navigator.of(dialogContext).pop(false),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: AgakColors.ink.withValues(alpha: 0.68),
                        side: BorderSide(
                          color: AgakColors.ink.withValues(alpha: 0.22),
                        ),
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                      ),
                      child: Text(
                        cancelLabel,
                        style: const TextStyle(fontWeight: FontWeight.w700),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: confirmIcon == null
                        ? ElevatedButton(
                            onPressed: () =>
                                Navigator.of(dialogContext).pop(true),
                            style: ElevatedButton.styleFrom(
                              foregroundColor: AgakColors.cream,
                              backgroundColor: confirmColor,
                              elevation: 0,
                              padding: const EdgeInsets.symmetric(vertical: 14),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(14),
                              ),
                            ),
                            child: Text(
                              confirmLabel,
                              style: const TextStyle(
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                          )
                        : ElevatedButton.icon(
                            onPressed: () =>
                                Navigator.of(dialogContext).pop(true),
                            icon: Icon(confirmIcon, size: 18),
                            label: Text(
                              confirmLabel,
                              style: const TextStyle(
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                            style: ElevatedButton.styleFrom(
                              foregroundColor: AgakColors.cream,
                              backgroundColor: confirmColor,
                              elevation: 0,
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
      );
    },
  );
  return result == true;
}

/// Whether [normalizedQuestion] plausibly names a *specific* mountain or
/// is asking to look one up by name — the gate for the free-text
/// Places/Nominatim search below. This is deliberately narrow: generic
/// hiking-topic words ("hike", "trail", "climb"...) do NOT count, because
/// a sentence merely mentioning hiking isn't a place-name query and
/// sending it as one risks a fuzzy match on an unrelated real point of
/// interest (this once matched "what's your name" to an unnamed POI
/// literally labeled "No Name Yet", and "I'm sad, do I need to hike?" —
/// no mountain named at all — to a bogus "not found" mountain-search
/// reply instead of actually engaging with what was asked). Anything
/// that isn't a named-mountain lookup should go straight to the AI (or
/// the companion small-talk/fallback paths), never through this search.
bool _looksLikeMountainQuery(String normalizedQuestion) {
  const mountainSignalWords = [
    'mt ',
    'mt.',
    'mount ',
    'organizer',
    'organizers',
    'guide for',
    'guides for',
    'contact for',
  ];
  return mountainSignalWords.any(normalizedQuestion.contains);
}

/// Shared hike-question answering logic — extracted from the original
/// `_HikeAssistantScreenState` implementation so both the dark hike-assistant
/// chat and Kyrielle's own in-screen conversation (`KyrielleCompanionChatScreen`)
/// give identical answers instead of drifting apart from two copies.
Future<String> _answerHikeAssistantQuestion({
  required String question,
  required _NearbyTrail? initialTrail,
  required Future<_NearbyTrail?> Function(String query)
  searchMountainInMindanao,
  required Future<List<_MountainOrganizer>> Function(_NearbyTrail trail)
  fetchMountainOrganizers,
  required String aiApiKey,
  required String systemInstruction,
  void Function(_NearbyTrail trail)? onMountainMentioned,
  String? extraContext,
}) async {
  final normalized = question.toLowerCase();
  if (normalized.contains('what to bring') ||
      normalized.contains('what i need to bring') ||
      normalized.contains('what should i bring') ||
      normalized.contains('what do i bring') ||
      normalized.contains('what should i pack') ||
      normalized.contains('need to bring') ||
      normalized.contains('packing list') ||
      normalized.contains('gear') ||
      normalized.contains('pack') ||
      normalized.contains('prepare') ||
      normalized.contains('what do i need') ||
      normalized.contains('what do i need for') ||
      normalized.contains('what is needed') ||
      normalized.contains('what should i wear') ||
      normalized.contains('what is the gear')) {
    if (initialTrail == null) {
      return 'For a hike, bring plenty of water, snacks, weather-proof '
          'layers, a first-aid kit, a flashlight, and a charged phone. '
          'Tell me which mountain you have in mind and I can tailor the '
          'list to it.';
    }
    final items = buildPackingList(
      difficulty: initialTrail.difficulty,
      elevationMasl: initialTrail.elevationMasl,
    );
    return 'For ${initialTrail.name}, bring: ${items.join(', ')}.';
  }

  bool matchesTrailInQuestion(_NearbyTrail trail) {
    final normalizedName = trail.name.toLowerCase();
    return normalized.contains(normalizedName) ||
        normalized.contains('this mountain') ||
        normalized.contains('this hike') ||
        normalized.contains('the hike');
  }

  // Only questions that plausibly name/ask about a mountain go to the
  // free-text Places/Nominatim search — anything else (weather, location,
  // small talk) either has its own dedicated context or nothing to
  // usefully match, and sending it as a place-name query risks a fuzzy
  // match on an unrelated real place (e.g. "what is the weather today"
  // once matched PAGASA's office; "what's your name" once matched an
  // unnamed POI literally labeled "No Name Yet").
  final skipMountainSearch =
      _isWeatherQuestion(normalized) ||
      _isLocationQuestion(normalized) ||
      !_looksLikeMountainQuery(normalized);

  _NearbyTrail? trail = initialTrail;
  if (trail == null || !matchesTrailInQuestion(trail)) {
    trail = skipMountainSearch
        ? null
        : await searchMountainInMindanao(question);
  }
  if (trail != null) {
    onMountainMentioned?.call(trail);
  }

  final organizers = trail == null
      ? const <_MountainOrganizer>[]
      : await fetchMountainOrganizers(trail);

  if (aiApiKey.isNotEmpty) {
    final contextBuffer = StringBuffer();
    if (extraContext != null && extraContext.isNotEmpty) {
      contextBuffer.writeln(extraContext);
    }
    if (trail != null) {
      contextBuffer.writeln(
        'Matched trail: ${trail.name}, ${trail.provinceOrCity}.',
      );
      if (organizers.isNotEmpty) {
        final organizerList = organizers
            .take(5)
            .map((organizer) {
              return '${organizer.name} — ${organizer.contact} (${organizer.source})${organizer.verified ? ' ✓ verified' : ''}';
            })
            .join('\n');
        contextBuffer.writeln(
          'Known organizer contacts for this trail:\n$organizerList',
        );
      } else {
        contextBuffer.writeln(
          'No organizer contacts are on file for this trail in the app.',
        );
      }
    } else {
      contextBuffer.writeln(
        'No specific trail was matched in the app database for this question.',
      );
    }
    final prompt =
        '''
The user asked: "$question"
$contextBuffer
Answer the user's actual question directly and helpfully, using your general knowledge (e.g. elevation, difficulty, weather, best season) whenever the app data above doesn't cover it. Only bring up organizer contacts if the question is actually about finding a guide, or the listed contacts are directly relevant. Keep it to 2-4 sentences.
''';
    final aiAnswer = await fetchGeminiResponse(
      apiKey: aiApiKey,
      systemInstruction: systemInstruction,
      prompt: prompt,
    );
    if (aiAnswer.isNotEmpty) {
      return aiAnswer;
    }
  }

  if (trail == null) {
    if (skipMountainSearch) {
      // We deliberately never searched — the question wasn't mountain-
      // related to begin with, so "I couldn't find a mountain matching
      // that" would be a non sequitur here (this is the AI-unavailable
      // fallback; the AI branch above already tried to answer directly).
      return "I'm more in my element talking trails — difficulty, "
          'elevation, weather, gear, or organizer contacts for a '
          "mountain. Throw one of those my way and I'll help you plan "
          'it out!';
    }
    return 'I could not find a mountain matching that query. Try asking with a more exact name, such as "Mt. Apo" or "Mount Matutum."';
  }

  if (organizers.isEmpty) {
    return 'I found ${trail.name}, but I could not find any matching organizers right now. You can still search again with another mountain name, or use the Explore map to browse nearby trails.';
  }

  final buffer = StringBuffer();
  buffer.writeln(
    'I found ${organizers.length} organizer suggestions for ${trail.name}:',
  );
  final displayedOrganizers = organizers.take(3);
  var index = 1;
  for (final organizer in displayedOrganizers) {
    buffer.writeln(
      '${index++}. ${organizer.name} — ${organizer.contact} (${organizer.source})${organizer.verified ? ' ✓ verified' : ''}',
    );
  }
  if (organizers.length > 3) {
    buffer.writeln('And ${organizers.length - 3} more results are available.');
  }
  buffer.writeln(
    'You can ask me to search another mountain or request more details.',
  );
  return buffer.toString();
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
    required this.imageUrl,
    required this.likeCount,
    required this.commentCount,
    required this.createdAt,
  });

  final String id;
  final String authorId;
  final String authorName;
  final String content;
  final String mountainName;
  final String imageUrl;
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
          color: AgakColors.ink.withValues(alpha: 0.52),
          fontSize: 8,
          fontWeight: FontWeight.w800,
        ),
      ),
    );
  }
}

enum _NearbyAnchorMode { nearMe, nearSearch }

enum _MarkerStatusFilter { all, open, closed }

enum _MyHikesView { completed, recorded }

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
    southwest: const LatLng(4.3, 121.0),
    northeast: const LatLng(10.7, 126.7),
  );
  GoogleMapController? _mapController;
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseAuth _firebaseAuth = FirebaseAuth.instance;
  final HikeRoomService _hikeRoomService = HikeRoomService();
  final TextEditingController _searchController = TextEditingController();
  final TextEditingController _communityComposerController =
      TextEditingController();
  XFile? _communityComposerImage;
  bool _postingCommunityPost = false;
  final WeatherService _weatherService = WeatherService();
  String _mapsApiKey = '';
  String _weatherApiKey = '';
  String _customSearchApiKey = '';
  String _customSearchEngineId = '';
  String _accountType = 'hiker';
  String _locationAccessStatus = 'Checking';
  bool _checkingLocationAccessStatus = false;
  bool _updatingProfile = false;
  bool _uploadingProfilePhoto = false;
  Map<String, dynamic> _currentUserProfile = <String, dynamic>{};
  LatLng _currentCenter = _fallbackCenter;
  LatLng? _myLocationCenter;
  _NearbyTrail? _searchedTrailAnchor;
  String _kyrielleAiApiKey = '';
  _NearbyAnchorMode _nearbyAnchorMode = _NearbyAnchorMode.nearMe;
  bool _nearbyCardCollapsed = false;
  String? _locationMessage;
  String? _nearbyTrailsMessage;
  bool _locationGranted = false;
  bool _isSearching = false;
  bool _isLoadingNearbyTrails = false;
  _MarkerStatusFilter _markerStatusFilter = _MarkerStatusFilter.all;
  int _selectedNavIndex = 0;
  int _communityFeedFilterIndex = 0;
  _MyHikesView _myHikesView = _MyHikesView.completed;
  Marker? _searchMarker;
  List<_NearbyTrail> _nearbyTrails = const [];
  List<PendingTrailSubmission> _pendingTrailSubmissions =
      const <PendingTrailSubmission>[];
  bool _loadingPendingTrailSubmissions = false;
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
        setState(() {
          _accountType = accountType;
          _currentUserProfile = profile;
        });
      }
    } catch (_) {
      _accountType = 'hiker';
    }
    unawaited(_backfillPublicProfileName());
    unawaited(AgakBehaviorDatabase.instance.clearCompletedHikes());
    await _loadMapsApiKey();
    await _loadSearchProviderConfig();
    unawaited(_ensureDefaultAppContent());
    unawaited(_refreshLocationAccessStatus());
    unawaited(AgakController.instance.refresh());
    unawaited(_loadCompletedHikesFromFirestore());
    await _loadCurrentLocation();
    unawaited(_refreshAgakAmbientWeather());
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

  Future<void> _loadSearchProviderConfig() async {
    if (_customSearchApiKey.isNotEmpty && _customSearchEngineId.isNotEmpty) {
      return;
    }

    try {
      final apiKey = await _configChannel.invokeMethod<String>(
        'getCustomSearchApiKey',
      );
      final searchEngineId = await _configChannel.invokeMethod<String>(
        'getCustomSearchEngineId',
      );
      if (apiKey != null && apiKey.trim().isNotEmpty) {
        _customSearchApiKey = apiKey.trim();
      }
      if (searchEngineId != null && searchEngineId.trim().isNotEmpty) {
        _customSearchEngineId = searchEngineId.trim();
      }
    } catch (_) {
      // Ignore missing provider config.
    }
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
      unawaited(
        AgakBehaviorDatabase.instance.logSearch(
          query: query,
          matchedMountainId: result == null
              ? null
              : buildMountainMatchKey(
                  name: result.name,
                  region: result.provinceOrCity,
                ),
          matchedMountainName: result?.name,
          source: 'dashboard_search',
        ),
      );

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

  Future<List<_MountainOrganizer>> _fetchMountainOrganizers(
    _NearbyTrail trail,
  ) async {
    const maxTokens = 10;
    final foundOrganizers = <_MountainOrganizer>[];
    final mountainKey = _mountainKeyForTrail(trail);
    final nameKey = _normalizeTokenString(trail.name);
    final searchTokens = _mountainTokens(trail.name).take(maxTokens).toList();

    try {
      final primaryResult = await _firestore
          .collection('mountain_organizers')
          .where('mountainKey', isEqualTo: mountainKey)
          .get();
      var docs = primaryResult.docs;
      if (docs.isEmpty && mountainKey.contains('__')) {
        final fallbackResult = await _firestore
            .collection('mountain_organizers')
            .where('mountainKey', isEqualTo: nameKey)
            .get();
        docs = fallbackResult.docs;
      }
      for (final doc in docs) {
        final data = doc.data();
        final name = data['organizerName']?.toString().trim() ?? 'Organizer';
        final contact =
            data['contact']?.toString().trim() ?? 'Contact not available';
        final description = data['description']?.toString().trim() ?? '';
        final source = data['source']?.toString().trim() ?? 'App listing';
        final verified = data['verified'] == true;
        foundOrganizers.add(
          _MountainOrganizer(
            id: doc.id,
            name: name,
            contact: contact,
            description: description,
            source: source,
            verified: verified,
          ),
        );
      }
    } catch (_) {
      // Ignore missing organizer collection.
    }

    if (searchTokens.isEmpty) {
      return foundOrganizers;
    }

    try {
      final usersQuery = _firestore
          .collection('users')
          .where('accountType', isEqualTo: 'tour_guide');

      List<QueryDocumentSnapshot<Map<String, dynamic>>> userDocs;

      if (searchTokens.isNotEmpty) {
        final matchingGuides = await usersQuery
            .where('serviceMountains', arrayContainsAny: searchTokens)
            .get();

        if (matchingGuides.docs.isNotEmpty) {
          userDocs = matchingGuides.docs;
        } else {
          final allGuides = await usersQuery.get();
          userDocs = allGuides.docs.where((doc) {
            final data = doc.data();
            final serviceMountains = <String>[];
            if (data['serviceMountains'] is List) {
              serviceMountains.addAll(
                (data['serviceMountains'] as List)
                    .map((item) => item?.toString().trim() ?? '')
                    .where((item) => item.isNotEmpty),
              );
            } else if (data['serviceMountains'] is String) {
              serviceMountains.addAll(
                data['serviceMountains']
                    .toString()
                    .split(RegExp(r'[;,]'))
                    .map((item) => item.trim())
                    .where((item) => item.isNotEmpty),
              );
            }

            final normalizedServiceMountains = serviceMountains
                .map(_normalizeTokenWords)
                .where((item) => item.isNotEmpty)
                .toList();
            final normalizedBio = _normalizeTokenWords(
              data['bio']?.toString() ?? '',
            );

            return searchTokens.any((token) {
              return normalizedServiceMountains.any(
                    (entry) => entry.contains(token),
                  ) ||
                  normalizedBio.contains(token);
            });
          }).toList();
        }
      } else {
        final allGuides = await usersQuery.get();
        userDocs = allGuides.docs;
      }

      for (final doc in userDocs) {
        final data = doc.data();
        final displayName =
            data['fullName']?.toString().trim() ??
            data['displayName']?.toString().trim() ??
            'Tour Guide';
        final contact =
            data['phoneNumber']?.toString().trim() ??
            data['contactNumber']?.toString().trim() ??
            data['phone']?.toString().trim() ??
            data['email']?.toString().trim() ??
            'Contact not available';
        final serviceMountains = <String>[];
        if (data['serviceMountains'] is List) {
          serviceMountains.addAll(
            (data['serviceMountains'] as List)
                .map((item) => item?.toString().trim() ?? '')
                .where((item) => item.isNotEmpty),
          );
        } else if (data['serviceMountains'] is String) {
          serviceMountains.addAll(
            data['serviceMountains']
                .toString()
                .split(RegExp(r'[;,]'))
                .map((item) => item.trim())
                .where((item) => item.isNotEmpty),
          );
        }

        final normalizedBio = _normalizeTokenWords(
          data['bio']?.toString() ?? '',
        );
        if (serviceMountains.isEmpty && searchTokens.isNotEmpty) {
          for (final token in searchTokens) {
            if (normalizedBio.contains(token)) {
              serviceMountains.add(token);
              break;
            }
          }
        }

        final description = serviceMountains.isNotEmpty
            ? 'Offers hikes for ${serviceMountains.join(', ')}.'
            : data['bio']?.toString().trim() ?? '';
        final source = 'Guide account';
        final verified = data['guideVerified'] == true;
        final organizer = _MountainOrganizer(
          id: doc.id,
          name: displayName,
          contact: contact,
          description: description,
          source: source,
          verified: verified,
        );
        if (!foundOrganizers.any((item) => item.id == organizer.id)) {
          foundOrganizers.add(organizer);
        }
      }
    } catch (_) {
      // If token-based query is unavailable, ignore.
    }

    try {
      final externalOrganizers = await _fetchExternalOrganizerSuggestions(
        trail,
      );
      for (final organizer in externalOrganizers) {
        if (!foundOrganizers.any((item) => item.id == organizer.id)) {
          foundOrganizers.add(organizer);
        }
      }
    } catch (_) {
      // Ignore external search failures.
    }

    return foundOrganizers;
  }

  Future<List<_MountainOrganizer>> _fetchExternalOrganizerSuggestions(
    _NearbyTrail trail,
  ) async {
    if (_customSearchApiKey.isNotEmpty && _customSearchEngineId.isNotEmpty) {
      try {
        final customSearchResults = await _fetchGoogleCustomSearchSuggestions(
          trail,
        );
        if (customSearchResults.isNotEmpty) {
          return customSearchResults;
        }
      } catch (error) {
        debugPrint('Google Custom Search failed: $error');
      }
    }

    try {
      return await _fetchDuckDuckGoOrganizerSuggestions(trail);
    } catch (error) {
      debugPrint('DuckDuckGo search failed: $error');
      return const <_MountainOrganizer>[];
    }
  }

  Future<List<_MountainOrganizer>> _fetchGoogleCustomSearchSuggestions(
    _NearbyTrail trail,
  ) async {
    final query = <String>[
      trail.name,
      trail.provinceOrCity,
      _provinceOrCityFromAddress(trail.address),
      'mountain guide',
      'tour guide',
    ].where((part) => part.isNotEmpty).join(' ');

    final uri = Uri.https('www.googleapis.com', '/customsearch/v1', {
      'key': _customSearchApiKey,
      'cx': _customSearchEngineId,
      'q': query,
      'num': '5',
      'safe': 'off',
    });

    final response = await http.get(uri).timeout(const Duration(seconds: 10));
    if (response.statusCode != 200) {
      return const <_MountainOrganizer>[];
    }

    final body = json.decode(response.body);
    if (body is! Map<String, dynamic>) {
      return const <_MountainOrganizer>[];
    }

    final items = body['items'];
    if (items is! List || items.isEmpty) {
      return const <_MountainOrganizer>[];
    }

    final suggestions = <_MountainOrganizer>[];
    for (var index = 0; index < items.length; index++) {
      final item = items[index];
      if (item is! Map<String, dynamic>) {
        continue;
      }
      final title = item['title']?.toString().trim() ?? 'Search result';
      final link = item['link']?.toString().trim() ?? '';
      final snippet = item['snippet']?.toString().trim() ?? '';
      if (title.isEmpty && link.isEmpty) {
        continue;
      }
      suggestions.add(
        _MountainOrganizer(
          id: 'google_custom_search_${trail.placeId}_$index',
          name: title,
          contact: link.isNotEmpty ? link : 'Search result',
          description: snippet,
          source: 'Google Custom Search',
          verified: false,
          isExternalSuggestion: true,
        ),
      );
    }
    return suggestions;
  }

  Future<List<_MountainOrganizer>> _fetchDuckDuckGoOrganizerSuggestions(
    _NearbyTrail trail,
  ) async {
    final cityOrProvince = _provinceOrCityFromAddress(trail.address);
    final queries = <String>{
      [
        trail.name,
        'mountain guide contact',
        cityOrProvince,
      ].where((part) => part.isNotEmpty).join(' '),
      [
        trail.name,
        'hiking guide',
        cityOrProvince,
      ].where((part) => part.isNotEmpty).join(' '),
      [
        trail.name,
        'tour guide',
        cityOrProvince,
      ].where((part) => part.isNotEmpty).join(' '),
      [
        trail.name,
        'mountain guide Philippines',
      ].where((part) => part.isNotEmpty).join(' '),
      [
        'Mount ${trail.name}',
        'guide',
        cityOrProvince,
      ].where((part) => part.isNotEmpty).join(' '),
    };

    for (final query in queries) {
      final uri = Uri.https('api.duckduckgo.com', '/', {
        'q': query,
        'format': 'json',
        'no_redirect': '1',
        'no_html': '1',
      });

      try {
        final response = await http
            .get(uri)
            .timeout(const Duration(seconds: 10));
        if (response.statusCode != 200) {
          continue;
        }

        final body = json.decode(response.body);
        if (body is! Map<String, dynamic>) {
          continue;
        }

        final suggestions = <_MountainOrganizer>[];
        final abstractText = body['AbstractText']?.toString().trim() ?? '';
        final abstractSource = body['AbstractSource']?.toString().trim();
        if (abstractText.isNotEmpty) {
          suggestions.add(
            _MountainOrganizer(
              id: 'web_${trail.placeId}_abstract_$query',
              name: 'Search suggestion',
              contact: abstractSource?.isNotEmpty == true
                  ? abstractSource!
                  : 'Web search result',
              description: abstractText,
              source: 'DuckDuckGo',
              verified: false,
              isExternalSuggestion: true,
            ),
          );
        }

        if (body['RelatedTopics'] is List) {
          for (final topic in _extractDuckDuckGoTopics(
            body['RelatedTopics'] as List,
          )) {
            final text = topic['Text']?.toString().trim() ?? '';
            if (text.isEmpty) {
              continue;
            }

            final firstUrl = topic['FirstURL']?.toString().trim();
            final title =
                topic['Name']?.toString().trim() ?? 'Web search recommendation';
            final id =
                'web_${trail.placeId}_${suggestions.length}_${text.hashCode}';

            suggestions.add(
              _MountainOrganizer(
                id: id,
                name: title,
                contact: firstUrl?.isNotEmpty == true
                    ? firstUrl!
                    : 'Search provider result',
                description: text,
                source: 'DuckDuckGo',
                verified: false,
                isExternalSuggestion: true,
              ),
            );
          }
        }

        if (suggestions.isNotEmpty) {
          return suggestions;
        }
      } catch (_) {
        continue;
      }
    }

    return const <_MountainOrganizer>[];
  }

  Iterable<Map<String, dynamic>> _extractDuckDuckGoTopics(
    List<dynamic> items,
  ) sync* {
    for (final item in items) {
      if (item is Map<String, dynamic>) {
        if (item.containsKey('Text')) {
          yield item;
        }
        if (item['Topics'] is List) {
          yield* _extractDuckDuckGoTopics(item['Topics'] as List<dynamic>);
        }
      }
    }
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

  // Popping a dialog route immediately after unfocusing a still-focused
  // TextField can hit a Flutter framework race (`_dependents.isEmpty`
  // assertion in framework.dart) because the keyboard/IME teardown hasn't
  // finished when the route's Element tree is torn down. Giving it one
  // extra frame before popping avoids it.
  void _unfocusThenPop<T>(BuildContext dialogContext, [T? result]) {
    FocusManager.instance.primaryFocus?.unfocus();
    Future.delayed(const Duration(milliseconds: 80), () {
      if (dialogContext.mounted) {
        Navigator.of(dialogContext).pop(result);
      }
    });
  }

  Future<void> _refreshPendingTrailSubmissions() async {
    if (_loadingPendingTrailSubmissions) {
      return;
    }
    setState(() => _loadingPendingTrailSubmissions = true);
    try {
      final submissions = await OfflineActivityDatabase.instance
          .getPendingTrailSubmissions();
      if (!mounted) {
        return;
      }
      setState(() {
        _pendingTrailSubmissions = submissions;
        _loadingPendingTrailSubmissions = false;
      });
    } catch (_) {
      if (mounted) {
        setState(() => _loadingPendingTrailSubmissions = false);
      }
    }
  }

  Stream<QuerySnapshot<Map<String, dynamic>>>? _trailSubmissionsStream() {
    final user = _firebaseAuth.currentUser;
    if (user == null) {
      return null;
    }
    return _firestore
        .collection('trail_submissions')
        .where('submittedBy', isEqualTo: user.uid)
        .snapshots();
  }

  Future<void> _ensureDefaultAppContent() async {
    final defaults = <String, Map<String, dynamic>>{
      'safety_guide': {
        'body':
            'Use Agakbay as a planning and tracking aid. Always follow local rules, weather advisories, and your guide.',
        'sections': [
          {
            'title': 'Before the hike',
            'body':
                'Check weather, tell someone your route, charge your phone, bring water, food, a light, and first-aid basics.',
          },
          {
            'title': 'During the hike',
            'body':
                'Stay on the trail, keep your group together, watch for sudden weather changes, and save battery for navigation and SOS.',
          },
          {
            'title': 'Emergency',
            'body':
                'Use the Hike SOS Room when hiking with a guide. Share your GPS location and wait for instructions if injured or lost.',
          },
        ],
        'updatedAt': FieldValue.serverTimestamp(),
      },
      'about_agakbay': {
        'body':
            'Agakbay is a hiking companion for exploring mountains, tracking hikes, recording missing trails, and supporting guide-led SOS rooms.',
        'sections': [
          {
            'title': 'Trail recording',
            'body':
                'When a mountain has no mapped trail, hikers can record the real route. Agakbay checks the recording before showing it as a community route.',
          },
          {
            'title': 'Community routes',
            'body':
                'Community recorded trails are useful guides, but hikers should still follow local guides, signs, and safety rules.',
          },
        ],
        'updatedAt': FieldValue.serverTimestamp(),
      },
    };

    for (final entry in defaults.entries) {
      try {
        final ref = _firestore.collection('app_content').doc(entry.key);
        final snapshot = await ref.get();
        if (!snapshot.exists) {
          await ref.set({
            ...entry.value,
            'createdAt': FieldValue.serverTimestamp(),
          });
        }
      } catch (_) {
        // Keep the UI usable even if Firestore rules block app content writes.
      }
    }
  }

  /// Self-heals accounts created before `users/{uid}/public/profile`
  /// existed — without this doc, other users resolving *this* account's
  /// live display name (see `_fetchCommunityAuthorName`) would keep
  /// falling back to whatever name was frozen into their old posts.
  /// Cheap: only writes if the doc is actually missing.
  Future<void> _backfillPublicProfileName() async {
    final user = _firebaseAuth.currentUser;
    if (user == null) {
      return;
    }
    try {
      final publicDocRef = _firestore
          .collection('users')
          .doc(user.uid)
          .collection('public')
          .doc('profile');
      final existing = await publicDocRef.get();
      if (existing.exists &&
          (existing.data()?['fullName']?.toString().trim().isNotEmpty ??
              false)) {
        return;
      }
      await publicDocRef.set({'fullName': _communityDisplayName()});
    } catch (error) {
      debugPrint('Failed to backfill public profile name: $error');
    }
  }

  String _communityDisplayName() {
    final profileName =
        _currentUserProfile['fullName']?.toString().trim() ??
        _currentUserProfile['displayName']?.toString().trim() ??
        '';
    if (profileName.isNotEmpty) {
      return profileName;
    }
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

  String _accountTypeLabel() {
    return _accountType == 'tour_guide' ? 'Tour Guide' : 'Hiker';
  }

  String _profilePhotoUrl() {
    final profileUrl = _currentUserProfile['profilePhotoUrl']?.toString() ?? '';
    if (profileUrl.trim().isNotEmpty) {
      return profileUrl.trim();
    }
    return _firebaseAuth.currentUser?.photoURL?.trim() ?? '';
  }

  Future<void> _openEditProfileDialog() async {
    final controller = TextEditingController(text: _communityDisplayName());
    final result = await showDialog<String>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          backgroundColor: const Color(0xFF072117),
          title: const Text('Edit Name', style: TextStyle(color: Colors.white)),
          content: TextField(
            controller: controller,
            textCapitalization: TextCapitalization.words,
            textInputAction: TextInputAction.done,
            style: const TextStyle(color: Colors.white),
            decoration: InputDecoration(
              labelText: 'Display name',
              labelStyle: TextStyle(color: Colors.white.withValues(alpha: 0.7)),
              prefixIcon: const Icon(Icons.person_outline_rounded),
            ),
            onSubmitted: (value) =>
                _unfocusThenPop<String>(dialogContext, value),
          ),
          actions: [
            TextButton(
              onPressed: () => _unfocusThenPop<String>(dialogContext),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () {
                final value = controller.text;
                _unfocusThenPop<String>(dialogContext, value);
              },
              child: const Text('Save'),
            ),
          ],
        );
      },
    );
    controller.dispose();
    if (result == null || !mounted) {
      return;
    }
    final name = result.trim();
    if (name.length < 2) {
      _showDashboardSnackBar('Enter a valid display name.');
      return;
    }
    final user = _firebaseAuth.currentUser;
    if (user == null) {
      _showDashboardSnackBar('Sign in to update your profile.');
      return;
    }
    setState(() => _updatingProfile = true);
    try {
      await user.updateDisplayName(name);
      setState(() {
        _currentUserProfile = {
          ..._currentUserProfile,
          'fullName': name,
          'displayName': name,
        };
      });
      try {
        await _firestore.collection('users').doc(user.uid).set({
          'fullName': name,
          'displayName': name,
          'updatedAt': FieldValue.serverTimestamp(),
        }, SetOptions(merge: true));
        unawaited(
          _firestore
              .collection('users')
              .doc(user.uid)
              .collection('public')
              .doc('profile')
              .set({'fullName': name}),
        );
        _showDashboardSnackBar('Profile name updated.');
      } on FirebaseException catch (error) {
        _showDashboardSnackBar(
          'Name updated, but database save failed: ${_firebaseErrorText(error)}',
        );
      }
    } on FirebaseException catch (error) {
      _showDashboardSnackBar(
        'Unable to update profile name: ${_firebaseErrorText(error)}',
      );
    } catch (error) {
      _showDashboardSnackBar('Unable to update profile name: $error');
    } finally {
      if (mounted) {
        setState(() => _updatingProfile = false);
      }
    }
  }

  Future<void> _pickAndUploadProfilePhoto() async {
    final user = _firebaseAuth.currentUser;
    if (user == null) {
      _showDashboardSnackBar('Sign in to upload a profile photo.');
      return;
    }
    try {
      final picked = await ImagePicker().pickImage(
        source: ImageSource.gallery,
        imageQuality: 82,
        maxWidth: 900,
        maxHeight: 900,
      );
      if (picked == null || !mounted) {
        return;
      }
      setState(() => _uploadingProfilePhoto = true);
      final ref = FirebaseStorage.instance
          .ref()
          .child('profile_photos')
          .child(user.uid)
          .child('avatar.jpg');
      final bytes = await picked.readAsBytes();
      await ref.putData(
        bytes,
        SettableMetadata(
          contentType: picked.mimeType ?? 'image/jpeg',
          // Not immutable — this filename gets overwritten on every
          // re-upload, so a long/immutable cache would hide a changed
          // avatar. Moderate max-age keeps the CDN edge useful without
          // masking updates for too long.
          cacheControl: 'public, max-age=3600',
        ),
      );
      final url = await ref.getDownloadURL();
      await user.updatePhotoURL(url);
      setState(() {
        _currentUserProfile = {..._currentUserProfile, 'profilePhotoUrl': url};
      });
      try {
        await _firestore.collection('users').doc(user.uid).set({
          'profilePhotoUrl': url,
          'updatedAt': FieldValue.serverTimestamp(),
        }, SetOptions(merge: true));
        _showDashboardSnackBar('Profile photo updated.');
      } on FirebaseException catch (error) {
        _showDashboardSnackBar(
          'Photo uploaded, but database save failed: ${_firebaseErrorText(error)}',
        );
      }
    } on FirebaseException catch (error) {
      _showDashboardSnackBar(
        'Photo upload failed: ${_firebaseErrorText(error)}',
      );
    } on PlatformException catch (error) {
      _showDashboardSnackBar(
        'Photo picker failed: ${error.message ?? error.code}',
      );
    } catch (error) {
      _showDashboardSnackBar('Unable to upload profile photo: $error');
    } finally {
      if (mounted) {
        setState(() => _uploadingProfilePhoto = false);
      }
    }
  }

  String _firebaseErrorText(FirebaseException error) {
    final message = error.message?.trim();
    if (message != null && message.isNotEmpty) {
      return message;
    }
    return error.code;
  }

  String _emergencyContactName() {
    return _currentUserProfile['emergencyContactName']?.toString().trim() ?? '';
  }

  String _emergencyContactPhone() {
    return _currentUserProfile['emergencyContactPhone']?.toString().trim() ??
        '';
  }

  String _emergencyContactSummary() {
    final name = _emergencyContactName();
    final phone = _emergencyContactPhone();
    if (name.isEmpty && phone.isEmpty) {
      return 'Not set';
    }
    if (name.isNotEmpty && phone.isNotEmpty) {
      return '$name - $phone';
    }
    return name.isNotEmpty ? name : phone;
  }

  Future<void> _refreshLocationAccessStatus() async {
    if (_checkingLocationAccessStatus) {
      return;
    }
    if (mounted) {
      setState(() => _checkingLocationAccessStatus = true);
    }
    try {
      final serviceEnabled = await Geolocator.isLocationServiceEnabled();
      var status = 'Service off';
      if (serviceEnabled) {
        final permission = await Geolocator.checkPermission();
        status = switch (permission) {
          LocationPermission.always => 'Always allowed',
          LocationPermission.whileInUse => 'Allowed while using',
          LocationPermission.denied => 'Permission needed',
          LocationPermission.deniedForever => 'Permission blocked',
          LocationPermission.unableToDetermine => 'Unknown',
        };
      }
      if (!mounted) {
        return;
      }
      setState(() {
        _locationAccessStatus = status;
        _checkingLocationAccessStatus = false;
      });
    } catch (_) {
      if (!mounted) {
        return;
      }
      setState(() {
        _locationAccessStatus = 'Unknown';
        _checkingLocationAccessStatus = false;
      });
    }
  }

  Future<void> _openEmergencyContactDialog() async {
    final nameController = TextEditingController(text: _emergencyContactName());
    final phoneController = TextEditingController(
      text: _emergencyContactPhone(),
    );
    final result = await showDialog<Map<String, String>>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          backgroundColor: const Color(0xFF072117),
          title: const Text(
            'Emergency Contact',
            style: TextStyle(color: Colors.white),
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: nameController,
                textInputAction: TextInputAction.next,
                style: const TextStyle(color: Colors.white),
                decoration: InputDecoration(
                  labelText: 'Name',
                  labelStyle: TextStyle(
                    color: Colors.white.withValues(alpha: 0.7),
                  ),
                  prefixIcon: const Icon(Icons.person_outline_rounded),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: phoneController,
                keyboardType: TextInputType.phone,
                textInputAction: TextInputAction.done,
                style: const TextStyle(color: Colors.white),
                decoration: InputDecoration(
                  labelText: 'Phone number',
                  labelStyle: TextStyle(
                    color: Colors.white.withValues(alpha: 0.7),
                  ),
                  prefixIcon: const Icon(Icons.phone_rounded),
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => _unfocusThenPop(dialogContext),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () {
                _unfocusThenPop(dialogContext, {
                  'name': nameController.text.trim(),
                  'phone': phoneController.text.trim(),
                });
              },
              child: const Text('Save'),
            ),
          ],
        );
      },
    );
    nameController.dispose();
    phoneController.dispose();
    if (result == null || !mounted) {
      return;
    }
    final name = result['name'] ?? '';
    final phone = result['phone'] ?? '';
    if (name.isEmpty && phone.isEmpty) {
      _showDashboardSnackBar('Enter a name or phone number.');
      return;
    }
    final user = _firebaseAuth.currentUser;
    if (user == null) {
      _showDashboardSnackBar('Sign in to save an emergency contact.');
      return;
    }
    try {
      await _firestore.collection('users').doc(user.uid).set({
        'emergencyContactName': name,
        'emergencyContactPhone': phone,
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
      setState(() {
        _currentUserProfile = {
          ..._currentUserProfile,
          'emergencyContactName': name,
          'emergencyContactPhone': phone,
        };
      });
      _showDashboardSnackBar('Emergency contact saved.');
    } catch (_) {
      _showDashboardSnackBar('Unable to save emergency contact.');
    }
  }

  void _openMyHikesView(_MyHikesView view) {
    setState(() {
      _selectedNavIndex = 1;
      _myHikesView = view;
    });
    if (view != _MyHikesView.completed) {
      unawaited(_refreshPendingTrailSubmissions());
    }
  }

  String _communityAvatarSeed(String name) {
    final trimmed = name.trim();
    if (trimmed.isEmpty) {
      return '?';
    }
    return trimmed[0].toUpperCase();
  }

  static const List<List<Color>> _avatarGradientPalette = [
    [Color(0xFF53D97A), Color(0xFF0F5A3D)],
    [Color(0xFF48D1FF), Color(0xFF0E5A73)],
    [Color(0xFFFFD76A), Color(0xFFB2600C)],
    [Color(0xFFFF9D7A), Color(0xFFB23A2E)],
    [Color(0xFFB79CFF), Color(0xFF5A3EA6)],
    [Color(0xFF7CF9A2), Color(0xFF1B6E4C)],
  ];

  LinearGradient _avatarGradient(String name) {
    final trimmed = name.trim();
    final hash = trimmed.isEmpty
        ? 0
        : trimmed.codeUnits.fold<int>(0, (total, code) => total + code);
    final colors = _avatarGradientPalette[hash % _avatarGradientPalette.length];
    return LinearGradient(
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
      colors: colors,
    );
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
      imageUrl: data['imageUrl']?.toString() ?? '',
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

  Future<void> _createCommunityPost(String content, {XFile? image}) async {
    final user = _firebaseAuth.currentUser;
    if (user == null) {
      _showDashboardSnackBar('Please sign in to create a post.');
      return;
    }
    final text = content.trim();
    if (text.isEmpty && image == null) {
      _showDashboardSnackBar('Write something or add a photo before posting.');
      return;
    }
    try {
      var imageUrl = '';
      if (image != null) {
        final ref = FirebaseStorage.instance
            .ref()
            .child('community_post_photos')
            .child(user.uid)
            .child('${DateTime.now().microsecondsSinceEpoch}.jpg');
        final bytes = await image.readAsBytes();
        await ref.putData(
          bytes,
          SettableMetadata(
            contentType: image.mimeType ?? 'image/jpeg',
            // Safe to mark immutable: the filename embeds a microsecond
            // timestamp, so a given URL's content never changes.
            cacheControl: 'public, max-age=86400, immutable',
          ),
        );
        imageUrl = await ref.getDownloadURL();
      }
      await _firestore.collection('community_posts').add({
        'authorId': user.uid,
        'authorName': _communityDisplayName(),
        'content': text,
        'mountainName': _searchedTrailAnchor?.name ?? '',
        'imageUrl': imageUrl,
        'likeCount': 0,
        'commentCount': 0,
        'createdAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      });
    } catch (_) {
      _showDashboardSnackBar('Failed to publish post.');
    }
  }

  Future<void> _pickCommunityComposerImage() async {
    FocusManager.instance.primaryFocus?.unfocus();
    try {
      final picked = await ImagePicker().pickImage(
        source: ImageSource.gallery,
        imageQuality: 82,
        maxWidth: 1600,
        maxHeight: 1600,
      );
      if (picked == null || !mounted) {
        return;
      }
      setState(() => _communityComposerImage = picked);
    } catch (error) {
      _showDashboardSnackBar('Unable to select photo: $error');
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

  Future<void> _deleteCommunityComment(String postId, String commentId) async {
    final postRef = _firestore.collection('community_posts').doc(postId);
    final commentRef = postRef.collection('comments').doc(commentId);
    try {
      await _firestore.runTransaction((tx) async {
        final postSnap = await tx.get(postRef);
        if (!postSnap.exists) {
          return;
        }
        final current = (postSnap.data()?['commentCount'] is num)
            ? (postSnap.data()!['commentCount'] as num).toInt()
            : 0;
        tx.delete(commentRef);
        tx.update(postRef, {
          'commentCount': current > 0 ? current - 1 : 0,
          'updatedAt': FieldValue.serverTimestamp(),
        });
      });
    } catch (_) {
      _showDashboardSnackBar('Unable to delete comment.');
    }
  }

  Future<void> _editCommunityPost(_CommunityPost post) async {
    final user = _firebaseAuth.currentUser;
    if (user == null || user.uid != post.authorId) {
      return;
    }
    final controller = TextEditingController(text: post.content);
    final result = await showDialog<String>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          backgroundColor: const Color(0xFF072117),
          title: const Text('Edit Post', style: TextStyle(color: Colors.white)),
          content: TextField(
            controller: controller,
            minLines: 1,
            maxLines: 5,
            style: const TextStyle(color: Colors.white),
            decoration: InputDecoration(
              hintText: "What's on your trail today?",
              hintStyle: TextStyle(color: Colors.white.withValues(alpha: 0.6)),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: BorderSide(
                  color: Colors.white.withValues(alpha: 0.2),
                ),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: const BorderSide(color: Color(0xFF53D97A)),
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => _unfocusThenPop<String>(dialogContext),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () {
                final text = controller.text.trim();
                _unfocusThenPop<String>(dialogContext, text);
              },
              style: ElevatedButton.styleFrom(
                foregroundColor: Colors.black,
                backgroundColor: const Color(0xFF53D97A),
              ),
              child: const Text('Save'),
            ),
          ],
        );
      },
    );
    controller.dispose();
    if (result == null || !mounted) {
      return;
    }
    if (result.isEmpty && post.imageUrl.trim().isEmpty) {
      _showDashboardSnackBar('Post cannot be empty.');
      return;
    }
    try {
      await _firestore.collection('community_posts').doc(post.id).update({
        'content': result,
        'updatedAt': FieldValue.serverTimestamp(),
      });
    } catch (_) {
      _showDashboardSnackBar('Unable to update post.');
    }
  }

  Future<void> _deleteCommunityPost(_CommunityPost post) async {
    final user = _firebaseAuth.currentUser;
    if (user == null || user.uid != post.authorId) {
      return;
    }
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          backgroundColor: const Color(0xFF072117),
          title: const Text(
            'Delete Post?',
            style: TextStyle(color: Colors.white),
          ),
          content: Text(
            'This will permanently remove your post.',
            style: TextStyle(color: Colors.white.withValues(alpha: 0.86)),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () => Navigator.of(dialogContext).pop(true),
              style: ElevatedButton.styleFrom(
                foregroundColor: Colors.white,
                backgroundColor: const Color(0xFFE05555),
              ),
              child: const Text('Delete'),
            ),
          ],
        );
      },
    );
    if (confirmed != true) {
      return;
    }
    try {
      await _firestore.collection('community_posts').doc(post.id).delete();
      if (post.imageUrl.trim().isNotEmpty) {
        try {
          await FirebaseStorage.instance.refFromURL(post.imageUrl).delete();
        } catch (_) {
          // Photo may already be gone; ignore.
        }
      }
      _showDashboardSnackBar('Post deleted.');
    } catch (_) {
      _showDashboardSnackBar('Unable to delete post.');
    }
  }

  Future<void> _openCommunityPostDetails(_CommunityPost post) async {
    final commentController = TextEditingController();
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) {
        return PopScope(
          canPop: false,
          onPopInvokedWithResult: (didPop, result) {
            if (didPop) return;
            // The comment TextField's keyboard teardown racing with the
            // sheet's own dismiss animation is what trips a framework
            // assertion on drag-to-dismiss — unfocusing first, then
            // popping, sequences the two instead of leaving them to race.
            FocusManager.instance.primaryFocus?.unfocus();
            Navigator.of(sheetContext).pop();
          },
          child: FractionallySizedBox(
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
                            final currentUid = _firebaseAuth.currentUser?.uid;
                            return Column(
                              children: docs.map((doc) {
                                final data = doc.data();
                                final commentAuthorId =
                                    data['authorId']?.toString() ?? '';
                                final author = _communityAuthorName(
                                  commentAuthorId,
                                  data['authorName']?.toString() ?? 'Hiker',
                                );
                                final content =
                                    data['content']?.toString() ?? '';
                                final isOwnComment =
                                    currentUid != null &&
                                    commentAuthorId == currentUid;
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
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Row(
                                        children: [
                                          Expanded(
                                            child: Text(
                                              author,
                                              style: const TextStyle(
                                                color: Colors.white,
                                                fontWeight: FontWeight.w700,
                                              ),
                                            ),
                                          ),
                                          if (isOwnComment)
                                            GestureDetector(
                                              onTap: () => unawaited(
                                                _deleteCommunityComment(
                                                  post.id,
                                                  doc.id,
                                                ),
                                              ),
                                              child: Icon(
                                                Icons.delete_outline_rounded,
                                                size: 16,
                                                color: Colors.white.withValues(
                                                  alpha: 0.5,
                                                ),
                                              ),
                                            ),
                                        ],
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
                              FocusManager.instance.primaryFocus?.unfocus();
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

  String _provinceOrCityFromAddress(String address) {
    final parts = address
        .split(RegExp(r'[,\n]'))
        .map((part) => part.trim())
        .where((part) => part.isNotEmpty)
        .toList();
    final filtered = parts
        .where(
          (part) => !RegExp(
            r'^(philippines|ph|usa|united states|united states of america)',
            caseSensitive: false,
          ).hasMatch(part),
        )
        .toList();
    if (filtered.isEmpty) {
      return parts.isNotEmpty ? parts.last : '';
    }
    return filtered.last;
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
          fetchWeatherSnapshot: _fetchCurrentWeatherSnapshot,
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
    unawaited(_recordHikeAttempt(trail, session));
    unawaited(_updateLeaderboardStats(trail, session));
    _recordAgakHikeCompletion(trail, session);
    unawaited(_submitTrailRouteIfAccepted(trail, session));
    _pushPostHikeCompanionMessage(trail, session);
  }

  Future<_TrailRecordingDetails?> _askTrailRecordingDetails(
    _NearbyTrail trail,
  ) async {
    final nameController = TextEditingController(text: trail.name);
    final stationControllers = <TextEditingController>[];
    final recordedAt = DateTime.now();

    InputDecoration fieldDecoration(String hint) {
      return InputDecoration(
        hintText: hint,
        hintStyle: const TextStyle(color: Colors.white38),
        filled: true,
        fillColor: Colors.white.withValues(alpha: 0.06),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide.none,
        ),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 12,
          vertical: 10,
        ),
      );
    }

    final result = await showDialog<_TrailRecordingDetails>(
      context: context,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            void setStationCount(int next) {
              final clamped = next.clamp(0, 20);
              setDialogState(() {
                if (clamped > stationControllers.length) {
                  for (var i = stationControllers.length; i < clamped; i++) {
                    stationControllers.add(TextEditingController());
                  }
                } else {
                  while (stationControllers.length > clamped) {
                    stationControllers.removeLast().dispose();
                  }
                }
              });
            }

            return AlertDialog(
              backgroundColor: const Color(0xFF072117),
              title: const Text(
                'Record Trail Route?',
                style: TextStyle(color: Colors.white),
              ),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Keep GPS tracking active while you follow the real '
                      'trail. When you end the hike, this route is '
                      'automatically saved as a community recorded trail '
                      'that future hikers can see.',
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.86),
                      ),
                    ),
                    const SizedBox(height: 16),
                    const Text(
                      'Trail Name',
                      style: TextStyle(
                        color: Colors.white70,
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 6),
                    TextField(
                      controller: nameController,
                      style: const TextStyle(color: Colors.white),
                      decoration: fieldDecoration('e.g. Mt Apo via Kapatagan'),
                    ),
                    const SizedBox(height: 16),
                    Row(
                      children: [
                        const Expanded(
                          child: Text(
                            'Stations',
                            style: TextStyle(
                              color: Colors.white70,
                              fontSize: 12,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                        IconButton(
                          onPressed: stationControllers.isEmpty
                              ? null
                              : () => setStationCount(
                                  stationControllers.length - 1,
                                ),
                          icon: const Icon(
                            Icons.remove_circle_outline,
                            color: Colors.white70,
                          ),
                        ),
                        Text(
                          stationControllers.length.toString(),
                          style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        IconButton(
                          onPressed: stationControllers.length >= 20
                              ? null
                              : () => setStationCount(
                                  stationControllers.length + 1,
                                ),
                          icon: const Icon(
                            Icons.add_circle_outline,
                            color: Colors.white70,
                          ),
                        ),
                      ],
                    ),
                    for (var i = 0; i < stationControllers.length; i++) ...[
                      const SizedBox(height: 8),
                      TextField(
                        controller: stationControllers[i],
                        style: const TextStyle(color: Colors.white),
                        decoration: fieldDecoration('Station ${i + 1} name'),
                      ),
                    ],
                    const SizedBox(height: 16),
                    Row(
                      children: [
                        const Icon(
                          Icons.event_rounded,
                          size: 16,
                          color: Colors.white54,
                        ),
                        const SizedBox(width: 6),
                        Text(
                          'Date recorded: ${_formatDate(recordedAt)}',
                          style: TextStyle(
                            color: Colors.white.withValues(alpha: 0.7),
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () =>
                      _unfocusThenPop<_TrailRecordingDetails>(dialogContext),
                  child: const Text('Cancel'),
                ),
                ElevatedButton.icon(
                  onPressed: () {
                    final trailName = nameController.text.trim();
                    if (trailName.isEmpty) {
                      _showDashboardSnackBar('Enter a trail name to continue.');
                      return;
                    }
                    final stationNames = <String>[
                      for (var i = 0; i < stationControllers.length; i++)
                        stationControllers[i].text.trim().isEmpty
                            ? 'Station ${i + 1}'
                            : stationControllers[i].text.trim(),
                    ];
                    _unfocusThenPop<_TrailRecordingDetails>(
                      dialogContext,
                      _TrailRecordingDetails(
                        trailName: trailName,
                        stationNames: stationNames,
                        recordedAt: recordedAt,
                      ),
                    );
                  },
                  icon: const Icon(Icons.route_rounded),
                  label: const Text('Start Recording'),
                ),
              ],
            );
          },
        );
      },
    );

    nameController.dispose();
    for (final controller in stationControllers) {
      controller.dispose();
    }
    return result;
  }

  Future<void> _startTrailRecordingForMountain(_NearbyTrail trail) async {
    if (_firebaseAuth.currentUser == null) {
      _showDashboardSnackBar('Sign in before recording a trail route.');
      return;
    }

    final details = await _askTrailRecordingDetails(trail);
    if (details == null || !mounted) {
      return;
    }

    final communityTrail = await _fetchCommunityTrail(trail);
    if (!mounted) {
      return;
    }
    final session = await Navigator.of(context).push<_LiveHikeResult>(
      MaterialPageRoute<_LiveHikeResult>(
        builder: (_) => _HikingModeScreen(
          trail: trail,
          mapsApiKey: _mapsApiKey,
          communityTrail: communityTrail,
          recordingNewTrail: true,
          fetchWeatherSnapshot: _fetchCurrentWeatherSnapshot,
        ),
      ),
    );
    if (!mounted || session == null) {
      return;
    }
    // Recording a new trail always saves the walked route (below) even if
    // the hiker turns back early — that GPX data is useful either way. But
    // it only counts as a *completed* hike — the "Completed" list, the
    // milestone-tracking count, the trail's completed badge — when they
    // actually reached the summit, same bar as any other hike.
    setState(() {
      _rememberTrail(trail);
      if (session.reachedSummit) {
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
      }
    });
    unawaited(_recordHikeAttempt(trail, session));
    unawaited(_updateLeaderboardStats(trail, session));
    if (session.reachedSummit) {
      _recordAgakHikeCompletion(trail, session);
    }
    _pushPostHikeCompanionMessage(trail, session);
    await _submitTrailRouteIfAccepted(
      trail,
      session,
      askFirst: false,
      recordingDetails: details,
    );
    await _fetchCommunityTrail(trail, forceRefresh: true);
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

  List<LatLng> _downsampleRoutePoints(
    List<LatLng> points, {
    int maxPoints = 600,
  }) {
    if (points.length <= maxPoints) {
      return List<LatLng>.from(points);
    }
    final step = (points.length - 1) / (maxPoints - 1);
    final sampled = <LatLng>[];
    for (var i = 0; i < maxPoints; i++) {
      final index = (i * step).round().clamp(0, points.length - 1).toInt();
      sampled.add(points[index]);
    }
    sampled[0] = points.first;
    sampled[sampled.length - 1] = points.last;
    return sampled;
  }

  List<_TrailTrackPoint> _downsampleTrackPoints(
    List<_TrailTrackPoint> points, {
    int maxPoints = 900,
  }) {
    if (points.length <= maxPoints) {
      return List<_TrailTrackPoint>.from(points);
    }
    final step = (points.length - 1) / (maxPoints - 1);
    final sampled = <_TrailTrackPoint>[];
    for (var i = 0; i < maxPoints; i++) {
      final index = (i * step).round().clamp(0, points.length - 1).toInt();
      sampled.add(points[index]);
    }
    sampled[0] = points.first;
    sampled[sampled.length - 1] = points.last;
    return sampled;
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

  /// Blocks a bare "Start Hiking" tap on a mountain with no mapped or
  /// community route — asks up front instead of silently dropping the
  /// hiker into trail-recording mode with no warning. Returns true only
  /// when the hiker explicitly chose to record the trail; false/null
  /// (including barrier dismiss) means stay on the details sheet.
  Future<bool> _showNoTrailRouteDialog(String mountainName) {
    return _showAgakConfirmDialog(
      context,
      icon: Icons.signpost_rounded,
      title: 'No Trail Route Yet',
      message:
          "$mountainName doesn't have a mapped trail route yet. "
          'You can record your walked path as you hike so future '
          'hikers have a route to follow, or exit and pick another '
          'mountain.',
      cancelLabel: 'Exit',
      confirmLabel: 'Record Trail',
      confirmIcon: Icons.route_rounded,
    );
  }

  Future<bool> _showLogoutConfirmationDialog() {
    return _showAgakConfirmDialog(
      context,
      icon: Icons.logout_rounded,
      title: 'Sign Out?',
      message:
          "You'll need to sign back in to see your hikes, saved "
          'mountains, and messages from Kyrielle.',
      cancelLabel: 'Cancel',
      confirmLabel: 'Sign Out',
    );
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
    _LiveHikeResult hikeResult, {
    bool askFirst = true,
    _TrailRecordingDetails? recordingDetails,
  }) async {
    if (_firebaseAuth.currentUser == null) {
      return;
    }
    if (askFirst) {
      final shouldSubmit = await _askSubmitTrailRoute(trail);
      if (!shouldSubmit || !mounted) {
        return;
      }
    }
    try {
      final mountainKey = _mountainKeyForTrail(trail);
      final routePoints = _downsampleRoutePoints(hikeResult.routePoints);
      final trackPoints = _downsampleTrackPoints(hikeResult.trackPoints);
      if (routePoints.length < 2 || trackPoints.length < 2) {
        _showDashboardSnackBar('Route too short to submit.');
        return;
      }

      final estimatedQuality = _estimateSubmissionQuality(hikeResult);
      await OfflineActivityDatabase.instance.queueTrailSubmission({
        'mountainKey': mountainKey,
        'mountainName': trail.name,
        'trailName': recordingDetails?.trailName ?? trail.name,
        'stations': recordingDetails?.stationNames ?? const <String>[],
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
        'recordedAt': (recordingDetails?.recordedAt ?? DateTime.now())
            .toUtc()
            .toIso8601String(),
        'startedAt': hikeResult.startedAt.toUtc().toIso8601String(),
        'endedAt': hikeResult.endedAt.toUtc().toIso8601String(),
      });
      _communityTrailCache[mountainKey] = _CommunityTrailData(
        mountainKey: mountainKey,
        status: 'pending',
        points: routePoints,
        qualityScore: estimatedQuality,
        submissionCount: 1,
        source: 'local_pending_recording',
        updatedAt: DateTime.now(),
      );
      _showDashboardSnackBar(
        askFirst
            ? 'Trail route saved. It will upload automatically when online.'
            : 'Trail recording submitted. It will become a trail automatically.',
      );
      unawaited(
        _createUserNotification(
          type: 'trail',
          title: 'Trail Recording Saved',
          body: '${trail.name} was saved and will upload automatically.',
        ),
      );
      unawaited(_refreshPendingTrailSubmissions());
      unawaited(ActivitySyncService.shared.syncPendingActivities());
    } catch (_) {
      _showDashboardSnackBar('Unable to save the trail submission locally.');
    }
  }

  /// The durable, per-hike record — one Firestore document per hike
  /// *attempt*, completed or not. Unlike the old setup (an in-memory list
  /// that reset to empty on every app restart, plus a bare Firestore
  /// counter with no records behind it), this is the actual source of
  /// truth: it survives restarts and reinstalls, and every other "how many
  /// hikes" number in the app gets reconciled against it.
  Future<void> _recordHikeAttempt(
    _NearbyTrail trail,
    _LiveHikeResult session,
  ) async {
    final user = _firebaseAuth.currentUser;
    if (user == null) {
      return;
    }
    try {
      await _firestore
          .collection('users')
          .doc(user.uid)
          .collection('hikes')
          .add({
            'placeId': trail.placeId,
            'mountainName': trail.name,
            'address': trail.address,
            'lat': trail.location.latitude,
            'lon': trail.location.longitude,
            'provinceOrCity': trail.provinceOrCity,
            'difficulty': trail.difficulty,
            'status': trail.status,
            'description': trail.description,
            'distanceKm': session.distanceKm,
            'durationSeconds': session.duration.inSeconds,
            'elevationGainMasl': session.elevationGainMasl,
            'maxElevationMasl': session.maxElevationMasl,
            'checkpointsReached': session.checkpointsReached,
            'totalCheckpoints': session.totalCheckpoints,
            'reachedSummit': session.reachedSummit,
            'startedAt': session.startedAt.toUtc().toIso8601String(),
            'endedAt': session.endedAt.toUtc().toIso8601String(),
            'completedAt': FieldValue.serverTimestamp(),
          });
    } catch (error) {
      debugPrint('Failed to record hike attempt: $error');
    }
  }

  /// Loads real hike history from Firestore on dashboard start, replacing
  /// whatever was in the in-memory `_completedHikeSessions`/
  /// `_completedTrailIds` (empty on a fresh launch) with what actually
  /// happened. Also reconciles the leaderboard's `completedMountains`
  /// counter to match this real count — that counter used to drift from
  /// reality (it incremented on every ended hike regardless of summit,
  /// for a long stretch), and had nothing behind it to correct against;
  /// now it's recomputed from the real records every time the dashboard
  /// loads instead of trusting an independently-incrementing number.
  Future<void> _loadCompletedHikesFromFirestore() async {
    final user = _firebaseAuth.currentUser;
    if (user == null) {
      return;
    }
    try {
      final snapshot = await _firestore
          .collection('users')
          .doc(user.uid)
          .collection('hikes')
          .orderBy('completedAt', descending: true)
          .limit(300)
          .get();
      final sessions = <_CompletedHikeSession>[];
      for (final doc in snapshot.docs) {
        final data = doc.data();
        final distanceKm = (data['distanceKm'] as num?)?.toDouble() ?? 0;
        // Belt-and-suspenders against records written before the
        // meaningful-distance guard existed (a summit credited on the
        // very first GPS fix, before any real walking) — require actual
        // distance covered, not just the stored flag.
        if (data['reachedSummit'] != true || distanceKm < 0.1) {
          continue;
        }
        final completedAtField = data['completedAt'];
        final completedAt = completedAtField is Timestamp
            ? completedAtField.toDate()
            : DateTime.tryParse(data['endedAt']?.toString() ?? '') ??
                  DateTime.now();
        sessions.add(
          _CompletedHikeSession(
            trail: _NearbyTrail(
              placeId: data['placeId']?.toString() ?? doc.id,
              name: data['mountainName']?.toString() ?? 'Unknown Mountain',
              address: data['address']?.toString() ?? '',
              location: LatLng(
                (data['lat'] as num?)?.toDouble() ?? 0,
                (data['lon'] as num?)?.toDouble() ?? 0,
              ),
              provinceOrCity: data['provinceOrCity']?.toString(),
              difficulty: data['difficulty']?.toString(),
              status: data['status']?.toString(),
              description: data['description']?.toString(),
            ),
            completedAt: completedAt,
            distanceKm: distanceKm,
            duration: Duration(
              seconds: (data['durationSeconds'] as num?)?.toInt() ?? 0,
            ),
            elevationGainMasl:
                (data['elevationGainMasl'] as num?)?.toInt() ?? 0,
            maxElevationMasl: (data['maxElevationMasl'] as num?)?.toInt() ?? 0,
            checkpointsReached:
                (data['checkpointsReached'] as num?)?.toInt() ?? 0,
            totalCheckpoints: (data['totalCheckpoints'] as num?)?.toInt() ?? 0,
            reachedSummit: true,
          ),
        );
      }
      if (!mounted) {
        return;
      }
      setState(() {
        _completedHikeSessions
          ..clear()
          ..addAll(sessions);
        _completedTrailIds
          ..clear()
          ..addAll(sessions.map((session) => session.trail.placeId));
      });
      unawaited(_reconcileLeaderboardCompletedCount(sessions.length));
    } catch (error) {
      debugPrint('Failed to load completed hikes: $error');
    }
  }

  Future<void> _reconcileLeaderboardCompletedCount(int trueCount) async {
    final user = _firebaseAuth.currentUser;
    if (user == null) {
      return;
    }
    try {
      await _firestore.collection('leaderboard').doc(user.uid).set({
        'completedMountains': trueCount,
      }, SetOptions(merge: true));
    } catch (error) {
      debugPrint('Failed to reconcile leaderboard completed count: $error');
    }
  }

  Future<void> _updateLeaderboardStats(
    _NearbyTrail trail,
    _LiveHikeResult hikeResult,
  ) async {
    final user = _firebaseAuth.currentUser;
    if (user == null) {
      return;
    }
    final mountainKey = _mountainKeyForTrail(trail);
    await _firestore.collection('leaderboard').doc(user.uid).set({
      'userId': user.uid,
      'displayName': _communityDisplayName(),
      'accountType': _accountType,
      'completedMountains': FieldValue.increment(
        hikeResult.reachedSummit ? 1 : 0,
      ),
      'summitsReached': FieldValue.increment(hikeResult.reachedSummit ? 1 : 0),
      'totalDistanceKm': FieldValue.increment(hikeResult.distanceKm),
      'lastMountainName': trail.name,
      'lastMountainKey': mountainKey,
      'completedTrailKeys': FieldValue.arrayUnion([mountainKey]),
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  /// Records a completed hike in AGAK's local (offline) behavior history —
  /// separate from `_recordHikeAttempt`'s Firestore record (the actual
  /// source of truth for "how many hikes have I completed"), this one
  /// exists purely to feed the on-device recommendation engine and trigger
  /// a milestone celebration when one is hit.
  /// Triggers Kyrielle's milestone celebration when this genuinely-reached
  /// summit crosses a milestone threshold. The count comes from
  /// `_completedHikeSessions` — by the time this runs, the caller has
  /// already inserted this session into it, and that list is itself loaded
  /// from `users/{uid}/hikes` in Firestore (see
  /// `_loadCompletedHikesFromFirestore`), the same real record
  /// `AgakController` reads for its recommendation engine. One source of
  /// truth, not a separate on-device tally that can drift from it.
  void _recordAgakHikeCompletion(_NearbyTrail trail, _LiveHikeResult session) {
    final milestone = detectCompletedHikeMilestone(
      _completedHikeSessions.length,
    );
    unawaited(
      AgakController.instance.refresh(force: true, milestone: milestone),
    );
  }

  /// What Kyrielle says on the dashboard right after a hike ends — pushed
  /// as a [AgakTipScope.global] tip so it actually shows on
  /// [AgakFloatingCompanion] (unlike every tip Hiking Mode pushes during
  /// the hike itself, which is [AgakTipScope.hikingOnly] and filtered out
  /// there). Distinct message depending on whether the summit was actually
  /// reached, so ending a hike early doesn't get the same congratulations
  /// as genuinely finishing it.
  void _pushPostHikeCompanionMessage(
    _NearbyTrail trail,
    _LiveHikeResult session,
  ) {
    if (session.reachedSummit) {
      AgakTipBus.instance.push(
        AgakTip(
          emotion: AgakEmotionState.celebration,
          message:
              'CAW-CAW! You completed ${trail.name} — congratulations! '
              'Rest up and hydrate. Whenever you\'re ready, I\'ve got more '
              'mountains for you.',
        ),
      );
    } else {
      AgakTipBus.instance.push(
        AgakTip(
          emotion: AgakEmotionState.encouragement,
          message:
              "Welcome back! How'd ${trail.name} go — you doing okay? "
              "Whenever you're ready, let's plan what's next.",
        ),
      );
    }
  }

  Future<void> _createUserNotification({
    required String type,
    required String title,
    required String body,
  }) async {
    final user = _firebaseAuth.currentUser;
    if (user == null) {
      return;
    }
    await _firestore
        .collection('users')
        .doc(user.uid)
        .collection('notifications')
        .add({
          'type': type,
          'title': title,
          'body': body,
          'read': false,
          'createdAt': FieldValue.serverTimestamp(),
        });
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

  /// Best-effort "is it bad outside right now, near the user" check that
  /// feeds AGAK's weather-warning mood. Separate from the hike-planning
  /// forecast above (which looks up a specific trail + future date) —
  /// this looks at the user's live location, right now, and silently
  /// no-ops on any failure so it can never block the companion greeting.
  Future<void> _refreshAgakAmbientWeather() async {
    try {
      if (!_locationGranted || _myLocationCenter == null) {
        return;
      }
      await _loadWeatherApiKey();
      if (_weatherApiKey.isEmpty) {
        return;
      }
      final snapshot = await _fetchCurrentWeatherSnapshot(_myLocationCenter!);
      AgakController.instance.updateAmbientWeather(snapshot);
      if (snapshot != null) {
        final AgakEmotionState emotion;
        final String message;
        if (snapshot.isSevere) {
          emotion = AgakEmotionState.discouraging;
          message = '${snapshot.headline}. Be careful out there today!';
        } else if (snapshot.isCaution) {
          emotion = AgakEmotionState.discouraging;
          message =
              "Today's weather: ${snapshot.headline}. It could turn to "
              'rain, so keep an eye on the sky and bring rain gear just '
              'in case.';
        } else if (snapshot.isSunny) {
          emotion = AgakEmotionState.sunny;
          message =
              "Today's weather: ${snapshot.headline}. Great day for a hike!";
        } else {
          emotion = AgakEmotionState.encouragement;
          message =
              "Today's weather: ${snapshot.headline}. Great day for a hike!";
        }
        AgakTipBus.instance.push(AgakTip(emotion: emotion, message: message));
      }
    } catch (error) {
      debugPrint('AGAK ambient weather check failed: $error');
    }
  }

  // Delegates to the shared WeatherService, which calls the
  // fetchWeatherSnapshot Cloud Function instead of hitting Google directly
  // — the Weather API key and the risk-classification logic both moved
  // server-side (functions/index.js), so this no longer needs
  // _weatherApiKey at all. Kept as its own named method (rather than
  // repointing every call site at WeatherService directly) purely so the
  // several existing callers below don't all need touching.
  Future<AgakWeatherSnapshot?> _fetchCurrentWeatherSnapshot(
    LatLng location,
  ) {
    return _weatherService.fetchCurrentSnapshot(
      latitude: location.latitude,
      longitude: location.longitude,
    );
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
        weatherCode == 3 || // overcast — real rain risk, not a "clear" day
        rainChance >= 50 ||
        precipitation >= 5 ||
        windSpeed >= 30) {
      return _HikeWeatherRisk.caution;
    }
    // Partly cloudy/partly sunny (weatherCode 2) is NOT auto-caution — it's
    // a normal, hikeable sky. Only the actual rain/wind numbers above (or
    // a wetter/overcast code) should push it into caution; otherwise a
    // "Partly sunny" reading would always show the rain-gear warning even
    // with a near-zero chance of rain.
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

  // Rough max footprint (bubble + gap + character) used only to keep the
  // draggable companion fully on screen — doesn't need to be pixel-exact.
  static const Size _agakFootprint = Size(280, 350);

  Offset? _agakOffset;

  @override
  Widget build(BuildContext context) {
    final keyboardOpen = MediaQuery.of(context).viewInsets.bottom > 0;
    return Scaffold(
      body: LayoutBuilder(
        builder: (context, constraints) {
          final bodySize = constraints.biggest;
          _agakOffset ??= Offset(
            bodySize.width - _agakFootprint.width - 12,
            bodySize.height - _agakFootprint.height - 140,
          );
          return Stack(
            children: [
              _buildActiveTab(keyboardOpen),
              if (!keyboardOpen)
                Positioned(
                  left: _agakOffset!.dx,
                  top: _agakOffset!.dy,
                  child: AgakFloatingCompanion(
                    onTap: _openKyrielleCompanion,
                    onDragDelta: (delta) {
                      setState(() {
                        final maxX = bodySize.width - _agakFootprint.width - 4;
                        final maxY =
                            bodySize.height - _agakFootprint.height - 4;
                        _agakOffset = Offset(
                          (_agakOffset!.dx + delta.dx).clamp(
                            4.0,
                            maxX < 4.0 ? 4.0 : maxX,
                          ),
                          (_agakOffset!.dy + delta.dy).clamp(
                            4.0,
                            maxY < 4.0 ? 4.0 : maxY,
                          ),
                        );
                      });
                    },
                  ),
                ),
            ],
          );
        },
      ),
      bottomNavigationBar: keyboardOpen ? null : _buildBottomNavigationBar(),
    );
  }

  Widget _buildActiveTab(bool keyboardOpen) {
    switch (_selectedNavIndex) {
      case 1:
        return _buildMyHikesTab();
      case 2:
        return _buildCommunityTab();
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
        if (index == 1) {
          unawaited(_refreshPendingTrailSubmissions());
        }
      },
      type: BottomNavigationBarType.fixed,
      backgroundColor: Colors.white,
      selectedItemColor: AgakColors.maroon,
      unselectedItemColor: AgakColors.ink.withValues(alpha: 0.5),
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

  Future<void> _openAppMenuSheet() async {
    await showGeneralDialog<void>(
      context: context,
      barrierDismissible: true,
      barrierLabel: 'Close menu',
      barrierColor: Colors.black.withValues(alpha: 0.48),
      transitionDuration: const Duration(milliseconds: 260),
      pageBuilder: (dialogContext, animation, secondaryAnimation) {
        final width = MediaQuery.of(dialogContext).size.width;
        return Align(
          alignment: Alignment.centerLeft,
          child: Material(
            color: Colors.transparent,
            child: SafeArea(
              child: Container(
                width: math.min(width * 0.82, 340),
                height: double.infinity,
                margin: const EdgeInsets.fromLTRB(10, 10, 0, 10),
                padding: const EdgeInsets.fromLTRB(18, 16, 18, 18),
                decoration: BoxDecoration(
                  color: AgakColors.cream,
                  borderRadius: BorderRadius.circular(28),
                  border: Border.all(
                    color: AgakColors.ink.withValues(alpha: 0.12),
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.2),
                      blurRadius: 28,
                      offset: const Offset(12, 0),
                    ),
                  ],
                ),
                child: Column(
                  children: [
                    Row(
                      children: [
                        const Text(
                          'Menu',
                          style: TextStyle(
                            color: AgakColors.ink,
                            fontSize: 24,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                        const Spacer(),
                        IconButton(
                          tooltip: 'Close menu',
                          onPressed: () => Navigator.of(dialogContext).pop(),
                          icon: Icon(
                            Icons.close_rounded,
                            color: AgakColors.ink.withValues(alpha: 0.68),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 18),
                    _menuUserHeader(),
                    const SizedBox(height: 28),
                    _appMenuItem(
                      icon: Icons.event_available_rounded,
                      iconColor: const Color(0xFF53D97A),
                      title: 'My Scheduled Hikes',
                      subtitle: 'Upcoming hikes and packing lists',
                      onTap: () {
                        Navigator.of(dialogContext).pop();
                        Navigator.of(context).push(
                          MaterialPageRoute<void>(
                            builder: (context) => AgakScheduledHikesScreen(
                              onScheduleNewHike: _openScheduleHikeFromCatalog,
                            ),
                          ),
                        );
                      },
                    ),
                    _appMenuItem(
                      icon: Icons.leaderboard_rounded,
                      iconColor: const Color(0xFFFFD76A),
                      title: 'Leaderboard',
                      subtitle: 'Top hikers',
                      onTap: () {
                        Navigator.of(dialogContext).pop();
                        _openLeaderboardSheet();
                      },
                    ),
                    _appMenuItem(
                      icon: Icons.health_and_safety_rounded,
                      iconColor: const Color(0xFFFF7A7A),
                      title: 'Safety Guide',
                      subtitle: 'Hiking safety content',
                      onTap: () {
                        Navigator.of(dialogContext).pop();
                        _openSafetyGuideSheet();
                      },
                    ),
                    _appMenuItem(
                      icon: Icons.info_outline_rounded,
                      iconColor: const Color(0xFF48D1FF),
                      title: 'About Agakbay',
                      subtitle: 'App information',
                      onTap: () {
                        Navigator.of(dialogContext).pop();
                        _openAboutAgakbaySheet();
                      },
                    ),
                    const Spacer(),
                    Divider(color: AgakColors.ink.withValues(alpha: 0.1)),
                    _appMenuItem(
                      icon: Icons.person_outline_rounded,
                      iconColor: const Color(0xFF7CF9A2),
                      title: 'Profile',
                      subtitle: 'Account, safety, and trail activity',
                      onTap: () {
                        Navigator.of(dialogContext).pop();
                        setState(() => _selectedNavIndex = 3);
                      },
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
      transitionBuilder: (context, animation, secondaryAnimation, child) {
        final curved = CurvedAnimation(
          parent: animation,
          curve: Curves.easeOut,
        );
        return SlideTransition(
          position: Tween<Offset>(
            begin: const Offset(-1, 0),
            end: Offset.zero,
          ).animate(curved),
          child: child,
        );
      },
    );
  }

  Widget _menuUserHeader() {
    final displayName = _communityDisplayName();
    final photoUrl = _profilePhotoUrl();
    return Row(
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(14),
          child: Container(
            width: 56,
            height: 56,
            decoration: BoxDecoration(gradient: _avatarGradient(displayName)),
            child: photoUrl.isEmpty
                ? Center(
                    child: Text(
                      _communityAvatarSeed(displayName),
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 22,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  )
                : Image.network(photoUrl, fit: BoxFit.cover),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                displayName,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: AgakColors.ink,
                  fontSize: 17,
                  fontWeight: FontWeight.w900,
                ),
              ),
              const SizedBox(height: 3),
              Text(
                _firebaseAuth.currentUser?.email ?? 'No email',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: AgakColors.ink.withValues(alpha: 0.58),
                  fontSize: 12,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _appMenuItem({
    required IconData icon,
    required Color iconColor,
    required String title,
    required String subtitle,
    required VoidCallback onTap,
  }) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 9),
          child: Row(
            children: [
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  color: iconColor.withValues(alpha: 0.14),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Icon(icon, color: iconColor),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(
                        color: AgakColors.ink,
                        fontSize: 15,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: AgakColors.ink.withValues(alpha: 0.62),
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
              Icon(
                Icons.chevron_right_rounded,
                color: AgakColors.ink.withValues(alpha: 0.35),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _openLeaderboardSheet() {
    return _openDatabaseSheet(
      title: 'Leaderboard',
      icon: Icons.leaderboard_rounded,
      child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
        stream: _firestore
            .collection('leaderboard')
            .orderBy('completedMountains', descending: true)
            .limit(50)
            .snapshots(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const _SheetLoading();
          }
          final docs = snapshot.data?.docs ?? const [];
          if (docs.isEmpty) {
            return _sheetEmptyState(
              icon: Icons.leaderboard_rounded,
              title: 'No rankings yet',
              message: 'Leaderboard records appear after users finish hikes.',
            );
          }
          return Column(
            children: [
              for (var index = 0; index < docs.length; index++) ...[
                _leaderboardRow(index + 1, docs[index].data()),
                if (index != docs.length - 1)
                  Divider(color: AgakColors.ink.withValues(alpha: 0.08)),
              ],
            ],
          );
        },
      ),
    );
  }

  Widget _leaderboardRow(int rank, Map<String, dynamic> data) {
    final name = data['displayName']?.toString() ?? 'Hiker';
    final role = data['accountType']?.toString() == 'tour_guide'
        ? 'Tour Guide'
        : 'Hiker';
    final completed = (data['completedMountains'] as num?)?.toInt() ?? 0;
    final summits = (data['summitsReached'] as num?)?.toInt() ?? 0;
    final distance = (data['totalDistanceKm'] as num?)?.toDouble() ?? 0;
    final color = rank == 1
        ? AgakColors.goldDark
        : rank == 2
        ? AgakColors.ink.withValues(alpha: 0.45)
        : rank == 3
        ? const Color(0xFFB2703A)
        : AgakColors.olive;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Row(
        children: [
          Container(
            width: 38,
            height: 38,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.16),
              borderRadius: BorderRadius.circular(13),
            ),
            child: Text(
              '#$rank',
              style: TextStyle(color: color, fontWeight: FontWeight.w900),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: AgakColors.ink,
                    fontSize: 15,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  '$role - ${distance.toStringAsFixed(1)} km - $summits summits',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: AgakColors.ink.withValues(alpha: 0.6),
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ),
          Text(
            '$completed',
            style: const TextStyle(
              color: AgakColors.maroon,
              fontSize: 24,
              fontWeight: FontWeight.w900,
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _openSafetyGuideSheet() {
    return _openDatabaseContentSheet(
      title: 'Safety Guide',
      icon: Icons.health_and_safety_rounded,
      docId: 'safety_guide',
      emptyTitle: 'No safety guide yet',
      emptyMessage:
          'Add app_content/safety_guide in Firestore with sections to show it here.',
    );
  }

  Future<void> _openAboutAgakbaySheet() {
    return _openDatabaseContentSheet(
      title: 'About Agakbay',
      icon: Icons.info_outline_rounded,
      docId: 'about_agakbay',
      emptyTitle: 'No about content yet',
      emptyMessage:
          'Add app_content/about_agakbay in Firestore to show app information here.',
    );
  }

  Future<void> _openDatabaseContentSheet({
    required String title,
    required IconData icon,
    required String docId,
    required String emptyTitle,
    required String emptyMessage,
  }) {
    return _openDatabaseSheet(
      title: title,
      icon: icon,
      child: StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
        stream: _firestore.collection('app_content').doc(docId).snapshots(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const _SheetLoading();
          }
          final data = snapshot.data?.data();
          if (data == null) {
            return _sheetEmptyState(
              icon: icon,
              title: emptyTitle,
              message: emptyMessage,
            );
          }
          final body = data['body']?.toString() ?? '';
          final sections = data['sections'];
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (body.trim().isNotEmpty) ...[
                Text(
                  body,
                  style: TextStyle(
                    color: AgakColors.ink.withValues(alpha: 0.82),
                    height: 1.38,
                  ),
                ),
                const SizedBox(height: 14),
              ],
              if (sections is List)
                for (final section in sections)
                  if (section is Map)
                    _contentSectionCard(
                      title: section['title']?.toString() ?? 'Section',
                      body: section['body']?.toString() ?? '',
                    ),
            ],
          );
        },
      ),
    );
  }

  Widget _contentSectionCard({required String title, required String body}) {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(13),
      decoration: BoxDecoration(
        color: AgakColors.ink.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AgakColors.ink.withValues(alpha: 0.1)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(
              color: AgakColors.ink,
              fontWeight: FontWeight.w900,
            ),
          ),
          if (body.trim().isNotEmpty) ...[
            const SizedBox(height: 5),
            Text(
              body,
              style: TextStyle(
                color: AgakColors.ink.withValues(alpha: 0.74),
                height: 1.32,
              ),
            ),
          ],
        ],
      ),
    );
  }

  Future<void> _openNotificationsSheet() {
    final user = _firebaseAuth.currentUser;
    return _openDatabaseSheet(
      title: 'Notifications',
      icon: Icons.notifications_none_rounded,
      child: user == null
          ? _sheetEmptyState(
              icon: Icons.login_rounded,
              title: 'Sign in required',
              message: 'Sign in to see trail, SOS, and safety notifications.',
            )
          : StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
              stream: _firestore
                  .collection('users')
                  .doc(user.uid)
                  .collection('notifications')
                  .orderBy('createdAt', descending: true)
                  .limit(50)
                  .snapshots(),
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const _SheetLoading();
                }
                final docs = snapshot.data?.docs ?? const [];
                if (docs.isEmpty) {
                  return _sheetEmptyState(
                    icon: Icons.notifications_none_rounded,
                    title: 'No notifications yet',
                    message:
                        'Trail checks, SOS room updates, and safety alerts will appear here.',
                  );
                }
                return Column(
                  children: [
                    for (var index = 0; index < docs.length; index++) ...[
                      _notificationRow(docs[index].data()),
                      if (index != docs.length - 1)
                        Divider(color: Colors.white.withValues(alpha: 0.08)),
                    ],
                  ],
                );
              },
            ),
    );
  }

  Widget _notificationRow(Map<String, dynamic> data) {
    final title = data['title']?.toString() ?? 'Notification';
    final body = data['body']?.toString() ?? '';
    final type = data['type']?.toString() ?? 'info';
    final createdAt = data['createdAt'];
    final color = switch (type) {
      'sos' => const Color(0xFFFF7A7A),
      'trail' => const Color(0xFF7CF9A2),
      'safety' => const Color(0xFFFFD76A),
      'comment' => const Color(0xFF48D1FF),
      _ => const Color(0xFF48D1FF),
    };
    final icon = switch (type) {
      'sos' => Icons.sos_rounded,
      'trail' => Icons.route_rounded,
      'comment' => Icons.chat_bubble_rounded,
      'safety' => Icons.health_and_safety_rounded,
      _ => Icons.notifications_none_rounded,
    };
    DateTime? date;
    if (createdAt is Timestamp) {
      date = createdAt.toDate();
    }

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.14),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Icon(icon, color: color, size: 21),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    color: AgakColors.ink,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                if (body.trim().isNotEmpty) ...[
                  const SizedBox(height: 3),
                  Text(
                    body,
                    style: TextStyle(
                      color: AgakColors.ink.withValues(alpha: 0.7),
                      height: 1.3,
                    ),
                  ),
                ],
                if (date != null) ...[
                  const SizedBox(height: 5),
                  Text(
                    _formatDate(date),
                    style: TextStyle(
                      color: AgakColors.ink.withValues(alpha: 0.48),
                      fontSize: 11,
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

  Future<void> _openDatabaseSheet({
    required String title,
    required IconData icon,
    required Widget child,
  }) {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) {
        return DraggableScrollableSheet(
          initialChildSize: 0.72,
          minChildSize: 0.45,
          maxChildSize: 0.92,
          expand: false,
          builder: (context, scrollController) {
            return Container(
              decoration: const BoxDecoration(
                color: AgakColors.cream,
                borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
              ),
              child: Column(
                children: [
                  const SizedBox(height: 10),
                  Container(
                    width: 44,
                    height: 4,
                    decoration: BoxDecoration(
                      color: AgakColors.ink.withValues(alpha: 0.18),
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 12, 8, 8),
                    child: Row(
                      children: [
                        Icon(icon, color: AgakColors.maroon),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            title,
                            style: const TextStyle(
                              color: AgakColors.ink,
                              fontSize: 22,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                        ),
                        IconButton(
                          onPressed: () => Navigator.of(sheetContext).pop(),
                          icon: Icon(
                            Icons.close_rounded,
                            color: AgakColors.ink.withValues(alpha: 0.68),
                          ),
                        ),
                      ],
                    ),
                  ),
                  Expanded(
                    child: ListView(
                      controller: scrollController,
                      padding: const EdgeInsets.fromLTRB(16, 4, 16, 20),
                      children: [child],
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

  Widget _sheetEmptyState({
    required IconData icon,
    required String title,
    required String message,
  }) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: AgakColors.ink.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AgakColors.ink.withValues(alpha: 0.1)),
      ),
      child: Column(
        children: [
          Icon(icon, color: AgakColors.maroon, size: 42),
          const SizedBox(height: 10),
          Text(
            title,
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: AgakColors.ink,
              fontSize: 17,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 5),
          Text(
            message,
            textAlign: TextAlign.center,
            style: TextStyle(
              color: AgakColors.ink.withValues(alpha: 0.68),
              height: 1.35,
            ),
          ),
        ],
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
                    AgakColors.cream.withValues(alpha: 0.55),
                    Colors.transparent,
                    AgakColors.cream.withValues(alpha: 0.78),
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
                    _circleButton(icon: Icons.menu, onTap: _openAppMenuSheet),
                    const SizedBox(width: 10),
                    const Text(
                      'Agakbay',
                      style: TextStyle(
                        color: AgakColors.ink,
                        fontSize: 30,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const Spacer(),
                    _circleButton(
                      icon: Icons.chat_bubble_outline_rounded,
                      onTap: _openAgakCompanion,
                    ),
                    const SizedBox(width: 10),
                    _circleButton(
                      icon: Icons.notifications_none_rounded,
                      onTap: _openNotificationsSheet,
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Container(
                  height: 48,
                  padding: const EdgeInsets.symmetric(horizontal: 14),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.85),
                    borderRadius: BorderRadius.circular(18),
                    border: Border.all(
                      color: AgakColors.ink.withValues(alpha: 0.18),
                    ),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        Icons.search_rounded,
                        color: AgakColors.ink.withValues(alpha: 0.7),
                        size: 22,
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: TextField(
                          controller: _searchController,
                          textInputAction: TextInputAction.search,
                          onSubmitted: (_) => _searchOnMap(),
                          style: const TextStyle(
                            color: AgakColors.ink,
                            fontSize: 16,
                          ),
                          decoration: InputDecoration(
                            isCollapsed: true,
                            hintText: 'Search place or mountain...',
                            hintStyle: TextStyle(
                              color: AgakColors.ink.withValues(alpha: 0.5),
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
                                        color: AgakColors.maroon,
                                      ),
                                    )
                                  : const Icon(
                                      Icons.arrow_forward_rounded,
                                      color: AgakColors.maroon,
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
                      color: AgakColors.maroon.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: AgakColors.maroon.withValues(alpha: 0.5),
                      ),
                    ),
                    child: Text(
                      _locationMessage!,
                      style: const TextStyle(color: AgakColors.maroon),
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
      constraints: BoxConstraints(
        maxHeight: _nearbyCardCollapsed ? double.infinity : 330,
      ),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.fromLTRB(14, 14, 14, 10),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.92),
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: AgakColors.ink.withValues(alpha: 0.12)),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.18),
              blurRadius: 22,
              offset: const Offset(0, 12),
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                const Text(
                  'Nearby Trails',
                  style: TextStyle(
                    color: AgakColors.ink,
                    fontSize: 19,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const Spacer(),
                if (!_nearbyCardCollapsed)
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
                            color: AgakColors.maroon,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ),
                  ),
                Material(
                  color: Colors.transparent,
                  child: InkWell(
                    onTap: () {
                      setState(() {
                        _nearbyCardCollapsed = !_nearbyCardCollapsed;
                      });
                    },
                    borderRadius: BorderRadius.circular(20),
                    child: Padding(
                      padding: const EdgeInsets.all(4),
                      child: Icon(
                        _nearbyCardCollapsed
                            ? Icons.keyboard_arrow_up_rounded
                            : Icons.keyboard_arrow_down_rounded,
                        color: AgakColors.ink.withValues(alpha: 0.7),
                      ),
                    ),
                  ),
                ),
              ],
            ),
            if (!_nearbyCardCollapsed) ...[
              const SizedBox(height: 6),
              Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  _nearbyAnchorLabel(),
                  style: TextStyle(
                    color: AgakColors.ink.withValues(alpha: 0.7),
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
          ],
        ),
      ),
    );
  }

  Future<void> _openHikeAssistant() async {
    await Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (_) => _HikeAssistantScreen(
          initialTrail: _searchedTrailAnchor,
          searchMountainInMindanao: (query) async {
            final result = await _searchMountainInMindanao(query);
            unawaited(
              AgakBehaviorDatabase.instance.logSearch(
                query: query,
                matchedMountainId: result == null
                    ? null
                    : buildMountainMatchKey(
                        name: result.name,
                        region: result.provinceOrCity,
                      ),
                matchedMountainName: result?.name,
                source: 'assistant_chat',
              ),
            );
            return result;
          },
          fetchMountainOrganizers: _fetchMountainOrganizers,
        ),
      ),
    );
  }

  Future<void> _openAgakCompanion() async {
    await Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (_) => AgakCompanionScreen(
          openHikeAssistantChat: () => _openHikeAssistant(),
        ),
      ),
    );
  }

  /// Tries a quick AI rephrase of [deterministic] using
  /// [aiSystemInstruction]/[aiPrompt], falling back to [deterministic]
  /// verbatim if the AI is unavailable or the call fails. Used so
  /// weather/location answers always have a solid, correct answer on
  /// their own and only get nicer phrasing when the AI actually comes
  /// through — never depending on it to produce the answer at all.
  Future<String> _polishWithAi({
    required String deterministic,
    required String aiSystemInstruction,
    required String aiPrompt,
  }) async {
    if (_kyrielleAiApiKey.isEmpty) {
      return deterministic;
    }
    final aiAnswer = await fetchGeminiResponse(
      apiKey: _kyrielleAiApiKey,
      systemInstruction: aiSystemInstruction,
      prompt: aiPrompt,
    );
    return aiAnswer.isNotEmpty ? aiAnswer : deterministic;
  }

  /// Answers a weather question directly from a live weather snapshot.
  /// Unlike routing weather data through the general AI Q&A pipeline as
  /// mere "context" (which leaves the hiker with nothing if that AI call
  /// fails), this always has something honest and useful to say on its
  /// own — the AI is only asked to make the phrasing nicer when it's
  /// actually reachable, never relied on to relay the data at all.
  Future<String> _kyrielleWeatherAnswer(String hikerName) async {
    if (_myLocationCenter == null) {
      await _loadCurrentLocation();
    }
    final location = _myLocationCenter;
    if (location == null) {
      return "I can't see your location right now, $hikerName — turn on "
          'location access in Agakbay and ask again, or check a weather '
          'app in the meantime.';
    }

    await _loadWeatherApiKey();
    AgakWeatherSnapshot? snapshot;
    if (_weatherApiKey.isNotEmpty) {
      try {
        snapshot = await _fetchCurrentWeatherSnapshot(location);
      } catch (_) {
        snapshot = null;
      }
    }
    if (snapshot == null) {
      return "I couldn't pull live weather just now, $hikerName — worth "
          'checking the sky or a weather app before you head out. Ask me '
          'again in a bit and I\'ll try again.';
    }

    final deterministicAnswer = snapshot.isSevere
        ? "It's looking rough right now — ${snapshot.headline}. I'd hold "
              'off or pick an easier day for this one, $hikerName.'
        : snapshot.isCaution
        ? "It's a bit unsettled — ${snapshot.headline}. Still hikeable, "
              'just keep an eye on the sky and bring rain gear.'
        : 'Conditions look good — ${snapshot.headline}. Solid day to be '
              'out there, $hikerName.';

    final severityLabel = snapshot.isSevere
        ? 'severe — advise real caution or postponing the hike'
        : snapshot.isCaution
        ? 'unsettled — worth a caution'
        : 'good hiking conditions';
    return _polishWithAi(
      deterministic: deterministicAnswer,
      aiSystemInstruction:
          'You are Kyrielle, a capable AI trail companion. Rephrase '
          'the given live weather data into 1-3 natural, encouraging '
          'sentences addressed to $hikerName by name. Do not invent '
          'any details beyond what is given.',
      aiPrompt:
          "Live weather right now at the hiker's GPS location: "
          '${snapshot.headline} ($severityLabel).',
    );
  }

  /// Inside this radius of a real, findable mountain/trail point, the
  /// hiker is treated as being on that trail rather than merely near it.
  static const double _onTrailRadiusKm = 2.0;

  /// Runs the same nearby-mountain lookup [_loadNearbyTrails] uses (live
  /// Places search, falling back to a text search, falling back to
  /// Nominatim), so "is the hiker on a trail" and "what's the nearest
  /// hikeable mountain" both reuse the app's one real trail-finding path
  /// instead of a second, possibly-inconsistent one.
  Future<List<_NearbyTrail>> _findMountainsNear(
    LatLng center, {
    required double maxDistanceKm,
  }) async {
    await _loadMapsApiKey();
    List<_NearbyTrail> trails = const <_NearbyTrail>[];
    if (_mapsApiKey.isNotEmpty) {
      trails = await _fetchNearbyTrailsByDistance(
        center,
        maxDistanceKm: maxDistanceKm,
      );
    }
    if (trails.isEmpty && _mapsApiKey.isNotEmpty) {
      trails = await _fetchNearbyTrailsFromPlaces(
        center,
        maxDistanceKm: maxDistanceKm,
      );
    }
    if (trails.isEmpty) {
      trails = await _fetchNearbyTrailsFromNominatim(
        center,
        maxDistanceKm: maxDistanceKm,
      );
    }
    return trails;
  }

  /// Reverse-geocodes [point] to a human city/town/neighborhood label via
  /// Nominatim (same free OSM host [_fetchNearbyTrailsFromNominatim]
  /// already talks to, so this needs no new API key). Returns null if the
  /// lookup fails rather than guessing.
  Future<String?> _reverseGeocodeCityName(LatLng point) async {
    try {
      final uri = Uri.https('nominatim.openstreetmap.org', '/reverse', {
        'lat': '${point.latitude}',
        'lon': '${point.longitude}',
        'format': 'jsonv2',
        'zoom': '14',
      });
      final response = await http
          .get(
            uri,
            headers: const {
              'User-Agent': 'Agakbay/1.0',
              'Accept': 'application/json',
            },
          )
          .timeout(const Duration(seconds: 8));
      if (response.statusCode != 200) return null;
      final decoded = jsonDecode(response.body);
      if (decoded is! Map<String, dynamic>) return null;
      final address = decoded['address'];
      if (address is Map<String, dynamic>) {
        final place =
            address['city'] ??
            address['town'] ??
            address['municipality'] ??
            address['village'] ??
            address['suburb'] ??
            address['county'];
        if (place != null) {
          final placeStr = place.toString();
          final province = address['state'] ?? address['province'];
          if (province != null &&
              province.toString().isNotEmpty &&
              province.toString() != placeStr) {
            return '$placeStr, ${province.toString()}';
          }
          return placeStr;
        }
      }
      final displayName = decoded['display_name']?.toString();
      if (displayName != null && displayName.isNotEmpty) {
        return _extractProvinceOrCity(displayName);
      }
      return null;
    } catch (_) {
      return null;
    }
  }

  /// Answers a "where am I" question directly: classifies the hiker's
  /// live GPS point as either on an actual trail or in a non-hiking area
  /// first (never guessing from raw coordinates), builds a ready answer
  /// from that fact, and only asks the AI to polish the phrasing — same
  /// self-contained-first rationale as [_kyrielleWeatherAnswer]. When
  /// they're not on a trail, this also finds the nearest real hikeable
  /// mountain to proactively suggest, and hands that trail back so the
  /// chat can show a tappable mention card for it — mirroring how a
  /// name-matched mountain does.
  Future<({String text, _NearbyTrail? recommendedMountain})>
  _kyrielleLocationAnswer(String hikerName) async {
    if (_myLocationCenter == null) {
      await _loadCurrentLocation();
    }
    final location = _myLocationCenter;
    if (location == null) {
      return (
        text:
            "I can't see your location right now, $hikerName — turn on "
            'location access in Agakbay and ask again.',
        recommendedMountain: null,
      );
    }

    final onTrailMatches = await _findMountainsNear(
      location,
      maxDistanceKm: _onTrailRadiusKm,
    );
    if (onTrailMatches.isNotEmpty) {
      final trail = onTrailMatches.first;
      final elevationText = trail.elevationMasl > 0
          ? '${trail.elevationMasl} MASL'
          : 'elevation not on file';
      final answer = await _polishWithAi(
        deterministic:
            "You're right on the ${trail.name} trail in "
            '${trail.provinceOrCity}, around $elevationText. Want the '
            'nearest campsite or trail info?',
        aiSystemInstruction:
            'You are Kyrielle, a capable AI trail companion. Rephrase '
            'the given live location data into 1-3 natural, encouraging '
            'sentences addressed to $hikerName by name — describe this '
            'as being on the trail (name the mountain; add elevation or '
            'nearest-campsite knowledge of your own if useful). Never '
            'call this a city or non-hiking location.',
        aiPrompt:
            "Live location: the hiker's GPS puts them ON the "
            '${trail.name} trail in ${trail.provinceOrCity} '
            '($elevationText).',
      );
      return (text: answer, recommendedMountain: trail);
    }

    final cityName = await _reverseGeocodeCityName(location);
    final place = (cityName == null || cityName.isEmpty)
        ? "an area I couldn't identify by name"
        : cityName;
    final nearby = await _findMountainsNear(location, maxDistanceKm: 80.0);
    if (nearby.isEmpty) {
      final answer = await _polishWithAi(
        deterministic:
            "You're in $place — no trail there, and I couldn't find a "
            "hikeable mountain nearby in the app's data right now.",
        aiSystemInstruction:
            'You are Kyrielle, a capable AI trail companion. Rephrase '
            'the given live location data into 1-2 natural sentences '
            'addressed to $hikerName by name. This is NOT a hiking '
            'trail — never use trail language for it. State plainly '
            'where they are; do not invent a nearby mountain since none '
            'was found.',
        aiPrompt: "Live location: the hiker's GPS puts them in $place.",
      );
      return (text: answer, recommendedMountain: null);
    }
    final closest = nearby.first;
    final distanceLabel = closest.distanceKm > 0
        ? '${closest.distanceKm.toStringAsFixed(1)} km away'
        : 'nearby';
    final answer = await _polishWithAi(
      deterministic:
          "You're in $place. No trail here, but ${closest.name} is "
          "about $distanceLabel and a good hike if you're heading out "
          '— want directions or trail info?',
      aiSystemInstruction:
          'You are Kyrielle, a capable AI trail companion. Rephrase the '
          'given live location data into 1-3 natural, encouraging '
          'sentences addressed to $hikerName by name. This is NOT a '
          'hiking trail — never use trail language for it or call it a '
          'trail. State plainly where they are, then proactively '
          'recommend the given nearby mountain as a hike.',
      aiPrompt:
          "Live location: the hiker's GPS puts them in $place. Nearest "
          'real hikeable mountain: ${closest.name} ($distanceLabel).',
    );
    return (text: answer, recommendedMountain: closest);
  }

  /// Instant, deterministic replies for companion-style small talk —
  /// Kyrielle should never stumble on "what's your name" waiting on a
  /// network round trip, and these double as a chance to act like an
  /// actual trail buddy (encourage, then nudge toward a concrete next
  /// step) instead of a flat assistant. Returns null for anything that
  /// isn't small talk, so real hiking questions still go to the full
  /// answer pipeline below.
  String? _kyrielleSmallTalkReply(String normalizedQuestion, String hikerName) {
    const namePhrases = [
      "what's your name",
      'what is your name',
      'who are you',
      'what are you',
    ];
    if (namePhrases.any(normalizedQuestion.contains)) {
      return "I'm Kyrielle — your trail companion here in Agakbay, "
          '$hikerName! I\'ll help you plan, check conditions, and keep '
          "you company once you're out there. Want me to check the "
          'weather or find the nearest trail to get you started?';
    }
    final trimmed = normalizedQuestion.trim();
    const greetingPhrases = ['hello', 'hey kyrielle', 'hi kyrielle'];
    if (trimmed == 'hi' ||
        trimmed == 'hey' ||
        greetingPhrases.any(normalizedQuestion.contains)) {
      return 'Hey $hikerName! Good to have you here. Got a mountain in '
          'mind, or want me to suggest one nearby?';
    }
    const thanksPhrases = ['thank you', 'thanks', 'thx'];
    if (thanksPhrases.any(normalizedQuestion.contains)) {
      return "Anytime, $hikerName — that's what I'm here for. You've got "
          'this. Ready for the next mountain?';
    }
    const howAreYouPhrases = ['how are you', "how're you", 'how you doing'];
    if (howAreYouPhrases.any(normalizedQuestion.contains)) {
      return 'Doing great and ready for the trail, $hikerName! How about '
          'you — planning a hike soon, or just scouting ideas?';
    }
    // A real companion notices when you're not okay before jumping to
    // trail logistics — this checks in first, and only then offers
    // hiking as an option, not a prescription.
    const feelingDownPhrases = [
      'im sad',
      "i'm sad",
      'i am sad',
      'feeling sad',
      'feeling down',
      'im down',
      "i'm down",
      'im stressed',
      "i'm stressed",
      'i am stressed',
      'feeling stressed',
      'im anxious',
      "i'm anxious",
      'feeling anxious',
      'feeling low',
      "i'm not okay",
      'im not okay',
      'im depressed',
      "i'm depressed",
      'having a bad day',
      'rough day',
      'im tired',
      "i'm tired",
      'feeling tired',
      'im overwhelmed',
      "i'm overwhelmed",
    ];
    if (feelingDownPhrases.any(normalizedQuestion.contains)) {
      return "I'm sorry you're feeling that way, $hikerName — you don't "
          'need a reason to hike, so no pressure either way. That said, '
          'a lot of hikers say time on the trail genuinely helps clear '
          "their head. Want me to suggest an easy nearby trail for some "
          "fresh air? Either way, how are you holding up?";
    }
    return null;
  }

  /// Builds the tappable mention card for [trail], or null. Shared by
  /// every answer path (name-matched, location-recommended) so the card
  /// always behaves the same way.
  KyrielleMountainMention? _kyrielleMentionFor(_NearbyTrail? trail) {
    if (trail == null) return null;
    final distanceLabel = trail.distanceKm > 0
        ? '${trail.distanceKm.toStringAsFixed(1)} km away'
        : trail.provinceOrCity;
    return KyrielleMountainMention(
      name: trail.name,
      subtitle: '$distanceLabel · tap to view on map',
      onTap: () {
        Navigator.of(context).pop();
        unawaited(_focusTrailAndOpenDetails(trail));
      },
    );
  }

  Future<KyrielleAnswer> _answerKyrielleQuestion(String question) async {
    final firstName = _communityDisplayName().trim().split(' ').first;
    final hikerName = firstName.isEmpty ? 'this hiker' : firstName;
    final normalizedQuestion = question.toLowerCase();

    final smallTalk = _kyrielleSmallTalkReply(normalizedQuestion, hikerName);
    if (smallTalk != null) {
      return KyrielleAnswer(text: smallTalk);
    }

    if (_kyrielleAiApiKey.isEmpty) {
      _kyrielleAiApiKey = await loadGeminiApiKey();
    }

    // Weather and location both have dedicated, always-answer-something
    // handlers (never dependent on the general AI/mountain-search
    // pipeline below actually succeeding) — see their doc comments.
    if (_isWeatherQuestion(normalizedQuestion)) {
      return KyrielleAnswer(text: await _kyrielleWeatherAnswer(hikerName));
    }
    if (_isLocationQuestion(normalizedQuestion)) {
      final result = await _kyrielleLocationAnswer(hikerName);
      return KyrielleAnswer(
        text: result.text,
        mountain: _kyrielleMentionFor(result.recommendedMountain),
      );
    }

    _NearbyTrail? mentionedTrail;
    final text = await _answerHikeAssistantQuestion(
      question: question,
      initialTrail: _searchedTrailAnchor,
      searchMountainInMindanao: _searchMountainInMindanao,
      fetchMountainOrganizers: _fetchMountainOrganizers,
      aiApiKey: _kyrielleAiApiKey,
      systemInstruction:
          'You are Kyrielle, an AI trail companion inside the Agakbay '
          'hiking app for Mindanao, Philippines. You are talking with '
          '$hikerName — speak to them directly and by name every so '
          'often, the way a real hiking buddy would, not like a generic '
          'assistant answering a search query. Your tone is encouraging, '
          'concise, and grounded in practical trail knowledge — avoid '
          "overly cute or childish language; you're a capable guide, not "
          'a mascot performing for the user. Answer whatever they '
          'actually ask — trail difficulty, elevation, safety, gear, or '
          'general hiking advice — using your own knowledge. Only talk '
          'about organizers/guides when they ask about finding one or '
          'contact info is provided to you. Keep replies conversational, '
          '2-4 sentences.',
      onMountainMentioned: (trail) => mentionedTrail = trail,
    );

    return KyrielleAnswer(
      text: text,
      mountain: _kyrielleMentionFor(mentionedTrail),
    );
  }

  Future<void> _openKyrielleCompanion() async {
    final firstName = _communityDisplayName().trim().split(' ').first;
    await Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (_) => KyrielleCompanionChatScreen(
          userFirstName: firstName.isEmpty ? 'there' : firstName,
          onNearestTrail: () {
            Navigator.of(context).pop();
            _openNearbyTrailsSheet();
          },
          askQuestion: _answerKyrielleQuestion,
        ),
      ),
    );
  }

  // ignore: unused_element
  Widget _buildCommunityTab() {
    return Container(
      decoration: BoxDecoration(gradient: AgakColors.screenBackground),
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
                      color: AgakColors.ink,
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
                color: AgakColors.ink,
                fontSize: 36,
                fontWeight: FontWeight.w800,
              ),
            ),
            Text(
              'Share your hikes. Inspire others.',
              style: TextStyle(
                color: AgakColors.ink.withValues(alpha: 0.72),
                fontSize: 14,
              ),
            ),
            const SizedBox(height: 12),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Container(
                padding: const EdgeInsets.all(4),
                decoration: BoxDecoration(
                  color: AgakColors.ink.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Row(
                  children: [
                    Expanded(child: _communityFeedChip('All Posts', 0)),
                    Expanded(child: _communityFeedChip('My Posts', 1)),
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
                  color: AgakColors.ink.withValues(alpha: 0.06),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(
                    color: AgakColors.ink.withValues(alpha: 0.08),
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (_communityComposerImage != null) ...[
                      Stack(
                        children: [
                          ClipRRect(
                            borderRadius: BorderRadius.circular(10),
                            child: Image.file(
                              File(_communityComposerImage!.path),
                              height: 140,
                              width: double.infinity,
                              fit: BoxFit.cover,
                            ),
                          ),
                          Positioned(
                            top: 6,
                            right: 6,
                            child: GestureDetector(
                              onTap: () => setState(
                                () => _communityComposerImage = null,
                              ),
                              child: Container(
                                padding: const EdgeInsets.all(4),
                                decoration: BoxDecoration(
                                  color: Colors.black.withValues(alpha: 0.6),
                                  shape: BoxShape.circle,
                                ),
                                child: const Icon(
                                  Icons.close_rounded,
                                  color: Colors.white,
                                  size: 16,
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                    ],
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        IconButton(
                          onPressed: _postingCommunityPost
                              ? null
                              : _pickCommunityComposerImage,
                          icon: const Icon(
                            Icons.add_photo_alternate_rounded,
                            color: AgakColors.maroon,
                          ),
                        ),
                        Expanded(
                          child: TextField(
                            controller: _communityComposerController,
                            minLines: 1,
                            maxLines: 3,
                            style: const TextStyle(color: AgakColors.ink),
                            decoration: InputDecoration(
                              hintText: "What's on your trail today?",
                              hintStyle: TextStyle(
                                color: AgakColors.ink.withValues(alpha: 0.5),
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
                            onPressed: _postingCommunityPost
                                ? null
                                : () async {
                                    final content = _communityComposerController
                                        .text
                                        .trim();
                                    final image = _communityComposerImage;
                                    if (content.isEmpty && image == null) {
                                      return;
                                    }
                                    FocusManager.instance.primaryFocus
                                        ?.unfocus();
                                    setState(
                                      () => _postingCommunityPost = true,
                                    );
                                    await _createCommunityPost(
                                      content,
                                      image: image,
                                    );
                                    _communityComposerController.clear();
                                    setState(() {
                                      _communityComposerImage = null;
                                      _postingCommunityPost = false;
                                    });
                                  },
                            style: ElevatedButton.styleFrom(
                              foregroundColor: AgakColors.cream,
                              backgroundColor: AgakColors.maroon,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(10),
                              ),
                            ),
                            child: _postingCommunityPost
                                ? const SizedBox(
                                    height: 18,
                                    width: 18,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                      color: AgakColors.cream,
                                    ),
                                  )
                                : const Text(
                                    'Post',
                                    style: TextStyle(
                                      fontWeight: FontWeight.w700,
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
            const SizedBox(height: 8),
            Expanded(
              child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                stream: _communityPostsStream(),
                builder: (context, snapshot) {
                  if (snapshot.connectionState == ConnectionState.waiting) {
                    return const Center(
                      child: CircularProgressIndicator(
                        strokeWidth: 2.2,
                        color: AgakColors.maroon,
                      ),
                    );
                  }
                  final docs = snapshot.data?.docs ?? const [];
                  var posts = docs
                      .map(_communityPostFromSnapshot)
                      .where(
                        (post) =>
                            post.content.trim().isNotEmpty ||
                            post.imageUrl.trim().isNotEmpty,
                      )
                      .toList();
                  if (_communityFeedFilterIndex == 1) {
                    final uid = _firebaseAuth.currentUser?.uid;
                    posts = uid == null
                        ? <_CommunityPost>[]
                        : posts.where((post) => post.authorId == uid).toList();
                  }

                  if (posts.isEmpty) {
                    final emptyText = _communityFeedFilterIndex == 1
                        ? 'You have no posts yet.'
                        : 'No posts yet. Be the first to share.';
                    return Center(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 22),
                        child: Text(
                          emptyText,
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            color: AgakColors.ink.withValues(alpha: 0.74),
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
            color: isActive ? AgakColors.maroon : Colors.transparent,
            borderRadius: BorderRadius.circular(10),
          ),
          child: Text(
            label,
            style: TextStyle(
              color: isActive
                  ? AgakColors.cream
                  : AgakColors.ink.withValues(alpha: 0.6),
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
      decoration: BoxDecoration(gradient: AgakColors.screenBackground),
      child: SafeArea(
        child: Column(
          children: [
            const SizedBox(height: 14),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Row(
                children: [
                  const Expanded(
                    child: Text(
                      'My Hikes',
                      style: TextStyle(
                        color: AgakColors.ink,
                        fontSize: 28,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                  IconButton(
                    tooltip: 'Refresh trail recordings',
                    onPressed: _refreshPendingTrailSubmissions,
                    icon: _loadingPendingTrailSubmissions
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: AgakColors.maroon,
                            ),
                          )
                        : const Icon(
                            Icons.sync_rounded,
                            color: AgakColors.maroon,
                          ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: _myHikesSummaryHeader(),
            ),
            const SizedBox(height: 12),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: _myHikesViewSelector(),
            ),
            const SizedBox(height: 12),
            Expanded(
              child: switch (_myHikesView) {
                _MyHikesView.completed => _completedHikesList(),
                _MyHikesView.recorded => _recordedTrailSubmissionsList(),
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _myHikesSummaryHeader() {
    final hikeCount = _completedHikeSessions.length;
    final totalDistanceKm = _completedHikeSessions.fold<double>(
      0,
      (total, session) => total + session.distanceKm,
    );
    final summitCount = _completedHikeSessions
        .where((session) => session.reachedSummit)
        .length;
    final pendingCount = _pendingTrailSubmissions.length;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AgakColors.ink.withValues(alpha: 0.12)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.1),
            blurRadius: 18,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  color: AgakColors.maroon.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: const Icon(
                  Icons.landscape_rounded,
                  color: AgakColors.maroon,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Trail Log',
                      style: TextStyle(
                        color: AgakColors.ink,
                        fontSize: 17,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      pendingCount > 0
                          ? '$pendingCount trail recording waiting to upload'
                          : 'Your hikes and trail contributions',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: AgakColors.ink.withValues(alpha: 0.68),
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              _myHikesSummaryStat(
                label: 'Hikes',
                value: hikeCount.toString(),
                color: AgakColors.maroon,
              ),
              const SizedBox(width: 8),
              _myHikesSummaryStat(
                label: 'Distance',
                value: '${totalDistanceKm.toStringAsFixed(1)} km',
                color: AgakColors.olive,
              ),
              const SizedBox(width: 8),
              _myHikesSummaryStat(
                label: 'Summits',
                value: summitCount.toString(),
                color: AgakColors.goldDark,
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _myHikesSummaryStat({
    required String label,
    required String value,
    required Color color,
  }) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
        decoration: BoxDecoration(
          color: AgakColors.ink.withValues(alpha: 0.055),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: color.withValues(alpha: 0.18)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: AgakColors.ink.withValues(alpha: 0.62),
                fontSize: 11,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 3),
            Text(
              value,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: color,
                fontSize: 16,
                fontWeight: FontWeight.w900,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _myHikesViewSelector() {
    Widget item(_MyHikesView view, String label, IconData icon, int count) {
      final selected = _myHikesView == view;
      return Expanded(
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: () {
              setState(() => _myHikesView = view);
              if (view != _MyHikesView.completed) {
                unawaited(_refreshPendingTrailSubmissions());
              }
            },
            borderRadius: BorderRadius.circular(12),
            child: Container(
              height: 48,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: selected
                    ? AgakColors.maroon
                    : AgakColors.ink.withValues(alpha: 0.06),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: selected
                      ? Colors.transparent
                      : AgakColors.ink.withValues(alpha: 0.12),
                ),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    icon,
                    size: 17,
                    color: selected
                        ? AgakColors.cream
                        : AgakColors.ink.withValues(alpha: 0.6),
                  ),
                  const SizedBox(width: 6),
                  Flexible(
                    child: Text(
                      label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: selected
                            ? AgakColors.cream
                            : AgakColors.ink.withValues(alpha: 0.6),
                        fontSize: 12,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                  if (count > 0) ...[
                    const SizedBox(width: 5),
                    Container(
                      constraints: const BoxConstraints(minWidth: 18),
                      height: 18,
                      alignment: Alignment.center,
                      padding: const EdgeInsets.symmetric(horizontal: 5),
                      decoration: BoxDecoration(
                        color: selected
                            ? AgakColors.cream.withValues(alpha: 0.22)
                            : AgakColors.maroon.withValues(alpha: 0.14),
                        borderRadius: BorderRadius.circular(999),
                      ),
                      child: Text(
                        count.toString(),
                        style: TextStyle(
                          color: selected
                              ? AgakColors.cream
                              : AgakColors.maroon,
                          fontSize: 10,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      );
    }

    return Row(
      children: [
        item(
          _MyHikesView.completed,
          'Completed',
          Icons.hiking_rounded,
          _completedHikeSessions.length,
        ),
        const SizedBox(width: 8),
        item(
          _MyHikesView.recorded,
          'Recorded',
          Icons.route_rounded,
          _pendingTrailSubmissions.length,
        ),
      ],
    );
  }

  Widget _completedHikesList() {
    if (_completedHikeSessions.isEmpty) {
      return _myHikesEmptyState(
        icon: Icons.hiking_rounded,
        title: 'No completed hikes yet',
        message: 'Start a hike from Explore. Finished hikes will appear here.',
        actionLabel: 'Open Explore',
        onAction: () {
          setState(() => _selectedNavIndex = 0);
        },
      );
    }
    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 96),
      itemCount: _completedHikeSessions.length,
      separatorBuilder: (_, _) => const SizedBox(height: 10),
      itemBuilder: (_, index) {
        final session = _completedHikeSessions[index];
        return _completedHikeCard(session);
      },
    );
  }

  Widget _recordedTrailSubmissionsList() {
    final stream = _trailSubmissionsStream();
    if (stream == null) {
      return _myHikesEmptyState(
        icon: Icons.login_rounded,
        title: 'Sign in required',
        message: 'Sign in to see your trail recordings.',
      );
    }
    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: stream,
      builder: (context, snapshot) {
        final remoteDocs = _sortedTrailSubmissionDocs(snapshot.data?.docs);
        final hasLocal = _pendingTrailSubmissions.isNotEmpty;
        if (snapshot.connectionState == ConnectionState.waiting &&
            remoteDocs.isEmpty &&
            !hasLocal) {
          return const Center(
            child: CircularProgressIndicator(
              strokeWidth: 2.4,
              color: AgakColors.maroon,
            ),
          );
        }
        if (remoteDocs.isEmpty && !hasLocal) {
          return _myHikesEmptyState(
            icon: Icons.route_rounded,
            title: 'No recorded trails yet',
            message:
                'When you record a missing mountain trail, its status appears here.',
            actionLabel: 'Find a Mountain',
            onAction: () {
              setState(() => _selectedNavIndex = 0);
            },
          );
        }
        return ListView(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 96),
          children: [
            if (hasLocal) ...[
              _myHikesSectionLabel('Saved on this device'),
              for (final submission in _pendingTrailSubmissions) ...[
                _localTrailSubmissionCard(submission),
                const SizedBox(height: 10),
              ],
              const SizedBox(height: 8),
            ],
            if (remoteDocs.isNotEmpty) ...[
              _myHikesSectionLabel('Uploaded recordings'),
              for (final doc in remoteDocs) ...[
                _remoteTrailSubmissionCard(doc),
                const SizedBox(height: 10),
              ],
            ],
          ],
        );
      },
    );
  }

  List<QueryDocumentSnapshot<Map<String, dynamic>>> _sortedTrailSubmissionDocs(
    List<QueryDocumentSnapshot<Map<String, dynamic>>>? docs,
  ) {
    final sorted = List<QueryDocumentSnapshot<Map<String, dynamic>>>.from(
      docs ?? const <QueryDocumentSnapshot<Map<String, dynamic>>>[],
    );
    sorted.sort((a, b) {
      final aTime =
          _submissionDate(a.data()) ?? DateTime.fromMillisecondsSinceEpoch(0);
      final bTime =
          _submissionDate(b.data()) ?? DateTime.fromMillisecondsSinceEpoch(0);
      return bTime.compareTo(aTime);
    });
    return sorted;
  }

  DateTime? _submissionDate(Map<String, dynamic> data) {
    final raw = data['createdAt'] ?? data['startedAt'] ?? data['endedAt'];
    if (raw is Timestamp) {
      return raw.toDate();
    }
    if (raw is String) {
      return DateTime.tryParse(raw)?.toLocal();
    }
    return null;
  }

  Widget _myHikesSectionLabel(String label) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Text(
        label,
        style: TextStyle(
          color: AgakColors.ink.withValues(alpha: 0.72),
          fontSize: 12,
          fontWeight: FontWeight.w800,
          letterSpacing: 0.4,
        ),
      ),
    );
  }

  Widget _myHikesEmptyState({
    required IconData icon,
    required String title,
    required String message,
    String? actionLabel,
    VoidCallback? onAction,
  }) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 28),
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.fromLTRB(22, 24, 22, 22),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: AgakColors.ink.withValues(alpha: 0.11)),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.1),
                blurRadius: 20,
                offset: const Offset(0, 10),
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 76,
                height: 76,
                decoration: BoxDecoration(
                  gradient: RadialGradient(
                    colors: [
                      AgakColors.maroon.withValues(alpha: 0.24),
                      AgakColors.maroon.withValues(alpha: 0.04),
                    ],
                  ),
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: AgakColors.maroon.withValues(alpha: 0.3),
                  ),
                ),
                child: Icon(icon, size: 36, color: AgakColors.maroon),
              ),
              const SizedBox(height: 14),
              Text(
                title,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: AgakColors.ink,
                  fontSize: 19,
                  fontWeight: FontWeight.w900,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                message,
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: AgakColors.ink.withValues(alpha: 0.72),
                  height: 1.35,
                ),
              ),
              if (actionLabel != null && onAction != null) ...[
                const SizedBox(height: 18),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    onPressed: onAction,
                    icon: const Icon(Icons.explore_rounded),
                    label: Text(actionLabel),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AgakColors.maroon,
                      foregroundColor: AgakColors.cream,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _localTrailSubmissionCard(PendingTrailSubmission submission) {
    final payload = submission.payload;
    final mountainName =
        payload['mountainName']?.toString() ?? 'Recorded trail';
    final trailName = payload['trailName']?.toString() ?? mountainName;
    final province = payload['provinceOrCity']?.toString() ?? '';
    final distanceKm = (payload['distanceKm'] as num?)?.toDouble();
    final durationSeconds = (payload['durationSeconds'] as num?)?.toInt();
    final routePoints = payload['routePoints'] is List
        ? (payload['routePoints'] as List).length
        : 0;
    final stationCount = payload['stations'] is List
        ? (payload['stations'] as List).length
        : 0;
    return _trailSubmissionCardShell(
      title: trailName,
      subtitle: province.isEmpty ? mountainName : '$mountainName · $province',
      statusLabel: 'Waiting Upload',
      statusColor: AgakColors.goldDark,
      statusIcon: Icons.cloud_off_rounded,
      dateText: _formatDate(submission.createdAt),
      metrics: [
        if (distanceKm != null) '${distanceKm.toStringAsFixed(2)} km',
        if (durationSeconds != null)
          _formatDuration(Duration(seconds: durationSeconds)),
        '$routePoints points',
        if (stationCount > 0) '$stationCount stations',
      ],
      footer:
          'This recording will upload and become a trail automatically '
          'once you\'re back online.',
    );
  }

  Widget _remoteTrailSubmissionCard(
    QueryDocumentSnapshot<Map<String, dynamic>> doc,
  ) {
    final data = doc.data();
    final mountainName = data['mountainName']?.toString() ?? 'Recorded trail';
    final trailName = data['trailName']?.toString() ?? mountainName;
    final province = data['provinceOrCity']?.toString() ?? '';
    final status = (data['status']?.toString() ?? 'pending').toLowerCase();
    final distanceKm = (data['distanceKm'] as num?)?.toDouble();
    final durationSeconds = (data['durationSeconds'] as num?)?.toInt();
    final routePoints = data['routePoints'] is List
        ? (data['routePoints'] as List).length
        : 0;
    final stationCount = data['stations'] is List
        ? (data['stations'] as List).length
        : 0;
    final date = _submissionDate(data);
    final rejection = data['rejectionReason']?.toString();

    return _trailSubmissionCardShell(
      title: trailName,
      subtitle: province.isEmpty ? mountainName : '$mountainName · $province',
      statusLabel: _submissionStatusLabel(status),
      statusColor: _submissionStatusColor(status),
      statusIcon: _submissionStatusIcon(status),
      dateText: date == null ? 'Date unavailable' : _formatDate(date),
      metrics: [
        if (distanceKm != null) '${distanceKm.toStringAsFixed(2)} km',
        if (durationSeconds != null)
          _formatDuration(Duration(seconds: durationSeconds)),
        '$routePoints points',
        if (stationCount > 0) '$stationCount stations',
      ],
      footer: rejection == null || rejection.isEmpty
          ? _submissionStatusDescription(status)
          : 'Rejected: ${rejection.replaceAll('_', ' ')}',
    );
  }

  Widget _trailSubmissionCardShell({
    required String title,
    required String subtitle,
    required String statusLabel,
    required Color statusColor,
    required IconData statusIcon,
    required String dateText,
    required List<String> metrics,
    required String footer,
  }) {
    return Container(
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: statusColor.withValues(alpha: 0.28)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.1),
            blurRadius: 14,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(height: 4, color: statusColor.withValues(alpha: 0.82)),
          Padding(
            padding: const EdgeInsets.all(13),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      width: 46,
                      height: 46,
                      decoration: BoxDecoration(
                        color: statusColor.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: Icon(statusIcon, color: statusColor, size: 24),
                    ),
                    const SizedBox(width: 11),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: AgakColors.ink,
                              fontSize: 16,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                          const SizedBox(height: 3),
                          Text(
                            subtitle,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: AgakColors.ink.withValues(alpha: 0.68),
                              fontSize: 12,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 9,
                        vertical: 5,
                      ),
                      decoration: BoxDecoration(
                        color: statusColor.withValues(alpha: 0.14),
                        borderRadius: BorderRadius.circular(999),
                      ),
                      child: Text(
                        statusLabel,
                        style: TextStyle(
                          color: statusColor,
                          fontSize: 11,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    Icon(
                      Icons.calendar_month_rounded,
                      color: AgakColors.ink.withValues(alpha: 0.54),
                      size: 15,
                    ),
                    const SizedBox(width: 6),
                    Text(
                      dateText,
                      style: TextStyle(
                        color: AgakColors.ink.withValues(alpha: 0.64),
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
                if (metrics.isNotEmpty) ...[
                  const SizedBox(height: 10),
                  Wrap(
                    spacing: 7,
                    runSpacing: 7,
                    children: metrics
                        .map(
                          (metric) => _myHikesChip(
                            label: metric,
                            color: AgakColors.ink.withValues(alpha: 0.78),
                          ),
                        )
                        .toList(growable: false),
                  ),
                ],
                const SizedBox(height: 11),
                Text(
                  footer,
                  style: TextStyle(
                    color: AgakColors.ink.withValues(alpha: 0.72),
                    height: 1.32,
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _myHikesChip({required String label, required Color color}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
      decoration: BoxDecoration(
        color: AgakColors.ink.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: AgakColors.ink.withValues(alpha: 0.08)),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: color,
          fontSize: 11,
          fontWeight: FontWeight.w800,
        ),
      ),
    );
  }

  String _submissionStatusLabel(String status) {
    return switch (status) {
      'included' => 'Live Trail',
      'checked' => 'Live Trail',
      'accepted' => 'Live Trail',
      'rejected' => 'Rejected',
      _ => 'Processing',
    };
  }

  String _submissionStatusDescription(String status) {
    return switch (status) {
      'included' => 'This recording is now the trail for this mountain.',
      'checked' => 'This recording is now the trail for this mountain.',
      'accepted' => 'This recording is now the trail for this mountain.',
      'rejected' => 'This recording could not be used.',
      _ => 'Uploaded and becoming a trail.',
    };
  }

  Color _submissionStatusColor(String status) {
    return switch (status) {
      'included' => AgakColors.olive,
      'checked' => AgakColors.olive,
      'accepted' => AgakColors.olive,
      'rejected' => AgakColors.maroon,
      _ => AgakColors.goldDark,
    };
  }

  IconData _submissionStatusIcon(String status) {
    return switch (status) {
      'included' => Icons.route_rounded,
      'checked' => Icons.check_circle_rounded,
      'accepted' => Icons.check_circle_rounded,
      'rejected' => Icons.cancel_rounded,
      _ => Icons.pending_actions_rounded,
    };
  }

  Widget _buildProfileTab() {
    final user = _firebaseAuth.currentUser;
    final pendingCount = _pendingTrailSubmissions.length;
    return Container(
      decoration: BoxDecoration(gradient: AgakColors.screenBackground),
      child: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 96),
          children: [
            const Text(
              'Profile',
              style: TextStyle(
                color: AgakColors.ink,
                fontSize: 30,
                fontWeight: FontWeight.w900,
              ),
            ),
            const SizedBox(height: 14),
            _profileUserCard(user),
            const SizedBox(height: 18),
            _profileSection(
              title: 'Safety',
              children: [
                _profileActionTile(
                  icon: Icons.groups_rounded,
                  iconColor: const Color(0xFFFFD76A),
                  title: 'Hike SOS Room',
                  subtitle: 'Join or manage an active guide room',
                  trailing: Icons.chevron_right_rounded,
                  onTap: () async {
                    await Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (context) =>
                            HikeRoomScreen(onStartHiking: _startHikingFromRoom),
                      ),
                    );
                  },
                ),
                _profileActionTile(
                  icon: Icons.contact_emergency_rounded,
                  iconColor: const Color(0xFFFF7A7A),
                  title: 'Emergency Contact',
                  subtitle: _emergencyContactSummary(),
                  trailing: Icons.edit_rounded,
                  onTap: _openEmergencyContactDialog,
                ),
                _profileActionTile(
                  icon: Icons.location_on_rounded,
                  iconColor: const Color(0xFF48D1FF),
                  title: 'Location Access',
                  subtitle: _checkingLocationAccessStatus
                      ? 'Checking...'
                      : _locationAccessStatus,
                  trailing: Icons.refresh_rounded,
                  onTap: _refreshLocationAccessStatus,
                ),
              ],
            ),
            const SizedBox(height: 16),
            _profileSection(
              title: 'Trail Activity',
              children: [
                Row(
                  children: [
                    _profileStatTile(
                      label: 'Completed',
                      value: _completedHikeSessions.length.toString(),
                      color: AgakColors.maroon,
                      onTap: () => _openMyHikesView(_MyHikesView.completed),
                    ),
                    const SizedBox(width: 10),
                    _profileStatTile(
                      label: 'Recorded',
                      value: pendingCount.toString(),
                      color: AgakColors.maroon,
                      onTap: () => _openMyHikesView(_MyHikesView.recorded),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                _profileActionTile(
                  icon: Icons.route_rounded,
                  iconColor: AgakColors.maroon,
                  title: 'Recorded Trails',
                  subtitle: 'View uploaded and saved trail recordings',
                  trailing: Icons.chevron_right_rounded,
                  onTap: () => _openMyHikesView(_MyHikesView.recorded),
                ),
              ],
            ),
            const SizedBox(height: 16),
            _profileSection(
              title: 'Kyrielle Companion',
              children: [
                _profileActionTile(
                  icon: Icons.auto_awesome_rounded,
                  iconColor: AgakColors.olive,
                  title: "Meet Kyrielle's Emotions",
                  subtitle: 'See how your companion reacts to your hikes',
                  trailing: Icons.chevron_right_rounded,
                  onTap: () {
                    Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (context) => const AgakEmotionShowcaseScreen(),
                      ),
                    );
                  },
                ),
              ],
            ),
            const SizedBox(height: 16),
            _profileSection(
              title: 'Account',
              children: [
                _profileActionTile(
                  icon: Icons.logout_rounded,
                  iconColor: const Color(0xFFFF7A7A),
                  title: 'Sign Out',
                  subtitle: user?.email ?? 'No email',
                  trailing: Icons.chevron_right_rounded,
                  onTap: () async {
                    final confirmed = await _showLogoutConfirmationDialog();
                    if (confirmed) {
                      await _firebaseAuth.signOut();
                    }
                  },
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _profileUserCard(User? user) {
    final displayName = _communityDisplayName();
    final photoUrl = _profilePhotoUrl();
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AgakColors.ink.withValues(alpha: 0.12)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.1),
            blurRadius: 18,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: Row(
        children: [
          GestureDetector(
            onTap: _uploadingProfilePhoto ? null : _pickAndUploadProfilePhoto,
            child: Stack(
              children: [
                ClipOval(
                  child: Container(
                    width: 66,
                    height: 66,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      gradient: _avatarGradient(displayName),
                    ),
                    child: photoUrl.isEmpty
                        ? Text(
                            _communityAvatarSeed(displayName),
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 24,
                              fontWeight: FontWeight.w900,
                            ),
                          )
                        : Image.network(
                            photoUrl,
                            width: 66,
                            height: 66,
                            fit: BoxFit.cover,
                            errorBuilder: (_, _, _) {
                              return Text(
                                _communityAvatarSeed(displayName),
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 24,
                                  fontWeight: FontWeight.w900,
                                ),
                              );
                            },
                          ),
                  ),
                ),
                Positioned(
                  right: 0,
                  bottom: 0,
                  child: Container(
                    width: 24,
                    height: 24,
                    decoration: BoxDecoration(
                      color: AgakColors.maroon,
                      shape: BoxShape.circle,
                      border: Border.all(color: Colors.white, width: 2),
                    ),
                    child: _uploadingProfilePhoto
                        ? const Padding(
                            padding: EdgeInsets.all(5),
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: AgakColors.cream,
                            ),
                          )
                        : const Icon(
                            Icons.camera_alt_rounded,
                            color: AgakColors.cream,
                            size: 14,
                          ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        displayName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: AgakColors.ink,
                          fontSize: 20,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    ),
                    IconButton(
                      tooltip: 'Edit name',
                      onPressed: _updatingProfile
                          ? null
                          : _openEditProfileDialog,
                      icon: _updatingProfile
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: AgakColors.maroon,
                              ),
                            )
                          : const Icon(
                              Icons.edit_rounded,
                              color: AgakColors.maroon,
                              size: 19,
                            ),
                    ),
                  ],
                ),
                Text(
                  user?.email ?? 'No email',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: AgakColors.ink.withValues(alpha: 0.6),
                    fontSize: 13,
                  ),
                ),
                const SizedBox(height: 10),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    _profileBadge(_accountTypeLabel(), AgakColors.maroon),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _profileBadge(String label, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.13),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withValues(alpha: 0.18)),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: color,
          fontSize: 11,
          fontWeight: FontWeight.w900,
        ),
      ),
    );
  }

  Widget _profileSection({
    required String title,
    required List<Widget> children,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 2, bottom: 8),
          child: Text(
            title,
            style: TextStyle(
              color: AgakColors.ink.withValues(alpha: 0.74),
              fontSize: 13,
              fontWeight: FontWeight.w900,
              letterSpacing: 0.5,
            ),
          ),
        ),
        Container(
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: AgakColors.ink.withValues(alpha: 0.1)),
          ),
          child: Column(
            children: [
              for (var i = 0; i < children.length; i++) ...[
                children[i],
                if (i != children.length - 1)
                  Divider(
                    height: 1,
                    color: AgakColors.ink.withValues(alpha: 0.08),
                    indent: 58,
                  ),
              ],
            ],
          ),
        ),
      ],
    );
  }

  Widget _profileActionTile({
    required IconData icon,
    required Color iconColor,
    required String title,
    required String subtitle,
    required IconData trailing,
    required VoidCallback onTap,
  }) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(18),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 13),
          child: Row(
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: iconColor.withValues(alpha: 0.13),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(icon, color: iconColor, size: 20),
              ),
              const SizedBox(width: 11),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: AgakColors.ink,
                        fontSize: 15,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: AgakColors.ink.withValues(alpha: 0.62),
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Icon(
                trailing,
                color: AgakColors.ink.withValues(alpha: 0.54),
                size: 21,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _profileStatTile({
    required String label,
    required String value,
    required Color color,
    required VoidCallback onTap,
  }) {
    return Expanded(
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(16),
          child: Container(
            padding: const EdgeInsets.all(13),
            decoration: BoxDecoration(
              color: AgakColors.ink.withValues(alpha: 0.055),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: color.withValues(alpha: 0.18)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: TextStyle(
                    color: AgakColors.ink.withValues(alpha: 0.64),
                    fontSize: 12,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 5),
                Text(
                  value,
                  style: TextStyle(
                    color: color,
                    fontSize: 24,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _circleButton({required IconData icon, VoidCallback? onTap}) {
    return Material(
      color: Colors.transparent,
      shape: const CircleBorder(),
      child: InkWell(
        onTap: onTap,
        customBorder: const CircleBorder(),
        child: Container(
          width: 44,
          height: 44,
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.85),
            shape: BoxShape.circle,
            border: Border.all(color: AgakColors.ink.withValues(alpha: 0.16)),
          ),
          child: Icon(icon, color: AgakColors.ink, size: 24),
        ),
      ),
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
                ? AgakColors.maroon
                : Colors.white.withValues(alpha: 0.82),
            borderRadius: BorderRadius.circular(24),
            border: Border.all(
              color: isActive
                  ? Colors.transparent
                  : AgakColors.ink.withValues(alpha: 0.18),
            ),
          ),
          child: Text(
            label,
            style: TextStyle(
              color: isActive ? AgakColors.cream : AgakColors.ink,
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
            color: Colors.white.withValues(alpha: 0.9),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: AgakColors.ink.withValues(alpha: 0.18)),
          ),
          child: Icon(icon, color: AgakColors.ink, size: 24),
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
                ? AgakColors.maroon
                : AgakColors.ink.withValues(alpha: 0.06),
            borderRadius: BorderRadius.circular(18),
            border: Border.all(
              color: isActive
                  ? Colors.transparent
                  : AgakColors.ink.withValues(alpha: isEnabled ? 0.18 : 0.08),
            ),
          ),
          child: Text(
            label,
            style: TextStyle(
              color: isActive
                  ? AgakColors.cream
                  : isEnabled
                  ? AgakColors.ink
                  : AgakColors.ink.withValues(alpha: 0.4),
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ),
    );
  }

  /// Cache of authorId -> current display name, resolved live from
  /// `users/{authorId}` instead of trusting whatever name was frozen into
  /// a post/comment at the moment it was written. Session-lived only (not
  /// persisted) — cheap to rebuild, and a renamed user's own posts/replies
  /// always resolve instantly since that branch never needs a fetch.
  final Map<String, String> _communityAuthorNameCache = <String, String>{};
  final Set<String> _communityAuthorNameFetching = <String>{};

  /// Returns the best name to show for [authorId] right now — your own
  /// live display name if it's you, a cached live lookup if one's already
  /// resolved, otherwise [fallback] (the frozen name stored on the
  /// post/comment) while a lookup kicks off in the background.
  String _communityAuthorName(String authorId, String fallback) {
    if (authorId.isEmpty) {
      return fallback;
    }
    final currentUser = _firebaseAuth.currentUser;
    if (currentUser != null && authorId == currentUser.uid) {
      return _communityDisplayName();
    }
    final cached = _communityAuthorNameCache[authorId];
    if (cached != null) {
      return cached;
    }
    if (_communityAuthorNameFetching.add(authorId)) {
      unawaited(_fetchCommunityAuthorName(authorId, fallback));
    }
    return fallback;
  }

  Future<void> _fetchCommunityAuthorName(
    String authorId,
    String fallback,
  ) async {
    try {
      // Reads the public name slice, not the full profile doc — Firestore
      // rules only let a user read their own full `users/{id}` doc (or a
      // tour guide's), so resolving other hikers' live names has to go
      // through the small denormalized `public/profile` doc instead.
      final doc = await _firestore
          .collection('users')
          .doc(authorId)
          .collection('public')
          .doc('profile')
          .get();
      final data = doc.data();
      final fullName = data?['fullName']?.toString().trim();
      final displayName = data?['displayName']?.toString().trim();
      final resolved = (fullName != null && fullName.isNotEmpty)
          ? fullName
          : (displayName != null && displayName.isNotEmpty)
          ? displayName
          : fallback;
      if (!mounted) {
        return;
      }
      setState(() {
        _communityAuthorNameCache[authorId] = resolved;
      });
    } catch (error) {
      debugPrint('Failed to resolve community author name: $error');
    } finally {
      _communityAuthorNameFetching.remove(authorId);
    }
  }

  Widget _communityPostCard(
    _CommunityPost post, {
    bool showCommentAction = true,
  }) {
    final user = _firebaseAuth.currentUser;
    final authorName = _communityAuthorName(post.authorId, post.authorName);
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
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AgakColors.ink.withValues(alpha: 0.1)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.12),
            blurRadius: 16,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 32,
                height: 32,
                decoration: BoxDecoration(
                  gradient: _avatarGradient(authorName),
                  shape: BoxShape.circle,
                ),
                alignment: Alignment.center,
                child: Text(
                  _communityAvatarSeed(authorName),
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      authorName,
                      style: const TextStyle(
                        color: AgakColors.ink,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    Text(
                      post.createdAt == null
                          ? 'Just now'
                          : _formatDate(post.createdAt!),
                      style: TextStyle(
                        color: AgakColors.ink.withValues(alpha: 0.55),
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
                    color: AgakColors.ink.withValues(alpha: 0.06),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    post.mountainName,
                    style: const TextStyle(
                      color: AgakColors.maroon,
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              if (user != null && user.uid == post.authorId)
                PopupMenuButton<String>(
                  icon: Icon(
                    Icons.more_vert_rounded,
                    color: AgakColors.ink.withValues(alpha: 0.54),
                    size: 20,
                  ),
                  color: Colors.white,
                  onSelected: (value) {
                    if (value == 'edit') {
                      unawaited(_editCommunityPost(post));
                    } else if (value == 'delete') {
                      unawaited(_deleteCommunityPost(post));
                    }
                  },
                  itemBuilder: (context) => const [
                    PopupMenuItem(
                      value: 'edit',
                      child: Text(
                        'Edit',
                        style: TextStyle(color: AgakColors.ink),
                      ),
                    ),
                    PopupMenuItem(
                      value: 'delete',
                      child: Text(
                        'Delete',
                        style: TextStyle(color: AgakColors.maroon),
                      ),
                    ),
                  ],
                ),
            ],
          ),
          const SizedBox(height: 10),
          if (post.content.trim().isNotEmpty) ...[
            Text(
              post.content,
              style: const TextStyle(color: AgakColors.ink, height: 1.35),
            ),
            const SizedBox(height: 10),
          ],
          if (post.imageUrl.trim().isNotEmpty) ...[
            ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: Image.network(
                post.imageUrl,
                width: double.infinity,
                fit: BoxFit.cover,
                loadingBuilder: (context, child, progress) {
                  if (progress == null) return child;
                  return Container(
                    height: 200,
                    alignment: Alignment.center,
                    child: const CircularProgressIndicator(
                      strokeWidth: 2,
                      color: AgakColors.maroon,
                    ),
                  );
                },
                errorBuilder: (context, error, stackTrace) => Container(
                  height: 120,
                  alignment: Alignment.center,
                  color: AgakColors.ink.withValues(alpha: 0.05),
                  child: Icon(
                    Icons.broken_image_outlined,
                    color: AgakColors.ink.withValues(alpha: 0.38),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 10),
          ],
          Row(
            children: [
              if (likeDocStream == null)
                _communityActionText(
                  icon: Icons.favorite_border_rounded,
                  label: '${post.likeCount}',
                  color: AgakColors.ink.withValues(alpha: 0.6),
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
                      color: liked
                          ? AgakColors.maroon
                          : AgakColors.ink.withValues(alpha: 0.6),
                      onTap: () => _toggleCommunityPostLike(post),
                    );
                  },
                ),
              const SizedBox(width: 14),
              if (showCommentAction)
                _communityActionText(
                  icon: Icons.chat_bubble_outline_rounded,
                  label: '${post.commentCount}',
                  color: AgakColors.ink.withValues(alpha: 0.6),
                  onTap: () => unawaited(_openCommunityPostDetails(post)),
                )
              else
                Row(
                  children: [
                    Icon(
                      Icons.chat_bubble_outline_rounded,
                      color: AgakColors.ink.withValues(alpha: 0.6),
                      size: 18,
                    ),
                    const SizedBox(width: 4),
                    Text(
                      '${post.commentCount}',
                      style: TextStyle(
                        color: AgakColors.ink.withValues(alpha: 0.6),
                      ),
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
                color: AgakColors.cream,
                borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
              ),
              child: Column(
                children: [
                  const SizedBox(height: 10),
                  Container(
                    width: 44,
                    height: 4,
                    decoration: BoxDecoration(
                      color: AgakColors.ink.withValues(alpha: 0.18),
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 12, 8, 8),
                    child: Row(
                      children: [
                        const Expanded(
                          child: Text(
                            'All Nearby Trails',
                            style: TextStyle(
                              color: AgakColors.ink,
                              fontSize: 20,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                        IconButton(
                          onPressed: () {
                            Navigator.of(sheetContext).pop();
                          },
                          icon: Icon(
                            Icons.close_rounded,
                            color: AgakColors.ink.withValues(alpha: 0.68),
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
                          color: AgakColors.ink.withValues(alpha: 0.72),
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
            color: AgakColors.maroon,
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
        color: AgakColors.ink.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Text(
        message,
        style: TextStyle(color: AgakColors.ink.withValues(alpha: 0.75)),
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
            color: AgakColors.ink.withValues(alpha: 0.05),
            borderRadius: BorderRadius.circular(14),
          ),
          child: Row(
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(10),
                child: Container(
                  width: 70,
                  height: 50,
                  color: AgakColors.surfaceRaised,
                  child: _trailImage(trail),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            trail.name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: AgakColors.ink,
                              fontSize: 16,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                        const SizedBox(width: 6),
                        Container(
                          width: 9,
                          height: 9,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: trail.status == 'Open'
                                ? AgakColors.olive
                                : AgakColors.maroon,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 2),
                    Text(
                      _displayDistanceText(trail),
                      style: const TextStyle(
                        color: AgakColors.maroon,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    if (trail.address.isNotEmpty)
                      Text(
                        trail.address,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: AgakColors.ink.withValues(alpha: 0.6),
                          fontSize: 12,
                        ),
                      ),
                  ],
                ),
              ),
              Icon(
                Icons.chevron_right_rounded,
                color: AgakColors.ink.withValues(alpha: 0.7),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _trailImage(_NearbyTrail trail) {
    if (trail.imageUrl == null || trail.imageUrl!.isEmpty) {
      return const Icon(Icons.terrain_rounded, color: AgakColors.maroon);
    }
    return Image.network(
      trail.imageUrl!,
      fit: BoxFit.cover,
      errorBuilder: (_, _, _) {
        return const Icon(Icons.terrain_rounded, color: AgakColors.maroon);
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
              color: AgakColors.maroon,
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
    final statusColor = session.reachedSummit
        ? AgakColors.maroon
        : AgakColors.olive;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(18),
        child: Container(
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: statusColor.withValues(alpha: 0.22)),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.2),
                blurRadius: 14,
                offset: const Offset(0, 8),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                height: 4,
                decoration: BoxDecoration(
                  color: statusColor.withValues(alpha: 0.86),
                  borderRadius: const BorderRadius.vertical(
                    top: Radius.circular(18),
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.all(13),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        ClipRRect(
                          borderRadius: BorderRadius.circular(14),
                          child: Container(
                            width: 54,
                            height: 54,
                            color: AgakColors.surfaceRaised,
                            child: _trailImage(session.trail),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                session.trail.name,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  color: AgakColors.ink,
                                  fontSize: 17,
                                  fontWeight: FontWeight.w900,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Row(
                                children: [
                                  Icon(
                                    Icons.calendar_month_rounded,
                                    color: AgakColors.ink.withValues(
                                      alpha: 0.54,
                                    ),
                                    size: 15,
                                  ),
                                  const SizedBox(width: 5),
                                  Expanded(
                                    child: Text(
                                      _formatDate(session.completedAt),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: TextStyle(
                                        color: AgakColors.ink.withValues(
                                          alpha: 0.65,
                                        ),
                                        fontSize: 12,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 6,
                          ),
                          decoration: BoxDecoration(
                            color: statusColor.withValues(alpha: 0.14),
                            borderRadius: BorderRadius.circular(999),
                          ),
                          child: Text(
                            session.reachedSummit ? 'Summit' : 'Ended',
                            style: TextStyle(
                              color: statusColor,
                              fontSize: 11,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Wrap(
                      spacing: 7,
                      runSpacing: 7,
                      children: [
                        _myHikesChip(
                          label: '${session.distanceKm.toStringAsFixed(2)} km',
                          color: AgakColors.olive,
                        ),
                        _myHikesChip(
                          label: _formatDuration(session.duration),
                          color: AgakColors.ink.withValues(alpha: 0.85),
                        ),
                        _myHikesChip(
                          label: '+${session.elevationGainMasl} m',
                          color: AgakColors.maroon,
                        ),
                        _myHikesChip(
                          label: '${session.maxElevationMasl} MASL',
                          color: AgakColors.olive,
                        ),
                      ],
                    ),
                    const SizedBox(height: 11),
                    Row(
                      children: [
                        Expanded(
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(999),
                            child: LinearProgressIndicator(
                              value: session.totalCheckpoints <= 0
                                  ? 0
                                  : (session.checkpointsReached /
                                            session.totalCheckpoints)
                                        .clamp(0.0, 1.0),
                              minHeight: 7,
                              backgroundColor: AgakColors.ink.withValues(
                                alpha: 0.08,
                              ),
                              valueColor: AlwaysStoppedAnimation<Color>(
                                statusColor,
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Text(
                          '${session.checkpointsReached}/${session.totalCheckpoints} checkpoints',
                          style: TextStyle(
                            color: AgakColors.ink.withValues(alpha: 0.68),
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _openMountainDetailsCard(_NearbyTrail trail) async {
    _rememberTrail(trail);
    unawaited(
      AgakBehaviorDatabase.instance.logView(
        mountainId: buildMountainMatchKey(
          name: trail.name,
          region: trail.provinceOrCity,
        ),
        mountainName: trail.name,
        source: 'details_card',
      ),
    );
    final communityTrail = await _fetchCommunityTrail(trail);
    final routeOptions = await _loadMountainRouteOptions(trail);
    final trailMatchKey = buildMountainMatchKey(
      name: trail.name,
      region: trail.provinceOrCity,
    );
    unawaited(_pushMountainTriviaTip(trail, trailMatchKey));
    var isBookmarked = await AgakBehaviorDatabase.instance.isBookmarked(
      mountainId: trailMatchKey,
      mountainName: trail.name,
    );
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
    var hasRequestedInitialDetailsLoad = false;
    var selectedRoute = routeOptions.isNotEmpty ? routeOptions.first : null;
    var hasCompletedBefore = _completedTrailIds.contains(trail.placeId);

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, sheetSetState) {
            final trailStatus = (communityTrail?.status ?? 'none')
                .toLowerCase();
            final mappedRouteCount = routeOptions.length;
            final hasMappedRoutes = mappedRouteCount > 0;
            final hasCommunityRoute =
                (trailStatus == 'verified' || trailStatus == 'provisional') &&
                (communityTrail?.points.length ?? 0) >= 2;
            final hasAnyUsableRoute = hasMappedRoutes || hasCommunityRoute;
            final trailStatusLabel = switch (trailStatus) {
              'verified' => 'Community Verified',
              'provisional' => 'Community Recorded',
              'pending' => 'Checking',
              _ =>
                hasMappedRoutes
                    ? 'Mapped ($mappedRouteCount routes)'
                    : 'No Data',
            };
            final trailStatusColor = switch (trailStatus) {
              'verified' => AgakColors.olive,
              'provisional' => AgakColors.goldDark,
              'pending' => AgakColors.goldDark,
              _ =>
                hasMappedRoutes
                    ? AgakColors.olive
                    : AgakColors.ink.withValues(alpha: 0.6),
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
                  hikeWeatherError =
                      'Weather forecast is unavailable right now.';
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

            if (!hasRequestedInitialDetailsLoad) {
              hasRequestedInitialDetailsLoad = true;
              if (mounted && sheetActive) {
                unawaited(loadHikeWeather(sheetSetState, selectedHikeDate));
              }
            }
            return Container(
              height: MediaQuery.of(context).size.height * 0.88,
              decoration: const BoxDecoration(
                color: AgakColors.cream,
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
                        color: AgakColors.ink.withValues(alpha: 0.24),
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
                                color: AgakColors.surfaceRaised,
                                child: const Icon(
                                  Icons.terrain_rounded,
                                  color: AgakColors.maroon,
                                  size: 70,
                                ),
                              )
                            : Image.network(
                                trail.imageUrl!,
                                fit: BoxFit.cover,
                                errorBuilder: (_, _, _) {
                                  return Container(
                                    color: AgakColors.surfaceRaised,
                                    child: const Icon(
                                      Icons.terrain_rounded,
                                      color: AgakColors.maroon,
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
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Expanded(
                                child: Text(
                                  trail.name,
                                  style: const TextStyle(
                                    color: AgakColors.ink,
                                    fontSize: 32,
                                    fontWeight: FontWeight.w800,
                                  ),
                                ),
                              ),
                              IconButton(
                                onPressed: () async {
                                  final nowBookmarked = !isBookmarked;
                                  sheetSetState(() {
                                    isBookmarked = nowBookmarked;
                                  });
                                  if (nowBookmarked) {
                                    await AgakBehaviorDatabase.instance
                                        .addBookmark(
                                          mountainId: trailMatchKey,
                                          mountainName: trail.name,
                                          region: trail.provinceOrCity,
                                          difficulty: trail.difficulty,
                                          elevationMasl: trail.elevationMasl,
                                        );
                                  } else {
                                    await AgakBehaviorDatabase.instance
                                        .removeBookmark(
                                          mountainId: trailMatchKey,
                                          mountainName: trail.name,
                                        );
                                  }
                                  unawaited(AgakController.instance.refresh());
                                },
                                icon: Icon(
                                  isBookmarked
                                      ? Icons.bookmark_rounded
                                      : Icons.bookmark_border_rounded,
                                  color: isBookmarked
                                      ? AgakColors.maroon
                                      : AgakColors.ink.withValues(alpha: 0.6),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 3),
                          Text(
                            '${trail.elevationMasl} MASL',
                            style: const TextStyle(
                              color: AgakColors.ink,
                              fontSize: 20,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            trail.provinceOrCity,
                            style: TextStyle(
                              color: AgakColors.ink.withValues(alpha: 0.7),
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
                              color: AgakColors.ink.withValues(alpha: 0.05),
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
                                color: AgakColors.maroon,
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
                                          ? AgakColors.maroon.withValues(
                                              alpha: 0.12,
                                            )
                                          : AgakColors.ink.withValues(
                                              alpha: 0.04,
                                            ),
                                      borderRadius: BorderRadius.circular(12),
                                      border: Border.all(
                                        color:
                                            selectedRoute?.assetPath ==
                                                route.assetPath
                                            ? AgakColors.maroon
                                            : AgakColors.ink.withValues(
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
                                            color: AgakColors.ink,
                                            fontWeight: FontWeight.w700,
                                          ),
                                        ),
                                        const SizedBox(height: 4),
                                        Text(
                                          'Jump-off: ${route.jumpOffLabel}',
                                          style: TextStyle(
                                            color: AgakColors.ink.withValues(
                                              alpha: 0.7,
                                            ),
                                            fontSize: 12,
                                          ),
                                        ),
                                        const SizedBox(height: 2),
                                        Text(
                                          'Start point: ${_formatLatLngCompact(route.startPoint)}',
                                          style: TextStyle(
                                            color: AgakColors.ink.withValues(
                                              alpha: 0.6,
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
                                color: AgakColors.ink.withValues(alpha: 0.05),
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: Text(
                                hasCommunityRoute
                                    ? 'A community ${trailStatusLabel.toLowerCase()} route is available and will be used in Hiking Mode.'
                                    : 'No mapped trail routes found for this mountain yet.',
                                style: TextStyle(
                                  color: AgakColors.ink.withValues(alpha: 0.7),
                                  fontSize: 12,
                                ),
                              ),
                            ),
                            if (!hasAnyUsableRoute) ...[
                              const SizedBox(height: 10),
                              Container(
                                width: double.infinity,
                                padding: const EdgeInsets.all(14),
                                decoration: BoxDecoration(
                                  color: AgakColors.maroon.withValues(
                                    alpha: 0.08,
                                  ),
                                  borderRadius: BorderRadius.circular(14),
                                  border: Border.all(
                                    color: AgakColors.maroon.withValues(
                                      alpha: 0.36,
                                    ),
                                  ),
                                ),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    const Text(
                                      'Help Map This Trail',
                                      style: TextStyle(
                                        color: AgakColors.ink,
                                        fontWeight: FontWeight.w800,
                                        fontSize: 15,
                                      ),
                                    ),
                                    const SizedBox(height: 5),
                                    Text(
                                      'Record the real path while hiking. Agakbay checks the route automatically before other users see it as a community trail.',
                                      style: TextStyle(
                                        color: AgakColors.ink.withValues(
                                          alpha: 0.68,
                                        ),
                                        height: 1.35,
                                        fontSize: 12,
                                      ),
                                    ),
                                    const SizedBox(height: 12),
                                    SizedBox(
                                      width: double.infinity,
                                      child: OutlinedButton.icon(
                                        onPressed: () {
                                          Navigator.of(context).pop();
                                          unawaited(
                                            _startTrailRecordingForMountain(
                                              trail,
                                            ),
                                          );
                                        },
                                        icon: const Icon(Icons.route_rounded),
                                        label: const Text(
                                          'Record Trail Route',
                                          style: TextStyle(
                                            fontWeight: FontWeight.w800,
                                          ),
                                        ),
                                        style: OutlinedButton.styleFrom(
                                          foregroundColor: AgakColors.maroon,
                                          side: const BorderSide(
                                            color: AgakColors.maroon,
                                          ),
                                          shape: RoundedRectangleBorder(
                                            borderRadius: BorderRadius.circular(
                                              12,
                                            ),
                                          ),
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ],
                          const SizedBox(height: 6),
                          Container(
                            width: double.infinity,
                            padding: const EdgeInsets.all(14),
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(14),
                              border: Border.all(
                                color: AgakColors.ink.withValues(alpha: 0.12),
                              ),
                            ),
                            child: Row(
                              children: [
                                Icon(
                                  trail.status == 'Open'
                                      ? Icons.check_circle_rounded
                                      : Icons.cancel_rounded,
                                  color: trail.status == 'Open'
                                      ? AgakColors.olive
                                      : AgakColors.maroon,
                                ),
                                const SizedBox(width: 10),
                                Text(
                                  trail.status == 'Open'
                                      ? 'OPEN FOR HIKING'
                                      : 'CURRENTLY CLOSED',
                                  style: TextStyle(
                                    color: trail.status == 'Open'
                                        ? AgakColors.olive
                                        : AgakColors.maroon,
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
                              color: AgakColors.maroon,
                              fontSize: 14,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            trail.description,
                            style: TextStyle(
                              color: AgakColors.ink.withValues(alpha: 0.85),
                              height: 1.4,
                            ),
                          ),
                          const SizedBox(height: 14),
                          Container(
                            width: double.infinity,
                            padding: const EdgeInsets.all(14),
                            decoration: BoxDecoration(
                              color: AgakColors.ink.withValues(alpha: 0.04),
                              borderRadius: BorderRadius.circular(14),
                              border: Border.all(
                                color: AgakColors.ink.withValues(alpha: 0.1),
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
                                foregroundColor: AgakColors.goldDark,
                                side: const BorderSide(
                                  color: AgakColors.goldDark,
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
                          height: 48,
                          width: double.infinity,
                          child: OutlinedButton.icon(
                            onPressed: () => _openScheduleHikeDialog(
                              trail,
                              selectedHikeDate,
                            ),
                            icon: const Icon(Icons.event_available_rounded),
                            label: const Text(
                              'Schedule this Hike',
                              style: TextStyle(fontWeight: FontWeight.w800),
                            ),
                            style: OutlinedButton.styleFrom(
                              foregroundColor: AgakColors.olive,
                              side: const BorderSide(color: AgakColors.olive),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(16),
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(height: 8),
                        SizedBox(
                          height: 52,
                          width: double.infinity,
                          child: ElevatedButton.icon(
                            onPressed: () async {
                              if (!hasAnyUsableRoute) {
                                final shouldRecord =
                                    await _showNoTrailRouteDialog(trail.name);
                                if (!mounted || !shouldRecord) {
                                  return;
                                }
                              }
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
                                        recordingNewTrail: !hasAnyUsableRoute,
                                        fetchWeatherSnapshot:
                                            _fetchCurrentWeatherSnapshot,
                                      ),
                                    ),
                                  );
                              if (!mounted || session == null) {
                                return;
                              }
                              // Only counts as "completed" — badge, list,
                              // milestone — once the summit is actually
                              // reached, even for trails auto-recorded
                              // because they had no mapped route yet.
                              setState(() {
                                _rememberTrail(trail);
                                if (session.reachedSummit) {
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
                                      maxElevationMasl:
                                          session.maxElevationMasl,
                                      checkpointsReached:
                                          session.checkpointsReached,
                                      totalCheckpoints:
                                          session.totalCheckpoints,
                                      reachedSummit: session.reachedSummit,
                                    ),
                                  );
                                }
                              });
                              if (session.reachedSummit) {
                                sheetSetState(() => hasCompletedBefore = true);
                                _showDashboardSnackBar(
                                  '${trail.name} hike completed! Great work.',
                                );
                                _recordAgakHikeCompletion(trail, session);
                              } else {
                                _showDashboardSnackBar(
                                  '${trail.name} trail route saved. Reach '
                                  'the summit next time to complete it!',
                                );
                              }
                              unawaited(_recordHikeAttempt(trail, session));
                              unawaited(
                                _updateLeaderboardStats(trail, session),
                              );
                              _pushPostHikeCompanionMessage(trail, session);
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
                              foregroundColor: AgakColors.cream,
                              backgroundColor: AgakColors.maroon,
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

  /// Best-effort "fun fact about this mountain" pop-up, fired when the
  /// user opens a mountain's details. Curated catalog mountains already
  /// have a hand-written description — free, instant, offline. For
  /// anything else (a live Places search result not in the 8-mountain
  /// catalog), falls back to asking Gemini for one short fact; silently
  /// does nothing if that's unavailable or fails, same as every other
  /// AI-enhancement in this app.
  Future<void> _pushMountainTriviaTip(
    _NearbyTrail trail,
    String matchKey,
  ) async {
    try {
      final catalog = await AgakBehaviorDatabase.instance.getCatalog();
      final catalogMatches = catalog
          .where((m) => m.matchKey == matchKey)
          .toList();

      String? trivia;
      if (catalogMatches.isNotEmpty &&
          catalogMatches.first.description.trim().isNotEmpty) {
        trivia = 'Did you know? ${catalogMatches.first.description.trim()}';
      } else {
        final apiKey = await loadGeminiApiKey();
        if (apiKey.isEmpty) {
          return;
        }
        final response = await fetchGeminiResponse(
          apiKey: apiKey,
          systemInstruction:
              'You are AGAK, a friendly bald-eagle hiking companion mascot '
              'for the Agakbay app. Share one short, fun, factual trivia '
              'sentence about the named mountain in Mindanao, Philippines. '
              'Under 25 words. If you are not confident about a real fact '
              'for this specific mountain, reply with exactly an empty '
              'string instead of guessing.',
          prompt: '${trail.name}, ${trail.provinceOrCity}',
          maxOutputTokens: 80,
        );
        final cleaned = response.trim();
        if (cleaned.isEmpty) {
          return;
        }
        trivia = 'Did you know? $cleaned';
      }

      if (!mounted) {
        return;
      }
      AgakTipBus.instance.push(
        AgakTip(emotion: AgakEmotionState.pointingSuggestion, message: trivia),
      );
    } catch (error) {
      debugPrint('AGAK mountain trivia failed: $error');
    }
  }

  Future<void> _openScheduleHikeDialog(
    _NearbyTrail trail,
    DateTime initialDate,
  ) {
    return _promptScheduleHike(
      mountainId: buildMountainMatchKey(
        name: trail.name,
        region: trail.provinceOrCity,
      ),
      mountainName: trail.name,
      region: trail.provinceOrCity,
      difficulty: trail.difficulty,
      elevationMasl: trail.elevationMasl,
      initialDate: initialDate,
    );
  }

  /// Entry point for scheduling a hike without already being on a specific
  /// trail's details sheet (e.g. from the home-screen companion card) —
  /// picks a mountain from the curated catalog first, then reuses the same
  /// date+notes prompt as the details-sheet flow.
  Future<void> _openScheduleHikeFromCatalog() async {
    final catalog = await AgakBehaviorDatabase.instance.getCatalog();
    if (!mounted) return;
    if (catalog.isEmpty) {
      _showDashboardSnackBar('No mountains available to schedule yet.');
      return;
    }

    final chosen = await showDialog<MountainCatalogEntry>(
      context: context,
      builder: (dialogContext) {
        return SimpleDialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(24),
          ),
          titlePadding: const EdgeInsets.fromLTRB(20, 20, 20, 4),
          title: const Text(
            'Schedule a Hike',
            style: TextStyle(fontWeight: FontWeight.w900, fontSize: 19),
          ),
          children: [
            for (final mountain in catalog)
              SimpleDialogOption(
                onPressed: () => Navigator.of(dialogContext).pop(mountain),
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 6),
                  child: Row(
                    children: [
                      Container(
                        width: 38,
                        height: 38,
                        decoration: BoxDecoration(
                          color: const Color(
                            0xFF2F8C5A,
                          ).withValues(alpha: 0.14),
                          borderRadius: BorderRadius.circular(11),
                        ),
                        child: const Icon(
                          Icons.landscape_rounded,
                          size: 19,
                          color: Color(0xFF2F8C5A),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              mountain.name,
                              style: const TextStyle(
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              '${mountain.region} · ${mountain.elevationMasl}m · '
                              '${mountain.difficulty}',
                              style: TextStyle(
                                fontSize: 12,
                                color: Colors.grey.shade600,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
          ],
        );
      },
    );

    if (chosen == null || !mounted) {
      return;
    }

    await _promptScheduleHike(
      mountainId: chosen.matchKey,
      mountainName: chosen.name,
      region: chosen.region,
      difficulty: chosen.difficulty,
      elevationMasl: chosen.elevationMasl,
      initialDate: _dateOnly(DateTime.now()),
    );
  }

  /// Shared date+notes prompt used by both scheduling entry points above.
  Future<void> _promptScheduleHike({
    required String? mountainId,
    required String mountainName,
    required String? region,
    required String difficulty,
    required int elevationMasl,
    required DateTime initialDate,
  }) async {
    final firstDate = _dateOnly(DateTime.now());
    final lastDate = firstDate.add(const Duration(days: 180));
    var chosenDate = initialDate.isBefore(firstDate) ? firstDate : initialDate;
    final notesController = TextEditingController();

    final scheduled = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (dialogContext, dialogSetState) {
            return AlertDialog(
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(24),
              ),
              title: Text(
                'Schedule $mountainName',
                style: const TextStyle(
                  fontWeight: FontWeight.w900,
                  fontSize: 18,
                ),
              ),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 10,
                    ),
                    decoration: BoxDecoration(
                      color: const Color(0xFF53D97A).withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(
                        color: const Color(0xFF53D97A).withValues(alpha: 0.4),
                      ),
                    ),
                    child: Row(
                      children: [
                        const Icon(
                          Icons.calendar_today_rounded,
                          size: 18,
                          color: Color(0xFF2F8C5A),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            _formatHikeDate(chosenDate),
                            style: const TextStyle(fontWeight: FontWeight.w700),
                          ),
                        ),
                        TextButton(
                          onPressed: () async {
                            final picked = await showDatePicker(
                              context: dialogContext,
                              initialDate: chosenDate,
                              firstDate: firstDate,
                              lastDate: lastDate,
                            );
                            if (picked != null) {
                              dialogSetState(() {
                                chosenDate = _dateOnly(picked);
                              });
                            }
                          },
                          child: const Text(
                            'Change',
                            style: TextStyle(fontWeight: FontWeight.w700),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 14),
                  TextField(
                    controller: notesController,
                    maxLines: 2,
                    decoration: InputDecoration(
                      hintText: 'Notes (optional) — e.g. hiking with friends',
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                    ),
                  ),
                ],
              ),
              actionsPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(dialogContext).pop(false),
                  child: const Text('Cancel'),
                ),
                FilledButton(
                  onPressed: () => Navigator.of(dialogContext).pop(true),
                  style: FilledButton.styleFrom(
                    backgroundColor: const Color(0xFF53D97A),
                    foregroundColor: Colors.black,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                  ),
                  child: const Text(
                    'Schedule',
                    style: TextStyle(fontWeight: FontWeight.w800),
                  ),
                ),
              ],
            );
          },
        );
      },
    );

    if (scheduled != true) {
      return;
    }

    final notes = notesController.text.trim();
    try {
      await AgakBehaviorDatabase.instance.scheduleHike(
        mountainId: mountainId,
        mountainName: mountainName,
        region: region,
        difficulty: difficulty,
        elevationMasl: elevationMasl,
        scheduledDate: chosenDate,
        notes: notes.isEmpty ? null : notes,
      );
      unawaited(AgakController.instance.refresh(force: true));
      if (!mounted) {
        return;
      }
      _showDashboardSnackBar(
        '$mountainName scheduled for ${_formatHikeDate(chosenDate)}.',
      );
    } catch (error) {
      debugPrint('scheduleHike failed: $error');
      if (!mounted) {
        return;
      }
      _showDashboardSnackBar("Couldn't save that hike — please try again.");
    }
  }

  Widget _detailStatCard({required String label, required String value}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 12),
      decoration: BoxDecoration(
        color: AgakColors.ink.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: TextStyle(
              color: AgakColors.ink.withValues(alpha: 0.6),
              fontSize: 12,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            value,
            style: const TextStyle(
              color: AgakColors.ink,
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
        ? AgakColors.maroon
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
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: riskColor.withValues(alpha: 0.34)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Select Hike Date',
            style: TextStyle(
              color: AgakColors.ink,
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
              color: AgakColors.surfaceRaised,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: AgakColors.ink.withValues(alpha: 0.08)),
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
                              color: AgakColors.ink,
                              fontSize: 15,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            _formatHikeDate(selectedDate),
                            style: TextStyle(
                              color: AgakColors.ink.withValues(alpha: 0.68),
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
                          color: AgakColors.maroon,
                        ),
                      ),
                      const SizedBox(width: 10),
                      Text(
                        'Checking mountain weather...',
                        style: TextStyle(
                          color: AgakColors.ink.withValues(alpha: 0.82),
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
                            color: AgakColors.ink,
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
                      color: AgakColors.ink.withValues(alpha: 0.88),
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
                            color: AgakColors.ink.withValues(alpha: 0.82),
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
                        color: AgakColors.goldDark,
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
                        foregroundColor: AgakColors.maroon,
                        side: BorderSide(
                          color: AgakColors.maroon.withValues(alpha: 0.55),
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
        color: AgakColors.surfaceRaised,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AgakColors.ink.withValues(alpha: 0.08)),
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
                      color: AgakColors.ink,
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
          const Row(
            children: [
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
                color: AgakColors.ink.withValues(alpha: 0.56),
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
        color: AgakColors.maroon,
        disabledColor: AgakColors.ink.withValues(alpha: 0.18),
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
                  ? AgakColors.maroon
                  : isToday
                  ? AgakColors.maroon.withValues(alpha: 0.16)
                  : Colors.transparent,
              borderRadius: BorderRadius.circular(9),
              border: isToday && !isSelected
                  ? Border.all(color: AgakColors.maroon.withValues(alpha: 0.55))
                  : null,
            ),
            child: Text(
              dayNumber.toString(),
              style: TextStyle(
                color: !isEnabled
                    ? AgakColors.ink.withValues(alpha: 0.18)
                    : isSelected
                    ? AgakColors.cream
                    : AgakColors.ink,
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
        color: AgakColors.ink.withValues(alpha: 0.72),
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
        color: AgakColors.ink.withValues(alpha: 0.055),
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
                    color: AgakColors.ink,
                    fontSize: 12,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  '${outlook.summary}, ${outlook.temperatureLabel}$rainText',
                  style: TextStyle(
                    color: AgakColors.ink.withValues(alpha: 0.74),
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
      _HikeWeatherRisk.good => AgakColors.olive,
      _HikeWeatherRisk.caution => AgakColors.goldDark,
      _HikeWeatherRisk.unsafe => AgakColors.maroon,
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
              color: AgakColors.ink.withValues(alpha: 0.68),
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            value.isEmpty ? '-' : value,
            style: const TextStyle(color: AgakColors.ink),
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
    this.recordingNewTrail = false,
    this.fetchWeatherSnapshot,
  });

  final _NearbyTrail trail;
  final String mapsApiKey;
  final _CommunityTrailData? communityTrail;
  final String? preferredGpxAssetPath;
  final String? selectedRouteLabel;
  final bool recordingNewTrail;

  /// Reuses the dashboard's single weather-check implementation (same API
  /// key, same risk classification) instead of duplicating it here — this
  /// screen just calls it periodically with the live hike location. Null
  /// (shouldn't happen in practice, but keeps this screen decoupled) means
  /// mid-hike weather re-checks are silently skipped.
  final Future<AgakWeatherSnapshot?> Function(LatLng location)?
  fetchWeatherSnapshot;

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
  final Set<String> _approachingAnnounced = <String>{};
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
  int _lastAnnouncedKm = 0;
  int _motivationTipIndex = 0;
  double? _currentHeadingDegrees;
  DateTime? _lastWrongWayWarningAt;
  DateTime _lastMovementAt = DateTime.now();
  DateTime? _lastStillCheckInAt;

  // Rough max footprint (bubble + gap + character) used only to keep the
  // draggable Kyrielle presence fully within the map area — doesn't need
  // to be pixel-exact, same idea as the dashboard's _agakFootprint.
  static const Size _kyrielleFootprint = Size(260, 320);
  Offset? _kyrielleOffset;

  static const _motivationMessages = <String>[
    "You're doing amazing out there — keep that pace up!",
    "Every step counts. Enjoy the trail!",
    "Stay hydrated and keep enjoying the climb!",
    "You've got this — one step at a time!",
    'Beautiful hike so far — keep pushing forward!',
  ];

  // Course-over-ground (GPS heading) is only meaningful while actually
  // walking at a reasonable pace with a decent fix — otherwise it's noise.
  static const _minSpeedForHeadingMps = 0.6;
  static const _maxAccuracyForHeadingMeters = 30.0;
  static const _wrongWayAngleThresholdDegrees = 110.0;
  // Smaller drift gets a gentle "turn left/right" nudge rather than the
  // full "wrong way, turn around" — reads like a companion correcting your
  // line, not alarming you over a normal switchback.
  static const _driftAngleThresholdDegrees = 35.0;
  static const _wrongWayCooldown = Duration(minutes: 2);

  // How far out (along the route, or straight-line as a fallback) Kyrielle
  // gives a heads-up that the next station is coming up — well before the
  // tighter arrival threshold in the checkpoint loop below actually marks
  // it reached, so it reads as "almost there" rather than "you're here."
  static const _approachingThresholdMeters = 500.0;

  // How long without meaningful movement before AGAK checks in — and, if
  // the hiker stays put, how often it asks again afterward.
  static const _stillCheckInThreshold = Duration(minutes: 8);

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
      if (_elapsed.inSeconds > 0 && _elapsed.inSeconds % 60 == 0) {
        _pushMinuteMotivationTip();
      }
      if (_elapsed.inSeconds > 0 && _elapsed.inSeconds % 600 == 0) {
        unawaited(_checkMidHikeWeather());
      }
      _maybePushStillCheckIn();
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
      debugPrint(
        'DEBUG hike-start: about to push greeting, bus version before push '
        'is ${AgakTipBus.instance.version}',
      );
      AgakTipBus.instance.push(
        AgakTip(
          emotion: AgakEmotionState.pointingSuggestion,
          message:
              'Ready to take on ${widget.trail.name}? I\'ll be right '
              'here with you the whole way up!',
          choices: [
            AgakTipChoice(
              label: "Let's go!",
              onSelected: () {
                final packingPreview = buildPackingList(
                  difficulty: widget.trail.difficulty,
                  elevationMasl: widget.trail.elevationMasl,
                ).take(3).join(', ');
                AgakTipBus.instance.push(
                  AgakTip(
                    emotion: AgakEmotionState.encouragement,
                    message:
                        "That's the spirit! CAW-CAW — let's climb! Quick "
                        'check before you go: $packingPreview, and the '
                        'usual essentials.',
                    scope: AgakTipScope.hikingOnly,
                  ),
                );
              },
            ),
            AgakTipChoice(
              label: 'Give me a sec',
              onSelected: () => AgakTipBus.instance.push(
                const AgakTip(
                  emotion: AgakEmotionState.pointingSuggestion,
                  message: "Take your time — I'm not going anywhere.",
                  scope: AgakTipScope.hikingOnly,
                ),
              ),
            ),
          ],
          scope: AgakTipScope.hikingOnly,
        ),
      );
      debugPrint(
        'DEBUG hike-start: greeting pushed, bus version after push is '
        '${AgakTipBus.instance.version}',
      );
    } catch (error, stackTrace) {
      debugPrint('Hiking Mode failed to start: $error\n$stackTrace');
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

  void _pushMinuteMotivationTip() {
    final message =
        _motivationMessages[_motivationTipIndex % _motivationMessages.length];
    _motivationTipIndex++;
    AgakTipBus.instance.push(
      AgakTip(
        emotion: AgakEmotionState.encouragement,
        message: message,
        scope: AgakTipScope.hikingOnly,
      ),
    );
  }

  /// Checks whether it's time for AGAK to ask if the hiker is okay — fires
  /// once after [_stillCheckInThreshold] of no meaningful movement, then
  /// again every full threshold period of continued stillness (reset by
  /// [_lastStillCheckInAt] going back to null the moment real movement is
  /// detected in `_updateFromPosition`).
  void _maybePushStillCheckIn() {
    final stillFor = DateTime.now().difference(_lastMovementAt);
    if (stillFor < _stillCheckInThreshold) {
      return;
    }
    final lastCheckIn = _lastStillCheckInAt;
    if (lastCheckIn != null &&
        DateTime.now().difference(lastCheckIn) < _stillCheckInThreshold) {
      return;
    }
    _lastStillCheckInAt = DateTime.now();
    AgakTipBus.instance.push(
      AgakTip(
        emotion: AgakEmotionState.pointingSuggestion,
        message: "You haven't moved in a while — everything okay out there?",
        choices: [
          AgakTipChoice(
            label: "I'm okay!",
            onSelected: () => _respondToStillCheckIn(imOkay: true),
          ),
          AgakTipChoice(
            label: 'Just resting',
            onSelected: () => _respondToStillCheckIn(imOkay: false),
          ),
        ],
        scope: AgakTipScope.hikingOnly,
      ),
    );
  }

  void _respondToStillCheckIn({required bool imOkay}) {
    AgakTipBus.instance.push(
      AgakTip(
        emotion: imOkay
            ? AgakEmotionState.encouragement
            : AgakEmotionState.pointingSuggestion,
        message: imOkay
            ? "Good to hear! Whenever you're ready, I'll be right here."
            : "Take all the time you need — I'll keep an eye on things.",
        scope: AgakTipScope.hikingOnly,
      ),
    );
  }

  /// Re-checks weather at the live hike location every ~10 minutes so a
  /// change in conditions (rain moving in) gets flagged mid-hike, not just
  /// once back on the dashboard before the hike even started. Silently
  /// skipped offline or if there's nothing actionable to say — this never
  /// announces "still fine," only real changes worth reacting to, so it
  /// doesn't compete with the km/checkpoint/minute tips already firing.
  Future<void> _checkMidHikeWeather() async {
    final fetchSnapshot = widget.fetchWeatherSnapshot;
    final location = _currentLocation;
    if (fetchSnapshot == null || location == null || !_hasNetworkConnection) {
      return;
    }
    try {
      final snapshot = await fetchSnapshot(location);
      if (!mounted || snapshot == null) {
        return;
      }
      if (snapshot.isSevere) {
        AgakTipBus.instance.push(
          AgakTip(
            emotion: AgakEmotionState.discouraging,
            message:
                '${snapshot.headline}! Consider finding shelter or heading '
                'back if it gets worse.',
            scope: AgakTipScope.hikingOnly,
          ),
        );
      } else if (snapshot.isCaution) {
        AgakTipBus.instance.push(
          AgakTip(
            emotion: AgakEmotionState.discouraging,
            message:
                '${snapshot.headline} — rain could be on the way. Might '
                'be a good time to put on your rain gear!',
            scope: AgakTipScope.hikingOnly,
          ),
        );
      }
    } catch (error) {
      debugPrint('Mid-hike weather check failed: $error');
    }
  }

  void _pushKmMilestoneTip(int km) {
    AgakTipBus.instance.push(
      AgakTip(
        emotion: AgakEmotionState.encouragement,
        message: km == 1
            ? "You've hiked 1 km! Great start, keep it up!"
            : '$km km down! Your pace is solid — keep going!',
        scope: AgakTipScope.hikingOnly,
      ),
    );
  }

  void _pushApproachingCheckpointTip(_HikeCheckpoint checkpoint) {
    AgakTipBus.instance.push(
      AgakTip(
        emotion: AgakEmotionState.encouragement,
        message: checkpoint.isSummit
            ? "Almost there! The peak — ${checkpoint.name} — is coming up. You've got this!"
            : "Almost there! ${checkpoint.name} is coming up — keep going!",
        scope: AgakTipScope.hikingOnly,
      ),
    );
  }

  void _pushCheckpointTip(_HikeCheckpoint checkpoint) {
    if (checkpoint.isSummit) {
      AgakTipBus.instance.push(
        AgakTip(
          emotion: AgakEmotionState.celebration,
          message:
              'CAW-CAW! You made it to the peak — ${checkpoint.name} '
              'conquered! Incredible work!',
          scope: AgakTipScope.hikingOnly,
        ),
      );
    } else {
      AgakTipBus.instance.push(
        AgakTip(
          emotion: AgakEmotionState.rewardReveal,
          message: 'Checkpoint reached: ${checkpoint.name}! Nice progress.',
          scope: AgakTipScope.hikingOnly,
        ),
      );
    }
  }

  /// Turn-by-turn-style course check — compares the direction you're
  /// actually walking (GPS course-over-ground) against the bearing toward
  /// a point further up the planned trail, and speaks up like a real hiking
  /// buddy: a gentle "turn left/right a bit" for normal drift, escalating
  /// to "wrong way, turn around" only when you're basically facing away
  /// from the trail. Only once every couple of minutes, so a single noisy
  /// GPS reading can't nag.
  void _checkWrongDirection(Position position) {
    if (_plannedRoutePoints.isEmpty) {
      return;
    }
    final now = DateTime.now();
    final lastWarnedAt = _lastWrongWayWarningAt;
    if (lastWarnedAt != null &&
        now.difference(lastWarnedAt) < _wrongWayCooldown) {
      return;
    }

    final lookaheadIndex = (_activeRouteIndex + 3).clamp(
      0,
      _plannedRoutePoints.length - 1,
    );
    final target = _plannedRoutePoints[lookaheadIndex];
    if (Geolocator.distanceBetween(
          position.latitude,
          position.longitude,
          target.latitude,
          target.longitude,
        ) <
        20) {
      // Already basically at the lookahead point — nothing meaningful to
      // compare against.
      return;
    }

    final bearingToTarget = Geolocator.bearingBetween(
      position.latitude,
      position.longitude,
      target.latitude,
      target.longitude,
    );
    final normalizedBearing = (bearingToTarget + 360) % 360;
    final normalizedHeading = (position.heading + 360) % 360;
    // Signed delta in (-180, 180]: positive means the trail is clockwise
    // from where you're facing (turn right), negative means counter-
    // clockwise (turn left).
    var delta = normalizedBearing - normalizedHeading;
    if (delta > 180) {
      delta -= 360;
    } else if (delta < -180) {
      delta += 360;
    }
    final diff = delta.abs();

    if (diff >= _wrongWayAngleThresholdDegrees) {
      _lastWrongWayWarningAt = now;
      AgakTipBus.instance.push(
        const AgakTip(
          emotion: AgakEmotionState.discouraging,
          message: "Whoa, wrong way! Turn around and head back onto the trail.",
          scope: AgakTipScope.hikingOnly,
        ),
      );
    } else if (diff >= _driftAngleThresholdDegrees) {
      _lastWrongWayWarningAt = now;
      final direction = delta > 0 ? 'right' : 'left';
      AgakTipBus.instance.push(
        AgakTip(
          emotion: AgakEmotionState.pointingSuggestion,
          message: "Turn $direction a bit — you're drifting off the trail.",
          scope: AgakTipScope.hikingOnly,
        ),
      );
    }
  }

  void _updateFromPosition(Position position, {bool isInitial = false}) {
    if (!mounted) {
      return;
    }

    final currentPoint = LatLng(position.latitude, position.longitude);
    var segmentMeters = 0.0;
    var shouldPersistPoint = false;
    int? kmJustReached;
    _HikeCheckpoint? checkpointJustReached;
    _HikeCheckpoint? checkpointNowApproaching;
    final previous = _lastPosition;
    if (previous != null) {
      segmentMeters = Geolocator.distanceBetween(
        previous.latitude,
        previous.longitude,
        position.latitude,
        position.longitude,
      );
    }

    // Course-over-ground only means something while actually walking with
    // a decent fix — otherwise it's noise, so the arrow/wrong-way check
    // simply keeps showing the last known good heading instead.
    final hasReliableHeading =
        position.heading.isFinite &&
        position.speed.isFinite &&
        position.speed >= _minSpeedForHeadingMps &&
        position.accuracy.isFinite &&
        position.accuracy <= _maxAccuracyForHeadingMeters;

    setState(() {
      if (hasReliableHeading) {
        _currentHeadingDegrees = position.heading;
      }
      if (!isInitial && segmentMeters >= 2 && segmentMeters <= 250) {
        _trackedDistanceMeters += segmentMeters;
        _lastMovementAt = DateTime.now();
        _lastStillCheckInAt = null;
        final currentKm = (_trackedDistanceMeters / 1000).floor();
        if (currentKm > _lastAnnouncedKm && currentKm > 0) {
          _lastAnnouncedKm = currentKm;
          kmJustReached = currentKm;
        }
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
        // The summit specifically requires genuine movement this session —
        // otherwise a mountain whose (possibly placeholder/inaccurate)
        // target coordinate happens to sit near wherever the hike started
        // gets credited as "summited" on the very first GPS fix, before
        // any actual hiking happened.
        final meaningfulDistanceWalked =
            !checkpoint.isSummit || _trackedDistanceMeters >= 100;
        if (meaningfulDistanceWalked &&
            (alongRouteMeters <= threshold || directMeters <= threshold)) {
          _reachedCheckpoints.add(checkpoint.name);
          _approachingAnnounced.add(checkpoint.name);
          checkpointJustReached ??= checkpoint;
        } else if ((alongRouteMeters <= _approachingThresholdMeters ||
                directMeters <= _approachingThresholdMeters) &&
            _approachingAnnounced.add(checkpoint.name)) {
          checkpointNowApproaching ??= checkpoint;
        }
      }
    });

    if (kmJustReached != null) {
      _pushKmMilestoneTip(kmJustReached!);
    }
    if (checkpointNowApproaching != null) {
      _pushApproachingCheckpointTip(checkpointNowApproaching!);
    }
    if (checkpointJustReached != null) {
      _pushCheckpointTip(checkpointJustReached!);
    }
    if (hasReliableHeading) {
      _checkWrongDirection(position);
    }

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

    final confirmed = await _showAgakConfirmDialog(
      context,
      icon: Icons.sos_rounded,
      title: 'Send SOS Alert?',
      message:
          'This will prepare an emergency SOS with your identity and GPS '
          'coordinates.\n\n'
          'Hiker: ${_sosSenderName()}\n'
          'Trail: ${widget.trail.name}\n'
          'Latitude: ${location.latitude.toStringAsFixed(6)}\n'
          'Longitude: ${location.longitude.toStringAsFixed(6)}\n\n'
          'Bluetooth/LoRa transmission will be connected in the next step.',
      cancelLabel: 'Cancel',
      confirmLabel: 'Send SOS',
      confirmIcon: Icons.sos_rounded,
    );

    if (confirmed) {
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
        backgroundColor: AgakColors.maroon,
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
      final heading = _currentHeadingDegrees;
      markers.add(
        fm.Marker(
          point: _offlineLatLng(current),
          width: 42,
          height: 42,
          child: heading == null
              ? const Icon(
                  Icons.my_location_rounded,
                  color: Color(0xFF2CA9FF),
                  size: 34,
                )
              : Transform.rotate(
                  angle: heading * (math.pi / 180),
                  child: const Icon(
                    Icons.navigation_rounded,
                    color: Color(0xFF2CA9FF),
                    size: 34,
                  ),
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

  List<LatLng> _recordedRoutePointsForSubmission() {
    if (_trackPoints.length >= 2) {
      return List<LatLng>.from(_trackPoints);
    }
    final fromRawTrack = _rawTrackPoints
        .map((point) => LatLng(point.lat, point.lon))
        .toList(growable: false);
    if (fromRawTrack.length >= 2) {
      return fromRawTrack;
    }
    return List<LatLng>.from(_plannedRoutePoints);
  }

  bool get _hasReachedFinish {
    if (_reachedCheckpoints.contains('Peak')) {
      return true;
    }
    // Same guard as the checkpoint loop — no crediting a finish you never
    // actually walked to.
    if (_trackedDistanceMeters < 100) {
      return false;
    }
    final currentLocation = _currentLocation;
    final target = _hikeTarget ?? widget.trail.location;
    if (currentLocation == null) {
      return false;
    }
    final distanceToTarget = Geolocator.distanceBetween(
      currentLocation.latitude,
      currentLocation.longitude,
      target.latitude,
      target.longitude,
    );
    return distanceToTarget <= 160;
  }

  Future<bool> _confirmEarlyEndHike() async {
    if (widget.recordingNewTrail || _hasReachedFinish) {
      return true;
    }
    final remainingKm = _remainingRouteDistanceKm();
    final remainingText = remainingKm == null
        ? 'the finish'
        : 'about ${remainingKm.toStringAsFixed(2)} km from the finish';
    return _showAgakConfirmDialog(
      context,
      icon: Icons.flag_circle_rounded,
      title: 'Finish Not Reached',
      message:
          'You are not yet at the route finish or summit — you are '
          '$remainingText. If you stop now, this hike will not be '
          'recorded as completed.',
      cancelLabel: 'Keep Hiking',
      confirmLabel: 'Stop Anyway',
    );
  }

  Future<void> _endHike() async {
    if (_ending) {
      return;
    }
    setState(() => _ending = true);

    final shouldEnd = await _confirmEarlyEndHike();
    if (!shouldEnd) {
      if (mounted) {
        setState(() => _ending = false);
      }
      return;
    }

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
      routePoints: _recordedRoutePointsForSubmission(),
      peakLocation: _hikeTarget ?? widget.trail.location,
      startedAt: _startedAt,
      endedAt: endedAt,
    );
    if (!mounted) {
      return;
    }

    final shouldRecordCompletedHike =
        widget.recordingNewTrail || _hasReachedFinish;
    if (!shouldRecordCompletedHike) {
      Navigator.of(context).pop(null);
      return;
    }

    Navigator.of(context).pop(result);
  }

  Widget _metricCard(String label, String value) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        decoration: BoxDecoration(
          color: AgakColors.surface,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AgakColors.ink.withValues(alpha: 0.1)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              label,
              style: TextStyle(
                color: AgakColors.ink.withValues(alpha: 0.6),
                fontSize: 11,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              value,
              style: const TextStyle(
                color: AgakColors.ink,
                fontSize: 16,
                fontWeight: FontWeight.w800,
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
        ? AgakColors.olive
        : AgakColors.goldDark;

    return Scaffold(
      body: Container(
        decoration: BoxDecoration(gradient: AgakColors.screenBackground),
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
            child: Column(
              children: [
                Row(
                  children: [
                    IconButton(
                      onPressed: () => Navigator.of(context).pop(),
                      icon: const Icon(Icons.arrow_back_rounded),
                      color: AgakColors.ink,
                    ),
                    const SizedBox(width: 4),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            widget.recordingNewTrail
                                ? 'Trail Recording'
                                : 'Hiking Mode',
                            style: const TextStyle(
                              color: AgakColors.maroon,
                              fontSize: 12,
                              fontWeight: FontWeight.w800,
                              letterSpacing: 0.8,
                            ),
                          ),
                          Text(
                            widget.trail.name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: AgakColors.ink,
                              fontSize: 18,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                          Text(
                            widget.recordingNewTrail
                                ? 'Recording your walked GPS trail'
                                : _usingCommunityTrail
                                ? 'Trail source: Community (${widget.communityTrail?.status ?? 'unknown'})'
                                : _usingGpxTrail
                                ? () {
                                    final label = widget.selectedRouteLabel
                                        ?.trim();
                                    final source =
                                        (label != null && label.isNotEmpty)
                                        ? label
                                        : (_gpxTrailAssetPath
                                                  ?.split('/')
                                                  .last ??
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
                              color: AgakColors.ink.withValues(alpha: 0.62),
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
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
                    child: LayoutBuilder(
                      builder: (context, mapConstraints) {
                        final mapSize = mapConstraints.biggest;
                        _kyrielleOffset ??= const Offset(10, 56);
                        return Stack(
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
                                  color: AgakColors.ink.withValues(alpha: 0.72),
                                  borderRadius: BorderRadius.circular(10),
                                  border: Border.all(
                                    color: trackingStatusColor.withValues(
                                      alpha: 0.7,
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
                            Positioned(
                              left: _kyrielleOffset!.dx,
                              top: _kyrielleOffset!.dy,
                              child: AgakTipPopup(
                                onDragDelta: (delta) {
                                  setState(() {
                                    final maxX =
                                        mapSize.width -
                                        _kyrielleFootprint.width -
                                        4;
                                    final maxY =
                                        mapSize.height -
                                        _kyrielleFootprint.height -
                                        4;
                                    _kyrielleOffset = Offset(
                                      (_kyrielleOffset!.dx + delta.dx).clamp(
                                        4.0,
                                        maxX < 4.0 ? 4.0 : maxX,
                                      ),
                                      (_kyrielleOffset!.dy + delta.dy).clamp(
                                        4.0,
                                        maxY < 4.0 ? 4.0 : maxY,
                                      ),
                                    );
                                  });
                                },
                              ),
                            ),
                            if (_initializing)
                              Container(
                                color: AgakColors.ink.withValues(alpha: 0.45),
                                alignment: Alignment.center,
                                child: const CircularProgressIndicator(
                                  color: AgakColors.gold,
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
                                    color: AgakColors.maroon.withValues(
                                      alpha: 0.92,
                                    ),
                                    borderRadius: BorderRadius.circular(10),
                                    border: Border.all(
                                      color: AgakColors.gold.withValues(
                                        alpha: 0.7,
                                      ),
                                    ),
                                  ),
                                  child: Text(
                                    _errorMessage!,
                                    style: const TextStyle(
                                      color: AgakColors.cream,
                                    ),
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
                                  color: AgakColors.ink.withValues(alpha: 0.72),
                                  borderRadius: BorderRadius.circular(10),
                                ),
                                child: Row(
                                  children: [
                                    Expanded(
                                      child: Text(
                                        'Current Elev: $currentElevationText',
                                        style: const TextStyle(
                                          color: AgakColors.cream,
                                        ),
                                      ),
                                    ),
                                    Expanded(
                                      child: Text(
                                        'Peak: $peakMasl MASL',
                                        textAlign: TextAlign.right,
                                        style: const TextStyle(
                                          color: AgakColors.cream,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ],
                        );
                      },
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
                          backgroundColor: AgakColors.maroon,
                          foregroundColor: AgakColors.cream,
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
                          backgroundColor: AgakColors.ink,
                          foregroundColor: AgakColors.cream,
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
        decoration: BoxDecoration(gradient: AgakColors.screenBackground),
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
                        color: AgakColors.ink,
                      ),
                      const SizedBox(height: 12),
                      Text(
                        'Forgot Password',
                        style: Theme.of(context).textTheme.headlineMedium
                            ?.copyWith(
                              color: AgakColors.ink,
                              fontWeight: FontWeight.w800,
                            ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Enter your registered email. We will send a secure reset link.',
                        style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                          color: AgakColors.maroon,
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
                            backgroundColor: AgakColors.maroon,
                            foregroundColor: AgakColors.cream,
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
                                    color: AgakColors.cream,
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
        color: AgakColors.ink.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AgakColors.ink.withValues(alpha: 0.12)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Choose account type',
            style: TextStyle(
              color: AgakColors.ink.withValues(alpha: 0.82),
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
                ? AgakColors.maroon.withValues(alpha: 0.16)
                : AgakColors.ink.withValues(alpha: 0.04),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: isSelected
                  ? AgakColors.maroon
                  : AgakColors.ink.withValues(alpha: 0.1),
            ),
          ),
          child: Row(
            children: [
              Icon(
                icon,
                color: isSelected
                    ? AgakColors.maroon
                    : AgakColors.ink.withValues(alpha: 0.7),
                size: 22,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: isSelected ? AgakColors.maroon : AgakColors.ink,
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
        decoration: BoxDecoration(gradient: AgakColors.screenBackground),
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
                        color: AgakColors.ink,
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
                              colors: [AgakColors.olive, AgakColors.maroon],
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
                                color: AgakColors.ink,
                              ),
                        ),
                      ),
                      const SizedBox(height: 8),
                      Center(
                        child: Text(
                          'Fill in your details to get started.',
                          style: Theme.of(context).textTheme.bodyLarge
                              ?.copyWith(color: AgakColors.maroon),
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
                            color: AgakColors.ink.withValues(alpha: 0.66),
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
                            color: AgakColors.ink.withValues(alpha: 0.66),
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
                            backgroundColor: AgakColors.maroon,
                            foregroundColor: AgakColors.cream,
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
                                    color: AgakColors.cream,
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
        final uid = FirebaseAuth.instance.currentUser?.uid;
        final onboarded = uid == null
            ? true
            : await OnboardingService().hasCompletedOnboarding(uid);
        if (!mounted) {
          return;
        }
        Navigator.of(context).pushAndRemoveUntil(
          MaterialPageRoute<void>(
            builder: (context) => onboarded
                ? const DashboardScreen()
                : const OnboardingFlowScreen(),
          ),
          (route) => false,
        );
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
        decoration: BoxDecoration(gradient: AgakColors.screenBackground),
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
                        color: AgakColors.ink,
                      ),
                      const SizedBox(height: 10),
                      Text(
                        'Verify Your Email',
                        style: Theme.of(context).textTheme.headlineMedium
                            ?.copyWith(
                              color: AgakColors.ink,
                              fontWeight: FontWeight.w800,
                            ),
                      ),
                      const SizedBox(height: 10),
                      Text(
                        'Click the verification link sent to:',
                        style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                          color: AgakColors.maroon,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        widget.email,
                        style: const TextStyle(
                          color: AgakColors.ink,
                          fontWeight: FontWeight.w700,
                          fontSize: 17,
                        ),
                      ),
                      const SizedBox(height: 30),
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: AgakColors.ink.withValues(alpha: 0.05),
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(
                            color: AgakColors.ink.withValues(alpha: 0.15),
                          ),
                        ),
                        child: Text(
                          'After tapping the link in your email, return here and press "I HAVE VERIFIED".',
                          style: TextStyle(
                            color: AgakColors.ink.withValues(alpha: 0.85),
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
                              color: AgakColors.ink.withValues(alpha: 0.66),
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
                            backgroundColor: AgakColors.maroon,
                            foregroundColor: AgakColors.cream,
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
                                    color: AgakColors.cream,
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
      style: const TextStyle(color: AgakColors.ink, fontSize: 21),
      cursorColor: AgakColors.olive,
      decoration: InputDecoration(
        hintText: hint,
        hintStyle: TextStyle(color: AgakColors.ink.withValues(alpha: 0.48)),
        prefixIcon: Icon(icon, color: AgakColors.olive, size: 25),
        suffixIcon: suffix,
        filled: true,
        fillColor: Colors.white.withValues(alpha: 0.55),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(18),
          borderSide: BorderSide(color: AgakColors.ink.withValues(alpha: 0.18)),
        ),
        focusedBorder: const OutlineInputBorder(
          borderRadius: BorderRadius.all(Radius.circular(18)),
          borderSide: BorderSide(color: AgakColors.olive),
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
        color: Colors.white.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        children: [
          Icon(icon, color: AgakColors.olive, size: 18),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              label,
              style: const TextStyle(
                color: AgakColors.ink,
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

class _SheetLoading extends StatelessWidget {
  const _SheetLoading();

  @override
  Widget build(BuildContext context) {
    return const Padding(
      padding: EdgeInsets.symmetric(vertical: 28),
      child: Center(
        child: CircularProgressIndicator(
          strokeWidth: 2.4,
          color: Color(0xFF7CF9A2),
        ),
      ),
    );
  }
}
