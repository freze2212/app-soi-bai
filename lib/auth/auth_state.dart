import 'package:equatable/equatable.dart';

import '../models/session_user.dart';

enum AuthStatus { unknown, authenticated, unauthenticated }

final class AuthState extends Equatable {
  const AuthState({
    this.status = AuthStatus.unknown,
    this.busy = false,
    this.errorMessage,
    this.profile,
  });

  final AuthStatus status;
  final bool busy;
  final String? errorMessage;
  final SessionUser? profile;

  AuthState copyWith({
    AuthStatus? status,
    bool? busy,
    String? errorMessage,
    SessionUser? profile,
    bool clearError = false,
    bool clearProfile = false,
  }) {
    return AuthState(
      status: status ?? this.status,
      busy: busy ?? this.busy,
      errorMessage: clearError ? null : (errorMessage ?? this.errorMessage),
      profile: clearProfile ? null : (profile ?? this.profile),
    );
  }

  @override
  List<Object?> get props => [status, busy, errorMessage, profile];
}
