import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../data/api.dart';
import '../data/call.dart';
import '../data/repo.dart';
import '../format.dart';
import '../push/ring.dart';
import '../theme/theme.dart';
import '../theme/tokens.dart';
import '../widgets/buddy.dart';
import '../widgets/coil.dart';
import '../data/models.dart';
import '../widgets/common.dart';
import 'onboarding.dart' show RingingBuddy;

// ---------------------------------------------------------------- incoming

class IncomingCallScreen extends StatefulWidget {
  /// A real ringing call, or null for the demo ring (developer menu).
  const IncomingCallScreen({super.key, this.occurrenceId});
  final String? occurrenceId;
  @override
  State<IncomingCallScreen> createState() => _IncomingCallScreenState();
}

class _IncomingCallScreenState extends State<IncomingCallScreen> with SingleTickerProviderStateMixin {
  late final AnimationController _ring =
      AnimationController(vsync: this, duration: const Duration(milliseconds: 2400))..repeat();
  Timer? _haptic;
  bool _busy = false;

  Occurrence? get _occ => widget.occurrenceId == null
      ? null
      : repo.occurrences.where((o) => o.id == widget.occurrenceId).firstOrNull;

  @override
  void initState() {
    super.initState();
    _haptic = Timer.periodic(const Duration(milliseconds: 1600), (_) => HapticFeedback.mediumImpact());
    Ring.start();
    repo.addListener(_stillRinging);
  }

  /// If the call stops ringing (they were too slow, or it was cancelled), leave quietly.
  void _stillRinging() {
    if (widget.occurrenceId == null || _busy || !mounted) return;
    final o = _occ;
    if (o != null && o.status != 'ringing') context.go('/idle');
  }

  Future<void> _answer() async {
    final id = widget.occurrenceId;
    if (id == null) return context.go('/call/live');       // demo
    if (_busy) return;
    _busy = true;
    Ring.stop();
    try {
      await callController.answer(id);
      if (mounted) context.go('/call/live');
    } on ApiError catch (e) {
      _failed(e.message);
    } catch (_) {
      _failed("Couldn't connect the call. Please try again.");
    }
  }

  void _failed(String msg) {
    _busy = false;
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      behavior: SnackBarBehavior.floating,
      backgroundColor: context.c.ink,
      content: Text(msg, style: inter(15, 600, color: context.c.bg, tabular: false)),
    ));
    context.go('/idle');
  }

  Future<void> _decline() async {
    final id = widget.occurrenceId;
    if (id != null) await callController.decline(id);
    if (mounted) context.go('/idle');
  }

  @override
  void dispose() {
    repo.removeListener(_stillRinging);
    Ring.stop();
    _haptic?.cancel();
    _ring.dispose();
    super.dispose();
  }

  String _medicineName() {
    final o = _occ;
    return (o == null ? null : repo.reminderById(o.reminderId)?.medicine) ?? 'Metformin';
  }

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final o = _occ;
    final tone = (o == null ? null : repo.linkOf(o)?.tone.color) ?? MapaColors.mint;
    return MapaScaffold(
      child: Stack(children: [
        const Blobs([
          (Alignment(-1.3, -.9), 340, MapaColors.peach, .75),
          (Alignment(1.4, .1), 300, MapaColors.lilac, .7),
          (Alignment(-.4, 1.3), 280, MapaColors.mint, .7),
        ]),
        Padding(
          padding: const EdgeInsets.fromLTRB(24, 30, 24, 28),
          child: Column(children: [
            const SizedBox(height: 34),
            RingingBuddy(controller: _ring, color: tone, size: 178),
            const SizedBox(height: 20),
            Text('Mapa is calling', style: inter(38, 800, color: c.ink, spacing: -.035, height: 1.05, tabular: false)),
            const SizedBox(height: 12),
            Text('Time for your ${_medicineName()}',
                textAlign: TextAlign.center, style: inter(21, 600, color: c.ink, height: 1.35, tabular: false)),
            const Spacer(),
            _SlideToAnswer(onAnswer: _answer),
            const SizedBox(height: 10),
            QuietLink('Not now', size: 18, strong: true, onTap: _decline),
          ]),
        ),
      ]),
    );
  }
}

