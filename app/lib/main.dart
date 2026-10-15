import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'ui/app_shell.dart';
import 'ui/app_theme.dart';
import 'src/rust/frb_generated.dart';
import 'services/app_controller.dart';

Future<void> main([List<String> arguments = const []]) async {
  WidgetsFlutterBinding.ensureInitialized();
  await RustLib.init();
  runApp(
    ProviderScope(
      overrides: [
        if (!Platform.isAndroid && arguments.isNotEmpty)
          appProvider.overrideWith(
            (ref) => AppController(initialDocumentPath: arguments.first),
          ),
      ],
      child: const IhtdApp(),
    ),
  );
}

class IhtdApp extends StatelessWidget {
  const IhtdApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'IHTD · Your tasks, connected',
      debugShowCheckedModeBanner: false,
      theme: buildIhtdTheme(),
      home: const AppShell(),
    );
  }
}
