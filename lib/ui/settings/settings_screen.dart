import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../data/repositories/billing_repository.dart';
import '../../data/repositories/profile_repository.dart';
import '../../domain/models/access_state.dart';
import '../../domain/models/app_user.dart';
import '../../domain/plans.dart';
import '../core/state/session_controller.dart';
import '../core/state/theme_controller.dart';
import '../core/theme/app_palette.dart';
import '../core/toast.dart';
import '../core/widgets/app_card.dart';
import '../core/widgets/empty_state.dart';
import '../core/widgets/in_app_browser.dart';
import '../core/widgets/page_header.dart';
import '../core/widgets/skeleton.dart';
import '../profile/widgets/profile_form_fields.dart';
import 'widgets/bank_transfer_sheet.dart';
import 'widgets/platform_review_card.dart';

/// Settings.
///
/// Port of `src/pages/dashboard/SettingsView.jsx`: the profile block, the monthly
/// fee (or subscription), and the payment history. Paying is a bank transfer
/// with a receipt an admin confirms — there is no gateway and no card, here or
/// on the website.
class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  final _firstName = TextEditingController();
  final _lastName = TextEditingController();
  final _phone = TextEditingController();
  final _parentEmail = TextEditingController();

  String _state = 'Lagos';
  String _targetExam = 'JAMB';
  String _studentMode = 'online';
  String? _centreId;

  String? _hydratedFrom;
  bool _savingProfile = false;

  List<ClassOffering> _classes = const [];
  bool _loadingClasses = true;
  ClassOffering? _selectedClass;

  List<({String id, String name, String? state, String? city})> _centres =
      const [];

  List<PaymentRecord>? _payments;
  Fees _fees = const Fees();

  PaymentProof? _pendingProof;
  bool _loadingProof = true;

  static const _exams = ['JAMB', 'WAEC', 'NECO', 'GCE'];

  @override
  void initState() {
    super.initState();
    _loadBilling();
  }

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
    _parentEmail.text = profile.parentEmail ?? '';
    _state = nigerianStates.contains(profile.state)
        ? profile.state!
        : nigerianStates.first;
    // Kept verbatim, even when this screen has no option for it. A junior's
    // `BECE (JSS)` is not in [_exams], and coercing it to the first senior exam
    // meant saving the profile silently moved them onto the senior track — and
    // so onto the senior fee list. Changing level goes through the upgrade card,
    // which also resets the lesson fee.
    _targetExam = profile.targetExam ?? _exams.first;
    _studentMode = profile.studentMode;
    _centreId = profile.center;
  }

  Future<void> _loadBilling() async {
    final billing = context.read<BillingRepository>();
    final uid = context.read<SessionController>().account?.uid;

    final classes = await billing.classes();
    if (!mounted) return;
    setState(() {
      _classes = classes;
      _loadingClasses = false;
    });
    _syncSelectedClass();

    final centres = await billing.centres();
    if (mounted) setState(() => _centres = centres);

    final fees = await billing.fees();
    if (mounted) setState(() => _fees = fees);

    if (uid != null) {
      final payments = await billing.payments(uid);
      if (mounted) setState(() => _payments = payments);
    }

    await _refreshProof();
  }

  /// The fees that concern this student: their study mode crossed with their
  /// level. Driven by the toggle above rather than the saved profile, so the list
  /// tracks what they're picking.
  List<ClassOffering> get _myClasses {
    final isJunior =
        context.read<SessionController>().profile?.isJunior ?? false;
    return filterClassesForStudent(
      _classes,
      isPhysical: _studentMode == 'physical',
      isJunior: isJunior,
    );
  }

  /// The chosen fee, but only while it is still one this student may pay for.
  ///
  /// The list is filtered against a profile that can arrive after the classes
  /// do, and against a toggle the student can move afterwards. Reading the
  /// selection back out of the filtered list means neither can leave a fee from
  /// another level or study mode sitting behind the Pay button.
  ClassOffering? get _payableSelection {
    final id = _selectedClass?.id;
    if (id == null) return null;
    for (final offering in _myClasses) {
      if (offering.id == id) return offering;
    }
    return null;
  }

  /// Keeps the selection valid as the filtered list changes, and auto-picks when
  /// there is only one fee on offer — the common case for online students.
  void _syncSelectedClass() {
    final mine = _myClasses;
    if (mine.length == 1) {
      setState(() => _selectedClass = mine.first);
      return;
    }
    if (_selectedClass != null &&
        !mine.any((c) => c.id == _selectedClass!.id)) {
      setState(() => _selectedClass = null);
    }
  }

  @override
  void dispose() {
    _firstName.dispose();
    _lastName.dispose();
    _phone.dispose();
    _parentEmail.dispose();
    super.dispose();
  }

  Future<void> _saveProfile() async {
    final session = context.read<SessionController>();
    final uid = session.account?.uid;
    if (uid == null) return;
    final profiles = context.read<ProfileRepository>();

    setState(() => _savingProfile = true);
    try {
      await profiles.save(uid, {
        'firstName': _firstName.text.trim(),
        'lastName': _lastName.text.trim(),
        'phone': _phone.text.trim(),
        'state': _state,
        // Only when this screen could actually offer it — see _hydrate.
        if (_exams.contains(_targetExam)) 'targetExam': _targetExam,
        'studentMode': _studentMode,
        if (_studentMode == 'physical') 'center': _centreId ?? '',
        if (_parentEmail.text.trim().isNotEmpty)
          'parentEmail': _parentEmail.text.trim().toLowerCase(),
      });
      await session.refreshProfile();
      if (!mounted) return;
      showToast('Profile saved!', variant: ToastVariant.success);
    } catch (_) {
      if (!mounted) return;
      showToast('Save failed. Check your connection.', variant: ToastVariant.error);
    } finally {
      if (mounted) setState(() => _savingProfile = false);
    }
  }

  /// Opens the bank transfer flow for a fee or the Pro plan.
  ///
  /// There is no gateway to hand off to: the student transfers to the NLTC
  /// account, uploads the receipt, and an admin confirms it. The approval is
  /// what unlocks the account, and it arrives over the profile stream — so
  /// there is nothing here to poll and no browser to come back from.
  Future<void> _payByTransfer({required bool lessonFee}) async {
    final session = context.read<SessionController>();
    final uid = session.account?.uid;
    if (uid == null) return;

    final chosen = _payableSelection;
    if (lessonFee && chosen == null) {
      showToast('Please select a class first.', variant: ToastVariant.error);
      return;
    }

    // Which package, before anything is priced. Dismissing the picker is a
    // decision not to pay, so it stops here rather than falling through to a
    // default length the student never chose.
    String? planId;
    if (!lessonFee) {
      planId = await _pickPackage();
      if (!mounted || planId == null) return;
    }

    if (lessonFee && chosen != null) {
      // Remembered on the profile so an admin sees the right fee against this
      // student even if they end up paying cash at the centre.
      await context.read<ProfileRepository>().save(uid, {
        'classId': chosen.id,
        'className': chosen.name,
        'classType': chosen.type,
      }).catchError((_) {});
    }
    if (!mounted) return;

    final submitted = await showBankTransferSheet(
      context,
      type: lessonFee ? 'lesson_fee' : 'plan_upgrade',
      plan: planId,
      classItem: lessonFee ? chosen : null,
    );
    if (!mounted || !submitted) return;

    // The receipt is now with an admin. Swapping the pay button for the
    // pending card immediately is what stops a student transferring twice
    // while they wait.
    await _refreshProof();
    if (!mounted) return;
    final payments = await context.read<BillingRepository>().payments(uid);
    if (mounted) setState(() => _payments = payments);
  }

  /// Asks which Pro package to buy. Null when the student backs out.
  Future<String?> _pickPackage() {
    final profile = context.read<SessionController>().profile;
    final expiry = profile?.planExpiresAt == null
        ? null
        : DateTime.fromMillisecondsSinceEpoch(profile!.planExpiresAt!);
    final daysLeft = expiry == null
        ? 0
        : expiry.difference(DateTime.now()).inDays.clamp(0, 9999);

    return showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (sheetContext) => _PackagePicker(
        fees: _fees,
        // Renewing stacks on top of the days that are left — the backend adds
        // the grant to the remaining window — so the picker can say so rather
        // than leave a student wondering whether paying early costs them.
        daysLeft: (profile?.plan ?? 'free') != 'free' ? daysLeft : 0,
      ),
    );
  }

  /// Re-reads whether a receipt is still with an admin.
  Future<void> _refreshProof() async {
    final proof = await context.read<BillingRepository>().pendingProof();
    if (mounted) {
      setState(() {
        _pendingProof = proof;
        _loadingProof = false;
      });
    }
  }

  /// Junior → senior. Resets the fee status, which the rules allow a student to
  /// do to their own record and the copy warns about plainly.
  Future<void> _upgradeToSenior() async {
    final session = context.read<SessionController>();
    final uid = session.account?.uid;
    if (uid == null) return;

    var exam = _exams.first;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (dialogContext, setDialogState) => AlertDialog(
          title: const Text('Upgrade to Senior Student'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              ProfileDropdown<String>(
                label: 'Target exam',
                value: exam,
                items: [
                  for (final option in _exams)
                    DropdownMenuItem(value: option, child: Text(option)),
                ],
                onChanged: (value) =>
                    setDialogState(() => exam = value ?? exam),
              ),
              const SizedBox(height: Tokens.s4),
              Text(
                'This cannot be undone from here. Your lesson fee status will '
                "reset — you'll need to pay again, or wait for your admin to "
                'activate your account, before lessons and CBT unlock.',
                style: TextStyle(
                  fontSize: 12.5,
                  height: 1.55,
                  color: Theme.of(dialogContext).colorScheme.error,
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(dialogContext).pop(true),
              child: const Text('Confirm Upgrade'),
            ),
          ],
        ),
      ),
    );

    if (confirmed != true || !mounted) return;

    try {
      await context.read<ProfileRepository>().save(uid, {
        'targetExam': exam,
        'lessonFeePaid': false,
        'lessonFeeExpiresAt': null,
      });
      await session.refreshProfile();
      if (!mounted) return;
      showToast(
        'Account upgraded to Senior Student!',
        variant: ToastVariant.success,
      );
    } catch (_) {
      if (!mounted) return;
      showToast('Upgrade failed. Please try again.', variant: ToastVariant.error);
    }
  }

  @override
  Widget build(BuildContext context) {
    final session = context.watch<SessionController>();
    final profile = session.profile;
    final access = session.access;
    final isJunior = profile?.isJunior ?? false;
    final isPhysical = _studentMode == 'physical';

    // Centre students bill through a class: their money buys a seat in a room,
    // and only their centre can price that. Online students buy a Pro package —
    // monthly through to yearly — which is the one flow that offers a term or a
    // session up front. The backend enforces the same split, so an online fee an
    // admin publishes by mistake can no longer quietly become the online
    // student's only option.
    final useClassBilling = isPhysical;

    return ListView(
      padding: const EdgeInsets.fromLTRB(Tokens.s4, 0, Tokens.s4, Tokens.s10),
      children: [
        const PageHeader(
          title: 'Settings',
          subtitle: 'Manage your profile and account preferences.',
        ),

        if (isJunior) ...[
          _SeniorUpgradeCard(onUpgrade: _upgradeToSenior),
          const SizedBox(height: Tokens.s4),
        ],

        // ── Profile ──
        AppCard(
          title: 'Profile Information',
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
                      textCapitalization: TextCapitalization.words,
                    ),
                  ),
                  const SizedBox(width: Tokens.s3),
                  Expanded(
                    child: ProfileField(
                      controller: _lastName,
                      label: 'Last name',
                      textCapitalization: TextCapitalization.words,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: Tokens.s4),
              ProfileField(
                label: 'Email',
                initialValue: session.account?.email ?? '',
                enabled: false,
              ),
              const SizedBox(height: Tokens.s4),
              ProfileField(
                controller: _phone,
                label: 'Phone',
                hint: '080xxxxxxxx',
                keyboardType: TextInputType.phone,
              ),
              const SizedBox(height: Tokens.s4),
              ProfileField(
                controller: _parentEmail,
                label: 'Parent / Guardian email',
                hint: 'parent@example.com',
                helper: 'Optional — for weekly progress reports.',
                keyboardType: TextInputType.emailAddress,
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
              if (_exams.contains(_targetExam))
                ProfileDropdown<String>(
                  label: 'Target exam',
                  value: _targetExam,
                  items: [
                    for (final exam in _exams)
                      DropdownMenuItem(value: exam, child: Text(exam)),
                  ],
                  onChanged: (value) =>
                      setState(() => _targetExam = value ?? _targetExam),
                )
              else
                // A junior's exam has no entry here on purpose: picking a senior
                // one from a dropdown would move their level without resetting
                // the fee. The card at the top of this screen does both.
                ProfileField(
                  label: 'Target exam',
                  initialValue: _targetExam,
                  enabled: false,
                  helper: 'Use “Upgrade to Senior Student” above to change this.',
                ),
              const SizedBox(height: Tokens.s4),
              _StudentTypeToggle(
                value: _studentMode,
                onChanged: (value) {
                  setState(() => _studentMode = value);
                  _syncSelectedClass();
                },
              ),
              if (isPhysical) ...[
                const SizedBox(height: Tokens.s4),
                ProfileDropdown<String>(
                  label: 'Centre',
                  value: _centres.any((c) => c.id == _centreId)
                      ? _centreId
                      : null,
                  hint: _centres.isEmpty
                      ? 'No centres listed yet'
                      : '-- Choose a centre --',
                  items: [
                    for (final centre in _centres)
                      DropdownMenuItem(
                        value: centre.id,
                        child: Text(
                          [
                            centre.name,
                            if (centre.state != null) centre.state!,
                          ].join(' — '),
                        ),
                      ),
                  ],
                  onChanged: (value) => setState(() => _centreId = value),
                ),
              ],
              const SizedBox(height: Tokens.s5),
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: _savingProfile ? null : _saveProfile,
                  icon: _savingProfile
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.save_rounded, size: 18),
                  label: Text(_savingProfile ? 'Saving…' : 'Save Profile'),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: Tokens.s4),

        // ── Fee / subscription ──
        //
        // A receipt already with an admin replaces the pay card outright.
        // Leaving a Pay button up while one is under review is how a student
        // ends up transferring for the same month twice.
        if (_pendingProof case final proof?)
          _PendingReviewCard(proof: proof, onRefresh: _refreshProof)
        else if (useClassBilling)
          _FeeCard(
            isPhysical: isPhysical,
            isJunior: isJunior,
            access: access,
            classes: _myClasses,
            loadingClasses: _loadingClasses,
            selected: _payableSelection,
            onSelect: (offering) => setState(() => _selectedClass = offering),
            busy: _loadingProof,
            onPay: () => _payByTransfer(lessonFee: true),
          )
        else
          _SubscriptionCard(
            profile: profile,
            fees: _fees,
            busy: _loadingProof,
            onUpgrade: () => _payByTransfer(lessonFee: false),
          ),
        const SizedBox(height: Tokens.s4),

        _PaymentHistoryCard(payments: _payments),
        const SizedBox(height: Tokens.s4),

        const PlatformReviewCard(),
        const SizedBox(height: Tokens.s4),

        const _LegalCard(),
        const SizedBox(height: Tokens.s4),

        // App-only: the website has no theme switch because it has no dark mode.
        const _AppearanceCard(),
      ],
    );
  }
}

