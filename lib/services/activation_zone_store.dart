import 'dart:convert';
import 'dart:ui' show Offset, Rect;

import 'package:shared_preferences/shared_preferences.dart';

/// Vùng trên màn hình (tọa độ chuẩn hóa 0–1 theo chiều rộng / cao màn hình).
class NormalizedActivationZone {
  const NormalizedActivationZone({
    required this.left,
    required this.top,
    required this.right,
    required this.bottom,
  });

  final double left;
  final double top;
  final double right;
  final double bottom;

  Rect toScreenRect(double screenW, double screenH) {
    return Rect.fromLTRB(
      left * screenW,
      top * screenH,
      right * screenW,
      bottom * screenH,
    );
  }

  String toJsonString() => jsonEncode({
        'l': left,
        't': top,
        'r': right,
        'b': bottom,
      });

  static NormalizedActivationZone? fromJsonString(String? raw) {
    if (raw == null || raw.isEmpty) return null;
    try {
      final m = jsonDecode(raw) as Map<String, dynamic>;
      return NormalizedActivationZone(
        left: (m['l'] as num).toDouble().clamp(0.0, 1.0),
        top: (m['t'] as num).toDouble().clamp(0.0, 1.0),
        right: (m['r'] as num).toDouble().clamp(0.0, 1.0),
        bottom: (m['b'] as num).toDouble().clamp(0.0, 1.0),
      );
    } catch (_) {
      return null;
    }
  }
}

/// Một điểm slot chuẩn hóa theo vùng dealer (0..1 trong zone).
class NormalizedSlotPoint {
  const NormalizedSlotPoint({required this.x, required this.y});

  final double x;
  final double y;

  Map<String, double> toMap() => {'x': x, 'y': y};

  static NormalizedSlotPoint fromMap(Map<String, dynamic> m) {
    return NormalizedSlotPoint(
      x: (m['x'] as num).toDouble().clamp(0.0, 1.0),
      y: (m['y'] as num).toDouble().clamp(0.0, 1.0),
    );
  }
}

/// Rect slot chuẩn hóa theo zone (0..1 trong zone).
class NormalizedSlotRect {
  const NormalizedSlotRect({
    required this.left,
    required this.top,
    required this.right,
    required this.bottom,
  });

  final double left;
  final double top;
  final double right;
  final double bottom;

  Map<String, double> toMap() => {
        'l': left,
        't': top,
        'r': right,
        'b': bottom,
      };

  static NormalizedSlotRect fromMap(Map<String, dynamic> m) {
    return NormalizedSlotRect(
      left: (m['l'] as num).toDouble().clamp(0.0, 1.0),
      top: (m['t'] as num).toDouble().clamp(0.0, 1.0),
      right: (m['r'] as num).toDouble().clamp(0.0, 1.0),
      bottom: (m['b'] as num).toDouble().clamp(0.0, 1.0),
    );
  }
}

/// Cấu hình hiển thị fake: vùng dealer + 6 slot lá bài.
class OverlayCalibrationProfile {
  const OverlayCalibrationProfile({
    required this.zone,
    required this.slots,
    this.slotActive,
    this.cardWidthInZone,
    this.cardHeightInZone,
    this.slotRects,
    this.screenSlotRects,
  });

  final NormalizedActivationZone zone;
  final List<NormalizedSlotPoint> slots;

  /// Slot nào vẽ lá (vd. BCR 4 lá: [T,T,F,F,T,T]). Null = cả 6.
  final List<bool>? slotActive;

  /// Kích thước lá theo tọa độ trong zone (0..1 theo width/height của zone).
  /// Nếu null -> overlay dùng kích thước mặc định.
  final double? cardWidthInZone;
  final double? cardHeightInZone;

  /// Rect từng lá trong zone (0..1). Legacy — overlay dùng [screenSlotRects].
  final List<NormalizedSlotRect>? slotRects;

  /// Rect từng lá trên **toàn màn hình** (0..1) — 5%×3% tại 40/45/55/60/70/75%.
  final List<NormalizedSlotRect>? screenSlotRects;

