import 'package:cloud_firestore/cloud_firestore.dart';

import '../../domain/models/app_user.dart' show tsToMs;
import '../services/api_client.dart';
import '../services/firestore_cache.dart';

/// One fee band an admin has published — a class a student can pay for.
class ClassOffering {
  const ClassOffering({
    required this.id,
    required this.name,
    required this.price,
    this.type = 'general',
    this.description,
    this.timing,
    this.audience,
    this.level,
  });

  final String id;
  final String name;

  /// Naira per month.
  final int price;

  /// `general`, `weekend`, `intensive` — colours the badge.
  final String type;

  final String? description;

  /// Free text — "Mon, Wed, Fri · 4pm".
  final String? timing;

  /// `online`, `physical`, or null for both.
  final String? audience;

  /// `junior`, `senior`, or null for both.
  final String? level;

  /// Whether this fee is one the given student should be shown.
  ///
  /// Port of `filterClassesForStudent`: a class with no audience or level set
  /// applies to everyone, which is how the older records behave.
  bool appliesTo({required bool isPhysical, required bool isJunior}) {
    final wantedAudience = isPhysical ? 'physical' : 'online';
    final wantedLevel = isJunior ? 'junior' : 'senior';
    if (audience != null && audience != 'all' && audience != wantedAudience) {
      return false;
    }
    if (level != null && level != 'all' && level != wantedLevel) return false;
    return true;
  }

  static String? _str(dynamic v) {
    if (v is String && v.trim().isNotEmpty) return v.trim();
    return null;
  }

  factory ClassOffering.fromMap(String id, Map<String, dynamic> m) =>
      ClassOffering(
        id: id,
        name: _str(m['name']) ?? 'Monthly fee',
        price: m['price'] is num ? (m['price'] as num).toInt() : 0,
        type: _str(m['type']) ?? 'general',
        description: _str(m['description']),
        timing: _str(m['timing']),
        audience: _str(m['audience']),
        level: _str(m['level']),
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'price': price,
        'type': type,
        'description': description,
        'timing': timing,
        'audience': audience,
        'level': level,
      };
}

/// A row in the student's payment history.
class PaymentRecord {
  const PaymentRecord({
    required this.id,
    required this.amount,
    required this.status,
    this.description,
    this.periodLabel,
    this.reference,
    this.createdAt,
  });

  final String id;
  final int amount;

  /// `success`, `failed`, `pending`.
  final String status;

  final String? description;

  /// "1 Jul – 31 Jul", when the payment bought a period.
  final String? periodLabel;

  final String? reference;
  final DateTime? createdAt;

  bool get succeeded => status == 'success';

  static String? _str(dynamic v) {
    if (v is String && v.trim().isNotEmpty) return v.trim();
    return null;
  }

  factory PaymentRecord.fromMap(String id, Map<String, dynamic> m) {
    final ms = tsToMs(m['createdAt']) ?? tsToMs(m['date']);
    return PaymentRecord(
      id: id,
      amount: m['amount'] is num ? (m['amount'] as num).toInt() : 0,
      status: _str(m['status']) ?? 'pending',
      description: _str(m['description']) ?? _str(m['plan']),
      periodLabel: _str(m['periodLabel']),
      reference: _str(m['reference']),
      createdAt: ms == null ? null : DateTime.fromMillisecondsSinceEpoch(ms),
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'amount': amount,
        'status': status,
        'description': description,
        'periodLabel': periodLabel,
        'reference': reference,
        'createdAt': createdAt?.millisecondsSinceEpoch,
      };
}

/// The platform's current prices.
class Fees {
  const Fees({this.proMonthly = 2000, this.lessonFeeDefault = 5000});

  final int proMonthly;
  final int lessonFeeDefault;

