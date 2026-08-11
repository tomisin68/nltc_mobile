/// The Pro packages an online student can buy.
///
/// Mirrors `nltc-backend/src/config/plans.js` and the website's
/// `src/utils/plans.js`. The backend is the authority — it prices every quote
/// and every receipt, and no amount is ever sent from here — but the picker has
/// to show a price before the quote comes back, and a student choosing between
/// four lengths needs the saving spelled out.
///
/// Centre (physical) students never see these: their fee is their centre's
/// monthly lesson fee, priced from the class document.
library;

class ProPlan {
  const ProPlan({
    required this.id,
    required this.cycle,
    required this.label,
    required this.months,
    required this.days,
    required this.feeKey,
    required this.defaultPrice,
    required this.blurb,
  });

  /// What travels to the backend as `plan`.
  final String id;

  /// What the backend records on the profile as `planCycle`.
  final String cycle;

  /// "Monthly", "6 Months" — what the student reads.
  final String label;

  final int months;

  /// Days of access an approval grants. Not `months * 30` — the backend's
  /// figure is the one that matters and it is copied here verbatim.
  final int days;

  /// The field in `settings/fees` an admin overrides the price from.
  final String feeKey;

  final int defaultPrice;

  final String blurb;
}

const kProPlans = <ProPlan>[
  ProPlan(
    id: 'pro_monthly',
    cycle: 'monthly',
    label: 'Monthly',
    months: 1,
    days: 30,
    feeKey: 'proMonthly',
    defaultPrice: 3000,
    blurb: 'Try a month. Renew when you want to.',
  ),
  ProPlan(
    id: 'pro_quarterly',
    cycle: 'quarterly',
    label: 'Quarterly',
    months: 3,
    days: 91,
    feeKey: 'proQuarterly',
    defaultPrice: 10000,
    blurb: 'A full term of prep, paid once.',
  ),
  ProPlan(
    id: 'pro_biannual',
    cycle: 'biannual',
    label: '6 Months',
    months: 6,
    days: 182,
    feeKey: 'proBiannual',
    defaultPrice: 15000,
    blurb: 'Two terms — the usual run-up to an exam.',
  ),
  ProPlan(
    id: 'pro_yearly',
    cycle: 'yearly',
    label: 'Yearly',
    months: 12,
    days: 365,
    feeKey: 'proYearly',
    defaultPrice: 30000,
    blurb: 'The whole session. Best value by a distance.',
  ),
];

/// What a bare `pro` meant before the packages existed.
const kDefaultProPlanId = 'pro_monthly';

/// The package for an id. A null or legacy `pro` resolves to monthly, so a
/// profile written before the packages existed still reads as something.
ProPlan resolveProPlan(String? id) {
  if (id == null || id.isEmpty || id == 'pro') {
    return kProPlans.firstWhere((p) => p.id == kDefaultProPlanId);
  }
  return kProPlans.firstWhere(
    (p) => p.id == id,
    orElse: () => kProPlans.firstWhere((p) => p.id == kDefaultProPlanId),
  );
}