  String toJsonString() => jsonEncode({
        'zone': {
          'l': zone.left,
          't': zone.top,
          'r': zone.right,
          'b': zone.bottom,
        },
        'slots': slots.map((e) => e.toMap()).toList(),
        if (slotActive != null) 'slotActive': slotActive,
        if (cardWidthInZone != null) 'cw': cardWidthInZone,
        if (cardHeightInZone != null) 'ch': cardHeightInZone,
        if (slotRects != null) 'slotRects': slotRects!.map((e) => e.toMap()).toList(),
        if (screenSlotRects != null)
          'screenSlots': screenSlotRects!.map((e) => e.toMap()).toList(),
      });

  static OverlayCalibrationProfile? fromJsonString(String? raw) {
    if (raw == null || raw.isEmpty) return null;
    try {
      final m = jsonDecode(raw) as Map<String, dynamic>;
      final z = m['zone'] as Map<String, dynamic>;
      final zone = NormalizedActivationZone(
        left: (z['l'] as num).toDouble().clamp(0.0, 1.0),
        top: (z['t'] as num).toDouble().clamp(0.0, 1.0),
        right: (z['r'] as num).toDouble().clamp(0.0, 1.0),
        bottom: (z['b'] as num).toDouble().clamp(0.0, 1.0),
      );
      final arr = (m['slots'] as List<dynamic>? ?? const []);
      final slots = arr
          .whereType<Map>()
          .map((e) => NormalizedSlotPoint.fromMap(
                Map<String, dynamic>.from(e.cast<String, dynamic>()),
              ))
          .toList();
      if (slots.length != 6) return null;
      List<bool>? slotActive;
      final sa = m['slotActive'];
      if (sa is List && sa.length == 6) {
        slotActive = sa.map((e) => e == true || e == 1).toList();
      }

      final cwRaw = m['cw'];
      final chRaw = m['ch'];
      final cw = cwRaw is num ? cwRaw.toDouble().clamp(0.02, 0.6) : null;
      final ch = chRaw is num ? chRaw.toDouble().clamp(0.02, 0.6) : null;

      List<NormalizedSlotRect>? slotRects;
      final sr = m['slotRects'];
      if (sr is List && sr.length == 6) {
        slotRects = sr
            .whereType<Map>()
            .map((e) => NormalizedSlotRect.fromMap(
                  Map<String, dynamic>.from(e.cast<String, dynamic>()),
                ))
            .toList();
        if (slotRects.length != 6) slotRects = null;
      }
      List<NormalizedSlotRect>? screenSlotRects;
      final ss = m['screenSlots'];
      if (ss is List && ss.length == 6) {
        screenSlotRects = ss
            .whereType<Map>()
            .map((e) => NormalizedSlotRect.fromMap(
                  Map<String, dynamic>.from(e.cast<String, dynamic>()),
                ))
            .toList();
        if (screenSlotRects.length != 6) screenSlotRects = null;
      }
      return OverlayCalibrationProfile(
        zone: zone,
        slots: slots,
        slotActive: slotActive,
        cardWidthInZone: cw,
        cardHeightInZone: ch,
        slotRects: slotRects,
        screenSlotRects: screenSlotRects,
      );
    } catch (_) {
      return null;
    }
  }
}

/// Vùng bàn AE Sexy (preset gốc): 30%–40% từ trên màn hình.
const double aeSexyActivationLeft = 0.16;
const double aeSexyActivationRight = 0.84;
const double aeSexyActivationTop = 0.30;
const double aeSexyActivationBottom = 0.40;

/// Mỗi ô lá: 5% rộng × 3% cao (theo toàn màn hình).
const double aeSexySlotWidth = 0.05;
const double aeSexySlotHeight = 0.03;

/// Hàng 4 lá giữa — tâm dọc ~35% (giữa vùng vàng).
const double aeSexySlotCenterY = 0.35;

/// 2 lá hộp (70%, 75%) — hạ ~2% so với preset trước (0.32 → 0.34).
const double aeSexyShoeSlotCenterY = 0.34;

/// Hàng 4 lá: 2 trái dịch phải ~1% + tách nhẹ; 2 phải dịch trái ~1% + tách nhẹ.
const double aeSexySlotLeft1CenterX = 0.41;
const double aeSexySlotLeft2CenterX = 0.465;
const double aeSexySlotRight1CenterX = 0.535;
const double aeSexySlotRight2CenterX = 0.595;
/// 2 lá hộp phải — tách nhẹ như cặp 4 lá giữa (~6% giữa 2 tâm).
const double aeSexyShoeLeftCenterX = 0.715;
const double aeSexyShoeRightCenterX = 0.775;

