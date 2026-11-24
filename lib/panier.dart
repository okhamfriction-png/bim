// Un panier de basket à chaque point gagné (points du sprint, ou case Santé tenue).
import 'dart:math';

import 'package:flutter/material.dart';

import 'store.dart';

class PanierOverlay extends StatefulWidget {
  const PanierOverlay({super.key});
  @override
  State<PanierOverlay> createState() => _PanierOverlayState();
}

class _PanierOverlayState extends State<PanierOverlay> with SingleTickerProviderStateMixin {
  late final AnimationController c =
      AnimationController(vsync: this, duration: const Duration(milliseconds: 2100));
  int? prev, prevH;
  String text = '';

  int get _health {
    if (!store.sprints.contains(store.current)) return 0;
    final (a, b) = store.healthIn(store.current);
    return a + b;
  }

  void _watch() {
    final v = store.valueWeek, h = _health;
    // Pas de panier pour des points arrivés par la synchro d'un autre appareil.
    if (prev != null && store.syncState != 'sync') {
      if (v > prev!) {
        _fire('+${v - prev!} pt${v - prev! > 1 ? 's' : ''}');
      } else if (h > prevH!) {
        _fire('+${h - prevH!} Santé');
      }
    }
    prev = v;
    prevH = h;
  }

  void _fire(String s) {
    text = s;
    c.forward(from: 0);
  }

  @override
  void initState() {
    super.initState();
    prev = store.valueWeek;
    prevH = _health;
    store.addListener(_watch);
  }

  @override
  void dispose() {
    store.removeListener(_watch);
    c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => IgnorePointer(
        child: AnimatedBuilder(
          animation: c,
          builder: (context, _) => c.isAnimating
              ? CustomPaint(painter: _Shot(c.value, text), size: Size.infinite)
              : const SizedBox.expand(),
        ),
      );
}

class _Shot extends CustomPainter {
  final double t;
  final String text;
  _Shot(this.t, this.text);

  @override
  void paint(Canvas c, Size s) {
    final fade = t < .1 ? t / .1 : (t > .82 ? (1 - t) / .18 : 1.0);
    final cx = s.width / 2, ry = s.height * .36; // le cercle du panier
    const orange = Color(0xFFF97316);
    c.drawRect(Offset.zero & s, Paint()..color = Colors.black.withValues(alpha: .42 * fade));
    c.saveLayer(Offset.zero & s, Paint()..color = Colors.white.withValues(alpha: fade));

    // Panneau.
    final board = RRect.fromRectAndRadius(
        Rect.fromCenter(center: Offset(cx, ry - 46), width: 150, height: 100),
        const Radius.circular(8));
    c.drawRRect(board, Paint()..color = Colors.white);
    c.drawRRect(
        board,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 3
          ..color = const Color(0xFF94A3B8));
    c.drawRect(
        Rect.fromCenter(center: Offset(cx, ry - 22), width: 56, height: 40),
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 3
          ..color = orange);

    // Ballon : une cloche jusqu'au cercle, puis la chute à travers le filet.
    final u = (t / .5).clamp(0.0, 1.0);
    final v = ((t - .5) / .22).clamp(0.0, 1.0);
    final p0 = Offset(cx - 180, s.height * .82), p1 = Offset(cx - 90, ry - 330), p2 = Offset(cx, ry - 8);
    var ball = p0 * ((1 - u) * (1 - u)) + p1 * (2 * u * (1 - u)) + p2 * (u * u);
    if (u >= 1) ball = Offset(cx, ry - 8 + v * v * 190);
    final ballFade = t < .68 ? 1.0 : (1 - (t - .68) / .08).clamp(0.0, 1.0);
    void drawBall() {
      if (ballFade <= 0) return;
      const r = 26.0;
      final paint = Paint()..color = orange.withValues(alpha: ballFade);
      final line = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.2
        ..color = const Color(0xFF7C2D12).withValues(alpha: ballFade);
      c.save();
      c.translate(ball.dx, ball.dy);
      c.rotate(-t * 7);
      c.drawCircle(Offset.zero, r, paint);
      c.drawCircle(Offset.zero, r, line);
      c.drawLine(const Offset(-r, 0), const Offset(r, 0), line);
      c.drawLine(const Offset(0, -r), const Offset(0, r), line);
      c.drawArc(Rect.fromCircle(center: const Offset(-r * 1.25, 0), radius: r), -.9, 1.8, false, line);
      c.drawArc(Rect.fromCircle(center: const Offset(r * 1.25, 0), radius: r), pi - .9, 1.8, false, line);
      c.restore();
    }

    drawBall();

    // Filet (il s'étire au passage du ballon) puis cercle, par-dessus le ballon.
    final stretch = 1 + .3 * sin(pi * v) * (t > .5 ? 1 : 0);
    final net = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2
      ..color = Colors.white.withValues(alpha: .9);
    const top = 44.0, bottom = 26.0, depth = 58.0;
    for (var i = 0; i <= 6; i++) {
      final a = -1 + i / 3; // de -1 à 1
      c.drawLine(Offset(cx + a * top, ry), Offset(cx + a * bottom, ry + depth * stretch), net);
    }
    for (var j = 1; j <= 3; j++) {
      final k = j / 3;
      final w = top + (bottom - top) * k;
      c.drawLine(Offset(cx - w, ry + depth * stretch * k), Offset(cx + w, ry + depth * stretch * k), net);
    }
    c.drawOval(
        Rect.fromCenter(center: Offset(cx, ry), width: 96, height: 16),
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 5
          ..color = orange);

    // « +2 pts » : il saute quand le ballon rentre.
    if (t > .5) {
      final k = ((t - .5) / .12).clamp(0.0, 1.0);
      final scale = k < 1 ? .3 + .95 * k : 1.25 - .25 * ((t - .62) / .08).clamp(0.0, 1.0);
      final tp = TextPainter(
          text: TextSpan(
              text: text,
              style: const TextStyle(
                  fontSize: 54,
                  fontWeight: FontWeight.w900,
                  color: Color(0xFFFACC15),
                  shadows: [Shadow(offset: Offset(0, 3), color: Color(0x73000000))])),
          textDirection: TextDirection.ltr)
        ..layout();
      c.save();
      c.translate(cx, ry + 150);
      c.scale(scale);
      tp.paint(c, Offset(-tp.width / 2, -tp.height / 2));
      c.restore();
    }
    c.restore();
  }

  @override
  bool shouldRepaint(_Shot o) => o.t != t || o.text != text;
}
