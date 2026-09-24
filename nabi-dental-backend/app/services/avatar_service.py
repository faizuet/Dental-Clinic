from io import BytesIO
from pathlib import Path

from fastapi import UploadFile
from PIL import Image, UnidentifiedImageError
from sqlalchemy.ext.asyncio import AsyncSession

from app.core.config import settings
from app.core.exceptions import NotFoundError, ValidationAppError
from app.models import User
from app.models.mixins import utc_now

ALLOWED_TYPES = {
    "image/jpeg": "JPEG",
    "image/jpg": "JPEG",
    "image/png": "PNG",
    "image/webp": "WEBP",
}
ALLOWED_NAMES = {".jpg", ".jpeg", ".png", ".webp"}


class AvatarService:
    def __init__(self, session: AsyncSession) -> None:
        self.session = session

    def _dir(self) -> Path:
        path = Path(settings.UPLOAD_DIR) / "avatars"
        path.mkdir(parents=True, exist_ok=True)
        return path

    def _file_for(self, user: User) -> Path:
        return self._dir() / f"{user.id}.jpg"

    async def save(self, user: User, upload: UploadFile) -> None:
        content_type = (upload.content_type or "").lower()
        suffix = Path(upload.filename or "").suffix.lower()
        if content_type not in ALLOWED_TYPES and suffix not in ALLOWED_NAMES:
            raise ValidationAppError("Use a JPG, PNG, or WebP image.")

        data = await upload.read()
        if not data:
            raise ValidationAppError("The selected file is empty.")
        if len(data) > settings.AVATAR_MAX_BYTES:
            raise ValidationAppError("The image must be 2 MB or smaller.")

        try:
            image = Image.open(BytesIO(data))
            image.load()
        except (UnidentifiedImageError, OSError, ValueError) as exc:
            raise ValidationAppError("That file is not a valid image.") from exc

        width, height = image.size
        if width < settings.AVATAR_MIN_PX or height < settings.AVATAR_MIN_PX:
            raise ValidationAppError("The image is too small. Use at least 64×64 pixels.")
        if width > settings.AVATAR_MAX_PX or height > settings.AVATAR_MAX_PX:
            raise ValidationAppError("The image is too large. Use at most 4096×4096 pixels.")

        image = image.convert("RGB")
        longest = max(image.size)
        if longest > 1024:
            ratio = 1024 / longest
            image = image.resize((int(image.width * ratio), int(image.height * ratio)), Image.Resampling.LANCZOS)

        dest = self._file_for(user)
        image.save(dest, format="JPEG", quality=85, optimize=True)
        user.avatar_path = str(dest)
        user.updated_at = utc_now()
        await self.session.flush()

    def path_for(self, user: User) -> Path:
        if not user.avatar_path:
            raise NotFoundError("No profile photo yet.")
        path = Path(user.avatar_path)
        if not path.is_file():
            raise NotFoundError("No profile photo yet.")
        return path

    async def delete(self, user: User) -> None:
        if user.avatar_path:
            path = Path(user.avatar_path)
            if path.is_file():
                path.unlink()
        user.avatar_path = None
        user.updated_at = utc_now()
        await self.session.flush()
