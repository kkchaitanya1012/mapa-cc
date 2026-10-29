import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../data/models.dart';
import '../data/repo.dart';
import '../theme/theme.dart';
import '../theme/tokens.dart';
import '../widgets/buddy.dart';
import '../widgets/common.dart';
import 'alerts.dart';
import 'today.dart';

class CaretakerShell extends StatefulWidget {
  const CaretakerShell({super.key, this.initialTab = 0});
  final int initialTab;
  @override
  State<CaretakerShell> createState() => _CaretakerShellState();
}

class _CaretakerShellState extends State<CaretakerShell> {
  late int _tab = widget.initialTab;
  String? _hiddenLive;

  Future<void> _openAdd() async {
    await showGeneralDialog<void>(
      context: context,
      barrierDismissible: true,
      barrierLabel: 'Close',
      barrierColor: Colors.transparent,
      transitionDuration: const Duration(milliseconds: 260),
      pageBuilder: (_, _, _) => const _AddMenu(),
      transitionBuilder: (_, a, _, child) =>
          FadeTransition(opacity: CurvedAnimation(parent: a, curve: Curves.easeOutCubic), child: child),
    );
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: repo,
      builder: (context, _) {
        final showFab = _tab == 0 && repo.hasReminders;
        return MapaScaffold(
          safeBottom: false,
          child: Stack(children: [
            Positioned.fill(
              child: IndexedStack(index: _tab, children: [
                const TodayScreen(),
                const _PeopleTab(),
                const AlertsScreen(),
              ]),
            ),
            if (showFab)
              Positioned(
                right: 20,
                bottom: 112,
                child: _Fab(onTap: _openAdd),
              ),
            Positioned(left: 0, right: 0, bottom: 0, child: _TabBar(index: _tab, onTap: (i) => setState(() => _tab = i))),
            if (repo.liveCall != null && repo.liveCall!.id != _hiddenLive)
              Positioned.fill(child: _LiveCallSheet(occurrence: repo.liveCall!, onHide: () => setState(() => _hiddenLive = repo.liveCall?.id))),
          ]),
        );
      },
    );
  }
}

class _Fab extends StatelessWidget {
  const _Fab({required this.onTap, this.open = false});
  final VoidCallback onTap;
  final bool open;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return Semantics(
      button: true,
      label: open ? 'Close' : 'Add',
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          width: 64,
          height: 64,
          decoration: BoxDecoration(
            color: open ? c.surface : c.ink,
            borderRadius: BorderRadius.circular(22),
            boxShadow: [
              BoxShadow(color: open ? c.line : c.edge, offset: const Offset(0, 4)),
              BoxShadow(color: c.shadow, blurRadius: 28, spreadRadius: -8, offset: const Offset(0, 16)),
            ],
          ),
          child: AnimatedRotation(
            turns: open ? .125 : 0,
            duration: const Duration(milliseconds: 260),
            curve: Curves.easeOutCubic,
            child: Icon(LucideIcons.plus, size: 30, color: open ? c.ink : c.bg),
          ),
        ),
      ),
    );
  }
}

class _AddMenu extends StatelessWidget {
  const _AddMenu();

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    void go(Future<void> Function(BuildContext) action) {
      final ctx = Navigator.of(context, rootNavigator: true).context;
      Navigator.of(context).pop();
      action(ctx);
    }

    return Stack(children: [
      Positioned.fill(
        child: GestureDetector(
          onTap: () => Navigator.of(context).pop(),
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 14, sigmaY: 14),
            child: Container(color: c.bg.withValues(alpha: .46)),
          ),
        ),
      ),
      Positioned(
        right: 20,
        bottom: 192 + MediaQuery.of(context).padding.bottom * 0,
        child: Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
          _Opt('Add another person', LucideIcons.users, Tone.mint, () => go((c) async => c.push('/pair'))),
          const SizedBox(height: 12),
          _Opt('Add a reminder', LucideIcons.messageCircle, Tone.peach, () => go(startReminder)),
        ]),
      ),
      Positioned(right: 20, bottom: 112, child: _Fab(open: true, onTap: () => Navigator.of(context).pop())),
    ]);
  }
}

