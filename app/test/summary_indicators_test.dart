import 'package:app/services/app_controller.dart';
import 'package:app/ui/app_shell.dart';
import 'package:app/ui/app_theme.dart';
import 'package:app/ui/summary_indicators.dart';
import 'package:app/ui/priority_icon.dart';
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
    'footer is bottom aligned and inline; nonzero priority stacks stay centered',
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
      final mainRow = find
          .descendant(
            of: find.byType(SummaryBodyControls).first,
            matching: find.byType(Row),
          )
          .first;
      final mainBodyHeight = tester.getSize(mainRow).height;
      final menuPosition = tester.getTopLeft(
        find.byKey(const ValueKey('menu-2')),
      );
      row['summary'] = <String, dynamic>{'next_due_date': null};
      h.app.notifyListeners();
      await tester.pumpAndSettle();
      expect(find.byType(SummaryIndicators), findsNothing);
      expect(
        tester.getTopLeft(find.byKey(const ValueKey('menu-2'))),
        menuPosition,
      );
      row['summary'] = <String, dynamic>{
        'total': 5,
        'completed': 2,
        'high_priority': 0,
        'medium_priority': 2,
        'low_priority': 1,
        'next_due_date': '2026-12-01',
      };
      h.app.notifyListeners();
      await tester.pumpAndSettle();
      expect(tester.getSize(mainRow).height, mainBodyHeight);
      final title = find.descendant(of: card, matching: find.text('Folder'));
      expect(
        tester.getCenter(title).dy,
        closeTo(tester.getCenter(mainRow).dy, .1),
      );
      expect(
        tester.getCenter(find.byKey(const ValueKey('menu-2'))).dy,
        closeTo(tester.getCenter(mainRow).dy, .1),
      );
      expect(find.text('Total: 2 / 5'), findsOneWidget);
      expect(find.text('Next: 2026-12-01'), findsOneWidget);
      expect(find.byType(SummaryIndicators), findsOneWidget);
      expect(
        tester.getTopLeft(find.text('Total: 2 / 5')).dy,
        tester.getTopLeft(find.text('Next: 2026-12-01')).dy,
      );
      expect(
        tester.getTopLeft(find.text('Total: 2 / 5')).dx,
        lessThan(tester.getTopLeft(find.text('Next: 2026-12-01')).dx),
      );
      expect(
        tester.getTopLeft(find.text('Total: 2 / 5')).dy,
        greaterThan(
          tester
              .getBottomLeft(
                find.descendant(of: card, matching: find.text('Folder')),
              )
              .dy,
        ),
      );
      final body = find.descendant(
        of: card,
        matching: find.byType(IntrinsicHeight),
      );
      expect(
        tester.getCenter(body).dy,
        greaterThan(tester.getCenter(title).dy),
      );
      expect(
        tester.getBottomLeft(find.text('Total: 2 / 5')).dy,
        closeTo(tester.getBottomLeft(body).dy, .1),
      );
      for (final counts in [(1, 0, 0), (1, 0, 2), (1, 2, 3), (0, 0, 0)]) {
        final summary = row['summary'] as Map<String, dynamic>;
        summary.addAll({
          'high_priority': counts.$1,
          'medium_priority': counts.$2,
          'low_priority': counts.$3,
        });
        h.app.notifyListeners();
        await tester.pumpAndSettle();
        final visible = [
          counts.$1,
          counts.$2,
          counts.$3,
        ].where((n) => n > 0).length;
        final icons = find.descendant(
          of: find.byType(SummaryPriorityCounts),
          matching: find.byType(PriorityIcon),
        );
        expect(icons, findsNWidgets(visible));
        if (visible > 0) {
          final stack = find.descendant(
            of: find.byType(SummaryPriorityCounts),
            matching: find.byType(Column),
          );
          expect(
            tester.getCenter(stack).dy,
            closeTo(tester.getCenter(body).dy, .1),
          );
        } else {
          expect(find.byType(SummaryPriorityCounts), findsNothing);
        }
      }
      row['summary'] = <String, dynamic>{'total': 0, 'high_priority': 0};
      h.app.notifyListeners();
      await tester.pumpAndSettle();
      expect(find.text('Total: 0'), findsOneWidget);
      expect(find.byType(SummaryPriorityCounts), findsNothing);
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
                    // Preserve the 72px summary area plus the added 16px control.
                    width: 88,
                    child: IntrinsicHeight(
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          const SummaryBodyControls(
                            summary: {'total': 12345, 'completed': 123},
                            child: SizedBox(
                              width: 16,
                              height: 48,
                              child: Icon(Icons.more_horiz, size: 14),
                            ),
                          ),
                          Expanded(
                            child: SummaryItemContent(
                              summary: const {
                                'total': 12345,
                                'completed': 123,
                                'next_due_date': null,
                              },
                              child: const Text(
                                'Parent',
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ),
                          const SummaryPriorityCounts(
                            summary: {
                              'high_priority': 0,
                              'medium_priority': 12,
                              'low_priority': 4,
                            },
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        final control = find
            .descendant(
              of: find.byType(SummaryBodyControls),
              matching: find.byType(SizedBox),
            )
            .first;
        expect(
          tester.getCenter(find.text('Parent')).dy,
          closeTo(tester.getCenter(control).dy, .1),
        );
        final stack = find.descendant(
          of: find.byType(SummaryPriorityCounts),
          matching: find.byType(Column),
        );
        expect(
          tester.getCenter(stack).dy,
          closeTo(tester.getCenter(find.byType(IntrinsicHeight)).dy, .1),
        );
        expect(find.textContaining('Next:'), findsNothing);
        expect(
          find.bySemanticsLabel(
            RegExp('Direct child tasks.*Total: 123 / 12345'),
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
