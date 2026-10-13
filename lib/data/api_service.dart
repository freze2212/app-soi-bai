import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:http/http.dart' as http;

import '../models/session_user.dart';
import '../services/secure_storage_service.dart';

/// Kết quả đăng nhập / đăng ký: [token], [user] (nếu API trả về) hoặc [errorMessage].
class AuthHttpResult {
  const AuthHttpResult._({this.token, this.errorMessage, this.user});

  const AuthHttpResult.ok(String token, {SessionUser? user})
      : this._(token: token, errorMessage: null, user: user);

  const AuthHttpResult.fail(String message)
      : this._(token: null, errorMessage: message, user: null);

  final String? token;
  final String? errorMessage;
  final SessionUser? user;

  bool get isOk => token != null && token!.isNotEmpty;
}

/// Gọi REST API theo biến trong `.env`.
class ApiService {
  ApiService(this._storage);

  final SecureStorageService _storage;

  /// Giới hạn thời gian chờ (tránh treo lâu khi DNS/mạng lỗi).
  static Duration get _requestTimeout {
    final s = int.tryParse(dotenv.env['API_REQUEST_TIMEOUT_SECONDS'] ?? '15');
    return Duration(seconds: (s ?? 15).clamp(5, 120));
  }

  /// Gốc HTTPS, **không** có dấu `/` cuối (vd: `https://api.robotmm88.com`).
  String get _origin {
    var o = (dotenv.env['API_BASE_URL'] ?? 'https://api.robotmm88.com').trim();
    while (o.endsWith('/')) {
      o = o.substring(0, o.length - 1);
    }
    return o;
  }

  /// Tiền tố chung trước `/auth/...` nếu backend đặt API sau `/api` (để trống nếu không dùng).
  /// Ví dụ: `/api` → gọi `https://host/api/auth/login`.
  String get _pathPrefix {
    var p = (dotenv.env['API_PATH_PREFIX'] ?? '').trim();
    if (p.isEmpty) return '';
    if (!p.startsWith('/')) p = '/$p';
    while (p.endsWith('/')) {
      p = p.substring(0, p.length - 1);
    }
    return p;
  }

  Uri _uri(String path) {
    var p = path.trim();
    if (p.isEmpty) p = '/';
    if (!p.startsWith('/')) p = '/$p';
    return Uri.parse('$_origin$_pathPrefix$p');
  }

  String _networkErrorMessage(Object e) {
    if (e is SocketException) {
      return 'Không kết nối được máy chủ. Kiểm tra Wi‑Fi/dữ liệu di động và '
          'DNS (lỗi: ${e.message}).';
    }
    if (e is TimeoutException) {
      return 'Hết thời gian chờ (${_requestTimeout.inSeconds}s). Mạng chậm hoặc máy chủ không phản hồi.';
    }
    final msg = e.toString();
    if (msg.contains('Failed host lookup') || msg.contains('SocketException')) {
      return 'Không phân giải được tên miền API. Kiểm tra mạng hoặc địa chỉ API_BASE_URL trong .env.';
    }
    return 'Lỗi mạng: $e';
  }

  String? _parseTokenFromBody(String body) {
    try {
      final decoded = jsonDecode(body);
      if (decoded is Map<String, dynamic>) {
        final t = decoded['token'] ??
            decoded['accessToken'] ??
            decoded['access_token'];
        if (t != null) return t.toString();
        final data = decoded['data'];
        if (data is Map<String, dynamic>) {
          final t2 = data['token'] ?? data['accessToken'];
          if (t2 != null) return t2.toString();
        }
      }
    } catch (_) {}
    return null;
  }

  SessionUser? _parseUserFromBody(String body) {
    try {
      final decoded = jsonDecode(body);
      if (decoded is! Map<String, dynamic>) return null;
      final u = decoded['user'];
      if (u is Map<String, dynamic>) {
        return SessionUser.fromJson(u);
      }
    } catch (_) {}
    return null;
  }

