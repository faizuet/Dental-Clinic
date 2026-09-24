import pytest

from app.core.config import settings


@pytest.mark.asyncio
async def test_login_success(client):
    response = await client.post(
        "/api/v1/auth/login",
        json={
            "email": settings.OWNER_EMAIL.upper(),
            "password": settings.OWNER_PASSWORD,
            "device_id": "device-1",
            "device_name": "Phone",
        },
    )
    assert response.status_code == 200
    body = response.json()
    assert body["token_type"] == "bearer"
    assert body["expires_in"] == settings.ACCESS_TOKEN_MINUTES * 60
    assert body["user"]["email"] == settings.OWNER_EMAIL.lower()
    assert body["clinic"]["name"] == settings.DEFAULT_CLINIC_NAME
    assert body["user"]["default_home_budget"] == "30000.00"


@pytest.mark.asyncio
async def test_login_invalid_password(client):
    response = await client.post(
        "/api/v1/auth/login",
        json={
            "email": settings.OWNER_EMAIL,
            "password": "wrong-password",
            "device_id": "device-1",
        },
    )
    assert response.status_code == 401
    assert response.json()["error"]["code"] == "UNAUTHORIZED"


@pytest.mark.asyncio
async def test_refresh_rotation_and_replay(client):
    login = await client.post(
        "/api/v1/auth/login",
        json={
            "email": settings.OWNER_EMAIL,
            "password": settings.OWNER_PASSWORD,
            "device_id": "device-1",
        },
    )
    first = login.json()["refresh_token"]
    refreshed = await client.post("/api/v1/auth/refresh", json={"refresh_token": first, "device_id": "device-1"})
    assert refreshed.status_code == 200
    replay = await client.post("/api/v1/auth/refresh", json={"refresh_token": first, "device_id": "device-1"})
    assert replay.status_code == 401


@pytest.mark.asyncio
async def test_logout_and_me(client):
    login = (
        await client.post(
            "/api/v1/auth/login",
            json={
                "email": settings.OWNER_EMAIL,
                "password": settings.OWNER_PASSWORD,
                "device_id": "device-1",
            },
        )
    ).json()
    headers = {"Authorization": f"Bearer {login['access_token']}"}
    me = await client.get("/api/v1/auth/me", headers=headers)
    assert me.status_code == 200
    logout = await client.post("/api/v1/auth/logout", json={"refresh_token": login["refresh_token"]})
    assert logout.status_code == 204
    replay = await client.post("/api/v1/auth/refresh", json={"refresh_token": login["refresh_token"]})
    assert replay.status_code == 401


@pytest.mark.asyncio
async def test_change_password_revokes_sessions(client):
    login = (
        await client.post(
            "/api/v1/auth/login",
            json={
                "email": settings.OWNER_EMAIL,
                "password": settings.OWNER_PASSWORD,
                "device_id": "device-1",
            },
        )
    ).json()
    headers = {"Authorization": f"Bearer {login['access_token']}"}
    changed = await client.post(
        "/api/v1/auth/change-password",
        headers=headers,
        json={"current_password": settings.OWNER_PASSWORD, "new_password": "ANewPassword9"},
    )
    assert changed.status_code == 204
    replay = await client.post("/api/v1/auth/refresh", json={"refresh_token": login["refresh_token"]})
    assert replay.status_code == 401
    old_login = await client.post(
        "/api/v1/auth/login",
        json={
            "email": settings.OWNER_EMAIL,
            "password": settings.OWNER_PASSWORD,
            "device_id": "device-1",
        },
    )
    assert old_login.status_code == 401
    new_login = await client.post(
        "/api/v1/auth/login",
        json={
            "email": settings.OWNER_EMAIL,
            "password": "ANewPassword9",
            "device_id": "device-1",
        },
    )
    assert new_login.status_code == 200
