import 'package:flutter/material.dart';
import '../theme/app_theme.dart';

enum AppButtonVariant {
  primary,
  secondary,
  outline,
  danger,
}

class AppButton extends StatefulWidget {
  final String text;
  final VoidCallback? onPressed;
  final AppButtonVariant variant;
  final IconData? icon;
  final bool isLoading;
  final Color? customAccent;
  final double? width;
  final double height;

  const AppButton({
    super.key,
    required this.text,
    required this.onPressed,
    this.variant = AppButtonVariant.primary,
    this.icon,
    this.isLoading = false,
    this.customAccent,
    this.width,
    this.height = 40,
  });

  @override
  State<AppButton> createState() => _AppButtonState();
}

class _AppButtonState extends State<AppButton> {
  bool _isHovered = false;
  bool _isPressed = false;

  @override
  Widget build(BuildContext context) {
    final isDark = AppColors.isDark;
    final isEnabled = widget.onPressed != null && !widget.isLoading;
    final accent = widget.customAccent ?? AppColors.iphoneBlue;

    // Determine colors and liquid glass decorations
    Gradient? gradient;
    Color? solidBg;
    Color fg;
    Border border;
    List<BoxShadow> shadows = [];

    switch (widget.variant) {
      case AppButtonVariant.primary:
        if (!isEnabled) {
          solidBg = isDark ? const Color(0x22FFFFFF) : const Color(0xFFE2E8F0);
          fg = isDark ? const Color(0x55FFFFFF) : const Color(0xFF94A3B8);
          border = Border.all(color: Colors.transparent);
        } else {
          gradient = LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: _isHovered
                ? [const Color(0xFF38A8FF), const Color(0xFF0075EC)]
                : [const Color(0xFF2898FF), const Color(0xFF006FE0)],
          );
          fg = Colors.white;
          border = Border.all(
            color: Colors.white.withValues(alpha: 0.35),
            width: 1.0,
          );
          shadows = [
            BoxShadow(
              color: accent.withValues(alpha: _isHovered ? 0.42 : 0.28),
              blurRadius: _isHovered ? 14 : 8,
              offset: const Offset(0, 3),
            ),
            const BoxShadow(
              color: Color(0x18000000),
              blurRadius: 2,
              offset: Offset(0, 1),
            ),
          ];
        }
        break;

      case AppButtonVariant.secondary:
        if (!isEnabled) {
          solidBg = isDark ? const Color(0x11FFFFFF) : const Color(0x08000000);
          fg = isDark ? const Color(0x44FFFFFF) : const Color(0xFF94A3B8);
          border = Border.all(color: Colors.transparent);
        } else {
          gradient = LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: isDark
                ? (_isHovered
                    ? [const Color(0x3DFFFFFF), const Color(0x26FFFFFF)]
                    : [const Color(0x2EFFFFFF), const Color(0x1AFFFFFF)])
                : (_isHovered
                    ? [const Color(0xFFFFFFFF), const Color(0xF2F0F4F9)]
                    : [const Color(0xF7FFFFFF), const Color(0xE8F2F6FB)]),
          );
          fg = AppColors.textPrimary;
          border = Border.all(
            color: isDark
                ? Colors.white.withValues(alpha: 0.18)
                : const Color(0x18000000),
            width: 1.0,
          );
          shadows = [
            BoxShadow(
              color: isDark ? const Color(0x40000000) : const Color(0x0A0F172A),
              blurRadius: _isHovered ? 8 : 4,
              offset: const Offset(0, 2),
            ),
          ];
        }
        break;

      case AppButtonVariant.outline:
        solidBg = _isHovered
            ? (accent.withValues(alpha: isDark ? 0.16 : 0.08))
            : Colors.transparent;
        fg = isEnabled ? accent : AppColors.textMuted;
        border = Border.all(
          color: isEnabled
              ? accent.withValues(alpha: _isHovered ? 0.8 : 0.45)
              : AppColors.cardBorder,
          width: 1.1,
        );
        break;

      case AppButtonVariant.danger:
        // Glossy red pill matching iOS 26 / macOS Delete button
        gradient = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: _isHovered
              ? [const Color(0xFFFF5247), const Color(0xFFE6251B)]
              : [const Color(0xFFFF453A), const Color(0xFFD61D14)],
        );
        fg = Colors.white;
        border = Border.all(
          color: Colors.white.withValues(alpha: 0.35),
          width: 1.0,
        );
        shadows = [
          BoxShadow(
            color: AppColors.error.withValues(alpha: _isHovered ? 0.4 : 0.25),
            blurRadius: _isHovered ? 12 : 6,
            offset: const Offset(0, 3),
          ),
        ];
        break;
    }

    return MouseRegion(
      onEnter: (_) {
        if (isEnabled && mounted) setState(() => _isHovered = true);
      },
      onExit: (_) {
        if (isEnabled && mounted) setState(() => _isHovered = false);
      },
      cursor: isEnabled ? SystemMouseCursors.click : SystemMouseCursors.basic,
      child: GestureDetector(
        onTapDown: (_) {
          if (isEnabled && mounted) setState(() => _isPressed = true);
        },
        onTapUp: (_) {
          if (isEnabled && mounted) setState(() => _isPressed = false);
        },
        onTapCancel: () {
          if (isEnabled && mounted) setState(() => _isPressed = false);
        },
        onTap: isEnabled ? widget.onPressed : null,
        child: AnimatedScale(
          scale: _isPressed ? 0.97 : (_isHovered && isEnabled ? 1.015 : 1.0),
          duration: const Duration(milliseconds: 120),
          curve: Curves.easeOutCubic,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 160),
            curve: Curves.easeOutCubic,
            width: widget.width,
            height: widget.height,
            decoration: BoxDecoration(
              gradient: gradient,
              color: solidBg,
              borderRadius: BorderRadius.circular(12),
              border: border,
              boxShadow: shadows,
            ),
            child: Stack(
              children: [
                // Top subtle specular reflection sheen
                if (gradient != null)
                  Positioned(
                    top: 0,
                    left: 4,
                    right: 4,
                    height: widget.height * 0.45,
                    child: Container(
                      decoration: BoxDecoration(
                        borderRadius: const BorderRadius.vertical(
                          top: Radius.circular(11),
                        ),
                        gradient: LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: [
                            Colors.white.withValues(alpha: 0.22),
                            Colors.white.withValues(alpha: 0.0),
                          ],
                        ),
                      ),
                    ),
                  ),

                // Content (Icon, Loading, Label)
                Center(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 18),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        if (widget.isLoading) ...[
                          SizedBox(
                            width: 14,
                            height: 14,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              valueColor: AlwaysStoppedAnimation<Color>(fg),
                            ),
                          ),
                          const SizedBox(width: 8),
                        ] else if (widget.icon != null) ...[
                          Icon(widget.icon, size: 16, color: fg),
                          const SizedBox(width: 8),
                        ],
                        Text(
                          widget.text,
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            color: fg,
                            letterSpacing: -0.1,
                          ),
                        ),
                      ],
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