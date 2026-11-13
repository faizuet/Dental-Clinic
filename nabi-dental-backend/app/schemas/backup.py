from datetime import datetime

from app.utils.pagination import APIModel


class BackupStatusRead(APIModel):
    last_export_at: datetime | None = None
    reminder_after_days: int
    format_version: int
    pg_dump_available: bool


class BackupRestoreRead(APIModel):
    restored: bool
    restored_at: datetime
    format_version: int