class _Opt extends StatelessWidget {
  const _Opt(this.label, this.icon, this.tone, this.onTap);
  final String label;
  final IconData icon;
  final Tone tone;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return Semantics(
      button: true,
      label: label,
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.fromLTRB(22, 10, 12, 10),
          decoration: BoxDecoration(
            color: c.surface,
            borderRadius: BorderRadius.circular(24),
            boxShadow: [BoxShadow(color: c.shadow, blurRadius: 30, spreadRadius: -12, offset: const Offset(0, 16))],
          ),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            Text(label, style: inter(17, 700, color: c.ink, tabular: false)),
            const SizedBox(width: 14),
            Container(
              width: 46,
              height: 46,
              decoration: BoxDecoration(color: tone.color, borderRadius: BorderRadius.circular(16)),
              child: Icon(icon, size: 22, color: MapaColors.onPastel),
            ),
          ]),
        ),
      ),
    );
  }
}

class _TabBar extends StatelessWidget {
  const _TabBar({required this.index, required this.onTap});
  final int index;
  final ValueChanged<int> onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final bottom = MediaQuery.of(context).padding.bottom;
    return ClipRect(
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 22, sigmaY: 22),
        child: Container(
          height: 58 + bottom + 8,
          padding: EdgeInsets.fromLTRB(24, 8, 24, bottom),
          decoration: BoxDecoration(color: c.frost, border: Border(top: BorderSide(color: c.frostLine))),
          child: Row(mainAxisAlignment: MainAxisAlignment.spaceAround, children: [
            _TabItem('Today', LucideIcons.calendarDays, index == 0, () => onTap(0)),
            _TabItem('People', LucideIcons.users, index == 1, () => onTap(1)),
            _TabItem('Alerts', LucideIcons.bell, index == 2, () => onTap(2), badge: repo.unseenAlerts),
          ]),
        ),
      ),
    );
  }
}

class _TabItem extends StatelessWidget {
  const _TabItem(this.label, this.icon, this.on, this.onTap, {this.badge = 0});
  final String label;
  final IconData icon;
  final bool on;
  final VoidCallback onTap;
  final int badge;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final col = on ? c.ink : c.ink2;
    return Semantics(
      button: true,
      selected: on,
      label: label,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: SizedBox(
          width: 92,
          height: 52,
          child: Stack(alignment: Alignment.topCenter, clipBehavior: Clip.none, children: [
            if (on)
              Positioned(
                top: -8,
                child: Container(
                  width: 28,
                  height: 4,
                  decoration: BoxDecoration(color: c.ink, borderRadius: const BorderRadius.vertical(bottom: Radius.circular(4))),
                ),
              ),
            Column(mainAxisAlignment: MainAxisAlignment.center, children: [
              Icon(icon, size: 24, color: col),
              const SizedBox(height: 4),
              Text(label, style: inter(12, 600, color: col, tabular: false)),
            ]),
            if (badge > 0)
              Positioned(
                top: 0,
                left: 52,
                child: Container(
                  constraints: const BoxConstraints(minWidth: 18),
                  height: 18,
                  padding: const EdgeInsets.symmetric(horizontal: 5),
                  alignment: Alignment.center,
                  decoration: BoxDecoration(color: c.bad, borderRadius: BorderRadius.circular(9)),
                  child: Text('$badge', style: inter(11, 800, color: c.isDark ? MapaColors.onPastel : Colors.white)),
                ),
              ),
          ]),
        ),
      ),
    );
  }
}

