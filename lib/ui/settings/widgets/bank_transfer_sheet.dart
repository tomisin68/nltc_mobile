import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../../data/repositories/billing_repository.dart';
import '../../../data/services/api_client.dart' show ApiException;
import '../../../domain/plans.dart';
import '../../core/state/session_controller.dart';
import '../../core/theme/app_palette.dart';
import '../../core/toast.dart';

/// Receipt formats the reviewer can actually open, and the ceiling in
/// `storage.rules`. Kept together so the picker and the pre-upload check cannot
/// disagree about what is allowed.
const _receiptExtensions = ['jpg', 'jpeg', 'png', 'webp', 'heic', 'pdf'];
const _receiptMaxBytes = 10 * 1024 * 1024;

/// Opens the bank transfer flow. Resolves true when a receipt was submitted.
///
/// [classItem] prices a lesson fee; pass null with [plan] for a plan upgrade.
Future<bool> showBankTransferSheet(
  BuildContext context, {
  required String type,
  String? plan,
  ClassOffering? classItem,
}) async {
  final submitted = await showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (_) => BankTransferSheet(
      type: type,
      plan: plan,
      classItem: classItem,
    ),
  );
  return submitted ?? false;
}

/// Bank transfer, then proof of it.
///
/// The whole payment flow: the student transfers to the NLTC account, uploads
/// the receipt, and an admin confirms it. Nothing here grants access — the
/// backend prices the submission and the approval is what opens the account.
class BankTransferSheet extends StatefulWidget {
  const BankTransferSheet({
    super.key,
    required this.type,
    this.plan,
    this.classItem,
  });

  final String type;
  final String? plan;
  final ClassOffering? classItem;

  @override
  State<BankTransferSheet> createState() => _BankTransferSheetState();
}

class _BankTransferSheetState extends State<BankTransferSheet> {
  final _note = TextEditingController();

  BankAccount _bank = const BankAccount();
  PaymentQuote? _quote;
  String? _quoteError;

  File? _receipt;
  String? _receiptName;
  String? _receiptType;

  double _progress = 0;
  bool _busy = false;
  bool _done = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _note.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final billing = context.read<BillingRepository>();

    final account = await billing.bankAccount();
    if (mounted) setState(() => _bank = account);

