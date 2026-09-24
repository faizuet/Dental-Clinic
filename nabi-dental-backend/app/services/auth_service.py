from datetime import datetime, timedelta, timezone

from fastapi import Request
from sqlalchemy.ext.asyncio import AsyncSession

from app.core.config import settings
from app.core.constants import ErrorCode
from app.core.exceptions import AppError, UnauthorizedError, ValidationAppError
from app.core.rate_limit import rate_limiter
from app.core.security import (
    create_access_token,
    generate_refresh_token,
    hash_password,
    hash_refresh_token,
    verify_password,
)
from app.models import RefreshToken, User
from app.models.mixins import utc_now
from app.repositories.users import RefreshTokenRepository, UserRepository
from app.schemas.auth import (
    ChangePasswordRequest,
    ClinicPublic,
    LoginRequest,
    LoginResponse,
    MeResponse,
    RefreshRequest,
    TokenRefreshResponse,
    UserPublic,
)


class AuthService:
    def __init__(self, session: AsyncSession) -> None:
        self.session = session
        self.users = UserRepository(session)
        self.refresh_tokens = RefreshTokenRepository(session)

    async def login(self, payload: LoginRequest, request: Request) -> LoginResponse:
        email = payload.email
        client_ip = request.client.host if request.client else "unknown"
        rate_limiter.hit(f"login:ip:{client_ip}")
        rate_limiter.hit(f"login:email:{email}")

        user = await self.users.get_by_email(email)
        if user is None or not verify_password(payload.password, user.password_hash):
            raise UnauthorizedError("Email or password is incorrect.")
        if not user.is_active:
            raise AppError(ErrorCode.INACTIVE_ACCOUNT, "This account is inactive.", status_code=401)

        access_token, refresh_token = await self._issue_tokens(
            user,
            device_id=payload.device_id,
            device_name=payload.device_name,
        )
        user.last_login_at = utc_now()
        await self.session.flush()
        return LoginResponse(
            access_token=access_token,
            refresh_token=refresh_token,
            expires_in=settings.ACCESS_TOKEN_MINUTES * 60,
            user=UserPublic.model_validate(user),
            clinic=ClinicPublic.model_validate(user.clinic),
        )

    async def refresh(self, payload: RefreshRequest, request: Request) -> TokenRefreshResponse:
        client_ip = request.client.host if request.client else "unknown"
        rate_limiter.hit(f"refresh:ip:{client_ip}")

        token_hash = hash_refresh_token(payload.refresh_token)
        stored = await self.refresh_tokens.get_by_hash(token_hash)
        now = utc_now()
        if stored is None:
            raise UnauthorizedError("The refresh token is invalid.")
        if stored.revoked_at is not None:
            await self._revoke_all(stored.user_id)
            raise UnauthorizedError("The refresh token is invalid.")
        if stored.expires_at <= now:
            raise UnauthorizedError("The refresh token is invalid or expired.")
        if payload.device_id and payload.device_id != stored.device_id:
            raise UnauthorizedError("The refresh token is invalid.")
        if not stored.user.is_active:
            raise AppError(ErrorCode.INACTIVE_ACCOUNT, "This account is inactive.", status_code=401)

        access_token, refresh_token = await self._issue_tokens(
            stored.user,
            device_id=stored.device_id,
            device_name=stored.device_name,
            replacing=stored,
        )
        return TokenRefreshResponse(
            access_token=access_token,
            refresh_token=refresh_token,
            expires_in=settings.ACCESS_TOKEN_MINUTES * 60,
        )

    async def logout(self, refresh_token: str) -> None:
        stored = await self.refresh_tokens.get_by_hash(hash_refresh_token(refresh_token))
        if stored and stored.revoked_at is None:
            stored.revoked_at = utc_now()
            await self.session.flush()

    async def logout_all(self, user: User) -> None:
        await self._revoke_all(user.id)

    async def change_password(self, user: User, payload: ChangePasswordRequest) -> None:
        if not verify_password(payload.current_password, user.password_hash):
            raise UnauthorizedError("The current password is incorrect.")
        if payload.new_password == payload.current_password:
            raise ValidationAppError(
                "The new password must be different from the current password.",
                details=[{"field": "new_password", "message": "The new password must be different."}],
            )
        user.password_hash = hash_password(payload.new_password)
        user.updated_at = utc_now()
        await self._revoke_all(user.id)

    async def me(self, user: User) -> MeResponse:
        if user.clinic is None:
            user = await self.users.get_by_id(user.id)  # type: ignore[assignment]
        return MeResponse(user=UserPublic.model_validate(user), clinic=ClinicPublic.model_validate(user.clinic))

    async def _issue_tokens(
        self,
        user: User,
        *,
        device_id: str,
        device_name: str | None,
        replacing: RefreshToken | None = None,
    ) -> tuple[str, str]:
        access_token = create_access_token(user_id=user.id, role=user.role, clinic_id=user.clinic_id)
        raw_refresh = generate_refresh_token()
        record = RefreshToken(
            user_id=user.id,
            token_hash=hash_refresh_token(raw_refresh),
            device_id=device_id,
            device_name=device_name,
            expires_at=datetime.now(timezone.utc) + timedelta(days=settings.REFRESH_TOKEN_DAYS),
        )
        self.session.add(record)
        await self.session.flush()
        if replacing is not None:
            replacing.revoked_at = utc_now()
            replacing.replaced_by_token_id = record.id
            await self.session.flush()
        return access_token, raw_refresh

    async def _revoke_all(self, user_id) -> None:
        now = utc_now()
        tokens = await self.refresh_tokens.list_active_for_user(user_id)
        for token in tokens:
            token.revoked_at = now
        await self.session.flush()
