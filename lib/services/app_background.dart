import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Android: đưa activity xuống nền (tương đương nút Home). iOS/web: không làm gì.
Future<void> moveAppToBackground() async {
  if (kIsWeb) return;
  if (defaultTargetPlatform != TargetPlatform.android) return;
  try {
    await const MethodChannel('com.example.tool_forecast/app')
        .invokeMethod<void>('moveTaskToBack');
  } catch (_) {
    // Thiếu plugin native hoặc không hỗ trợ — bỏ qua.
  }
}
