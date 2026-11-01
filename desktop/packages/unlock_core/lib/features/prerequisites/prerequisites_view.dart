import 'package:flutter/material.dart';
import '../../core/prerequisites/prerequisite_service.dart';
import '../../theme/app_theme.dart';
import '../../widgets/app_button.dart';
import '../../widgets/prerequisite_card.dart';

class PrerequisitesView extends StatelessWidget {
  final PrerequisiteService service;
  final AppBrandVariant variant;
  final VoidCallback onContinue;

  const PrerequisitesView({
    super.key,
    required this.service,
    required this.variant,
    required this.onContinue,
  });

  @override
  Widget build(BuildContext context) {
    final accentColor = variant == AppBrandVariant.iphone
        ? AppColors.iphoneBlue
        : AppColors.androidGreen;

    return ListenableBuilder(
      listenable: service,
      builder: (context, _) {
        final allPassed = service.allPassed;
        final isChecking = service.isChecking;

        return SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 24),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 780),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Page Heading
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: accentColor.withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Icon(
                          Icons.verified_outlined,
                          color: accentColor,
                          size: 26,
                        ),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              "Let's check your PC",
                              style: TextStyle(
                                fontSize: 24,
                                fontWeight: FontWeight.w700,
                                color: AppColors.textPrimary,
                                letterSpacing: -0.4,
                              ),
                            ),
                            const SizedBox(height: 3),
                            Text(
                              variant == AppBrandVariant.iphone
                                  ? 'Verifying Apple drivers, communication services, and device software.'
                                  : 'Verifying Android USB drivers, ADB bridge, and fastboot protocols.',
                              style: TextStyle(
                                fontSize: 13,
                                color: AppColors.textSecondary,
                              ),
                            ),
                          ],
                        ),
                      ),
                      // Recheck All button
                      AppButton(
                        text: 'Recheck All',
                        icon: Icons.refresh_rounded,
                        variant: AppButtonVariant.secondary,
                        isLoading: isChecking,
                        onPressed: isChecking ? null : () => service.recheckAll(),
                      ),
                    ],
                  ),

                  const SizedBox(height: 24),

                  // Prerequisite Cards List
                  ...service.prerequisites.map(
                    (p) => PrerequisiteCard(
                      prerequisite: p,
                      onRecheck: () => service.recheck(p.id),
                      onDownload: () => p.openDownload(),
                    ),
                  ),

                  const SizedBox(height: 20),

                  // Status Banner & Continue Button
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: allPassed
                          ? AppColors.success.withValues(alpha: 0.1)
                          : AppColors.card,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(
                        color: allPassed
                            ? AppColors.success.withValues(alpha: 0.3)
                            : AppColors.cardBorder,
                      ),
                    ),
                    child: Row(
                      children: [
                        Icon(
                          allPassed
                              ? Icons.check_circle_rounded
                              : Icons.info_outline_rounded,
                          color: allPassed
                              ? AppColors.success
                              : AppColors.textSecondary,
                          size: 20,
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            allPassed
                                ? 'All system prerequisites are satisfied. You may proceed to connect your device.'
                                : 'One or more required components are missing. Download official software or recheck.',
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight:
                                  allPassed ? FontWeight.w600 : FontWeight.normal,
                              color: allPassed
                                  ? AppColors.success
                                  : AppColors.textSecondary,
                            ),
                          ),
                        ),
                        const SizedBox(width: 16),
                        AppButton(
                          text: 'Continue',
                          icon: Icons.arrow_forward_rounded,
                          variant: AppButtonVariant.primary,
                          onPressed: allPassed ? onContinue : null,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}