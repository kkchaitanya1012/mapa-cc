import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart' show AppLifecycleState, WidgetsBinding, WidgetsBindingObserver;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../config.dart';
import '../widgets/common.dart' show Status;
import 'api.dart';
import 'models.dart';

/// The app's single source of truth. Reads go to Supabase under row-level
/// security; writes that need rules go through the Python API. Realtime keeps
/// it fresh, so the caretaker sees a call finish without refreshing.
class Repo extends ChangeNotifier with WidgetsBindingObserver {
  final api = ApiClient();
  SupabaseClient get _db => Supabase.instance.client;

  bool ready = false;
  bool onboardingSeen = false;
  String? role; // 'caretaker' | 'recipient' | null until chosen
  String? loadError;

  List<Link> links = [];
  List<Reminder> reminders = [];
  List<Occurrence> occurrences = [];
  Map<String, CallResult> results = {};
  List<AlertItem> alerts = [];

  RealtimeChannel? _channel;
  Timer? _debounce;
  Timer? _poll;
  bool _refreshing = false;

  bool get signedIn => Config.isSet && ready && _db.auth.currentSession != null;

  // ------------------------------------------------------------ start up

  Future<void> init() async {
    try {
      final p = await SharedPreferences.getInstance();
      onboardingSeen = p.getBool('onboardingSeen') ?? false;
    } catch (_) {}
    if (Config.isSet) {
      await Supabase.initialize(url: Config.supabaseUrl, publishableKey: Config.supabaseAnonKey);
      if (_db.auth.currentSession != null) {
        await _loadRole();
        await refresh();
        _subscribe();
      }
    }
    WidgetsBinding.instance.addObserver(this);
    _startPolling();
    ready = true;
    notifyListeners();
  }

