import 'dart:math';
import 'dart:ui' show Offset;

import 'package:flutter_overlay_window/flutter_overlay_window.dart';

import 'app_branding.dart';

/// Bubble: cửa sổ overlay **chỉ bọc icon / panel** — không fullscreen (không chặn cả màn).
abstract final class OverlayBubbleConstants {
  OverlayBubbleConstants._();

  static const double fabInnerDp = 48;
  static const double fabLayerMargin = 10;
  static const double windowPadding = 6;

  static int bubbleWindowSideDp(double screenW, double screenH) {
    final idle = idleFabScreenOffset(screenW, screenH);
    return max(
      fabInnerDp.ceil() + (windowPadding * 2).ceil(),
      (idle.dx + fabInnerDp + windowPadding).ceil().clamp(56, screenW.ceil()),
    ).clamp(56, screenW.ceil());
  }

  static OverlayPosition idleFabWindowPosition(double screenW, double screenH) {
    final idle = idleFabScreenOffset(screenW, screenH);
    return OverlayPosition(
      max(0, (idle.dx - windowPadding).floor()).toDouble(),
      max(0, (idle.dy - windowPadding).floor()).toDouble(),
    );
  }

  /// Icon khi chỉ hiện bubble — góc phải-dưới màn hình.
  static Offset idleFabScreenOffset(double screenW, double screenH) {
    final side = fabInnerDp;
    return Offset(
      (screenW - side - 12).clamp(0.0, screenW - side),
      (screenH * 0.78 - side).clamp(0.0, screenH - side),
    );
  }

  /// Icon trên lớp kéo: bên trái, giữa dọc (phải = vùng vàng/lá).
  static Offset fabOnLayerLeftCenter(double layerW, double layerH) {
    final side = fabInnerDp;
    return Offset(
      fabLayerMargin,
      ((layerH - side) / 2).clamp(0.0, layerH - side),
    );
  }

  /// Mở overlay dạng bubble nhỏ — không phủ full màn.
  static Future<void> openTransparentOverlay() async {
    if (await FlutterOverlayWindow.isActive()) {
      try {
        await FlutterOverlayWindow.closeOverlay().timeout(
          const Duration(seconds: 4),
          onTimeout: () => null,
        );
      } catch (_) {}
      await Future<void>.delayed(const Duration(milliseconds: 400));
    }

    await FlutterOverlayWindow.showOverlay(
      width: 56,
      height: 56,
      alignment: OverlayAlignment.topLeft,
      flag: OverlayFlag.defaultFlag,
      enableDrag: false,
      positionGravity: PositionGravity.none,
      startPosition: const OverlayPosition(0, 0),
      overlayTitle: AppBranding.overlayNotificationTitle,
      overlayContent: AppBranding.overlayNotificationContent,
    );

    await Future<void>.delayed(const Duration(milliseconds: 300));
    try {
      await FlutterOverlayWindow.shareData({'type': 'overlay_sync_window'});
    } catch (_) {}
  }
}
