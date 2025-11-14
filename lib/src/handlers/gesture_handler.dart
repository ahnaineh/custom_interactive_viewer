import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/physics.dart';
import 'package:flutter/widgets.dart';
import 'package:custom_interactive_viewer/src/controller/interactive_controller.dart';
import 'package:custom_interactive_viewer/src/enums/scroll_mode.dart';

/// A handler for gesture interactions with [CustomInteractiveViewer]
class GestureHandler {
  /// The controller that manages the view state
  final CustomInteractiveViewerController controller;

  /// Whether rotation is enabled
  final bool enableRotation;

  /// Whether to constrain content to bounds
  final bool constrainBounds;

  /// Whether fling behavior is enabled
  final bool enableFling;

  /// Whether zooming is enabled at all
  final bool enableZoom;

  /// Whether double-tap zoom is enabled
  final bool enableDoubleTapZoom;

  /// Factor by which to zoom on double-tap
  final double doubleTapZoomFactor;

  /// Size of the content being viewed
  final Size? contentSize;

  /// The reference to the viewport
  final GlobalKey viewportKey;

  /// Whether Ctrl+Scroll scaling is enabled
  final bool enableCtrlScrollToScale;

  /// Minimum allowed scale
  final double minScale;

  /// Maximum allowed scale
  final double maxScale;

  /// The scroll mode that determines allowed scroll directions
  final ScrollMode scrollMode;

  /// Stores the last focal point during scale gesture
  Offset _lastFocalPoint = Offset.zero;

  /// Stores the last scale during scale gesture
  double _lastScale = 1.0;

  /// Stores the last rotation during scale gesture
  double _lastRotation = 0.0;

  /// Tracks position of double tap for zoom
  Offset? _doubleTapPosition;

  /// Tracks whether Ctrl key is currently pressed
  bool isCtrlPressed = false;

  /// Simulation for the fling animation
  Simulation? _flingSimulation;

  /// Timer for the fling animation
  Timer? _flingTimer;

  /// Creates a gesture handler
  GestureHandler({
    required this.controller,
    required this.enableRotation,
    required this.constrainBounds,
    required this.enableDoubleTapZoom,
    required this.doubleTapZoomFactor,
    required this.contentSize,
    required this.viewportKey,
    required this.enableCtrlScrollToScale,
    required this.minScale,
    required this.maxScale,
    this.enableFling = true,
    required this.enableZoom,
    this.scrollMode = ScrollMode.both,
  });

  /// Handles the start of a scale gesture
  void handleScaleStart(ScaleStartDetails details) {
    _lastFocalPoint = details.focalPoint;
    _lastScale = controller.scale;
    _lastRotation = controller.rotation;
  }

