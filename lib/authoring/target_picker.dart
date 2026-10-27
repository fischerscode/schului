import 'package:flutter/services.dart';

import '../lessons/application_target.dart';
import 'target_application.dart';

const targetPickerChannel = MethodChannel('schului/target-picker');

/// One native picker per editor. Candidate messages contain presentation only;
/// the confirmed result is validated before it becomes an authored target.
class TargetPicker {
  Future<ApplicationTarget?> pick({
    required void Function(String label, String error) onCandidate,
    required TargetApplication application,
  }) async {
    targetPickerChannel.setMethodCallHandler((call) async {
      if (call.method != 'candidate') return;
      final raw = call.arguments;
      if (raw is Map<Object?, Object?> &&
          raw['label'] is String &&
          raw['error'] is String) {
        onCandidate(raw['label'] as String, raw['error'] as String);
      }
    });
    try {
      final raw = await targetPickerChannel.invokeMethod<Object?>(
        'begin',
        application.toJson(),
      );
      if (raw == null) return null;
      if (raw is! Map<Object?, Object?>) {
        throw const FormatException(
          'Windows hat einen ungültigen Zielpfad geliefert.',
        );
      }
      return ApplicationTarget.fromJson(raw);
    } finally {
      targetPickerChannel.setMethodCallHandler(null);
    }
  }

  Future<void> cancel() async {
    try {
      await targetPickerChannel.invokeMethod<void>('cancel');
    } on MissingPluginException {
      // No native picker was started in a non-Windows preview.
    }
  }
}