  /// Phản hồi trừ xu thành công: có thể là user phẳng hoặc lồng `user`.
  int? _parseCoinsFromSubtractBody(String body) {
    try {
      final decoded = jsonDecode(body);
      if (decoded is! Map<String, dynamic>) return null;
      final c0 = decoded['coins'];
      if (c0 is int) return c0;
      if (c0 is num) return c0.toInt();
      final u = decoded['user'];
      if (u is Map<String, dynamic>) {
        final c = u['coins'];
        if (c is int) return c;
        if (c is num) return c.toInt();
      }
    } catch (_) {}
    return null;
  }

  String? _extractApiMessageField(String body) {
    try {
      final d = jsonDecode(body);
      if (d is Map && d['message'] != null) {
        return d['message'].toString();
      }
    } catch (_) {}
    return null;
  }

  String _friendlySubtractMessage(int statusCode, String body) {
    final api = _extractApiMessageField(body);
    if (api != null && api.isNotEmpty) {
      return api;
    }
    switch (statusCode) {
      case 400:
        return 'Không thể trừ xu — dữ liệu không hợp lệ hoặc số xu không đủ.';
      case 401:
        return 'Phiên đăng nhập hết hạn. Vui lòng mở app và đăng nhập lại.';
      case 404:
        return 'Không tìm thấy tài khoản trên máy chủ.';
      default:
        return 'Không thể cập nhật số xu (mã $statusCode).';
    }
  }

  Future<SessionUser> _resolveProfileForCoinsUpdate(int coins) async {
    final cur = await _storage.readSessionUser();
    final (savedU, _) = await _storage.readRememberedCredentials();
    final name = (cur?.username ?? savedU ?? '').trim();
    return SessionUser(username: name.isEmpty ? '—' : name, coins: coins);
  }

  Future<AuthHttpResult> login({
    required String username,
    required String password,
  }) async {
    final path = dotenv.env['API_LOGIN_PATH'] ?? '/auth/login';
    try {
      final res = await http
          .post(
            _uri(path),
            headers: const {
              'Content-Type': 'application/json',
              'accept': '*/*',
            },
            body: jsonEncode({'username': username, 'password': password}),
          )
          .timeout(_requestTimeout);
      if (res.statusCode != 200 && res.statusCode != 201) {
        debugPrint('login ${res.statusCode}: ${res.body}');
        return const AuthHttpResult.fail(
          'Đăng nhập thất bại. Kiểm tra tài khoản hoặc mật khẩu.',
        );
      }
      final token = _parseTokenFromBody(res.body);
      if (token == null || token.isEmpty) {
        return const AuthHttpResult.fail(
          'Máy chủ không trả token. Liên hệ quản trị API.',
        );
      }
      final user = _parseUserFromBody(res.body);
      return AuthHttpResult.ok(token, user: user);
    } on TimeoutException catch (e) {
      return AuthHttpResult.fail(_networkErrorMessage(e));
    } on SocketException catch (e) {
      return AuthHttpResult.fail(_networkErrorMessage(e));
    } on http.ClientException catch (e) {
      return AuthHttpResult.fail(_networkErrorMessage(e));
    } catch (e) {
      debugPrint('login unexpected: $e');
      return AuthHttpResult.fail(_networkErrorMessage(e));
    }
  }

  Future<AuthHttpResult> register({
    required String username,
    required String password,
    required String phone,
    required String managedByAdmin,
  }) async {
    final path = dotenv.env['API_REGISTER_PATH'] ?? '/auth/register';
    try {
      final res = await http
          .post(
            _uri(path),
            headers: const {
              'Content-Type': 'application/json',
              'accept': '*/*',
            },
            body: jsonEncode({
              'username': username,
              'password': password,
              'phone': phone,
              'managedByAdmin': managedByAdmin,
            }),
          )
          .timeout(_requestTimeout);
      if (res.statusCode != 200 && res.statusCode != 201) {
        debugPrint('register ${res.statusCode}: ${res.body}');
        return const AuthHttpResult.fail(
          'Đăng ký thất bại. Kiểm tra dữ liệu hoặc thử lại sau.',
        );
      }
      final token = _parseTokenFromBody(res.body);
      if (token != null && token.isNotEmpty) {
        final user = _parseUserFromBody(res.body);
        return AuthHttpResult.ok(token, user: user);
      }
      // Một số API chỉ trả 201 không có token — đăng nhập lại.
      return login(username: username, password: password);
    } on TimeoutException catch (e) {
      return AuthHttpResult.fail(_networkErrorMessage(e));
    } on SocketException catch (e) {
      return AuthHttpResult.fail(_networkErrorMessage(e));
    } on http.ClientException catch (e) {
      return AuthHttpResult.fail(_networkErrorMessage(e));
    } catch (e) {
      debugPrint('register unexpected: $e');
      return AuthHttpResult.fail(_networkErrorMessage(e));
    }
  }

