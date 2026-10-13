import 'dart:io';
import 'dart:math' show max, min, sqrt;
import 'dart:typed_data';
import 'dart:ui' show Rect;

import 'package:flutter/services.dart' show rootBundle;
import 'package:image/image.dart' as img;

/// Một lá detect bằng so khớp ảnh mẫu.
class TemplateCardHit {
  TemplateCardHit({
    required this.left,
    required this.top,
    required this.right,
    required this.bottom,
    required this.score,
  });

  final int left;
  final int top;
  final int right;
  final int bottom;
  final double score;

  int get w => right - left + 1;
  int get h => bottom - top + 1;
  double get cx => (left + right) / 2.0;
  double get cy => (top + bottom) / 2.0;
}

/// Tìm lá úp giống [assets/card_back_template.png] trong khung đỏ (vùng ngang bàn).
abstract final class CardTemplateDetector {
  CardTemplateDetector._();

  static const _assetPath = 'assets/card_back_template.png';

  /// Khung quét detect — bọc 6 ô preset (40–75% ngang, 30–40% dọc).
  static const Rect _redBandNorm = Rect.fromLTRB(0.34, 0.26, 0.82, 0.42);

  static double _maxCx(int imageW) => imageW * 0.82;

  static img.Image? _template;

  /// Gọi từ isolate — template đã load sẵn từ bytes.
  static void initTemplateFromBytes(Uint8List? bytes) {
    _template = bytes == null ? null : img.decodeImage(bytes);
  }

  static Future<void> _ensureTemplate() async {
    if (_template != null) return;
    img.Image? decoded;
    try {
      final data = await rootBundle.load(_assetPath);
      decoded = img.decodeImage(data.buffer.asUint8List());
    } catch (_) {
      for (final path in const [
        'assets/card_back_template.png',
        r'd:\KJC\app\assets\card_back_template.png',
      ]) {
        final f = File(path);
        if (f.existsSync()) {
          decoded = img.decodeImage(f.readAsBytesSync());
          break;
        }
      }
    }
    if (decoded == null) return;
    _template = decoded;
  }

  /// Vùng quét chuẩn (0..1) — dùng crop trước khi detect.
  static Rect get searchBandNormalized => _redBandNorm;

  /// Detect tối đa 6 lá (đồng bộ — template phải load trước).
  /// Chỉ quét màu lá úp (nhanh); template NCC chỉ refine vài ứng viên.
  static List<TemplateCardHit> detectSixSync(
    img.Image work, {
    Rect? searchRoiPx,
  }) {
    final w = work.width;
    final roi = searchRoiPx ?? _searchRoi(work);

    var candidates = _scanPinkSalmonCards(work, roi, w, fast: true);
    if (candidates.length < 8) {
      candidates = [
        ...candidates,
        ..._scanPinkSalmonCards(work, roi, w, fast: false),
      ];
    }
    if (_template != null && candidates.isNotEmpty) {
      candidates = _boostTopWithTemplate(work, candidates);
    }

    // Ảnh đã crop theo [_redBandNorm] trước khi gọi — giữ mọi hit trong crop.
    final merged = _nms(candidates, iouThreshold: 0.32);
    final picked = _pickSix(merged, w);
    return picked.map((h) => _refinePinkBounds(work, h)).toList();
  }

  /// Cộng điểm NCC cho tối đa 24 ứng viên (thay vì quét cả ảnh).
  static List<TemplateCardHit> _boostTopWithTemplate(
    img.Image work,
    List<TemplateCardHit> hits,
  ) {
    final templ = _template;
    if (templ == null || hits.isEmpty) return hits;

    final sorted = [...hits]..sort((a, b) => b.score.compareTo(a.score));
    final top = sorted.take(24).toList();
    final boosted = <TemplateCardHit>[];
    for (final h in top) {
      final tw = h.w.clamp(12, 100);
      final th = h.h.clamp(10, 95);
      var tImg = img.copyResize(templ, width: tw, height: th);
      final tGray = _grayValues(tImg);
      final tMean = _mean(tGray);
      final tStd = _std(tGray, tMean);
      if (tStd < 1e-3) {
        boosted.add(h);
        continue;
      }
      final ncc = _nccAt(work, tGray, tw, th, h.left, h.top, tMean, tStd);
      boosted.add(
        TemplateCardHit(
          left: h.left,
          top: h.top,
          right: h.right,
          bottom: h.bottom,
          score: (h.score * 0.55 + ncc * 0.45).clamp(0.0, 1.0),
        ),
      );
    }
    final rest = sorted.skip(24);
    return [...boosted, ...rest];
  }

