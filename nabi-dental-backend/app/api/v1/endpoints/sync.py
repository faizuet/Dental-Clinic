from typing import Annotated

from fastapi import APIRouter, Query

from app.api.deps import CurrentUser, DBSession
from app.core.config import settings
from app.schemas.sync import SyncBootstrapResponse, SyncPushRequest, SyncPushResponse, SyncPullResponse
from app.services.sync_service import SyncService

router = APIRouter(prefix="/sync", tags=["sync"])


@router.post("/push", response_model=SyncPushResponse)
async def sync_push(payload: SyncPushRequest, user: CurrentUser, session: DBSession):
    return await SyncService(session).push(user, payload)


@router.get("/pull", response_model=SyncPullResponse)
async def sync_pull(
    user: CurrentUser,
    session: DBSession,
    cursor: str | None = None,
    limit: Annotated[int, Query(ge=1, le=500)] = 100,
):
    limit = min(limit, settings.SYNC_PULL_MAX_LIMIT)
    return await SyncService(session).pull(user, cursor=cursor, limit=limit)


@router.post("/bootstrap", response_model=SyncBootstrapResponse)
async def sync_bootstrap(user: CurrentUser, session: DBSession):
    return await SyncService(session).bootstrap(user)
