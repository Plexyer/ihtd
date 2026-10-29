import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../services/app_controller.dart';
import 'editor_dialog.dart';
import 'shared.dart';

const _indicators = <String, String>{
  'total': 'Total',
  'completed_ratio': 'Completed / total',
  'high_priority': 'High-priority count',
  'medium_priority': 'Medium-priority count',
  'low_priority': 'Low-priority count',
  'next_due_date': 'Next due date',
};

Map<String, dynamic> _copy(Map value) => asMap(jsonDecode(jsonEncode(value)));

Future<void> showCollectionSettings(
  BuildContext context,
  AppController app,
) async {
  if (!await app.finishDraft() || !context.mounted || app.document == null) {
    return;
  }
  await showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (_) => _SettingsDialog(app: app),
  );
}

Future<void> showIndicatorSettings(
  BuildContext context,
  AppController app, {
  required int itemId,
  required int viewId,
}) async {
  if (app.document == null) return;
  await showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (_) => _SettingsDialog(app: app, itemId: itemId, viewId: viewId),
  );
}

class _SettingsDialog extends StatefulWidget {
  const _SettingsDialog({required this.app, this.itemId, this.viewId});
  final AppController app;
  final int? itemId, viewId;
  @override
  State<_SettingsDialog> createState() => _SettingsDialogState();
}

class _SettingsDialogState extends State<_SettingsDialog> {
  late final DocumentEditIdentity identity;
  late final Map<String, dynamic> original, oldParent, oldView;
  late final Map<String, dynamic> indicators, parent, local;
  late final TextEditingController count, days;
  final form = GlobalKey<FormState>();
  bool saving = false;
  String? error;
  bool get collection => widget.itemId == null;

  @override
  void initState() {
    super.initState();
    final app = widget.app;
    identity = app.editIdentity;
    original = _copy(app.collectionSettings);
    indicators = _copy(asMap(original['indicators']));
    oldParent = _copy(
      asMap(
        asMap(app.document?['parent_indicator_defaults'])['${widget.itemId}'],
      ),
    );
    final view = asMap(asMap(app.document?['views'])['${widget.viewId}']);
    oldView = _copy(
      asMap(
        asMap(asMap(view['preferences'])['${widget.itemId}'])['indicators'],
      ),
    );
    parent = _copy(oldParent);
    local = _copy(oldView);
    count = TextEditingController(text: '${original['tag_suggestion_count']}');
    days = TextEditingController(text: '${original['tag_half_life_days']}');
  }

  @override
  void dispose() {
    count.dispose();
    days.dispose();
    super.dispose();
  }

  Future<void> save() async {
    if (saving || !(form.currentState?.validate() ?? false)) return;
    setState(() {
      saving = true;
      error = null;
    });
    final result = await widget.app.dispatch(
      collection
          ? {
              'op': 'set_collection_settings',
              'expected_settings': original,
              'settings': {
                'tag_suggestion_count': int.parse(count.text.trim()),
                'tag_half_life_days': int.parse(days.text.trim()),
                'indicators': indicators,
              },
            }
          : {
              'op': 'set_indicator_settings',
              'item_id': widget.itemId,
              'view_id': widget.viewId,
              'expected_parent': oldParent,
              'expected_view': oldView,
              'parent_overrides': parent,
              'view_overrides': local,
            },
      expectedDocument: identity,
    );
    if (!mounted) return;
    if (result != null) {
      Navigator.pop(context);
      return;
    }
    setState(() {
      saving = false;
      error =
          widget.app.error ??
          'Settings could not be saved. Your choices are still here.';
    });
  }

  Widget number(
    TextEditingController controller,
    String label, {
    required int minimum,
  }) => Padding(
    padding: const EdgeInsets.only(bottom: 20),
    child: TextFormField(
      controller: controller,
      enabled: !saving,
      keyboardType: TextInputType.number,
      inputFormatters: [FilteringTextInputFormatter.digitsOnly],
      decoration: InputDecoration(labelText: label, errorMaxLines: 3),
      validator: (text) {
        final value = int.tryParse(text?.trim() ?? '');
        if (value == null || value < minimum || value > 4294967295) {
          return minimum == 0
              ? 'Enter a non-negative whole number.'
              : 'Enter a positive whole number of days.';
        }
        return null;
      },
    ),
  );

