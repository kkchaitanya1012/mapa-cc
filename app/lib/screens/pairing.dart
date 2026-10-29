import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../data/api.dart';
import '../data/repo.dart';
import '../theme/theme.dart';
import '../theme/tokens.dart';
import '../widgets/common.dart';

/// Caretaker pairing: say who it's for, get a code + QR, wait for their phone.
class PairingScreen extends StatefulWidget {
  const PairingScreen({super.key});
  @override
  State<PairingScreen> createState() => _PairingScreenState();
}

class _PairingScreenState extends State<PairingScreen> {
  final _name = TextEditingController();
  final _me = TextEditingController();
  late final int _linksAtStart;
  ({String code, String qrPayload, DateTime expiresAt})? _code;
  bool _busy = false;
  bool _paired = false;
  int _left = 0;
  Timer? _tick, _poll;

  @override
  void initState() {
    super.initState();
    _linksAtStart = repo.links.length; // captured now, before any new link can arrive
    repo.addListener(_watchForPairing);
  }

  /// The parent's phone redeemed the code: a new link appeared.
  void _watchForPairing() {
    if (_paired || _code == null || repo.links.length <= _linksAtStart || !mounted) return;
    // Once only: this screen lingers during its fade-out, and a later update must
    // not send the person "home" again over whatever they opened since.
    _paired = true;
    repo.removeListener(_watchForPairing);
    context.go('/home');
  }

  Future<void> _create() async {
    if (_name.text.trim().isEmpty || _busy) return;
    FocusScope.of(context).unfocus();
    setState(() => _busy = true);
    try {
      final c = await repo.createCode(_name.text, myName: _me.text);
      _tick?.cancel();
      // Realtime tells us the moment they pair; this is the safety net if one update is missed.
      _poll?.cancel();
      _poll = Timer.periodic(const Duration(seconds: 4), (_) => repo.refresh());
      _left = c.expiresAt.difference(DateTime.now()).inSeconds;
      _tick = Timer.periodic(const Duration(seconds: 1), (_) {
        if (mounted) setState(() => _left = _code!.expiresAt.difference(DateTime.now()).inSeconds);
      });
      setState(() {
        _code = c;
        _busy = false;
      });
    } on ApiError catch (e) {
      _fail(e.message);
    } catch (_) {
      _fail("Couldn't make a code. Check your connection and try again.");
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
  void dispose() {
    repo.removeListener(_watchForPairing);
    _tick?.cancel();
    _poll?.cancel();
    _name.dispose();
    _me.dispose();
    super.dispose();
  }

  String get _clock {
    final s = _left < 0 ? 0 : _left;
    return '${s ~/ 60}:${(s % 60).toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return MapaScaffold(
      child: Column(children: [
        MapaNav(
          title: 'Pair a phone',
          onBack: () => repo.links.isEmpty ? context.go('/role') : context.pop(),
        ),
        Expanded(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(20, 6, 20, 30),
            children: _code == null ? _inputStage(c) : _codeStage(c),
          ),
        ),
      ]),
    );
  }

  List<Widget> _inputStage(MapaColors c) => [
        Text('Who are you setting this up for?', style: inter(30, 800, color: c.ink, spacing: -.03, height: 1.1, tabular: false)),
        const SizedBox(height: 22),
        _Field(controller: _name, label: 'What do you call them?', hint: 'Amma', icon: LucideIcons.users, onChanged: () => setState(() {})),
        const SizedBox(height: 12),
        _Field(controller: _me, label: 'Your name (they will see it)', hint: 'Optional', icon: LucideIcons.user, onChanged: () {}),
        const SizedBox(height: 26),
        KeyButton(
          label: _busy ? 'Making your code…' : 'Create code',
          onTap: _name.text.trim().isEmpty || _busy ? null : _create,
          kind: _name.text.trim().isEmpty ? KeyKind.quiet : KeyKind.primary,
        ),
      ];

