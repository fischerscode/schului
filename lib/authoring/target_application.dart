sealed class TargetApplication {
  const TargetApplication();
  String get name;
  Map<String, Object?> toJson();

  factory TargetApplication.fromJson(Object? raw) {
    if (raw is! Map<String, Object?>) {
      throw const FormatException('Zielsoftware fehlt.');
    }
    return switch (raw['kind']) {
      'unconfigured' => const UnconfiguredApplication(),
      'libreoffice.draw' => const DrawApplication(),
      'windows' => WindowsApplication(
        name: _text(raw['name']),
        executable: _text(raw['executable']),
        arguments: _arguments(raw['arguments']),
        windowClass: _text(raw['windowClass'], empty: true),
        titleContains: _text(raw['titleContains'], empty: true),
      ),
      _ => throw const FormatException(
        'Unbekannte Zielsoftware-Konfiguration.',
      ),
    };
  }
  static String _text(Object? value, {bool empty = false}) {
    if (value is! String ||
        value.length > 32768 ||
        value.contains('\u0000') ||
        (!empty && value.trim().isEmpty)) {
      throw const FormatException('Ungültige Programmeinstellung.');
    }
    return value;
  }

  static List<String> _arguments(Object? value) {
    if (value is! List<Object?> || value.length > 100) {
      throw const FormatException('Ungültige Startargumente.');
    }
    return [for (final item in value) _text(item, empty: true)];
  }
}

class UnconfiguredApplication extends TargetApplication {
  const UnconfiguredApplication();
  @override
  String get name => 'Zielsoftware auswählen';
  @override
  Map<String, Object?> toJson() => {'kind': 'unconfigured'};
}

class DrawApplication extends TargetApplication {
  const DrawApplication();
  @override
  String get name => 'LibreOffice Draw';
  @override
  Map<String, Object?> toJson() => {'kind': 'libreoffice.draw'};
}

class WindowsApplication extends TargetApplication {
  WindowsApplication({
    required this.name,
    required this.executable,
    List<String> arguments = const [],
    this.windowClass = '',
    this.titleContains = '',
  }) : arguments = List.unmodifiable(arguments) {
    TargetApplication._text(name);
    TargetApplication._text(executable);
    if (!RegExp(r'^(?:[a-zA-Z]:[\\/]|\\\\)').hasMatch(executable)) {
      throw const FormatException(
        'Einen absoluten Windows-Programmpfad auswählen.',
      );
    }
    TargetApplication._text(windowClass, empty: true);
    TargetApplication._text(titleContains, empty: true);
    TargetApplication._arguments(this.arguments);
  }
  @override
  final String name;
  final String executable, windowClass, titleContains;
  final List<String> arguments;
  @override
  Map<String, Object?> toJson() => {
    'kind': 'windows',
    'name': name,
    'executable': executable,
    'arguments': arguments,
    'windowClass': windowClass,
    'titleContains': titleContains,
  };
}
