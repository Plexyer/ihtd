import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'ui/app_shell.dart';
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
    const ink = Color(0xff18334c);
    final scheme = ColorScheme.fromSeed(
      seedColor: const Color(0xff2763a5),
      surface: const Color(0xfff5f7fa),
    );
    return MaterialApp(
      title: 'IHTD · Your tasks, connected',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: scheme,
        scaffoldBackgroundColor: const Color(0xfff5f7fa),
        fontFamily: 'Segoe UI',
        textTheme: const TextTheme(
          headlineMedium: TextStyle(
            fontSize: 28,
            fontWeight: FontWeight.w600,
            color: ink,
          ),
          titleLarge: TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.w600,
            color: ink,
          ),
          bodyMedium: TextStyle(fontSize: 14, color: ink),
        ),
        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: Colors.white,
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 14,
            vertical: 13,
          ),
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
            borderSide: const BorderSide(color: Color(0xffdbe2eb)),
          ),
        ),
        dividerColor: const Color(0xffe1e7ef),
        visualDensity: VisualDensity.standard,
      ),
      home: const AppShell(),
    );
  }
}
