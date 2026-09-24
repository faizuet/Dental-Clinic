from io import BytesIO

import pytest
from PIL import Image

from tests.api.conftest import auth_header, login


def _png_bytes(size: int = 128) -> bytes:
    image = Image.new("RGB", (size, size), color=(124, 58, 237))
    buffer = BytesIO()
    image.save(buffer, format="PNG")
    return buffer.getvalue()


@pytest.mark.asyncio
async def test_avatar_upload_get_and_delete(client):
    tokens = await login(client)
    headers = auth_header(tokens)

    missing = await client.get("/api/v1/settings/avatar", headers=headers)
    assert missing.status_code == 404

    uploaded = await client.post(
        "/api/v1/settings/avatar",
        headers=headers,
        files={"file": ("owner.png", _png_bytes(), "image/png")},
    )
    assert uploaded.status_code == 200, uploaded.text
    assert uploaded.json()["has_avatar"] is True

    fetched = await client.get("/api/v1/settings/avatar", headers=headers)
    assert fetched.status_code == 200
    assert fetched.headers["content-type"] == "image/jpeg"

    deleted = await client.delete("/api/v1/settings/avatar", headers=headers)
    assert deleted.status_code == 200
    assert deleted.json()["has_avatar"] is False


@pytest.mark.asyncio
async def test_avatar_rejects_invalid_and_tiny_files(client):
    tokens = await login(client)
    headers = auth_header(tokens)

    text_file = await client.post(
        "/api/v1/settings/avatar",
        headers=headers,
        files={"file": ("notes.txt", b"not-an-image", "text/plain")},
    )
    assert text_file.status_code == 400

    tiny = await client.post(
        "/api/v1/settings/avatar",
        headers=headers,
        files={"file": ("tiny.png", _png_bytes(16), "image/png")},
    )
    assert tiny.status_code == 400
