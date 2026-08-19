import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:google_sign_in/google_sign_in.dart';

class AuthDatabaseService {
  AuthDatabaseService({
    FirebaseAuth? auth,
    FirebaseFirestore? firestore,
    GoogleSignIn? googleSignIn,
  }) : _auth = auth ?? FirebaseAuth.instance,
       _firestore = firestore ?? FirebaseFirestore.instance,
       _googleSignIn = googleSignIn ?? GoogleSignIn();

  final FirebaseAuth _auth;
  final FirebaseFirestore _firestore;
  final GoogleSignIn _googleSignIn;

  User? get currentUser => _auth.currentUser;

  Future<void> sendPasswordResetEmail(String email) async {
    await _auth.sendPasswordResetEmail(email: email);
  }

  Future<UserCredential> signInUser({
    required String email,
    required String password,
  }) async {
    return _auth.signInWithEmailAndPassword(email: email, password: password);
  }

  Future<UserCredential> signUpUser({
    required String fullName,
    required String username,
    required String email,
    required String password,
    required String accountType,
  }) async {
    final credential = await _auth.createUserWithEmailAndPassword(
      email: email,
      password: password,
    );

    final user = credential.user;
    if (user == null) {
      throw FirebaseAuthException(
        code: 'user-null',
        message: 'User account creation failed.',
      );
    }

    await user.updateDisplayName(fullName);
    await user.sendEmailVerification();

    await _firestore.collection('users').doc(user.uid).set({
      'uid': user.uid,
      'fullName': fullName,
      'username': username,
      'email': email,
      'accountType': accountType,
      'role': accountType,
      'guideVerified': accountType == 'tour_guide' ? false : null,
      'emailVerified': false,
      'verificationMethod': 'link',
      'onboardingComplete': false,
      'createdAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    });
    // Publicly-readable name slice — lets other signed-in users resolve
    // this account's current display name (e.g. on community posts)
    // without needing read access to the full profile doc.
    await _firestore
        .collection('users')
        .doc(user.uid)
        .collection('public')
        .doc('profile')
        .set({'fullName': fullName});

    return credential;
  }

  /// Google's own OAuth flow already verifies the account is real, so this
  /// bypasses the email-link/6-digit-code verification signUpUser sets up
  /// — new users land with `emailVerified` reflecting Google's state and
  /// `onboardingComplete: false`, so they still go through the normal
  /// onboarding flow (skill level, weather preference) the same as an
  /// email/password signup would.
  Future<UserCredential> signInWithGoogle() async {
    final googleUser = await _googleSignIn.signIn();
    if (googleUser == null) {
      throw FirebaseAuthException(
        code: 'sign-in-canceled',
        message: 'Google sign-in was canceled.',
      );
    }
    final googleAuth = await googleUser.authentication;
    final credential = GoogleAuthProvider.credential(
      accessToken: googleAuth.accessToken,
      idToken: googleAuth.idToken,
    );
    final userCredential = await _auth.signInWithCredential(credential);
    final user = userCredential.user;
    if (user == null) {
      throw FirebaseAuthException(
        code: 'user-null',
        message: 'Google sign-in failed.',
      );
    }

    final profileRef = _firestore.collection('users').doc(user.uid);
    final existing = await profileRef.get();
    if (!existing.exists) {
      final displayName = user.displayName?.trim() ?? '';
      final emailLocalPart = user.email?.split('@').first ?? '';
      final fullName = displayName.isNotEmpty
          ? displayName
          : (emailLocalPart.isNotEmpty ? emailLocalPart : 'Hiker');
      await profileRef.set({
        'uid': user.uid,
        'fullName': fullName,
        'username': emailLocalPart.isNotEmpty ? emailLocalPart : user.uid,
        'email': user.email ?? '',
        // No hiker-vs-guide question exists in the Google flow today —
        // defaults new accounts to hiker, matching the more common case;
        // a profile-completion step to change this is a reasonable follow-up.
        'accountType': 'hiker',
        'role': 'hiker',
        'guideVerified': null,
        'emailVerified': user.emailVerified,
        'verificationMethod': 'google',
        'onboardingComplete': false,
        'createdAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      });
      await _firestore
          .collection('users')
          .doc(user.uid)
          .collection('public')
          .doc('profile')
          .set({'fullName': fullName});
    }

    return userCredential;
  }

  Future<void> resendVerificationEmail() async {
    final user = _auth.currentUser;
    if (user == null) {
      throw FirebaseAuthException(
        code: 'no-current-user',
        message: 'No signed in user found for verification.',
      );
    }
    await user.sendEmailVerification();
  }

  Future<bool> reloadAndCheckEmailVerified() async {
    final user = _auth.currentUser;
    if (user == null) {
      return false;
    }

    await user.reload();
    final refreshed = _auth.currentUser;
    final verified = refreshed?.emailVerified ?? false;
    if (verified) {
      await _firestore.collection('users').doc(refreshed!.uid).update({
        'emailVerified': true,
        'verifiedAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      });
    }
    return verified;
  }
}