  Widget overrides(
    Map<String, dynamic> values,
    Map<String, dynamic> inherited,
    String Function(String) source,
  ) => Column(
    mainAxisSize: MainAxisSize.min,
    children: _indicators.entries.map((field) {
      final enabled = (values[field.key] ?? inherited[field.key]) == true;
      return Padding(
        padding: const EdgeInsets.only(top: 8, bottom: 12),
        child: DropdownButtonFormField<String>(
          key: ValueKey(
            '${identical(values, local) ? 'view' : 'parent'}-${field.key}-${values[field.key]}-${inherited[field.key]}',
          ),
          initialValue: values[field.key] == null
              ? 'inherit'
              : values[field.key] == true
              ? 'on'
              : 'off',
          isExpanded: true,
          decoration: InputDecoration(
            labelText: field.value,
            helperMaxLines: 3,
            helperText: values[field.key] == null
                ? 'From ${source(field.key)}: ${enabled ? 'On' : 'Off'}'
                : 'Override: ${enabled ? 'On' : 'Off'}',
          ),
          items: const [
            DropdownMenuItem(
              value: 'inherit',
              child: Text('Use inherited setting'),
            ),
            DropdownMenuItem(value: 'on', child: Text('On')),
            DropdownMenuItem(value: 'off', child: Text('Off')),
          ],
          onChanged: saving
              ? null
              : (choice) => setState(() {
                  if (choice == 'inherit') {
                    values.remove(field.key);
                  } else if (choice != null) {
                    values[field.key] = choice == 'on';
                  }
                }),
        ),
      );
    }).toList(),
  );

  @override
  Widget build(BuildContext context) {
    final effectiveParent = {...indicators, ...parent};
    final name = itemById(widget.app, widget.itemId ?? -1)['title'];
    final view = asMap(
      asMap(widget.app.document?['views'])['${widget.viewId}'],
    );
    return PopScope<void>(
      canPop: !saving,
      child: EditorDialog(
        title: Text(
          collection ? 'Collection Settings' : 'Summary indicator settings',
        ),
        content: Form(
          key: form,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (error != null)
                Padding(
                  padding: const EdgeInsets.only(bottom: 16),
                  child: Text(
                    error!,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ),
                ),
              if (collection) ...[
                const SectionLabel('Tag suggestions'),
                number(count, 'Suggested unselected tags', minimum: 0),
                number(days, 'Tag usage half-life (days)', minimum: 1),
                const Text(
                  'An assignment has half its influence after this many days. Zero suggestions hides suggestions without hiding selected tags.',
                ),
                const SectionLabel('Default summary indicators'),
                const Text(
                  'Defaults for all parents and views unless individually overridden. Completed / total replaces the plain Total count when Total is enabled.',
                ),
                ..._indicators.entries.map(
                  (field) => SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: Text(field.value),
                    value: indicators[field.key] == true,
                    onChanged: saving
                        ? null
                        : (value) =>
                              setState(() => indicators[field.key] = value),
                  ),
                ),
              ] else ...[
                Text('$name · ${view['name']}'),
                const SizedBox(height: 12),
                const Text(
                  'Each setting inherits independently. Use inherited setting to follow later changes to its defaults. These preferences are separate from task edits.',
                ),
                const SectionLabel('This parent in this view'),
                const Text('Changes here leave other views unchanged.'),
                overrides(
                  local,
                  effectiveParent,
                  (key) => parent[key] == null
                      ? 'collection defaults'
                      : 'shared parent defaults',
                ),
                ExpansionTile(
                  tilePadding: EdgeInsets.zero,
                  title: const Text('Shared parent defaults'),
                  subtitle: const Text(
                    'Apply across views unless that view overrides them',
                  ),
                  children: [
                    overrides(parent, indicators, (_) => 'collection defaults'),
                  ],
                ),
              ],
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: saving ? null : () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: saving ? null : save,
            child: Text(saving ? 'Saving…' : 'Save settings'),
          ),
        ],
      ),
    );
  }
}
