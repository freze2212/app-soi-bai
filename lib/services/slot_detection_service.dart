import 'dart:convert';
import 'dart:io';
import 'dart:isolate';
import 'dart:math' show max;
import 'dart:typed_data';
import 'dart:ui' show Offset, Rect;

import 'package:flutter/services.dart' show rootBundle;
import 'package:image/image.dart' as img;

import 'activation_zone_store.dart';
import 'card_template_detector.dart';

/// Kết quả detect lá úp từ screenshot.
class SlotDetectionResult {
  const SlotDetectionResult({
    required this.success,
    required this.cardsDetected,
    required this.confidence,
    required this.debug,
    this.profile,
    this.cardRectsNormalized = const [],
    this.zoneNormalized,
  });

  final bool success;
  final int cardsDetected;
  final double confidence;
  final String debug;
  final OverlayCalibrationProfile? profile;

  final List<Rect> cardRectsNormalized;
  final Rect? zoneNormalized;
}

/// Detect 6 lá úp: so khớp ảnh mẫu trong khung đỏ (vùng bàn dealer).
abstract final class SlotDetectionService {
  SlotDetectionService._();

  static Uint8List? _templateBytesCache;

  /// Nạp sẵn template — gọi lúc mở app để detect gallery nhanh hơn.
  static Future<void> preloadTemplate() async {
    if (_templateBytesCache != null) return;
    try {
      final data = await rootBundle.load('assets/card_back_template.png');
      _templateBytesCache = data.buffer.asUint8List();
    } catch (_) {}
  }

  static Future<SlotDetectionResult> detectFromScreenshot(
    String imagePath,
  ) async {
    await preloadTemplate();
    final templateBytes = _templateBytesCache;

    return Isolate.run(
      () => _detectSync(imagePath, templateBytes),
    );
  }

  /// Map hit từ ảnh crop+resize về tọa độ 0..1 màn gốc.
  static List<Rect> _normHitsFromCrop(
    List<TemplateCardHit> row,
    int origW,
    int origH, {
    required int cropX,
    required int cropY,
    required double workScale,
  }) {
    final inv = 1.0 / workScale;
    final sorted = [...row]..sort((a, b) => a.cx.compareTo(b.cx));
    final rects = sorted
        .map(
          (e) => Rect.fromLTRB(
            (e.left * inv + cropX) / origW,
            (e.top * inv + cropY) / origH,
            ((e.right + 1) * inv + cropX) / origW,
            ((e.bottom + 1) * inv + cropY) / origH,
          ),
        )
        .toList();
    while (rects.length < 6) {
      rects.add(Rect.zero);
    }
    return rects.take(6).toList();
  }

  static List<Offset> toScreenSlots(
    OverlayCalibrationProfile profile,
    double screenW,
    double screenH,
  ) {
    final z = profile.zone.toScreenRect(screenW, screenH);
    return profile.slots
        .map((s) => Offset(z.left + s.x * z.width, z.top + s.y * z.height))
        .toList();
  }

  /// Tạo profile từ 6 ô user chỉnh (tọa độ 0..1 theo ảnh).
  static OverlayCalibrationProfile buildProfileFromCardRects(
    List<Rect> cardRectsNormalized,
  ) {
    final cards = _ensureSixGlobalRects(cardRectsNormalized);
    final active = cards.where((r) => r.width > 0.001).length;
    final zone = defaultActivationZone();
    final slotActive = _slotActiveForCount(active);
    final slotRects = _slotRectsFromGlobalRects(cards, zone, active);
    final slots = _slotCentersFromRects(cards, zone);
    final (cw, ch) = _estimateCardSizeInZone(cards, zone);
    return OverlayCalibrationProfile(
      zone: zone,
      slots: slots,
      slotActive: slotActive,
      cardWidthInZone: cw,
      cardHeightInZone: ch,
      slotRects: slotRects,
    );
  }

