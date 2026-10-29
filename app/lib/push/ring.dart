import 'package:flutter/services.dart';

/// Rings the phone while Mapa's own incoming-call screen is showing (Android only;
/// elsewhere this quietly does nothing). The lock-screen call has its own ringtone.
class Ring {
  static const _channel = MethodChannel('app.mapa/ring');

  static Future<void> start() async {
    try {
      await _channel.invokeMethod<void>('start');
    } on MissingPluginException {
      // not Android
    } catch (_) {}
  }

  static Future<void> stop() async {
    try {
      await _channel.invokeMethod<void>('stop');
    } on MissingPluginException {
      // not Android
    } catch (_) {}
  }
}
