import 'dart:async';

import 'package:flutter/material.dart';
import 'package:tunga/widgets/agak_theme.dart';

/// Text field styling for forms on AGAK's cream dialogs — white fill,
/// ink text, maroon focus — so edit forms match the rest of the app
/// instead of Material's dark default.
InputDecoration agakInputDecoration({
  required String label,
  required IconData icon,
  String? hint,
}) {
  OutlineInputBorder border(Color color, {double width = 1}) {
    return OutlineInputBorder(
      borderRadius: BorderRadius.circular(14),
      borderSide: BorderSide(color: color, width: width),
    );
  }

  return InputDecoration(
    labelText: label,
    hintText: hint,
    labelStyle: TextStyle(color: AgakColors.ink.withValues(alpha: 0.6)),
    floatingLabelStyle: const TextStyle(
      color: AgakColors.maroon,
      fontWeight: FontWeight.w700,
    ),
    hintStyle: TextStyle(color: AgakColors.ink.withValues(alpha: 0.35)),
    prefixIcon: Icon(icon, color: AgakColors.maroon),
    filled: true,
    fillColor: AgakColors.surface,
    border: border(AgakColors.ink.withValues(alpha: 0.14)),
    enabledBorder: border(AgakColors.ink.withValues(alpha: 0.14)),
    focusedBorder: border(AgakColors.maroon, width: 1.6),
  );
}

/// A cream AGAK-styled dialog shell for edit forms: icon badge, title,
/// optional subtitle, the form [children], then Cancel / Save. The caller
/// pops the dialog (with its result) from [onSave] / [onCancel].
class AgakFormDialog extends StatelessWidget {
  const AgakFormDialog({
    super.key,
    required this.icon,
    required this.title,
    required this.children,
    required this.onSave,
    required this.onCancel,
    this.subtitle,
    this.saveLabel = 'Save',
  });

  final IconData icon;
  final String title;
  final String? subtitle;
  final List<Widget> children;
  final VoidCallback onSave;
  final VoidCallback onCancel;
  final String saveLabel;

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
      child: Container(
        padding: const EdgeInsets.fromLTRB(22, 26, 22, 18),
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
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Center(
                child: Container(
                  width: 60,
                  height: 60,
                  decoration: BoxDecoration(
                    color: AgakColors.maroon.withValues(alpha: 0.12),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(icon, color: AgakColors.maroon, size: 30),
                ),
              ),
              const SizedBox(height: 14),
              Text(
                title,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: AgakColors.ink,
                  fontSize: 18,
                  fontWeight: FontWeight.w900,
                ),
              ),
              if (subtitle != null) ...[
                const SizedBox(height: 6),
                Text(
                  subtitle!,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: AgakColors.ink.withValues(alpha: 0.65),
                    fontSize: 13,
                    height: 1.4,
                  ),
                ),
              ],
              const SizedBox(height: 18),
              ...children,
              const SizedBox(height: 22),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: onCancel,
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
                      child: const Text(
                        'Cancel',
                        style: TextStyle(fontWeight: FontWeight.w700),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: ElevatedButton(
                      onPressed: onSave,
                      style: ElevatedButton.styleFrom(
                        foregroundColor: AgakColors.cream,
                        backgroundColor: AgakColors.maroon,
                        elevation: 0,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                      ),
                      child: Text(
                        saveLabel,
                        style: const TextStyle(fontWeight: FontWeight.w800),
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

/// AGAK-styled result popup for profile edits — replaces the plain bottom
/// snackbar. A success closes itself after a moment; an error stays until
/// the user taps OK, so it isn't missed.
Future<void> showAgakResultPopup(
  BuildContext context, {
  required String title,
  required String message,
  bool success = true,
}) async {
  final color = success ? AgakColors.olive : AgakColors.maroon;
  Timer? autoClose;
  await showDialog<void>(
    context: context,
    barrierColor: Colors.black.withValues(alpha: 0.4),
    builder: (dialogContext) {
      if (success) {
        autoClose = Timer(const Duration(milliseconds: 1600), () {
          if (dialogContext.mounted) Navigator.of(dialogContext).pop();
        });
      }
      return Dialog(
        backgroundColor: Colors.transparent,
        insetPadding: const EdgeInsets.symmetric(horizontal: 48),
        child: Container(
          padding: const EdgeInsets.fromLTRB(24, 26, 24, 20),
          decoration: BoxDecoration(
            color: AgakColors.cream,
            borderRadius: BorderRadius.circular(28),
            border: Border.all(color: AgakColors.ink.withValues(alpha: 0.08)),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.25),
                blurRadius: 26,
                offset: const Offset(0, 12),
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TweenAnimationBuilder<double>(
                tween: Tween(begin: 0.6, end: 1),
                duration: const Duration(milliseconds: 320),
                curve: Curves.easeOutBack,
                builder: (context, scale, child) =>
                    Transform.scale(scale: scale, child: child),
                child: Container(
                  width: 64,
                  height: 64,
                  decoration: BoxDecoration(
                    color: color.withValues(alpha: 0.16),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    success ? Icons.check_rounded : Icons.error_outline_rounded,
                    color: success ? const Color(0xFF5E8F2E) : color,
                    size: 36,
                  ),
                ),
              ),
              const SizedBox(height: 14),
              Text(
                title,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: AgakColors.ink,
                  fontSize: 17,
                  fontWeight: FontWeight.w900,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                message,
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: AgakColors.ink.withValues(alpha: 0.68),
                  fontSize: 13.5,
                  height: 1.4,
                ),
              ),
              if (!success) ...[
                const SizedBox(height: 18),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: () => Navigator.of(dialogContext).pop(),
                    style: ElevatedButton.styleFrom(
                      foregroundColor: AgakColors.cream,
                      backgroundColor: AgakColors.maroon,
                      elevation: 0,
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                    ),
                    child: const Text(
                      'OK',
                      style: TextStyle(fontWeight: FontWeight.w800),
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      );
    },
  );
  autoClose?.cancel();
}
