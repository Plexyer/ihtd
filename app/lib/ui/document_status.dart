import 'package:flutter/material.dart';

import '../services/document_save_coordinator.dart';
import '../services/app_controller.dart';

Future<bool> confirmDocumentAction(
  BuildContext context,
  String title,
  String message,
) async =>
    await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: SingleChildScrollView(child: Text(message)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Confirm'),
          ),
        ],
      ),
    ) ??
    false;

class DocumentStatus extends StatelessWidget {
  const DocumentStatus({super.key, required this.app});
  final AppController app;

  @override
  Widget build(BuildContext context) {
    final storage = app.documentServices;
    final issue = app.documentIssue;
    final red = storage.severe;
    final scheme = Theme.of(context).colorScheme;
    return Material(
      color: issue
          ? (red ? scheme.errorContainer : const Color(0xffffefbd))
          : Colors.transparent,
      child: InkWell(
        onTap: () => showDialog<void>(
          context: context,
          builder: (_) => DocumentIssueDialog(app: app),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Row(
            children: [
              Icon(
                issue
                    ? (red ? Icons.error_outline : Icons.warning_amber_rounded)
                    : Icons.save_outlined,
                size: 19,
                color: red ? scheme.onErrorContainer : null,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  app.status,
                  style: TextStyle(color: red ? scheme.onErrorContainer : null),
                ),
              ),
              const Icon(Icons.info_outline, size: 18),
            ],
          ),
        ),
      ),
    );
  }
}

class DocumentIssueDialog extends StatefulWidget {
  const DocumentIssueDialog({super.key, required this.app});
  final AppController app;
  @override
  State<DocumentIssueDialog> createState() => _DocumentIssueDialogState();
}

class _DocumentIssueDialogState extends State<DocumentIssueDialog> {
  bool extended = false;
  bool exporting = false;
  String? result;

  Future<void> export() async {
    if (extended &&
        !await confirmDocumentAction(
          context,
          'Include additional information?',
          'The exported log will include the collection’s current/previous filenames, provider name, size, modification time and provider capability flags. '
              'These can reveal personal file or provider information. Full document URIs, task titles, notes, contents and credentials are not collected. '
              'Review the exported file before sharing it.',
        )) {
      return;
    }
    setState(() {
      exporting = true;
      result = null;
    });
    await widget.app.exportDiagnostics(extended: extended);
    if (mounted) {
      setState(() {
        exporting = false;
        result =
            widget.app.documentActionNotice ??
            widget.app.error ??
            'Export dialog completed. No log is uploaded automatically.';
      });
    }
  }

