from uuid import UUID

from sqlalchemy import select

from app.models.sync_change import SyncChange
from app.repositories.base import BaseRepository


class SyncChangeRepository(BaseRepository):
    async def get_by_client_change_id(self, client_change_id: UUID) -> SyncChange | None:
        return await self.session.scalar(select(SyncChange).where(SyncChange.client_change_id == client_change_id))
