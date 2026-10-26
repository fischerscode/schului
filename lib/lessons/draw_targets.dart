import '../src/node_selector.dart';
import 'draw_target.dart';

// Full indexed paths from the export and user-provided Inspector paths.
// The historical exporter used Element
// for empty provider types; these paths preserve the actual empty type.
abstract final class DrawTargets {
  static const workingArea = DrawTarget(
    NodeSelector([
      PathSegment('Fenster', null),
      PathSegment('', '', index: 0),
      PathSegment('', '', index: 0),
      PathSegment('', '', index: 0),
      PathSegment('Dokument', null),
    ]),
  );
  static const sidebar = DrawTarget(
    NodeSelector([
      PathSegment('Fenster', null),
      PathSegment('', '', index: 0),
      PathSegment('', '', index: 0),
      PathSegment('', '', index: 2),
    ]),
    includesUnnamedClient: true,
  );
  static const drawingToolbar = DrawTarget(
    NodeSelector([
      PathSegment('Fenster', null),
      PathSegment('', '', index: 2),
      PathSegment('Symbolleiste', 'Zeichnung'),
    ]),
  );
  static const standardToolbar = DrawTarget(
    NodeSelector([
      PathSegment('Fenster', null),
      PathSegment('', '', index: 1),
      PathSegment('Symbolleiste', 'Standard'),
    ]),
  );
  static const rectangleTool = DrawTarget(
    NodeSelector([
      PathSegment('Fenster', null),
      PathSegment('', '', index: 2),
      PathSegment('Symbolleiste', 'Zeichnung'),
      PathSegment('Schaltfläche', 'Rechteck'),
    ]),
  );
  static const ellipseTool = DrawTarget(
    NodeSelector([
      PathSegment('Fenster', null),
      PathSegment('', '', index: 2),
      PathSegment('Symbolleiste', 'Zeichnung'),
      PathSegment('Schaltfläche', 'Ellipse'),
    ]),
  );
  static const lineTool = DrawTarget(
    NodeSelector([
      PathSegment('Fenster', null),
      PathSegment('', '', index: 2),
      PathSegment('Symbolleiste', 'Zeichnung'),
      PathSegment('Schaltfläche', 'Linie'),
    ]),
  );
  static const triangleTool = DrawTarget(
    NodeSelector([
      PathSegment('Fenster', null),
      PathSegment('', '', index: 2),
      PathSegment('Symbolleiste', 'Zeichnung'),
      PathSegment('Trennschaltfläche', 'Grundformen'),
    ]),
  );
  static const save = DrawTarget(
    NodeSelector([
      PathSegment('Fenster', null),
      PathSegment('', '', index: 1),
      PathSegment('Symbolleiste', 'Standard'),
      PathSegment('Trennschaltfläche', 'Speichern'),
    ]),
  );
  static const undo = DrawTarget(
    NodeSelector([
      PathSegment('Fenster', null),
      PathSegment('', '', index: 1),
      PathSegment('Symbolleiste', 'Standard'),
      PathSegment('Trennschaltfläche', 'Rückgängig'),
    ]),
  );
  static const arrange = DrawTarget(
    NodeSelector([
      PathSegment('Fenster', null),
      PathSegment('', '', index: 1),
      PathSegment('Symbolleiste', 'Standard'),
      PathSegment('Trennschaltfläche', 'Anordnen'),
    ]),
  );
  static const sidebarFillColor = DrawTarget(
    NodeSelector([
      PathSegment('Fenster', null),
      PathSegment('', '', index: 0),
      PathSegment('', '', index: 0),
      PathSegment('', '', index: 2),
      PathSegment('', 'Eigenschaften'),
      PathSegment('', '', index: 1),
      PathSegment('', '', index: 0),
      PathSegment('', '', index: 0),
      PathSegment('', '', index: 1),
      PathSegment('', '', index: 0),
      PathSegment('', '', index: 0),
      PathSegment('', '', index: 2),
      PathSegment('', '', index: 1),
      PathSegment('', '', index: 0),
      PathSegment('', '', index: 0),
      PathSegment('', '', index: 1),
      PathSegment('Symbolleiste', '', index: 0),
    ]),
    includesUnnamedClient: true,
  );
  static const width = DrawTarget(
    NodeSelector([
      PathSegment('Fenster', null),
      PathSegment('', '', index: 0),
      PathSegment('', '', index: 0),
      PathSegment('', '', index: 2),
      PathSegment('', 'Eigenschaften'),
      PathSegment('', '', index: 1),
      PathSegment('', '', index: 0),
      PathSegment('', '', index: 0),
      PathSegment('', '', index: 1),
      PathSegment('', '', index: 0),
      PathSegment('', '', index: 0),
      PathSegment('', '', index: 7),
      PathSegment('', '', index: 1),
      PathSegment('', '', index: 0),
      PathSegment('', '', index: 0),
      PathSegment('Netz', 'Breite'),
    ]),
    includesUnnamedClient: true,
  );
  static const height = DrawTarget(
    NodeSelector([
      PathSegment('Fenster', null),
      PathSegment('', '', index: 0),
      PathSegment('', '', index: 0),
      PathSegment('', '', index: 2),
      PathSegment('', 'Eigenschaften'),
      PathSegment('', '', index: 1),
      PathSegment('', '', index: 0),
      PathSegment('', '', index: 0),
      PathSegment('', '', index: 1),
      PathSegment('', '', index: 0),
      PathSegment('', '', index: 0),
      PathSegment('', '', index: 7),
      PathSegment('', '', index: 1),
      PathSegment('', '', index: 0),
      PathSegment('', '', index: 0),
      PathSegment('Netz', 'Höhe'),
    ]),
    includesUnnamedClient: true,
  );
  static const rectangleObject = DrawTarget(
    NodeSelector([
      PathSegment('Fenster', null),
      PathSegment('', '', index: 0),
      PathSegment('', '', index: 0),
      PathSegment('', '', index: 0),
      PathSegment('', '', index: 0),
      PathSegment('Dokument', null),
      PathSegment('', 'Rectangle '),
    ]),
    includesUnnamedClient: true,
  );
}
