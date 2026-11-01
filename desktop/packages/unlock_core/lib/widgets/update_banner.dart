import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import '../core/logging/app_logger.dart';
import '../core/update/app_update_models.dart';
import '../core/update/app_update_service.dart';
import '../theme/app_theme.dart';
import 'app_button.dart';

/// Non-blocking liquid glass banner displayed when an optional update is available.
/// Displays the new version and release notes with "Update now" and "Later" actions.
class UpdateBanner extends StatelessWidget {
  final UpdateCheckResult update;
  final VoidCallback? onDismiss;

  const UpdateBanner({
    super.key,
    required this.update,
    this.onDismiss,
  });

  Future<void> _launchUpdateUrl(BuildContext context) async {
    if (!update.hasValidHttpsUrl) {
      AppLogger().warning('Cannot open update: Invalid release URL "${update.releaseUrl}"');
      return;
    }

    try {
      final uri = Uri.parse(update.releaseUrl);
      await launchUrl(uri, mode: LaunchMode.externalApplication);
      AppLogger().info('Opened update release URL: ${update.releaseUrl}');
    } catch (e) {
      AppLogger().error('Failed to open update URL', e.toString());
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = AppColors.isDark;

    return Container(
      margin: const EdgeInsets.fromLTRB(16, 12, 16, 8),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(14),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: isDark
              ? [const Color(0x381E3A8A), const Color(0x22172554)]
              : [const Color(0xFFF0F7FF), const Color(0xFFE0EFFF)],
        ),
        border: Border.all(
          color: isDark
              ? const Color(0x443B82F6)
              : const Color(0x332563EB),
          width: 1.0,
        ),
        boxShadow: [
          BoxShadow(
            color: const Color(0x0C0F172A),
            blurRadius: 12,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          // Glowing update badge icon
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: AppColors.iphoneBlue.withValues(alpha: isDark ? 0.22 : 0.12),
              border: Border.all(
                color: AppColors.iphoneBlue.withValues(alpha: 0.35),
                width: 1,
              ),
            ),
            child: const Icon(
              Icons.system_update_rounded,
              color: AppColors.iphoneBlue,
              size: 20,
            ),
          ),
          const SizedBox(width: 14),

          // Version info and release notes
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    Text(
                      'A new version is available',
                      style: TextStyle(
                        color: AppColors.textPrimary,
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        letterSpacing: -0.2,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1.5),
                      decoration: BoxDecoration(
                        color: AppColors.iphoneBlue.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        'v${update.latestVersion}',
                        style: const TextStyle(
                          color: AppColors.iphoneBlue,
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ],
                ),
                if (update.releaseNotes.isNotEmpty) ...[
                  const SizedBox(height: 2),
                  Text(
                    update.releaseNotes,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: AppColors.textSecondary,
                      fontSize: 12,
                      height: 1.3,
                    ),
                  ),
                ],
              ],
            ),
          ),

          const SizedBox(width: 12),

          // Actions: "Later" and "Update now"
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextButton(
                onPressed: () {
                  AppUpdateService().dismissOptionalUpdate();
                  onDismiss?.call();
                },
                style: TextButton.styleFrom(
                  foregroundColor: AppColors.textSecondary,
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  minimumSize: Size.zero,
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
                child: const Text(
                  'Later',
                  style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
                ),
              ),
              const SizedBox(width: 8),
              AppButton(
                text: 'Update now',
                icon: Icons.open_in_new_rounded,
                height: 32,
                onPressed: () => _launchUpdateUrl(context),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
