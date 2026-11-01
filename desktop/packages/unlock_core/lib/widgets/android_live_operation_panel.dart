import 'package:flutter/material.dart';
import '../core/device/android_device_state.dart';
import '../core/engine/engine_event.dart';
import '../theme/app_theme.dart';
import 'app_button.dart';

class AndroidLiveOperationPanel extends StatelessWidget {
  final RecoveryAction action;
  final String? progressMessage;
  final List<EngineEvent> events;
  final VoidCallback onCancel;

  const AndroidLiveOperationPanel({
    super.key,
    required this.action,
    this.progressMessage,
    required this.events,
    required this.onCancel,
  });

  @override
  Widget build(BuildContext context) {
    const accentGreen = AppColors.androidGreen;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: accentGreen.withValues(alpha: 0.4), width: 1.2),
        boxShadow: [
          BoxShadow(
            color: accentGreen.withValues(alpha: 0.08),
            blurRadius: 16,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Operation Header
          Row(
            children: [
              SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(
                  strokeWidth: 2.2,
                  valueColor: const AlwaysStoppedAnimation<Color>(accentGreen),
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      action.name,
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                        color: AppColors.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      progressMessage ?? 'Executing operation...',
                      style: TextStyle(
                        fontSize: 12,
                        color: AppColors.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
              AppButton(
                text: 'Cancel',
                variant: AppButtonVariant.danger,
                height: 32,
                onPressed: onCancel,
              ),
            ],
          ),

          const SizedBox(height: 14),

          // Real-time Indeterminate Progress Bar (No fake progression)
          ClipRRect(
            borderRadius: BorderRadius.all(Radius.circular(4)),
            child: LinearProgressIndicator(
              minHeight: 4,
              backgroundColor: AppColors.cardElevated,
              valueColor: AlwaysStoppedAnimation<Color>(accentGreen),
            ),
          ),

          const SizedBox(height: 16),
          Divider(color: AppColors.cardBorder, height: 1),
          const SizedBox(height: 12),

          // Live Activity
          Row(
            children: [
              Icon(Icons.monitor_heart_outlined,
                  size: 14, color: AppColors.textSecondary),
              SizedBox(width: 8),
              Text(
                'LIVE ACTIVITY',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.8,
                  color: AppColors.textSecondary,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),

          Container(
            height: 110,
            width: double.infinity,
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: AppColors.background,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: AppColors.cardBorder),
            ),
            child: events.isEmpty
                ? Center(
                    child: Text(
                      'Waiting for backend output...',
                      style: TextStyle(fontSize: 12, color: AppColors.textMuted),
                    ),
                  )
                : ListView.builder(
                    reverse: true,
                    itemCount: events.length,
                    itemBuilder: (context, index) {
                      final event = events[events.length - 1 - index];
                      return Padding(
                        padding: const EdgeInsets.symmetric(vertical: 2),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              event.formattedTime,
                              style: TextStyle(
                                fontFamily: 'Consolas',
                                fontSize: 11,
                                color: AppColors.textMuted,
                              ),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                event.message,
                                style: TextStyle(
                                  fontFamily: 'Consolas',
                                  fontSize: 11,
                                  color: event.type == EngineEventType.warning
                                      ? AppColors.warning
                                      : event.type == EngineEventType.operationCompleted
                                          ? AppColors.success
                                          : AppColors.textPrimary,
                                ),
                              ),
                            ),
                          ],
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}