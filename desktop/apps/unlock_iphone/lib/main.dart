import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:tray_manager/tray_manager.dart';
import 'package:unlock_core/unlock_core.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:window_manager/window_manager.dart';

import 'widgets/close_confirmation_dialog.dart';
import 'widgets/custom_title_bar.dart';

final GlobalKey<NavigatorState> appNavigatorKey = GlobalKey<NavigatorState>();

void main(List<String> args) async {
  WidgetsFlutterBinding.ensureInitialized();

  // Load persisted configuration (appearance theme, tray behavior, etc.)
  try {
    await AppConfig().load();
    AppColors.isDark = AppConfig().isDarkMode;
  } catch (_) {}

  final startInTray = args.contains('--tray') ||
      args.contains('--background') ||
      args.contains('-t');

  if (!kIsWeb && (defaultTargetPlatform == TargetPlatform.windows ||
                  defaultTargetPlatform == TargetPlatform.linux ||
                  defaultTargetPlatform == TargetPlatform.macOS)) {
    try {
      await windowManager.ensureInitialized();
      const windowOptions = WindowOptions(
        size: Size(1280, 750),
        minimumSize: Size(960, 600),
        center: true,
        backgroundColor: Colors.transparent,
        skipTaskbar: false,
        titleBarStyle: TitleBarStyle.hidden,
      );
      await windowManager.waitUntilReadyToShow(windowOptions, () async {
        if (!startInTray) {
          await windowManager.show();
          await windowManager.focus();
        } else {
          await windowManager.hide();
        }
        await windowManager.setPreventClose(true);
      });
    } catch (_) {}
  }

  runApp(const UnlockIPhoneApp());
}

class UnlockIPhoneApp extends StatefulWidget {
  const UnlockIPhoneApp({super.key});

  @override
  State<UnlockIPhoneApp> createState() => _UnlockIPhoneAppState();
}

