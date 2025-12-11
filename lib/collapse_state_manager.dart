import 'dart:async';

import 'package:drag_and_drop_lists/auto_collapse_config.dart';
import 'package:drag_and_drop_lists/drag_and_drop_item.dart';
import 'package:drag_and_drop_lists/drag_and_drop_list_interface.dart';
import 'package:flutter/widgets.dart';

/// Enable/disable logging for debugging collapse behavior.
/// Set via [CollapseStateManager.enableLogging].
bool _enableCollapseLogging = false;

void _log(String message) {
  if (_enableCollapseLogging) {
    debugPrint('[CollapseManager] $message');
  }
}

/// Manages the state of list expansion during drag operations.
///
/// This class handles saving, collapsing, and restoring expansion states
/// for [DragAndDropListExpansionInterface] lists. It ensures smooth
/// transitions and proper state restoration even in edge cases.
class CollapseStateManager {
  /// Configuration for the auto-collapse behavior.
  final AutoCollapseConfig config;

  /// Callback to get the current scroll controller.
  final ScrollController? Function() getScrollController;

  /// Callback to get the current list of children.
  final List<DragAndDropListInterface> Function() getChildren;

  /// The saved expansion states before collapse.
  /// Uses both key and index for redundancy.
  final Map<_ListIdentifier, bool> _savedExpansionStates = {};

  /// Whether lists are currently collapsed for a drag operation.
  bool _isCollapsed = false;

  /// The list that is currently being dragged.
  DragAndDropListInterface? _draggingList;

  /// The item that is currently being dragged.
  DragAndDropItem? _draggingItem;

  /// Timer for delayed collapse.
  Timer? _collapseDelayTimer;

  /// Whether a collapse operation is in progress.
  bool _collapseInProgress = false;

  /// Whether a restore operation is in progress.
  bool _restoreInProgress = false;

  /// The index where the list was dropped.
  int? droppedListIndex;

  /// Creates a new [CollapseStateManager].
  CollapseStateManager({
    required this.config,
    required this.getScrollController,
    required this.getChildren,
  });

  /// Enable or disable debug logging for collapse behavior.
  ///
  /// When enabled, detailed logs are printed to help debug drag-drop issues.
  /// Disabled by default.
  static set enableLogging(bool value) => _enableCollapseLogging = value;

  /// Whether debug logging is currently enabled.
  static bool get enableLogging => _enableCollapseLogging;

  /// Whether lists are currently collapsed for drag.
  bool get isCollapsed => _isCollapsed;

  /// Whether a collapse operation is in progress.
  bool get isCollapseInProgress => _collapseInProgress;

  /// Whether a restore operation is in progress.
  bool get isRestoreInProgress => _restoreInProgress;

  /// The currently dragging list, if any.
  DragAndDropListInterface? get draggingList => _draggingList;

  /// The currently dragging item, if any.
  DragAndDropItem? get draggingItem => _draggingItem;

  /// Called when a list drag starts.
  ///
  /// This triggers the collapse operation after the configured delay.
  Future<void> onListDragStart(DragAndDropListInterface list) async {
    _log('onListDragStart() called - list: ${list.runtimeType}, key: ${list.key}');
    _log('  config.enabled: ${config.enabled}');
    _log('  previous state: _isCollapsed=$_isCollapsed, _restoreInProgress=$_restoreInProgress, _collapseInProgress=$_collapseInProgress');

    if (!config.enabled) {
      _log('  -> returning early, config not enabled');
      return;
    }

    // Reset state on new drag start - this handles cases where:
    // 1. Previous drag ended abnormally (widget disposed mid-drag)
    // 2. Widget rebuild created new expanded list instances
    // 3. Drag callbacks fired multiple times
    _isCollapsed = false;
    _restoreInProgress = false;
    _collapseInProgress = false;

    _draggingList = list;
    _draggingItem = null;
    droppedListIndex = null;

    _log('  -> scheduling collapse');
    await _scheduleCollapse();
    _log('  -> collapse scheduled/completed');
  }

  /// Called when an item drag starts.
  ///
  /// This triggers the collapse operation if [AutoCollapseConfig.collapseOnItemDrag]
  /// is enabled.
  Future<void> onItemDragStart(DragAndDropItem item) async {
    if (!config.enabled || !config.collapseOnItemDrag) return;

    // Reset state on new drag start (same as onListDragStart)
    _isCollapsed = false;
    _restoreInProgress = false;
    _collapseInProgress = false;

    _draggingItem = item;
    _draggingList = null;
    droppedListIndex = null;

    await _scheduleCollapse();
  }

