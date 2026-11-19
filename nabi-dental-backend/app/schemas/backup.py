from datetime import datetime

from app.utils.pagination import APIModel


class BackupCopyRead(APIModel):
    filename: str
    created_at: datetime
    bytes: int


class BackupStatusRead(APIModel):
    last_export_at: datetime | None = None
    last_error: str | None = None
    last_error_at: datetime | None = None
    reminder_after_days: int
    format_version: int
    pg_dump_available: bool
    retention_count: int = 14
    backups: list[BackupCopyRead] = []


class BackupRestoreRead(APIModel):
    restored: bool
    restored_at: datetime
    format_version: int
    safety_backup: str | None = None
    verified: bool = True
    verification: str | None = None
