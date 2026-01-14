import 'package:drag_and_drop_lists/drag_and_drop_lists.dart';
import 'package:drag_and_drop_lists/src/animated_ghost_placeholder.dart';
import 'package:flutter/material.dart';

class DragAndDropItemWrapper extends StatefulWidget {
  final DragAndDropItem child;
  final DragAndDropBuilderParameters? parameters;

  const DragAndDropItemWrapper({
    required this.child,
    required this.parameters,
    super.key,
  });

  @override
  State<StatefulWidget> createState() => _DragAndDropItemWrapper();
}

class _DragAndDropItemWrapper extends State<DragAndDropItemWrapper>
    with TickerProviderStateMixin {
  DragAndDropItem? _hoveredDraggable;
  bool _dragging = false;

  // Cached size for feedback offset calculation (only used with drag handle)
  Size? _cachedContainerSize;

  @override
  Widget build(BuildContext context) {
    final params = widget.parameters!;

    // Build the ghost placeholder using opacity animation (no layout thrashing)
    final ghostPlaceholder = AnimatedGhostPlaceholder(
      isVisible: _hoveredDraggable != null,
      height: params.itemHeight,
      opacity: params.itemGhostOpacity,
      duration: Duration(milliseconds: params.itemSizeAnimationDuration),
      child: params.itemGhost ?? _hoveredDraggable?.child,
    );

    // Build the draggable content
    final draggable = _buildDraggable(context, params);

    // Use DragTarget's builder directly to avoid Stack+Positioned.fill overhead
    return DragTarget<DragAndDropItem>(
      builder: (context, candidateData, rejectedData) {
        return Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: params.verticalAlignment,
          children: <Widget>[
            ghostPlaceholder,
            Listener(
              onPointerMove: _onPointerMove,
              onPointerDown: params.onPointerDown,
              onPointerUp: params.onPointerUp,
              child: draggable,
            ),
          ],
        );
      },
      onWillAcceptWithDetails: (details) {
        bool accept = true;
        if (params.itemOnWillAccept != null) {
          accept = params.itemOnWillAccept!(details.data, widget.child);
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
            params.onItemReordered?.call(details.data, widget.child);
            _hoveredDraggable = null;
          });
        }
      },
    );
  }

  Widget _buildDraggable(
    BuildContext context,
    DragAndDropBuilderParameters params,
  ) {
    if (!widget.child.canDrag) {
      // Non-draggable items: show/hide based on hover state
      // Use opacity + visibility for performance (no AnimatedSize)
      return Visibility(
        visible: _hoveredDraggable == null,
        maintainSize: true,
        maintainAnimation: true,
        maintainState: true,
        child: widget.child.child,
      );
    }

    if (params.itemDragHandle != null) {
      return _buildDraggableWithHandle(context, params);
    } else if (params.dragOnLongPress) {
      return _buildLongPressDraggable(context, params);
    } else {
      return _buildSimpleDraggable(context, params);
    }
  }

  Widget _buildDraggableWithHandle(
    BuildContext context,
    DragAndDropBuilderParameters params,
  ) {
    final handle = params.itemDragHandle!;

    // Use MediaQuery for width instead of LayoutBuilder (which doesn't support intrinsic dimensions)
    final screenWidth = MediaQuery.of(context).size.width;
    _cachedContainerSize = Size(
      params.itemDraggingWidth ?? screenWidth,
      params.itemHeight ?? 48.0,
    );

    final feedback = _buildFeedbackWithHandle(context, params, handle);
    final dragHandle = _buildPositionedDragHandle(
      context,
      params,
      handle,
      feedback,
    );

    // Collapse height to 0 when dragging (item visually disappears)
    return ClipRect(
      child: Align(
        alignment: Alignment.topCenter,
        heightFactor: _dragging ? 0.0 : 1.0,
        child: Stack(
          children: [
            widget.child.child,
            dragHandle,
          ],
        ),
      ),
    );
  }

  Widget _buildPositionedDragHandle(
    BuildContext context,
    DragAndDropBuilderParameters params,
    DragHandle handle,
    Widget feedback,
  ) {
    return Positioned(
      right: handle.onLeft ? null : 0,
      left: handle.onLeft ? 0 : null,
      top: handle.verticalAlignment == DragHandleVerticalAlignment.bottom
          ? null
          : 0,
      bottom: handle.verticalAlignment == DragHandleVerticalAlignment.top
          ? null
          : 0,
      child: MouseRegion(
        cursor: SystemMouseCursors.grab,
        child: Draggable<DragAndDropItem>(
          data: widget.child,
          axis: params.axis == Axis.vertical && params.constrainDraggingAxis
              ? Axis.vertical
              : null,
          feedback: Transform.translate(
            offset: _calculateFeedbackOffset(params, handle),
            child: feedback,
          ),
          childWhenDragging: const SizedBox.shrink(),
          onDragStarted: () => _setDragging(true),
          onDragCompleted: () => _setDragging(false),
          onDraggableCanceled: (_, __) => _setDragging(false),
          onDragEnd: (_) => _setDragging(false),
          child: handle,
        ),
      ),
    );
  }

  Widget _buildFeedbackWithHandle(
    BuildContext context,
    DragAndDropBuilderParameters params,
    DragHandle handle,
  ) {
    return SizedBox(
      width: params.itemDraggingWidth ?? _cachedContainerSize?.width,
      child: Material(
        color: Colors.transparent,
        child: Container(
          decoration: params.itemDecorationWhileDragging,
          child: Directionality(
            textDirection: Directionality.of(context),
            child: Stack(
              children: [
                widget.child.child,
                Positioned(
                  right: handle.onLeft ? null : 0,
                  left: handle.onLeft ? 0 : null,
                  top: handle.verticalAlignment ==
                          DragHandleVerticalAlignment.bottom
                      ? null
                      : 0,
                  bottom: handle.verticalAlignment ==
                          DragHandleVerticalAlignment.top
                      ? null
                      : 0,
                  child: handle,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Offset _calculateFeedbackOffset(
    DragAndDropBuilderParameters params,
    DragHandle handle,
  ) {
    final containerWidth = _cachedContainerSize?.width ?? 0;
    final containerHeight =
        params.itemHeight ?? (_cachedContainerSize?.height ?? 48.0);

    // Estimate handle size (use provided dimensions or defaults)
    final handleWidth = handle.child is SizedBox
        ? (handle.child as SizedBox).width ?? 48.0
        : 48.0;
    final handleHeight = handle.child is SizedBox
        ? (handle.child as SizedBox).height ?? 48.0
        : 48.0;

    final xOffset = handle.onLeft ? 0.0 : -containerWidth + handleWidth;
    final yOffset = handle.verticalAlignment == DragHandleVerticalAlignment.bottom
        ? -containerHeight + handleHeight
        : 0.0;

    return Offset(xOffset, yOffset);
  }

  Widget _buildLongPressDraggable(
    BuildContext context,
    DragAndDropBuilderParameters params,
  ) {
    return LongPressDraggable<DragAndDropItem>(
      data: widget.child,
      axis: params.axis == Axis.vertical && params.constrainDraggingAxis
          ? Axis.vertical
          : null,
      feedback: _buildSimpleFeedback(context, params),
      childWhenDragging: const SizedBox.shrink(),
      onDragStarted: () => _setDragging(true),
      onDragCompleted: () => _setDragging(false),
      onDraggableCanceled: (_, __) => _setDragging(false),
      onDragEnd: (_) => _setDragging(false),
      child: widget.child.child,
    );
  }

  Widget _buildSimpleDraggable(
    BuildContext context,
    DragAndDropBuilderParameters params,
  ) {
    return Draggable<DragAndDropItem>(
      data: widget.child,
      axis: params.axis == Axis.vertical && params.constrainDraggingAxis
          ? Axis.vertical
          : null,
      feedback: _buildSimpleFeedback(context, params),
      childWhenDragging: const SizedBox.shrink(),
      onDragStarted: () => _setDragging(true),
      onDragCompleted: () => _setDragging(false),
      onDraggableCanceled: (_, __) => _setDragging(false),
      onDragEnd: (_) => _setDragging(false),
      child: widget.child.child,
    );
  }

  Widget _buildSimpleFeedback(
    BuildContext context,
    DragAndDropBuilderParameters params,
  ) {
    // Use itemDraggingWidth if set, otherwise use screen width as reasonable default
    final width =
        params.itemDraggingWidth ?? MediaQuery.of(context).size.width;

    return SizedBox(
      width: width,
      child: Material(
        color: Colors.transparent,
        child: Container(
          decoration: params.itemDecorationWhileDragging,
          child: Directionality(
            textDirection: Directionality.of(context),
            child: widget.child.feedbackWidget ?? widget.child.child,
          ),
        ),
      ),
    );
  }

  void _setDragging(bool dragging) {
    if (_dragging != dragging && mounted) {
      setState(() {
        _dragging = dragging;
      });
      widget.parameters!.onItemDraggingChanged?.call(widget.child, dragging);
    }
  }

  void _onPointerMove(PointerMoveEvent event) {
    if (_dragging) widget.parameters!.onPointerMove?.call(event);
  }
}
