import 'dart:async';

import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/material.dart';

import '../admin_main.dart' show AdminColors;

/// "Forgot password?" for the Admin Dashboard sign-in page.
///
/// Step 1: the admin enters their email and gets a 6-digit code by email.
/// Step 2: they enter that code plus a new password.
/// Backed by requestAdminPasswordReset / confirmAdminPasswordReset in
/// functions/adminPasswordReset.js (admin accounts only).
///
/// Returns the email whose password was reset, or null if cancelled.
Future<String?> showAdminForgotPasswordDialog(
  BuildContext context, {
  String initialEmail = '',
}) {
  return showDialog<String>(
    context: context,
    barrierDismissible: false,
    builder: (_) => _AdminForgotPasswordDialog(initialEmail: initialEmail),
  );
}

FirebaseFunctions get _resetFunctions =>
    FirebaseFunctions.instanceFor(region: 'asia-southeast1');

class _AdminForgotPasswordDialog extends StatefulWidget {
  const _AdminForgotPasswordDialog({required this.initialEmail});

  final String initialEmail;

  @override
  State<_AdminForgotPasswordDialog> createState() =>
      _AdminForgotPasswordDialogState();
}

class _AdminForgotPasswordDialogState
    extends State<_AdminForgotPasswordDialog> {
  late final TextEditingController _emailController = TextEditingController(
    text: widget.initialEmail,
  );
  final _codeController = TextEditingController();
  final _passwordController = TextEditingController();
  final _confirmController = TextEditingController();

  bool _codeSent = false;
  bool _busy = false;
  bool _showPassword = false;
  String? _error;
  String? _info;

  // Matches the server's 60-second resend cooldown.
  static const _resendCooldown = 60;
  int _resendSecondsLeft = 0;
  Timer? _resendTimer;

  @override
  void initState() {
    super.initState();
    _passwordController.addListener(() => setState(() {}));
    _confirmController.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _resendTimer?.cancel();
    _emailController.dispose();
    _codeController.dispose();
    _passwordController.dispose();
    _confirmController.dispose();
    super.dispose();
  }

  String get _email => _emailController.text.trim().toLowerCase();

  bool get _hasLength => _passwordController.text.length >= 8;
  bool get _hasNumber => RegExp(r'[0-9]').hasMatch(_passwordController.text);
  bool get _hasSpecial =>
      RegExp(r'[^A-Za-z0-9]').hasMatch(_passwordController.text);
  bool get _passwordsMatch =>
      _confirmController.text.isNotEmpty &&
      _confirmController.text == _passwordController.text;
  bool get _passwordReady =>
      _hasLength && _hasNumber && _hasSpecial && _passwordsMatch;

  void _startResendCooldown() {
    _resendTimer?.cancel();
    setState(() => _resendSecondsLeft = _resendCooldown);
    _resendTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) return;
      setState(() => _resendSecondsLeft--);
      if (_resendSecondsLeft <= 0) timer.cancel();
    });
  }

  String _errorText(Object error) {
    if (error is FirebaseFunctionsException) {
      return error.message ?? 'Something went wrong. Please try again.';
    }
    return 'Something went wrong. Please try again.';
  }

  Future<void> _sendCode() async {
    if (!RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$').hasMatch(_email)) {
      setState(() => _error = 'Enter a valid email address.');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final result = await _resetFunctions
          .httpsCallable('requestAdminPasswordReset')
          .call<Map<String, dynamic>>({'email': _email});
      if (!mounted) return;
      setState(() {
        _codeSent = true;
        _info =
            '${result.data['message'] ?? 'A reset code has been sent.'} '
            'Not in your Inbox? Check Spam.';
      });
      _startResendCooldown();
    } catch (error) {
      if (mounted) setState(() => _error = _errorText(error));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _resetPassword() async {
    final code = _codeController.text.trim();
    if (!RegExp(r'^\d{6}$').hasMatch(code)) {
      setState(() => _error = 'Enter the 6-digit code from your email.');
      return;
    }
    if (!_passwordReady) {
      setState(() => _error = 'Your new password does not meet the rules yet.');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await _resetFunctions.httpsCallable('confirmAdminPasswordReset').call({
        'email': _email,
        'code': code,
        'newPassword': _passwordController.text,
      });
      if (!mounted) return;
      FocusManager.instance.primaryFocus?.unfocus();
      Navigator.of(context).pop(_email);
    } catch (error) {
      if (mounted) setState(() => _error = _errorText(error));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  InputDecoration _decoration(String label, IconData icon, {Widget? suffix}) {
    return InputDecoration(
      labelText: label,
      prefixIcon: Icon(icon),
      suffixIcon: suffix,
      border: const OutlineInputBorder(
        borderRadius: BorderRadius.all(Radius.circular(10)),
      ),
    );
  }

  Widget _rule(bool ok, String label) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: [
          Icon(
            ok ? Icons.check_circle : Icons.radio_button_unchecked,
            size: 16,
            color: ok ? AdminColors.accent : Colors.grey,
          ),
          const SizedBox(width: 6),
          Text(
            label,
            style: TextStyle(
              fontSize: 12.5,
              color: ok ? AdminColors.accent : Colors.grey.shade700,
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(_codeSent ? 'Enter your reset code' : 'Forgot password'),
      content: SizedBox(
        width: 420,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (!_codeSent) ...[
                const Text(
                  'Enter your admin email. We will send you a 6-digit code to '
                  'reset your password.',
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: _emailController,
                  keyboardType: TextInputType.emailAddress,
                  autofocus: widget.initialEmail.isEmpty,
                  enabled: !_busy,
                  onSubmitted: (_) => _busy ? null : _sendCode(),
                  decoration: _decoration('Email', Icons.mail_outline),
                ),
              ] else ...[
                if (_info != null)
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: AdminColors.accent.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Text(_info!, style: const TextStyle(fontSize: 13)),
                  ),
                const SizedBox(height: 16),
                TextField(
                  controller: _codeController,
                  keyboardType: TextInputType.number,
                  maxLength: 6,
                  autofocus: true,
                  enabled: !_busy,
                  decoration: _decoration('6-digit code', Icons.pin_outlined),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: _passwordController,
                  obscureText: !_showPassword,
                  enabled: !_busy,
                  decoration: _decoration(
                    'New password',
                    Icons.lock_outline,
                    suffix: IconButton(
                      tooltip: _showPassword ? 'Hide password' : 'Show password',
                      onPressed: () =>
                          setState(() => _showPassword = !_showPassword),
                      icon: Icon(
                        _showPassword
                            ? Icons.visibility_off_outlined
                            : Icons.visibility_outlined,
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                _rule(_hasLength, 'At least 8 characters'),
                _rule(_hasNumber, 'Includes a number'),
                _rule(_hasSpecial, 'Includes a special character (e.g. ! @ #)'),
                const SizedBox(height: 12),
                TextField(
                  controller: _confirmController,
                  obscureText: !_showPassword,
                  enabled: !_busy,
                  onSubmitted: (_) => _busy ? null : _resetPassword(),
                  decoration: _decoration(
                    'Confirm new password',
                    Icons.lock_reset_outlined,
                  ),
                ),
                const SizedBox(height: 4),
                _rule(_passwordsMatch, 'Passwords match'),
                Align(
                  alignment: Alignment.centerLeft,
                  child: TextButton(
                    onPressed: (_busy || _resendSecondsLeft > 0)
                        ? null
                        : _sendCode,
                    child: Text(
                      _resendSecondsLeft > 0
                          ? 'Resend code in ${_resendSecondsLeft}s'
                          : 'Resend code',
                    ),
                  ),
                ),
              ],
              if (_error != null) ...[
                const SizedBox(height: 8),
                Text(
                  _error!,
                  style: const TextStyle(color: Colors.red, fontSize: 13),
                ),
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _busy
              ? null
              : () {
                  FocusManager.instance.primaryFocus?.unfocus();
                  Navigator.of(context).pop();
                },
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: _busy
              ? null
              : (_codeSent ? _resetPassword : _sendCode),
          style: FilledButton.styleFrom(backgroundColor: AdminColors.accent),
          child: _busy
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: Colors.white,
                  ),
                )
              : Text(_codeSent ? 'Reset password' : 'Send code'),
        ),
      ],
    );
  }
}