// ─── Profile bits ───────────────────────────────────────────────────────────

class _StudentTypeToggle extends StatelessWidget {
  const _StudentTypeToggle({required this.value, required this.onChanged});

  final String value;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Student type',
          style: TextStyle(
            fontSize: 11.5,
            fontWeight: FontWeight.w700,
            color: scheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 6),
        Row(
          children: [
            for (final option in const [
              (id: 'online', icon: Icons.wifi_rounded, label: 'Online'),
              (
                id: 'physical',
                icon: Icons.business_rounded,
                label: 'Physical Centre',
              ),
            ])
              Expanded(
                child: Padding(
                  padding: EdgeInsets.only(
                    right: option.id == 'online' ? Tokens.s2 : 0,
                  ),
                  child: OutlinedButton.icon(
                    onPressed: () => onChanged(option.id),
                    style: OutlinedButton.styleFrom(
                      backgroundColor: value == option.id
                          ? scheme.primaryContainer
                          : null,
                      side: BorderSide(
                        color: value == option.id
                            ? scheme.primary
                            : scheme.outlineVariant,
                        width: 1.5,
                      ),
                      padding: const EdgeInsets.symmetric(vertical: 11),
                    ),
                    icon: Icon(option.icon, size: 15),
                    label: Text(
                      option.label,
                      style: const TextStyle(fontSize: 12),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ],
    );
  }
}

class _SeniorUpgradeCard extends StatelessWidget {
  const _SeniorUpgradeCard({required this.onUpgrade});

  final VoidCallback onUpgrade;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return AppCard(
      title: 'Upgrade to Senior Student',
      titleIcon: Icons.school_rounded,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'Ready to move up from Junior (BECE / Junior WAEC) to Senior '
            'Secondary (JAMB, WAEC, NECO, GCE)? Upgrading switches your account '
            'to the senior track and unlocks senior lessons, CBT and mock exams.',
            style: TextStyle(
              fontSize: 12.5,
              height: 1.55,
              color: scheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: Tokens.s3),
          _Notice(
            icon: Icons.warning_amber_rounded,
            tone: BlueprintPalette.warning,
            message: "After upgrading you'll need to pay the senior lesson fee — "
                'or wait for your admin to activate you — before lessons, CBT '
                'and live classes unlock again.',
          ),
          const SizedBox(height: Tokens.s4),
          FilledButton.icon(
            onPressed: onUpgrade,
            icon: const Icon(Icons.arrow_upward_rounded, size: 17),
            label: const Text('Upgrade to Senior Student'),
          ),
        ],
      ),
    );
  }
}

