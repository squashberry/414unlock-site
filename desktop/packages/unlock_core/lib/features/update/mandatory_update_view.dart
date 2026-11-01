import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../core/auth/auth_service.dart';
import '../../core/logging/app_logger.dart';
import '../../core/update/app_update_models.dart';
import '../../theme/app_theme.dart';
import '../../widgets/app_button.dart';

/// Full-screen modal blocking view displayed when a mandatory update is required.
/// Disables unlock and service operations until updated, while retaining sign-out
/// and the ability to open the installer release download link.
class MandatoryUpdateView extends StatelessWidget {
  final UpdateCheckResult update;
  final AuthService authService;

  const MandatoryUpdateView({
    super.key,
    required this.update,
    required this.authService,
  });

  Future<void> _launchUpdateUrl(BuildContext context) async {
    if (!update.hasValidHttpsUrl) {
      AppLogger().warning('Cannot open update: Invalid release URL "${update.releaseUrl}"');
      return;
    }

    try {
      final uri = Uri.parse(update.releaseUrl);
      await launchUrl(uri, mode: LaunchMode.externalApplication);
      AppLogger().info('Opened mandatory update release URL: ${update.releaseUrl}');
    } catch (e) {
      AppLogger().error('Failed to open update URL', e.toString());
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      color: Colors.black.withValues(alpha: 0.75),
      alignment: Alignment.center,
      padding: const EdgeInsets.all(24),
      child: Container(
        constraints: const BoxConstraints(maxWidth: 520),
        padding: const EdgeInsets.all(32),
        decoration: AppColors.liquidGlassDecoration(
          radius: 22,
          elevated: true,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            // Warning Shield Icon
            Container(
              width: 56,
              height: 56,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: AppColors.error.withValues(alpha: 0.12),
                border: Border.all(
                  color: AppColors.error.withValues(alpha: 0.35),
                  width: 1.5,
                ),
              ),
              child: const Icon(
                Icons.warning_amber_rounded,
                color: AppColors.error,
                size: 32,
              ),
            ),
            const SizedBox(height: 20),

            // Title
            Text(
              'Update required',
              style: TextStyle(
                color: AppColors.textPrimary,
                fontSize: 22,
                fontWeight: FontWeight.w700,
                letterSpacing: -0.4,
              ),
            ),
            const SizedBox(height: 8),

            // Explanation
            Text(
              '414Unlock v${update.currentVersion} is no longer supported.\nPlease update to version ${update.latestVersion} to continue using the application.',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: AppColors.textSecondary,
                fontSize: 14,
                height: 1.45,
              ),
            ),
            const SizedBox(height: 20),

            // Release Notes Box
            if (update.releaseNotes.isNotEmpty) ...[
              Container(
                width: double.infinity,
                constraints: const BoxConstraints(maxHeight: 140),
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: AppColors.card,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: AppColors.cardBorder,
                    width: 1,
                  ),
                ),
                child: SingleChildScrollView(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'What\'s new in v${update.latestVersion}:',
                        style: TextStyle(
                          color: AppColors.textPrimary,
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        update.releaseNotes,
                        style: TextStyle(
                          color: AppColors.textSecondary,
                          fontSize: 12,
                          height: 1.4,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 24),
            ],

            // Action Buttons
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                // Sign out button (contract requirement: keep sign out functional)
                AppButton(
                  text: 'Sign out',
                  icon: Icons.logout_rounded,
                  variant: AppButtonVariant.outline,
                  height: 40,
                  onPressed: () async {
                    await authService.signOut();
                  },
                ),
                const SizedBox(width: 14),

                // Update now button
                AppButton(
                  text: 'Update now',
                  icon: Icons.download_rounded,
                  variant: AppButtonVariant.primary,
                  height: 40,
                  onPressed: () => _launchUpdateUrl(context),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
