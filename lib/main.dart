import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';

import 'auth/auth_bloc.dart';
import 'auth/auth_event.dart';
import 'auth/auth_state.dart';
import 'data/api_service.dart';
import 'overlay_calculator.dart';
import 'services/secure_storage_service.dart';
import 'services/slot_detection_service.dart';
import 'ui/login_screen.dart';
import 'ui/lobby_screen.dart';
import 'app_branding.dart';
import 'ui/splash_screen.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  try {
    await dotenv.load(fileName: '.env');
  } catch (_) {}
  runApp(const ToolForecastApp());
  unawaited(SlotDetectionService.preloadTemplate());
}

@pragma('vm:entry-point')
void overlayMain() {
  WidgetsFlutterBinding.ensureInitialized();
  unawaited(_overlayBootstrap());
}

Future<void> _overlayBootstrap() async {
  await dotenv.load(fileName: '.env');
  runApp(
    const MaterialApp(
      debugShowCheckedModeBanner: false,
      home: OverlayCalculator(),
    ),
  );
}

class ToolForecastApp extends StatelessWidget {
  const ToolForecastApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MultiRepositoryProvider(
      providers: [
        RepositoryProvider<SecureStorageService>(
          create: (_) => SecureStorageService(),
        ),
        RepositoryProvider<ApiService>(
          create: (c) => ApiService(c.read<SecureStorageService>()),
        ),
      ],
      child: BlocProvider(
        create: (c) => AuthBloc(
          api: c.read<ApiService>(),
          storage: c.read<SecureStorageService>(),
        )..add(const AuthStarted()),
        child: MaterialApp(
          title: AppBranding.appTitle,
          debugShowCheckedModeBanner: false,
          theme: ThemeData(
            colorScheme: ColorScheme.fromSeed(
              seedColor: const Color(0xFF1976D2),
              brightness: Brightness.light,
            ),
            useMaterial3: true,
          ),
          home: const _AuthGate(),
        ),
      ),
    );
  }
}

class _AuthGate extends StatefulWidget {
  const _AuthGate();

  @override
  State<_AuthGate> createState() => _AuthGateState();
}

class _AuthGateState extends State<_AuthGate> {
  Timer? _splashWatchdog;

  @override
  void initState() {
    super.initState();
    // Tránh kẹt splash khi secure storage / cache treo.
    _splashWatchdog = Timer(const Duration(seconds: 5), () {
      if (!mounted) return;
      final bloc = context.read<AuthBloc>();
      if (bloc.state.status == AuthStatus.unknown) {
        bloc.add(const AuthBootstrapTimeout());
      }
    });
  }

  @override
  void dispose() {
    _splashWatchdog?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return BlocListener<AuthBloc, AuthState>(
      listenWhen: (p, c) => p.status != c.status && c.status != AuthStatus.unknown,
      listener: (_, __) => _splashWatchdog?.cancel(),
      child: BlocBuilder<AuthBloc, AuthState>(
        builder: (context, state) {
          if (state.status == AuthStatus.unknown) {
            return const SplashScreen();
          }
          if (state.status == AuthStatus.authenticated) {
            return const LobbyScreen();
          }
          return const LoginScreen();
        },
      ),
    );
  }
}