  /// Called when a list drag ends.
  ///
  /// This triggers the restoration of expansion states.
  Future<void> onListDragEnd({int? newListIndex}) async {
    _log('onListDragEnd() called - newListIndex: $newListIndex');
    _log('  config.enabled: ${config.enabled}');
    _log('  previous state: _isCollapsed=$_isCollapsed, _restoreInProgress=$_restoreInProgress, _collapseInProgress=$_collapseInProgress');
    _log('  _savedExpansionStates: $_savedExpansionStates');

    if (!config.enabled) {
      _log('  -> returning early, config not enabled');
      return;
    }

    // Clear dragging reference FIRST to prevent onWidgetUpdate from
    // re-collapsing during the restore phase
    _log('  -> clearing _draggingList reference');
    _draggingList = null;

    _cancelCollapseDelay();
    droppedListIndex = newListIndex;
    _log('  -> droppedListIndex set to: $droppedListIndex');

    if (_isCollapsed) {
      _log('  -> calling _restoreExpansionStates()');
      await _restoreExpansionStates();
      _log('  -> _restoreExpansionStates() completed');
    } else {
      _log('  -> NOT calling _restoreExpansionStates() because _isCollapsed=$_isCollapsed');
    }
  }

  /// Called when the widget tree might have changed during drag.
  ///
  /// This re-collapses any lists that may have been recreated with
  /// expanded state due to widget rebuilds. Should be called from
  /// [State.didUpdateWidget] or when children change during drag.
  void onWidgetUpdate() {
    _log('onWidgetUpdate() called');
    _log('  config.enabled: ${config.enabled}');
    _log('  _restoreInProgress: $_restoreInProgress, _collapseInProgress: $_collapseInProgress');
    _log('  _draggingList: $_draggingList, _draggingItem: $_draggingItem');

    if (!config.enabled) {
      _log('  -> returning early, config not enabled');
      return;
    }

    // Don't do anything if we're in the middle of restoring or collapsing
    if (_restoreInProgress || _collapseInProgress) {
      _log('  -> returning early, restore or collapse in progress');
      return;
    }

    // Only re-collapse if we're actively dragging
    final isDragging = _draggingList != null || _draggingItem != null;
    if (!isDragging) {
      _log('  -> returning early, not currently dragging');
      return;
    }

    // Check if any list is unexpectedly expanded
    final children = getChildren();
    _log('  checking ${children.length} children for unexpectedly expanded lists');
    final anyUnexpectedlyExpanded = children.any((list) {
      if (list is! DragAndDropListExpansionInterface) return false;
      if (!list.isExpanded) return false;
      // Dragging list is allowed to be expanded
      if (config.excludeDraggingList && identical(list, _draggingList)) {
        _log('    list ${list.key} is expanded but is the dragging list, skipping');
        return false;
      }
      _log('    list ${list.key} is UNEXPECTEDLY expanded!');
      return true;
    });

    if (anyUnexpectedlyExpanded) {
      _log('  -> re-collapsing lists due to unexpected expansion');
      // Re-collapse - fire and forget
      _collapseAllLists();
    } else {
      _log('  -> no unexpectedly expanded lists found');
    }
  }

  /// Called when an item drag ends.
  Future<void> onItemDragEnd() async {
    if (!config.enabled || !config.collapseOnItemDrag) return;

    // Clear dragging reference FIRST to prevent onWidgetUpdate from
    // re-collapsing during the restore phase
    _draggingItem = null;

    _cancelCollapseDelay();

    if (_isCollapsed) {
      await _restoreExpansionStates();
    }
  }

  /// Schedules a collapse operation after the configured delay.
  Future<void> _scheduleCollapse() async {
    _cancelCollapseDelay();

    if (config.collapseDelay == Duration.zero) {
      await _collapseAllLists();
    } else {
      final completer = Completer<void>();
      _collapseDelayTimer = Timer(config.collapseDelay, () async {
        await _collapseAllLists();
        completer.complete();
      });
      await completer.future;
    }
  }

  /// Cancels any pending collapse delay.
  void _cancelCollapseDelay() {
    _collapseDelayTimer?.cancel();
    _collapseDelayTimer = null;
  }

