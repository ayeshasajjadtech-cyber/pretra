import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'models.dart';

class LandscapeView extends StatefulWidget {
  const LandscapeView({super.key, required this.visual, required this.phase});

  final VisualState visual;
  final AppPhase phase;

  @override
  State<LandscapeView> createState() => _LandscapeViewState();
}

class _LandscapeViewState extends State<LandscapeView>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  double _lastTimeMs = 0;
  double _breathing = 0.5;
  double _pulse = 0.45;
  double _confidence = 0;
  bool _active = false;
  bool _stale = false;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(days: 1),
    )..repeat();
    _controller.addListener(_tick);
  }

  @override
  void dispose() {
    _controller
      ..removeListener(_tick)
      ..dispose();
    super.dispose();
  }

  void _tick() {
    final timeMs = _controller.value * 86400000.0;
    final dt = _lastTimeMs == 0 ? 16.0 : (timeMs - _lastTimeMs).clamp(1.0, 80.0).toDouble();
    _lastTimeMs = timeMs;
    final alpha = 1 - math.exp(-dt / 420);
    final visual = widget.visual;
    final targetBreathing = visual.breathing ?? 0.5;
    final targetPulse = visual.pulse ?? 0.45;
    final targetConfidence = (visual.confidence / 100).clamp(0.0, 1.0).toDouble();

    setState(() {
      _breathing += (targetBreathing - _breathing) * alpha;
      _pulse += (targetPulse - _pulse) * alpha;
      _confidence += (targetConfidence - _confidence) * alpha;
      _active = visual.active;
      _stale = visual.stale;
    });
  }

  @override
  Widget build(BuildContext context) {
    final timeMs = _controller.value * 86400000.0;
    return RepaintBoundary(
      child: CustomPaint(
        painter: LandscapePainter(
          timeMs: timeMs,
          breathing: _breathing,
          pulse: _pulse,
          confidence: _confidence,
          active: _active,
          stale: _stale,
          traces: widget.visual.traces,
        ),
        child: const SizedBox.expand(),
      ),
    );
  }
}

class LandscapePainter extends CustomPainter {
  LandscapePainter({
    required this.timeMs,
    required this.breathing,
    required this.pulse,
    required this.confidence,
    required this.active,
    required this.stale,
    required this.traces,
  });

  final double timeMs;
  final double breathing;
  final double pulse;
  final double confidence;
  final bool active;
  final bool stale;
  final TraceSet traces;

  static final _Scene _scene = _Scene.generate();

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final shortest = math.min(size.width, size.height);
    final time = timeMs / 1000;
    final intensity = active ? (0.35 + confidence * 0.65) : 0.18;
    final breath = breathing.clamp(0.0, 1.0).toDouble();
    final pulseValue = pulse.clamp(0.0, 1.0).toDouble();

    _paintSky(canvas, rect);
    _paintStars(canvas, size, time, intensity);
    _paintGlow(canvas, size, breath, intensity, shortest);
    _paintMist(canvas, size, time);
    _paintHills(canvas, size, breath);
    _paintAura(canvas, size, breath, intensity, shortest, time);
    _paintPulseRings(canvas, size, pulseValue, intensity, shortest, time);
    _paintMeadow(canvas, size);
    _paintTraces(canvas, size);
    _paintGrass(canvas, size, time, pulseValue);
    _paintFlowers(canvas, size, time, breath, intensity);
    _paintFireflies(canvas, size, time, intensity);
    _paintVignette(canvas, size);