class _PeopleTab extends StatelessWidget {
  const _PeopleTab();

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return ListenableBuilder(
      listenable: repo,
      builder: (context, _) {
        final people = repo.links;
        return ListView(
          padding: const EdgeInsets.fromLTRB(20, 14, 20, 150),
          children: [
            Text('People', style: T.h1(c.ink)),
            const SizedBox(height: 4),
            Text('The people Mapa calls for you.', style: inter(15, 500, color: c.ink2, tabular: false)),
            const SizedBox(height: 22),
            if (people.isNotEmpty)
              MCard(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Column(children: [
                  for (var i = 0; i < people.length; i++)
                    InkWell(
                      onTap: () => context.push('/person/${people[i].id}'),
                      child: Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(border: i == people.length - 1 ? null : Border(bottom: BorderSide(color: c.line))),
                        child: Row(children: [
                          PersonAvatar(people[i].initial, tone: people[i].tone, size: 52),
                          const SizedBox(width: 14),
                          Expanded(
                            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                              Text(people[i].nickname, style: inter(18, 700, color: c.ink, tabular: false)),
                              const SizedBox(height: 2),
                              Text(
                                repo.streakFor(people[i].id) > 0
                                    ? '${repo.streakFor(people[i].id)} days in a row'
                                    : '${repo.remindersFor(people[i].id).length} reminders',
                                style: T.small(c.ink2),
                              ),
                            ]),
                          ),
                          Icon(LucideIcons.chevronRight, color: c.ink2),
                        ]),
                      ),
                    ),
                ]),
              ),
            const SizedBox(height: 16),
            KeyButton(label: 'Add another person', icon: LucideIcons.plus, kind: KeyKind.secondary, onTap: () => context.push('/pair')),
          ],
        );
      },
    );
  }
}

/// The live call lifts on frosted glass; everything behind quiets down.
class _LiveCallSheet extends StatelessWidget {
  const _LiveCallSheet({required this.occurrence, required this.onHide});
  final Occurrence occurrence;
  final VoidCallback onHide;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final link = repo.linkOf(occurrence);
    final rem = repo.reminderById(occurrence.reminderId);
    final name = link?.nickname ?? 'them';
    return Stack(children: [
      Positioned.fill(
        child: GestureDetector(
          onTap: onHide,
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
            child: Container(color: c.bg.withValues(alpha: .4)),
          ),
        ),
      ),
      Positioned(
        left: 10,
        right: 10,
        bottom: 10 + MediaQuery.of(context).padding.bottom,
        child: Frost(
          radius: 38,
          blur: 30,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 22, 20, 18),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              Row(children: [
                Buddy(color: link?.tone.color ?? MapaColors.mint, size: 62, wobble: true),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text('Mapa is talking to $name', style: inter(20, 700, color: c.ink, spacing: -.01, tabular: false)),
                    const SizedBox(height: 2),
                    Text(rem == null ? 'On a call' : 'Checking on ${rem.medicine}', style: T.small(c.ink2)),
                  ]),
                ),
                const _Wave(),
              ]),
              const SizedBox(height: 8),
              QuietLink('Hide', onTap: onHide),
            ]),
          ),
        ),
      ),
    ]);
  }
}

class _Wave extends StatefulWidget {
  const _Wave();
  @override
  State<_Wave> createState() => _WaveState();
}

class _WaveState extends State<_Wave> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 1000))..repeat();
  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    const hs = [.45, .8, 1.0, .65, .9];
    return SizedBox(
      height: 34,
      child: AnimatedBuilder(
        animation: _c,
        builder: (_, _) => Row(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.center, children: [
          for (var i = 0; i < hs.length; i++)
            Container(
              margin: const EdgeInsets.symmetric(horizontal: 2),
              width: 5,
              height: 34 * hs[i] * (.45 + .55 * (0.5 + 0.5 * (1 - ((_c.value + i * .12) % 1 * 2 - 1).abs()))),
              decoration: BoxDecoration(color: c.ink, borderRadius: BorderRadius.circular(3)),
            ),
        ]),
      ),
    );
  }
}
