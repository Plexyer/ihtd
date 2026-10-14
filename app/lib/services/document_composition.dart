import 'dart:io';

import 'android_documents.dart';
import 'document_save_coordinator.dart';
import 'filesystem_documents.dart';

/// Only the composition layer selects the operating-system implementation.
DocumentSaveCoordinator composeDocumentServices(
  Future<String> Function(String) command,
) => DocumentSaveCoordinator(
  adapter: Platform.isAndroid
      ? AndroidDocumentAdapter()
      : FilesystemDocumentAdapter(command),
);
