from typing import Any

from app.core.constants import ErrorCode


class AppError(Exception):
    def __init__(
        self,
        code: str,
        message: str,
        status_code: int = 400,
        details: list[dict[str, Any]] | None = None,
        extra: dict[str, Any] | None = None,
    ) -> None:
        self.code = code
        self.message = message
        self.status_code = status_code
        self.details = details or []
        self.extra = extra or {}
        super().__init__(message)


class UnauthorizedError(AppError):
    def __init__(self, message: str = "Authentication is required.") -> None:
        super().__init__(ErrorCode.UNAUTHORIZED, message, status_code=401)


class ForbiddenError(AppError):
    def __init__(self, message: str = "You do not have access to this resource.") -> None:
        super().__init__(ErrorCode.FORBIDDEN, message, status_code=403)


class NotFoundError(AppError):
    def __init__(self, message: str = "The requested resource was not found.") -> None:
        super().__init__(ErrorCode.NOT_FOUND, message, status_code=404)


class ConflictError(AppError):
    def __init__(
        self,
        message: str,
        code: str = ErrorCode.CONFLICT,
        details: list[dict[str, Any]] | None = None,
        extra: dict[str, Any] | None = None,
    ) -> None:
        super().__init__(code, message, status_code=409, details=details, extra=extra)


class VersionConflictError(ConflictError):
    def __init__(self, message: str = "The record was updated by another change.", record: Any = None) -> None:
        extra = {"record": record} if record is not None else None
        super().__init__(message, code=ErrorCode.VERSION_CONFLICT, extra=extra)


class RateLimitError(AppError):
    def __init__(self, message: str = "Too many requests. Please try again later.", retry_after: int = 60) -> None:
        super().__init__(
            ErrorCode.RATE_LIMITED,
            message,
            status_code=429,
            extra={"retry_after": retry_after},
        )


class ValidationAppError(AppError):
    def __init__(self, message: str, details: list[dict[str, Any]] | None = None) -> None:
        super().__init__(ErrorCode.VALIDATION_ERROR, message, status_code=400, details=details)
