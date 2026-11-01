import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:url_launcher/url_launcher.dart';
import '../core/config/app_config.dart';
import '../core/logging/app_logger.dart';
import '../core/update/app_update_service.dart';
import '../theme/app_theme.dart';
import 'app_button.dart';

class SettingsDialog extends StatefulWidget {
  final AppBrandVariant variant;

  const SettingsDialog({
    super.key,
    required this.variant,
  });

  @override
  State<SettingsDialog> createState() => _SettingsDialogState();
}

class _SettingsDialogState extends State<SettingsDialog>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  final _exeController = TextEditingController();
  final _urlController = TextEditingController();

  String? _testConnectionStatus;
  bool _isTesting = false;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    final config = AppConfig();
    _exeController.text = config.partnerExecutablePath;
    _urlController.text = config.partnerUrl;
  }

  @override
  void dispose() {
    _tabController.dispose();
    _exeController.dispose();
    _urlController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final config = AppConfig();
    final accentColor = widget.variant == AppBrandVariant.iphone
        ? AppColors.iphoneBlue
        : AppColors.androidGreen;

    return Dialog(
      backgroundColor: AppColors.cardElevated,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: AppColors.cardBorder, width: 1),
      ),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 620, maxHeight: 520),
        child: Padding(
          padding: const EdgeInsets.all(22),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: accentColor.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Icon(
                      Icons.settings_outlined,
                      color: accentColor,
                      size: 20,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Text(
                    'Settings',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w700,
                      color: AppColors.textPrimary,
                    ),
                  ),
                  const Spacer(),
                  IconButton(
                    icon: Icon(Icons.close_rounded,
                        size: 20, color: AppColors.textSecondary),
                    splashRadius: 18,
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ],
              ),

              const SizedBox(height: 14),

              // Tab Bar
              Container(
                decoration: BoxDecoration(
                  border: Border(
                    bottom: BorderSide(color: AppColors.cardBorder, width: 1),
                  ),
                ),
                child: TabBar(
                  controller: _tabController,
                  indicatorColor: accentColor,
                  labelColor: accentColor,
                  unselectedLabelColor: AppColors.textSecondary,
                  labelStyle: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                  tabs: const [
                    Tab(text: 'General'),
                    Tab(text: 'Partner Tool'),
                    Tab(text: 'Diagnostics'),
                  ],
                ),
              ),

              const SizedBox(height: 16),

              // Tab Views
              Expanded(
                child: TabBarView(
                  controller: _tabController,
                  children: [
                    // 1. General Tab
                    _buildGeneralTab(config, accentColor),

                    // 2. Partner Tool Tab
                    _buildPartnerTab(config, accentColor),

                    // 3. Diagnostics Tab
                    _buildDiagnosticsTab(accentColor),
                  ],
                ),
              ),

              const SizedBox(height: 14),

              // Footer
              Align(
                alignment: Alignment.centerRight,
                child: AppButton(
                  text: 'Save & Close',
                  variant: AppButtonVariant.primary,
                  onPressed: () async {
                    final navigator = Navigator.of(context);
                    await config.setPartnerExecutablePath(_exeController.text);
                    await config.setPartnerUrl(_urlController.text);
                    if (mounted) navigator.pop();
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildGeneralTab(AppConfig config, Color accentColor) {
    return ListenableBuilder(
      listenable: config,
      builder: (context, _) {
        return ListView(
          children: [
            // Theme Mode Selector
            Padding(
              padding: const EdgeInsets.only(bottom: 14),
              child: Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: AppColors.background,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: AppColors.cardBorder),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(Icons.palette_outlined, size: 16, color: accentColor),
                        const SizedBox(width: 8),
                        Text(
                          'Appearance Theme',
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            color: AppColors.textPrimary,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 3),
                    Text(
                      'Select clean white or dark theme for the macOS / iOS UI.',
                      style: TextStyle(fontSize: 11, color: AppColors.textSecondary),
                    ),
                    const SizedBox(height: 10),
                    Row(
                      children: [
                        Expanded(
                          child: InkWell(
                            onTap: () {
                              config.setThemeMode('light');
                              AppColors.isDark = false;
                            },
                            borderRadius: BorderRadius.circular(8),
                            child: Container(
                              padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 10),
                              decoration: BoxDecoration(
                                color: !config.isDarkMode
                                    ? accentColor.withValues(alpha: 0.12)
                                    : AppColors.card,
                                borderRadius: BorderRadius.circular(8),
                                border: Border.all(
                                  color: !config.isDarkMode
                                      ? accentColor
                                      : AppColors.cardBorder,
                                  width: !config.isDarkMode ? 1.5 : 1,
                                ),
                              ),
                              child: Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Icon(
                                    Icons.light_mode_rounded,
                                    size: 15,
                                    color: !config.isDarkMode ? accentColor : AppColors.textSecondary,
                                  ),
                                  const SizedBox(width: 6),
                                  Text(
                                    'Clean White (Default)',
                                    style: TextStyle(
                                      fontSize: 11.5,
                                      fontWeight: FontWeight.w600,
                                      color: !config.isDarkMode ? accentColor : AppColors.textPrimary,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: InkWell(
                            onTap: () {
                              config.setThemeMode('dark');
                              AppColors.isDark = true;
                            },
                            borderRadius: BorderRadius.circular(8),
                            child: Container(
                              padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 10),
                              decoration: BoxDecoration(
                                color: config.isDarkMode
                                    ? accentColor.withValues(alpha: 0.12)
                                    : AppColors.card,
                                borderRadius: BorderRadius.circular(8),
                                border: Border.all(
                                  color: config.isDarkMode
                                      ? accentColor
                                      : AppColors.cardBorder,
                                  width: config.isDarkMode ? 1.5 : 1,
                                ),
                              ),
                              child: Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Icon(
                                    Icons.dark_mode_rounded,
                                    size: 15,
                                    color: config.isDarkMode ? accentColor : AppColors.textSecondary,
                                  ),
                                  const SizedBox(width: 6),
                                  Text(
                                    'Dark Glass',
                                    style: TextStyle(
                                      fontSize: 11.5,
                                      fontWeight: FontWeight.w600,
                                      color: config.isDarkMode ? accentColor : AppColors.textPrimary,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
            _buildSwitchTile(
              title: 'Start with Windows',
              subtitle: 'Automatically launch 414Unlock when signing in to Windows',
              value: config.startWithWindows,
              accentColor: accentColor,
              onChanged: (val) => config.setStartWithWindows(val),
            ),
            _buildSwitchTile(
              title: 'Minimize to system tray',
              subtitle: 'Keep running in the background when the window is closed',
              value: config.minimizeToTray,
              accentColor: accentColor,
              onChanged: (val) => config.setMinimizeToTray(val),
            ),
            _buildSwitchTile(
              title: 'Automatically check prerequisites',
              subtitle: 'Inspect system dependencies on application startup',
              value: config.autoCheckPrerequisites,
              accentColor: accentColor,
              onChanged: (val) => config.setAutoCheckPrerequisites(val),
            ),
            _buildSwitchTile(
              title: 'Automatically detect USB devices',
              subtitle: 'Continuously listen for device connections and disconnections',
              value: config.autoDetectUsb,
              accentColor: accentColor,
              onChanged: (val) => config.setAutoDetectUsb(val),
            ),
            const SizedBox(height: 12),
            _buildUpdateTile(accentColor),
          ],
        );
      },
    );
  }

  Widget _buildUpdateTile(Color accentColor) {
    return ListenableBuilder(
      listenable: AppUpdateService(),
      builder: (context, _) {
        final updateService = AppUpdateService();
        final latest = updateService.latestResult;
        final isChecking = updateService.isChecking;

        String statusText;
        Color statusColor;

        if (isChecking) {
          statusText = 'Checking for updates...';
          statusColor = accentColor;
        } else if (latest != null && latest.updateAvailable) {
          statusText = 'Update available: v${latest.latestVersion}';
          statusColor = AppColors.warning;
        } else if (latest != null) {
          statusText = 'Up to date (Version ${AppUpdateService.currentAppVersion})';
          statusColor = AppColors.success;
        } else {
          statusText = 'Version ${AppUpdateService.currentAppVersion}';
          statusColor = AppColors.textSecondary;
        }

        return Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: AppColors.background,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: AppColors.cardBorder),
          ),
          child: Row(
            children: [
              Container(
                width: 32,
                height: 32,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: accentColor.withValues(alpha: 0.12),
                ),
                child: Icon(
                  Icons.system_update_rounded,
                  size: 16,
                  color: accentColor,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '414Unlock Updates',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: AppColors.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      statusText,
                      style: TextStyle(
                        fontSize: 11.5,
                        color: statusColor,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              if (latest != null && latest.updateAvailable)
                AppButton(
                  text: 'Update now',
                  height: 32,
                  onPressed: () {
                    final url = latest.releaseUrl;
                    if (url.startsWith('https://')) {
                      launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
                    }
                  },
                )
              else
                AppButton(
                  text: 'Check',
                  variant: AppButtonVariant.secondary,
                  height: 32,
                  isLoading: isChecking,
                  onPressed: () => updateService.checkForUpdates(),
                ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildPartnerTab(AppConfig config, Color accentColor) {
    return ListView(
      children: [
        Text(
          'Configure the external authorized partner utility for specialized operations. 414Unlock will prepare connection parameters and hand off execution.',
          style: TextStyle(
            fontSize: 12,
            color: AppColors.textSecondary,
            height: 1.4,
          ),
        ),
        const SizedBox(height: 16),

        // Partner Executable Path
        Text(
          'Partner Executable Path',
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: AppColors.textPrimary,
          ),
        ),
        const SizedBox(height: 6),
        Container(
          decoration: BoxDecoration(
            color: AppColors.card,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: AppColors.cardBorder),
          ),
          child: TextField(
            controller: _exeController,
            style: TextStyle(fontSize: 13, color: AppColors.textPrimary),
            decoration: InputDecoration(
              hintText: r'C:\Program Files\PartnerUtility\Partner.exe',
              hintStyle: TextStyle(fontSize: 12, color: AppColors.textMuted),
              border: InputBorder.none,
              contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            ),
          ),
        ),

        const SizedBox(height: 16),

        // Partner URL
        Text(
          'Partner URL (Fallback / Web Console)',
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: AppColors.textPrimary,
          ),
        ),
        const SizedBox(height: 6),
        Container(
          decoration: BoxDecoration(
            color: AppColors.card,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: AppColors.cardBorder),
          ),
          child: TextField(
            controller: _urlController,
            style: TextStyle(fontSize: 13, color: AppColors.textPrimary),
            decoration: InputDecoration(
              hintText: 'https://partner.example.com',
              hintStyle: TextStyle(fontSize: 12, color: AppColors.textMuted),
              border: InputBorder.none,
              contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            ),
          ),
        ),

        const SizedBox(height: 16),

        // Test Connection Button
        Row(
          children: [
            AppButton(
              text: 'Test Connection',
              icon: Icons.electrical_services_rounded,
              variant: AppButtonVariant.secondary,
              height: 36,
              isLoading: _isTesting,
              onPressed: _testPartnerConnection,
            ),
            const SizedBox(width: 12),
            if (_testConnectionStatus != null)
              Expanded(
                child: Text(
                  _testConnectionStatus!,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                    color: _testConnectionStatus!.contains('Valid') ||
                            _testConnectionStatus!.contains('Reachable')
                        ? AppColors.success
                        : AppColors.warning,
                  ),
                ),
              ),
          ],
        ),
      ],
    );
  }

  Future<void> _testPartnerConnection() async {
    setState(() {
      _isTesting = true;
      _testConnectionStatus = null;
    });

    final exe = _exeController.text.trim();
    final url = _urlController.text.trim();

    await Future.delayed(const Duration(milliseconds: 600));

    if (exe.isNotEmpty) {
      final file = File(exe);
      if (file.existsSync()) {
        setState(() {
          _isTesting = false;
          _testConnectionStatus = 'Valid executable found at path.';
        });
        return;
      } else {
        setState(() {
          _isTesting = false;
          _testConnectionStatus = 'Executable path does not exist on disk.';
        });
        return;
      }
    }

    if (url.isNotEmpty) {
      try {
        final uri = Uri.parse(url);
        final canLaunch = await canLaunchUrl(uri);
        setState(() {
          _isTesting = false;
          _testConnectionStatus = canLaunch ? 'Partner URL reachable.' : 'Invalid URL scheme.';
        });
      } catch (_) {
        setState(() {
          _isTesting = false;
          _testConnectionStatus = 'Unable to parse URL.';
        });
      }
      return;
    }

    setState(() {
      _isTesting = false;
      _testConnectionStatus = 'No partner executable or URL configured.';
    });
  }

  Widget _buildDiagnosticsTab(Color accentColor) {
    return ListView(
      children: [
        Text(
          'Troubleshoot application behavior, view raw telemetry, or export diagnostics for customer support.',
          style: TextStyle(
            fontSize: 12,
            color: AppColors.textSecondary,
            height: 1.4,
          ),
        ),
        const SizedBox(height: 16),

        _buildActionTile(
          icon: Icons.folder_open_rounded,
          title: 'Open Logs Folder',
          description: 'Explore diagnostic logs stored in your local application directory',
          onTap: () async {
            try {
              final dir = await getApplicationDocumentsDirectory();
              await Process.run('explorer.exe', [dir.path]);
            } catch (_) {}
          },
        ),

        const SizedBox(height: 10),

        _buildActionTile(
          icon: Icons.copy_rounded,
          title: 'Copy Diagnostic Summary',
          description: 'Copy sanitized timestamped log data to your clipboard',
          onTap: () {
            Clipboard.setData(ClipboardData(text: AppLogger().exportDiagnostics()));
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('Copied diagnostics to clipboard'),
                duration: Duration(seconds: 2),
              ),
            );
          },
        ),

        const SizedBox(height: 10),

        _buildActionTile(
          icon: Icons.delete_outline_rounded,
          title: 'Clear Session Logs',
          description: 'Reset internal log memory for this active session',
          onTap: () {
            AppLogger().clear();
            setState(() {});
          },
        ),
      ],
    );
  }

  Widget _buildSwitchTile({
    required String title,
    required String subtitle,
    required bool value,
    required Color accentColor,
    required ValueChanged<bool> onChanged,
  }) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppColors.cardBorder),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: AppColors.textPrimary,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  subtitle,
                  style: TextStyle(
                    fontSize: 11,
                    color: AppColors.textSecondary,
                  ),
                ),
              ],
            ),
          ),
          Switch(
            value: value,
            activeThumbColor: accentColor,
            onChanged: onChanged,
          ),
        ],
      ),
    );
  }

  Widget _buildActionTile({
    required IconData icon,
    required String title,
    required String description,
    required VoidCallback onTap,
  }) {
    return Material(
      color: AppColors.card,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8),
        side: BorderSide(color: AppColors.cardBorder),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          child: Row(
            children: [
              Icon(icon, size: 20, color: AppColors.textPrimary),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: AppColors.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      description,
                      style: TextStyle(
                        fontSize: 11,
                        color: AppColors.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
              Icon(Icons.chevron_right, size: 18, color: AppColors.textMuted),
            ],
          ),
        ),
      ),
    );
  }
}