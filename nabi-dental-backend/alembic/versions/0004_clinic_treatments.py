"""Patients, treatment visit details, and X-ray attachments.

Revision ID: 0004_clinic_treatments
Revises: 0003_construction
Create Date: 2026-09-25
"""

from collections.abc import Sequence

import sqlalchemy as sa
from alembic import op
from sqlalchemy.dialects import postgresql

revision: str = "0004_clinic_treatments"
down_revision: str | None = "0003_construction"
branch_labels: str | Sequence[str] | None = None
depends_on: str | Sequence[str] | None = None


def upgrade() -> None:
    op.create_table(
        "patients",
        sa.Column("id", postgresql.UUID(as_uuid=True), primary_key=True),
        sa.Column("clinic_id", postgresql.UUID(as_uuid=True), sa.ForeignKey("clinics.id"), nullable=False, index=True),
        sa.Column("name", sa.String(150), nullable=False),
        sa.Column("phone", sa.String(40), nullable=True),
        sa.Column("notes", sa.String(1000), nullable=True),
        sa.Column("created_at", sa.DateTime(timezone=True), nullable=False),
        sa.Column("updated_at", sa.DateTime(timezone=True), nullable=False),
        sa.Column("deleted_at", sa.DateTime(timezone=True), nullable=True),
        sa.Column("version", sa.Integer(), nullable=False, server_default="1"),
    )
    op.create_index("ix_patients_clinic_name", "patients", ["clinic_id", "name"])

    op.add_column(
        "treatment_transactions",
        sa.Column("patient_id", postgresql.UUID(as_uuid=True), sa.ForeignKey("patients.id"), nullable=True),
    )
    op.add_column("treatment_transactions", sa.Column("serial_no", sa.Integer(), nullable=True))
    op.add_column("treatment_transactions", sa.Column("sub_treatment", sa.String(150), nullable=True))
    op.add_column(
        "treatment_transactions",
        sa.Column("details", postgresql.JSONB(astext_type=sa.Text()), nullable=False, server_default=sa.text("'{}'::jsonb")),
    )
    op.create_index("ix_treatment_transactions_patient_id", "treatment_transactions", ["patient_id"])

    op.execute(
        """
        WITH numbered AS (
            SELECT id,
                   ROW_NUMBER() OVER (
                       PARTITION BY clinic_id
                       ORDER BY transaction_date, created_at, id
                   ) AS n
            FROM treatment_transactions
        )
        UPDATE treatment_transactions AS t
        SET serial_no = numbered.n
        FROM numbered
        WHERE t.id = numbered.id
        """
    )
    op.alter_column("treatment_transactions", "serial_no", nullable=False)
    op.create_index(
        "uq_treatment_transactions_clinic_serial",
        "treatment_transactions",
        ["clinic_id", "serial_no"],
        unique=True,
        postgresql_where=sa.text("deleted_at IS NULL"),
    )

    op.create_table(
        "treatment_attachments",
        sa.Column("id", postgresql.UUID(as_uuid=True), primary_key=True),
        sa.Column("clinic_id", postgresql.UUID(as_uuid=True), sa.ForeignKey("clinics.id"), nullable=False, index=True),
        sa.Column(
            "transaction_id",
            postgresql.UUID(as_uuid=True),
            sa.ForeignKey("treatment_transactions.id"),
            nullable=False,
            index=True,
        ),
        sa.Column("stored_path", sa.String(500), nullable=False),
        sa.Column("original_name", sa.String(255), nullable=True),
        sa.Column("label", sa.String(40), nullable=False, server_default="other"),
        sa.Column("content_type", sa.String(80), nullable=False, server_default="image/jpeg"),
        sa.Column("byte_size", sa.Integer(), nullable=False, server_default="0"),
        sa.Column("created_at", sa.DateTime(timezone=True), nullable=False),
        sa.Column("updated_at", sa.DateTime(timezone=True), nullable=False),
        sa.Column("deleted_at", sa.DateTime(timezone=True), nullable=True),
        sa.Column("version", sa.Integer(), nullable=False, server_default="1"),
    )


def downgrade() -> None:
    op.drop_table("treatment_attachments")
    op.drop_index("uq_treatment_transactions_clinic_serial", table_name="treatment_transactions")
    op.drop_index("ix_treatment_transactions_patient_id", table_name="treatment_transactions")
    op.drop_column("treatment_transactions", "details")
    op.drop_column("treatment_transactions", "sub_treatment")
    op.drop_column("treatment_transactions", "serial_no")
    op.drop_column("treatment_transactions", "patient_id")
    op.drop_index("ix_patients_clinic_name", table_name="patients")
    op.drop_table("patients")
