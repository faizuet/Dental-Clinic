import time
from collections import defaultdict

from app.core.config import settings
from app.core.exceptions import RateLimitError


class InMemoryRateLimiter:
    def __init__(self) -> None:
        self._hits: dict[str, list[float]] = defaultdict(list)

    def hit(self, key: str, *, limit: int | None = None, window_seconds: int | None = None) -> None:
        limit = limit if limit is not None else settings.LOGIN_RATE_LIMIT
        window_seconds = window_seconds if window_seconds is not None else settings.LOGIN_RATE_WINDOW_SECONDS
        now = time.monotonic()
        recent = [stamp for stamp in self._hits[key] if now - stamp < window_seconds]
        if len(recent) >= limit:
            self._hits[key] = recent
            raise RateLimitError(retry_after=window_seconds)
        recent.append(now)
        self._hits[key] = recent


rate_limiter = InMemoryRateLimiter()
