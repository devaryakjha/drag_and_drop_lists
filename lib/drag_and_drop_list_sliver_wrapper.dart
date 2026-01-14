import 'package:drag_and_drop_lists/collapse_state_manager.dart';
import 'package:drag_and_drop_lists/drag_and_drop_builder_parameters.dart';
import 'package:drag_and_drop_lists/drag_and_drop_item.dart';
import 'dart:async';

import 'package:drag_and_drop_lists/drag_and_drop_item_target.dart';
import 'package:drag_and_drop_lists/drag_and_drop_item_wrapper.dart';
import 'package:drag_and_drop_lists/drag_and_drop_list_interface.dart';
import 'package:drag_and_drop_lists/drag_handle.dart';
import 'package:drag_and_drop_lists/measure_size.dart';
import 'package:flutter/material.dart';
import 'package:sliver_tools/sliver_tools.dart';

void _log(String message) {
  if (CollapseStateManager.enableLogging) {
    debugPrint('[SliverListWrapper] $message');
  }
}

/// A sliver-based wrapper for [DragAndDropListInterface] that supports pinned headers.
///
/// This widget renders each list as a [MultiSliver] containing:
/// - A ghost placeholder sliver (appears above header when another list hovers)
/// - A [SliverPinnedHeader] for the list header (stays pinned while scrolling)
/// - A [SliverToBoxAdapter] for the collapsible body content
///
/// When multiple lists use this wrapper inside a parent [MultiSliver] with
/// `pushPinnedChildren: true`, the pinned headers will stack and push each other.
class DragAndDropListSliverWrapper extends StatefulWidget {
  final DragAndDropListInterface dragAndDropList;
  final DragAndDropBuilderParameters parameters;

  const DragAndDropListSliverWrapper({
    required this.dragAndDropList,
    required this.parameters,
    super.key,
  });

  @override
  State<DragAndDropListSliverWrapper> createState() =>
      _DragAndDropListSliverWrapperState();
}

