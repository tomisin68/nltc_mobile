import 'package:flutter/material.dart';

import '../theme/app_palette.dart';

/// The row of search and filter controls above a list.
///
/// Port of `.filter-bar` in `globals.css`. On the web the controls sit on one
/// line; on a phone the search field takes its own row and the dropdowns wrap
/// beneath it, because three shrunken controls side by side are unusable.
class FilterBar extends StatelessWidget {
  const FilterBar({super.key, this.search, this.filters = const []});

  final Widget? search;
  final List<Widget> filters;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            ?search,
            if (search != null && filters.isNotEmpty)
              const SizedBox(height: Tokens.s2),
            if (filters.isNotEmpty)
              Wrap(
                spacing: Tokens.s2,
                runSpacing: Tokens.s2,
                children: filters,
              ),
          ],
        ),
      );
}

/// `.filter-input` — the search box, with its leading magnifier.
class FilterSearchField extends StatelessWidget {
  const FilterSearchField({
    super.key,
    required this.hintText,
    required this.onChanged,
    this.controller,
  });

  final String hintText;
  final ValueChanged<String> onChanged;
  final TextEditingController? controller;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return TextField(
      controller: controller,
      onChanged: onChanged,
      textInputAction: TextInputAction.search,
      style: const TextStyle(fontSize: 14),
      decoration: InputDecoration(
        hintText: hintText,
        isDense: true,
        prefixIcon: Icon(
          Icons.search_rounded,
          size: 18,
          color: scheme.onSurfaceVariant,
        ),
        prefixIconConstraints: const BoxConstraints(minWidth: 38),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: Tokens.s3,
          vertical: 12,
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(Tokens.rSm),
          borderSide: BorderSide(color: scheme.outlineVariant, width: 1.5),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(Tokens.rSm),
          borderSide: BorderSide(color: scheme.outlineVariant, width: 1.5),
        ),
      ),
    );
  }
}

/// `.filter-select` — a compact dropdown.
///
/// Values are `T?`, with null meaning "all", matching the web's `'all'` option.
class FilterDropdown<T> extends StatelessWidget {
  const FilterDropdown({
    super.key,
    required this.value,
    required this.allLabel,
    required this.options,
    required this.onChanged,
    required this.labelOf,
  });

  final T? value;

  /// Label for the null option — "All Subjects", "All Types", …
  final String allLabel;

  final List<T> options;
  final ValueChanged<T?> onChanged;
  final String Function(T) labelOf;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Container(
      height: 40,
      padding: const EdgeInsets.symmetric(horizontal: 10),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(Tokens.rSm),
        border: Border.all(color: scheme.outlineVariant, width: 1.5),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<T?>(
          value: value,
          isDense: true,
          borderRadius: BorderRadius.circular(Tokens.rMd),
          icon: Icon(
            Icons.expand_more_rounded,
            size: 18,
            color: scheme.onSurfaceVariant,
          ),
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w600,
            color: scheme.onSurface,
          ),
          items: [
            DropdownMenuItem<T?>(value: null, child: Text(allLabel)),
            for (final option in options)
              DropdownMenuItem<T?>(value: option, child: Text(labelOf(option))),
          ],
          onChanged: onChanged,
        ),
      ),
    );
  }
}

/// The pill filters on the Live Classes rail — `.lh-filter`, with its count.
class PillFilter extends StatelessWidget {
  const PillFilter({
    super.key,
    required this.label,
    required this.selected,
    required this.onTap,
    this.count,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;
  final int? count;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Material(
      color: selected ? scheme.primary : scheme.surfaceContainerLowest,
      borderRadius: BorderRadius.circular(100),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(100),
        child: Container(
          height: 36,
          padding: const EdgeInsets.symmetric(horizontal: 14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(100),
            border: Border.all(
              color: selected ? scheme.primary : scheme.outlineVariant,
              width: 1.5,
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                label,
                style: TextStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w700,
                  color: selected ? scheme.onPrimary : scheme.onSurfaceVariant,
                ),
              ),
              if (count != null && count! > 0) ...[
                const SizedBox(width: 6),
                Text(
                  '$count',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w800,
                    color: selected
                        ? scheme.onPrimary.withValues(alpha: 0.75)
                        : scheme.primary,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
