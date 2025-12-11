/// Configuration for the auto-collapse behavior during drag operations.
///
/// This class controls how lists collapse and expand when a drag operation
/// is in progress. The feature provides better visibility and UX when
/// reordering lists by temporarily collapsing expanded lists.
class AutoCollapseConfig {
  /// Whether auto-collapse is enabled.
  ///
  /// When enabled, lists will automatically collapse when a drag operation
  /// starts and restore to their previous state when the drag ends.
  /// Defaults to `true`.
  final bool enabled;

  /// Whether to also collapse lists when an item (not a list) is being dragged.
  ///
  /// When `true`, dragging an item between lists will also trigger the
  /// collapse behavior. This can help users see all available drop targets.
  /// Defaults to `false`.
  final bool collapseOnItemDrag;

  /// Duration of the collapse animation.
  ///
  /// This should match or be slightly shorter than the animation duration
  /// of [ProgrammaticExpansionTile] (200ms by default).
  /// Defaults to 200ms.
  final Duration collapseAnimationDuration;

  /// Duration of the expand animation when restoring states.
  ///
  /// Defaults to 200ms.
  final Duration expandAnimationDuration;

  /// Duration of the scroll animation when scrolling to the dropped list.
  ///
  /// Defaults to 300ms.
  final Duration scrollToDroppedDuration;

  /// Whether to maintain the visual scroll position when collapsing.
  ///
  /// When `true`, the scroll position will be adjusted during collapse
  /// to keep the dragged item in approximately the same visual position.
  /// This prevents disorienting jumps in the UI.
  /// Defaults to `true`.
  final bool maintainScrollPosition;

  /// Whether to exclude the currently dragged list from collapsing.
  ///
  /// When `true`, the list being dragged will not be collapsed, allowing
  /// users to see its full content while dragging.
  /// Defaults to `true`.
  final bool excludeDraggingList;

  /// Delay before starting the collapse operation.
  ///
  /// A small delay can help avoid visual jank if the drag is very short
  /// (e.g., accidental touch). Set to [Duration.zero] for immediate collapse.
  /// Defaults to 50ms.
  final Duration collapseDelay;

  /// Whether to scroll to the dropped list after drag ends.
  ///
  /// When `true` and the dropped list position might be out of view,
  /// the view will automatically scroll to show the dropped list.
  /// Defaults to `true`.
  final bool scrollToDroppedList;

  /// Alignment for scroll-to-dropped-list operation.
  ///
  /// Controls where in the viewport the dropped list should appear.
  /// Uses [ScrollAlignment] values.
  final ScrollToAlignment scrollAlignment;

  /// Whether to stagger the collapse animations for a smoother effect.
  ///
  /// When `true`, lists will collapse with a slight delay between each,
  /// creating a cascading effect. When `false`, all collapse simultaneously.
  /// Defaults to `false`.
  final bool staggerCollapseAnimations;

  /// Delay between each list's collapse animation when [staggerCollapseAnimations] is true.
  ///
  /// Defaults to 30ms.
  final Duration staggerDelay;

  const AutoCollapseConfig({
    this.enabled = true,
    this.collapseOnItemDrag = false,
    this.collapseAnimationDuration = const Duration(milliseconds: 200),
    this.expandAnimationDuration = const Duration(milliseconds: 200),
    this.scrollToDroppedDuration = const Duration(milliseconds: 300),
    this.maintainScrollPosition = true,
    this.excludeDraggingList = true,
    this.collapseDelay = const Duration(milliseconds: 50),
    this.scrollToDroppedList = true,
    this.scrollAlignment = ScrollToAlignment.start,
    this.staggerCollapseAnimations = false,
    this.staggerDelay = const Duration(milliseconds: 30),
  });

  /// A configuration with auto-collapse disabled.
  static const AutoCollapseConfig disabled = AutoCollapseConfig(enabled: false);

  /// Creates a copy of this config with the given fields replaced.
  AutoCollapseConfig copyWith({
    bool? enabled,
    bool? collapseOnItemDrag,
    Duration? collapseAnimationDuration,
    Duration? expandAnimationDuration,
    Duration? scrollToDroppedDuration,
    bool? maintainScrollPosition,
    bool? excludeDraggingList,
    Duration? collapseDelay,
    bool? scrollToDroppedList,
    ScrollToAlignment? scrollAlignment,
    bool? staggerCollapseAnimations,
    Duration? staggerDelay,
  }) {
    return AutoCollapseConfig(
      enabled: enabled ?? this.enabled,
      collapseOnItemDrag: collapseOnItemDrag ?? this.collapseOnItemDrag,
      collapseAnimationDuration:
          collapseAnimationDuration ?? this.collapseAnimationDuration,
      expandAnimationDuration:
          expandAnimationDuration ?? this.expandAnimationDuration,
      scrollToDroppedDuration:
          scrollToDroppedDuration ?? this.scrollToDroppedDuration,
      maintainScrollPosition:
          maintainScrollPosition ?? this.maintainScrollPosition,
      excludeDraggingList: excludeDraggingList ?? this.excludeDraggingList,
      collapseDelay: collapseDelay ?? this.collapseDelay,
      scrollToDroppedList: scrollToDroppedList ?? this.scrollToDroppedList,
      scrollAlignment: scrollAlignment ?? this.scrollAlignment,
      staggerCollapseAnimations:
          staggerCollapseAnimations ?? this.staggerCollapseAnimations,
      staggerDelay: staggerDelay ?? this.staggerDelay,
    );
  }
}

/// Alignment options for scroll-to-dropped-list operations.
enum ScrollToAlignment {
  /// Align the target at the start/top of the viewport.
  start,

  /// Align the target at the center of the viewport.
  center,

  /// Align the target at the end/bottom of the viewport.
  end,

  /// Only scroll if the target is not already visible.
  /// If visible, no scrolling occurs.
  nearest,
}
