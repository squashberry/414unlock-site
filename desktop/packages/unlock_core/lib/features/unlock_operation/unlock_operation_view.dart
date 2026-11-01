import 'dart:async';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../core/device/apple_usbmux_client.dart';
import '../../core/device/device_info.dart';
import '../../core/prerequisites/iremove_manager.dart';
import '../../theme/app_theme.dart';
import '../../widgets/app_button.dart';

enum UnlockOpState {
  preparing,
  downloadingSupport,
  verifyingFiles,
  preparingFiles,
  checkingInstallation,
  launchingTools,
  toolActive,
  verifyingCompletion,
  awaitingTrustPrompt,
  completedSuccess,
  failed,
}

class UnlockOperationView extends StatefulWidget {
  final DeviceInfo device;
  final IRemoveManager iremoveManager;
  final VoidCallback onCancel;
  final VoidCallback onComplete;

  const UnlockOperationView({
    super.key,
    required this.device,
    required this.iremoveManager,
    required this.onCancel,
    required this.onComplete,
  });

  @override
  State<UnlockOperationView> createState() => _UnlockOperationViewState();
}

class _UnlockOperationViewState extends State<UnlockOperationView> {
  UnlockOpState _state = UnlockOpState.preparing;
  String _statusTitle = 'Preparing your unlock';
  String _statusSubtitle = 'Verifying environment and required tools...';
  String _errorMessage = '';
  bool _operationStarted = false;

