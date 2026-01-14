import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';

/// A sliver that scales its child's extent by a [factor] between 0.0 and 1.0.
///
/// This is useful for creating collapse/expand animations where the sliver
/// smoothly transitions between fully visible (factor = 1.0) and hidden
/// (factor = 0.0) without triggering layout recalculations on every frame.
///
/// Unlike [SizeTransition], this widget operates at the sliver level and
/// efficiently scales the sliver geometry rather than rebuilding the widget.
class SliverFractionalHeight extends SingleChildRenderObjectWidget {
  const SliverFractionalHeight({
    super.key,
    required this.factor,
    required Widget child,
  }) : super(child: child);

  /// The fraction of the child's height to display, from 0.0 to 1.0.
  final double factor;

  @override
  RenderSliverFractionalHeight createRenderObject(BuildContext context) {
    return RenderSliverFractionalHeight(factor: factor);
  }

  @override
  void updateRenderObject(
    BuildContext context,
    RenderSliverFractionalHeight renderObject,
  ) {
    renderObject.factor = factor;
  }
}

class RenderSliverFractionalHeight extends RenderSliver
    with RenderObjectWithChildMixin<RenderSliver> {
  RenderSliverFractionalHeight({required double factor}) : _factor = factor;

  double _factor;
  double get factor => _factor;
  set factor(double value) {
    if (_factor == value) return;
    _factor = value;
    markNeedsLayout();
  }

  @override
  void setupParentData(RenderObject child) {
    if (child.parentData is! SliverPhysicalParentData) {
      child.parentData = SliverPhysicalParentData();
    }
  }

  @override
  void performLayout() {
    if (child == null) {
      geometry = SliverGeometry.zero;
      return;
    }
    child!.layout(constraints, parentUsesSize: true);
    final childGeometry = child!.geometry!;
    final scrollExtent = childGeometry.scrollExtent * _factor;
    final paintExtent = (childGeometry.paintExtent * _factor).clamp(
      0.0,
      constraints.remainingPaintExtent,
    );
    final maxPaintExtent = childGeometry.maxPaintExtent * _factor;
    // layoutExtent must be <= paintExtent
    final layoutExtent = (childGeometry.layoutExtent * _factor).clamp(
      0.0,
      paintExtent,
    );

    geometry = SliverGeometry(
      scrollExtent: scrollExtent,
      paintExtent: paintExtent,
      maxPaintExtent: maxPaintExtent,
      layoutExtent: layoutExtent,
      hasVisualOverflow: childGeometry.hasVisualOverflow || _factor < 1.0,
      cacheExtent: childGeometry.cacheExtent * _factor,
    );
  }

  @override
  void paint(PaintingContext context, Offset offset) {
    if (child != null && geometry!.visible) {
      context.paintChild(child!, offset);
    }
  }

  @override
  bool hitTestChildren(
    SliverHitTestResult result, {
    required double mainAxisPosition,
    required double crossAxisPosition,
  }) {
    if (child != null) {
      return child!.hitTest(
        result,
        mainAxisPosition: mainAxisPosition,
        crossAxisPosition: crossAxisPosition,
      );
    }
    return false;
  }

  @override
  void applyPaintTransform(RenderObject child, Matrix4 transform) {}
}
