import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_callkit_incoming/flutter_callkit_incoming.dart';
import 'package:livekit_client/livekit_client.dart';

import 'repo.dart';

enum CallPhase { idle, joining, live, ended }

/// The parent's side of one call: joins Mapa's room, listens, shows captions.
/// Mapa (the voice agent) does the talking; this just carries the audio.
class CallController extends ChangeNotifier {
  CallPhase phase = CallPhase.idle;
  String? error;

  // For the "thank you" screen, after the room is gone.
  String name = '';
  String caretaker = '';

  String mapaLine = '';
  String youLine = '';
  bool mapaSpeaking = false;
  int seconds = 0;

  Room? _room;
  EventsListener<RoomEvent>? _events;
  Timer? _clock;

  bool get active => phase == CallPhase.joining || phase == CallPhase.live;

  /// [name] and [caretaker] let a call answered from the lock screen show the right
  /// words before the app has finished loading its data.
  Future<bool> answer(String occurrenceId, {String? name, String? caretaker}) async {
    if (active) return false;
    final occ = repo.occurrences.where((o) => o.id == occurrenceId).firstOrNull;
    final link = occ == null ? null : repo.linkOf(occ);
    this.name = link?.nickname ?? name ?? 'there';
    this.caretaker = link?.caretakerName ?? caretaker ?? '';
    _reset();
    phase = CallPhase.joining;
    notifyListeners();
    try {
      final j = await repo.api.joinCall(occurrenceId);
      final room = Room(roomOptions: const RoomOptions(adaptiveStream: false, dynacast: false));
      _room = room;
      _events = room.createListener()
        ..on<RoomDisconnectedEvent>((_) => _finish())
        ..on<ActiveSpeakersChangedEvent>((_) => _updateSpeaking())
        ..on<ParticipantConnectedEvent>((_) => _updateSpeaking());
      room.registerTextStreamHandler('lk.transcription', _onCaption);
      await room.connect(j.url, j.token);
      await room.localParticipant?.setMicrophoneEnabled(true);
      // A parent should hear Mapa without holding the phone to an ear: speaker by default.
      await setSpeaker(true);
      phase = CallPhase.live;
      _clock = Timer.periodic(const Duration(seconds: 1), (_) {
        seconds++;
        notifyListeners();
      });
      notifyListeners();
      return true;
    } catch (e) {
      error = e.toString();
      await _teardown();
      phase = CallPhase.idle;
      notifyListeners();
      rethrow;
    }
  }

  bool speakerOn = true;

  Future<void> setSpeaker(bool on) async {
    speakerOn = on;
    try {
      await AudioManager.instance.setSpeakerOutputPreferred(on);
    } catch (_) {}
    notifyListeners();
  }

  Future<void> decline(String occurrenceId) async {
    try {
      await repo.api.declineCall(occurrenceId);
    } catch (_) {}
    await repo.refresh();
  }

  Future<void> hangUp() async {
    await _teardown();
    _finish();
  }

  void _finish() {
    if (phase == CallPhase.ended || phase == CallPhase.idle) return;
    FlutterCallkitIncoming.endAllCalls(); // clear the native call notification
    _clock?.cancel();
    phase = CallPhase.ended;
    notifyListeners();
    _teardown();
    repo.refresh();
  }

  void acknowledgeEnd() {
    phase = CallPhase.idle;
    notifyListeners();
  }

  void _onCaption(TextStreamReader reader, String identity) {
    final room = _room;
    final fromMapa = room?.remoteParticipants[identity]?.kind == ParticipantKind.AGENT;
    var text = '';
    reader.listen((chunk) {
      text += utf8.decode(chunk.content);
      if (fromMapa) {
        mapaLine = text;
      } else {
        youLine = text;
      }
      notifyListeners();
    });
  }

  void _updateSpeaking() {
    final agents = _room?.remoteParticipants.values.where((p) => p.kind == ParticipantKind.AGENT) ?? const [];
    final speaking = agents.any((p) => p.isSpeaking);
    if (speaking != mapaSpeaking) {
      mapaSpeaking = speaking;
      notifyListeners();
    }
  }

  void _reset() {
    error = null;
    mapaLine = '';
    youLine = '';
    mapaSpeaking = false;
    seconds = 0;
  }

  Future<void> _teardown() async {
    _clock?.cancel();
    final room = _room;
    final events = _events;
    _room = null;
    _events = null;
    try {
      room?.unregisterTextStreamHandler('lk.transcription');
      await events?.dispose();
      await room?.disconnect();
      await room?.dispose();
    } catch (_) {}
  }
}

final callController = CallController();
