import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../core/theme/app_palette.dart';

/// The 36 states and the FCT, in the order the website lists them.
const nigerianStates = <String>[
  'Abia',
  'Adamawa',
  'Akwa Ibom',
  'Anambra',
  'Bauchi',
  'Bayelsa',
  'Benue',
  'Borno',
  'Cross River',
  'Delta',
  'Ebonyi',
  'Edo',
  'Ekiti',
  'Enugu',
  'FCT',
  'Gombe',
  'Imo',
  'Jigawa',
  'Kaduna',
  'Kano',
  'Katsina',
  'Kebbi',
  'Kogi',
  'Kwara',
  'Lagos',
  'Nasarawa',
  'Niger',
  'Ogun',
  'Ondo',
  'Osun',
  'Oyo',
  'Plateau',
  'Rivers',
  'Sokoto',
  'Taraba',
  'Yobe',
  'Zamfara',
];

/// A labelled text field — the web's `.form-group` with a `.form-input` in it.
class ProfileField extends StatelessWidget {
  const ProfileField({
    super.key,
    required this.label,
    this.controller,
    this.initialValue,
    this.hint,
    this.helper,
    this.keyboardType,
    this.textCapitalization = TextCapitalization.none,
    this.maxLines = 1,
    this.enabled = true,
    this.validator,
  });

  final String label;
  final TextEditingController? controller;
  final String? initialValue;
  final String? hint;
  final String? helper;
  final TextInputType? keyboardType;
  final TextCapitalization textCapitalization;
  final int maxLines;
  final bool enabled;
  final String? Function(String?)? validator;

  @override
  Widget build(BuildContext context) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _FieldLabel(label),
          const SizedBox(height: 5),
          TextFormField(
            controller: controller,
            initialValue: controller == null ? initialValue : null,
            enabled: enabled,
            keyboardType: keyboardType,
            textCapitalization: textCapitalization,
            maxLines: maxLines,
            validator: validator,
            style: const TextStyle(fontSize: 14),
            decoration: InputDecoration(
              hintText: hint,
              helperText: helper,
              helperMaxLines: 3,
              isDense: true,
            ),
          ),
        ],
      );
}

/// A labelled dropdown — the web's `.form-select`.
class ProfileDropdown<T> extends StatelessWidget {
  const ProfileDropdown({
    super.key,
    required this.label,
    required this.value,
    required this.items,
    required this.onChanged,
    this.hint,
  });

  final String label;
  final T? value;
  final List<DropdownMenuItem<T>> items;
  final ValueChanged<T?> onChanged;

  /// Shown when nothing is selected — the web's `-- Select --` option.
  final String? hint;

  @override
  Widget build(BuildContext context) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _FieldLabel(label),
          const SizedBox(height: 5),
          DropdownButtonFormField<T>(
            initialValue: value,
            items: items,
            onChanged: onChanged,
            isExpanded: true,
            style: TextStyle(
              fontSize: 14,
              color: Theme.of(context).colorScheme.onSurface,
            ),
            hint: hint == null ? null : Text(hint!),
            decoration: const InputDecoration(isDense: true),
          ),
        ],
      );
}

/// A date field that opens the platform picker.
///
/// The value is carried as the `yyyy-MM-dd` string the website stores, so the two
/// write the same shape; only the display is localised.
class ProfileDateField extends StatelessWidget {
  const ProfileDateField({
    super.key,
    required this.label,
    required this.value,
    required this.firstDate,
    required this.lastDate,
    required this.onChanged,
    this.helper,
    this.clearable = false,
  });

  final String label;
  final String? value;
  final DateTime firstDate;
  final DateTime lastDate;
  final ValueChanged<String?> onChanged;
  final String? helper;

  /// Whether the field offers a way back to empty. Not every date is optional.
  final bool clearable;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final parsed = value == null ? null : DateTime.tryParse(value!);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _FieldLabel(label),
        const SizedBox(height: 5),
        InkWell(
          onTap: () async {
            final picked = await showDatePicker(
              context: context,
              initialDate: parsed ?? _clamp(DateTime.now()),
              firstDate: firstDate,
              lastDate: lastDate,
              helpText: label,
            );
            if (picked != null) {
              onChanged(
                '${picked.year}-${picked.month.toString().padLeft(2, '0')}-'
                '${picked.day.toString().padLeft(2, '0')}',
              );
            }
          },
          borderRadius: BorderRadius.circular(Tokens.rSm),
          child: InputDecorator(
            decoration: InputDecoration(
              isDense: true,
              helperText: helper,
              helperMaxLines: 3,
              suffixIcon: clearable && parsed != null
                  ? IconButton(
                      onPressed: () => onChanged(null),
                      icon: const Icon(Icons.close_rounded, size: 17),
                      tooltip: 'Clear',
                    )
                  : Icon(
                      Icons.calendar_today_rounded,
                      size: 16,
                      color: scheme.onSurfaceVariant,
                    ),
            ),
            child: Text(
              parsed == null
                  ? 'Not set'
                  : DateFormat('d MMMM yyyy').format(parsed),
              style: TextStyle(
                fontSize: 14,
                color: parsed == null
                    ? scheme.onSurfaceVariant
                    : scheme.onSurface,
              ),
            ),
          ),
        ),
      ],
    );
  }

  /// Keeps the picker's opening date inside its own bounds — showDatePicker
  /// throws rather than clamping when it isn't.
  DateTime _clamp(DateTime date) {
    if (date.isBefore(firstDate)) return firstDate;
    if (date.isAfter(lastDate)) return lastDate;
    return date;
  }
}

class _FieldLabel extends StatelessWidget {
  const _FieldLabel(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Text(
        text,
        style: TextStyle(
          fontSize: 11.5,
          fontWeight: FontWeight.w700,
          color: Theme.of(context).colorScheme.onSurfaceVariant,
        ),
      );
}