    try {
      final quote = await billing.quote(
        type: widget.type,
        plan: widget.plan,
        classId: widget.classItem?.id,
      );
      if (mounted) setState(() => _quote = quote);
    } on ApiException catch (e) {
      if (!mounted) return;
      // Falling back to the price already on screen keeps the account details
      // usable while the backend cold-starts.
      final fallback = widget.classItem;
      setState(() {
        if (fallback != null) {
          _quote = PaymentQuote(
            amount: fallback.price,
            description: fallback.name,
          );
        } else {
          _quoteError = e.message;
        }
      });
    }
  }

  Future<void> _copy(String label, String value) async {
    await Clipboard.setData(ClipboardData(text: value));
    if (!mounted) return;
    showToast('$label copied', variant: ToastVariant.success);
  }

  Future<void> _pickReceipt() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: _receiptExtensions,
      withData: false,
    );
    final picked = result?.files.singleOrNull;
    final path = picked?.path;
    if (picked == null || path == null) return;

    if (picked.size > _receiptMaxBytes) {
      showToast('That file is too large — keep it under 10 MB.',
          variant: ToastVariant.error);
      return;
    }

    final ext = (picked.extension ?? '').toLowerCase();
    final contentType = ext == 'pdf'
        ? 'application/pdf'
        : ext == 'png'
            ? 'image/png'
            : ext == 'webp'
                ? 'image/webp'
                : ext == 'heic'
                    ? 'image/heic'
                    : 'image/jpeg';

    setState(() {
      _receipt = File(path);
      _receiptName = picked.name;
      _receiptType = contentType;
    });
  }

  Future<void> _submit() async {
    final receipt = _receipt;
    final contentType = _receiptType;
    if (receipt == null || contentType == null) {
      showToast('Choose your receipt first.', variant: ToastVariant.error);
      return;
    }

    final uid = context.read<SessionController>().account?.uid;
    if (uid == null) return;

    setState(() {
      _busy = true;
      _progress = 0;
    });

    try {
      await context.read<BillingRepository>().submitProof(
            uid: uid,
            receipt: receipt,
            contentType: contentType,
            type: widget.type,
            plan: widget.plan,
            classId: widget.classItem?.id,
            note: _note.text.trim().isEmpty ? null : _note.text.trim(),
            onProgress: (p) {
              if (mounted) setState(() => _progress = p);
            },
          );
      if (!mounted) return;
      setState(() => _done = true);
    } on ApiException catch (e) {
      if (!mounted) return;
      // The backend refuses for reasons the student can act on — a receipt
      // already under review, a class that closed. Replacing those with a
      // generic message turns the button into one that silently does nothing.
      showToast(e.message, variant: ToastVariant.error);
      setState(() => _busy = false);
    } catch (_) {
      if (!mounted) return;
      showToast('Could not submit your receipt. Please try again.',
          variant: ToastVariant.error);
      setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final inset = MediaQuery.of(context).viewInsets.bottom;

    return Padding(
      padding: EdgeInsets.only(bottom: inset),
      child: DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.9,
        maxChildSize: 0.95,
        minChildSize: 0.5,
        builder: (context, controller) => Column(
          children: [
            Container(
              margin: const EdgeInsets.symmetric(vertical: Tokens.s3),
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: scheme.outlineVariant,
                borderRadius: BorderRadius.circular(99),
              ),
            ),
            Expanded(
              child: SingleChildScrollView(
                controller: controller,
                padding: const EdgeInsets.fromLTRB(
                    Tokens.s4, 0, Tokens.s4, Tokens.s6),
                child: _done ? _buildDone(scheme) : _buildForm(scheme),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDone(ColorScheme scheme) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SizedBox(height: Tokens.s6),
          Icon(Icons.receipt_long_rounded,
              size: 56, color: BlueprintPalette.b500),
          const SizedBox(height: Tokens.s4),
          Text(
            "We've got your receipt",
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.w800,
                ),
          ),
          const SizedBox(height: Tokens.s3),
          Text(
            'An admin is reviewing it now. Your account opens as soon as it is '
            'confirmed — this usually takes $kConfirmationWindow. '
            "We'll notify you the moment it's done.",
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 13.5,
              height: 1.6,
              color: scheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: Tokens.s6),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Done'),
          ),
          const SizedBox(height: Tokens.s4),
        ],
      );

  Widget _buildForm(ColorScheme scheme) {
    final money = NumberFormat.decimalPattern();
    final amount = _quote?.amount ?? widget.classItem?.price;
    final label = _quote?.description ??
        widget.classItem?.name ??
        (widget.plan == null ? 'Monthly fee' : 'Pro plan');
    final studentName =
        context.watch<SessionController>().profile?.displayName.trim() ?? '';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'Pay by Bank Transfer',
          style: Theme.of(context)
              .textTheme
              .titleLarge
              ?.copyWith(fontWeight: FontWeight.w800),
        ),
        const SizedBox(height: Tokens.s4),

        // ─── What to send ───────────────────────────────────────────────
        Container(
          padding: const EdgeInsets.all(Tokens.s4),
          decoration: BoxDecoration(
            color: BlueprintPalette.warningBg,
            borderRadius: BorderRadius.circular(Tokens.rSm),
            border: Border.all(color: BlueprintPalette.warning),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'AMOUNT TO TRANSFER',
                style: TextStyle(
                  fontSize: 10.5,
                  letterSpacing: 0.6,
                  fontWeight: FontWeight.w700,
                  color: Color(0xFF92400E),
                ),
              ),
              const SizedBox(height: Tokens.s1),
              if (amount == null)
                const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              else
                Text(
                  '₦${money.format(amount)}',
                  style: const TextStyle(
                    fontSize: 28,
                    fontWeight: FontWeight.w900,
                    color: Color(0xFF7C2D12),
                  ),
                ),
              const SizedBox(height: Tokens.s1),
              Text(
                // A centre lesson fee is always a month; a Pro package is
                // whatever length was picked. Telling a student who has just
                // been quoted ₦30,000 that it buys "30 days access" is the
                // fastest route to a support message.
                '$label · '
                '${widget.plan == null ? 30 : resolveProPlan(widget.plan).days}'
                ' days access',
                style: const TextStyle(fontSize: 12.5, color: Color(0xFF92400E)),
              ),
              if (_quoteError != null) ...[
                const SizedBox(height: Tokens.s2),
                Text(
                  _quoteError!,
                  style: const TextStyle(
                      fontSize: 12, color: BlueprintPalette.error),
                ),
              ],
            ],
          ),
        ),
        const SizedBox(height: Tokens.s5),

        // ─── Where to send it ───────────────────────────────────────────
        _StepLabel(number: '1', text: 'Transfer to this account'),
        const SizedBox(height: Tokens.s2),
        Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(Tokens.rSm),
            border: Border.all(color: scheme.outlineVariant),
          ),
          padding: const EdgeInsets.symmetric(horizontal: Tokens.s4),
          child: Column(
            children: [
              _DetailRow(
                label: 'Account number',
                value: _bank.accountNumber,
                emphasis: true,
                onCopy: () => _copy('Account number', _bank.accountNumber),
              ),
              _DetailRow(
                label: 'Bank',
                value: _bank.bankName,
                onCopy: () => _copy('Bank name', _bank.bankName),
              ),
              _DetailRow(
                label: 'Account name',
                value: _bank.accountName,
                last: true,
                onCopy: () => _copy('Account name', _bank.accountName),
              ),
            ],
          ),
        ),
        if (studentName.isNotEmpty) ...[
          const SizedBox(height: Tokens.s3),
          Container(
            padding: const EdgeInsets.all(Tokens.s3),
            decoration: BoxDecoration(
              color: scheme.surfaceContainerHigh,
              borderRadius: BorderRadius.circular(Tokens.rSm),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(Icons.lightbulb_outline_rounded,
                    size: 16, color: BlueprintPalette.warning),
                const SizedBox(width: Tokens.s2),
                Expanded(
                  child: Text.rich(
                    TextSpan(
                      children: [
                        const TextSpan(text: 'Use '),
                        TextSpan(
                          text: studentName,
                          style: const TextStyle(fontWeight: FontWeight.w800),
                        ),
                        const TextSpan(
                          text: ' as the transfer narration so we can match '
                              'your payment quickly.',
                        ),
                      ],
                    ),
                    style: TextStyle(
                      fontSize: 12.5,
                      height: 1.5,
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
        const SizedBox(height: Tokens.s5),

        // ─── Prove it ───────────────────────────────────────────────────
        _StepLabel(number: '2', text: 'Upload your receipt'),
        const SizedBox(height: Tokens.s2),
        InkWell(
          onTap: _busy ? null : _pickReceipt,
          borderRadius: BorderRadius.circular(Tokens.rSm),
          child: Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(
                vertical: Tokens.s5, horizontal: Tokens.s4),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(Tokens.rSm),
              border: Border.all(
                color: _receipt == null
                    ? scheme.outlineVariant
                    : BlueprintPalette.b500,
                width: 1.5,
              ),
              color: _receipt == null ? null : BlueprintPalette.b500.withValues(alpha: 0.06),
            ),
            child: Column(
              children: [
                Icon(
                  _receipt == null
                      ? Icons.cloud_upload_outlined
                      : Icons.task_alt_rounded,
                  color: BlueprintPalette.b500,
                ),
                const SizedBox(height: Tokens.s2),
                Text(
                  _receiptName ?? 'Choose a photo or PDF of your receipt',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: scheme.onSurface,
                  ),
                ),
                const SizedBox(height: Tokens.s1),
                Text(
                  'Screenshot, photo or PDF · up to 10 MB',
                  style: TextStyle(
                      fontSize: 11, color: scheme.onSurfaceVariant),
                ),
              ],
            ),
          ),
        ),
        if (_busy && _progress > 0) ...[
          const SizedBox(height: Tokens.s3),
          ClipRRect(
            borderRadius: BorderRadius.circular(99),
            child: LinearProgressIndicator(value: _progress, minHeight: 6),
          ),
        ],
        const SizedBox(height: Tokens.s4),

        TextField(
          controller: _note,
          enabled: !_busy,
          maxLength: 500,
          decoration: const InputDecoration(
            labelText: 'Note for the admin (optional)',
            hintText: "e.g. paid from my mum's account",
            counterText: '',
          ),
        ),
        const SizedBox(height: Tokens.s3),

        Container(
          padding: const EdgeInsets.all(Tokens.s3),
          decoration: BoxDecoration(
            color: BlueprintPalette.warningBg,
            borderRadius: BorderRadius.circular(Tokens.rSm),
            border: Border.all(color: BlueprintPalette.warning),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Icon(Icons.schedule_rounded,
                  size: 16, color: Color(0xFF92400E)),
              const SizedBox(width: Tokens.s2),
              const Expanded(
                child: Text(
                  'Your account opens as soon as an admin confirms the '
                  'transfer — usually $kConfirmationWindow.',
                  style: TextStyle(
                    fontSize: 12.5,
                    height: 1.5,
                    color: Color(0xFF92400E),
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: Tokens.s4),

        Row(
          children: [
            Expanded(
              child: OutlinedButton(
                onPressed: _busy ? null : () => Navigator.of(context).pop(false),
                child: const Text('Cancel'),
              ),
            ),
            const SizedBox(width: Tokens.s3),
            Expanded(
              flex: 2,
              child: FilledButton.icon(
                onPressed: _busy || _receipt == null ? null : _submit,
                icon: _busy
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.send_rounded, size: 18),
                label: const Text('Submit Receipt'),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _StepLabel extends StatelessWidget {
  const _StepLabel({required this.number, required this.text});

  final String number;
  final String text;

  @override
  Widget build(BuildContext context) => Row(
        children: [
          Text(
            '$number.',
            style: const TextStyle(
              fontWeight: FontWeight.w900,
              color: BlueprintPalette.b500,
              fontSize: 14,
            ),
          ),
          const SizedBox(width: Tokens.s2),
          Text(
            text,
            style: TextStyle(
              fontWeight: FontWeight.w800,
              fontSize: 14,
              color: Theme.of(context).colorScheme.onSurface,
            ),
          ),
        ],
      );
}

/// One "Account number · 8270157607 · [copy]" row.
class _DetailRow extends StatelessWidget {
  const _DetailRow({
    required this.label,
    required this.value,
    required this.onCopy,
    this.emphasis = false,
    this.last = false,
  });

  final String label;
  final String value;
  final VoidCallback onCopy;
  final bool emphasis;
  final bool last;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(vertical: Tokens.s3),
      decoration: last
          ? null
          : BoxDecoration(
              border: Border(
                bottom: BorderSide(color: scheme.outlineVariant, width: 0.6),
              ),
            ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label.toUpperCase(),
                  style: TextStyle(
                    fontSize: 10,
                    letterSpacing: 0.5,
                    fontWeight: FontWeight.w700,
                    color: scheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 2),
                SelectableText(
                  value,
                  style: TextStyle(
                    fontSize: emphasis ? 19 : 14,
                    fontWeight: FontWeight.w800,
                    letterSpacing: emphasis ? 1.2 : 0,
                    color: scheme.onSurface,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: Tokens.s2),
          IconButton(
            onPressed: onCopy,
            visualDensity: VisualDensity.compact,
            icon: const Icon(Icons.copy_rounded, size: 18),
            tooltip: 'Copy $label',
          ),
        ],
      ),
    );
  }
}
