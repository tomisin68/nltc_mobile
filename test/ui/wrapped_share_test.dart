import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nltc/ui/wrapped/wrapped_share.dart';
import 'package:path/path.dart' as p;

/// The bug these replace: the captured card was handed to the share sheet as an
/// `XFile.fromData` carrying a temp path nobody had written to. share_plus
/// returns an `XFile` untouched whenever its path is non-empty, so the platform
/// side was given a path to nothing and threw — and every student saw "Could
/// not build your card" on a card that had rendered perfectly.
///
/// Nothing above `stageFile` can tell the difference, because the failure only
/// surfaces where the bytes are read. So these check the one thing that
/// matters: the file is on disk, under the name the card is shared as.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const channel = MethodChannel('plugins.flutter.io/path_provider');
  const fileName = 'nltc-wrapped-2026-07.png';

  late Directory temp;

  setUp(() {
    temp = Directory.systemTemp.createTempSync('wrapped_share');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      channel,
      (call) async => call.method == 'getTemporaryDirectory' ? temp.path : null,
    );
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
    temp.deleteSync(recursive: true);
  });

  test('writes the card where it says it did', () async {
    final bytes = Uint8List.fromList(List.generate(64, (i) => i));

    final staged = await WrappedShare.stageFile(bytes, fileName);
    final onDisk = File(staged.path);

    expect(
      onDisk.existsSync(),
      isTrue,
      reason: 'nothing was written to ${staged.path}',
    );
    expect(onDisk.readAsBytesSync(), bytes);
    expect(staged.mimeType, 'image/png');
  });

  test('shares it under the name the card was given', () async {
    // share_plus copies the staged file into its own cache folder keeping the
    // basename, so this is the filename that reaches WhatsApp.
    final staged = await WrappedShare.stageFile(Uint8List(8), fileName);

    expect(p.basename(staged.path), fileName);
  });

  test('re-shares the same month over the card already staged', () async {
    // Sharing twice without leaving the screen is the ordinary case, and the
    // second card is the one that has to arrive.
    await WrappedShare.stageFile(Uint8List.fromList([1, 2, 3]), fileName);
    final staged =
        await WrappedShare.stageFile(Uint8List.fromList([9, 9]), fileName);

    expect(File(staged.path).readAsBytesSync(), [9, 9]);
  });
}
