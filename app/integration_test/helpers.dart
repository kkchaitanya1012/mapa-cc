import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Future<void> until(WidgetTester t, Finder f, {int seconds = 20, String? why}) async {
  final end = DateTime.now().add(Duration(seconds: seconds));
  while (DateTime.now().isBefore(end)) {
    await t.pump(const Duration(milliseconds: 250));
    if (f.evaluate().isNotEmpty) return;
  }
  final seen = find.byType(Text).evaluate().map((e) => (e.widget as Text).data).whereType<String>().toList();
  throw TestFailure('Timed out waiting for ${why ?? f.describeMatch(Plurality.one)}. On screen: ${seen.join(" | ")}');
}

Future<void> tap(WidgetTester t, Finder f) async {
  await until(t, f);
  await t.tap(f.first);
  await t.pump(const Duration(milliseconds: 400));
}
