import 'package:flutter/material.dart';
import '../theme/app_theme.dart';
import 'app_button.dart';

class TroubleshootDialog extends StatelessWidget {
  final AppBrandVariant variant;

  const TroubleshootDialog({
    super.key,
    required this.variant,
  });

  @override
  Widget build(BuildContext context) {
    final isIos = variant == AppBrandVariant.iphone;
    final accentColor = isIos ? AppColors.iphoneBlue : AppColors.androidGreen;

    return Dialog(
      backgroundColor: AppColors.cardElevated,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: AppColors.cardBorder, width: 1),
      ),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 540),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Title Row
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: accentColor.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Icon(
                      Icons.help_outline_rounded,
                      color: accentColor,
                      size: 22,
                    ),
                  ),
                  const SizedBox(width: 14),
                  Text(
                    'Connection Troubleshooting',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w700,
                      color: AppColors.textPrimary,
                    ),
                  ),
                  const Spacer(),
                  IconButton(
                    icon: Icon(Icons.close_rounded,
                        size: 20, color: AppColors.textSecondary),
                    splashRadius: 18,
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ],
              ),

              const SizedBox(height: 18),
              Text(
                'If your computer cannot communicate with the device, follow these standard diagnostic checks:',
                style: TextStyle(
                  fontSize: 13,
                  color: AppColors.textSecondary,
                  height: 1.4,
                ),
              ),

              const SizedBox(height: 16),

              // Checklist Items
              _buildStep(
                icon: Icons.cable_rounded,
                title: 'Check your USB cable',
                description:
                    'Ensure you are using an authentic, high-speed data transfer cable. Many third-party charging cables do not support data lines.',
              ),
              _buildStep(
                icon: Icons.usb_rounded,
                title: 'Try another USB port',
                description:
                    'Plug directly into a rear motherboard USB 3.0 port if using a desktop. Avoid unpowered USB hubs, keyboard passthroughs, or monitors.',
              ),
              _buildStep(
                icon: Icons.lock_open_rounded,
                title: 'Unlock the device screen',
                description:
                    'Modern operating systems disable USB data controllers when locked. Wake the screen and enter your passcode or PIN.',
              ),
              _buildStep(
                icon: Icons.verified_user_outlined,
                title: isIos ? 'Trust this Computer' : 'Allow USB Debugging',
                description: isIos
                    ? 'When the "Trust This Computer?" prompt appears on iOS, tap Trust and enter your device passcode.'
                    : 'If prompted with "Allow USB debugging?", check "Always allow from this computer" and tap OK.',
              ),
              _buildStep(
                icon: Icons.settings_system_daydream_rounded,
                title: isIos ? 'Verify Apple Software' : 'Verify Android Drivers',
                description: isIos
                    ? 'Make sure the official Apple Devices app from the Microsoft Store or iTunes is installed and active.'
                    : 'Ensure the official OEM USB driver or Google USB driver is registered in Windows Device Manager.',
              ),

              const SizedBox(height: 20),

              // Footer Action
              Align(
                alignment: Alignment.centerRight,
                child: AppButton(
                  text: 'Got it',
                  variant: AppButtonVariant.primary,
                  onPressed: () => Navigator.of(context).pop(),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildStep({
    required IconData icon,
    required String title,
    required String description,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 18, color: AppColors.textPrimary),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: AppColors.textPrimary,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  description,
                  style: TextStyle(
                    fontSize: 12,
                    color: AppColors.textSecondary,
                    height: 1.3,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}