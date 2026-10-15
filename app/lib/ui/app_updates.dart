import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../services/app_controller.dart';
import '../services/update_composition.dart';
import '../services/update_coordinator.dart';

class AppUpdateButton extends ConsumerWidget {
  const AppUpdateButton({super.key, required this.app});
  final AppController app;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final updates = ref.watch(updateProvider);
    if (updates.candidate == null) return const SizedBox.shrink();
    return UpdateIndicator(
      updates: updates,
      onPressed: () async {
        if (updates.phase == UpdatePhase.ready) {
          await updates.install(app.prepareForUpdate);
          if (context.mounted && updates.message != null) {
            ScaffoldMessenger.of(context)
                .showSnackBar(SnackBar(content: Text(updates.message!)));
          }
        } else {
          await showUpdateDetails(context, updates);
        }
      },
    );
  }
}

class UpdateIndicator extends StatefulWidget {
  const UpdateIndicator({
    super.key,
    required this.updates,
    required this.onPressed,
  });
  final UpdateCoordinator updates;
  final VoidCallback onPressed;
  @override
  State<UpdateIndicator> createState() => _UpdateIndicatorState();
}

class _UpdateIndicatorState extends State<UpdateIndicator>
    with SingleTickerProviderStateMixin {
  late final AnimationController motion = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1300),
  );
  @override
  void dispose() {
    motion.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final u = widget.updates;
    final downloading =
        u.phase == UpdatePhase.downloading || u.phase == UpdatePhase.verifying;
    final ready = u.phase == UpdatePhase.ready;
    final animate = downloading && !MediaQuery.disableAnimationsOf(context);
    if (animate && !motion.isAnimating) motion.repeat();
    if (!animate && motion.isAnimating) motion.stop();
    final label = ready
        ? 'Install update'
        : downloading
        ? (u.phase == UpdatePhase.verifying
              ? 'Verifying update'
              : 'Downloading update${u.progress == null ? '' : ' ${(100 * u.progress!).round()}%'}')
        : u.phase == UpdatePhase.error
        ? 'Update failed. Retry'
        : 'Update available';
    return Semantics(
      label: label,
      button: true,
      child: IconButton(
        tooltip: label,
        onPressed: widget.onPressed,
        icon: AnimatedBuilder(
          animation: motion,
          builder: (context, _) => SizedBox(
            width: 32,
            height: 32,
            child: Stack(
              alignment: Alignment.center,
              children: [
                DecoratedBox(
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: ready
                        ? const Color(0xffe0f3e4)
                        : const Color(0xffe0edff),
                  ),
                  child: const SizedBox.expand(),
                ),
                if (downloading)
                  Transform.rotate(
                    angle: animate ? motion.value * math.pi * 2 : 0,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      value: u.progress ?? .3,
                      color: const Color(0xff2763a5),
                    ),
                  ),
                Transform.translate(
                  offset: Offset(0, animate ? (motion.value - .5) * 5 : 0),
                  child: Icon(
                    ready
                        ? Icons.check
                        : u.phase == UpdatePhase.error
                        ? Icons.error_outline
                        : Icons.arrow_downward,
                    size: 22,
                    color: ready
                        ? const Color(0xff26743c)
                        : animate
                        ? Color.lerp(
                            const Color(0xff2763a5),
                            const Color(0xff70b9f7),
                            motion.value,
                          )
                        : const Color(0xff2763a5),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

Future<void> showUpdateDetails(
  BuildContext context,
  UpdateCoordinator updates,
) async {
  final action = await showDialog<String>(
    context: context,
    builder: (context) => ListenableBuilder(
      listenable: updates,
      builder: (context, _) {
        final c = updates.candidate;
        final active =
            updates.phase == UpdatePhase.downloading ||
            updates.phase == UpdatePhase.verifying;
        return AlertDialog(
          title: const Text('IHTD updates'),
          content: SizedBox(
            width: 420,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (updates.installed != null)
                    Text(
                      'Installed: ${updates.installed!.version} (build ${updates.installed!.build})',
                    ),
                  if (c != null) ...[
                    const SizedBox(height: 12),
                    Text(
                      'Available: ${c.version} (build ${c.build})',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    Text(
                      '${(c.size / 1048576).toStringAsFixed(1)} MB · ${c.platform}',
                    ),
                    const SizedBox(height: 12),
                    SelectableText(
                      c.notes.isEmpty ? 'No release notes provided.' : c.notes,
                    ),
                    if (!updates.platform.canInstall)
                      const Padding(
                        padding: EdgeInsets.only(top: 12),
                        child: Text(
                          'Desktop package signing is not configured yet. Download and install manually from the release page.',
                        ),
                      ),
                  ],
                  if (updates.message != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 12),
                      child: Text(updates.message!),
                    ),
                  if (active)
                    Padding(
                      padding: const EdgeInsets.only(top: 12),
                      child: Text(
                        updates.phase == UpdatePhase.verifying
                            ? 'Verifying download…'
                            : 'Downloading in the background…',
                      ),
                    ),
                  const SizedBox(height: 12),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Check automatically'),
                    subtitle: const Text(
                      'At most once a day. Checks contact GitHub; your collections are never sent.',
                    ),
                    value: updates.automatic,
                    onChanged: updates.setAutomatic,
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
            if (c == null)
              TextButton(
                onPressed: updates.phase == UpdatePhase.checking
                    ? null
                    : () => updates.check(),
                child: Text(
                  updates.phase == UpdatePhase.checking
                      ? 'Checking…'
                      : 'Check now',
                ),
              ),
            if (c != null &&
                !active &&
                updates.phase != UpdatePhase.ready &&
                updates.phase != UpdatePhase.checking)
              FilledButton(
                onPressed: () => Navigator.pop(
                  context,
                  updates.platform.canInstall ? 'download' : 'page',
                ),
                child: Text(
                  updates.platform.canInstall
                      ? (updates.phase == UpdatePhase.error
                            ? 'Retry download'
                            : 'Download')
                      : 'Open release page',
                ),
              ),
          ],
        );
      },
    ),
  );
  // User confirmation closes the popup before native work and animation start.
  if (action == 'download') await updates.download();
  if (action == 'page') await updates.openRelease();
}
