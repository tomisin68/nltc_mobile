import 'dart:io';

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../data/repositories/profile_repository.dart';
import '../../domain/models/app_user.dart';
import '../core/state/session_controller.dart';
import '../core/theme/app_palette.dart';
import '../core/toast.dart';
import '../core/widgets/app_card.dart';
import '../core/widgets/page_header.dart';
import 'widgets/profile_form_fields.dart';

/// My Profile.
///
/// Port of `src/pages/dashboard/ProfileView.jsx`: the student-record card with the
/// avatar and account summary, then the personal-information and guardian forms.
/// Every field the website writes is here, under the same names, because the two
/// edit the same document.
class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  final _formKey = GlobalKey<FormState>();

  final _firstName = TextEditingController();
  final _lastName = TextEditingController();
  final _phone = TextEditingController();
  final _houseAddress = TextEditingController();
  final _parentName = TextEditingController();
  final _parentPhone = TextEditingController();

  String? _gender;
  String? _dateOfBirth;
  String _targetExam = 'JAMB';
  String? _examDate;
  String _state = 'Lagos';

  String? _avatarUrl;
  double _uploadProgress = 0;
  bool _uploading = false;
  bool _saving = false;

  /// The account the fields were filled from, so a profile update arriving over
  /// the stream cannot overwrite something half-typed.
  String? _hydratedFrom;

  static const _genders = ['Male', 'Female', 'Prefer not to say'];
  static const _seniorExams = ['JAMB', 'WAEC', 'NECO', 'GCE'];
  static const _juniorExams = ['Junior WAEC', 'Multiple'];

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final profile = context.watch<SessionController>().profile;
    if (profile != null && _hydratedFrom != profile.uid) _hydrate(profile);
  }

  void _hydrate(AppUser profile) {
    _hydratedFrom = profile.uid;

    _firstName.text = profile.firstName ?? '';
    _lastName.text = profile.lastName ?? '';
    _phone.text = profile.phone ?? '';
    _houseAddress.text = profile.houseAddress ?? '';
    _parentName.text = profile.parentName ?? '';
    _parentPhone.text = profile.parentPhone ?? '';

    _gender = _genders.contains(profile.gender) ? profile.gender : null;
    _dateOfBirth = profile.dateOfBirth;

    // The stored `BECE (JSS)` is shown as the label the picker offers, exactly as
    // the web normalises it.
    final exam =
        profile.targetExam == 'BECE (JSS)' ? 'Junior WAEC' : profile.targetExam;
    final options = profile.isJunior ? _juniorExams : _seniorExams;
    _targetExam = options.contains(exam) ? exam! : options.first;

    _examDate = profile.examDate == null
        ? null
        : _dateKey(DateTime.fromMillisecondsSinceEpoch(profile.examDate!));
    _state = nigerianStates.contains(profile.state)
        ? profile.state!
        : nigerianStates.first;
    _avatarUrl = profile.avatarUrl;
  }

  @override
  void dispose() {
    _firstName.dispose();
    _lastName.dispose();
    _phone.dispose();
    _houseAddress.dispose();
    _parentName.dispose();
    _parentPhone.dispose();
    super.dispose();
  }

  static String _dateKey(DateTime date) =>
      '${date.year}-${date.month.toString().padLeft(2, '0')}-'
      '${date.day.toString().padLeft(2, '0')}';

  // ─── Avatar ────────────────────────────────────────────────────────────────

  Future<void> _changePhoto() async {
    final picked = await ImagePicker().pickImage(
      source: ImageSource.gallery,
      // Downscaled before it leaves the phone: a modern camera photo is several
      // megabytes, and this is displayed at 96px.
      maxWidth: 1024,
      maxHeight: 1024,
      imageQuality: 85,
    );
    if (picked == null || !mounted) return;

    final session = context.read<SessionController>();
    final uid = session.account?.uid;
    if (uid == null) return;
    final profiles = context.read<ProfileRepository>();

    setState(() {
      _uploading = true;
      _uploadProgress = 0;
    });

    try {
      final url = await profiles.uploadAvatar(
        File(picked.path),
        onProgress: (progress) {
          if (mounted) setState(() => _uploadProgress = progress);
        },
      );
      await profiles.save(uid, {'profileImage': url});
      if (!mounted) return;
      setState(() => _avatarUrl = url);
      await session.refreshProfile();
      if (!mounted) return;
      showToast('Profile photo updated!', variant: ToastVariant.success);
    } catch (e) {
      if (!mounted) return;
      showToast(
        '$e'.contains('5 MB')
            ? 'Image must be under 5 MB.'
            : 'Upload failed. Check your connection and try again.',
        variant: ToastVariant.error,
      );
    } finally {
      if (mounted) {
        setState(() {
          _uploading = false;
          _uploadProgress = 0;
        });
      }
    }
  }

  // ─── Saving ────────────────────────────────────────────────────────────────

  Future<void> _save() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;

    final session = context.read<SessionController>();
    final uid = session.account?.uid;
    if (uid == null) return;
    final profiles = context.read<ProfileRepository>();
    final hadExamName = session.profile?.examName != null;

    setState(() => _saving = true);
    try {
      await profiles.save(uid, {
        'firstName': _firstName.text.trim(),
        'lastName': _lastName.text.trim(),
        'phone': _phone.text.trim(),
        'gender': _gender,
        'dateOfBirth': _dateOfBirth,
        'targetExam': _targetExam,
        'state': _state,
        'houseAddress': _houseAddress.text.trim(),
        'parentName': _parentName.text.trim(),
        'parentPhone': _parentPhone.text.trim(),
        // These two feed the dashboard countdown. Clearing the date clears the
        // name with it, so a stale "JAMB" label can't linger behind nothing.
        'examDate': _examDate,
        if (_examDate != null && !hadExamName) 'examName': _targetExam,
        if (_examDate == null) 'examName': null,
      });
      await session.refreshProfile();
      if (!mounted) return;
      showToast('Profile saved!', variant: ToastVariant.success);
    } catch (_) {
      if (!mounted) return;
      showToast(
        'Could not save your profile. Check your connection.',
        variant: ToastVariant.error,
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final session = context.watch<SessionController>();
    final profile = session.profile;
    final examOptions =
        (profile?.isJunior ?? false) ? _juniorExams : _seniorExams;

    return Form(
      key: _formKey,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(Tokens.s4, 0, Tokens.s4, Tokens.s10),
        children: [
          const PageHeader(
            title: 'My Profile',
            subtitle: 'Manage your personal information and account details.',
          ),

          _StudentRecordCard(
            profile: profile,
            email: session.account?.email,
            avatarUrl: _avatarUrl,
            uploading: _uploading,
            uploadProgress: _uploadProgress,
            onChangePhoto: _uploading ? null : _changePhoto,
          ),
          const SizedBox(height: Tokens.s4),

          _AccountStatusCard(profile: profile),
          const SizedBox(height: Tokens.s4),

          AppCard(
            title: 'Personal Information',
            titleIcon: Icons.person_rounded,
            child: Column(
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: ProfileField(
                        controller: _firstName,
                        label: 'First name',
                        hint: 'First name',
                        textCapitalization: TextCapitalization.words,
                      ),
                    ),
                    const SizedBox(width: Tokens.s3),
                    Expanded(
                      child: ProfileField(
                        controller: _lastName,
                        label: 'Last name',
                        hint: 'Last name',
                        textCapitalization: TextCapitalization.words,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: Tokens.s4),
                // Read-only: the email *is* the account, and editing it here
                // would desync Firebase Auth from the profile document.
                ProfileField(
                  label: 'Email address',
                  initialValue: session.account?.email ?? '',
                  enabled: false,
                ),
                const SizedBox(height: Tokens.s4),
                ProfileField(
                  controller: _phone,
                  label: 'Phone number',
                  hint: '080xxxxxxxx',
                  keyboardType: TextInputType.phone,
                ),
                const SizedBox(height: Tokens.s4),
                ProfileDropdown<String>(
                  label: 'Gender',
                  value: _gender,
                  hint: '-- Select --',
                  items: [
                    for (final gender in _genders)
                      DropdownMenuItem(value: gender, child: Text(gender)),
                  ],
                  onChanged: (value) => setState(() => _gender = value),
                ),
                const SizedBox(height: Tokens.s4),
                ProfileDateField(
                  label: 'Date of birth',
                  value: _dateOfBirth,
                  // A future birthday is always a typo, and nobody sitting these
                  // exams was born before 1950.
                  firstDate: DateTime(1950),
                  lastDate: DateTime.now(),
                  clearable: true,
                  onChanged: (value) => setState(() => _dateOfBirth = value),
                ),
                const SizedBox(height: Tokens.s4),
                ProfileDropdown<String>(
                  label: 'Target exam',
                  value: _targetExam,
                  items: [
                    for (final exam in examOptions)
                      DropdownMenuItem(value: exam, child: Text(exam)),
                  ],
                  onChanged: (value) =>
                      setState(() => _targetExam = value ?? _targetExam),
                ),
                const SizedBox(height: Tokens.s4),
                ProfileDropdown<String>(
                  label: 'State',
                  value: _state,
                  items: [
                    for (final state in nigerianStates)
                      DropdownMenuItem(value: state, child: Text(state)),
                  ],
                  onChanged: (value) => setState(() => _state = value ?? _state),
                ),
                const SizedBox(height: Tokens.s4),
                ProfileDateField(
                  label: 'Exam date',
                  value: _examDate,
                  firstDate: DateTime.now(),
                  lastDate: DateTime.now().add(const Duration(days: 365 * 3)),
                  helper: 'Powers the countdown on your dashboard. '
                      'Clear it to remove the countdown.',
                  clearable: true,
                  onChanged: (value) => setState(() => _examDate = value),
                ),
                const SizedBox(height: Tokens.s4),
                ProfileField(
                  controller: _houseAddress,
                  label: 'Home address',
                  hint: 'Street, city, state',
                  maxLines: 2,
                  textCapitalization: TextCapitalization.words,
                ),
              ],
            ),
          ),
          const SizedBox(height: Tokens.s4),

          AppCard(
            title: 'Parent / Guardian',
            titleIcon: Icons.people_rounded,
            child: Column(
              children: [
                ProfileField(
                  controller: _parentName,
                  label: 'Parent / Guardian name',
                  hint: 'Full name',
                  textCapitalization: TextCapitalization.words,
                ),
                const SizedBox(height: Tokens.s4),
                ProfileField(
                  controller: _parentPhone,
                  label: 'Parent phone number',
                  hint: '080xxxxxxxx',
                  keyboardType: TextInputType.phone,
                ),
              ],
            ),
          ),
          const SizedBox(height: Tokens.s5),

          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: _saving ? null : _save,
              style: FilledButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 14),
              ),
              icon: _saving
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.save_rounded, size: 18),
              label: Text(_saving ? 'Saving…' : 'Save Profile'),
            ),
          ),
        ],
      ),
    );
  }
}

