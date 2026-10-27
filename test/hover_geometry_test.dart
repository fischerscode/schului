import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:schului/main.dart';

import 'sample_lesson.dart';

void main() {
  testWidgets(
    'hover requests current bounds and tracks changes without a new tree snapshot',
    (tester) async {
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetDevicePixelRatio);
      final nodes = sampleTree().map((node) => node.toMap()).toList();
      nodes.last['offscreen'] = true;
      nodes.last['width'] = 0.0;
      Map<String, dynamic>? geometry;
      var hovering = true;
      var geometryGeneration = 1;
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(bridge, (call) async {
            if (call.method == 'state') {
              return {
                'hoverTarget': hovering ? openTarget.toJson() : null,
                'hoverGeometry': geometry,
                'hoverGeneration': 1,
                'hoverGeometryGeneration': geometryGeneration,
                'nodes':
                    <
                      Object
                    >[], // The new rectangle is absent from the snapshot.
                'targetLeft': 100.0,
                'targetTop': 50.0,
              };
            }
            return null;
          });
      await tester.pumpWidget(
        SchoolApp(role: 'overlay', document: sampleDocument()),
      );
      await tester.pump();
      expect(
        find.byType(Positioned),
        findsNothing,
        reason: 'Snapshot coordinates must not be shown while waiting for fresh bounds.',
      );
      geometry = {
        ...nodes.last,
        'offscreen': false,
        'left': 450.0,
        'top': 300.0,
        'width': 130.0,
        'height': 90.0,
      };
      await tester.pump(const Duration(milliseconds: 100));
      await tester.pump();
      var frame = tester.widget<Positioned>(find.byType(Positioned));
      expect(frame.left, 346);
      expect(frame.top, 246);
      expect(frame.width, 138);
      geometry = {...geometry, 'left': 600.0, 'width': 220.0};
      await tester.pump(const Duration(milliseconds: 100));
      await tester.pump();
      frame = tester.widget<Positioned>(find.byType(Positioned));
      expect(frame.left, 496);
      expect(frame.width, 228);
      geometry = {...geometry, 'id': 'previous-hover'};
      geometryGeneration = 0;
      await tester.pump(const Duration(milliseconds: 100));
      await tester.pump();
      expect(
        find.byType(Positioned),
        findsNothing,
        reason: 'Late geometry from a previous hover is ignored.',
      );
      geometry = {...geometry, 'id': 'save'};
      hovering = false;
      await tester.pump(const Duration(milliseconds: 100));
      await tester.pump();
      expect(find.byType(Positioned), findsNothing);
      await tester.pumpWidget(const SizedBox());
    },
  );
}
