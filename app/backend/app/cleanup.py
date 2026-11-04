"""Retry pending deletions: python -m app.cleanup (safe to run as a CronJob)."""
import logging
from sqlalchemy import select
from .models import BlobDeletion

log = logging.getLogger(__name__)


def cleanup_pending(sessions, storage, limit=50):
    with sessions() as db:
        names = list(db.scalars(select(BlobDeletion.blob_name).limit(limit)))
    for name in names:
        try:
            storage.delete(name)
            with sessions() as db:
                entry = db.get(BlobDeletion, name)
                if entry:
                    db.delete(entry)
                    db.commit()
        except Exception:
            log.warning("Blob cleanup deferred; rerun the cleanup job")


if __name__ == "__main__":
    from .config import Settings
    from .database import make_engine, make_sessions
    from .storage import BlobStore
    settings = Settings.load()
    engine = make_engine(settings.database_url)
    storage = BlobStore(settings)
    try:
        cleanup_pending(make_sessions(engine), storage, limit=1000)
    finally:
        storage.close()
        engine.dispose()
