const backupReminderDays = 7;

class ClinicBackupCopy {
  const ClinicBackupCopy({required this.filename, required this.createdAt, required this.bytes});

  final String filename;
  final DateTime createdAt;
  final int bytes;

  factory ClinicBackupCopy.fromJson(Map<String, dynamic> json) {
    return ClinicBackupCopy(
      filename: json['filename']?.toString() ?? '',
      createdAt: DateTime.tryParse(json['created_at']?.toString() ?? '')?.toLocal() ?? DateTime.now(),
      bytes: json['bytes'] is int ? json['bytes'] as int : int.tryParse('${json['bytes']}') ?? 0,
    );
  }
}

class BackupStatus {
  const BackupStatus({this.lastBackupAt, this.lastError, this.backups = const []});

  final DateTime? lastBackupAt;
  final String? lastError;
  final List<ClinicBackupCopy> backups;

  factory BackupStatus.fromJson(Map<String, dynamic> json) {
    final rawBackups = json['backups'];
    final error = json['last_error']?.toString().trim();
    return BackupStatus(
      lastBackupAt: DateTime.tryParse(json['last_export_at']?.toString() ?? ''),
      lastError: error == null || error.isEmpty ? null : error,
      backups: [
        for (final item in rawBackups is List ? rawBackups : const [])
          if (item is Map) ClinicBackupCopy.fromJson(Map<String, dynamic>.from(item)),
      ],
    );
  }

  bool get isOverdue {
    final last = lastBackupAt;
    if (last == null) {
      return true;
    }
    return DateTime.now().toUtc().difference(last.toUtc()).inDays >= backupReminderDays;
  }

  String get subtitle {
    if (lastError != null) {
      return 'Last automatic backup failed. $lastError';
    }
    final last = lastBackupAt;
    if (last == null) {
      return 'No backup saved on this computer yet';
    }
    final days = DateTime.now().toUtc().difference(last.toUtc()).inDays;
    if (days <= 0) {
      return 'Latest backup was today. Daily copies stay on this computer.';
    }
    if (days == 1) {
      return 'Latest backup was yesterday. Daily copies stay on this computer.';
    }
    if (days >= backupReminderDays) {
      return 'Latest backup was $days days ago. Save a new copy.';
    }
    return 'Latest backup was $days days ago. Daily copies stay on this computer.';
  }
}
