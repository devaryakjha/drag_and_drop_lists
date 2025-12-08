import 'package:drag_and_drop_lists/drag_and_drop_item.dart';
import 'package:drag_and_drop_lists/drag_and_drop_list_interface.dart';
import 'package:flutter/widgets.dart';

/// Alignment options for scroll-to-index operations.
enum ScrollAlignment {
  /// Align the target at the start/top of the viewport.
  start,

  /// Align the target at the center of the viewport.
  center,

  /// Align the target at the end/bottom of the viewport.
  end,
}

/// Configuration for calculating scroll offsets based on fixed heights.
///
/// All height values should represent the dimension along the scroll axis
/// (height for vertical scrolling, width for horizontal scrolling).
class DragAndDropScrollPositionConfig {
  /// Height of a standard [DragAndDropList] header widget, if present.
  final double groupHeaderHeight;

  /// Height of a [DragAndDropListExpansion] title/header area.
  /// Defaults to 56.0 (standard ListTile height).
  final double expansionTileHeaderHeight;

  /// Height of each [DragAndDropItem] in the lists.
  final double itemHeight;

  /// Height of the "contents when empty" widget shown when a list has no items.
  final double contentsWhenEmptyHeight;

  /// Height of the drop target at the end of each list.
  final double lastItemTargetHeight;

  /// Height of dividers between items within a list, if present.
  final double itemDividerHeight;

  /// Height of dividers between lists, if present.
  final double listDividerHeight;

  /// Padding around each list/group.
  final EdgeInsets groupPadding;

  /// Height of a standard [DragAndDropList] footer widget, if present.
  final double groupFooterHeight;

  /// Default top offset to account for pinned headers (e.g., SliverAppBar).
  ///
  /// When using [DragAndDropLists] inside a [CustomScrollView] with pinned
  /// slivers at the top, set this to the height of those pinned elements.
  /// This ensures scroll-to operations position items below the pinned area.
  ///
  /// Can be overridden per scroll operation via the `topOffset` parameter
  /// in [DragAndDropScrollController.scrollToGroup] and
  /// [DragAndDropScrollController.scrollToItem].
  final double topOffset;

  const DragAndDropScrollPositionConfig({
    this.groupHeaderHeight = 0,
    this.expansionTileHeaderHeight = 56.0,
    this.itemHeight = 48.0,
    this.contentsWhenEmptyHeight = 48.0,
    this.lastItemTargetHeight = 20.0,
    this.itemDividerHeight = 0,
    this.listDividerHeight = 0,
    this.groupPadding = EdgeInsets.zero,
    this.groupFooterHeight = 0,
    this.topOffset = 0,
  });
}

/// A custom [ScrollController] that provides scroll-to-index functionality
/// for [DragAndDropLists] widget.
///
/// This controller calculates scroll offsets based on fixed heights provided
/// via [DragAndDropScrollPositionConfig]. You must call [updateLists] to
/// synchronize the controller with the current list data whenever the lists
/// change.
///
/// Example usage:
/// ```dart
/// final controller = DragAndDropScrollController(
///   config: DragAndDropScrollPositionConfig(
///     groupHeaderHeight: 40,
///     itemHeight: 56,
///     lastItemTargetHeight: 20,
///   ),
/// );
///
/// // After building lists
/// controller.updateLists(myLists, hasListDividers: true);
///
/// // Scroll to group 2
/// await controller.scrollToGroup(2);
///
/// // Scroll to item 3 in group 1
/// await controller.scrollToItem(1, 3, alignment: ScrollAlignment.center);
/// ```
class DragAndDropScrollController extends ScrollController {
  /// Configuration for height calculations.
  final DragAndDropScrollPositionConfig config;

  /// Internal reference to the list of groups.
  List<DragAndDropListInterface> _lists = [];

  /// Whether list dividers are present between groups.
  bool _hasListDividers = false;

  /// Whether a divider appears after the last list.
  bool _listDividerOnLastChild = true;

