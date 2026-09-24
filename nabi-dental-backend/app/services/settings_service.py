from sqlalchemy.ext.asyncio import AsyncSession

from app.models import User
from app.models.mixins import utc_now
from app.schemas.settings import SettingsRead, SettingsUpdate


class SettingsService:
    def __init__(self, session: AsyncSession) -> None:
        self.session = session

    async def read(self, user: User) -> SettingsRead:
        return SettingsRead(
            clinic_id=str(user.clinic_id),
            clinic_name=user.clinic.name,
            currency=user.clinic.currency,
            timezone=user.clinic.timezone,
            full_name=user.full_name,
            email=user.email,
            default_home_budget=user.default_home_budget,
            has_avatar=user.has_avatar,
        )

    async def update(self, user: User, payload: SettingsUpdate) -> SettingsRead:
        data = payload.model_dump(exclude_unset=True)
        if "clinic_name" in data:
            user.clinic.name = data["clinic_name"]
        if "currency" in data:
            user.clinic.currency = data["currency"]
        if "timezone" in data:
            user.clinic.timezone = data["timezone"]
        if "full_name" in data:
            user.full_name = data["full_name"]
        if "default_home_budget" in data:
            user.default_home_budget = data["default_home_budget"]
        now = utc_now()
        user.updated_at = now
        user.clinic.updated_at = now
        await self.session.flush()
        return await self.read(user)
