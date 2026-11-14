import uuid
from datetime import datetime

from pydantic import ConfigDict, field_serializer

from app.utils.dates import serialize_datetime
from app.utils.pagination import APIModel


def loaded_relation_name(value: object, relation: str) -> str | None:
    """Read a related record's name only when SQLAlchemy has already loaded it."""
    if not hasattr(value, relation):
        return None
    try:
        from sqlalchemy import inspect as sa_inspect

        if relation in sa_inspect(value).unloaded:
            return None
    except Exception:
        return None
    related = getattr(value, relation)
    name = getattr(related, "name", None)
    if not isinstance(name, str):
        return None
    cleaned = name.strip()
    return cleaned or None


class VersionedRead(APIModel):
    model_config = ConfigDict(from_attributes=True)

    id: uuid.UUID
    created_at: datetime
    updated_at: datetime
    deleted_at: datetime | None = None
    version: int

    @field_serializer("created_at", "updated_at", "deleted_at")
    def serialize_timestamps(self, value: datetime | None) -> str | None:
        if value is None:
            return None
        return serialize_datetime(value)
