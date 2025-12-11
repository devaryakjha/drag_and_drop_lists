import 'package:drag_and_drop_lists/collapse_state_manager.dart';
import 'package:drag_and_drop_lists/drag_and_drop_builder_parameters.dart';
import 'package:drag_and_drop_lists/drag_and_drop_list_interface.dart';
import 'package:flutter/material.dart';
import 'package:flutter/widgets.dart';

/// Enable/disable logging for debugging drag-drop behavior.
/// Controlled via [CollapseStateManager.enableLogging].
void _log(String message) {
  if (CollapseStateManager.enableLogging) {
    debugPrint('[ListTarget] $message');
  }
}

typedef OnDropOnLastTarget = void Function(
  DragAndDropListInterface newOrReordered,
  DragAndDropListTarget receiver,
);

class DragAndDropListTarget extends StatefulWidget {
  final Widget? child;
  final DragAndDropBuilderParameters parameters;
  final OnDropOnLastTarget onDropOnLastTarget;
  final double lastListTargetSize;

  const DragAndDropListTarget(
      {this.child,
      required this.parameters,
      required this.onDropOnLastTarget,
      this.lastListTargetSize = 110,
      super.key});

  @override
  State<StatefulWidget> createState() => _DragAndDropListTarget();
}

class _DragAndDropListTarget extends State<DragAndDropListTarget>
    with TickerProviderStateMixin {
  DragAndDropListInterface? _hoveredDraggable;

  @override
  Widget build(BuildContext context) {
    Widget visibleContents = Column(
      children: <Widget>[
        AnimatedSize(
          duration: Duration(
              milliseconds: widget.parameters.listSizeAnimationDuration),
          alignment: widget.parameters.axis == Axis.vertical
              ? Alignment.bottomCenter
              : Alignment.centerLeft,
          child: _hoveredDraggable != null
              ? Opacity(
                  opacity: widget.parameters.listGhostOpacity,
                  child: widget.parameters.listGhost ??
                      _hoveredDraggable!.generateWidget(widget.parameters),
                )
              : Container(),
        ),
        widget.child ??
            SizedBox(
              height: widget.parameters.axis == Axis.vertical
                  ? widget.lastListTargetSize
                  : null,
              width: widget.parameters.axis == Axis.horizontal
                  ? widget.lastListTargetSize
                  : null,
            ),
      ],
    );

    if (widget.parameters.listPadding != null) {
      visibleContents = Padding(
        padding: widget.parameters.listPadding!,
        child: visibleContents,
      );
    }

    if (widget.parameters.axis == Axis.horizontal) {
      visibleContents = SingleChildScrollView(child: visibleContents);
    }

    return Stack(
      children: <Widget>[
        visibleContents,
        Positioned.fill(
          child: DragTarget<DragAndDropListInterface>(
            builder: (context, candidateData, rejectedData) {
              if (candidateData.isNotEmpty) {}
              return Container();
            },
            onWillAcceptWithDetails: (details) {
              _log('onWillAcceptWithDetails called (last target)');
              _log('  incoming: ${details.data.runtimeType}, key=${details.data.key}');

              bool accept = true;
              if (widget.parameters.listTargetOnWillAccept != null) {
                accept =
                    widget.parameters.listTargetOnWillAccept!(details.data, widget);
                _log('  listTargetOnWillAccept returned: $accept');
              }
              if (accept && mounted) {
                _log('  -> accepting, setting _hoveredDraggable');
                setState(() {
                  _hoveredDraggable = details.data;
                });
              }
              return accept;
            },
            onLeave: (data) {
              _log('onLeave called (last target)');
              _log('  data: ${data?.runtimeType}, key=${data?.key}');
              if (mounted) {
                setState(() {
                  _hoveredDraggable = null;
                });
              }
            },
            onAcceptWithDetails: (details) {
              _log('onAcceptWithDetails called (last target) - THIS IS THE DROP!');
              _log('  dropped: ${details.data.runtimeType}, key=${details.data.key}');
              _log('  mounted: $mounted');

              if (mounted) {
                _log('  -> calling onDropOnLastTarget callback');
                setState(() {
                  widget.onDropOnLastTarget(details.data, widget);
                  _hoveredDraggable = null;
                });
                _log('  onAcceptWithDetails complete');
              } else {
                _log('  -> NOT calling onDropOnLastTarget, widget not mounted!');
              }
            },
          ),
        ),
      ],
    );
  }
}
