import 'dart:math' as math;
import 'package:custom_interactive_viewer/src/enums/scroll_mode.dart';
import 'package:custom_interactive_viewer/src/models/transformation_state.dart';
import 'package:flutter/widgets.dart';

@immutable
class InteractionRequest {
  final Offset? panDelta;
  final double? scale;
  final double? rotation;
  final Offset? focalPoint;
  final bool includePanDeltaWhenScaling;

  const InteractionRequest({
    this.panDelta,
    this.scale,
    this.rotation,
    this.focalPoint,
    this.includePanDeltaWhenScaling = false,
  });

  bool get hasScaleOrRotate => scale != null || rotation != null;

  InteractionRequest copyWith({
    Offset? panDelta,
    double? scale,
    double? rotation,
    Offset? focalPoint,
    bool? includePanDeltaWhenScaling,
  }) {
    return InteractionRequest(
      panDelta: panDelta ?? this.panDelta,
      scale: scale ?? this.scale,
      rotation: rotation ?? this.rotation,
      focalPoint: focalPoint ?? this.focalPoint,
      includePanDeltaWhenScaling:
          includePanDeltaWhenScaling ?? this.includePanDeltaWhenScaling,
    );
  }
}

@immutable
class InteractionContext {
  final TransformationState state;
  final Size? contentSize;
  final Size? viewportSize;
  final double? minScale;
  final double? maxScale;
  final Alignment alignment;
  final Offset alignmentOrigin;
  final Offset alignmentOffset;

  const InteractionContext({
    required this.state,
    required this.contentSize,
    required this.viewportSize,
    required this.minScale,
    required this.maxScale,
    this.alignment = Alignment.topLeft,
    this.alignmentOrigin = Offset.zero,
    this.alignmentOffset = Offset.zero,
  });

  InteractionContext copyWith({
    TransformationState? state,
    Size? contentSize,
    Size? viewportSize,
    double? minScale,
    double? maxScale,
    Alignment? alignment,
    Offset? alignmentOrigin,
    Offset? alignmentOffset,
  }) {
    return InteractionContext(
      state: state ?? this.state,
      contentSize: contentSize ?? this.contentSize,
      viewportSize: viewportSize ?? this.viewportSize,
      minScale: minScale ?? this.minScale,
      maxScale: maxScale ?? this.maxScale,
      alignment: alignment ?? this.alignment,
      alignmentOrigin: alignmentOrigin ?? this.alignmentOrigin,
      alignmentOffset: alignmentOffset ?? this.alignmentOffset,
    );
  }
}

abstract class InteractionBehavior {
  const InteractionBehavior();

  InteractionRequest onRequest(
    InteractionRequest request,
    InteractionContext context,
  ) {
    return request;
  }

  TransformationState onResult(
    TransformationState state,
    InteractionContext context,
  ) {
    return state;
  }

  const factory InteractionBehavior.none() = _NoopInteractionBehavior;

  factory InteractionBehavior.combine(List<InteractionBehavior> behaviors) {
    if (behaviors.isEmpty) {
      return const _NoopInteractionBehavior();
    }
    if (behaviors.length == 1) {
      return behaviors.first;
    }
    return _CompositeInteractionBehavior(behaviors);
  }
}

class _NoopInteractionBehavior extends InteractionBehavior {
  const _NoopInteractionBehavior();
}

class _CompositeInteractionBehavior extends InteractionBehavior {
  final List<InteractionBehavior> _behaviors;

  _CompositeInteractionBehavior(List<InteractionBehavior> behaviors)
    : _behaviors = List<InteractionBehavior>.unmodifiable(behaviors);

  @override
  InteractionRequest onRequest(
    InteractionRequest request,
    InteractionContext context,
  ) {
    InteractionRequest nextRequest = request;
    for (final behavior in _behaviors) {
      nextRequest = behavior.onRequest(nextRequest, context);
    }
    return nextRequest;
  }

  @override
  TransformationState onResult(
    TransformationState state,
    InteractionContext context,
  ) {
    TransformationState nextState = state;
    for (final behavior in _behaviors) {
      final InteractionContext nextContext = context.copyWith(state: nextState);
      nextState = behavior.onResult(nextState, nextContext);
    }
    return nextState;
  }
}

class ScrollModeBehavior extends InteractionBehavior {
  final ScrollMode scrollMode;

  const ScrollModeBehavior(this.scrollMode);

  @override
  InteractionRequest onRequest(
    InteractionRequest request,
    InteractionContext context,
  ) {
    if (request.panDelta == null) {
      return request;
    }

    final Offset panDelta = request.panDelta!;
    final Offset constrainedDelta;
    switch (scrollMode) {
      case ScrollMode.horizontal:
        constrainedDelta = Offset(panDelta.dx, 0);
        break;
      case ScrollMode.vertical:
        constrainedDelta = Offset(0, panDelta.dy);
        break;
      case ScrollMode.none:
        constrainedDelta = Offset.zero;
        break;
      case ScrollMode.both:
        constrainedDelta = panDelta;
        break;
    }

    return request.copyWith(panDelta: constrainedDelta);
  }
}

