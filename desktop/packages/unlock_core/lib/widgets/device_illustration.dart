import 'package:flutter/material.dart';
import '../core/device/device_info.dart';
import '../theme/app_theme.dart';

/// A realistic, model-aware iPhone & mobile device illustration.
///
/// Dynamically morphs between genuine Apple design archetypes based on
/// the connected device model:
/// - [IPhoneDesignFamily.touchId]: Forehead speaker/camera + bottom Touch ID Home button.
/// - [IPhoneDesignFamily.notched]: Edge-to-edge display with classic Apple Face ID notch.
/// - [IPhoneDesignFamily.dynamicIsland]: Modern flagship with floating pill cutout and thin bezels.
///
/// Features connected Apple Lightning/USB-C cable with the USB trident icon
/// and soft circular radar pulsing background.
class DeviceIllustration extends StatefulWidget {
  final AppBrandVariant variant;
  final bool isConnected;
  final DeviceInfo? device;
  final double size;

  const DeviceIllustration({
    super.key,
    required this.variant,
    required this.isConnected,
    this.device,
    this.size = 180,
  });

  @override
  State<DeviceIllustration> createState() => _DeviceIllustrationState();
}

class _DeviceIllustrationState extends State<DeviceIllustration>
    with SingleTickerProviderStateMixin {
  late AnimationController _pulseController;
  late Animation<double> _pulseAnimation;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2200),
    )..repeat();

    _pulseAnimation = Tween<double>(begin: 0.95, end: 1.05).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _pulseController.dispose();
    super.dispose();
  }

  IPhoneDesignFamily _resolveFamily() {
    if (widget.device != null) {
      return widget.device!.iphoneDesignFamily;
    }
    return IPhoneDesignFamily.dynamicIsland;
  }

  @override
  Widget build(BuildContext context) {
    final isIos = widget.variant == AppBrandVariant.iphone;
    final family = isIos ? _resolveFamily() : IPhoneDesignFamily.dynamicIsland;
    final isDark = AppColors.isDark;
    final accentColor = isIos ? AppColors.iphoneBlue : AppColors.androidGreen;

    final phoneWidth = widget.size * 0.72;
    final phoneHeight = widget.size * 1.44;

    return AnimatedBuilder(
      animation: _pulseAnimation,
      builder: (context, child) {
        final pulseScale = widget.isConnected ? 1.0 : _pulseAnimation.value;

        return SizedBox(
          width: widget.size * 1.5,
          height: widget.size * 1.7,
          child: Stack(
            alignment: Alignment.center,
            clipBehavior: Clip.none,
            children: [
              // 1. Soft Circular Radar Background Halo (matches reference media_1793322886292.png)
              _buildRadarPulse(pulseScale, accentColor),

              // 2. Realistic Side Hardware Buttons (Volume, Power, Action)
              _buildHardwareButtons(phoneWidth, phoneHeight, isDark),

              // 3. Main Phone Chassis (Realistic metallic rim + OLED Display)
              Transform.scale(
                scale: pulseScale,
                child: Container(
                  width: phoneWidth,
                  height: phoneHeight,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(
                      family == IPhoneDesignFamily.touchId ? 24 : 28,
                    ),
                    gradient: LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: isDark
                          ? [
                              const Color(0xFF2C3240),
                              const Color(0xFF151922),
                              const Color(0xFF0F131A),
                            ]
                          : [
                              const Color(0xFFE2E8F0),
                              const Color(0xFFF1F5F9),
                              const Color(0xFFCBD5E1),
                            ],
                    ),
                    border: Border.all(
                      color: widget.isConnected
                          ? accentColor.withValues(alpha: 0.8)
                          : (isDark ? const Color(0xFF334155) : const Color(0xFF94A3B8)),
                      width: widget.isConnected ? 2.0 : 1.5,
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: widget.isConnected
                            ? accentColor.withValues(alpha: isDark ? 0.25 : 0.18)
                            : (isDark
                                ? Colors.black.withValues(alpha: 0.5)
                                : const Color(0x1F0F172A)),
                        blurRadius: 26,
                        spreadRadius: widget.isConnected ? 2 : 0,
                        offset: const Offset(0, 10),
                      ),
                    ],
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(4.0),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(
                        family == IPhoneDesignFamily.touchId ? 20 : 24,
                      ),
                      child: Container(
                        decoration: BoxDecoration(
                          color: isDark ? const Color(0xFF05070A) : const Color(0xFFF8FAFC),
                        ),
                        child: _buildScreenContent(
                          family: family,
                          isIos: isIos,
                          isDark: isDark,
                          accentColor: accentColor,
                          phoneWidth: phoneWidth,
                          phoneHeight: phoneHeight,
                        ),
                      ),
                    ),
                  ),
                ),
              ),

              // 4. Connected USB / Lightning Cable at the bottom (matches reference media_1793322886292.png)
              Positioned(
                bottom: 2,
                child: _buildUsbCable(accentColor, isDark),
              ),
            ],
          ),
        );
      },
    );
  }

  /// Circular radar pulse ripple behind phone.
  Widget _buildRadarPulse(double scale, Color accentColor) {
    if (widget.isConnected) {
      return Container(
        width: widget.size * 1.3,
        height: widget.size * 1.3,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: RadialGradient(
            colors: [
              accentColor.withValues(alpha: 0.18),
              accentColor.withValues(alpha: 0.05),
              Colors.transparent,
            ],
            stops: const [0.0, 0.6, 1.0],
          ),
        ),
      );
    }

    return Container(
      width: widget.size * 1.35 * scale,
      height: widget.size * 1.35 * scale,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(
          color: accentColor.withValues(
            alpha: (1.06 - scale).clamp(0.05, 0.35),
          ),
          width: 1.5,
        ),
      ),
    );
  }

  /// Outer side hardware buttons (Power button on right, Volume on left).
  Widget _buildHardwareButtons(double w, double h, bool isDark) {
    final buttonColor = isDark ? const Color(0xFF334155) : const Color(0xFF94A3B8);

    return SizedBox(
      width: w + 6,
      height: h,
      child: Stack(
        children: [
          // Left: Mute / Action switch
          Positioned(
            left: 0,
            top: h * 0.18,
            child: Container(
              width: 2.5,
              height: 12,
              decoration: BoxDecoration(
                color: buttonColor,
                borderRadius: BorderRadius.circular(1.5),
              ),
            ),
          ),
          // Left: Volume Up
          Positioned(
            left: 0,
            top: h * 0.26,
            child: Container(
              width: 2.5,
              height: 22,
              decoration: BoxDecoration(
                color: buttonColor,
                borderRadius: BorderRadius.circular(1.5),
              ),
            ),
          ),
          // Left: Volume Down
          Positioned(
            left: 0,
            top: h * 0.38,
            child: Container(
              width: 2.5,
              height: 22,
              decoration: BoxDecoration(
                color: buttonColor,
                borderRadius: BorderRadius.circular(1.5),
              ),
            ),
          ),
          // Right: Power / Side button
          Positioned(
            right: 0,
            top: h * 0.28,
            child: Container(
              width: 2.5,
              height: 32,
              decoration: BoxDecoration(
                color: buttonColor,
                borderRadius: BorderRadius.circular(1.5),
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// Internal screen area: Top status bar, model-specific cutout/chin, center display.
  Widget _buildScreenContent({
    required IPhoneDesignFamily family,
    required bool isIos,
    required bool isDark,
    required Color accentColor,
    required double phoneWidth,
    required double phoneHeight,
  }) {
    return Stack(
      children: [
        // Subtle ambient screen backlight
        Positioned.fill(
          child: Container(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: widget.isConnected
                    ? [
                        accentColor.withValues(alpha: isDark ? 0.08 : 0.05),
                        isDark ? const Color(0xFF090D14) : const Color(0xFFF1F5F9),
                      ]
                    : [
                        isDark ? const Color(0xFF090D14) : const Color(0xFFFFFFFF),
                        isDark ? const Color(0xFF05070A) : const Color(0xFFF1F5F9),
                      ],
              ),
            ),
          ),
        ),

        // 1. Status Bar (Time + Wifi + Cellular + Battery)
        Positioned(
          top: family == IPhoneDesignFamily.touchId ? 24 : 7,
          left: 12,
          right: 12,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              // Time
              Text(
                '9:41',
                style: TextStyle(
                  fontSize: 8.5,
                  fontWeight: FontWeight.w700,
                  color: isDark ? const Color(0xFFE2E8F0) : const Color(0xFF1E293B),
                  letterSpacing: -0.2,
                ),
              ),
              // Status Icons (Signal, Wifi, Battery)
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.signal_cellular_alt_rounded,
                    size: 9.5,
                    color: isDark ? const Color(0xFF94A3B8) : const Color(0xFF64748B),
                  ),
                  const SizedBox(width: 3),
                  Icon(
                    Icons.wifi_rounded,
                    size: 9.5,
                    color: isDark ? const Color(0xFF94A3B8) : const Color(0xFF64748B),
                  ),
                  const SizedBox(width: 4),
                  // Battery pill
                  Container(
                    width: 14,
                    height: 7,
                    padding: const EdgeInsets.all(1),
                    decoration: BoxDecoration(
                      border: Border.all(
                        color: isDark ? const Color(0xFF94A3B8) : const Color(0xFF64748B),
                        width: 1,
                      ),
                      borderRadius: BorderRadius.circular(2.5),
                    ),
                    child: Container(
                      decoration: BoxDecoration(
                        color: widget.isConnected ? AppColors.success : accentColor,
                        borderRadius: BorderRadius.circular(1),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),

        // 2. Model Cutouts (Dynamic Island vs Notch vs Touch ID Forehead)
        if (family == IPhoneDesignFamily.dynamicIsland)
          Positioned(
            top: 7,
            left: 0,
            right: 0,
            child: Center(
              child: Container(
                width: 36,
                height: 9,
                decoration: BoxDecoration(
                  color: Colors.black,
                  borderRadius: BorderRadius.circular(5),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    Container(
                      width: 4,
                      height: 4,
                      margin: const EdgeInsets.only(right: 3),
                      decoration: const BoxDecoration(
                        shape: BoxShape.circle,
                        color: Color(0xFF0F172A),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          )
        else if (family == IPhoneDesignFamily.notched)
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: Center(
              child: Container(
                width: 46,
                height: 9,
                decoration: const BoxDecoration(
                  color: Colors.black,
                  borderRadius: BorderRadius.vertical(bottom: Radius.circular(7)),
                ),
                child: Center(
                  child: Container(
                    width: 18,
                    height: 2,
                    decoration: BoxDecoration(
                      color: const Color(0xFF1E293B),
                      borderRadius: BorderRadius.circular(1),
                    ),
                  ),
                ),
              ),
            ),
          )
        else if (family == IPhoneDesignFamily.touchId) ...[
          // Top Forehead bezel with speaker & camera
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            height: 22,
            child: Container(
              color: isDark ? const Color(0xFF0B0E14) : const Color(0xFFE2E8F0),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  // Camera dot
                  Container(
                    width: 4,
                    height: 4,
                    decoration: const BoxDecoration(
                      shape: BoxShape.circle,
                      color: Color(0xFF0F172A),
                    ),
                  ),
                  const SizedBox(width: 8),
                  // Speaker slit
                  Container(
                    width: 26,
                    height: 3,
                    decoration: BoxDecoration(
                      color: isDark ? const Color(0xFF1E293B) : const Color(0xFF94A3B8),
                      borderRadius: BorderRadius.circular(1.5),
                    ),
                  ),
                ],
              ),
            ),
          ),
          // Bottom Chin bezel with Touch ID Home button
          Positioned(
            bottom: 0,
            left: 0,
            right: 0,
            height: 26,
            child: Container(
              color: isDark ? const Color(0xFF0B0E14) : const Color(0xFFE2E8F0),
              alignment: Alignment.center,
              child: Container(
                width: 20,
                height: 20,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: isDark ? const Color(0xFF05070A) : Colors.white,
                  border: Border.all(
                    color: isDark ? const Color(0xFF475569) : const Color(0xFF94A3B8),
                    width: 1.5,
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.1),
                      blurRadius: 2,
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],

        // 3. Center Screen Graphics
        Positioned.fill(
          top: family == IPhoneDesignFamily.touchId ? 24 : 20,
          bottom: family == IPhoneDesignFamily.touchId ? 28 : 16,
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              if (widget.isConnected) ...[
                // Connected Brand Icon (Apple or Android)
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: accentColor.withValues(alpha: 0.12),
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: accentColor.withValues(alpha: 0.35),
                      width: 1,
                    ),
                  ),
                  child: Icon(
                    isIos ? Icons.phone_iphone_rounded : Icons.phone_android_rounded,
                    size: 24,
                    color: accentColor,
                  ),
                ),
                const SizedBox(height: 10),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 10),
                  child: Text(
                    widget.device?.name ?? (isIos ? 'iPhone Connected' : 'Android Device'),
                    textAlign: TextAlign.center,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 10.5,
                      fontWeight: FontWeight.w700,
                      color: isDark ? const Color(0xFFF8FAFC) : const Color(0xFF0F172A),
                    ),
                  ),
                ),
                const SizedBox(height: 2),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: AppColors.success.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(4),
                    border: Border.all(
                      color: AppColors.success.withValues(alpha: 0.4),
                      width: 0.8,
                    ),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        width: 4,
                        height: 4,
                        decoration: const BoxDecoration(
                          color: AppColors.success,
                          shape: BoxShape.circle,
                        ),
                      ),
                      const SizedBox(width: 4),
                      Text(
                        widget.device?.mode.label ?? 'Connected',
                        style: const TextStyle(
                          fontSize: 8,
                          fontWeight: FontWeight.w600,
                          color: AppColors.success,
                        ),
                      ),
                    ],
                  ),
                ),
              ] else ...[
                // Waiting for connection prompt
                Container(
                  width: 42,
                  height: 42,
                  decoration: BoxDecoration(
                    color: (isDark ? Colors.white : Colors.black).withValues(alpha: 0.05),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    Icons.cable_rounded,
                    size: 22,
                    color: isDark ? const Color(0xFF64748B) : const Color(0xFF94A3B8),
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  isIos ? 'Connect iPhone' : 'Connect Device',
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w600,
                    color: isDark ? const Color(0xFF94A3B8) : const Color(0xFF64748B),
                  ),
                ),
              ],
            ],
          ),
        ),

        // 4. Apple Home Indicator Bar (for notched and dynamic island phones)
        if (family != IPhoneDesignFamily.touchId)
          Positioned(
            bottom: 5,
            left: 0,
            right: 0,
            child: Center(
              child: Container(
                width: 38,
                height: 2.5,
                decoration: BoxDecoration(
                  color: isDark
                      ? const Color(0xFF475569).withValues(alpha: 0.8)
                      : const Color(0xFF94A3B8).withValues(alpha: 0.9),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
          ),
      ],
    );
  }

  /// Connected USB-C / Lightning Cable with USB Trident symbol
  /// Exactly matches reference image media_1793322886292.png.
  Widget _buildUsbCable(Color accentColor, bool isDark) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // Lightning / USB-C Plug Head
        Container(
          width: 18,
          height: 14,
          decoration: BoxDecoration(
            color: isDark ? const Color(0xFF1E293B) : const Color(0xFFFFFFFF),
            borderRadius: BorderRadius.circular(4),
            border: Border.all(
              color: widget.isConnected
                  ? accentColor
                  : (isDark ? const Color(0xFF475569) : const Color(0xFFCBD5E1)),
              width: 1.2,
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.15),
                blurRadius: 4,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          alignment: Alignment.center,
          child: Icon(
            Icons.usb_rounded,
            size: 11,
            color: widget.isConnected
                ? accentColor
                : (isDark ? const Color(0xFF94A3B8) : const Color(0xFF64748B)),
          ),
        ),
        // Strain relief collar
        Container(
          width: 7,
          height: 5,
          color: isDark ? const Color(0xFF334155) : const Color(0xFFE2E8F0),
        ),
        // Flexible cable wire extending down
        Container(
          width: 4.5,
          height: 20,
          decoration: BoxDecoration(
            color: widget.isConnected
                ? accentColor.withValues(alpha: 0.9)
                : (isDark ? const Color(0xFF334155) : const Color(0xFFCBD5E1)),
            borderRadius: const BorderRadius.vertical(bottom: Radius.circular(2)),
          ),
        ),
      ],
    );
  }
}
