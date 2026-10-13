import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_overlay_window/flutter_overlay_window.dart';
import '../auth/auth_bloc.dart';
import '../auth/auth_event.dart';
import '../auth/auth_state.dart';
import '../models/session_user.dart';
import '../app_branding.dart';
import '../overlay_bubble_constants.dart';
import '../services/activation_zone_store.dart';
import '../services/app_background.dart';
import '../services/secure_storage_service.dart';

/// Màn chọn sảnh — sau khi chọn: bật bubble overlay (6 lá) rồi đưa app xuống nền.
class LobbyScreen extends StatefulWidget {
  const LobbyScreen({super.key});

  @override
  State<LobbyScreen> createState() => _LobbyScreenState();
}

class _LobbyScreenState extends State<LobbyScreen> with WidgetsBindingObserver {
  bool _busy = false;
  /// Bubble overlay đang chạy (đồng bộ từ [FlutterOverlayWindow.isActive]).
  bool _overlayActive = false;

  static const _lobbiesTop = <({String asset, String label})>[
    (asset: 'assets/lobby/lobby-sexy.png', label: 'AE Sexy'),
    (asset: 'assets/lobby/lobby-dreamgaming.png', label: 'Dream Gaming'),
    (asset: 'assets/lobby/lobby-AG.png', label: 'Asia Gaming'),
    (asset: 'assets/lobby/lobby-vivogaming.png', label: 'Vivo Gaming'),
    (asset: 'assets/lobby/lobby-wmcasino.png', label: 'WM Casino'),
    (asset: 'assets/lobby/lobby-evolution.png', label: 'Evolution'),
  ];

