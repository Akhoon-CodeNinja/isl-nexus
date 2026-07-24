import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/material.dart';

// ─────────────────────────────────────────────────────────────────────────────
// AI MASCOT (pure Flutter, no Rive / no external animation assets)
//
// Implements the "living assistant" behaviour from the animation spec using
// only CustomPainter + implicit/explicit Flutter animations:
//   • Idle breathing + glow pulse + random blink (always running)
//   • userTyping   -> eyes look toward input, slight forward lean
//   • thinking     -> eyes look up/sideways, head tilt, animated "..." dots
//   • speaking     -> mouth flaps while text streams in
//   • happy        -> brief bright glow + big smile after a reply lands
//   • error        -> worried mouth, dimmer glow, head tilt
//
// Usage:
//   AiMascotAvatar(state: MascotState.thinking, size: 40)
//
// NOTE: "userTyping" and "typingWatching" from the original spec are merged
// into a single `userTyping` state here (same visual — eyes on the input,
// attentive smile) to keep the state machine simple; likewise "send" is
// folded into the transition straight into `thinking`, since it's only a
// ~150ms beat that isn't very visible on a 40px avatar anyway.
// ─────────────────────────────────────────────────────────────────────────────

enum MascotState { idle, userTyping, thinking, speaking, happy, error }

class AiMascotAvatar extends StatefulWidget {
  const AiMascotAvatar({
    super.key,
    required this.state,
    this.size = 40,
    this.showAntenna = true,
  });

  final MascotState state;
  final double size;
  final bool showAntenna;

  @override
  State<AiMascotAvatar> createState() => _AiMascotAvatarState();
}

class _AiMascotAvatarState extends State<AiMascotAvatar>
    with TickerProviderStateMixin {
  // Continuous ambient loop -> drives breathing float, glow pulse,
  // thinking-dots phase, and the speaking mouth-flap wave.
  late final AnimationController _loop = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 2600),
  )..repeat();

  // One-shot quick blink (open -> closed -> open), retriggered on a
  // randomised 3-6s timer per the spec.
  late final AnimationController _blink = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 140),
  );
  Timer? _blinkTimer;
  final math.Random _rng = math.Random();

  // Smoothly eases the whole expression (eyes/tilt/smile/glow) from
  // whatever it currently is toward the new target whenever `state`
  // changes, instead of snapping.
  late final AnimationController _exprCtrl = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 260),
  )..value = 1;
  late _Expression _fromExpr = _targetFor(widget.state);
  late _Expression _toExpr = _targetFor(widget.state);

  @override
  void initState() {
    super.initState();
    _scheduleBlink();
  }

  void _scheduleBlink() {
    final ms = 3000 + _rng.nextInt(3000); // 3-6s, per spec
    _blinkTimer = Timer(Duration(milliseconds: ms), () async {
      if (!mounted) return;
      await _blink.forward();
      if (!mounted) return;
      await _blink.reverse();
      if (!mounted) return;
      _scheduleBlink();
    });
  }

  @override
  void didUpdateWidget(covariant AiMascotAvatar oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.state != widget.state) {
      final current = _Expression.lerp(
        _fromExpr,
        _toExpr,
        Curves.easeOutCubic.transform(_exprCtrl.value),
      );
      _fromExpr = current;
      _toExpr = _targetFor(widget.state);
      _exprCtrl
        ..value = 0
        ..forward();
    }
  }

  _Expression _targetFor(MascotState s) {
    switch (s) {
      case MascotState.idle:
        return const _Expression(
            eyeX: 0, eyeY: 0, tilt: 0, smile: 0.35, glow: 0.35, squint: 0);
      case MascotState.userTyping:
        return const _Expression(
            eyeX: 0, eyeY: 0.4, tilt: 0.05, smile: 0.45, glow: 0.55, squint: 0);
      case MascotState.thinking:
        return const _Expression(
            eyeX: 0.18, eyeY: -0.35, tilt: -0.09, smile: 0.12, glow: 0.75, squint: 0);
      case MascotState.speaking:
        return const _Expression(
            eyeX: 0, eyeY: 0, tilt: 0, smile: 0.5, glow: 0.65, squint: 0);
      case MascotState.happy:
        return const _Expression(
            eyeX: 0, eyeY: 0, tilt: 0, smile: 0.9, glow: 1.0, squint: 0.45);
      case MascotState.error:
        return const _Expression(
            eyeX: 0, eyeY: 0.1, tilt: 0.1, smile: -0.55, glow: 0.2, squint: 0);
    }
  }

  @override
  void dispose() {
    _blinkTimer?.cancel();
    _loop.dispose();
    _blink.dispose();
    _exprCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: Listenable.merge([_loop, _blink, _exprCtrl]),
      builder: (context, _) {
        final expr = _Expression.lerp(
          _fromExpr,
          _toExpr,
          Curves.easeOutCubic.transform(_exprCtrl.value),
        );

        final t = _loop.value; // 0..1 repeating, ~2.6s period
        final breathe = math.sin(t * 2 * math.pi); // -1..1
        final glowPulse = (math.sin(t * 2 * math.pi) + 1) / 2; // 0..1

        double mouthWave = 0;
        if (widget.state == MascotState.speaking) {
          mouthWave = math.sin(t * 2 * math.pi * 6).abs() * 0.35;
        }

        // A tiny internal pixel offset is invisible on a 24-34px avatar,
        // so the "breathing" is expressed as a visible whole-avatar scale
        // pulse (~6%) instead of just an internal draw offset.
        final scalePulse = 1.0 + (breathe * 0.06);

        return Transform.scale(
          scale: scalePulse,
          child: CustomPaint(
            size: Size.square(widget.size),
            painter: _MascotPainter(
              eyeOpen: 1 - _blink.value,
              eyeX: expr.eyeX,
              eyeY: expr.eyeY,
              tilt: expr.tilt,
              smile: (expr.smile + mouthWave).clamp(-1.0, 1.0),
              squint: expr.squint,
              glow: (expr.glow * 0.45) + (glowPulse * expr.glow * 0.55),
              breathe: breathe,
              showDots: widget.state == MascotState.thinking,
              dotsPhase: t,
              showAntenna: widget.showAntenna,
            ),
          ),
        );
      },
    );
  }
}

