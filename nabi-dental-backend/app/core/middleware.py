import uuid
from time import perf_counter

from starlette.types import ASGIApp, Receive, Scope, Send

from app.core.logging import logger


class RequestContextMiddleware:
    def __init__(self, app: ASGIApp) -> None:
        self.app = app

    async def __call__(self, scope: Scope, receive: Receive, send: Send) -> None:
        if scope["type"] != "http":
            await self.app(scope, receive, send)
            return

        headers = {key.decode("latin-1").lower(): value.decode("latin-1") for key, value in scope.get("headers", [])}
        request_id = headers.get("x-request-id") or str(uuid.uuid4())
        state = scope.get("state")
        if state is None:
            scope["state"] = {"request_id": request_id}
        elif isinstance(state, dict):
            state["request_id"] = request_id
        else:
            setattr(state, "request_id", request_id)
        start = perf_counter()
        status_code = 500

        async def send_wrapper(message: dict) -> None:
            nonlocal status_code
            if message["type"] == "http.response.start":
                status_code = message["status"]
                raw_headers = list(message.get("headers", []))
                raw_headers.append((b"x-request-id", request_id.encode("latin-1")))
                message = {**message, "headers": raw_headers}
            await send(message)

        try:
            await self.app(scope, receive, send_wrapper)
        except Exception:
            duration_ms = round((perf_counter() - start) * 1000, 2)
            logger.exception(
                "Unhandled exception",
                extra={
                    "request_id": request_id,
                    "method": scope.get("method"),
                    "path": scope.get("path"),
                    "duration_ms": duration_ms,
                },
            )
            raise
        duration_ms = round((perf_counter() - start) * 1000, 2)
        user_id = None
        state = scope.get("state")
        if isinstance(state, dict):
            user_id = state.get("user_id")
        else:
            user_id = getattr(state, "user_id", None)
        logger.info(
            "request completed",
            extra={
                "request_id": request_id,
                "method": scope.get("method"),
                "path": scope.get("path"),
                "status_code": status_code,
                "duration_ms": duration_ms,
                "user_id": str(user_id) if user_id else None,
            },
        )
