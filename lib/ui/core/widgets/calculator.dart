import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../theme/app_palette.dart';

/// The in-exam calculator.
///
/// Port of `src/components/ui/Calculator.jsx`, including its exact arithmetic:
/// results are rounded to ten decimal places so repeated operations don't drift
/// into floating-point noise, and dividing by zero shows "Error" rather than
/// infinity.
class Calculator extends StatefulWidget {
  const Calculator({super.key, this.onClose});

  /// How to dismiss. Null means the calculator is on a route of its own and
  /// closing pops it — which is what [show] sets up.
  final VoidCallback? onClose;

  /// Opens the calculator as a sheet. Exams that offer it use this.
  static Future<void> show(BuildContext context) => showModalBottomSheet<void>(
        context: context,
        builder: (_) => const Calculator(),
      );

  @override
  State<Calculator> createState() => _CalculatorState();
}

class _CalculatorState extends State<Calculator> {
  String _display = '0';
  double? _previous;
  String? _operator;

  /// True once an operator has been pressed, so the next digit starts a fresh
  /// number instead of appending to the answer on screen.
  bool _waitingForNext = false;

  static double _round(double n) => (n * 1e10).roundToDouble() / 1e10;

  /// Formats a result the way JavaScript's `String(number)` does — no trailing
  /// `.0` on whole numbers, which is what the web shows.
  static String _format(double n) {
    if (n == n.roundToDouble() && n.abs() < 1e15) {
      return n.toStringAsFixed(0);
    }
    return n.toString();
  }

  void _input(int digit) => setState(() {
        if (_waitingForNext) {
          _display = '$digit';
          _waitingForNext = false;
        } else {
          _display = _display == '0' ? '$digit' : '$_display$digit';
        }
      });

  void _decimal() => setState(() {
        if (_waitingForNext) {
          _display = '0.';
          _waitingForNext = false;
        } else if (!_display.contains('.')) {
          _display = '$_display.';
        }
      });

  double? _current() => double.tryParse(_display);

  String _calc(double a, double b, String? operator) => switch (operator) {
        '+' => _format(_round(a + b)),
        '−' => _format(_round(a - b)),
        '×' => _format(_round(a * b)),
        // Guarded rather than allowed to produce infinity — "Error" is what a
        // real exam calculator shows, and it can't be operated on further.
        '÷' => b == 0 ? 'Error' : _format(_round(a / b)),
        '%' => b == 0 ? 'Error' : _format(_round(a % b)),
        _ => _format(b),
      };

  void _operate(String nextOperator) {
    final current = _current();
    if (current == null) return;

    setState(() {
      // Chained operators evaluate as they go — `2 + 3 + ` shows 5 before the
      // second operand is typed.
      if (_previous != null && !_waitingForNext) {
        final result = _calc(_previous!, current, _operator);
        _display = result;
        _previous = double.tryParse(result);
      } else {
        _previous = current;
      }
      _operator = nextOperator;
      _waitingForNext = true;
    });
  }

  void _equals() {
    final current = _current();
    if (_operator == null || _previous == null || current == null) return;
    setState(() {
      _display = _calc(_previous!, current, _operator);
      _previous = null;
      _operator = null;
      _waitingForNext = true;
    });
  }

  void _clear() => setState(() {
        _display = '0';
        _previous = null;
        _operator = null;
        _waitingForNext = false;
      });

  void _toggleSign() => setState(() {
        _display = _display.startsWith('-')
            ? _display.substring(1)
            : '-$_display';
      });

  void _percent() => setState(() {
        final current = _current();
        if (current != null) _display = _format(current / 100);
      });

  void _backspace() => setState(() {
        _display = _display.length > 1
            ? _display.substring(0, _display.length - 1)
            : '0';
      });

  void _square() => setState(() {
        final current = _current();
        if (current == null) return;
        _display = _format(_round(current * current));
        _waitingForNext = true;
      });