  static Future<List<TemplateCardHit>> detectSix(
    img.Image work, {
    Rect? searchRoiPx,
  }) async {
    await _ensureTemplate();
    return detectSixSync(work, searchRoiPx: searchRoiPx);
  }

  /// Quét lá úp hồng/đỏ salmon (giống detect pixel cũ) — ưu tiên màu, ít phụ thuộc mẫu.
  static List<TemplateCardHit> _scanPinkSalmonCards(
    img.Image work,
    Rect roi,
    int imageW, {
    bool fast = false,
  }) {
    final w = work.width;
    final h = work.height;
    final baseW = (w * 0.045).round().clamp(14, 80);
    final hits = <TemplateCardHit>[];
    final scales = fast ? [0.85, 1.1] : [0.7, 0.9, 1.1, 1.3];
    final portraits = fast ? const [false] : const [false, true];
    final stepDiv = fast ? 4 : 6;

    for (final sc in scales) {
      for (final portrait in portraits) {
        final tw0 = (baseW * sc).round();
        final th0 = (tw0 * 1.35).round();
        final tw = portrait ? th0 : tw0;
        final th = portrait ? tw0 : th0;
        final stepX = max(3, tw ~/ stepDiv);
        final stepY = max(3, th ~/ stepDiv);
        final x0 = roi.left.floor().clamp(0, w - tw);
        final x1 = min(roi.right.ceil(), _maxCx(w).floor()).clamp(tw, w);
        final y0 = roi.top.floor().clamp(0, h - th);
        final y1 = roi.bottom.ceil().clamp(th, h);

        for (var y = y0; y <= y1 - th; y += stepY) {
          for (var x = x0; x <= x1 - tw; x += stepX) {
            final pink = _pinkSalmonScore(work, x, y, tw, th);
            if (pink < 0.38) continue;
            final border = _borderScore(work, x, y, tw, th);
            final score = pink * 0.72 + border * 0.28;
            if (score < 0.42) continue;
            hits.add(
              TemplateCardHit(
                left: x,
                top: y,
                right: x + tw - 1,
                bottom: y + th - 1,
                score: score,
              ),
            );
          }
        }
      }
    }
    return hits;
  }

  static Rect _searchRoi(img.Image image) {
    return Rect.fromLTWH(0, 0, image.width.toDouble(), image.height.toDouble());
  }

  static List<double> _grayValues(img.Image im) {
    final out = List<double>.filled(im.width * im.height, 0);
    var i = 0;
    for (var y = 0; y < im.height; y++) {
      for (var x = 0; x < im.width; x++) {
        final p = im.getPixel(x, y);
        out[i++] = (p.r + p.g + p.b) / 3.0;
      }
    }
    return out;
  }

  static double _mean(List<double> v) {
    if (v.isEmpty) return 0;
    var s = 0.0;
    for (final x in v) {
      s += x;
    }
    return s / v.length;
  }

  static double _std(List<double> v, double mean) {
    if (v.isEmpty) return 0;
    var s = 0.0;
    for (final x in v) {
      final d = x - mean;
      s += d * d;
    }
    return sqrt(s / v.length);
  }

