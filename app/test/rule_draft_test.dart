import 'package:app/services/rule_draft.dart';
import 'package:flutter_test/flutter_test.dart';

Map<String, dynamic> tag(int id) => {'op': 'tag', 'tag_id': id};
Map<String, dynamic> group(String op, List<Map<String, dynamic>> rules) => {
  'op': op,
  'rules': rules,
};

void main() {
  test('same-op projection preserves exact saved tree, duplicates and source identities', () {
    final original = group('or', [
      tag(1),
      group('or', [tag(2), tag(2)]),
    ]);
    final draft = RuleDraft(original);
    expect(draft.operands(draft.root).map((n) => n.value['tag_id']), [1, 2, 2]);
    expect(draft.encode(), original);
    expect(
      draft.root.children[1].children[0],
      same(draft.operands(draft.root)[1]),
    );
    draft.operands(draft.root)[1].value['tag_id'] = 3;
    expect(original['rules'][1]['rules'][0]['tag_id'], 2); // isolated copy
    expect(draft.encode()['rules'][1]['rules'][0]['tag_id'], 3);
  });
  test('inner and outer additions have distinct scope', () {
    final draft = RuleDraft(
      group('and', [
        tag(1),
        group('or', [tag(2), tag(3)]),
      ]),
    );
    final inner = draft.root.children[1];
    draft.append(inner, draft.read(tag(4)));
    draft.append(draft.root, draft.read(tag(5)));
    expect(
      draft.encode(),
      group('and', [
        tag(1),
        group('or', [tag(2), tag(3), tag(4)]),
        tag(5),
      ]),
    );
  });
  test(
    'new operators have two real draft slots and cannot serialize incomplete',
    () {
      final draft = RuleDraft();
      draft.fill(draft.root, 'and');
      expect(draft.slots.length, 2);
      expect(() => draft.encode(), throwsStateError);
      draft.fill(draft.root.children[0], 'all');
      expect(draft.slots.length, 1);
      draft.fill(draft.root.children[1], 'tag', tag(7));
      expect(
        draft.encode(),
        group('and', [
          {'op': 'all'},
          tag(7),
        ]),
      );
    },
  );
  test(
    'changing coalesced AND to OR retains every operand and source subtree',
    () {
      final draft = RuleDraft(
        group('and', [
          tag(1),
          group('and', [tag(2), tag(3)]),
        ]),
      );
      final ids = draft.operands(draft.root).map((n) => n.id).toList();
      draft.changeConnector(draft.root, 'or');
      expect(
        draft.encode(),
        group('or', [
          tag(1),
          group('or', [tag(2), tag(3)]),
        ]),
      );
      expect(draft.operands(draft.root).map((n) => n.id), ids);
    },
  );
  test('conversion to exactly-one applies to all displayed operands once', () {
    final draft = RuleDraft(
      group('and', [
        tag(1),
        group('and', [tag(2), tag(3)]),
      ]),
    );
    draft.changeConnector(draft.root, 'xor');
    expect(draft.encode(), group('xor', [tag(1), tag(2), tag(3)]));
  });
  test(
    'nested XOR and NOT boundaries and duplicate branches remain intact',
    () {
      final original = group('xor', [
        tag(1),
        group('xor', [tag(2), tag(2)]),
        {
          'op': 'not',
          'rule': group('or', [tag(3), tag(4)]),
        },
      ]);
      final draft = RuleDraft(original);
      expect(draft.operands(draft.root).length, 3);
      expect(draft.operands(draft.root)[1].op, 'xor');
      expect(draft.encode(), original);
    },
  );
  test(
    'remove sole operand leaves an unfilled draft, not implicit match-all',
    () {
      final draft = RuleDraft(group('and', [tag(1), tag(2)]));
      draft.remove(draft.root.children[0]);
      expect(draft.encode(), group('and', [tag(2)]));
      draft.remove(draft.root.children[0]);
      expect(draft.slots.length, 1);
      expect(() => draft.encode(), throwsStateError);
      draft.remove(draft.root);
      expect(draft.root.slot, true);
    },
  );
  test(
    'loaded empty groups are constants, never confused with new placeholders',
    () {
      for (final op in ['and', 'or', 'xor']) {
        final original = group(op, []);
        final draft = RuleDraft(original);
        expect(draft.slots, isEmpty);
        expect(draft.encode(), original);
      }
      final original = group('and', [group('and', []), tag(1)]);
      final draft = RuleDraft(original);
      expect(draft.operands(draft.root).length, 2);
      expect(draft.encode(), original);
    },
  );
  test('removing final flattened subgroup operand keeps surviving outer chain complete', () {
    final draft = RuleDraft(
      group('and', [
        tag(1),
        group('and', [tag(2)]),
      ]),
    );
    draft.remove(draft.operands(draft.root)[1]);
    expect(draft.slots, isEmpty);
    expect(draft.encode(), group('and', [tag(1)]));
  });
  test('combine wraps only target and keeps its content and sibling scope', () {
    final draft = RuleDraft(group('and', [tag(1), tag(2)]));
    draft.combine(draft.root.children[1], 'or');
    expect(draft.root.children[0].value, tag(1));
    expect(draft.root.children[1].children[0].value, tag(2));
    expect(draft.root.children[1].children[1].slot, true);
  });
  test('every leaf roundtrips including options, negative text and missing references', () {
    final original = group('and', [
      {
        'op': 'text',
        'field': 'notes',
        'comparison': 'not_contains',
        'value': 'xx1',
        'case_sensitive': true,
      },
      {'op': 'folder', 'folder_id': 99, 'recursive': false},
      {'op': 'due', 'comparison': 'is_not_set', 'value': null},
      {'op': 'due', 'comparison': 'on_or_after', 'value': '2026-10-31'},
      {'op': 'priority', 'comparison': 'le', 'value': 2},
      {'op': 'kind', 'kind': 'folder'},
      {'op': 'completed', 'value': false},
      tag(42),
      {'op': 'all'},
    ]);
    expect(RuleDraft(original).encode(), original);
  });
}