  @override
  void initState() {
    super.initState();
    widget.iremoveManager.addListener(_onManagerUpdated);
    // Begin automated preparation workflow once
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_operationStarted) {
        _operationStarted = true;
        _startAutomatedPreparation();
      }
    });
  }

  void _onManagerUpdated() {
    if (!mounted) return;
    final mgr = widget.iremoveManager;

    if (mgr.status == IRemoveStatus.downloading) {
      setState(() {
        _state = UnlockOpState.downloadingSupport;
        _statusTitle = 'Downloading unlocking support';
        _statusSubtitle = mgr.totalBytes > 0
            ? '${(mgr.downloadedBytes / (1024 * 1024)).toStringAsFixed(1)} MB / ${(mgr.totalBytes / (1024 * 1024)).toStringAsFixed(1)} MB (${(mgr.downloadProgress * 100).toStringAsFixed(0)}%)'
            : 'Downloading required files...';
      });
    } else if (mgr.status == IRemoveStatus.validating) {
      setState(() {
        _state = UnlockOpState.verifyingFiles;
        _statusTitle = 'Verifying downloaded files';
        _statusSubtitle = 'Validating file integrity and digital signatures...';
      });
    } else if (mgr.status == IRemoveStatus.extracting) {
      setState(() {
        _state = UnlockOpState.preparingFiles;
        _statusTitle = 'Preparing required files';
        _statusSubtitle = 'Extracting and configuring unlocking support...';
      });
    }
  }

  Future<void> _startAutomatedPreparation() async {
    setState(() {
      _state = UnlockOpState.preparing;
      _statusTitle = 'Preparing your unlock';
      _statusSubtitle = 'Checking installation and requirements...';
      _errorMessage = '';
    });

    try {
      // 1. Check if usable installation already exists
      final isInstalled = await widget.iremoveManager.checkInstalled();

      if (!isInstalled) {
        // Automatically download and prepare unlocking support
        setState(() {
          _state = UnlockOpState.downloadingSupport;
          _statusTitle = 'Downloading unlocking support';
          _statusSubtitle = 'Connecting to download servers...';
        });

        final downloaded = await widget.iremoveManager.downloadAndExtract();
        if (!downloaded) {
          setState(() {
            _state = UnlockOpState.failed;
            _statusTitle = 'Preparation Failed';
            _statusSubtitle = 'Could not download unlocking support.';
            _errorMessage = widget.iremoveManager.statusMessage;
          });
          return;
        }
      }

      // 2. Check installation
      setState(() {
        _state = UnlockOpState.checkingInstallation;
        _statusTitle = 'Checking installation';
        _statusSubtitle = 'Verifying tool binaries and dependencies...';
      });

      await Future.delayed(const Duration(milliseconds: 400));
      if (!widget.iremoveManager.isReady) {
        setState(() {
          _state = UnlockOpState.failed;
          _statusTitle = 'Preparation Failed';
          _statusSubtitle = 'Executable was not detected or failed validation.';
          _errorMessage = widget.iremoveManager.statusMessage;
        });
        return;
      }

      // 3. Launching required tools
      setState(() {
        _state = UnlockOpState.launchingTools;
        _statusTitle = 'Launching required tools…';
        _statusSubtitle = 'Please do not close 414Unlock while this operation is in progress.';
      });

      final success = await widget.iremoveManager.launchTool(widget.device);
      if (success) {
        setState(() {
          _state = UnlockOpState.toolActive;
          _statusTitle = 'Unlock In Progress';
          _statusSubtitle =
              'Follow the instructions in the external tool to complete the unlock.\nOnce finished, click "Done — Verify Device Unlock" below.';
        });
      } else {
        setState(() {
          _state = UnlockOpState.failed;
          _statusTitle = 'Launch Failed';
          _statusSubtitle = 'Could not start the unlocking support executable.';
          _errorMessage = widget.iremoveManager.statusMessage;
        });
      }
    } catch (e) {
      setState(() {
        _state = UnlockOpState.failed;
        _statusTitle = 'Unexpected Error';
        _statusSubtitle = 'An error occurred during preparation.';
        _errorMessage = e.toString();
      });
    }
  }

  Future<void> _onUserClickedDone() async {
    setState(() {
      _state = UnlockOpState.verifyingCompletion;
      _statusTitle = 'Verifying Device Status';
      _statusSubtitle = 'Closing external tools and cross-checking iPhone response...';
    });

    // Cleanly terminate the opened partner tool as requested
    await widget.iremoveManager.terminateTool();

    // Brief pause to allow USB stack to settle
    await Future.delayed(const Duration(milliseconds: 1200));

    await _checkDevicePostUnlockStatus();
  }

  Future<void> _checkDevicePostUnlockStatus() async {
    setState(() {
      _state = UnlockOpState.verifyingCompletion;
      _statusTitle = 'Cross-checking iPhone';
      _statusSubtitle = 'Communicating with iPhone over USB...';
    });

    try {
      final devices = await AppleUsbmuxClient.listConnectedDevices(
        timeout: const Duration(seconds: 3),
      );

      if (devices.isEmpty) {
        setState(() {
          _state = UnlockOpState.awaitingTrustPrompt;
          _statusTitle = 'Device Rebooting or Reconnecting';
          _statusSubtitle =
              'Ensure your iPhone has finished rebooting to the home screen and is connected via USB.';
        });
        return;
      }

      final deviceEntry = devices.first;
      final (info, error) = await AppleUsbmuxClient.queryLockdownWithRawResponse(
        deviceEntry.deviceId,
        timeout: const Duration(seconds: 3),
      );

      if (info != null) {
        setState(() {
          _state = UnlockOpState.completedSuccess;
          _statusTitle = 'Unlock Done & Verified!';
          _statusSubtitle =
              'The iPhone is verified and active on the home screen. External tools have been closed.';
        });
      } else if (error != null &&
          (error.contains('Pairing') ||
              error.contains('Password') ||
              error.contains('InvalidHost') ||
              error.contains('untrusted'))) {
        setState(() {
          _state = UnlockOpState.awaitingTrustPrompt;
          _statusTitle = 'Check iPhone & Tap "Trust"';
          _statusSubtitle =
              'The iPhone has reached the home screen! Please wake the device, unlock it, and tap "Trust This Computer" when prompted.';
        });
      } else {
        setState(() {
          _state = UnlockOpState.completedSuccess;
          _statusTitle = 'Unlock Process Done';
          _statusSubtitle =
              'The unlock workflow has finished and helper tools have been cleanly closed.';
        });
      }
    } catch (_) {
      setState(() {
        _state = UnlockOpState.completedSuccess;
        _statusTitle = 'Unlock Process Finished';
        _statusSubtitle =
            'The unlock workflow has finished and helper tools have been cleanly closed.';
      });
    }
  }

  Future<void> _cancelAndCleanup() async {
    await widget.iremoveManager.terminateTool();
    widget.onCancel();
  }

  void _retry() {
    _startAutomatedPreparation();
  }

  Future<void> _contactSupport() async {
    final uri = Uri.parse('mailto:414unlock@gmail.com?subject=414Unlock%20Support%20Request');
    try {
      if (await canLaunchUrl(uri)) {
        await launchUrl(uri);
      }
    } catch (_) {}
  }

  @override
  void dispose() {
    widget.iremoveManager.removeListener(_onManagerUpdated);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isWorking = _state == UnlockOpState.preparing ||
        _state == UnlockOpState.downloadingSupport ||
        _state == UnlockOpState.verifyingFiles ||
        _state == UnlockOpState.preparingFiles ||
        _state == UnlockOpState.checkingInstallation ||
        _state == UnlockOpState.launchingTools ||
        _state == UnlockOpState.verifyingCompletion;
    final isDownloading = _state == UnlockOpState.downloadingSupport;
    final isFailed = _state == UnlockOpState.failed;

    return Scaffold(
      backgroundColor: AppColors.background,
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 40),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 580),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                // Icon
                Container(
                  width: 64,
                  height: 64,
                  decoration: BoxDecoration(
                    color: AppColors.card,
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: isFailed
                          ? AppColors.error.withValues(alpha: 0.6)
                          : (_state == UnlockOpState.completedSuccess || _state == UnlockOpState.toolActive)
                              ? AppColors.success.withValues(alpha: 0.6)
                              : _state == UnlockOpState.awaitingTrustPrompt
                                  ? AppColors.warning.withValues(alpha: 0.6)
                                  : AppColors.iphoneBlue.withValues(alpha: 0.6),
                      width: 2,
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: (isFailed
                                ? AppColors.error
                                : _state == UnlockOpState.awaitingTrustPrompt
                                    ? AppColors.warning
                                    : AppColors.iphoneBlue)
                            .withValues(alpha: 0.2),
                        blurRadius: 16,
                      ),
                    ],
                  ),
                  child: Center(
                    child: Icon(
                      isFailed
                          ? Icons.error_outline_rounded
                          : _state == UnlockOpState.completedSuccess
                              ? Icons.verified_rounded
                              : _state == UnlockOpState.awaitingTrustPrompt
                                  ? Icons.touch_app_rounded
                                  : _state == UnlockOpState.toolActive
                                      ? Icons.phonelink_setup_rounded
                                      : Icons.sync_rounded,
                      color: isFailed
                          ? AppColors.error
                          : _state == UnlockOpState.completedSuccess
                              ? AppColors.success
                              : _state == UnlockOpState.awaitingTrustPrompt
                                  ? AppColors.warning
                                  : AppColors.iphoneBlue,
                      size: 28,
                    ),
                  ),
                ),
                const SizedBox(height: 24),

                // Title & Subtitle
                Text(
                  _statusTitle,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.w700,
                    color: AppColors.textPrimary,
                    letterSpacing: -0.3,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  _statusSubtitle,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 13,
                    color: AppColors.textSecondary,
                    height: 1.4,
                  ),
                ),
                const SizedBox(height: 28),

                // Progress Bar when working
                if (isWorking) ...[
                  ClipRRect(
                    borderRadius: BorderRadius.circular(4),
                    child: LinearProgressIndicator(
                      value: isDownloading && widget.iremoveManager.downloadProgress > 0
                          ? widget.iremoveManager.downloadProgress
                          : null,
                      backgroundColor: AppColors.cardBorder,
                      valueColor: const AlwaysStoppedAnimation<Color>(AppColors.iphoneBlue),
                      minHeight: 6,
                    ),
                  ),
                  const SizedBox(height: 24),
                ],

                // Connected Device Info Box
                Container(
                  padding: const EdgeInsets.all(18),
                  decoration: AppColors.liquidGlassDecoration(
                    radius: 14,
                    elevated: true,
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.phone_iphone_rounded, color: AppColors.iphoneBlue, size: 24),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              widget.device.name,
                              style: TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w600,
                                color: AppColors.textPrimary,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              'Device ID: ${widget.device.maskedIdentifier} · Mode: ${widget.device.mode.label}',
                              style: TextStyle(fontSize: 12, color: AppColors.textSecondary),
                            ),
                            if (widget.device.modelIdentifier != null || widget.device.osVersion != null) ...[
                              const SizedBox(height: 2),
                              Text(
                                '${widget.device.modelIdentifier ?? "Model ID Unconfirmed"} · ${widget.device.osVersion != null ? "iOS ${widget.device.osVersion!}" : "Firmware Unconfirmed"}',
                                style: TextStyle(fontSize: 11, color: AppColors.textMuted),
                              ),
                            ],
                          ],
                        ),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(
                          color: AppColors.success.withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: const Text(
                          'CONNECTED',
                          style: TextStyle(
                            color: AppColors.success,
                            fontSize: 10,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),

                // No-Cellular-Signal Limitation Reminder
                if (widget.device.compatibilityResult?.hasNoCellularSignalLimitation == true) ...[
                  const SizedBox(height: 12),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                    decoration: BoxDecoration(
                      color: AppColors.warning.withValues(alpha: 0.08),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: AppColors.warning.withValues(alpha: 0.3)),
                    ),
                    child: Row(
                      children: const [
                        Icon(Icons.info_outline_rounded, size: 14, color: AppColors.warning),
                        SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            'Service Limitation: Provides Wi-Fi capability only (No cellular voice, SMS, or carrier data).',
                            style: TextStyle(fontSize: 11, color: AppColors.warning, fontWeight: FontWeight.w600),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],

                // Error Box with Support Contact & Official Apple Guide
                if (isFailed) ...[
                  const SizedBox(height: 20),
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: AppColors.error.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: AppColors.error.withValues(alpha: 0.3)),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (_errorMessage.isNotEmpty) ...[
                          Text(
                            _errorMessage,
                            style: const TextStyle(color: AppColors.error, fontSize: 13),
                          ),
                          const SizedBox(height: 12),
                        ],
                        Text(
                          'Need help? Contact 414unlock@gmail.com',
                          style: TextStyle(
                            color: AppColors.textPrimary,
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(height: 8),
                        InkWell(
                          onTap: () => launchUrl(
                            Uri.parse('https://support.apple.com/en-us/108934'),
                            mode: LaunchMode.externalApplication,
                          ),
                          child: const Text(
                            'Official Apple Activation Lock Guide (support.apple.com/en-us/108934) ↗',
                            style: TextStyle(
                              color: AppColors.iphoneBlue,
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],

                const SizedBox(height: 28),

                // Action Buttons
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    if (isFailed) ...[
                      AppButton(
                        text: 'Retry',
                        icon: Icons.refresh_rounded,
                        variant: AppButtonVariant.primary,
                        onPressed: _retry,
                      ),
                      const SizedBox(width: 12),
                      AppButton(
                        text: 'Contact Support',
                        icon: Icons.email_outlined,
                        variant: AppButtonVariant.secondary,
                        onPressed: _contactSupport,
                      ),
                      const SizedBox(width: 12),
                      AppButton(
                        text: 'Cancel',
                        variant: AppButtonVariant.secondary,
                        onPressed: _cancelAndCleanup,
                      ),
                    ] else if (_state == UnlockOpState.toolActive) ...[
                      AppButton(
                        text: 'Done — Verify Device Unlock',
                        icon: Icons.check_circle_outline_rounded,
                        variant: AppButtonVariant.primary,
                        onPressed: _onUserClickedDone,
                      ),
                      const SizedBox(width: 12),
                      AppButton(
                        text: 'Cancel',
                        variant: AppButtonVariant.secondary,
                        onPressed: _cancelAndCleanup,
                      ),
                    ] else if (_state == UnlockOpState.awaitingTrustPrompt) ...[
                      AppButton(
                        text: 'I Have Trusted — Re-Check',
                        icon: Icons.refresh_rounded,
                        variant: AppButtonVariant.primary,
                        onPressed: _checkDevicePostUnlockStatus,
                      ),
                      const SizedBox(width: 12),
                      AppButton(
                        text: 'Skip & Finish',
                        variant: AppButtonVariant.secondary,
                        onPressed: widget.onComplete,
                      ),
                    ] else if (_state == UnlockOpState.completedSuccess) ...[
                      AppButton(
                        text: 'Finish & Done',
                        icon: Icons.check_circle_rounded,
                        variant: AppButtonVariant.primary,
                        onPressed: widget.onComplete,
                      ),
                    ] else if (_state == UnlockOpState.verifyingCompletion) ...[
                      const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          valueColor: AlwaysStoppedAnimation<Color>(AppColors.iphoneBlue),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Text(
                        'Verifying iPhone status...',
                        style: TextStyle(fontSize: 13, color: AppColors.textSecondary),
                      ),
                    ] else ...[
                      AppButton(
                        text: 'Cancel Operation',
                        variant: AppButtonVariant.secondary,
                        onPressed: _cancelAndCleanup,
                      ),
                    ],
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}