"""Move lab charges out of clinic expenses into their own table.

Existing clinic expenses in a lab category are copied to lab_charges with the same id,
date, amount, notes, and history. The originals are soft-deleted (not removed) so every
laptop's offline cache drops them on the next sync and they are never counted twice.

Revision ID: 0006_lab_charges
Revises: 0005_drop_construction
Create Date: 2026-11-14
"""

from collections.abc import Sequence

import sqlalchemy as sa
from alembic import op
from sqlalchemy.dialects import postgresql

revision: str = "0006_lab_charges"
down_revision: str | None = "0005_drop_construction"
branch_labels: str | Sequence[str] | None = None
depends_on: str | Sequence[str] | None = None

LAB_CATEGORY_MATCH = "lower(trim(name)) IN ('lab charges', 'lab charge', 'lab')"


def upgrade() -> None:
    op.create_table(
        "lab_charges",
        sa.Column("id", postgresql.UUID(as_uuid=True), primary_key=True),
        sa.Column("clinic_id", postgresql.UUID(as_uuid=True), sa.ForeignKey("clinics.id"), nullable=False, index=True),
        sa.Column("created_by", postgresql.UUID(as_uuid=True), sa.ForeignKey("users.id"), nullable=False),
        sa.Column("patient_id", postgresql.UUID(as_uuid=True), sa.ForeignKey("patients.id"), nullable=True, index=True),
        sa.Column(
            "transaction_id",
            postgresql.UUID(as_uuid=True),
            sa.ForeignKey("treatment_transactions.id"),
            nullable=True,
            index=True,
        ),
        sa.Column("charge_date", sa.Date(), nullable=False),
        sa.Column("amount", sa.Numeric(14, 2), nullable=False),
        sa.Column("lab_name", sa.String(150), nullable=True),
        sa.Column("notes", sa.String(1000), nullable=True),
        sa.Column("created_at", sa.DateTime(timezone=True), nullable=False, server_default=sa.func.now()),
        sa.Column("updated_at", sa.DateTime(timezone=True), nullable=False, server_default=sa.func.now()),
        sa.Column("deleted_at", sa.DateTime(timezone=True), nullable=True),
        sa.Column("version", sa.Integer(), nullable=False, server_default="1"),
        sa.CheckConstraint("amount > 0", name="ck_lab_charges_amount_positive"),
    )
    op.create_index("ix_lab_charges_clinic_date", "lab_charges", ["clinic_id", "charge_date"])

    op.execute(
        f"""
        INSERT INTO lab_charges (
            id, clinic_id, created_by, charge_date, amount, notes,
            created_at, updated_at, deleted_at, version
        )
        SELECT e.id, e.clinic_id, e.created_by, e.expense_date, e.amount, e.notes,
               e.created_at, now(), e.deleted_at, e.version
        FROM clinic_expenses AS e
        WHERE e.category_id IN (SELECT id FROM clinic_expense_categories WHERE {LAB_CATEGORY_MATCH})
        """
    )
    op.execute(
        """
        UPDATE clinic_expenses
        SET deleted_at = COALESCE(deleted_at, now()),
            updated_at = now(),
            version = version + 1
        WHERE id IN (SELECT id FROM lab_charges)
        """
    )
    op.execute(
        f"""
        UPDATE clinic_expense_categories
        SET is_active = false,
            deleted_at = now(),
            updated_at = now(),
            version = version + 1
        WHERE deleted_at IS NULL AND {LAB_CATEGORY_MATCH}
        """
    )


def downgrade() -> None:
    raise RuntimeError(
        "Lab charges now have their own records. Restore a backup taken before this update instead of downgrading."
    )
