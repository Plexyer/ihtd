import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import 'app_brand.dart';

void showIhtdAbout(BuildContext context) {
  showAboutDialog(
    context: context,
    applicationName: 'IHTD',
    applicationIcon: const IhtdLogo(size: 48),
    applicationLegalese:
        'Copyright (C) 2026 IHTD contributors.\n'
        'GNU AGPL version 3 only. No warranty.\n'
        'Third-party components retain their own licenses.',
    children: [
      const SizedBox(height: 12),
      const SelectableText(
        'Corresponding source and build instructions:\n'
        'https://github.com/Plexyer/ihtd\n'
        'For releases, select the matching vX.Y.Z tag; for development builds, '
        'use the actual source commit.',
      ),
      TextButton(
        onPressed: () async {
          var opened = false;
          try {
            opened = await launchUrl(
              Uri.https('github.com', '/Plexyer/ihtd'),
              mode: LaunchMode.externalApplication,
            );
          } catch (_) {
            /* Leave the source URL available to copy. */
          }
          if (!opened && context.mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text(
                  'Could not open the browser. Copy the source link above.',
                ),
              ),
            );
          }
        },
        child: const Text('Open source repository'),
      ),
    ],
  );
}
