from uuid import UUID

from sqlalchemy import func, select
from sqlalchemy.orm import selectinload

from app.models import Clinic, RefreshToken, User
from app.repositories.base import BaseRepository


class UserRepository(BaseRepository):
    async def get_by_id(self, user_id: UUID) -> User | None:
        return await self.session.scalar(
            select(User).options(selectinload(User.clinic)).where(User.id == user_id)
        )

    async def get_by_email(self, email: str) -> User | None:
        return await self.session.scalar(
            select(User).options(selectinload(User.clinic)).where(func.lower(User.email) == email.lower())
        )


class ClinicRepository(BaseRepository):
    async def get_by_id(self, clinic_id: UUID) -> Clinic | None:
        return await self.session.get(Clinic, clinic_id)


class RefreshTokenRepository(BaseRepository):
    async def get_by_hash(self, token_hash: str) -> RefreshToken | None:
        return await self.session.scalar(
            select(RefreshToken).options(selectinload(RefreshToken.user).selectinload(User.clinic)).where(
                RefreshToken.token_hash == token_hash
            )
        )

    async def list_active_for_user(self, user_id: UUID) -> list[RefreshToken]:
        result = await self.session.scalars(
            select(RefreshToken).where(
                RefreshToken.user_id == user_id,
                RefreshToken.revoked_at.is_(None),
            )
        )
        return list(result)
