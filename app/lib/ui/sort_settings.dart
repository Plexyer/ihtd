import 'package:flutter/material.dart';

import '../services/app_controller.dart';
import 'editor_dialog.dart';
import 'shared.dart';

const sortNames = {
  'manual': 'Manual',
  'title': 'Title',
  'due_date': 'Due date',
  'priority': 'Priority',
};
Map<String, dynamic> sortFor(AppController app, int view, int? parent) {
  final saved = asMap(asMap(asMap(app.document?['views'])['$view'])['sorting']);
  return {
    'mode': 'manual',
    'descending': false,
    ...asMap(saved['${parent ?? 0}']),
  };
}

Future<void> showSortSettings(
  BuildContext context,
  AppController app, {
  int? parent,
}) async {
  if (app.document == null) return;
  await showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (_) => _SortDialog(app: app, parent: parent),
  );
}

class SortControl extends StatelessWidget {
  const SortControl({super.key, required this.app, this.parent});
  final AppController app;
  final int? parent;
  @override
  Widget build(BuildContext context) {
    final spec = sortFor(app, app.selectedViewId, parent);
    return TextButton.icon(
      onPressed: app.busy
          ? null
          : () => showSortSettings(context, app, parent: parent),
      icon: const Icon(Icons.sort, size: 18),
      label: Text('Sort: ${sortNames[spec['mode']]}'),
      style: TextButton.styleFrom(visualDensity: VisualDensity.compact),
    );
  }
}

class _SortDialog extends StatefulWidget {
  const _SortDialog({required this.app, this.parent});
  final AppController app;
  final int? parent;
  @override
  State<_SortDialog> createState() => _SortState();
}

class _SortState extends State<_SortDialog> {
  late final DocumentEditIdentity owner;
  late final int view;
  late final Map<String, dynamic> original;
  late String mode;
  late bool descending;
  bool saving = false;
  String? error;
  @override
  void initState() {
    super.initState();
    owner = widget.app.editIdentity;
    view = widget.app.selectedViewId;
    original = sortFor(widget.app, view, widget.parent);
    mode = '${original['mode']}';
    descending = original['descending'] == true;
  }

  Future<void> save() async {
    if (saving) return;
    setState(() {
      saving = true;
      error = null;
    });
    final result = await widget.app.dispatch({
      'op': 'set_sort',
      'view_id': view,
      'parent': widget.parent,
      'expected_sort': original,
      'sort': {
        'mode': mode,
        'descending': mode == 'manual' ? false : descending,
      },
    }, expectedDocument: owner);
    if (!mounted) return;
    if (result != null) {
      Navigator.pop(context);
      return;
    }
    setState(() {
      saving = false;
      error = widget.app.error ?? 'Sorting could not be saved.';
    });
  }

  @override
  Widget build(BuildContext context) => PopScope<void>(
    canPop: !saving,
    child: EditorDialog(
      title: Text(
        widget.parent == null ? 'Sort top-level items' : 'Sort children',
      ),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '${widget.parent == null ? 'Top level' : itemById(widget.app, widget.parent!)['title']} · ${asMap(asMap(widget.app.document?['views'])['$view'])['name']}',
          ),
          const SizedBox(height: 16),
          if (error != null)
            Text(
              error!,
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          DropdownButtonFormField<String>(
            initialValue: mode,
            isExpanded: true,
            decoration: const InputDecoration(labelText: 'Sort by'),
            items: sortNames.entries
                .map(
                  (s) => DropdownMenuItem(value: s.key, child: Text(s.value)),
                )
                .toList(),
            onChanged: saving
                ? null
                : (v) => setState(() => mode = v ?? 'manual'),
          ),
          const SizedBox(height: 20),
          DropdownButtonFormField<bool>(
            initialValue: descending,
            isExpanded: true,
            decoration: const InputDecoration(labelText: 'Direction'),
            items: const [
              DropdownMenuItem(value: false, child: Text('Ascending')),
              DropdownMenuItem(value: true, child: Text('Descending')),
            ],
            onChanged: saving || mode == 'manual'
                ? null
                : (v) => setState(() => descending = v == true),
          ),
          const SizedBox(height: 16),
          const Text(
            'This sort choice applies only in this view. Automatic sorts keep folders first. Manual order is shared across views.',
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: saving ? null : () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: saving ? null : save,
          child: const Text('Save sorting'),
        ),
      ],
    ),
  );
}