Rect _aeSexySlotRect(double centerX, double centerY) {
  final hw = aeSexySlotWidth / 2;
  final hh = aeSexySlotHeight / 2;
  return Rect.fromLTRB(
    centerX - hw,
    centerY - hh,
    centerX + hw,
    centerY + hh,
  );
}

NormalizedActivationZone defaultActivationZone() {
  return const NormalizedActivationZone(
    left: aeSexyActivationLeft,
    top: aeSexyActivationTop,
    right: aeSexyActivationRight,
    bottom: aeSexyActivationBottom,
  );
}

/// 6 ô lá — hàng 4 giữa + 2 lá hộp phải.
List<Rect> defaultCardRectsNormalized() {
  return [
    _aeSexySlotRect(aeSexySlotLeft1CenterX, aeSexySlotCenterY),
    _aeSexySlotRect(aeSexySlotLeft2CenterX, aeSexySlotCenterY),
    _aeSexySlotRect(aeSexySlotRight1CenterX, aeSexySlotCenterY),
    _aeSexySlotRect(aeSexySlotRight2CenterX, aeSexySlotCenterY),
    _aeSexySlotRect(aeSexyShoeLeftCenterX, aeSexyShoeSlotCenterY),
    _aeSexySlotRect(aeSexyShoeRightCenterX, aeSexyShoeSlotCenterY),
  ];
}

List<NormalizedSlotRect> _screenSlotsFromGlobalRects(List<Rect> cards) {
  return cards
      .map(
        (r) => NormalizedSlotRect(
          left: r.left.clamp(0.0, 1.0),
          top: r.top.clamp(0.0, 1.0),
          right: r.right.clamp(0.0, 1.0),
          bottom: r.bottom.clamp(0.0, 1.0),
        ),
      )
      .toList();
}

/// 6 ô lá trên màn hình (0..1) — luôn preset AE Sexy (tránh profile cũ lệch lá).
List<Rect> screenCardRectsForProfile(OverlayCalibrationProfile? profile) {
  return defaultCardRectsNormalized();
}

/// Profile mặc định AE Sexy (vùng lớn + 6 ô lá).
OverlayCalibrationProfile defaultAeSexyCalibrationProfile() {
  final zone = defaultActivationZone();
  final cards = defaultCardRectsNormalized();
  final screenSlots = _screenSlotsFromGlobalRects(cards);
  final zw = (zone.right - zone.left).clamp(1e-6, 1.0);
  final zh = (zone.bottom - zone.top).clamp(1e-6, 1.0);
  final slots = cards
      .map(
        (r) => NormalizedSlotPoint(
          x: (((r.left + r.right) / 2 - zone.left) / zw).clamp(0.0, 1.0),
          y: (((r.top + r.bottom) / 2 - zone.top) / zh).clamp(0.0, 1.0),
        ),
      )
      .toList();
  final slotRects = cards
      .map(
        (r) => NormalizedSlotRect(
          left: ((r.left - zone.left) / zw).clamp(0.0, 1.0),
          top: ((r.top - zone.top) / zh).clamp(0.0, 1.0),
          right: ((r.right - zone.left) / zw).clamp(0.0, 1.0),
          bottom: ((r.bottom - zone.top) / zh).clamp(0.0, 1.0),
        ),
      )
      .toList();
  final cw = cards.map((r) => r.width / zw).reduce((a, b) => a + b) / 6;
  final ch = cards.map((r) => r.height / zh).reduce((a, b) => a + b) / 6;
  return OverlayCalibrationProfile(
    zone: zone,
    slots: slots,
    slotActive: const [true, true, true, true, true, true],
    cardWidthInZone: cw.clamp(0.04, 0.25),
    cardHeightInZone: ch.clamp(0.04, 0.25),
    slotRects: slotRects,
    screenSlotRects: screenSlots,
  );
}

/// Layout AE Sexy / live BCR: 4 lá ngang (Player+Banker) + 2 lá hộp bài phải.
List<Offset> defaultSlotPointsInZone() {
  final zone = defaultActivationZone();
  final zw = zone.right - zone.left;
  final zh = zone.bottom - zone.top;
  return defaultCardRectsNormalized()
      .map(
        (r) => Offset(
          (((r.left + r.right) / 2 - zone.left) / zw).clamp(0.0, 1.0),
          (((r.top + r.bottom) / 2 - zone.top) / zh).clamp(0.0, 1.0),
        ),
      )
      .toList();
}

