from alembic import context
from app.config import Settings
from app.database import make_engine
from app.models import Base

engine = make_engine(Settings.load().database_url)
with engine.connect() as connection:
    context.configure(connection=connection, target_metadata=Base.metadata)
    with context.begin_transaction():
        context.run_migrations()
engine.dispose()