@immutable
class _Expression {
  const _Expression({
    required this.eyeX,
    required this.eyeY,
    required this.tilt,
    required this.smile,
    required this.glow,
    required this.squint,
  });

  final double eyeX; // -1..1 (left/right look)
  final double eyeY; // -1..1 (up/down look)
  final double tilt; // radians, small head tilt
  final double smile; // -1 (worried) .. 1 (big smile)
  final double glow; // 0..1 glow intensity
  final double squint; // 0..1 happy-eye squint

  static _Expression lerp(_Expression a, _Expression b, double t) {
    double l(double x, double y) => x + (y - x) * t;
    return _Expression(
      eyeX: l(a.eyeX, b.eyeX),
      eyeY: l(a.eyeY, b.eyeY),
      tilt: l(a.tilt, b.tilt),
      smile: l(a.smile, b.smile),
      glow: l(a.glow, b.glow),
      squint: l(a.squint, b.squint),
    );
  }
}

class _MascotPainter extends CustomPainter {
  _MascotPainter({
    required this.eyeOpen,
    required this.eyeX,
    required this.eyeY,
    required this.tilt,
    required this.smile,
    required this.squint,
    required this.glow,
    required this.breathe,
    required this.showDots,
    required this.dotsPhase,
    required this.showAntenna,
  });

  final double eyeOpen, eyeX, eyeY, tilt, smile, squint, glow, breathe;
  final bool showDots, showAntenna;
  final double dotsPhase;

  static const Color _glowGreen = Color(0xFF34D399);
  static const Color _ledGreen = Color(0xFF22C55E);

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;
    final float = breathe * (h * 0.02);
    final center = Offset(w / 2, h / 2 + float);

    canvas.save();
    canvas.translate(center.dx, center.dy);
    canvas.rotate(tilt);
    canvas.translate(-center.dx, -center.dy);

    // ── Soft outer glow, reacts to state/pulse ──────────────────────────
    final glowPaint = Paint()
      ..color = _glowGreen.withOpacity(0.45 * glow.clamp(0.0, 1.0))
      ..maskFilter = MaskFilter.blur(BlurStyle.normal, w * 0.20);
    canvas.drawCircle(center, w * 0.47, glowPaint);

    // ── Head: white matte rounded shell ─────────────────────────────────
    final headRect = Rect.fromCenter(center: center, width: w * 0.86, height: h * 0.86);
    final headRRect = RRect.fromRectAndRadius(headRect, Radius.circular(w * 0.30));
    canvas.drawRRect(headRRect, Paint()..color = Colors.white);
    canvas.drawRRect(
      headRRect,
      Paint()
        ..color = Colors.black.withOpacity(0.06)
        ..style = PaintingStyle.stroke
        ..strokeWidth = math.max(0.6, w * 0.012),
    );

