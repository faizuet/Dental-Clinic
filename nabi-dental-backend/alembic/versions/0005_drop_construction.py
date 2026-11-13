"""Remove construction tables. Clinic and home records are unchanged.

Revision ID: 0005_drop_construction
Revises: 0004_clinic_treatments
Create Date: 2026-11-13
"""

from collections.abc import Sequence

from alembic import op

revision: str = "0005_drop_construction"
down_revision: str | None = "0004_clinic_treatments"
branch_labels: str | Sequence[str] | None = None
depends_on: str | Sequence[str] | None = None


def upgrade() -> None:
    op.execute(
        "DELETE FROM sync_changes WHERE entity_type IN "
        "('construction_material_category', 'construction_material', 'construction_purchase')"
    )
    op.execute("DROP TABLE IF EXISTS construction_purchases")
    op.execute("DROP TABLE IF EXISTS construction_materials")
    op.execute("DROP TABLE IF EXISTS construction_material_categories")


def downgrade() -> None:
    raise RuntimeError("Construction was removed from Nabi Dental Clinic and cannot be restored by this migration.")