  /// Handles updates to a scale gesture
  void handleScaleUpdate(ScaleUpdateDetails details) {
    // Get the render box to convert global position to local
    final RenderBox? box =
        viewportKey.currentContext?.findRenderObject() as RenderBox?;
    if (box == null) return;

    // Convert focal point from global to local coordinates
    final Offset localFocalPoint = box.globalToLocal(details.focalPoint);

    // Handle scale updates
    double? newScale;
    if (enableZoom && details.scale != 1.0) {
      newScale = _lastScale * details.scale;
      newScale = newScale.clamp(minScale, maxScale);
    }

    // Handle rotation updates
    double? newRotation;
    if (enableRotation && details.pointerCount >= 2) {
      newRotation = _lastRotation + details.rotation;
    }

    // For scale or rotation changes, we need to preserve the focal point position
    if ((newScale != null && newScale != controller.scale) ||
        (newRotation != null && newRotation != controller.rotation)) {
      // First get the position of the focal point RELATIVE TO THE CONTENT ORIGIN
      // before any transformations
      final Offset focalPointBeforeTransform =
          (localFocalPoint - controller.offset) / controller.scale;

      // Calculate the new offset needed to keep the focal point visually fixed
      Offset newOffset = controller.offset;

      if (newScale != null && newScale != controller.scale) {
        // The focal point should stay at the same visual location
        // To achieve this, we need to adjust the offset based on the scale change
        newOffset = localFocalPoint - (focalPointBeforeTransform * newScale);
      }

      if (newRotation != null &&
          newRotation != controller.rotation &&
          enableRotation) {
        // For rotation, we need more complex calculations to keep the focal point fixed
        final double rotationDelta = newRotation - controller.rotation;

        // Get the vector from content origin to focal point (in content coordinates)
        final Offset contentVector = focalPointBeforeTransform;

        // Calculate where this point would be after rotation (still in content coordinates)
        final double cosTheta = math.cos(rotationDelta);
        final double sinTheta = math.sin(rotationDelta);
        final Offset rotatedContentVector = Offset(
          contentVector.dx * cosTheta - contentVector.dy * sinTheta,
          contentVector.dx * sinTheta + contentVector.dy * cosTheta,
        );

        // Scale the rotated vector
        final Offset scaledRotatedVector =
            rotatedContentVector * (newScale ?? controller.scale);

        // Calculate the new offset that keeps the focal point visually fixed
        newOffset = localFocalPoint - scaledRotatedVector;
      }

      // Update the controller with all new values
      controller.update(
        newScale: newScale,
        newRotation: newRotation,
        newOffset: newOffset,
      );
    } else {
      // For simple panning without scale/rotation changes
      final Offset focalDiff = details.focalPoint - _lastFocalPoint;
      final Offset constrainedDiff = _constrainPanByScrollMode(focalDiff);
      controller.update(newOffset: controller.offset + constrainedDiff);
    }

    _applyConstraints();
    _lastFocalPoint = details.focalPoint;
  }

  /// Handles the end of a scale gesture
  void handleScaleEnd(ScaleEndDetails details) {
    // Only process fling for single pointer panning (not for pinch/zoom)
    if (!enableFling || details.pointerCount > 1) return;

    // Start a fling animation if the velocity is significant
    final double velocityMagnitude = details.velocity.pixelsPerSecond.distance;
    if (velocityMagnitude >= 200.0) {
      _startFling(details.velocity);
    }
  }

  /// Starts a fling animation with the given velocity
  void _startFling(Velocity velocity) {
    _stopFling(); // Stop any existing fling

    // Calculate appropriate friction based on velocity magnitude
    // Use higher friction for faster flicks to prevent excessive movement
    final double velocityMagnitude = velocity.pixelsPerSecond.distance;
    final double frictionCoefficient = _calculateDynamicFriction(
      velocityMagnitude,
    );

    // Create a friction simulation for the fling
    _flingSimulation = FrictionSimulation(
      frictionCoefficient, // dynamic friction coefficient
      0.0, // initial position (we'll use this for time, not position)
      velocityMagnitude, // velocity magnitude
    );

    // Get the fling direction as a normalized vector
    final Offset direction =
        velocity.pixelsPerSecond.distance > 0
            ? velocity.pixelsPerSecond / velocity.pixelsPerSecond.distance
            : Offset.zero;

    // Start time tracking
    final startTime = DateTime.now().millisecondsSinceEpoch;

    // Create a timer that updates the position 60 times per second
    _flingTimer = Timer.periodic(const Duration(milliseconds: 16), (timer) {
      final now = DateTime.now().millisecondsSinceEpoch;
      final elapsedSeconds = (now - startTime) / 1000.0;

      // Calculate the new position using the physics simulation
      final double distance = _flingSimulation!.x(elapsedSeconds);
      final double prevDistance = _flingSimulation!.x(elapsedSeconds - 0.016);
      final double delta = distance - prevDistance;

      // Skip tiny movements at the end of the animation
      if (delta.abs() < 0.1 && _flingSimulation!.isDone(elapsedSeconds)) {
        _stopFling();
        return;
      }

      // Apply the movement in the direction of the fling
      final Offset movement = direction * delta;
      final Offset constrainedMovement = _constrainPanByScrollMode(movement);

      // Update the controller position
      controller.update(newOffset: controller.offset + constrainedMovement);

      _applyConstraints();

      // Stop the fling when the animation is done
      if (_flingSimulation!.isDone(elapsedSeconds)) {
        _stopFling();
      }
    });
  }

