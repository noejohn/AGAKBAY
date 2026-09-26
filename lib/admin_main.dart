// Separate entry point for the Admin Web dashboard — run/build it with:
//   flutter run -t lib/admin_main.dart -d chrome --web-port 3000
//   flutter build web -t lib/admin_main.dart
// It shares this package's services (AdminPasswordAuthService, Firebase
// config) but not lib/main.dart's mobile hiker/guide UI — the mobile app
// and the admin dashboard are two different apps built from one codebase.
//
// Sign-in is plain Firebase email/password — no Auth0 involved on this
// side (the mobile app's Auth0 bridge is separate and untouched). See
// AdminPasswordAuthService for why that's still a real access gate and
// not just a password box.
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';

import 'admin/admin_dashboard_shell.dart';
import 'firebase_options.dart';
import 'services/admin_password_auth_service.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  runApp(const AdminApp());
}

class AdminColors {
  static const backgroundTop = Color(0xFF16342A);
  static const backgroundBottom = Color(0xFF070B09);
  static const accent = Color(0xFF1FA35C);
  static const accentDim = Color(0x331FA35C);
}

class AdminApp extends StatelessWidget {
  const AdminApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'AGAKBAY Admin',
      theme: ThemeData(useMaterial3: true, colorSchemeSeed: AdminColors.accent),
      home: const AdminLoginScreen(),
    );
  }
}

class AdminLoginScreen extends StatefulWidget {
  const AdminLoginScreen({super.key});

  @override
  State<AdminLoginScreen> createState() => _AdminLoginScreenState();
}