  static double _nccAt(
    img.Image work,
    List<double> tGray,
    int tw,
    int th,
    int x,
    int y,
    double tMean,
    double tStd,
  ) {
    var pMean = 0.0;
    final n = tw * th;
    final pVals = List<double>.filled(n, 0);
    var idx = 0;
    for (var dy = 0; dy < th; dy++) {
      for (var dx = 0; dx < tw; dx++) {
        final p = work.getPixel(x + dx, y + dy);
        final g = (p.r + p.g + p.b) / 3.0;
        pVals[idx++] = g;
        pMean += g;
      }
    }
    pMean /= n;
    var num = 0.0;
    var pVar = 0.0;
    for (var i = 0; i < n; i++) {
      final pd = pVals[i] - pMean;
      final td = tGray[i] - tMean;
      num += pd * td;
      pVar += pd * pd;
    }
    final pStd = sqrt(pVar / n);
    if (pStd < 1e-3) return 0;
    final c = num / (n * pStd * tStd);
    return c.clamp(-1.0, 1.0) * 0.5 + 0.5;
  }

  static bool _isGreenPixel(img.Image im, int x, int y) {
    final p = im.getPixel(x, y);
    final r = p.r.toInt();
    final g = p.g.toInt();
    final b = p.b.toInt();
    return g > r + 10 && g > b + 6 && g > 45 && g < 240;
  }

  static bool _isBrightBorder(double r, double g, double b) {
    final m = min(r, min(g, b));
    return m > 0.68 && (r + g + b) / 3 > 0.72;
  }

  /// Lá úp hồng/đỏ salmon trên bàn xanh (AE Sexy).
  static bool _isSalmonCardBack(double r, double g, double b) {
    final maxV = max(r, max(g, b));
    final minV = min(r, min(g, b));
    final sat = maxV < 0.05 ? 0.0 : (maxV - minV) / maxV;
    if (maxV < 0.32 || maxV > 0.96) return false;
    if (sat > 0.48) return false;
    if (g > r + 0.08 && g > b + 0.06) return false;
    return r > 0.40 && r >= g * 0.85 && b > 0.22;
  }

  static double _pinkSalmonScore(img.Image im, int x, int y, int tw, int th) {
    var salmon = 0;
    var border = 0;
    var n = 0;
    for (var py = y; py < y + th; py += 2) {
      for (var px = x; px < x + tw; px += 2) {
        if (_isGreenPixel(im, px, py)) continue;
        n++;
        final p = im.getPixel(px, py);
        final r = p.r / 255.0;
        final g = p.g / 255.0;
        final b = p.b / 255.0;
        if (_isSalmonCardBack(r, g, b)) salmon += 2;
        if (_isBrightBorder(r, g, b)) border++;
      }
    }
    if (n < 4) return 0;
    return ((salmon / (n * 2)) * 0.85 + (border / n) * 0.15).clamp(0.0, 1.0);
  }

  static double _borderScore(img.Image im, int x, int y, int tw, int th) {
    var border = 0;
    var n = 0;
    for (var py = y; py < y + th; py += 2) {
      for (var px = x; px < x + tw; px += 2) {
        final onEdge = px < x + tw * 0.22 ||
            px > x + tw * 0.78 ||
            py < y + th * 0.22 ||
            py > y + th * 0.78;
        if (!onEdge) continue;
        n++;
        final p = im.getPixel(px, py);
        if (_isBrightBorder(p.r / 255.0, p.g / 255.0, p.b / 255.0)) border++;
      }
    }
    if (n == 0) return 0;
    return (border / n).clamp(0.0, 1.0);
  }

  static bool _isGreyCardBack(double r, double g, double b) {
    final m = (r + g + b) / 3;
    final spread = max(r, max(g, b)) - min(r, min(g, b));
    return m > 0.52 && m < 0.93 && spread < 0.18;
  }

  static List<TemplateCardHit> _nms(
    List<TemplateCardHit> hits, {
    required double iouThreshold,
  }) {
    final sorted = [...hits]..sort((a, b) => b.score.compareTo(a.score));
    final kept = <TemplateCardHit>[];
    for (final h in sorted) {
      if (kept.any((k) => _iou(k, h) > iouThreshold)) continue;
      kept.add(h);
    }
    return kept;
  }

  static double _iou(TemplateCardHit a, TemplateCardHit b) {
    final x0 = max(a.left, b.left);
    final y0 = max(a.top, b.top);
    final x1 = min(a.right, b.right);
    final y1 = min(a.bottom, b.bottom);
    if (x1 < x0 || y1 < y0) return 0;
    final inter = (x1 - x0 + 1) * (y1 - y0 + 1);
    final u = a.w * a.h + b.w * b.h - inter;
    return u <= 0 ? 0 : inter / u;
  }

