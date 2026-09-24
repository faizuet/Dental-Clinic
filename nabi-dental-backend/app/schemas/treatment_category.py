import uuid

from pydantic import Field, field_validator

from app.schemas.common import VersionedRead
from app.utils.pagination import APIModel


def _clean_name(value: str, max_length: int) -> str:
    cleaned = value.strip()
    if not cleaned:
        raise ValueError("Name is required.")
    if len(cleaned) > max_length:
        raise ValueError(f"Name must be at most {max_length} characters.")
    return cleaned


class TreatmentCategoryCreate(APIModel):
    id: uuid.UUID | None = None
    name: str = Field(min_length=1, max_length=120)
    display_order: int | None = Field(default=None, ge=0)
    is_active: bool = True

    @field_validator("name")
    @classmethod
    def trim_name(cls, value: str) -> str:
        return _clean_name(value, 120)


class TreatmentCategoryUpdate(APIModel):
    version: int = Field(ge=1)
    name: str | None = Field(default=None, min_length=1, max_length=120)
    display_order: int | None = Field(default=None, ge=0)
    is_active: bool | None = None

    @field_validator("name")
    @classmethod
    def trim_name(cls, value: str | None) -> str | None:
        return _clean_name(value, 120) if value is not None else None


class TreatmentCategoryRead(VersionedRead):
    clinic_id: uuid.UUID
    name: str
    display_order: int
    is_active: bool