class _UnlockIPhoneAppState extends State<UnlockIPhoneApp>
    with WindowListener, TrayListener {
  late final PrerequisiteService _prerequisiteService;
  late final DeviceDetectionService _detectionService;
  late final ExternalPartnerEngine _engine;
  late final ITunesManager _itunesManager;
  late final IRemoveManager _iremoveManager;
  late final SetupCoordinator _setupCoordinator;
  late final AuthService _authService;
  late final AppUpdateService _updateService;
  late final PartnerSupervisorService _partnerSupervisor;

  @override
  void initState() {
    super.initState();

    _updateService = AppUpdateService();
    _updateService.addListener(_onUpdateStateChanged);

    _partnerSupervisor = PartnerSupervisorService();
    _partnerSupervisor.onPartnerDirectLaunchDetected = _onPartnerDirectLaunchDetected;

    if (!kIsWeb &&
        defaultTargetPlatform == TargetPlatform.windows &&
        !Platform.environment.containsKey('FLUTTER_TEST')) {
      windowManager.addListener(this);
      trayManager.addListener(this);
      _initSystemTray();
      _partnerSupervisor.start();
      _updateService.startPeriodicChecks();
      StartupService.ensureAutoStartEnabled();
    }

    _prerequisiteService = PrerequisiteService(
      prerequisites: ApplePrerequisites.getPrerequisites(),
    );
    _detectionService = AppleDeviceDetectionService();
    _engine = ExternalPartnerEngine();

    _itunesManager = ITunesManager();
    _iremoveManager = IRemoveManager();
    _setupCoordinator = SetupCoordinator(
      itunesManager: _itunesManager,
      iremoveManager: _iremoveManager,
    );
    _authService = AuthService();
    _authService.currentDeviceGetter = () => _detectionService.currentDevice;
    _detectionService.addListener(_onDeviceChanged);

    // Pause partner supervisor while 414Unlock itself is running the engine handoff
    _engine.addListener(_onEngineChanged);
  }

  void _onEngineChanged() {
    if (_engine.state == EngineState.running) {
      _partnerSupervisor.pause();
    } else {
      _partnerSupervisor.resume();
    }
  }

  void _onPartnerDirectLaunchDetected() {
    _bringWindowToForeground();
  }

  void _onUpdateStateChanged() {
    if (mounted) setState(() {});
    _updateTrayMenu();
  }

  Future<void> _initSystemTray() async {
    if (kIsWeb || Platform.environment.containsKey('FLUTTER_TEST')) return;
    try {
      // Set system tray icon to multi-resolution Windows ICO
      final iconPath = Platform.isWindows
          ? 'windows/runner/resources/app_icon.ico'
          : 'assets/icons/app_icon.png';
      await trayManager.setIcon(iconPath);
      await _updateTrayMenu();
    } catch (_) {}
  }

  Future<void> _updateTrayMenu() async {
    if (kIsWeb || Platform.environment.containsKey('FLUTTER_TEST')) return;
    try {
      final device = _detectionService.currentDevice;
      final deviceLabel =
          device != null ? 'Connected: ${device.name}' : 'No iPhone connected';

      final update = _updateService.latestResult;
      final updateAvailable = update != null && update.updateAvailable;

      final menu = Menu(
        items: [
          MenuItem(
            key: 'show_window',
            label: 'Open 414Unlock',
          ),
          if (updateAvailable) ...[
            MenuItem.separator(),
            MenuItem(
              key: 'update_app',
              label: 'Update Available (v${update.latestVersion})',
            ),
          ],
          MenuItem.separator(),
          MenuItem(
            key: 'device_status',
            label: deviceLabel,
            disabled: true,
          ),
          MenuItem.separator(),
          MenuItem(
            key: 'quit_app',
            label: 'Quit 414Unlock',
          ),
        ],
      );
      await trayManager.setContextMenu(menu);
      await trayManager.setToolTip(
        updateAvailable
            ? '414Unlock (v${update.latestVersion} available) — $deviceLabel'
            : '414Unlock — $deviceLabel',
      );
    } catch (_) {}
  }

  void _onDeviceChanged() {
    _authService.onConnectedDeviceChanged(_detectionService.currentDevice);
    _updateTrayMenu();
    if (_detectionService.currentDevice != null) {
      _bringWindowToForeground();
    }
  }

  Future<void> _bringWindowToForeground() async {
    if (kIsWeb || Platform.environment.containsKey('FLUTTER_TEST')) return;
    try {
      final isVisible = await windowManager.isVisible();
      if (!isVisible) {
        await windowManager.show();
      }
      await windowManager.restore();
      await windowManager.focus();
    } catch (_) {}
  }

  @override
  void onTrayIconMouseDown() async {
    try {
      await _bringWindowToForeground();
    } catch (_) {}
  }

  @override
  void onTrayIconRightMouseDown() async {
    try {
      await trayManager.popUpContextMenu();
    } catch (_) {}
  }

  @override
  void onTrayMenuItemClick(MenuItem menuItem) async {
    if (menuItem.key == 'show_window') {
      try {
        await _bringWindowToForeground();
      } catch (_) {}
    } else if (menuItem.key == 'update_app') {
      try {
        await _bringWindowToForeground();
        final releaseUrl = _updateService.latestResult?.releaseUrl;
        if (releaseUrl != null && releaseUrl.startsWith('https://')) {
          await launchUrl(Uri.parse(releaseUrl), mode: LaunchMode.externalApplication);
        }
      } catch (_) {}
    } else if (menuItem.key == 'quit_app') {
      try {
        await windowManager.setPreventClose(false);
        await trayManager.destroy();
        await windowManager.destroy();
      } catch (_) {}
      exit(0);
    }
  }

  @override
  void onWindowClose() async {
    final navContext = appNavigatorKey.currentContext;
    if (navContext != null) {
      CloseConfirmationDialog.show(navContext);
    } else {
      try {
        await windowManager.setPreventClose(false);
        await trayManager.destroy();
        await windowManager.destroy();
      } catch (_) {}
      exit(0);
    }
  }

  @override
  void dispose() {
    if (!kIsWeb &&
        defaultTargetPlatform == TargetPlatform.windows &&
        !Platform.environment.containsKey('FLUTTER_TEST')) {
      windowManager.removeListener(this);
      trayManager.removeListener(this);
      _partnerSupervisor.stop();
      _updateService.stopPeriodicChecks();
    }
    _detectionService.removeListener(_onDeviceChanged);
    _engine.removeListener(_onEngineChanged);
    _updateService.removeListener(_onUpdateStateChanged);
    _prerequisiteService.dispose();
    _detectionService.dispose();
    _engine.dispose();
    _setupCoordinator.dispose();
    _itunesManager.dispose();
    _iremoveManager.dispose();
    _authService.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: AppConfig(),
      builder: (context, _) {
        final isDark = AppConfig().isDarkMode;
        AppColors.isDark = isDark;

        return MaterialApp(
          navigatorKey: appNavigatorKey,
          title: '414Unlock - iPhone Device Utility',
          debugShowCheckedModeBanner: false,
          theme: AppTheme.getTheme(AppBrandVariant.iphone, darkMode: isDark),
          builder: (context, child) {
            return Container(
              decoration: BoxDecoration(
                color: AppColors.background,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color: isDark
                      ? Colors.white.withValues(alpha: 0.16)
                      : const Color(0x1F000000),
                  width: 1,
                ),
                boxShadow: [
                  BoxShadow(
                    color: isDark
                        ? Colors.black.withValues(alpha: 0.7)
                        : const Color(0x1A0F172A),
                    blurRadius: 36,
                    offset: const Offset(0, 14),
                  ),
                ],
              ),
              clipBehavior: Clip.antiAlias,
              child: child,
            );
          },
          home: Scaffold(
            backgroundColor: Colors.transparent,
            body: Container(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: isDark
                      ? [const Color(0xFF161A22), const Color(0xFF10131A)]
                      : [const Color(0xFFF7F9FD), const Color(0xFFEEF2F8)],
                ),
              ),
              child: Stack(
                children: [
                  Column(
                    children: [
                      CustomTitleBar(
                        onCloseRequested: () {
                          final navContext =
                              appNavigatorKey.currentContext ?? context;
                          CloseConfirmationDialog.show(navContext);
                        },
                      ),
                      // Non-blocking optional update banner
                      if (_updateService.shouldShowOptionalPrompt)
                        UpdateBanner(
                          update: _updateService.latestResult!,
                          onDismiss: () => setState(() {}),
                        ),
                      Expanded(
                        child: MainFlowShell(
                          title: '414Unlock',
                          subtitle: 'iPhone Device Utility',
                          variant: AppBrandVariant.iphone,
                          prerequisiteService: _prerequisiteService,
                          detectionService: _detectionService,
                          engine: _engine,
                          setupCoordinator: _setupCoordinator,
                          authService: _authService,
                        ),
                      ),
                    ],
                  ),
                  // Blocking mandatory update modal overlay
                  if (_updateService.shouldShowMandatoryScreen)
                    Positioned.fill(
                      child: MandatoryUpdateView(
                        update: _updateService.latestResult!,
                        authService: _authService,
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
