import 'package:flutter/material.dart';
import '../core/device/android_device_state.dart';
import '../theme/app_theme.dart';
import 'app_button.dart';

class AndroidActionsPanel extends StatelessWidget {
  final List<RecoveryAction> actions;
  final bool isOperationRunning;
  final ValueChanged<RecoveryAction> onSelectAction;

  const AndroidActionsPanel({
    super.key,
    required this.actions,
    required this.isOperationRunning,
    required this.onSelectAction,
  });

  @override
  Widget build(BuildContext context) {
    if (actions.isEmpty) {
      return Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: AppColors.card,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: AppColors.cardBorder),
        ),
        child: Center(
          child: Text(
            'Connect an Android device to inspect available recovery actions.',
            style: TextStyle(fontSize: 13, color: AppColors.textSecondary),
          ),
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'AVAILABLE RECOVERY ACTIONS',
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w700,
            letterSpacing: 0.8,
            color: AppColors.textSecondary,
          ),
        ),
        const SizedBox(height: 10),
        ListView.separated(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          itemCount: actions.length,
          separatorBuilder: (_, _) => const SizedBox(height: 8),
          itemBuilder: (context, index) {
            final action = actions[index];
            return _buildActionRow(context, action);
          },
        ),
      ],
    );
  }

  Widget _buildActionRow(BuildContext context, RecoveryAction action) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: action.isDestructive
              ? AppColors.error.withValues(alpha: 0.3)
              : AppColors.cardBorder,
        ),
      ),
      child: Row(
        children: [
          Icon(
            action.isDestructive
                ? Icons.delete_forever_rounded
                : Icons.play_arrow_rounded,
            size: 20,
            color: action.isDestructive ? AppColors.error : AppColors.androidGreen,
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(
                      action.name,
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: AppColors.textPrimary,
                      ),
                    ),
                    if (action.isDestructive) ...[
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: AppColors.error.withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: const Text(
                          'DESTRUCTIVE',
                          style: TextStyle(
                            fontSize: 9,
                            fontWeight: FontWeight.w700,
                            color: AppColors.error,
                            letterSpacing: 0.5,
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: 3),
                Text(
                  action.description,
                  style: TextStyle(
                    fontSize: 12,
                    color: AppColors.textSecondary,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 16),
          AppButton(
            text: action.isDestructive ? 'Reset...' : 'Run',
            variant: action.isDestructive
                ? AppButtonVariant.danger
                : AppButtonVariant.secondary,
            height: 34,
            onPressed: isOperationRunning
                ? null
                : () => _handleActionClick(context, action),
          ),
        ],
      ),
    );
  }

  void _handleActionClick(BuildContext context, RecoveryAction action) {
    if (action.requiresConfirmation) {
      showDialog(
        context: context,
        builder: (_) => AlertDialog(
          backgroundColor: AppColors.cardElevated,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
            side: BorderSide(color: AppColors.cardBorder),
          ),
          title: Row(
            children: [
              const Icon(Icons.warning_amber_rounded, color: AppColors.error, size: 24),
              const SizedBox(width: 10),
              Text(
                action.confirmationTitle ?? 'Confirm Action',
                style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700),
              ),
            ],
          ),
          content: Text(
            action.confirmationMessage ?? 'Are you sure you want to proceed?',
            style: TextStyle(fontSize: 13, color: AppColors.textSecondary, height: 1.4),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: Text('Cancel', style: TextStyle(color: AppColors.textSecondary)),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.error,
                foregroundColor: Colors.white,
              ),
              onPressed: () {
                Navigator.of(context).pop();
                onSelectAction(action);
              },
              child: const Text('Erase & Reset'),
            ),
          ],
        ),
      );
    } else {
      onSelectAction(action);
    }
  }
}