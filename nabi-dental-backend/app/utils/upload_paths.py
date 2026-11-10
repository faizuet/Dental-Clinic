from pathlib import Path

from app.core.exceptions import ValidationAppError


def ensure_upload_dir(path: Path) -> Path:
    try:
        path.mkdir(parents=True, exist_ok=True)
    except OSError as exc:
        raise ValidationAppError(
            "The clinic could not save this image on this computer. Check the local uploads folder and try again."
        ) from exc
    return path