// ─── Fees ───────────────────────────────────────────────────────────────────

class _FeeCard extends StatelessWidget {
  const _FeeCard({
    required this.isPhysical,
    required this.isJunior,
    required this.access,
    required this.classes,
    required this.loadingClasses,
    required this.selected,
    required this.onSelect,
    required this.busy,
    required this.onPay,
  });

  final bool isPhysical;
  final bool isJunior;
  final AccessState access;
  final List<ClassOffering> classes;
  final bool loadingClasses;
  final ClassOffering? selected;
  final ValueChanged<ClassOffering> onSelect;
  final bool busy;
  final VoidCallback onPay;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    // One access read covers both grants, so an online student on an active plan
    // is never shown an "unpaid" card the day a centre fee is introduced.
    final feePaid = access.active && access.reason != AccessReason.trial;
    final daysLeft = access.active ? access.daysLeft : null;
    final expiry = access.expiresAt;

    return AppCard(
      title: isPhysical ? 'Monthly Lesson Fee' : 'Subscription',
      titleIcon: isPhysical
          ? Icons.calendar_month_rounded
          : Icons.credit_card_rounded,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (feePaid) ...[
            _Notice(
              icon: Icons.check_circle_rounded,
              tone: BlueprintPalette.success,
              message: expiry == null
                  ? 'Monthly fee paid — access active.'
                  : 'Monthly fee paid — active until '
                      '${DateFormat('d MMMM yyyy').format(expiry)}'
                      '${daysLeft != null && daysLeft <= 7 ? daysLeft == 0 ? ' (expires today)' : ' ($daysLeft day${daysLeft == 1 ? '' : 's'} left)' : ''}.',
            ),
            if (daysLeft != null && daysLeft <= 7) ...[
              const SizedBox(height: Tokens.s3),
              _Notice(
                icon: Icons.warning_amber_rounded,
                tone: BlueprintPalette.warning,
                message:
                    'Renew before your access expires to avoid interruption.',
              ),
            ],
            const SizedBox(height: Tokens.s4),
            Text(
              'Want to renew early?',
              style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant),
            ),
            const SizedBox(height: Tokens.s2),
          ] else ...[
            _Notice(
              icon: Icons.event_busy_rounded,
              tone: BlueprintPalette.warning,
              message: expiry != null
                  ? 'Your monthly access expired on '
                      '${DateFormat('d MMMM yyyy').format(expiry)}. Renew below.'
                  : 'Pay your monthly ${isPhysical ? 'lesson fee' : 'fee'} to '
                      'unlock all features.',
            ),
            const SizedBox(height: Tokens.s4),
          ],
          _ClassSelector(
            classes: classes,
            loading: loadingClasses,
            selected: selected,
            onSelect: onSelect,
            isPhysical: isPhysical,
            isJunior: isJunior,
          ),
          const SizedBox(height: Tokens.s4),
          FilledButton.icon(
            onPressed: busy || selected == null ? null : onPay,
            icon: busy
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : Icon(
                    feePaid
                        ? Icons.autorenew_rounded
                        : Icons.account_balance_rounded,
                    size: 18,
                  ),
            label: Text(
              feePaid
                  ? 'Renew — Bank Transfer'
                  : isPhysical
                      ? 'Pay Monthly Fee'
                      : 'Pay by Bank Transfer',
            ),
          ),
          const SizedBox(height: Tokens.s3),
          Text(
            isPhysical
                ? 'Already paid at the centre? Your admin will activate your '
                    'account — no need to pay again.'
                : 'Transfer to the NLTC account, upload your receipt, and your '
                    'access is opened once an admin confirms it — usually '
                    '$kConfirmationWindow. Access runs for 30 days.',
            style: TextStyle(
              fontSize: 11,
              height: 1.5,
              color: scheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}

class _ClassSelector extends StatelessWidget {
  const _ClassSelector({
    required this.classes,
    required this.loading,
    required this.selected,
    required this.onSelect,
    required this.isPhysical,
    required this.isJunior,
  });

  final List<ClassOffering> classes;
  final bool loading;
  final ClassOffering? selected;
  final ValueChanged<ClassOffering> onSelect;
  final bool isPhysical;
  final bool isJunior;

  static const _typeColors = <String, Color>{
    'general': BlueprintPalette.b700,
    'weekend': Color(0xFF7C3AED),
    'intensive': Color(0xFFDC2626),
    'holiday': Color(0xFF059669),
  };

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final money = NumberFormat.decimalPattern();

    if (loading) return const SkeletonListItem(lines: 2);

    if (classes.isEmpty) {
      return Text(
        'No fee has been set for ${isJunior ? 'junior' : 'senior'} '
        '${isPhysical ? 'centre' : 'online'} students yet. Contact the admin.',
        style: TextStyle(fontSize: 12.5, color: scheme.onSurfaceVariant),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          classes.length == 1 ? 'Your fee' : 'Select a class',
          style: TextStyle(
            fontSize: 11.5,
            fontWeight: FontWeight.w700,
            color: scheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: Tokens.s2),
        for (final offering in classes)
          Padding(
            padding: const EdgeInsets.only(bottom: Tokens.s2),
            child: InkWell(
              onTap: () => onSelect(offering),
              borderRadius: BorderRadius.circular(Tokens.rSm),
              child: Container(
                padding: const EdgeInsets.all(Tokens.s3),
                decoration: BoxDecoration(
                  color: selected?.id == offering.id
                      ? scheme.primaryContainer.withValues(alpha: 0.45)
                      : scheme.surfaceContainerLowest,
                  borderRadius: BorderRadius.circular(Tokens.rSm),
                  border: Border.all(
                    color: selected?.id == offering.id
                        ? scheme.primary
                        : scheme.outlineVariant,
                    width: 1.5,
                  ),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            offering.name,
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w800,
                              color: scheme.onSurface,
                            ),
                          ),
                          if (offering.timing != null) ...[
                            const SizedBox(height: 2),
                            Row(
                              children: [
                                Icon(
                                  Icons.schedule_rounded,
                                  size: 11,
                                  color: scheme.onSurfaceVariant,
                                ),
                                const SizedBox(width: 3),
                                Text(
                                  offering.timing!,
                                  style: TextStyle(
                                    fontSize: 11,
                                    color: scheme.onSurfaceVariant,
                                  ),
                                ),
                              ],
                            ),
                          ],
                          if (offering.description != null) ...[
                            const SizedBox(height: 3),
                            Text(
                              offering.description!,
                              style: TextStyle(
                                fontSize: 11,
                                height: 1.4,
                                color: scheme.onSurfaceVariant,
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                    const SizedBox(width: Tokens.s2),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 7,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color: _typeColors[offering.type] ??
                                BlueprintPalette.b700,
                            borderRadius: BorderRadius.circular(100),
                          ),
                          child: Text(
                            offering.type.toUpperCase(),
                            style: const TextStyle(
                              fontSize: 8,
                              fontWeight: FontWeight.w900,
                              letterSpacing: 0.5,
                              color: Colors.white,
                            ),
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          '₦${money.format(offering.price)}/mo',
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w900,
                            color: scheme.primary,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
        if (selected != null)
          _Notice(
            icon: Icons.info_outline_rounded,
            tone: BlueprintPalette.b600,
            message: 'You will be charged ₦${money.format(selected!.price)} for '
                '${selected!.name} — valid for 30 days.',
          ),
      ],
    );
  }
}

/// The four lengths of Pro, priced from the backend's fee settings.
///
/// One plan, four packages — every one of them unlocks exactly the same thing.
/// The only variable is how long is paid for, so the cards lead with the length
/// and the saving rather than repeating an identical feature list four times.
class _PackagePicker extends StatefulWidget {
  const _PackagePicker({required this.fees, required this.daysLeft});

  final Fees fees;

  /// Days still on the current plan, or 0. Renewals stack on top of these.
  final int daysLeft;

  @override
  State<_PackagePicker> createState() => _PackagePickerState();
}

class _PackagePickerState extends State<_PackagePicker> {
  String _selected = kDefaultProPlanId;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final money = NumberFormat.decimalPattern();
    final fees = widget.fees;

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(
          Tokens.s4,
          0,
          Tokens.s4,
          Tokens.s4,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              widget.daysLeft > 0 ? 'Renew your Pro plan' : 'Choose your Pro package',
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: Tokens.s2),
            Text(
              'Every package unlocks the same thing — all premium video lessons, '
              'live classes, the full question bank and priority support. The '
              'only difference is how long you pay for.',
              style: TextStyle(
                fontSize: 12.5,
                height: 1.5,
                color: scheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: Tokens.s4),
            Flexible(
              child: SingleChildScrollView(
                child: Column(
                  children: [
                    for (final plan in kProPlans) ...[
                      _PackageTile(
                        plan: plan,
                        price: fees.priceOf(plan),
                        monthlyRate: fees.monthlyRateOf(plan),
                        savingPercent: fees.savingPercentOf(plan),
                        selected: _selected == plan.id,
                        onTap: () => setState(() => _selected = plan.id),
                      ),
                      const SizedBox(height: Tokens.s2),
                    ],
                  ],
                ),
              ),
            ),
            if (widget.daysLeft > 0) ...[
              const SizedBox(height: Tokens.s2),
              _Notice(
                icon: Icons.add_circle_outline_rounded,
                tone: BlueprintPalette.success,
                message: 'You have ${widget.daysLeft} '
                    'day${widget.daysLeft == 1 ? '' : 's'} left. Renewing adds '
                    'to that — you lose nothing by paying early.',
              ),
            ],
            const SizedBox(height: Tokens.s4),
            FilledButton.icon(
              onPressed: () => Navigator.of(context).pop(_selected),
              icon: const Icon(Icons.account_balance_rounded, size: 18),
              label: Text(
                'Continue — ₦${money.format(fees.priceOf(resolveProPlan(_selected)))}',
              ),
            ),
            const SizedBox(height: Tokens.s2),
            Text(
              'Bank transfer · activated in $kConfirmationWindow · '
              'payments are final',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 10.5, color: scheme.onSurfaceVariant),
            ),
          ],
        ),
      ),
    );
  }
}

class _PackageTile extends StatelessWidget {
  const _PackageTile({
    required this.plan,
    required this.price,
    required this.monthlyRate,
    required this.savingPercent,
    required this.selected,
    required this.onTap,
  });

