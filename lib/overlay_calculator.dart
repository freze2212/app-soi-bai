import 'dart:async';
import 'dart:math';
import 'dart:ui' show PlatformDispatcher, Rect;

import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_overlay_window/flutter_overlay_window.dart';
import 'package:vibration/vibration.dart';

import 'data/api_service.dart';
import 'overlay_bubble_constants.dart';
import 'services/activation_zone_store.dart';
import 'services/secure_storage_service.dart';

@immutable
class PlayingCard {
  const PlayingCard({required this.rank, required this.suit});

  final int rank;
  final int suit;

  static const _suits = ['♠', '♥', '♦', '♣'];

  String get rankLabel => switch (rank) {
        1 => 'A',
        11 => 'J',
        12 => 'Q',
        13 => 'K',
        _ => '$rank',
      };

  String get suitChar => _suits[suit];
  bool get isRed => suit == 1 || suit == 2;
}

/// Icon trái + khung vàng phải (layout trong panel kéo).
class _PanelChromeLayout {
  const _PanelChromeLayout({
    required this.windowW,
    required this.windowH,
    required this.zoneLocal,
    required this.fabLocal,
  });

  final double windowW;
  final double windowH;
  final Rect zoneLocal;
  final Offset fabLocal;
}

class OverlayCalculator extends StatefulWidget {
  const OverlayCalculator({super.key});

  @override
  State<OverlayCalculator> createState() => _OverlayCalculatorState();
}

