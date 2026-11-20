import 'package:flutter/material.dart';

import '../design/nix_surfaces.dart';

class WorkspaceDragSource extends StatelessWidget {
  const WorkspaceDragSource(
      {super.key, required this.id, required this.label, required this.child});
  final String id;
  final String label;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final feedback = Material(
      elevation: 4,
      borderRadius: BorderRadius.circular(9),
      color: Theme.of(context).colorScheme.surfaceContainerHigh,
      child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 240),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
            child: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis),
          )),
    );
    final ghost = Opacity(opacity: .34, child: child);
    if (MediaQuery.sizeOf(context).width < nixDesktopBreakpoint) {
      return LongPressDraggable<String>(
          data: id, feedback: feedback, childWhenDragging: ghost, child: child);
    }
    return Draggable<String>(
        data: id, feedback: feedback, childWhenDragging: ghost, child: child);
  }
}
