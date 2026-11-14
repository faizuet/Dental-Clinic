import os
import subprocess
import sys
import uuid
from datetime import datetime, timezone
from decimal import Decimal
from pathlib import Path

import asyncpg
import pytest
from sqlalchemy.engine.url import make_url

from app.core.config import settings

BACKEND_ROOT = Path(__file__).resolve().parents[2]
SCRATCH_DB = "nabi_dental_migration_test"


def _alembic(url: str, target: str) -> None:
    env = os.environ.copy()
    env["DATABASE_URL"] = url
    subprocess.run([sys.executable, "-m", "alembic", "upgrade", target], check=True, cwd=BACKEND_ROOT, env=env)


def _dsn(database: str) -> str:
    url = make_url(settings.DATABASE_URL).set(drivername="postgresql", database=database)
    return url.render_as_string(hide_password=False)


async def _recreate(database: str, *, drop_only: bool = False) -> None:
    admin = await asyncpg.connect(_dsn("postgres"))
    try:
        await admin.execute(
            "SELECT pg_terminate_backend(pid) FROM pg_stat_activity WHERE datname = $1 AND pid <> pg_backend_pid()",
            database,
        )
        await admin.execute(f'DROP DATABASE IF EXISTS "{database}"')
        if not drop_only:
            await admin.execute(f'CREATE DATABASE "{database}"')
    finally:
        await admin.close()


@pytest.mark.asyncio
async def test_migration_moves_lab_expenses_without_loss_or_double_count():
    scratch_url = make_url(settings.DATABASE_URL).set(database=SCRATCH_DB).render_as_string(hide_password=False)
    await _recreate(SCRATCH_DB)
    try:
        _alembic(scratch_url, "0005_drop_construction")
        clinic_id, user_id, lab_cat, materials_cat = (uuid.uuid4() for _ in range(4))
        live_lab, deleted_lab, materials = (uuid.uuid4() for _ in range(3))
        conn = await asyncpg.connect(_dsn(SCRATCH_DB))
        try:
            await conn.execute("INSERT INTO clinics (id, name) VALUES ($1, 'Nabi Dental Clinic')", clinic_id)
            await conn.execute(
                "INSERT INTO users (id, clinic_id, full_name, email, password_hash) VALUES ($1, $2, 'Owner', 'o@x.pk', 'x')",
                user_id,
                clinic_id,
            )
            await conn.executemany(
                "INSERT INTO clinic_expense_categories (id, clinic_id, name, display_order) VALUES ($1, $2, $3, $4)",
                [(lab_cat, clinic_id, "Lab Charges", 0), (materials_cat, clinic_id, "Materials", 1)],
            )
            await conn.executemany(
                "INSERT INTO clinic_expenses (id, clinic_id, category_id, created_by, expense_date, amount, notes, deleted_at) "
                "VALUES ($1, $2, $3, $4, '2026-09-10', $5, $6, $7)",
                [
                    (live_lab, clinic_id, lab_cat, user_id, Decimal("1500.00"), "Crown for Ali", None),
                    (deleted_lab, clinic_id, lab_cat, user_id, Decimal("700.00"), None, datetime(2026, 9, 12, tzinfo=timezone.utc)),
                    (materials, clinic_id, materials_cat, user_id, Decimal("2000.00"), "Gloves", None),
                ],
            )
        finally:
            await conn.close()

        _alembic(scratch_url, "head")

        conn = await asyncpg.connect(_dsn(SCRATCH_DB))
        try:
            charges = {row["id"]: row for row in await conn.fetch("SELECT * FROM lab_charges")}
            assert set(charges) == {live_lab, deleted_lab}
            assert charges[live_lab]["amount"] == Decimal("1500.00")
            assert charges[live_lab]["notes"] == "Crown for Ali"
            assert str(charges[live_lab]["charge_date"]) == "2026-09-10"
            assert charges[live_lab]["created_by"] == user_id
            assert charges[live_lab]["deleted_at"] is None
            assert charges[deleted_lab]["deleted_at"] is not None

            live_expenses = await conn.fetch("SELECT id, amount FROM clinic_expenses WHERE deleted_at IS NULL")
            assert [(row["id"], row["amount"]) for row in live_expenses] == [(materials, Decimal("2000.00"))]
            moved = await conn.fetch("SELECT version, deleted_at FROM clinic_expenses WHERE id = $1", live_lab)
            assert moved[0]["deleted_at"] is not None
            assert moved[0]["version"] == 2

            categories = {
                row["name"]: row
                for row in await conn.fetch("SELECT name, is_active, deleted_at FROM clinic_expense_categories")
            }
            assert categories["Lab Charges"]["deleted_at"] is not None
            assert categories["Lab Charges"]["is_active"] is False
            assert categories["Materials"]["deleted_at"] is None
        finally:
            await conn.close()
    finally:
        await _recreate(SCRATCH_DB, drop_only=True)
