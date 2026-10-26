import 'draw_targets.dart';
import 'lesson_model.dart';
export 'lesson_model.dart';

const steps = [
  LessonStep(
    'Hallo, Draw!',
    [
      LessonParagraph([
        LessonText(
          'Mit LibreOffice Draw kannst du Zeichnungen am Computer erstellen. Dafür stehen dir verschiedene Formen, Linien und Farben zur Verfügung.',
        ),
      ]),
      LessonParagraph([
        LessonText(
          'Heute lernst du das Programm kennen und erstellst eine eigene Zeichnung.',
        ),
      ]),
    ],
    'Fahre mit der Maus über die blau unterstrichenen Begriffe, um die passende Stelle in Draw zu sehen.',
  ),
  LessonStep(
    'Dein erstes Objekt',
    [
      LessonParagraph([
        LessonText('Im '),
        LessonLink('Arbeitsbereich', target: DrawTargets.workingArea),
        LessonText(
          ' erstellst du deine Zeichnung. Dafür verwendest du die Werkzeuge aus der ',
        ),
        LessonLink('linken Symbolleiste', target: DrawTargets.drawingToolbar),
        LessonText('.'),
      ]),
      LessonParagraph([
        LessonText('Wähle '),
        LessonLink('Rechteck', target: DrawTargets.rectangleTool),
        LessonText(' durch einen Linksklick aus.'),
      ]),
      LessonParagraph([
        LessonText('Ziehe nun im '),
        LessonLink('Arbeitsbereich', target: DrawTargets.workingArea),
        LessonText(
          ' ein Rechteck auf, indem du die linke Maustaste gedrückt hältst.',
        ),
      ]),
      LessonParagraph([
        LessonText('Du hast dein erstes '),
        LessonLink('Objekt', target: DrawTargets.rectangleObject),
        LessonText(' erstellt!'),
      ]),
    ],
    'Wähle Rechteck und ziehe auf dem Zeichenblatt mit gedrückter linker Maustaste.',
  ),
  LessonStep('Dein Objekt hat Attribute', [
    LessonParagraph([
      LessonText('Wähle dein '),
      LessonLink('Objekt', target: DrawTargets.rectangleObject),
      LessonText(' durch einen Linksklick aus.'),
    ]),
    LessonParagraph([
      LessonText('In der '),
      LessonLink('Seitenleiste', target: DrawTargets.sidebar),
      LessonText(
        ' kannst du die Eigenschaften deines Objekts verändern. Diese Eigenschaften heißen Attribute.',
      ),
      LessonText('.'),
    ]),
    LessonParagraph([
      LessonText('Setze das Attribut '),
      LessonLink('Füllfarbe', target: DrawTargets.sidebarFillColor),
      LessonText(' auf den Attributwert "rot".'),
    ]),
    LessonParagraph([
      LessonText('Verändere anschließend die '),
      LessonLink('Breite', target: DrawTargets.width),
      LessonText(' und '),
      LessonLink('Höhe', target: DrawTargets.height),
      LessonText(' deines Rechtecks.'),
    ]),
  ], 'Die Eigenschaften erscheinen, wenn du dein Objekt auswählst.'),
  LessonStep('Speichere deine Zeichnung', [
    LessonParagraph([
      LessonText(
        'Damit deine Zeichnung nicht verloren geht, musst du sie speichern.',
      ),
    ]),
    LessonParagraph([
      LessonText('Klicke in der '),
      LessonLink('oberen Symbolleiste', target: DrawTargets.standardToolbar),
      LessonText(' auf '),
      LessonLink('Speichern', target: DrawTargets.save),
      LessonText('.'),
    ]),
    LessonParagraph([
      LessonText(
        'Speichere die Datei im Ordner "Informatik 06" den du bereits in deinem Namenslaufwerk angelegt hast.',
      ),
    ]),
    LessonParagraph([LessonText('Nenne die Datei "in der Pause.odg"')]),
  ], 'Beim ersten Speichern wählst du Ordner, Dateiname und Dateiformat.'),
  LessonStep('Was hast du gelernt?', [
    LessonActivity(
      'Lückentext öffnen',
      url: 'https://learningapps.org/show.php?id=px5j6w0gc26',
    ),
    LessonParagraph([
      LessonText('Übertrage anschließend die Lücken auf dein Arbeitsblatt.'),
    ]),
  ], 'Nutze die LearningApps-Aufgabe aus deinem Unterricht.'),
  LessonStep('Dein Pausenbild', [
    LessonParagraph([
      LessonText(
        'Zeichne ein eigenes Bild in Draw. Orientiere dich an deiner Skizze und verwende die Formen ',
      ),
      LessonLink('Rechteck', target: DrawTargets.rectangleTool),
      LessonText(', '),
      LessonLink('Ellipse/Kreis', target: DrawTargets.ellipseTool),
      LessonText(', '),
      LessonLink(
        'Dreieck',
        target: DrawTargets.triangleTool,
        help: 'Öffne Grundformen und wähle dort das Dreieck aus.',
      ),
      LessonText(' und '),
      LessonLink('Linie', target: DrawTargets.lineTool),
      LessonText('.'),
    ]),
    LessonParagraph([
      LessonText('Verändere die Farben und Größen deiner Objekte.'),
    ]),
    LessonParagraph([LessonText('Tipps:', bold: true)]),
    LessonBulletList([
      LessonParagraph([
        LessonText('Wenn ein Objekt verdeckt ist, kannst du es über '),
        LessonLink('Anordnen', target: DrawTargets.arrange),
        LessonText(' nach vorne bringen.'),
      ]),
      LessonParagraph([
        LessonText('Mit '),
        LessonLink('Rückgängig', target: DrawTargets.undo),
        LessonText(' in der '),
        LessonLink('oberen Symbolleiste', target: DrawTargets.standardToolbar),
        LessonText(' kannst du deine letzte Aktion rückgängig machen.'),
      ]),
      LessonParagraph([
        LessonText(
          'Mit der Entf-Taste kannst du ein ausgewähltes Objekt löschen.',
        ),
      ]),
    ]),
  ], 'Wähle ein Objekt aus, bevor du seine Eigenschaften veränderst.'),
  LessonStep('Fertig!', [
    LessonParagraph([
      LessonText('Vergesse nicht zu '),
      LessonLink('Speichern', target: DrawTargets.save),
      LessonText(' vor dem Schließen.'),
    ]),
  ], 'Zum Beispiel: Füllfarbe – Rot.'),
];
