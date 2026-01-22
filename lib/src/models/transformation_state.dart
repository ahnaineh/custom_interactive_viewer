import 'dart:math';
import 'package:custom_interactive_viewer/src/widget.dart';
import 'package:flutter/material.dart';

/// Represents the transformation state of a [CustomInteractiveViewer].
///
/// Contains information about scale, offset, and rotation, and provides
/// utility methods for working with transformations.
class TransformationState {
  /// The current scale factor.
  final double scale;

  /// The current offset of the content.
  final Offset offset;

  /// The current rotation in radians.
  final double rotation;

  /// Creates a new [TransformationState] with the given values.
  const TransformationState({
    this.scale = 1.0,
    this.offset = Offset.zero,
    this.rotation = 0.0,
  });

  /// Creates a copy of this state with the given fields replaced.
  TransformationState copyWith({
    double? scale,
    Offset? offset,
    double? rotation,
  }) {
    return TransformationState(
      scale: scale ?? this.scale,
      offset: offset ?? this.offset,
      rotation: rotation ?? this.rotation,
    );
  }

  /// Returns a [Matrix4] representing the current transformation.
  Matrix4 toMatrix4() {
    return Matrix4.identity()
      ..translateByDouble(offset.dx, offset.dy, 0, 1)
      ..scaleByDouble(scale, scale, 1, 1)
      ..rotateZ(rotation);
  }

  /// Converts a point from screen coordinates to content coordinates.
  Offset screenToContentPoint(
    Offset screenPoint, {
    Offset alignmentOrigin = Offset.zero,
    Offset alignmentOffset = Offset.zero,
  }) {
    final Offset adjusted =
        screenPoint - alignmentOffset - offset - alignmentOrigin;
    final Offset scaled = adjusted / scale;
    final double cosTheta = cos(rotation);
    final double sinTheta = sin(rotation);
    final Offset unrotated = Offset(
      scaled.dx * cosTheta + scaled.dy * sinTheta,
      -scaled.dx * sinTheta + scaled.dy * cosTheta,
    );
    return unrotated + alignmentOrigin;
  }

  /// Converts a point from content coordinates to screen coordinates.
  Offset contentToScreenPoint(
    Offset contentPoint, {
    Offset alignmentOrigin = Offset.zero,
    Offset alignmentOffset = Offset.zero,
  }) {
    final Offset contentDelta = contentPoint - alignmentOrigin;
    final double cosTheta = cos(rotation);
    final double sinTheta = sin(rotation);
    final Offset rotated = Offset(
      contentDelta.dx * cosTheta - contentDelta.dy * sinTheta,
      contentDelta.dx * sinTheta + contentDelta.dy * cosTheta,
    );
    return alignmentOffset + offset + alignmentOrigin + rotated * scale;
  }

  /// Creates a [TransformationState] to fit the content to the viewport.
  static TransformationState fitContent(
    Size contentSize,
    Size viewportSize, {
    double padding = 20.0,
  }) {
    // Calculate the scale needed to fit the content in the viewport with padding
    final double horizontalScale =
        (viewportSize.width - 2 * padding) / contentSize.width;
    final double verticalScale =
        (viewportSize.height - 2 * padding) / contentSize.height;
    final double targetScale =
        horizontalScale < verticalScale ? horizontalScale : verticalScale;

    // Calculate the offset to center the content
    final Offset targetOffset = Offset(
      (viewportSize.width - contentSize.width * targetScale) / 2,
      (viewportSize.height - contentSize.height * targetScale) / 2,
    );

    return TransformationState(scale: targetScale, offset: targetOffset);
  }

  /// Creates a [TransformationState] to center the content in the viewport.
  static TransformationState centerContent(
    Size contentSize,
    Size viewportSize,
    double scale,
  ) {
    final Offset targetOffset = Offset(
      (viewportSize.width - contentSize.width * scale) / 2,
      (viewportSize.height - contentSize.height * scale) / 2,
    );

    return TransformationState(scale: scale, offset: targetOffset);
  }

  /// Creates a [TransformationState] for zooming to a specific region.
  static TransformationState zoomToRegion(
    Rect region,
    Size viewportSize, {
    double padding = 20.0,
  }) {
    // Calculate the scale needed to fit the region in the viewport with padding
    final double horizontalScale =
        (viewportSize.width - 2 * padding) / region.width;
    final double verticalScale =
        (viewportSize.height - 2 * padding) / region.height;
    final double targetScale =
        horizontalScale < verticalScale ? horizontalScale : verticalScale;

    // Calculate the offset to center the region
    final double centerX = region.left + region.width / 2;
    final double centerY = region.top + region.height / 2;
    final Offset targetOffset = Offset(
      viewportSize.width / 2 - centerX * targetScale,
      viewportSize.height / 2 - centerY * targetScale,
    );

    return TransformationState(scale: targetScale, offset: targetOffset);
  }

  /// Constrains the transformation to the given bounds.
  TransformationState constrainToViewport(
    Size contentSize,
    Size viewportSize, {
    Offset alignmentOrigin = Offset.zero,
    Offset alignmentOffset = Offset.zero,
  }) {
    double newX = offset.dx;
    double newY = offset.dy;

    final List<Offset> corners = <Offset>[
      const Offset(0, 0),
      Offset(contentSize.width, 0),
      Offset(0, contentSize.height),
      Offset(contentSize.width, contentSize.height),
    ];

    double minX = double.infinity;
    double maxX = double.negativeInfinity;
    double minY = double.infinity;
    double maxY = double.negativeInfinity;

    for (final corner in corners) {
      final Offset transformed = contentToScreenPoint(
        corner,
        alignmentOrigin: alignmentOrigin,
        alignmentOffset: alignmentOffset,
      );
      final double x = transformed.dx - offset.dx;
      final double y = transformed.dy - offset.dy;
      minX = min(minX, x);
      maxX = max(maxX, x);
      minY = min(minY, y);
      maxY = max(maxY, y);
    }

    final double rotatedWidth = maxX - minX;
    final double rotatedHeight = maxY - minY;

    if (rotatedWidth <= viewportSize.width) {
      // If rotated content is smaller than viewport, center it horizontally.
      newX = (viewportSize.width - rotatedWidth) / 2 - minX;
    } else {
      // Otherwise restrict panning to keep rotated content filling the viewport.
      final double minOffsetX = viewportSize.width - maxX;
      final double maxOffsetX = -minX;
      newX = newX.clamp(minOffsetX, maxOffsetX);
    }

    if (rotatedHeight <= viewportSize.height) {
      // If rotated content is smaller than viewport, center it vertically.
      newY = (viewportSize.height - rotatedHeight) / 2 - minY;
    } else {
      // Otherwise restrict panning to keep rotated content filling the viewport.
      final double minOffsetY = viewportSize.height - maxY;
      final double maxOffsetY = -minY;
      newY = newY.clamp(minOffsetY, maxOffsetY);
    }

    if (newX == offset.dx && newY == offset.dy) {
      return this;
    }

    return copyWith(offset: Offset(newX, newY));
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is TransformationState &&
        other.scale == scale &&
        other.offset == offset &&
        other.rotation == rotation;
  }

  @override
  int get hashCode => Object.hash(scale, offset, rotation);

  @override
  String toString() =>
      'TransformationState(scale: $scale, offset: $offset, rotation: $rotation)';
}
