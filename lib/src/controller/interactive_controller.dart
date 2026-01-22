import 'dart:math';
import 'package:custom_interactive_viewer/src/interaction/interaction_pipeline.dart';
import 'package:custom_interactive_viewer/src/widget.dart';
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
///
/// A controller should be attached to only one viewer at a time using [attach].
class CustomInteractiveViewerController extends ChangeNotifier {
  /// Current transformation state
  TransformationState _state;

  /// State flags
  bool _isPanning = false;
  bool _isScaling = false;
  bool _isAnimating = false;

  /// Optional scale limits to apply for programmatic zooming.
  double? _minScale;
  double? _maxScale;

  /// Animation controllers and animations
  AnimationController? _animationController;
  Animation<TransformationState>? _transformationAnimation;

  /// Ticker provider for animations
  TickerProvider? vsync;

  /// Callback for transformation events
  final void Function(ViewerEvent event)? onEvent;

  /// Tracks which widget owns this controller.
  Object? _attachmentOwner;

  /// Interaction behavior pipeline.
  InteractionBehavior interactionBehavior;

  /// Resolved alignment for interaction transforms.
  Alignment alignment;

  /// Creates a controller with initial transformation state.
  CustomInteractiveViewerController({
    this.vsync,
    double initialScale = 1.0,
    Offset initialOffset = Offset.zero,
    double initialRotation = 0.0,
    double? minScale,
    double? maxScale,
    this.onEvent,
  }) : assert(
         minScale == null || maxScale == null || minScale <= maxScale,
         'minScale must be <= maxScale',
       ),
       _minScale = minScale,
       _maxScale = maxScale,
       interactionBehavior = const InteractionBehavior.none(),
       alignment = Alignment.topLeft,
       _state = TransformationState(
         scale: _clampScaleWithLimits(initialScale, minScale, maxScale),
         offset: initialOffset,
         rotation: initialRotation,
       );

  /// Minimum allowed scale for programmatic zooming.
  double? get minScale => _minScale;

  /// Maximum allowed scale for programmatic zooming.
  double? get maxScale => _maxScale;

  /// Update scale limits used for programmatic zooming.
  void setScaleLimits({double? minScale, double? maxScale}) {
    _minScale = minScale;
    _maxScale = maxScale;
    assert(
      _minScale == null || _maxScale == null || _minScale! <= _maxScale!,
      'minScale must be <= maxScale',
    );
    final double clampedScale = _clampScale(_state.scale);
    if (clampedScale != _state.scale) {
      updateState(_state.copyWith(scale: clampedScale));
    }
  }

  /// Attach this controller to a widget owner.
  void attach(
    Object owner, {
    TickerProvider? vsync,
    double? minScale,
    double? maxScale,
    InteractionBehavior? behavior,
    Alignment? alignment,
  }) {
    assert(
      _attachmentOwner == null || _attachmentOwner == owner,
      'CustomInteractiveViewerController is already attached to another widget.',
    );
    if (_attachmentOwner != null && _attachmentOwner != owner) {
      throw StateError(
        'CustomInteractiveViewerController is already attached to another widget.',
      );
    }
    _attachmentOwner = owner;
    if (vsync != null) {
      this.vsync = vsync;
    }
    if (minScale != null || maxScale != null) {
      setScaleLimits(minScale: minScale, maxScale: maxScale);
    }
    if (behavior != null) {
      interactionBehavior = behavior;
    }
    if (alignment != null) {
      this.alignment = alignment;
    }
  }

  /// Detach this controller from the owning widget.
  void detach(Object owner) {
    if (_attachmentOwner == owner) {
      if (vsync == owner) {
        vsync = null;
      }
      _attachmentOwner = null;
    }
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

    onEvent?.call(ViewerEvent.transformationUpdate);
    notifyListeners();
  }

  /// Updates the complete transformation state at once
  void updateState(TransformationState newState) {
    if (newState == _state) return;

    _state = newState;
    onEvent?.call(ViewerEvent.transformationUpdate);
    notifyListeners();
  }

