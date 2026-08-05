import 'package:flutter/material.dart';

/// The path of the logo render that reads against the current theme.
///
/// The mark is flat ink with no outline, so it ships as two files rather than
/// one tinted image: the navy artwork would sink into a dark surface, and the
/// white one would disappear on paper.
String brandAssetFor(BuildContext context) =>
    Theme.of(context).brightness == Brightness.dark
        ? 'assets/nltc-light.png'
        : 'assets/nltc-dark.png';

/// The NLTC Online logo lockup — the open-book mark above the wordmark.
class BrandMark extends StatelessWidget {
  const BrandMark({super.key, this.height = 84});

  /// Sized by height: the lockup is taller than it is wide, so its width
  /// follows from the artwork.
  final double height;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: 'NLTC Online',
      image: true,
      child: Image.asset(
        brandAssetFor(context),
        height: height,
        fit: BoxFit.contain,
        excludeFromSemantics: true,
      ),
    );
  }
}
