"""Initial schema for Nabi Dental Clinic.

Revision ID: 0001_initial
Revises:
Create Date: 2026-09-17
"""

from collections.abc import Sequence

import sqlalchemy as sa
from alembic import op
from sqlalchemy.dialects import postgresql

revision: str = "0001_initial"
down_revision: str | None = None
branch_labels: str | Sequence[str] | None = None
depends_on: str | Sequence[str] | None = None


def upgrade() -> None:
    op.execute("CREATE EXTENSION IF NOT EXISTS citext")

    op.create_table(
        "clinics",
        sa.Column("id", postgresql.UUID(as_uuid=True), primary_key=True),
        sa.Column("name", sa.String(150), nullable=False),
        sa.Column("currency", sa.CHAR(3), nullable=False, server_default="PKR"),
        sa.Column("timezone", sa.String(64), nullable=False, server_default="Asia/Karachi"),
        sa.Column("created_at", sa.DateTime(timezone=True), nullable=False, server_default=sa.func.now()),
        sa.Column("updated_at", sa.DateTime(timezone=True), nullable=False, server_default=sa.func.now()),
    )

    op.create_table(
        "users",
        sa.Column("id", postgresql.UUID(as_uuid=True), primary_key=True),
        sa.Column("clinic_id", postgresql.UUID(as_uuid=True), sa.ForeignKey("clinics.id"), nullable=False),
        sa.Column("full_name", sa.String(150), nullable=False),
        sa.Column("email", postgresql.CITEXT(), nullable=False),
        sa.Column("password_hash", sa.Text(), nullable=False),
        sa.Column("role", sa.String(30), nullable=False, server_default="owner"),
        sa.Column("default_home_budget", sa.Numeric(14, 2), nullable=False, server_default="30000.00"),
        sa.Column("is_active", sa.Boolean(), nullable=False, server_default=sa.true()),
        sa.Column("last_login_at", sa.DateTime(timezone=True), nullable=True),
        sa.Column("created_at", sa.DateTime(timezone=True), nullable=False, server_default=sa.func.now()),
        sa.Column("updated_at", sa.DateTime(timezone=True), nullable=False, server_default=sa.func.now()),
        sa.UniqueConstraint("email", name="uq_users_email"),
    )
    op.create_index("ix_users_clinic_id", "users", ["clinic_id"])
    op.create_index("uq_users_lower_email", "users", [sa.text("lower(email)")], unique=True)

    op.create_table(
        "refresh_tokens",
        sa.Column("id", postgresql.UUID(as_uuid=True), primary_key=True),
        sa.Column("user_id", postgresql.UUID(as_uuid=True), sa.ForeignKey("users.id"), nullable=False),
        sa.Column("token_hash", sa.CHAR(64), nullable=False),
        sa.Column("device_id", sa.String(128), nullable=False),
        sa.Column("device_name", sa.String(150), nullable=True),
        sa.Column("expires_at", sa.DateTime(timezone=True), nullable=False),
        sa.Column("revoked_at", sa.DateTime(timezone=True), nullable=True),
        sa.Column("replaced_by_token_id", postgresql.UUID(as_uuid=True), nullable=True),
        sa.Column("created_at", sa.DateTime(timezone=True), nullable=False, server_default=sa.func.now()),
        sa.UniqueConstraint("token_hash", name="uq_refresh_tokens_token_hash"),
    )
    op.create_index("ix_refresh_tokens_user_id", "refresh_tokens", ["user_id"])
    op.create_index(
        "ix_refresh_tokens_user_expires_revoked",
        "refresh_tokens",
        ["user_id", "expires_at", "revoked_at"],
    )

    op.create_table(
        "treatment_categories",
        sa.Column("id", postgresql.UUID(as_uuid=True), primary_key=True),
        sa.Column("clinic_id", postgresql.UUID(as_uuid=True), sa.ForeignKey("clinics.id"), nullable=False),
        sa.Column("name", sa.String(120), nullable=False),
        sa.Column("display_order", sa.Integer(), nullable=False, server_default="0"),
        sa.Column("is_active", sa.Boolean(), nullable=False, server_default=sa.true()),
        sa.Column("created_at", sa.DateTime(timezone=True), nullable=False, server_default=sa.func.now()),
        sa.Column("updated_at", sa.DateTime(timezone=True), nullable=False, server_default=sa.func.now()),
        sa.Column("deleted_at", sa.DateTime(timezone=True), nullable=True),
        sa.Column("version", sa.Integer(), nullable=False, server_default="1"),
    )
    op.create_index("ix_treatment_categories_clinic_id", "treatment_categories", ["clinic_id"])
    op.execute(
        "CREATE UNIQUE INDEX uq_treatment_categories_clinic_lower_name "
        "ON treatment_categories (clinic_id, lower(name)) WHERE deleted_at IS NULL"
    )
    op.create_index(
        "ix_treatment_categories_updated_id",
        "treatment_categories",
        ["updated_at", "id"],
    )

    op.create_table(
        "treatments",
        sa.Column("id", postgresql.UUID(as_uuid=True), primary_key=True),
        sa.Column("clinic_id", postgresql.UUID(as_uuid=True), sa.ForeignKey("clinics.id"), nullable=False),
        sa.Column(
            "category_id",
            postgresql.UUID(as_uuid=True),
            sa.ForeignKey("treatment_categories.id"),
            nullable=False,
        ),
        sa.Column("name", sa.String(150), nullable=False),
        sa.Column("default_price", sa.Numeric(14, 2), nullable=True),
        sa.Column("display_order", sa.Integer(), nullable=False, server_default="0"),
        sa.Column("is_active", sa.Boolean(), nullable=False, server_default=sa.true()),
        sa.Column("created_at", sa.DateTime(timezone=True), nullable=False, server_default=sa.func.now()),
        sa.Column("updated_at", sa.DateTime(timezone=True), nullable=False, server_default=sa.func.now()),
        sa.Column("deleted_at", sa.DateTime(timezone=True), nullable=True),
        sa.Column("version", sa.Integer(), nullable=False, server_default="1"),
    )
    op.create_index("ix_treatments_clinic_id", "treatments", ["clinic_id"])
    op.create_index("ix_treatments_category_id", "treatments", ["category_id"])
    op.execute(
        "CREATE UNIQUE INDEX uq_treatments_clinic_lower_name "
        "ON treatments (clinic_id, lower(name)) WHERE deleted_at IS NULL"
    )
    op.execute(
        "CREATE INDEX ix_treatments_clinic_category_active "
        "ON treatments (clinic_id, category_id, is_active) WHERE deleted_at IS NULL"
    )
    op.create_index("ix_treatments_updated_id", "treatments", ["updated_at", "id"])

    op.create_table(
        "treatment_transactions",
        sa.Column("id", postgresql.UUID(as_uuid=True), primary_key=True),
        sa.Column("clinic_id", postgresql.UUID(as_uuid=True), sa.ForeignKey("clinics.id"), nullable=False),
        sa.Column("treatment_id", postgresql.UUID(as_uuid=True), sa.ForeignKey("treatments.id"), nullable=False),
        sa.Column("created_by", postgresql.UUID(as_uuid=True), sa.ForeignKey("users.id"), nullable=False),
        sa.Column("transaction_date", sa.Date(), nullable=False),
        sa.Column("quantity", sa.Integer(), nullable=False, server_default="1"),
        sa.Column("amount", sa.Numeric(14, 2), nullable=False),
        sa.Column("notes", sa.String(1000), nullable=True),
        sa.Column("created_at", sa.DateTime(timezone=True), nullable=False, server_default=sa.func.now()),
        sa.Column("updated_at", sa.DateTime(timezone=True), nullable=False, server_default=sa.func.now()),
        sa.Column("deleted_at", sa.DateTime(timezone=True), nullable=True),
        sa.Column("version", sa.Integer(), nullable=False, server_default="1"),
        sa.CheckConstraint("quantity > 0", name="ck_treatment_transactions_quantity_positive"),
        sa.CheckConstraint("amount > 0", name="ck_treatment_transactions_amount_positive"),
    )
    op.create_index("ix_treatment_transactions_clinic_id", "treatment_transactions", ["clinic_id"])
    op.create_index("ix_treatment_transactions_treatment_id", "treatment_transactions", ["treatment_id"])
    op.create_index("ix_treatment_transactions_transaction_date", "treatment_transactions", ["transaction_date"])
    op.execute(
        "CREATE INDEX ix_treatment_transactions_clinic_date_live "
        "ON treatment_transactions (clinic_id, transaction_date) WHERE deleted_at IS NULL"
    )
    op.create_index("ix_treatment_transactions_updated_id", "treatment_transactions", ["updated_at", "id"])

    op.create_table(
        "clinic_expense_categories",
        sa.Column("id", postgresql.UUID(as_uuid=True), primary_key=True),
        sa.Column("clinic_id", postgresql.UUID(as_uuid=True), sa.ForeignKey("clinics.id"), nullable=False),
        sa.Column("name", sa.String(120), nullable=False),
        sa.Column("display_order", sa.Integer(), nullable=False, server_default="0"),
        sa.Column("is_active", sa.Boolean(), nullable=False, server_default=sa.true()),
        sa.Column("created_at", sa.DateTime(timezone=True), nullable=False, server_default=sa.func.now()),
        sa.Column("updated_at", sa.DateTime(timezone=True), nullable=False, server_default=sa.func.now()),
        sa.Column("deleted_at", sa.DateTime(timezone=True), nullable=True),
        sa.Column("version", sa.Integer(), nullable=False, server_default="1"),
    )
    op.create_index("ix_clinic_expense_categories_clinic_id", "clinic_expense_categories", ["clinic_id"])
    op.execute(
        "CREATE UNIQUE INDEX uq_clinic_expense_categories_clinic_lower_name "
        "ON clinic_expense_categories (clinic_id, lower(name)) WHERE deleted_at IS NULL"
    )
    op.create_index(
        "ix_clinic_expense_categories_updated_id",
        "clinic_expense_categories",
        ["updated_at", "id"],
    )

    op.create_table(
        "clinic_expenses",
        sa.Column("id", postgresql.UUID(as_uuid=True), primary_key=True),
        sa.Column("clinic_id", postgresql.UUID(as_uuid=True), sa.ForeignKey("clinics.id"), nullable=False),
        sa.Column(
            "category_id",
            postgresql.UUID(as_uuid=True),
            sa.ForeignKey("clinic_expense_categories.id"),
            nullable=False,
        ),
        sa.Column("created_by", postgresql.UUID(as_uuid=True), sa.ForeignKey("users.id"), nullable=False),
        sa.Column("expense_date", sa.Date(), nullable=False),
        sa.Column("amount", sa.Numeric(14, 2), nullable=False),
        sa.Column("notes", sa.String(1000), nullable=True),
        sa.Column("created_at", sa.DateTime(timezone=True), nullable=False, server_default=sa.func.now()),
        sa.Column("updated_at", sa.DateTime(timezone=True), nullable=False, server_default=sa.func.now()),
        sa.Column("deleted_at", sa.DateTime(timezone=True), nullable=True),
        sa.Column("version", sa.Integer(), nullable=False, server_default="1"),
        sa.CheckConstraint("amount > 0", name="ck_clinic_expenses_amount_positive"),
    )
    op.create_index("ix_clinic_expenses_clinic_id", "clinic_expenses", ["clinic_id"])
    op.create_index("ix_clinic_expenses_category_id", "clinic_expenses", ["category_id"])
    op.create_index("ix_clinic_expenses_expense_date", "clinic_expenses", ["expense_date"])
    op.execute(
        "CREATE INDEX ix_clinic_expenses_clinic_date_live "
        "ON clinic_expenses (clinic_id, expense_date) WHERE deleted_at IS NULL"
    )
    op.create_index("ix_clinic_expenses_updated_id", "clinic_expenses", ["updated_at", "id"])

    op.create_table(
        "home_expense_categories",
        sa.Column("id", postgresql.UUID(as_uuid=True), primary_key=True),
        sa.Column("user_id", postgresql.UUID(as_uuid=True), sa.ForeignKey("users.id"), nullable=False),
        sa.Column("name", sa.String(120), nullable=False),
        sa.Column("display_order", sa.Integer(), nullable=False, server_default="0"),
        sa.Column("is_active", sa.Boolean(), nullable=False, server_default=sa.true()),
        sa.Column("created_at", sa.DateTime(timezone=True), nullable=False, server_default=sa.func.now()),
        sa.Column("updated_at", sa.DateTime(timezone=True), nullable=False, server_default=sa.func.now()),
        sa.Column("deleted_at", sa.DateTime(timezone=True), nullable=True),
        sa.Column("version", sa.Integer(), nullable=False, server_default="1"),
    )
    op.create_index("ix_home_expense_categories_user_id", "home_expense_categories", ["user_id"])
    op.execute(
        "CREATE UNIQUE INDEX uq_home_expense_categories_user_lower_name "
        "ON home_expense_categories (user_id, lower(name)) WHERE deleted_at IS NULL"
    )
    op.create_index(
        "ix_home_expense_categories_updated_id",
        "home_expense_categories",
        ["updated_at", "id"],
    )

    op.create_table(
        "home_expenses",
        sa.Column("id", postgresql.UUID(as_uuid=True), primary_key=True),
        sa.Column("user_id", postgresql.UUID(as_uuid=True), sa.ForeignKey("users.id"), nullable=False),
        sa.Column(
            "category_id",
            postgresql.UUID(as_uuid=True),
            sa.ForeignKey("home_expense_categories.id"),
            nullable=False,
        ),
        sa.Column("expense_date", sa.Date(), nullable=False),
        sa.Column("amount", sa.Numeric(14, 2), nullable=False),
        sa.Column("notes", sa.String(1000), nullable=True),
        sa.Column("created_at", sa.DateTime(timezone=True), nullable=False, server_default=sa.func.now()),
        sa.Column("updated_at", sa.DateTime(timezone=True), nullable=False, server_default=sa.func.now()),
        sa.Column("deleted_at", sa.DateTime(timezone=True), nullable=True),
        sa.Column("version", sa.Integer(), nullable=False, server_default="1"),
        sa.CheckConstraint("amount > 0", name="ck_home_expenses_amount_positive"),
    )
    op.create_index("ix_home_expenses_user_id", "home_expenses", ["user_id"])
    op.create_index("ix_home_expenses_category_id", "home_expenses", ["category_id"])
    op.create_index("ix_home_expenses_expense_date", "home_expenses", ["expense_date"])
    op.execute(
        "CREATE INDEX ix_home_expenses_user_date_live "
        "ON home_expenses (user_id, expense_date) WHERE deleted_at IS NULL"
    )
    op.create_index("ix_home_expenses_updated_id", "home_expenses", ["updated_at", "id"])

    op.create_table(
        "home_budgets",
        sa.Column("id", postgresql.UUID(as_uuid=True), primary_key=True),
        sa.Column("user_id", postgresql.UUID(as_uuid=True), sa.ForeignKey("users.id"), nullable=False),
        sa.Column("year", sa.SmallInteger(), nullable=False),
        sa.Column("month", sa.SmallInteger(), nullable=False),
        sa.Column("amount", sa.Numeric(14, 2), nullable=False),
        sa.Column("created_at", sa.DateTime(timezone=True), nullable=False, server_default=sa.func.now()),
        sa.Column("updated_at", sa.DateTime(timezone=True), nullable=False, server_default=sa.func.now()),
        sa.Column("deleted_at", sa.DateTime(timezone=True), nullable=True),
        sa.Column("version", sa.Integer(), nullable=False, server_default="1"),
        sa.CheckConstraint("month >= 1 AND month <= 12", name="ck_home_budgets_month_range"),
        sa.CheckConstraint("amount >= 0", name="ck_home_budgets_amount_non_negative"),
    )
    op.create_index("ix_home_budgets_user_id", "home_budgets", ["user_id"])
    op.execute(
        "CREATE UNIQUE INDEX uq_home_budgets_user_year_month "
        "ON home_budgets (user_id, year, month) WHERE deleted_at IS NULL"
    )
    op.create_index("ix_home_budgets_updated_id", "home_budgets", ["updated_at", "id"])

    op.create_table(
        "sync_changes",
        sa.Column("id", postgresql.UUID(as_uuid=True), primary_key=True),
        sa.Column("client_change_id", postgresql.UUID(as_uuid=True), nullable=False),
        sa.Column("user_id", postgresql.UUID(as_uuid=True), sa.ForeignKey("users.id"), nullable=False),
        sa.Column("device_id", sa.String(128), nullable=False),
        sa.Column("entity_type", sa.String(64), nullable=False),
        sa.Column("entity_id", postgresql.UUID(as_uuid=True), nullable=False),
        sa.Column("operation", sa.String(16), nullable=False),
        sa.Column("status", sa.String(16), nullable=False),
        sa.Column("result", postgresql.JSONB(), nullable=False),
        sa.Column("created_at", sa.DateTime(timezone=True), nullable=False, server_default=sa.func.now()),
        sa.UniqueConstraint("client_change_id", name="uq_sync_changes_client_change_id"),
    )
    op.create_index("ix_sync_changes_user_id", "sync_changes", ["user_id"])


def downgrade() -> None:
    op.drop_table("sync_changes")
    op.drop_table("home_budgets")
    op.drop_table("home_expenses")
    op.drop_table("home_expense_categories")
    op.drop_table("clinic_expenses")
    op.drop_table("clinic_expense_categories")
    op.drop_table("treatment_transactions")
    op.drop_table("treatments")
    op.drop_table("treatment_categories")
    op.drop_table("refresh_tokens")
    op.drop_table("users")
    op.drop_table("clinics")