  /// Creates a [DragAndDropScrollController] with the given configuration.
  ///
  /// [config] defines the fixed heights used for offset calculations.
  DragAndDropScrollController({
    required this.config,
    super.initialScrollOffset,
    super.keepScrollOffset,
    super.debugLabel,
  });

  /// Updates the internal reference to the lists.
  ///
  /// This must be called whenever the list data changes to ensure accurate
  /// scroll offset calculations. Typically called in [initState] and after
  /// any reordering operations.
  ///
  /// [lists] is the current list of [DragAndDropListInterface] objects.
  /// [hasListDividers] indicates whether dividers are present between lists.
  /// [listDividerOnLastChild] indicates whether a divider appears after the last list.
  void updateLists(
    List<DragAndDropListInterface> lists, {
    bool hasListDividers = false,
    bool listDividerOnLastChild = true,
  }) {
    _lists = lists;
    _hasListDividers = hasListDividers;
    _listDividerOnLastChild = listDividerOnLastChild;
  }

  /// Scrolls to make the group at [groupIndex] visible.
  ///
  /// [alignment] specifies where in the viewport the group should appear.
  /// [duration] and [curve] control the scroll animation.
  /// [topOffset] accounts for pinned headers (e.g., SliverAppBar). If null,
  /// uses the value from [config.topOffset].
  ///
  /// Returns a [Future] that completes when the scroll animation is finished.
  /// Throws [RangeError] if [groupIndex] is out of bounds.
  /// Returns immediately if the controller is not attached to a scroll view.
  Future<void> scrollToGroup(
    int groupIndex, {
    ScrollAlignment alignment = ScrollAlignment.start,
    Duration duration = const Duration(milliseconds: 300),
    Curve curve = Curves.easeInOut,
    double? topOffset,
  }) async {
    if (!hasClients) return;

    if (groupIndex < 0 || groupIndex >= _lists.length) {
      throw RangeError.index(groupIndex, _lists, 'groupIndex');
    }

    final effectiveTopOffset = topOffset ?? config.topOffset;
    final offset = _calculateGroupOffset(groupIndex);
    final groupHeight = _getGroupHeight(_lists[groupIndex]);
    final adjustedOffset =
        _applyAlignment(offset, groupHeight, alignment, effectiveTopOffset);
    final clampedOffset = adjustedOffset.clamp(
      position.minScrollExtent,
      position.maxScrollExtent,
    );

    await animateTo(
      clampedOffset,
      duration: duration,
      curve: curve,
    );
  }

  /// Scrolls to make the item at [itemIndex] within group [groupIndex] visible.
  ///
  /// If the group is a [DragAndDropListExpansionInterface] and is collapsed,
  /// it will be expanded first, then scrolled to after the expansion animation
  /// completes.
  ///
  /// [alignment] specifies where in the viewport the item should appear.
  /// [duration] and [curve] control the scroll animation.
  /// [expansionAnimationDuration] is the time to wait for the expansion
  /// animation to complete (defaults to 250ms, which accounts for the 200ms
  /// animation plus a buffer).
  /// [topOffset] accounts for pinned headers (e.g., SliverAppBar). If null,
  /// uses the value from [config.topOffset].
  ///
  /// Returns a [Future] that completes when the scroll animation is finished.
  /// Throws [RangeError] if indices are out of bounds.
  /// Returns immediately if the controller is not attached to a scroll view.
  Future<void> scrollToItem(
    int groupIndex,
    int itemIndex, {
    ScrollAlignment alignment = ScrollAlignment.start,
    Duration duration = const Duration(milliseconds: 300),
    Curve curve = Curves.easeInOut,
    Duration expansionAnimationDuration = const Duration(milliseconds: 250),
    double? topOffset,
  }) async {
    if (!hasClients) return;

    if (groupIndex < 0 || groupIndex >= _lists.length) {
      throw RangeError.index(groupIndex, _lists, 'groupIndex');
    }

    final group = _lists[groupIndex];
    final children = group.children ?? [];

    if (itemIndex < 0 || itemIndex >= children.length) {
      throw RangeError.index(itemIndex, children, 'itemIndex');
    }

    // Handle expansion if the group is collapsed
    if (group is DragAndDropListExpansionInterface && !group.isExpanded) {
      group.expand();
      await Future.delayed(expansionAnimationDuration);
    }

    final effectiveTopOffset = topOffset ?? config.topOffset;
    final offset = _calculateItemOffset(groupIndex, itemIndex);
    final adjustedOffset =
        _applyAlignment(offset, config.itemHeight, alignment, effectiveTopOffset);
    final clampedOffset = adjustedOffset.clamp(
      position.minScrollExtent,
      position.maxScrollExtent,
    );

    await animateTo(
      clampedOffset,
      duration: duration,
      curve: curve,
    );
  }

