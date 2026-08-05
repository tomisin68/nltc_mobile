import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../data/repositories/billing_repository.dart';
import '../../data/repositories/profile_repository.dart';
import '../../data/services/api_client.dart' show ApiException;
import '../../domain/models/access_state.dart';
import '../../domain/models/app_user.dart';
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

/// Settings.
///
/// Port of `src/pages/dashboard/SettingsView.jsx`: the profile block, the monthly
/// fee (or subscription) with checkout, and the payment history. Checkout hands
/// off to Flutterwave in the browser exactly as the website does — the app never
/// touches card details, which keeps it out of PCI scope entirely.
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

  bool _checkingOut = false;

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

  /// Starts a checkout and runs it inside the app.
  ///
  /// Flutterwave is hosted, so the app never sees a card — but it does stay on
  /// screen around it. Handing the URL to the system browser used to drop the
  /// student out of NLTC mid-payment and leave them to find their own way back;
  /// now the checkout is a screen they can close, and the backend's callback
  /// redirect is what tells the app it is over.
  Future<void> _checkout({required bool lessonFee}) async {
    final session = context.read<SessionController>();
    final uid = session.account?.uid;
    if (uid == null) return;

    final chosen = _payableSelection;
    if (lessonFee && chosen == null) {
      showToast('Please select a class first.', variant: ToastVariant.error);
      return;
    }

    final billing = context.read<BillingRepository>();
    final profiles = context.read<ProfileRepository>();

    setState(() => _checkingOut = true);
    try {
      if (lessonFee && chosen != null) {
        // Remembered on the profile so an admin sees the right fee against this
        // student even if they end up paying cash at the centre.
        await profiles.save(uid, {
          'classId': chosen.id,
          'className': chosen.name,
          'classType': chosen.type,
        }).catchError((_) {});
      }

      final url = lessonFee
          ? await billing.startCheckout(
              type: 'lesson_fee',
              amount: chosen!.price,
              metadata: {
                'type': 'lesson_fee',
                'className': chosen.name,
                'classId': chosen.id,
                'description': chosen.name,
              },
            )
          : await billing.startCheckout(type: 'plan_upgrade', plan: 'pro');

      if (!mounted) return;
      // The backend verifies the transaction and then bounces to
      // `/payment/result?status=…` on the website. That redirect is the signal
      // the payment is finished — there is no page past it worth showing inside
      // the app, so the browser closes on it and reports what it said.
      final landed = await openInAppBrowser(
        context,
        url,
        title: lessonFee ? 'Lesson fee' : 'Upgrade to Pro',
        closeWhen: (uri) => uri.path.contains('/payment/result'),
      );
      if (!mounted) return;

      final status = landed == null
          ? null
          : Uri.tryParse(landed)?.queryParameters['status'];
      switch (status) {
        case 'success':
          // The unlock itself lands over the profile stream; refreshing just
          // stops the student staring at a locked screen while it does.
          await session.refreshProfile();
          if (!mounted) return;
          showToast('Payment received — thank you!',
              variant: ToastVariant.success);
        case 'cancelled':
          showToast('Payment cancelled.');
        case null:
          // Backed out of the browser without reaching the callback. The
          // payment may still land, so this is not an error.
          break;
        default:
          showToast(
            'That payment did not go through. Please try again.',
            variant: ToastVariant.error,
          );
      }
    } on ApiException catch (e) {
      if (!mounted) return;
      // The backend refuses a checkout for reasons the student can act on — the
      // class was closed, or it has no price set. Replacing all of them with
      // "please try again" turned those into a button that silently did nothing.
      showToast(e.message, variant: ToastVariant.error);
    } catch (_) {
      if (!mounted) return;
      showToast(
        'Could not start the payment. Please try again.',
        variant: ToastVariant.error,
      );
    } finally {
      if (mounted) setState(() => _checkingOut = false);
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

    // Physical students always bill through a class. Online students do too once
    // an admin publishes an online fee for their level; until then they keep the
    // plan-upgrade flow so nothing breaks before the fee is set up.
    final useClassBilling = isPhysical || _myClasses.isNotEmpty;

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
        if (useClassBilling)
          _FeeCard(
            isPhysical: isPhysical,
            isJunior: isJunior,
            access: access,
            classes: _myClasses,
            loadingClasses: _loadingClasses,
            selected: _payableSelection,
            onSelect: (offering) => setState(() => _selectedClass = offering),
            busy: _checkingOut,
            onPay: () => _checkout(lessonFee: true),
          )
        else
          _SubscriptionCard(
            profile: profile,
            fees: _fees,
            busy: _checkingOut,
            onUpgrade: () => _checkout(lessonFee: false),
          ),
        const SizedBox(height: Tokens.s4),

        _PaymentHistoryCard(payments: _payments),
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
                    feePaid ? Icons.autorenew_rounded : Icons.credit_card_rounded,
                    size: 18,
                  ),
            label: Text(
              feePaid
                  ? 'Renew for Another Month'
                  : isPhysical
                      ? 'Pay Monthly Fee'
                      : 'Pay Now',
            ),
          ),
          const SizedBox(height: Tokens.s3),
          Text(
            isPhysical
                ? 'Already paid at the centre? Your admin will activate your '
                    'account — no need to pay again.'
                : 'Your access unlocks immediately after payment and runs for '
                    '30 days.',
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
                  : 'Upgrade to Pro — ₦${money.format(fees.proMonthly)}/mo',
            ),
          ),
          const SizedBox(height: Tokens.s3),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.lock_rounded, size: 11, color: scheme.onSurfaceVariant),
              const SizedBox(width: 4),
              Text(
                'Secured by Flutterwave · Cancel anytime',
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
