import 'package:equatable/equatable.dart';

sealed class AuthEvent extends Equatable {
  const AuthEvent();

  @override
  List<Object?> get props => [];
}

final class AuthStarted extends AuthEvent {
  const AuthStarted();
}

/// Splash quá lâu (storage treo) → ép hiện màn đăng nhập.
final class AuthBootstrapTimeout extends AuthEvent {
  const AuthBootstrapTimeout();
}

final class AuthLoginSubmitted extends AuthEvent {
  const AuthLoginSubmitted({
    required this.username,
    required this.password,
    required this.rememberAccount,
  });

  final String username;
  final String password;
  final bool rememberAccount;

  @override
  List<Object?> get props => [username, password, rememberAccount];
}

final class AuthRegisterSubmitted extends AuthEvent {
  const AuthRegisterSubmitted({
    required this.username,
    required this.password,
    required this.phone,
    required this.managedByAdmin,
    required this.rememberAccount,
  });

  final String username;
  final String password;
  final String phone;
  /// Mã quản trị (vd. A2B9) — trường API `managedByAdmin`.
  final String managedByAdmin;
  final bool rememberAccount;

  @override
  List<Object?> get props =>
      [username, password, phone, managedByAdmin, rememberAccount];
}

final class AuthLogoutRequested extends AuthEvent {
  const AuthLogoutRequested();
}

/// Đồng bộ lại profile (số xu, …) từ secure storage — gọi khi app/ Home resume sau overlay.
final class AuthProfileSyncedFromStorage extends AuthEvent {
  const AuthProfileSyncedFromStorage();
}
