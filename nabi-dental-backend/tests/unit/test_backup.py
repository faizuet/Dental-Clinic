import json
import shutil
import zipfile
from pathlib import Path

import pytest

from app.core.exceptions import ValidationAppError
from app.services.backup_service import (
    BACKUP_KIND,
    DATABASE_DUMP_NAME,
    MANIFEST_NAME,
    BackupService,
    _dump_tables,
)


def test_dump_tables_reads_pg_restore_listing():
    listing = "\n".join(
        [
            ";",
            "; Archive created at 2026-11-14 10:00:00 PKT",
            "215; 1259 16390 TABLE public clinics postgres",
            "216; 1259 16402 TABLE public clinic_expenses postgres",
            "3401; 0 16390 TABLE DATA public clinics postgres",
            "3402; 2606 16420 CONSTRAINT public clinics clinics_pkey postgres",
            "3403; 1259 16430 INDEX public ix_users_clinic_id postgres",
        ]
    )
    assert _dump_tables(listing) == {"clinics", "clinic_expenses"}


def _write_zip(path: Path, *, kind: str = BACKUP_KIND, dump: bytes = b"DUMP", uploads: dict[str, bytes] | None = None) -> None:
    with zipfile.ZipFile(path, "w") as archive:
        archive.writestr(
            MANIFEST_NAME,
            json.dumps({"kind": kind, "format_version": 1, "created_at": "2026-11-13T00:00:00+00:00"}),
        )
        archive.writestr(DATABASE_DUMP_NAME, dump)
        for name, content in (uploads or {}).items():
            archive.writestr(f"uploads/{name}", content)


def test_create_zip_includes_manifest_dump_and_uploads(tmp_path: Path):
    uploads = tmp_path / "uploads"
    (uploads / "avatars").mkdir(parents=True)
    (uploads / "avatars" / "owner.jpg").write_bytes(b"photo")
    dumped = []

    def dump_database(dest: Path) -> None:
        dest.write_bytes(b"PGDUMP")
        dumped.append(dest)

    service = BackupService(upload_dir=uploads, dump_database=dump_database)
    artifact = service.create()
    try:
        assert dumped
        with zipfile.ZipFile(artifact.path) as archive:
            names = archive.namelist()
            assert MANIFEST_NAME in names
            assert DATABASE_DUMP_NAME in names
            assert "uploads/avatars/owner.jpg" in names
            manifest = json.loads(archive.read(MANIFEST_NAME))
            assert manifest["kind"] == BACKUP_KIND
            assert archive.read(DATABASE_DUMP_NAME) == b"PGDUMP"
    finally:
        shutil.rmtree(artifact.cleanup_dir, ignore_errors=True)


def test_restore_replaces_uploads_and_calls_database_restore(tmp_path: Path):
    current = tmp_path / "uploads"
    (current / "xrays" / "old").mkdir(parents=True)
    (current / "xrays" / "old" / "gone.jpg").write_bytes(b"old")
    archive = tmp_path / "clinic.zip"
    restored = []
    _write_zip(archive, uploads={"xrays/new/keep.jpg": b"new"})

    def restore_database(dump_path: Path) -> None:
        restored.append(dump_path.read_bytes())

    service = BackupService(upload_dir=current, restore_database=restore_database)
    result = service.restore(archive)
    assert result["restored"] is True
    assert restored == [b"DUMP"]
    assert (current / "xrays" / "new" / "keep.jpg").read_bytes() == b"new"
    assert not (current / "xrays" / "old" / "gone.jpg").exists()


def test_restore_rejects_unknown_zip(tmp_path: Path):
    archive = tmp_path / "other.zip"
    _write_zip(archive, kind="something-else")
    service = BackupService(upload_dir=tmp_path / "uploads", restore_database=lambda path: None)
    with pytest.raises(ValidationAppError, match="not a Nabi Dental"):
        service.restore(archive)


def test_restore_rejects_zip_with_path_escape(tmp_path: Path):
    archive = tmp_path / "bad.zip"
    with zipfile.ZipFile(archive, "w") as zf:
        zf.writestr(MANIFEST_NAME, json.dumps({"kind": BACKUP_KIND, "format_version": 1}))
        zf.writestr(DATABASE_DUMP_NAME, b"DUMP")
        zf.writestr("../evil.txt", b"nope")
    service = BackupService(upload_dir=tmp_path / "uploads", restore_database=lambda path: None)
    with pytest.raises(ValidationAppError, match="not a valid clinic backup"):
        service.restore(archive)
