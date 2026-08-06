import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';

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
    this.active = true,
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

  /// `junior`, `senior`, `both`, or null on a doc written before the field
  /// existed.
  final String? level;

  /// Whether an admin still has this fee open for payment.
  ///
  /// A deactivated class is refused by the backend at checkout, so listing one
  /// only offers a student a button that cannot work.
  final bool active;

  static const _audiences = {'physical', 'online', 'both'};
  static const _levels = {'junior', 'senior', 'both'};

  /// Who this fee is for, inferred from [type] when an admin never set it.
  ///
  /// Docs written before `audience` existed carry only a `type`: `online` is an
  /// online fee and every other type (morning, afternoon, evening, weekend) is a
  /// centre one. Treating a missing field as "everybody" instead is what put the
  /// centre's evening fees in front of online students.
  String get resolvedAudience => _audiences.contains(audience)
      ? audience!
      : type == 'online'
          ? 'online'
          : 'physical';

  /// The level this fee targets — legacy docs are shown to both rather than
  /// hidden from everyone.
  String get resolvedLevel => _levels.contains(level) ? level! : 'both';

  /// Whether this fee is one the given student should be shown.
  ///
  /// Port of `classMatchesStudent`: `both` is the wildcard the admin console
  /// writes, for each of the two fields independently.
  bool appliesTo({required bool isPhysical, required bool isJunior}) {
    final a = resolvedAudience;
    final l = resolvedLevel;
    return (a == 'both' || a == (isPhysical ? 'physical' : 'online')) &&
        (l == 'both' || l == (isJunior ? 'junior' : 'senior'));
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
        // Only an explicit `false` closes a class: docs written before the
        // toggle existed have no field at all and are still open.
        active: m['active'] != false,
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
        'active': active,
      };
}

/// The fees a student is allowed to pay, cheapest first.
///
/// Port of `filterClassesForStudent`: deactivated fees are dropped before
/// targeting is considered, so a class an admin has closed is never offered.
List<ClassOffering> filterClassesForStudent(
  Iterable<ClassOffering> classes, {
  required bool isPhysical,
  required bool isJunior,
}) =>
    classes
        .where(
          (c) =>
              c.active && c.appliesTo(isPhysical: isPhysical, isJunior: isJunior),
        )
        .toList()
      ..sort((a, b) => a.price.compareTo(b.price));

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

/// The account students transfer their fees to.
///
/// Mirrors `nltc-backend/src/config/bankAccount.js`. The backend is the source
/// of truth — an admin can change the account from `settings/bankAccount`
/// without a release — but a payment screen with a blank account number is
/// worse than a slightly stale one, so these constants are what shows when the
/// fetch fails.
class BankAccount {
  const BankAccount({
    this.accountNumber = '8270157607',
    this.bankName = 'Moniepoint',
    this.accountName = 'NLTC Global Service- Next level tutorial',
    this.note = 'Transfer the exact amount, then upload your receipt below. '
        'Confirmation usually takes under 2 hours.',
  });

  final String accountNumber;
  final String bankName;
  final String accountName;
  final String note;

  static String? _str(dynamic v) {
    if (v is String && v.trim().isNotEmpty) return v.trim();
    return null;
  }

  /// Merges a response field by field, so a partial payload cannot blank the
  /// account number.
  factory BankAccount.fromJson(Map<String, dynamic> json) {
    const fallback = BankAccount();
    return BankAccount(
      accountNumber: _str(json['accountNumber']) ?? fallback.accountNumber,
      bankName: _str(json['bankName']) ?? fallback.bankName,
      accountName: _str(json['accountName']) ?? fallback.accountName,
      note: _str(json['note']) ?? fallback.note,
    );
  }
}

/// How long a student should expect to wait for an admin to confirm.
const kConfirmationWindow = 'under 2 hours';

/// A receipt the student has sent in, and where it got to.
class PaymentProof {
  const PaymentProof({
    required this.id,
    required this.status,
    required this.amount,
    this.description,
    this.reference,
    this.receiptUrl,
    this.reviewNote,
    this.createdAt,
  });

  final String id;

  /// `pending`, `approved`, `rejected`.
  final String status;

  final int amount;
  final String? description;
  final String? reference;
  final String? receiptUrl;

  /// Why an admin rejected it — shown to the student verbatim.
  final String? reviewNote;

  final DateTime? createdAt;

  bool get isPending => status == 'pending';

  static String? _str(dynamic v) {
    if (v is String && v.trim().isNotEmpty) return v.trim();
    return null;
  }

  factory PaymentProof.fromJson(Map<String, dynamic> m) {
    final ms = m['createdAt'];
    return PaymentProof(
      id: (m['id'] ?? '').toString(),
      status: _str(m['status']) ?? 'pending',
      amount: m['amount'] is num ? (m['amount'] as num).toInt() : 0,
      description: _str(m['description']),
      reference: _str(m['reference']),
      receiptUrl: _str(m['receiptUrl']),
      reviewNote: _str(m['reviewNote']),
      createdAt: ms is num
          ? DateTime.fromMillisecondsSinceEpoch(ms.toInt())
          : null,
    );
  }
}

