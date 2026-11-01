import 'package:flutter/material.dart';
import '../../core/auth/auth_service.dart';
import '../../core/config/app_config.dart';
import '../../core/device/android_device_state_controller.dart';
import '../../core/device/device_detection_service.dart';
import '../../core/engine/external_partner_engine.dart';
import '../../core/logging/app_logger.dart';
import '../../core/prerequisites/prerequisite_service.dart';
import '../../core/prerequisites/setup_coordinator.dart';
import '../../theme/app_theme.dart';
import '../../widgets/app_button.dart';
import '../../widgets/app_header.dart';
import '../../widgets/log_viewer_dialog.dart';
import '../../widgets/settings_dialog.dart';
import '../../widgets/startup_logo_animation.dart';
import '../auth/auth_page_view.dart';
import '../device_connection/android_state_view.dart';
import '../device_connection/device_connection_view.dart';
import '../handoff/partner_handoff_view.dart';
import '../prerequisites/prerequisites_view.dart';
import '../result/result_view.dart';
import '../setup/setup_view.dart';
import '../unlock_operation/unlock_operation_view.dart';

enum FlowStep {
  splash,
  startupRequirements,
  prerequisites,
  deviceConnection,
  auth,
  unlockOperation,
  partnerHandoff,
  result,
}

class MainFlowShell extends StatefulWidget {
  final String title;
  final String subtitle;
  final AppBrandVariant variant;
  final PrerequisiteService prerequisiteService;
  final DeviceDetectionService detectionService;
  final ExternalPartnerEngine engine;
  final AndroidDeviceStateController? androidStateController;
  final SetupCoordinator? setupCoordinator;
  final AuthService? authService;

  const MainFlowShell({
    super.key,
    required this.title,
    required this.subtitle,
    required this.variant,
    required this.prerequisiteService,
    required this.detectionService,
    required this.engine,
    this.androidStateController,
    this.setupCoordinator,
    this.authService,
  });

  @override
  State<MainFlowShell> createState() => _MainFlowShellState();
}

class _MainFlowShellState extends State<MainFlowShell> {
  FlowStep _currentStep = FlowStep.splash;

  @override
  void initState() {
    super.initState();
    AppLogger().info('Application started: ${widget.title} (${widget.subtitle})');
    AppConfig().load();
    widget.engine.initialize();
    widget.authService?.restoreSession();
  }

  void _onSplashComplete() {
    if (widget.setupCoordinator != null) {
      setState(() {
        _currentStep = FlowStep.startupRequirements;
      });
      widget.setupCoordinator!.initialize();
      return;
    }

    setState(() {
      _currentStep = FlowStep.prerequisites;
    });
    if (AppConfig().autoCheckPrerequisites) {
      widget.prerequisiteService.checkAll();
    }
  }

  void _onRequirementsContinue() {
    setState(() {
      _currentStep = FlowStep.deviceConnection;
    });
    widget.detectionService.startMonitoring();
  }

  void _onPrerequisitesContinue() {
    setState(() {
      _currentStep = FlowStep.deviceConnection;
    });
    widget.detectionService.startMonitoring();
    if (widget.androidStateController != null) {
      widget.androidStateController!.reassessState();
    }
  }

  void _onDeviceConnectionContinue() {
    final dev = widget.detectionService.currentDevice;
    if (dev != null) {
      // For iPhone workflow, proceed to dedicated unlock operation
      if (widget.variant == AppBrandVariant.iphone) {
        setState(() {
          _currentStep = FlowStep.unlockOperation;
        });
      } else {
        widget.engine.executeOperation(dev);
        setState(() {
          _currentStep = FlowStep.partnerHandoff;
        });
      }
    }
  }

  void _onAuthCompleted() {
    // Return directly to unlock operation after successful authentication
    setState(() {
      _currentStep = FlowStep.unlockOperation;
    });
  }

  void _onHandoffComplete() {
    setState(() {
      _currentStep = FlowStep.result;
    });
  }

  void _onFinish() {
    setState(() {
      _currentStep = FlowStep.deviceConnection;
    });
    if (widget.androidStateController != null) {
      widget.androidStateController!.reassessState();
    }
  }

  void _openSettings() {
    showDialog(
      context: context,
      builder: (_) => SettingsDialog(variant: widget.variant),
    );
  }

