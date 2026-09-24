from fastapi import APIRouter, File, UploadFile
from fastapi.responses import FileResponse

from app.api.deps import CurrentUser, DBSession
from app.schemas.settings import SettingsRead, SettingsUpdate
from app.services.avatar_service import AvatarService
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
