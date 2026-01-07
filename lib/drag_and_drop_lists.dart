/// Drag and drop list reordering for two level lists.
///
/// [DragAndDropLists] is the main widget, and contains numerous options for controlling overall list presentation.
///
/// The children of [DragAndDropLists] are [DragAndDropList] or another class that inherits from
/// [DragAndDropListInterface] such as [DragAndDropListExpansion]. These lists can be reordered at will.
/// Each list contains its own properties, and can be styled separately if the defaults provided to [DragAndDropLists]
/// should be overridden.
///
/// The children of a [DragAndDropListInterface] are [DragAndDropItem]. These are the individual elements and can be
/// reordered within their own list and into other lists. If they should not be able to be reordered, they can also
/// be locked individually.
library drag_and_drop_lists;

import 'dart:math';

import 'package:drag_and_drop_lists/auto_collapse_config.dart';
import 'package:drag_and_drop_lists/collapse_state_manager.dart';
import 'package:drag_and_drop_lists/drag_and_drop_builder_parameters.dart';
import 'package:drag_and_drop_lists/drag_and_drop_item.dart';
import 'package:drag_and_drop_lists/drag_and_drop_item_target.dart';
import 'package:drag_and_drop_lists/drag_and_drop_list_interface.dart';
import 'package:drag_and_drop_lists/drag_and_drop_list_target.dart';
import 'package:drag_and_drop_lists/drag_and_drop_list_sliver_wrapper.dart';
import 'package:drag_and_drop_lists/drag_and_drop_list_wrapper.dart';
import 'package:drag_and_drop_lists/drag_handle.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';
import 'package:sliver_tools/sliver_tools.dart';

export 'package:drag_and_drop_lists/auto_collapse_config.dart';
export 'package:drag_and_drop_lists/collapse_state_manager.dart';
export 'package:drag_and_drop_lists/drag_and_drop_builder_parameters.dart';
export 'package:drag_and_drop_lists/drag_and_drop_item.dart';
export 'package:drag_and_drop_lists/drag_and_drop_item_target.dart';
export 'package:drag_and_drop_lists/drag_and_drop_item_wrapper.dart';
export 'package:drag_and_drop_lists/drag_and_drop_list.dart';
export 'package:drag_and_drop_lists/drag_and_drop_list_expansion.dart';
export 'package:drag_and_drop_lists/drag_and_drop_list_sliver_wrapper.dart';
export 'package:drag_and_drop_lists/drag_and_drop_list_target.dart';
export 'package:drag_and_drop_lists/drag_and_drop_list_wrapper.dart';
export 'package:drag_and_drop_lists/drag_handle.dart';
export 'package:drag_and_drop_lists/drag_and_drop_scroll_controller.dart';
export 'package:drag_and_drop_lists/src/animated_list_controller.dart';

/// Enable/disable logging for debugging drag-drop behavior.
/// Controlled via [CollapseStateManager.enableLogging].
void _log(String message) {
  if (CollapseStateManager.enableLogging) {
    debugPrint('[DragAndDropLists] $message');
  }
}

typedef OnItemReorder = void Function(
  int oldItemIndex,
  int oldListIndex,
  int newItemIndex,
  int newListIndex,
);
typedef OnItemAdd = void Function(
  DragAndDropItem newItem,
  int listIndex,
  int newItemIndex,
);
typedef OnListAdd = void Function(
    DragAndDropListInterface newList, int newListIndex);
typedef OnListReorder = void Function(int oldListIndex, int newListIndex);
typedef OnListDraggingChanged = void Function(
  DragAndDropListInterface? list,
  bool dragging,
);
typedef ListOnWillAccept = bool Function(
  DragAndDropListInterface? incoming,
  DragAndDropListInterface? target,
);
typedef ListOnAccept = void Function(
  DragAndDropListInterface incoming,
  DragAndDropListInterface target,
);
typedef ListTargetOnWillAccept = bool Function(
    DragAndDropListInterface? incoming, DragAndDropListTarget target);
typedef ListTargetOnAccept = void Function(
    DragAndDropListInterface incoming, DragAndDropListTarget target);
typedef OnItemDraggingChanged = void Function(
  DragAndDropItem item,
  bool dragging,
);
typedef ItemOnWillAccept = bool Function(
  DragAndDropItem? incoming,
  DragAndDropItem target,
);
typedef ItemOnAccept = void Function(
  DragAndDropItem incoming,
  DragAndDropItem target,
);
typedef ItemTargetOnWillAccept = bool Function(
    DragAndDropItem? incoming, DragAndDropItemTarget target);
typedef ItemTargetOnAccept = void Function(
  DragAndDropItem incoming,
  DragAndDropListInterface parentList,
  DragAndDropItemTarget target,
);

class DragAndDropLists extends StatefulWidget {
  /// The child lists to be displayed.
  /// If any of these children are [DragAndDropListExpansion] or inherit from
  /// [DragAndDropListExpansionInterface], [listGhost] must not be null.
  final List<DragAndDropListInterface> children;

  /// Calls this function when a list element is reordered.
  /// Takes into account the index change when removing an item, so the
  /// [newItemIndex] can be used directly when inserting.
  final OnItemReorder onItemReorder;

  /// Calls this function when a list is reordered.
  /// Takes into account the index change when removing a list, so the
  /// [newListIndex] can be used directly when inserting.
  final OnListReorder onListReorder;

  /// Calls this function when a new item has been added.
  final OnItemAdd? onItemAdd;

  /// Calls this function when a new list has been added.
  final OnListAdd? onListAdd;

