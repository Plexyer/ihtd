import 'package:flutter/material.dart';

import 'app_theme.dart';

/// Shared artwork. Platform icons are generated from the same canonical SVG.
class IhtdLogo extends StatelessWidget {
  const IhtdLogo({super.key, this.size = 32});
  final double size;
  @override
  Widget build(BuildContext context) => Image.asset(
    'assets/branding/ihtd.png',
    width: size,
    height: size,
    semanticLabel: 'IHTD connected tasks logo',
    filterQuality: FilterQuality.high,
  );
}

/// Only shown while real initialization is pending; no minimum splash delay.
class IhtdStartupScreen extends StatelessWidget {
  const IhtdStartupScreen({super.key, this.failed = false});
  final bool failed;
  @override
  Widget build(BuildContext context) => AnnotatedRegion(
    value: surfaceOverlays(
      top: AppSurfaces.of(context).header,
      bottom: AppSurfaces.of(context).header,
    ),
    child: Scaffold(
      backgroundColor: AppSurfaces.of(context).header,
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const IhtdLogo(size: 128),
                const SizedBox(height: 12),
                const Text(
                  'IHTD',
                  style: TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 1.6,
                  ),
                ),
                const SizedBox(height: 24),
                if (failed)
                  const Text(
                    'IHTD could not start. Please restart the app.',
                    textAlign: TextAlign.center,
                  )
                else
                  const SizedBox(
                    width: 24,
                    height: 24,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      semanticsLabel: 'Opening IHTD',
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    ),
  );
}
