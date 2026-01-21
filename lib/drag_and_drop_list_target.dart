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
              ? Alignment.topCenter
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

/// Wraps [DragAndDropListTarget] to expand it to fill remaining viewport space.
///
/// Used in sliver mode when auto-collapse is active and a list is being dragged.
/// This makes it easier to drop lists at the last position when there's whitespace
/// below the collapsed lists.
///
/// The caller is responsible for determining when to use this wrapper - this
/// widget always applies expansion when instantiated.
class ExpandedLastListTarget extends StatelessWidget {
  /// The [DragAndDropListTarget] to wrap with expanded height.
  final DragAndDropListTarget child;

  /// The scroll controller used to calculate viewport dimensions.
  ///
  /// Required to determine how much vertical space remains in the viewport
  /// for intelligent target sizing during drag operations.
  final ScrollController scrollController;

  const ExpandedLastListTarget({
    required this.child,
    required this.scrollController,
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final expandedHeight = _calculateExpandedHeight();

        return SizedBox(
          height: expandedHeight,
          child: child,
        );
      },
    );
  }

  double _calculateExpandedHeight() {
    // Minimum height is the original target size
    final minHeight = child.lastListTargetSize;

    // Fall back to minimum height if scroll controller not attached
    if (!scrollController.hasClients) {
      return minHeight;
    }

    final position = scrollController.position;
    final viewportHeight = position.viewportDimension;
    final maxScrollExtent = position.maxScrollExtent;

    // Only expand when content doesn't fill the viewport (maxScrollExtent is small).
    // This means there's genuine visible whitespace that can't be scrolled away.
    //
    // When maxScrollExtent is large, the content is scrollable and there's no
    // permanent whitespace - expanding would cause overscroll issues.
    //
    // We use minHeight as the threshold: if maxScrollExtent is less than the
    // default target size, there's whitespace we should fill.
    if (maxScrollExtent < minHeight) {
      // Content is shorter than viewport. Expand to fill the visible whitespace.
      // The whitespace equals: viewportHeight - (current content height)
      // Since content height ≈ maxScrollExtent + viewportHeight - currentTargetHeight,
      // and we want to fill to viewport, expand by the difference.
      final expandedHeight = viewportHeight - maxScrollExtent;
      return expandedHeight > minHeight ? expandedHeight : minHeight;
    }

    // Content fills the viewport - use minimum height to avoid overscroll
    return minHeight;
  }
}
