# Custom Interactive Viewer

A highly customizable replacement for Flutter's InteractiveViewer with advanced features including keyboard navigation, custom transformations, scroll modes, and flexible gesture controls.

## Features

- **Enhanced Zooming** - Zoom with gestures, keyboard controls, or programmatically with animations
- **Precise Panning** - Pan content with touch, mouse, or keyboard arrow keys
- **Scroll Modes** - Control scroll direction: horizontal only, vertical only, both, or none
- **Optional Rotation** - Enable rotation with multi-touch gestures
- **Keyboard Navigation** - Built-in keyboard controls with customizable key repeat
- **Programmable Controls** - Full API for controlling the view programmatically
- **Bounds Constraints** - Optional content constraints to keep content within viewport
- **Custom Animation** - Animate transformations with customizable durations and curves
- **Focal Point Zooming** - Zoom to a specific point with proper focal point preservation
- **Double Tap Support** - Optional double-tap to zoom feature
- **Ctrl+Scroll Zooming** - Desktop-friendly zoom with keyboard modifier keys
- **Region Targeting** - Zoom to specific regions of content
- **Fling Physics** - Smooth momentum scrolling after quick pan gestures

## Getting Started

Add the package to your `pubspec.yaml` file:

```yaml
dependencies:
  custom_interactive_viewer: ^0.0.9
```

Then import it in your Dart code:

```dart
import 'package:custom_interactive_viewer/custom_interactive_viewer.dart';
```

## Usage

### Basic Usage

```dart
// Create a controller
final controller = CustomInteractiveViewerController();

// Use the widget with default configuration
CustomInteractiveViewer(
  controller: controller,
  child: Image.asset('assets/image.jpg'),
);
```

### With Custom Configuration

```dart
CustomInteractiveViewer(
  controller: controller,
  contentSize: const Size(1000, 800),
  zoomConfig: const ZoomConfig(
    enableZoom: true,
    minScale: 0.5,
    maxScale: 4.0,
    enableDoubleTapZoom: true,
    doubleTapZoomFactor: 2.0,
    enableCtrlScrollToScale: true,
  ),
  interactionConfig: const InteractionConfig(
    enableRotation: false,
    constrainBounds: true,
    enableFling: true,
    scrollMode: ScrollMode.both,
  ),
  keyboardConfig: const KeyboardConfig(
    enableKeyboardControls: true,
    keyboardPanDistance: 20.0,
    keyboardZoomFactor: 1.1,
    enableKeyRepeat: true,
    animateKeyboardTransitions: true,
  ),
  child: Image.asset('assets/map.jpg'),
);
```

### Content Size Resolution

CustomInteractiveViewer needs the logical content size to center content and
constrain panning when bounds are enabled. It resolves size in this order:

1) contentSizeGetter (source of truth)
2) contentSize (fixed size)
3) inferred from the child's render size (default)

Use contentSizeGetter when:
- the child paints outside its layout bounds (CustomPaint)
- the logical content is larger than the laid-out widget (virtualized lists/slivers)
- you need to include extra margins/padding in the logical bounds

When provided, it is treated as the source of truth; return a non-null size when
calling center/fit or when bounds are constrained.

Example:

```dart
CustomInteractiveViewer(
  contentSizeGetter: () => const Size(4000, 2000),
  child: CustomPaint(
    painter: MyCanvasPainter(),
  ),
);
```

Tip: For normal widgets (Image, Container, Stack), you can omit both and let
the viewer infer the size.

### Using Preset Configurations

```dart
// Image viewer configuration
CustomInteractiveViewer(
  controller: controller,
  interactionConfig: const InteractionConfig.imageViewer(),
  child: Image.asset('assets/photo.jpg'),
);

// Disabled interactions
CustomInteractiveViewer(
  controller: controller,
  zoomConfig: const ZoomConfig.disabled(),
  interactionConfig: const InteractionConfig.disabled(),
  keyboardConfig: const KeyboardConfig.disabled(),
  child: YourWidget(),
);

// Fast keyboard controls
CustomInteractiveViewer(
  controller: controller,
  keyboardConfig: const KeyboardConfig.fast(),
  child: YourWidget(),
);
```

### Programmatic Control

```dart
// Zoom operations
controller.zoom(
  factor: 0.5,  // Positive to zoom in, negative to zoom out
  focalPoint: const Offset(100, 100),
  animate: true,
);

// Pan operations
controller.pan(
  const Offset(50, 50),
  animate: true,
);

// Rotation operations (if enabled)
controller.rotate(
  0.5,  // Angle in radians
  focalPoint: const Offset(100, 100),
  animate: true,
);

// Fit content to screen
controller.fitToScreen(
  contentSize, 
  viewportSize,
  padding: 20.0,
  animate: true,
);

// Center content
controller.center(
  contentSize: contentSize,
  viewportSize: viewportSize,
  animate: true,
);

// Zoom to specific region
controller.zoomToRegion(
  const Rect.fromLTWH(100, 100, 200, 200),
  viewportSize,
  animate: true,
);

// Reset to initial state
controller.reset(animate: true);

// Animate to custom state
controller.animateTo(
  targetState: TransformationState(
    scale: 2.0,
    offset: const Offset(100, 100),
    rotation: 0.0,
  ),
  duration: const Duration(milliseconds: 300),
  curve: Curves.easeInOut,
);
```

