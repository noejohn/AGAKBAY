import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
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

    // Reconcile claims from the trusted admin profile before routing. This
    // repairs accounts provisioned before role claims were added and prevents
    // a Mountain Head profile from being treated as an unclassified admin.
    late final Map<String, dynamic> refreshedAccess;
    try {
      final response = await FirebaseFunctions.instance
          .httpsCallable('refreshAdminClaims')
          .call<Map<String, dynamic>>();
      refreshedAccess = response.data;
    } on FirebaseFunctionsException {
      await _firebaseAuth.signOut();
      rethrow;
    }

    // Force-refresh to apply the server-verified role before opening the UI.
    final tokenResult = await refreshedUser.getIdTokenResult(true);
    final claims = tokenResult.claims;
    if (claims?['admin'] != true) {
      await _firebaseAuth.signOut();
      throw FirebaseAuthException(
        code: 'not-an-admin',
        message: 'This account does not have admin access.',
      );
    }
    final adminRole = claims?['adminRole'];
    if (adminRole != 'tourism_admin' && adminRole != 'mountain_head') {
      await _firebaseAuth.signOut();
      throw FirebaseAuthException(
        code: 'invalid-admin-role',
        message: 'The refreshed admin token has no valid admin role.',
      );
    }
    if (adminRole != refreshedAccess['adminRole']) {
      await _firebaseAuth.signOut();
      throw FirebaseAuthException(
        code: 'admin-role-mismatch',
        message:
            'The account profile is ${refreshedAccess['adminRole']}, but the sign-in token is $adminRole. Sign in again to refresh access.',
      );
    }
    if (adminRole == 'mountain_head' &&
        (claims?['managedMountainName'] is! String ||
            (claims?['managedMountainName'] as String).trim().isEmpty)) {
      await _firebaseAuth.signOut();
      throw FirebaseAuthException(
        code: 'missing-managed-mountain',
        message: 'This Mountain Head account has no assigned mountain.',
      );
    }
    if (adminRole == 'mountain_head' &&
        claims?['managedMountainName'] !=
            refreshedAccess['managedMountainName']) {
      await _firebaseAuth.signOut();
      throw FirebaseAuthException(
        code: 'admin-mountain-mismatch',
        message:
            'The Mountain Head assignment in the sign-in token does not match the admin profile. Sign in again to refresh access.',
      );
    }

    if (!refreshedUser.emailVerified) {
      await refreshedUser.sendEmailVerification();
      await _firebaseAuth.signOut();
      throw FirebaseAuthException(
        code: 'email-not-verified',
        message:
            'A verification email was sent. Verify your email, then sign in again.',
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
