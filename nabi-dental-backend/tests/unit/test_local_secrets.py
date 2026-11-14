from pathlib import Path

from app.core.local_secrets import (
    ensure_jwt_secret,
    is_example_owner_password,
    is_insecure_jwt,
    read_env_value,
    upsert_env_value,
)


def test_example_jwt_placeholders_are_insecure():
    assert is_insecure_jwt("change-me")
    assert is_insecure_jwt("change-me-to-a-long-random-secret")
    assert is_insecure_jwt("short")
    assert not is_insecure_jwt("a-long-unique-clinic-jwt-secret-key-value")


def test_example_owner_password_is_detected():
    assert is_example_owner_password("ChangeMeNow!1")
    assert not is_example_owner_password("ClinicOwnerPass9")


def test_ensure_jwt_secret_keeps_existing_unique_key(tmp_path: Path, monkeypatch):
    env = tmp_path / ".env"
    env.write_text("JWT_SECRET_KEY=already-unique-clinic-secret-key-value\n", encoding="utf-8")
    monkeypatch.setenv("JWT_SECRET_KEY", "change-me")
    secret = ensure_jwt_secret(env_path=env, persist=True)
    assert secret == "already-unique-clinic-secret-key-value"
    assert read_env_value(env, "JWT_SECRET_KEY") == "already-unique-clinic-secret-key-value"


def test_ensure_jwt_secret_replaces_example_and_writes_env(tmp_path: Path, monkeypatch):
    env = tmp_path / ".env"
    env.write_text("JWT_SECRET_KEY=change-me-to-a-long-random-secret\nOWNER_EMAIL=nabidentalclinic@gmail.com\n", encoding="utf-8")
    monkeypatch.setenv("JWT_SECRET_KEY", "change-me-to-a-long-random-secret")
    secret = ensure_jwt_secret(env_path=env, persist=True)
    assert not is_insecure_jwt(secret)
    assert read_env_value(env, "JWT_SECRET_KEY") == secret
    assert read_env_value(env, "OWNER_EMAIL") == "nabidentalclinic@gmail.com"


def test_upsert_env_value_appends_missing_key(tmp_path: Path):
    env = tmp_path / ".env"
    env.write_text("APP_ENV=development\n", encoding="utf-8")
    upsert_env_value(env, "JWT_SECRET_KEY", "generated-secret")
    assert read_env_value(env, "APP_ENV") == "development"
    assert read_env_value(env, "JWT_SECRET_KEY") == "generated-secret"
