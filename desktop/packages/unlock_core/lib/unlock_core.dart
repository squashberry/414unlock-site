// Config
export 'core/config/app_config.dart';

// Logging
export 'core/logging/app_logger.dart';

// Prerequisites
export 'core/prerequisites/prerequisite.dart';
export 'core/prerequisites/prerequisite_service.dart';
export 'core/prerequisites/windows_checker_helper.dart';
export 'core/prerequisites/apple_prerequisites.dart';
export 'core/prerequisites/android_prerequisites.dart';
export 'core/prerequisites/itunes_manager.dart';
export 'core/prerequisites/iremove_manager.dart';
export 'core/prerequisites/setup_coordinator.dart';

// Auth
export 'core/auth/auth_service.dart';

// Device
export 'core/device/device_info.dart';
export 'core/device/device_detection_service.dart';
export 'core/device/apple_device_detection_service.dart';
export 'core/device/apple_usbmux_client.dart';
export 'core/device/apple_device_database.dart';
export 'core/device/external_idevice_tools.dart';
export 'core/device/android_device_detection_service.dart';
export 'core/device/android_platform_tools_manager.dart';
export 'core/device/native_windows_usb.dart';

// Engine
export 'core/engine/repair_engine.dart';
export 'core/engine/external_partner_engine.dart';
export 'core/engine/engine_config.dart';
export 'core/engine/engine_event.dart';
export 'core/engine/engine_output_parser.dart';
export 'core/engine/engine_process_manager.dart';

// Theme
export 'theme/app_theme.dart';

// Widgets
export 'widgets/startup_logo_animation.dart';
export 'widgets/app_header.dart';
export 'widgets/app_button.dart';
export 'widgets/status_chip.dart';
export 'widgets/prerequisite_card.dart';
export 'widgets/device_illustration.dart';
export 'widgets/device_card.dart';
export 'widgets/troubleshoot_dialog.dart';
export 'widgets/settings_dialog.dart';
export 'widgets/log_viewer_dialog.dart';
export 'widgets/android_state_card.dart';
export 'widgets/android_actions_panel.dart';
export 'widgets/android_live_operation_panel.dart';
export 'widgets/android_engine_prompt_dialog.dart';

// Device State Assessment
export 'core/device/android_device_state.dart';
export 'core/device/android_device_state_controller.dart';

// Features / Views
export 'features/setup/setup_view.dart';
export 'features/prerequisites/prerequisites_view.dart';
export 'features/device_connection/device_connection_view.dart';
export 'features/device_connection/android_state_view.dart';
export 'features/handoff/partner_handoff_view.dart';
export 'features/result/result_view.dart';
export 'features/main_flow/main_flow_shell.dart';

// Update & Maintenance
export 'core/update/semantic_version.dart';
export 'core/update/app_update_models.dart';
export 'core/update/app_update_service.dart';
export 'core/services/startup_service.dart';
export 'core/services/partner_supervisor_service.dart';
export 'widgets/update_banner.dart';
export 'features/update/mandatory_update_view.dart';

