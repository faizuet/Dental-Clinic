import pytest

from tests.api.conftest import auth_header, login

GONE = (
    "/api/v1/construction-material-categories",
    "/api/v1/construction-materials",
    "/api/v1/construction-purchases",
    "/api/v1/reports/construction",
    "/api/v1/reports/construction/export",
    "/api/v1/dashboard/construction",
)


@pytest.mark.asyncio
async def test_construction_routes_are_gone(client):
    tokens = await login(client)
    headers = auth_header(tokens)
    for path in GONE:
        response = await client.get(path, headers=headers)
        assert response.status_code == 404, path
