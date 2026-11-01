import 'package:flutter/material.dart';
import '../core/device/android_device_state.dart';
import '../core/device/device_info.dart';
import '../theme/app_theme.dart';

class AndroidStateCard extends StatelessWidget {
  final AndroidDeviceState state;
  final AdbCapability adbCapability;
  final DeviceInfo? device;

  const AndroidStateCard({
    super.key,
    required this.state,
    required this.adbCapability,
    this.device,
  });

  @override
  Widget build(BuildContext context) {
    const accentGreen = AppColors.androidGreen;
    final isConnected = state != AndroidDeviceState.disconnected;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: isConnected ? accentGreen.withValues(alpha: 0.35) : AppColors.cardBorder,
          width: 1.2,
        ),
        boxShadow: [
          if (isConnected)
            BoxShadow(
              color: accentGreen.withValues(alpha: 0.08),
              blurRadius: 20,
              offset: const Offset(0, 4),
            ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header Row
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: isConnected
                      ? accentGreen.withValues(alpha: 0.12)
                      : AppColors.cardElevated,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(
                  Icons.phone_android_rounded,
                  color: isConnected ? accentGreen : AppColors.textMuted,
                  size: 26,
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      isConnected
                          ? (device?.name ?? 'Android Device')
                          : 'No Device Detected',
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
                          decoration: BoxDecoration(
                            color: isConnected ? AppColors.success : AppColors.textMuted,
                            shape: BoxShape.circle,
                          ),
                        ),
                        const SizedBox(width: 6),
                        Text(
                          isConnected ? 'USB Connected' : 'Waiting for connection...',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: isConnected ? AppColors.success : AppColors.textSecondary,
                          ),
                        ),
                        if (device?.connectionType != null) ...[
                          const SizedBox(width: 8),
                          Text(
                            '•  ${device!.connectionType}',
                            style: TextStyle(
                              fontSize: 12,
                              color: AppColors.textSecondary,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ],
                ),
              ),

              // State Badge
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                decoration: BoxDecoration(
                  color: state.badgeColor.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: state.badgeColor.withValues(alpha: 0.4)),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      _getStateIcon(state),
                      size: 13,
                      color: state.badgeColor,
                    ),
                    const SizedBox(width: 6),
                    Text(
                      state.label.toUpperCase(),
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 0.4,
                        color: state.badgeColor,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),

          const SizedBox(height: 18),
          Divider(color: AppColors.cardBorder, height: 1),
          const SizedBox(height: 16),

          // Detail Grid
          Wrap(
            spacing: 24,
            runSpacing: 12,
            children: [
              _buildInfoItem('STATE', state.label),
              _buildInfoItem('USB', isConnected ? 'Connected' : 'Disconnected'),
              _buildInfoItem(
                'ADB CAPABILITY',
                adbCapability.label,
                customColor: adbCapability.color,
              ),
              if (device?.model != null)
                _buildInfoItem('MODEL', device!.model!),
              if (device?.serialNumber != null)
                _buildInfoItem('IDENTIFIER', device!.serialNumber!),
              if (device?.osVersion != null)
                _buildInfoItem('ANDROID VERSION', device!.osVersion!),
            ],
          ),

          const SizedBox(height: 16),

          // What 414Unlock Found Box
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: AppColors.backgroundSecondary,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: AppColors.cardBorder),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(Icons.info_outline_rounded,
                        size: 14, color: AppColors.textSecondary),
                    SizedBox(width: 8),
                    Text(
                      'ASSESSMENT',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 0.8,
                        color: AppColors.textSecondary,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                Text(
                  state.userExplanation,
                  style: TextStyle(
                    fontSize: 13,
                    color: AppColors.textPrimary,
                    height: 1.4,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildInfoItem(String label, String value, {Color? customColor}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          label,
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
            fontWeight: FontWeight.w600,
            color: customColor ?? AppColors.textPrimary,
          ),
        ),
      ],
    );
  }

  IconData _getStateIcon(AndroidDeviceState st) {
    switch (st) {
      case AndroidDeviceState.disconnected:
        return Icons.usb_off_rounded;
      case AndroidDeviceState.normalAndroid:
        return Icons.check_circle_outline_rounded;
      case AndroidDeviceState.normalAndroidLocked:
        return Icons.lock_outline_rounded;
      case AndroidDeviceState.setupWizard:
        return Icons.flag_outlined;
      case AndroidDeviceState.recovery:
        return Icons.build_circle_outlined;
      case AndroidDeviceState.bootloader:
      case AndroidDeviceState.fastboot:
        return Icons.terminal_rounded;
      case AndroidDeviceState.downloadMode:
        return Icons.downloading_rounded;
      default:
        return Icons.help_outline_rounded;
    }
  }
}