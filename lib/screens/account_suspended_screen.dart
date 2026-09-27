import 'package:flutter/material.dart';

/// Shown when Firebase rejects a sign-in with `user-disabled` — the account
/// was suspended via the Admin Dashboard's "Suspend Account" action
/// (functions/userAccountActions.js disables the Firebase Auth account
/// server-side, so this is a real access block, not just a UI message).
class AccountSuspendedScreen extends StatelessWidget {
  const AccountSuspendedScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0B1A14),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 84,
                  height: 84,
                  decoration: BoxDecoration(
                    color: Colors.redAccent.withValues(alpha: 0.15),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    Icons.block_rounded,
                    color: Colors.redAccent,
                    size: 44,
                  ),
                ),
                const SizedBox(height: 24),
                const Text(
                  'Account Suspended',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 22,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 12),
                const Text(
                  'This account has been suspended by an administrator. '
                  'If you think this is a mistake, please contact the Agakbay team.',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: Colors.white70,
                    fontSize: 14.5,
                    height: 1.4,
                  ),
                ),
                const SizedBox(height: 28),
                SizedBox(
                  width: double.infinity,
                  height: 48,
                  child: FilledButton(
                    onPressed: () => Navigator.of(context).pop(),
                    child: const Text('Back to Sign In'),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