  /// Set in order to provide custom acceptance criteria for when a list can be
  /// dropped onto a specific other list
  final ListOnWillAccept? listOnWillAccept;

  /// Set in order to get the lists involved in a drag and drop operation after
  /// a list has been accepted. For general use cases where only reordering is
  /// necessary, only [onListReorder] or [onListAdd] is needed, and this should
  /// be left null. [onListReorder] or [onListAdd] will be called after this.
  final ListOnAccept? listOnAccept;

  /// Set in order to provide custom acceptance criteria for when a list can be
  /// dropped onto a specific target. This target always exists as the last
  /// target the DragAndDropLists, and also can be used independently.
  final ListTargetOnWillAccept? listTargetOnWillAccept;

  /// Set in order to get the list and target involved in a drag and drop
  /// operation after a list has been accepted. For general use cases where only
  /// reordering is necessary, only [onListReorder] or [onListAdd] is needed,
  /// and this should be left null. [onListReorder] or [onListAdd] will be
  /// called after this.
  final ListTargetOnAccept? listTargetOnAccept;

  /// Called when a list dragging is starting or ending
  final OnListDraggingChanged? onListDraggingChanged;

  /// Set in order to provide custom acceptance criteria for when a item can be
  /// dropped onto a specific other item
  final ItemOnWillAccept? itemOnWillAccept;

  /// Set in order to get the items involved in a drag and drop operation after
  /// an item has been accepted. For general use cases where only reordering is
  /// necessary, only [onItemReorder] or [onItemAdd] is needed, and this should
  /// be left null. [onItemReorder] or [onItemAdd] will be called after this.
  final ItemOnAccept? itemOnAccept;

  /// Set in order to provide custom acceptance criteria for when a item can be
  /// dropped onto a specific target. This target always exists as the last
  /// target for list of items, and also can be used independently.
  final ItemTargetOnWillAccept? itemTargetOnWillAccept;

  /// Set in order to get the item and target involved in a drag and drop
  /// operation after a item has been accepted. For general use cases where only
  /// reordering is necessary, only [onItemReorder] or [onItemAdd] is needed,
  /// and this should be left null. [onItemReorder] or [onItemAdd] will be
  /// called after this.
  final ItemTargetOnAccept? itemTargetOnAccept;

  /// Called when an item dragging is starting or ending
  final OnItemDraggingChanged? onItemDraggingChanged;

  /// Width of a list item when it is being dragged.
  final double? itemDraggingWidth;

  /// The widget that will be displayed at a potential drop position in a list
  /// when an item is being dragged.
  final Widget? itemGhost;

  /// The opacity of the [itemGhost]. This must be between 0 and 1.
  final double itemGhostOpacity;

  /// Length of animation for the change in an item size when displaying the [itemGhost].
  final int itemSizeAnimationDurationMilliseconds;

  /// If true, drag an item after doing a long press. If false, drag immediately.
  final bool itemDragOnLongPress;

  /// The decoration surrounding an item while it is in the process of being dragged.
  final Decoration? itemDecorationWhileDragging;

  /// A widget that will be displayed between each individual item.
  final Widget? itemDivider;

  /// The width of a list when dragging.
  final double? listDraggingWidth;

  /// The widget to be displayed as the last element in the DragAndDropLists,
  /// where a list will be accepted as the last list.
  final Widget? listTarget;

  /// The widget to be displayed at a potential list position while a list is being dragged.
  /// This must not be null when [children] includes one or more
  /// [DragAndDropListExpansion] or other class that inherit from [DragAndDropListExpansionInterface].
  final Widget? listGhost;

  /// The opacity of [listGhost]. It must be between 0 and 1.
  final double listGhostOpacity;

  /// The duration of the animation for the change in size when a [listGhost] is
  /// displayed at list position.
  final int listSizeAnimationDurationMilliseconds;

  /// Whether a list should be dragged on a long or short press.
  /// When true, the list will be dragged after a long press.
  /// When false, it will be dragged immediately.
  final bool listDragOnLongPress;

  /// The decoration surrounding a list.
  final Decoration? listDecoration;

  /// The decoration surrounding a list while it is in the process of being dragged.
  final Decoration? listDecorationWhileDragging;

  /// The decoration surrounding the inner list of items.
  final Decoration? listInnerDecoration;

  /// A widget that will be displayed between each individual list.
  final Widget? listDivider;

  /// Whether it should put a divider on the last list or not.
  final bool listDividerOnLastChild;

  /// The padding between each individual list.
  final EdgeInsets? listPadding;

  /// A widget that will be displayed whenever a list contains no items.
  final Widget? contentsWhenEmpty;

  /// The width of each individual list. This must be set to a finite value when
  /// [axis] is set to Axis.horizontal.
  final double listWidth;

  /// The height of the target for the last item in a list. This should be large
  /// enough to easily drag an item into the last position of a list.
  final double lastItemTargetHeight;

  /// Add the same height as the lastItemTargetHeight to the top of the list.
  /// This is useful when setting the [listInnerDecoration] to maintain visual
  /// continuity between the top and the bottom
  final bool addLastItemTargetHeightToTop;

  /// The height of the target for the last list. This should be large
  /// enough to easily drag a list to the last position in the DragAndDropLists.
  final double lastListTargetSize;

  /// The default vertical alignment of list contents.
  final CrossAxisAlignment verticalAlignment;

  /// The default horizontal alignment of list contents.
  final MainAxisAlignment horizontalAlignment;