  /// Collapses all lists (except optionally the dragging list).
  Future<void> _collapseAllLists() async {
    _log('_collapseAllLists() called');
    _log('  _collapseInProgress: $_collapseInProgress, _isCollapsed: $_isCollapsed');

    // Only check _collapseInProgress, not _isCollapsed
    // This allows re-collapse if lists were expanded mid-drag (e.g., widget rebuild)
    if (_collapseInProgress) {
      _log('  -> returning early, collapse already in progress');
      return;
    }

    _collapseInProgress = true;
    final children = getChildren();
    _log('  processing ${children.length} children');

    // Calculate lists that need to be collapsed
    final listsToCollapse = <DragAndDropListExpansionInterface>[];
    for (var i = 0; i < children.length; i++) {
      final list = children[i];
      if (list is DragAndDropListExpansionInterface && list.isExpanded) {
        // Skip the dragging list if configured
        if (config.excludeDraggingList && identical(list, _draggingList)) {
          _log('    [$i] skipping dragging list (key: ${list.key})');
          continue;
        }
        _log('    [$i] will collapse list (key: ${list.key})');
        listsToCollapse.add(list);
      } else if (list is DragAndDropListExpansionInterface) {
        _log('    [$i] already collapsed (key: ${list.key})');
      }
    }

    // If nothing to collapse, just mark as collapsed and return
    if (listsToCollapse.isEmpty) {
      _log('  -> nothing to collapse, marking as collapsed');
      _isCollapsed = true;
      _collapseInProgress = false;
      return;
    }

    // Save expansion states (only if we haven't already, to preserve original state)
    if (_savedExpansionStates.isEmpty) {
      _log('  saving expansion states...');
      for (var i = 0; i < children.length; i++) {
        final list = children[i];
        if (list is DragAndDropListExpansionInterface) {
          final identifier = _ListIdentifier(index: i, key: list.key);
          _savedExpansionStates[identifier] = list.isExpanded;
          _log('    saved state for [$i] key=${list.key}: ${list.isExpanded}');
        }
      }
    } else {
      _log('  expansion states already saved, skipping');
    }

    // Collapse lists
    _log('  collapsing ${listsToCollapse.length} lists (stagger: ${config.staggerCollapseAnimations})');
    if (config.staggerCollapseAnimations) {
      for (var i = 0; i < listsToCollapse.length; i++) {
        _log('    collapsing list $i');
        listsToCollapse[i].collapse();
        if (i < listsToCollapse.length - 1) {
          await Future.delayed(config.staggerDelay);
        }
      }
    } else {
      for (final list in listsToCollapse) {
        list.collapse();
      }
    }

    _isCollapsed = true;
    _collapseInProgress = false;
    _log('  -> collapse complete, _isCollapsed=$_isCollapsed');
  }

  /// Restores expansion states after drag ends.
  Future<void> _restoreExpansionStates() async {
    _log('_restoreExpansionStates() called');
    _log('  _isCollapsed: $_isCollapsed, _restoreInProgress: $_restoreInProgress');
    _log('  droppedListIndex: $droppedListIndex');
    _log('  _savedExpansionStates: $_savedExpansionStates');

    if (!_isCollapsed || _restoreInProgress) {
      _log('  -> returning early, _isCollapsed=$_isCollapsed, _restoreInProgress=$_restoreInProgress');
      return;
    }

    _restoreInProgress = true;
    final children = getChildren();
    final scrollController = getScrollController();
    _log('  processing ${children.length} children for restore');

    // Build a list of lists to restore, handling reordering
    final listsToRestore = <DragAndDropListExpansionInterface>[];

    for (var i = 0; i < children.length; i++) {
      final list = children[i];
      if (list is DragAndDropListExpansionInterface) {
        // Try to find saved state by key first, then by proximity
        final wasExpanded = _findSavedState(list, i);
        _log('    [$i] key=${list.key}, wasExpanded=$wasExpanded, isExpanded=${list.isExpanded}');
        if (wasExpanded == true && !list.isExpanded) {
          _log('      -> will restore (was expanded, now collapsed)');
          listsToRestore.add(list);
        } else if (wasExpanded == null) {
          _log('      -> no saved state found');
        }
      }
    }

    // Restore expansion states
    _log('  restoring ${listsToRestore.length} lists (stagger: ${config.staggerCollapseAnimations})');
    if (config.staggerCollapseAnimations) {
      for (var i = 0; i < listsToRestore.length; i++) {
        _log('    expanding list $i');
        listsToRestore[i].expand();
        if (i < listsToRestore.length - 1) {
          await Future.delayed(config.staggerDelay);
        }
      }
    } else {
      for (final list in listsToRestore) {
        list.expand();
      }
    }

    // Wait for animations to complete
    _log('  waiting for animation (${config.expandAnimationDuration})');
    await Future.delayed(config.expandAnimationDuration);

    // Scroll to dropped list if configured
    if (config.scrollToDroppedList && droppedListIndex != null) {
      _log('  scrolling to dropped list at index $droppedListIndex');
      await _scrollToDroppedList(scrollController);
    }

    _savedExpansionStates.clear();
    _isCollapsed = false;
    _restoreInProgress = false;
    _log('  -> restore complete, _isCollapsed=$_isCollapsed, _restoreInProgress=$_restoreInProgress');
  }

