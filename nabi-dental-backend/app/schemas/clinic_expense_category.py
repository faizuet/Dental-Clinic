import uuid

from pydantic import Field, field_validator

from app.schemas.common import VersionedRead
from app.utils.pagination import APIModel


class ClinicExpenseCategoryCreate(APIModel):
    id: uuid.UUID | None = None
    name: str = Field(min_length=1, max_length=120)
    display_order: int | None = Field(default=None, ge=0)
    is_active: bool = True

    @field_validator("name")
    @classmethod
    def trim_name(cls, value: str) -> str:
        cleaned = value.strip()
        if not cleaned:
            raise ValueError("Name is required.")
        return cleaned


class ClinicExpenseCategoryUpdate(APIModel):
    version: int = Field(ge=1)
    name: str | None = Field(default=None, min_length=1, max_length=120)
    display_order: int | None = Field(default=None, ge=0)
    is_active: bool | None = None

    @field_validator("name")
    @classmethod
    def trim_name(cls, value: str | None) -> str | None:
        if value is None:
            return None
        cleaned = value.strip()
        if not cleaned:
            raise ValueError("Name is required.")
        return cleaned


class ClinicExpenseCategoryRead(VersionedRead):
    clinic_id: uuid.UUID
    name: str
    display_order: int
    is_active: bool
