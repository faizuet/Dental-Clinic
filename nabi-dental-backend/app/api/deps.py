import uuid
from typing import Annotated

from fastapi import Depends, Request
from fastapi.security import HTTPAuthorizationCredentials, HTTPBearer
from sqlalchemy.ext.asyncio import AsyncSession

from app.core.exceptions import UnauthorizedError
from app.core.security import decode_access_token
from app.db.session import get_db
from app.models import User
from app.repositories.users import UserRepository

bearer_scheme = HTTPBearer(auto_error=False)


async def get_current_user(
    request: Request,
    session: Annotated[AsyncSession, Depends(get_db)],
    credentials: Annotated[HTTPAuthorizationCredentials | None, Depends(bearer_scheme)],
) -> User:
    if credentials is None or credentials.scheme.lower() != "bearer":
        raise UnauthorizedError("Authentication is required.")
    payload = decode_access_token(credentials.credentials)
    try:
        user_id = uuid.UUID(payload["sub"])
    except (KeyError, ValueError) as exc:
        raise UnauthorizedError("The access token is invalid or expired.") from exc
    user = await UserRepository(session).get_by_id(user_id)
    if user is None or not user.is_active:
        raise UnauthorizedError("The access token is invalid or expired.")
    request.state.user_id = user.id
    return user


async def get_current_user_detached(
    credentials: Annotated[HTTPAuthorizationCredentials | None, Depends(bearer_scheme)],
) -> User:
    """Authenticate without holding a database session (used by restore)."""
    from app.db.session import SessionLocal

    if credentials is None or credentials.scheme.lower() != "bearer":
        raise UnauthorizedError("Authentication is required.")
    payload = decode_access_token(credentials.credentials)
    try:
        user_id = uuid.UUID(payload["sub"])
    except (KeyError, ValueError) as exc:
        raise UnauthorizedError("The access token is invalid or expired.") from exc
    async with SessionLocal() as session:
        user = await UserRepository(session).get_by_id(user_id)
        if user is None or not user.is_active:
            raise UnauthorizedError("The access token is invalid or expired.")
        session.expunge(user)
        return user


DBSession = Annotated[AsyncSession, Depends(get_db)]
CurrentUser = Annotated[User, Depends(get_current_user)]
DetachedUser = Annotated[User, Depends(get_current_user_detached)]