enum AxisLock { none, horizontal, vertical, dominant }

class AxisLockBehavior extends InteractionBehavior {
  final AxisLock axisLock;

  const AxisLockBehavior(this.axisLock);

  @override
  InteractionRequest onRequest(
    InteractionRequest request,
    InteractionContext context,
  ) {
    if (axisLock == AxisLock.none || request.panDelta == null) {
      return request;
    }

    final Offset panDelta = request.panDelta!;
    final double absX = panDelta.dx.abs();
    final double absY = panDelta.dy.abs();

    final Offset lockedDelta;
    switch (axisLock) {
      case AxisLock.horizontal:
        lockedDelta = Offset(panDelta.dx, 0);
        break;
      case AxisLock.vertical:
        lockedDelta = Offset(0, panDelta.dy);
        break;
      case AxisLock.dominant:
        lockedDelta =
            absX >= absY ? Offset(panDelta.dx, 0) : Offset(0, panDelta.dy);
        break;
      case AxisLock.none:
        lockedDelta = panDelta;
        break;
    }

    return request.copyWith(panDelta: lockedDelta);
  }
}

class SnapToGridBehavior extends InteractionBehavior {
  final Offset gridSize;
  final double? scaleStep;

  const SnapToGridBehavior({
    required this.gridSize,
    this.scaleStep,
  });

  @override
  TransformationState onResult(
    TransformationState state,
    InteractionContext context,
  ) {
    final double snappedX =
        gridSize.dx == 0
            ? state.offset.dx
            : (state.offset.dx / gridSize.dx).roundToDouble() * gridSize.dx;
    final double snappedY =
        gridSize.dy == 0
            ? state.offset.dy
            : (state.offset.dy / gridSize.dy).roundToDouble() * gridSize.dy;

    double snappedScale = state.scale;
    if (scaleStep != null && scaleStep! > 0) {
      snappedScale = (state.scale / scaleStep!).roundToDouble() * scaleStep!;
      final double? minScale = context.minScale;
      final double? maxScale = context.maxScale;
      if (minScale != null || maxScale != null) {
        snappedScale = snappedScale.clamp(
          minScale ?? snappedScale,
          maxScale ?? snappedScale,
        );
      }
    }

    return state.copyWith(
      offset: Offset(snappedX, snappedY),
      scale: snappedScale,
    );
  }
}

abstract class BoundsBehavior extends InteractionBehavior {
  const BoundsBehavior();

  @override
  TransformationState onResult(
    TransformationState state,
    InteractionContext context,
  );
}

class ViewportBoundsBehavior extends BoundsBehavior {
  const ViewportBoundsBehavior();

  @override
  TransformationState onResult(
    TransformationState state,
    InteractionContext context,
  ) {
    final Size? contentSize = context.contentSize;
    final Size? viewportSize = context.viewportSize;
    if (contentSize == null || viewportSize == null) {
      return state;
    }
    return state.constrainToViewport(
      contentSize,
      viewportSize,
      alignmentOrigin: context.alignmentOrigin,
      alignmentOffset: context.alignmentOffset,
    );
  }
}

class InteractionTransformer {
  const InteractionTransformer();

  static TransformationState apply({
    required TransformationState state,
    required InteractionRequest request,
    Offset alignmentOrigin = Offset.zero,
    Offset alignmentOffset = Offset.zero,
  }) {
    final double targetScale = request.scale ?? state.scale;
    final double targetRotation = request.rotation ?? state.rotation;

    Offset targetOffset = state.offset;
    if (request.hasScaleOrRotate && request.focalPoint != null) {
      final Offset focalPoint = request.focalPoint!;
      final Offset contentPoint = state.screenToContentPoint(
        focalPoint,
        alignmentOrigin: alignmentOrigin,
        alignmentOffset: alignmentOffset,
      );
      final Offset contentDelta = contentPoint - alignmentOrigin;
      final double cosTheta = math.cos(targetRotation);
      final double sinTheta = math.sin(targetRotation);
      final Offset rotatedContent = Offset(
        contentDelta.dx * cosTheta - contentDelta.dy * sinTheta,
        contentDelta.dx * sinTheta + contentDelta.dy * cosTheta,
      );
      targetOffset =
          focalPoint -
          alignmentOffset -
          alignmentOrigin -
          rotatedContent * targetScale;
      if (request.includePanDeltaWhenScaling && request.panDelta != null) {
        targetOffset += request.panDelta!;
      }
    } else if (request.panDelta != null &&
        (!request.hasScaleOrRotate || request.includePanDeltaWhenScaling)) {
      targetOffset = targetOffset + request.panDelta!;
    }

    return state.copyWith(
      scale: targetScale,
      rotation: targetRotation,
      offset: targetOffset,
    );
  }
}
