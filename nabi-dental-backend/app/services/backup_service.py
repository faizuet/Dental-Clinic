from __future__ import annotations

import json
import os
import re
import shutil
import subprocess
import sys
import tempfile
import time
import zipfile
from contextlib import contextmanager
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
BACKUP_STATE_NAME = "backup-state.json"
UPLOADS_DIR_NAME = "uploads"
BACKUP_NAME_RE = re.compile(r"^nabi-dental-backup-\d{4}-\d{2}-\d{2}-\d{6}(?:-\d+)?\.zip$")
COUNT_TABLES = (
    "patients",
    "treatment_transactions",
    "clinic_expenses",
    "lab_charges",
    "home_expenses",
)
REMINDER_AFTER_DAYS = settings.BACKUP_REMINDER_DAYS
PG_TIMEOUT_SECONDS = 180
MAX_BACKUP_BYTES = 1_500_000_000
MAX_UNCOMPRESSED_BYTES = 2_000_000_000
BACKEND_ROOT = Path(__file__).resolve().parents[2]


@dataclass(frozen=True)
class BackupArtifact:
    path: Path
    filename: str
    cleanup_dir: Path


@dataclass(frozen=True)
class BackupCopy:
    filename: str
    created_at: datetime
    size: int
    path: Path


class BackupService:
    def __init__(
        self,
        *,
        upload_dir: Path | None = None,
        backup_dir: Path | None = None,
        database_url: str | None = None,
        retention_count: int | None = None,
        interval_hours: int | None = None,
        dump_database=None,
        restore_database=None,
        upgrade_database=None,
    ) -> None:
        self.upload_dir = Path(upload_dir or settings.UPLOAD_DIR)
        self.backup_dir = Path(backup_dir or settings.BACKUP_DIR)
        self.database_url = database_url or settings.DATABASE_URL
        self.retention_count = retention_count if retention_count is not None else settings.BACKUP_RETENTION_COUNT
        self.interval_hours = interval_hours if interval_hours is not None else settings.BACKUP_INTERVAL_HOURS
        self._use_pg_dump = dump_database is None
        self._use_pg_restore = restore_database is None
        self._dump_database = dump_database or self._pg_dump
        self._restore_database = restore_database or self._pg_restore
        if upgrade_database is None:
            upgrade_database = self._alembic_upgrade if restore_database is None else (lambda: None)
        self._upgrade_database = upgrade_database

    def status(self) -> dict[str, object]:
        copies = self.list_copies()
        state = self._read_state()
        last = copies[0].created_at.isoformat() if copies else None
        if last is None:
            previous = self._read_last_export()
            last = previous.get("created_at") if previous else None
        return {
            "last_export_at": last,
            "last_error": state.get("last_error"),
            "last_error_at": state.get("last_error_at"),
            "reminder_after_days": REMINDER_AFTER_DAYS,
            "format_version": BACKUP_FORMAT_VERSION,
            "pg_dump_available": self.tools_available(),
            "retention_count": self.retention_count,
            "backups": [
                {"filename": item.filename, "created_at": item.created_at.isoformat(), "bytes": item.size}
                for item in copies
            ],
        }

    def tools_available(self) -> bool:
        return bool(shutil.which("pg_dump") and shutil.which("pg_restore") and shutil.which("psql"))

    def create(self) -> BackupArtifact:
        self._require_tools(dump=True)
        stamp = datetime.now(timezone.utc)
        filename = f"nabi-dental-backup-{stamp.strftime('%Y-%m-%d-%H%M%S')}.zip"
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
                "counts": self._counts(),
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

    def restore(self, archive_path: Path, *, create_safety_backup: bool | None = None) -> dict[str, object]:
        self._require_tools(restore=True)
        if not archive_path.is_file():
            raise ValidationAppError("Choose a Nabi Dental backup zip file.")
        if archive_path.stat().st_size > MAX_BACKUP_BYTES:
            raise ValidationAppError("This backup file is too large to restore on this laptop.")
        manifest = self._read_manifest(archive_path)
        if create_safety_backup is None:
            create_safety_backup = self._use_pg_restore
        safety_name = None
        if create_safety_backup:
            try:
                safety_name = self.create_archive().filename
            except AppError as exc:
                raise AppError(
                    exc.code,
                    "Could not save a safety copy, so the clinic data was not replaced.",
                    status_code=exc.status_code,
                ) from exc
        work = Path(tempfile.mkdtemp(prefix="nabi-restore-"))
        try:
            extracted = self._extract_archive(archive_path, work)
            dump_path = extracted / DATABASE_DUMP_NAME
            uploads_source = extracted / UPLOADS_DIR_NAME
            self._restore_database(dump_path)
            self._upgrade_database()
            self.upload_dir.mkdir(parents=True, exist_ok=True)
            self._replace_uploads(uploads_source, self.upload_dir)
            restored_at = datetime.now(timezone.utc)
            verified, verification = self._verify_counts(manifest.get("counts"))
            self._write_last_export(restored_at, archive_path.name, archive_path.stat().st_size)
            return {
                "restored": True,
                "restored_at": restored_at.isoformat(),
                "format_version": BACKUP_FORMAT_VERSION,
                "safety_backup": safety_name,
                "verified": verified,
                "verification": verification,
            }
        finally:
            shutil.rmtree(work, ignore_errors=True)

    def needs_scheduled_backup(self) -> bool:
        latest = self.latest_copy()
        if latest is None:
            return True
        age = datetime.now(timezone.utc) - latest.created_at
        return age.total_seconds() >= self.interval_hours * 3600

    def seconds_until_due(self) -> int:
        latest = self.latest_copy()
        if latest is None:
            return 0
        elapsed = (datetime.now(timezone.utc) - latest.created_at).total_seconds()
        remaining = int(self.interval_hours * 3600 - elapsed)
        return max(60, remaining)

    def create_archive(self) -> BackupCopy:
        self.backup_dir.mkdir(parents=True, exist_ok=True)
        self._clear_stale_partials()
        with self._exclusive_lock():
            artifact = self.create()
            try:
                filename = self._available_name(artifact.filename)
                partial = self.backup_dir / f"{filename}.partial"
                final = self.backup_dir / filename
                shutil.copy2(artifact.path, partial)
                self._verify_zip_file(partial)
                os.replace(partial, final)
            finally:
                shutil.rmtree(artifact.cleanup_dir, ignore_errors=True)
            self.prune()
            copy = self._copy_from_path(final)
            self._write_state(success=copy)
            self._write_last_export(copy.created_at, copy.filename, copy.size)
            return copy

    def list_copies(self) -> list[BackupCopy]:
        if not self.backup_dir.is_dir():
            return []
        copies = []
        for path in self.backup_dir.glob("nabi-dental-backup-*.zip"):
            if not BACKUP_NAME_RE.match(path.name):
                continue
            try:
                self._verify_zip_file(path)
            except (OSError, ValidationAppError, AppError, zipfile.BadZipFile):
                continue
            copies.append(self._copy_from_path(path))
        copies.sort(key=lambda item: item.created_at, reverse=True)
        return copies

    def latest_copy(self) -> BackupCopy | None:
        copies = self.list_copies()
        return copies[0] if copies else None

    def copy_path(self, filename: str) -> Path:
        if not BACKUP_NAME_RE.match(filename):
            raise ValidationAppError("Choose a Nabi Dental backup zip file.")
        path = (self.backup_dir / filename).resolve()
        root = self.backup_dir.resolve()
        if path.parent != root or not path.is_file():
            raise ValidationAppError("That backup is no longer on this computer.")
        self._verify_zip_file(path)
        return path

    def prune(self) -> None:
        keep = max(1, self.retention_count)
        for stale in self.list_copies()[keep:]:
            stale.path.unlink(missing_ok=True)

    def record_failure(self, message: str) -> None:
        self.backup_dir.mkdir(parents=True, exist_ok=True)
        self._write_state(error=_public_backup_message(message))

    def _counts(self) -> dict[str, int]:
        if not self._use_pg_dump:
            return {}
        args, env = self._pg_connection()
        selects = ", ".join(f"(SELECT count(*) FROM {name})" for name in COUNT_TABLES)
        try:
            raw = self._run(
                ["psql", "--no-psqlrc", "-At", "-F", ",", "-c", f"SELECT {selects}", *args],
                env,
                timeout=PG_TIMEOUT_SECONDS,
            )
        except AppError:
            return {}
        parts = [part.strip() for part in raw.strip().split(",")]
        if len(parts) != len(COUNT_TABLES) or any(not part.isdigit() for part in parts):
            return {}
        return {name: int(value) for name, value in zip(COUNT_TABLES, parts, strict=True)}

    def _verify_counts(self, expected: object) -> tuple[bool, str]:
        if not isinstance(expected, dict) or not expected:
            return True, "This backup has no row counts to compare."
        actual = self._counts()
        if not actual:
            return False, "The restored clinic could not be checked."
        mismatched = [
            name
            for name in COUNT_TABLES
            if name in expected and str(expected.get(name)) != str(actual.get(name))
        ]
        if mismatched:
            return False, "Restored records did not match the backup."
        return True, "Restored records match the backup."

    def _copy_from_path(self, path: Path) -> BackupCopy:
        created = datetime.fromtimestamp(path.stat().st_mtime, timezone.utc)
        try:
            with zipfile.ZipFile(path) as archive:
                manifest = json.loads(archive.read(MANIFEST_NAME))
            parsed = datetime.fromisoformat(str(manifest.get("created_at")))
            if parsed.tzinfo is None:
                parsed = parsed.replace(tzinfo=timezone.utc)
            created = parsed
        except (OSError, json.JSONDecodeError, KeyError, TypeError, ValueError, zipfile.BadZipFile):
            pass
        return BackupCopy(filename=path.name, created_at=created, size=path.stat().st_size, path=path)

    def _read_manifest(self, archive_path: Path) -> dict:
        try:
            with zipfile.ZipFile(archive_path) as archive:
                self._validate_zip(archive)
                manifest = json.loads(archive.read(MANIFEST_NAME))
        except zipfile.BadZipFile as exc:
            raise ValidationAppError("This file is not a valid clinic backup zip.") from exc
        except json.JSONDecodeError as exc:
            raise ValidationAppError("This zip is not a Nabi Dental clinic backup.") from exc
        if not isinstance(manifest, dict) or manifest.get("kind") != BACKUP_KIND:
            raise ValidationAppError("This zip is not a Nabi Dental clinic backup.")
        if manifest.get("format_version") != BACKUP_FORMAT_VERSION:
            raise ValidationAppError("This backup was made with an unsupported version of the app.")
        return manifest

    def _verify_zip_file(self, path: Path) -> None:
        if not path.is_file() or path.stat().st_size == 0:
            raise ValidationAppError("This backup file is empty.")
        with zipfile.ZipFile(path) as archive:
            self._validate_zip(archive)
            info = archive.getinfo(DATABASE_DUMP_NAME)
            if info.file_size <= 0:
                raise ValidationAppError("This backup does not contain the clinic database.")

    def _clear_stale_partials(self) -> None:
        if not self.backup_dir.is_dir():
            return
        cutoff = time.time() - 3600
        for path in self.backup_dir.glob("*.partial"):
            try:
                if path.stat().st_mtime < cutoff:
                    path.unlink()
            except OSError:
                continue

    @contextmanager
    def _exclusive_lock(self):
        self.backup_dir.mkdir(parents=True, exist_ok=True)
        lock = self.backup_dir / ".backup.lock"
        if lock.exists():
            try:
                stale = time.time() - lock.stat().st_mtime > 7200
            except OSError:
                stale = True
            if stale:
                lock.unlink(missing_ok=True)
            else:
                raise AppError(
                    ErrorCode.CONFLICT,
                    "A clinic backup is already running.",
                    status_code=409,
                )
        try:
            fd = os.open(lock, os.O_CREAT | os.O_EXCL | os.O_WRONLY)
        except FileExistsError as exc:
            raise AppError(
                ErrorCode.INTERNAL_ERROR,
                "A clinic backup is already running.",
                status_code=409,
            ) from exc
        try:
            os.write(fd, str(os.getpid()).encode())
            yield
        finally:
            os.close(fd)
            lock.unlink(missing_ok=True)

    def _state_path(self) -> Path:
        return self.backup_dir / BACKUP_STATE_NAME

    def _read_state(self) -> dict[str, object]:
        path = self._state_path()
        if not path.is_file():
            return {}
        try:
            data = json.loads(path.read_text(encoding="utf-8"))
        except (OSError, json.JSONDecodeError):
            return {}
        return data if isinstance(data, dict) else {}

    def _write_state(self, *, success: BackupCopy | None = None, error: str | None = None) -> None:
        self.backup_dir.mkdir(parents=True, exist_ok=True)
        state = self._read_state()
        if success is not None:
            state["last_success_at"] = success.created_at.isoformat()
            state["last_success_filename"] = success.filename
            state["last_error"] = None
            state["last_error_at"] = None
        if error is not None:
            state["last_error"] = _public_backup_message(error)
            state["last_error_at"] = datetime.now(timezone.utc).isoformat()
        self._state_path().write_text(json.dumps(state), encoding="utf-8")

    def _require_tools(self, *, dump: bool = False, restore: bool = False) -> None:
        need_dump = dump and self._use_pg_dump and not shutil.which("pg_dump")
        need_restore = restore and self._use_pg_restore and not (shutil.which("pg_restore") and shutil.which("psql"))
        if need_dump or need_restore:
            raise AppError(
                ErrorCode.DEPENDENCY_UNAVAILABLE,
                "Backup tools are missing. Rebuild the Docker app image, or install PostgreSQL client tools.",
                status_code=503,
            )

    def _pg_connection(self) -> tuple[list[str], dict[str, str]]:
        url = make_url(self.database_url)
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

    def _run(self, command: list[str], env: dict[str, str], *, timeout: int, cwd: Path | None = None) -> str:
        try:
            completed = subprocess.run(
                command,
                env=env,
                cwd=cwd,
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
        return completed.stdout.decode("utf-8", errors="replace")

    def _pg_dump(self, dest: Path) -> None:
        args, env = self._pg_connection()
        self._run(
            ["pg_dump", "--format=custom", "--no-owner", "--no-acl", f"--file={dest}", *args],
            env,
            timeout=PG_TIMEOUT_SECONDS,
        )

    def _pg_restore(self, dump_path: Path) -> None:
        # Tables added after the backup was made (for example lab_charges) reference tables
        # in the dump, so pg_restore --clean cannot drop those. Drop them first in the same
        # transaction; the schema upgrade after restore recreates them from the old data.
        args, env = self._pg_connection()
        raw_script = dump_path.with_name("restore-raw.sql")
        script = dump_path.with_name("restore.sql")
        prelude = dump_path.with_name("prelude.sql")
        self._run(
            ["pg_restore", "--clean", "--if-exists", "--no-owner", "--no-acl", f"--file={raw_script}", str(dump_path)],
            env,
            timeout=PG_TIMEOUT_SECONDS,
        )
        _strip_unsupported_settings(raw_script, script)
        dumped = _dump_tables(self._run(["pg_restore", "--list", str(dump_path)], env, timeout=PG_TIMEOUT_SECONDS))
        current = self._run(
            ["psql", "--no-psqlrc", "-At", "-c", "SELECT tablename FROM pg_tables WHERE schemaname = 'public'", *args],
            env,
            timeout=PG_TIMEOUT_SECONDS,
        ).split()
        stale = sorted(set(current) - dumped)
        prelude.write_text(
            "".join(f'DROP TABLE IF EXISTS public."{name}" CASCADE;\n' for name in stale),
            encoding="utf-8",
        )
        self._run(
            [
                "psql",
                "--no-psqlrc",
                "--quiet",
                "--single-transaction",
                "--set=ON_ERROR_STOP=1",
                f"--file={prelude}",
                f"--file={script}",
                *args,
            ],
            env,
            timeout=PG_TIMEOUT_SECONDS,
        )

    def _available_name(self, filename: str) -> str:
        if not BACKUP_NAME_RE.match(filename):
            raise AppError(ErrorCode.INTERNAL_ERROR, "The clinic backup name was not valid.", status_code=500)
        stem = filename[:-4]
        candidate = filename
        index = 2
        while (self.backup_dir / candidate).exists():
            candidate = f"{stem}-{index}.zip"
            index += 1
            if index > 20:
                raise AppError(ErrorCode.CONFLICT, "A clinic backup is already running.", status_code=409)
        return candidate

    def _alembic_upgrade(self) -> None:
        env = os.environ.copy()
        env["DATABASE_URL"] = self.database_url
        self._run(
            [sys.executable, "-m", "alembic", "upgrade", "head"],
            env,
            timeout=PG_TIMEOUT_SECONDS,
            cwd=BACKEND_ROOT,
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


def _public_backup_message(message: str) -> str:
    text = " ".join(str(message).split())
    lowered = text.lower()
    if any(token in lowered for token in ("password", "postgres://", "postgresql", "pgpassword")):
        return "The clinic backup failed. Keep Docker running and try again."
    return text[:300] or "The clinic backup failed. Keep Docker running and try again."


def _strip_unsupported_settings(source: Path, dest: Path) -> None:
    # The image ships PostgreSQL 17 client tools; script output always sets transaction_timeout,
    # which the PostgreSQL 16 server rejects. Zero is already the default, so the line is dropped.
    with source.open("r", encoding="utf-8") as reader, dest.open("w", encoding="utf-8") as writer:
        for line in reader:
            if line.startswith("SET transaction_timeout"):
                continue
            writer.write(line)


def _dump_tables(listing: str) -> set[str]:
    tables: set[str] = set()
    for line in listing.splitlines():
        if line.startswith(";"):
            continue
        parts = line.split()
        if "TABLE" not in parts:
            continue
        index = parts.index("TABLE")
        if parts[index + 1 : index + 2] == ["public"] and len(parts) > index + 2:
            tables.add(parts[index + 2])
    return tables


if __name__ == "__main__":
    if len(sys.argv) != 2:
        raise SystemExit("Usage: python -m app.services.backup_service <backup.zip>")
    BackupService().restore(Path(sys.argv[1]))
    print("Restore finished.")