  /// Determines whether the DragAndDropLists are displayed in a horizontal or
  /// vertical manner.
  /// Set [axis] to Axis.vertical for vertical arrangement of the lists.
  /// Set [axis] to Axis.horizontal for horizontal arrangement of the lists.
  /// If [axis] is set to Axis.horizontal, [listWidth] must be set to some finite number.
  final Axis axis;

  /// Whether or not to return a widget or a sliver-compatible list.
  /// Set to true if using as a sliver. If true, a [scrollController] must be provided.
  /// Set to false if using in a widget only.
  final bool sliverList;

  /// Whether to pin list headers when using sliver mode.
  ///
  /// When true and [sliverList] is true, each list's header will pin to the top
  /// of the viewport while scrolling, and multiple pinned headers will stack
  /// and push each other (similar to iOS-style grouped lists).
  ///
  /// This requires each list to have a header widget defined.
  /// Defaults to false for backward compatibility.
  final bool pinnedHeaders;

  /// A scroll controller that can be used for the scrolling of the first level lists.
  /// This must be set if [sliverList] is set to true.
  final ScrollController? scrollController;

  /// Set to true in order to disable all scrolling of the lists.
  /// Note: to disable scrolling for sliver lists, it is also necessary in your
  /// parent CustomScrollView to set physics to NeverScrollableScrollPhysics()
  final bool disableScrolling;

  /// Set a custom drag handle to use iOS-like handles to drag rather than long
  /// or short presses
  final DragHandle? listDragHandle;

  /// Set a custom drag handle to use iOS-like handles to drag rather than long
  /// or short presses
  final DragHandle? itemDragHandle;

  /// Constrain the dragging axis in a vertical list to only allow dragging on
  /// the vertical axis. By default this is set to true. This may be useful to
  /// disable when setting customDragTargets
  final bool constrainDraggingAxis;

  /// If you put a widget before DragAndDropLists there's an unexpected padding
  /// before the list renders. This is the default behaviour for ListView which
  /// is used internally. To remove the padding, set this field to true
  /// https://github.com/flutter/flutter/issues/14842#issuecomment-371344881
  final bool removeTopPadding;

  /// Configuration for the auto-collapse feature.
  ///
  /// When enabled, lists will automatically collapse when a drag operation
  /// starts, providing better visibility of drop targets. Lists are restored
  /// to their previous expansion states when the drag ends.
  ///
  /// Use [AutoCollapseConfig] to configure the behavior, or use
  /// [AutoCollapseConfig.disabled] to disable the feature entirely.
  ///
  /// Example:
  /// ```dart
  /// DragAndDropLists(
  ///   autoCollapseConfig: AutoCollapseConfig(
  ///     enabled: true,
  ///     collapseOnItemDrag: true,
  ///     maintainScrollPosition: true,
  ///   ),
  ///   // ...
  /// )
  /// ```
  final AutoCollapseConfig autoCollapseConfig;

  /// Whether to automatically collapse all lists when a list is being dragged.
  ///
  /// @Deprecated: Use [autoCollapseConfig] instead for more control.
  /// This property is maintained for backward compatibility.
  @Deprecated('Use autoCollapseConfig instead')
  final bool collapseListsOnListDrag;

  /// Whether to automatically scroll to the dropped list position after a list
  /// drag ends. Only applies when [collapseListsOnListDrag] is true.
  ///
  /// @Deprecated: Use [autoCollapseConfig.scrollToDroppedList] instead.
  @Deprecated('Use autoCollapseConfig instead')
  final bool scrollToDroppedList;

  /// The size of the scroll trigger zone at the edges of the list in pixels.
  /// When dragging near the edge, auto-scroll is triggered within this zone.
  /// Defaults to 80 pixels.
  final double autoScrollAreaSize;

  /// The speed of the auto-scroll in pixels per animation frame.
  /// Higher values result in faster scrolling. Defaults to 8.0.
  final double autoScrollSpeed;

  /// The duration of each auto-scroll animation step in milliseconds.
  /// Lower values result in smoother but more frequent updates. Defaults to 30.
  final int autoScrollAnimationDuration;

  DragAndDropLists({
    required this.children,
    required this.onItemReorder,
    required this.onListReorder,
    this.onItemAdd,
    this.onListAdd,
    this.onListDraggingChanged,
    this.listOnWillAccept,
    this.listOnAccept,
    this.listTargetOnWillAccept,
    this.listTargetOnAccept,
    this.onItemDraggingChanged,
    this.itemOnWillAccept,
    this.itemOnAccept,
    this.itemTargetOnWillAccept,
    this.itemTargetOnAccept,
    this.itemDraggingWidth,
    this.itemGhost,
    this.itemGhostOpacity = 0.3,
    this.itemSizeAnimationDurationMilliseconds = 150,
    this.itemDragOnLongPress = true,
    this.itemDecorationWhileDragging,
    this.itemDivider,
    this.listDraggingWidth,
    this.listTarget,
    this.listGhost,
    this.listGhostOpacity = 0.3,
    this.listSizeAnimationDurationMilliseconds = 150,
    this.listDragOnLongPress = true,
    this.listDecoration,
    this.listDecorationWhileDragging,
    this.listInnerDecoration,
    this.listDivider,
    this.listDividerOnLastChild = true,
    this.listPadding,
    this.contentsWhenEmpty,
    this.listWidth = double.infinity,
    this.lastItemTargetHeight = 20,
    this.addLastItemTargetHeightToTop = false,
    this.lastListTargetSize = 110,
    this.verticalAlignment = CrossAxisAlignment.start,
    this.horizontalAlignment = MainAxisAlignment.start,
    this.axis = Axis.vertical,
    this.sliverList = false,
    this.pinnedHeaders = false,
    this.scrollController,
    this.disableScrolling = false,
    this.listDragHandle,
    this.itemDragHandle,
    this.constrainDraggingAxis = true,
    this.removeTopPadding = false,
    this.autoCollapseConfig = AutoCollapseConfig.disabled,
    this.autoScrollAreaSize = 80,
    this.autoScrollSpeed = 8.0,
    this.autoScrollAnimationDuration = 30,
    @Deprecated('Use autoCollapseConfig instead')
    this.collapseListsOnListDrag = false,
    @Deprecated('Use autoCollapseConfig instead')
    this.scrollToDroppedList = true,
    super.key,
  }) {
    if (sliverList && scrollController == null) {
      throw Exception(
          'A scroll controller must be provided when using sliver lists');
    }
    if (axis == Axis.horizontal && listWidth == double.infinity) {
      throw Exception(
          'A finite width must be provided when setting the axis to horizontal');
    }
    if (axis == Axis.horizontal && sliverList) {
      throw Exception(
          'Combining a sliver list with a horizontal list is currently unsupported');
    }
    if (pinnedHeaders && !sliverList) {
      throw Exception(
          'pinnedHeaders requires sliverList to be true');
    }
  }

