import 'package:flutter/material.dart';
import '../../core/device/device_info.dart';
import '../../core/engine/repair_engine.dart';
import '../../theme/app_theme.dart';
import '../../widgets/app_button.dart';

class ResultView extends StatelessWidget {
  final EngineResult? result;
  final AppBrandVariant variant;
  final VoidCallback onFinish;
  final VoidCallback onViewDiagnostics;

  const ResultView({
    super.key,
    required this.result,
    required this.variant,
    required this.onFinish,
    required this.onViewDiagnostics,
  });

  @override
  Widget build(BuildContext context) {
    final isVerifiedSuccess = result?.success == true && result?.isVerified == true;

    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 580),
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              // Large Central Icon
              Container(
                width: 80,
                height: 80,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: isVerifiedSuccess
                      ? AppColors.success.withValues(alpha: 0.15)
                      : AppColors.warning.withValues(alpha: 0.15),
                  border: Border.all(
                    color: isVerifiedSuccess
                        ? AppColors.success.withValues(alpha: 0.4)
                        : AppColors.warning.withValues(alpha: 0.4),
                    width: 2,
                  ),
                ),
                child: Center(
                  child: Icon(
                    isVerifiedSuccess
                        ? Icons.check_rounded
                        : Icons.shield_outlined,
                    size: 44,
                    color: isVerifiedSuccess
                        ? AppColors.success
                        : AppColors.warning,
                  ),
                ),
              ),

              const SizedBox(height: 24),

              // Title
              Text(
                isVerifiedSuccess ? 'Done' : 'Verification Required',
                style: TextStyle(
                  fontSize: 26,
                  fontWeight: FontWeight.w700,
                  color: AppColors.textPrimary,
                  letterSpacing: -0.4,
                ),
              ),

              const SizedBox(height: 10),

              // Subtitle
              Text(
                isVerifiedSuccess
                    ? 'The partner tool reported that the operation completed successfully.'
                    : 'The partner application finished, but 414Unlock could not independently verify the final device state.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 14,
                  color: AppColors.textSecondary,
                  height: 1.4,
                ),
              ),

              const SizedBox(height: 20),

              // Status Summary Box
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: AppColors.card,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: AppColors.cardBorder),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Text(
                          'ENGINE STATE: ${result?.status.label.toUpperCase() ?? "UNKNOWN"}',
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                            letterSpacing: 0.8,
                            color: AppColors.textMuted,
                          ),
                        ),
                        const Spacer(),
                        Text(
                          result?.isVerified == true
                              ? 'Provider Verified'
                              : 'Unconfirmed Provider',
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                            color: isVerifiedSuccess
                                ? AppColors.success
                                : AppColors.warning,
                          ),
                        ),
                      ],
                    ),
                    if (result?.deviceInfo != null) ...[
                      const SizedBox(height: 8),
                      Text(
                        'Device: ${result!.deviceInfo!.name} (${result!.deviceInfo!.mode.label})',
                        style: TextStyle(
                          fontSize: 13,
                          color: AppColors.textPrimary,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ],
                ),
              ),

              const SizedBox(height: 32),

              // Buttons
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  AppButton(
                    text: 'View Diagnostics',
                    icon: Icons.terminal_rounded,
                    variant: AppButtonVariant.secondary,
                    height: 42,
                    onPressed: onViewDiagnostics,
                  ),
                  const SizedBox(width: 14),
                  AppButton(
                    text: 'Finish',
                    icon: Icons.done_all_rounded,
                    variant: AppButtonVariant.primary,
                    height: 42,
                    onPressed: onFinish,
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}