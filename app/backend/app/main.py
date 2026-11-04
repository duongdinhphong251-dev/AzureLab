from contextlib import asynccontextmanager
from uuid import UUID, uuid4

from azure.core.exceptions import AzureError, ResourceNotFoundError
from fastapi import BackgroundTasks, FastAPI, File, HTTPException, Query, Request, Response, UploadFile
from fastapi.responses import JSONResponse
from sqlalchemy import func, or_, select, text
from sqlalchemy.exc import SQLAlchemyError
from sqlalchemy.orm.exc import StaleDataError

from .cleanup import cleanup_pending
from .config import Settings
from .database import make_engine, make_sessions
from .images import normalize_image
from .models import BlobDeletion, Product
from .schemas import ProductInput, ProductUpdate
from .storage import BlobStore


def serialize(p):
    return {
        "id": str(p.id), "name": p.name, "description": p.description,
        "category": p.category, "price": str(p.price), "stock": p.stock,
        "version": p.version, "created_at": p.created_at.isoformat(),
        "updated_at": p.updated_at.isoformat(),
        "image_url": f"/api/products/{p.id}/image?v={p.version}" if p.image_blob_name else None,
    }


def create_app(settings=None, engine=None, storage=None):
    settings = settings or Settings.load()
    engine = engine or make_engine(settings.database_url)
    sessions = make_sessions(engine)
    storage = storage or BlobStore(settings)

    @asynccontextmanager
    async def lifespan(app):
        # Database schema migration is a separate one-shot job, never per Pod.
        storage.prepare_local_container()
        yield
        storage.close()
        engine.dispose()

    app = FastAPI(title="AzureLab Product API", version="1.0.0", lifespan=lifespan,
                  docs_url="/api/docs", openapi_url="/api/openapi.json", redoc_url=None)

    @app.exception_handler(StaleDataError)
    async def stale_error(request, exc):
        return JSONResponse(status_code=409, content={"detail": "Dữ liệu đã thay đổi. Hãy tải lại rồi thử lại."})

    @app.exception_handler(SQLAlchemyError)
    async def database_error(request, exc):
        # Do not expose SQL parameters, credentials or connection strings.
        return JSONResponse(status_code=503, content={"detail": "Chưa kết nối được database. Vui lòng thử lại."})

    @app.exception_handler(AzureError)
    async def storage_error(request, exc):
        return JSONResponse(status_code=503, content={"detail": "Kho ảnh tạm thời không khả dụng. Vui lòng thử lại."})

    @app.middleware("http")
    async def headers(request: Request, call_next):
        response = await call_next(request)
        response.headers["X-Content-Type-Options"] = "nosniff"
        response.headers["Cache-Control"] = "no-store"
        return response

    def find_product(db, product_id, lock=False):
        stmt = select(Product).where(Product.id == product_id)
        if lock:
            stmt = stmt.with_for_update()
        product = db.scalar(stmt)
        if not product:
            raise HTTPException(404, "Không tìm thấy sản phẩm.")
        return product

    @app.get("/api/health")
    def health():
        return {"status": "ok"}

    @app.get("/api/ready")
    def ready():
        with sessions() as db:
            db.execute(text("SELECT 1"))
            db.execute(select(Product.id).limit(1))
        storage.check()
        return {"status": "ready"}

    @app.get("/api/summary")
    def summary():
        with sessions() as db:
            count, units, value = db.execute(select(
                func.count(Product.id), func.coalesce(func.sum(Product.stock), 0),
                func.coalesce(func.sum(Product.stock * Product.price), 0))).one()
            low = db.scalar(select(func.count()).select_from(Product).where(Product.stock <= 5))
            return {"products": count, "units": units, "inventory_value": str(value), "low_stock": low}

    @app.get("/api/products")
    def list_products(q: str = Query("", max_length=120), status: str = Query("all", pattern="^(all|available|low|empty)$"),
                      page: int = Query(1, ge=1), page_size: int = Query(12, ge=1, le=100)):
        conditions = []
        if q.strip():
            conditions.append(or_(Product.name.icontains(q.strip(), autoescape=True),
                                  Product.category.icontains(q.strip(), autoescape=True)))
        if status == "available": conditions.append(Product.stock > 5)
        if status == "low": conditions.append(Product.stock.between(1, 5))
        if status == "empty": conditions.append(Product.stock == 0)
        with sessions() as db:
            total = db.scalar(select(func.count()).select_from(Product).where(*conditions))
            items = db.scalars(select(Product).where(*conditions).order_by(Product.created_at.desc(), Product.id)
                               .offset((page - 1) * page_size).limit(page_size))
            return {"items": [serialize(p) for p in items], "total": total, "page": page, "page_size": page_size}

    @app.post("/api/products", status_code=201)
    def create_product(body: ProductInput):
        with sessions() as db:
            product = Product(**body.model_dump())
            db.add(product)
            db.commit()
            return serialize(product)

    @app.get("/api/products/{product_id}")
    def get_product(product_id: UUID):
        with sessions() as db:
            return serialize(find_product(db, product_id))

    @app.put("/api/products/{product_id}")
    def update_product(product_id: UUID, body: ProductUpdate):
        with sessions() as db:
            product = find_product(db, product_id, lock=True)
            if product.version != body.version:
                raise HTTPException(409, "Sản phẩm đã được chỉnh sửa ở nơi khác. Đóng form và tải lại.")
            for key, value in body.model_dump(exclude={"version"}).items():
                setattr(product, key, value)
            db.commit()
            return serialize(product)

    @app.delete("/api/products/{product_id}", status_code=204)
    def delete_product(product_id: UUID, background: BackgroundTasks, version: int = Query(..., ge=1)):
        with sessions() as db:
            product = find_product(db, product_id, lock=True)
            if product.version != version:
                raise HTTPException(409, "Dữ liệu đã thay đổi. Hãy tải lại trước khi xóa.")
            if product.image_blob_name:
                db.add(BlobDeletion(blob_name=product.image_blob_name))
            db.delete(product)
            db.commit()
        background.add_task(cleanup_pending, sessions, storage)
        return Response(status_code=204)

    @app.post("/api/products/{product_id}/image")
    def upload_image(product_id: UUID, background: BackgroundTasks,
                     version: int = Query(..., ge=1), file: UploadFile = File(...)):
        try:
            data, content_type, extension = normalize_image(file.file.read(settings.max_image_bytes + 1), settings.max_image_bytes)
        finally:
            file.file.close()
        blob_name = f"products/{product_id}/{uuid4()}.{extension}"
        # Upload a unique blob before switching the DB pointer. Old blobs are queued
        # transactionally for deletion. Best-effort compensation removes a new blob
        # if the DB update fails (a hard process crash can still leave an orphan).
        uploaded = False
        try:
            with sessions() as db:
                product = find_product(db, product_id, lock=True)
                if product.version != version:
                    raise HTTPException(409, "Sản phẩm đã thay đổi. Hãy tải lại trước khi cập nhật ảnh.")
                storage.upload(blob_name, data, content_type)
                uploaded = True
                if product.image_blob_name:
                    db.add(BlobDeletion(blob_name=product.image_blob_name))
                product.image_blob_name = blob_name
                product.image_content_type = content_type
                db.commit()
                result = serialize(product)
        except Exception:
            if uploaded:
                try:
                    storage.delete(blob_name)
                except Exception:
                    with sessions() as retry_db:
                        retry_db.merge(BlobDeletion(blob_name=blob_name))
                        retry_db.commit()
            raise
        background.add_task(cleanup_pending, sessions, storage)
        return result

    @app.get("/api/products/{product_id}/image")
    def download_image(product_id: UUID, download: bool = False):
        with sessions() as db:
            product = find_product(db, product_id)
            if not product.image_blob_name:
                raise HTTPException(404, "Sản phẩm chưa có ảnh.")
            blob_name, content_type = product.image_blob_name, product.image_content_type
        try:
            data = storage.download(blob_name)
        except ResourceNotFoundError:
            raise HTTPException(404, "Không tìm thấy ảnh trong kho lưu trữ.")
        suffix = "png" if content_type == "image/png" else "jpg"
        mode = "attachment" if download else "inline"
        return Response(data, media_type=content_type,
                        headers={"Content-Disposition": f'{mode}; filename="product-{product_id}.{suffix}"'})

    @app.delete("/api/products/{product_id}/image", status_code=204)
    def delete_image(product_id: UUID, background: BackgroundTasks, version: int = Query(..., ge=1)):
        with sessions() as db:
            product = find_product(db, product_id, lock=True)
            if product.version != version:
                raise HTTPException(409, "Sản phẩm đã thay đổi. Hãy tải lại.")
            if product.image_blob_name:
                db.add(BlobDeletion(blob_name=product.image_blob_name))
                product.image_blob_name = None
                product.image_content_type = None
                db.commit()
        background.add_task(cleanup_pending, sessions, storage)
        return Response(status_code=204)

    return app