  /// Finds the saved expansion state for a list.
  ///
  /// Tries to match by key first, then falls back to index proximity.
  bool? _findSavedState(DragAndDropListExpansionInterface list, int currentIndex) {
    // First, try to find by key
    if (list.key != null) {
      for (final entry in _savedExpansionStates.entries) {
        if (entry.key.key == list.key) {
          return entry.value;
        }
      }
    }

    // Fall back to index-based lookup with proximity tolerance
    // This handles cases where lists were reordered
    for (final entry in _savedExpansionStates.entries) {
      if (entry.key.index == currentIndex && entry.key.key == null) {
        return entry.value;
      }
    }

    // If the list was newly added during drag, it won't have saved state
    return null;
  }

  /// Scrolls to the dropped list position.
  Future<void> _scrollToDroppedList(ScrollController? scrollController) async {
    if (droppedListIndex == null ||
        scrollController == null ||
        !scrollController.hasClients) {
      return;
    }

    final children = getChildren();
    final targetIndex = droppedListIndex!;

    if (targetIndex < 0 || targetIndex >= children.length) {
      return;
    }

    // Calculate approximate scroll position
    // This is a rough estimate - for precise scrolling, use DragAndDropScrollController
    final maxScroll = scrollController.position.maxScrollExtent;
    final viewportHeight = scrollController.position.viewportDimension;
    final currentScroll = scrollController.position.pixels;

    // Simple heuristic: if the target might be off-screen, scroll to it
    final estimatedTargetPosition = _estimateListPosition(targetIndex, children);

    double targetOffset;
    switch (config.scrollAlignment) {
      case ScrollToAlignment.start:
        targetOffset = estimatedTargetPosition;
        break;
      case ScrollToAlignment.center:
        targetOffset = estimatedTargetPosition - (viewportHeight / 2);
        break;
      case ScrollToAlignment.end:
        targetOffset = estimatedTargetPosition - viewportHeight;
        break;
      case ScrollToAlignment.nearest:
        // Only scroll if the target is outside the current viewport
        if (estimatedTargetPosition >= currentScroll &&
            estimatedTargetPosition <= currentScroll + viewportHeight) {
          return; // Already visible, no scroll needed
        }
        // Scroll to bring it just into view
        if (estimatedTargetPosition < currentScroll) {
          targetOffset = estimatedTargetPosition;
        } else {
          targetOffset = estimatedTargetPosition - viewportHeight + 100; // Buffer
        }
        break;
    }

    // Clamp to valid range
    targetOffset = targetOffset.clamp(0.0, maxScroll);

    await scrollController.animateTo(
      targetOffset,
      duration: config.scrollToDroppedDuration,
      curve: Curves.easeInOut,
    );
  }

  /// Estimates the scroll position of a list at the given index.
  ///
  /// This is a rough estimate based on average heights.
  /// For precise positioning, use [DragAndDropScrollController].
  double _estimateListPosition(int index, List<DragAndDropListInterface> lists) {
    // Rough estimate: assume each collapsed header is ~56px
    // and each expanded list header is ~56px plus content
    const collapsedHeaderHeight = 56.0;
    const averageExpandedHeight = 200.0;

    double position = 0;
    for (var i = 0; i < index && i < lists.length; i++) {
      final list = lists[i];
      if (list is DragAndDropListExpansionInterface) {
        if (list.isExpanded) {
          position += averageExpandedHeight;
        } else {
          position += collapsedHeaderHeight;
        }
      } else {
        position += averageExpandedHeight;
      }
    }
    return position;
  }

  /// Disposes of any resources.
  void dispose() {
    _cancelCollapseDelay();
    _savedExpansionStates.clear();
  }

  /// Resets the manager state.
  ///
  /// Call this when the widget is rebuilt or the children change significantly.
  void reset() {
    _cancelCollapseDelay();
    _savedExpansionStates.clear();
    _isCollapsed = false;
    _collapseInProgress = false;
    _restoreInProgress = false;
    _draggingList = null;
    _draggingItem = null;
    droppedListIndex = null;
  }
}

/// Identifier for a list, using both key and index for robustness.
class _ListIdentifier {
  final int index;
  final Key? key;

  const _ListIdentifier({required this.index, this.key});

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    if (other is! _ListIdentifier) return false;
    // If both have keys, compare by key
    if (key != null && other.key != null) {
      return key == other.key;
    }
    // Otherwise compare by index
    return index == other.index;
  }

  @override
  int get hashCode => key?.hashCode ?? index.hashCode;

  @override
  String toString() => '_ListIdentifier(index: $index, key: $key)';
}
