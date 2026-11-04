import pytest
from app.config import Settings


def test_mount_file_overrides_environment(tmp_path, monkeypatch):
    secret = tmp_path / "db-url"
    secret.write_text("postgresql+psycopg://user:example@db/app\n")
    monkeypatch.setenv("DATABASE_URL_FILE", str(secret))
    monkeypatch.setenv("DATABASE_URL", "wrong")
    monkeypatch.setenv("APP_ENV", "azure")
    monkeypatch.setenv("AZURE_STORAGE_ACCOUNT_URL", "https://account.blob.core.windows.net")
    monkeypatch.delenv("AZURITE_CONNECTION_STRING", raising=False)
    assert Settings.load().database_url.endswith("@db/app")


def test_cloud_rejects_emulator_credentials(monkeypatch):
    monkeypatch.delenv("DATABASE_URL_FILE", raising=False)
    monkeypatch.setenv("DATABASE_URL", "postgresql+psycopg://db/app")
    monkeypatch.setenv("APP_ENV", "azure")
    monkeypatch.setenv("AZURITE_CONNECTION_STRING", "emulator")
    with pytest.raises(RuntimeError, match="only allowed"):
        Settings.load()