  Future<void> retained() async {
    final saved = await widget.app.documentServices.retainedCollections();
    if (!mounted) return;
    final choice = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Retained working copies'),
        content: SizedBox(
          width: 420,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: saved.isEmpty
                  ? [const Text('No other retained working copies.')]
                  : [
                      for (final item in saved)
                        ListTile(
                          title: Text('${item['name'] ?? 'Collection'}'),
                          subtitle: Text(
                            item['pending'] == true ||
                                    item['localDirty'] == true
                                ? 'Pending local edits retained'
                                : 'Retained local copy',
                          ),
                          onTap: () => Navigator.pop(context, item),
                        ),
                    ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Close'),
          ),
        ],
      ),
    );
    if (choice != null) await widget.app.restoreRetained(choice);
  }

  Future<void> migrationRecovery(DocumentSaveCoordinator storage) async {
    late List<Map<String, dynamic>> attempts;
    try {
      attempts = await storage.migrations.recoveryAttempts();
    } catch (_) {
      if (mounted) {
        setState(
          () => result = 'Recovery details could not be read. Check local storage; existing files have not been changed.',
        );
      }
      return;
    }
    if (!mounted) return;
    await showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Upgrade recovery files'),
        content: SizedBox(
          width: 520,
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'These private originals and candidates are retained. Open a verified backup through Open collection to inspect it separately. Export copies before replacing any changed external file.',
                ),
                for (final attempt in attempts) ...[
                  SelectableText(
                    "Attempt: ${attempt['id']}\nStage: ${attempt['stage']}\n"
                    "${[for (final b in (attempt['backups'] as List? ?? []))
                      if (b['verified'] == true) 'Backup: ${b['reference']['locator']}'].join('\n')}\n",
                  ),
                  for (final entry in <String, String?>{
                    'original':
                        (attempt['original'] as Map?)?['path'] as String? ??
                        attempt['metadataSource'] as String?,
                    'external snapshot': attempt['externalSnapshot'] as String?,
                    for (
                      var i = 0;
                      i < (attempt['candidates'] as List? ?? []).length;
                      i++
                    )
                      'candidate ${i + 1}':
                          attempt['candidates'][i]['path'] as String?,
                    'recovery':
                        (attempt['original'] as Map?)?['recoveryPath']
                            as String?,
                  }.entries)
                    if (entry.value != null)
                      TextButton(
                        onPressed: () =>
                            widget.app.exportMigrationFile(entry.value!),
                        child: Text('Save ${entry.key} as a separate copy…'),
                      ),
                ],
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: widget.app,
    builder: (context, _) {
      final app = widget.app;
      final storage = app.documentServices;
      return AlertDialog(
        title: const Text('File connection and saving'),
        content: SizedBox(
          width: 520,
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  storage.summary,
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 12),
                Text(storage.explanation),
                if (storage.migrations.hasIssue) ...[
                  for (final location in storage.migrations.backupLocations)
                    SelectableText('Verified backup: $location'),
                  TextButton(
                    onPressed: app.busy
                        ? null
                        : app.chooseMigrationBackupFolder,
                    child: const Text('Choose authorized backup folder…'),
                  ),
                  TextButton(
                    onPressed: app.busy
                        ? null
                        : () => migrationRecovery(storage),
                    child: const Text('Upgrade recovery files…'),
                  ),
                ],
                if (app.error != null) ...[
                  const SizedBox(height: 12),
                  Text(app.error!),
                ],
                if (app.documentActionNotice != null) ...[
                  const SizedBox(height: 12),
                  Text(app.documentActionNotice!),
                ],
                const SizedBox(height: 16),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    if ((storage.hasIssue || storage.pending) &&
                        !storage.migrations.hasIssue)
                      FilledButton(
                        onPressed: app.busy
                            ? null
                            : () => app.reconnectDocument(),
                        child: Text(
                          storage.connection == DocumentConnection.renamed
                              ? 'Confirm renamed file…'
                              : 'Retry / confirm file…',
                        ),
                      ),
                    OutlinedButton(
                      onPressed: app.busy
                          ? null
                          : () => app.reconnectDocument(selectFile: true),
                      child: const Text('Select file to reconnect…'),
                    ),
                    OutlinedButton(
                      onPressed: app.busy ? null : app.saveAs,
                      child: const Text('Save a copy…'),
                    ),
                    TextButton(
                      onPressed: app.busy ? null : app.openDocument,
                      child: const Text('Open external version…'),
                    ),
                  ],
                ),
                ExpansionTile(
                  title: const Text('Advanced details'),
                  tilePadding: EdgeInsets.zero,
                  children: [
                    SelectableText(
                      'Connection: ${storage.connection.name}\nPending edits: ${storage.pending}\n'
                      'Local persistence confirmed: ${storage.localDurable}\n'
                      'Private save awaiting retry: ${storage.localDirty}\n'
                      'Last failure code: ${storage.lastFailure ?? 'none'}\n'
                      'Metadata is provider supplied; timestamps and capability flags may be absent or stale.',
                    ),
                    const SizedBox(height: 12),
                    const Text(
                      'Default logs omit task contents, filenames, paths and document identifiers. Logs stay local until you choose to share them.',
                    ),
                    CheckboxListTile(
                      contentPadding: EdgeInsets.zero,
                      title: const Text('Include additional file information'),
                      subtitle: const Text(
                        'Names and provider metadata; confirmation required.',
                      ),
                      value: extended,
                      onChanged: exporting
                          ? null
                          : (value) =>
                                setState(() => extended = value ?? false),
                    ),
                    TextButton.icon(
                      onPressed: exporting || app.busy ? null : export,
                      icon: const Icon(Icons.download_outlined),
                      label: const Text('Export diagnostic log…'),
                    ),
                    TextButton(
                      onPressed: app.busy ? null : retained,
                      child: const Text('Retained working copies…'),
                    ),
                    if (!storage.migrations.hasIssue)
                      TextButton(
                        onPressed: app.busy
                            ? null
                            : () => migrationRecovery(storage),
                        child: const Text('Upgrade backups and recovery…'),
                      ),
                    if (result != null) Text(result!),
                  ],
                ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Close'),
          ),
        ],
      );
    },
  );
}