class _DragAndDropListSliverWrapperState
    extends State<DragAndDropListSliverWrapper> with TickerProviderStateMixin {
  DragAndDropListInterface? _hoveredDraggable;
  bool _dragging = false;
  Size _containerSize = Size.zero;
  Size _dragHandleSize = Size.zero;
  Timer? _expansionTimer;
  Timer? _leaveDebounceTimer;

  // Animation controller for expand/collapse
  late AnimationController _expandController;
  late Animation<double> _expandAnimation;

  @override
  void initState() {
    super.initState();

    final list = widget.dragAndDropList;
    final params = widget.parameters;

    // Initialize animation controller
    final isExpanded =
        list is DragAndDropListExpansionInterface ? list.isExpanded : true;

    _expandController = AnimationController(
      duration: params.autoCollapseConfig.expandAnimationDuration,
      reverseDuration: params.autoCollapseConfig.collapseAnimationDuration,
      vsync: this,
      value: isExpanded ? 1.0 : 0.0,
    );

    _expandAnimation = CurvedAnimation(
      parent: _expandController,
      curve: Curves.easeInOut,
    );

    // Listen to expansion changes
    if (list is DragAndDropListExpansionInterface) {
      list.expansionListenable?.addListener(_onExpansionChanged);
    }
  }

  @override
  void didUpdateWidget(covariant DragAndDropListSliverWrapper oldWidget) {
    super.didUpdateWidget(oldWidget);

    final oldList = oldWidget.dragAndDropList;
    final newList = widget.dragAndDropList;
    final newParams = widget.parameters;

    // Check if the list instance changed
    if (oldList != newList) {
      // Remove listener from old list
      if (oldList is DragAndDropListExpansionInterface) {
        oldList.expansionListenable?.removeListener(_onExpansionChanged);
      }

      // Add listener to new list
      if (newList is DragAndDropListExpansionInterface) {
        newList.expansionListenable?.addListener(_onExpansionChanged);

        // Update animation controller value to match new list's state
        final isExpanded = newList.isExpanded;
        _expandController.value = isExpanded ? 1.0 : 0.0;
      }
    }

    // Update animation durations if parameters changed
    if (oldWidget.parameters.autoCollapseConfig !=
        newParams.autoCollapseConfig) {
      _expandController.duration =
          newParams.autoCollapseConfig.expandAnimationDuration;
      _expandController.reverseDuration =
          newParams.autoCollapseConfig.collapseAnimationDuration;
    }
  }

  void _onExpansionChanged() {
    final list = widget.dragAndDropList;
    if (list is DragAndDropListExpansionInterface) {
      if (list.isExpanded) {
        _expandController.forward();
      } else {
        _expandController.reverse();
      }
    }
  }

  @override
  void dispose() {
    final list = widget.dragAndDropList;
    if (list is DragAndDropListExpansionInterface) {
      list.expansionListenable?.removeListener(_onExpansionChanged);
    }
    _expandController.dispose();
    _expansionTimer?.cancel();
    _leaveDebounceTimer?.cancel();
    super.dispose();
  }

  void _startExpansionTimer() {
    _stopExpansionTimer();
    _expansionTimer = Timer(const Duration(milliseconds: 400), () {
      final list = widget.dragAndDropList;
      if (list is DragAndDropListExpansionInterface) {
        list.expand();
      }
    });
  }

  void _stopExpansionTimer() {
    _expansionTimer?.cancel();
    _expansionTimer = null;
  }

  @override
  Widget build(BuildContext context) {
    final list = widget.dragAndDropList;
    final params = widget.parameters;

    // If the list supports expansion, wrap in ValueListenableBuilder to rebuild on state changes
    final expansionListenable = list is DragAndDropListExpansionInterface
        ? list.expansionListenable
        : null;

    if (expansionListenable != null) {
      return ValueListenableBuilder<bool>(
        valueListenable: expansionListenable,
        builder: (context, isExpanded, _) {
          return _buildSliverContent(list, params);
        },
      );
    }

    return _buildSliverContent(list, params);
  }

  Widget _buildSliverContent(
    DragAndDropListInterface list,
    DragAndDropBuilderParameters params,
  ) {
    final header = _extractHeader(list);
    final body = _buildBody(list, params);

    // Build the draggable header content
    Widget headerContent = _buildDraggableHeaderContent(header, params);

    // Build the collapsible body content
    Widget bodyContent = _buildCollapsibleBody(body, list, params);

    // Check if list is collapsed for item auto-expand handling
    bool isExpanded = true;
    if (list is DragAndDropListExpansionInterface) {
      isExpanded = list.isExpanded;
    }

    // Build the header widget with list drag target
    Widget headerWidget = _wrapWithListDragTarget(
      Listener(
        onPointerMove: _onPointerMove,
        onPointerDown: params.onPointerDown,
        onPointerUp: params.onPointerUp,
        child: headerContent,
      ),
      list,
      params,
    );

    // When collapsed, also add DragTarget<DragAndDropItem> overlay to header
    // so items hovering over the header will auto-expand the list
    if (!isExpanded) {
      headerWidget = Stack(
        children: [
          headerWidget,
          Positioned.fill(
            child: DragTarget<DragAndDropItem>(
              builder: (context, candidateData, rejectedData) {
                return const SizedBox.shrink();
              },
              onWillAcceptWithDetails: (details) {
                _log(
                    'Header DragTarget<Item>.onWillAcceptWithDetails - starting expansion timer');
                _startExpansionTimer();
                return false;
              },
              onLeave: (data) {
                _log(
                    'Header DragTarget<Item>.onLeave - stopping expansion timer');
                _stopExpansionTimer();
              },
              onAcceptWithDetails: (details) {},
            ),
          ),
        ],
      );
    }

    // Get decoration to apply to the entire group (header + body)
    Decoration? decoration;
    try {
      final dynamic dynamicList = list;
      decoration = dynamicList.decoration as Decoration?;
    } catch (_) {}
    decoration ??= params.listDecoration;

    Decoration? foregroundDecoration;
    try {
      final dynamic dynamicList = list;
      foregroundDecoration = dynamicList.foregroundDecoration as Decoration?;
    } catch (_) {}
    foregroundDecoration ??= params.listForegroundDecoration;

    Widget sliver = MultiSliver(
      pushPinnedChildren: true,
      children: [
        // 1. Ghost placeholder - wrapped with DragTarget so when ghost appears
        //    and pushes content down, pointer is still over a DragTarget.
        //    This prevents flicker from leave/enter when layout shifts.
        SliverToBoxAdapter(
          child: _wrapWithListDragTarget(
            _buildGhostPlaceholder(params),
            list,
            params,
          ),
        ),
        // 2. Pinned header wrapped with DragTarget
        SliverPinnedHeader(
          child: headerWidget,
        ),
        // 3. Collapsible body wrapped with DragTarget
        SliverToBoxAdapter(
          child: _wrapWithListDragTarget(
            Listener(
              onPointerMove: _onPointerMove,
              onPointerDown: params.onPointerDown,
              onPointerUp: params.onPointerUp,
              child: bodyContent,
            ),
            list,
            params,
          ),
        ),
      ],
    );

    // Wrap entire group with decoration (applies to header + body)
    if (decoration != null) {
      sliver = DecoratedSliver(
        decoration: decoration,
        position: DecorationPosition.background,
        sliver: sliver,
      );

      if (foregroundDecoration != null) {
        sliver = DecoratedSliver(
          decoration: foregroundDecoration,
          position: DecorationPosition.foreground,
          sliver: sliver,
        );
      }
    }

    return sliver;
  }

  /// Builds the ghost placeholder that appears above the header when hovered.
  /// This matches the original DragAndDropListWrapper behavior where the ghost
  /// appears ABOVE the list, indicating "drop here to insert before this list".
  Widget _buildGhostPlaceholder(DragAndDropBuilderParameters params) {
    return AnimatedSize(
      duration: Duration(milliseconds: params.listSizeAnimationDuration),
      alignment: Alignment.topCenter,
      child: _hoveredDraggable != null
          ? Opacity(
              opacity: params.listGhostOpacity,
              child: params.listGhost ??
                  Container(
                    padding: const EdgeInsets.all(0),
                    child: _hoveredDraggable!.generateWidget(params),
                  ),
            )
          : const SizedBox.shrink(),
    );
  }

  /// Wraps a widget with a DragTarget for list reordering.
  /// Uses debounced leave to prevent flicker when transitioning between
  /// ghost/header/body areas (which are separate slivers with separate DragTargets).
  Widget _wrapWithListDragTarget(
    Widget child,
    DragAndDropListInterface list,
    DragAndDropBuilderParameters params,
  ) {
    return Stack(
      children: [
        child,
        Positioned.fill(
          child: DragTarget<DragAndDropListInterface>(
            builder: (context, candidateData, rejectedData) {
              return const SizedBox.shrink();
            },
            onWillAcceptWithDetails: (details) {
              _log('DragTarget.onWillAcceptWithDetails');
              _log(
                  '  incoming: ${details.data.runtimeType}, key=${details.data.key}');
              _log('  target: ${list.runtimeType}, key=${list.key}');

              // Cancel any pending leave - we're still hovering over this list
              _leaveDebounceTimer?.cancel();

              bool accept = true;
              if (params.listOnWillAccept != null) {
                accept = params.listOnWillAccept!(details.data, list);
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
              _log('DragTarget.onLeave');
              // Debounce leave to prevent flicker when transitioning between
              // ghost/header/body DragTargets. If we quickly enter another
              // DragTarget of the same list, the timer is cancelled.
              _leaveDebounceTimer?.cancel();
              _leaveDebounceTimer = Timer(const Duration(milliseconds: 50), () {
                if (_hoveredDraggable != null && mounted) {
                  _log('  -> clearing _hoveredDraggable (debounced)');
                  setState(() {
                    _hoveredDraggable = null;
                  });
                }
              });
            },
            onAcceptWithDetails: (details) {
              _log('DragTarget.onAcceptWithDetails - DROP');
              _log(
                  '  dropped: ${details.data.runtimeType}, key=${details.data.key}');
              _log('  onto: ${list.runtimeType}, key=${list.key}');
              _leaveDebounceTimer?.cancel();
              if (mounted) {
                setState(() {
                  params.onListReordered!(details.data, list);
                  _hoveredDraggable = null;
                });
              }
            },
          ),
        ),
      ],
    );
  }

  /// Extracts the header widget from the list.
  Widget? _extractHeader(DragAndDropListInterface list) {
    try {
      final dynamic dynamicList = list;
      return dynamicList.header as Widget?;
    } catch (_) {
      return null;
    }
  }

  /// Builds the body content (items list) for the given list.
  Widget _buildBody(
    DragAndDropListInterface list,
    DragAndDropBuilderParameters params,
  ) {
    final children = list.children ?? [];
    final verticalAlignment = _getVerticalAlignment(list, params);

    if (children.isEmpty) {
      return _buildEmptyContent(list, params);
    }

    return _buildItemsList(list, children, params, verticalAlignment);
  }

  Widget _buildEmptyContent(
    DragAndDropListInterface list,
    DragAndDropBuilderParameters params,
  ) {
    Widget? contentsWhenEmpty;

    try {
      final dynamic dynamicList = list;
      contentsWhenEmpty = dynamicList.contentsWhenEmpty as Widget?;
    } catch (_) {}

    // Wrap entire empty content in DragTarget so the whole area is droppable
    // No lastTarget needed - the whole area is the drop zone
    return DragTarget<DragAndDropItem>(
      builder: (context, candidateData, rejectedData) {
        return Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            contentsWhenEmpty ??
                const Text(
                  'Empty list',
                  style: TextStyle(fontStyle: FontStyle.italic),
                ),
            // Show ghost when item is hovering
            if (candidateData.isNotEmpty)
              Opacity(
                opacity: params.itemGhostOpacity,
                child: params.itemGhost ?? candidateData.first!.child,
              ),
          ],
        );
      },
      onWillAcceptWithDetails: (details) => true,
      onAcceptWithDetails: (details) {
        params.onItemDropOnLastTarget?.call(
          details.data,
          list,
          DragAndDropItemTarget(
            parent: list,
            parameters: params,
            onReorderOrAdd: params.onItemDropOnLastTarget!,
            child: const SizedBox.shrink(),
          ),
        );
      },
    );
  }

  Widget _buildItemsList(
    DragAndDropListInterface list,
    List<DragAndDropItem> children,
    DragAndDropBuilderParameters params,
    CrossAxisAlignment verticalAlignment,
  ) {
    Widget? lastTarget;
    Widget? leftSide;
    Widget? rightSide;

    try {
      final dynamic dynamicList = list;
      lastTarget = dynamicList.lastTarget as Widget?;
      leftSide = dynamicList.leftSide as Widget?;
      rightSide = dynamicList.rightSide as Widget?;
    } catch (_) {}

    List<Widget> allChildren = [];

    if (params.addLastItemTargetHeightToTop) {
      allChildren.add(Padding(
        padding: EdgeInsets.only(top: params.lastItemTargetHeight),
      ));
    }

    for (int i = 0; i < children.length; i++) {
      allChildren.add(DragAndDropItemWrapper(
        key: children[i].key,
        child: children[i],
        parameters: params,
      ));
      if (params.itemDivider != null && i < children.length - 1) {
        allChildren.add(params.itemDivider!);
      }
    }

    allChildren.add(DragAndDropItemTarget(
      parent: list,
      parameters: params,
      onReorderOrAdd: params.onItemDropOnLastTarget!,
      child: lastTarget ?? SizedBox(height: params.lastItemTargetHeight),
    ));

    Widget itemsColumn = Column(
      crossAxisAlignment: verticalAlignment,
      mainAxisSize: MainAxisSize.min,
      children: allChildren,
    );

    // Add left/right sides if present
    if (leftSide != null || rightSide != null) {
      List<Widget> rowChildren = [];
      if (leftSide != null) rowChildren.add(leftSide);
      rowChildren.add(Expanded(child: itemsColumn));
      if (rightSide != null) rowChildren.add(rightSide);

      return IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: rowChildren,
        ),
      );
    }

    return itemsColumn;
  }

  CrossAxisAlignment _getVerticalAlignment(
    DragAndDropListInterface list,
    DragAndDropBuilderParameters params,
  ) {
    try {
      final dynamic dynamicList = list;
      return dynamicList.verticalAlignment as CrossAxisAlignment;
    } catch (_) {
      return params.verticalAlignment;
    }
  }

  /// Builds the draggable header content (without DragTarget - that's added separately).
  Widget _buildDraggableHeaderContent(
    Widget? header,
    DragAndDropBuilderParameters params,
  ) {
    if (header == null) {
      return const SizedBox.shrink();
    }

    final list = widget.dragAndDropList;

    if (!list.canDrag) {
      return header;
    }

    // Build draggable header
    if (params.listDragHandle != null) {
      return _buildHeaderWithDragHandle(header, params);
    } else if (params.dragOnLongPress) {
      return LongPressDraggable<DragAndDropListInterface>(
        data: list,
        axis: _draggableAxis(params),
        feedback: _buildFeedback(header, params),
        // Match non-pinned: empty Container when dragging
        childWhenDragging: Container(),
        onDragStarted: () => _setDragging(true),
        onDragCompleted: () => _setDragging(false),
        onDraggableCanceled: (_, __) => _setDragging(false),
        onDragEnd: (_) => _setDragging(false),
        child: header,
      );
    } else {
      return Draggable<DragAndDropListInterface>(
        data: list,
        axis: _draggableAxis(params),
        feedback: _buildFeedback(header, params),
        // Match non-pinned: empty Container when dragging
        childWhenDragging: Container(),
        onDragStarted: () => _setDragging(true),
        onDragCompleted: () => _setDragging(false),
        onDraggableCanceled: (_, __) => _setDragging(false),
        onDragEnd: (_) => _setDragging(false),
        child: header,
      );
    }
  }

  Widget _buildHeaderWithDragHandle(
    Widget header,
    DragAndDropBuilderParameters params,
  ) {
    final dragHandle = MouseRegion(
      cursor: SystemMouseCursors.grab,
      child: params.listDragHandle,
    );

    // Match non-pinned mode exactly: MeasureSize wraps Stack, Visibility hides content when dragging
    return MeasureSize(
      onSizeChange: (size) {
        if (mounted) {
          setState(() => _containerSize = size!);
        }
      },
      child: Stack(
        children: [
          // Match non-pinned: plain Visibility without maintainSize
          Visibility(
            visible: !_dragging,
            child: header,
          ),
          Positioned(
            right: params.listDragHandle!.onLeft ? null : 0,
            left: params.listDragHandle!.onLeft ? 0 : null,
            top: _dragHandleDistanceFromTop(params),
            child: Draggable<DragAndDropListInterface>(
              data: widget.dragAndDropList,
              axis: _draggableAxis(params),
              feedback: Transform.translate(
                offset: _feedbackContainerOffset(params),
                child: _buildFeedbackWithHandle(header, dragHandle, params),
              ),
              // Match non-pinned: empty Container when dragging
              childWhenDragging: Container(),
              onDragStarted: () => _setDragging(true),
              onDragCompleted: () => _setDragging(false),
              onDraggableCanceled: (_, __) => _setDragging(false),
              onDragEnd: (_) => _setDragging(false),
              child: MeasureSize(
                onSizeChange: (size) {
                  if (mounted) {
                    setState(() => _dragHandleSize = size!);
                  }
                },
                child: dragHandle,
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// Builds the collapsible body content with animation.
  /// Note: Group decoration is applied via DecoratedSliver in _buildSliverContent.
  Widget _buildCollapsibleBody(
    Widget body,
    DragAndDropListInterface list,
    DragAndDropBuilderParameters params,
  ) {
    // When dragging this list, hide body instantly (like non-pinned mode)
    if (_dragging) {
      return const SizedBox.shrink();
    }

    Widget content = body;

    // Apply inner decoration if present (this is for content inside the group)
    if (params.listInnerDecoration != null) {
      content = Container(
        decoration: params.listInnerDecoration,
        child: content,
      );
    }

    // Check if list is expanded (for collapsible lists)
    bool isExpanded = true;
    if (list is DragAndDropListExpansionInterface) {
      isExpanded = list.isExpanded;
    }

    // Animate collapse/expand using SizeTransition with AnimationController
    // This ensures animation persists across widget rebuilds
    Widget animatedContent = SizeTransition(
      sizeFactor: _expandAnimation,
      axisAlignment: -1.0, // Align to top
      child: content,
    );

    // When collapsed, add a DragTarget<DragAndDropItem> overlay that auto-expands
    // the list when an item hovers over it. This matches DragAndDropListExpansion behavior.
    if (!isExpanded) {
      return Stack(
        children: [
          animatedContent,
          Positioned.fill(
            child: DragTarget<DragAndDropItem>(
              builder: (context, candidateData, rejectedData) {
                return const SizedBox.shrink();
              },
              onWillAcceptWithDetails: (details) {
                _log(
                    'Collapsed body DragTarget<Item>.onWillAcceptWithDetails - starting expansion timer');
                _startExpansionTimer();
                return false; // Don't accept here, let it expand first
              },
              onLeave: (data) {
                _log(
                    'Collapsed body DragTarget<Item>.onLeave - stopping expansion timer');
                _stopExpansionTimer();
              },
              onAcceptWithDetails: (details) {},
            ),
          ),
        ],
      );
    }

    return animatedContent;
  }

  Widget _buildFeedback(Widget content, DragAndDropBuilderParameters params) {
    return SizedBox(
      width: params.listDraggingWidth ?? MediaQuery.of(context).size.width,
      child: Material(
        color: Colors.transparent,
        child: Container(
          decoration: params.listDecorationWhileDragging,
          child: Directionality(
            textDirection: Directionality.of(context),
            child: content,
          ),
        ),
      ),
    );
  }

  Widget _buildFeedbackWithHandle(
    Widget content,
    Widget dragHandle,
    DragAndDropBuilderParameters params,
  ) {
    return Material(
      color: Colors.transparent,
      child: Container(
        decoration: params.listDecorationWhileDragging,
        child: SizedBox(
          width: params.listDraggingWidth ?? _containerSize.width,
          child: Stack(
            children: [
              Directionality(
                textDirection: Directionality.of(context),
                child: content,
              ),
              Positioned(
                right: params.listDragHandle!.onLeft ? null : 0,
                left: params.listDragHandle!.onLeft ? 0 : null,
                top: params.listDragHandle!.verticalAlignment ==
                        DragHandleVerticalAlignment.bottom
                    ? null
                    : 0,
                bottom: params.listDragHandle!.verticalAlignment ==
                        DragHandleVerticalAlignment.top
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

  Axis? _draggableAxis(DragAndDropBuilderParameters params) {
    return params.axis == Axis.vertical && params.constrainDraggingAxis
        ? Axis.vertical
        : null;
  }

  double _dragHandleDistanceFromTop(DragAndDropBuilderParameters params) {
    switch (params.listDragHandle!.verticalAlignment) {
      case DragHandleVerticalAlignment.top:
        return 0;
      case DragHandleVerticalAlignment.center:
        return (_containerSize.height / 2.0) - (_dragHandleSize.height / 2.0);
      case DragHandleVerticalAlignment.bottom:
        return _containerSize.height - _dragHandleSize.height;
    }
  }

  Offset _feedbackContainerOffset(DragAndDropBuilderParameters params) {
    double xOffset = params.listDragHandle!.onLeft
        ? 0
        : -_containerSize.width + _dragHandleSize.width;
    double yOffset = params.listDragHandle!.verticalAlignment ==
            DragHandleVerticalAlignment.bottom
        ? -_containerSize.height + _dragHandleSize.width
        : 0;
    return Offset(xOffset, yOffset);
  }

  void _setDragging(bool dragging) {
    _log('_setDragging($dragging)');
    if (_dragging != dragging) {
      if (mounted) {
        setState(() => _dragging = dragging);
      } else {
        _dragging = dragging;
      }

      widget.parameters.onListDraggingChanged?.call(
        widget.dragAndDropList,
        dragging,
      );
    }
  }

  void _onPointerMove(PointerMoveEvent event) {
    if (_dragging) widget.parameters.onPointerMove!(event);
  }
}
