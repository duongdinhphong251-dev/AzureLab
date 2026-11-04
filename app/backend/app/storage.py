from azure.core.exceptions import ResourceExistsError, ResourceNotFoundError
from azure.identity import DefaultAzureCredential
from azure.storage.blob import BlobServiceClient, ContentSettings


class BlobStore:
    def __init__(self, settings):
        self.credential = None
        options = {"retry_total": 2, "connection_timeout": 5, "read_timeout": 15}
        if settings.environment == "local" and settings.storage_connection_string:
            self.service = BlobServiceClient.from_connection_string(
                settings.storage_connection_string, **options)
        else:
            self.credential = DefaultAzureCredential()
            self.service = BlobServiceClient(account_url=settings.storage_account_url,
                                             credential=self.credential, **options)
        self.container = self.service.get_container_client(settings.storage_container)
        self.local = settings.environment == "local"

    def prepare_local_container(self):
        # Cloud container is provisioned by Terraform, not by every backend Pod.
        if self.local:
            try:
                self.container.create_container()
            except ResourceExistsError:
                pass

    def upload(self, name, data, content_type):
        self.container.upload_blob(name, data, overwrite=False,
                                   content_settings=ContentSettings(content_type=content_type))

    def download(self, name):
        return self.container.download_blob(name).readall()

    def delete(self, name):
        try:
            self.container.delete_blob(name)
        except ResourceNotFoundError:
            pass

    def check(self):
        self.container.get_container_properties()

    def close(self):
        self.service.close()
        if self.credential:
            self.credential.close()
