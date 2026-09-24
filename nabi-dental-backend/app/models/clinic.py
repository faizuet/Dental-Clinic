from sqlalchemy import CHAR, String, text
from sqlalchemy.orm import Mapped, mapped_column, relationship

from app.db.base import Base
from app.models.mixins import TimestampMixin, UUIDPrimaryKeyMixin


class Clinic(UUIDPrimaryKeyMixin, TimestampMixin, Base):
    __tablename__ = "clinics"

    name: Mapped[str] = mapped_column(String(150), nullable=False)
    currency: Mapped[str] = mapped_column(CHAR(3), nullable=False, server_default=text("'PKR'"))
    timezone: Mapped[str] = mapped_column(String(64), nullable=False, server_default=text("'Asia/Karachi'"))

    users: Mapped[list["User"]] = relationship(back_populates="clinic")
