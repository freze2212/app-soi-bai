import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../models/session_user.dart';

/// Lưu token, profile hiển thị và (tuỳ chọn) tài khoản để điền lại màn đăng nhập.
class SecureStorageService {
  SecureStorageService({FlutterSecureStorage? storage})
      : _storage = storage ??
            const FlutterSecureStorage(
              aOptions: AndroidOptions(
                encryptedSharedPreferences: true,
                resetOnError: true,
              ),
            );

  final FlutterSecureStorage _storage;

  static const _readTimeout = Duration(seconds: 4);

  static const _kToken = 'auth_token';
  static const _kSessionUserJson = 'session_user_json';
  static const _kUsername = 'saved_username';
  static const _kPassword = 'saved_password';
  /// Tin nhắn từ overlay (vd lỗi trừ xu) — Home đọc và hiển thị rồi xóa.
  static const _kPendingHomeMessage = 'pending_home_message';

  Future<T?> _readSafe<T>(Future<T?> Function() read) async {
    try {
      return await read().timeout(_readTimeout);
    } catch (_) {
      return null;
    }
  }

  Future<String?> readToken() => _readSafe(() => _storage.read(key: _kToken));

  Future<void> writeToken(String token) =>
      _storage.write(key: _kToken, value: token);

  Future<void> deleteToken() => _storage.delete(key: _kToken);

  Future<void> saveSessionUser(SessionUser user) async {
    await _storage.write(
      key: _kSessionUserJson,
      value: jsonEncode(user.toJson()),
    );
  }

  Future<SessionUser?> readSessionUser() async {
    final raw = await _readSafe(() => _storage.read(key: _kSessionUserJson));
    if (raw == null || raw.isEmpty) return null;
    try {
      final m = jsonDecode(raw);
      if (m is Map<String, dynamic>) {
        return SessionUser.fromJson(m);
      }
    } catch (_) {}
    return null;
  }

  Future<void> deleteSessionUser() => _storage.delete(key: _kSessionUserJson);

  Future<void> saveRememberedCredentials({
    required String username,
    required String password,
  }) async {
    await _storage.write(key: _kUsername, value: username);
    await _storage.write(key: _kPassword, value: password);
  }

  Future<(String?, String?)> readRememberedCredentials() async {
    final u = await _readSafe(() => _storage.read(key: _kUsername));
    final p = await _readSafe(() => _storage.read(key: _kPassword));
    return (u, p);
  }

  Future<void> clearRememberedCredentials() async {
    await _storage.delete(key: _kUsername);
    await _storage.delete(key: _kPassword);
  }

  Future<void> setPendingHomeMessage(String message) async {
    if (message.isEmpty) return;
    await _storage.write(key: _kPendingHomeMessage, value: message);
  }

  /// Đọc và xóa — chỉ hiển thị một lần trên Home.
  Future<String?> takePendingHomeMessage() async {
    final v = await _storage.read(key: _kPendingHomeMessage);
    if (v != null && v.isNotEmpty) {
      await _storage.delete(key: _kPendingHomeMessage);
      return v;
    }
    return null;
  }

  /// Xóa phiên đăng nhập (token + profile). Giữ tài khoản/mật khẩu đã nhớ (nếu có).
  Future<void> clearSession() async {
    await deleteToken();
    await deleteSessionUser();
  }
}
