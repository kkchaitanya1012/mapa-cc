// The parent's phone: pair with the keypad, then Mapa "rings" and the incoming
// call opens by itself. Needs the API and the scheduler running (LiveKit may be
// unconfigured: this checks the ringing and declining, not the audio).
//
//   flutter test integration_test/call_ring_test.dart -d <simulator> --dart-define-from-file=config.local.json
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:integration_test/integration_test.dart';
import 'package:mapa/config.dart';
import 'package:mapa/data/repo.dart';
import 'package:mapa/main.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'helpers.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('a ringing call opens on the parent phone by itself, and Not now declines it', (t) async {
    await repo.init();
    await repo.signOutAndReset();

    // The caretaker's side, as a second independent sign-in.
    final other = SupabaseClient(Config.supabaseUrl, Config.supabaseAnonKey);
    await other.auth.signInAnonymously();
    Map<String, String> h() => {'content-type': 'application/json', 'authorization': 'Bearer ${other.auth.currentSession!.accessToken}'};
    Future<http.Response> post(String path, Map body) => http.post(Uri.parse('${Config.apiBaseUrl}$path'), headers: h(), body: jsonEncode(body));
    expect((await http.put(Uri.parse('${Config.apiBaseUrl}/me/profile'), headers: h(),
        body: jsonEncode({'role': 'caretaker', 'display_name': 'Priya'}))).statusCode, 200);
    final code = jsonDecode((await post('/pairing/codes', {'recipient_label': 'Amma'})).body)['code'] as String;

    // The parent's phone: first run, keypad, connect.
    await t.pumpWidget(const MapaApp());
    await tap(t, find.text('Get started'));
    await tap(t, find.text('Skip'));
    await tap(t, find.text('Someone looks after me'));
    await until(t, find.text('Connect'));
    for (final d in code.split('')) {
      await t.tap(find.descendant(of: find.byType(GridView), matching: find.text(d)));
      await t.pump(const Duration(milliseconds: 120));
    }
    await tap(t, find.text('Connect'));
    await until(t, find.textContaining('set this up for you'), why: 'the waiting screen');
    expect(find.text('Priya set this up for you'), findsOneWidget);

    // The caretaker adds a reminder and asks Mapa to call now.
    final link = (await other.from('care_links').select('id').single())['id'];
    final today = DateTime.now();
    final draft = {
      'medicine': 'BP tablet', 'times': ['09:00:00'], 'days_mask': 127,
      'start_date': '${today.year.toString().padLeft(4, '0')}-${today.month.toString().padLeft(2, '0')}-${today.day.toString().padLeft(2, '0')}',
    };
    expect((await post('/reminders', {'link_id': link, 'draft': draft})).statusCode, 201);
    final occ = (await other.from('call_occurrences').select('id').order('scheduled_at').limit(1)).first['id'];
    expect((await post('/calls/$occ/call-now', {})).statusCode, 202);

    // The scheduler rings; the parent's screen opens by itself.
    await until(t, find.text('Mapa is calling'), seconds: 60, why: 'the incoming call');
    expect(find.textContaining('BP tablet'), findsWidgets);
    await tap(t, find.text('Not now'));
    await until(t, find.textContaining('Mapa will call you'), seconds: 20, why: 'back to waiting');

    // Declining counted as unanswered and a retry is queued.
    await t.pump(const Duration(seconds: 2));
    final rows = await other.from('call_occurrences').select('status, attempt').order('scheduled_at');
    expect(rows.any((r) => r['status'] == 'no_answer' && r['attempt'] == 1), isTrue, reason: '$rows');
    expect(rows.any((r) => r['status'] == 'pending' && r['attempt'] == 2), isTrue, reason: '$rows');

    await other.auth.signOut();
  });
}
