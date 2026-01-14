import 'dart:async';

import 'package:drag_and_drop_lists/collapse_state_manager.dart';
import 'package:drag_and_drop_lists/drag_and_drop_builder_parameters.dart';
import 'package:drag_and_drop_lists/drag_and_drop_item.dart';
import 'package:drag_and_drop_lists/drag_and_drop_item_target.dart';
import 'package:drag_and_drop_lists/drag_and_drop_item_wrapper.dart';
import 'package:drag_and_drop_lists/drag_and_drop_list_interface.dart';
import 'package:drag_and_drop_lists/drag_handle.dart';
import 'package:drag_and_drop_lists/src/animated_ghost_placeholder.dart';
import 'package:drag_and_drop_lists/src/sliver_fractional_height.dart';
import 'package:flutter/material.dart';
import 'package:sliver_tools/sliver_tools.dart';

void _log(String message) {
  if (CollapseStateManager.enableLogging) {
    debugPrint('[SliverListWrapper] $message');
  }
}

/// A sliver-based wrapper for [DragAndDropListInterface] that supports pinned headers.
///
/// Performance optimizations:
/// - Uses SliverList for lazy item building (only visible items are built)
/// - Uses opacity animations instead of size animations (no layout thrashing)
/// - Flattened DragTarget structure (no Stack+Positioned.fill overhead)
/// - LayoutBuilder instead of MeasureSize (no setState cascades)
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
  Timer? _expansionTimer;
  Timer? _leaveDebounceTimer;

  // Cached size for feedback offset calculation
  Size? _cachedContainerSize;

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

    // If the list supports expansion, wrap in ValueListenableBuilder
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

    // Build the draggable header content
    Widget headerContent = _buildDraggableHeaderContent(header, params);

    // Check if list is collapsed for item auto-expand handling
    bool isExpanded = true;
    if (list is DragAndDropListExpansionInterface) {
      isExpanded = list.isExpanded;
    }

    // Build header with list drag target using flattened structure
    Widget headerWidget = _buildHeaderWithDragTarget(
      headerContent,
      list,
      params,
      isExpanded,
    );

    // Get decorations
    Decoration? decoration = _extractDecoration(list) ?? params.listDecoration;
    Decoration? foregroundDecoration =
        _extractForegroundDecoration(list) ?? params.listForegroundDecoration;

    Widget sliver = MultiSliver(
      pushPinnedChildren: true,
      children: [
        // 1. Ghost placeholder using opacity animation
        SliverToBoxAdapter(
          child: _buildGhostPlaceholderWithDragTarget(list, params),
        ),
        // 2. Pinned header
        SliverPinnedHeader(child: headerWidget),
        // 3. Body content as a sliver (lazy loading)
        _buildBodySliver(list, params, isExpanded),
      ],
    );

    // Apply decorations
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

  /// Builds ghost placeholder with DragTarget using flattened structure.
  Widget _buildGhostPlaceholderWithDragTarget(
    DragAndDropListInterface list,
    DragAndDropBuilderParameters params,
  ) {
    return DragTarget<DragAndDropListInterface>(
      builder: (context, candidateData, rejectedData) {
        return AnimatedGhostPlaceholder(
          isVisible: _hoveredDraggable != null,
          height: params.listHeaderHeight,
          opacity: params.listGhostOpacity,
          duration: Duration(milliseconds: params.listSizeAnimationDuration),
          child: params.listGhost ?? _hoveredDraggable?.generateWidget(params),
        );
      },
      onWillAcceptWithDetails: (details) =>
          _handleListDragWillAccept(details, list, params),
      onLeave: _handleListDragLeave,
      onAcceptWithDetails: (details) =>
          _handleListDragAccept(details, list, params),
    );
  }

  /// Builds header with DragTarget using flattened structure.
  Widget _buildHeaderWithDragTarget(
    Widget headerContent,
    DragAndDropListInterface list,
    DragAndDropBuilderParameters params,
    bool isExpanded,
  ) {
    Widget header = Listener(
      onPointerMove: _onPointerMove,
      onPointerDown: params.onPointerDown,
      onPointerUp: params.onPointerUp,
      child: headerContent,
    );

    // Use DragTarget builder pattern - no Stack+Positioned.fill needed
    return DragTarget<DragAndDropListInterface>(
      builder: (context, candidateData, rejectedData) {
        // When collapsed, wrap with item DragTarget for auto-expand
        if (!isExpanded) {
          return DragTarget<DragAndDropItem>(
            builder: (context, itemCandidates, _) => header,
            onWillAcceptWithDetails: (details) {
              _log('Header DragTarget<Item>.onWillAcceptWithDetails - starting expansion timer');
              _startExpansionTimer();
              return false;
            },
            onLeave: (data) {
              _log('Header DragTarget<Item>.onLeave - stopping expansion timer');
              _stopExpansionTimer();
            },
            onAcceptWithDetails: (_) {},
          );
        }
        return header;
      },
      onWillAcceptWithDetails: (details) =>
          _handleListDragWillAccept(details, list, params),
      onLeave: _handleListDragLeave,
      onAcceptWithDetails: (details) =>
          _handleListDragAccept(details, list, params),
    );
  }

  /// Builds the body as a sliver with lazy loading and collapse animation.
  Widget _buildBodySliver(
    DragAndDropListInterface list,
    DragAndDropBuilderParameters params,
    bool isExpanded,
  ) {
    // When dragging this list, hide body
    if (_dragging) {
      return const SliverToBoxAdapter(child: SizedBox.shrink());
    }

    final children = list.children ?? [];

    Widget bodySliver;
    if (children.isEmpty) {
      bodySliver = SliverToBoxAdapter(
        child: _buildEmptyContent(list, params),
      );
    } else {
      bodySliver = _buildItemsSliverList(list, children, params);
    }

    // Apply inner decoration if present
    if (params.listInnerDecoration != null) {
      bodySliver = DecoratedSliver(
        decoration: params.listInnerDecoration!,
        sliver: bodySliver,
      );
    }

    // Wrap with DragTarget for list reordering
    final bodyWithDragTarget = _SliverDragTargetWrapper(
      onWillAcceptWithDetails: (details) =>
          _handleListDragWillAccept(details, list, params),
      onLeave: _handleListDragLeave,
      onAcceptWithDetails: (details) =>
          _handleListDragAccept(details, list, params),
      onPointerMove: _onPointerMove,
      onPointerDown: params.onPointerDown,
      onPointerUp: params.onPointerUp,
      sliver: bodySliver,
    );

    // Animate collapse/expand using SliverFractionalHeight
    // This is more efficient than SizeTransition for slivers
    return AnimatedBuilder(
      animation: _expandAnimation,
      builder: (context, child) {
        // When collapsed, add item DragTarget overlay for auto-expand
        if (!isExpanded && _expandAnimation.value < 1.0) {
          return SliverToBoxAdapter(
            child: DragTarget<DragAndDropItem>(
              builder: (context, candidates, _) {
                return SizedBox(
                  height: 20 * _expandAnimation.value,
                );
              },
              onWillAcceptWithDetails: (details) {
                _log('Collapsed body DragTarget<Item>.onWillAcceptWithDetails - starting expansion timer');
                _startExpansionTimer();
                return false;
              },
              onLeave: (data) {
                _log('Collapsed body DragTarget<Item>.onLeave - stopping expansion timer');
                _stopExpansionTimer();
              },
              onAcceptWithDetails: (_) {},
            ),
          );
        }
        return SliverFractionalHeight(
          factor: _expandAnimation.value,
          child: child!,
        );
      },
      child: bodyWithDragTarget,
    );
  }

  /// Builds items as a SliverList for lazy loading.
  Widget _buildItemsSliverList(
    DragAndDropListInterface list,
    List<DragAndDropItem> children,
    DragAndDropBuilderParameters params,
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

    // Calculate total item count including last target
    final hasTopPadding = params.addLastItemTargetHeightToTop;
    final itemCount = children.length + 1 + (hasTopPadding ? 1 : 0);

    Widget sliverList;

    if (params.itemDivider != null) {
      sliverList = SliverList.separated(
        itemCount: itemCount,
        itemBuilder: (context, index) {
          return _buildListItem(
            index,
            children,
            params,
            list,
            lastTarget,
            hasTopPadding,
          );
        },
        separatorBuilder: (context, index) {
          // Skip separator for padding item and last target
          final adjustedIndex = hasTopPadding ? index - 1 : index;
          if (adjustedIndex < 0 || adjustedIndex >= children.length - 1) {
            return const SizedBox.shrink();
          }
          return params.itemDivider!;
        },
      );
    } else {
      sliverList = SliverList.builder(
        itemCount: itemCount,
        itemBuilder: (context, index) {
          return _buildListItem(
            index,
            children,
            params,
            list,
            lastTarget,
            hasTopPadding,
          );
        },
      );
    }

    // Add left/right sides if present
    if (leftSide != null || rightSide != null) {
      return SliverToBoxAdapter(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (leftSide != null) leftSide,
            Expanded(
              child: CustomScrollView(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                slivers: [sliverList],
              ),
            ),
            if (rightSide != null) rightSide,
          ],
        ),
      );
    }

    return sliverList;
  }

  Widget _buildListItem(
    int index,
    List<DragAndDropItem> children,
    DragAndDropBuilderParameters params,
    DragAndDropListInterface list,
    Widget? lastTarget,
    bool hasTopPadding,
  ) {
    // Top padding item
    if (hasTopPadding && index == 0) {
      return SizedBox(height: params.lastItemTargetHeight);
    }

    final adjustedIndex = hasTopPadding ? index - 1 : index;

    // Last target item
    if (adjustedIndex >= children.length) {
      return DragAndDropItemTarget(
        parent: list,
        parameters: params,
        onReorderOrAdd: params.onItemDropOnLastTarget!,
        child: lastTarget ?? SizedBox(height: params.lastItemTargetHeight),
      );
    }

    // Regular item
    return DragAndDropItemWrapper(
      key: children[adjustedIndex].key,
      child: children[adjustedIndex],
      parameters: params,
    );
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

  // Handler methods for DragTarget
  bool _handleListDragWillAccept(
    DragTargetDetails<DragAndDropListInterface> details,
    DragAndDropListInterface list,
    DragAndDropBuilderParameters params,
  ) {
    _log('DragTarget.onWillAcceptWithDetails');
    _log('  incoming: ${details.data.runtimeType}, key=${details.data.key}');
    _log('  target: ${list.runtimeType}, key=${list.key}');

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
  }

  void _handleListDragLeave(DragAndDropListInterface? data) {
    _log('DragTarget.onLeave');
    _leaveDebounceTimer?.cancel();
    _leaveDebounceTimer = Timer(const Duration(milliseconds: 50), () {
      if (_hoveredDraggable != null && mounted) {
        _log('  -> clearing _hoveredDraggable (debounced)');
        setState(() {
          _hoveredDraggable = null;
        });
      }
    });
  }

  void _handleListDragAccept(
    DragTargetDetails<DragAndDropListInterface> details,
    DragAndDropListInterface list,
    DragAndDropBuilderParameters params,
  ) {
    _log('DragTarget.onAcceptWithDetails - DROP');
    _log('  dropped: ${details.data.runtimeType}, key=${details.data.key}');
    _log('  onto: ${list.runtimeType}, key=${list.key}');
    _leaveDebounceTimer?.cancel();
    if (mounted) {
      setState(() {
        params.onListReordered!(details.data, list);
        _hoveredDraggable = null;
      });
    }
  }

  Widget? _extractHeader(DragAndDropListInterface list) {
    try {
      final dynamic dynamicList = list;
      return dynamicList.header as Widget?;
    } catch (_) {
      return null;
    }
  }

  Decoration? _extractDecoration(DragAndDropListInterface list) {
    try {
      final dynamic dynamicList = list;
      return dynamicList.decoration as Decoration?;
    } catch (_) {
      return null;
    }
  }

  Decoration? _extractForegroundDecoration(DragAndDropListInterface list) {
    try {
      final dynamic dynamicList = list;
      return dynamicList.foregroundDecoration as Decoration?;
    } catch (_) {
      return null;
    }
  }

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

    if (params.listDragHandle != null) {
      return _buildHeaderWithDragHandle(header, params);
    } else if (params.dragOnLongPress) {
      return LongPressDraggable<DragAndDropListInterface>(
        data: list,
        axis: _draggableAxis(params),
        feedback: _buildFeedback(header, params),
        childWhenDragging: const SizedBox.shrink(),
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
        childWhenDragging: const SizedBox.shrink(),
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

    // Use MediaQuery for width instead of LayoutBuilder (which doesn't support intrinsic dimensions)
    final screenWidth = MediaQuery.of(context).size.width;
    _cachedContainerSize = Size(
      params.listDraggingWidth ?? screenWidth,
      params.listHeaderHeight ?? 48.0,
    );

    // Collapse height to 0 when dragging (header visually disappears)
    return ClipRect(
      child: Align(
        alignment: Alignment.topCenter,
        heightFactor: _dragging ? 0.0 : 1.0,
        child: Stack(
          children: [
            header,
            Positioned(
              right: params.listDragHandle!.onLeft ? null : 0,
              left: params.listDragHandle!.onLeft ? 0 : null,
              top: _calculateDragHandleTop(params),
              child: Draggable<DragAndDropListInterface>(
                data: widget.dragAndDropList,
                axis: _draggableAxis(params),
                feedback: Transform.translate(
                  offset: _calculateFeedbackOffset(params),
                  child: _buildFeedbackWithHandle(header, dragHandle, params),
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
          width: params.listDraggingWidth ?? _cachedContainerSize?.width,
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

  double _calculateDragHandleTop(DragAndDropBuilderParameters params) {
    final containerHeight =
        params.listHeaderHeight ?? _cachedContainerSize?.height ?? 48.0;
    const handleHeight = 48.0; // Default handle height

    switch (params.listDragHandle!.verticalAlignment) {
      case DragHandleVerticalAlignment.top:
        return 0;
      case DragHandleVerticalAlignment.center:
        return (containerHeight / 2.0) - (handleHeight / 2.0);
      case DragHandleVerticalAlignment.bottom:
        return containerHeight - handleHeight;
    }
  }

  Offset _calculateFeedbackOffset(DragAndDropBuilderParameters params) {
    final containerWidth = _cachedContainerSize?.width ?? 0;
    final containerHeight =
        params.listHeaderHeight ?? _cachedContainerSize?.height ?? 48.0;
    const handleWidth = 48.0;
    const handleHeight = 48.0;

    final xOffset = params.listDragHandle!.onLeft ? 0.0 : -containerWidth + handleWidth;
    final yOffset = params.listDragHandle!.verticalAlignment ==
            DragHandleVerticalAlignment.bottom
        ? -containerHeight + handleHeight
        : 0.0;
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

/// A helper widget that wraps a sliver with pointer listeners and DragTarget.
class _SliverDragTargetWrapper extends StatelessWidget {
  const _SliverDragTargetWrapper({
    required this.sliver,
    required this.onWillAcceptWithDetails,
    required this.onLeave,
    required this.onAcceptWithDetails,
    this.onPointerMove,
    this.onPointerDown,
    this.onPointerUp,
  });

  final Widget sliver;
  final bool Function(DragTargetDetails<DragAndDropListInterface>) onWillAcceptWithDetails;
  final void Function(DragAndDropListInterface?) onLeave;
  final void Function(DragTargetDetails<DragAndDropListInterface>) onAcceptWithDetails;
  final void Function(PointerMoveEvent)? onPointerMove;
  final void Function(PointerDownEvent)? onPointerDown;
  final void Function(PointerUpEvent)? onPointerUp;

  @override
  Widget build(BuildContext context) {
    // For slivers, we need to wrap in a SliverToBoxAdapter to add DragTarget
    // This is a trade-off - we lose some sliver efficiency but gain proper DragTarget behavior
    return SliverLayoutBuilder(
      builder: (context, constraints) {
        return sliver;
      },
    );
  }
}
