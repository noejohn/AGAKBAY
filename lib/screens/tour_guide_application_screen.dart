import 'dart:typed_data';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../services/gemini_client.dart';
import '../widgets/agak_theme.dart';

const _reapplyCooldown = Duration(days: 7);

/// When a rejected applicant becomes eligible to submit a new application —
/// null if the application isn't rejected, or [reviewedAt] hasn't been
/// stamped yet (fails open: no timestamp means don't block reapplying).
DateTime? _reapplyCooldownEnd(Map<String, dynamic> data) {
  final reviewedAt = data['reviewedAt'];
  if (reviewedAt is! Timestamp) {
    return null;
  }
  return reviewedAt.toDate().add(_reapplyCooldown);
}

String _formatDate(DateTime date) {
  const months = [
    'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
    'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
  ];
  return '${months[date.month - 1]} ${date.day}, ${date.year}';
}

/// Profile-tab tile reflecting the signed-in hiker's Tour Guide
/// application status — reads the same tour_guide_applications collection
/// the admin dashboard's Tour Guide Verification page reviews. Nothing
/// here can move an application off "pending" itself; only
/// reviewTourGuideApplication (functions/adminActions.js) does that, via
/// the Admin SDK.
class TourGuideApplicationStatusTile extends StatelessWidget {
  const TourGuideApplicationStatusTile({super.key, required this.currentAccountType});

  /// The signed-in user's own accountType field, if already loaded
  /// (avoids a second Firestore read just to know "am I already a guide").
  final String? currentAccountType;

  @override
  Widget build(BuildContext context) {
    if (currentAccountType == 'tour_guide') {
      return _tile(
        icon: Icons.verified_rounded,
        iconColor: AgakColors.olive,
        title: 'Verified Tour Guide',
        subtitle: 'Your account can create and manage Hike Rooms.',
      );
    }

    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) {
      return const SizedBox.shrink();
    }

    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance
          .collection('tour_guide_applications')
          .where('uid', isEqualTo: uid)
          .orderBy('submittedAt', descending: true)
          .limit(1)
          .snapshots(),
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          // Fails open to the tappable "apply" state rather than getting
          // stuck on "Checking status..." forever — most likely cause is
          // firestore.rules not deployed yet for this collection.
          debugPrint('TourGuideApplicationStatusTile query failed: ${snapshot.error}');
          return _applyTile(context);
        }
        if (!snapshot.hasData) {
          return _tile(
            icon: Icons.badge_outlined,
            iconColor: AgakColors.maroon,
            title: 'Apply as Tour Guide',
            subtitle: 'Checking status...',
          );
        }
        final docs = snapshot.data!.docs;
        if (docs.isEmpty) {
          return _applyTile(context);
        }
        final data = docs.first.data() as Map<String, dynamic>;
        final status = data['status'] as String? ?? 'pending';

        if (status == 'pending') {
          return _tile(
            icon: Icons.hourglass_top_rounded,
            iconColor: Colors.orange,
            title: 'Application Pending',
            subtitle: 'An admin is reviewing your Tour Guide application.',
            trailing: Icons.chevron_right_rounded,
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) => TourGuideApplicationStatusScreen(data: data),
              ),
            ),
          );
        }
        if (status == 'rejected') {
          final canReapplyAt = _reapplyCooldownEnd(data);
          final canReapplyNow = canReapplyAt == null || DateTime.now().isAfter(canReapplyAt);
          return _tile(
            icon: Icons.badge_outlined,
            iconColor: AgakColors.maroon,
            title: canReapplyNow ? 'Reapply as Tour Guide' : 'Application Not Approved',
            subtitle: canReapplyNow
                ? 'Your last application was not approved. Tap to reapply.'
                : 'You can reapply on ${_formatDate(canReapplyAt)}.',
            trailing: Icons.chevron_right_rounded,
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) => TourGuideApplicationStatusScreen(data: data),
              ),
            ),
          );
        }
        // 'approved' but the users doc hasn't caught up yet (rare timing
        // gap right after review) — treat like already-verified rather
        // than inviting a redundant re-application.
        return _tile(
          icon: Icons.verified_rounded,
          iconColor: AgakColors.olive,
          title: 'Verified Tour Guide',
          subtitle: 'Your account can create and manage Hike Rooms.',
        );
      },
    );
  }

  Widget _applyTile(
    BuildContext context, {
    String title = 'Apply as Tour Guide',
    String subtitle = 'Submit your ID and certification for review.',
  }) {
    return _tile(
      icon: Icons.badge_outlined,
      iconColor: AgakColors.maroon,
      title: title,
      subtitle: subtitle,
      trailing: Icons.chevron_right_rounded,
      onTap: () => Navigator.of(context).push(
        MaterialPageRoute<void>(builder: (_) => const TourGuideApplicationScreen()),
      ),
    );
  }

  Widget _tile({
    required IconData icon,
    required Color iconColor,
    required String title,
    required String subtitle,
    IconData? trailing,
    VoidCallback? onTap,
  }) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(18),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 13),
          child: Row(
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: iconColor.withValues(alpha: 0.13),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(icon, color: iconColor, size: 20),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(fontWeight: FontWeight.w800, color: AgakColors.ink),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      style: TextStyle(fontSize: 12.5, color: AgakColors.ink.withValues(alpha: 0.6)),
                    ),
                  ],
                ),
              ),
              if (trailing != null)
                Icon(trailing, color: AgakColors.ink.withValues(alpha: 0.4)),
            ],
          ),
        ),
      ),
    );
  }
}