  static List<TemplateCardHit> _pickSix(List<TemplateCardHit> hits, int imgW) {
    if (hits.isEmpty) return const [];
    final sorted = [...hits]..sort((a, b) => a.cx.compareTo(b.cx));

    if (sorted.length <= 6) {
      return _fillSixSlots(sorted, imgW);
    }

    var best = <TemplateCardHit>[];
    var bestScore = -1.0;
    for (var i = 0; i <= sorted.length - 6; i++) {
      final window = sorted.sublist(i, i + 6);
      final gaps = <double>[];
      for (var j = 1; j < 6; j++) {
        gaps.add(window[j].cx - window[j - 1].cx);
      }
      final meanGap = gaps.reduce((a, b) => a + b) / gaps.length;
      var varG = 0.0;
      for (final g in gaps) {
        varG += (g - meanGap) * (g - meanGap);
      }
      varG = sqrt(varG / gaps.length);
      final cv = meanGap > 1 ? varG / meanGap : 99.0;
      final s = window.map((e) => e.score).reduce((a, b) => a + b) -
          cv * 2.5;
      if (s > bestScore) {
        bestScore = s;
        best = window;
      }
    }
    return best;
  }

  static List<TemplateCardHit> _fillSixSlots(
    List<TemplateCardHit> hits,
    int imgW,
  ) {
    final byX = [...hits]..sort((a, b) => a.cx.compareTo(b.cx));
    return byX;
  }

  static Rect zoneFromHits(List<TemplateCardHit> hits, int w, int h) {
    if (hits.isEmpty) {
      return Rect.fromLTRB(
        w * _redBandNorm.left,
        h * _redBandNorm.top,
        w * _redBandNorm.right,
        h * _redBandNorm.bottom,
      );
    }
    var minX = hits.map((e) => e.left).reduce(min).toDouble();
    var maxX = hits.map((e) => e.right).reduce(max).toDouble();
    var minY = hits.map((e) => e.top).reduce(min).toDouble();
    var maxY = hits.map((e) => e.bottom).reduce(max).toDouble();
    final padX = max((maxX - minX) * 0.14, w * 0.025);
    final padY = max((maxY - minY) * 0.35, h * 0.02);
    final maxRight = _maxCx(w);
    return Rect.fromLTRB(
      (minX - padX).clamp(0.0, w.toDouble()),
      (minY - padY).clamp(0.0, h.toDouble()),
      (maxX + padX).clamp(0.0, maxRight),
      (maxY + padY).clamp(0.0, h.toDouble()),
    );
  }

  static TemplateCardHit _refinePinkBounds(img.Image work, TemplateCardHit h) {
    final padX = max(6, (h.w * 0.3).round());
    final padY = max(4, (h.h * 0.35).round());
    final x0 = max(0, h.left - padX);
    final x1 = min(work.width - 1, h.right + padX);
    final y0 = max(0, h.top - padY);
    final y1 = min(work.height - 1, h.bottom + padY);
    var minX = x1, maxX = x0, minY = y1, maxY = y0;
    var found = false;
    for (var y = y0; y <= y1; y++) {
      for (var x = x0; x <= x1; x++) {
        if (_isGreenPixel(work, x, y)) continue;
        final p = work.getPixel(x, y);
        final r = p.r / 255.0;
        final g = p.g / 255.0;
        final b = p.b / 255.0;
        if (!_isSalmonCardBack(r, g, b) &&
            !_isBrightBorder(r, g, b) &&
            !_isGreyCardBack(r, g, b)) {
          continue;
        }
        found = true;
        if (x < minX) minX = x;
        if (x > maxX) maxX = x;
        if (y < minY) minY = y;
        if (y > maxY) maxY = y;
      }
    }
    if (!found) return h;
    return TemplateCardHit(
      left: minX,
      top: minY,
      right: maxX,
      bottom: maxY,
      score: h.score,
    );
  }
}
