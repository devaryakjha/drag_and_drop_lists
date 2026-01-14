import 'package:drag_and_drop_lists/drag_and_drop_builder_parameters.dart';
import 'package:drag_and_drop_lists/drag_and_drop_item.dart';
import 'package:drag_and_drop_lists/drag_and_drop_item_target.dart';
import 'package:drag_and_drop_lists/drag_and_drop_item_wrapper.dart';
import 'package:drag_and_drop_lists/drag_and_drop_list_interface.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/widgets.dart';

class DragAndDropList implements DragAndDropListExpansionInterface {
  /// The widget that is displayed at the top of the list.
  final Widget? header;

  /// The widget that is displayed at the bottom of the list.
  final Widget? footer;

  /// The widget that is displayed to the left of the list.
  final Widget? leftSide;

  /// The widget that is displayed to the right of the list.
  final Widget? rightSide;

  /// The widget to be displayed when a list is empty.
  /// If this is not null, it will override that set in [DragAndDropLists.contentsWhenEmpty].
  final Widget? contentsWhenEmpty;

  /// The widget to be displayed as the last element in the list that will accept
  /// a dragged item.
  final Widget? lastTarget;

  /// The decoration displayed around a list.
  /// If this is not null, it will override that set in [DragAndDropLists.listDecoration].
  final Decoration? decoration;

  /// The decoration displayed in front of a list.
  /// If this is not null, it will override that set in [DragAndDropLists.listForegroundDecoration].
  final Decoration? foregroundDecoration;

  /// The vertical alignment of the contents in this list.
  /// If this is not null, it will override that set in [DragAndDropLists.verticalAlignment].
  final CrossAxisAlignment verticalAlignment;

  /// The horizontal alignment of the contents in this list.
  /// If this is not null, it will override that set in [DragAndDropLists.horizontalAlignment].
  final MainAxisAlignment horizontalAlignment;

  /// The child elements that will be contained in this list.
  /// It is possible to not provide any children when an empty list is desired.
  @override
  final List<DragAndDropItem> children;

  /// Whether or not this item can be dragged.
  /// Set to true if it can be reordered.
  /// Set to false if it must remain fixed.
  @override
  final bool canDrag;
  @override
  final Key? key;

  /// Whether the list starts expanded. Defaults to true.
  final bool initiallyExpanded;

  // Expansion state
  final ValueNotifier<bool> _expanded;

  @override
  bool get isExpanded => _expanded.value;

  @override
  ValueListenable<bool> get expansionListenable => _expanded;

  @override
  void expand() {
    if (!_expanded.value) {
      _expanded.value = true;
    }
  }

  @override
  void collapse() {
    if (_expanded.value) {
      _expanded.value = false;
    }
  }

  @override
  void toggleExpanded() {
    _expanded.value = !_expanded.value;
  }

  DragAndDropList({
    required this.children,
    this.key,
    this.header,
    this.footer,
    this.leftSide,
    this.rightSide,
    this.contentsWhenEmpty,
    this.lastTarget,
    this.decoration,
    this.foregroundDecoration,
    this.horizontalAlignment = MainAxisAlignment.start,
    this.verticalAlignment = CrossAxisAlignment.start,
    this.canDrag = true,
    this.initiallyExpanded = true,
    ValueNotifier<bool>? expandedNotifier,
  }) : _expanded = expandedNotifier ?? ValueNotifier<bool>(initiallyExpanded);

  @override
  Widget generateWidget(DragAndDropBuilderParameters params) {
    return ValueListenableBuilder<bool>(
      valueListenable: _expanded,
      builder: (context, expanded, _) {
        var contents = <Widget>[];
        if (header != null) {
          contents.add(Flexible(child: header!));
        }

        // Build expandable content - always build it so width stays constant
        Widget expandableContent = IntrinsicHeight(
          child: Row(
            mainAxisAlignment: horizontalAlignment,
            mainAxisSize: MainAxisSize.max,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: _generateDragAndDropListInnerContents(params),
          ),
        );
        if (params.axis == Axis.horizontal) {
          expandableContent = SizedBox(
            width: params.listWidth,
            child: expandableContent,
          );
        }
        if (params.listInnerDecoration != null) {
          expandableContent = Container(
            decoration: params.listInnerDecoration,
            child: expandableContent,
          );
        }

        // Use TweenAnimationBuilder to animate heightFactor for smooth collapse/expand.
        // This ensures content is gradually revealed/hidden, not instantly clipped.
        contents.add(
          TweenAnimationBuilder<double>(
            tween: Tween<double>(end: expanded ? 1.0 : 0.0),
            duration: expanded
                ? params.autoCollapseConfig.expandAnimationDuration
                : params.autoCollapseConfig.collapseAnimationDuration,
            curve: Curves.easeInOut,
            builder: (context, heightFactor, child) {
              return ClipRect(
                child: Align(
                  alignment: Alignment.topCenter,
                  heightFactor: heightFactor,
                  child: child,
                ),
              );
            },
            child: expandableContent,
          ),
        );

        if (expanded && footer != null) {
          contents.add(Flexible(child: footer!));
        }

        return Container(
          key: key,
          width: params.axis == Axis.vertical
              ? double.infinity
              : params.listWidth - params.listPadding!.horizontal,
          decoration: decoration ?? params.listDecoration,
          foregroundDecoration:
              foregroundDecoration ?? params.listForegroundDecoration,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: verticalAlignment,
            children: contents,
          ),
        );
      },
    );
  }

  List<Widget> _generateDragAndDropListInnerContents(
      DragAndDropBuilderParameters parameters) {
    var contents = <Widget>[];
    if (leftSide != null) {
      contents.add(leftSide!);
    }
    if (children.isNotEmpty) {
      List<Widget> allChildren = <Widget>[];
      if (parameters.addLastItemTargetHeightToTop) {
        allChildren.add(Padding(
          padding: EdgeInsets.only(top: parameters.lastItemTargetHeight),
        ));
      }
      for (int i = 0; i < children.length; i++) {
        allChildren.add(DragAndDropItemWrapper(
          key: children[i].key,
          child: children[i],
          parameters: parameters,
        ));
        if (parameters.itemDivider != null && i < children.length - 1) {
          allChildren.add(parameters.itemDivider!);
        }
      }
      allChildren.add(DragAndDropItemTarget(
        parent: this,
        parameters: parameters,
        onReorderOrAdd: parameters.onItemDropOnLastTarget!,
        child: lastTarget ??
            Container(
              height: parameters.lastItemTargetHeight,
            ),
      ));
      contents.add(
        Expanded(
          child: SingleChildScrollView(
            physics: const NeverScrollableScrollPhysics(),
            child: Column(
              crossAxisAlignment: verticalAlignment,
              mainAxisSize: MainAxisSize.max,
              children: allChildren,
            ),
          ),
        ),
      );
    } else {
      contents.add(
        Expanded(
          child: SingleChildScrollView(
            physics: const NeverScrollableScrollPhysics(),
            child: Column(
              mainAxisSize: MainAxisSize.max,
              children: <Widget>[
                contentsWhenEmpty ??
                    const Text(
                      'Empty list',
                      style: TextStyle(
                        fontStyle: FontStyle.italic,
                      ),
                    ),
                DragAndDropItemTarget(
                  parent: this,
                  parameters: parameters,
                  onReorderOrAdd: parameters.onItemDropOnLastTarget!,
                  child: lastTarget ??
                      Container(
                        height: parameters.lastItemTargetHeight,
                      ),
                ),
              ],
            ),
          ),
        ),
      );
    }
    if (rightSide != null) {
      contents.add(rightSide!);
    }
    return contents;
  }
}