  /// Coming back to the app: the realtime socket may have died while it slept, so reload
  /// everything and rebuild the socket rather than trusting it.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      // After a lock/unlock the surface can come back blank until something repaints it.
      WidgetsBinding.instance.scheduleForcedFrame();
      _resubscribe();
      refresh();
      _startPolling();
    } else if (state == AppLifecycleState.paused) {
      _poll?.cancel();
    }
  }

  /// Safety net under realtime: a quiet reload every 20 s while the app is open.
  void _startPolling() {
    _poll?.cancel();
    _poll = Timer.periodic(const Duration(seconds: 20), (_) => refresh());
  }

  Future<void> _resubscribe() async {
    final ch = _channel;
    _channel = null;
    try {
      if (ch != null) await _db.removeChannel(ch);
    } catch (_) {}
    if (role != null && _db.auth.currentSession != null) _subscribe();
  }

  Future<void> _loadRole() async {
    try {
      final uid = _db.auth.currentUser!.id;
      final row = await _db.from('profiles').select('role').eq('id', uid).maybeSingle();
      role = row?['role'] as String?;
    } catch (_) {
      role = null;
    }
  }

  Future<void> markOnboardingSeen() async {
    onboardingSeen = true;
    try {
      (await SharedPreferences.getInstance()).setBool('onboardingSeen', true);
    } catch (_) {}
    notifyListeners();
  }

  /// First real step: sign in (anonymously, no sign-up form) and record the role.
  Future<void> chooseRole(String newRole, {String displayName = ''}) async {
    if (_db.auth.currentSession == null) await _db.auth.signInAnonymously();
    await api.putProfile(role: newRole, displayName: displayName);
    role = newRole;
    await refresh();
    _subscribe();
    notifyListeners();
  }

  Future<void> signOutAndReset() async {
    _debounce?.cancel();
    _poll?.cancel();
    final ch = _channel;
    _channel = null;
    if (ch != null) await _db.removeChannel(ch);
    try {
      await _db.auth.signOut();
      (await SharedPreferences.getInstance()).clear();
    } catch (_) {}
    role = null;
    onboardingSeen = false;
    links = [];
    reminders = [];
    occurrences = [];
    results = {};
    alerts = [];
    notifyListeners();
  }

  // ------------------------------------------------------------ loading

  Future<void> refresh() async {
    if (role == null || _db.auth.currentSession == null) return;
    if (_refreshing) {
      _again = true; // something changed mid-load: go round once more so it isn't missed
      return;
    }
    _refreshing = true;
    try {
      do {
        _again = false;
        await _load();
      } while (_again);
    } finally {
      _refreshing = false;
    }
  }

  bool _again = false;

  Future<void> _load() async {
    final since = DateTime.now().subtract(const Duration(days: 60)).toUtc().toIso8601String();
    final until = DateTime.now().add(const Duration(days: 3)).toUtc().toIso8601String();
    try {
      final r = await Future.wait([
        _db.from('care_links')
            .select('*, recipient:profiles!recipient_id(display_name,language), caretaker:profiles!caretaker_id(display_name)')
            .order('created_at'),
        _db.from('reminders').select().eq('active', true),
        _db.from('call_occurrences').select().gte('scheduled_at', since).lte('scheduled_at', until).order('scheduled_at'),
        _db.from('call_results').select().gte('created_at', since),
        role == 'caretaker'
            ? _db.from('alerts').select().order('created_at', ascending: false).limit(50)
            : Future.value(<Map<String, dynamic>>[]),
      ]);
      links = [for (final x in r[0]) Link.fromRow(x)];
      reminders = [for (final x in r[1]) Reminder.fromRow(x)];
      occurrences = [for (final x in r[2]) Occurrence.fromRow(x)];
      results = {for (final x in r[3]) x['occurrence_id'] as String: CallResult.fromRow(x)};
      alerts = [for (final x in r[4]) AlertItem.fromRow(x)];
      loadError = null;
    } catch (e) {
      loadError = "Couldn't load your latest data.";
    }
    notifyListeners();
  }

  void _subscribe() {
    if (_channel != null) return;
    var ch = _db.channel('mapa-live');
    for (final t in const ['care_links', 'reminders', 'call_occurrences', 'call_results', 'alerts']) {
      ch = ch.onPostgresChanges(
        event: PostgresChangeEvent.all,
        schema: 'public',
        table: t,
        callback: (_) {
          _debounce?.cancel();
          _debounce = Timer(const Duration(milliseconds: 400), refresh);
        },
      );
    }
    _channel = ch.subscribe((status, _) {
      // A dropped or failed socket would leave this phone quietly out of date: reconnect and reload.
      if (status == RealtimeSubscribeStatus.channelError || status == RealtimeSubscribeStatus.timedOut) {
        Timer(const Duration(seconds: 3), () {
          _resubscribe();
          refresh();
        });
      }
    });
  }

  // ------------------------------------------------------------ actions

  Future<({String code, String qrPayload, DateTime expiresAt})> createCode(String label, {String myName = ''}) async {
    if (myName.trim().isNotEmpty) {
      await api.putProfile(role: 'caretaker', displayName: myName.trim());
    }
    return api.createCode(label.trim());
  }

  Future<void> redeem(String code) async {
    await api.redeem(code);
    await refresh();
  }

  Future<void> addReminder(String linkId, Map<String, dynamic> draft) async {
    await api.createReminders(linkId, draft);
    await refresh();
  }

  Future<void> deleteReminder(String id) async {
    await api.deleteReminder(id);
    await refresh();
  }

  Future<void> markSeen(String alertId) async {
    await _db.from('alerts').update({'seen_at': DateTime.now().toUtc().toIso8601String()}).eq('id', alertId);
    await refresh();
  }

  Future<void> unpair(String linkId) async {
    await _db.from('care_links').delete().eq('id', linkId);
    await refresh();
  }

  // ------------------------------------------------------------ derived

  Link? linkById(String id) => links.where((l) => l.id == id).firstOrNull;
  Reminder? reminderById(String id) => reminders.where((r) => r.id == id).firstOrNull;
  Link? linkOf(Occurrence o) {
    final r = reminderById(o.reminderId);
    return r == null ? null : linkById(r.linkId);
  }

  /// When Call now already rang for this scheduled slot (null if it hasn't). The caretaker's
  /// button stays off for it: Mapa still calls at the scheduled time, as normal.
  DateTime? calledEarlyAt(Occurrence o) {
    for (final x in occurrences) {
      if (x.reminderId == o.reminderId && x.calledEarlyFor != null && x.calledEarlyFor!.isAtSameMomentAs(o.at)) return x.at;
    }
    return null;
  }

  bool get hasReminders => reminders.isNotEmpty;
  int get unseenAlerts => alerts.where((a) => a.unseen).length;

  static bool _sameDay(DateTime a, DateTime b) => a.year == b.year && a.month == b.month && a.day == b.day;

  List<Occurrence> get today {
    final now = DateTime.now();
    return [for (final o in occurrences) if (_sameDay(o.at, now) && reminderById(o.reminderId) != null) o];
  }

  /// The soonest call still to come (or happening), ignoring ones long past.
  Occurrence? get nextCall {
    final cutoff = DateTime.now().subtract(const Duration(minutes: 15));
    for (final o in occurrences) {
      if (o.open && o.at.isAfter(cutoff) && reminderById(o.reminderId) != null) return o;
    }
    return null;
  }

  /// A call happening now, for the caretaker's frosted sheet: ringing or in progress.
  Occurrence? get liveCall =>
      occurrences.where((o) => o.status == 'in_call').firstOrNull ??
      occurrences.where((o) => o.status == 'ringing').firstOrNull;

  /// For the parent's phone: a call that is ringing right now.
  Occurrence? get ringingForMe {
    if (role != 'recipient') return null;
    final cutoff = DateTime.now().subtract(const Duration(seconds: 70));
    return occurrences.where((o) => o.status == 'ringing' && o.startedAt != null && o.startedAt!.isAfter(cutoff)).firstOrNull;
  }

  List<Reminder> remindersFor(String linkId) => [for (final r in reminders) if (r.linkId == linkId) r];

  /// Past calls for a person, newest first.
  List<Occurrence> historyFor(String linkId, {int limit = 5}) {
    final now = DateTime.now();
    final list = [
      for (final o in occurrences)
        if (!o.open && o.at.isBefore(now) && reminderById(o.reminderId)?.linkId == linkId) o
    ]..sort((a, b) => b.at.compareTo(a.at));
    return list.take(limit).toList();
  }

  ({Status status, String label}) rowStatus(Occurrence o, {required bool isNext}) {
    final res = results[o.id];
    switch (o.status) {
      case 'completed':
        return switch (res?.medicineStatus) {
          'taken' => (status: Status.taken, label: 'Taken'),
          'not_taken' => (status: Status.missed, label: 'Not taken'),
          'will_take_later' => (status: Status.later, label: 'Later'),
          _ => (status: Status.later, label: 'Unclear'),
        };
      case 'no_answer':
        return (status: Status.missed, label: 'No answer');
      case 'failed':
        return (status: Status.missed, label: 'Missed');
      case 'in_call':
        return (status: Status.next, label: 'On a call');
      case 'ringing':
        return (status: Status.next, label: 'Calling');
      default:
        return isNext ? (status: Status.next, label: 'Up next') : (status: Status.later, label: 'Later');
    }
  }

  /// Whole days in a row where every call was taken. Days with no calls are
  /// neutral; a day still in progress doesn't break the run.
  int streakFor(String linkId) {
    final mine = {for (final r in reminders) if (r.linkId == linkId) r.id};
    final groups = <String, List<Occurrence>>{}; // reminder + day
    for (final o in occurrences) {
      if (!mine.contains(o.reminderId)) continue;
      groups.putIfAbsent('${o.reminderId}|${o.at.year}-${o.at.month}-${o.at.day}', () => []).add(o);
    }
    final now = DateTime.now();
    var streak = 0;
    for (var back = 0; back <= 60; back++) {
      final d = DateTime(now.year, now.month, now.day).subtract(Duration(days: back));
      final day = [for (final e in groups.entries) if (_sameDay(e.value.first.at, d)) e.value];
      if (day.isEmpty) continue;
      var broken = false, pending = false;
      for (final g in day) {
        final taken = g.any((o) => results[o.id]?.medicineStatus == 'taken');
        if (taken) continue;
        if (g.any((o) => o.open)) {
          pending = true;
        } else {
          broken = true;
        }
      }
      if (broken) break;
      if (!pending) streak++;
    }
    return streak;
  }

  /// Which of the last seven days (oldest first) were fully taken, missed, or had no calls.
  List<({DateTime day, String state})> weekFor(String linkId) {
    final mine = {for (final r in reminders) if (r.linkId == linkId) r.id};
    final now = DateTime.now();
    return [
      for (var back = 6; back >= 0; back--)
        () {
          final d = DateTime(now.year, now.month, now.day).subtract(Duration(days: back));
          final os = [for (final o in occurrences) if (mine.contains(o.reminderId) && _sameDay(o.at, d)) o];
          if (os.isEmpty) return (day: d, state: back == 0 ? 'today' : 'none');
          if (os.any((o) => o.open)) return (day: d, state: back == 0 ? 'today' : 'none');
          final byRem = <String, bool>{};
          for (final o in os) {
            byRem[o.reminderId] = (byRem[o.reminderId] ?? false) || results[o.id]?.medicineStatus == 'taken';
          }
          return (day: d, state: byRem.values.every((v) => v) ? 'done' : 'missed');
        }()
    ];
  }
}

final repo = Repo();