  /// Resolves a target state for the given interaction request.
  TransformationState resolveInteraction(
    InteractionRequest request, {
    TransformationState? baseState,
  }) {
    final TransformationState startingState = baseState ?? _state;
    final Size? contentSize = _getContentSize?.call();
    final Size? viewportSize = _getViewportSize?.call();
    final _AlignmentMetrics alignmentMetrics = _resolveAlignmentMetrics(
      contentSize: contentSize,
      viewportSize: viewportSize,
    );
    final InteractionContext context = InteractionContext(
      state: startingState,
      contentSize: contentSize,
      viewportSize: viewportSize,
      minScale: _minScale,
      maxScale: _maxScale,
      alignment: alignment,
      alignmentOrigin: alignmentMetrics.origin,
      alignmentOffset: alignmentMetrics.offset,
    );
    InteractionRequest adjustedRequest = interactionBehavior.onRequest(
      request,
      context,
    );

    if (adjustedRequest.scale != null) {
      final double clampedScale = _clampScale(adjustedRequest.scale!);
      if (clampedScale != adjustedRequest.scale) {
        adjustedRequest = adjustedRequest.copyWith(scale: clampedScale);
      }
    }

    final TransformationState nextState = InteractionTransformer.apply(
      state: startingState,
      request: adjustedRequest,
      alignmentOrigin: alignmentMetrics.origin,
      alignmentOffset: alignmentMetrics.offset,
    );

    final InteractionContext nextContext = context.copyWith(state: nextState);
    return interactionBehavior.onResult(nextState, nextContext);
  }

  /// Applies an interaction request immediately.
  void applyInteraction(InteractionRequest request) {
    updateState(resolveInteraction(request));
  }

  TransformationState _applyBehaviorToState(TransformationState state) {
    final Size? contentSize = _getContentSize?.call();
    final Size? viewportSize = _getViewportSize?.call();
    final _AlignmentMetrics alignmentMetrics = _resolveAlignmentMetrics(
      contentSize: contentSize,
      viewportSize: viewportSize,
    );
    final InteractionContext context = InteractionContext(
      state: state,
      contentSize: contentSize,
      viewportSize: viewportSize,
      minScale: _minScale,
      maxScale: _maxScale,
      alignment: alignment,
      alignmentOrigin: alignmentMetrics.origin,
      alignmentOffset: alignmentMetrics.offset,
    );
    return interactionBehavior.onResult(state, context);
  }

  _AlignmentMetrics _resolveAlignmentMetrics({
    required Size? contentSize,
    required Size? viewportSize,
  }) {
    if (contentSize == null || viewportSize == null) {
      return _AlignmentMetrics.zero;
    }
    final double originX = (contentSize.width * (alignment.x + 1)) / 2;
    final double originY = (contentSize.height * (alignment.y + 1)) / 2;
    final double offsetX =
        (viewportSize.width - contentSize.width) * (alignment.x + 1) / 2;
    final double offsetY =
        (viewportSize.height - contentSize.height) * (alignment.y + 1) / 2;
    return _AlignmentMetrics(
      origin: Offset(originX, originY),
      offset: Offset(offsetX, offsetY),
    );
  }

  TransformationState _applyAlignmentOffset(
    TransformationState state, {
    required Size? contentSize,
    required Size? viewportSize,
  }) {
    if (contentSize == null || viewportSize == null) {
      return state;
    }
    final _AlignmentMetrics alignmentMetrics = _resolveAlignmentMetrics(
      contentSize: contentSize,
      viewportSize: viewportSize,
    );
    final Offset correction =
        alignmentMetrics.offset + alignmentMetrics.origin * (1 - state.scale);
    if (correction == Offset.zero) {
      return state;
    }
    return state.copyWith(offset: state.offset - correction);
  }

  /// Gets the current transformation matrix
  Matrix4 get transformationMatrix => _state.toMatrix4();

  /// Zooms the view by the given factor, keeping the focal point visually fixed.
  ///
  /// Positive factor values zoom in, negative values zoom out.
  /// For example:
  /// - factor: 0.2 - zooms in by 20%
  /// - factor: -0.2 - zooms out by 20%
  /// - factor: 1.0 - doubles the current scale
  /// - factor: -0.5 - reduces the scale by half
  Future<void> zoom({
    required double factor,
    Offset? focalPoint,
    bool animate = true,
    Duration duration = const Duration(milliseconds: 300),
    Curve curve = Curves.easeInOut,
  }) async {
    final double absScaleFactor = 1.0 + factor.abs();
    double targetScale =
        factor >= 0
            ? _state.scale * absScaleFactor
            : _state.scale / absScaleFactor;
    final TransformationState targetState = resolveInteraction(
      InteractionRequest(scale: targetScale, focalPoint: focalPoint),
    );

    await animateTo(
      targetState: targetState,
      duration: duration,
      curve: curve,
      animate: animate,
    );
  }