    if (stale) {
      canvas.drawRect(
        rect,
        Paint()..color = const Color(0xFF071018).withValues(alpha: 0.28),
      );
    }
  }

  void _paintSky(Canvas canvas, Rect rect) {
    final paint = Paint()
      ..shader = const LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: <Color>[
          Color(0xFF050D18),
          Color(0xFF0B1D2C),
          Color(0xFF173746),
          Color(0xFF2B5360),
        ],
        stops: <double>[0, 0.42, 0.72, 1],
      ).createShader(rect);
    canvas.drawRect(rect, paint);
  }

  void _paintStars(Canvas canvas, Size size, double time, double intensity) {
    final paint = Paint();
    for (final star in _scene.stars) {
      final twinkle =
          0.55 + 0.45 * math.sin(time * star.speed + star.phase);
      final alpha = (star.alpha * twinkle * (0.35 + intensity * 0.65))
          .clamp(0.0, 1.0).toDouble();
      paint.color = Color(0xFFDDF4FF).withValues(alpha: alpha);
      canvas.drawCircle(
        Offset(star.x * size.width, star.y * size.height * 0.62),
        star.radius * (size.shortestSide / 900).clamp(0.6, 1.8).toDouble(),
        paint,
      );
    }
  }

  void _paintGlow(
    Canvas canvas,
    Size size,
    double breath,
    double intensity,
    double shortest,
  ) {
    final center = Offset(size.width * 0.72, size.height * 0.23);
    final radius = shortest * (0.12 + breath * 0.035);
    final rect = Rect.fromCircle(center: center, radius: radius * 3.4);
    final paint = Paint()
      ..shader = RadialGradient(
        colors: <Color>[
          const Color(0xFFFFE9B8).withValues(alpha: 0.72 * intensity),
          const Color(0xFFFFC978).withValues(alpha: 0.18 * intensity),
          Colors.transparent,
        ],
        stops: const <double>[0, 0.36, 1],
      ).createShader(rect);
    canvas.drawCircle(center, radius * 3.4, paint);
    canvas.drawCircle(
      center,
      radius,
      Paint()..color = const Color(0xFFFFF0C8).withValues(alpha: 0.82),
    );
  }

  void _paintMist(Canvas canvas, Size size, double time) {
    for (var i = 0; i < 3; i++) {
      final y = size.height * (0.52 + i * 0.055);
      final drift = math.sin(time * 0.05 + i) * size.width * 0.03;
      final rect = Rect.fromLTWH(
        -size.width * 0.2 + drift,
        y,
        size.width * 1.4,
        size.height * 0.06,
      );
      final paint = Paint()
        ..shader = LinearGradient(
          begin: Alignment.centerLeft,
          end: Alignment.centerRight,
          colors: <Color>[
            Colors.transparent,
            const Color(0xFFB7E7DE).withValues(alpha: 0.06 + i * 0.012),
            Colors.transparent,
          ],
        ).createShader(rect);
      canvas.drawRect(rect, paint);
    }
  }

  void _paintHills(Canvas canvas, Size size, double breath) {
    final w = size.width;
    final h = size.height;

    final back = Path()
      ..moveTo(0, h * 0.63)
      ..cubicTo(w * 0.16, h * 0.55, w * 0.31, h * 0.68, w * 0.48, h * 0.6)
      ..cubicTo(w * 0.67, h * 0.52, w * 0.82, h * 0.67, w, h * 0.59)
      ..lineTo(w, h)
      ..lineTo(0, h)
      ..close();
    canvas.drawPath(
      back,
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: <Color>[Color(0xFF214B4C), Color(0xFF102B30)],
        ).createShader(Rect.fromLTWH(0, h * 0.5, w, h * 0.5)),
    );

    final mid = Path()
      ..moveTo(0, h * 0.71)
      ..cubicTo(w * 0.14, h * 0.64, w * 0.28, h * 0.76, w * 0.46, h * 0.69)
      ..cubicTo(w * 0.63, h * 0.62, w * 0.78, h * 0.77, w, h * 0.68)
      ..lineTo(w, h)
      ..lineTo(0, h)
      ..close();
    canvas.drawPath(
      mid,
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: <Color>[Color(0xFF1B403B), Color(0xFF0C2425)],
        ).createShader(Rect.fromLTWH(0, h * 0.6, w, h * 0.4)),
    );

    final front = Path()
      ..moveTo(0, h * 0.8)
      ..cubicTo(
        w * 0.18,
        h * (0.76 - breath * 0.012),
        w * 0.34,
        h * 0.85,
        w * 0.52,
        h * 0.79,
      )
      ..cubicTo(w * 0.7, h * 0.73, w * 0.86, h * 0.84, w, h * 0.78)
      ..lineTo(w, h)
      ..lineTo(0, h)
      ..close();
    canvas.drawPath(
      front,
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: <Color>[Color(0xFF163A32), Color(0xFF071B1B)],
        ).createShader(Rect.fromLTWH(0, h * 0.7, w, h * 0.3)),
    );
  }

  void _paintAura(
    Canvas canvas,
    Size size,
    double breath,
    double intensity,
    double shortest,
    double time,
  ) {
    final center = Offset(size.width * 0.5, size.height * 0.68);
    final pulseBreath = 0.5 + 0.5 * math.sin(time / 2.8);
    final radius = shortest * (0.16 + breath * 0.2 + pulseBreath * 0.01);
    final rect = Rect.fromCircle(center: center, radius: radius * 2.2);
    final paint = Paint()
      ..shader = RadialGradient(
        colors: <Color>[
          const Color(0xFF78F0D4).withValues(alpha: 0.15 * intensity),
          const Color(0xFF3CC8B4).withValues(alpha: 0.07 * intensity),
          Colors.transparent,
        ],
      ).createShader(rect);
    canvas.drawCircle(center, radius * 2.2, paint);
  }

  void _paintPulseRings(
    Canvas canvas,
    Size size,
    double pulseValue,
    double intensity,
    double shortest,
    double time,
  ) {
    final center = Offset(size.width * 0.5, size.height * 0.68);
    final base = shortest * 0.16;
    final speed = 0.55 + pulseValue * 0.9;
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.1;
    for (var i = 0; i < 3; i++) {
      final phase = (time * speed + i / 3) % 1.0;
      final radius = base + phase * shortest * (0.24 + pulseValue * 0.08);
      paint.color = const Color(0xFF8CF5D9)
          .withValues(alpha: (1 - phase) * 0.22 * intensity);
      canvas.drawCircle(center, radius, paint);
    }
  }

  void _paintMeadow(Canvas canvas, Size size) {
    final rect = Rect.fromLTWH(0, size.height * 0.78, size.width, size.height);
    final paint = Paint()
      ..shader = const LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: <Color>[Color(0xFF12342D), Color(0xFF061616)],
      ).createShader(rect);
    canvas.drawRect(rect, paint);
  }

  void _paintTraces(Canvas canvas, Size size) {
    _drawTrace(
      canvas,
      size,
      traces.breathing,
      size.height * 0.79,
      size.height * 0.075,
      const Color(0xFF7CF5D8),
    );
    _drawTrace(
      canvas,
      size,
      traces.pulse,
      size.height * 0.89,
      size.height * 0.038,
      const Color(0xFFFFCF87),
    );
  }

  void _drawTrace(
    Canvas canvas,
    Size size,
    List<double> values,
    double y,
    double amplitude,
    Color color,
  ) {
    if (values.length < 2) return;
    final path = Path();
    final left = size.width * 0.08;
    final width = size.width * 0.84;
    for (var i = 0; i < values.length; i++) {
      final x = left + width * (i / (values.length - 1));
      final py = y - (values[i] - 0.5) * 2 * amplitude;
      if (i == 0) {
        path.moveTo(x, py);
      } else {
        path.lineTo(x, py);
      }
    }
    // Outer bloom glow matching neon aesthetic
    canvas.drawPath(
      path,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 4.0
        ..strokeCap = StrokeCap.round
        ..color = color.withValues(alpha: 0.22),
    );
    canvas.drawPath(
      path,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.6
        ..strokeCap = StrokeCap.round
        ..color = color.withValues(alpha: 0.85),
    );
  }

  void _paintGrass(Canvas canvas, Size size, double time, double pulseValue) {
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.2
      ..strokeCap = StrokeCap.round;
    for (final blade in _scene.grass) {
      final baseX = blade.x * size.width;
      final baseY = size.height * (0.82 + blade.y * 0.18);
      final height = blade.height * size.height * (0.1 + pulseValue * 0.04);
      final sway = math.sin(time * 0.9 + blade.phase + blade.x * 8) *
          (0.02 + pulseValue * 0.035);
      final tipX = baseX + sway * size.width + blade.lean * height;
      final tipY = baseY - height;
      final path = Path()
        ..moveTo(baseX, baseY)
        ..quadraticBezierTo(
          baseX + (tipX - baseX) * 0.35,
          baseY - height * 0.55,
          tipX,
          tipY,
        );
      paint.color = Color.lerp(
        const Color(0xFF0D3B2E),
        const Color(0xFF3AAE83),
        blade.tone,
      )!
          .withValues(alpha: 0.55);
      canvas.drawPath(path, paint);
    }
  }

  void _paintFlowers(
    Canvas canvas,
    Size size,
    double time,
    double breath,
    double intensity,
  ) {
    final bloom = (0.55 + breath * 0.55 + confidence * 0.18).clamp(0.5, 1.25).toDouble();
    for (final flower in _scene.flowers) {
      final x = flower.x * size.width;
      final y = size.height * (0.84 + flower.y * 0.14);
      final sway = math.sin(time * 0.8 + flower.phase) * 0.04;
      final stemHeight = size.height * flower.height * (0.09 + bloom * 0.035);
      final tip = Offset(x + sway * size.width, y - stemHeight);
      canvas.drawLine(
        Offset(x, y),
        tip,
        Paint()
          ..color = const Color(0xFF2A7A5F).withValues(alpha: 0.75)
          ..strokeWidth = 1.2,
      );

      final radius = size.shortestSide * flower.size * (0.006 + bloom * 0.005);
      final petals = 5 + flower.petals;
      final petalPaint = Paint()
        ..color = flower.color.withValues(alpha: 0.55 + intensity * 0.25);
      for (var i = 0; i < petals; i++) {
        final angle = i / petals * math.pi * 2 + flower.rotation;
        final center = tip +
            Offset(
              math.cos(angle) * radius * 0.85,
              math.sin(angle) * radius * 0.85,
            );
        canvas.save();
        canvas.translate(center.dx, center.dy);
        canvas.rotate(angle);
        canvas.drawOval(
          Rect.fromCenter(
            center: Offset.zero,
            width: radius * 1.5,
            height: radius * 0.9,
          ),
          petalPaint,
        );
        canvas.restore();
      }
      canvas.drawCircle(
        tip,
        radius * 0.5,
        Paint()..color = const Color(0xFFFFE6A8).withValues(alpha: 0.9),
      );
    }
  }

  void _paintFireflies(
    Canvas canvas,
    Size size,
    double time,
    double intensity,
  ) {
    for (final firefly in _scene.fireflies) {
      final x = (firefly.x +
              math.sin(time * firefly.speed + firefly.phase) * 0.035) *
          size.width;
      final y = (firefly.y +
              math.cos(time * firefly.speed * 0.8 + firefly.phase) * 0.025) *
          size.height;
      final alpha =
          (0.3 + 0.7 * (0.5 + 0.5 * math.sin(time * 2 + firefly.phase))) *
              intensity;
      final radius = size.shortestSide * 0.006;
      final rect = Rect.fromCircle(center: Offset(x, y), radius: radius * 5);
      canvas.drawCircle(
        Offset(x, y),
        radius * 5,
        Paint()
          ..shader = RadialGradient(
            colors: <Color>[
              const Color(0xFFFFF3B0).withValues(alpha: alpha * 0.55),
              Colors.transparent,
            ],
          ).createShader(rect),
      );
      canvas.drawCircle(
        Offset(x, y),
        radius,
        Paint()..color = const Color(0xFFFFF4BE).withValues(alpha: alpha),
      );
    }
  }

  void _paintVignette(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    canvas.drawRect(
      rect,
      Paint()
        ..shader = RadialGradient(
          center: const Alignment(0, 0.15),
          radius: 0.95,
          colors: <Color>[
            Colors.transparent,
            const Color(0xFF02070C).withValues(alpha: 0.42),
          ],
          stops: const <double>[0.55, 1],
        ).createShader(rect),
    );
  }

  @override
  bool shouldRepaint(covariant LandscapePainter oldDelegate) => true;
}

