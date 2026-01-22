import 'package:custom_interactive_viewer/src/config/interaction_config.dart';
import 'package:custom_interactive_viewer/src/config/keyboard_config.dart';
import 'package:custom_interactive_viewer/src/config/zoom_config.dart';
import 'package:custom_interactive_viewer/src/controller/interactive_controller.dart';
import 'package:custom_interactive_viewer/src/handlers/gesture_handler.dart';
import 'package:custom_interactive_viewer/src/handlers/keyboard_handler.dart';
import 'package:custom_interactive_viewer/src/interaction/interaction_pipeline.dart';
import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/services.dart';

/// A customizable widget for viewing content with interactive transformations.
///
/// This widget allows for panning, zooming, and optionally rotating its child.
/// It provides greater control and customization than Flutter's built-in
/// [InteractiveViewer].
class CustomInteractiveViewer extends StatefulWidget {
  /// The child widget to display.
  final Widget child;

  /// The controller that manages the transformation state.
  ///
  /// A controller should be attached to only one [CustomInteractiveViewer] at a time.
  final CustomInteractiveViewerController? controller;

  /// The size of the content being displayed. Used for centering and constraints.
  ///
  /// If null and [contentSizeGetter] is null, the viewer infers the size from the
  /// child's render box. This works for most standard widgets.
  final Size? contentSize;

  /// A getter for the logical content size.
  ///
  /// Use this when the child's render size is not the true content bounds
  /// (e.g. virtualized lists, custom painting outside layout bounds, or
  /// content that is offstage while still logically present).
  /// If provided, this is treated as the source of truth.
  final Size? Function()? contentSizeGetter;

  /// Configuration for zoom-related behavior.
  final ZoomConfig zoomConfig;

  /// Configuration for gesture and interaction behavior.
  final InteractionConfig interactionConfig;

  /// Configuration for keyboard controls.
  final KeyboardConfig keyboardConfig;

  /// External focus node for keyboard input.
  /// If provided, this focus node will be used for keyboard events.
  /// If null, an internal focus node will be created.
  final FocusNode? focusNode;

  /// Creates a [CustomInteractiveViewer].
  ///
  /// The [child] parameter is required.
  const CustomInteractiveViewer({
    super.key,
    required this.child,
    this.controller,
    this.contentSize,
    this.contentSizeGetter,
    this.zoomConfig = const ZoomConfig(),
    this.interactionConfig = const InteractionConfig(),
    this.keyboardConfig = const KeyboardConfig(),
    this.focusNode,
  });

  @override
  CustomInteractiveViewerState createState() => CustomInteractiveViewerState();
}

