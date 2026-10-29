import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../data/api.dart';
import '../data/repo.dart';
import '../theme/theme.dart';
import '../theme/tokens.dart';
import '../widgets/common.dart';

class RoleSelectScreen extends StatefulWidget {
  const RoleSelectScreen({super.key});
  @override
  State<RoleSelectScreen> createState() => _RoleSelectScreenState();
}

class _RoleSelectScreenState extends State<RoleSelectScreen> {
  bool _busy = false;

  Future<void> _choose(String role, String next) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await repo.chooseRole(role);
      if (mounted) context.go(next);
    } on ApiError catch (e) {
      _fail(e.message);
    } catch (_) {
      _fail("Couldn't get started. Check your connection and try again.");
    }
  }

  void _fail(String msg) {
    if (!mounted) return;
    setState(() => _busy = false);
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      behavior: SnackBarBehavior.floating,
      backgroundColor: context.c.ink,
      content: Text(msg, style: inter(15, 600, color: context.c.bg, tabular: false)),
    ));
  }

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return MapaScaffold(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20),
        child: AnimatedOpacity(
          opacity: _busy ? .5 : 1,
          duration: const Duration(milliseconds: 200),
          child: IgnorePointer(
            ignoring: _busy,
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const SizedBox(height: 34),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4),
            child: Text("Who's this phone for?", style: T.h1(c.ink)),
          ),
          const SizedBox(height: 6),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4),
            child: Text('You can change this later in settings.',
                style: inter(15, 500, color: c.ink2, tabular: false)),
          ),
          const SizedBox(height: 26),
          Expanded(
            child: _RoleTile(
              tone: Tone.peach,
              icon: LucideIcons.users,
              title: 'I look after someone',
              sub: "Set reminders, see how they're doing",
              onTap: () => _choose('caretaker', '/pair'),
            ),
          ),
          const SizedBox(height: 16),
          Expanded(
            child: _RoleTile(
              tone: Tone.mint,
              icon: LucideIcons.phone,
              title: 'Someone looks after me',
              sub: "I'll get Mapa's calls",
              onTap: () => _choose('recipient', '/join'),
            ),
          ),
          const SizedBox(height: 24),
        ]),
          ),
        ),
      ),
    );
  }
}

class _RoleTile extends StatefulWidget {
  const _RoleTile({required this.tone, required this.icon, required this.title, required this.sub, required this.onTap});
  final Tone tone;
  final IconData icon;
  final String title, sub;
  final VoidCallback onTap;
  @override
  State<_RoleTile> createState() => _RoleTileState();
}

class _RoleTileState extends State<_RoleTile> {
  bool _down = false;
  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return Semantics(
      button: true,
      label: '${widget.title}. ${widget.sub}',
      child: GestureDetector(
        onTapDown: (_) => setState(() => _down = true),
        onTapCancel: () => setState(() => _down = false),
        onTapUp: (_) => setState(() => _down = false),
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 110),
          transform: Matrix4.translationValues(0, _down ? 2 : 0, 0),
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            color: widget.tone.color,
            borderRadius: BorderRadius.circular(32),
            boxShadow: [
              const BoxShadow(color: Color(0x242D2A3E), offset: Offset(0, 5)),
              BoxShadow(color: c.shadow, blurRadius: 34, spreadRadius: -18, offset: const Offset(0, 18)),
            ],
          ),
          child: Stack(children: [
            Align(
              alignment: Alignment.topRight,
              child: Container(
                width: 88,
                height: 88,
                decoration: const BoxDecoration(color: Color(0x8CFFFFFF), shape: BoxShape.circle),
                child: Icon(widget.icon, size: 40, color: MapaColors.onPastel),
              ),
            ),
            Align(
              alignment: Alignment.bottomLeft,
              child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
                ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 210),
                  child: Text(widget.title,
                      style: inter(28, 800, color: MapaColors.onPastel, spacing: -.03, height: 1.1, tabular: false)),
                ),
                const SizedBox(height: 6),
                Text(widget.sub, style: inter(15.5, 500, color: MapaColors.onPastel2, tabular: false)),
              ]),
            ),
          ]),
        ),
      ),
    );
  }
}
