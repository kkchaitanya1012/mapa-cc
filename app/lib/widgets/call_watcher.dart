import 'package:flutter/material.dart';

import '../data/call.dart';
import '../data/repo.dart';
import '../push/push_service.dart';
import '../router.dart';

/// Sits above every screen on the parent's phone: when Mapa starts ringing,
/// open the incoming-call screen wherever they happen to be.
class CallWatcher extends StatefulWidget {
  const CallWatcher({super.key, required this.child});
  final Widget child;
  @override
  State<CallWatcher> createState() => _CallWatcherState();
}

class _CallWatcherState extends State<CallWatcher> {
  String? _shown; // the ringing call we already opened

  @override
  void initState() {
    super.initState();
    repo.addListener(_check);
  }

  @override
  void dispose() {
    repo.removeListener(_check);
    super.dispose();
  }

  Future<void> _check() async {
    final ring = repo.ringingForMe;
    if (ring == null) {
      _shown = null;
      return;
    }
    if (ring.id == _shown || callController.active) return;
    if (await PushService.showingNative(ring.id)) return; // the lock-screen call is already up
    if (!mounted || callController.active) return;
    final here = router.routerDelegate.currentConfiguration.uri.path;
    if (here.startsWith('/call/')) return;
    _shown = ring.id;
    router.go('/call/incoming?o=${ring.id}');
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