  factory Fees.fromJson(Map<String, dynamic> json) => Fees(
        proMonthly: json['proMonthly'] is num
            ? (json['proMonthly'] as num).toInt()
            : 2000,
        lessonFeeDefault: json['lessonFeeDefault'] is num
            ? (json['lessonFeeDefault'] as num).toInt()
            : 5000,
      );
}

/// Fees, payments and starting a checkout.
///
/// The app never handles card details: it asks the backend to open a Flutterwave
/// session and hands the returned URL to the browser, which is the same flow the
/// website uses and keeps the app out of PCI scope entirely.
class BillingRepository {
  BillingRepository({
    required ApiClient api,
    required FirestoreCache cache,
    FirebaseFirestore? firestore,
  })  : _api = api,
        _cache = cache,
        _db = firestore ?? FirebaseFirestore.instance;

  final ApiClient _api;
  final FirestoreCache _cache;
  final FirebaseFirestore _db;

  /// Published prices. Unauthenticated on the backend, like the web's `useFees`.
  Future<Fees> fees() async {
    try {
      final data = await _api.getPublic('/settings/fees');
      return Fees.fromJson(data);
    } catch (_) {
      // The defaults are the real current prices, so a failed read shows the
      // right number rather than a blank.
      return const Fees();
    }
  }

  /// Every published fee band.
  Future<List<ClassOffering>> classes() => _cache.read<List<ClassOffering>>(
        'classes',
        CacheTtl.classes,
        () async {
          try {
            final snap = await _db.collection('classes').get();
            return snap.docs
                .map((d) => ClassOffering.fromMap(d.id, d.data()))
                .toList();
          } catch (_) {
            return const <ClassOffering>[];
          }
        },
        decode: (json) => (json as List)
            .map(
              (e) => ClassOffering.fromMap(
                (e as Map)['id'].toString(),
                Map<String, dynamic>.from(e),
              ),
            )
            .toList(),
      );

  /// The physical centres a student can be attached to.
  Future<List<({String id, String name, String? state, String? city})>>
      centres() async {
    try {
      final snap = await _db.collection('centers').get();
      return snap.docs.map((d) {
        final data = d.data();
        return (
          id: d.id,
          name: (data['name'] ?? 'Centre').toString(),
          state: data['state']?.toString(),
          city: data['city']?.toString(),
        );
      }).toList();
    } catch (_) {
      return const [];
    }
  }

  Future<List<PaymentRecord>> payments(String uid, {int limit = 50}) =>
      _cache.read<List<PaymentRecord>>(
        'userPayments_$uid',
        CacheTtl.userPayments,
        () async {
          try {
            final snap = await _db
                .collection('users')
                .doc(uid)
                .collection('payments')
                .orderBy('createdAt', descending: true)
                .limit(limit)
                .get();
            return snap.docs
                .map((d) => PaymentRecord.fromMap(d.id, d.data()))
                .toList();
          } catch (_) {
            return const <PaymentRecord>[];
          }
        },
        decode: (json) => (json as List)
            .map(
              (e) => PaymentRecord.fromMap(
                (e as Map)['id'].toString(),
                Map<String, dynamic>.from(e),
              ),
            )
            .toList(),
      );

  void invalidatePayments(String uid) => _cache.invalidate('userPayments_$uid');

  /// Opens a checkout and returns the URL to send the student to.
  ///
  /// [type] is `lesson_fee` or `plan_upgrade`, matching the backend.
  Future<String> startCheckout({
    required String type,
    int? amount,
    String? plan,
    Map<String, dynamic>? metadata,
  }) async {
    final data = await _api.post('/flutterwave/initialize', {
      'type': type,
      'amount': ?amount,
      'plan': ?plan,
      // The backend's own callback finishes the payment and updates the profile,
      // which the app then sees over the profile stream — no deep link needed.
      'callbackUrl': '${_api.baseUrl}/api/flutterwave/callback',
      'metadata': ?metadata,
    });

    final url = data['authorizationUrl'] ?? data['authorization_url'];
    if (url is! String || url.isEmpty) {
      throw const ApiException('Could not start the payment. Please try again.');
    }
    return url;
  }
}
