import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nltc/ui/wrapped/wrapped_audio.dart';

/// A missing cue is silent, not loud: nothing in `WrappedAudio` throws when a
/// file cannot be found, so a renamed asset or a dropped pubspec entry would
/// ship as a Wrapped that has quietly lost its sound. These load the cues the
/// way audioplayers will and check the bytes are really audio.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  /// Where audioplayers looks: `AudioCache.prefix` + the source path.
  String bundlePath(WrappedCue cue) => '${AudioCache.instance.prefix}${cue.path}';

  test('every cue has a distinct file', () {
    final files = WrappedCue.values.map((c) => c.file).toSet();
    expect(files, hasLength(WrappedCue.values.length));
  });

  testWidgets('every cue is a real asset', (tester) async {
    for (final cue in WrappedCue.values) {
      final data = await rootBundle.load(bundlePath(cue));
      expect(
        data.lengthInBytes,
        greaterThan(1000),
        reason: '${cue.name} is too small to be a sound',
      );
    }
  });

  testWidgets('every cue is 16-bit mono PCM the players can decode',
      (tester) async {
    for (final cue in WrappedCue.values) {
      final bytes = (await rootBundle.load(bundlePath(cue)))
          .buffer
          .asUint8List();

      String tag(int at) => String.fromCharCodes(bytes.sublist(at, at + 4));
      expect(tag(0), 'RIFF', reason: '${cue.name} is not a RIFF container');
      expect(tag(8), 'WAVE', reason: '${cue.name} is not WAVE');

      // Little-endian fields of the fmt chunk, which starts at byte 12.
      int u16(int at) => bytes[at] | (bytes[at + 1] << 8);
      int u32(int at) =>
          bytes[at] | (bytes[at + 1] << 8) | (bytes[at + 2] << 16) | (bytes[at + 3] << 24);

      expect(tag(12), 'fmt ', reason: '${cue.name} has no fmt chunk');
      expect(u16(20), 1, reason: '${cue.name} is not uncompressed PCM');
      expect(u16(22), 1, reason: '${cue.name} is not mono');
      expect(u32(24), 22050, reason: '${cue.name} is not 22.05 kHz');
      expect(u16(34), 16, reason: '${cue.name} is not 16-bit');
    }
  });

  test('muting is honoured before anything has loaded', () {
    // The screen builds this from a stored preference, so a muted student must
    // never get a cue out of the gap between construction and load().
    final audio = WrappedAudio(enabled: false);
    expect(audio.enabled, isFalse);

    // None of these may throw with no players behind them.
    audio.play(WrappedCue.open);
    audio.playTicks(
      count: 3,
      first: const Duration(milliseconds: 90),
      gap: const Duration(milliseconds: 70),
    );
    audio.enabled = true;
    audio.enabled = false;
  });
}
