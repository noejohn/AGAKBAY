import 'package:flutter/material.dart';
import 'package:tunga/widgets/agak_theme.dart';

/// Longest free-text "Others" detail allowed. Kept short on purpose — the
/// reason also rides along in the offline LoRa packets (SOS and end-hike),
/// which have a small fixed buffer on the Heltec firmware (see
/// agakbay_heltec.ino).
const int sosReasonDetailMaxLength = 40;

/// First step of every SOS: asks the hiker WHY they need help (Lost,
/// Accident, or Others with a short note) so the Tour Guide knows what
/// kind of emergency it is before they even open the map.
///
/// Returns the reason as display text — "Lost", "Accident", "Others", or
/// "Others: note" — or null if the hiker backed out.
Future<String?> showSosReasonPicker(BuildContext context) {
  return _showReasonPicker(
    context,
    icon: Icons.sos_rounded,
    title: 'What happened?',
    subtitle:
        'Choose the reason for your SOS so your Tour Guide knows how to help.',
    options: const [
      _ReasonChoice(
        Icons.explore_off_rounded,
        'Lost',
        "I don't know where I am or how to get back",
      ),
      _ReasonChoice(
        Icons.personal_injury_rounded,
        'Accident',
        'I or someone with me is injured',
      ),
    ],
    othersHint: 'e.g. bad weather, wild animal',
  );
}

/// Asked when a hiker in a Hike Room ends their hike — the answer goes to
/// their Tour Guide (internet and/or Heltec, whichever is available).
/// Not for emergencies; those go through SOS.
///
/// Returns the reason as display text, or null if the hiker backed out.
Future<String?> showEndHikeReasonPicker(BuildContext context) {
  return _showReasonPicker(
    context,
    icon: Icons.flag_rounded,
    title: 'Why are you ending your hike?',
    subtitle:
        "Your Tour Guide will be told right away. You'll stay in the Hike "
        'Room. For an emergency, use SOS instead.',
    options: const [
      _ReasonChoice(
        Icons.emoji_events_rounded,
        'Completed the hike',
        "I'm done with the trail",
      ),
      _ReasonChoice(
        Icons.battery_alert_rounded,
        'Too tired',
        "I can't keep going",
      ),
      _ReasonChoice(
        Icons.healing_rounded,
        'Minor injury / not feeling well',
        'Not an emergency, but I need to stop',
      ),
      _ReasonChoice(
        Icons.thunderstorm_rounded,
        'Bad weather',
        "It's not safe to continue",
      ),
    ],
    othersHint: 'e.g. ran out of water',
  );
}

class _ReasonChoice {
  const _ReasonChoice(this.icon, this.label, this.description);

  final IconData icon;
  final String label;
  final String description;
}

Future<String?> _showReasonPicker(
  BuildContext context, {
  required IconData icon,
  required String title,
  required String subtitle,
  required List<_ReasonChoice> options,
  required String othersHint,
}) {
  return showDialog<String>(
    context: context,
    barrierColor: Colors.black.withValues(alpha: 0.55),
    builder: (dialogContext) => _ReasonDialog(
      icon: icon,
      title: title,
      subtitle: subtitle,
      options: options,
      othersHint: othersHint,
    ),
  );
}

class _ReasonDialog extends StatefulWidget {
  const _ReasonDialog({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.options,
    required this.othersHint,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final List<_ReasonChoice> options;
  final String othersHint;

  @override
  State<_ReasonDialog> createState() => _ReasonDialogState();
}

class _ReasonDialogState extends State<_ReasonDialog> {
  final TextEditingController _detailController = TextEditingController();
  bool _showOthersField = false;

  @override
  void dispose() {
    _detailController.dispose();
    super.dispose();
  }

  void _submitOthers() {
    final detail = _detailController.text.trim();
    Navigator.of(context).pop(detail.isEmpty ? 'Others' : 'Others: $detail');
  }

  @override
  Widget build(BuildContext context) {
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
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Center(
                child: Container(
                  width: 64,
                  height: 64,
                  decoration: BoxDecoration(
                    color: AgakColors.maroon.withValues(alpha: 0.12),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(widget.icon, color: AgakColors.maroon, size: 32),
                ),
              ),
              const SizedBox(height: 16),
              Text(
                widget.title,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: AgakColors.ink,
                  fontSize: 18,
                  fontWeight: FontWeight.w900,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                widget.subtitle,
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: AgakColors.ink.withValues(alpha: 0.7),
                  fontSize: 13.5,
                  height: 1.45,
                ),
              ),
              const SizedBox(height: 18),
              for (final option in widget.options) ...[
                _ReasonOption(
                  icon: option.icon,
                  label: option.label,
                  description: option.description,
                  onTap: () => Navigator.of(context).pop(option.label),
                ),
                const SizedBox(height: 10),
              ],
              _ReasonOption(
                icon: Icons.more_horiz_rounded,
                label: 'Others',
                description: 'Something else — describe it briefly',
                selected: _showOthersField,
                onTap: () => setState(() => _showOthersField = true),
              ),
              if (_showOthersField) ...[
                const SizedBox(height: 12),
                TextField(
                  controller: _detailController,
                  autofocus: true,
                  maxLength: sosReasonDetailMaxLength,
                  textInputAction: TextInputAction.done,
                  onSubmitted: (_) => _submitOthers(),
                  style: const TextStyle(color: AgakColors.ink),
                  decoration: InputDecoration(
                    hintText: widget.othersHint,
                    filled: true,
                    fillColor: AgakColors.surface,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                  ),
                ),
                ElevatedButton(
                  onPressed: _submitOthers,
                  style: ElevatedButton.styleFrom(
                    foregroundColor: AgakColors.cream,
                    backgroundColor: AgakColors.maroon,
                    elevation: 0,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                  ),
                  child: const Text(
                    'Continue',
                    style: TextStyle(fontWeight: FontWeight.w800),
                  ),
                ),
              ],
              const SizedBox(height: 12),
              TextButton(
                onPressed: () => Navigator.of(context).pop(),
                style: TextButton.styleFrom(
                  foregroundColor: AgakColors.ink.withValues(alpha: 0.68),
                ),
                child: const Text(
                  'Cancel',
                  style: TextStyle(fontWeight: FontWeight.w700),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ReasonOption extends StatelessWidget {
  const _ReasonOption({
    required this.icon,
    required this.label,
    required this.description,
    required this.onTap,
    this.selected = false,
  });

  final IconData icon;
  final String label;
  final String description;
  final VoidCallback onTap;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: selected
          ? AgakColors.maroon.withValues(alpha: 0.08)
          : AgakColors.surface,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: selected
                  ? AgakColors.maroon
                  : AgakColors.ink.withValues(alpha: 0.14),
            ),
          ),
          child: Row(
            children: [
              Icon(icon, color: AgakColors.maroon, size: 28),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      label,
                      style: const TextStyle(
                        color: AgakColors.ink,
                        fontSize: 15,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      description,
                      style: TextStyle(
                        color: AgakColors.ink.withValues(alpha: 0.65),
                        fontSize: 12.5,
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
  }
}
