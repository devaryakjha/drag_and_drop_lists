import 'package:flutter/material.dart';

/// Callback for building animated items during insertion/removal.
typedef AnimatedItemBuilder = Widget Function(
  BuildContext context,
  int index,
  Animation<double> animation,
);

/// Callback for building items during removal (provides the removed item).
typedef RemovedItemBuilder = Widget Function(
  BuildContext context,
  Animation<double> animation,
);

/// Controller for managing animated list operations.
///
/// This controller wraps a [SliverAnimatedListState] and provides
/// methods for animated insertions and removals.
class AnimatedListController {
  GlobalKey<SliverAnimatedListState>? _listKey;
  final Duration defaultDuration;
  final Curve defaultCurve;

  AnimatedListController({
    this.defaultDuration = const Duration(milliseconds: 300),
    this.defaultCurve = Curves.easeInOut,
  });

  /// The key to attach to the SliverAnimatedList.
  GlobalKey<SliverAnimatedListState> get listKey {
    _listKey ??= GlobalKey<SliverAnimatedListState>();
    return _listKey!;
  }

  /// Whether the list state is available for operations.
  bool get isAttached => _listKey?.currentState != null;

  /// Inserts an item at the given index with animation.
  void insertItem(
    int index, {
    Duration? duration,
  }) {
    _listKey?.currentState?.insertItem(
      index,
      duration: duration ?? defaultDuration,
    );
  }

  /// Removes an item at the given index with animation.
  ///
  /// [builder] is used to build the widget during the removal animation.
  /// The widget will animate out (shrink and fade).
  void removeItem(
    int index,
    RemovedItemBuilder builder, {
    Duration? duration,
  }) {
    _listKey?.currentState?.removeItem(
      index,
      (context, animation) => _buildRemovalAnimation(
        context,
        animation,
        builder,
      ),
      duration: duration ?? defaultDuration,
    );
  }

  /// Builds the removal animation with size and fade transitions.
  Widget _buildRemovalAnimation(
    BuildContext context,
    Animation<double> animation,
    RemovedItemBuilder builder,
  ) {
    return SizeTransition(
      sizeFactor: animation.drive(
        CurveTween(curve: defaultCurve),
      ),
      child: FadeTransition(
        opacity: animation,
        child: builder(context, animation),
      ),
    );
  }

  /// Inserts multiple items starting at the given index.
  void insertAllItems(
    int index,
    int count, {
    Duration? duration,
    Duration? staggerDelay,
  }) {
    final effectiveDuration = duration ?? defaultDuration;
    final effectiveDelay = staggerDelay ?? const Duration(milliseconds: 50);

    for (int i = 0; i < count; i++) {
      Future.delayed(effectiveDelay * i, () {
        if (isAttached) {
          insertItem(index + i, duration: effectiveDuration);
        }
      });
    }
  }

  /// Removes multiple items starting at the given index.
  ///
  /// Items are removed in reverse order (from end to start) to maintain
  /// correct indices during the removal process.
  void removeAllItems(
    int index,
    int count,
    RemovedItemBuilder builder, {
    Duration? duration,
    Duration? staggerDelay,
  }) {
    final effectiveDuration = duration ?? defaultDuration;
    final effectiveDelay = staggerDelay ?? const Duration(milliseconds: 50);

    // Remove in reverse order to maintain indices
    for (int i = count - 1; i >= 0; i--) {
      Future.delayed(effectiveDelay * (count - 1 - i), () {
        if (isAttached) {
          removeItem(index + i, builder, duration: effectiveDuration);
        }
      });
    }
  }
}

/// Extension to create removal animation widgets easily.
extension AnimatedRemovalExtension on Widget {
  /// Wraps this widget in a removal animation.
  Widget animateRemoval(Animation<double> animation, {Curve curve = Curves.easeInOut}) {
    return SizeTransition(
      sizeFactor: animation.drive(CurveTween(curve: curve)),
      child: FadeTransition(
        opacity: animation,
        child: this,
      ),
    );
  }
}
