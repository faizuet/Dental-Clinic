from collections.abc import Mapping
from typing import Any

from fastapi import FastAPI, Request
from fastapi.exceptions import RequestValidationError
from fastapi.middleware.cors import CORSMiddleware
from fastapi.responses import JSONResponse
from sqlalchemy import text
from sqlalchemy.exc import IntegrityError
from starlette.exceptions import HTTPException as StarletteHTTPException

from app.api.v1.router import v1_routers
from app.core.config import settings
from app.core.constants import ErrorCode
from app.core.exceptions import AppError
from app.core.logging import configure_logging, logger
from app.core.middleware import RequestContextMiddleware
from app.db.session import engine

configure_logging()

app = FastAPI(
    title=settings.APP_NAME,
    version="1.0.0",
)

app.add_middleware(RequestContextMiddleware)
if settings.cors_origin_list or settings.cors_origin_regex:
    app.add_middleware(
        CORSMiddleware,
        allow_origins=settings.cors_origin_list,
        allow_origin_regex=settings.cors_origin_regex,
        allow_credentials=True,
        allow_methods=["*"],
        allow_headers=["*"],
    )

for router in v1_routers:
    app.include_router(router, prefix=settings.API_V1_PREFIX)


def _request_id(request: Request) -> str:
    return getattr(request.state, "request_id", "unknown")


def error_body(
    *,
    code: str,
    message: str,
    request_id: str,
    details: list[dict[str, Any]] | None = None,
) -> dict[str, Any]:
    return {
        "error": {
            "code": code,
            "message": message,
            "details": details or [],
            "request_id": request_id,
        }
    }


@app.exception_handler(AppError)
async def app_error_handler(request: Request, exc: AppError) -> JSONResponse:
    headers: dict[str, str] = {"X-Request-ID": _request_id(request)}
    if exc.status_code == 429:
        headers["Retry-After"] = str(exc.extra.get("retry_after", 60))
    logger.warning(
        exc.message,
        extra={
            "request_id": _request_id(request),
            "error_code": exc.code,
            "method": request.method,
            "path": request.url.path,
            "status_code": exc.status_code,
        },
    )
    return JSONResponse(
        status_code=exc.status_code,
        content=error_body(
            code=exc.code,
            message=exc.message,
            request_id=_request_id(request),
            details=exc.details,
        ),
        headers=headers,
    )


@app.exception_handler(RequestValidationError)
async def validation_handler(request: Request, exc: RequestValidationError) -> JSONResponse:
    details = []
    for error in exc.errors():
        loc = [str(part) for part in error.get("loc", []) if part not in {"body", "query", "path"}]
        details.append({"field": ".".join(loc) or "request", "message": error.get("msg", "Invalid value.")})
    return JSONResponse(
        status_code=422,
        content=error_body(
            code=ErrorCode.VALIDATION_ERROR,
            message="The request contains invalid values.",
            request_id=_request_id(request),
            details=details,
        ),
        headers={"X-Request-ID": _request_id(request)},
    )


@app.exception_handler(StarletteHTTPException)
async def http_exception_handler(request: Request, exc: StarletteHTTPException) -> JSONResponse:
    code = ErrorCode.INTERNAL_ERROR
    if exc.status_code == 401:
        code = ErrorCode.UNAUTHORIZED
    elif exc.status_code == 403:
        code = ErrorCode.FORBIDDEN
    elif exc.status_code == 404:
        code = ErrorCode.NOT_FOUND
    elif exc.status_code == 429:
        code = ErrorCode.RATE_LIMITED
    return JSONResponse(
        status_code=exc.status_code,
        content=error_body(
            code=code,
            message=str(exc.detail),
            request_id=_request_id(request),
        ),
        headers={"X-Request-ID": _request_id(request)},
    )


@app.exception_handler(IntegrityError)
async def integrity_handler(request: Request, exc: IntegrityError) -> JSONResponse:
    logger.warning("Integrity error", extra={"request_id": _request_id(request), "error_code": ErrorCode.CONFLICT})
    return JSONResponse(
        status_code=409,
        content=error_body(
            code=ErrorCode.CONFLICT,
            message="The request conflicts with an existing record.",
            request_id=_request_id(request),
        ),
        headers={"X-Request-ID": _request_id(request)},
    )


@app.exception_handler(Exception)
async def unhandled_handler(request: Request, exc: Exception) -> JSONResponse:
    logger.exception("Unhandled server error", extra={"request_id": _request_id(request)})
    return JSONResponse(
        status_code=500,
        content=error_body(
            code=ErrorCode.INTERNAL_ERROR,
            message="An unexpected error occurred.",
            request_id=_request_id(request),
        ),
        headers={"X-Request-ID": _request_id(request)},
    )


@app.get("/")
async def root() -> Mapping[str, str]:
    return {
        "name": settings.APP_NAME,
        "docs": "/docs",
        "health": "/health",
        "api": settings.API_V1_PREFIX,
    }


@app.get("/health")
async def health() -> Mapping[str, str]:
    return {"status": "healthy"}


@app.get("/ready")
async def ready() -> Mapping[str, str]:
    try:
        async with engine.connect() as connection:
            await connection.execute(text("SELECT 1"))
    except Exception as exc:
        logger.exception("Readiness check failed")
        raise AppError(
            ErrorCode.DEPENDENCY_UNAVAILABLE,
            "The service is not ready.",
            status_code=503,
        ) from exc
    return {"status": "ready"}