  static List<Rect> _ensureSixGlobalRects(List<Rect> input) {
    final out = List<Rect>.filled(6, Rect.zero);
    final defaults = _defaultCardRectsNormalized();
    for (var i = 0; i < 6; i++) {
      if (i < input.length && input[i].width > 0.001) {
        out[i] = _clampNormRect(input[i]);
      } else {
        out[i] = defaults[i];
      }
    }
    return out;
  }

  static List<Rect> _defaultCardRectsNormalized() => defaultCardRectsNormalized();

  static Rect _clampNormRect(Rect r) {
    var l = r.left.clamp(0.0, 1.0);
    var t = r.top.clamp(0.0, 1.0);
    var ri = r.right.clamp(0.0, 1.0);
    var b = r.bottom.clamp(0.0, 1.0);
    if (ri - l < 0.015) ri = (l + 0.015).clamp(0.0, 1.0);
    if (b - t < 0.015) b = (t + 0.015).clamp(0.0, 1.0);
    return Rect.fromLTRB(l, t, ri, b);
  }


  static Future<String?> extractCardBackTextureBase64(
    String imagePath,
    SlotDetectionResult result, {
    int maxSizePx = 260,
  }) async {
    if (!result.success || result.cardRectsNormalized.isEmpty) return null;
    final bytes = await File(imagePath).readAsBytes();
    final decoded = img.decodeImage(bytes);
    if (decoded == null) return null;

    final r0 = result.cardRectsNormalized.firstWhere(
      (r) => r.width > 0.001 && r.height > 0.001,
      orElse: () => result.cardRectsNormalized.first,
    );
    if (r0.width <= 0) return null;

    final x0 = (r0.left * decoded.width).floor().clamp(0, decoded.width - 2);
    final y0 = (r0.top * decoded.height).floor().clamp(0, decoded.height - 2);
    final x1 =
        (r0.right * decoded.width).ceil().clamp(x0 + 1, decoded.width);
    final y1 =
        (r0.bottom * decoded.height).ceil().clamp(y0 + 1, decoded.height);
    var crop = img.copyCrop(
      decoded,
      x: x0,
      y: y0,
      width: x1 - x0,
      height: y1 - y0,
    );

    final maxSide = max(crop.width, crop.height);
    if (maxSide > maxSizePx) {
      final s = maxSizePx / maxSide;
      crop = img.copyResize(
        crop,
        width: (crop.width * s).round().clamp(20, maxSizePx),
        height: (crop.height * s).round().clamp(20, maxSizePx),
      );
    }
    return base64Encode(img.encodePng(crop, level: 3));
  }

  /// Cắt ảnh mặt sau từng lá đúng bbox detect (6 slot).
  static Future<List<String>> extractSlotCardBackTexturesBase64(
    String imagePath,
    SlotDetectionResult result,
  ) async {
    if (!result.success) return List.filled(6, '');
    return Isolate.run(
      () => _extractSlotTexturesSync(imagePath, result.cardRectsNormalized),
    );
  }

  static List<String> _extractSlotTexturesSync(
    String imagePath,
    List<Rect> rects,
  ) {
    final bytes = File(imagePath).readAsBytesSync();
    final decoded = img.decodeImage(bytes);
    if (decoded == null) return List.filled(6, '');

    final out = List<String>.filled(6, '');
    for (var i = 0; i < 6 && i < rects.length; i++) {
      final r = rects[i];
      if (r.width <= 0.001 || r.height <= 0.001) continue;
      final x0 = (r.left * decoded.width).floor().clamp(0, decoded.width - 2);
      final y0 = (r.top * decoded.height).floor().clamp(0, decoded.height - 2);
      final x1 =
          (r.right * decoded.width).ceil().clamp(x0 + 1, decoded.width);
      final y1 =
          (r.bottom * decoded.height).ceil().clamp(y0 + 1, decoded.height);
      final crop = img.copyCrop(
        decoded,
        x: x0,
        y: y0,
        width: x1 - x0,
        height: y1 - y0,
      );
      out[i] = base64Encode(img.encodePng(crop, level: 3));
    }
    return out;
  }
}

