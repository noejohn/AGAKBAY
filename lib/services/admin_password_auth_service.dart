import 'package:firebase_auth/firebase_auth.dart';

/// Email/password admin login for the Admin dashboard — no Auth0
/// involved (the mobile app's Auth0 bridge, [Auth0Service], is separate
/// and untouched). Reaching a signed-in Firebase user here proves
/// nothing about admin access on its own: [signIn] checks the `admin`
/// custom claim (granted via scripts/grantAdminRole.js) and immediately
/// signs back out if it's missing — same gate the Auth0 path used.
class AdminPasswordAuthService {
  AdminPasswordAuthService({FirebaseAuth? firebaseAuth})
    : _firebaseAuth = firebaseAuth ?? FirebaseAuth.instance;

  final FirebaseAuth _firebaseAuth;

  User? get currentUser => _firebaseAuth.currentUser;

  Future<User> signIn({required String email, required String password}) async {
    final credential = await _firebaseAuth.signInWithEmailAndPassword(
      email: email,
      password: password,
    );
    final user = credential.user;
    if (user == null) {
      throw FirebaseAuthException(
        code: 'no-user',
        message: 'Sign-in did not return a Firebase user.',
      );
    }

    // Force-refresh: a returning admin's cached ID token can predate a
    // just-granted claim (scripts/grantAdminRole.js runs after the
    // account already exists), so a stale token must not be trusted here.
    final tokenResult = await user.getIdTokenResult(true);
    if (tokenResult.claims?['admin'] != true) {
      await _firebaseAuth.signOut();
      throw FirebaseAuthException(
        code: 'not-an-admin',
        message: 'This account does not have admin access.',
      );
    }

    return user;
  }

  Future<void> signOut() => _firebaseAuth.signOut();
}
