import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

/// Nền kiểu hacker: gradient đỏ **sáng** (không tối quá) + cột ký tự rơi từ trên xuống.
/// Đặt trong [Stack] (full screen), [Scaffold] đặt phía trên với `backgroundColor: transparent`.
class HackerMatrixBackdrop extends StatefulWidget {
  const HackerMatrixBackdrop({super.key});

  @override
  State<HackerMatrixBackdrop> createState() => _HackerMatrixBackdropState();
}

class _RainColumn {
  _RainColumn({
    required this.x,
    required this.headY,
    required this.speedPxPerSec,
    required this.cellHeight,
    required this.chars,
  });

  final double x;
  double headY;
  final double speedPxPerSec;
  final double cellHeight;
  final List<String> chars;
}

class _HackerMatrixBackdropState extends State<HackerMatrixBackdrop>
    with SingleTickerProviderStateMixin {
  late final Ticker _ticker;
  Duration _prev = Duration.zero;
  double _elapsedSec = 0;
  final _rnd = math.Random();
  List<_RainColumn>? _columns;
  Size _lastLayout = Size.zero;

  /// Ký tự an toàn (font hệ thống hiển thị ổn).
  static const _charset = r'01ABCDEF0123456789[]{}<>/|+*:;_@#%^&';

  @override
  void initState() {
    super.initState();
    _ticker = createTicker(_onTick)..start();
  }

  void _onTick(Duration elapsed) {
    final dt = _prev == Duration.zero
        ? 0.016
        : (elapsed - _prev).inMicroseconds / 1e6;
    _prev = elapsed;
    _elapsedSec = elapsed.inMilliseconds / 1000.0;
    if (!mounted || _columns == null || _lastLayout == Size.zero) return;
    setState(() {
      for (final c in _columns!) {
        c.headY += c.speedPxPerSec * dt;
        final streamH = c.chars.length * c.cellHeight;
        if (c.headY > _lastLayout.height + streamH) {
          c.headY = -streamH - _rnd.nextDouble() * 160;
          for (var i = 0; i < c.chars.length; i++) {
            c.chars[i] = _char();
          }
        }
      }
    });
  }

  String _char() => _charset[_rnd.nextInt(_charset.length)];

  void _ensureColumns(Size s) {
    if (s.isEmpty) return;
    if (_columns != null &&
        (s.width - _lastLayout.width).abs() < 6 &&
        (s.height - _lastLayout.height).abs() < 6) {
      return;
    }
    _lastLayout = s;
    const cellW = 17.0;
    final n = (s.width / cellW).floor().clamp(14, 34);
    final offsetX = (s.width - n * cellW) / 2;
    _columns = List.generate(n, (i) {
      final cellCount = 11 + _rnd.nextInt(7);
      return _RainColumn(
        x: offsetX + i * cellW + 2,
        headY: -_rnd.nextDouble() * s.height * 1.2,
        speedPxPerSec: 48 + _rnd.nextDouble() * 88,
        cellHeight: 15.5,
        chars: List.generate(cellCount, (_) => _char()),
      );
    });
  }

  @override
  void dispose() {
    _ticker.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final s = Size(constraints.maxWidth, constraints.maxHeight);
        _ensureColumns(s);
        if (_columns == null) return const SizedBox.shrink();
        return Stack(
          fit: StackFit.expand,
          children: [
            const _BackdropGradients(),
            IgnorePointer(
              child: CustomPaint(
                painter: _MatrixRainPainter(columns: _columns!),
                size: s,
              ),
            ),
            IgnorePointer(
              child: CustomPaint(
                painter: _HudRedNeonPainter(timeSec: _elapsedSec),
                size: s,
              ),
            ),
          ],
        );
      },
    );
  }
}