/// The state for a [CustomInteractiveViewer].
class CustomInteractiveViewerState extends State<CustomInteractiveViewer>
    with TickerProviderStateMixin {
  late final CustomInteractiveViewerController controller =
      widget.controller ?? CustomInteractiveViewerController(vsync: this);

  /// The key for the viewport.
  final GlobalKey _viewportKey = GlobalKey();

  /// The key for measuring the content size when it is not provided explicitly.
  final GlobalKey _contentKey = GlobalKey();

  Size? _lastContentSize;
  Alignment _resolvedAlignment = Alignment.topLeft;

  /// Focus node for keyboard input.
  late FocusNode _focusNode;

  bool _ownsFocusNode = false;

  /// Handles gesture interactions.
  late GestureHandler _gestureHandler;

  /// Handles keyboard interactions.
  late KeyboardHandler _keyboardHandler;

  final Set<int> _activePointers = <int>{};
  bool _gesturesBlocked = false;

  @override
  void initState() {
    super.initState();
    _focusNode = widget.focusNode ?? FocusNode();
    _ownsFocusNode = widget.focusNode == null;
    controller.attach(
      this,
      vsync: this,
      minScale: widget.zoomConfig.minScale,
      maxScale: widget.zoomConfig.maxScale,
      behavior: _buildInteractionBehavior(),
    );
    controller.addListener(_onControllerUpdate);

    // Register size getters with the controller
    _registerControllerSizeGetters();

    _initializeHandlers();

    // Add listener for control key state
    HardwareKeyboard.instance.addHandler(_handleHardwareKeyChange);

    WidgetsBinding.instance.addPostFrameCallback((_) {
      _centerContentIfNeeded();
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _syncResolvedAlignment();
  }

  /// Register viewport and content size getters with the controller
  void _registerControllerSizeGetters() {
    // Register viewport size getter
    controller.viewportSizeGetter = () {
      final RenderBox? box =
          _viewportKey.currentContext?.findRenderObject() as RenderBox?;
      return box?.size;
    };

    // Always register a resolver so the controller can query size when needed.
    controller.contentSizeGetter = _resolveContentSize;
  }

  void _syncControllerScaleLimits() {
    controller.setScaleLimits(
      minScale: widget.zoomConfig.minScale,
      maxScale: widget.zoomConfig.maxScale,
    );
  }

  void _syncResolvedAlignment() {
    final Alignment resolved = AlignmentDirectional.topStart.resolve(
      Directionality.of(context),
    );
    if (_resolvedAlignment == resolved) {
      return;
    }
    _resolvedAlignment = resolved;
    controller.alignment = resolved;
    controller.applyInteraction(const InteractionRequest());
  }

  void _syncInteractionBehavior() {
    controller.interactionBehavior = _buildInteractionBehavior();
    controller.applyInteraction(const InteractionRequest());
  }

  InteractionBehavior _buildInteractionBehavior() {
    final List<InteractionBehavior> behaviors = <InteractionBehavior>[
      ScrollModeBehavior(widget.interactionConfig.scrollMode),
    ];

    if (widget.interactionConfig.behaviors.isNotEmpty) {
      behaviors.addAll(widget.interactionConfig.behaviors);
    }

    final BoundsBehavior? boundsBehavior =
        widget.interactionConfig.boundsBehavior;
    final bool hasBoundsBehavior = widget.interactionConfig.behaviors.any(
      (b) => b is BoundsBehavior,
    );
    if (!hasBoundsBehavior && boundsBehavior != null) {
      behaviors.add(boundsBehavior);
    } else if (!hasBoundsBehavior && widget.interactionConfig.constrainBounds) {
      behaviors.add(const ViewportBoundsBehavior());
    }

    return InteractionBehavior.combine(behaviors);
  }

  Size? _resolveContentSize() {
    if (widget.contentSizeGetter != null) {
      final Size? size = widget.contentSizeGetter!.call();
      if (size != null) {
        _lastContentSize = size;
      }
      return size;
    }

    if (widget.contentSize != null) {
      _lastContentSize = widget.contentSize;
      return widget.contentSize;
    }

    return _inferContentSize();
  }

  Size? _inferContentSize() {
    final RenderObject? renderObject =
        _contentKey.currentContext?.findRenderObject();
    if (renderObject is! RenderBox ||
        !renderObject.attached ||
        !renderObject.hasSize) {
      return _lastContentSize;
    }

    final Size size = renderObject.size;
    if (size.isEmpty) {
      return _lastContentSize;
    }

    _lastContentSize = size;
    return size;
  }

  /// Initialize gesture and keyboard handlers
  void _initializeHandlers() {
    _gestureHandler = GestureHandler(
      controller: controller,
      enableRotation: widget.interactionConfig.enableRotation,
      enableDoubleTapZoom:
          widget.zoomConfig.enableZoom && widget.zoomConfig.enableDoubleTapZoom,
      doubleTapZoomFactor: widget.zoomConfig.doubleTapZoomFactor,
      viewportKey: _viewportKey,
      enableCtrlScrollToScale:
          widget.zoomConfig.enableZoom &&
          widget.zoomConfig.enableCtrlScrollToScale,
      enableFling: widget.interactionConfig.enableFling,
      enableZoom: widget.zoomConfig.enableZoom,
    );
    _keyboardHandler = KeyboardHandler(
      controller: controller,
      keyboardPanDistance: widget.keyboardConfig.keyboardPanDistance,
      keyboardZoomFactor: widget.keyboardConfig.keyboardZoomFactor,
      enableKeyboardControls: widget.keyboardConfig.enableKeyboardControls,
      enableKeyboardZoom:
          widget.zoomConfig.enableZoom &&
          widget.keyboardConfig.enableKeyboardControls,
      enableKeyRepeat: widget.keyboardConfig.enableKeyRepeat,
      keyRepeatInitialDelay: widget.keyboardConfig.keyRepeatInitialDelay,
      keyRepeatInterval: widget.keyboardConfig.keyRepeatInterval,
      animateKeyboardTransitions:
          widget.keyboardConfig.animateKeyboardTransitions,
      keyboardAnimationDuration:
          widget.keyboardConfig.keyboardAnimationDuration,
      keyboardAnimationCurve: widget.keyboardConfig.keyboardAnimationCurve,
      focusNode: _focusNode,
      viewportKey: _viewportKey,
      invertArrowKeyDirection: widget.keyboardConfig.invertArrowKeyDirection,
    );
  }

  /// Center the content if a content size is provided
  void _centerContentIfNeeded() {
    final Size? contentSize = _resolveContentSize();
    if (contentSize != null) {
      centerContent(animate: false);
    }
  }

  @override
  void didUpdateWidget(CustomInteractiveViewer oldWidget) {
    super.didUpdateWidget(oldWidget);

    // Reinitialize handlers if any config changes
    final bool configChanged =
        oldWidget.zoomConfig != widget.zoomConfig ||
        oldWidget.interactionConfig != widget.interactionConfig ||
        oldWidget.keyboardConfig != widget.keyboardConfig;
    final bool focusNodeChanged = oldWidget.focusNode != widget.focusNode;
    if (configChanged || focusNodeChanged) {
      _gestureHandler.dispose();
      _keyboardHandler.dispose();

      if (focusNodeChanged) {
        if (_ownsFocusNode) {
          _focusNode.dispose();
        }
        _focusNode = widget.focusNode ?? FocusNode();
        _ownsFocusNode = widget.focusNode == null;
      }

      _initializeHandlers();
    }

    if (oldWidget.zoomConfig != widget.zoomConfig) {
      _syncControllerScaleLimits();
    }

    if (oldWidget.interactionConfig != widget.interactionConfig) {
      _syncInteractionBehavior();
    }
  }

  @override
  void dispose() {
    // Stop any active animations before disposing to prevent ticker assertion errors
    if (controller.vsync == this) {
      controller.stopAnimation(shouldNotify: false);
    }
    controller.detach(this);

    // Remove listeners before disposing resources
    controller.removeListener(_onControllerUpdate);
    HardwareKeyboard.instance.removeHandler(_handleHardwareKeyChange);

    // Dispose handlers
    _gestureHandler.dispose();
    _keyboardHandler.dispose();

    // Dispose focus node if it was created internally
    if (_ownsFocusNode) {
      _focusNode.dispose();
    }

    // Dispose controller if it was created internally
    if (widget.controller == null) {
      controller.dispose();
    }

    // Call super.dispose() last, after all cleanup
    super.dispose();
  }

  /// Handle hardware key changes to track ctrl key state
  bool _handleHardwareKeyChange(KeyEvent event) {
    if (event is KeyDownEvent &&
        (event.logicalKey == LogicalKeyboardKey.controlLeft ||
            event.logicalKey == LogicalKeyboardKey.controlRight)) {
      setState(() {
        _gestureHandler.isCtrlPressed = true;
      });
    } else if (event is KeyUpEvent &&
        (event.logicalKey == LogicalKeyboardKey.controlLeft ||
            event.logicalKey == LogicalKeyboardKey.controlRight)) {
      setState(() {
        _gestureHandler.isCtrlPressed = false;
      });
    }
    return false; // Allow other handlers to process this event
  }

  /// Update the UI when the controller state changes
  void _onControllerUpdate() => setState(() {});

  void _handlePointerDown(PointerDownEvent event) {
    _activePointers.add(event.pointer);
    _gestureHandler.handlePointerDown(event);
    _updateGestureBlockState();
  }

  void _handlePointerUp(PointerUpEvent event) {
    _activePointers.remove(event.pointer);
    _gestureHandler.handlePointerUp(event);
    _updateGestureBlockState();
  }

  void _handlePointerCancel(PointerCancelEvent event) {
    _activePointers.remove(event.pointer);
    _gestureHandler.handlePointerCancel(event);
    _updateGestureBlockState();
  }

  void _updateGestureBlockState() {
    final bool shouldBlock;
    if (_gesturesBlocked) {
      shouldBlock = _activePointers.isNotEmpty;
    } else {
      shouldBlock = _activePointers.length > 2;
    }
    if (shouldBlock == _gesturesBlocked) {
      return;
    }
    setState(() {
      _gesturesBlocked = shouldBlock;
      if (_gesturesBlocked) {
        _gestureHandler.forceCancelGesture();
      }
    });
  }

  /// Center the content in the viewport
  Future<void> centerContent({
    bool animate = true,
    Duration duration = const Duration(milliseconds: 300),
    Curve curve = Curves.easeInOut,
  }) async {
    final Size? contentSize = _resolveContentSize();
    if (contentSize == null) return;
    final RenderBox? box =
        _viewportKey.currentContext?.findRenderObject() as RenderBox?;
    if (box == null) return;

    final Size viewportSize = box.size;

    await controller.center(
      contentSize: contentSize,
      viewportSize: viewportSize,
      animate: animate,
      duration: duration,
      curve: curve,
    );
  }

  @override
  Widget build(BuildContext context) {
    final bool gesturesBlocked = _gesturesBlocked;
    final bool allowScale = !gesturesBlocked;
    final bool allowFling =
        !gesturesBlocked && widget.interactionConfig.enableFling;
    final bool allowDoubleTap =
        !gesturesBlocked && widget.zoomConfig.enableDoubleTapZoom;
    return FocusTraversalGroup(
      policy: _NoArrowTraversalPolicy(),
      child: KeyboardListener(
        focusNode: _focusNode,
        onKeyEvent: _keyboardHandler.handleKeyEvent,
        child: Listener(
          onPointerDown: _handlePointerDown,
          onPointerUp: _handlePointerUp,
          onPointerCancel: _handlePointerCancel,
          onPointerSignal: (PointerSignalEvent event) {
            if (event is PointerScrollEvent) {
              // On web, prevent default browser zoom behavior when Ctrl is pressed
              if (_gestureHandler.isCtrlPressed &&
                  widget.zoomConfig.enableCtrlScrollToScale) {
                // The event is handled by our zoom logic
                _gestureHandler.handlePointerScroll(event);
              } else {
                _gestureHandler.handlePointerScroll(event);
              }
            }
          },
          child: GestureDetector(
            key: _viewportKey,
            onScaleStart: allowScale ? _gestureHandler.handleScaleStart : null,
            onScaleUpdate:
                allowScale ? _gestureHandler.handleScaleUpdate : null,
            onScaleEnd: allowFling ? _gestureHandler.handleScaleEnd : null,
            onDoubleTapDown:
                allowDoubleTap ? _gestureHandler.handleDoubleTapDown : null,
            onDoubleTap:
                allowDoubleTap ? () => _gestureHandler.handleDoubleTap() : null,
            onTap:
                gesturesBlocked
                    ? null
                    : () {
                      if (!_focusNode.hasFocus) {
                        _focusNode.requestFocus();
                      }
                    },
            child: LayoutBuilder(
              builder: (context, constraints) {
                return Container(
                  color: Colors.transparent,
                  child: ClipRRect(
                    child: OverflowBox(
                      maxWidth: 1 / 0,
                      maxHeight: 1 / 0,
                      alignment: AlignmentDirectional.topStart,
                      child: Transform(
                        alignment: AlignmentDirectional.topStart,
                        transform: controller.transformationMatrix,
                        child: KeyedSubtree(
                          key: _contentKey,
                          child: widget.child,
                        ),
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
        ),
      ),
    );
  }
}

class _NoArrowTraversalPolicy extends WidgetOrderTraversalPolicy {
  @override
  bool inDirection(FocusNode currentNode, TraversalDirection direction) {
    // Block arrow key focus movement
    if (direction == TraversalDirection.left ||
        direction == TraversalDirection.right ||
        direction == TraversalDirection.up ||
        direction == TraversalDirection.down) {
      return false;
    }
    return super.inDirection(currentNode, direction);
  }
}
