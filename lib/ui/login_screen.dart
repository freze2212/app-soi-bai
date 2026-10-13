import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../auth/auth_bloc.dart';
import '../auth/auth_event.dart';
import '../auth/auth_state.dart';
import '../services/secure_storage_service.dart';
import 'register_screen.dart';
import 'widgets/ai_soi_bcr_logo.dart';
import 'widgets/auth_hud.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _userCtrl = TextEditingController();
  final _passCtrl = TextEditingController();
  final _formKey = GlobalKey<FormState>();
  bool _obscure = true;
  bool _rememberAccount = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      unawaited(_loadSaved());
    });
  }

  Future<void> _loadSaved() async {
    final storage = context.read<SecureStorageService>();
    final (u, p) = await storage.readRememberedCredentials();
    if (!mounted) return;
    if (u != null) _userCtrl.text = u;
    if (p != null) _passCtrl.text = p;
    setState(() {
      _rememberAccount = u != null && p != null && u.isNotEmpty && p.isNotEmpty;
    });
  }

  @override
  void dispose() {
    _userCtrl.dispose();
    _passCtrl.dispose();
    super.dispose();
  }

  void _submit() {
    if (!_formKey.currentState!.validate()) return;
    context.read<AuthBloc>().add(
      AuthLoginSubmitted(
        username: _userCtrl.text,
        password: _passCtrl.text,
        rememberAccount: _rememberAccount,
      ),
    );
  }

  InputDecoration _modalFieldDecoration({
    required String label,
    required String hint,
    Widget? suffixIcon,
  }) {
    final border = OutlineInputBorder(
      borderRadius: BorderRadius.circular(2),
      borderSide: BorderSide(
        color: AuthHud.neonRed.withValues(alpha: 0.86),
        width: 1.15,
      ),
    );
    return InputDecoration(
      labelText: '$label:',
      hintText: hint,
      labelStyle: const TextStyle(
        fontFamily: 'Source Code Pro',
        color: AuthHud.neonRed,
        fontSize: 13.2,
        height: 1.0,
        fontWeight: FontWeight.w800,
      ),
      floatingLabelStyle: const TextStyle(
        fontFamily: 'Source Code Pro',
        color: Color(0xFFFF6565),
        fontSize: 13.2,
        height: 1.0,
        fontWeight: FontWeight.w800,
      ),
      hintStyle: const TextStyle(
        fontFamily: 'Source Code Pro',
        color: AuthHud.hintMaroon,
        fontSize: 16.0,
        height: 1.0,
        fontWeight: FontWeight.w400,
      ),
      filled: true,
      fillColor: AuthHud.fillDark,
      isDense: true,
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      border: border,
      enabledBorder: border,
      focusedBorder: border.copyWith(
        borderSide: const BorderSide(color: AuthHud.borderRed, width: 1.55),
      ),
      suffixIcon: suffixIcon,
    );
  }

  @override
  Widget build(BuildContext context) {
    return BlocListener<AuthBloc, AuthState>(
      listenWhen: (p, c) =>
          p.errorMessage != c.errorMessage && c.errorMessage != null,
      listener: (context, state) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(state.errorMessage!),
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
            margin: const EdgeInsets.all(16),
          ),
        );
      },
      child: AnnotatedRegion<SystemUiOverlayStyle>(
        value: SystemUiOverlayStyle.light,
        child: Scaffold(
          backgroundColor: Colors.transparent,
          body: Stack(
            fit: StackFit.expand,
            children: [
              Positioned.fill(
                child: Image.asset(
                  'assets/background-auth.png',
                  fit: BoxFit.cover,
                  alignment: Alignment.topCenter,
                  filterQuality: FilterQuality.high,
                ),
              ),
              SafeArea(
                child: Align(
                  alignment: Alignment.topCenter,
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 4,
                      vertical: 20,
                    ),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.start,
                      children: [
                        const SizedBox(height: 0),
                        const Padding(
                          padding: EdgeInsets.symmetric(horizontal: 12),
                          child: AiSoiBcrLogo(
                            fontSize: 50,
                            maxWidth: 520,
                            letterSpacing: 3.8,
                          ),
                        ),
                        const SizedBox(height: 24),
                        ConstrainedBox(
                          constraints: const BoxConstraints(maxWidth: 480),
                          child: AuthFramePanel(
                            padding: const EdgeInsets.fromLTRB(34, 34, 34, 26),
                            child: Form(
                              key: _formKey,
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: [
                                  const _LoginTitle(),
                                  const SizedBox(height: 14),
                                  Padding(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 14,
                                    ),
                                    child: TextFormField(
                                      controller: _userCtrl,
                                      textInputAction: TextInputAction.next,
                                      autocorrect: false,
                                      style: const TextStyle(
                                        color: Colors.white,
                                        fontSize: 18,
                                        fontWeight: FontWeight.w600,
                                      ),
                                      decoration: _modalFieldDecoration(
                                        label: 'TÀI KHOẢN',
                                        hint: 'Nhập tên đăng nhập',
                                      ),
                                      validator: (v) {
                                        if (v == null || v.trim().isEmpty) {
                                          return 'Nhập tài khoản';
                                        }
                                        return null;
                                      },
                                    ),
                                  ),
                                  const SizedBox(height: 10),
                                  Padding(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 14,
                                    ),
                                    child: TextFormField(
                                      controller: _passCtrl,
                                      obscureText: _obscure,
                                      textInputAction: TextInputAction.done,
                                      style: const TextStyle(
                                        color: Colors.white,
                                        fontSize: 18,
                                        fontWeight: FontWeight.w600,
                                      ),
                                      decoration: _modalFieldDecoration(
                                        label: 'MẬT KHẨU',
                                        hint: 'Nhập mật khẩu',
                                        suffixIcon: IconButton(
                                          onPressed: () => setState(
                                            () => _obscure = !_obscure,
                                          ),
                                          icon: Icon(
                                            _obscure
                                                ? Icons.visibility_off_outlined
                                                : Icons.visibility_outlined,
                                            color: const Color(0xFFFF8484),
                                            size: 20,
                                          ),
                                        ),
                                      ),
                                      validator: (v) {
                                        if (v == null || v.isEmpty) {
                                          return 'Nhập mật khẩu';
                                        }
                                        return null;
                                      },
                                    ),
                                  ),
                                  const SizedBox(height: 14),
                                  BlocBuilder<AuthBloc, AuthState>(
                                    buildWhen: (p, c) => p.busy != c.busy,
                                    builder: (context, state) {
                                      return Padding(
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 14,
                                        ),
                                        child: _LoginActionButton(
                                          label: '>ĐĂNG NHẬP NGAY<',
                                          busy: state.busy,
                                          onPressed: state.busy
                                              ? null
                                              : _submit,
                                        ),
                                      );
                                    },
                                  ),
                                  const SizedBox(height: 10),
                                  BlocBuilder<AuthBloc, AuthState>(
                                    buildWhen: (p, c) => p.busy != c.busy,
                                    builder: (context, state) {
                                      return Padding(
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 14,
                                        ),
                                        child: _RegisterPanel(
                                          enabled: !state.busy,
                                          onTap: () {
                                            Navigator.of(context).push(
                                              MaterialPageRoute<void>(
                                                builder: (_) =>
                                                    BlocProvider.value(
                                                      value: context
                                                          .read<AuthBloc>(),
                                                      child:
                                                          const RegisterScreen(),
                                                    ),
                                              ),
                                            );
                                          },
                                        ),
                                      );
                                    },
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(height: 14),
                        ConstrainedBox(
                          constraints: const BoxConstraints(maxWidth: 480),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 14),
                            child: Row(
                              children: const [
                                Expanded(
                                  child: _SocialButton(
                                    assetIcon: 'assets/icon-tele.png',
                                    label: 'Telegram',
                                    color: Color(0xFF2AABEE),
                                  ),
                                ),
                                SizedBox(width: 10),
                                Expanded(
                                  child: _SocialButton(
                                    assetIcon: 'assets/icon-fb.png',
                                    label: 'facebook',
                                    color: Color(0xFF2048D8),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _LoginActionButton extends StatelessWidget {
  const _LoginActionButton({
    required this.label,
    required this.busy,
    required this.onPressed,
  });

  final String label;
  final bool busy;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final enabled = onPressed != null && !busy;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: enabled ? onPressed : null,
        borderRadius: BorderRadius.circular(2),
        child: Ink(
          height: 44,
          decoration: BoxDecoration(
            gradient: enabled
                ? const LinearGradient(
                    begin: Alignment.centerLeft,
                    end: Alignment.centerRight,
                    colors: [Color(0xFFFDC500), Color(0xFFC96A00)],
                  )
                : null,
            color: enabled ? null : Colors.grey.shade700,
          ),
          child: Center(
            child: busy
                ? const SizedBox(
                    height: 20,
                    width: 20,
                    child: CircularProgressIndicator(
                      strokeWidth: 2.4,
                      color: Colors.white,
                    ),
                  )
                : Text(
                    label,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      fontFamily: 'Source Code Pro',
                      fontSize: 19.2,
                      height: 1.0,
                      letterSpacing: 0,
                      fontWeight: FontWeight.w600,
                      color: Colors.white,
                    ),
                  ),
          ),
        ),
      ),
    );
  }
}

class _LoginTitle extends StatelessWidget {
  const _LoginTitle();

  @override
  Widget build(BuildContext context) {
    const text = 'ĐĂNG NHẬP';
    const strokeColor = Color(0xFFFF1B1B);
    const baseStyle = TextStyle(
      fontFamily: 'Roboto',
      fontSize: 40,
      height: 1.0,
      letterSpacing: 0,
      fontWeight: FontWeight.w900,
    );

    return Stack(
      alignment: Alignment.center,
      children: [
        Text(
          text,
          textAlign: TextAlign.center,
          style: baseStyle.copyWith(
            foreground: Paint()
              ..style = PaintingStyle.stroke
              ..strokeWidth = 1.3
              ..strokeJoin = StrokeJoin.round
              ..color = strokeColor,
          ),
        ),
        Text(
          text,
          textAlign: TextAlign.center,
          style: baseStyle.copyWith(
            color: Colors.white,
            shadows: const [
              Shadow(color: strokeColor, offset: Offset(0, 0), blurRadius: 12),
            ],
          ),
        ),
      ],
    );
  }
}

class _RegisterPanel extends StatelessWidget {
  const _RegisterPanel({required this.enabled, required this.onTap});

  final bool enabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        border: Border.all(color: const Color(0xFFFF3B3B), width: 1),
        color: const Color(0x66A10000),
      ),
      child: Column(
        children: [
          const Text(
            'NGƯỜI DÙNG MỚI?',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontFamily: 'Source Code Pro',
              fontSize: 14.34,
              height: 1.0,
              letterSpacing: 0,
              fontWeight: FontWeight.w600,
              color: Colors.white,
            ),
          ),
          const SizedBox(height: 3),
          GestureDetector(
            onTap: enabled ? onTap : null,
            child: Text(
              '>>ĐĂNG KÝ TÀI KHOẢN<<',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontFamily: 'Source Code Pro',
                fontSize: 14.34,
                height: 1.0,
                letterSpacing: 0,
                fontWeight: FontWeight.w600,
                color: const Color(
                  0xFFFFF600,
                ).withValues(alpha: enabled ? 1 : 0.45),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _SocialButton extends StatelessWidget {
  const _SocialButton({
    required this.assetIcon,
    required this.label,
    required this.color,
  });

  final String assetIcon;
  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () {},
        borderRadius: BorderRadius.circular(24),
        child: Ink(
          height: 44,
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(24),
            boxShadow: [
              BoxShadow(
                color: color.withValues(alpha: 0.35),
                blurRadius: 10,
                offset: const Offset(0, 3),
              ),
            ],
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Image.asset(
                assetIcon,
                height: 22,
                width: 22,
                filterQuality: FilterQuality.high,
              ),
              const SizedBox(width: 8),
              Text(
                label,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 0.2,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