  /// Calculate appropriate friction based on velocity magnitude
  double _calculateDynamicFriction(double velocityMagnitude) {
    // Use higher friction for faster flicks
    // These values can be tuned for the feel you want
    if (velocityMagnitude > 5000) {
      return 0.03; // Higher friction for very fast flicks
    } else if (velocityMagnitude > 3000) {
      return 0.02; // Medium friction for moderate flicks
    } else {
      return 0.01; // Lower friction for gentle movements
    }
  }

  /// Stops any active fling animation
  void _stopFling() {
    _flingTimer?.cancel();
    _flingTimer = null;
    _flingSimulation = null;
  }

  /// Stores double tap position for zoom
  void handleDoubleTapDown(TapDownDetails details) {
    if (!enableDoubleTapZoom) return;
    _doubleTapPosition = details.globalPosition;
  }

  /// Handles double tap for zoom
  void handleDoubleTap(BuildContext context) async {
    if (!enableDoubleTapZoom || _doubleTapPosition == null) return;

    // Use viewportKey to get the RenderBox instead of Overlay
    final RenderBox? box = context.findRenderObject() as RenderBox?;
    if (box == null) return;

    // Always use the local position where the user pressed as the zoom center
    final Offset localFocal = box.globalToLocal(_doubleTapPosition!);

    final double currentScale = controller.state.scale;
    final double targetScale =
        (currentScale < doubleTapZoomFactor) ? doubleTapZoomFactor : 1.0;

    // Calculate the zoom factor for the new zoom method
    final double factor;
    if (targetScale > currentScale) {
      // Zoom in: calculate positive factor
      factor = (targetScale / currentScale) - 1.0;
    } else {
      // Zoom out: calculate negative factor
      factor = -((currentScale / targetScale) - 1.0);
    }

    await controller.zoom(
      factor: factor,
      focalPoint: localFocal,
      animate: true,
    );

    _doubleTapPosition = null; // Reset after handling
    _applyConstraints();
  }

  /// Handles pointer scroll events
  void handlePointerScroll(PointerScrollEvent event, BuildContext context) {
    // Determine if scaling should occur based on ctrl key
    if (enableCtrlScrollToScale && isCtrlPressed) {
      _handleCtrlScroll(event, context);
    } else {
      _handleNormalScroll(event);
    }
  }

  /// Handle Ctrl+Scroll for zooming
  void _handleCtrlScroll(PointerScrollEvent event, BuildContext context) {
    final RenderBox? box = context.findRenderObject() as RenderBox?;
    if (box == null) return;

    final Offset localPosition = box.globalToLocal(event.position);

    // Calculate zoom factor - negative scrollDelta.dy means scroll up (zoom in)
    // This matches browser behavior: scroll up = zoom in, scroll down = zoom out
    final double zoomFactor = event.scrollDelta.dy > 0 ? -0.1 : 0.1;

    controller.zoom(
      factor: zoomFactor,
      focalPoint: localPosition,
      animate: false,
    );

    _applyConstraints();
  }

  /// Handle normal scroll for panning
  void _handleNormalScroll(PointerScrollEvent event) {
    // Pan using scroll delta, constrained by scroll mode
    final Offset constrainedDelta = _constrainPanByScrollMode(
      -event.scrollDelta,
    );
    controller.pan(constrainedDelta, animate: false);

    _applyConstraints();
  }

  /// Apply constraints if needed
  void _applyConstraints() {
    if (constrainBounds && contentSize != null) {
      final RenderBox? box =
          viewportKey.currentContext?.findRenderObject() as RenderBox?;
      if (box != null) {
        controller.constrainToBounds(contentSize!, box.size);
      }
    }
  }

  /// Constrains pan movement based on the scroll mode
  Offset _constrainPanByScrollMode(Offset delta) {
    switch (scrollMode) {
      case ScrollMode.horizontal:
        return Offset(delta.dx, 0);
      case ScrollMode.vertical:
        return Offset(0, delta.dy);
      case ScrollMode.none:
        return Offset.zero;
      case ScrollMode.both:
        return delta;
    }
  }

  /// Disposes the gesture handler and cleans up resources
  void dispose() {
    _stopFling();
  }
}
