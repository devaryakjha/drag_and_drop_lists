import 'package:flutter/widgets.dart';

/// A ghost placeholder widget that animates visibility using opacity instead
/// of size animation.
///
/// This is more performant than [AnimatedSize] because it doesn't trigger
/// layout recalculations on every animation frame - only paint operations.
///
/// When [isVisible] is true, the ghost fades in. When false, it fades out.
/// The [height] should be pre-calculated or obtained from config to avoid
/// runtime measurement.
class AnimatedGhostPlaceholder extends StatefulWidget {
  const AnimatedGhostPlaceholder({
    super.key,
    required this.isVisible,
    required this.child,
    this.height,
    this.opacity = 0.3,
    this.duration = const Duration(milliseconds: 150),
  });

  /// Whether the ghost should be visible.
  final bool isVisible;

  /// The ghost content to display.
  final Widget? child;

  /// Fixed height for the ghost. If null, uses intrinsic sizing.
  /// For best performance, provide a fixed height.
  final double? height;

  /// Opacity of the ghost when visible.
  final double opacity;

  /// Duration of the fade animation.
  final Duration duration;

  @override
  State<AnimatedGhostPlaceholder> createState() =>
      _AnimatedGhostPlaceholderState();
}

class _AnimatedGhostPlaceholderState extends State<AnimatedGhostPlaceholder>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _opacityAnimation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: widget.duration,
      vsync: this,
      value: widget.isVisible ? 1.0 : 0.0,
    );
    _opacityAnimation = CurvedAnimation(
      parent: _controller,
      curve: Curves.easeInOut,
    );
  }

  @override
  void didUpdateWidget(covariant AnimatedGhostPlaceholder oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.duration != oldWidget.duration) {
      _controller.duration = widget.duration;
    }
    if (widget.isVisible != oldWidget.isVisible) {
      if (widget.isVisible) {
        _controller.forward();
      } else {
        _controller.reverse();
      }
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _opacityAnimation,
      builder: (context, child) {
        // Early exit when fully invisible - don't build child
        if (_opacityAnimation.value == 0.0) {
          return const SizedBox.shrink();
        }

        final content = Opacity(
          opacity: _opacityAnimation.value * widget.opacity,
          child: widget.child,
        );

        // Use fixed height if provided for performance
        if (widget.height != null) {
          return SizedBox(
            height: widget.height! * _opacityAnimation.value,
            child: content,
          );
        }

        // Fallback: animate height using ClipRect + Align for dynamic content
        return ClipRect(
          child: Align(
            alignment: Alignment.topCenter,
            heightFactor: _opacityAnimation.value,
            child: content,
          ),
        );
      },
    );
  }
}
