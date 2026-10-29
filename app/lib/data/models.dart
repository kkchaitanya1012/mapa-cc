import '../theme/tokens.dart';

DateTime _local(String iso) => DateTime.parse(iso).toLocal();

class Link {
  Link({required this.id, required this.caretakerId, required this.recipientId, required this.nickname,
      required this.tone, required this.createdAt, this.language = 'en', this.caretakerName = ''});

  final String id, caretakerId, recipientId, nickname, language, caretakerName;
  final Tone tone;
  final DateTime createdAt;

  String get initial => nickname.isEmpty ? '?' : String.fromCharCode(nickname.runes.first).toUpperCase();

  factory Link.fromRow(Map<String, dynamic> r) => Link(
        id: r['id'],
        caretakerId: r['caretaker_id'],
        recipientId: r['recipient_id'],
        nickname: r['nickname'],
        tone: Tone.values.byName(r['tone']),
        createdAt: _local(r['created_at']),
        language: (r['recipient'] as Map?)?['language'] ?? 'en',
        caretakerName: ((r['caretaker'] as Map?)?['display_name'] ?? '') as String,
      );
}

class Reminder {
  Reminder({required this.id, required this.linkId, required this.medicine, this.dose, required this.hour,
      required this.minute, required this.daysMask, required this.start, this.end});

  final String id, linkId, medicine;
  final String? dose;
  final int hour, minute, daysMask;
  final DateTime start;
  final DateTime? end;

  factory Reminder.fromRow(Map<String, dynamic> r) {
    final t = (r['time_of_day'] as String).split(':');
    return Reminder(
      id: r['id'], linkId: r['link_id'], medicine: r['medicine'], dose: r['dose'],
      hour: int.parse(t[0]), minute: int.parse(t[1]), daysMask: r['days_mask'],
      start: DateTime.parse(r['start_date']),
      end: r['end_date'] == null ? null : DateTime.parse(r['end_date']),
    );
  }
}

class Occurrence {
  Occurrence({required this.id, required this.reminderId, required this.at, required this.status, required this.attempt, this.startedAt, this.calledEarlyFor});

  final String id, reminderId, status;
  final DateTime at; // device-local
  final DateTime? startedAt; // when it began ringing
  final DateTime? calledEarlyFor; // set when Call now moved this call here from that scheduled time
  final int attempt;

  bool get open => status == 'pending' || status == 'ringing' || status == 'in_call';

  factory Occurrence.fromRow(Map<String, dynamic> r) => Occurrence(
        id: r['id'], reminderId: r['reminder_id'], at: _local(r['scheduled_at']),
        status: r['status'], attempt: r['attempt'],
        startedAt: r['started_at'] == null ? null : _local(r['started_at']),
        calledEarlyFor: r['called_early_for'] == null ? null : _local(r['called_early_for']),
      );
}

class CallResult {
  CallResult({required this.occurrenceId, required this.medicineStatus, this.wellbeing, this.note});
  final String occurrenceId, medicineStatus;
  final String? wellbeing, note;

  factory CallResult.fromRow(Map<String, dynamic> r) => CallResult(
        occurrenceId: r['occurrence_id'], medicineStatus: r['medicine_status'],
        wellbeing: r['wellbeing'], note: r['note'],
      );
}

class AlertItem {
  AlertItem({required this.id, required this.linkId, required this.kind, required this.message,
      required this.createdAt, this.seenAt});
  final String id, linkId, kind, message;
  final DateTime createdAt;
  final DateTime? seenAt;

  bool get unseen => seenAt == null;

  factory AlertItem.fromRow(Map<String, dynamic> r) => AlertItem(
        id: r['id'], linkId: r['link_id'], kind: r['kind'], message: r['message'],
        createdAt: _local(r['created_at']),
        seenAt: r['seen_at'] == null ? null : _local(r['seen_at']),
      );
}

/// What the chat assistant sent back.
class ChatReply {
  ChatReply({required this.type, this.question, this.field, this.options = const [], this.draft});
  final String type; // create | clarify | reject
  final String? question, field;
  final List<String> options;
  final Map<String, dynamic>? draft;

  factory ChatReply.fromJson(Map<String, dynamic> j) {
    final c = j['clarify'] as Map<String, dynamic>?;
    return ChatReply(
      type: j['type'],
      question: c?['question'],
      field: c?['field'],
      options: [for (final o in (c?['options'] as List? ?? [])) o as String],
      draft: j['draft'] as Map<String, dynamic>?,
    );
  }
}