List<bool> _slotActiveForCount(int n) {
  if (n >= 6) return List<bool>.filled(6, true);
  if (n >= 4) return [true, true, true, true, false, false];
  if (n == 3) return [true, true, true, false, false, false];
  if (n == 2) return [true, true, false, false, false, false];
  return List<bool>.filled(6, false);
}

List<NormalizedSlotPoint> _slotCentersFromRects(
  List<Rect> globalRects,
  NormalizedActivationZone zone,
) {
  final zw = (zone.right - zone.left).clamp(1e-6, 1.0);
  final zh = (zone.bottom - zone.top).clamp(1e-6, 1.0);
  final out = <NormalizedSlotPoint>[];
  for (var i = 0; i < 6; i++) {
    if (i >= globalRects.length || globalRects[i].width <= 0) {
      final d = defaultSlotPointsInZone();
      out.add(NormalizedSlotPoint(x: d[i].dx, y: d[i].dy));
      continue;
    }
    final r = globalRects[i];
    out.add(
      NormalizedSlotPoint(
        x: (((r.left + r.right) / 2 - zone.left) / zw).clamp(0.0, 1.0),
        y: (((r.top + r.bottom) / 2 - zone.top) / zh).clamp(0.0, 1.0),
      ),
    );
  }
  return out;
}

(double?, double?) _estimateCardSizeInZone(
  List<Rect> rects,
  NormalizedActivationZone zone,
) {
  final valid = rects.where((r) => r.width > 0.001).toList();
  if (valid.isEmpty) return (null, null);
  final zw = (zone.right - zone.left).clamp(1e-6, 1.0);
  final zh = (zone.bottom - zone.top).clamp(1e-6, 1.0);
  final ws = valid.map((r) => r.width / zw).toList()..sort();
  final hs = valid.map((r) => r.height / zh).toList()..sort();
  return (
    ws[ws.length ~/ 2].clamp(0.04, 0.35),
    hs[hs.length ~/ 2].clamp(0.04, 0.35),
  );
}

List<NormalizedSlotRect> _slotRectsFromGlobalRects(
  List<Rect> globalRectsNorm,
  NormalizedActivationZone zone,
  int detectedCount,
) {
  final zw = (zone.right - zone.left).clamp(1e-6, 1.0);
  final zh = (zone.bottom - zone.top).clamp(1e-6, 1.0);

  NormalizedSlotRect toZone(Rect g) {
    if (g.width <= 0) {
      return const NormalizedSlotRect(left: 0, top: 0, right: 0, bottom: 0);
    }
    return NormalizedSlotRect(
      left: ((g.left) - zone.left) / zw,
      top: ((g.top) - zone.top) / zh,
      right: ((g.right) - zone.left) / zw,
      bottom: ((g.bottom) - zone.top) / zh,
    );
  }

  final rects = List<NormalizedSlotRect?>.filled(6, null);
  for (var i = 0; i < 6 && i < globalRectsNorm.length; i++) {
    rects[i] = toZone(globalRectsNorm[i]);
  }
  for (var i = 0; i < 6; i++) {
    rects[i] ??= const NormalizedSlotRect(left: 0, top: 0, right: 0, bottom: 0);
  }
  return rects.cast<NormalizedSlotRect>();
}

/// Chỉ xử lý dải bàn dealer (không decode/resize cả màn hình).
const _detectMaxBandWidth = 640;

/// Detect lệch layout chuẩn (40–75% ngang, trong vùng 30–40%) → preset 6 ô.
List<Rect> _usePresetIfDetectOffTable(List<Rect> rects) {
  final valid = rects.where((r) => r.width > 0.001 && r.height > 0.001).toList();
  if (valid.isEmpty) return defaultCardRectsNormalized();
  final avgCx =
      valid.map((r) => (r.left + r.right) / 2).reduce((a, b) => a + b) / valid.length;
  final avgCy =
      valid.map((r) => (r.top + r.bottom) / 2).reduce((a, b) => a + b) / valid.length;
  if (avgCx < 0.36 ||
      avgCx > 0.82 ||
      avgCy < aeSexyActivationTop - 0.02 ||
      avgCy > aeSexyActivationBottom + 0.02) {
    return defaultCardRectsNormalized();
  }
  return rects;
}

