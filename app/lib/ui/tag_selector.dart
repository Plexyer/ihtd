import 'dart:convert';

import 'package:flutter/material.dart';

import '../services/app_controller.dart';
import 'editor_dialog.dart';
import 'shared.dart';

List<Map<String, dynamic>> _tags(AppController app) =>
    documentValues(app, 'tags')..sort((a, b) {
      final byName = '${a['name']}'.toLowerCase().compareTo(
        '${b['name']}'.toLowerCase(),
      );
      return byName != 0
          ? byName
          : intValue(a['id']).compareTo(intValue(b['id']));
    });

/// Shared task/folder selector. Chips change only the current editor draft.
class TagSelector extends StatefulWidget {
  const TagSelector({
    super.key,
    required this.app,
    required this.sessionId,
    required this.selected,
    required this.disabled,
  });
  final AppController app;
  final String sessionId;
  final List<int> selected;
  final bool disabled;
  @override
  State<TagSelector> createState() => _TagSelectorState();
}

class _TagSelectorState extends State<TagSelector> {
  List<int>? order;
  String? error;
  String? selectionError;
  String signature = '';
  int generation = 0;

  String get currentSignature => jsonEncode([
    widget.sessionId,
    widget.app.editIdentity.workingPath,
    widget.app.editIdentity.documentId,
    // Accepted mutations advance the revision; private keystrokes don't. Avoid
    // serializing the collection's entire usage history on every editor build.
    widget.app.document?['revision'],
    widget.app.collectionSettings['tag_half_life_days'],
  ]);
  @override
  void initState() {
    super.initState();
    schedule();
  }

  @override
  void didUpdateWidget(TagSelector oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (signature != currentSignature) schedule();
  }

  void schedule() {
    signature = currentSignature;
    final ticket = ++generation;
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted || ticket != generation) return;
      final app = widget.app, owner = widget.app.editIdentity;
      final session = widget.sessionId;
      final result = await app.rankedTags(owner);
      if (!mounted ||
          ticket != generation ||
          app.editIdentity != owner ||
          app.itemDraft?.sessionId != session) {
        return;
      }
      setState(() {
        order = result;
        error = result == null ? 'Tag suggestions could not be loaded.' : null;
      });
    });
  }

  void change(int id, bool selected) {
    final ids = widget.selected.toSet();
    selected ? ids.add(id) : ids.remove(id);
    widget.app.changeItemDraft(
      'tag_ids',
      ids.toList()..sort(),
      sessionId: widget.sessionId,
    );
  }

  Future<void> selectOther() async {
    setState(() => selectionError = null);
    final app = widget.app, owner = widget.app.editIdentity;
    final session = widget.sessionId;
    final tagBaseline = jsonEncode(app.document?['tags']);
    final selectionBaseline = List<int>.from(widget.selected)..sort();
    final selected = await showDialog<List<int>>(
      context: context,
      builder: (_) => _TagPicker(tags: _tags(app), selected: widget.selected),
    );
    if (!mounted ||
        selected == null ||
        app.editIdentity != owner ||
        app.itemDraft?.sessionId != session) {
      return;
    }
    final currentSelection = List<int>.from(
      app.itemDraft!.values['tag_ids'] as List,
    )..sort();
    if (tagBaseline != jsonEncode(app.document?['tags']) ||
        jsonEncode(selectionBaseline) != jsonEncode(currentSelection)) {
      setState(
        () => selectionError = 'Tags changed while selecting. Open Select other again to review them.',
      );
      return;
    }
    app.changeItemDraft('tag_ids', selected, sessionId: session);
  }

  @override
  Widget build(BuildContext context) {
    final message = selectionError ?? error;
    final selected = widget.selected.toSet();
    final tags = _tags(widget.app);
    final byId = {for (final tag in tags) intValue(tag['id']): tag};
    final limit =
        (widget.app.collectionSettings['tag_suggestion_count'] as num?)
            ?.toInt() ??
        0;
    final suggestions = (order ?? <int>[])
        .where((id) => !selected.contains(id) && byId.containsKey(id))
        .take(limit);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        if (selected.isEmpty)
          const Text(
            'No tags selected',
            style: TextStyle(color: Color(0xff748498)),
          ),
        Wrap(
          spacing: 6,
          runSpacing: 6,
          children: [
            for (final tag in tags.where(
              (tag) => selected.contains(intValue(tag['id'])),
            ))
              FilterChip(
                key: ValueKey('selected-tag-${tag['id']}'),
                label: Text('${tag['name']}'),
                selected: true,
                onSelected: widget.disabled
                    ? null
                    : (_) => change(intValue(tag['id']), false),
              ),
          ],
        ),
        const Divider(height: 20),
        Wrap(
          spacing: 6,
          runSpacing: 6,
          children: [
            for (final id in suggestions)
              FilterChip(
                key: ValueKey('suggested-tag-$id'),
                label: Text('${byId[id]!['name']}'),
                selected: false,
                onSelected: widget.disabled ? null : (_) => change(id, true),
              ),
            ActionChip(
              label: const Text('Select other…'),
              onPressed: widget.disabled ? null : selectOther,
            ),
          ],
        ),
        if (message != null)
          Row(
            children: [
              Flexible(
                child: Text(
                  message,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              ),
              TextButton(
                onPressed: widget.disabled
                    ? null
                    : selectionError != null
                    ? selectOther
                    : schedule,
                child: Text(selectionError != null ? 'Select again' : 'Retry'),
              ),
            ],
          ),
      ],
    );
  }
}

class _TagPicker extends StatefulWidget {
  const _TagPicker({required this.tags, required this.selected});
  final List<Map<String, dynamic>> tags;
  final List<int> selected;
  @override
  State<_TagPicker> createState() => _TagPickerState();
}

class _TagPickerState extends State<_TagPicker> {
  late final selected = widget.selected.toSet();
  String query = '';
  @override
  Widget build(BuildContext context) {
    final tags = widget.tags
        .where(
          (t) => '${t['name']}'.toLowerCase().contains(query.toLowerCase()),
        )
        .toList();
    return EditorDialog(
      title: const Text('Select tags'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          TextField(
            autofocus: true,
            decoration: const InputDecoration(
              labelText: 'Search tags',
              prefixIcon: Icon(Icons.search),
            ),
            onChanged: (value) => setState(() => query = value),
          ),
          const SizedBox(height: 12),
          Text('${selected.length} selected'),
          const SizedBox(height: 8),
          SizedBox(
            height: 280,
            child: tags.isEmpty
                ? const Center(child: Text('No matching tags'))
                : ListView.builder(
                    itemCount: tags.length,
                    itemBuilder: (_, index) {
                      final tag = tags[index], id = intValue(tags[index]['id']);
                      final duplicate =
                          widget.tags
                              .where((t) => t['name'] == tag['name'])
                              .length >
                          1;
                      return CheckboxListTile(
                        key: ValueKey('pick-tag-$id'),
                        contentPadding: EdgeInsets.zero,
                        title: Text(
                          '${tag['name']}${duplicate ? ' (#$id)' : ''}',
                        ),
                        value: selected.contains(id),
                        onChanged: (on) => setState(() {
                          on == true ? selected.add(id) : selected.remove(id);
                        }),
                      );
                    },
                  ),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(context, selected.toList()..sort()),
          child: const Text('Done'),
        ),
      ],
    );
  }
}
