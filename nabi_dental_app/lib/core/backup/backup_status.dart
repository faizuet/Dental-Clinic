const backupReminderDays = 7;

class BackupStatus {
  const BackupStatus({this.lastBackupAt});

  final DateTime? lastBackupAt;

  bool get isOverdue {
    final last = lastBackupAt;
    if (last == null) {
      return true;
    }
    return DateTime.now().toUtc().difference(last.toUtc()).inDays >= backupReminderDays;
  }

  String get subtitle {
    final last = lastBackupAt;
    if (last == null) {
      return 'No backup saved on this computer yet';
    }
    final days = DateTime.now().toUtc().difference(last.toUtc()).inDays;
    if (days <= 0) {
      return 'Last backup was today';
    }
    if (days == 1) {
      return 'Last backup was yesterday';
    }
    if (days >= backupReminderDays) {
      return 'Last backup was $days days ago — save a new copy';
    }
    return 'Last backup was $days days ago';
  }
}
