from __future__ import annotations

import os
import secrets
from pathlib import Path

from app.core.config import settings
from app.core.logging import logger
from app.core.security import verify_password

INSECURE_JWT_SECRETS = frozenset(
    {
        "change-me",
        "change-me-to-a-long-random-secret",
        "secret",
        "changeme",
    }
)
EXAMPLE_OWNER_PASSWORDS = frozenset({"ChangeMeNow!1"})
MIN_JWT_SECRET_LENGTH = 32


def env_file_path() -> Path:
    return Path(os.environ.get("ENV_FILE", ".env"))


def is_insecure_jwt(secret: str | None) -> bool:
    value = (secret or "").strip()
    if not value or len(value) < MIN_JWT_SECRET_LENGTH:
        return True
    return value.lower() in INSECURE_JWT_SECRETS


def is_example_owner_password(password: str | None) -> bool:
    return (password or "") in EXAMPLE_OWNER_PASSWORDS


def uses_example_owner_password(password_hash: str | None) -> bool:
    if not password_hash:
        return False
    return any(verify_password(candidate, password_hash) for candidate in EXAMPLE_OWNER_PASSWORDS)


def read_env_value(path: Path, key: str) -> str | None:
    if not path.is_file():
        return None
    prefix = f"{key}="
    for raw_line in path.read_text(encoding="utf-8").splitlines():
        line = raw_line.strip()
        if not line or line.startswith("#"):
            continue
        if line.startswith("export "):
            line = line[7:].strip()
        if not line.startswith(prefix):
            continue
        value = line.split("=", 1)[1].strip()
        if len(value) >= 2 and value[0] == value[-1] and value[0] in {"'", '"'}:
            value = value[1:-1]
        return value
    return None


def upsert_env_value(path: Path, key: str, value: str) -> None:
    lines: list[str] = []
    if path.is_file():
        lines = path.read_text(encoding="utf-8").splitlines()
    prefix = f"{key}="
    replaced = False
    out: list[str] = []
    for line in lines:
        stripped = line.strip()
        comparable = stripped[7:].strip() if stripped.startswith("export ") else stripped
        if comparable.startswith(prefix) and not stripped.startswith("#"):
            out.append(f"{key}={value}")
            replaced = True
        else:
            out.append(line)
    if not replaced:
        if out and out[-1] != "":
            out.append("")
        out.append(f"{key}={value}")
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text("\n".join(out) + "\n", encoding="utf-8")


def apply_jwt_secret(secret: str) -> None:
    os.environ["JWT_SECRET_KEY"] = secret
    settings.JWT_SECRET_KEY = secret


def ensure_jwt_secret(*, env_path: Path | None = None, persist: bool = True) -> str:
    path = env_path or env_file_path()
    file_secret = read_env_value(path, "JWT_SECRET_KEY")
    if file_secret and not is_insecure_jwt(file_secret):
        apply_jwt_secret(file_secret)
        return file_secret
    current = os.environ.get("JWT_SECRET_KEY") or settings.JWT_SECRET_KEY
    if not is_insecure_jwt(current):
        return current
    generated = secrets.token_urlsafe(48)
    if persist:
        upsert_env_value(path, "JWT_SECRET_KEY", generated)
        logger.warning("Replaced the example JWT secret. Sign in again. The new key is stored in %s", path)
    apply_jwt_secret(generated)
    return generated
