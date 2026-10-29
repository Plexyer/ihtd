import 'dart:async';

import 'package:flutter/material.dart';

/// The barrier delegates to shared policy instead of popping first. Nested
/// pickers/dialogs own their barriers and never commit the editor beneath them.
class GuardedEditorRoute extends DialogRoute<void> {
  GuardedEditorRoute({
    required super.context,
    required WidgetBuilder content,
    required this.outside,
    required Future<void> Function() back,
  }) : super(
         barrierDismissible: false,
         builder: (context) => PopScope<void>(
           canPop: false,
           onPopInvokedWithResult: (didPop, _) {
             if (!didPop) unawaited(back());
           },
           child: content(context),
         ),
       );
  final Future<void> Function() outside;
  @override
  Widget buildModalBarrier() => ModalBarrier(
    color: barrierColor,
    dismissible: true,
    onDismiss: () => unawaited(outside()),
    semanticsLabel: 'Close editor',
  );
}
