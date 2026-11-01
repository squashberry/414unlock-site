import 'package:flutter/material.dart';
import '../../core/config/app_config.dart';
import '../../core/device/device_info.dart';
import '../../core/engine/external_partner_engine.dart';
import '../../core/prerequisites/iremove_manager.dart';
import '../../theme/app_theme.dart';
import '../../widgets/app_button.dart';
import '../../widgets/device_card.dart';

class PartnerHandoffView extends StatefulWidget {
  final ExternalPartnerEngine engine;
  final DeviceInfo device;
  final AppBrandVariant variant;
  final IRemoveManager? iremoveManager;
  final VoidCallback onVerificationComplete;
  final VoidCallback onCancel;

  const PartnerHandoffView({
    super.key,
    required this.engine,
    required this.device,
    required this.variant,
    this.iremoveManager,
    required this.onVerificationComplete,
    required this.onCancel,
  });

  @override
  State<PartnerHandoffView> createState() => _PartnerHandoffViewState();
}

class _PartnerHandoffViewState extends State<PartnerHandoffView> {
  bool _hasLaunched = false;
  bool _isCheckingStatus = false;
  String? _launchError;

  @override
  Widget build(BuildContext context) {
    final accentColor = widget.variant == AppBrandVariant.iphone
        ? AppColors.iphoneBlue
        : AppColors.androidGreen;

    final config = AppConfig();

    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 24),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 720),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Cancel / Back Button
              TextButton.icon(
                onPressed: widget.onCancel,
                icon: Icon(Icons.arrow_back_rounded,
                    size: 16, color: AppColors.textSecondary),
                label: Text(
                  'Back to Device',
                  style:
                      TextStyle(fontSize: 12, color: AppColors.textSecondary),
                ),
              ),

              const SizedBox(height: 12),

              // Title
              Text(
                'Continue with Partner Tool',
                style: TextStyle(
                  fontSize: 26,
                  fontWeight: FontWeight.w700,
                  color: AppColors.textPrimary,
                  letterSpacing: -0.4,
                ),
              ),

              const SizedBox(height: 8),

              // Body
              Text(
                '414Unlock has prepared the device connection. Continue in the authorized partner application to perform the next supported operation.',
                style: TextStyle(
                  fontSize: 14,
                  color: AppColors.textSecondary,
                  height: 1.4,
                ),
              ),

              const SizedBox(height: 20),

              // Device Summary Card
              DeviceCard(device: widget.device, variant: widget.variant),

              const SizedBox(height: 20),

              // Warning Banner
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: AppColors.warning.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(
                    color: AppColors.warning.withValues(alpha: 0.35),
                    width: 1,
                  ),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Icon(
                      Icons.warning_amber_rounded,
                      color: AppColors.warning,
                      size: 22,
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Third-Party Handoff Notice',
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w700,
                              color: AppColors.warning,
                            ),
                          ),
                          SizedBox(height: 3),
                          Text(
                            '414Unlock does not control the partner application. Please ensure you are running authorized and authentic partner software.',
                            style: TextStyle(
                              fontSize: 12,
                              color: AppColors.textSecondary,
                              height: 1.3,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 16),

              // Partner Config info
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                decoration: BoxDecoration(
                  color: AppColors.card,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: AppColors.cardBorder),
                ),
                child: Row(
                  children: [
                    Icon(Icons.settings_outlined,
                        size: 16, color: AppColors.textMuted),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        config.partnerExecutablePath.isNotEmpty
                            ? 'Configured Path: ${config.partnerExecutablePath}'
                            : 'Configured URL: ${config.partnerUrl}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 12,
                          color: AppColors.textSecondary,
                        ),
                      ),
                    ),
                  ],
                ),
              ),

              if (_launchError != null) ...[
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: AppColors.error.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: AppColors.error.withValues(alpha: 0.3)),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.error_outline,
                          size: 16, color: AppColors.error),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          _launchError!,
                          style: const TextStyle(
                              fontSize: 12, color: AppColors.error),
                        ),
                      ),
                    ],
                  ),
                ),
              ],

              const SizedBox(height: 28),

              // Checking Status State or Buttons
              if (_isCheckingStatus) ...[
                Container(
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    color: AppColors.card,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: AppColors.cardBorder),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          valueColor: AlwaysStoppedAnimation<Color>(accentColor),
                        ),
                      ),
                      const SizedBox(width: 14),
                      Text(
                        'Checking operation status...',
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: AppColors.textPrimary,
                        ),
                      ),
                    ],
                  ),
                ),
              ] else ...[
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    AppButton(
                      text: 'Cancel',
                      variant: AppButtonVariant.secondary,
                      onPressed: widget.onCancel,
                    ),
                    const SizedBox(width: 12),
                    if (!_hasLaunched)
                      AppButton(
                        text: 'Open Partner Tool',
                        icon: Icons.open_in_new_rounded,
                        variant: AppButtonVariant.primary,
                        onPressed: _launchPartner,
                      )
                    else
                      AppButton(
                        text: 'Check Operation Status',
                        icon: Icons.verified_rounded,
                        variant: AppButtonVariant.primary,
                        onPressed: _verifyStatus,
                      ),
                  ],
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _launchPartner() async {
    setState(() {
      _launchError = null;
    });

    final bool success;
    if (widget.variant == AppBrandVariant.iphone && widget.iremoveManager != null) {
      success = await widget.iremoveManager!.launchTool();
      if (!success) {
        setState(() {
          _launchError = widget.iremoveManager!.statusMessage;
        });
        return;
      }
    } else {
      success = await widget.engine.launchPartnerTool();
    }

    if (success) {
      setState(() {
        _hasLaunched = true;
      });
    } else {
      setState(() {
        _launchError =
            'Partner application could not be started. Check the configured partner-tool path in Settings.';
      });
    }
  }

  Future<void> _verifyStatus() async {
    setState(() {
      _isCheckingStatus = true;
    });

    await Future.delayed(const Duration(milliseconds: 1000));
    await widget.engine.verifyHandoffCompletion(widget.device);

    if (mounted) {
      setState(() {
        _isCheckingStatus = false;
      });
      widget.onVerificationComplete();
    }
  }
}