  /// Trừ xu qua API. [amount] / [action] mặc định lấy từ `.env`.
  /// Trả `true` khi thành công và đã cập nhật profile local (nếu có).
  Future<bool> subtractCoins({int? amount, String? action}) async {
    final token = await _storage.readToken();
    if (token == null || token.isEmpty) {
      debugPrint('subtractCoins: chưa có token');
      await _storage.setPendingHomeMessage(
        'Chưa đăng nhập — không thể trừ xu. Mở app và đăng nhập trước.',
      );
      return false;
    }
    final path =
        dotenv.env['API_SUBTRACT_COINS_PATH'] ?? '/users/subtract-coins-for-action';
    final deduct = amount ??
        int.tryParse(dotenv.env['SUBTRACT_COINS_AMOUNT'] ?? '1') ??
        1;
    final act = action ?? dotenv.env['SUBTRACT_COINS_ACTION'] ?? 'PLAY_GAME';
    try {
      final res = await http
          .post(
            _uri(path),
            headers: {
              'Content-Type': 'application/json',
              'accept': '*/*',
              'Authorization': 'Bearer $token',
            },
            body: jsonEncode({'amount': deduct, 'action': act}),
          )
          .timeout(_requestTimeout);
      final success = res.statusCode >= 200 && res.statusCode < 300;
      if (success) {
        var newCoins = _parseCoinsFromSubtractBody(res.body);
        if (newCoins == null) {
          final cur = await _storage.readSessionUser();
          if (cur != null) {
            newCoins = (cur.coins - deduct).clamp(0, 0x7fffffff);
          }
        }
        if (newCoins != null) {
          final profile = await _resolveProfileForCoinsUpdate(newCoins);
          await _storage.saveSessionUser(profile);
        }
        return true;
      }
      debugPrint('subtractCoins ${res.statusCode}: ${res.body}');
      await _storage.setPendingHomeMessage(
        _friendlySubtractMessage(res.statusCode, res.body),
      );
      return false;
    } on TimeoutException catch (e) {
      await _storage.setPendingHomeMessage(_networkErrorMessage(e));
      return false;
    } on SocketException catch (e) {
      await _storage.setPendingHomeMessage(_networkErrorMessage(e));
      return false;
    } on http.ClientException catch (e) {
      await _storage.setPendingHomeMessage(_networkErrorMessage(e));
      return false;
    } catch (e, st) {
      debugPrint('subtractCoins: $e\n$st');
      await _storage.setPendingHomeMessage(
        'Đã xảy ra lỗi khi trừ xu. Mở app để xem chi tiết.',
      );
      return false;
    }
  }

  /// Mỗi lần overlay vào vùng bàn và hiện lá — trừ 1 xu (cấu hình `.env`).
  Future<bool> subtractCoinsForOverlayReveal() {
    final amount = int.tryParse(
          dotenv.env['SUBTRACT_COINS_OVERLAY_AMOUNT'] ??
              dotenv.env['SUBTRACT_COINS_AMOUNT'] ??
              '1',
        ) ??
        1;
    final action = dotenv.env['SUBTRACT_COINS_OVERLAY_ACTION'] ??
        dotenv.env['SUBTRACT_COINS_ACTION'] ??
        'SOI_BCR_REVEAL';
    return subtractCoins(amount: amount, action: action);
  }

  /// Gọi sau khi tính toán xong; cần Bearer token đã lưu.
  Future<void> subtractCoinsForAction() async {
    await subtractCoins();
  }
}
