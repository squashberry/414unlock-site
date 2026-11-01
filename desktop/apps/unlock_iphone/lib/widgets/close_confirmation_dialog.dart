import 'dart:io';
import 'package:flutter/material.dart';
import 'package:tray_manager/tray_manager.dart';
import 'package:unlock_core/unlock_core.dart';
import 'package:window_manager/window_manager.dart';

/// Modal dialog prompting the user to either close the application or
/// minimize it to the system tray to preserve background device detection.
class CloseConfirmationDialog extends StatelessWidget {
  const CloseConfirmationDialog({super.key});

  /// Static helper to display the confirmation dialog.
  static Future<void> show(BuildContext context) async {
    return showDialog<void>(
      context: context,
      barrierDismissible: true,
      barrierColor: Colors.black.withValues(alpha: 0.45),
      builder: (dialogContext) => const CloseConfirmationDialog(),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Colors.transparent,
      elevation: 0,
      insetPadding: const EdgeInsets.symmetric(horizontal: 32, vertical: 24),
      child: Container(
        width: 440,
        padding: const EdgeInsets.all(24),
        decoration: AppColors.liquidGlassDecoration(
          radius: 18,
          elevated: true,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header icon and title
            Row(
              children: [
                Container(
                  width: 42,
                  height: 42,
                  decoration: BoxDecoration(
                    color: AppColors.warning.withValues(alpha: 0.12),
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: AppColors.warning.withValues(alpha: 0.35),
                      width: 1,
                    ),
                  ),
                  child: const Icon(
                    Icons.power_settings_new_rounded,
                    color: AppColors.warning,
                    size: 22,
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Close 414Unlock?',
                        style: TextStyle(
                          color: AppColors.textPrimary,
                          fontSize: 17,
                          fontWeight: FontWeight.w700,
                          letterSpacing: -0.3,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        'Confirm application exit',
                        style: TextStyle(
                          color: AppColors.textSecondary,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),

            const SizedBox(height: 18),

            // Question prompt
            Text(
              'Are you sure you want to close 414Unlock, or would you rather minimize it to the system tray?',
              style: TextStyle(
                color: AppColors.textPrimary,
                fontSize: 14,
                fontWeight: FontWeight.w500,
                height: 1.45,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Minimizing keeps background iPhone connection and diagnostic monitoring active in the system tray so your device is recognized instantly when reconnected.',
              style: TextStyle(
                color: AppColors.textSecondary,
                fontSize: 12,
                height: 1.4,
              ),
            ),

            const SizedBox(height: 24),

            // Action Buttons: (Close) and (Minimize)
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                // Close button (terminates application instantly without background lag)
                AppButton(
                  text: 'Close',
                  icon: Icons.close_rounded,
                  variant: AppButtonVariant.danger,
                  height: 38,
                  onPressed: () async {
                    Navigator.of(context, rootNavigator: true).pop();
                    if (!Platform.environment.containsKey('FLUTTER_TEST')) {
                      try {
                        await windowManager.setPreventClose(false).timeout(const Duration(milliseconds: 500));
                        await trayManager.destroy().timeout(const Duration(milliseconds: 500));
                        await windowManager.destroy().timeout(const Duration(milliseconds: 500));
                      } catch (_) {}
                      exit(0);
                    }
                  },
                ),

                const SizedBox(width: 12),

                // Minimize button (minimizes to system tray quietly)
                AppButton(
                  text: 'Minimize',
                  icon: Icons.remove_rounded,
                  variant: AppButtonVariant.primary,
                  height: 38,
                  onPressed: () async {
                    Navigator.of(context, rootNavigator: true).pop();
                    if (!Platform.environment.containsKey('FLUTTER_TEST')) {
                      try {
                        await windowManager.hide().timeout(const Duration(milliseconds: 500));
                      } catch (_) {}
                    }
                  },
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
