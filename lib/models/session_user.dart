import 'package:equatable/equatable.dart';

/// Thông tin user trả về sau đăng nhập / đăng ký (trường `user` trong JSON).
class SessionUser extends Equatable {
  const SessionUser({
    required this.username,
    required this.coins,
  });

  final String username;
  final int coins;

  SessionUser copyWith({String? username, int? coins}) {
    return SessionUser(
      username: username ?? this.username,
      coins: coins ?? this.coins,
    );
  }

  Map<String, dynamic> toJson() => {
        'username': username,
        'coins': coins,
      };

  factory SessionUser.fromJson(Map<String, dynamic> json) {
    final c = json['coins'];
    int coins = 0;
    if (c is int) {
      coins = c;
    } else if (c is num) {
      coins = c.toInt();
    }
    return SessionUser(
      username: json['username']?.toString() ?? '',
      coins: coins,
    );
  }

  @override
  List<Object?> get props => [username, coins];
}
