"""Add optional owner avatar path.

Revision ID: 0002_user_avatar
Revises: 0001_initial
Create Date: 2026-09-23
"""

from collections.abc import Sequence

import sqlalchemy as sa
from alembic import op

revision: str = "0002_user_avatar"
down_revision: str | None = "0001_initial"
branch_labels: str | Sequence[str] | None = None
depends_on: str | Sequence[str] | None = None


def upgrade() -> None:
    op.add_column("users", sa.Column("avatar_path", sa.String(255), nullable=True))


def downgrade() -> None:
    op.drop_column("users", "avatar_path")
