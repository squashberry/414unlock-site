import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import '../core/compatibility/device_compatibility_service.dart';
import '../core/device/device_info.dart';
import '../theme/app_theme.dart';
import 'status_chip.dart';

class DeviceCard extends StatelessWidget {
  final DeviceInfo device;
  final AppBrandVariant variant;

  const DeviceCard({
    super.key,
    required this.device,
    required this.variant,
  });

  Future<void> _openAppleGuide() async {
    final uri = Uri.parse('https://support.apple.com/en-us/108934');
    try {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    final isIos = variant == AppBrandVariant.iphone;
    final accentColor = isIos ? AppColors.iphoneBlue : AppColors.androidGreen;
    final compat = device.compatibilityResult;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(22),
      decoration: AppColors.liquidGlassDecoration(
        radius: 16,
        elevated: true,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header with device icon & mode chip
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: accentColor.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(
                  isIos ? Icons.phone_iphone_rounded : Icons.phone_android_rounded,
                  color: accentColor,
                  size: 24,
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      device.name,
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w700,
                        color: AppColors.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Row(
                      children: [
                        Container(
                          width: 8,
                          height: 8,
                          decoration: const BoxDecoration(
                            color: AppColors.success,
                            shape: BoxShape.circle,
                          ),
                        ),
                        const SizedBox(width: 6),
                        const Text(
                          'Connected',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: AppColors.success,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            '•  ${device.statusDescription}',
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 12,
                              color: AppColors.textSecondary,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              StatusChip(
                label: device.mode.label,
                color: device.mode.isDiagnosticState
                    ? AppColors.warning
                    : accentColor,
                icon: device.mode.isDiagnosticState
                    ? Icons.build_circle_outlined
                    : Icons.check_circle_outline_rounded,
              ),
            ],
          ),

          const SizedBox(height: 16),
          Divider(color: AppColors.cardBorder, height: 1),
          const SizedBox(height: 16),

          // Lockdown status warning (e.g., device locked or untrusted)
          if (device.lockdownStatus.showsWarning) ...[
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AppColors.warning.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: AppColors.warning.withValues(alpha: 0.35)),
              ),
              child: Row(
                children: [
                  Icon(
                    device.requiresRestore ? Icons.build_circle_outlined : Icons.lock_outline_rounded,
                    size: 16,
                    color: AppColors.warning,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          device.requiresRestore
                              ? 'DEVICE RESTORE REQUIRED'
                              : 'LIMITED DEVICE INFORMATION',
                          style: const TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.w800,
                            letterSpacing: 0.6,
                            color: AppColors.warning,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          device.lockdownStatus.userMessage,
                          style: TextStyle(
                            fontSize: 12,
                            color: AppColors.textPrimary,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
          ],

          // Details Grid
          Wrap(
            spacing: 24,
            runSpacing: 12,
            children: [
              if (device.model != null)
                _buildInfoItem('Model', device.model!),
              if (device.modelIdentifier != null)
                _buildInfoItem('Model Identifier', device.modelIdentifier!)
              else if (isIos)
                _buildInfoItem('Model Identifier', 'Not reported'),
              if (device.chipFamily != null)
                _buildInfoItem('Architecture', device.chipFamily!),
              if (device.osVersion != null)
                _buildInfoItem('Firmware / iOS', 'iOS ${device.osVersion!}')
              else if (isIos)
                _buildInfoItem('Firmware / iOS', 'Not reported (Unconfirmed)'),
              if (device.serialNumber != null)
                _buildInfoItem(device.identifierLabel, device.maskedIdentifier),
              _buildInfoItem('Connection', device.connectionType),
            ],
          ),

          // iOS Compatibility & Limitations Section
          if (isIos && compat != null) ...[
            const SizedBox(height: 18),
            Divider(color: AppColors.cardBorder, height: 1),
            const SizedBox(height: 14),

            // Compatibility Assessment Header & Badge
            Row(
              children: [
                Icon(Icons.analytics_outlined, size: 16, color: AppColors.textSecondary),
                const SizedBox(width: 6),
                Text(
                  'COMPATIBILITY EVALUATION',
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0.8,
                    color: AppColors.textSecondary,
                  ),
                ),
                const Spacer(),
                _buildCompatibilityBadge(compat),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              compat.explanation,
              style: TextStyle(fontSize: 12, color: AppColors.textSecondary, height: 1.4),
            ),

            // Prominent No-Cellular-Signal Limitation Alert
            if (compat.hasNoCellularSignalLimitation) ...[
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: AppColors.warning.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: AppColors.warning.withValues(alpha: 0.35)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: const [
                        Icon(Icons.signal_cellular_connected_no_internet_0_bar_rounded,
                            size: 16, color: AppColors.warning),
                        SizedBox(width: 8),
                        Text(
                          'NO CELLULAR SIGNAL LIMITATION',
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w800,
                            letterSpacing: 0.5,
                            color: AppColors.warning,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Text(
                      'The software vendor describes this service as leaving the device without normal cellular calling and SMS capabilities.',
                      style: TextStyle(fontSize: 11, color: AppColors.textPrimary, fontWeight: FontWeight.w600),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '• Wi-Fi connectivity and internet-connected apps (FaceTime, App Store, Safari) may remain usable.\n'
                      '• Traditional cellular calls, SMS, and carrier data will not work as expected.\n'
                      '• Internet communication over Wi-Fi does not replace ordinary carrier cellular service.',
                      style: TextStyle(fontSize: 11, color: AppColors.textSecondary, height: 1.45),
                    ),
                  ],
                ),
              ),
            ],

            // Legitimate Activation Lock Recovery Pathway
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AppColors.cardElevated,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: AppColors.cardBorder),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Icon(Icons.shield_outlined, size: 15, color: AppColors.iphoneBlue),
                      const SizedBox(width: 6),
                      const Text(
                        'LEGITIMATE ACTIVATION LOCK RECOVERY',
                        style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 0.6,
                          color: AppColors.iphoneBlue,
                        ),
                      ),
                      const Spacer(),
                      InkWell(
                        onTap: _openAppleGuide,
                        child: Row(
                          children: const [
                            Text(
                              'Apple Guide',
                              style: TextStyle(fontSize: 11, color: AppColors.iphoneBlue, fontWeight: FontWeight.w600),
                            ),
                            SizedBox(width: 2),
                            Icon(Icons.open_in_new_rounded, size: 12, color: AppColors.iphoneBlue),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'Activation Lock is an Apple anti-theft security control. For owners or authorized technicians, legitimate options include:',
                    style: TextStyle(fontSize: 11, color: AppColors.textMuted),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '1. Sign in with the original Apple Account associated with this device.\n'
                    '2. Ask the previous owner to remove the device remotely at icloud.com/find.\n'
                    '3. Contact Apple Support with valid proof of purchase (support.apple.com/en-us/108934).',
                    style: TextStyle(fontSize: 11, color: AppColors.textSecondary, height: 1.4),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildCompatibilityBadge(DeviceCompatibilityResult compat) {
    Color badgeColor;
    IconData badgeIcon;

    switch (compat.status) {
      case CompatibilityStatus.verifiedSupported:
        badgeColor = AppColors.success;
        badgeIcon = Icons.check_circle_outline_rounded;
        break;
      case CompatibilityStatus.firmwareOutsideRange:
        badgeColor = AppColors.warning;
        badgeIcon = Icons.warning_amber_rounded;
        break;
      case CompatibilityStatus.unconfirmed:
      case CompatibilityStatus.unsupported:
        badgeColor = AppColors.textMuted;
        badgeIcon = Icons.help_outline_rounded;
        break;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: badgeColor.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: badgeColor.withValues(alpha: 0.4)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(badgeIcon, size: 12, color: badgeColor),
          const SizedBox(width: 4),
          Text(
            compat.statusBadge,
            style: TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w700,
              color: badgeColor,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildInfoItem(String label, String value) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          label.toUpperCase(),
          style: TextStyle(
            fontSize: 10,
            fontWeight: FontWeight.w600,
            letterSpacing: 0.8,
            color: AppColors.textMuted,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          value,
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w500,
            color: AppColors.textPrimary,
          ),
        ),
      ],
    );
  }
}