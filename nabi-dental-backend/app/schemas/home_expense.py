import uuid
from datetime import date

from pydantic import Field, field_validator

from app.core.config import settings
from app.schemas.common import VersionedRead
from app.utils.money import MoneyPositive
from app.utils.pagination import APIModel


class HomeExpenseCreate(APIModel):
    id: uuid.UUID | None = None
    category_id: uuid.UUID
    expense_date: date
    amount: MoneyPositive
    notes: str | None = Field(default=None, max_length=1000)

    @field_validator("notes")
    @classmethod
    def trim_notes(cls, value: str | None) -> str | None:
        if value is None:
            return None
        cleaned = value.strip()
        return cleaned or None


class HomeExpenseUpdate(APIModel):
    version: int = Field(ge=1)
    category_id: uuid.UUID | None = None
    expense_date: date | None = None
    amount: MoneyPositive | None = None
    notes: str | None = Field(default=None, max_length=1000)

    @field_validator("notes")
    @classmethod
    def trim_notes(cls, value: str | None) -> str | None:
        if value is None:
            return None
        cleaned = value.strip()
        return cleaned or None


class HomeExpenseBatchCreate(APIModel):
    items: list[HomeExpenseCreate] = Field(min_length=1, max_length=settings.BATCH_MAX_ITEMS)


class HomeExpenseRead(VersionedRead):
    user_id: uuid.UUID
    category_id: uuid.UUID
    expense_date: date
    amount: MoneyPositive
    notes: str | None
