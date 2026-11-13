import asyncio
import shutil
import tempfile
from pathlib import Path

from fastapi import APIRouter, File, Query, UploadFile
from fastapi.responses import FileResponse
from starlette.background import BackgroundTask

from app.api.deps import CurrentUser, DBSession, DetachedUser
from app.core.exceptions import ValidationAppError
from app.db.session import engine
from app.schemas.backup import BackupRestoreRead, BackupStatusRead
from app.schemas.settings import SettingsRead, SettingsUpdate
from app.services.avatar_service import AvatarService
from app.services.backup_service import MAX_BACKUP_BYTES, BackupService
from app.services.settings_service import SettingsService

router = APIRouter(prefix="/settings", tags=["settings"])


@router.get("", response_model=SettingsRead)
async def get_settings(user: CurrentUser, session: DBSession):
    return await SettingsService(session).read(user)


@router.patch("", response_model=SettingsRead)
async def update_settings(payload: SettingsUpdate, user: CurrentUser, session: DBSession):
    return await SettingsService(session).update(user, payload)


@router.get("/avatar")
async def get_avatar(user: CurrentUser, session: DBSession):
    path = AvatarService(session).path_for(user)
    return FileResponse(path, media_type="image/jpeg")


@router.post("/avatar", response_model=SettingsRead)
async def upload_avatar(
    user: CurrentUser,
    session: DBSession,
    file: UploadFile = File(...),
):
    await AvatarService(session).save(user, file)
    return await SettingsService(session).read(user)


@router.delete("/avatar", response_model=SettingsRead)
async def delete_avatar(user: CurrentUser, session: DBSession):
    await AvatarService(session).delete(user)
    return await SettingsService(session).read(user)


@router.get("/backup", response_model=BackupStatusRead)
async def backup_status(user: CurrentUser):
    _ = user.id
    return BackupService().status()


@router.get("/backup/export")
async def export_backup(user: CurrentUser):
    _ = user.id
    artifact = await asyncio.to_thread(BackupService().create)
    return FileResponse(
        artifact.path,
        media_type="application/zip",
        filename=artifact.filename,
        background=BackgroundTask(shutil.rmtree, artifact.cleanup_dir, True),
    )


@router.post("/backup/restore", response_model=BackupRestoreRead)
async def restore_backup(
    user: DetachedUser,
    file: UploadFile = File(...),
    confirm: bool = Query(False),
):
    _ = user.id
    if not confirm:
        raise ValidationAppError("Confirm restore. This replaces all clinic records and X-rays on this computer.")
    suffix = Path(file.filename or "backup.zip").suffix.lower()
    if suffix != ".zip":
        raise ValidationAppError("Choose a Nabi Dental backup zip file.")
    work = Path(tempfile.mkdtemp(prefix="nabi-restore-upload-"))
    saved = work / "backup.zip"
    written = 0
    try:
        with saved.open("wb") as handle:
            while True:
                chunk = await file.read(1024 * 1024)
                if not chunk:
                    break
                written += len(chunk)
                if written > MAX_BACKUP_BYTES:
                    raise ValidationAppError("This backup file is too large to restore on this laptop.")
                handle.write(chunk)
        if written == 0:
            raise ValidationAppError("Choose a Nabi Dental backup zip file.")
        await engine.dispose()
        result = await asyncio.to_thread(BackupService().restore, saved)
        return result
    finally:
        shutil.rmtree(work, ignore_errors=True)