  @override
  State<StatefulWidget> createState() => DragAndDropListsState();
}

class DragAndDropListsState extends State<DragAndDropLists> {
  ScrollController? _scrollController;
  bool _pointerDown = false;
  double? _pointerYPosition;
  double? _pointerXPosition;
  bool _scrolling = false;
  final PageStorageBucket _pageStorageBucket = PageStorageBucket();

  /// Manager for the auto-collapse feature.
  late CollapseStateManager _collapseManager;

  /// Effective auto-collapse config, merging new and deprecated properties.
  AutoCollapseConfig get _effectiveAutoCollapseConfig {
    // If new config is explicitly enabled, use it
    if (widget.autoCollapseConfig.enabled) {
      return widget.autoCollapseConfig;
    }
    // Otherwise, check deprecated property for backward compatibility
    // ignore: deprecated_member_use_from_same_package
    if (widget.collapseListsOnListDrag) {
      return AutoCollapseConfig(
        enabled: true,
        // ignore: deprecated_member_use_from_same_package
        scrollToDroppedList: widget.scrollToDroppedList,
      );
    }
    return AutoCollapseConfig.disabled;
  }

  @override
  void initState() {
    super.initState();

    if (widget.scrollController != null) {
      _scrollController = widget.scrollController;
    } else {
      _scrollController = ScrollController();
    }

    _collapseManager = CollapseStateManager(
      config: _effectiveAutoCollapseConfig,
      getScrollController: () => _scrollController,
      getChildren: () => widget.children,
    );
  }

  @override
  void didUpdateWidget(DragAndDropLists oldWidget) {
    super.didUpdateWidget(oldWidget);

    // Update scroll controller if changed
    if (widget.scrollController != oldWidget.scrollController) {
      if (widget.scrollController != null) {
        _scrollController = widget.scrollController;
      }
    }

    // Update collapse manager config if needed
    final newConfig = _effectiveAutoCollapseConfig;
    if (newConfig.enabled != _collapseManager.config.enabled) {
      _collapseManager = CollapseStateManager(
        config: newConfig,
        getScrollController: () => _scrollController,
        getChildren: () => widget.children,
      );
    }

    // Notify collapse manager that widget tree may have changed
    // This handles the case where list instances are recreated during drag
    _collapseManager.onWidgetUpdate();
  }

