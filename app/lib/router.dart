import 'dart:io' show Directory, File;

import 'package:flutter/foundation.dart' show kDebugMode;
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import 'screens/allow_calls.dart';
import 'screens/call_screens.dart';
import 'screens/chat.dart';
import 'screens/demo_menu.dart';
import 'screens/enter_code.dart';
import 'screens/idle.dart';
import 'screens/landing.dart';
import 'screens/onboarding.dart';
import 'screens/pairing.dart';
import 'screens/person.dart';
import 'screens/role_select.dart';
import 'screens/shell.dart';
import 'data/repo.dart';

/// Debug builds only: a file named `mapa_route` in the app's temp folder sets
/// the first screen, so each screen can be opened and screenshotted directly.
String? _debugStartRoute() {
  if (!kDebugMode) return null;
  try {
    final f = File('${Directory.systemTemp.path}/mapa_route');
    return f.existsSync() ? f.readAsStringSync().trim() : null;
  } catch (_) {
    return null;
  }
}

Page<void> _fade(GoRouterState s, Widget child) => CustomTransitionPage<void>(
      key: s.pageKey,
      child: child,
      transitionDuration: const Duration(milliseconds: 360),
      reverseTransitionDuration: const Duration(milliseconds: 260),
      transitionsBuilder: (_, a, _, c) =>
          FadeTransition(opacity: CurvedAnimation(parent: a, curve: Curves.easeOutCubic), child: c),
    );

final router = GoRouter(
  initialLocation: _debugStartRoute() ?? '/',
  routes: [
    GoRoute(path: '/', pageBuilder: (c, s) => _fade(s, const LandingScreen())),
    GoRoute(path: '/onboarding', builder: (c, s) => const OnboardingScreen()),
    GoRoute(path: '/role', builder: (c, s) => const RoleSelectScreen()),
    GoRoute(path: '/pair', builder: (c, s) => const PairingScreen()),
    GoRoute(path: '/home', pageBuilder: (c, s) => _fade(s, const CaretakerShell())),
    GoRoute(path: '/chat', builder: (c, s) => ChatScreen(linkId: s.uri.queryParameters['link'] ?? '')),
    GoRoute(
      path: '/person/:id',
      builder: (c, s) => PersonScreen(linkId: s.pathParameters['id']!),
    ),
    GoRoute(path: '/alerts', builder: (c, s) => const CaretakerShell(initialTab: 2)),
    GoRoute(path: '/join', builder: (c, s) => const EnterCodeScreen()),
    GoRoute(path: '/allow-calls', builder: (c, s) => const AllowCallsScreen()),
    GoRoute(path: '/idle', pageBuilder: (c, s) => _fade(s, const IdleScreen())),
    GoRoute(path: '/call/incoming', pageBuilder: (c, s) => _fade(s, IncomingCallScreen(occurrenceId: s.uri.queryParameters['o']))),
    GoRoute(path: '/call/live', pageBuilder: (c, s) => _fade(s, const InCallScreen())),
    GoRoute(path: '/call/done', pageBuilder: (c, s) => _fade(s, const CallDoneScreen())),
    GoRoute(path: '/demo', builder: (c, s) => const DemoMenu()),
  ],
  // Returning people skip the welcome screens and land where they left off. This runs once at
  // start (the repo has loaded by then); do not make it listen to the repo, or every realtime
  // update re-runs routing and can rebuild screens the person is in the middle of using.
  redirect: (context, state) {
    if (state.uri.path != '/' || !repo.signedIn || repo.role == null) return null;
    if (repo.role == 'caretaker') return '/home';
    return repo.links.isEmpty ? '/join' : '/idle';
  },
);
