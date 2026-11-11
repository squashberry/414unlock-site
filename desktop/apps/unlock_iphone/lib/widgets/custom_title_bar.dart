import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:unlock_core/unlock_core.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:window_manager/window_manager.dart';

import 'close_confirmation_dialog.dart';

/// Premium macOS-style title bar with top-left traffic lights, liquid glass
/// aesthetics, and integrated help/settings controls.
class CustomTitleBar extends StatefulWidget {
  final VoidCallback? onCloseRequested;

  const CustomTitleBar({
    super.key,
    this.onCloseRequested,
  });

  @override
  State<CustomTitleBar> createState() => _CustomTitleBarState();
}

class _CustomTitleBarState extends State<CustomTitleBar> with WindowListener {
  bool _isMaximized = false;
  bool _isHoveringTrafficLights = false;

  static const String _kSupportUrl = 'https://414unlock.pages.dev/support.html';

  @override
  void initState() {
    super.initState();
    if (!kIsWeb &&
        defaultTargetPlatform == TargetPlatform.windows &&
        !Platform.environment.containsKey('FLUTTER_TEST')) {
      try {
        windowManager.addListener(this);
        _checkMaximized();
      } catch (_) {}
    }
  }

  @override
  void dispose() {
    if (!kIsWeb && defaultTargetPlatform == TargetPlatform.windows) {
      try {
        windowManager.removeListener(this);
      } catch (_) {}
    }
    super.dispose();
  }

  Future<void> _checkMaximized() async {
    try {
      final max = await windowManager.isMaximized();
      if (mounted) {
        setState(() => _isMaximized = max);
      }
    } catch (_) {}
  }

  @override
  void onWindowMaximize() {
    if (mounted) setState(() => _isMaximized = true);
  }

  @override
  void onWindowUnmaximize() {
    if (mounted) setState(() => _isMaximized = false);
  }

  Future<void> _handleMinimize() async {
    if (Platform.environment.containsKey('FLUTTER_TEST')) return;
    try {
      await windowManager.minimize().timeout(const Duration(milliseconds: 500));
    } catch (_) {}
  }

  Future<void> _handleMaximizeToggle() async {
    if (Platform.environment.containsKey('FLUTTER_TEST')) {
      if (mounted) setState(() => _isMaximized = !_isMaximized);
      return;
    }
    try {
      final max = await windowManager.isMaximized().timeout(const Duration(milliseconds: 500));
      if (max) {
        await windowManager.unmaximize().timeout(const Duration(milliseconds: 500));
      } else {
        await windowManager.maximize().timeout(const Duration(milliseconds: 500));
      }
      _checkMaximized();
    } catch (_) {}
  }

  void _handleClose() {
    if (widget.onCloseRequested != null) {
      widget.onCloseRequested!();
    } else {
      CloseConfirmationDialog.show(context);
    }
  }

  Future<void> _openSupport() async {
    try {
      final uri = Uri.parse(_kSupportUrl);
      if (await canLaunchUrl(uri)) {
        await launchUrl(uri, mode: LaunchMode.externalApplication);
      }
    } catch (_) {}
  }

  void _openDiagnostics() {
    showDialog(
      context: context,
      builder: (ctx) => const LogViewerDialog(variant: AppBrandVariant.iphone),
    );
  }

