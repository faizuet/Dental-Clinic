import uuid
from datetime import datetime

from pydantic import ConfigDict, field_serializer

from app.utils.dates import serialize_datetime
from app.utils.pagination import APIModel


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