class _OverlayCalculatorState extends State<OverlayCalculator>
    with WidgetsBindingObserver {
  static const double _fabSize = OverlayBubbleConstants.fabInnerDp;
  static const double _tapDragSlop = 8;
  static const double _yellowPanelRadius = 15;

  final Random _rng = Random();
  final ValueNotifier<Offset> _panelScreen = ValueNotifier(Offset.zero);
  /// Kéo mượt: chỉ Flutter khi đang giữ, native sync khi thả tay / đổi vùng lá.
  final ValueNotifier<Offset> _dragVisual = ValueNotifier(Offset.zero);

  /// Góc cửa sổ Android sau [_syncNativeWindow].
  Offset _lockedWindowOrigin = Offset.zero;

  /// Vùng màn hình panel được kéo trong — cửa sổ overlay bọc đúng vùng này (không clip).
  Rect? _layerEnvelope;

  bool _layerVisible = false;
  bool _inActivationZone = false;
  bool _activationChargeInFlight = false;
  bool _coinBlockedUntilLeave = false;
  bool _insufficientCoinsDialogOpen = false;
  bool _winPosInitialized = false;
  bool _pointerDragging = false;
  bool _metricsSyncPending = false;

  List<PlayingCard> _sixCards = const [];
  _PanelChromeLayout? _chromeLayout;
  double? _layoutCacheDw;
  double? _layoutCacheDh;

  double _winX = 0;
  double _winY = 0;
  double _displayW = 0;
  double _displayH = 0;

  StreamSubscription<dynamic>? _overlaySub;
  Timer? _layoutRecoveryTimer;
  int _layoutRecoveryAttempts = 0;
  Offset _fabPointerTotal = Offset.zero;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _dealSix();
    _overlaySub = FlutterOverlayWindow.overlayListener.listen((message) {
      if (message is! Map) return;
      final t = message['type'];
      if (t == 'activation_zone_cleared') {
        unawaited(_reloadProfile(resetUi: true));
      } else if (t == 'activation_zone_reload') {
        unawaited(_reloadProfile(resetUi: false));
      } else if (t == 'overlay_sync_window' || t == 'overlay_force_resize') {
        if (!_pointerDragging) unawaited(_syncNativeWindow());
      }
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      unawaited(_bootstrap());
    });
  }

  @override
  void didChangeMetrics() {
    if (!mounted) return;
    _invalidateLayoutCache();
    if (_pointerDragging) {
      _metricsSyncPending = true;
      return;
    }
    unawaited(_syncNativeWindow());
    setState(() {});
  }

  @override
  void dispose() {
    _layoutRecoveryTimer?.cancel();
    _panelScreen.dispose();
    _dragVisual.dispose();
    WidgetsBinding.instance.removeObserver(this);
    _overlaySub?.cancel();
    super.dispose();
  }

  Future<void> _bootstrap() async {
    await ActivationZoneStore.loadProfile();
    if (!mounted) return;
    await _syncNativeWindow();
    if (mounted) setState(() {});
    _startLayoutRecovery();
  }

  void _startLayoutRecovery() {
    _layoutRecoveryTimer?.cancel();
    _layoutRecoveryAttempts = 0;
    _layoutRecoveryTimer =
        Timer.periodic(const Duration(milliseconds: 250), (t) async {
      if (!mounted) {
        t.cancel();
        return;
      }
      _layoutRecoveryAttempts++;
      final (dw, dh) = _displaySize();
      if (dw >= 80 && dh >= 80) {
        t.cancel();
        await _syncNativeWindow();
        if (mounted) setState(() {});
        return;
      }
      if (_layoutRecoveryAttempts >= 24) t.cancel();
    });
  }

  /// Kích thước màn hình thật (view overlay bubble ~56dp không dùng được).
  (double, double) _displaySize() {
    if (_displayW >= 80 && _displayH >= 80) {
      return (_displayW, _displayH);
    }
    final pd = PlatformDispatcher.instance;
    if (pd.displays.isNotEmpty) {
      final d = pd.displays.first;
      return (
        d.size.width / d.devicePixelRatio,
        d.size.height / d.devicePixelRatio,
      );
    }
    final view = pd.views.first;
    final dpr = view.devicePixelRatio;
    return (
      view.physicalSize.width / dpr,
      view.physicalSize.height / dpr,
    );
  }

  void _ensureWinPosInitialized(double dw, double dh) {
    if (_winPosInitialized) return;
    final idle = OverlayBubbleConstants.idleFabScreenOffset(dw, dh);
    final pad = OverlayBubbleConstants.windowPadding;
    _winX = idle.dx - pad;
    _winY = idle.dy - pad;
    _winPosInitialized = true;
  }

  void _invalidateLayoutCache() {
    _chromeLayout = null;
    _layoutCacheDw = null;
    _layoutCacheDh = null;
  }

  _PanelChromeLayout _computeChromeLayout(double dw, double dh) {
    if (_chromeLayout != null &&
        _layoutCacheDw == dw &&
        _layoutCacheDh == dh) {
      return _chromeLayout!;
    }

    final z = defaultActivationZone();
    final zoneW = (z.right - z.left) * dw;
    final zoneH = (z.bottom - z.top) * dh;
    final pad = OverlayBubbleConstants.windowPadding;
    final fabGap = OverlayBubbleConstants.fabLayerMargin;
    final zoneLocalLeft = _fabSize + fabGap * 2;
    final windowH = max(_fabSize, zoneH) + pad * 2;
    final windowW = zoneLocalLeft + zoneW + pad;

    final layout = _PanelChromeLayout(
      windowW: windowW,
      windowH: windowH,
      zoneLocal: Rect.fromLTWH(
        zoneLocalLeft,
        (windowH - zoneH) / 2,
        zoneW,
        zoneH,
      ),
      fabLocal: Offset(pad, (windowH - _fabSize) / 2),
    );
    _chromeLayout = layout;
    _layoutCacheDw = dw;
    _layoutCacheDh = dh;
    return layout;
  }

  double _bubbleSide() => _fabSize + OverlayBubbleConstants.windowPadding * 2;

  Offset _effectivePanelOrigin() =>
      _panelScreen.value + _dragVisual.value;

  Rect _panelRectOnScreen(_PanelChromeLayout chrome, Offset panelOrigin) {
    return Rect.fromLTWH(
      panelOrigin.dx,
      panelOrigin.dy,
      chrome.windowW,
      chrome.windowH,
    );
  }

  /// Bbox cửa sổ khi mở layer: vùng bàn + 6 lá + panel có thể kéo tới 4 góc màn.
  Rect _computeLayerDragEnvelope(double dw, double dh, Offset panelOrigin) {
    final chrome = _computeChromeLayout(dw, dh);
    var env = defaultActivationZone().toScreenRect(dw, dh);
    env = env.expandToInclude(_panelRectOnScreen(chrome, panelOrigin));
    for (final o in <Offset>[
      Offset.zero,
      Offset(dw - chrome.windowW, 0),
      Offset(0, dh - chrome.windowH),
      Offset(dw - chrome.windowW, dh - chrome.windowH),
    ]) {
      env = env.expandToInclude(_panelRectOnScreen(chrome, o));
    }
    for (final r in defaultCardRectsNormalized()) {
      env = env.expandToInclude(
        Rect.fromLTRB(
          r.left * dw,
          r.top * dh,
          r.right * dw,
          r.bottom * dh,
        ),
      );
    }
    return env.inflate(OverlayBubbleConstants.windowPadding);
  }

  void _clampPanelToLayerEnvelope(
    double dw,
    double dh,
    _PanelChromeLayout chrome,
  ) {
    final env = _layerEnvelope ?? Rect.fromLTWH(0, 0, dw, dh);
    final eff = _effectivePanelOrigin();
    final clamped = Offset(
      eff.dx.clamp(env.left, max(env.left, env.right - chrome.windowW)),
      eff.dy.clamp(env.top, max(env.top, env.bottom - chrome.windowH)),
    );
    _dragVisual.value = clamped - _panelScreen.value;
  }

  Rect _fitBoundsOnScreen(Rect bounds, double dw, double dh) {
    var w = bounds.width.clamp(56.0, dw);
    var h = bounds.height.clamp(56.0, dh);
    var left = bounds.left.clamp(0.0, max(0.0, dw - w));
    var top = bounds.top.clamp(0.0, max(0.0, dh - h));
    if (left + w > dw) left = max(0.0, dw - w);
    if (top + h > dh) top = max(0.0, dh - h);
    return Rect.fromLTWH(
      left.toDouble(),
      top.toDouble(),
      w.toDouble(),
      h.toDouble(),
    );
  }

  Future<void> _syncNativeWindow({bool allowWhileDragging = false}) async {
    if (_pointerDragging && !allowWhileDragging) return;
    final (dw, dh) = _displaySize();
    if (dw < 80 || dh < 80) return;

    _displayW = dw;
    _displayH = dh;
    _ensureWinPosInitialized(dw, dh);

    try {
      if (_layerVisible) {
        final chrome = _computeChromeLayout(dw, dh);
        _clampPanelScreen(dw, dh, chrome);
        final panel = _effectivePanelOrigin();
        _layerEnvelope = _fitBoundsOnScreen(
          _computeLayerDragEnvelope(dw, dh, panel),
          dw,
          dh,
        );
        final bounds = _layerEnvelope!;
        await FlutterOverlayWindow.resizeOverlay(
          bounds.width.ceil().clamp(56, dw.ceil()),
          bounds.height.ceil().clamp(56, dh.ceil()),
          false,
        );
        await FlutterOverlayWindow.moveOverlay(
          OverlayPosition(bounds.left, bounds.top),
        );
        await FlutterOverlayWindow.updateFlag(OverlayFlag.focusPointer);
        _lockedWindowOrigin = Offset(bounds.left, bounds.top);
      } else {
        _layerEnvelope = null;
        final side = _bubbleSide().ceil().clamp(56, dw.ceil());
        _winX = _winX.clamp(0.0, max(0.0, dw - side));
        _winY = _winY.clamp(0.0, max(0.0, dh - side));
        await FlutterOverlayWindow.resizeOverlay(side, side, false);
        await FlutterOverlayWindow.moveOverlay(OverlayPosition(_winX, _winY));
        await FlutterOverlayWindow.updateFlag(OverlayFlag.defaultFlag);
      }
    } catch (_) {}
  }

  void _clampPanelScreen(double dw, double dh, _PanelChromeLayout chrome) {
    final x = _panelScreen.value.dx.clamp(0.0, max(0.0, dw - chrome.windowW));
    final y = _panelScreen.value.dy.clamp(0.0, max(0.0, dh - chrome.windowH));
    if (x != _panelScreen.value.dx || y != _panelScreen.value.dy) {
      _panelScreen.value = Offset(x.toDouble(), y.toDouble());
    }
  }

  Rect _yellowOnScreen(_PanelChromeLayout chrome, Offset panelOrigin) {
    return Rect.fromLTWH(
      panelOrigin.dx + chrome.zoneLocal.left,
      panelOrigin.dy + chrome.zoneLocal.top,
      chrome.zoneLocal.width,
      chrome.zoneLocal.height,
    );
  }

  /// Lá chỉ hiện khi **tâm** khung vàng nằm trong vùng bàn (không chỉ chạm mép).
  bool _yellowOverTable(
    double dw,
    double dh,
    _PanelChromeLayout chrome,
    Offset panelOrigin,
  ) {
    final target = defaultActivationZone().toScreenRect(dw, dh);
    return target.contains(_yellowOnScreen(chrome, panelOrigin).center);
  }

  /// Vào vùng bàn: trừ 1 xu rồi mới hiện lá; ra vùng: ẩn lá.
  void _updateActivationState(double dw, double dh) {
    final chrome = _computeChromeLayout(dw, dh);
    final hit = _yellowOverTable(dw, dh, chrome, _effectivePanelOrigin());
    if (hit == _inActivationZone) return;
    if (!hit) {
      _coinBlockedUntilLeave = false;
      if (_inActivationZone && mounted) {
        setState(() => _inActivationZone = false);
      } else {
        _inActivationZone = false;
      }
      return;
    }
    if (_activationChargeInFlight || _coinBlockedUntilLeave) return;
    unawaited(_activateZoneWithCoinCharge(dw, dh));
  }

  int _overlayCoinCost() {
    return int.tryParse(
          dotenv.env['SUBTRACT_COINS_OVERLAY_AMOUNT'] ??
              dotenv.env['SUBTRACT_COINS_AMOUNT'] ??
              '1',
        ) ??
        1;
  }

  Future<void> _showInsufficientCoinsPopup({
    required int need,
    int? current,
    String? detail,
  }) async {
    if (!mounted || _insufficientCoinsDialogOpen) return;
    _insufficientCoinsDialogOpen = true;
    final body = detail ??
        (current != null
            ? 'Bạn đang có $current xu, cần $need xu mỗi lần soi lá.'
            : 'Cần $need xu mỗi lần soi lá. Mở app để kiểm tra số dư.');

    try {
      await showDialog<void>(
        context: context,
        barrierDismissible: true,
        builder: (ctx) => AlertDialog(
          backgroundColor: const Color(0xFF1A0508),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
            side: const BorderSide(color: Color(0xFFFF3131), width: 1.2),
          ),
          title: const Text(
            'Không đủ xu',
            style: TextStyle(
              color: Color(0xFFFFE082),
              fontWeight: FontWeight.w800,
            ),
          ),
          content: Text(
            body,
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.92),
              height: 1.35,
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: const Text(
                'Đã hiểu',
                style: TextStyle(
                  color: Color(0xFFFF8C00),
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ],
        ),
      );
    } finally {
      _insufficientCoinsDialogOpen = false;
    }
  }

  Future<void> _activateZoneWithCoinCharge(double dw, double dh) async {
    _activationChargeInFlight = true;
    try {
      final storage = SecureStorageService();
      final profile = await storage.readSessionUser();
      final need = _overlayCoinCost();
      if (profile == null || profile.coins < need) {
        _coinBlockedUntilLeave = true;
        if (await Vibration.hasVibrator() == true) {
          unawaited(Vibration.vibrate(duration: 120));
        }
        await _showInsufficientCoinsPopup(
          need: need,
          current: profile?.coins,
          detail: profile == null
              ? 'Chưa đăng nhập. Mở app và đăng nhập trước khi soi lá.'
              : null,
        );
        return;
      }

      final ok = await ApiService(storage).subtractCoinsForOverlayReveal();
      if (!ok) {
        _coinBlockedUntilLeave = true;
        if (!mounted) return;
        if (await Vibration.hasVibrator() == true) {
          unawaited(Vibration.vibrate(duration: 120));
        }
        final cur = await storage.readSessionUser();
        await _showInsufficientCoinsPopup(
          need: need,
          current: cur?.coins,
          detail: cur != null && cur.coins < need
              ? 'Bạn đang có ${cur.coins} xu, cần $need xu mỗi lần soi lá.'
              : 'Không trừ được xu. Kiểm tra số dư hoặc đăng nhập lại trong app.',
        );
        return;
      }
      if (!mounted) return;

      final chrome = _computeChromeLayout(dw, dh);
      if (!_yellowOverTable(dw, dh, chrome, _effectivePanelOrigin())) return;

      _dealSix();
      setState(() => _inActivationZone = true);
      if (await Vibration.hasVibrator() == true) {
        unawaited(Vibration.vibrate(duration: 22));
      }
    } finally {
      _activationChargeInFlight = false;
    }
  }

  List<Rect> _cardSlotsLocal(double dw, double dh, Offset windowOrigin) {
    return defaultCardRectsNormalized()
        .map(
          (r) => Rect.fromLTRB(
            r.left * dw - windowOrigin.dx,
            r.top * dh - windowOrigin.dy,
            r.right * dw - windowOrigin.dx,
            r.bottom * dh - windowOrigin.dy,
          ),
        )
        .toList();
  }

  Future<void> _reloadProfile({required bool resetUi}) async {
    await ActivationZoneStore.loadProfile();
    _invalidateLayoutCache();
    if (!mounted) return;
    if (resetUi) {
      final (dw, dh) = _displaySize();
      if (_layerVisible && dw >= 80 && dh >= 80) {
        final pad = OverlayBubbleConstants.windowPadding;
        _winX = _panelScreen.value.dx;
        _winY = (_panelScreen.value.dy +
                (_computeChromeLayout(dw, dh).windowH - _fabSize - pad * 2) / 2)
            .clamp(0.0, max(0.0, dh - _bubbleSide()));
      }
      _layerVisible = false;
      _inActivationZone = false;
      _layerEnvelope = null;
      _dragVisual.value = Offset.zero;
    }
    if (mounted) setState(() {});
    await _syncNativeWindow();
    _refreshActivation();
  }

  void _dealSix() {
    final deck = <PlayingCard>[
      for (var r = 1; r <= 13; r++)
        for (var s = 0; s < 4; s++) PlayingCard(rank: r, suit: s),
    ]..shuffle(_rng);
    _sixCards = deck.sublist(0, 6);
  }

  void _refreshActivation() {
    if (!mounted || !_layerVisible) {
      if (_inActivationZone && mounted) {
        setState(() => _inActivationZone = false);
      }
      return;
    }
    final (dw, dh) = _displaySize();
    if (dw < 80 || dh < 80) return;
    _updateActivationState(dw, dh);
    setState(() {});
  }

  void _onDragUpdate(Offset delta, double dw, double dh) {
    _pointerDragging = true;
    if (_layerVisible) {
      final chrome = _computeChromeLayout(dw, dh);
      _dragVisual.value += delta;
      _clampPanelToLayerEnvelope(dw, dh, chrome);
      _updateActivationState(dw, dh);
      return;
    }

    final side = _bubbleSide();
    final next = Offset(_winX, _winY) + _dragVisual.value + delta;
    final clamped = Offset(
      next.dx.clamp(0.0, max(0.0, dw - side)),
      next.dy.clamp(0.0, max(0.0, dh - side)),
    );
    _dragVisual.value = clamped - Offset(_winX, _winY);
  }

  void _bakeBubbleDragIntoWinPos() {
    _winX += _dragVisual.value.dx;
    _winY += _dragVisual.value.dy;
    _dragVisual.value = Offset.zero;
  }

  Future<void> _commitDrag(double dw, double dh) async {
    if (!_pointerDragging) return;
    _pointerDragging = false;
    if (_layerVisible) {
      _panelScreen.value = _effectivePanelOrigin();
      _dragVisual.value = Offset.zero;
    } else {
      _bakeBubbleDragIntoWinPos();
    }
    await _syncNativeWindow();
    if (_metricsSyncPending) {
      _metricsSyncPending = false;
      await _syncNativeWindow();
    }
    _refreshActivation();
  }

  Future<void> _collapseTransparentLayer() async {
    if (!_layerVisible) return;
    final (dw, dh) = _displaySize();
    if (dw >= 80 && dh >= 80) {
      final pad = OverlayBubbleConstants.windowPadding;
      _winX = _panelScreen.value.dx;
      _winY = (_panelScreen.value.dy +
              (_computeChromeLayout(dw, dh).windowH - _fabSize - pad * 2) / 2)
          .clamp(0.0, max(0.0, dh - _bubbleSide()));
    }
    setState(() {
      _layerVisible = false;
      _inActivationZone = false;
      _layerEnvelope = null;
      _dragVisual.value = Offset.zero;
    });
    await _syncNativeWindow();
  }

  Future<void> _showTransparentLayer() async {
    if (_layerVisible) return;
    final (dw, dh) = _displaySize();
    if (dw < 80 || dh < 80) return;

    _bakeBubbleDragIntoWinPos();

    final chrome = _computeChromeLayout(dw, dh);
    final pad = OverlayBubbleConstants.windowPadding;
    final px = _winX.clamp(0.0, max(0.0, dw - chrome.windowW));
    final py = (_winY - (chrome.windowH - _fabSize - pad * 2) / 2)
        .clamp(0.0, max(0.0, dh - chrome.windowH));

    _panelScreen.value = Offset(px.toDouble(), py.toDouble());
    _dragVisual.value = Offset.zero;
    setState(() {
      _layerVisible = true;
      _inActivationZone = false;
    });

    await _syncNativeWindow();
    _refreshActivation();
  }

  /// Bấm icon: mở nền hoặc đóng nền — **không** đổi lá (chỉ kéo vào vùng bàn).
  Future<void> _onFabTap() async {
    if (!_layerVisible) {
      await _showTransparentLayer();
      if (await Vibration.hasVibrator() == true) {
        unawaited(Vibration.vibrate(duration: 18));
      }
      return;
    }
    await _collapseTransparentLayer();
    if (await Vibration.hasVibrator() == true) {
      unawaited(Vibration.vibrate(duration: 18));
    }
  }

  Widget _fabPointerHandler({
    required double dw,
    required double dh,
    required Widget child,
  }) {
    return Listener(
      behavior: HitTestBehavior.opaque,
      onPointerDown: (_) => _fabPointerTotal = Offset.zero,
      onPointerMove: (e) {
        _fabPointerTotal += e.delta;
        if (!_layerVisible && _fabPointerTotal.distance > _tapDragSlop) {
          unawaited(_showTransparentLayer());
          return;
        }
        if (_fabPointerTotal.distance > _tapDragSlop) {
          _onDragUpdate(e.delta, dw, dh);
        }
      },
      onPointerUp: (_) {
        if (_fabPointerTotal.distance <= _tapDragSlop) {
          unawaited(_onFabTap());
        } else {
          unawaited(_commitDrag(dw, dh));
        }
        _fabPointerTotal = Offset.zero;
      },
      onPointerCancel: (_) {
        unawaited(_commitDrag(dw, dh));
        _fabPointerTotal = Offset.zero;
      },
      child: child,
    );
  }

  Widget _fabFace() {
    return Material(
      elevation: 8,
      shadowColor: Colors.black54,
      shape: const CircleBorder(),
      clipBehavior: Clip.antiAlias,
      color: Colors.white,
      child: SizedBox(
        width: _fabSize,
        height: _fabSize,
        child: Image.asset(
          'assets/floating-button-mm88.png',
          fit: BoxFit.cover,
          errorBuilder: (context, error, stackTrace) => const Icon(
            Icons.bubble_chart_rounded,
            size: 28,
            color: Color(0xFF1976D2),
          ),
        ),
      ),
    );
  }

  Widget _yellowVisual({required bool showCards}) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(_yellowPanelRadius),
      child: Stack(
        fit: StackFit.expand,
        children: [
          DecoratedBox(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(_yellowPanelRadius),
              border: Border.all(
                color: Colors.yellow.withValues(
                  alpha: showCards ? 0.95 : 0.75,
                ),
                width: 2,
              ),
              color: Colors.yellow.withValues(alpha: 0.14),
            ),
          ),
          ColoredBox(
            color: Colors.black.withValues(
              alpha: showCards ? 0.08 : 0.22,
            ),
          ),
        ],
      ),
    );
  }

  Widget _layerStack({
    required double dw,
    required double dh,
    required Offset panelLocal,
    required Offset windowOrigin,
    required bool showCards,
    required bool highlightZone,
  }) {
    final chrome = _computeChromeLayout(dw, dh);

    return Stack(
      clipBehavior: Clip.none,
      children: [
        Positioned.fromRect(
          rect: Rect.fromLTWH(
            panelLocal.dx,
            panelLocal.dy,
            chrome.windowW,
            chrome.windowH,
          ),
          child: GestureDetector(
            onPanStart: (_) => _pointerDragging = true,
            onPanUpdate: (d) => _onDragUpdate(d.delta, dw, dh),
            onPanEnd: (_) => unawaited(_commitDrag(dw, dh)),
            onPanCancel: () => unawaited(_commitDrag(dw, dh)),
            child: Stack(
              clipBehavior: Clip.none,
              children: [
                Positioned.fromRect(
                  rect: chrome.zoneLocal,
                  child: _yellowVisual(showCards: highlightZone),
                ),
                Positioned(
                  left: chrome.fabLocal.dx,
                  top: chrome.fabLocal.dy,
                  child: GestureDetector(
                    onTap: () => unawaited(_onFabTap()),
                    child: _fabFace(),
                  ),
                ),
              ],
            ),
          ),
        ),
        if (showCards)
          RepaintBoundary(
            child: IgnorePointer(
              child: _ScreenFixedCardsLayer(
                cards: _sixCards,
                localSlots: _cardSlotsLocal(dw, dh, windowOrigin),
              ),
            ),
          ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final (dw, dh) = _displaySize();
        if (dw < 80 || dh < 80) {
          return const Material(
            color: Colors.transparent,
            child: SizedBox.shrink(),
          );
        }

        _displayW = dw;
        _displayH = dh;
        _ensureWinPosInitialized(dw, dh);

        final pad = OverlayBubbleConstants.windowPadding;

        if (!_layerVisible) {
          return SizedBox(
            width: constraints.maxWidth,
            height: constraints.maxHeight,
            child: Material(
              color: Colors.transparent,
              child: AnimatedBuilder(
                animation: _dragVisual,
                builder: (context, _) {
                  final d = _dragVisual.value;
                  return Stack(
                    clipBehavior: Clip.none,
                    children: [
                      Positioned(
                        left: pad + d.dx,
                        top: pad + d.dy,
                        child: _fabPointerHandler(
                          dw: dw,
                          dh: dh,
                          child: _fabFace(),
                        ),
                      ),
                    ],
                  );
                },
              ),
            ),
          );
        }

        return SizedBox(
          width: constraints.maxWidth,
          height: constraints.maxHeight,
          child: Material(
            color: Colors.transparent,
            child: AnimatedBuilder(
              animation: Listenable.merge([_panelScreen, _dragVisual]),
              builder: (context, _) {
                final effective = _effectivePanelOrigin();
                final chrome = _computeChromeLayout(dw, dh);
                final inZone =
                    _yellowOverTable(dw, dh, chrome, effective);
                final showCards = _inActivationZone && inZone;
                return _layerStack(
                  dw: dw,
                  dh: dh,
                  panelLocal: effective - _lockedWindowOrigin,
                  windowOrigin: _lockedWindowOrigin,
                  showCards: showCards,
                  highlightZone: inZone,
                );
              },
            ),
          ),
        );
      },
    );
  }
}

