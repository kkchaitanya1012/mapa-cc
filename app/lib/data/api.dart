import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';

import '../config.dart';
import 'models.dart';

class ApiError implements Exception {
  ApiError(this.code, this.status);
  final String code;
  final int status;

  /// Plain-language message for the person, never the raw code.
  String get message => switch (code) {
        'invalid_code' => "That code doesn't match. Check it and try again.",
        'code_expired' => 'That code has expired. Ask for a new one.',
        'code_used' => 'That code was already used. Ask for a new one.',
        'self_pair' => "That's your own code. Enter it on the other person's phone.",
        'too_many_attempts' => 'Too many tries. Wait a few minutes and try again.',
        'caretaker_only' || 'recipient_only' => 'This phone is set up for the other role.',
        'link_not_found' => 'That person is no longer paired.',
        'not_ringing' || 'call_expired' => 'That call has already ended.',
        'calls_not_configured' => 'Calling is not switched on yet.',
        'call_finished' => 'That call has already finished.',
        'assistant_unavailable' => "Mapa's assistant is busy. Try again in a moment.",
        'unreachable' => "Can't reach Mapa right now. Check your connection.",
        _ => 'Something went wrong. Please try again.',
      };

  @override
  String toString() => 'ApiError($code, $status)';
}

/// Talks to the Python service. Reads go straight to Supabase instead.
class ApiClient {
  Future<Map<String, dynamic>> _send(String method, String path, [Map<String, dynamic>? body]) async {
    final token = Supabase.instance.client.auth.currentSession?.accessToken;
    final req = http.Request(method, Uri.parse('${Config.apiBaseUrl}$path'))
      ..headers['content-type'] = 'application/json'
      ..headers['authorization'] = 'Bearer ${token ?? ''}';
    if (body != null) req.body = jsonEncode(body);
    try {
      final res = await http.Response.fromStream(await req.send().timeout(const Duration(seconds: 20)));
      final decoded = res.body.isEmpty ? <String, dynamic>{} : jsonDecode(res.body);
      if (res.statusCode >= 400) {
        final d = decoded is Map ? decoded['detail'] : null;
        throw ApiError(d is String ? d : 'error', res.statusCode);
      }
      return decoded is Map<String, dynamic> ? decoded : <String, dynamic>{};
    } on ApiError {
      rethrow;
    } on TimeoutException {
      throw ApiError('unreachable', 0);
    } catch (_) {
      throw ApiError('unreachable', 0);
    }
  }

  Future<void> putProfile({required String role, required String displayName, String language = 'en', String timezone = 'Asia/Kolkata'}) =>
      _send('PUT', '/me/profile', {'role': role, 'display_name': displayName, 'language': language, 'timezone': timezone});

  Future<({String code, String qrPayload, DateTime expiresAt})> createCode(String label) async {
    final j = await _send('POST', '/pairing/codes', {'recipient_label': label});
    return (code: j['code'] as String, qrPayload: j['qr_payload'] as String, expiresAt: DateTime.parse(j['expires_at']).toLocal());
  }

  Future<String> redeem(String code) async => (await _send('POST', '/pairing/redeem', {'code': code}))['link_id'] as String;

  Future<ChatReply> chat(String linkId, List<({String role, String text})> messages) async => ChatReply.fromJson(
      await _send('POST', '/chat', {
        'link_id': linkId,
        'messages': [for (final m in messages) {'role': m.role, 'text': m.text}],
      }));

  Future<void> createReminders(String linkId, Map<String, dynamic> draft) =>
      _send('POST', '/reminders', {'link_id': linkId, 'draft': draft});

  Future<void> putPushToken(String token) => _send('PUT', '/me/push-token', {'token': token});

  Future<void> deleteReminder(String id) => _send('DELETE', '/reminders/$id');

  // ---- calls

  /// The parent answered: trade the ringing call for a room token.
  Future<({String url, String token})> joinCall(String occurrenceId) async {
    final j = await _send('POST', '/calls/$occurrenceId/join');
    return (url: j['url'] as String, token: j['token'] as String);
  }

  Future<void> declineCall(String occurrenceId) => _send('POST', '/calls/$occurrenceId/decline');

  /// Caretaker: ring them now instead of at the scheduled time.
  /// Returns 'calling' or 'already_calling'.
  Future<String> callNow(String occurrenceId) async =>
      (await _send('POST', '/calls/$occurrenceId/call-now'))['status'] as String? ?? 'calling';
}