/// Mimics the iOS slide-to-answer: a frosted track, a green key to drag, and a
/// coiled cord that stretches behind it and springs back if you let go.
class _SlideToAnswer extends StatefulWidget {
  const _SlideToAnswer({required this.onAnswer});
  final VoidCallback onAnswer;
  @override
  State<_SlideToAnswer> createState() => _SlideToAnswerState();
}

class _SlideToAnswerState extends State<_SlideToAnswer> with TickerProviderStateMixin {
  static const _h = 76.0, _pad = 8.0;
  double _dx = 0;
  bool _armed = false;
  late final AnimationController _back = AnimationController(vsync: this, duration: const Duration(milliseconds: 380));
  late final AnimationController _shine = AnimationController(vsync: this, duration: const Duration(milliseconds: 2600))..repeat();

  @override
  void dispose() {
    _back.dispose();
    _shine.dispose();
    super.dispose();
  }

  void _release(double max) {
    if (_dx / max > .82) {
      HapticFeedback.heavyImpact();
      widget.onAnswer();
      return;
    }
    final from = _dx;
    final anim = CurvedAnimation(parent: _back, curve: Curves.easeOutBack);
    void tick() => setState(() => _dx = from * (1 - anim.value));
    _back
      ..removeListener(tick)
      ..addListener(tick)
      ..forward(from: 0);
    _armed = false;
  }

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return LayoutBuilder(builder: (context, box) {
      final max = box.maxWidth - _h - _pad * 2;
      final p = (_dx / max).clamp(0.0, 1.0);
      return Semantics(
        label: 'Slide to answer',
        hint: 'Swipe right, or double tap, to answer the call',
        onTap: widget.onAnswer,
        child: Frost(
          radius: 46,
          blur: 26,
          child: SizedBox(
            height: _h + _pad * 2,
            child: Stack(children: [
              if (_dx > 6)
                Positioned(
                  left: _pad + 6,
                  top: 0,
                  bottom: 0,
                  width: _dx,
                  child: Center(child: HCoil(color: c.ink.withValues(alpha: .8), stretch: p, height: 52)),
                ),
              Positioned.fill(
                child: Opacity(
                  opacity: (1 - p * 2).clamp(0, 1),
                  child: Padding(
                    padding: const EdgeInsets.only(left: _h + 12),
                    child: Center(
                      child: AnimatedBuilder(
                        animation: _shine,
                        builder: (_, _) => ShaderMask(
                          blendMode: BlendMode.srcIn,
                          shaderCallback: (r) => LinearGradient(
                            begin: Alignment(-1 + 3 * _shine.value - 1, 0),
                            end: Alignment(1 + 3 * _shine.value - 1, 0),
                            colors: [c.ink2, c.ink, c.ink2],
                            stops: const [.3, .5, .7],
                          ).createShader(r),
                          child: Text('slide to answer', style: inter(21, 600, color: Colors.white, tabular: false)),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              Positioned(
                left: _pad + _dx,
                top: _pad,
                child: GestureDetector(
                  onHorizontalDragStart: (_) => _back.stop(),
                  onHorizontalDragUpdate: (d) {
                    setState(() => _dx = (_dx + d.delta.dx).clamp(0, max));
                    final armed = _dx / max > .82;
                    if (armed && !_armed) HapticFeedback.selectionClick();
                    _armed = armed;
                  },
                  onHorizontalDragEnd: (_) => _release(max),
                  child: Container(
                    width: _h,
                    height: _h,
                    decoration: BoxDecoration(
                      color: MapaColors.answer,
                      shape: BoxShape.circle,
                      boxShadow: [
                        const BoxShadow(color: Color(0x29000000), offset: Offset(0, 4)),
                        BoxShadow(color: MapaColors.answer.withValues(alpha: .5), blurRadius: 20, spreadRadius: -6, offset: const Offset(0, 10)),
                      ],
                    ),
                    child: const Icon(LucideIcons.phone, size: 34, color: Colors.white),
                  ),
                ),
              ),
            ]),
          ),
        ),
      );
    });
  }
}

// -------------------------------------------------------------------- live

class InCallScreen extends StatefulWidget {
  const InCallScreen({super.key});
  @override
  State<InCallScreen> createState() => _InCallScreenState();
}

class _InCallScreenState extends State<InCallScreen> {
  // Demo mode (developer menu): a scripted call. Real mode: driven by callController.
  int _s = 0;
  bool _answered = false;
  bool _loud = false;
  Timer? _t;
  late final bool _real = callController.phase != CallPhase.idle;

  @override
  void initState() {
    super.initState();
    if (_real) {
      callController.addListener(_watchEnd);
      _watchEnd();
    } else {
      _t = Timer.periodic(const Duration(seconds: 1), (_) {
        if (!mounted) return;
        setState(() {
          _s++;
          if (_s == 4) _answered = true;
        });
      });
    }
  }

  /// Mapa (or the network) ended the call: say thank you.
  void _watchEnd() {
    if (callController.phase == CallPhase.ended && mounted) context.go('/call/done');
  }

  @override
  void dispose() {
    callController.removeListener(_watchEnd);
    _t?.cancel();
    super.dispose();
  }

  Future<void> _end() async {
    if (_real) await callController.hangUp();
    if (mounted) context.go('/call/done');
  }

  static String _fmt(int s) => '${s ~/ 60}:${(s % 60).toString().padLeft(2, '0')}';

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return ListenableBuilder(
      listenable: callController,
      builder: (context, _) {
        final joining = callController.phase == CallPhase.joining;
        final clock = _real ? _fmt(callController.seconds) : _fmt(_s);
        final mapaText = !_real
            ? '"Did you take your Metformin with lunch?"'
            : callController.mapaLine.isNotEmpty
                ? callController.mapaLine
                : (joining ? 'Connecting you to Mapa\u2026' : 'Mapa is saying hello\u2026');
        final youText = !_real
            ? (_answered ? 'You: "Not yet, I\'m about to."' : null)
            : (callController.youLine.isNotEmpty ? 'You: "${callController.youLine}"' : null);
        return MapaScaffold(
          child: Stack(children: [
            const Blobs([
              (Alignment(-1.3, -1.0), 320, MapaColors.mint, .7),
              (Alignment(1.4, .6), 300, MapaColors.butter, .7),
            ]),
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 18, 24, 28),
              child: Column(children: [
                Text('Mapa \u00b7 $clock', style: inter(18, 700, color: c.ink2)),
                const SizedBox(height: 14),
                const Buddy(color: MapaColors.mint, size: 170, wobble: true),
                const SizedBox(height: 14),
                _Bars(active: !_real || callController.mapaSpeaking),
                const SizedBox(height: 22),
                Frost(
                  radius: 30,
                  blur: 24,
                  child: Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(22),
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text(mapaText, style: inter(25, 700, color: c.ink, height: 1.28, spacing: -.015, tabular: false)),
                      AnimatedSize(
                        duration: const Duration(milliseconds: 300),
                        curve: Curves.easeOutCubic,
                        child: youText != null
                            ? Padding(
                                padding: const EdgeInsets.only(top: 14),
                                child: Text(youText, style: inter(17, 500, color: c.ink2, height: 1.4, tabular: false)),
                              )
                            : const SizedBox(width: double.infinity),
                      ),
                    ]),
                  ),
                ),
                const Spacer(),
                Row(mainAxisAlignment: MainAxisAlignment.center, crossAxisAlignment: CrossAxisAlignment.end, children: [
                  _RoundCtl(
                    icon: (_real ? callController.speakerOn : _loud) ? LucideIcons.volume2 : LucideIcons.volume1,
                    label: (_real ? callController.speakerOn : _loud) ? 'Speaker on' : 'Speaker off',
                    onTap: () => _real ? callController.setSpeaker(!callController.speakerOn) : setState(() => _loud = !_loud),
                  ),
                  const SizedBox(width: 26),
                  _RoundCtl(icon: LucideIcons.phone, label: 'End', end: true, onTap: _end),
                ]),
              ]),
            ),
          ]),
        );
      },
    );
  }
}

