import 'dart:async';
import 'package:flutter/foundation.dart';
import 'prerequisite.dart';
import '../logging/app_logger.dart';

class PrerequisiteService extends ChangeNotifier {
  final List<Prerequisite> prerequisites;
  bool _isChecking = false;

  PrerequisiteService({required this.prerequisites}) {
    for (final p in prerequisites) {
      p.addListener(notifyListeners);
    }
  }

  bool get isChecking => _isChecking;

  bool get allPassed =>
      prerequisites.isNotEmpty &&
      prerequisites.every((p) => p.status == PrerequisiteStatus.installed);

  bool get hasMissing =>
      prerequisites.any((p) => p.status == PrerequisiteStatus.missing);

  int get installedCount =>
      prerequisites.where((p) => p.status == PrerequisiteStatus.installed).length;

  Future<void> checkAll() async {
    _isChecking = true;
    notifyListeners();
    AppLogger().info('Checking prerequisites (${prerequisites.length} items)');

    for (final p in prerequisites) {
      await p.check();
    }

    _isChecking = false;
    notifyListeners();
    AppLogger().info(
      'Prerequisites check complete: $installedCount/${prerequisites.length} passed',
    );
  }

  Future<void> recheck(String id) async {
    final prereq = prerequisites.firstWhere((p) => p.id == id);
    AppLogger().info('Rechecking prerequisite: ${prereq.displayName}');
    await prereq.check();
    notifyListeners();
  }

  Future<void> recheckAll() async {
    await checkAll();
  }

  @override
  void dispose() {
    for (final p in prerequisites) {
      p.removeListener(notifyListeners);
    }
    super.dispose();
  }
}
