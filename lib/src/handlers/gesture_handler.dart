import 'package:flutter/gestures.dart';
import 'package:flutter/physics.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/widgets.dart';
import 'package:custom_interactive_viewer/src/controller/interactive_controller.dart';
import 'package:custom_interactive_viewer/src/interaction/interaction_pipeline.dart';

/// A handler for gesture interactions with [CustomInteractiveViewer]
class GestureHandler {
  /// The controller that manages the view state
  final CustomInteractiveViewerController controller;

  /// Whether rotation is enabled
  final bool enableRotation;

  /// Whether fling behavior is enabled
  final bool enableFling;

  /// Whether zooming is enabled at all
  final bool enableZoom;

  /// Whether double-tap zoom is enabled
  final bool enableDoubleTapZoom;

  /// Factor by which to zoom on double-tap
  final double doubleTapZoomFactor;

  /// The reference to the viewport
  final GlobalKey viewportKey;

  /// Whether Ctrl+Scroll scaling is enabled
  final bool enableCtrlScrollToScale;

  /// Stores the last focal point during scale gesture
  Offset _lastFocalPoint = Offset.zero;

  /// Stores the last scale factor reported by the gesture
  double _lastScale = 1.0;

  /// Stores the last rotation reported by the gesture
  double _lastRotation = 0.0;

  /// Stores the last pointer count to detect changes mid-gesture
  int _lastPointerCount = 0;

  /// Tracks whether a scale or rotate gesture occurred during this interaction
  bool _hadScaleOrRotate = false;

  /// Tracks whether scaling is currently active for this gesture
  bool _isScalingGesture = false;

  /// Tracks position of double tap for zoom
  Offset? _doubleTapPosition;

  /// Tracks whether Ctrl key is currently pressed
  bool isCtrlPressed = false;

  /// Tracks active pointers to avoid phantom pointer counts.
  final Set<int> _activePointers = <int>{};

  /// Ignore gesture updates until all pointers are released.
  bool _ignoreGesture = false;

  /// Simulation for the fling animation
  Simulation? _flingSimulation;

  /// Frame callback id for the fling animation
  int? _flingFrameCallbackId;

  /// Timestamp for the start of the current fling
  Duration? _flingStartTime;

  /// Last elapsed time used by the fling simulation
  double _lastFlingElapsedSeconds = 0.0;

  /// Direction for the current fling
  Offset _flingDirection = Offset.zero;

  /// Creates a gesture handler
  GestureHandler({
    required this.controller,
    required this.enableRotation,
    required this.enableDoubleTapZoom,
    required this.doubleTapZoomFactor,
    required this.viewportKey,
    required this.enableCtrlScrollToScale,
    this.enableFling = true,
    required this.enableZoom,
  });

  /// Handles the start of a scale gesture
  void handleScaleStart(ScaleStartDetails details) {
    _stopFling();
    _hadScaleOrRotate = false;
    _isScalingGesture = false;
    _lastFocalPoint = details.localFocalPoint;
    _lastScale = 1.0;
    _lastRotation = 0.0;
    _lastPointerCount = _effectivePointerCount(details.pointerCount);
    if (_ignoreGesture) {
      return;
    }
    controller.setScaling(false);
    controller.setPanning(true);
  }

