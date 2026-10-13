import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:tool_forecast/auth/auth_bloc.dart';
import 'package:tool_forecast/auth/auth_event.dart';
import 'package:tool_forecast/data/api_service.dart';
import 'package:tool_forecast/services/secure_storage_service.dart';
import 'package:tool_forecast/ui/lobby_screen.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    await dotenv.load(
      mergeWith: {
        'API_BASE_URL': 'https://example.com',
        'API_LOGIN_PATH': '/auth/login',
        'API_REGISTER_PATH': '/auth/register',
        'API_SUBTRACT_COINS_PATH': '/users/subtract-coins-for-action',
        'SUBTRACT_COINS_AMOUNT': '1',
        'SUBTRACT_COINS_ACTION': 'PLAY_GAME',
        'DEFAULT_MANAGED_BY_ADMIN': '',
      },
      isOptional: true,
    );
  });

  testWidgets('Lobby screen builds when authenticated',
      (WidgetTester tester) async {
    await tester.pumpWidget(
      MultiRepositoryProvider(
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
          child: const MaterialApp(home: LobbyScreen()),
        ),
      ),
    );
    await tester.pump(const Duration(seconds: 2));

    expect(find.textContaining('Chọn sảnh'), findsOneWidget);
  });
}
