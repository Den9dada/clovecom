import 'dart:math' as math;

import 'package:flutter/material.dart';

/// 下拉菜单共用的窗口避让规则：下方放得下时始终向下，否则选择空间更大的一侧。
class DsMenuGeometry {
  const DsMenuGeometry({required this.anchor, required this.bounds});

  final Rect anchor;
  final Rect bounds;

  double get below => math.max(0, bounds.bottom - anchor.bottom);
  double get above => math.max(0, anchor.top - bounds.top);
  double get maxHeight => math.max(below, above);

  Offset position(Size menu) {
    final openBelow = below >= menu.height || below >= above;
    final left = anchor.left.clamp(
      bounds.left,
      math.max(bounds.left, bounds.right - menu.width),
    );
    return Offset(
      left.toDouble(),
      openBelow ? anchor.bottom : anchor.top - menu.height,
    );
  }

  static Rect safeBounds(Size viewport, EdgeInsets padding) => Rect.fromLTRB(
    padding.left + 8,
    padding.top + 8,
    math.max(padding.left + 8, viewport.width - padding.right - 8),
    math.max(padding.top + 8, viewport.height - padding.bottom - 8),
  );
}

/// 动态菜单按实际布局后的高度定位，短列表不会因预估大高度而提前翻转。
class DsAnchoredMenuLayout extends SingleChildLayoutDelegate {
  DsAnchoredMenuLayout({
    required this.anchor,
    required this.padding,
    this.heightLimit = 400,
  });

  final Rect anchor;
  final EdgeInsets padding;
  final double heightLimit;

  DsMenuGeometry _geometry(Size size) => DsMenuGeometry(
    anchor: anchor,
    bounds: DsMenuGeometry.safeBounds(size, padding),
  );

  @override
  BoxConstraints getConstraintsForChild(BoxConstraints constraints) {
    final geometry = _geometry(constraints.biggest);
    return BoxConstraints.tightFor(
      width: math.min(anchor.width, geometry.bounds.width),
    ).copyWith(maxHeight: math.min(heightLimit, geometry.maxHeight));
  }

  @override
  Offset getPositionForChild(Size size, Size childSize) =>
      _geometry(size).position(childSize);

  @override
  bool shouldRelayout(DsAnchoredMenuLayout oldDelegate) =>
      anchor != oldDelegate.anchor ||
      padding != oldDelegate.padding ||
      heightLimit != oldDelegate.heightLimit;
}