SlotDetectionResult _detectSync(String imagePath, Uint8List? templateBytes) {
  CardTemplateDetector.initTemplateFromBytes(templateBytes);

  final bytes = File(imagePath).readAsBytesSync();
  final decoded = img.decodeImage(bytes);
  if (decoded == null) {
    throw const FormatException('Không đọc được ảnh screenshot.');
  }

  final origW = decoded.width;
  final origH = decoded.height;
  if (origW < 200 || origH < 200) {
    throw const FormatException('Ảnh quá nhỏ để detect.');
  }

  final band = CardTemplateDetector.searchBandNormalized;
  final cropX = (origW * band.left).floor().clamp(0, origW - 2);
  final cropY = (origH * band.top).floor().clamp(0, origH - 2);
  final cropR = (origW * band.right).ceil().clamp(cropX + 2, origW);
  final cropB = (origH * band.bottom).ceil().clamp(cropY + 2, origH);
  final cropped = img.copyCrop(
    decoded,
    x: cropX,
    y: cropY,
    width: cropR - cropX,
    height: cropB - cropY,
  );
  final work = cropped.width > _detectMaxBandWidth
      ? img.copyResize(cropped, width: _detectMaxBandWidth)
      : cropped;
  final workScale = work.width / cropped.width;

  final hits = CardTemplateDetector.detectSixSync(work);
  final group = hits.length >= 6 ? hits.take(6).toList() : hits;

  if (group.length < 4) {
    return SlotDetectionResult(
      success: false,
      cardsDetected: group.length,
      confidence: group.isEmpty
          ? 0
          : group.map((e) => e.score).reduce((a, b) => a + b) / group.length,
      debug:
          'Không đủ lá giống mẫu trong khung bàn (thấy ${group.length}/6). '
          'Chụp khi dealer đã úp đủ 6 lá, nằm trong vùng PLAYER/BANKER.',
      cardRectsNormalized: group.isEmpty
          ? defaultCardRectsNormalized()
          : SlotDetectionService._normHitsFromCrop(
              group,
              origW,
              origH,
              cropX: cropX,
              cropY: cropY,
              workScale: workScale,
            ),
    );
  }

  final zone = defaultActivationZone();

  var overlayRects = SlotDetectionService._normHitsFromCrop(
    group,
    origW,
    origH,
    cropX: cropX,
    cropY: cropY,
    workScale: workScale,
  );
  overlayRects = _usePresetIfDetectOffTable(overlayRects);
  final slotActive = _slotActiveForCount(group.length);
  final slotRects = _slotRectsFromGlobalRects(overlayRects, zone, group.length);
  final slots = _slotCentersFromRects(overlayRects, zone);
  final (cw, ch) = _estimateCardSizeInZone(overlayRects, zone);
  final conf = group.map((e) => e.score).reduce((a, b) => a + b) / group.length;

  final profile = OverlayCalibrationProfile(
    zone: zone,
    slots: slots,
    slotActive: slotActive,
    cardWidthInZone: cw,
    cardHeightInZone: ch,
    slotRects: slotRects,
  );

  return SlotDetectionResult(
    success: true,
    cardsDetected: group.length,
    confidence: conf.clamp(0.0, 1.0),
    profile: profile,
    debug:
        'OK: ${group.length} lá hồng (70% trái), score ${(conf * 100).toStringAsFixed(0)}%',
    cardRectsNormalized: overlayRects,
    zoneNormalized: Rect.fromLTRB(
      zone.left,
      zone.top,
      zone.right,
      zone.bottom,
    ),
  );
}