/// What a student will be asked to transfer, priced by the backend.
class PaymentQuote {
  const PaymentQuote({required this.amount, required this.description});

  final int amount;
  final String description;

  factory PaymentQuote.fromJson(Map<String, dynamic> m) => PaymentQuote(
        amount: m['amount'] is num ? (m['amount'] as num).toInt() : 0,
        description: (m['description'] ?? 'Monthly fee').toString(),
      );
}

/// Fees, payments, and submitting proof of a bank transfer.
///
/// There is no payment gateway. A student transfers to the NLTC account,
/// uploads the receipt here, and an admin confirms it — the approval is what
/// opens the account. The app never sees card details because no card is ever
/// involved.
class BillingRepository {
  BillingRepository({
    required ApiClient api,
    required FirestoreCache cache,
    FirebaseFirestore? firestore,
    FirebaseStorage? storage,
  })  : _api = api,
        _cache = cache,
        _db = firestore ?? FirebaseFirestore.instance,
        _storage = storage ?? FirebaseStorage.instance;

  final ApiClient _api;
  final FirestoreCache _cache;
  final FirebaseFirestore _db;
  final FirebaseStorage _storage;

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

  /// The account to transfer to, falling back to the bundled constants.
  ///
  /// Never throws: the caller is rendering payment instructions and the
  /// fallback is correct.
  Future<BankAccount> bankAccount() async {
    try {
      final data = await _api.getPublic('/payments/bank-account');
      final acct = data['bankAccount'];
      if (acct is Map) {
        return BankAccount.fromJson(Map<String, dynamic>.from(acct));
      }
    } catch (_) {
      // Backend cold-starting or offline — the hard-coded account still holds.
    }
    return const BankAccount();
  }

  /// What the student will be asked to transfer.
  ///
  /// Priced by the same backend code that prices the submission, so the figure
  /// on the transfer screen cannot drift from the one an admin reviews.
  ///
  /// [type] is `lesson_fee` or `plan_upgrade`, matching the backend.
  Future<PaymentQuote> quote({
    required String type,
    String? plan,
    String? classId,
  }) async {
    final data = await _api.get('/payments/quote', query: {
      'type': type,
      'source': 'app',
      'plan': ?plan,
      'classId': ?classId,
    });
    return PaymentQuote.fromJson(data);
  }

  /// The receipts this student has sent in, newest first.
  Future<List<PaymentProof>> myProofs() async {
    try {
      final data = await _api.get('/payments/proofs/mine');
      final list = data['proofs'];
      if (list is! List) return const [];
      return list
          .map((e) => PaymentProof.fromJson(Map<String, dynamic>.from(e as Map)))
          .toList();
    } catch (_) {
      return const [];
    }
  }

  /// The one receipt still with an admin, if any.
  Future<PaymentProof?> pendingProof() async {
    final proofs = await myProofs();
    for (final p in proofs) {
      if (p.isPending) return p;
    }
    return null;
  }

  /// Uploads a receipt and submits it for review.
  ///
  /// This grants nothing. The backend prices the submission from the class
  /// document — no amount travels with it — and an admin approving the proof is
  /// what opens the account.
  ///
  /// [onProgress] reports 0.0–1.0 while the file uploads.
  Future<PaymentProof> submitProof({
    required String uid,
    required File receipt,
    required String contentType,
    required String type,
    String? plan,
    String? classId,
    String? note,
    void Function(double)? onProgress,
  }) async {
    // Storage rules confine this path to the signed-in student, and the backend
    // re-checks that the submitted path sits under their own folder.
    final safeName = receipt.uri.pathSegments.last
        .replaceAll(RegExp(r'[^\w.\-]'), '_');
    final trimmed = safeName.length > 80
        ? safeName.substring(safeName.length - 80)
        : safeName;
    final path =
        'paymentProofs/$uid/${DateTime.now().millisecondsSinceEpoch}-$trimmed';

    final ref = _storage.ref(path);
    final task = ref.putFile(receipt, SettableMetadata(contentType: contentType));

    if (onProgress != null) {
      task.snapshotEvents.listen((s) {
        if (s.totalBytes > 0) {
          onProgress(s.bytesTransferred / s.totalBytes);
        }
      });
    }

    await task;
    final url = await ref.getDownloadURL();

    final data = await _api.post('/payments/proof', {
      'type': type,
      'plan': ?plan,
      'receiptUrl': url,
      'receiptPath': path,
      'receiptName': receipt.uri.pathSegments.last,
      'receiptType': contentType,
      'note': ?note,
      'source': 'app',
      if (classId != null) 'metadata': {'classId': classId},
    });

    final proof = data['proof'];
    if (proof is! Map) {
      throw const ApiException('Could not submit your receipt. Please try again.');
    }
    return PaymentProof.fromJson(Map<String, dynamic>.from(proof));
  }
}