  @override
  void dispose() {
    _collapseManager.dispose();
    // Only dispose scroll controller if we created it
    if (widget.scrollController == null) {
      _scrollController?.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    var parameters = DragAndDropBuilderParameters(
      listGhost: widget.listGhost,
      listGhostOpacity: widget.listGhostOpacity,
      listDraggingWidth: widget.listDraggingWidth,
      itemDraggingWidth: widget.itemDraggingWidth,
      listSizeAnimationDuration: widget.listSizeAnimationDurationMilliseconds,
      dragOnLongPress: widget.listDragOnLongPress,
      listPadding: widget.listPadding,
      itemSizeAnimationDuration: widget.itemSizeAnimationDurationMilliseconds,
      onPointerDown: _onPointerDown,
      onPointerUp: _onPointerUp,
      onPointerMove: _onPointerMove,
      onItemReordered: _internalOnItemReorder,
      onItemDropOnLastTarget: _internalOnItemDropOnLastTarget,
      onListReordered: _internalOnListReorder,
      onItemDraggingChanged: _handleItemDraggingChanged,
      onListDraggingChanged: _handleListDraggingChanged,
      listOnWillAccept: widget.listOnWillAccept,
      listTargetOnWillAccept: widget.listTargetOnWillAccept,
      itemOnWillAccept: widget.itemOnWillAccept,
      itemTargetOnWillAccept: widget.itemTargetOnWillAccept,
      itemGhostOpacity: widget.itemGhostOpacity,
      itemDivider: widget.itemDivider,
      itemDecorationWhileDragging: widget.itemDecorationWhileDragging,
      verticalAlignment: widget.verticalAlignment,
      axis: widget.axis,
      itemGhost: widget.itemGhost,
      listDecoration: widget.listDecoration,
      listDecorationWhileDragging: widget.listDecorationWhileDragging,
      listInnerDecoration: widget.listInnerDecoration,
      listWidth: widget.listWidth,
      lastItemTargetHeight: widget.lastItemTargetHeight,
      addLastItemTargetHeightToTop: widget.addLastItemTargetHeightToTop,
      listDragHandle: widget.listDragHandle,
      itemDragHandle: widget.itemDragHandle,
      constrainDraggingAxis: widget.constrainDraggingAxis,
      disableScrolling: widget.disableScrolling,
      autoCollapseConfig: _effectiveAutoCollapseConfig,
    );

    DragAndDropListTarget dragAndDropListTarget = DragAndDropListTarget(
      parameters: parameters,
      onDropOnLastTarget: _internalOnListDropOnLastTarget,
      lastListTargetSize: widget.lastListTargetSize,
      child: widget.listTarget,
    );

    if (widget.children.isNotEmpty) {
      Widget outerListHolder;

      if (widget.sliverList) {
        outerListHolder = widget.pinnedHeaders
            ? _buildPinnedHeaderSliverList(dragAndDropListTarget, parameters)
            : _buildSliverList(dragAndDropListTarget, parameters);
      } else if (widget.disableScrolling) {
        outerListHolder =
            _buildUnscrollableList(dragAndDropListTarget, parameters);
      } else {
        outerListHolder = _buildListView(parameters, dragAndDropListTarget);
      }

      if (widget.children
          .whereType<DragAndDropListExpansionInterface>()
          .isNotEmpty) {
        outerListHolder = PageStorage(
          bucket: _pageStorageBucket,
          child: outerListHolder,
        );
      }
      return outerListHolder;
    } else {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            widget.contentsWhenEmpty ?? const Text('Empty'),
            dragAndDropListTarget,
          ],
        ),
      );
    }
  }

  Widget _buildSliverList(DragAndDropListTarget dragAndDropListTarget,
      DragAndDropBuilderParameters parameters) {
    bool includeSeparators = widget.listDivider != null;
    int childrenCount = _calculateChildrenCount(includeSeparators);

    return SliverList(
      delegate: SliverChildBuilderDelegate(
        (context, index) {
          return _buildInnerList(index, childrenCount, dragAndDropListTarget,
              includeSeparators, parameters);
        },
        childCount: childrenCount,
      ),
    );
  }

  /// Builds a sliver list with pinned headers.
  ///
  /// Each list is rendered as a [MultiSliver] containing:
  /// - A [SliverPinnedHeader] for the list header
  /// - A [SliverToBoxAdapter] for the body content
  ///
  /// All lists are wrapped in a parent [MultiSliver] with `pushPinnedChildren: true`
  /// which causes pinned headers to stack and push each other.
  Widget _buildPinnedHeaderSliverList(
    DragAndDropListTarget dragAndDropListTarget,
    DragAndDropBuilderParameters parameters,
  ) {
    final children = <Widget>[];

    for (int i = 0; i < widget.children.length; i++) {
      // Add divider between lists if configured
      if (widget.listDivider != null && i > 0) {
        children.add(SliverToBoxAdapter(child: widget.listDivider!));
      }

      // Add padding wrapper if configured
      Widget listSection = DragAndDropListSliverWrapper(
        key: widget.children[i].key,
        dragAndDropList: widget.children[i],
        parameters: parameters,
      );

      if (widget.listPadding != null) {
        listSection = SliverPadding(
          padding: widget.listPadding!,
          sliver: listSection,
        );
      }

      children.add(listSection);
    }

    // Add divider before last target if configured
    if (widget.listDivider != null && widget.listDividerOnLastChild) {
      children.add(SliverToBoxAdapter(child: widget.listDivider!));
    }

    // Add the drop target for adding lists at the end
    children.add(SliverToBoxAdapter(child: dragAndDropListTarget));

    return MultiSliver(
      pushPinnedChildren: true,
      children: children,
    );
  }

  Widget _buildUnscrollableList(DragAndDropListTarget dragAndDropListTarget,
      DragAndDropBuilderParameters parameters) {
    if (widget.axis == Axis.vertical) {
      return Column(
        children: _buildOuterList(dragAndDropListTarget, parameters),
      );
    } else {
      return Row(
        children: _buildOuterList(dragAndDropListTarget, parameters),
      );
    }
  }

  Widget _buildListView(DragAndDropBuilderParameters parameters,
      DragAndDropListTarget dragAndDropListTarget) {
    Widget listView = ListView(
      scrollDirection: widget.axis,
      controller: _scrollController,
      children: _buildOuterList(dragAndDropListTarget, parameters),
    );

    return widget.removeTopPadding
        ? MediaQuery.removePadding(
            removeTop: true,
            context: context,
            child: listView,
          )
        : listView;
  }

  List<Widget> _buildOuterList(DragAndDropListTarget dragAndDropListTarget,
      DragAndDropBuilderParameters parameters) {
    bool includeSeparators = widget.listDivider != null;
    int childrenCount = _calculateChildrenCount(includeSeparators);

    return List.generate(childrenCount, (index) {
      return _buildInnerList(index, childrenCount, dragAndDropListTarget,
          includeSeparators, parameters);
    });
  }

  int _calculateChildrenCount(bool includeSeparators) {
    if (includeSeparators) {
      return (widget.children.length * 2) -
          (widget.listDividerOnLastChild ? 0 : 1) +
          1;
    } else {
      return widget.children.length + 1;
    }
  }

  Widget _buildInnerList(
      int index,
      int childrenCount,
      DragAndDropListTarget dragAndDropListTarget,
      bool includeSeparators,
      DragAndDropBuilderParameters parameters) {
    if (index == childrenCount - 1) {
      return dragAndDropListTarget;
    } else if (includeSeparators && index.isOdd) {
      return widget.listDivider!;
    } else {
      return DragAndDropListWrapper(
        dragAndDropList:
            widget.children[(includeSeparators ? index / 2 : index).toInt()],
        parameters: parameters,
      );
    }
  }

  _internalOnItemReorder(DragAndDropItem reordered, DragAndDropItem receiver) {
    if (widget.itemOnAccept != null) {
      widget.itemOnAccept!(reordered, receiver);
    }

    int reorderedListIndex = -1;
    int reorderedItemIndex = -1;
    int receiverListIndex = -1;
    int receiverItemIndex = -1;

    for (int i = 0; i < widget.children.length; i++) {
      if (reorderedItemIndex == -1) {
        reorderedItemIndex =
            widget.children[i].children!.indexWhere((e) => reordered == e);
        if (reorderedItemIndex != -1) reorderedListIndex = i;
      }
      if (receiverItemIndex == -1) {
        receiverItemIndex =
            widget.children[i].children!.indexWhere((e) => receiver == e);
        if (receiverItemIndex != -1) receiverListIndex = i;
      }
      if (reorderedItemIndex != -1 && receiverItemIndex != -1) {
        break;
      }
    }

    if (reorderedItemIndex == -1) {
      // this is a new item
      if (widget.onItemAdd != null) {
        widget.onItemAdd!(reordered, receiverListIndex, receiverItemIndex);
      }
    } else {
      if (reorderedListIndex == receiverListIndex &&
          receiverItemIndex > reorderedItemIndex) {
        // same list, so if the new position is after the old position, the removal of the old item must be taken into account
        receiverItemIndex--;
      }

      widget.onItemReorder(reorderedItemIndex, reorderedListIndex,
          receiverItemIndex, receiverListIndex);
    }
  }

  _internalOnListReorder(
      DragAndDropListInterface reordered, DragAndDropListInterface receiver) {
    _log('_internalOnListReorder() called');
    _log('  reordered: ${reordered.runtimeType}, key=${reordered.key}');
    _log('  receiver: ${receiver.runtimeType}, key=${receiver.key}');

    // First try object identity, then fall back to key comparison.
    // This handles cases where widget rebuilds create new list instances
    // during drag operations (e.g., due to onWidgetUpdate re-collapse).
    int reorderedListIndex = widget.children.indexWhere((e) => reordered == e);
    if (reorderedListIndex == -1 && reordered.key != null) {
      _log('  reordered not found by identity, trying key lookup');
      reorderedListIndex =
          widget.children.indexWhere((e) => e.key == reordered.key);
    }

    int receiverListIndex = widget.children.indexWhere((e) => receiver == e);
    if (receiverListIndex == -1 && receiver.key != null) {
      _log('  receiver not found by identity, trying key lookup');
      receiverListIndex =
          widget.children.indexWhere((e) => e.key == receiver.key);
    }

    _log(
        '  reorderedListIndex: $reorderedListIndex, receiverListIndex: $receiverListIndex');

    int newListIndex = receiverListIndex;

    if (widget.listOnAccept != null) {
      _log('  calling widget.listOnAccept');
      widget.listOnAccept!(reordered, receiver);
    }

    if (reorderedListIndex == -1) {
      // this is a new list
      _log('  -> NEW LIST, calling widget.onListAdd with index $newListIndex');
      if (widget.onListAdd != null) widget.onListAdd!(reordered, newListIndex);
      // Store the dropped index for scrolling
      _collapseManager.droppedListIndex = newListIndex;
    } else {
      if (newListIndex > reorderedListIndex) {
        // same list, so if the new position is after the old position, the removal of the old item must be taken into account
        newListIndex--;
        _log(
            '  adjusted newListIndex to $newListIndex (was after old position)');
      }
      _log(
          '  -> REORDER, calling widget.onListReorder($reorderedListIndex, $newListIndex)');
      widget.onListReorder(reorderedListIndex, newListIndex);
      // Store the dropped index for scrolling
      _collapseManager.droppedListIndex = newListIndex;
    }
    _log('  _internalOnListReorder() complete');
  }

  _internalOnItemDropOnLastTarget(DragAndDropItem newOrReordered,
      DragAndDropListInterface parentList, DragAndDropItemTarget receiver) {
    if (widget.itemTargetOnAccept != null) {
      widget.itemTargetOnAccept!(newOrReordered, parentList, receiver);
    }

    int reorderedListIndex = -1;
    int reorderedItemIndex = -1;
    int receiverListIndex = -1;
    int receiverItemIndex = -1;

    if (widget.children.isNotEmpty) {
      for (int i = 0; i < widget.children.length; i++) {
        if (reorderedItemIndex == -1) {
          reorderedItemIndex = widget.children[i].children
                  ?.indexWhere((e) => newOrReordered == e) ??
              -1;
          if (reorderedItemIndex != -1) reorderedListIndex = i;
        }

        if (receiverItemIndex == -1 && widget.children[i] == parentList) {
          receiverListIndex = i;
          receiverItemIndex = widget.children[i].children?.length ?? -1;
        }

        if (reorderedItemIndex != -1 && receiverItemIndex != -1) {
          break;
        }
      }
    }

    if (reorderedItemIndex == -1) {
      if (widget.onItemAdd != null) {
        widget.onItemAdd!(
            newOrReordered, receiverListIndex, reorderedItemIndex);
      }
    } else {
      if (reorderedListIndex == receiverListIndex &&
          receiverItemIndex > reorderedItemIndex) {
        // same list, so if the new position is after the old position, the removal of the old item must be taken into account
        receiverItemIndex--;
      }
      widget.onItemReorder(reorderedItemIndex, reorderedListIndex,
          receiverItemIndex, receiverListIndex);
    }
  }

  _internalOnListDropOnLastTarget(
      DragAndDropListInterface newOrReordered, DragAndDropListTarget receiver) {
    _log('_internalOnListDropOnLastTarget() called');
    _log(
        '  newOrReordered: ${newOrReordered.runtimeType}, key=${newOrReordered.key}');

    // determine if newOrReordered is new or existing
    // First try object identity, then fall back to key comparison.
    int reorderedListIndex =
        widget.children.indexWhere((e) => newOrReordered == e);
    if (reorderedListIndex == -1 && newOrReordered.key != null) {
      _log('  newOrReordered not found by identity, trying key lookup');
      reorderedListIndex =
          widget.children.indexWhere((e) => e.key == newOrReordered.key);
    }
    _log(
        '  reorderedListIndex: $reorderedListIndex, children.length: ${widget.children.length}');

    if (widget.listOnAccept != null) {
      _log('  calling widget.listTargetOnAccept');
      widget.listTargetOnAccept!(newOrReordered, receiver);
    }

    if (reorderedListIndex >= 0) {
      final newIndex = widget.children.length - 1;
      _log(
          '  -> REORDER to last, calling widget.onListReorder($reorderedListIndex, $newIndex)');
      widget.onListReorder(reorderedListIndex, newIndex);
      // Store the dropped index for scrolling (last position)
      _collapseManager.droppedListIndex = newIndex;
    } else {
      _log('  -> NEW LIST at end, calling widget.onListAdd');
      if (widget.onListAdd != null) {
        widget.onListAdd!(newOrReordered, reorderedListIndex);
      }
      // Store the dropped index for scrolling
      _collapseManager.droppedListIndex = widget.children.length;
    }
    _log('  _internalOnListDropOnLastTarget() complete');
  }

  _onPointerMove(PointerMoveEvent event) {
    if (_pointerDown) {
      _pointerYPosition = event.position.dy;
      _pointerXPosition = event.position.dx;

      _scrollList();
    }
  }

  _onPointerDown(PointerDownEvent event) {
    _pointerDown = true;
    _pointerYPosition = event.position.dy;
    _pointerXPosition = event.position.dx;
  }

  _onPointerUp(PointerUpEvent event) {
    _pointerDown = false;
  }

  _scrollList() async {
    if (!widget.disableScrolling &&
        !_scrolling &&
        _pointerDown &&
        _pointerYPosition != null &&
        _pointerXPosition != null) {
      double? newOffset;

      var rb = context.findRenderObject()!;
      late Size size;
      if (rb is RenderBox) {
        size = rb.size;
      } else if (rb is RenderSliver) {
        size = rb.paintBounds.size;
      }

      var topLeftOffset = localToGlobal(rb, Offset.zero);
      var bottomRightOffset = localToGlobal(rb, size.bottomRight(Offset.zero));

      if (widget.axis == Axis.vertical) {
        newOffset = _scrollListVertical(topLeftOffset, bottomRightOffset);
      } else {
        var directionality = Directionality.of(context);
        if (directionality == TextDirection.ltr) {
          newOffset =
              _scrollListHorizontalLtr(topLeftOffset, bottomRightOffset);
        } else {
          newOffset =
              _scrollListHorizontalRtl(topLeftOffset, bottomRightOffset);
        }
      }

      if (newOffset != null) {
        _scrolling = true;
        await _scrollController!.animateTo(newOffset,
            duration:
                Duration(milliseconds: widget.autoScrollAnimationDuration),
            curve: Curves.linear);
        _scrolling = false;
        if (_pointerDown) _scrollList();
      }
    }
  }

  /// Calculates scroll speed based on distance into the scroll zone.
  /// Returns a value between 0.3 (at edge) and 1.0 (deep in zone) that
  /// multiplies the base scroll speed.
  double _calculateScrollSpeedMultiplier(double distanceIntoZone) {
    // Normalize distance to 0-1 range based on scroll area size
    final normalizedDistance =
        (distanceIntoZone / widget.autoScrollAreaSize).clamp(0.0, 1.0);
    // Use easeIn curve for more natural acceleration
    // Start at 0.5 speed at edge, ramp up to 1.0 deep in zone
    return 0.5 + (0.5 * normalizedDistance * normalizedDistance);
  }

  double? _scrollListVertical(Offset topLeftOffset, Offset bottomRightOffset) {
    double top = topLeftOffset.dy;
    double bottom = bottomRightOffset.dy;
    double? newOffset;

    var pointerYPosition = _pointerYPosition;
    var scrollController = _scrollController;
    if (scrollController != null && pointerYPosition != null) {
      // Scroll UP when pointer is in top scroll zone
      if (pointerYPosition < (top + widget.autoScrollAreaSize) &&
          scrollController.position.pixels >
              scrollController.position.minScrollExtent) {
        final distanceIntoZone =
            (top + widget.autoScrollAreaSize) - pointerYPosition;
        final speedMultiplier =
            _calculateScrollSpeedMultiplier(distanceIntoZone);
        final scrollAmount = widget.autoScrollSpeed * speedMultiplier;
        newOffset = max(scrollController.position.minScrollExtent,
            scrollController.position.pixels - scrollAmount);
      }
      // Scroll DOWN when pointer is in bottom scroll zone
      else if (pointerYPosition > (bottom - widget.autoScrollAreaSize) &&
          scrollController.position.pixels <
              scrollController.position.maxScrollExtent) {
        final distanceIntoZone =
            pointerYPosition - (bottom - widget.autoScrollAreaSize);
        final speedMultiplier =
            _calculateScrollSpeedMultiplier(distanceIntoZone);
        final scrollAmount = widget.autoScrollSpeed * speedMultiplier;
        newOffset = min(scrollController.position.maxScrollExtent,
            scrollController.position.pixels + scrollAmount);
      }
    }

    return newOffset;
  }

  double? _scrollListHorizontalLtr(
      Offset topLeftOffset, Offset bottomRightOffset) {
    double left = topLeftOffset.dx;
    double right = bottomRightOffset.dx;
    double? newOffset;

    var pointerXPosition = _pointerXPosition;
    var scrollController = _scrollController;
    if (scrollController != null && pointerXPosition != null) {
      // Scroll LEFT when pointer is in left scroll zone
      if (pointerXPosition < (left + widget.autoScrollAreaSize) &&
          scrollController.position.pixels >
              scrollController.position.minScrollExtent) {
        final distanceIntoZone =
            (left + widget.autoScrollAreaSize) - pointerXPosition;
        final speedMultiplier =
            _calculateScrollSpeedMultiplier(distanceIntoZone);
        final scrollAmount = widget.autoScrollSpeed * speedMultiplier;
        newOffset = max(scrollController.position.minScrollExtent,
            scrollController.position.pixels - scrollAmount);
      }
      // Scroll RIGHT when pointer is in right scroll zone
      else if (pointerXPosition > (right - widget.autoScrollAreaSize) &&
          scrollController.position.pixels <
              scrollController.position.maxScrollExtent) {
        final distanceIntoZone =
            pointerXPosition - (right - widget.autoScrollAreaSize);
        final speedMultiplier =
            _calculateScrollSpeedMultiplier(distanceIntoZone);
        final scrollAmount = widget.autoScrollSpeed * speedMultiplier;
        newOffset = min(scrollController.position.maxScrollExtent,
            scrollController.position.pixels + scrollAmount);
      }
    }

    return newOffset;
  }

  double? _scrollListHorizontalRtl(
      Offset topLeftOffset, Offset bottomRightOffset) {
    double left = topLeftOffset.dx;
    double right = bottomRightOffset.dx;
    double? newOffset;

    var pointerXPosition = _pointerXPosition;
    var scrollController = _scrollController;
    if (scrollController != null && pointerXPosition != null) {
      // Scroll toward maxScrollExtent when pointer is in left scroll zone (RTL)
      if (pointerXPosition < (left + widget.autoScrollAreaSize) &&
          scrollController.position.pixels <
              scrollController.position.maxScrollExtent) {
        final distanceIntoZone =
            (left + widget.autoScrollAreaSize) - pointerXPosition;
        final speedMultiplier =
            _calculateScrollSpeedMultiplier(distanceIntoZone);
        final scrollAmount = widget.autoScrollSpeed * speedMultiplier;
        newOffset = min(scrollController.position.maxScrollExtent,
            scrollController.position.pixels + scrollAmount);
      }
      // Scroll toward minScrollExtent when pointer is in right scroll zone (RTL)
      else if (pointerXPosition > (right - widget.autoScrollAreaSize) &&
          scrollController.position.pixels >
              scrollController.position.minScrollExtent) {
        final distanceIntoZone =
            pointerXPosition - (right - widget.autoScrollAreaSize);
        final speedMultiplier =
            _calculateScrollSpeedMultiplier(distanceIntoZone);
        final scrollAmount = widget.autoScrollSpeed * speedMultiplier;
        newOffset = max(scrollController.position.minScrollExtent,
            scrollController.position.pixels - scrollAmount);
      }
    }

    return newOffset;
  }

  static Offset localToGlobal(RenderObject object, Offset point,
      {RenderObject? ancestor}) {
    return MatrixUtils.transformPoint(object.getTransformTo(ancestor), point);
  }

  // Auto-collapse feature methods

  /// Handles list drag state changes and triggers auto-collapse behavior.
  void _handleListDraggingChanged(
      DragAndDropListInterface? list, bool dragging) {
    _log('_handleListDraggingChanged() called');
    _log('  list: ${list?.runtimeType}, key=${list?.key}');
    _log('  dragging: $dragging');
    _log('  droppedListIndex before: ${_collapseManager.droppedListIndex}');

    if (list != null) {
      if (dragging) {
        _log('  -> drag START, calling _collapseManager.onListDragStart()');
        _collapseManager.onListDragStart(list);
      } else {
        _log(
            '  -> drag END, calling _collapseManager.onListDragEnd(newListIndex: ${_collapseManager.droppedListIndex})');
        _collapseManager.onListDragEnd(
          newListIndex: _collapseManager.droppedListIndex,
        );
      }
    } else {
      _log('  -> list is null, not calling collapse manager');
    }
    _log('  calling widget.onListDraggingChanged');
    widget.onListDraggingChanged?.call(list, dragging);
    _log('  _handleListDraggingChanged() complete');
  }

  /// Handles item drag state changes and triggers auto-collapse behavior
  /// if configured.
  void _handleItemDraggingChanged(DragAndDropItem item, bool dragging) {
    _log('_handleItemDraggingChanged() called');
    _log('  item: ${item.runtimeType}, key=${item.key}');
    _log('  dragging: $dragging');

    if (dragging) {
      _log('  -> drag START, calling _collapseManager.onItemDragStart()');
      _collapseManager.onItemDragStart(item);
    } else {
      _log('  -> drag END, calling _collapseManager.onItemDragEnd()');
      _collapseManager.onItemDragEnd();
    }
    widget.onItemDraggingChanged?.call(item, dragging);
    _log('  _handleItemDraggingChanged() complete');
  }
}
