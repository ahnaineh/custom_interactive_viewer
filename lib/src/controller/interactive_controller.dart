import 'package:flutter/material.dart';
import 'package:custom_interactive_viewer/src/models/transformation_state.dart';

/// Events that can be fired by the [CustomInteractiveViewerController]
enum ViewerEvent {
  /// Fired when transformation begins (e.g., user starts panning or scaling)
  transformationStart,

  /// Fired when transformation changes
  transformationUpdate,

  /// Fired when transformation ends
  transformationEnd,

  /// Fired when animation begins
  animationStart,

  /// Fired when animation ends
  animationEnd,
}

/// A controller for [CustomInteractiveViewer] that manages transformation state
/// and provides methods for programmatically manipulating the view.
class CustomInteractiveViewerController extends ChangeNotifier {
  /// Current transformation state
  TransformationState _state;

  /// State flags
  bool _isPanning = false;
  bool _isScaling = false;
  bool _isAnimating = false;

  /// Animation controllers and animations
  AnimationController? _animationController;
  Animation<TransformationState>? _transformationAnimation;

  /// Ticker provider for animations
  TickerProvider? _vsync;

  /// Callback for transformation events
  final void Function(ViewerEvent event)? onEvent;

  /// Creates a controller with initial transformation state.
  CustomInteractiveViewerController({
    TickerProvider? vsync,
    double initialScale = 1.0,
    Offset initialOffset = Offset.zero,
    double initialRotation = 0.0,
    this.onEvent,
  }) : _vsync = vsync,
       _state = TransformationState(
         scale: initialScale,
         offset: initialOffset,
         rotation: initialRotation,
       );

  /// Sets or updates the ticker provider
  set vsync(TickerProvider? value) {
    _vsync = value;
  }

  /// Current scale factor
  double get scale => _state.scale;

  /// Current offset
  Offset get offset => _state.offset;

  /// Current rotation
  double get rotation => _state.rotation;

  /// Whether the view is currently being panned
  bool get isPanning => _isPanning;

  /// Whether the view is currently being scaled
  bool get isScaling => _isScaling;

  /// Whether the view is currently animating
  bool get isAnimating => _isAnimating;

  /// Current transformation state
  TransformationState get state => _state;

  /// Updates the transformation state
  void update({double? newScale, Offset? newOffset, double? newRotation}) {
    if (newScale == _state.scale &&
        newOffset == _state.offset &&
        newRotation == _state.rotation) {
      return;
    }

    _state = _state.copyWith(
      scale: newScale,
      offset: newOffset,
      rotation: newRotation,
    );

    notifyListeners();
  }

  /// Updates the complete transformation state at once
  void updateState(TransformationState newState) {
    if (newState == _state) return;

    _state = newState;
    notifyListeners();
  }

  /// Gets the current transformation matrix
  Matrix4 get transformationMatrix => _state.toMatrix4();

  /// Zoom in by the given factor
  Future<void> zoomIn({
    double factor = 1.2,
    Offset? focalPoint,
    bool animate = true,
    Duration duration = const Duration(milliseconds: 300),
    Curve curve = Curves.easeInOut,
  }) async {
    final targetScale = _state.scale * factor;
    TransformationState targetState;

    if (focalPoint != null) {
      // Keep the focal point in the same position on screen during zoom
      final Offset beforeScaleOffset = (_state.screenToContentPoint(
        focalPoint,
      ));

      targetState = _state.copyWith(scale: targetScale);

      final Offset afterScaleOffset = (targetState.screenToContentPoint(
        focalPoint,
      ));
      final Offset offsetAdjustment =
          (afterScaleOffset - beforeScaleOffset) * targetScale;

      targetState = targetState.copyWith(
        offset: _state.offset - offsetAdjustment,
      );
    } else {
      targetState = _state.copyWith(scale: targetScale);
    }

    await animateTo(
      targetState: targetState,
      duration: duration,
      curve: curve,
      animate: animate,
    );
  }