class _AdminLoginScreenState extends State<AdminLoginScreen> {
  final _adminAuth = AdminPasswordAuthService();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  User? _user;
  bool _restoring = true;
  bool _signingIn = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _restoreSession();
  }

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _restoreSession() async {
    // Firebase persists the session in the browser, so a page reload
    // resolves the current user asynchronously rather than instantly.
    try {
      final persistedUser = await FirebaseAuth.instance.authStateChanges().first;
      final user = persistedUser == null
          ? null
          : await _adminAuth.validateAdmin(persistedUser);
      if (!mounted) return;
      setState(() {
        _user = user;
        _restoring = false;
      });
    } on FirebaseAuthException catch (error) {
      if (!mounted) return;
      setState(() {
        _user = null;
        _error = error.message ?? 'Please verify your email before signing in.';
        _restoring = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _user = null;
        _error = 'Could not restore the admin session. Please sign in again.';
        _restoring = false;
      });
    }
  }

  Future<void> _signIn() async {
    setState(() {
      _signingIn = true;
      _error = null;
    });
    try {
      final user = await _adminAuth.signIn(
        email: _emailController.text.trim(),
        password: _passwordController.text,
      );
      if (!mounted) {
        return;
      }
      setState(() => _user = user);
    } on FirebaseAuthException catch (e) {
      if (!mounted) {
        return;
      }
      setState(() => _error = e.message ?? 'Sign-in failed.');
    } catch (e) {
      if (!mounted) {
        return;
      }
      setState(() => _error = e.toString());
    } finally {
      if (mounted) {
        setState(() => _signingIn = false);
      }
    }
  }

  Future<void> _signOut() async {
    await _adminAuth.signOut();
    if (!mounted) {
      return;
    }
    setState(() => _user = null);
  }

  @override
  Widget build(BuildContext context) {
    if (!_restoring && _user != null) {
      // The dashboard shell fills the whole viewport with its own sidebar
      // + content layout — it doesn't use the login screen's centered
      // card/gradient chrome below.
      return Scaffold(body: AdminDashboardShell(user: _user!, onSignOut: _signOut));
    }
    return Scaffold(
      body: Container(
        width: double.infinity,
        height: double.infinity,
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [AdminColors.backgroundTop, AdminColors.backgroundBottom],
          ),
        ),
        child: Stack(
          children: [
            const Positioned.fill(child: CustomPaint(painter: _MountainPainter())),
            Center(
              child: SingleChildScrollView(
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 40),
                child: _restoring
                    ? const CircularProgressIndicator(color: Colors.white)
                    : _SignInCard(
                        emailController: _emailController,
                        passwordController: _passwordController,
                        loading: _signingIn,
                        error: _error,
                        onSignIn: _signIn,
                      ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Faint overlapping mountain silhouettes anchored to the bottom of the
/// screen — purely decorative, matches the AGAKBAY hiking-app branding.
class _MountainPainter extends CustomPainter {
  const _MountainPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..color = Colors.white.withValues(alpha: 0.04);
    final back = Path()
      ..moveTo(0, size.height)
      ..lineTo(size.width * 0.22, size.height * 0.62)
      ..lineTo(size.width * 0.48, size.height)
      ..close();
    canvas.drawPath(back, paint);

    final front = Path()
      ..moveTo(size.width * 0.55, size.height)
      ..lineTo(size.width * 0.82, size.height * 0.7)
      ..lineTo(size.width, size.height)
      ..close();
    canvas.drawPath(front, paint..color = Colors.white.withValues(alpha: 0.06));
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class _SignInCard extends StatelessWidget {
  const _SignInCard({
    required this.emailController,
    required this.passwordController,
    required this.loading,
    required this.error,
    required this.onSignIn,
  });

  final TextEditingController emailController;
  final TextEditingController passwordController;
  final bool loading;
  final String? error;
  final VoidCallback onSignIn;

  @override
  Widget build(BuildContext context) {
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 420),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 64,
            height: 64,
            decoration: BoxDecoration(
              color: AdminColors.accent,
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: AdminColors.accentDim, width: 3),
            ),
            child: const Icon(Icons.terrain_rounded, color: Colors.white, size: 32),
          ),
          const SizedBox(height: 16),
          const Text(
            'Agakbay',
            style: TextStyle(color: Colors.white, fontSize: 28, fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 4),
          const Text(
            'Admin Dashboard',
            style: TextStyle(
              color: AdminColors.accent,
              fontSize: 15,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 28),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(28),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(20),
              boxShadow: [
                BoxShadow(color: Colors.black.withValues(alpha: 0.25), blurRadius: 30, offset: const Offset(0, 12)),
              ],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Text('Email', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
                const SizedBox(height: 6),
                TextField(
                  controller: emailController,
                  keyboardType: TextInputType.emailAddress,
                  onSubmitted: (_) => loading ? null : onSignIn(),
                  decoration: const InputDecoration(
                    hintText: 'admin@agakbay.ph',
                    prefixIcon: Icon(Icons.mail_outline),
                    border: OutlineInputBorder(borderRadius: BorderRadius.all(Radius.circular(10))),
                  ),
                ),
                const SizedBox(height: 16),
                const Text('Password', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
                const SizedBox(height: 6),
                TextField(
                  controller: passwordController,
                  obscureText: true,
                  onSubmitted: (_) => loading ? null : onSignIn(),
                  decoration: const InputDecoration(
                    hintText: '••••••••',
                    prefixIcon: Icon(Icons.lock_outline),
                    border: OutlineInputBorder(borderRadius: BorderRadius.all(Radius.circular(10))),
                  ),
                ),
                const SizedBox(height: 20),
                SizedBox(
                  height: 48,
                  child: FilledButton(
                    onPressed: loading ? null : onSignIn,
                    style: FilledButton.styleFrom(
                      backgroundColor: AdminColors.accent,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                    child: loading
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                          )
                        : const Text('Sign In'),
                  ),
                ),
                if (error != null) ...[
                  const SizedBox(height: 16),
                  Text(
                    error!,
                    textAlign: TextAlign.center,
                    style: const TextStyle(color: Colors.red, fontSize: 13),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}
