import 'package:auth0_flutter/auth0_flutter.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';

/// Result of an Auth0-bridged sign-in. [isNewUser] comes straight from
/// exchangeAuth0Token's resolveFirebaseUid — every new account bootstraps
/// as a hiker there (bootstrapNewUserDoc), so there's no client-side
/// hiker/tour-guide choice to make; becoming a tour guide only happens
/// later via a reviewed "Apply as Tour Guide" application.
class Auth0SignInResult {
  const Auth0SignInResult({required this.credential, required this.isNewUser});

  final UserCredential credential;
  final bool isNewUser;
}

/// Bridges Auth0 Universal Login into the existing Firebase Auth session:
/// Auth0 handles the actual login/MFA/anomaly detection and is the source
/// of role/authorization data, but the `exchangeAuth0Token` Cloud Function
/// mints a Firebase custom token so `FirebaseAuth.instance.currentUser` and
/// `authStateChanges()` — and everything built on them, like `AuthGate` and
/// Firestore's `request.auth.uid` rules — keep working completely
/// unchanged. See the AGAKBAY Auth0 bridge plan for the full design.
///
/// Domain/client ID below are the AGAKBAY Mobile Auth0 application (not
/// secret — public per OAuth/OIDC for a native/PKCE client).
class Auth0Service {
  Auth0Service({Auth0? auth0, FirebaseFunctions? functions, FirebaseAuth? firebaseAuth})
    : _auth0 = auth0 ??
          Auth0(
            'dev-cmd5w5abm4lstmka.us.auth0.com',
            'sxPTfCseNEZODTAWP9XqyeJOg5CQkmE9',
          ),
      _functions = functions ?? FirebaseFunctions.instance,
      _firebaseAuth = firebaseAuth ?? FirebaseAuth.instance;

  final Auth0 _auth0;
  final FirebaseFunctions _functions;
  final FirebaseAuth _firebaseAuth;

  Future<Auth0SignInResult> signIn() async {
    return _login();
  }

  /// Skips Auth0's own login-picker page and goes straight to Google —
  /// via Auth0's `connection` parameter — so from the user's point of view
  /// this looks identical to a plain "Sign in with Google" button, even
  /// though Auth0 sits in the middle verifying the token before Firebase
  /// ever sees it.
  Future<Auth0SignInResult> signInWithGoogle() async {
    return _login(parameters: {'connection': 'google-oauth2'});
  }

  Future<Auth0SignInResult> _login({
    Map<String, String> parameters = const {},
  }) async {
    // 'com.example.tunga' matches auth0Scheme in android/app/build.gradle.kts
    // (set to applicationId there) — must stay in sync with that value.
    final credentials = await _auth0
        .webAuthentication(scheme: 'com.example.tunga')
        .login(scopes: {'openid', 'profile', 'email'}, parameters: parameters);

    final result = await _functions
        .httpsCallable('exchangeAuth0Token')
        .call<Map<String, dynamic>>({'idToken': credentials.idToken});

    final customToken = result.data['firebaseCustomToken'] as String?;
    if (customToken == null) {
      throw FirebaseAuthException(
        code: 'auth0-exchange-failed',
        message: 'Auth0 sign-in did not return a Firebase token.',
      );
    }
    final isNewUser = result.data['isNewUser'] as bool? ?? false;

    final userCredential = await _firebaseAuth.signInWithCustomToken(
      customToken,
    );
    return Auth0SignInResult(credential: userCredential, isNewUser: isNewUser);
  }
}
