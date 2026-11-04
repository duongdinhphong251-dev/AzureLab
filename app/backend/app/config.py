import os
from dataclasses import dataclass
from pathlib import Path


@dataclass(frozen=True)
class Settings:
    database_url: str
    environment: str
    storage_account_url: str
    storage_container: str
    storage_connection_string: str
    max_image_bytes: int = 5 * 1024 * 1024

    @classmethod
    def load(cls):
        # Key Vault CSI mounts the connection string as a file in AKS.
        secret_file = os.getenv("DATABASE_URL_FILE")
        database_url = (Path(secret_file).read_text().strip() if secret_file
                        else os.getenv("DATABASE_URL", ""))
        if not database_url:
            raise RuntimeError("Set DATABASE_URL_FILE or DATABASE_URL")
        environment = os.getenv("APP_ENV", "azure")
        connection = os.getenv("AZURITE_CONNECTION_STRING", "")
        account_url = os.getenv("AZURE_STORAGE_ACCOUNT_URL", "")
        if environment != "local" and connection:
            raise RuntimeError("AZURITE_CONNECTION_STRING is only allowed with APP_ENV=local")
        if environment != "local" and not account_url.startswith("https://"):
            raise RuntimeError("Azure storage requires an HTTPS AZURE_STORAGE_ACCOUNT_URL")
        return cls(database_url, environment, account_url,
                   os.getenv("AZURE_STORAGE_CONTAINER", "product-images"), connection)