  final ProPlan plan;
  final int price;
  final int monthlyRate;
  final int savingPercent;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final money = NumberFormat.decimalPattern();

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(Tokens.rSm),
      child: Container(
        padding: const EdgeInsets.all(Tokens.s3),
        decoration: BoxDecoration(
          color: selected
              ? BlueprintPalette.b500.withValues(alpha: 0.07)
              : scheme.surface,
          border: Border.all(
            color: selected ? BlueprintPalette.b500 : scheme.outlineVariant,
            width: selected ? 1.6 : 1,
          ),
          borderRadius: BorderRadius.circular(Tokens.rSm),
        ),
        child: Row(
          children: [
            Icon(
              selected
                  ? Icons.radio_button_checked_rounded
                  : Icons.radio_button_unchecked_rounded,
              size: 20,
              color: selected ? BlueprintPalette.b500 : scheme.outline,
            ),
            const SizedBox(width: Tokens.s3),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text(
                        plan.label,
                        style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      if (savingPercent > 0) ...[
                        const SizedBox(width: Tokens.s2),
                        AppBadge(
                          label: 'Save $savingPercent%',
                          tone: BadgeTone.success,
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: 2),
                  Text(
                    plan.months == 1
                        ? '${plan.days} days access'
                        : '₦${money.format(monthlyRate)}/month · '
                            '${plan.days} days access',
                    style: TextStyle(
                      fontSize: 11.5,
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
            Text(
              '₦${money.format(price)}',
              style: TextStyle(
                fontSize: 17,
                fontWeight: FontWeight.w900,
                // The web's gold reads as brand blue in the Blueprint remap.
                color: Theme.of(context).brightness == Brightness.dark
                    ? BlueprintPalette.b300
                    : BlueprintPalette.b600,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SubscriptionCard extends StatelessWidget {
  const _SubscriptionCard({
    required this.profile,
    required this.fees,
    required this.busy,
    required this.onUpgrade,
  });

  final AppUser? profile;
  final Fees fees;
  final bool busy;
  final VoidCallback onUpgrade;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final plan = profile?.plan ?? 'free';
    final isPro = plan != 'free';
    final expiry = profile?.planExpiresAt == null
        ? null
        : DateTime.fromMillisecondsSinceEpoch(profile!.planExpiresAt!);
    final daysLeft =
        expiry?.difference(DateTime.now()).inDays.clamp(0, 9999);
    final money = NumberFormat.decimalPattern();

    return AppCard(
      title: 'Subscription',
      titleIcon: Icons.credit_card_rounded,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            padding: const EdgeInsets.all(Tokens.s3),
            decoration: BoxDecoration(
              color: scheme.surfaceContainerHigh,
              borderRadius: BorderRadius.circular(Tokens.rSm),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    'Current plan',
                    style: TextStyle(
                      fontSize: 12,
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                ),
                AppBadge(
                  label: isPro ? 'Pro' : 'Free',
                  tone: isPro ? BadgeTone.gold : BadgeTone.navy,
                  icon: isPro ? Icons.local_fire_department_rounded : null,
                ),
              ],
            ),
          ),
          if (isPro && expiry != null) ...[
            const SizedBox(height: Tokens.s3),
            if (daysLeft != null && daysLeft <= 7)
              _Notice(
                icon: Icons.warning_amber_rounded,
                tone: BlueprintPalette.warning,
                message: daysLeft == 0
                    ? 'Your plan expires today!'
                    : 'Your plan expires in $daysLeft '
                        'day${daysLeft == 1 ? '' : 's'} — renew to keep access.',
              )
            else
              _Notice(
                icon: Icons.check_circle_rounded,
                tone: BlueprintPalette.success,
                message: 'Your Pro plan is active until '
                    '${DateFormat('d MMMM yyyy').format(expiry)}.',
              ),
          ],
          const SizedBox(height: Tokens.s4),
          FilledButton.icon(
            onPressed: busy ? null : onUpgrade,
            icon: busy
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : Icon(
                    isPro ? Icons.autorenew_rounded : Icons.rocket_launch_rounded,
                    size: 18,
                  ),
            label: Text(
              isPro
                  ? 'Renew Plan'
                  // The cheapest way in, so the button is never quoting a price
                  // above the one the picker opens on.
                  : 'Go Pro — from ₦${money.format(fees.priceOf(resolveProPlan(kDefaultProPlanId)))}/mo',
            ),
          ),
          const SizedBox(height: Tokens.s3),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.lock_rounded, size: 11, color: scheme.onSurfaceVariant),
              const SizedBox(width: 4),
              Text(
                'Bank transfer · activated in $kConfirmationWindow',
                style: TextStyle(
                  fontSize: 10.5,
                  color: scheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

// ─── History ────────────────────────────────────────────────────────────────

/// Shown in place of the pay card while a receipt is with an admin.
class _PendingReviewCard extends StatelessWidget {
  const _PendingReviewCard({required this.proof, required this.onRefresh});

  final PaymentProof proof;
  final Future<void> Function() onRefresh;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final money = NumberFormat.decimalPattern();

    return AppCard(
      title: 'Monthly Fee',
      titleIcon: Icons.hourglass_top_rounded,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            padding: const EdgeInsets.all(Tokens.s4),
            decoration: BoxDecoration(
              color: BlueprintPalette.b500.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(Tokens.rSm),
              border: Border.all(
                color: BlueprintPalette.b500.withValues(alpha: 0.35),
              ),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(Icons.hourglass_top_rounded,
                    color: BlueprintPalette.b500),
                const SizedBox(width: Tokens.s3),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Receipt received — awaiting confirmation',
                        style: TextStyle(
                          fontWeight: FontWeight.w800,
                          color: BlueprintPalette.b600,
                        ),
                      ),
                      const SizedBox(height: Tokens.s2),
                      Text(
                        "We're checking your ₦${money.format(proof.amount)} "
                        'transfer for ${proof.description ?? 'your fee'}. Your '
                        'account opens as soon as it is confirmed — usually '
                        "$kConfirmationWindow. We'll notify you the moment "
                        "it's done.",
                        style: TextStyle(
                          fontSize: 12.5,
                          height: 1.55,
                          color: scheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: Tokens.s3),
          OutlinedButton.icon(
            onPressed: onRefresh,
            icon: const Icon(Icons.refresh_rounded, size: 18),
            label: const Text('Check status'),
          ),
        ],
      ),
    );
  }
}

// ─── History ────────────────────────────────────────────────────────────────

class _PaymentHistoryCard extends StatelessWidget {
  const _PaymentHistoryCard({required this.payments});

  final List<PaymentRecord>? payments;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final money = NumberFormat.decimalPattern();

    return AppCard(
      title: 'Payment History',
      titleIcon: Icons.history_rounded,
      padding: payments == null || payments!.isEmpty
          ? const EdgeInsets.all(Tokens.s4)
          : EdgeInsets.zero,
      child: payments == null
          ? const SkeletonTable()
          : payments!.isEmpty
              ? const EmptyState(
                  icon: Icons.receipt_long_rounded,
                  title: 'No payments yet',
                  message: 'Your payment history will appear here after your '
                      'first transaction.',
                )
              : Column(
                  children: [
                    for (final payment in payments!)
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: Tokens.s4,
                          vertical: Tokens.s3,
                        ),
                        decoration: BoxDecoration(
                          border: payment == payments!.last
                              ? null
                              : Border(
                                  bottom: BorderSide(
                                    color: scheme.outlineVariant,
                                  ),
                                ),
                        ),
                        child: Row(
                          children: [
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    payment.description ?? 'Payment',
                                    style: TextStyle(
                                      fontSize: 12.5,
                                      fontWeight: FontWeight.w800,
                                      color: scheme.onSurface,
                                    ),
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    [
                                      if (payment.createdAt != null)
                                        DateFormat('d MMM yyyy')
                                            .format(payment.createdAt!),
                                      if (payment.periodLabel != null)
                                        payment.periodLabel!,
                                    ].join(' · '),
                                    style: TextStyle(
                                      fontSize: 11,
                                      color: scheme.onSurfaceVariant,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(width: Tokens.s2),
                            Column(
                              crossAxisAlignment: CrossAxisAlignment.end,
                              children: [
                                Text(
                                  '₦${money.format(payment.amount)}',
                                  style: TextStyle(
                                    fontSize: 13,
                                    fontWeight: FontWeight.w800,
                                    color: scheme.onSurface,
                                  ),
                                ),
                                const SizedBox(height: 3),
                                AppBadge(
                                  label: payment.status,
                                  tone: payment.succeeded
                                      ? BadgeTone.success
                                      : BadgeTone.error,
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                  ],
                ),
    );
  }
}

/// The theme switch. App-only — the website has no dark mode to match.
/// The agreement the student is actually operating under.
///
/// The app had no route to it at all, which mattered once messaging began
/// carrying a consent term: reporting a conversation sends the whole thread to
/// our staff, and the terms are where that is written down. Burying the only
/// copy on a website the student may never open is not consent worth relying
/// on. Opened in the in-app browser so nobody loses their place in the app.
class _LegalCard extends StatelessWidget {
  const _LegalCard();

  static const _documents = <({String label, IconData icon, String path})>[
    (
      label: 'Terms & Conditions',
      icon: Icons.gavel_rounded,
      path: 'https://nltc.com.ng/terms-and-conditions.html',
    ),
    (
      label: 'Privacy Policy',
      icon: Icons.lock_outline_rounded,
      path: 'https://nltc.com.ng/privacy-policy.html',
    ),
    (
      label: 'Refund Policy',
      icon: Icons.receipt_long_rounded,
      path: 'https://nltc.com.ng/refund-policy.html',
    ),
  ];

  @override
  Widget build(BuildContext context) => AppCard(
        title: 'Legal',
        titleIcon: Icons.description_outlined,
        child: Column(
          children: [
            for (final doc in _documents)
              ListTile(
                contentPadding: EdgeInsets.zero,
                dense: true,
                leading: Icon(doc.icon, size: 20),
                title: Text(doc.label, style: const TextStyle(fontSize: 13.5)),
                trailing: const Icon(Icons.open_in_new_rounded, size: 17),
                onTap: () =>
                    openInAppBrowser(context, doc.path, title: doc.label),
              ),
          ],
        ),
      );
}

class _AppearanceCard extends StatelessWidget {
  const _AppearanceCard();

  @override
  Widget build(BuildContext context) {
    final theme = context.watch<ThemeController>();
    final scheme = Theme.of(context).colorScheme;
    final (icon, label) = theme.indicator;

    return AppCard(
      title: 'Appearance',
      titleIcon: Icons.palette_rounded,
      child: Row(
        children: [
          Icon(icon, size: 20, color: scheme.primary),
          const SizedBox(width: Tokens.s3),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w800,
                    color: scheme.onSurface,
                  ),
                ),
                const SizedBox(height: 1),
                Text(
                  'Dark mode is an app feature — the website is light only.',
                  style: TextStyle(
                    fontSize: 11,
                    color: scheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          TextButton(onPressed: theme.cycle, child: const Text('Change')),
        ],
      ),
    );
  }
}

/// The tinted note the settings page leans on for state and warnings.
class _Notice extends StatelessWidget {
  const _Notice({
    required this.icon,
    required this.tone,
    required this.message,
  });

  final IconData icon;
  final Color tone;
  final String message;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.all(Tokens.s3),
        decoration: BoxDecoration(
          color: tone.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(Tokens.rSm),
          border: Border.all(color: tone.withValues(alpha: 0.35)),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, size: 15, color: tone),
            const SizedBox(width: 7),
            Expanded(
              child: Text(
                message,
                style: TextStyle(
                  fontSize: 12,
                  height: 1.5,
                  fontWeight: FontWeight.w600,
                  color: Theme.of(context).colorScheme.onSurface,
                ),
              ),
            ),
          ],
        ),
      );
}
