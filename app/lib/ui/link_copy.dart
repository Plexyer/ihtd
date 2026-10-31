import 'package:flutter/material.dart';

import '../services/app_controller.dart';
import 'editor_dialog.dart';
import 'shared.dart';

Future<void> showLinkCopy(
  BuildContext context,
  AppController app,
  int source,
) async {
  final owner = app.editIdentity;
  if (!await app.finishDraft() ||
      !context.mounted ||
      app.editIdentity != owner) {
    return;
  }
  final options = await app.dispatch({
    'op': 'copy_options',
    'id': source,
  }, expectedDocument: owner);
  if (options == null || !context.mounted) return;
  await showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (_) => _LinkCopyDialog(
      app: app,
      source: source,
      owner: owner,
      options: options,
    ),
  );
}

class _LinkCopyDialog extends StatefulWidget {
  const _LinkCopyDialog({
    required this.app,
    required this.source,
    required this.owner,
    required this.options,
  });
  final AppController app;
  final int source;
  final DocumentEditIdentity owner;
  final Map<String, dynamic> options;
  @override
  State<_LinkCopyDialog> createState() => _LinkCopyState();
}

class _LinkCopyState extends State<_LinkCopyDialog> {
  final query = TextEditingController();
  bool copying = false,
      independent = false,
      info = false,
      selected = false,
      saving = false;
  int? destination;
  String depth = '0';
  String? error;
  Set<int> get forbidden => {
    widget.source,
    ...(widget.options['descendants'] as List).cast<int>(),
  };
  bool get forced => copying && selected && forbidden.contains(destination);
  @override
  void dispose() {
    query.dispose();
    super.dispose();
  }

  Future<void> save() async {
    if (!selected || saving) return;
    setState(() {
      saving = true;
      error = null;
    });
    final result = await widget.app.dispatch({
      'op': 'link_or_copy',
      'source': widget.source,
      'destination': destination,
      'mode': copying ? 'copy' : 'link',
      'depth': forced || depth == 'all' ? null : int.parse(depth),
      'independent': copying && independent,
      'expected_revision': widget.options['revision'],
    }, expectedDocument: widget.owner);
    if (!mounted) return;
    if (result != null) {
      Navigator.pop(context);
      return;
    }
    setState(() {
      saving = false;
      error = widget.app.error ?? 'The operation could not be completed. Reopen to review the collection.';
    });
  }

  @override
  Widget build(BuildContext context) {
    final maxDepth = intValue(widget.options['max_depth']);
    final search = query.text.trim().toLowerCase();
    final items =
        documentValues(widget.app, 'items')
            .where(
              (item) =>
                  (copying || !forbidden.contains(item['id'])) &&
                  '${item['title']} #${item['id']}'.toLowerCase().contains(
                    search,
                  ),
            )
            .toList()
          ..sort(
            (a, b) => '${a['title']}'.toLowerCase().compareTo(
              '${b['title']}'.toLowerCase(),
            ),
          );
    return PopScope<void>(
      canPop: !saving,
      child: EditorDialog(
        title: Row(
          children: [
            const Expanded(child: Text('Link / copy task to')),
            IconButton(
              tooltip: 'About linking and copying',
              onPressed: () => setState(() => info = !info),
              icon: const Icon(Icons.info_outline),
            ),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Source: ${itemById(widget.app, widget.source)['title']} (#${widget.source})',
            ),
            if (info)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 12),
                child: Text(
                  'Link: show the same item and children elsewhere; edits are shared.\nCopy: create a separate item, copying children to the selected depth.',
                ),
              ),
            if (error != null)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 12),
                child: Text(
                  error!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              ),
            const SizedBox(height: 12),
            TextField(
              controller: query,
              enabled: !saving,
              decoration: const InputDecoration(
                labelText: 'Search destination title or ID',
              ),
              onChanged: (_) => setState(() {}),
            ),
            SizedBox(
              height: 210,
              child: ListView(
                children: [
                  if (search.isEmpty || 'top level'.contains(search))
                    ListTile(
                      title: const Text('Top level'),
                      selected: selected && destination == null,
                      leading: const Icon(Icons.home_outlined),
                      onTap: saving
                          ? null
                          : () => setState(() {
                              selected = true;
                              destination = null;
                            }),
                    ),
                  for (final item in items)
                    ListTile(
                      key: ValueKey('destination-${item['id']}'),
                      title: Text('${item['title']}'),
                      subtitle: Text('#${item['id']} · ${item['kind']}'),
                      selected: selected && destination == item['id'],
                      onTap: saving
                          ? null
                          : () => setState(() {
                              selected = true;
                              destination = intValue(item['id']);
                            }),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            DropdownButtonFormField<bool>(
              initialValue: copying,
              decoration: const InputDecoration(labelText: 'Operation'),
              items: const [
                DropdownMenuItem(value: false, child: Text('Link')),
                DropdownMenuItem(value: true, child: Text('Copy')),
              ],
              onChanged: saving
                  ? null
                  : (v) => setState(() {
                      copying = v == true;
                      if (!copying && forbidden.contains(destination)) {
                        selected = false;
                        destination = null;
                      }
                    }),
            ),
            const SizedBox(height: 20),
            DropdownButtonFormField<String>(
              key: ValueKey('copy-depth-$copying-$forced-$depth'),
              initialValue: forced ? 'all' : depth,
              isExpanded: true,
              decoration: const InputDecoration(labelText: 'Copy depth'),
              items: [
                const DropdownMenuItem(
                  value: '0',
                  child: Text('Source item only; link its children'),
                ),
                for (var d = 1; d <= maxDepth; d++)
                  DropdownMenuItem(
                    value: '$d',
                    child: Text(
                      d == 1
                          ? 'Through direct children'
                          : 'Through $d levels of children',
                    ),
                  ),
                const DropdownMenuItem(
                  value: 'all',
                  child: Text('Create copies of all child tasks'),
                ),
              ],
              onChanged: !copying || forced || saving
                  ? null
                  : (v) => setState(() => depth = v ?? '0'),
            ),
            if (forced)
              const Padding(
                padding: EdgeInsets.only(top: 12),
                child: Text(
                  'Copying into this task or one of its children requires All descendants. Copy depth is locked to avoid circular links.',
                ),
              ),
            CheckboxListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Make every appearance independent'),
              subtitle: const Text(
                'Off by default: copy each unique item once and preserve links within the copy.',
              ),
              value: independent,
              onChanged: copying && !saving
                  ? (v) => setState(() => independent = v == true)
                  : null,
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: saving ? null : () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: !selected || saving ? null : save,
            child: Text(
              saving
                  ? 'Working…'
                  : copying
                  ? 'Copy to'
                  : 'Link to',
            ),
          ),
        ],
      ),
    );
  }
}
