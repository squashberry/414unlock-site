import 'package:flutter/material.dart';
import '../../core/device/android_device_state.dart';
import '../../core/device/android_device_state_controller.dart';
import '../../theme/app_theme.dart';
import '../../widgets/android_actions_panel.dart';
import '../../widgets/android_engine_prompt_dialog.dart';
import '../../widgets/android_live_operation_panel.dart';
import '../../widgets/android_state_card.dart';
import '../../widgets/app_button.dart';
import '../../widgets/device_illustration.dart';
import '../../widgets/troubleshoot_dialog.dart';

class AndroidStateView extends StatefulWidget {
  final AndroidDeviceStateController stateController;
  final VoidCallback onBack;
  final VoidCallback onOpenLogs;

  const AndroidStateView({
    super.key,
    required this.stateController,
    required this.onBack,
    required this.onOpenLogs,
  });

  @override
  State<AndroidStateView> createState() => _AndroidStateViewState();
}

class _AndroidStateViewState extends State<AndroidStateView> {
  @override
  void initState() {
    super.initState();
    widget.stateController.addListener(_handleStateChange);
  }

  @override
  void dispose() {
    widget.stateController.removeListener(_handleStateChange);
    super.dispose();
  }

  void _handleStateChange() {
    if (!mounted) return;
    final prompt = widget.stateController.activePrompt;
    if (prompt != null) {
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (_) => AndroidEnginePromptDialog(
          prompt: prompt,
          onActionSelected: (action) {
            widget.stateController.respondToPrompt(action);
          },
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: widget.stateController,
      builder: (context, _) {
        final ctrl = widget.stateController;
        final state = ctrl.state;
        final isConnected = state != AndroidDeviceState.disconnected;

        return SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 24),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 780),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  // Back button
                  Align(
                    alignment: Alignment.centerLeft,
                    child: TextButton.icon(
                      onPressed: widget.onBack,
                      icon: Icon(Icons.arrow_back_rounded,
                          size: 16, color: AppColors.textSecondary),
                      label: Text(
                        'Prerequisites',
                        style: TextStyle(
                            fontSize: 12, color: AppColors.textSecondary),
                      ),
                    ),
                  ),

                  const SizedBox(height: 8),

                  // Title & Subtitle: "Detecting your Android device..." initially!
                  Text(
                    isConnected
                        ? 'Android Device State'
                        : 'Detecting your Android device...',
                    style: TextStyle(
                      fontSize: 26,
                      fontWeight: FontWeight.w700,
                      color: AppColors.textPrimary,
                      letterSpacing: -0.4,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    isConnected
                        ? 'Inspecting low-level hardware interfaces and supported recovery options.'
                        : 'Connect your Android device to this PC using a USB cable.',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 14,
                      color: AppColors.textSecondary,
                    ),
                  ),

                  const SizedBox(height: 24),

                  // Central Device Illustration (with pulse or connection aura)
                  DeviceIllustration(
                    variant: AppBrandVariant.android,
                    isConnected: isConnected,
                    size: 150,
                  ),

                  const SizedBox(height: 24),

                  // Main Evidence-Based State Card
                  AndroidStateCard(
                    state: state,
                    adbCapability: ctrl.adbCapability,
                    device: ctrl.currentDevice,
                  ),

                  const SizedBox(height: 20),

                  // Live Operation Panel OR Available Recovery Actions Panel
                  if (ctrl.isOperationRunning && ctrl.activeOperation != null) ...[
                    AndroidLiveOperationPanel(
                      action: ctrl.activeOperation!,
                      progressMessage: ctrl.activeProgressMessage,
                      events: ctrl.liveEvents,
                      onCancel: ctrl.cancelOperation,
                    ),
                    const SizedBox(height: 20),
                  ] else if (isConnected) ...[
                    AndroidActionsPanel(
                      actions: ctrl.availableActions,
                      isOperationRunning: ctrl.isOperationRunning,
                      onSelectAction: (action) => ctrl.executeAction(action),
                    ),
                    const SizedBox(height: 20),
                  ],

                  // Bottom Toolbar
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      AppButton(
                        text: 'Troubleshoot',
                        icon: Icons.help_outline_rounded,
                        variant: AppButtonVariant.secondary,
                        height: 38,
                        onPressed: () {
                          showDialog(
                            context: context,
                            builder: (_) => const TroubleshootDialog(
                              variant: AppBrandVariant.android,
                            ),
                          );
                        },
                      ),
                      const SizedBox(width: 12),
                      AppButton(
                        text: 'Recheck State',
                        icon: Icons.refresh_rounded,
                        variant: AppButtonVariant.secondary,
                        height: 38,
                        isLoading: ctrl.isAssessing,
                        onPressed: ctrl.isAssessing
                            ? null
                            : () => ctrl.reassessState(),
                      ),
                      const SizedBox(width: 12),
                      AppButton(
                        text: 'View Diagnostics',
                        icon: Icons.terminal_rounded,
                        variant: AppButtonVariant.secondary,
                        height: 38,
                        onPressed: widget.onOpenLogs,
                      ),
                    ],
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