import os
from pathlib import Path

from sqlalchemy.engine.url import make_url


def _test_database_url() -> str:
    explicit = os.environ.get("TEST_DATABASE_URL", "").strip()
    if explicit:
        return explicit
    current = os.environ.get("DATABASE_URL", "").strip()
    if not current:
        env_file = Path(__file__).resolve().parents[1] / ".env"
        if env_file.is_file():
            for line in env_file.read_text(encoding="utf-8").splitlines():
                if line.startswith("DATABASE_URL="):
                    current = line.split("=", 1)[1].strip().strip('"').strip("'")
                    break
    if not current:
        raise RuntimeError("Set TEST_DATABASE_URL before running tests.")
    url = make_url(current)
    if url.database != "nabi_dental_test":
        url = url.set(database="nabi_dental_test")
    return url.render_as_string(hide_password=False)


os.environ["DATABASE_URL"] = _test_database_url()
os.environ["DEBUG"] = "false"
os.environ["APP_ENV"] = "test"
