"""Initial product and blob cleanup tables."""
from alembic import op
import sqlalchemy as sa

revision = "001_products"
down_revision = None
branch_labels = None
depends_on = None


def upgrade():
    op.create_table("products",
        sa.Column("id", sa.Uuid(), primary_key=True),
        sa.Column("name", sa.String(120), nullable=False),
        sa.Column("description", sa.Text(), nullable=False),
        sa.Column("category", sa.String(60), nullable=False),
        sa.Column("price", sa.Numeric(12, 2), nullable=False),
        sa.Column("stock", sa.Integer(), nullable=False),
        sa.Column("image_blob_name", sa.String(200)),
        sa.Column("image_content_type", sa.String(40)),
        sa.Column("version", sa.Integer(), nullable=False),
        sa.Column("created_at", sa.DateTime(timezone=True), nullable=False),
        sa.Column("updated_at", sa.DateTime(timezone=True), nullable=False),
        sa.CheckConstraint("price >= 0", name="price_nonnegative"),
        sa.CheckConstraint("stock >= 0", name="stock_nonnegative"))
    op.create_table("blob_deletions", sa.Column("blob_name", sa.String(200), primary_key=True))


def downgrade():
    op.drop_table("blob_deletions")
    op.drop_table("products")