/// The avatar card, stamped the way the web's `.pf-record` is.
class _StudentRecordCard extends StatelessWidget {
  const _StudentRecordCard({
    required this.profile,
    required this.email,
    required this.avatarUrl,
    required this.uploading,
    required this.uploadProgress,
    required this.onChangePhoto,
  });

  final AppUser? profile;
  final String? email;
  final String? avatarUrl;
  final bool uploading;
  final double uploadProgress;
  final VoidCallback? onChangePhoto;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final isPro = (profile?.plan ?? 'free') != 'free';

    return AppCard(
      padding: const EdgeInsets.symmetric(
        horizontal: Tokens.s5,
        vertical: Tokens.s6,
      ),
      child: Column(
        children: [
          Stack(
            children: [
              Container(
                width: 96,
                height: 96,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: scheme.primaryContainer,
                  border: Border.all(color: scheme.outlineVariant, width: 3),
                  image: avatarUrl == null
                      ? null
                      : DecorationImage(
                          image: NetworkImage(avatarUrl!),
                          fit: BoxFit.cover,
                        ),
                ),
                alignment: Alignment.center,
                child: avatarUrl != null
                    ? null
                    : Text(
                        profile?.initials ?? '?',
                        style: GoogleFonts.fraunces(
                          fontSize: 30,
                          fontWeight: FontWeight.w900,
                          color: scheme.onPrimaryContainer,
                        ),
                      ),
              ),
              if (uploading)
                Positioned.fill(
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: BlueprintPalette.ink.withValues(alpha: 0.62),
                    ),
                    child: Center(
                      child: Text(
                        '${(uploadProgress * 100).round()}%',
                        style: const TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w800,
                          color: Colors.white,
                        ),
                      ),
                    ),
                  ),
                ),
              Positioned(
                right: 0,
                bottom: 0,
                child: Material(
                  color: scheme.primary,
                  shape: const CircleBorder(),
                  child: InkWell(
                    onTap: onChangePhoto,
                    customBorder: const CircleBorder(),
                    child: Padding(
                      padding: const EdgeInsets.all(7),
                      child: Icon(
                        Icons.photo_camera_rounded,
                        size: 15,
                        color: scheme.onPrimary,
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: Tokens.s4),
          Text(
            profile?.displayName ?? 'Student',
            style: GoogleFonts.fraunces(
              fontSize: 17,
              fontWeight: FontWeight.w800,
              color: scheme.onSurface,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 2),
          Text(
            email ?? '',
            style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant),
          ),
          const SizedBox(height: Tokens.s3),
          AppBadge(
            label: isPro ? 'Pro' : 'Free',
            tone: isPro ? BadgeTone.gold : BadgeTone.navy,
            icon: isPro ? Icons.local_fire_department_rounded : null,
          ),
          if (uploading) ...[
            const SizedBox(height: Tokens.s3),
            ClipRRect(
              borderRadius: BorderRadius.circular(2),
              child: LinearProgressIndicator(
                value: uploadProgress,
                minHeight: 4,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              'Uploading… ${(uploadProgress * 100).round()}%',
              style: TextStyle(fontSize: 11, color: scheme.onSurfaceVariant),
            ),
          ],
        ],
      ),
    );
  }
}

/// The read-only summary — what this student has earned, and what they've paid.
class _AccountStatusCard extends StatelessWidget {
  const _AccountStatusCard({required this.profile});

  final AppUser? profile;

  @override
  Widget build(BuildContext context) {
    final isPhysical = profile?.studentMode == 'physical';
    final feePaid = profile?.lessonFeePaid ?? false;
    final numbers = NumberFormat.decimalPattern();

    return AppCard(
      title: 'Account Status',
      titleIcon: Icons.insights_rounded,
      padding: const EdgeInsets.fromLTRB(Tokens.s4, 4, Tokens.s4, Tokens.s3),
      child: Column(
        children: [
          _StatusRow(
            label: 'Student type',
            value: isPhysical ? 'Physical' : 'Online',
            icon: isPhysical ? Icons.business_rounded : Icons.wifi_rounded,
          ),
          if (isPhysical)
            _StatusRow(
              label: 'Lesson fee',
              value: feePaid ? 'Paid' : 'Unpaid',
              icon: feePaid
                  ? Icons.check_circle_rounded
                  : Icons.error_rounded,
              tone: feePaid ? BlueprintPalette.success : BlueprintPalette.error,
            ),
          _StatusRow(
            label: 'XP earned',
            value: numbers.format(profile?.xp ?? 0),
            tone: BlueprintPalette.warning,
          ),
          _StatusRow(label: 'Day streak', value: '${profile?.streak ?? 0} days'),
          _StatusRow(label: 'CBT sessions', value: '${profile?.cbtCount ?? 0}'),
          _StatusRow(
            label: 'Member since',
            value: profile?.createdAt == null
                ? '—'
                : DateFormat('d MMM yyyy').format(
                    DateTime.fromMillisecondsSinceEpoch(profile!.createdAt!),
                  ),
            last: true,
          ),
        ],
      ),
    );
  }
}

class _StatusRow extends StatelessWidget {
  const _StatusRow({
    required this.label,
    required this.value,
    this.icon,
    this.tone,
    this.last = false,
  });

  final String label;
  final String value;
  final IconData? icon;
  final Color? tone;
  final bool last;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Container(
      padding: const EdgeInsets.symmetric(vertical: 11),
      decoration: BoxDecoration(
        border: last
            ? null
            : Border(bottom: BorderSide(color: scheme.outlineVariant)),
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(
              label,
              style: TextStyle(fontSize: 12.5, color: scheme.onSurfaceVariant),
            ),
          ),
          if (icon != null) ...[
            Icon(icon, size: 14, color: tone ?? scheme.onSurface),
            const SizedBox(width: 5),
          ],
          Text(
            value,
            style: TextStyle(
              fontSize: 12.5,
              fontWeight: FontWeight.w800,
              color: tone ?? scheme.onSurface,
            ),
          ),
        ],
      ),
    );
  }
}
