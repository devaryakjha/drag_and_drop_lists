import 'package:drag_and_drop_lists/drag_and_drop_list_interface.dart';
import 'package:drag_and_drop_lists/drag_and_drop_lists.dart';
import 'package:drag_and_drop_lists/src/animated_ghost_placeholder.dart';
import 'package:flutter/material.dart';

class DragAndDropItemTarget extends StatefulWidget {
  final Widget child;
  final DragAndDropListInterface? parent;
  final DragAndDropBuilderParameters parameters;
  final OnItemDropOnLastTarget onReorderOrAdd;

  const DragAndDropItemTarget({
    required this.child,
    required this.onReorderOrAdd,
    required this.parameters,
    this.parent,
    super.key,
  });

  @override
  State<StatefulWidget> createState() => _DragAndDropItemTarget();
}

class _DragAndDropItemTarget extends State<DragAndDropItemTarget>
    with TickerProviderStateMixin {
  DragAndDropItem? _hoveredDraggable;

  @override
  Widget build(BuildContext context) {
    final params = widget.parameters;

    // Build the ghost placeholder using opacity animation (no layout thrashing)
    final ghostPlaceholder = AnimatedGhostPlaceholder(
      isVisible: _hoveredDraggable != null,
      height: params.itemHeight,
      opacity: params.itemGhostOpacity,
      duration: Duration(milliseconds: params.itemSizeAnimationDuration),
      child: params.itemGhost ?? _hoveredDraggable?.child,
    );

    // Use DragTarget's builder directly to avoid Stack+Positioned.fill overhead
    return DragTarget<DragAndDropItem>(
      builder: (context, candidateData, rejectedData) {
        return Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: params.verticalAlignment,
          children: <Widget>[
            ghostPlaceholder,
            widget.child,
          ],
        );
      },
      onWillAcceptWithDetails: (details) {
        bool accept = true;
        if (params.itemTargetOnWillAccept != null) {
          accept = params.itemTargetOnWillAccept!(details.data, widget);
        }
        if (accept && mounted) {
          setState(() {
            _hoveredDraggable = details.data;
          });
        }
        return accept;
      },
      onLeave: (data) {
        if (mounted) {
          setState(() {
            _hoveredDraggable = null;
          });
        }
      },
      onAcceptWithDetails: (details) {
        if (mounted) {
          setState(() {
            widget.onReorderOrAdd(details.data, widget.parent!, widget);
            _hoveredDraggable = null;
          });
        }
      },
    );
  }
}