  void _openSettings() {
    showDialog(
      context: context,
      builder: (ctx) => const SettingsDialog(variant: AppBrandVariant.iphone),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = AppColors.isDark;

    return Container(
      height: 42,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: isDark
              ? [const Color(0x33283344), const Color(0x1F1E2633)]
              : [const Color(0xF5FFFFFF), const Color(0xE6F2F5FA)],
        ),
        border: Border(
          bottom: BorderSide(
            color: isDark
                ? Colors.white.withValues(alpha: 0.08)
                : const Color(0x14000000),
            width: 1,
          ),
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // 1. macOS Traffic Lights on Top Left (Red, Yellow, Green)
          // Matches user reference media_1793322886303.png
          MouseRegion(
            onEnter: (_) => setState(() => _isHoveringTrafficLights = true),
            onExit: (_) => setState(() => _isHoveringTrafficLights = false),
            child: Container(
              padding: const EdgeInsets.only(left: 14, right: 12),
              alignment: Alignment.centerLeft,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Red: Close
                  _TrafficLightCircle(
                    color: const Color(0xFFFF5F56),
                    icon: Icons.close_rounded,
                    showIcon: _isHoveringTrafficLights,
                    tooltip: 'Close 414Unlock',
                    onTap: _handleClose,
                  ),
                  const SizedBox(width: 8),
                  // Yellow: Minimize
                  _TrafficLightCircle(
                    color: const Color(0xFFFFBD2E),
                    icon: Icons.remove_rounded,
                    showIcon: _isHoveringTrafficLights,
                    tooltip: 'Minimize',
                    onTap: _handleMinimize,
                  ),
                  const SizedBox(width: 8),
                  // Green: Maximize / Zoom
                  _TrafficLightCircle(
                    color: const Color(0xFF27C93F),
                    icon: _isMaximized ? Icons.filter_none_rounded : Icons.crop_square_rounded,
                    showIcon: _isHoveringTrafficLights,
                    tooltip: _isMaximized ? 'Restore' : 'Zoom Window',
                    onTap: _handleMaximizeToggle,
                  ),
                ],
              ),
            ),
          ),

          // 2. Center Draggable Title Area
          Expanded(
            child: DragToMoveArea(
              child: GestureDetector(
                behavior: HitTestBehavior.translucent,
                onDoubleTap: _handleMaximizeToggle,
                child: Row(
                  children: [
                    const SizedBox(width: 6),
                    // App Brand Icon
                    ClipRRect(
                      borderRadius: BorderRadius.circular(4),
                      child: Image.asset(
                        'assets/icons/app_icon.png',
                        width: 18,
                        height: 18,
                        fit: BoxFit.contain,
                        errorBuilder: (context, error, stackTrace) => Container(
                          width: 18,
                          height: 18,
                          decoration: BoxDecoration(
                            color: AppColors.iphoneBlue.withValues(alpha: 0.18),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: const Icon(
                            Icons.phone_iphone_rounded,
                            size: 13,
                            color: AppColors.iphoneBlue,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    // App Title
                    Text(
                      '414Unlock',
                      style: TextStyle(
                        fontSize: 12.5,
                        fontWeight: FontWeight.w700,
                        color: AppColors.textPrimary,
                        letterSpacing: -0.2,
                      ),
                    ),
                    const SizedBox(width: 6),
                    Flexible(
                      child: Text(
                        '— iPhone Device Utility',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 11.5,
                          fontWeight: FontWeight.w400,
                          color: AppColors.textSecondary,
                          letterSpacing: 0.1,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),

          // 3. Top-Right macOS Utility Toolbar (Help, Logs, Settings)
          Row(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              // Update button (visible when update is available)
              ListenableBuilder(
                listenable: AppUpdateService(),
                builder: (context, _) {
                  final update = AppUpdateService().latestResult;
                  if (update == null || !update.updateAvailable) {
                    return const SizedBox.shrink();
                  }
                  return Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      _TitleBarIconButton(
                        icon: Icons.system_update_rounded,
                        tooltip: 'Update Available: v${update.latestVersion}',
                        color: AppColors.iphoneBlue,
                        onPressed: () {
                          final url = update.releaseUrl;
                          if (url.startsWith('https://')) {
                            launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
                          }
                        },
                      ),
                      const SizedBox(width: 2),
                    ],
                  );
                },
              ),
              // Help & Support button (pointing to support website requested by user)
              _TitleBarIconButton(
                icon: Icons.help_outline_rounded,
                tooltip: 'Help & Support (Online Guide)',
                onPressed: _openSupport,
              ),
              const SizedBox(width: 2),
              // Diagnostics & Logs button
              _TitleBarIconButton(
                icon: Icons.terminal_rounded,
                tooltip: 'Diagnostics & Logs',
                onPressed: _openDiagnostics,
              ),
              const SizedBox(width: 2),
              // Settings & Theme picker button
              _TitleBarIconButton(
                icon: Icons.settings_outlined,
                tooltip: 'Settings & Appearance',
                onPressed: _openSettings,
              ),
              const SizedBox(width: 8),
            ],
          ),
        ],
      ),
    );
  }
}

/// A macOS-style circular traffic light button (Close/Minimize/Zoom)
/// with micro-symbols revealed on hover.
class _TrafficLightCircle extends StatelessWidget {
  final Color color;
  final IconData icon;
  final bool showIcon;
  final String tooltip;
  final VoidCallback onTap;

  const _TrafficLightCircle({
    required this.color,
    required this.icon,
    required this.showIcon,
    required this.tooltip,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      waitDuration: const Duration(milliseconds: 500),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: Container(
          width: 12.5,
          height: 12.5,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            gradient: RadialGradient(
              center: const Alignment(-0.25, -0.35),
              radius: 0.85,
              colors: [
                Color.lerp(color, Colors.white, 0.45)!,
                color,
                Color.lerp(color, Colors.black, 0.25)!,
              ],
              stops: const [0.0, 0.55, 1.0],
            ),
            border: Border.all(
              color: Colors.black.withValues(alpha: 0.22),
              width: 0.75,
            ),
            boxShadow: [
              BoxShadow(
                color: color.withValues(alpha: 0.35),
                blurRadius: 3,
                offset: const Offset(0, 1),
              ),
            ],
          ),
          alignment: Alignment.center,
          child: AnimatedOpacity(
            opacity: showIcon ? 1.0 : 0.0,
            duration: const Duration(milliseconds: 140),
            child: Icon(
              icon,
              size: 8,
              color: const Color(0xDD000000),
            ),
          ),
        ),
      ),
    );
  }
}

/// Subtle translucent icon button in title bar.
class _TitleBarIconButton extends StatefulWidget {
  final IconData icon;
  final String tooltip;
  final VoidCallback onPressed;
  final Color? color;

  const _TitleBarIconButton({
    required this.icon,
    required this.tooltip,
    required this.onPressed,
    this.color,
  });

  @override
  State<_TitleBarIconButton> createState() => _TitleBarIconButtonState();
}

class _TitleBarIconButtonState extends State<_TitleBarIconButton> {
  bool _isHovered = false;

  @override
  Widget build(BuildContext context) {
    final isDark = AppColors.isDark;

    return Tooltip(
      message: widget.tooltip,
      waitDuration: const Duration(milliseconds: 400),
      child: MouseRegion(
        onEnter: (_) => setState(() => _isHovered = true),
        onExit: (_) => setState(() => _isHovered = false),
        cursor: SystemMouseCursors.click,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: widget.onPressed,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 150),
            width: 28,
            height: 28,
            margin: const EdgeInsets.symmetric(horizontal: 2),
            decoration: BoxDecoration(
              color: _isHovered
                  ? (isDark
                      ? Colors.white.withValues(alpha: 0.12)
                      : Colors.black.withValues(alpha: 0.07))
                  : Colors.transparent,
              borderRadius: BorderRadius.circular(6),
            ),
            alignment: Alignment.center,
            child: Icon(
              widget.icon,
              size: 16,
              color: widget.color ??
                  (_isHovered ? AppColors.textPrimary : AppColors.textSecondary),
            ),
          ),
        ),
      ),
    );
  }
}
