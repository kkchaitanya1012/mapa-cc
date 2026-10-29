// Drives the real app against the real backend, like a person would.
// Needs the API running on API_BASE_URL and config via --dart-define-from-file.
//
//   flutter test integration_test/flow_test.dart -d <simulator> --dart-define-from-file=config.local.json
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:integration_test/integration_test.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:mapa/config.dart';
import 'package:mapa/data/repo.dart';
import 'package:mapa/main.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'helpers.dart';

Future<void> say(WidgetTester t, String text) async {
  await t.tap(find.byType(TextField)); // focus it, as a person would
  await t.pump(const Duration(milliseconds: 300));
  await t.enterText(find.byType(TextField), text);
  await t.pump(const Duration(milliseconds: 300));
  await t.tap(find.byIcon(LucideIcons.send));
  await t.pump(const Duration(milliseconds: 300));
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('caretaker pairs a parent, chats a reminder, and sees it on Today', (t) async {
    await repo.init();
    await repo.signOutAndReset();
    await t.pumpWidget(const MapaApp());

    // First run: landing -> onboarding (skip) -> role
    await tap(t, find.text('Get started'));
    await tap(t, find.text('Skip'));
    await tap(t, find.text('I look after someone'));

    // Pairing: name the person, get a code
    await until(t, find.text('Create code'));
    await t.enterText(find.byType(TextField).first, 'Amma');
    await t.enterText(find.byType(TextField).last, 'Priya');
    await t.pump(const Duration(milliseconds: 300));
    await tap(t, find.text('Create code'));
    final codeFinder = find.byWidgetPredicate((w) => w is Text && RegExp(r'^\d{3} \d{3}$').hasMatch(w.data ?? ''));
    await until(t, codeFinder, why: 'the pairing code');
    final code = (t.widget(codeFinder.first) as Text).data!.replaceAll(' ', '');
    expect(code, matches(RegExp(r'^\d{6}$')));

    // The parent's phone: a second, independent sign-in redeems the code.
    final other = SupabaseClient(Config.supabaseUrl, Config.supabaseAnonKey);
    await other.auth.signInAnonymously();
    final h = {'content-type': 'application/json', 'authorization': 'Bearer ${other.auth.currentSession!.accessToken}'};
    var r = await http.put(Uri.parse('${Config.apiBaseUrl}/me/profile'), headers: h, body: jsonEncode({'role': 'recipient', 'display_name': ''}));
    expect(r.statusCode, 200);
    r = await http.post(Uri.parse('${Config.apiBaseUrl}/pairing/redeem'), headers: h, body: jsonEncode({'code': code}));
    expect(r.statusCode, 200, reason: r.body);

    // The caretaker's screen moves on by itself (realtime).
    await until(t, find.text('Amma is paired.'), seconds: 25);

    // Chat: off-topic is refused with the fixed line; a real reminder asks one question.
    await tap(t, find.text('Add a reminder'));
    await until(t, find.text('Tell me the medicine, time and days.'));
    await say(t, 'tell me a joke');
    await until(t, find.textContaining('I can only set medicine reminders'));

    // The kind of message that used to fail: a typo'd drug name and a dotted time.
    await say(t, 'Pegbalin tablet at 10.50 pm for 7 days');
    await until(t, find.text('Got it. Does this look right?'), seconds: 40, why: 'the confirmation card');
    expect(find.textContaining('Pegbalin'), findsWidgets);
    expect(find.text('10:50 pm'), findsOneWidget);   // not 10:00, not 10:50 am
    await tap(t, find.text('Looks right'));

    // Back on Today: the next call is scheduled.
    await until(t, find.text('Call log'), seconds: 20, why: 'Today with a reminder');
    await until(t, find.text('Mapa calls Amma'));
    expect(repo.reminders.length, 1);
    expect(repo.occurrences, isNotEmpty);

    await other.auth.signOut();
  });
}