  /// Handles updates to a scale gesture
  void handleScaleUpdate(ScaleUpdateDetails details) {
    if (_ignoreGesture) {
      return;
    }
    final Offset localFocalPoint = details.localFocalPoint;
    final int pointerCount = _effectivePointerCount(details.pointerCount);
    final bool isMultiTouch = pointerCount > 1;

    if (pointerCount != _lastPointerCount) {
      _lastPointerCount = pointerCount;
      _lastScale = details.scale;
      _lastRotation = details.rotation;
      _lastFocalPoint = localFocalPoint;
      if (pointerCount <= 1 && _isScalingGesture) {
        _isScalingGesture = false;
        controller.setScaling(false);
        controller.setPanning(true);
      }
    }

    double? newScale;
    if (enableZoom && isMultiTouch) {
      final double scaleFactor =
          _lastScale == 0.0 ? 1.0 : details.scale / _lastScale;
      if (scaleFactor != 1.0) {
        newScale = controller.scale * scaleFactor;
      }
    }

    double? newRotation;
    if (enableRotation && isMultiTouch) {
      final double rotationDelta = details.rotation - _lastRotation;
      if (rotationDelta != 0.0) {
        newRotation = controller.rotation + rotationDelta;
      }
    }

    final bool scaleChanged = newScale != null && newScale != controller.scale;
    final bool rotationChanged =
        newRotation != null && newRotation != controller.rotation;
    final bool hasScaleOrRotate = scaleChanged || rotationChanged;

    if (hasScaleOrRotate && !_isScalingGesture) {
      _isScalingGesture = true;
      controller.setScaling(true);
      controller.setPanning(false);
    } else if (!hasScaleOrRotate && _isScalingGesture) {
      _isScalingGesture = false;
      controller.setScaling(false);
      controller.setPanning(true);
    }

    if (hasScaleOrRotate) {
      _hadScaleOrRotate = true;
    }

    // For scale or rotation changes, we need to preserve the focal point position
    if (scaleChanged || rotationChanged) {
      controller.applyInteraction(
        InteractionRequest(
          panDelta: localFocalPoint - _lastFocalPoint,
          scale: newScale,
          rotation: newRotation,
          focalPoint: localFocalPoint,
          includePanDeltaWhenScaling: true,
        ),
      );
    } else {
      // For simple panning without scale/rotation changes
      final Offset focalDiff = localFocalPoint - _lastFocalPoint;
      controller.applyInteraction(InteractionRequest(panDelta: focalDiff));
    }

    _lastScale = details.scale;
    _lastRotation = details.rotation;
    _lastFocalPoint = localFocalPoint;
  }

  /// Handles the end of a scale gesture
  void handleScaleEnd(ScaleEndDetails details) {
    if (_ignoreGesture) {
      _resetGestureTracking(clearPointers: true);
      _ignoreGesture = false;
      return;
    }
    controller.setScaling(false);
    controller.setPanning(false);

    // Only process fling for single pointer panning (not for pinch/zoom)
    if (!enableFling || _hadScaleOrRotate) {
      _resetGestureTracking(clearPointers: true);
      return;
    }

    // Start a fling animation if the velocity is significant
    final double velocityMagnitude = details.velocity.pixelsPerSecond.distance;
    if (velocityMagnitude >= 200.0) {
      _startFling(details.velocity);
    }

    _resetGestureTracking(clearPointers: true);
  }

  void handlePointerDown(PointerDownEvent event) {
    _activePointers.add(event.pointer);
    if (_activePointers.length > 2) {
      forceCancelGesture();
    }
  }

  void handlePointerUp(PointerUpEvent event) {
    _activePointers.remove(event.pointer);
    _handlePointerRelease();
  }

  void handlePointerCancel(PointerCancelEvent event) {
    _activePointers.remove(event.pointer);
    _handlePointerRelease();
  }

  int _effectivePointerCount(int reportedCount) {
    if (_activePointers.isEmpty) {
      return reportedCount;
    }
    if (reportedCount < _activePointers.length) {
      _activePointers.clear();
      return reportedCount;
    }
    return _activePointers.length;
  }

  void _handlePointerRelease() {
    if (_activePointers.isEmpty) {
      controller.setScaling(false);
      controller.setPanning(false);
      _resetGestureTracking();
      _ignoreGesture = false;
    }
  }

  void _cancelActivePointers() {
    for (final int pointer in _activePointers) {
      GestureBinding.instance.cancelPointer(pointer);
    }
  }

  void forceCancelGesture() {
    _ignoreGesture = true;
    _cancelActivePointers();
    _resetGestureTracking(clearPointers: false);
    controller.setScaling(false);
    controller.setPanning(false);
  }

