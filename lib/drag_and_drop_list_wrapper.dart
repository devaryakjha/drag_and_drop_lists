import 'package:drag_and_drop_lists/collapse_state_manager.dart';
import 'package:drag_and_drop_lists/drag_and_drop_builder_parameters.dart';
import 'package:drag_and_drop_lists/drag_and_drop_list_interface.dart';
import 'package:drag_and_drop_lists/drag_handle.dart';
import 'package:drag_and_drop_lists/src/animated_ghost_placeholder.dart';
import 'package:flutter/material.dart';

/// Enable/disable logging for debugging drag-drop behavior.
/// Controlled via [CollapseStateManager.enableLogging].
void _log(String message) {
  if (CollapseStateManager.enableLogging) {
    debugPrint('[ListWrapper] $message');
  }
}

class DragAndDropListWrapper extends StatefulWidget {
  final DragAndDropListInterface dragAndDropList;
  final DragAndDropBuilderParameters parameters;

  const DragAndDropListWrapper(
      {required this.dragAndDropList, required this.parameters, super.key});

  @override
  State<StatefulWidget> createState() => _DragAndDropListWrapper();
}

class _DragAndDropListWrapper extends State<DragAndDropListWrapper>
    with TickerProviderStateMixin {
  DragAndDropListInterface? _hoveredDraggable;
  bool _dragging = false;

  // Cached size for feedback offset calculation (only used with drag handle)
  Size? _cachedContainerSize;

  @override
  Widget build(BuildContext context) {
    final params = widget.parameters;

    // Build the ghost placeholder using opacity animation (no layout thrashing)
    final ghostPlaceholder = AnimatedGhostPlaceholder(
      isVisible: _hoveredDraggable != null,
      height: params.listHeaderHeight,
      opacity: params.listGhostOpacity,
      duration: Duration(milliseconds: params.listSizeAnimationDuration),
      child: params.listGhost ??
          (params.axis == Axis.vertical
              ? _hoveredDraggable?.generateWidget(params)
              : Container(
                  padding: EdgeInsets.symmetric(
                      horizontal: params.listPadding?.horizontal ?? 0),
                  child: _hoveredDraggable?.generateWidget(params),
                )),
    );

    // Build the draggable content
    final draggable = _buildDraggable(context, params);

    // Use DragTarget's builder directly to avoid Stack+Positioned.fill overhead
    Widget content = DragTarget<DragAndDropListInterface>(
      builder: (context, candidateData, rejectedData) {
        final children = <Widget>[
          ghostPlaceholder,
          Listener(
            onPointerMove: _onPointerMove,
            onPointerDown: params.onPointerDown,
            onPointerUp: params.onPointerUp,
            child: draggable,
          ),
        ];

        return params.axis == Axis.vertical
            ? Column(mainAxisSize: MainAxisSize.min, children: children)
            : Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: children,
              );
      },
      onWillAcceptWithDetails: (details) {
        _log('DragTarget.onWillAcceptWithDetails called');
        _log(
            '  incoming: ${details.data.runtimeType}, key=${details.data.key}');
        _log(
            '  target: ${widget.dragAndDropList.runtimeType}, key=${widget.dragAndDropList.key}');

        bool accept = true;
        if (params.listOnWillAccept != null) {
          accept = params.listOnWillAccept!(details.data, widget.dragAndDropList);
          _log('  listOnWillAccept returned: $accept');
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
        _log('DragTarget.onLeave called');
        _log('  data: ${data?.runtimeType}, key=${data?.key}');
        if (_hoveredDraggable != null) {
          if (mounted) {
            _log('  -> clearing _hoveredDraggable');
            setState(() {
              _hoveredDraggable = null;
            });
          }
        }
      },
      onAcceptWithDetails: (details) {
        _log('DragTarget.onAcceptWithDetails called - THIS IS THE DROP!');
        _log(
            '  dropped: ${details.data.runtimeType}, key=${details.data.key}');
        _log(
            '  onto: ${widget.dragAndDropList.runtimeType}, key=${widget.dragAndDropList.key}');
        _log('  mounted: $mounted');

        if (mounted) {
          _log('  -> calling onListReordered callback');
          setState(() {
            params.onListReordered!(details.data, widget.dragAndDropList);
            _hoveredDraggable = null;
          });
          _log('  onAcceptWithDetails complete');
        } else {
          _log('  -> NOT calling onListReordered, widget not mounted!');
        }
      },
    );

    if (params.listPadding != null) {
      content = Padding(
        padding: params.listPadding!,
        child: content,
      );
    }

    if (params.axis == Axis.horizontal && !params.disableScrolling) {
      content = SingleChildScrollView(child: content);
    }

    return content;
  }

  Widget _buildDraggable(
    BuildContext context,
    DragAndDropBuilderParameters params,
  ) {
    final dragAndDropListContents =
        widget.dragAndDropList.generateWidget(params);

    if (!widget.dragAndDropList.canDrag) {
      return dragAndDropListContents;
    }

    if (params.listDragHandle != null) {
      return _buildDraggableWithHandle(context, params, dragAndDropListContents);
    } else if (params.dragOnLongPress) {
      return _buildLongPressDraggable(context, params, dragAndDropListContents);
    } else {
      return _buildSimpleDraggable(context, params, dragAndDropListContents);
    }
  }

  Widget _buildDraggableWithHandle(
    BuildContext context,
    DragAndDropBuilderParameters params,
    Widget dragAndDropListContents,
  ) {
    final handle = params.listDragHandle!;

    // Use MediaQuery for width instead of LayoutBuilder (which doesn't support intrinsic dimensions)
    final screenWidth = MediaQuery.of(context).size.width;
    _cachedContainerSize = Size(
      params.listDraggingWidth ?? screenWidth,
      params.listHeaderHeight ?? 48.0,
    );

    final dragHandle = MouseRegion(
      cursor: SystemMouseCursors.grab,
      child: handle,
    );

    final feedback = _buildFeedbackWithHandle(
      context,
      params,
      dragAndDropListContents,
      dragHandle,
    );

    // Collapse height to 0 when dragging (list visually disappears)
    return ClipRect(
      child: Align(
        alignment: Alignment.topCenter,
        heightFactor: _dragging ? 0.0 : 1.0,
        child: Stack(
          children: [
            dragAndDropListContents,
            Positioned(
              right: handle.onLeft ? null : 0,
              left: handle.onLeft ? 0 : null,
              top: handle.verticalAlignment == DragHandleVerticalAlignment.bottom
                  ? null
                  : 0,
              bottom: handle.verticalAlignment == DragHandleVerticalAlignment.top
                  ? null
                  : 0,
              child: Draggable<DragAndDropListInterface>(
                data: widget.dragAndDropList,
                axis: _draggableAxis(params),
                feedback: Transform.translate(
                  offset: _calculateFeedbackOffset(params, handle),
                  child: feedback,
                ),
                childWhenDragging: const SizedBox.shrink(),
                onDragStarted: () => _setDragging(true),
                onDragCompleted: () => _setDragging(false),
                onDraggableCanceled: (_, __) => _setDragging(false),
                onDragEnd: (_) => _setDragging(false),
                child: dragHandle,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFeedbackWithHandle(
    BuildContext context,
    DragAndDropBuilderParameters params,
    Widget dragAndDropListContents,
    Widget dragHandle,
  ) {
    final handle = params.listDragHandle!;

    return Material(
      color: Colors.transparent,
      child: Container(
        decoration: params.listDecorationWhileDragging,
        child: SizedBox(
          width: params.listDraggingWidth ?? _cachedContainerSize?.width,
          child: Stack(
            children: [
              Directionality(
                textDirection: Directionality.of(context),
                child: dragAndDropListContents,
              ),
              Positioned(
                right: handle.onLeft ? null : 0,
                left: handle.onLeft ? 0 : null,
                top: handle.verticalAlignment ==
                        DragHandleVerticalAlignment.bottom
                    ? null
                    : 0,
                bottom:
                    handle.verticalAlignment == DragHandleVerticalAlignment.top
                        ? null
                        : 0,
                child: dragHandle,
              ),
            ],
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
        params.listHeaderHeight ?? (_cachedContainerSize?.height ?? 48.0);

    // Estimate handle size (use provided dimensions or defaults)
    final handleWidth = handle.child is SizedBox
        ? (handle.child as SizedBox).width ?? 48.0
        : 48.0;
    final handleHeight = handle.child is SizedBox
        ? (handle.child as SizedBox).height ?? 48.0
        : 48.0;

    final xOffset = handle.onLeft ? 0.0 : -containerWidth + handleWidth;
    final yOffset =
        handle.verticalAlignment == DragHandleVerticalAlignment.bottom
            ? -containerHeight + handleHeight
            : 0.0;

    return Offset(xOffset, yOffset);
  }

  Widget _buildLongPressDraggable(
    BuildContext context,
    DragAndDropBuilderParameters params,
    Widget dragAndDropListContents,
  ) {
    return LongPressDraggable<DragAndDropListInterface>(
      data: widget.dragAndDropList,
      axis: _draggableAxis(params),
      feedback: _buildFeedbackWithoutHandle(context, params, dragAndDropListContents),
      childWhenDragging: const SizedBox.shrink(),
      onDragStarted: () => _setDragging(true),
      onDragCompleted: () => _setDragging(false),
      onDraggableCanceled: (_, __) => _setDragging(false),
      onDragEnd: (_) => _setDragging(false),
      child: dragAndDropListContents,
    );
  }

  Widget _buildSimpleDraggable(
    BuildContext context,
    DragAndDropBuilderParameters params,
    Widget dragAndDropListContents,
  ) {
    return Draggable<DragAndDropListInterface>(
      data: widget.dragAndDropList,
      axis: _draggableAxis(params),
      feedback: _buildFeedbackWithoutHandle(context, params, dragAndDropListContents),
      childWhenDragging: const SizedBox.shrink(),
      onDragStarted: () => _setDragging(true),
      onDragCompleted: () => _setDragging(false),
      onDraggableCanceled: (_, __) => _setDragging(false),
      onDragEnd: (_) => _setDragging(false),
      child: dragAndDropListContents,
    );
  }

  Widget _buildFeedbackWithoutHandle(
    BuildContext context,
    DragAndDropBuilderParameters params,
    Widget dragAndDropListContents,
  ) {
    final width = params.axis == Axis.vertical
        ? (params.listDraggingWidth ?? MediaQuery.of(context).size.width)
        : (params.listDraggingWidth ?? params.listWidth);

    return SizedBox(
      width: width,
      child: Material(
        color: Colors.transparent,
        child: Container(
          decoration: params.listDecorationWhileDragging,
          child: Directionality(
            textDirection: Directionality.of(context),
            child: dragAndDropListContents,
          ),
        ),
      ),
    );
  }

  Axis? _draggableAxis(DragAndDropBuilderParameters params) {
    return params.axis == Axis.vertical && params.constrainDraggingAxis
        ? Axis.vertical
        : null;
  }

  void _setDragging(bool dragging) {
    _log('_setDragging($dragging) called');
    _log(
        '  list: ${widget.dragAndDropList.runtimeType}, key=${widget.dragAndDropList.key}');
    _log('  current _dragging: $_dragging, mounted: $mounted');

    // CRITICAL: Always call the callback when dragging state changes, even if not mounted.
    // When widget is unmounted during drag (e.g., due to reorder rebuild), we still need
    // to notify the collapse manager that drag ended, otherwise _draggingList is never
    // cleared and causes infinite re-collapse loops.
    if (_dragging != dragging) {
      _log('  -> changing _dragging from $_dragging to $dragging');

      // Only call setState if mounted (UI update)
      if (mounted) {
        setState(() {
          _dragging = dragging;
        });
      } else {
        _dragging = dragging;
        _log('  -> (not mounted, skipping setState)');
      }

      // ALWAYS call the callback to ensure drag end is properly handled
      if (widget.parameters.onListDraggingChanged != null) {
        _log('  -> calling onListDraggingChanged callback');
        widget.parameters.onListDraggingChanged!(
            widget.dragAndDropList, dragging);
      } else {
        _log('  -> onListDraggingChanged is null, not calling');
      }
    } else {
      _log('  -> no change needed (_dragging=$_dragging, dragging=$dragging)');
    }
  }

  void _onPointerMove(PointerMoveEvent event) {
    if (_dragging) widget.parameters.onPointerMove!(event);
  }
}
