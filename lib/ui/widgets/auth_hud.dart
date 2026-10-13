import 'package:flutter/material.dart';

/// Khung HUD + field / nút theo theme đỏ neon (login & đăng ký).
class AuthHud {
  AuthHud._();

  static const Color neonRed = Color(0xFFFF3131);
  static const Color borderRed = Color(0xFFFF0000);
  static const Color hintMaroon = Color(0xFF4A0000);
  static const Color fillDark = Color(0x99000000);
  static const Color linkYellow = Color(0xFFFFFF00);

  static const LinearGradient primaryButtonGradient = LinearGradient(
    colors: [Color(0xFFFF0000), Color(0xFFFF8C00)],
    begin: Alignment.centerLeft,
    end: Alignment.centerRight,
  );

  static InputDecoration fieldDecoration({
    required String labelUpper,
    String? hint,
    Widget? suffixIcon,
  }) {
    const radius = 6.0;
    final base = OutlineInputBorder(
      borderRadius: BorderRadius.circular(radius),
      borderSide: BorderSide(color: neonRed.withValues(alpha: 0.9), width: 1.2),
    );
    return InputDecoration(
      labelText: labelUpper,
      hintText: hint,
      suffixIcon: suffixIcon,
      floatingLabelBehavior: FloatingLabelBehavior.auto,
      labelStyle: const TextStyle(
        color: neonRed,
        fontSize: 11,
        fontWeight: FontWeight.w800,
        letterSpacing: 0.4,
      ),
      floatingLabelStyle: const TextStyle(
        color: Color(0xFFFF5555),
        fontSize: 11.5,
        fontWeight: FontWeight.w800,
        letterSpacing: 0.3,
      ),
      hintStyle: const TextStyle(
        color: hintMaroon,
        fontSize: 13,
        fontWeight: FontWeight.w500,
      ),
      filled: true,
      fillColor: fillDark,
      isDense: true,
      border: base,
      enabledBorder: base,
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(radius),
        borderSide: const BorderSide(color: borderRed, width: 1.65),
      ),
      errorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(radius),
        borderSide: BorderSide(color: Colors.red.shade400, width: 1.2),
      ),
      focusedErrorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(radius),
        borderSide: BorderSide(color: Colors.red.shade300, width: 1.4),
      ),
      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
    );
  }

  static const TextStyle inputTextStyle = TextStyle(
    color: Colors.white,
    fontSize: 15,
    fontWeight: FontWeight.w500,
  );
}

/// Tiêu đề trắng, viền đỏ (stroke) — dùng trong khung frame.
class AuthHudStrokedTitle extends StatelessWidget {
  const AuthHudStrokedTitle(
    this.text, {
    super.key,
    this.fontSize = 28,
  });

  final String text;
  final double fontSize;

  @override
  Widget build(BuildContext context) {
    final base = TextStyle(
      fontSize: fontSize,
      fontWeight: FontWeight.w800,
      letterSpacing: 0.35,
      height: 1.15,
    );
    return Stack(
      alignment: Alignment.center,
      clipBehavior: Clip.none,
      children: [
        Text(
          text,
          textAlign: TextAlign.center,
          style: base.copyWith(
            foreground: Paint()
              ..style = PaintingStyle.stroke
              ..strokeWidth = 3
              ..color = const Color(0xFFD32F2F),
          ),
        ),
        Text(
          text,
          textAlign: TextAlign.center,
          style: base.copyWith(color: Colors.white),
        ),
      ],
    );
  }
}

/// Khối tiêu đề + dòng phụ (dòng phụ trắng mờ, không viền).
class AuthHudTitleBlock extends StatelessWidget {
  const AuthHudTitleBlock({
    super.key,
    required this.title,
    required this.subtitle,
    this.titleFontSize = 28,
  });

  final String title;
  final String subtitle;
  final double titleFontSize;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        AuthHudStrokedTitle(title, fontSize: titleFontSize),
        const SizedBox(height: 8),
        Text(
          subtitle,
          textAlign: TextAlign.center,
          style: TextStyle(
            color: Colors.white.withValues(alpha: 0.78),
            fontSize: 13.5,
            height: 1.35,
            fontWeight: FontWeight.w500,
          ),
        ),
      ],
    );
  }
}

/// Nền [frame-auth.png] + vùng form bên trong (chiều cao theo tỉ lệ ảnh, không cắt form dài).
class AuthFramePanel extends StatelessWidget {
  const AuthFramePanel({
    super.key,
    required this.child,
    /// Padding lớn trái/phải để field không dính sát viền nét trong [frame-auth.png].
    this.padding = const EdgeInsets.fromLTRB(48, 28, 48, 24),
  });

  final Widget child;
  final EdgeInsets padding;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, c) {
        final w = c.maxWidth;
        return ClipRRect(
          borderRadius: BorderRadius.circular(4),
          child: Container(
            width: w,
            constraints: const BoxConstraints(minHeight: 340),
            decoration: const BoxDecoration(
              image: DecorationImage(
                image: AssetImage('assets/frame-auth.png'),
                fit: BoxFit.fill,
                filterQuality: FilterQuality.high,
              ),
            ),
            child: Padding(padding: padding, child: child),
          ),
        );
      },
    );
  }
}

class AuthHudGradientButton extends StatelessWidget {
  const AuthHudGradientButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.busy = false,
    this.height = 50,
  });

  final String label;
  final VoidCallback? onPressed;
  final bool busy;
  final double height;

  @override
  Widget build(BuildContext context) {
    final enabled = onPressed != null && !busy;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: enabled ? onPressed : null,
        borderRadius: BorderRadius.circular(6),
        child: Ink(
          height: height,
          decoration: BoxDecoration(
            gradient: enabled ? AuthHud.primaryButtonGradient : null,
            color: enabled ? null : Colors.grey.shade700,
            borderRadius: BorderRadius.circular(6),
            boxShadow: enabled
                ? [
                    BoxShadow(
                      color: const Color(0xFFFF0000).withValues(alpha: 0.45),
                      blurRadius: 14,
                      offset: const Offset(0, 4),
                    ),
                  ]
                : null,
          ),
          child: Center(
            child: busy
                ? const SizedBox(
                    height: 22,
                    width: 22,
                    child: CircularProgressIndicator(
                      strokeWidth: 2.5,
                      color: Colors.white,
                    ),
                  )
                : Text(
                    label,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 15,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 0.8,
                    ),
                  ),
          ),
        ),
      ),
    );
  }
}

/// Viền trắng + dòng phụ + link vàng (theo mockup).
class AuthHudLinkFooter extends StatelessWidget {
  const AuthHudLinkFooter({
    super.key,
    required this.line1,
    required this.linkText,
    required this.onLink,
    this.enabled = true,
  });

  final String line1;
  final String linkText;
  final VoidCallback onLink;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.white.withValues(alpha: 0.65)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            line1,
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w600,
              fontSize: 13,
              letterSpacing: 0.3,
            ),
          ),
          const SizedBox(height: 6),
          GestureDetector(
            onTap: enabled ? onLink : null,
            child: Text(
              linkText,
              textAlign: TextAlign.center,
              style: TextStyle(
                color: AuthHud.linkYellow.withValues(alpha: enabled ? 1 : 0.4),
                fontWeight: FontWeight.w700,
                fontSize: 14,
                letterSpacing: 0.4,
                decoration: TextDecoration.underline,
                decorationColor: AuthHud.linkYellow.withValues(
                  alpha: enabled ? 0.9 : 0.3,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