class _Star {
  const _Star({
    required this.x,
    required this.y,
    required this.radius,
    required this.alpha,
    required this.phase,
    required this.speed,
  });

  final double x;
  final double y;
  final double radius;
  final double alpha;
  final double phase;
  final double speed;
}

class _Firefly {
  const _Firefly({
    required this.x,
    required this.y,
    required this.phase,
    required this.speed,
  });

  final double x;
  final double y;
  final double phase;
  final double speed;
}

class _Grass {
  const _Grass({
    required this.x,
    required this.y,
    required this.height,
    required this.lean,
    required this.phase,
    required this.tone,
  });

  final double x;
  final double y;
  final double height;
  final double lean;
  final double phase;
  final double tone;
}

class _Flower {
  const _Flower({
    required this.x,
    required this.y,
    required this.height,
    required this.size,
    required this.rotation,
    required this.phase,
    required this.petals,
    required this.color,
  });

  final double x;
  final double y;
  final double height;
  final double size;
  final double rotation;
  final double phase;
  final int petals;
  final Color color;
}

class _Scene {
  const _Scene({
    required this.stars,
    required this.fireflies,
    required this.grass,
    required this.flowers,
  });

  final List<_Star> stars;
  final List<_Firefly> fireflies;
  final List<_Grass> grass;
  final List<_Flower> flowers;

