import 'package:flutter/material.dart';
import '../theme/app_theme.dart';

class AppHeader extends StatelessWidget {
  final String title;
  final String subtitle;
  final AppBrandVariant variant;
  final VoidCallback onOpenSettings;
  final VoidCallback onOpenLogs;
  final Widget? trailing;

  const AppHeader({
    super.key,
    required this.title,
    required this.subtitle,
    required this.variant,
    required this.onOpenSettings,
    required this.onOpenLogs,
    this.trailing,
  });

  @override
  Widget build(BuildContext context) {
    final accentColor = variant == AppBrandVariant.iphone
        ? AppColors.iphoneBlue
        : AppColors.androidGreen;

    return Container(
      height: 64,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      decoration: BoxDecoration(
        color: AppColors.backgroundSecondary,
        border: Border(
          bottom: BorderSide(color: AppColors.cardBorder, width: 1),
        ),
      ),
      child: Row(
        children: [
          // Brand Lockup
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(6),
                child: Image.asset(
                  'assets/icons/app_icon.png',
                  width: 24,
                  height: 24,
                  fit: BoxFit.contain,
                  errorBuilder: (context, error, stackTrace) => const SizedBox.shrink(),
                ),
              ),
              const SizedBox(width: 8),
              Text(
                '414',
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w900,
                  color: AppColors.textPrimary,
                  letterSpacing: -0.8,
                ),
              ),
              const SizedBox(width: 4),
              Text(
                'unlock',
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w400,
                  color: accentColor,
                  letterSpacing: -0.4,
                ),
              ),
            ],
          ),

          const SizedBox(width: 12),
          Container(
            height: 16,
            width: 1,
            color: AppColors.cardBorderHover,
          ),
          const SizedBox(width: 12),

          // Subtitle
          Flexible(
            child: Text(
              subtitle,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w500,
                color: AppColors.textSecondary,
                letterSpacing: 0.2,
              ),
            ),
          ),

          const Spacer(),

          if (trailing != null) ...[
            trailing!,
            const SizedBox(width: 12),
          ],

          // Logs Button
          IconButton(
            tooltip: 'View Diagnostics & Logs',
            icon: Icon(
              Icons.terminal_rounded,
              size: 20,
              color: AppColors.textSecondary,
            ),
            splashRadius: 20,
            onPressed: onOpenLogs,
          ),

          const SizedBox(width: 4),

          // Settings Button
          IconButton(
            tooltip: 'Settings',
            icon: Icon(
              Icons.settings_outlined,
              size: 20,
              color: AppColors.textSecondary,
            ),
            splashRadius: 20,
            onPressed: onOpenSettings,
          ),
        ],
      ),
    );
  }
}