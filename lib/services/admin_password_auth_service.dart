import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

/// Email/password admin login for the Admin dashboard — no Auth0
/// involved (the mobile app's Auth0 bridge, [Auth0Service], is separate
/// and untouched). Reaching a signed-in Firebase user here proves
/// nothing about admin access on its own: [signIn] checks the `admin`
/// custom claim and verified Firebase email before allowing access.
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

    return validateAdmin(user);
  }

  Future<User> validateAdmin(User user) async {
    await user.reload();
    final refreshedUser = _firebaseAuth.currentUser ?? user;

    // Force-refresh so a stale ID token cannot bypass the latest admin role.
    final tokenResult = await refreshedUser.getIdTokenResult(true);
    if (tokenResult.claims?['admin'] != true) {
      await _firebaseAuth.signOut();
      throw FirebaseAuthException(
        code: 'not-an-admin',
        message: 'This account does not have admin access.',
      );
    }

    if (!refreshedUser.emailVerified) {
      await refreshedUser.sendEmailVerification();
      await _firebaseAuth.signOut();
      throw FirebaseAuthException(
        code: 'email-not-verified',
        message: 'A verification email was sent. Verify your email, then sign in again.',
      );
    }

    try {
      await FirebaseFirestore.instance
          .collection('users')
          .doc(refreshedUser.uid)
          .update({
            'emailVerified': true,
            'verifiedAt': FieldValue.serverTimestamp(),
            'updatedAt': FieldValue.serverTimestamp(),
          });
    } on FirebaseException {
      // Authentication's verified email state is authoritative. A profile
      // sync failure should not prevent a verified admin from signing in.
    }

    return refreshedUser;
  }

  Future<void> signOut() => _firebaseAuth.signOut();
}