  static const _venus =
      (asset: 'assets/lobby/lobby-venus.png', label: 'Venus Casino');

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      unawaited(_syncProfileAndOverlayMessages());
      unawaited(_refreshOverlayActive());
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      if (mounted) setState(() => _busy = false);
      unawaited(_syncProfileAndOverlayMessages());
      unawaited(_refreshOverlayActive());
    }
  }

  Future<void> _refreshOverlayActive() async {
    try {
      final on = await FlutterOverlayWindow.isActive();
      if (mounted) setState(() => _overlayActive = on);
    } catch (_) {
      if (mounted) setState(() => _overlayActive = false);
    }
  }

  /// Tắt bubble overlay (giữ app ở foreground).
  Future<void> _closeFloatingOverlay() async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      if (await FlutterOverlayWindow.isActive()) {
        try {
          await FlutterOverlayWindow.closeOverlay().timeout(
                const Duration(seconds: 4),
                onTimeout: () => null,
              );
        } catch (e, st) {
          debugPrint('closeOverlay: $e\n$st');
        }
      }
      await _refreshOverlayActive();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Đã tắt ${AppBranding.appTitle}'),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _notifyOverlayZoneChanged({bool cleared = false}) async {
    try {
      if (await FlutterOverlayWindow.isActive()) {
        await FlutterOverlayWindow.shareData({
          'type': cleared
              ? 'activation_zone_cleared'
              : 'activation_zone_reload',
        });
      }
    } catch (_) {}
  }

  /// Bật bubble + layout cố định (nút icon trên app bar).
  Future<void> _showBubbleWithFixedLayout() async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await ActivationZoneStore.saveProfile(defaultAeSexyCalibrationProfile());

      var ok = await FlutterOverlayWindow.isPermissionGranted();
      if (!ok) {
        try {
          await FlutterOverlayWindow.requestPermission().timeout(
                const Duration(seconds: 45),
                onTimeout: () => false,
              );
        } catch (_) {}
        ok = await FlutterOverlayWindow.isPermissionGranted();
      }
      if (!ok) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text(
                'Cần quyền “Hiển thị trên ứng dụng khác” để mở ${AppBranding.appTitle}.',
              ),
              behavior: SnackBarBehavior.floating,
            ),
          );
        }
        return;
      }

      await OverlayBubbleConstants.openTransparentOverlay();

      await Future<void>.delayed(const Duration(milliseconds: 400));
      await _notifyOverlayZoneChanged();
      await _refreshOverlayActive();

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Đã bật ${AppBranding.appTitle}. Bấm icon → kéo khung vàng vào vùng bàn (30–40% trên) → hiện 6 lá.',
          ),
          behavior: SnackBarBehavior.floating,
          duration: Duration(seconds: 4),
        ),
      );
    } catch (e, st) {
      debugPrint('showBubble: $e\n$st');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Không mở được ${AppBranding.appTitle}: $e'),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _confirmClearActivationZone() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Xóa vùng bài?'),
        content: const Text(
          'Sau khi xóa, khung lá sẽ luôn hiện khi mở tool (không cần trùng vùng).',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Hủy'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Xóa'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    await ActivationZoneStore.clear();
    await _notifyOverlayZoneChanged(cleared: true);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Đã xóa vùng đã căn.'),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }


  Future<void> _syncProfileAndOverlayMessages() async {
    if (!mounted) return;
    context.read<AuthBloc>().add(const AuthProfileSyncedFromStorage());
    final msg = await context.read<SecureStorageService>().takePendingHomeMessage();
    if (!mounted || msg == null || msg.isEmpty) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg),
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 6),
      ),
    );
  }

  /// Bật bubble overlay (nếu chưa có), sau đó đưa app xuống nền.
  Future<void> _openOverlayAndBackground() async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      var ok = await FlutterOverlayWindow.isPermissionGranted();
      if (!ok) {
        try {
          await FlutterOverlayWindow.requestPermission().timeout(
                const Duration(seconds: 45),
                onTimeout: () => false,
              );
        } catch (_) {}
        ok = await FlutterOverlayWindow.isPermissionGranted();
      }
      if (!ok) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text(
                'Cần quyền “Hiển thị trên ứng dụng khác” để mở ${AppBranding.appTitle}.',
              ),
              behavior: SnackBarBehavior.floating,
            ),
          );
        }
        return;
      }

      await OverlayBubbleConstants.openTransparentOverlay();

      await ActivationZoneStore.saveProfile(defaultAeSexyCalibrationProfile());
      await Future<void>.delayed(const Duration(milliseconds: 500));
      try {
        await FlutterOverlayWindow.shareData({'type': 'activation_zone_reload'});
      } catch (_) {}

      await moveAppToBackground();
      await _refreshOverlayActive();
    } catch (e, st) {
      debugPrint('Lobby overlay: $e\n$st');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Không mở được overlay: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  String _formatCoinsVi(int n) {
    final s = n.abs().toString();
    final buf = StringBuffer();
    final len = s.length;
    for (var i = 0; i < len; i++) {
      if (i > 0 && (len - i) % 3 == 0) buf.write('.');
      buf.write(s[i]);
    }
    return n < 0 ? '-$buf' : buf.toString();
  }

  @override
  Widget build(BuildContext context) {
    const gridPad = 16.0;
    const gap = 12.0;

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.light.copyWith(
        statusBarColor: Colors.transparent,
        statusBarIconBrightness: Brightness.light,
      ),
      child: Scaffold(
        backgroundColor: const Color(0xFF1A0508),
        extendBodyBehindAppBar: true,
        appBar: AppBar(
          elevation: 0,
          scrolledUnderElevation: 0,
          backgroundColor: Colors.black.withValues(alpha: 0.35),
          foregroundColor: Colors.white,
          title: const Text(
            'Chọn sảnh',
            style: TextStyle(fontWeight: FontWeight.w700, letterSpacing: 0.5),
          ),
          actions: [
            Tooltip(
              message: _overlayActive
                  ? 'Tắt ${AppBranding.appTitle}'
                  : 'Chưa bật — chọn một sảnh bên dưới',
              child: Padding(
                padding: const EdgeInsets.only(right: 4),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      'Nổi',
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.white.withValues(
                          alpha: _overlayActive ? 1 : 0.55,
                        ),
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    Transform.scale(
                      scale: 0.85,
                      child: Switch.adaptive(
                        value: _overlayActive,
                        onChanged: _busy
                            ? null
                            : (on) {
                                if (!on) {
                                  unawaited(_closeFloatingOverlay());
                                } else {
                                  unawaited(_showBubbleWithFixedLayout());
                                }
                              },
                      ),
                    ),
                  ],
                ),
              ),
            ),
            BlocBuilder<AuthBloc, AuthState>(
              buildWhen: (p, c) => p.profile != c.profile,
              builder: (context, state) {
                final coins = state.profile?.coins ?? 0;
                return Padding(
                  padding: const EdgeInsets.only(right: 6),
                  child: Center(
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.monetization_on_rounded,
                          size: 20,
                          color: const Color(0xFFFFE082).withValues(alpha: 0.95),
                        ),
                        const SizedBox(width: 4),
                        Text(
                          _formatCoinsVi(coins),
                          style: const TextStyle(
                            fontWeight: FontWeight.w700,
                            fontSize: 15,
                            color: Color(0xFFFFE082),
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
            IconButton(
              tooltip: 'Bật ${AppBranding.appTitle}',
              icon: const Icon(Icons.bubble_chart_rounded),
              onPressed: _busy ? null : () => unawaited(_showBubbleWithFixedLayout()),
            ),
            IconButton(
              tooltip: 'Xóa vùng đã căn',
              icon: const Icon(Icons.delete_outline_rounded),
              onPressed: _busy
                  ? null
                  : () => unawaited(_confirmClearActivationZone()),
            ),
            IconButton(
              tooltip: 'Đăng xuất',
              icon: const Icon(Icons.logout_rounded),
              onPressed: () {
                context.read<AuthBloc>().add(const AuthLogoutRequested());
              },
            ),
          ],
        ),
        body: Stack(
          fit: StackFit.expand,
          children: [
            Positioned.fill(
              child: Image.asset(
                'assets/background-auth.png',
                fit: BoxFit.cover,
                alignment: Alignment.topCenter,
                filterQuality: FilterQuality.high,
              ),
            ),
            SafeArea(
              child: LayoutBuilder(
                builder: (context, c) {
                  final w = c.maxWidth;
                  final cellW = (w - gridPad * 2 - gap) / 2;
                  return CustomScrollView(
                    physics: const BouncingScrollPhysics(
                      parent: AlwaysScrollableScrollPhysics(),
                    ),
                    slivers: [
                      SliverToBoxAdapter(
                        child: Padding(
                          padding: const EdgeInsets.fromLTRB(
                            gridPad,
                            8,
                            gridPad,
                            12,
                          ),
                          child: BlocBuilder<AuthBloc, AuthState>(
                            buildWhen: (p, q) => p.profile != q.profile,
                            builder: (context, state) {
                              return _ProfileStrip(profile: state.profile);
                            },
                          ),
                        ),
                      ),
                      SliverPadding(
                        padding: const EdgeInsets.symmetric(horizontal: gridPad),
                        sliver: SliverGrid(
                          gridDelegate:
                              SliverGridDelegateWithFixedCrossAxisCount(
                            crossAxisCount: 2,
                            mainAxisSpacing: gap,
                            crossAxisSpacing: gap,
                            childAspectRatio: 0.58,
                          ),
                          delegate: SliverChildBuilderDelegate(
                            (context, index) {
                              final item = _lobbiesTop[index];
                              return _LobbyCard(
                                asset: item.asset,
                                label: item.label,
                                enabled: !_busy,
                                onTap: _openOverlayAndBackground,
                              );
                            },
                            childCount: _lobbiesTop.length,
                          ),
                        ),
                      ),
                      SliverToBoxAdapter(
                        child: Padding(
                          padding: const EdgeInsets.fromLTRB(
                            gridPad,
                            gap,
                            gridPad,
                            24,
                          ),
                          child: Center(
                            child: SizedBox(
                              width: cellW,
                              child: AspectRatio(
                                aspectRatio: 0.58,
                                child: _LobbyCard(
                                  asset: _venus.asset,
                                  label: _venus.label,
                                  enabled: !_busy,
                                  onTap: _openOverlayAndBackground,
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ],
                  );
                },
              ),
            ),
            if (_busy)
              Positioned.fill(
                child: ColoredBox(
                  color: Colors.black.withValues(alpha: 0.25),
                  child: const Center(
                    child: CircularProgressIndicator(
                      color: Color(0xFFFF5252),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _ProfileStrip extends StatelessWidget {
  const _ProfileStrip({required this.profile});

  final SessionUser? profile;

  @override
  Widget build(BuildContext context) {
    final name = profile?.username.trim() ?? '';
    return Row(
      children: [
        Icon(Icons.person_rounded,
            color: Colors.white.withValues(alpha: 0.85), size: 22),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            name.isEmpty ? '—' : name,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w600,
              fontSize: 16,
            ),
          ),
        ),
      ],
    );
  }
}

class _LobbyCard extends StatelessWidget {
  const _LobbyCard({
    required this.asset,
    required this.label,
    required this.onTap,
    this.enabled = true,
  });

  final String asset;
  final String label;
  final VoidCallback onTap;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: enabled ? onTap : null,
        borderRadius: BorderRadius.circular(12),
        child: Ink(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            boxShadow: [
              BoxShadow(
                color: const Color(0xFFB71C1C).withValues(alpha: 0.35),
                blurRadius: 12,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: Stack(
              fit: StackFit.expand,
              children: [
                Image.asset(
                  asset,
                  fit: BoxFit.cover,
                  filterQuality: FilterQuality.high,
                  errorBuilder: (context, e, st) => ColoredBox(
                    color: Colors.grey.shade900,
                    child: const Icon(Icons.broken_image, color: Colors.white54),
                  ),
                ),
                Positioned(
                  left: 0,
                  right: 0,
                  bottom: 0,
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.bottomCenter,
                        end: Alignment.topCenter,
                        colors: [
                          Colors.black.withValues(alpha: 0.75),
                          Colors.transparent,
                        ],
                      ),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(8, 16, 8, 8),
                      child: Text(
                        label,
                        textAlign: TextAlign.center,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          shadows: [
                            Shadow(
                              color: Colors.black87,
                              blurRadius: 6,
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