  /// Zoom out by the given factor
  Future<void> zoomOut({
    double factor = 1.2,
    Offset? focalPoint,
    bool animate = true,
    Duration duration = const Duration(milliseconds: 300),
    Curve curve = Curves.easeInOut,
  }) async {
    final targetScale = _state.scale / factor;
    TransformationState targetState;

    if (focalPoint != null) {
      // Keep the focal point in the same position on screen during zoom
      final Offset beforeScaleOffset = (_state.screenToContentPoint(
        focalPoint,
      ));

      targetState = _state.copyWith(scale: targetScale);

      final Offset afterScaleOffset = (targetState.screenToContentPoint(
        focalPoint,
      ));
      final Offset offsetAdjustment =
          (afterScaleOffset - beforeScaleOffset) * targetScale;

      targetState = targetState.copyWith(
        offset: _state.offset - offsetAdjustment,
      );
    } else {
      targetState = _state.copyWith(scale: targetScale);
    }

    await animateTo(
      targetState: targetState,
      duration: duration,
      curve: curve,
      animate: animate,
    );
  }

  /// Pans the view by the given delta
  Future<void> panBy(
    Offset delta, {
    bool animate = true,
    Duration duration = const Duration(milliseconds: 300),
    Curve curve = Curves.easeInOut,
  }) async {
    final targetState = _state.copyWith(offset: _state.offset + delta);

    if (animate) {
      await animateTo(
        targetState: targetState,
        duration: duration,
        curve: curve,
      );
    } else {
      updateState(targetState);
    }
  }

  /// Rotates the view by the given angle in radians
  Future<void> rotate(
    double angleRadians, {
    Offset? focalPoint,
    bool animate = true,
    Duration duration = const Duration(milliseconds: 300),
    Curve curve = Curves.easeInOut,
  }) async {
    final targetRotation = _state.rotation + angleRadians;
    TransformationState targetState;

    if (focalPoint != null) {
      // Keep the focal point in the same position on screen during rotation
      final Offset beforeRotationOffset = _state.screenToContentPoint(
        focalPoint,
      );

      targetState = _state.copyWith(rotation: targetRotation);

      final Offset afterRotationOffset = targetState.screenToContentPoint(
        focalPoint,
      );
      final Offset offsetAdjustment =
          afterRotationOffset - beforeRotationOffset;

      targetState = targetState.copyWith(
        offset: _state.offset - offsetAdjustment * targetState.scale,
      );
    } else {
      targetState = _state.copyWith(rotation: targetRotation);
    }

    if (animate) {
      await animateTo(
        targetState: targetState,
        duration: duration,
        curve: curve,
      );
    } else {
      updateState(targetState);
    }
  }

  /// Rotates the view to the given absolute angle in radians
  Future<void> rotateTo(
    double angleRadians, {
    Offset? focalPoint,
    bool animate = true,
    Duration duration = const Duration(milliseconds: 300),
    Curve curve = Curves.easeInOut,
  }) async {
    // Calculate how much we need to rotate from current rotation
    final rotationDelta = angleRadians - _state.rotation;
    await rotate(
      rotationDelta,
      focalPoint: focalPoint,
      animate: animate,
      duration: duration,
      curve: curve,
    );
  }

  /// Convert a point from screen coordinates to content coordinates
  Offset screenToContentPoint(Offset screenPoint) =>
      _state.screenToContentPoint(screenPoint);

  /// Convert a point from content coordinates to screen coordinates
  Offset contentToScreenPoint(Offset contentPoint) =>
      _state.contentToScreenPoint(contentPoint);

