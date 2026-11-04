from sqlalchemy import create_engine
from sqlalchemy.orm import sessionmaker


def make_engine(url):
    kwargs = {"pool_pre_ping": True}
    if url.startswith("postgresql"):
        kwargs["connect_args"] = {"connect_timeout": 5}
        kwargs.update(pool_size=5, max_overflow=5)
    elif url.startswith("sqlite"):
        # SQLite is for automated tests only; deployed/local app uses PostgreSQL.
        kwargs["connect_args"] = {"check_same_thread": False}
    return create_engine(url, **kwargs)


def make_sessions(engine):
    return sessionmaker(bind=engine, expire_on_commit=False)
