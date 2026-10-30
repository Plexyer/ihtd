import 'package:app/services/app_controller.dart';
import 'package:app/ui/app_shell.dart';
import 'package:app/ui/app_theme.dart';
import 'package:app/ui/summary_indicators.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:package_info_plus/package_info_plus.dart';

import 'support/item_draft_harness.dart';

void main() {
  late DraftHarness h;
  var containerDisposedApp = false;
  setUp(() async {
    containerDisposedApp = false;
    PackageInfo.setMockInitialValues(
      appName: 'IHTD',
      packageName: 'dev.ihtd.app',
      version: '0.2.5',
      buildNumber: '14',
      buildSignature: '',
    );
    h = DraftHarness(memoryDrafts: true);
    await h.initialize();
  });
  tearDown(() async {
    if (!containerDisposedApp) {
      await h.dispose();
    } else {
      await h.app.itemDrafts.flush();
      await h.storage.diagnostics.flush();
      await h.directory.delete(recursive: true);
    }
  });

  test(
    'local day refresh is read-only and retains unfinished item fields',
    () async {
      var now = DateTime(2026, 10, 30, 23, 59);
      h.app.dispose();
      h.app = AppController(
        command: h.command,
        polling: false,
        now: () => now,
        documentServices: h.storage,
        supportDirectory: () async => h.directory,
        draftStore: MemoryDraftStore(),
      );
      await h.app.ready;
      await h.app.selectItem(3);
      h.app.changeItemDraft('notes', 'Private unfinished notes');
      await h.app.refreshRows();
      var queries = h.commands.where((r) => r['op'] == 'query').toList();
      expect(queries.last['today'], '2026-10-30');
      final count = queries.length;
      await h.app.poll();
      expect(h.commands.where((r) => r['op'] == 'query').length, count);
      now = DateTime(2026, 10, 31);
      await h.app.poll();
      queries = h.commands.where((r) => r['op'] == 'query').toList();
      expect(queries.length, count + 1);
      expect(queries.last['today'], '2026-10-31');
      expect(h.app.itemDraft!.values['notes'], 'Private unfinished notes');
      expect(h.doc['items']['3']['notes'], 'Saved notes');
      expect(h.adapter.writes, 0);
      expect(h.commands.where((r) => r['op'] == 'save_item_draft'), isEmpty);
    },
  );

  testWidgets(
    'real parent card keeps its normal height with all priority counts and ratio',
    (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final row = <String, dynamic>{
        'id': 2,
        'path': '2',
        'depth': 0,
        'has_children': false,
        'expanded': false,
        'context_only': false,
      };
      h.app.rows = [row];
      final container = ProviderContainer(
        overrides: [appProvider.overrideWith((ref) => h.app)],
      );
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(theme: buildIhtdTheme(), home: const AppShell()),
        ),
      );
      await tester.pumpAndSettle();
      final card = find.byKey(const ValueKey('into-2'));
      final height = tester.getSize(card).height;
      final menuPosition = tester.getTopLeft(
        find.byKey(const ValueKey('menu-2')),
      );
      row['summary'] = {'next_due_date': null};
      h.app.notifyListeners();
      await tester.pumpAndSettle();
      expect(find.byType(SummaryIndicators), findsNothing);
      expect(
        tester.getTopLeft(find.byKey(const ValueKey('menu-2'))),
        menuPosition,
      );
      row['summary'] = {
        'total': 5,
        'completed': 2,
        'high_priority': 0,
        'medium_priority': 2,
        'low_priority': 1,
        'next_due_date': '2026-12-01',
      };
      h.app.notifyListeners();
      await tester.pumpAndSettle();
      expect(tester.getSize(card).height, height);
      expect(find.text('Total: 2 / 5'), findsOneWidget);
      expect(find.text('Next: 2026-12-01'), findsOneWidget);
      expect(find.byType(SummaryIndicators), findsOneWidget);
      expect(
        find.bySemanticsLabel(
          RegExp('Direct child tasks.*High priority: 0.*Medium priority: 2'),
        ),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      containerDisposedApp = true;
      container.dispose();
    },
  );

  testWidgets(
    'deep narrow panels scroll instead of overflow and keep large text accessible',
    (tester) async {
      for (final scale in [1.0, 2.0]) {
        await tester.pumpWidget(
          MaterialApp(
            theme: buildIhtdTheme(),
            home: Scaffold(
              body: MediaQuery(
                data: MediaQueryData(textScaler: TextScaler.linear(scale)),
                child: Align(
                  alignment: Alignment.topLeft,
                  child: SizedBox(
                    width: 72,
                    child: SummaryIndicators(
                      summary: const {
                        'total': 12345,
                        'completed': 123,
                        'high_priority': 0,
                        'medium_priority': 12,
                        'low_priority': 4,
                        'next_due_date': null,
                      },
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        expect(find.textContaining('Next:'), findsNothing);
        expect(
          find.bySemanticsLabel(
            RegExp('Direct child tasks.*Total: 123 / 12345.*Low priority: 4'),
          ),
          findsOneWidget,
        );
        final scrollable = tester.state<ScrollableState>(
          find.byType(Scrollable),
        );
        expect(scrollable.position.maxScrollExtent, greaterThan(0));
        await tester.drag(
          find.byType(SummaryIndicators),
          const Offset(-400, 0),
        );
        await tester.pumpAndSettle();
        expect(scrollable.position.pixels, greaterThan(0));
      }
    },
  );
}