  /// Fit the content to the screen size
  Future<void> fitToScreen(
    Size contentSize,
    Size viewportSize, {
    double padding = 20.0,
    bool animate = true,
    Duration duration = const Duration(milliseconds: 300),
    Curve curve = Curves.easeInOut,
  }) async {
    final targetState = TransformationState.fitContent(
      contentSize,
      viewportSize,
      padding: padding,
    );

    if (animate) {
      await animateTo(
        targetState: targetState,
        duration: duration,
        curve: curve,
      );
    } else {
      updateState(targetState);
    }
  }

  /// Resets the view to initial values
  Future<void> reset({
    bool animate = true,
    Duration duration = const Duration(milliseconds: 300),
    Curve curve = Curves.easeInOut,
  }) async {
    final targetState = TransformationState();

    if (animate) {
      await animateTo(
        targetState: targetState,
        duration: duration,
        curve: curve,
      );
    } else {
      updateState(targetState);
    }
  }

  /// Animates from the current state to the provided target state.
  Future<void> animateTo({
    required TransformationState targetState,
    Duration duration = const Duration(milliseconds: 300),
    Curve curve = Curves.easeInOut,
    bool animate = true,
  }) async {
    if (!animate) {
      updateState(targetState);
      return;
    }

    if (_vsync == null) {
      throw StateError(
        'Setting vsync is required to be able to perform animations',
      );
    }

    _isAnimating = true;
    onEvent?.call(ViewerEvent.animationStart);
    notifyListeners();

    // Dispose any previous animation controller
    _animationController?.dispose();
    _animationController = AnimationController(
      vsync: _vsync!,
      duration: duration,
    );

    // Create a tween for the entire transformation state
    _transformationAnimation = TransformationStateTween(
      begin: _state,
      end: targetState,
    ).animate(CurvedAnimation(parent: _animationController!, curve: curve));

    _animationController!.addListener(() {
      updateState(_transformationAnimation!.value);
    });

    try {
      await _animationController!.forward();
    } finally {
      _animationController!.dispose();
      _animationController = null;
      _transformationAnimation = null;

      _isAnimating = false;
      onEvent?.call(ViewerEvent.animationEnd);
      notifyListeners();
    }
  }

  /// Zooms to a specific region of the content
  Future<void> zoomToRegion(
    Rect region,
    Size viewportSize, {
    bool animate = true,
    Duration duration = const Duration(milliseconds: 300),
    Curve curve = Curves.easeInOut,
    double padding = 20.0,
  }) async {
    final targetState = TransformationState.zoomToRegion(
      region,
      viewportSize,
      padding: padding,
    );

    if (animate) {
      await animateTo(
        targetState: targetState,
        duration: duration,
        curve: curve,
      );
    } else {
      updateState(targetState);
    }
  }

  /// Ensures content stays within bounds
  void constrainToBounds(Size contentSize, Size viewportSize) {
    final constrainedState = _state.constrainToViewport(
      contentSize,
      viewportSize,
    );
    if (constrainedState != _state) {
      updateState(constrainedState);
    }
  }

  /// Centers the content within the viewport.
  ///
  /// This method can automatically determine viewport and content sizes if they're
  /// not explicitly provided, using the size getters registered with the controller.
  ///
  /// If not providing explicit sizes, make sure the controller has been properly
  /// initialized with viewportSizeGetter and contentSizeGetter.
  Future<void> center({
    Size? contentSize,
    Size? viewportSize,
    bool animate = true,
    Duration duration = const Duration(milliseconds: 300),
    Curve curve = Curves.easeInOut,
  }) async {
    // Get viewport size from parameter or registered getter
    final Size? finalViewportSize = viewportSize ?? _getViewportSize?.call();
    if (finalViewportSize == null) {
      assert(
        false,
        'Cannot center content because viewport size is unknown. '
        'Provide a viewportSize parameter or set the viewportSizeGetter.',
      );
      return;
    }

    // Get content size from parameter or registered getter
    final Size? finalContentSize = contentSize ?? _getContentSize?.call();
    if (finalContentSize == null) {
      assert(
        false,
        'Cannot center content because content size is unknown. '
        'Provide a contentSize parameter or set the contentSizeGetter.',
      );
      return;
    }

    final targetState = TransformationState.centerContent(
      finalContentSize,
      finalViewportSize,
      _state.scale,
    );

    if (animate) {
      await animateTo(
        targetState: targetState,
        duration: duration,
        curve: curve,
      );
    } else {
      updateState(targetState);
    }
  }