class _ScreenFixedCardsLayer extends StatelessWidget {
  const _ScreenFixedCardsLayer({
    required this.cards,
    required this.localSlots,
  });

  final List<PlayingCard> cards;
  final List<Rect> localSlots;

  @override
  Widget build(BuildContext context) {
    final deck = cards.length >= 6
        ? cards
        : List<PlayingCard>.filled(6, const PlayingCard(rank: 1, suit: 0));
    return Stack(
      clipBehavior: Clip.none,
      children: [
        for (var i = 0; i < 6; i++)
          if (i < localSlots.length) _cardAt(deck[i], localSlots[i]),
      ],
    );
  }

  Widget _cardAt(PlayingCard card, Rect local) {
    if (local.width < 4 || local.height < 4) {
      return const SizedBox.shrink();
    }
    return Positioned.fromRect(
      rect: local,
      child: _MiniCardFront(card: card),
    );
  }
}

class _MiniCardFront extends StatelessWidget {
  const _MiniCardFront({required this.card});

  final PlayingCard card;

  @override
  Widget build(BuildContext context) {
    final fg = card.isRed ? const Color(0xFFD50000) : const Color(0xFF0D47A1);
    return LayoutBuilder(
      builder: (context, c) {
        final w = c.maxWidth;
        final h = c.maxHeight;
        if (w < 4 || h < 4) return const SizedBox.shrink();
        final r = (min(w, h) * 0.12).clamp(2.0, 8.0);
        return ClipRRect(
          borderRadius: BorderRadius.circular(r),
          child: Container(
            color: Colors.white,
            alignment: Alignment.topLeft,
            padding: EdgeInsets.all((min(w, h) * 0.08).clamp(1.0, 6.0)),
            child: FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.topLeft,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    card.rankLabel,
                    style: TextStyle(
                      color: fg,
                      fontWeight: FontWeight.w900,
                      height: 1,
                    ),
                  ),
                  Text(
                    card.suitChar,
                    style: TextStyle(color: fg, height: 1),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}
