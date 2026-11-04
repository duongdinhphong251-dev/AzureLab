import io
from decimal import Decimal
from uuid import uuid4

import pytest
from azure.core.exceptions import AzureError, ResourceNotFoundError
from fastapi.testclient import TestClient
from PIL import Image
from sqlalchemy import select

from app.config import Settings
from app.database import make_engine, make_sessions
from app.main import create_app
from app.models import Base, BlobDeletion
from app.cleanup import cleanup_pending


class MemoryBlobs:
    def __init__(self):
        self.items = {}
        self.fail_upload = False
        self.fail_delete = False
    def prepare_local_container(self): pass
    def close(self): pass
    def check(self): pass
    def upload(self, name, data, content_type):
        if self.fail_upload: raise AzureError("simulated storage outage")
        self.items[name] = data
    def download(self, name):
        if name not in self.items: raise ResourceNotFoundError("missing")
        return self.items[name]
    def delete(self, name):
        if self.fail_delete: raise AzureError("simulated cleanup outage")
        self.items.pop(name, None)


@pytest.fixture
def system(tmp_path):
    url = f"sqlite:///{tmp_path / 'test.db'}"
    settings = Settings(url, "local", "", "images", "")
    engine = make_engine(url)
    Base.metadata.create_all(engine)
    storage = MemoryBlobs()
    with TestClient(create_app(settings, engine, storage)) as client:
        yield client, storage, engine


def product(client, **changes):
    body = {"name": "Bàn phím", "category": "Phụ kiện", "description": "Không dây", "price": "450000.50", "stock": 8}
    body.update(changes)
    response = client.post("/api/products", json=body)
    assert response.status_code == 201, response.text
    return response.json()


def picture():
    stream = io.BytesIO()
    Image.new("RGB", (80, 60), "purple").save(stream, "PNG")
    return stream.getvalue()


def upload(client, p):
    return client.post(f'/api/products/{p["id"]}/image?version={p["version"]}', files={"file": ("photo.png", picture(), "image/png")})


def test_crud_search_filter_pagination_and_summary(system):
    client, _, _ = system
    first = product(client)
    product(client, name="Sổ tay", category="Văn phòng", stock=0, price="50000")
    product(client, name="Bình nước", stock=3, price="120000")
    assert client.get("/api/products", params={"q": "Bàn"}).json()["total"] == 1
    assert client.get("/api/products", params={"q": "%"}).json()["total"] == 0
    assert client.get("/api/products?status=low").json()["total"] == 1
    assert client.get("/api/products?status=empty").json()["total"] == 1
    assert len(client.get("/api/products?page_size=2&page=2").json()["items"]) == 1
    summary = client.get("/api/summary").json()
    assert summary["products"] == 3 and summary["units"] == 11 and summary["low_stock"] == 2
    assert Decimal(summary["inventory_value"]) == Decimal("3960004.00")
    body = {"name": "Bàn phím mới", "category": "Phụ kiện", "description": "", "price": "99.99", "stock": 1, "version": first["version"]}
    path = f'/api/products/{first["id"]}'
    updated = client.put(path, json=body)
    assert updated.status_code == 200
    assert updated.json()["version"] > first["version"]
    assert client.put(path, json=body).status_code == 409
    assert client.delete(path, params={"version": first["version"]}).status_code == 409
    assert client.delete(path, params={"version": updated.json()["version"]}).status_code == 204
    assert client.get(path).status_code == 404


@pytest.mark.parametrize("changes", [{"name": "   "}, {"price": "-1"}, {"price": "1.001"}, {"stock": -1}, {"stock": 1.5}, {"unexpected": "x"}])
def test_reject_invalid_product(system, changes):
    client, _, _ = system
    body = {"name": "Test", "price": "10", "stock": 1}
    body.update(changes)
    assert client.post("/api/products", json=body).status_code == 422


def test_image_roundtrip_replace_delete_and_product_delete(system):
    client, storage, _ = system
    p = product(client)
    assert client.get(f'/api/products/{p["id"]}/image').status_code == 404
    p = upload(client, p).json()
    assert p["image_url"].startswith("/api/") and len(storage.items) == 1
    response = client.get(p["image_url"] + "&download=true")
    assert response.status_code == 200 and response.headers["content-type"] == "image/jpeg"
    assert "attachment" in response.headers["content-disposition"]
    assert response.headers["x-content-type-options"] == "nosniff"
    Image.open(io.BytesIO(response.content)).verify()
    old_names = set(storage.items)
    p = upload(client, p).json()
    assert len(storage.items) == 1 and not (old_names & set(storage.items))
    assert client.delete(f'/api/products/{p["id"]}/image', params={"version": p["version"]}).status_code == 204
    assert not storage.items
    p = client.get(f'/api/products/{p["id"]}').json()
    p = upload(client, p).json()
    assert client.delete(f'/api/products/{p["id"]}', params={"version": p["version"]}).status_code == 204
    assert not storage.items


def test_invalid_file_and_limit(system):
    client, storage, _ = system
    p = product(client)
    path = f'/api/products/{p["id"]}/image?version={p["version"]}'
    assert client.post(path, files={"file": ("fake.png", b"<script>alert(1)</script>", "image/png")}).status_code == 415
    assert client.post(path, files={"file": ("big.png", b"a" * (5 * 1024 * 1024 + 1), "image/png")}).status_code == 413
    assert not storage.items


def test_blob_failure_preserves_existing_image_and_retries_cleanup(system):
    client, storage, engine = system
    p = upload(client, product(client)).json()
    original = p["image_url"]
    storage.fail_upload = True
    assert upload(client, p).status_code == 503
    assert client.get(f'/api/products/{p["id"]}').json()["image_url"] == original
    storage.fail_upload = False
    storage.fail_delete = True
    p = upload(client, p).json()
    assert len(storage.items) == 2
    sessions = make_sessions(engine)
    with sessions() as db: assert len(list(db.scalars(select(BlobDeletion)))) == 1
    storage.fail_delete = False
    cleanup_pending(sessions, storage)
    assert len(storage.items) == 1
    with sessions() as db: assert len(list(db.scalars(select(BlobDeletion)))) == 0


def test_health_missing_and_stale_upload(system):
    client, storage, _ = system
    assert client.get("/api/health").status_code == 200
    assert client.get("/api/ready").status_code == 200
    assert client.get(f"/api/products/{uuid4()}").status_code == 404
    assert client.get("/api/products/not-a-uuid").status_code == 422
    p = product(client)
    assert upload(client, p).status_code == 200
    assert upload(client, p).status_code == 409
    assert len(storage.items) == 1