class _RoundCtl extends StatelessWidget {
  const _RoundCtl({required this.icon, required this.label, required this.onTap, this.end = false});
  final IconData icon;
  final String label;
  final bool end;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final size = end ? 104.0 : 84.0;
    return Semantics(
      button: true,
      label: end ? 'End call' : label,
      child: GestureDetector(
        onTap: onTap,
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Container(
            width: size,
            height: size,
            decoration: BoxDecoration(
              color: end ? MapaColors.hangUp : c.surface,
              shape: BoxShape.circle,
              boxShadow: [
                BoxShadow(color: end ? const Color(0x2E000000) : c.line, offset: const Offset(0, 4)),
                BoxShadow(
                  color: end ? MapaColors.hangUp.withValues(alpha: .5) : c.shadow,
                  blurRadius: 24,
                  spreadRadius: -8,
                  offset: const Offset(0, 14),
                ),
              ],
            ),
            child: Transform.rotate(
              angle: end ? 2.356 : 0,
              child: Icon(icon, size: end ? 44 : 34, color: end ? MapaColors.onPastel : c.ink),
            ),
          ),
          const SizedBox(height: 8),
          Text(label, style: inter(16, 700, color: c.ink, tabular: false)),
        ]),
      ),
    );
  }
}

class _Bars extends StatefulWidget {
  const _Bars({this.active = true});
  final bool active;
  @override
  State<_Bars> createState() => _BarsState();
}