  /// Pans the view by the given offset
  ///
  /// The offset specifies how much the view should move. Positive x values
  /// move the view to the right, negative to the left. Positive y values move
  /// the view down, negative up.
  Future<void> pan(
    Offset offset, {
    bool animate = true,
    Duration duration = const Duration(milliseconds: 300),
    Curve curve = Curves.easeInOut,
  }) async {
    final TransformationState targetState = resolveInteraction(
      InteractionRequest(panDelta: offset),
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

  /// Rotates the view by the given angle in radians
  Future<void> rotate(
    double angleRadians, {
    Offset? focalPoint,
    bool animate = true,
    Duration duration = const Duration(milliseconds: 300),
    Curve curve = Curves.easeInOut,
  }) async {
    final double targetRotation = _state.rotation + angleRadians;
    final TransformationState targetState = resolveInteraction(
      InteractionRequest(rotation: targetRotation, focalPoint: focalPoint),
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
  Offset screenToContentPoint(Offset screenPoint) {
    final _AlignmentMetrics alignmentMetrics = _resolveAlignmentMetrics(
      contentSize: _getContentSize?.call(),
      viewportSize: _getViewportSize?.call(),
    );
    return _state.screenToContentPoint(
      screenPoint,
      alignmentOrigin: alignmentMetrics.origin,
      alignmentOffset: alignmentMetrics.offset,
    );
  }

  /// Convert a point from content coordinates to screen coordinates
  Offset contentToScreenPoint(Offset contentPoint) {
    final _AlignmentMetrics alignmentMetrics = _resolveAlignmentMetrics(
      contentSize: _getContentSize?.call(),
      viewportSize: _getViewportSize?.call(),
    );
    return _state.contentToScreenPoint(
      contentPoint,
      alignmentOrigin: alignmentMetrics.origin,
      alignmentOffset: alignmentMetrics.offset,
    );
  }

  /// Fit the content to the screen size
  Future<void> fitToScreen(
    Size contentSize,
    Size viewportSize, {
    double padding = 20.0,
    bool animate = true,
    Duration duration = const Duration(milliseconds: 300),
    Curve curve = Curves.easeInOut,
  }) async {
    final baseState = TransformationState.fitContent(
      contentSize,
      viewportSize,
      padding: padding,
    );
    final double targetScale = _clampScale(baseState.scale);
    final TransformationState unclampedState =
        targetScale == baseState.scale
            ? baseState
            : TransformationState.centerContent(
              contentSize,
              viewportSize,
              targetScale,
            );
    final TransformationState alignedState = _applyAlignmentOffset(
      unclampedState,
      contentSize: contentSize,
      viewportSize: viewportSize,
    );
    final TransformationState targetState = _applyBehaviorToState(alignedState);

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
    final targetState = _applyBehaviorToState(const TransformationState());

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

    if (vsync == null) {
      throw StateError(
        'Setting vsync is required to be able to perform animations',
      );
    }

    _isAnimating = true;
    onEvent?.call(ViewerEvent.animationStart);
    notifyListeners();

    // Stop and dispose any previous animation controller
    _stopAnimation();
    _animationController = AnimationController(
      vsync: vsync!,
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
    final baseState = TransformationState.zoomToRegion(
      region,
      viewportSize,
      padding: padding,
    );
    final double targetScale = _clampScale(baseState.scale);
    final Offset regionCenter = region.center;
    final TransformationState unclampedState =
        targetScale == baseState.scale
            ? baseState
            : baseState.copyWith(
              scale: targetScale,
              offset: Offset(
                viewportSize.width / 2 - regionCenter.dx * targetScale,
                viewportSize.height / 2 - regionCenter.dy * targetScale,
              ),
            );
    final TransformationState alignedState = _applyAlignmentOffset(
      unclampedState,
      contentSize: _getContentSize?.call(),
      viewportSize: viewportSize,
    );
    final TransformationState targetState = _applyBehaviorToState(alignedState);

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
    final _AlignmentMetrics alignmentMetrics = _resolveAlignmentMetrics(
      contentSize: contentSize,
      viewportSize: viewportSize,
    );
    final constrainedState = _state.constrainToViewport(
      contentSize,
      viewportSize,
      alignmentOrigin: alignmentMetrics.origin,
      alignmentOffset: alignmentMetrics.offset,
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
    final TransformationState alignedState = _applyAlignmentOffset(
      targetState,
      contentSize: finalContentSize,
      viewportSize: finalViewportSize,
    );
    final TransformationState finalTargetState = _applyBehaviorToState(
      alignedState,
    );

    if (animate) {
      await animateTo(
        targetState: finalTargetState,
        duration: duration,
        curve: curve,
      );
    } else {
      updateState(finalTargetState);
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
    final double targetScale =
        scale == null ? _state.scale : _clampScale(scale);

    final _AlignmentMetrics alignmentMetrics = _resolveAlignmentMetrics(
      contentSize: _getContentSize?.call(),
      viewportSize: finalViewportSize,
    );
    final Offset rectDelta = rectCenter - alignmentMetrics.origin;
    final double cosRotation = cos(_state.rotation);
    final double sinRotation = sin(_state.rotation);
    final Offset rotated = Offset(
      rectDelta.dx * cosRotation - rectDelta.dy * sinRotation,
      rectDelta.dx * sinRotation + rectDelta.dy * cosRotation,
    );

    final Offset targetOffset = Offset(
      (finalViewportSize.width / 2) -
          alignmentMetrics.offset.dx -
          alignmentMetrics.origin.dx -
          (rotated.dx * targetScale),
      (finalViewportSize.height / 2) -
          alignmentMetrics.offset.dy -
          alignmentMetrics.origin.dy -
          (rotated.dy * targetScale),
    );

    final targetState = _applyBehaviorToState(
      _state.copyWith(scale: targetScale, offset: targetOffset),
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

    final bool wasTransforming = _isPanning || _isScaling;
    _isPanning = value;
    _notifyTransformingState(wasTransforming);
  }

  /// Sets scaling state - for internal use
  void setScaling(bool value) {
    if (_isScaling == value) return;

    final bool wasTransforming = _isPanning || _isScaling;
    _isScaling = value;
    _notifyTransformingState(wasTransforming);
  }

  double _clampScale(double scale) {
    final double? min = _minScale;
    final double? max = _maxScale;
    if (min == null && max == null) {
      return scale;
    }
    return scale.clamp(min ?? scale, max ?? scale);
  }

  static double _clampScaleWithLimits(
    double scale,
    double? minScale,
    double? maxScale,
  ) {
    if (minScale == null && maxScale == null) {
      return scale;
    }
    return scale.clamp(minScale ?? scale, maxScale ?? scale);
  }

  void _notifyTransformingState(bool wasTransforming) {
    final bool isTransforming = _isPanning || _isScaling;
    if (!wasTransforming && isTransforming) {
      onEvent?.call(ViewerEvent.transformationStart);
    } else if (wasTransforming && !isTransforming) {
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

  /// Stops any active animation without disposing the controller
  void _stopAnimation() {
    if (_animationController != null) {
      if (_animationController!.isAnimating) {
        _animationController!.stop();
      }
      _animationController!.dispose();
      _animationController = null;
      _transformationAnimation = null;
      _isAnimating = false;
    }
  }

  /// Stops any active animation. Can be called externally to cancel animations.
  void stopAnimation({bool shouldNotify = true}) {
    if (_isAnimating) {
      _stopAnimation();
      onEvent?.call(ViewerEvent.animationEnd);
      if (shouldNotify) {
        notifyListeners();
      }
    }
  }

  @override
  void dispose() {
    // Stop and dispose any active animations before disposing the controller
    _stopAnimation();
    super.dispose();
  }
}

class _AlignmentMetrics {
  final Offset origin;
  final Offset offset;

  const _AlignmentMetrics({required this.origin, required this.offset});

  static const _AlignmentMetrics zero = _AlignmentMetrics(
    origin: Offset.zero,
    offset: Offset.zero,
  );
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
