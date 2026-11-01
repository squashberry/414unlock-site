import 'package:flutter/material.dart';
import '../../core/prerequisites/itunes_manager.dart';
import '../../core/prerequisites/setup_coordinator.dart';
import '../../theme/app_theme.dart';
import '../../widgets/app_button.dart';

class SetupView extends StatelessWidget {
  final SetupCoordinator coordinator;
  final VoidCallback onContinue;

  const SetupView({
    super.key,
    required this.coordinator,
    required this.onContinue,
  });

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: coordinator,
      builder: (context, _) {
        final itunes = coordinator.itunesManager;
        final isReady = coordinator.isReady;

        // Auto-advance if ready
        if (isReady) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            onContinue();
          });
        }

        return Scaffold(
          backgroundColor: AppColors.background,
          body: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 40),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 620),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    // Brand Wordmark & Icon
                    Container(
                      width: 64,
                      height: 64,
                      decoration: BoxDecoration(
                        color: AppColors.card,
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: AppColors.iphoneBlue.withValues(alpha: 0.6),
                          width: 2,
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: AppColors.iphoneBlue.withValues(alpha: 0.2),
                            blurRadius: 16,
                            spreadRadius: 2,
                          ),
                        ],
                      ),
                      child: const Center(
                        child: Text(
                          '414',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 22,
                            fontWeight: FontWeight.w900,
                            letterSpacing: -1,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 20),

                    // Title & Subtitle
                    Text(
                      'Loading 414Unlock engine',
                      style: TextStyle(
                        color: AppColors.textPrimary,
                        fontSize: 24,
                        fontWeight: FontWeight.w700,
                        letterSpacing: -0.3,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      'Checking requirements',
                      style: TextStyle(
                        color: AppColors.textSecondary,
                        fontSize: 14,
                      ),
                    ),
                    const SizedBox(height: 28),

                    // Clean Progress Indicator
                    ClipRRect(
                      borderRadius: BorderRadius.circular(4),
                      child: itunes.status == ITunesInstallStatus.downloading
                          ? LinearProgressIndicator(
                              value: itunes.downloadProgress > 0 ? itunes.downloadProgress : null,
                              backgroundColor: AppColors.cardBorder,
                              valueColor: const AlwaysStoppedAnimation<Color>(AppColors.iphoneBlue),
                              minHeight: 4,
                            )
                          : isReady
                              ? Container(height: 4, color: AppColors.success)
                              : LinearProgressIndicator(
                                  backgroundColor: AppColors.cardBorder,
                                  valueColor: const AlwaysStoppedAnimation<Color>(AppColors.iphoneBlue),
                                  minHeight: 4,
                                ),
                    ),
                    const SizedBox(height: 24),

                    // Checklist Box
                    Container(
                      padding: const EdgeInsets.all(22),
                      decoration: AppColors.liquidGlassDecoration(
                        radius: 16,
                        elevated: true,
                      ),
                      child: Column(
                        children: [
                          _buildChecklistItem(
                            title: 'Windows System Environment',
                            description: 'Core runtime architecture and system services',
                            state: coordinator.windowsSystemState,
                          ),
                          Divider(color: AppColors.cardBorder, height: 24),
                          _buildChecklistItem(
                            title: 'Apple Device Communication',
                            description: 'iTunes USB subsystem and Apple Mobile Device Support',
                            state: coordinator.appleCommunicationState,
                          ),
                          Divider(color: AppColors.cardBorder, height: 24),
                          _buildChecklistItem(
                            title: '414Unlock Engine',
                            description: 'Secure authorization and device diagnostic engine',
                            state: coordinator.engineState,
                          ),
                        ],
                      ),
                    ),

                    // Requirement Action Area (When iTunes is missing, downloading, or installing)
                    if (coordinator.currentStep == SetupStep.itunesMissing ||
                        coordinator.currentStep == SetupStep.downloadingItunes ||
                        coordinator.currentStep == SetupStep.itunesInstallRequired ||
                        coordinator.currentStep == SetupStep.installingItunes ||
                        coordinator.currentStep == SetupStep.failed) ...[
                      const SizedBox(height: 20),
                      _buildActionBox(context, coordinator, itunes),
                    ],

                    // Ready Button (if not yet automatically navigated)
                    if (isReady) ...[
                      const SizedBox(height: 24),
                      AppButton(
                        text: 'Continue',
                        icon: Icons.arrow_forward_rounded,
                        variant: AppButtonVariant.primary,
                        onPressed: onContinue,
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildChecklistItem({
    required String title,
    required String description,
    required RequirementState state,
  }) {
    Color badgeColor;
    String badgeText;
    Widget icon;

    switch (state) {
      case RequirementState.checking:
        badgeColor = AppColors.iphoneBlue;
        badgeText = 'Checking…';
        icon = const SizedBox(
          width: 14,
          height: 14,
          child: CircularProgressIndicator(
            strokeWidth: 2,
            valueColor: AlwaysStoppedAnimation<Color>(AppColors.iphoneBlue),
          ),
        );
        break;
      case RequirementState.passed:
        badgeColor = AppColors.success;
        badgeText = 'Passed';
        icon = const Icon(Icons.check_circle_rounded, color: AppColors.success, size: 18);
        break;
      case RequirementState.actionRequired:
        badgeColor = AppColors.warning;
        badgeText = 'Action required';
        icon = const Icon(Icons.warning_amber_rounded, color: AppColors.warning, size: 18);
        break;
      case RequirementState.ready:
        badgeColor = AppColors.success;
        badgeText = 'Ready';
        icon = const Icon(Icons.check_circle_rounded, color: AppColors.success, size: 18);
        break;
    }

    return Row(
      children: [
        Container(
          width: 32,
          height: 32,
          decoration: BoxDecoration(
            color: badgeColor.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Center(child: icon),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: TextStyle(
                  color: AppColors.textPrimary,
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                description,
                style: TextStyle(
                  color: AppColors.textSecondary,
                  fontSize: 11,
                ),
              ),
            ],
          ),
        ),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          decoration: BoxDecoration(
            color: badgeColor.withValues(alpha: 0.15),
            borderRadius: BorderRadius.circular(6),
          ),
          child: Text(
            badgeText,
            style: TextStyle(
              color: badgeColor,
              fontSize: 11,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildActionBox(BuildContext context, SetupCoordinator coordinator, ITunesManager itunes) {
    final isDownloading = itunes.status == ITunesInstallStatus.downloading;
    final isInstallRequired = itunes.status == ITunesInstallStatus.installRequired;
    final isInstalling = itunes.status == ITunesInstallStatus.installing;
    final isFailed = coordinator.currentStep == SetupStep.failed;

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: isFailed
          ? BoxDecoration(
              color: AppColors.error.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                color: AppColors.error.withValues(alpha: 0.35),
                width: 1.1,
              ),
            )
          : AppColors.liquidGlassDecoration(radius: 14, elevated: false),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                isFailed ? Icons.error_outline_rounded : Icons.info_outline_rounded,
                color: isFailed ? AppColors.error : AppColors.iphoneBlue,
                size: 20,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  isFailed
                      ? (coordinator.errorMessage.isNotEmpty
                          ? coordinator.errorMessage
                          : 'Requirement verification failed.')
                      : '414Unlock needs iTunes to detect and communicate with your iPhone.',
                  style: TextStyle(
                    color: isFailed ? AppColors.error : AppColors.textPrimary,
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),

          // Downloading progress info
          if (isDownloading) ...[
            Text(
              itunes.statusMessage,
              style: TextStyle(color: AppColors.textSecondary, fontSize: 12),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                AppButton(
                  text: 'Cancel Download',
                  variant: AppButtonVariant.secondary,
                  onPressed: () => coordinator.cancelItunesDownload(),
                ),
              ],
            ),
          ] else if (isInstallRequired) ...[
            Text(
              'The official iTunes installer is downloaded and verified. Windows administrator approval is required.',
              style: TextStyle(color: AppColors.textSecondary, fontSize: 12),
            ),
            const SizedBox(height: 14),
            Row(
              children: [
                AppButton(
                  text: 'Install iTunes',
                  icon: Icons.play_arrow_rounded,
                  variant: AppButtonVariant.primary,
                  onPressed: () => coordinator.launchItunesInstaller(),
                ),
              ],
            ),
          ] else if (isInstalling) ...[
            Row(
              children: [
                SizedBox(
                  width: 14,
                  height: 14,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    valueColor: AlwaysStoppedAnimation<Color>(AppColors.iphoneBlue),
                  ),
                ),
                SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'Installing iTunes... Please complete any Windows UAC prompts on your screen.',
                    style: TextStyle(color: AppColors.textSecondary, fontSize: 12),
                  ),
                ),
              ],
            ),
          ] else ...[
            Text(
              'Download the official Apple installer directly into 414Unlock, or open Apple’s official webpage.',
              style: TextStyle(color: AppColors.textSecondary, fontSize: 12),
            ),
            const SizedBox(height: 14),
            Row(
              children: [
                AppButton(
                  text: 'Download iTunes',
                  icon: Icons.download_rounded,
                  variant: AppButtonVariant.primary,
                  onPressed: () => coordinator.startItunesDownload(),
                ),
                const SizedBox(width: 10),
                AppButton(
                  text: 'Check Again',
                  icon: Icons.refresh_rounded,
                  variant: AppButtonVariant.secondary,
                  onPressed: () => coordinator.retry(),
                ),
                const Spacer(),
                TextButton(
                  onPressed: () => itunes.openOfficialDownloadPage(),
                  child: const Text(
                    'Apple Website',
                    style: TextStyle(color: AppColors.iphoneBlue, fontSize: 12),
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}