  void _squareRoot() => setState(() {
        final current = _current();
        if (current == null) return;
        _display = current < 0 ? 'Error' : _format(_round(math.sqrt(current)));
        _waitingForNext = true;
      });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    // Long results switch to exponential rather than overflowing the display.
    final value = _current();
    final displayText = _display.length > 12 && value != null
        ? value.toStringAsExponential(4)
        : _display;

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(
          Tokens.s4,
          Tokens.s2,
          Tokens.s4,
          Tokens.s4,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Text(
                  'Calculator',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w800,
                    color: scheme.onSurface,
                  ),
                ),
                const Spacer(),
                IconButton(
                  onPressed:
                      widget.onClose ?? () => Navigator.of(context).pop(),
                  icon: const Icon(Icons.close_rounded, size: 20),
                  tooltip: 'Close calculator',
                ),
              ],
            ),
            // Display
            Container(
              padding: const EdgeInsets.symmetric(
                horizontal: Tokens.s4,
                vertical: Tokens.s3,
              ),
              decoration: BoxDecoration(
                color: scheme.surfaceContainerHigh,
                borderRadius: BorderRadius.circular(Tokens.rMd),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  // The pending expression, so a chained sum is followable.
                  SizedBox(
                    height: 16,
                    child: _operator != null && _previous != null
                        ? Text(
                            '${_format(_previous!)} $_operator',
                            style: TextStyle(
                              fontSize: 12.5,
                              color: scheme.onSurfaceVariant,
                            ),
                          )
                        : null,
                  ),
                  Text(
                    displayText,
                    maxLines: 1,
                    style: GoogleFonts.dmSans(
                      fontSize: 32,
                      fontWeight: FontWeight.w700,
                      height: 1.2,
                      color: scheme.onSurface,
                      fontFeatures: const [FontFeature.tabularFigures()],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: Tokens.s3),
            // Keypad — same order and grouping as the web's BTNS array.
            _KeyRow(children: [
              _Key(label: 'x²', onTap: _square, kind: _KeyKind.function),
              _Key(label: '√', onTap: _squareRoot, kind: _KeyKind.function),
              _Key(label: 'AC', onTap: _clear, kind: _KeyKind.function),
            ]),
            _KeyRow(children: [
              _Key(label: '+/−', onTap: _toggleSign, kind: _KeyKind.function),
              _Key(label: '%', onTap: _percent, kind: _KeyKind.function),
              _Key(label: '÷', onTap: () => _operate('÷'), kind: _KeyKind.operator),
            ]),
            _KeyRow(children: [
              _Key(label: '7', onTap: () => _input(7)),
              _Key(label: '8', onTap: () => _input(8)),
              _Key(label: '9', onTap: () => _input(9)),
              _Key(label: '×', onTap: () => _operate('×'), kind: _KeyKind.operator),
            ]),
            _KeyRow(children: [
              _Key(label: '4', onTap: () => _input(4)),
              _Key(label: '5', onTap: () => _input(5)),
              _Key(label: '6', onTap: () => _input(6)),
              _Key(label: '−', onTap: () => _operate('−'), kind: _KeyKind.operator),
            ]),
            _KeyRow(children: [
              _Key(label: '1', onTap: () => _input(1)),
              _Key(label: '2', onTap: () => _input(2)),
              _Key(label: '3', onTap: () => _input(3)),
              _Key(label: '+', onTap: () => _operate('+'), kind: _KeyKind.operator),
            ]),
            _KeyRow(children: [
              _Key(label: '⌫', onTap: _backspace, kind: _KeyKind.function),
              _Key(label: '0', onTap: () => _input(0)),
              _Key(label: '.', onTap: _decimal),
              _Key(label: '=', onTap: _equals, kind: _KeyKind.equals),
            ]),
          ],
        ),
      ),
    );
  }
}

enum _KeyKind { digit, function, operator, equals }

class _KeyRow extends StatelessWidget {
  const _KeyRow({required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: Tokens.s2),
        child: Row(
          children: [
            for (var i = 0; i < children.length; i++) ...[
              if (i > 0) const SizedBox(width: Tokens.s2),
              Expanded(child: children[i]),
            ],
          ],
        ),
      );
}

class _Key extends StatelessWidget {
  const _Key({
    required this.label,
    required this.onTap,
    this.kind = _KeyKind.digit,
  });

  final String label;
  final VoidCallback onTap;
  final _KeyKind kind;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    final (background, foreground) = switch (kind) {
      _KeyKind.equals => (scheme.primary, scheme.onPrimary),
      _KeyKind.operator => (scheme.primaryContainer, scheme.onPrimaryContainer),
      _KeyKind.function => (
          scheme.surfaceContainerHigh,
          scheme.onSurfaceVariant,
        ),
      _KeyKind.digit => (scheme.surfaceContainerLow, scheme.onSurface),
    };

    return Material(
      color: background,
      borderRadius: BorderRadius.circular(Tokens.rSm),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(Tokens.rSm),
        child: Container(
          height: 52,
          alignment: Alignment.center,
          child: Text(
            label,
            style: TextStyle(
              fontSize: 17,
              fontWeight: FontWeight.w700,
              color: foreground,
            ),
          ),
        ),
      ),
    );
  }
}