class _BarsState extends State<_Bars> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 1000))..repeat();
  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    const hs = [14.0, 30.0, 44.0, 26.0, 38.0, 18.0, 30.0];
    return SizedBox(
      height: 44,
      child: AnimatedBuilder(
        animation: _c,
        builder: (_, _) => Row(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.center, children: [
          for (var i = 0; i < hs.length; i++)
            Container(
              margin: const EdgeInsets.symmetric(horizontal: 3),
              width: 7,
              height: hs[i] * (widget.active ? (.45 + .55 * (1 - ((_c.value + i * .1) % 1 * 2 - 1).abs())) : .3),
              decoration: BoxDecoration(color: c.ink, borderRadius: BorderRadius.circular(4)),
            ),
        ]),
      ),
    );
  }
}

// -------------------------------------------------------------------- done

class CallDoneScreen extends StatelessWidget {
  const CallDoneScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final real = callController.name.isNotEmpty;
    final name = real ? callController.name : 'Nanna';
    final who = real ? (callController.caretaker.isEmpty ? 'Your family' : callController.caretaker) : 'Priya';
    final next = repo.nextCall;
    final nextText = !real
        ? 'Next call tomorrow, 1:30 pm'
        : next == null
            ? 'Mapa will call again soon'
            : 'Next call ${next.at.day != DateTime.now().day ? 'tomorrow, ' : ''}${timeText(next.at)}';
    return MapaScaffold(
      child: Stack(children: [
        const Blobs([
          (Alignment(-1.3, -1.0), 340, MapaColors.butter, .8),
          (Alignment(1.4, .7), 300, MapaColors.peach, .7),
        ]),
        Padding(
          padding: const EdgeInsets.fromLTRB(24, 0, 24, 28),
          child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
            const Buddy(color: MapaColors.butter, size: 200, wobble: true),
            const SizedBox(height: 14),
            Text('Thank you, $name!', textAlign: TextAlign.center, style: inter(38, 800, color: c.ink, spacing: -.035, height: 1.05, tabular: false)),
            const SizedBox(height: 12),
            Text("$who will know you're doing well.",
                textAlign: TextAlign.center, style: inter(21, 600, color: c.ink2, height: 1.35, tabular: false)),
            const SizedBox(height: 30),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 16),
              decoration: BoxDecoration(color: MapaColors.butter, borderRadius: BorderRadius.circular(24)),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                const Icon(LucideIcons.clock, size: 24, color: MapaColors.nextText),
                const SizedBox(width: 12),
                Flexible(child: Text(nextText, style: inter(18, 700, color: MapaColors.nextText))),
              ]),
            ),
            const SizedBox(height: 30),
            KeyButton(
              label: 'Close',
              height: 64,
              fontSize: 20,
              onTap: () {
                callController.acknowledgeEnd();
                context.go('/idle');
              },
            ),
          ]),
        ),
      ]),
    );
  }
}
