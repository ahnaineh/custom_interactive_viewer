## 0.0.8 - 2025-11-15

### Fixed
 - Auto center content on initiaization without animation
 - fix controller disposal issues


## 0.0.7 - 2025-07-19

### Fixed
- Fixed `constrainToViewport` method to properly handle rotation when constraining bounds during keyboard navigation
- Fixed `centerOnRect` method to correctly center on rectangles when content is rotated
- Both fixes now properly account for rotation transformations when calculating offsets and bounds
- API changes

## 0.0.6 - 2025-04-30

### Fixed
- Updated double-tap zoom functionality to use the new `zoom` method instead of deprecated `zoomIn` and `zoomOut` methods
- Improved code maintainability by removing usage of deprecated methods in gesture handling
- Imporoved dispose flow.
## 0.0.5 - 2025-04-18
### Fixed
- Zoom/Rotate center


## 0.0.4 - 2025-04-15

### Added
- When the viewer is tapped, it's in focus, allowing to directly use the keyboard to control it (arrows, page up/down, home/end). Previous focusing was done by navigating to the widget with the tab or arrow keys.
  Note: You can use the focus node to know when it's in focus & when not and request focus programmatically, check the [org_chart](https://pub.dev/packages/org_chart) example for more details.
- Added invertArrowKeyDirection property to the controller, which allows you to invert the arrow key direction.

### Fixed
- Fixed double tap to zoom issue (zooming center was not correct)
- Fixed keyboard navigation animation on key repeat

### Changed
- `zoomIn` - `zoomOut` - `panBy` are deprecated, use `zoom` and `pan` instead.


## 0.0.3 - 2025-04-13

### Added
- Fix Keyboard Navigation
- add rotate & rotateto method to controller
- add centeronrect method to controller
- update center method (viewportsize and contentsize are no longer required in it)
- introduced a bunch of flags like 'enableZoom'

## 0.0.2 - 2024-04-12

### Added
- Fling behavior for smooth inertial scrolling after quick pan gestures
- Dynamic friction coefficient that's adjusted based on gesture velocity
- Optimizations for fling animation performance

## 0.0.1 - 2024-04-12

### Added
- Initial release of the Custom Interactive Viewer package
- Core CustomInteractiveViewer widget with enhanced pan and zoom capabilities
- CustomInteractiveViewerController for programmatically controlling transformations
- TransformationState model for clean state management
- Support for keyboard navigation with arrow keys and zoom controls
- Mouse/touch gesture support including pinch-to-zoom and panning
- Optional content rotation functionality
- Support for content constraints to keep content within bounds
- Double-tap to zoom functionality
- Ctrl+scroll to scale for desktop environments
- Animation support for all transformations with customizable durations and curves
- Focal point preservation during zoom operations
- Helper methods for common operations:
  - Zoom in/out
  - Fit to screen
  - Center content
  - Zoom to specific regions
  - Reset to initial state
