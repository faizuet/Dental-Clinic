import json
import logging
import re
import sys
from datetime import datetime, timezone

from app.core.config import settings

_URL_USERINFO = re.compile(r"([a-z][a-z0-9+.-]*://[^/\s:@]+):[^@\s/]+@", re.IGNORECASE)
_PGPASSWORD = re.compile(r"(?i)(PGPASSWORD=)\S+")


def redact_secrets(value: str) -> str:
    text = _URL_USERINFO.sub(r"\1:***@", value)
    return _PGPASSWORD.sub(r"\1***", text)


class JsonFormatter(logging.Formatter):
    def format(self, record: logging.LogRecord) -> str:
        payload = {
            "timestamp": datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ"),
            "level": record.levelname,
            "logger": record.name,
            "message": redact_secrets(record.getMessage()),
        }
        for key in (
            "request_id",
            "method",
            "path",
            "status_code",
            "duration_ms",
            "user_id",
            "error_code",
        ):
            value = getattr(record, key, None)
            if value is not None:
                payload[key] = value
        if record.exc_info:
            payload["exception"] = redact_secrets(self.formatException(record.exc_info))
        return json.dumps(payload, default=str)


class TextFormatter(logging.Formatter):
    def format(self, record: logging.LogRecord) -> str:
        base = f"{record.levelname} {record.name}: {redact_secrets(record.getMessage())}"
        extras = []
        for key in ("request_id", "method", "path", "status_code", "duration_ms", "user_id"):
            value = getattr(record, key, None)
            if value is not None:
                extras.append(f"{key}={value}")
        if extras:
            base = f"{base} ({', '.join(extras)})"
        if record.exc_info:
            base = f"{base}\n{redact_secrets(self.formatException(record.exc_info))}"
        return base


def configure_logging() -> None:
    handler = logging.StreamHandler(sys.stdout)
    if settings.is_production:
        handler.setFormatter(JsonFormatter())
    else:
        handler.setFormatter(TextFormatter())

    root = logging.getLogger()
    root.handlers.clear()
    root.addHandler(handler)
    root.setLevel(getattr(logging, settings.LOG_LEVEL.upper(), logging.INFO))

    logging.getLogger("uvicorn.access").disabled = True


logger = logging.getLogger("nabi")