class TourGuideApplicationScreen extends StatefulWidget {
  const TourGuideApplicationScreen({super.key});

  @override
  State<TourGuideApplicationScreen> createState() => _TourGuideApplicationScreenState();
}

class _TourGuideApplicationScreenState extends State<TourGuideApplicationScreen> {
  final _fullNameController = TextEditingController();
  final _contactController = TextEditingController();
  final _experienceController = TextEditingController();
  final _mountainsController = TextEditingController();

  Uint8List? _idImageBytes;
  String? _idImageMimeType;
  Uint8List? _certificateImageBytes;
  String? _certificateImageMimeType;

  bool _submitting = false;
  bool _checkingId = false;

  @override
  void initState() {
    super.initState();
    _fullNameController.text = FirebaseAuth.instance.currentUser?.displayName ?? '';
  }

  @override
  void dispose() {
    _fullNameController.dispose();
    _contactController.dispose();
    _experienceController.dispose();
    _mountainsController.dispose();
    super.dispose();
  }

  Future<void> _pickImage({required bool isId}) async {
    final picked = await ImagePicker().pickImage(
      source: ImageSource.gallery,
      imageQuality: 85,
      maxWidth: 1600,
    );
    if (picked == null) {
      return;
    }
    final bytes = await picked.readAsBytes();
    if (!mounted) {
      return;
    }

    if (isId) {
      setState(() => _checkingId = true);
      final looksValid = await _looksLikeGovernmentId(bytes, picked.mimeType);
      if (!mounted) {
        return;
      }
      setState(() => _checkingId = false);
      // Only explicit "no" blocks the upload — null means the check
      // itself couldn't run (no/exhausted Gemini credits, network issue),
      // which fails open rather than blocking every application whenever
      // the AI happens to be unavailable.
      if (looksValid == false) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              "That doesn't look like a valid ID. Please upload a valid Philippine "
              'government-issued ID.',
            ),
          ),
        );
        return;
      }
    }

    setState(() {
      if (isId) {
        _idImageBytes = bytes;
        _idImageMimeType = picked.mimeType;
      } else {
        _certificateImageBytes = bytes;
        _certificateImageMimeType = picked.mimeType;
      }
    });
  }

  /// Null means "couldn't check" (no/exhausted Gemini key, network error) —
  /// callers must treat that as "allow it" (admin still reviews manually
  /// before final approval), never as "definitely invalid".
  Future<bool?> _looksLikeGovernmentId(Uint8List bytes, String? mimeType) async {
    final apiKey = await loadGeminiApiKey();
    if (apiKey.isEmpty) {
      return null;
    }
    final answer = await fetchGeminiImageResponse(
      apiKey: apiKey,
      prompt:
          'Does this image show a valid Philippine government-issued ID card '
          "(e.g. national ID, driver's license, passport, UMID, PhilHealth ID, "
          "voter's ID, postal ID, or similar)? Reply with only one word: YES or NO.",
      imageBytes: bytes,
      mimeType: mimeType ?? 'image/jpeg',
    );
    if (answer.isEmpty) {
      return null;
    }
    return answer.toUpperCase().contains('YES');
  }

  Future<String> _uploadImage(Uint8List bytes, String? mimeType, String uid, String fileName) async {
    final ref = FirebaseStorage.instance
        .ref()
        .child('tour_guide_applications')
        .child(uid)
        .child(fileName);
    await ref.putData(bytes, SettableMetadata(contentType: mimeType ?? 'image/jpeg'));
    return ref.getDownloadURL();
  }

  Future<void> _submit() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      return;
    }

    final fullName = _fullNameController.text.trim();
    final contact = _contactController.text.trim();
    final experience = _experienceController.text.trim();
    final mountains = _mountainsController.text.trim();

    if (fullName.isEmpty || contact.isEmpty || experience.isEmpty || mountains.isEmpty) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Please complete all fields.')));
      return;
    }
    if (_idImageBytes == null || _certificateImageBytes == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please upload both your ID and certificate.')),
      );
      return;
    }

    setState(() => _submitting = true);
    try {
      final idUrl = await _uploadImage(_idImageBytes!, _idImageMimeType, user.uid, 'id.jpg');
      final certUrl = await _uploadImage(
        _certificateImageBytes!,
        _certificateImageMimeType,
        user.uid,
        'certificate.jpg',
      );

      await FirebaseFirestore.instance.collection('tour_guide_applications').add({
        'uid': user.uid,
        'applicantEmail': user.email,
        'fullName': fullName,
        'contactNumber': contact,
        'experienceYears': experience,
        'mountainsHandled': mountains,
        'idImageUrl': idUrl,
        'certificateImageUrl': certUrl,
        'status': 'pending',
        'submittedAt': FieldValue.serverTimestamp(),
        'reviewedAt': null,
        'reviewedBy': null,
        'reviewNote': null,
      });

      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Application submitted! We'll notify you once it's reviewed.")),
      );
      Navigator.of(context).pop();
    } catch (error) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Failed to submit: $error')));
    } finally {
      if (mounted) {
        setState(() => _submitting = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        decoration: BoxDecoration(gradient: AgakColors.screenBackground),
        child: SafeArea(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 32),
            children: [
              Row(
                children: [
                  IconButton(
                    icon: const Icon(Icons.arrow_back_rounded, color: AgakColors.ink),
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                  const SizedBox(width: 4),
                  const Expanded(
                    child: Text(
                      'Apply as Tour Guide',
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.w900,
                        color: AgakColors.ink,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4),
                child: Text(
                  'Submit your details, ID, and a relevant certification. '
                  'An admin will review your application before your account '
                  'is upgraded.',
                  style: TextStyle(color: AgakColors.ink.withValues(alpha: 0.65)),
                ),
              ),
              const SizedBox(height: 20),
              _label('Full Name'),
              _textField(_fullNameController, hint: 'Juan Dela Cruz'),
              const SizedBox(height: 14),
              _label('Contact Number'),
              _textField(
                _contactController,
                hint: '09XX XXX XXXX',
                keyboardType: TextInputType.phone,
              ),
              const SizedBox(height: 14),
              _label('Years of Experience'),
              _textField(
                _experienceController,
                hint: 'e.g. 5',
                keyboardType: TextInputType.number,
              ),
              const SizedBox(height: 14),
              _label('Mountains Handled'),
              _textField(
                _mountainsController,
                hint: 'e.g. Mt. Apo, Mt. Kitanglad',
                maxLines: 2,
              ),
              const SizedBox(height: 20),
              _label('Government ID'),
              _imagePickerTile(
                bytes: _idImageBytes,
                onTap: _checkingId ? null : () => _pickImage(isId: true),
                loading: _checkingId,
              ),
              const SizedBox(height: 14),
              _label('Certification (e.g. DOT/LGU guide certificate)'),
              _imagePickerTile(
                bytes: _certificateImageBytes,
                onTap: () => _pickImage(isId: false),
              ),
              const SizedBox(height: 26),
              SizedBox(
                height: 52,
                child: FilledButton(
                  onPressed: _submitting ? null : _submit,
                  style: FilledButton.styleFrom(
                    backgroundColor: AgakColors.maroon,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                  ),
                  child: _submitting
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                        )
                      : const Text('Submit Application', style: TextStyle(fontWeight: FontWeight.w800)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _label(String text) => Padding(
    padding: const EdgeInsets.only(bottom: 6, left: 2),
    child: Text(
      text,
      style: TextStyle(
        fontSize: 12.5,
        fontWeight: FontWeight.w700,
        color: AgakColors.ink.withValues(alpha: 0.75),
      ),
    ),
  );

  Widget _textField(
    TextEditingController controller, {
    required String hint,
    TextInputType? keyboardType,
    int maxLines = 1,
  }) {
    return TextField(
      controller: controller,
      keyboardType: keyboardType,
      maxLines: maxLines,
      decoration: InputDecoration(
        hintText: hint,
        filled: true,
        fillColor: Colors.white,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide.none,
        ),
      ),
    );
  }

  Widget _imagePickerTile({
    required Uint8List? bytes,
    required VoidCallback? onTap,
    bool loading = false,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(14),
      child: Container(
        height: 120,
        width: double.infinity,
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: AgakColors.ink.withValues(alpha: 0.12)),
        ),
        child: loading
            ? const Center(child: CircularProgressIndicator(strokeWidth: 2))
            : bytes == null
            ? Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.add_a_photo_outlined, color: AgakColors.ink.withValues(alpha: 0.4)),
                    const SizedBox(height: 6),
                    Text(
                      'Tap to upload',
                      style: TextStyle(color: AgakColors.ink.withValues(alpha: 0.5), fontSize: 12),
                    ),
                  ],
                ),
              )
            : ClipRRect(
                borderRadius: BorderRadius.circular(14),
                child: Image.memory(bytes, fit: BoxFit.cover, width: double.infinity, height: 120),
              ),
      ),
    );
  }
}

class TourGuideApplicationStatusScreen extends StatelessWidget {
  const TourGuideApplicationStatusScreen({super.key, required this.data});

  final Map<String, dynamic> data;

  @override
  Widget build(BuildContext context) {
    final status = data['status'] as String? ?? 'pending';
    final fullName = data['fullName'] as String? ?? '—';
    final contact = data['contactNumber'] as String? ?? '—';
    final experience = data['experienceYears'] as String? ?? '—';
    final mountains = data['mountainsHandled'] as String? ?? '—';
    final reviewNote = data['reviewNote'] as String?;

    final (statusLabel, statusColor) = switch (status) {
      'approved' => ('Approved', AgakColors.olive),
      'rejected' => ('Not Approved', AgakColors.maroon),
      _ => ('Pending Review', Colors.orange),
    };

    return Scaffold(
      body: Container(
        decoration: BoxDecoration(gradient: AgakColors.screenBackground),
        child: SafeArea(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 32),
            children: [
              Row(
                children: [
                  IconButton(
                    icon: const Icon(Icons.arrow_back_rounded, color: AgakColors.ink),
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                  const SizedBox(width: 4),
                  const Expanded(
                    child: Text(
                      'Application Status',
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.w900,
                        color: AgakColors.ink,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 20),
              Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(18)),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                      decoration: BoxDecoration(
                        color: statusColor.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Text(
                        statusLabel,
                        style: TextStyle(color: statusColor, fontWeight: FontWeight.w700, fontSize: 13),
                      ),
                    ),
                    const SizedBox(height: 18),
                    _statusField('Full Name', fullName),
                    _statusField('Contact Number', contact),
                    _statusField('Years of Experience', experience),
                    _statusField('Mountains Handled', mountains),
                    if (reviewNote != null && reviewNote.isNotEmpty) _statusField('Admin Note', reviewNote),
                  ],
                ),
              ),
              if (status == 'rejected') ...[
                const SizedBox(height: 20),
                Builder(
                  builder: (context) {
                    final canReapplyAt = _reapplyCooldownEnd(data);
                    final canReapplyNow = canReapplyAt == null || DateTime.now().isAfter(canReapplyAt);
                    if (!canReapplyNow) {
                      return Text(
                        'You can reapply on ${_formatDate(canReapplyAt)}.',
                        textAlign: TextAlign.center,
                        style: TextStyle(color: AgakColors.ink.withValues(alpha: 0.6)),
                      );
                    }
                    return SizedBox(
                      height: 52,
                      child: FilledButton(
                        onPressed: () => Navigator.of(context).pushReplacement(
                          MaterialPageRoute<void>(
                            builder: (_) => const TourGuideApplicationScreen(),
                          ),
                        ),
                        style: FilledButton.styleFrom(
                          backgroundColor: AgakColors.maroon,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                        ),
                        child: const Text('Reapply', style: TextStyle(fontWeight: FontWeight.w800)),
                      ),
                    );
                  },
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _statusField(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: AgakColors.ink.withValues(alpha: 0.5),
            ),
          ),
          const SizedBox(height: 3),
          Text(value, style: const TextStyle(fontWeight: FontWeight.w600, color: AgakColors.ink)),
        ],
      ),
    );
  }
}
