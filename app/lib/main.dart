import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'ui/app_shell.dart';
import 'ui/app_theme.dart';
import 'ui/app_brand.dart';
import 'src/rust/frb_generated.dart';
import 'services/app_controller.dart';

Future<void> main([List<String> arguments = const []]) async {
  WidgetsFlutterBinding.ensureInitialized();
  final initialization = RustLib.init();
  runApp(
    ProviderScope(
      overrides: [
        if (!Platform.isAndroid && arguments.isNotEmpty)
          appProvider.overrideWith(
            (ref) => AppController(initialDocumentPath: arguments.first),
          ),
      ],
      child: IhtdApp(initialization: initialization),
    ),
  );
}

class IhtdApp extends StatelessWidget {
  const IhtdApp({super.key, this.initialization});
  final Future<void>? initialization;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'IHTD · Your tasks, connected',
      debugShowCheckedModeBanner: false,
      theme: buildIhtdTheme(),
      home: initialization == null
          ? const AppShell()
          : FutureBuilder<void>(
              future: initialization,
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.done &&
                    !snapshot.hasError) {
                  return const AppShell();
                }
                return IhtdStartupScreen(failed: snapshot.hasError);
              },
            ),
    );
  }
}
