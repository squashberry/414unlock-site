import 'package:flutter/material.dart';
import 'package:unlock_core/unlock_core.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const UnlockAndroidApp());
}

class UnlockAndroidApp extends StatefulWidget {
  const UnlockAndroidApp({super.key});

  @override
  State<UnlockAndroidApp> createState() => _UnlockAndroidAppState();
}

class _UnlockAndroidAppState extends State<UnlockAndroidApp> {
  late final PrerequisiteService _prerequisiteService;
  late final DeviceDetectionService _detectionService;
  late final ExternalPartnerEngine _engine;
  late final EngineProcessManager _engineManager;
  late final AndroidDeviceStateController _stateController;

  @override
  void initState() {
    super.initState();
    _prerequisiteService = PrerequisiteService(
      prerequisites: AndroidPrerequisites.getPrerequisites(),
    );
    _detectionService = AndroidDeviceDetectionService();
    _engine = ExternalPartnerEngine();

    final engineConfig = EngineConfig();
    _engineManager = EngineProcessManager(config: engineConfig);
    _stateController = AndroidDeviceStateController(
      detectionService: _detectionService,
      processManager: _engineManager,
    );
    _engineManager.start();
  }

  @override
  void dispose() {
    _stateController.dispose();
    _engineManager.dispose();
    _prerequisiteService.dispose();
    _detectionService.dispose();
    _engine.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: '414Unlock Android - Android Device Utility',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.getTheme(AppBrandVariant.android),
      home: MainFlowShell(
        title: '414Unlock Android',
        subtitle: 'Android Device Utility',
        variant: AppBrandVariant.android,
        prerequisiteService: _prerequisiteService,
        detectionService: _detectionService,
        engine: _engine,
        androidStateController: _stateController,
      ),
    );
  }
}
