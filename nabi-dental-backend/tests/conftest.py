import os

os.environ["DATABASE_URL"] = os.environ.get(
    "TEST_DATABASE_URL",
    "postgresql+asyncpg://postgres:postgres@localhost:5433/nabi_dental",
)
os.environ["DEBUG"] = "false"
os.environ["APP_ENV"] = "test"
