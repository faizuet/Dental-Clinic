from fastapi import APIRouter, Request, Response, status

from app.api.deps import CurrentUser, DBSession
from app.schemas.auth import (
    ChangePasswordRequest,
    LoginRequest,
    LoginResponse,
    LogoutRequest,
    MeResponse,
    RefreshRequest,
    TokenRefreshResponse,
)
from app.services.auth_service import AuthService

router = APIRouter(prefix="/auth", tags=["auth"])


@router.post("/login", response_model=LoginResponse)
async def login(payload: LoginRequest, request: Request, session: DBSession) -> LoginResponse:
    return await AuthService(session).login(payload, request)


@router.post("/refresh", response_model=TokenRefreshResponse)
async def refresh(payload: RefreshRequest, request: Request, session: DBSession) -> TokenRefreshResponse:
    return await AuthService(session).refresh(payload, request)


@router.post("/logout", status_code=status.HTTP_204_NO_CONTENT)
async def logout(payload: LogoutRequest, session: DBSession) -> Response:
    await AuthService(session).logout(payload.refresh_token)
    return Response(status_code=status.HTTP_204_NO_CONTENT)


@router.post("/logout-all", status_code=status.HTTP_204_NO_CONTENT)
async def logout_all(user: CurrentUser, session: DBSession) -> Response:
    await AuthService(session).logout_all(user)
    return Response(status_code=status.HTTP_204_NO_CONTENT)


@router.get("/me", response_model=MeResponse)
async def me(user: CurrentUser, session: DBSession) -> MeResponse:
    return await AuthService(session).me(user)


@router.post("/change-password", status_code=status.HTTP_204_NO_CONTENT)
async def change_password(payload: ChangePasswordRequest, user: CurrentUser, session: DBSession) -> Response:
    await AuthService(session).change_password(user, payload)
    return Response(status_code=status.HTTP_204_NO_CONTENT)
