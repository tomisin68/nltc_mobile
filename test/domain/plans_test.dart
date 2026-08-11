import 'package:flutter_test/flutter_test.dart';
import 'package:nltc/data/repositories/billing_repository.dart';
import 'package:nltc/domain/plans.dart';

void main() {
  group('resolveProPlan', () {
    test('resolves each package by id', () {
      expect(resolveProPlan('pro_monthly').days, 30);
      expect(resolveProPlan('pro_quarterly').days, 91);
      expect(resolveProPlan('pro_biannual').days, 182);
      expect(resolveProPlan('pro_yearly').days, 365);
    });

    // Receipts submitted by an older build carry a bare `pro`, and profiles
    // activated before the packages existed carry nothing at all. Neither may
    // resolve to null — a student in that state still has to see a plan.
    test('treats a legacy or missing plan as monthly', () {
      expect(resolveProPlan('pro').id, kDefaultProPlanId);
      expect(resolveProPlan(null).id, kDefaultProPlanId);
      expect(resolveProPlan('').id, kDefaultProPlanId);
    });

    test('falls back rather than throwing on an unknown id', () {
      expect(resolveProPlan('pro_decade').id, kDefaultProPlanId);
    });
  });

  group('Fees.priceOf', () {
    test('uses the catalogue price when nothing is published', () {
      const fees = Fees();
      for (final plan in kProPlans) {
        expect(fees.priceOf(plan), plan.defaultPrice);
      }
    });

    test('an admin override wins over the catalogue', () {
      const fees = Fees(packagePrices: {'proYearly': 25000});
      expect(fees.priceOf(resolveProPlan('pro_yearly')), 25000);
      // Untouched packages keep their catalogue price — a partial settings
      // document must not blank the rest.
      expect(fees.priceOf(resolveProPlan('pro_monthly')), 3000);
    });

    test('ignores a zero or negative stored price', () {
      const fees = Fees(packagePrices: {'proMonthly': 0});
      expect(fees.priceOf(resolveProPlan('pro_monthly')), 3000);
    });

    test('reads only package fields off the fees payload', () {
      final fees = Fees.fromJson({
        'proMonthly': 3000,
        'proYearly': 30000,
        'lessonFeeDefault': 7000,
      });
      expect(fees.priceOf(resolveProPlan('pro_monthly')), 3000);
      expect(fees.priceOf(resolveProPlan('pro_yearly')), 30000);
      expect(fees.lessonFeeDefault, 7000);
    });
  });

  group('savings', () {
    // The claim on a package card has to survive a student doing the
    // multiplication, so it is computed against the monthly price rather than
    // written down. At ₦3,000 a month, three months costs ₦9,000 — less than
    // the ₦10,000 quarterly package — so quarterly must claim nothing.
    test('claims nothing where paying up front is not cheaper', () {
      const fees = Fees();
      expect(fees.savingPercentOf(resolveProPlan('pro_quarterly')), 0);
      expect(fees.monthlyRateOf(resolveProPlan('pro_quarterly')), 3333);
    });

    test('rounds a genuine saving down, never up', () {
      const fees = Fees();
      // 6 × 3000 = 18,000 against 15,000 → 16.67%, advertised as 16%.
      expect(fees.savingPercentOf(resolveProPlan('pro_biannual')), 16);
      expect(fees.savingPercentOf(resolveProPlan('pro_yearly')), 16);
    });

    test('monthly never advertises a saving against itself', () {
      const fees = Fees();
      expect(fees.savingPercentOf(resolveProPlan('pro_monthly')), 0);
    });

    test('follows the monthly price when an admin moves it', () {
      const fees = Fees(packagePrices: {'proMonthly': 5000});
      // 12 × 5000 = 60,000 against a 30,000 year → half price.
      expect(fees.savingPercentOf(resolveProPlan('pro_yearly')), 50);
    });
  });
}