class _BackdropGradients extends StatelessWidget {
  const _BackdropGradients();

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: [
        const DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                Color(0xFF3D1A1E),
                Color(0xFF2E1518),
                Color(0xFF241016),
              ],
            ),
          ),
        ),
        DecoratedBox(
          decoration: BoxDecoration(
            gradient: RadialGradient(
              center: const Alignment(0.75, -0.85),
              radius: 1.25,
              colors: [
                const Color(0xFFE53935).withValues(alpha: 0.22),
                Colors.transparent,
              ],
            ),
          ),
        ),
        DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.center,
              colors: [
                const Color(0xFFFF8A80).withValues(alpha: 0.12),
                Colors.transparent,
              ],
            ),
          ),
        ),
        IgnorePointer(
          child: DecoratedBox(
            decoration: BoxDecoration(
              gradient: RadialGradient(
                center: Alignment.center,
                radius: 1.05,
                colors: [
                  Colors.transparent,
                  const Color(0xFF1A0A0C).withValues(alpha: 0.35),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}

/// Lớp HUD kiểu sci‑fi: khung octagon, bracket góc, lưới hex, gauge, sóng, mạch — **đỏ neon**.
class _HudRedNeonPainter extends CustomPainter {
  _HudRedNeonPainter({required this.timeSec});

  final double timeSec;

  static const _neon = Color(0xFFFF1744);
  static const _neonMid = Color(0xFFFF5252);
  static const _neonDim = Color(0xFFE53935);

  Path _octagonPath(Rect r, double cut) {
    final l = r.left;
    final t = r.top;
    final rgt = r.right;
    final bot = r.bottom;
    return Path()
      ..moveTo(l + cut, t)
      ..lineTo(rgt - cut, t)
      ..lineTo(rgt, t + cut)
      ..lineTo(rgt, bot - cut)
      ..lineTo(rgt - cut, bot)
      ..lineTo(l + cut, bot)
      ..lineTo(l, bot - cut)
      ..lineTo(l, t + cut)
      ..close();
  }

  void _strokeGlowPath(Canvas canvas, Path path, Color core, {double coreW = 1.2}) {
    for (var w = 8.0; w >= 2; w -= 2) {
      canvas.drawPath(
        path,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = w
          ..color = _neon.withValues(alpha: 0.04 + (10 - w) * 0.025)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 2.5),
      );
    }
    canvas.drawPath(
      path,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = coreW
        ..color = core,
    );
  }

  void _cornerBrackets(Canvas canvas, Size size, double inset) {
    const arm = 24.0;
    final w = size.width;
    final h = size.height;
    void bracket(Path path) => _strokeGlowPath(canvas, path, _neonMid, coreW: 1.0);

    bracket(Path()
      ..moveTo(inset, inset + arm)
      ..lineTo(inset, inset)
      ..lineTo(inset + arm, inset));
    bracket(Path()
      ..moveTo(w - inset - arm, inset)
      ..lineTo(w - inset, inset)
      ..lineTo(w - inset, inset + arm));
    bracket(Path()
      ..moveTo(inset, h - inset - arm)
      ..lineTo(inset, h - inset)
      ..lineTo(inset + arm, h - inset));
    bracket(Path()
      ..moveTo(w - inset - arm, h - inset)
      ..lineTo(w - inset, h - inset)
      ..lineTo(w - inset, h - inset - arm));
  }

  void _hexGrid(Canvas canvas, Size size) {
    final topH = size.height * 0.22;
    const r = 10.0;
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 0.8
      ..color = _neon.withValues(alpha: 0.14);
    var row = 0;
    for (var y = r + 4.0; y < topH; y += r * 1.65) {
      final offset = (row.isOdd) ? r * 0.9 : 0.0;
      for (var x = offset + 6.0; x < size.width - 6; x += r * 1.75) {
        final cx = x;
        final cy = y;
        final p = Path();
        for (var i = 0; i < 6; i++) {
          final a = (math.pi / 3) * i - math.pi / 6;
          final px = cx + r * math.cos(a);
          final py = cy + r * math.sin(a);
          if (i == 0) {
            p.moveTo(px, py);
          } else {
            p.lineTo(px, py);
          }
        }
        p.close();
        canvas.drawPath(p, paint);
      }
      row++;
    }
  }

  void _cornerGauge(
    Canvas canvas,
    Rect rect,
    double progress,
    String label,
  ) {
    final paintArc = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3
      ..strokeCap = StrokeCap.round
      ..color = _neonDim.withValues(alpha: 0.45);
    canvas.drawArc(rect, -math.pi * 0.85, math.pi * 1.1, false, paintArc);
    final paintProg = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3.5
      ..strokeCap = StrokeCap.round
      ..color = _neon;
    canvas.drawArc(
      rect,
      -math.pi * 0.85,
      math.pi * 1.1 * progress.clamp(0.0, 1.0),
      false,
      paintProg,
    );
    final tp = TextPainter(
      text: TextSpan(
        text: label,
        style: TextStyle(
          color: Colors.white.withValues(alpha: 0.85),
          fontSize: 11,
          fontWeight: FontWeight.w600,
          fontFamily: 'monospace',
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    tp.paint(
      canvas,
      Offset(
        rect.center.dx - tp.width / 2,
        rect.center.dy - tp.height / 2,
      ),
    );
  }

  void _waveformBottom(Canvas canvas, Size size) {
    final baseY = size.height * 0.88;
    final path = Path()..moveTo(0, baseY);
    for (var x = 0.0; x <= size.width; x += 5) {
      final y = baseY +
          14 * math.sin(timeSec * 2.4 + x * 0.018) +
          7 * math.sin(timeSec * 1.1 + x * 0.041);
      path.lineTo(x, y);
    }
    _strokeGlowPath(canvas, path, _neonMid.withValues(alpha: 0.9), coreW: 1.4);
  }

  void _circuitLines(Canvas canvas, Size size) {
    final p = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1
      ..color = _neon.withValues(alpha: 0.28);
    void line(Offset a, Offset b) {
      canvas.drawLine(a, b, p);
      canvas.drawCircle(a, 2.2, Paint()..color = _neonMid.withValues(alpha: 0.55));
      canvas.drawCircle(b, 2.2, Paint()..color = _neonMid.withValues(alpha: 0.55));
    }

    line(Offset(size.width * 0.08, size.height * 0.32),
        Offset(size.width * 0.22, size.height * 0.38));
    line(Offset(size.width * 0.78, size.height * 0.30),
        Offset(size.width * 0.92, size.height * 0.36));
    line(Offset(size.width * 0.12, size.height * 0.62),
        Offset(size.width * 0.28, size.height * 0.72));
    line(Offset(size.width * 0.72, size.height * 0.65),
        Offset(size.width * 0.88, size.height * 0.74));
  }

  void _scanLine(Canvas canvas, Size size) {
    final y = (timeSec * 42) % (size.height * 1.1) - size.height * 0.05;
    final rect = Rect.fromLTWH(0, y, size.width, 36);
    final g = Paint()
      ..shader = LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [
          Colors.transparent,
          _neon.withValues(alpha: 0.07),
          Colors.transparent,
        ],
      ).createShader(rect);
    canvas.drawRect(rect, g);
  }

  void _topBloom(Canvas canvas, Size size) {
    final rect = Rect.fromCenter(
      center: Offset(size.width * 0.5, -size.height * 0.02),
      width: size.width * 1.1,
      height: size.height * 0.45,
    );
    final paint = Paint()
      ..shader = RadialGradient(
        colors: [
          const Color(0xFFFF8A80).withValues(alpha: 0.18),
          Colors.transparent,
        ],
      ).createShader(rect);
    canvas.drawOval(rect, paint);
  }

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty) return;
    final inset = size.shortestSide * 0.045;
    final rect = Rect.fromLTWH(inset, inset, size.width - 2 * inset, size.height - 2 * inset);
    final cut = math.min(rect.width, rect.height) * 0.07;
    final outer = _octagonPath(rect, cut);
    _strokeGlowPath(canvas, outer, _neon);

    final innerRect = rect.deflate(math.min(rect.width, rect.height) * 0.028);
    final innerCut = math.min(innerRect.width, innerRect.height) * 0.06;
    _strokeGlowPath(
      canvas,
      _octagonPath(innerRect, innerCut),
      _neonMid.withValues(alpha: 0.75),
      coreW: 0.9,
    );

    _topBloom(canvas, size);
    _hexGrid(canvas, size);

    _cornerBrackets(canvas, size, inset * 0.65);

    const g = 52.0;
    Rect gaugeRect(double dx, double dy) => Rect.fromLTWH(dx, dy, g, g);
    _cornerGauge(
      canvas,
      gaugeRect(size.width * 0.06, size.height * 0.12),
      0.55 + 0.4 * math.sin(timeSec * 0.9),
      '${(48 + (math.sin(timeSec * 1.3) * 25).round()).clamp(20, 99)}%',
    );
    _cornerGauge(
      canvas,
      gaugeRect(size.width - size.width * 0.06 - g, size.height * 0.12),
      0.62 + 0.35 * math.cos(timeSec * 0.75),
      '${(62 + (math.cos(timeSec * 1.1) * 18).round()).clamp(30, 99)}%',
    );
    _cornerGauge(
      canvas,
      gaugeRect(size.width * 0.06, size.height * 0.78),
      0.48 + 0.45 * math.sin(timeSec * 1.05),
      '${(71 + (math.sin(timeSec * 0.85) * 12).round()).clamp(40, 99)}%',
    );
    _cornerGauge(
      canvas,
      gaugeRect(size.width - size.width * 0.06 - g, size.height * 0.78),
      0.58 + 0.38 * math.cos(timeSec * 0.95),
      '${(55 + (math.cos(timeSec * 1.2) * 22).round()).clamp(25, 99)}%',
    );

    _waveformBottom(canvas, size);
    _circuitLines(canvas, size);
    _scanLine(canvas, size);

    final deco = TextPainter(
      text: TextSpan(
        text: '01001110  11001001  00110101',
        style: TextStyle(
          color: _neon.withValues(alpha: 0.22),
          fontSize: 9,
          fontFamily: 'monospace',
          letterSpacing: 1.2,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    deco.paint(canvas, Offset(inset + 4, size.height * 0.26));
  }

  @override
  bool shouldRepaint(covariant _HudRedNeonPainter oldDelegate) =>
      oldDelegate.timeSec != timeSec;
}

class _MatrixRainPainter extends CustomPainter {
  _MatrixRainPainter({required this.columns});

  final List<_RainColumn> columns;

  static const _tail = Color(0xFF5D1018);
  static const _head = Color(0xFFFFF3E0);

  @override
  void paint(Canvas canvas, Size canvasSize) {
    for (final c in columns) {
      final n = c.chars.length;
      if (n == 0) continue;
      for (var i = 0; i < n; i++) {
        final py = c.headY + i * c.cellHeight;
        if (py < -20 || py > canvasSize.height + 4) continue;
        final t = n <= 1 ? 1.0 : i / (n - 1);
        final color = Color.lerp(
          _tail.withValues(alpha: 0.45),
          _head,
          Curves.easeOut.transform(t),
        )!;
        final tp = TextPainter(
          text: TextSpan(
            text: c.chars[i],
            style: TextStyle(
              color: color,
              fontSize: 12.5,
              height: 1,
              fontWeight: t > 0.85 ? FontWeight.w700 : FontWeight.w500,
              fontFamily: 'monospace',
            ),
          ),
          textDirection: TextDirection.ltr,
        )..layout();
        tp.paint(canvas, Offset(c.x, py));
      }
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => true;
}
