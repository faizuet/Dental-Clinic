from io import BytesIO
from pathlib import Path
import uuid

from fastapi import UploadFile
from PIL import Image, UnidentifiedImageError
from sqlalchemy.ext.asyncio import AsyncSession

from app.core.config import settings
from app.core.exceptions import NotFoundError, ValidationAppError
from app.models import TreatmentAttachment, TreatmentTransaction, User
from app.repositories.treatments import TreatmentAttachmentRepository

ALLOWED_TYPES = {
    "image/jpeg": "JPEG",
    "image/jpg": "JPEG",
    "image/png": "PNG",
    "image/webp": "WEBP",
}
ALLOWED_NAMES = {".jpg", ".jpeg", ".png", ".webp"}
ALLOWED_LABELS = {"before", "working", "after", "other"}
MAX_ATTACHMENTS = 8


class XrayService:
    def __init__(self, session: AsyncSession) -> None:
        self.session = session
        self.attachments = TreatmentAttachmentRepository(session)

    def _dir(self, clinic_id: uuid.UUID, transaction_id: uuid.UUID) -> Path:
        path = Path(settings.UPLOAD_DIR) / "xrays" / str(clinic_id) / str(transaction_id)
        path.mkdir(parents=True, exist_ok=True)
        return path

    async def save(
        self,
        user: User,
        record: TreatmentTransaction,
        upload: UploadFile,
        *,
        label: str | None = None,
    ) -> TreatmentAttachment:
        if record.clinic_id != user.clinic_id:
            raise NotFoundError("Treatment record was not found.")
        if await self.attachments.live_count(record.id) >= MAX_ATTACHMENTS:
            raise ValidationAppError("A treatment can have at most 8 X-ray images.")

        kind = (label or "other").strip().lower()
        if kind not in ALLOWED_LABELS:
            raise ValidationAppError("Use before, working, after, or other for the X-ray label.")

        content_type = (upload.content_type or "").lower()
        suffix = Path(upload.filename or "").suffix.lower()
        if content_type not in ALLOWED_TYPES and suffix not in ALLOWED_NAMES:
            raise ValidationAppError("Use a JPG, PNG, or WebP image.")

        data = await upload.read()
        if not data:
            raise ValidationAppError("The selected file is empty.")
        if len(data) > settings.XRAY_MAX_BYTES:
            raise ValidationAppError("The X-ray must be 5 MB or smaller.")

        try:
            image = Image.open(BytesIO(data))
            image.load()
        except (UnidentifiedImageError, OSError, ValueError) as exc:
            raise ValidationAppError("That file is not a valid image.") from exc

        width, height = image.size
        if width < settings.XRAY_MIN_PX or height < settings.XRAY_MIN_PX:
            raise ValidationAppError("The image is too small. Use at least 64×64 pixels.")
        if width > settings.XRAY_MAX_PX or height > settings.XRAY_MAX_PX:
            raise ValidationAppError("The image is too large. Use at most 8192×8192 pixels.")

        image = image.convert("RGB")
        longest = max(image.size)
        if longest > 2048:
            ratio = 2048 / longest
            image = image.resize((int(image.width * ratio), int(image.height * ratio)), Image.Resampling.LANCZOS)

        dest = self._dir(record.clinic_id, record.id) / f"{uuid.uuid4()}.jpg"
        image.save(dest, format="JPEG", quality=88, optimize=True)
        attachment = TreatmentAttachment(
            clinic_id=record.clinic_id,
            transaction_id=record.id,
            stored_path=str(dest),
            original_name=(upload.filename or "")[:255] or None,
            label=kind,
            content_type="image/jpeg",
            byte_size=dest.stat().st_size,
        )
        self.session.add(attachment)
        await self.session.flush()
        await self.session.refresh(attachment)
        return attachment

    def path_for(self, user: User, attachment: TreatmentAttachment) -> Path:
        if attachment.clinic_id != user.clinic_id or attachment.deleted_at is not None:
            raise NotFoundError("X-ray was not found.")
        path = Path(attachment.stored_path)
        if not path.is_file():
            raise NotFoundError("X-ray was not found.")
        return path

    async def delete(self, user: User, attachment: TreatmentAttachment) -> None:
        if attachment.clinic_id != user.clinic_id:
            raise NotFoundError("X-ray was not found.")
        path = Path(attachment.stored_path)
        if path.is_file():
            path.unlink()
        attachment.soft_delete()
        await self.session.flush()
