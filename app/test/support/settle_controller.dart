import 'package:app/services/app_controller.dart';
import 'package:flutter_test/flutter_test.dart';

/// Pump the widget clock while real document/draft IO completes. Disk latency
/// varies on native CI; a fixed number of frames is not a save-completion signal.
Future<void> settleController(WidgetTester tester, AppController app) async {
  final elapsed = Stopwatch()..start();
  var idleFrames = 0;
  while (idleFrames < 2) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 10)),
    );
    await tester.pump(const Duration(milliseconds: 20));
    final idle =
        !app.busy &&
        !app.savingItemDraft &&
        !app.discardingItemDraft &&
        !app.retainingItemDraft;
    idleFrames = idle ? idleFrames + 1 : 0;
    if (elapsed.elapsed > const Duration(seconds: 15)) {
      fail(
        'Controller IO did not finish: busy=${app.busy}, '
        'saving=${app.savingItemDraft}, discarding=${app.discardingItemDraft}, '
        'retaining=${app.retainingItemDraft}; error=${app.error}',
      );
    }
  }
  await tester.pumpAndSettle();
}
