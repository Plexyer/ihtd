import 'dart:convert';

/// UI identities/empty slots never enter the persisted FilterExpr encoding.
class RuleNode {
  RuleNode(this.id, this.value, this.children);
  final int id;
  Map<String, dynamic> value;
  List<RuleNode> children;
  String get op => value['op'] as String? ?? 'slot';
  bool get chain => const ['and', 'or', 'xor'].contains(op);
  bool get slot => op == 'slot';
}

class RuleDraft {
  RuleDraft([Map<String, dynamic>? filter]) {
    root = filter == null ? empty() : read(filter);
  }
  int _next = 0;
  late RuleNode root;
  RuleNode empty() => RuleNode(_next++, {}, []);

  RuleNode read(Map<String, dynamic> value) {
    final copy = Map<String, dynamic>.from(
      jsonDecode(jsonEncode(value)) as Map,
    );
    final op = copy['op'];
    final children = <RuleNode>[];
    if (const ['and', 'or', 'xor'].contains(op)) {
      for (final child in copy.remove('rules') as List) {
        children.add(read(Map<String, dynamic>.from(child as Map)));
      }
    } else if (op == 'not') {
      children.add(read(Map<String, dynamic>.from(copy.remove('rule') as Map)));
    }
    return RuleNode(_next++, copy, children);
  }

  Map<String, dynamic> encode([RuleNode? node]) {
    final n = node ?? root;
    if (n.slot) {
      throw StateError('Fill or remove each empty condition before saving.');
    }
    return {
      ...n.value,
      if (n.chain) 'rules': n.children.map((child) => encode(child)).toList(),
      if (n.op == 'not') 'rule': encode(n.children.single),
    };
  }

  List<RuleNode> get slots {
    final result = <RuleNode>[];
    final pending = [root];
    while (pending.isNotEmpty) {
      final n = pending.removeLast();
      if (n.slot) result.add(n);
      pending.addAll(n.children.reversed);
    }
    return result;
  }

  /// Flatten the display only: retain stored boundaries for creation hints.
  List<RuleNode> operands(RuleNode chain) {
    final result = <RuleNode>[];
    final pending = chain.children.reversed.toList();
    while (pending.isNotEmpty) {
      final n = pending.removeLast();
      if ((chain.op == 'and' || chain.op == 'or') &&
          n.op == chain.op &&
          n.children.isNotEmpty) {
        pending.addAll(n.children.reversed);
      } else {
        result.add(n);
      }
    }
    return result;
  }

  void fill(RuleNode node, String op, [Map<String, dynamic>? leaf]) {
    node.value = leaf == null ? {'op': op} : {...leaf};
    node.children = const ['and', 'or', 'xor'].contains(op)
        ? [empty(), empty()]
        : op == 'not'
        ? [empty()]
        : [];
  }

  void append(RuleNode chain, RuleNode operand) => chain.children.add(operand);

  /// Changing a visually coalesced chain changes all its same-op connectors.
  void changeConnector(RuleNode chain, String op) {
    final old = chain.op;
    if (op == old) return;
    if (op == 'xor' && (old == 'and' || old == 'or')) {
      // Exactly-one is not associative: convert the visible operands once.
      chain.children = operands(chain);
      chain.value = {...chain.value, 'op': op};
      return;
    }
    final pending = [chain];
    while (pending.isNotEmpty) {
      final n = pending.removeLast();
      if ((old == 'and' || old == 'or') && n.children.isNotEmpty) {
        pending.addAll(n.children.where((child) => child.op == old));
      }
      n.value = {...n.value, 'op': op};
    }
  }

  void combine(RuleNode node, String op) {
    final original = RuleNode(_next++, node.value, node.children);
    node.value = {'op': op};
    node.children = op == 'not' ? [original] : [original, empty()];
  }

  void remove(RuleNode target) {
    if (identical(root, target)) {
      root = empty();
      return;
    }
    final pending = [root];
    while (pending.isNotEmpty) {
      final parent = pending.removeLast();
      if (parent.children.contains(target)) {
        if (parent.children.length == 1) {
          // A hidden same-op subgroup belongs to the displayed outer chain.
          // Removing its last operand removes that subgroup, not a new hole.
          final ancestors = [root];
          RuleNode? outer;
          while (ancestors.isNotEmpty) {
            final candidate = ancestors.removeLast();
            if (candidate.children.contains(parent)) {
              outer = candidate;
              break;
            }
            ancestors.addAll(candidate.children);
          }
          if (outer != null &&
              outer.op == parent.op &&
              (parent.op == 'and' || parent.op == 'or')) {
            remove(parent);
          } else {
            parent.children[0] = empty();
          }
        } else {
          parent.children.remove(target);
        }
        return;
      }
      pending.addAll(parent.children);
    }
  }
}
