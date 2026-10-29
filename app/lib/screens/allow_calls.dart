import 'package:flutter/material.dart';
import 'package:flutter_callkit_incoming/flutter_callkit_incoming.dart';
import 'package:go_router/go_router.dart';
import 'package:livekit_client/livekit_client.dart';

import '../data/repo.dart';
import '../push/push_service.dart';
import '../theme/theme.dart';
import '../theme/tokens.dart';
import '../widgets/buddy.dart';
import '../widgets/common.dart';

/// Parent, right after pairing: Android only rings over a locked screen if it
/// has been allowed to. Three taps' worth of permissions, explained once, kindly.
class AllowCallsScreen extends StatefulWidget {
  const AllowCallsScreen({super.key});
  @override
  State<AllowCallsScreen> createState() => _AllowCallsScreenState();
}

class _AllowCallsScreenState extends State<AllowCallsScreen> {
  bool _busy = false;

  Future<void> _allow() async {
    setState(() => _busy = true);
    try {
      await FlutterCallkitIncoming.requestNotificationPermission({
        'title': 'Let Mapa ring you',
        'rationaleMessagePermission': 'Mapa needs to show a notification to ring your phone like a normal call.',
        'postNotificationMessageRequired': 'Please allow notifications for Mapa in Settings so it can ring you.',
      });
      await FlutterCallkitIncoming.requestFullIntentPermission();
      // Ask for the microphone now, so answering later is just one slide.
      final mic = await LocalAudioTrack.create();
      await mic.stop();
      await PushService.registerToken();
    } catch (_) {
      // Whatever they decline, the app still works while it is open.
    }
    if (mounted) context.go('/idle');
  }

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final link = repo.links.firstOrNull;
    return MapaScaffold(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(24, 30, 24, 24),
        child: Column(children: [
          const Spacer(),
          Buddy(color: link?.tone.color ?? MapaColors.mint, size: 170, wobble: true),
          const SizedBox(height: 24),
          Text('Let Mapa ring you', textAlign: TextAlign.center, style: inter(34, 800, color: c.ink, spacing: -.035, height: 1.05, tabular: false)),
          const SizedBox(height: 14),
          Text(
            'So your phone rings like a normal call, even when it is locked. You will be asked for three things: notifications, showing calls on the lock screen, and the microphone.',
            textAlign: TextAlign.center,
            style: inter(18, 500, color: c.ink2, height: 1.45, tabular: false),
          ),
          const Spacer(flex: 2),
          KeyButton(label: _busy ? 'One moment…' : 'Allow', height: 64, fontSize: 20, onTap: _busy ? null : _allow),
          const SizedBox(height: 6),
          QuietLink('Maybe later', size: 17, onTap: () => context.go('/idle')),
        ]),
      ),
    );
  }
}
