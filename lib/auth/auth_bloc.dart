import 'package:flutter_bloc/flutter_bloc.dart';

import '../data/api_service.dart';
import '../models/session_user.dart';
import '../services/secure_storage_service.dart';
import 'auth_event.dart';
import 'auth_state.dart';

class AuthBloc extends Bloc<AuthEvent, AuthState> {
  AuthBloc({
    required ApiService api,
    required SecureStorageService storage,
  })  : _api = api,
        _storage = storage,
        super(const AuthState()) {
    on<AuthStarted>(_onStarted);
    on<AuthBootstrapTimeout>(_onBootstrapTimeout);
    on<AuthLoginSubmitted>(_onLogin);
    on<AuthRegisterSubmitted>(_onRegister);
    on<AuthLogoutRequested>(_onLogout);
    on<AuthProfileSyncedFromStorage>(_onProfileSyncedFromStorage);
  }

  final ApiService _api;
  final SecureStorageService _storage;

  Future<void> _onStarted(AuthStarted event, Emitter<AuthState> emit) async {
    try {
      final results = await Future.wait<Object?>([
        _storage.readToken(),
        _storage.readSessionUser(),
      ]);
      final token = results[0] as String?;
      final profile = results[1] as SessionUser?;
      if (token != null && token.isNotEmpty) {
        emit(state.copyWith(
          status: AuthStatus.authenticated,
          profile: profile,
          clearError: true,
        ));
        return;
      }
    } catch (_) {}
    emit(state.copyWith(
      status: AuthStatus.unauthenticated,
      clearError: true,
      clearProfile: true,
    ));
  }

  Future<void> _onBootstrapTimeout(
    AuthBootstrapTimeout event,
    Emitter<AuthState> emit,
  ) async {
    if (state.status != AuthStatus.unknown) return;
    emit(state.copyWith(
      status: AuthStatus.unauthenticated,
      clearError: true,
      clearProfile: true,
    ));
  }

  Future<void> _onLogin(
    AuthLoginSubmitted event,
    Emitter<AuthState> emit,
  ) async {
    emit(state.copyWith(busy: true, clearError: true));
    final r = await _api.login(
      username: event.username.trim(),
      password: event.password,
    );
    if (!r.isOk) {
      emit(state.copyWith(
        busy: false,
        status: AuthStatus.unauthenticated,
        errorMessage: r.errorMessage ??
            'Đăng nhập thất bại. Kiểm tra tài khoản hoặc mật khẩu.',
      ));
      return;
    }
    await _storage.writeToken(r.token!);
    final profile = r.user ??
        SessionUser(username: event.username.trim(), coins: 0);
    await _storage.saveSessionUser(profile);
    if (event.rememberAccount) {
      await _storage.saveRememberedCredentials(
        username: event.username.trim(),
        password: event.password,
      );
    } else {
      await _storage.clearRememberedCredentials();
    }
    emit(state.copyWith(
      busy: false,
      status: AuthStatus.authenticated,
      profile: profile,
      clearError: true,
    ));
  }

  Future<void> _onRegister(
    AuthRegisterSubmitted event,
    Emitter<AuthState> emit,
  ) async {
    emit(state.copyWith(busy: true, clearError: true));
    final r = await _api.register(
      username: event.username.trim(),
      password: event.password,
      phone: event.phone.trim(),
      managedByAdmin: event.managedByAdmin.trim(),
    );
    if (!r.isOk) {
      emit(state.copyWith(
        busy: false,
        status: AuthStatus.unauthenticated,
        errorMessage: r.errorMessage ??
            'Đăng ký thất bại. Kiểm tra dữ liệu hoặc thử lại sau.',
      ));
      return;
    }
    await _storage.writeToken(r.token!);
    final profile = r.user ??
        SessionUser(username: event.username.trim(), coins: 0);
    await _storage.saveSessionUser(profile);
    if (event.rememberAccount) {
      await _storage.saveRememberedCredentials(
        username: event.username.trim(),
        password: event.password,
      );
    } else {
      await _storage.clearRememberedCredentials();
    }
    emit(state.copyWith(
      busy: false,
      status: AuthStatus.authenticated,
      profile: profile,
      clearError: true,
    ));
  }

  Future<void> _onLogout(
    AuthLogoutRequested event,
    Emitter<AuthState> emit,
  ) async {
    await _storage.clearSession();
    emit(state.copyWith(
      status: AuthStatus.unauthenticated,
      clearError: true,
      clearProfile: true,
    ));
  }

  Future<void> _onProfileSyncedFromStorage(
    AuthProfileSyncedFromStorage event,
    Emitter<AuthState> emit,
  ) async {
    if (state.status != AuthStatus.authenticated) return;
    final profile = await _storage.readSessionUser();
    emit(state.copyWith(profile: profile));
  }
}
