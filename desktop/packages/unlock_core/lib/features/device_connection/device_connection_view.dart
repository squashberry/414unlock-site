import 'package:flutter/material.dart';
import '../../core/auth/auth_service.dart';
import '../../core/device/device_detection_service.dart';
import '../../core/prerequisites/setup_coordinator.dart';
import '../../theme/app_theme.dart';
import '../../widgets/app_button.dart';
import '../../widgets/device_card.dart';
import '../../widgets/device_illustration.dart';
import '../../widgets/troubleshoot_dialog.dart';

class DeviceConnectionView extends StatelessWidget {
  final DeviceDetectionService detectionService;
  final AppBrandVariant variant;
  final VoidCallback onContinue;
  final VoidCallback onBack;
  final AuthService? authService;
  final SetupCoordinator? setupCoordinator;
  final VoidCallback? onNeedSetup;
  final VoidCallback? onNavigateToAuth;

  const DeviceConnectionView({
    super.key,
    required this.detectionService,
    required this.variant,
    required this.onContinue,
    required this.onBack,
    this.authService,
    this.setupCoordinator,
    this.onNeedSetup,
    this.onNavigateToAuth,
  });

  @override
  Widget build(BuildContext context) {
    final isIos = variant == AppBrandVariant.iphone;
    final accentColor = isIos ? AppColors.iphoneBlue : AppColors.androidGreen;

    final listenables = <Listenable>[
      detectionService,
      ?authService,
      ?setupCoordinator,
    ];

    return ListenableBuilder(
      listenable: Listenable.merge(listenables),
      builder: (context, _) {
        final device = detectionService.currentDevice;
        final isConnected = device != null;
        final auth = authService;

        return Scaffold(
          backgroundColor: AppColors.background,
          body: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 24),
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 720),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    // Top navigation / Back
                    Align(
                      alignment: Alignment.centerLeft,
                      child: TextButton.icon(
                        onPressed: onBack,
                        icon: Icon(
                          Icons.arrow_back_rounded,
                          size: 16,
                          color: AppColors.textSecondary,
                        ),
                        label: Text(
                          setupCoordinator != null ? 'Setup Requirements' : 'Prerequisites',
                          style: TextStyle(
                            fontSize: 12,
                            color: AppColors.textSecondary,
                          ),
                        ),
                      ),
                    ),

                    const SizedBox(height: 8),

                    // Title & Subtitle
                    Text(
                      isIos ? 'Connect your iPhone' : 'Connect your Android device',
                      style: TextStyle(
                        fontSize: 26,
                        fontWeight: FontWeight.w700,
                        color: AppColors.textPrimary,
                        letterSpacing: -0.4,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      isIos
                          ? 'Connect your iPhone to this PC using a certified Apple USB cable.'
                          : 'Connect your Android device to this PC using a USB cable.',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 14,
                        color: AppColors.textSecondary,
                      ),
                    ),

                    const SizedBox(height: 24),

                    // Large Central Device Illustration
                    DeviceIllustration(
                      variant: variant,
                      isConnected: isConnected,
                      device: device,
                      size: 160,
                    ),

                    const SizedBox(height: 20),

                    // Dynamic Device Status Banner
                    AnimatedSwitcher(
                      duration: const Duration(milliseconds: 300),
                      child: isConnected
                          ? Row(
                              key: const ValueKey('detected'),
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Container(
                                  width: 9,
                                  height: 9,
                                  decoration: const BoxDecoration(
                                    color: AppColors.success,
                                    shape: BoxShape.circle,
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Text(
                                  isIos ? 'iPhone Detected' : 'Android Device Detected',
                                  style: const TextStyle(
                                    fontSize: 15,
                                    fontWeight: FontWeight.w700,
                                    color: AppColors.success,
                                  ),
                                ),
                              ],
                            )
                          : Row(
                              key: const ValueKey('waiting'),
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                SizedBox(
                                  width: 14,
                                  height: 14,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    valueColor: AlwaysStoppedAnimation<Color>(accentColor),
                                  ),
                                ),
                                const SizedBox(width: 10),
                                Text(
                                  'Waiting for USB device connection...',
                                  style: TextStyle(
                                    fontSize: 15,
                                    fontWeight: FontWeight.w500,
                                    color: AppColors.textSecondary,
                                  ),
                                ),
                              ],
                            ),
                    ),

                    const SizedBox(height: 20),

                    // Device Card (when detected)
                    if (isConnected) ...[
                      DeviceCard(device: device, variant: variant),
                      const SizedBox(height: 16),
                    ] else ...[
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
                        decoration: AppColors.liquidGlassDecoration(
                          radius: 12,
                          elevated: false,
                        ),
                        child: Row(
                          children: [
                            Icon(
                              Icons.info_outline_rounded,
                              size: 18,
                              color: AppColors.textMuted,
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Text(
                                isIos
                                    ? 'Connect your iPhone at the Setup / Activation Lock screen. If the device is passcode-locked, put it into Recovery Mode and restore it with iTunes first.'
                                    : 'Ensure your Android device is unlocked and USB transfer / debugging is enabled if needed.',
                                style: TextStyle(
                                  fontSize: 12,
                                  color: AppColors.textSecondary,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 20),
                    ],

                    // Signed-in banner if authenticated
                    if (auth != null && auth.isAuthenticated) ...[
                      Container(
                        margin: const EdgeInsets.only(bottom: 16),
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                        decoration: AppColors.liquidGlassDecoration(
                          radius: 10,
                          elevated: false,
                        ),
                        child: Row(
                          children: [
                            const Icon(Icons.verified_user_rounded, color: AppColors.success, size: 16),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                'Authorized Account: ${auth.user?.email ?? "Signed in"}',
                                style: TextStyle(fontSize: 12, color: AppColors.textSecondary),
                              ),
                            ),
                            TextButton(
                              onPressed: onNavigateToAuth,
                              child: const Text('Account Details', style: TextStyle(fontSize: 11, color: AppColors.iphoneBlue)),
                            ),
                          ],
                        ),
                      ),
                    ],

                    // Action Buttons
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        AppButton(
                          text: 'Troubleshoot connection',
                          icon: Icons.help_outline_rounded,
                          variant: AppButtonVariant.secondary,
                          height: 42,
                          onPressed: () {
                            showDialog(
                              context: context,
                              builder: (_) => TroubleshootDialog(variant: variant),
                            );
                          },
                        ),
                        const SizedBox(width: 14),
                        AppButton(
                          text: isIos
                              ? (isConnected
                                  ? (device.requiresRestore
                                      ? 'Restore Required in iTunes'
                                      : 'Start Unlock — ${device.name}')
                                  : 'Start Unlock')
                              : 'Continue',
                          icon: isConnected && device.requiresRestore
                              ? Icons.build_circle_outlined
                              : Icons.play_arrow_rounded,
                          variant: isConnected && device.requiresRestore
                              ? AppButtonVariant.secondary
                              : AppButtonVariant.primary,
                          height: 42,
                          onPressed: isConnected
                              ? () {
                                  if (device.requiresRestore) {
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      const SnackBar(
                                        content: Text(
                                          'This device is passcode-locked or in diagnostic mode. Please restore it via iTunes/Finder to reach the Hello / Setup screen before proceeding.',
                                        ),
                                      ),
                                    );
                                    return;
                                  }
                                  if (setupCoordinator != null && !setupCoordinator!.isReady) {
                                    if (onNeedSetup != null) {
                                      onNeedSetup!();
                                      return;
                                    }
                                  }
                                  // If authentication is required and user is not signed in, navigate to dedicated auth page
                                  if (auth != null && !auth.isAuthenticated && onNavigateToAuth != null) {
                                    onNavigateToAuth!();
                                    return;
                                  }
                                  onContinue();
                                }
                              : null,
                        ),
                      ],
                    ),

                    if (isIos && auth != null && isConnected && !auth.isAuthenticated) ...[
                      const SizedBox(height: 10),
                      Text(
                        'Note: You will be prompted to sign in with your 414Unlock account when starting the unlock.',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 12,
                          color: AppColors.textMuted,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}