from app.core.logging import redact_secrets


def test_logs_hide_database_credentials():
    raw = (
        "connection failed postgresql+asyncpg://postgres:super-secret@db:5432/nabi_dental "
        "PGPASSWORD=super-secret"
    )
    cleaned = redact_secrets(raw)
    assert "super-secret" not in cleaned
    assert "postgres:***@db:5432/nabi_dental" in cleaned
    assert "PGPASSWORD=***" in cleaned
