import uuid

from pydantic import Field

from app.schemas.common import VersionedRead
from app.utils.money import MoneyNonNegative
from app.utils.pagination import APIModel


class HomeBudgetCreate(APIModel):
    id: uuid.UUID | None = None
    year: int = Field(ge=2000, le=2100)
    month: int = Field(ge=1, le=12)
    amount: MoneyNonNegative


class HomeBudgetUpdate(APIModel):
    version: int = Field(ge=1)
    amount: MoneyNonNegative | None = None


class HomeBudgetRead(VersionedRead):
    user_id: uuid.UUID
    year: int
    month: int
    amount: MoneyNonNegative


class HomeBudgetCurrent(APIModel):
    year: int
    month: int
    amount: MoneyNonNegative
    source: str
    override: HomeBudgetRead | None = None