  List<Widget> _codeStage(MapaColors c) {
    final who = _name.text.trim();
    final shown = '${_code!.code.substring(0, 3)} ${_code!.code.substring(3)}';
    final expired = _left <= 0;
    return [
      Center(
        child: AnimatedOpacity(
          opacity: expired ? .25 : 1,
          duration: const Duration(milliseconds: 300),
          child: Container(
            width: 222,
            height: 222,
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(30),
              boxShadow: [BoxShadow(color: c.shadow, blurRadius: 40, spreadRadius: -20, offset: const Offset(0, 20))],
            ),
            child: Semantics(
              label: 'QR code for pairing',
              child: QrImageView(
                data: _code!.qrPayload,
                padding: EdgeInsets.zero,
                eyeStyle: const QrEyeStyle(eyeShape: QrEyeShape.square, color: Color(0xFF2D2A3E)),
                dataModuleStyle: const QrDataModuleStyle(dataModuleShape: QrDataModuleShape.square, color: Color(0xFF2D2A3E)),
              ),
            ),
          ),
        ),
      ),
      const SizedBox(height: 22),
      Semantics(
        label: 'Pairing code ${_code!.code.split("").join(" ")}',
        child: Text(shown, textAlign: TextAlign.center, style: inter(50, 800, color: expired ? c.ink2 : c.ink, spacing: .06, height: 1)),
      ),
      const SizedBox(height: 10),
      Text(
        expired
            ? 'This code has expired.'
            : "Open Mapa on $who's phone and scan or type this. Expires in $_clock.",
        textAlign: TextAlign.center,
        style: inter(14.5, 500, color: c.ink2, height: 1.4),
      ),
      const SizedBox(height: 18),
      if (!expired)
        Row(mainAxisAlignment: MainAxisAlignment.center, children: [
          const _Dots(),
          const SizedBox(width: 10),
          Text("Waiting for $who's phone", style: inter(15.5, 600, color: c.ink2, tabular: false)),
        ]),
      const SizedBox(height: 24),
      if (expired)
        KeyButton(label: 'Make a new code', onTap: _create)
      else
        KeyButton(
          label: 'Share the code',
          icon: LucideIcons.share,
          kind: KeyKind.secondary,
          onTap: () {
            Clipboard.setData(ClipboardData(text: _code!.code));
            ScaffoldMessenger.of(context).showSnackBar(SnackBar(
              behavior: SnackBarBehavior.floating,
              backgroundColor: c.ink,
              content: Text('Code copied', style: inter(15, 600, color: c.bg, tabular: false)),
            ));
          },
        ),
      const SizedBox(height: 6),
      Center(
        child: QuietLink('Use a different name', onTap: () {
          _tick?.cancel();
          _poll?.cancel();
          setState(() => _code = null);
        }),
      ),
    ];
  }
}

class _Field extends StatelessWidget {
  const _Field({required this.controller, required this.label, required this.hint, required this.icon, required this.onChanged});
  final TextEditingController controller;
  final String label, hint;
  final IconData icon;
  final VoidCallback onChanged;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return Container(
      height: 62,
      padding: const EdgeInsets.symmetric(horizontal: 18),
      decoration: BoxDecoration(
        color: c.surface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: c.line, width: 1.5),
      ),
      child: Row(children: [
        Icon(icon, color: c.ink2, size: 22),
        const SizedBox(width: 12),
        Expanded(
          child: TextField(
            controller: controller,
            onChanged: (_) => onChanged(),
            textCapitalization: TextCapitalization.words,
            maxLength: 40,
            style: inter(18, 600, color: c.ink, tabular: false),
            cursorColor: c.ink,
            decoration: InputDecoration(
              border: InputBorder.none,
              counterText: '',
              labelText: label,
              hintText: hint,
              hintStyle: inter(18, 500, color: c.ink2.withValues(alpha: .6), tabular: false),
              labelStyle: inter(14, 600, color: c.ink2, tabular: false),
              floatingLabelBehavior: FloatingLabelBehavior.always,
            ),
          ),
        ),
      ]),
    );
  }
}

class _Dots extends StatefulWidget {
  const _Dots();
  @override
  State<_Dots> createState() => _DotsState();
}

class _DotsState extends State<_Dots> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 1200))..repeat();
  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return AnimatedBuilder(
      animation: _c,
      builder: (_, _) => Row(mainAxisSize: MainAxisSize.min, children: [
        for (var i = 0; i < 3; i++)
          Builder(builder: (_) {
            final t = ((_c.value - i * .125) % 1 + 1) % 1;
            final up = t < .4 ? (1 - (t / .4 - .5).abs() * 2) : 0.0;
            return Container(
              margin: const EdgeInsets.symmetric(horizontal: 2),
              width: 7,
              height: 7,
              transform: Matrix4.translationValues(0, -3 * up, 0),
              decoration: BoxDecoration(color: c.ink2.withValues(alpha: .3 + .7 * up), shape: BoxShape.circle),
            );
          }),
      ]),
    );
  }
}