  /// Centers the view on a specific rectangle within the content.
  ///
  /// This method will position the view so that the provided rectangle is centered,
  /// and optionally apply a specific scale factor.
  ///
  /// If [viewportSize] is not provided, it will try to use the registered viewport size getter.
  /// If [scale] is not provided, the current scale will be maintained.
  Future<void> centerOnRect(
    Rect rect, {
    Size? viewportSize,
    double? scale,
    bool animate = true,
    Duration duration = const Duration(milliseconds: 300),
    Curve curve = Curves.easeInOut,
  }) async {
    // Get viewport size from parameter or registered getter
    final Size? finalViewportSize = viewportSize ?? _getViewportSize?.call();
    if (finalViewportSize == null) {
      assert(
        false,
        'Cannot center on rect because viewport size is unknown. '
        'Provide a viewportSize parameter or set the viewportSizeGetter.',
      );
      return;
    }

    // Calculate the center point of the rectangle in content coordinates
    final Offset rectCenter = rect.center;

    // Determine the target scale
    final double targetScale = scale ?? _state.scale;

    // Calculate the offset needed to center the rectangle
    // The offset is in the coordinate system of the content, before any transformations
    final Offset targetOffset = Offset(
      (finalViewportSize.width / 2) - (rectCenter.dx * targetScale),
      (finalViewportSize.height / 2) - (rectCenter.dy * targetScale),
    );

    final targetState = _state.copyWith(
      scale: targetScale,
      offset: targetOffset,
    );

    if (animate) {
      await animateTo(
        targetState: targetState,
        duration: duration,
        curve: curve,
      );
    } else {
      updateState(targetState);
    }
  }

  /// Sets panning state - for internal use
  void setPanning(bool value) {
    if (_isPanning == value) return;

    _isPanning = value;
    if (value) {
      onEvent?.call(ViewerEvent.transformationStart);
    } else {
      onEvent?.call(ViewerEvent.transformationEnd);
    }
    notifyListeners();
  }

  /// Sets scaling state - for internal use
  void setScaling(bool value) {
    if (_isScaling == value) return;

    _isScaling = value;
    if (value) {
      onEvent?.call(ViewerEvent.transformationStart);
    } else {
      onEvent?.call(ViewerEvent.transformationEnd);
    }
    notifyListeners();
  }

  /// Function type for getting the viewport size
  Size? Function()? _getViewportSize;

  /// Function type for getting the content size
  Size? Function()? _getContentSize;

  /// Sets the viewport size provider function
  set viewportSizeGetter(Size? Function()? getter) {
    _getViewportSize = getter;
  }

  /// Sets the content size provider function
  set contentSizeGetter(Size? Function()? getter) {
    _getContentSize = getter;
  }

  @override
  void dispose() {
    _animationController?.dispose();
    super.dispose();
  }
}

/// A [Tween] for animating between two [TransformationState]s
class TransformationStateTween extends Tween<TransformationState> {
  /// Creates a [TransformationState] tween
  TransformationStateTween({
    required TransformationState begin,
    required TransformationState end,
  }) : super(begin: begin, end: end);

  @override
  TransformationState lerp(double t) {
    return TransformationState(
      scale: lerpDouble(begin!.scale, end!.scale, t),
      offset: Offset.lerp(begin!.offset, end!.offset, t)!,
      rotation: lerpDouble(begin!.rotation, end!.rotation, t),
    );
  }

  /// Linearly interpolate between two doubles.
  double lerpDouble(double a, double b, double t) {
    return a + (b - a) * t;
  }
}