  static _Scene generate() {
    final random = math.Random(0xB4EA7);
    final stars = List<_Star>.generate(90, (index) {
      return _Star(
        x: random.nextDouble(),
        y: random.nextDouble(),
        radius: 0.5 + random.nextDouble() * 1.7,
        alpha: 0.2 + random.nextDouble() * 0.65,
        phase: random.nextDouble() * math.pi * 2,
        speed: 0.3 + random.nextDouble() * 0.8,
      );
    });

    final fireflies = List<_Firefly>.generate(26, (index) {
      return _Firefly(
        x: 0.08 + random.nextDouble() * 0.84,
        y: 0.5 + random.nextDouble() * 0.4,
        phase: random.nextDouble() * math.pi * 2,
        speed: 0.25 + random.nextDouble() * 0.55,
      );
    });

    final grass = List<_Grass>.generate(190, (index) {
      return _Grass(
        x: random.nextDouble(),
        y: random.nextDouble(),
        height: 0.5 + random.nextDouble() * 1.5,
        lean: -0.35 + random.nextDouble() * 0.7,
        phase: random.nextDouble() * math.pi * 2,
        tone: random.nextDouble(),
      );
    });

    const flowerColors = <Color>[
      Color(0xFFF7B7D2),
      Color(0xFFB9A7FF),
      Color(0xFFFFD59A),
      Color(0xFF9CE7DA),
      Color(0xFFE6A8FF),
    ];

    final flowers = List<_Flower>.generate(30, (index) {
      return _Flower(
        x: 0.03 + random.nextDouble() * 0.94,
        y: random.nextDouble(),
        height: 0.6 + random.nextDouble() * 1.5,
        size: 0.7 + random.nextDouble() * 1.3,
        rotation: random.nextDouble() * math.pi * 2,
        phase: random.nextDouble() * math.pi * 2,
        petals: random.nextInt(3),
        color: flowerColors[random.nextInt(flowerColors.length)],
      );
    });

    return _Scene(
      stars: stars,
      fireflies: fireflies,
      grass: grass,
      flowers: flowers,
    );
  }
}
