import 'package:flutter/material.dart';
import '../core/prerequisites/prerequisite.dart';
import '../theme/app_theme.dart';

class StatusChip extends StatelessWidget {
  final String label;
  final Color color;
  final IconData? icon;
  final bool isLoading;

  const StatusChip({
    super.key,
    required this.label,
    required this.color,
    this.icon,
    this.isLoading = false,
  });

  factory StatusChip.fromPrerequisiteStatus(PrerequisiteStatus status) {
    switch (status) {
      case PrerequisiteStatus.checking:
        return const StatusChip(
          label: 'Checking...',
          color: AppColors.info,
          isLoading: true,
        );
      case PrerequisiteStatus.installed:
        return const StatusChip(
          label: 'Installed',
          color: AppColors.success,
          icon: Icons.check_circle_outline_rounded,
        );
      case PrerequisiteStatus.missing:
        return const StatusChip(
          label: 'Missing',
          color: AppColors.error,
          icon: Icons.cancel_outlined,
        );
      case PrerequisiteStatus.updateRequired:
        return const StatusChip(
          label: 'Update required',
          color: AppColors.warning,
          icon: Icons.update_rounded,
        );
      case PrerequisiteStatus.unableToVerify:
        return const StatusChip(
          label: 'Unable to verify',
          color: AppColors.warning,
          icon: Icons.help_outline_rounded,
        );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: color.withValues(alpha: 0.3), width: 1),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (isLoading) ...[
            SizedBox(
              width: 11,
              height: 11,
              child: CircularProgressIndicator(
                strokeWidth: 1.8,
                valueColor: AlwaysStoppedAnimation<Color>(color),
              ),
            ),
            const SizedBox(width: 6),
          ] else if (icon != null) ...[
            Icon(icon, size: 13, color: color),
            const SizedBox(width: 5),
          ],
          Text(
            label,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: color,
            ),
          ),
        ],
      ),
    );
  }
}
