import io
import json
import zipfile
from pathlib import Path
from unittest.mock import patch

import pytest

from app.services.backup_service import (
    BACKUP_KIND,
    DATABASE_DUMP_NAME,
    MANIFEST_NAME,
    BackupArtifact,
)
from tests.api.conftest import auth_header, login


def _backup_zip_bytes() -> bytes:
    buffer = io.BytesIO()
    with zipfile.ZipFile(buffer, "w") as archive:
        archive.writestr(
            MANIFEST_NAME,
            json.dumps({"kind": BACKUP_KIND, "format_version": 1, "created_at": "2026-11-13T00:00:00+00:00"}),
        )
        archive.writestr(DATABASE_DUMP_NAME, b"DUMP")
    return buffer.getvalue()


@pytest.mark.asyncio
async def test_backup_requires_login(client):
    status = await client.get("/api/v1/settings/backup")
    assert status.status_code == 401
    export = await client.get("/api/v1/settings/backup/export")
    assert export.status_code == 401
    restore = await client.post("/api/v1/settings/backup/restore")
    assert restore.status_code == 401


@pytest.mark.asyncio
async def test_backup_status_and_export(client, tmp_path: Path):
    tokens = await login(client)
    headers = auth_header(tokens)

    status = await client.get("/api/v1/settings/backup", headers=headers)
    assert status.status_code == 200, status.text
    body = status.json()
    assert body["format_version"] == 1
    assert body["reminder_after_days"] == 7
    assert "pg_dump_available" in body

    cleanup = tmp_path / "cleanup"
    cleanup.mkdir()
    zip_path = cleanup / "nabi-dental-backup-test.zip"
    zip_path.write_bytes(_backup_zip_bytes())

    def fake_create():
        return BackupArtifact(path=zip_path, filename=zip_path.name, cleanup_dir=cleanup)

    with patch("app.api.v1.endpoints.settings.BackupService") as service_cls:
        service_cls.return_value.create.side_effect = fake_create
        exported = await client.get("/api/v1/settings/backup/export", headers=headers)
    assert exported.status_code == 200, exported.text
    assert exported.headers["content-type"].startswith("application/zip")
    assert exported.content[:2] == b"PK"


@pytest.mark.asyncio
async def test_restore_replaces_data_when_confirmed(client):
    tokens = await login(client)
    headers = auth_header(tokens)
    files = {"file": ("clinic.zip", _backup_zip_bytes(), "application/zip")}

    with patch("app.api.v1.endpoints.settings.BackupService") as service_cls:
        service_cls.return_value.restore.return_value = {
            "restored": True,
            "restored_at": "2026-11-13T00:00:00+00:00",
            "format_version": 1,
        }
        restored = await client.post(
            "/api/v1/settings/backup/restore",
            headers=headers,
            params={"confirm": "true"},
            files=files,
        )
    assert restored.status_code == 200, restored.text
    assert restored.json()["restored"] is True


@pytest.mark.asyncio
async def test_restore_requires_confirm_and_rejects_invalid_zip(client):
    tokens = await login(client)
    headers = auth_header(tokens)
    files = {"file": ("clinic.zip", _backup_zip_bytes(), "application/zip")}

    missing = await client.post("/api/v1/settings/backup/restore", headers=headers, files=files)
    assert missing.status_code == 400

    invalid = await client.post(
        "/api/v1/settings/backup/restore",
        headers=headers,
        params={"confirm": "true"},
        files={"file": ("notes.txt", b"not-a-zip", "text/plain")},
    )
    assert invalid.status_code == 400
