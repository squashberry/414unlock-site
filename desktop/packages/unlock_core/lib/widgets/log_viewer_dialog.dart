import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import '../core/logging/app_logger.dart';
import '../theme/app_theme.dart';
import 'app_button.dart';

class LogViewerDialog extends StatefulWidget {
  final AppBrandVariant variant;

  const LogViewerDialog({
    super.key,
    required this.variant,
  });

  @override
  State<LogViewerDialog> createState() => _LogViewerDialogState();
}

class _LogViewerDialogState extends State<LogViewerDialog> {
  final ScrollController _scrollController = ScrollController();
  LogLevel? _filterLevel;
  String _searchQuery = '';
  String? _statusNotification;

  @override
  Widget build(BuildContext context) {
    final accentColor = widget.variant == AppBrandVariant.iphone
        ? AppColors.iphoneBlue
        : AppColors.androidGreen;

    final allEntries = AppLogger().entries;
    final filtered = allEntries.where((e) {
      if (_filterLevel != null && e.level != _filterLevel) return false;
      if (_searchQuery.isNotEmpty &&
          !e.message.toLowerCase().contains(_searchQuery.toLowerCase()) &&
          !(e.details?.toLowerCase().contains(_searchQuery.toLowerCase()) ?? false)) {
        return false;
      }
      return true;
    }).toList();

    return Dialog(
      backgroundColor: AppColors.cardElevated,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: AppColors.cardBorder, width: 1),
      ),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 820, maxHeight: 620),
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
                      Icons.terminal_rounded,
                      color: accentColor,
                      size: 20,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Text(
                    'Diagnostics & Event Log',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w700,
                      color: AppColors.textPrimary,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                    decoration: BoxDecoration(
                      color: AppColors.card,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: AppColors.cardBorder),
                    ),
                    child: Text(
                      '${filtered.length} events',
                      style: TextStyle(
                        fontSize: 11,
                        color: AppColors.textSecondary,
                        fontWeight: FontWeight.w500,
                      ),
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

              // Filter & Search Toolbar
              Row(
                children: [
                  // Search box
                  Expanded(
                    child: Container(
                      height: 36,
                      decoration: BoxDecoration(
                        color: AppColors.card,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: AppColors.cardBorder),
                      ),
                      child: TextField(
                        style: TextStyle(fontSize: 13, color: AppColors.textPrimary),
                        decoration: InputDecoration(
                          hintText: 'Filter log messages...',
                          hintStyle: TextStyle(fontSize: 12, color: AppColors.textMuted),
                          prefixIcon: Icon(Icons.search, size: 16, color: AppColors.textMuted),
                          border: InputBorder.none,
                          contentPadding: EdgeInsets.symmetric(vertical: 8),
                        ),
                        onChanged: (val) => setState(() => _searchQuery = val),
                      ),
                    ),
                  ),

                  const SizedBox(width: 10),

                  // Level dropdown filter
                  Container(
                    height: 36,
                    padding: const EdgeInsets.symmetric(horizontal: 10),
                    decoration: BoxDecoration(
                      color: AppColors.card,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: AppColors.cardBorder),
                    ),
                    child: DropdownButtonHideUnderline(
                      child: DropdownButton<LogLevel?>(
                        value: _filterLevel,
                        dropdownColor: AppColors.cardElevated,
                        style: TextStyle(fontSize: 12, color: AppColors.textPrimary),
                        items: [
                          const DropdownMenuItem(
                            value: null,
                            child: Text('All Levels'),
                          ),
                          ...LogLevel.values.map(
                            (lvl) => DropdownMenuItem(
                              value: lvl,
                              child: Text(lvl.name.toUpperCase()),
                            ),
                          ),
                        ],
                        onChanged: (lvl) => setState(() => _filterLevel = lvl),
                      ),
                    ),
                  ),
                ],
              ),

              const SizedBox(height: 12),

              if (_statusNotification != null)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    decoration: BoxDecoration(
                      color: AppColors.success.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(color: AppColors.success.withValues(alpha: 0.3)),
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.check_circle_outline, size: 14, color: AppColors.success),
                        const SizedBox(width: 8),
                        Text(
                          _statusNotification!,
                          style: const TextStyle(fontSize: 12, color: AppColors.success),
                        ),
                      ],
                    ),
                  ),
                ),

              // Console Log Viewer
              Expanded(
                child: Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: AppColors.background,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: AppColors.cardBorder),
                  ),
                  child: filtered.isEmpty
                      ? Center(
                          child: Text(
                            'No logs recorded yet',
                            style: TextStyle(fontSize: 13, color: AppColors.textMuted),
                          ),
                        )
                      : ListView.builder(
                          controller: _scrollController,
                          itemCount: filtered.length,
                          itemBuilder: (context, index) {
                            final entry = filtered[index];
                            final color = _getColorForLevel(entry.level);

                            return Padding(
                              padding: const EdgeInsets.symmetric(vertical: 2.5),
                              child: Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    entry.formattedTime,
                                    style: TextStyle(
                                      fontFamily: 'Consolas',
                                      fontSize: 12,
                                      color: AppColors.textMuted,
                                    ),
                                  ),
                                  const SizedBox(width: 10),
                                  Container(
                                    width: 72,
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 4, vertical: 1),
                                    decoration: BoxDecoration(
                                      color: color.withValues(alpha: 0.12),
                                      borderRadius: BorderRadius.circular(4),
                                    ),
                                    alignment: Alignment.center,
                                    child: Text(
                                      entry.level.name.toUpperCase(),
                                      style: TextStyle(
                                        fontFamily: 'Consolas',
                                        fontSize: 10,
                                        fontWeight: FontWeight.w600,
                                        color: color,
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 10),
                                  Expanded(
                                    child: Text.rich(
                                      TextSpan(
                                        text: entry.message,
                                        style: TextStyle(
                                          fontFamily: 'Consolas',
                                          fontSize: 12,
                                          color: AppColors.textPrimary,
                                        ),
                                        children: [
                                          if (entry.details != null)
                                            TextSpan(
                                              text: '  —  ${entry.details}',
                                              style: TextStyle(
                                                fontFamily: 'Consolas',
                                                fontSize: 11,
                                                color: AppColors.textSecondary,
                                              ),
                                            ),
                                        ],
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            );
                          },
                        ),
                ),
              ),

              const SizedBox(height: 16),

              // Bottom Actions
              Row(
                children: [
                  AppButton(
                    text: 'Copy Summary',
                    icon: Icons.copy_rounded,
                    variant: AppButtonVariant.secondary,
                    height: 36,
                    onPressed: () {
                      final summary = AppLogger().exportDiagnostics();
                      Clipboard.setData(ClipboardData(text: summary));
                      _showStatus('Copied diagnostics to clipboard');
                    },
                  ),
                  const SizedBox(width: 8),
                  AppButton(
                    text: 'Export Logs',
                    icon: Icons.download_rounded,
                    variant: AppButtonVariant.secondary,
                    height: 36,
                    onPressed: () async {
                      try {
                        final dir = await getApplicationDocumentsDirectory();
                        final file = File(
                          '${dir.path}\\414Unlock_Diagnostics_${DateTime.now().millisecondsSinceEpoch}.log',
                        );
                        await file.writeAsString(AppLogger().exportDiagnostics());
                        _showStatus('Exported to: ${file.path}');
                      } catch (e) {
                        _showStatus('Export failed: $e');
                      }
                    },
                  ),
                  const Spacer(),
                  AppButton(
                    text: 'Close',
                    variant: AppButtonVariant.primary,
                    height: 36,
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showStatus(String msg) {
    setState(() => _statusNotification = msg);
    Future.delayed(const Duration(seconds: 4), () {
      if (mounted) setState(() => _statusNotification = null);
    });
  }

  Color _getColorForLevel(LogLevel level) {
    switch (level) {
      case LogLevel.info:
        return AppColors.textSecondary;
      case LogLevel.warning:
        return AppColors.warning;
      case LogLevel.error:
        return AppColors.error;
      case LogLevel.hardware:
        return AppColors.info;
      case LogLevel.engine:
        return widget.variant == AppBrandVariant.iphone
            ? AppColors.iphoneBlue
            : AppColors.androidGreen;
    }
  }
}