    // ── Antenna ──────────────────────────────────────────────────────────
    if (showAntenna && w >= 28) {
      final base = Offset(center.dx, headRect.top + h * 0.02);
      final tip = Offset(center.dx, headRect.top - h * 0.14);
      canvas.drawLine(
        base,
        tip,
        Paint()
          ..color = Colors.grey.shade400
          ..strokeWidth = math.max(1.0, w * 0.025)
          ..strokeCap = StrokeCap.round,
      );
      canvas.drawCircle(tip, w * 0.055, Paint()..color = _ledGreen);
    }

    // ── Face: glossy black OLED screen ──────────────────────────────────
    final screenRect = Rect.fromCenter(
      center: Offset(center.dx, center.dy + h * 0.02),
      width: w * 0.60,
      height: h * 0.48,
    );
    final screenRRect = RRect.fromRectAndRadius(screenRect, Radius.circular(w * 0.15));
    canvas.drawRRect(screenRRect, Paint()..color = const Color(0xFF0B0F10));

    // subtle glossy highlight
    final highlight = Path()
      ..moveTo(screenRect.left + screenRect.width * 0.1, screenRect.top + screenRect.height * 0.08)
      ..lineTo(screenRect.left + screenRect.width * 0.55, screenRect.top + screenRect.height * 0.08)
      ..lineTo(screenRect.left + screenRect.width * 0.35, screenRect.top + screenRect.height * 0.35)
      ..lineTo(screenRect.left + screenRect.width * 0.1, screenRect.top + screenRect.height * 0.35)
      ..close();
    canvas.drawPath(highlight, Paint()..color = Colors.white.withOpacity(0.04));

    // ── Eyes ─────────────────────────────────────────────────────────────
    final eyeSpacing = screenRect.width * 0.26;
    final eyeBaseY = screenRect.center.dy - screenRect.height * 0.05;
    final eyeOffsetX = eyeX * screenRect.width * 0.10;
    final eyeOffsetY = eyeY * screenRect.height * 0.12;
    final eyeH = (screenRect.height * 0.32 * eyeOpen.clamp(0.05, 1.0) * (1 - squint * 0.55))
        .clamp(1.0, screenRect.height);
    final eyeW = screenRect.width * 0.17;

    final eyePaint = Paint()
      ..color = _ledGreen
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 1.0);

    for (final dx in [-eyeSpacing, eyeSpacing]) {
      final eyeCenter = Offset(
        screenRect.center.dx + dx + eyeOffsetX,
        eyeBaseY + eyeOffsetY,
      );
      final eyeRect = Rect.fromCenter(center: eyeCenter, width: eyeW, height: eyeH);
      canvas.drawRRect(
        RRect.fromRectAndRadius(eyeRect, Radius.circular(eyeW * 0.4)),
        eyePaint,
      );
    }

    // ── Mouth (curve direction = smile/worried) ────────────────────────
    final mouthCenter = Offset(
      screenRect.center.dx,
      screenRect.bottom - screenRect.height * 0.20,
    );
    final mouthWidth = screenRect.width * 0.32;
    final curveAmt = smile.clamp(-1.0, 1.0) * (screenRect.height * 0.11);
    final mouthPath = Path()
      ..moveTo(mouthCenter.dx - mouthWidth / 2, mouthCenter.dy)
      ..quadraticBezierTo(
        mouthCenter.dx,
        mouthCenter.dy + curveAmt,
        mouthCenter.dx + mouthWidth / 2,
        mouthCenter.dy,
      );
    canvas.drawPath(
      mouthPath,
      Paint()
        ..color = _ledGreen
        ..style = PaintingStyle.stroke
        ..strokeWidth = math.max(1.0, w * 0.032)
        ..strokeCap = StrokeCap.round,
    );

    // ── Thinking dots ("...") ───────────────────────────────────────────
    if (showDots) {
      for (int i = 0; i < 3; i++) {
        final phase = ((dotsPhase * 3) - i) % 3;
        final opacity = (0.25 + 0.75 * (1 - phase.abs().clamp(0.0, 1.0))).clamp(0.2, 1.0);
        final dotX = screenRect.center.dx + (i - 1) * (w * 0.055);
        canvas.drawCircle(
          Offset(dotX, screenRect.bottom - screenRect.height * 0.08),
          w * 0.017,
          Paint()..color = _ledGreen.withOpacity(opacity),
        );
      }
    }

    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _MascotPainter oldDelegate) => true;
}