/// Lưu đọc vùng kích hoạt — dùng chung app chính và isolate overlay (cùng package Android).
abstract final class ActivationZoneStore {
  ActivationZoneStore._();

  static const _key = 'overlay_activation_profile_v2';
  static const _texKey = 'overlay_card_back_texture_v1';
  static const _slotTexPrefix = 'overlay_slot_tex_v2_';

  static Future<OverlayCalibrationProfile?> loadProfile() async {
    final p = await SharedPreferences.getInstance();
    final raw = OverlayCalibrationProfile.fromJsonString(p.getString(_key));
    final fixed = defaultAeSexyCalibrationProfile();
    if (raw == null) {
      await saveProfile(fixed);
      return fixed;
    }
    if (_profileNeedsAeSexyLayoutV6(raw)) {
      await saveProfile(fixed);
      return fixed;
    }
    if (raw.screenSlotRects == null || raw.screenSlotRects!.length != 6) {
      await saveProfile(fixed);
      return fixed;
    }
    return raw;
  }

  /// Profile cũ / thiếu screenSlots / lệch preset lá → ghi lại preset.
  static bool _profileNeedsAeSexyLayoutV6(OverlayCalibrationProfile profile) {
    final z = profile.zone;
    if ((z.top - aeSexyActivationTop).abs() > 0.012 ||
        (z.bottom - aeSexyActivationBottom).abs() > 0.012 ||
        (z.left - aeSexyActivationLeft).abs() > 0.02 ||
        (z.right - aeSexyActivationRight).abs() > 0.02) {
      return true;
    }
    final ss = profile.screenSlotRects;
    if (ss == null || ss.length != 6) return true;
    final cx0 = (ss[0].left + ss[0].right) / 2;
    if ((cx0 - aeSexySlotLeft1CenterX).abs() > 0.02) return true;
    final cyShoe = (ss[4].top + ss[4].bottom) / 2;
    if ((cyShoe - aeSexyShoeSlotCenterY).abs() > 0.015) return true;
    final cxShoeRight = (ss[5].left + ss[5].right) / 2;
    return (cxShoeRight - aeSexyShoeRightCenterX).abs() > 0.02;
  }

  static Future<void> saveProfile(OverlayCalibrationProfile profile) async {
    final p = await SharedPreferences.getInstance();
    await p.setString(_key, profile.toJsonString());
  }

  static Future<NormalizedActivationZone?> load() async {
    final profile = await loadProfile();
    return profile?.zone;
  }

  static Future<void> save(NormalizedActivationZone zone) async {
    final profile = OverlayCalibrationProfile(
      zone: zone,
      slots: defaultSlotPointsInZone()
          .map((e) => NormalizedSlotPoint(x: e.dx, y: e.dy))
          .toList(),
    );
    await saveProfile(profile);
  }

  static Future<void> clear() async {
    final p = await SharedPreferences.getInstance();
    await p.remove(_key);
    await p.remove(_texKey);
    for (var i = 0; i < 6; i++) {
      await p.remove('$_slotTexPrefix$i');
    }
  }

  static Future<void> saveCardBackTextureBase64(String base64Png) async {
    final p = await SharedPreferences.getInstance();
    await p.setString(_texKey, base64Png);
  }

  static Future<String?> loadCardBackTextureBase64() async {
    final p = await SharedPreferences.getInstance();
    final s = p.getString(_texKey);
    return (s == null || s.isEmpty) ? null : s;
  }

  static Future<void> saveSlotCardBackTexturesBase64(List<String> b64List) async {
    final p = await SharedPreferences.getInstance();
    for (var i = 0; i < 6; i++) {
      final key = '$_slotTexPrefix$i';
      if (i < b64List.length && b64List[i].isNotEmpty) {
        await p.setString(key, b64List[i]);
      } else {
        await p.remove(key);
      }
    }
  }

  static Future<List<String?>> loadSlotCardBackTexturesBase64() async {
    final p = await SharedPreferences.getInstance();
    final out = <String?>[];
    for (var i = 0; i < 6; i++) {
      final s = p.getString('$_slotTexPrefix$i');
      out.add((s == null || s.isEmpty) ? null : s);
    }
    return out;
  }
}
