import 'package:flutter_test/flutter_test.dart';
import 'package:nltc/data/repositories/question_repository.dart';

/// What the download strip is allowed to claim about a download.
///
/// A subject bank is no longer capped, so a download can run to thousands of
/// questions — the bar has to be honest about how far along it is, and honest
/// about not knowing when the server wouldn't say.
void main() {
  group('DownloadProgress.fraction', () {
    test('is the share of the bank that has arrived', () {
      expect(
        const DownloadProgress(fetched: 500, total: 4000, done: false).fraction,
        0.125,
      );
    });

    test('is null when the bank size is unknown', () {
      // The count aggregate can fail on its own; that costs the bar its
      // percentage, not the download.
      expect(
        const DownloadProgress(fetched: 500, done: false).fraction,
        isNull,
      );
      expect(
        const DownloadProgress(fetched: 0, total: 0, done: false).fraction,
        isNull,
      );
    });

    test('never reads past full', () {
      // The count includes questions too malformed to save, so the last page
      // can arrive with fewer saved than counted — and a bar at 103% is worse
      // than a bar that simply finishes.
      expect(
        const DownloadProgress(fetched: 4100, total: 4000, done: true).fraction,
        1.0,
      );
    });
  });
}