## API Documentation

### Configuration Classes

#### ZoomConfig
Configuration for zoom-related behavior:

```dart
const ZoomConfig({
  bool enableZoom = true,
  double minScale = 0.5,
  double maxScale = 4.0,
  bool enableDoubleTapZoom = false,
  double doubleTapZoomFactor = 2.0,
  bool enableCtrlScrollToScale = true,
});
```

#### InteractionConfig
Configuration for gesture and interaction behavior:

```dart
const InteractionConfig({
  bool enableRotation = false,
  bool constrainBounds = false,
  bool enableFling = true,
  ScrollMode scrollMode = ScrollMode.both,
});
```

#### KeyboardConfig
Configuration for keyboard controls:

```dart
const KeyboardConfig({
  bool enableKeyboardControls = true,
  double keyboardPanDistance = 20.0,
  double keyboardZoomFactor = 1.1,
  bool enableKeyRepeat = true,
  Duration keyRepeatInitialDelay = const Duration(milliseconds: 500),
  Duration keyRepeatInterval = const Duration(milliseconds: 50),
  bool animateKeyboardTransitions = true,
  Duration keyboardAnimationDuration = const Duration(milliseconds: 200),
  Curve keyboardAnimationCurve = Curves.easeOutCubic,
  bool invertArrowKeyDirection = false,
});
```

#### ScrollMode Enum
Defines allowed scroll directions:

```dart
enum ScrollMode {
  both,       // Allow scrolling in both directions
  horizontal, // Allow horizontal scrolling only
  vertical,   // Allow vertical scrolling only
  none,       // Disable scrolling
}
```

### Widget Parameters

```dart
CustomInteractiveViewer({
  Key? key,
  required Widget child,
  CustomInteractiveViewerController? controller,
  Size? contentSize,
  Size? Function()? contentSizeGetter,
  ZoomConfig zoomConfig = const ZoomConfig(),
  InteractionConfig interactionConfig = const InteractionConfig(),
  KeyboardConfig keyboardConfig = const KeyboardConfig(),
  FocusNode? focusNode,
});
```

### Controller Events

The controller supports event callbacks:

```dart
final controller = CustomInteractiveViewerController(
  onEvent: (ViewerEvent event) {
    switch (event) {
      case ViewerEvent.transformationStart:
        print('User started transforming');
        break;
      case ViewerEvent.transformationUpdate:
        print('Transformation updated');
        break;
      case ViewerEvent.transformationEnd:
        print('User finished transforming');
        break;
      case ViewerEvent.animationStart:
        print('Animation started');
        break;
      case ViewerEvent.animationEnd:
        print('Animation ended');
        break;
    }
  },
);
```

### Keyboard Controls

- **Arrow Keys**: Pan the view (direction can be inverted with `invertArrowKeyDirection`)
- **+ / -**: Zoom in/out
- **Home**: Reset to initial state
- **Ctrl + Scroll**: Zoom with mouse wheel (desktop)

### Coordinate System

The package provides coordinate conversion methods:

```dart
// Convert screen point to content coordinates
Offset contentPoint = controller.screenToContentPoint(screenPoint);

// Convert content point to screen coordinates
Offset screenPoint = controller.contentToScreenPoint(contentPoint);
```

## Examples

### Map Viewer Example

```dart
import 'package:flutter/material.dart';
import 'package:custom_interactive_viewer/custom_interactive_viewer.dart';

class MapViewer extends StatefulWidget {
  @override
  _MapViewerState createState() => _MapViewerState();
}

class _MapViewerState extends State<MapViewer> {
  late final CustomInteractiveViewerController controller;

  @override
  void initState() {
    super.initState();
    controller = CustomInteractiveViewerController();
  }

  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Map Viewer'),
        actions: [
          IconButton(
            icon: const Icon(Icons.zoom_in),
            onPressed: () => controller.zoom(factor: 0.5),
          ),
          IconButton(
            icon: const Icon(Icons.zoom_out),
            onPressed: () => controller.zoom(factor: -0.5),
          ),
          IconButton(
            icon: const Icon(Icons.center_focus_strong),
            onPressed: () => controller.center(),
          ),
        ],
      ),
      body: CustomInteractiveViewer(
        controller: controller,
        contentSize: const Size(2000, 2000),
        zoomConfig: const ZoomConfig(
          minScale: 0.1,
          maxScale: 10.0,
          enableDoubleTapZoom: true,
        ),
        interactionConfig: const InteractionConfig(
          constrainBounds: true,
          enableFling: true,
        ),
        child: Image.asset('assets/map.png'),
      ),
    );
  }
}
```

### Document Viewer with Vertical Scroll Only

```dart
CustomInteractiveViewer(
  controller: controller,
  interactionConfig: const InteractionConfig(
    scrollMode: ScrollMode.vertical,
    constrainBounds: true,
  ),
  keyboardConfig: const KeyboardConfig(
    invertArrowKeyDirection: true,  // Natural scrolling
  ),
  child: YourDocumentWidget(),
);
```

## Contributing

If you find any issues or have suggestions for improvements, please file an issue or submit a pull request.