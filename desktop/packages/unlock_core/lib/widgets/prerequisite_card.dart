import 'package:flutter/material.dart';
import '../core/prerequisites/prerequisite.dart';
import '../theme/app_theme.dart';
import 'app_button.dart';
import 'status_chip.dart';

class PrerequisiteCard extends StatelessWidget {
  final Prerequisite prerequisite;
  final VoidCallback onRecheck;
  final VoidCallback onDownload;

  const PrerequisiteCard({
    super.key,
    required this.prerequisite,
    required this.onRecheck,
    required this.onDownload,
  });

  @override
  Widget build(BuildContext context) {
    final status = prerequisite.status;
    final isInstalled = status == PrerequisiteStatus.installed;
    final isChecking = status == PrerequisiteStatus.checking;

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(18),
      decoration: AppColors.liquidGlassDecoration(
        radius: 14,
        elevated: !isInstalled,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Top Header: Name and Status Badge
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      prerequisite.displayName,
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                        color: AppColors.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      prerequisite.description,
                      style: TextStyle(
                        fontSize: 13,
                        color: AppColors.textSecondary,
                        height: 1.3,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 16),
              StatusChip.fromPrerequisiteStatus(status),
            ],
          ),

          const SizedBox(height: 14),

          // Metadata row & Action buttons
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              // Detected Version / Status Info
              if (prerequisite.detectedVersion != null) ...[
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: AppColors.cardElevated,
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(color: AppColors.cardBorder),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.info_outline_rounded,
                          size: 13, color: AppColors.textMuted),
                      const SizedBox(width: 5),
                      Text(
                        'Version: ${prerequisite.detectedVersion}',
                        style: TextStyle(
                          fontSize: 12,
                          color: AppColors.textSecondary,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                ),
              ] else if (prerequisite.statusDetail != null) ...[
                Expanded(
                  child: Text(
                    prerequisite.statusDetail!,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 12,
                      color: isInstalled ? AppColors.textMuted : AppColors.warning,
                    ),
                  ),
                ),
              ] else ...[
                const Spacer(),
              ],

              const Spacer(),

              // "Download Now" button (if missing or update required)
              if (!isInstalled) ...[
                AppButton(
                  text: 'Download Now',
                  icon: Icons.open_in_new_rounded,
                  variant: AppButtonVariant.outline,
                  height: 34,
                  onPressed: onDownload,
                ),
                const SizedBox(width: 8),
              ],

              // "Recheck" button
              AppButton(
                text: 'Recheck',
                icon: Icons.refresh_rounded,
                variant: AppButtonVariant.secondary,
                height: 34,
                isLoading: isChecking,
                onPressed: isChecking ? null : onRecheck,
              ),
            ],
          ),
        ],
      ),
    );
  }
}