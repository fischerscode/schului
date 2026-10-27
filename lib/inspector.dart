import 'main.dart' as application;

// Alternate entry point; the overlay and hint engines retain their roles.
void main(List<String> args) {
  application.main([
    if (args.isEmpty || args.first == 'lesson') 'inspector' else args.first,
    ...args.skip(1),
  ]);
}