  void _resetGestureTracking({bool clearPointers = false}) {
    _hadScaleOrRotate = false;
    _isScalingGesture = false;
    _lastPointerCount = 0;
    _lastScale = 1.0;
    _lastRotation = 0.0;
    _lastFocalPoint = Offset.zero;
    if (clearPointers) {
      _activePointers.clear();
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
    _flingDirection =
        velocity.pixelsPerSecond.distance > 0
            ? velocity.pixelsPerSecond / velocity.pixelsPerSecond.distance
            : Offset.zero;

    _flingStartTime = null;
    _lastFlingElapsedSeconds = 0.0;
    _scheduleFlingFrame();
    controller.setPanning(true);
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
    if (_flingFrameCallbackId != null) {
      SchedulerBinding.instance.cancelFrameCallbackWithId(
        _flingFrameCallbackId!,
      );
      _flingFrameCallbackId = null;
    }
    _flingStartTime = null;
    _lastFlingElapsedSeconds = 0.0;
    _flingSimulation = null;
    controller.setPanning(false);
  }

  void _scheduleFlingFrame() {
    _flingFrameCallbackId = SchedulerBinding.instance.scheduleFrameCallback(
      _handleFlingFrame,
    );
  }

  void _handleFlingFrame(Duration timeStamp) {
    if (_flingSimulation == null) return;

    _flingStartTime ??= timeStamp;
    final double elapsedSeconds =
        (timeStamp - _flingStartTime!).inMicroseconds / 1e6;

    // Calculate the new position using the physics simulation
    final double distance = _flingSimulation!.x(elapsedSeconds);
    final double prevDistance = _flingSimulation!.x(_lastFlingElapsedSeconds);
    final double delta = distance - prevDistance;
    _lastFlingElapsedSeconds = elapsedSeconds;

    // Skip tiny movements at the end of the animation
    if (delta.abs() < 0.1 && _flingSimulation!.isDone(elapsedSeconds)) {
      _stopFling();
      return;
    }

    // Apply the movement in the direction of the fling
    final Offset movement = _flingDirection * delta;
    // Update the controller position
    controller.applyInteraction(InteractionRequest(panDelta: movement));

    // Stop the fling when the animation is done
    if (_flingSimulation!.isDone(elapsedSeconds)) {
      _stopFling();
    } else {
      _scheduleFlingFrame();
    }
  }

  /// Stores double tap position for zoom
  void handleDoubleTapDown(TapDownDetails details) {
    if (!enableDoubleTapZoom) return;
    _doubleTapPosition = details.globalPosition;
  }

  /// Handles double tap for zoom
  void handleDoubleTap() async {
    if (!enableDoubleTapZoom || _doubleTapPosition == null) return;

    // Use viewportKey to get the RenderBox instead of Overlay
    final RenderBox? box =
        viewportKey.currentContext?.findRenderObject() as RenderBox?;
    if (box == null) return;

    // Always use the local position where the user pressed as the zoom center
    final Offset localFocal = box.globalToLocal(_doubleTapPosition!);

    final double currentScale = controller.state.scale;
    final double targetScale =
        (currentScale < doubleTapZoomFactor) ? doubleTapZoomFactor : 1.0;
    final targetState = controller.resolveInteraction(
      InteractionRequest(scale: targetScale, focalPoint: localFocal),
    );

    if (targetState == controller.state) {
      _doubleTapPosition = null;
      return;
    }

    controller.setScaling(true);
    await controller.animateTo(
      targetState: targetState,
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeInOut,
      animate: true,
    );
    controller.setScaling(false);

    _doubleTapPosition = null; // Reset after handling
    // Constraints and behaviors are applied via the controller pipeline.
  }

  /// Handles pointer scroll events
  void handlePointerScroll(PointerScrollEvent event) {
    // Determine if scaling should occur based on ctrl key
    if (enableCtrlScrollToScale && isCtrlPressed) {
      controller.setScaling(true);
      _handleCtrlScroll(event);
      controller.setScaling(false);
    } else {
      controller.setPanning(true);
      _handleNormalScroll(event);
      controller.setPanning(false);
    }
  }

  /// Handle Ctrl+Scroll for zooming
  void _handleCtrlScroll(PointerScrollEvent event) {
    final RenderBox? box =
        viewportKey.currentContext?.findRenderObject() as RenderBox?;
    if (box == null) return;

    final Offset localPosition = box.globalToLocal(event.position);

    // Calculate zoom factor - negative scrollDelta.dy means scroll up (zoom in)
    // This matches browser behavior: scroll up = zoom in, scroll down = zoom out
    final double zoomFactor = event.scrollDelta.dy > 0 ? -0.1 : 0.1;

    final double currentScale = controller.scale;
    final double targetScale = currentScale * (1 + zoomFactor);
    controller.applyInteraction(
      InteractionRequest(scale: targetScale, focalPoint: localPosition),
    );
  }

  /// Handle normal scroll for panning
  void _handleNormalScroll(PointerScrollEvent event) {
    // Pan using scroll delta
    controller.pan(-event.scrollDelta, animate: false);
  }

  /// Disposes the gesture handler and cleans up resources
  void dispose() {
    _stopFling();
  }
}
