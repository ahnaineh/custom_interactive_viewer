import 'package:custom_interactive_viewer/src/config/interaction_config.dart';
import 'package:custom_interactive_viewer/src/config/keyboard_config.dart';
import 'package:custom_interactive_viewer/src/config/zoom_config.dart';
import 'package:custom_interactive_viewer/src/controller/interactive_controller.dart';
import 'package:custom_interactive_viewer/src/handlers/gesture_handler.dart';
import 'package:custom_interactive_viewer/src/handlers/keyboard_handler.dart';
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
  final CustomInteractiveViewerController? controller;

  /// The size of the content being displayed. Used for centering and constraints.
  final Size? contentSize;

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

  /// Focus node for keyboard input.
  late final FocusNode _focusNode = widget.focusNode ?? FocusNode();

  /// Handles gesture interactions.
  late GestureHandler _gestureHandler;

  /// Handles keyboard interactions.
  late KeyboardHandler _keyboardHandler;

  @override
  void initState() {
    super.initState();
    controller.vsync = this;
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

  /// Register viewport and content size getters with the controller
  void _registerControllerSizeGetters() {
    // Register viewport size getter
    controller.viewportSizeGetter = () {
      final RenderBox? box =
          _viewportKey.currentContext?.findRenderObject() as RenderBox?;
      return box?.size;
    };

    // Register content size getter if available
    if (widget.contentSize != null) {
      controller.contentSizeGetter = () => widget.contentSize;
    }
  }

  /// Initialize gesture and keyboard handlers
  void _initializeHandlers() {
    _gestureHandler = GestureHandler(
      controller: controller,
      enableRotation: widget.interactionConfig.enableRotation,
      constrainBounds: widget.interactionConfig.constrainBounds,
      enableDoubleTapZoom:
          widget.zoomConfig.enableZoom && widget.zoomConfig.enableDoubleTapZoom,
      doubleTapZoomFactor: widget.zoomConfig.doubleTapZoomFactor,
      contentSize: widget.contentSize,
      viewportKey: _viewportKey,
      enableCtrlScrollToScale:
          widget.zoomConfig.enableZoom &&
          widget.zoomConfig.enableCtrlScrollToScale,
      minScale: widget.zoomConfig.minScale,
      maxScale: widget.zoomConfig.maxScale,
      enableFling: widget.interactionConfig.enableFling,
      enableZoom: widget.zoomConfig.enableZoom,
      scrollMode: widget.interactionConfig.scrollMode,
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
      constrainBounds: widget.interactionConfig.constrainBounds,
      contentSize: widget.contentSize,
      viewportKey: _viewportKey,
      minScale: widget.zoomConfig.minScale,
      maxScale: widget.zoomConfig.maxScale,
      invertArrowKeyDirection: widget.keyboardConfig.invertArrowKeyDirection,
      scrollMode: widget.interactionConfig.scrollMode,
    );
  }

  /// Center the content if a content size is provided
  void _centerContentIfNeeded() {
    if (widget.contentSize != null) {
      centerContent(animate: false);
    }
  }

  @override
  void didUpdateWidget(CustomInteractiveViewer oldWidget) {
    super.didUpdateWidget(oldWidget);

    // Update content size getter if content size changes
    if (oldWidget.contentSize != widget.contentSize) {
      if (widget.contentSize != null) {
        controller.contentSizeGetter = () => widget.contentSize!;
      } else {
        controller.contentSizeGetter = null;
      }
    }

    // Reinitialize handlers if any config changes
    if (oldWidget.zoomConfig != widget.zoomConfig ||
        oldWidget.interactionConfig != widget.interactionConfig ||
        oldWidget.keyboardConfig != widget.keyboardConfig) {
      _initializeHandlers();
    }
  }

  @override
  void dispose() {
    // Stop any active animations before disposing to prevent ticker assertion errors
    controller.stopAnimation(shouldNotify: false);

    // Remove listeners before disposing resources
    controller.removeListener(_onControllerUpdate);
    HardwareKeyboard.instance.removeHandler(_handleHardwareKeyChange);

    // Dispose handlers
    _gestureHandler.dispose();
    _keyboardHandler.dispose();

    // Dispose focus node if it was created internally
    if (widget.focusNode == null) {
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

  /// Center the content in the viewport
  Future<void> centerContent({
    bool animate = true,
    Duration duration = const Duration(milliseconds: 300),
    Curve curve = Curves.easeInOut,
  }) async {
    if (widget.contentSize == null) return;
    final RenderBox? box =
        _viewportKey.currentContext?.findRenderObject() as RenderBox?;
    if (box == null) return;

    final Size viewportSize = box.size;

    await controller.center(
      contentSize: widget.contentSize,
      viewportSize: viewportSize,
      animate: animate,
      duration: duration,
      curve: curve,
    );
  }

  @override
  Widget build(BuildContext context) {
    return FocusTraversalGroup(
      policy: _NoArrowTraversalPolicy(),
      child: KeyboardListener(
        focusNode: _focusNode,
        onKeyEvent: _keyboardHandler.handleKeyEvent,
        child: Listener(
          onPointerSignal: (PointerSignalEvent event) {
            if (event is PointerScrollEvent) {
              // On web, prevent default browser zoom behavior when Ctrl is pressed
              if (_gestureHandler.isCtrlPressed &&
                  widget.zoomConfig.enableCtrlScrollToScale) {
                // The event is handled by our zoom logic
                _gestureHandler.handlePointerScroll(event, context);
              } else {
                _gestureHandler.handlePointerScroll(event, context);
              }
            }
          },
          child: GestureDetector(
            onScaleStart: _gestureHandler.handleScaleStart,
            onScaleUpdate: _gestureHandler.handleScaleUpdate,
            onScaleEnd:
                widget.interactionConfig.enableFling
                    ? _gestureHandler.handleScaleEnd
                    : null,
            onDoubleTapDown:
                widget.zoomConfig.enableDoubleTapZoom
                    ? _gestureHandler.handleDoubleTapDown
                    : null,
            onDoubleTap:
                widget.zoomConfig.enableDoubleTapZoom
                    ? () => _gestureHandler.handleDoubleTap(context)
                    : null,
            onTap: () {
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
                      key: _viewportKey,
                      maxWidth: 1 / 0,
                      maxHeight: 1 / 0,
                      alignment: AlignmentDirectional.topStart,
                      child: Transform(
                        alignment: AlignmentDirectional.topStart,
                        transform: controller.transformationMatrix,
                        child: widget.child,
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
