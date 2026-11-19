"""Backup and restore drill.

Uses only the database named nabi_backup_drill. It never restores the live clinic database.
"""

from __future__ import annotations

import asyncio
import os
import subprocess
import sys
from datetime import date
from decimal import Decimal
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
if str(ROOT) not in sys.path:
    sys.path.insert(0, str(ROOT))

from sqlalchemy.engine.url import make_url


def _refuse_unless_drill(url: str) -> None:
    name = make_url(url).database
    if name != "nabi_backup_drill":
        raise SystemExit(f"Refusing to run. This drill only uses nabi_backup_drill, not {name}.")


def _psql(url: str, sql: str) -> str:
    parsed = make_url(url)
    env = os.environ.copy()
    env["PGPASSWORD"] = parsed.password or ""
    completed = subprocess.run(
        [
            "psql",
            "--no-psqlrc",
            "-v",
            "ON_ERROR_STOP=1",
            "-At",
            "-h",
            parsed.host or "localhost",
            "-p",
            str(parsed.port or 5432),
            "-U",
            parsed.username or "postgres",
            "-d",
            parsed.database or "postgres",
            "-c",
            sql,
        ],
        check=True,
        capture_output=True,
        env=env,
        text=True,
    )
    return completed.stdout.strip()


def _prepare_database(drill_url: str) -> None:
    parsed = make_url(drill_url)
    admin = parsed.set(database="postgres").render_as_string(hide_password=False)
    _psql(
        admin,
        "SELECT pg_terminate_backend(pid) FROM pg_stat_activity "
        "WHERE datname = 'nabi_backup_drill' AND pid <> pg_backend_pid()",
    )
    _psql(admin, "DROP DATABASE IF EXISTS nabi_backup_drill")
    _psql(admin, "CREATE DATABASE nabi_backup_drill")
    env = os.environ.copy()
    env["DATABASE_URL"] = drill_url
    subprocess.run(
        [sys.executable, "-m", "alembic", "upgrade", "head"],
        check=True,
        cwd="/app",
        env=env,
    )


async def _seed_known_rows() -> None:
    from sqlalchemy import select

    from app.db.seed import seed_database
    from app.db.session import SessionLocal
    from app.models import Clinic, ClinicExpense, ClinicExpenseCategory, LabCharge, Patient, Treatment, TreatmentTransaction, User

    async with SessionLocal() as session:
        await seed_database(session)
        clinic = (await session.execute(select(Clinic))).scalar_one()
        owner = (await session.execute(select(User))).scalar_one()
        treatment = (await session.execute(select(Treatment).limit(1))).scalar_one()
        category = (await session.execute(select(ClinicExpenseCategory).limit(1))).scalar_one()
        patient = Patient(clinic_id=clinic.id, name="Backup Drill Patient", phone="03001112233")
        session.add(patient)
        await session.flush()
        session.add(
            TreatmentTransaction(
                clinic_id=clinic.id,
                treatment_id=treatment.id,
                created_by=owner.id,
                patient_id=patient.id,
                serial_no=9001,
                transaction_date=date(2026, 11, 19),
                quantity=1,
                amount=Decimal("1234.50"),
                details={},
                notes="Drill visit",
            )
        )
        session.add(
            ClinicExpense(
                clinic_id=clinic.id,
                category_id=category.id,
                created_by=owner.id,
                expense_date=date(2026, 11, 19),
                amount=Decimal("250.00"),
                notes="Drill rent",
            )
        )
        session.add(
            LabCharge(
                clinic_id=clinic.id,
                created_by=owner.id,
                charge_date=date(2026, 11, 19),
                amount=Decimal("75.00"),
                lab_name="Drill Lab",
                notes="Drill lab",
            )
        )
        await session.commit()


