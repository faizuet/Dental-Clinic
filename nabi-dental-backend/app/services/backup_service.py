from __future__ import annotations

import json
import os
import shutil
import subprocess
import tempfile
import zipfile
from dataclasses import dataclass
from datetime import datetime, timezone
from pathlib import Path

from sqlalchemy.engine.url import make_url

from app.core.config import settings
from app.core.constants import ErrorCode
from app.core.exceptions import AppError, ValidationAppError

BACKUP_KIND = "nabi-dental-backup"
BACKUP_FORMAT_VERSION = 1
DATABASE_DUMP_NAME = "database.dump"
MANIFEST_NAME = "manifest.json"
LAST_BACKUP_NAME = ".last_backup.json"
UPLOADS_DIR_NAME = "uploads"
REMINDER_AFTER_DAYS = settings.BACKUP_REMINDER_DAYS
PG_TIMEOUT_SECONDS = 180
MAX_BACKUP_BYTES = 1_500_000_000
MAX_UNCOMPRESSED_BYTES = 2_000_000_000


@dataclass(frozen=True)
class BackupArtifact:
    path: Path
    filename: str
    cleanup_dir: Path


class BackupService:
    def __init__(
        self,
        *,
        upload_dir: Path | None = None,
        dump_database=None,
        restore_database=None,
    ) -> None:
        self.upload_dir = Path(upload_dir or settings.UPLOAD_DIR)
        self._use_pg_dump = dump_database is None
        self._use_pg_restore = restore_database is None
        self._dump_database = dump_database or self._pg_dump
        self._restore_database = restore_database or self._pg_restore

    def status(self) -> dict[str, object]:
        last = self._read_last_export()
        return {
            "last_export_at": last.get("created_at") if last else None,
            "reminder_after_days": REMINDER_AFTER_DAYS,
            "format_version": BACKUP_FORMAT_VERSION,
            "pg_dump_available": self.tools_available(),
        }

    def tools_available(self) -> bool:
        return bool(shutil.which("pg_dump") and shutil.which("pg_restore"))

    def create(self) -> BackupArtifact:
        self._require_tools(dump=True)
        stamp = datetime.now(timezone.utc)
        filename = f"nabi-dental-backup-{stamp.strftime('%Y-%m-%d-%H%M')}.zip"
        work = Path(tempfile.mkdtemp(prefix="nabi-backup-"))
        try:
            dump_path = work / DATABASE_DUMP_NAME
            self._dump_database(dump_path)
            if not dump_path.is_file() or dump_path.stat().st_size == 0:
                raise AppError(
                    ErrorCode.INTERNAL_ERROR,
                    "The clinic database backup was empty. Try again.",
                    status_code=500,
                )
            staging_uploads = work / UPLOADS_DIR_NAME
            self._copy_uploads(self.upload_dir, staging_uploads)
            manifest = {
                "kind": BACKUP_KIND,
                "format_version": BACKUP_FORMAT_VERSION,
                "created_at": stamp.isoformat(),
                "app": "Nabi Dental Clinic",
                "includes_uploads": staging_uploads.exists(),
            }
            (work / MANIFEST_NAME).write_text(json.dumps(manifest, indent=2), encoding="utf-8")
            zip_path = work / filename
            with zipfile.ZipFile(zip_path, "w", compression=zipfile.ZIP_DEFLATED) as archive:
                archive.write(work / MANIFEST_NAME, MANIFEST_NAME)
                archive.write(dump_path, DATABASE_DUMP_NAME)
                if staging_uploads.exists():
                    for file_path in staging_uploads.rglob("*"):
                        if file_path.is_file():
                            archive.write(file_path, Path(UPLOADS_DIR_NAME) / file_path.relative_to(staging_uploads))
            self._write_last_export(stamp, filename, zip_path.stat().st_size)
            return BackupArtifact(path=zip_path, filename=filename, cleanup_dir=work)
        except Exception:
            shutil.rmtree(work, ignore_errors=True)
            raise

    def restore(self, archive_path: Path) -> dict[str, object]:
        self._require_tools(restore=True)
        if not archive_path.is_file():
            raise ValidationAppError("Choose a Nabi Dental backup zip file.")
        if archive_path.stat().st_size > MAX_BACKUP_BYTES:
            raise ValidationAppError("This backup file is too large to restore on this laptop.")
        work = Path(tempfile.mkdtemp(prefix="nabi-restore-"))
        try:
            extracted = self._extract_archive(archive_path, work)
            dump_path = extracted / DATABASE_DUMP_NAME
            uploads_source = extracted / UPLOADS_DIR_NAME
            self._restore_database(dump_path)
            self.upload_dir.mkdir(parents=True, exist_ok=True)
            self._replace_uploads(uploads_source, self.upload_dir)
            restored_at = datetime.now(timezone.utc)
            self._write_last_export(restored_at, archive_path.name, archive_path.stat().st_size)
            return {
                "restored": True,
                "restored_at": restored_at.isoformat(),
                "format_version": BACKUP_FORMAT_VERSION,
            }
        finally:
            shutil.rmtree(work, ignore_errors=True)

    def _require_tools(self, *, dump: bool = False, restore: bool = False) -> None:
        need_dump = dump and self._use_pg_dump and not shutil.which("pg_dump")
        need_restore = restore and self._use_pg_restore and not shutil.which("pg_restore")
        if need_dump or need_restore:
            raise AppError(
                ErrorCode.DEPENDENCY_UNAVAILABLE,
                "Backup tools are missing. Rebuild the Docker app image, or install PostgreSQL client tools.",
                status_code=503,
            )

    def _pg_connection(self) -> tuple[list[str], dict[str, str]]:
        url = make_url(settings.DATABASE_URL)
        args = [
            f"--host={url.host or 'localhost'}",
            f"--port={url.port or 5432}",
            f"--username={url.username or 'postgres'}",
            f"--dbname={url.database or 'nabi_dental'}",
        ]
        env = os.environ.copy()
        env["PGPASSWORD"] = url.password or ""
        env["PGCLIENTENCODING"] = "UTF8"
        return args, env

    def _run(self, command: list[str], env: dict[str, str], *, timeout: int) -> None:
        try:
            completed = subprocess.run(
                command,
                env=env,
                check=False,
                capture_output=True,
                timeout=timeout,
            )
        except FileNotFoundError as exc:
            raise AppError(
                ErrorCode.DEPENDENCY_UNAVAILABLE,
                "Backup tools are missing. Rebuild the Docker app image, or install PostgreSQL client tools.",
                status_code=503,
            ) from exc
        except subprocess.TimeoutExpired as exc:
            raise AppError(
                ErrorCode.INTERNAL_ERROR,
                "The clinic backup timed out. Try again.",
                status_code=500,
            ) from exc
        if completed.returncode != 0:
            raise AppError(
                ErrorCode.INTERNAL_ERROR,
                "The clinic could not complete backup or restore. Keep Docker running and try again.",
                status_code=500,
            )

    def _pg_dump(self, dest: Path) -> None:
        args, env = self._pg_connection()
        self._run(
            ["pg_dump", "--format=custom", "--no-owner", "--no-acl", f"--file={dest}", *args],
            env,
            timeout=PG_TIMEOUT_SECONDS,
        )

    def _pg_restore(self, dump_path: Path) -> None:
        args, env = self._pg_connection()
        self._run(
            [
                "pg_restore",
                "--clean",
                "--if-exists",
                "--no-owner",
                "--no-acl",
                "--single-transaction",
                "--exit-on-error",
                *args,
                str(dump_path),
            ],
            env,
            timeout=PG_TIMEOUT_SECONDS,
        )

    def _copy_uploads(self, source: Path, dest: Path) -> None:
        if not source.exists():
            return
        dest.mkdir(parents=True, exist_ok=True)
        for child in source.iterdir():
            if child.name.startswith("."):
                continue
            target = dest / child.name
            if child.is_dir():
                shutil.copytree(child, target, dirs_exist_ok=True)
            elif child.is_file():
                shutil.copy2(child, target)

    def _replace_uploads(self, source: Path, dest: Path) -> None:
        dest.mkdir(parents=True, exist_ok=True)
        for child in list(dest.iterdir()):
            if child.name == LAST_BACKUP_NAME:
                continue
            if child.is_dir():
                shutil.rmtree(child)
            else:
                child.unlink()
        if source.exists():
            self._copy_uploads(source, dest)

    def _extract_archive(self, archive_path: Path, dest: Path) -> Path:
        try:
            with zipfile.ZipFile(archive_path) as archive:
                self._validate_zip(archive)
                archive.extractall(dest)
        except zipfile.BadZipFile as exc:
            raise ValidationAppError("This file is not a valid clinic backup zip.") from exc
        manifest_path = dest / MANIFEST_NAME
        dump_path = dest / DATABASE_DUMP_NAME
        if not manifest_path.is_file() or not dump_path.is_file():
            raise ValidationAppError("This zip is not a Nabi Dental clinic backup.")
        try:
            manifest = json.loads(manifest_path.read_text(encoding="utf-8"))
        except json.JSONDecodeError as exc:
            raise ValidationAppError("This zip is not a Nabi Dental clinic backup.") from exc
        if manifest.get("kind") != BACKUP_KIND:
            raise ValidationAppError("This zip is not a Nabi Dental clinic backup.")
        version = manifest.get("format_version")
        if version != BACKUP_FORMAT_VERSION:
            raise ValidationAppError("This backup was made with an unsupported version of the app.")
        return dest

    def _validate_zip(self, archive: zipfile.ZipFile) -> None:
        names = archive.namelist()
        if MANIFEST_NAME not in names or DATABASE_DUMP_NAME not in names:
            raise ValidationAppError("This zip is not a Nabi Dental clinic backup.")
        total = 0
        for info in archive.infolist():
            name = info.filename.replace("\\", "/")
            path = Path(name)
            if path.is_absolute() or ".." in path.parts or name.startswith("/"):
                raise ValidationAppError("This file is not a valid clinic backup.")
            total += max(info.file_size, 0)
            if total > MAX_UNCOMPRESSED_BYTES:
                raise ValidationAppError("This backup file is too large to restore on this laptop.")

    def _last_backup_path(self) -> Path:
        return self.upload_dir / LAST_BACKUP_NAME

    def _read_last_export(self) -> dict[str, object]:
        path = self._last_backup_path()
        if not path.is_file():
            return {}
        try:
            data = json.loads(path.read_text(encoding="utf-8"))
        except (OSError, json.JSONDecodeError):
            return {}
        return data if isinstance(data, dict) else {}

    def _write_last_export(self, created_at: datetime, filename: str, size: int) -> None:
        self.upload_dir.mkdir(parents=True, exist_ok=True)
        payload = {
            "created_at": created_at.isoformat(),
            "filename": filename,
            "bytes": size,
        }
        self._last_backup_path().write_text(json.dumps(payload), encoding="utf-8")
