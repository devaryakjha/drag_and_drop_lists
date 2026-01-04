import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/scheduler.dart';

typedef OnWidgetSizeChange = void Function(Size? size);

/// A widget that reports its size after layout.
///
/// Uses a custom RenderObject to efficiently detect size changes,
/// only calling [onSizeChange] when the size actually changes,
/// not on every build.
class MeasureSize extends SingleChildRenderObjectWidget {
  final OnWidgetSizeChange onSizeChange;

  const MeasureSize({
    super.key,
    required this.onSizeChange,
    required super.child,
  });

  @override
  RenderObject createRenderObject(BuildContext context) {
    return MeasureSizeRenderBox(onSizeChange: onSizeChange);
  }

  @override
  void updateRenderObject(
    BuildContext context,
    covariant MeasureSizeRenderBox renderObject,
  ) {
    renderObject.onSizeChange = onSizeChange;
  }
}

/// Custom render box that measures its size and reports changes.
class MeasureSizeRenderBox extends RenderProxyBox {
  /// Callback invoked when size changes.
  OnWidgetSizeChange onSizeChange;
  Size? _oldSize;
  bool _scheduledCallback = false;

  /// Creates a render box that reports size changes.
  MeasureSizeRenderBox({required this.onSizeChange});

  @override
  void performLayout() {
    super.performLayout();

    // Only notify if size actually changed
    if (size != _oldSize && !_scheduledCallback) {
      _scheduledCallback = true;
      // Schedule callback for after the frame to avoid layout during build
      SchedulerBinding.instance.addPostFrameCallback((_) {
        _scheduledCallback = false;
        if (_oldSize != size) {
          _oldSize = size;
          onSizeChange(size);
        }
      });
    }
  }
}