def main() -> None:
    configured = os.environ.get("DATABASE_URL", "")
    if make_url(configured).database != "nabi_dental":
        raise SystemExit("This drill must run inside the clinic app container.")
    live_url = configured
    drill_url = make_url(configured).set(database="nabi_backup_drill").render_as_string(hide_password=False)
    _refuse_unless_drill(drill_url)
    live_patients = _psql(live_url, "SELECT count(*) FROM patients")
    live_visits = _psql(live_url, "SELECT count(*) FROM treatment_transactions")

    _prepare_database(drill_url)
    os.environ["DATABASE_URL"] = drill_url
    os.environ["APP_ENV"] = "test"
    os.environ["DISABLE_BACKUP_SCHEDULER"] = "1"

    from app.core.config import get_settings
    from app.db.session import engine
    from app.services.backup_service import BackupService

    get_settings.cache_clear()
    uploads = Path("/tmp/nabi-backup-drill-uploads")
    backups = Path("/tmp/nabi-backup-drill-copies")
    if uploads.exists():
        import shutil

        shutil.rmtree(uploads)
    if backups.exists():
        import shutil

        shutil.rmtree(backups)
    xray = uploads / "xrays" / "drill.jpg"
    xray.parent.mkdir(parents=True)
    xray.write_bytes(b"drill-xray-bytes")

    asyncio.run(_seed_known_rows())
    asyncio.run(engine.dispose())
    service = BackupService(upload_dir=uploads, backup_dir=backups, database_url=drill_url)
    copy = service.create_archive()
    xray.unlink()
    _psql(
        drill_url,
        "TRUNCATE TABLE lab_charges, clinic_expenses, treatment_transactions, patients RESTART IDENTITY CASCADE",
    )
    restored = service.restore(copy.path, create_safety_backup=True)
    patient = _psql(drill_url, "SELECT name FROM patients WHERE name = 'Backup Drill Patient'")
    visit = Decimal(_psql(drill_url, "SELECT amount FROM treatment_transactions WHERE serial_no = 9001"))
    expense = Decimal(_psql(drill_url, "SELECT amount FROM clinic_expenses WHERE notes = 'Drill rent'"))
    lab = Decimal(_psql(drill_url, "SELECT amount FROM lab_charges WHERE lab_name = 'Drill Lab'"))
    file_ok = xray.is_file() and xray.read_bytes() == b"drill-xray-bytes"
    if patient != "Backup Drill Patient" or visit != Decimal("1234.50") or expense != Decimal("250.00") or lab != Decimal("75.00") or not file_ok:
        raise SystemExit(
            f"Restore check failed patient={patient!r} visit={visit!r} expense={expense!r} lab={lab!r} file={file_ok} verified={restored.get('verified')}"
        )
    if restored.get("verified") is not True or not restored.get("safety_backup"):
        raise SystemExit(f"Restore did not verify or did not keep a safety copy: {restored}")
    live_patients_after = _psql(live_url, "SELECT count(*) FROM patients")
    live_visits_after = _psql(live_url, "SELECT count(*) FROM treatment_transactions")
    if live_patients_after != live_patients or live_visits_after != live_visits:
        raise SystemExit(
            f"Live clinic counts changed. patients {live_patients} -> {live_patients_after}, visits {live_visits} -> {live_visits_after}."
        )
    asyncio.run(engine.dispose())
    admin = make_url(drill_url).set(database="postgres").render_as_string(hide_password=False)
    _psql(
        admin,
        "SELECT pg_terminate_backend(pid) FROM pg_stat_activity "
        "WHERE datname = 'nabi_backup_drill' AND pid <> pg_backend_pid()",
    )
    _psql(admin, "DROP DATABASE IF EXISTS nabi_backup_drill")
    print("backup roundtrip ok")
    print(f"safety_backup={restored['safety_backup']}")
    print(f"verified={restored['verified']}")
    print(f"live_patients={live_patients_after}")
    print(f"live_visits={live_visits_after}")


if __name__ == "__main__":
    main()
