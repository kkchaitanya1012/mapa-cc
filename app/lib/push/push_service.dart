import 'dart:async';
import 'dart:io' show Platform;

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_callkit_incoming/entities/entities.dart';
import 'package:flutter_callkit_incoming/flutter_callkit_incoming.dart';

import '../config.dart';
import '../data/call.dart';
import '../data/repo.dart';
import '../router.dart';

FirebaseOptions get _options => FirebaseOptions(
      apiKey: Config.firebaseApiKey,
      appId: Config.firebaseAppId,
      messagingSenderId: Config.firebaseSenderId,
      projectId: Config.firebaseProjectId,
    );

/// Shows the native incoming-call screen: full screen over the lock screen,
/// ringtone, Answer and Not now. Used from the background isolate too.
Future<void> showNativeCall(Map<String, dynamic> d) async {
  final id = d['occurrence_id'] as String? ?? '';
  if (id.isEmpty) return;
  await FlutterCallkitIncoming.showCallkitIncoming(CallKitParams(
    id: id,
    nameCaller: 'Mapa',
    appName: 'Mapa',
    handle: 'Time for your ${d['medicine'] ?? 'medicine'}',
    type: 0, // audio
    duration: 45000, // rings as long as the server keeps trying
    extra: {for (final k in const ['occurrence_id', 'name', 'medicine', 'caretaker', 'language']) k: d[k]},
    missedCallNotification: const NotificationParams(
      showNotification: true,
      isShowCallback: false,
      subtitle: 'Missed call from Mapa',
    ),
    android: const AndroidParams(
      isCustomNotification: true,
      isShowLogo: false,
      ringtonePath: 'system_ringtone_default',
      backgroundColor: '#2D2A3E',
      actionColor: '#33C58A',
      textColor: '#FFFFFF',
      incomingCallNotificationChannelName: 'Mapa calls',
      missedCallNotificationChannelName: 'Missed Mapa calls',
      isShowFullLockedScreen: true,
      textAccept: 'Answer',
      textDecline: 'Not now',
    ),
  ));
}

/// Runs in its own isolate when the app is in the background or closed.
@pragma('vm:entry-point')
Future<void> mapaBackgroundMessage(RemoteMessage m) async {
  if (!Config.pushIsSet) return;
  try {
    await Firebase.initializeApp(options: _options);
  } catch (_) {} // already initialised in this isolate
  switch (m.data['type']) {
    case 'incoming_call':
      await showNativeCall(m.data);
    case 'call_cancelled':
      await FlutterCallkitIncoming.endAllCalls();
  }
}

class PushService {
  static bool enabled = false;
  static final _handled = <String>{};

  /// Android only. Does nothing (and the app works as before) until Firebase is configured.
  static Future<void> init() async {
    if (kIsWeb || !Platform.isAndroid || !Config.pushIsSet) return;
    try {
      await Firebase.initializeApp(options: _options);
    } catch (_) {
      return;
    }
    enabled = true;
    FirebaseMessaging.onBackgroundMessage(mapaBackgroundMessage);

    // App open: the in-app ring (realtime) already shows the call, so only tidy up.
    FirebaseMessaging.onMessage.listen((m) {
      if (m.data['type'] == 'call_cancelled') FlutterCallkitIncoming.endAllCalls();
      // The push beats the realtime socket: load now so the in-app ring starts without waiting for it.
      if (m.data['type'] == 'incoming_call') repo.refresh();
    });
    // getToken/onTokenRefresh are marked deprecated in favour of a newer Installation-ID flow;
    // the classic registration token is what FCM's HTTP v1 `token` field expects.
    // ignore: deprecated_member_use
    FirebaseMessaging.instance.onTokenRefresh.listen(_send);
    FlutterCallkitIncoming.onEvent.listen(_onCallEvent);

    await registerToken();
    await _resumeAcceptedCall();
  }

  /// Tell the server which phone to wake for this person. Safe to call often.
  static Future<void> registerToken() async {
    if (!enabled || !repo.signedIn || repo.role != 'recipient') return;
    try {
      // ignore: deprecated_member_use
      final t = await FirebaseMessaging.instance.getToken();
      if (t != null) await _send(t);
    } catch (_) {}
  }

  static Future<void> _send(String token) async {
    if (repo.role != 'recipient') return;
    try {
      await repo.api.putPushToken(token);
    } catch (_) {}
  }

  static void _onCallEvent(CallEvent? e) {
    switch (e) {
      case CallEventActionCallAccept(:final callKitParams):
        _accept(callKitParams.id, _extra(callKitParams));
      case CallEventActionCallDecline(:final callKitParams):
        callController.decline(_occurrenceId(callKitParams));
      default:
        break;
    }
  }

  static Map<String, dynamic> _extra(CallKitParams p) => (p.extra ?? const {}).cast<String, dynamic>();
  static String _occurrenceId(CallKitParams p) => (_extra(p)['occurrence_id'] as String?) ?? p.id;

  /// The app was closed when they answered: the answer event came before we could listen.
  static Future<void> _resumeAcceptedCall() async {
    try {
      for (final c in await FlutterCallkitIncoming.activeCalls()) {
        if (c.isAccepted) _accept(_occurrenceId(c), _extra(c));
      }
    } catch (_) {}
  }

  static Future<void> _accept(String id, Map<String, dynamic> extra) async {
    if (!_handled.add(id) || callController.active) return;
    try {
      await callController.answer(id, name: extra['name'] as String?, caretaker: extra['caretaker'] as String?);
      router.go('/call/live');
    } catch (_) {
      router.go('/idle');
    }
  }

  /// Is a native call screen already showing for this call?
  static Future<bool> showingNative(String id) async {
    if (!enabled) return false;
    try {
      return (await FlutterCallkitIncoming.activeCalls()).any((c) => c.id == id);
    } catch (_) {
      return false;
    }
  }
}
