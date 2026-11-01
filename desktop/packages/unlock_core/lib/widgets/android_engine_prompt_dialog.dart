import 'package:flutter/material.dart';
import '../core/engine/engine_event.dart';
import '../theme/app_theme.dart';
import 'app_button.dart';

class AndroidEnginePromptDialog extends StatelessWidget {
  final EnginePrompt prompt;
  final ValueChanged<EnginePromptAction> onActionSelected;

  const AndroidEnginePromptDialog({
    super.key,
    required this.prompt,
    required this.onActionSelected,
  });

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: AppColors.cardElevated,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: AppColors.cardBorder),
      ),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 480),
        child: Padding(
          padding: const EdgeInsets.all(22),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: AppColors.warning.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Icon(Icons.touch_app_outlined,
                        color: AppColors.warning, size: 22),
                  ),
                  const SizedBox(width: 12),
                  Text(
                    'Device Action Required',
                    style: TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.w700,
                      color: AppColors.textPrimary,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              Text(
                prompt.message,
                style: TextStyle(
                  fontSize: 13,
                  color: AppColors.textSecondary,
                  height: 1.4,
                ),
              ),
              const SizedBox(height: 24),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: prompt.allowedActions.map((action) {
                  final isCancel = action == EnginePromptAction.cancel;
                  return Padding(
                    padding: const EdgeInsets.only(left: 8),
                    child: AppButton(
                      text: action.label,
                      variant: isCancel
                          ? AppButtonVariant.secondary
                          : AppButtonVariant.primary,
                      height: 36,
                      onPressed: () {
                        Navigator.of(context).pop();
                        onActionSelected(action);
                      },
                    ),
                  );
                }).toList(),
              ),
            ],
          ),
        ),
      ),
    );
  }
}