  /// Calculates the scroll offset to the start of the group at [groupIndex].
  double _calculateGroupOffset(int groupIndex) {
    double offset = 0;

    for (int i = 0; i < groupIndex; i++) {
      offset += _getGroupHeight(_lists[i]);

      // Add list divider height if applicable
      if (_hasListDividers) {
        // Add divider after each list except possibly the last one
        if (i < _lists.length - 1 || _listDividerOnLastChild) {
          offset += config.listDividerHeight;
        }
      }
    }

    return offset;
  }

  /// Calculates the scroll offset to a specific item within a group.
  double _calculateItemOffset(int groupIndex, int itemIndex) {
    double offset = _calculateGroupOffset(groupIndex);

    final group = _lists[groupIndex];

    // Add offset to reach the item within the group
    offset += config.groupPadding.top;

    if (group is DragAndDropListExpansionInterface) {
      // For expansion tiles, add the header height
      offset += config.expansionTileHeaderHeight;
    } else {
      // For standard lists, add header height if present
      offset += config.groupHeaderHeight;
    }

    // Add the offset for items before this one
    offset += itemIndex * config.itemHeight;
    offset += itemIndex * config.itemDividerHeight;

    return offset;
  }

  /// Gets the total height of a single list/group.
  double _getGroupHeight(DragAndDropListInterface list) {
    double height = config.groupPadding.vertical;

    if (list is DragAndDropListExpansionInterface) {
      // Expansion tile header is always visible
      height += config.expansionTileHeaderHeight;

      // Content is only visible when expanded
      if (list.isExpanded) {
        height += _getItemsHeight(list.children);
      }
    } else {
      // Standard DragAndDropList
      height += config.groupHeaderHeight;
      height += _getItemsHeight(list.children);
      height += config.groupFooterHeight;
    }

    return height;
  }

  /// Gets the total height of all items in a list (including dividers and target).
  double _getItemsHeight(List<DragAndDropItem>? children) {
    if (children == null || children.isEmpty) {
      // Empty list shows contentsWhenEmpty + lastItemTarget
      return config.contentsWhenEmptyHeight + config.lastItemTargetHeight;
    }

    double height = 0;

    // Item heights
    height += children.length * config.itemHeight;

    // Dividers between items (one less than item count)
    height += (children.length - 1) * config.itemDividerHeight;

    // Last item target at the end
    height += config.lastItemTargetHeight;

    return height;
  }

  /// Applies alignment adjustment to the calculated offset.
  ///
  /// [topOffset] is subtracted to account for pinned headers, ensuring the
  /// target appears in the visible area below any pinned elements.
  double _applyAlignment(
    double targetOffset,
    double targetHeight,
    ScrollAlignment alignment,
    double topOffset,
  ) {
    if (!hasClients) return targetOffset;

    final viewportDimension = position.viewportDimension;
    final effectiveViewport = viewportDimension - topOffset;

    switch (alignment) {
      case ScrollAlignment.start:
        // Position target just below the pinned area
        return targetOffset - topOffset;
      case ScrollAlignment.center:
        // Center target in the effective viewport (excluding pinned area)
        return targetOffset - topOffset - (effectiveViewport / 2) + (targetHeight / 2);
      case ScrollAlignment.end:
        // Position target at the bottom of the viewport
        return targetOffset - viewportDimension + targetHeight;
    }
  }
}