  void _openLogs() {
    showDialog(
      context: context,
      builder: (_) => LogViewerDialog(variant: widget.variant),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_currentStep == FlowStep.splash) {
      return StartupLogoAnimation(
        variant: widget.variant,
        subtitle: widget.subtitle,
        onComplete: _onSplashComplete,
      );
    }

    return Scaffold(
      backgroundColor: AppColors.background,
      body: Column(
        children: [
          // Header
          AppHeader(
            title: widget.title,
            subtitle: widget.subtitle,
            variant: widget.variant,
            onOpenSettings: _openSettings,
            onOpenLogs: _openLogs,
            trailing: _buildBreadcrumb(),
          ),

          // Main View Body
          Expanded(
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 250),
              child: _buildCurrentStepView(),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBreadcrumb() {
    String stepLabel;
    switch (_currentStep) {
      case FlowStep.splash:
        stepLabel = 'Starting';
        break;
      case FlowStep.startupRequirements:
        stepLabel = 'Checking Requirements';
        break;
      case FlowStep.prerequisites:
        stepLabel = 'Prerequisites';
        break;
      case FlowStep.deviceConnection:
        stepLabel = (widget.variant == AppBrandVariant.android && widget.androidStateController != null)
            ? 'Device Assessment'
            : 'Device Connection';
        break;
      case FlowStep.auth:
        stepLabel = 'Account Authorization';
        break;
      case FlowStep.unlockOperation:
        stepLabel = 'Preparing Unlock';
        break;
      case FlowStep.partnerHandoff:
        stepLabel = 'Partner Handoff';
        break;
      case FlowStep.result:
        stepLabel = 'Status Verification';
        break;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.cardBorder),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 6,
            height: 6,
            decoration: BoxDecoration(
              color: widget.variant == AppBrandVariant.iphone
                  ? AppColors.iphoneBlue
                  : AppColors.androidGreen,
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 6),
          Text(
            stepLabel,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: AppColors.textSecondary,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCurrentStepView() {
    switch (_currentStep) {
      case FlowStep.splash:
        return const SizedBox.shrink();

      case FlowStep.startupRequirements:
        if (widget.setupCoordinator != null) {
          return SetupView(
            key: const ValueKey('startup_requirements'),
            coordinator: widget.setupCoordinator!,
            onContinue: _onRequirementsContinue,
          );
        }
        return const SizedBox.shrink();

      case FlowStep.prerequisites:
        return PrerequisitesView(
          key: const ValueKey('prereqs'),
          service: widget.prerequisiteService,
          variant: widget.variant,
          onContinue: _onPrerequisitesContinue,
        );

      case FlowStep.deviceConnection:
        if (widget.variant == AppBrandVariant.android && widget.androidStateController != null) {
          return AndroidStateView(
            key: const ValueKey('android_state_view'),
            stateController: widget.androidStateController!,
            onBack: () => setState(() => _currentStep = FlowStep.prerequisites),
            onOpenLogs: _openLogs,
          );
        }
        return DeviceConnectionView(
          key: const ValueKey('connection'),
          detectionService: widget.detectionService,
          variant: widget.variant,
          authService: widget.authService,
          setupCoordinator: widget.setupCoordinator,
          onNeedSetup: () => setState(() => _currentStep = FlowStep.startupRequirements),
          onNavigateToAuth: () => setState(() => _currentStep = FlowStep.auth),
          onContinue: _onDeviceConnectionContinue,
          onBack: () => setState(() {
            _currentStep = widget.setupCoordinator != null
                ? FlowStep.startupRequirements
                : FlowStep.prerequisites;
          }),
        );

      case FlowStep.auth:
        return AuthPageView(
          key: const ValueKey('auth_page'),
          authService: widget.authService!,
          onAuthenticated: _onAuthCompleted,
          onBack: () => setState(() => _currentStep = FlowStep.deviceConnection),
        );

      case FlowStep.unlockOperation:
        final dev = widget.detectionService.currentDevice;
        if (dev == null) {
          return Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.usb_off_rounded, color: AppColors.warning, size: 48),
                const SizedBox(height: 16),
                Text(
                  'No iPhone Connected',
                  style: TextStyle(color: AppColors.textPrimary, fontSize: 18, fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 8),
                Text(
                  'Please connect your iPhone via USB to continue.',
                  style: TextStyle(color: AppColors.textSecondary, fontSize: 13),
                ),
                const SizedBox(height: 20),
                AppButton(
                  text: 'Return to Connection',
                  onPressed: () => setState(() => _currentStep = FlowStep.deviceConnection),
                ),
              ],
            ),
          );
        }
        return UnlockOperationView(
          key: const ValueKey('unlock_operation'),
          device: dev,
          iremoveManager: widget.setupCoordinator!.iremoveManager,
          onCancel: () => setState(() => _currentStep = FlowStep.deviceConnection),
          onComplete: () => setState(() => _currentStep = FlowStep.result),
        );

      case FlowStep.partnerHandoff:
        return PartnerHandoffView(
          key: const ValueKey('handoff'),
          engine: widget.engine,
          device: widget.detectionService.currentDevice!,
          variant: widget.variant,
          iremoveManager: widget.setupCoordinator?.iremoveManager,
          onVerificationComplete: _onHandoffComplete,
          onCancel: () => setState(() => _currentStep = FlowStep.deviceConnection),
        );

      case FlowStep.result:
        return ResultView(
          key: const ValueKey('result'),
          result: widget.engine.lastResult,
          variant: widget.variant,
          onFinish: _onFinish,
          onViewDiagnostics: _openLogs,
        );
    }
  }

  @override
  void dispose() {
    widget.detectionService.stopMonitoring();
    super.dispose();
  }
}