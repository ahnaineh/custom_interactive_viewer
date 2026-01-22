import 'dart:math' as math;

import 'package:custom_interactive_viewer/custom_interactive_viewer.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vector_math/vector_math_64.dart';

Rect _boundsForState(TransformationState state, Size contentSize) {
  final Matrix4 matrix = state.toMatrix4();
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
    final Vector3 transformed = matrix.transform3(
      Vector3(corner.dx, corner.dy, 0),
    );
    minX = math.min(minX, transformed.x);
    maxX = math.max(maxX, transformed.x);
    minY = math.min(minY, transformed.y);
    maxY = math.max(maxY, transformed.y);
  }

  return Rect.fromLTRB(minX, minY, maxX, maxY);
}

void main() {
  test('zoom clamps to min and max scales', () async {
    final controller = CustomInteractiveViewerController(
      initialScale: 1.0,
      minScale: 0.5,
      maxScale: 2.0,
    );

    await controller.zoom(factor: 10.0, animate: false);
    expect(controller.scale, 2.0);

    await controller.zoom(factor: -10.0, animate: false);
    expect(controller.scale, 0.5);
  });

  test('constrainToViewport centers rotated content that fits', () {
    final TransformationState state = TransformationState(
      scale: 1.0,
      offset: const Offset(30, 15),
      rotation: math.pi / 2,
    );
    final Size contentSize = const Size(100, 50);
    final Size viewportSize = const Size(200, 200);

    final TransformationState constrained = state.constrainToViewport(
      contentSize,
      viewportSize,
    );

    final Rect bounds = _boundsForState(constrained, contentSize);
    expect(bounds.center.dx, closeTo(viewportSize.width / 2, 0.001));
    expect(bounds.center.dy, closeTo(viewportSize.height / 2, 0.001));
  });

  test('constrainToViewport clamps oversized content', () {
    final TransformationState state = TransformationState(
      scale: 1.0,
      offset: const Offset(50, -20),
      rotation: 0.0,
    );
    final Size contentSize = const Size(200, 100);
    final Size viewportSize = const Size(100, 100);

    final TransformationState constrained = state.constrainToViewport(
      contentSize,
      viewportSize,
    );

    expect(constrained.offset.dx, 0.0);
    expect(constrained.offset.dy, 0.0);
  });

  test('snap to grid behavior snaps offsets', () {
    final controller = CustomInteractiveViewerController();
    controller.interactionBehavior = InteractionBehavior.combine(
      const <InteractionBehavior>[
        SnapToGridBehavior(gridSize: Offset(10, 10)),
      ],
    );

    controller.applyInteraction(
      const InteractionRequest(panDelta: Offset(7, 7)),
    );

    expect(controller.offset, const Offset(10, 10));
  });

  testWidgets('pinch keeps focal point anchored', (tester) async {
    final controller = CustomInteractiveViewerController();

    await tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: Center(
          child: SizedBox(
            width: 200,
            height: 200,
            child: CustomInteractiveViewer(
              controller: controller,
              child: const SizedBox(width: 100, height: 100),
            ),
          ),
        ),
      ),
    );

    await tester.pumpAndSettle();

    final Finder viewerFinder = find.byType(CustomInteractiveViewer);
    final Offset globalCenter = tester.getCenter(viewerFinder);
    final RenderBox box = tester.renderObject(viewerFinder);
    final Offset localCenter = box.globalToLocal(globalCenter);

    final Offset contentBefore = controller.screenToContentPoint(localCenter);

    final TestGesture g1 =
        await tester.startGesture(globalCenter - const Offset(20, 0));
    final TestGesture g2 =
        await tester.startGesture(globalCenter + const Offset(20, 0));
    await tester.pump();

    await g1.moveTo(globalCenter - const Offset(40, 0));
    await g2.moveTo(globalCenter + const Offset(40, 0));
    await tester.pump();

    final Offset contentAfter = controller.screenToContentPoint(localCenter);

    expect((contentAfter - contentBefore).distance, lessThan(0.01));

    await g1.up();
    await g2.up();
  });

  testWidgets('pinch keeps focal point anchored in RTL', (tester) async {
    final controller = CustomInteractiveViewerController();

    await tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.rtl,
        child: Center(
          child: SizedBox(
            width: 200,
            height: 200,
            child: CustomInteractiveViewer(
              controller: controller,
              child: const SizedBox(width: 100, height: 100),
            ),
          ),
        ),
      ),
    );

    await tester.pumpAndSettle();

    final Finder viewerFinder = find.byType(CustomInteractiveViewer);
    final Offset globalCenter = tester.getCenter(viewerFinder);
    final RenderBox box = tester.renderObject(viewerFinder);
    final Offset localCenter = box.globalToLocal(globalCenter);

    final Offset contentBefore = controller.screenToContentPoint(localCenter);

    final TestGesture g1 =
        await tester.startGesture(globalCenter - const Offset(20, 0));
    final TestGesture g2 =
        await tester.startGesture(globalCenter + const Offset(20, 0));
    await tester.pump();

    await g1.moveTo(globalCenter - const Offset(40, 0));
    await g2.moveTo(globalCenter + const Offset(40, 0));
    await tester.pump();

    final Offset contentAfter = controller.screenToContentPoint(localCenter);

    expect((contentAfter - contentBefore).distance, lessThan(0.01));

    await g1.up();
    await g2.up();
  });

  testWidgets('ctrl scroll zooms at pointer', (tester) async {
    final controller = CustomInteractiveViewerController();

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: SizedBox(
              width: 200,
              height: 200,
              child: CustomInteractiveViewer(
                controller: controller,
                child: const SizedBox(width: 100, height: 100),
              ),
            ),
          ),
        ),
      ),
    );

    await tester.pumpAndSettle();

    final Finder viewerFinder = find.byType(CustomInteractiveViewer);
    final Offset globalCenter = tester.getCenter(viewerFinder);

    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.pump();

    tester.sendEventToBinding(
      PointerScrollEvent(
        position: globalCenter,
        scrollDelta: const Offset(0, -120),
      ),
    );
    await tester.pump();

    expect(controller.scale, greaterThan(1.0));

    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await tester.pump();
  });
}
