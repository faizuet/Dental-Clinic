import 'package:flutter_test/flutter_test.dart';
import 'package:nabi_dental_app/core/backup/backup_status.dart';

void main() {
  test('backup is overdue when none has been saved', () {
    const status = BackupStatus();
    expect(status.isOverdue, isTrue);
    expect(status.subtitle, 'No backup saved on this computer yet');
  });

  test('backup is current when saved today', () {
    final status = BackupStatus(lastBackupAt: DateTime.now().toUtc());
    expect(status.isOverdue, isFalse);
    expect(status.subtitle, 'Last backup was today');
  });

  test('backup is overdue after the reminder window', () {
    final status = BackupStatus(
      lastBackupAt: DateTime.now().toUtc().subtract(const Duration(days: 8)),
    );
    expect(status.isOverdue, isTrue);
    expect(status.subtitle, contains('8 days ago'));
  });
}
