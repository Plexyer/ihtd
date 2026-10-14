import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../services/app_controller.dart';
import '../services/rule_draft.dart';
import 'editor_dialog.dart';
import 'rule_condition_editor.dart';

/// Shared infix layout: Option-A rows on narrow windows, inline runs on wide ones.
class RuleExpression extends StatelessWidget {
  const RuleExpression({
    super.key,
    required this.app,
    required this.draft,
    required this.identity,
    required this.onChanged,
    this.enabled = true,
  });
  final AppController app;
  final RuleDraft draft;
  final DocumentEditIdentity identity;
  final VoidCallback onChanged;
  final bool enabled;
  String connector(String op) => op == 'xor' ? 'EXACTLY ONE' : op.toUpperCase();

  Future<void> pick(
    BuildContext context,
    RuleNode target, {
    bool append = false,
  }) async {
    final type = await showDialog<String>(
      context: context,
      builder: (context) => EditorDialog(
        title: Text(
          append
              ? 'Add condition to ${connector(target.op)} chain'
              : 'Choose condition or group',
        ),
        content: Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final entry in ruleKinds.entries)
              OutlinedButton(
                key: ValueKey('pick-${entry.key}'),
                onPressed: () => Navigator.pop(context, entry.key),
                child: Text(entry.value),
              ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
        ],
      ),
    );
    if (type == null || !context.mounted) return;
    Map<String, dynamic>? value;
    if (!const ['and', 'or', 'xor', 'not'].contains(type)) {
      value = await editCondition(
        context,
        app,
        initialCondition(type),
        identity,
      );
      if (value == null || !context.mounted) return;
    }
    final node = append ? draft.empty() : target;
    draft.fill(node, type, value);
    if (append) draft.append(target, node);
    onChanged();
  }

  Future<void> edit(BuildContext context, RuleNode node) async {
    final value = await editCondition(context, app, node.value, identity);
    if (value != null && context.mounted) {
      node.value = value;
      onChanged();
    }
  }

  Future<void> change(BuildContext context, RuleNode node) async {
    final op = await showDialog<String>(
      context: context,
      builder: (context) => EditorDialog(
        title: const Text('Change chain operator'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Changes the connector for this whole chain. Conditions are kept.',
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final op in ['and', 'or', 'xor'])
                  OutlinedButton(
                    key: ValueKey('connector-$op'),
                    onPressed: () => Navigator.pop(context, op),
                    child: Text(connector(op)),
                  ),
              ],
            ),
            const SizedBox(height: 12),
            const Text(
              'AND: all must match. OR: at least one. EXACTLY ONE: only one branch may match.',
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
        ],
      ),
    );
    if (op != null && context.mounted) {
      draft.changeConnector(node, op);
      onChanged();
    }
  }

  Future<void> combine(BuildContext context, RuleNode node) async {
    final op = await showDialog<String>(
      context: context,
      builder: (context) => EditorDialog(
        title: const Text('Combine this expression'),
        content: Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final op in ['and', 'or', 'xor', 'not'])
              OutlinedButton(
                onPressed: () => Navigator.pop(context, op),
                child: Text(connector(op)),
              ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
        ],
      ),
    );
    if (op != null && context.mounted) {
      draft.combine(node, op);
      onChanged();
    }
  }

  Widget menu(BuildContext context, RuleNode node) => PopupMenuButton<String>(
    key: ValueKey('rule-menu-${node.id}'),
    tooltip: node.chain
        ? '${connector(node.op)} chain actions'
        : 'Condition actions',
    enabled: enabled,
    onSelected: (action) {
      switch (action) {
        case 'change':
          change(context, node);
        case 'combine':
          combine(context, node);
        case 'replace':
          pick(context, node);
        case 'remove':
          draft.remove(node);
          onChanged();
      }
    },
    itemBuilder: (_) => [
      if (node.chain)
        const PopupMenuItem(
          value: 'change',
          child: Text('Change chain operator…'),
        ),
      const PopupMenuItem(
        value: 'combine',
        child: Text('Combine with another condition…'),
      ),
      const PopupMenuItem(value: 'replace', child: Text('Replace expression…')),
      const PopupMenuItem(value: 'remove', child: Text('Remove expression')),
    ],
  );
  Widget plus(
    BuildContext context,
    RuleNode node, {
    bool append = false,
    bool label = false,
  }) {
    final scope = append
        ? 'Add ${connector(node.op)} condition'
        : 'Fill empty condition';
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        IconButton.outlined(
          key: ValueKey('${append ? 'append' : 'slot'}-${node.id}'),
          tooltip: scope,
          style: IconButton.styleFrom(
            shape: const CircleBorder(),
            minimumSize: const Size(48, 48),
          ),
          onPressed: enabled ? () => pick(context, node, append: append) : null,
          icon: const Icon(Icons.add, size: 20),
        ),
        if (label)
          Flexible(
            child: Padding(
              padding: const EdgeInsets.only(left: 8),
              child: Text(scope),
            ),
          ),
      ],
    );
  }

  bool deleted(RuleNode node) =>
      node.op == 'folder' &&
      (app.document?['deleted_item_ids'] as List? ?? []).contains(
        node.value['folder_id'],
      );
  Widget leaf(BuildContext context, RuleNode node, double width) {
    if (node.slot) return plus(context, node);
    return ConstrainedBox(
      constraints: BoxConstraints(maxWidth: width),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Flexible(
            child: TextButton(
              key: ValueKey('condition-${node.id}'),
              style: TextButton.styleFrom(
                alignment: Alignment.centerLeft,
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 12,
                ),
                backgroundColor: deleted(node)
                    ? const Color(0xfffff4d0)
                    : Theme.of(context).colorScheme.surfaceContainerLow,
                foregroundColor: Theme.of(context).colorScheme.onSurface,
              ),
              onPressed: enabled ? () => edit(context, node) : null,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(conditionSummary(app, node.value)),
                  if (deleted(node))
                    const Text(
                      'This container was deleted. Replace it or remove this rule.',
                      style: TextStyle(color: Color(0xff8a5b00)),
                    ),
                ],
              ),
            ),
          ),
          menu(context, node),
        ],
      ),
    );
  }

  Widget operatorButton(BuildContext context, RuleNode chain) => ConstrainedBox(
    constraints: const BoxConstraints(maxWidth: 112),
    child: TextButton(
      key: ValueKey('operator-${chain.id}'),
      onPressed: enabled ? () => change(context, chain) : null,
      child: Text(
        connector(chain.op),
        style: const TextStyle(fontWeight: FontWeight.bold),
      ),
    ),
  );

  Widget narrow(BuildContext context, RuleNode node, double width) {
    if (!node.chain && node.op != 'not') return leaf(context, node, width);
    if (node.op == 'not') {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(children: [const Text('NOT ('), menu(context, node)]),
          narrow(context, node.children.single, width),
          const Text(')'),
        ],
      );
    }
    final operands = draft.operands(node);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        if (operands.isEmpty)
          Text(
            'Empty ${connector(node.op)} group · ${node.op == 'and' ? 'matches all items' : 'matches no items'}',
          ),
        for (var i = 0; i < operands.length; i++) ...[
          if (operands[i].chain || operands[i].op == 'not') ...[
            Row(
              children: [
                if (i > 0) operatorButton(context, node),
                const Text('('),
              ],
            ),
            // Only indent the current level; deeply nested rendering uses a shared width budget.
            Padding(
              padding: EdgeInsets.only(left: width > 240 ? 12 : 0),
              child: narrow(
                context,
                operands[i],
                width > 240 ? width - 12 : width,
              ),
            ),
            const Text(')'),
          ] else
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (i > 0) operatorButton(context, node),
                  Expanded(
                    child: leaf(
                      context,
                      operands[i],
                      math.max(80, width - (i > 0 ? 96 : 0)),
                    ),
                  ),
                ],
              ),
            ),
        ],
        Row(
          children: [
            Expanded(child: plus(context, node, append: true, label: true)),
            menu(context, node),
          ],
        ),
        if (node.op == 'xor')
          const Text(
            'Exactly one branch must match.',
            style: TextStyle(fontSize: 12),
          ),
      ],
    );
  }

  void inlineTokens(
    BuildContext context,
    RuleNode node,
    double width,
    List<Widget> tokens, {
    RuleNode? preceding,
    bool nested = false,
  }) {
    final prefix = preceding == null
        ? <Widget>[]
        : [operatorButton(context, preceding)];
    if (node.chain) {
      final operands = draft.operands(node);
      if (nested) {
        tokens.add(
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [...prefix, const Text('(')],
          ),
        );
      }
      if (operands.isEmpty) {
        tokens.add(
          Text(
            'Empty ${connector(node.op)} group · ${node.op == 'and' ? 'matches all items' : 'matches no items'}',
          ),
        );
      }
      for (var i = 0; i < operands.length; i++) {
        inlineTokens(
          context,
          operands[i],
          width,
          tokens,
          preceding: i == 0 ? null : node,
          nested: operands[i].chain,
        );
      }
      tokens.add(
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            plus(context, node, append: true),
            menu(context, node),
            if (nested) const Text(')'),
          ],
        ),
      );
    } else if (node.op == 'not') {
      tokens.add(
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [...prefix, const Text('NOT ('), menu(context, node)],
        ),
      );
      inlineTokens(
        context,
        node.children.single,
        width,
        tokens,
        // NOT already supplies its own explicit operand parentheses.
        nested: false,
      );
      tokens.add(const Text(')'));
    } else {
      tokens.add(
        ConstrainedBox(
          constraints: BoxConstraints(maxWidth: width),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              ...prefix,
              Flexible(
                child: leaf(
                  context,
                  node,
                  width - (preceding == null ? 0 : 96),
                ),
              ),
            ],
          ),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final width = constraints.maxWidth;
      final scale = MediaQuery.textScalerOf(context).scale(14) / 14;
      if (width < 640 * scale) return narrow(context, draft.root, width);
      final tokens = <Widget>[];
      inlineTokens(context, draft.root, width, tokens);
      return Wrap(
        spacing: 8,
        runSpacing: 8,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: tokens,
      );
    },
  );
}
