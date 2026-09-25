from decimal import Decimal
from functools import lru_cache
from urllib.parse import urlparse

from pydantic import field_validator
from pydantic_settings import BaseSettings, SettingsConfigDict
from sqlalchemy.engine.url import make_url


def normalize_database_url(value: str) -> str:
    url = (value or "").strip().strip('"').strip("'")
    if not url:
        raise ValueError("DATABASE_URL is empty.")
    if "${{" in url or url.startswith("${"):
        raise ValueError(
            "DATABASE_URL was not interpolated. On Railway, add it with "
            "Add Variable → Variable Reference → Postgres → DATABASE_PRIVATE_URL. "
            "Do not leave the raw ${{Postgres.DATABASE_PRIVATE_URL}} text unresolved."
        )

    if url.startswith("postgres://"):
        url = "postgresql://" + url[len("postgres://") :]
    if url.startswith("postgresql://") and "+asyncpg" not in url:
        url = url.replace("postgresql://", "postgresql+asyncpg://", 1)
    if "sslmode=" in url and "ssl=" not in url:
        url = url.replace("sslmode=require", "ssl=require").replace(
            "sslmode=prefer", "ssl=require"
        )

    try:
        parsed = make_url(url)
    except Exception as exc:
        host = url.split("@")[-1] if "@" in url else "unparseable"
        raise ValueError(f"DATABASE_URL is not a valid Postgres URL ({host}).") from exc
    if parsed.drivername not in {"postgresql+asyncpg", "postgresql"}:
        raise ValueError("DATABASE_URL must be a Postgres URL.")
    return url


def database_target(url: str) -> str:
    parsed = urlparse(url)
    host = parsed.hostname or "?"
    port = f":{parsed.port}" if parsed.port else ""
    db = (parsed.path or "/").lstrip("/") or "?"
    return f"{parsed.scheme}://{host}{port}/{db}"


class Settings(BaseSettings):
    model_config = SettingsConfigDict(
        env_file=".env",
        env_file_encoding="utf-8",
        extra="ignore",
        case_sensitive=True,
    )

    APP_NAME: str = "Nabi Dental Clinic API"
    APP_ENV: str = "development"
    DEBUG: bool = False
    API_V1_PREFIX: str = "/api/v1"
    LOG_LEVEL: str = "INFO"

    DATABASE_URL: str = "postgresql+asyncpg://postgres:postgres@localhost:5433/nabi_dental"
    PORT: int = 8000

    JWT_SECRET_KEY: str = "change-me"
    JWT_ALGORITHM: str = "HS256"
    ACCESS_TOKEN_MINUTES: int = 20
    REFRESH_TOKEN_DAYS: int = 30

    CORS_ORIGINS: str = ""
    CORS_ORIGIN_REGEX: str = ""

    DEFAULT_CLINIC_NAME: str = "Nabi Dental Clinic"
    DEFAULT_CURRENCY: str = "PKR"
    DEFAULT_TIMEZONE: str = "Asia/Karachi"
    DEFAULT_HOME_BUDGET: Decimal = Decimal("30000.00")

    OWNER_EMAIL: str = "owner@example.com"
    OWNER_PASSWORD: str = "ChangeMeNow!1"
    OWNER_FULL_NAME: str = "Clinic Owner"

    MAX_FUTURE_DAYS: int = 30
    MAX_RANGE_YEARS: int = 10
    LOGIN_RATE_LIMIT: int = 5
    LOGIN_RATE_WINDOW_SECONDS: int = 60

    FORWARDED_ALLOW_IPS: str = ""
    BATCH_MAX_ITEMS: int = 50
    SYNC_PUSH_MAX_CHANGES: int = 100
    SYNC_PULL_MAX_LIMIT: int = 500

    UPLOAD_DIR: str = "uploads"
    AVATAR_MAX_BYTES: int = 2_000_000
    AVATAR_MIN_PX: int = 64
    AVATAR_MAX_PX: int = 4096
    XRAY_MAX_BYTES: int = 5_000_000
    XRAY_MIN_PX: int = 64
    XRAY_MAX_PX: int = 8192

    @field_validator("DEFAULT_CURRENCY")
    @classmethod
    def currency_upper(cls, value: str) -> str:
        return value.strip().upper()

    @field_validator("DATABASE_URL")
    @classmethod
    def async_database_url(cls, value: str) -> str:
        return normalize_database_url(value)

    @property
    def cors_origin_list(self) -> list[str]:
        return [item.strip() for item in self.CORS_ORIGINS.split(",") if item.strip()]

    @property
    def cors_origin_regex(self) -> str | None:
        if self.CORS_ORIGIN_REGEX.strip():
            return self.CORS_ORIGIN_REGEX.strip()
        if not self.is_production:
            return r"https?://(localhost|127\.0\.0\.1)(:\d+)?"
        return None

    @property
    def is_production(self) -> bool:
        return self.APP_ENV == "production"


@lru_cache
def get_settings() -> Settings:
    return Settings()


settings = get_settings()
