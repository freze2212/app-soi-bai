import 'dart:math' as math;

import 'package:flutter/material.dart';

/// Logo chữ "A.I SOI BCR" — gradient + glow neon (thay ảnh logo-toolm1b).
class AiSoiBcrLogo extends StatefulWidget {
  const AiSoiBcrLogo({
    super.key,
    this.fontSize = 44,
    this.maxWidth = 520,
    this.letterSpacing = 3.2,
  });

  final double fontSize;
  final double maxWidth;
  final double letterSpacing;

  static const String _text = 'A.I SOI BCR';

  @override
  State<AiSoiBcrLogo> createState() => _AiSoiBcrLogoState();
}

class _AiSoiBcrLogoState extends State<AiSoiBcrLogo>
    with SingleTickerProviderStateMixin {
  late final AnimationController _pulse;

  @override
  void initState() {
    super.initState();
    _pulse = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2200),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _pulse.dispose();
    super.dispose();
  }

  TextStyle _baseStyle(double fontSize, {Color? color, List<Shadow>? shadows}) {
    return TextStyle(
      fontSize: fontSize,
      fontWeight: FontWeight.w900,
      letterSpacing: widget.letterSpacing,
      height: 1.05,
      color: color,
      shadows: shadows,
    );
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final maxW = math.min(
          widget.maxWidth,
          constraints.maxWidth.isFinite ? constraints.maxWidth : widget.maxWidth,
        );
        return ConstrainedBox(
          constraints: BoxConstraints(maxWidth: maxW),
          child: FittedBox(
            fit: BoxFit.scaleDown,
            child: AnimatedBuilder(
              animation: _pulse,
              builder: (context, _) {
                final t = 0.65 + 0.35 * math.sin(_pulse.value * math.pi * 2);
                return _LogoLayers(
                  text: AiSoiBcrLogo._text,
                  fontSize: widget.fontSize,
                  letterSpacing: widget.letterSpacing,
                  pulse: t,
                  baseStyle: _baseStyle,
                );
              },
            ),
          ),
        );
      },
    );
  }
}

class _LogoLayers extends StatelessWidget {
  const _LogoLayers({
    required this.text,
    required this.fontSize,
    required this.letterSpacing,
    required this.pulse,
    required this.baseStyle,
  });

  final String text;
  final double fontSize;
  final double letterSpacing;
  final double pulse;
  final TextStyle Function(double fontSize, {Color? color, List<Shadow>? shadows})
      baseStyle;

  @override
  Widget build(BuildContext context) {
    final glowOuter = (22 * pulse).clamp(14.0, 28.0);
    final glowMid = (14 * pulse).clamp(8.0, 18.0);

    return Stack(
      alignment: Alignment.center,
      clipBehavior: Clip.none,
      children: [
        Text(
          text,
          textAlign: TextAlign.center,
          style: baseStyle(
            fontSize,
            color: const Color(0xFF00E5FF).withValues(alpha: 0.35 * pulse),
            shadows: [
              Shadow(
                color: const Color(0xFF00E5FF).withValues(alpha: 0.55),
                blurRadius: glowOuter * 1.4,
              ),
              Shadow(
                color: const Color(0xFFFF0000).withValues(alpha: 0.45),
                blurRadius: glowOuter,
              ),
            ],
          ),
        ),
        Text(
          text,
          textAlign: TextAlign.center,
          style: baseStyle(
            fontSize,
            color: const Color(0xFFFF3131).withValues(alpha: 0.5),
            shadows: [
              Shadow(
                color: const Color(0xFFFF8C00).withValues(alpha: 0.7),
                blurRadius: glowMid,
              ),
            ],
          ),
        ),
        ShaderMask(
          blendMode: BlendMode.srcIn,
          shaderCallback: (bounds) => const LinearGradient(
            colors: [
              Color(0xFFFFF8E1),
              Color(0xFFFFE082),
              Color(0xFFFF5252),
              Color(0xFFFF8C00),
            ],
            stops: [0.0, 0.35, 0.72, 1.0],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ).createShader(bounds),
          child: Text(
            text,
            textAlign: TextAlign.center,
            style: baseStyle(
              fontSize,
              color: Colors.white,
              shadows: [
                Shadow(
                  color: Colors.white.withValues(alpha: 0.85 * pulse),
                  blurRadius: 6,
                ),
                Shadow(
                  color: const Color(0xFFFF0000).withValues(alpha: 0.35),
                  blurRadius: 2,
                  offset: const Offset(0, 1),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}
