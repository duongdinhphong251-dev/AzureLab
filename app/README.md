# AzureLab — ứng dụng quản lý sản phẩm

Ứng dụng phục vụ bài lab AKS: tạo, xem, sửa, xóa sản phẩm; upload/download ảnh qua backend. Mã nguồn frontend/backend tách riêng. Phần Terraform, AGIC và ArgoCD tiếp tục làm ở **checkpoint1**; thư mục này không tự triển khai tài nguyên Azure.

## Chạy local bằng Docker Desktop

Yêu cầu: Docker Desktop đang chạy **Linux containers**, có Docker Compose.

Trong PowerShell của VS Code:

```powershell
cd E:\download\AzureLab\AzureLab\app
docker compose up --build -d
docker compose ps
```

Mở **http://localhost:8080**. API docs: **http://localhost:8080/api/docs**.

Lần đầu tải/build image có thể mất vài phút. Danh mục ban đầu rỗng; dùng nút **Thêm sản phẩm** để tạo dữ liệu thật. Không có dữ liệu giả tự thêm vào database.

Nếu cổng 8080 đã được sử dụng:

```powershell
$env:APP_PORT = "8081"
docker compose up --build -d
```

Sau đó mở http://localhost:8081.

Xem log khi có lỗi:

```powershell
docker compose logs --tail=100 backend migrate
docker compose logs --tail=100 db azurite frontend
```

Dừng ứng dụng (giữ dữ liệu):

```powershell
docker compose down
```

PostgreSQL và Azurite dùng Docker volumes nên dữ liệu còn sau khi restart/recreate containers. `docker compose down -v` **xóa dữ liệu local**; chỉ dùng khi chủ động muốn làm lại từ đầu.

### Các service trong Compose

| Service | Vai trò |
|---|---|
| `frontend` | Nginx phục vụ HTML/CSS/JavaScript và chuyển `/api/*` đến backend |
| `backend` | FastAPI, CRUD và xử lý ảnh |
| `db` | PostgreSQL 17 cho dữ liệu sản phẩm |
| `azurite` | Trình mô phỏng Azure Blob Storage, chỉ dùng local |
| `migrate` | Chạy `alembic upgrade head` một lần trước khi backend chạy |

Chỉ frontend mở cổng trên `127.0.0.1`; database, backend và Azurite ở mạng Docker nội bộ. Các mật khẩu/key mẫu trong Compose là **credential local cho lab**, không được tái sử dụng trên Azure. Có thể sao chép `.env.example` thành `.env` để tùy chỉnh. Nếu dùng ký tự đặc biệt trong mật khẩu DB của Compose, phải URL-encode mật khẩu trong DATABASE_URL hoặc chỉnh cấu hình kết nối tương ứng.

## Chức năng

- CRUD tên, danh mục, mô tả, giá VND và tồn kho.
- Tìm theo tên/danh mục; lọc còn hàng, sắp hết, hết hàng; phân trang.
- Thống kê trên toàn bộ danh mục, không chỉ trang đang xem.
- Upload JPG/PNG/WebP tối đa 5 MB; kiểm tra nội dung ảnh, xử lý hướng EXIF, thu nhỏ cạnh dài tối đa 2400 px và mã hóa lại. File tải xuống là ảnh đã xử lý, không nhất thiết giống byte của file gốc.
- Backend trả dữ liệu ảnh về browser; không trả public Blob URL hoặc SAS URL.
- Xác nhận trước khi xóa; hiển thị loading/empty/error rõ ràng.
- Kiểm tra phiên bản dữ liệu khi sửa/xóa/đổi ảnh; trả HTTP 409 nếu người khác đã sửa.
- Khi thông tin đã lưu nhưng upload ảnh thất bại, form giữ ID sản phẩm để thử lại không tạo trùng.

Ứng dụng lab này **chưa có đăng nhập/phân quyền người dùng**: người truy cập được API có thể CRUD. Private database/storage bảo vệ truy cập trực tiếp vào data services, không thay thế xác thực người dùng của ứng dụng.

## Cấu trúc source và nên đọc từ đâu

```text
app/
├── frontend/
│   ├── src/index.html          # Cấu trúc giao diện
│   ├── src/styles.css          # Bố cục desktop/mobile
│   ├── src/app.js              # Gọi API, form, tìm kiếm, upload
│   ├── nginx.conf.template     # Proxy local /api/*
│   └── Dockerfile
├── backend/
│   ├── app/main.py             # Các API endpoint
│   ├── app/schemas.py          # Kiểm tra dữ liệu đầu vào
│   ├── app/models.py           # Bảng products và hàng đợi dọn blob
│   ├── app/database.py         # Pool kết nối database
│   ├── app/storage.py          # Azure Blob SDK + Workload Identity
│   ├── app/images.py           # Kiểm tra và xử lý ảnh
│   ├── app/config.py           # Biến môi trường / file secret
│   ├── app/cleanup.py          # Thử lại các lần xóa blob thất bại
│   ├── migrations/            # Alembic schema migrations
│   ├── tests/                 # Kiểm thử API và config
│   ├── requirements.txt       # Phiên bản thư viện runtime đã kiểm thử
│   └── Dockerfile
├── compose.yaml
└── README.md
```

Nên đọc `schemas.py` → `models.py` → các API CRUD trong `main.py` → `frontend/src/app.js`. Sau đó đọc `storage.py` để hiểu đường đi của ảnh.

## API

| Method | Path | Chức năng |
|---|---|---|
| GET | `/api/products?q=&status=all&page=1&page_size=12` | Danh sách (`status`: all/available/low/empty) |
| POST | `/api/products` | Tạo sản phẩm |
| GET | `/api/products/{id}` | Chi tiết |
| PUT | `/api/products/{id}` | Cập nhật toàn bộ thông tin, kèm `version` |
| DELETE | `/api/products/{id}?version=N` | Xóa sản phẩm và lên lịch dọn ảnh |
| POST | `/api/products/{id}/image?version=N` | Upload multipart, trường `file` |
| GET | `/api/products/{id}/image` | Xem ảnh |
| GET | `/api/products/{id}/image?download=true` | Download ảnh |
| DELETE | `/api/products/{id}/image?version=N` | Xóa ảnh |
| GET | `/api/summary` | Thống kê danh mục |
| GET | `/api/health` | Liveness: tiến trình API hoạt động |
| GET | `/api/ready` | Readiness: truy cập được DB/schema và Blob container |

Ví dụ body tạo sản phẩm:

```json
{
  "name": "Bàn phím không dây",
  "category": "Phụ kiện",
  "description": "Kết nối Bluetooth",
  "price": "450000.00",
  "stock": 12
}
```

Giá trả về dạng chuỗi decimal để tránh sai số float. PUT dùng các trường trên và thêm `version` từ GET gần nhất. ID là UUID do backend tạo. OpenAPI tại `/api/docs` cho phép thử API trực tiếp.

## Khi nối với AKS và dịch vụ Azure thật

### Backend

Image chạy port **8080**, dưới user không phải root. Không lưu ảnh hoặc dữ liệu ứng dụng vào ổ đĩa Pod.

| Biến | Giá trị / ý nghĩa |
|---|---|
| `APP_ENV` | `azure` (mặc định) |
| `DATABASE_URL_FILE` | Ví dụ `/mnt/secrets-store/database-url`; file chứa connection string từ Key Vault CSI |
| `DATABASE_URL` | Chỉ dùng khi không đặt `DATABASE_URL_FILE`; không ghi giá trị thật vào Git |
| `AZURE_STORAGE_ACCOUNT_URL` | `https://<account>.blob.core.windows.net` |
| `AZURE_STORAGE_CONTAINER` | `product-images` |

Connection string PostgreSQL dùng SQLAlchemy driver `postgresql+psycopg`. Ví dụ **mẫu**, không phải credential thật:

```text
postgresql+psycopg://APP_USER:URL_ENCODED_PASSWORD@SERVER.postgres.database.azure.com:5432/azurelab?sslmode=verify-full&sslrootcert=/etc/ssl/certs/ca-certificates.crt
```

- Tạo database/schema bằng migration Job dùng cùng backend image: `alembic upgrade head`. Job có thể dùng identity/credential riêng có quyền DDL; backend runtime chỉ cần quyền đọc/ghi bảng.
- Không chạy migration đồng thời trong mọi backend Pod. Khi thêm schema migration mới, tạo file migration có thứ tự; đừng sửa file `001_products.py` đã apply.
- Runtime dùng `DefaultAzureCredential`, hỗ trợ AKS Workload Identity. Cấu hình OIDC/federated identity, ServiceAccount và nhãn `azure.workload.identity/use: "true"` trong phần hạ tầng/GitOps.
- Backend identity cần `Storage Blob Data Contributor` trên container ảnh. Container phải được Terraform tạo trước; backend Azure không tự tạo container.
- Key Vault CSI cần quyền đọc secret và mount đúng file. Nếu secret thay đổi, thực hiện rollout backend để tạo lại DB connection pool; code đọc file ở lúc khởi động.
- Dùng hostname chuẩn của Azure; Private DNS sẽ phân giải thành private IP. Không hardcode private IP.
- `AZURITE_CONNECTION_STRING` bị từ chối khi `APP_ENV` khác `local`; không dùng emulator key trong Azure.

### Frontend / AGIC

- Frontend image chạy port **8080**. `/healthz` là health endpoint.
- JavaScript gọi đường dẫn tương đối `/api/*`, không có URL backend riêng được hardcode.
- AGIC route `/` → frontend Service, `/api/*` → backend Service; giữ nguyên tiền tố `/api`.
- Nếu dùng proxy Nginx, `BACKEND_HOST` mặc định `backend`, `BACKEND_PORT` mặc định `8080`; đặt tên Service tương ứng hoặc đổi env này. Nginx cần phân giải hostname backend ngay khi khởi động.
- Frontend local giới hạn request 6 MB. Khi AGIC route thẳng backend, đặt giới hạn upload/request phù hợp trên gateway/WAF và cho phép multipart upload tới 5 MB cộng phần bao gói.
- Backend liveness: `/api/health`; readiness: `/api/ready`. Frontend dùng `/healthz`.
- Hai replicas không cần sticky session: dữ liệu chung ở PostgreSQL/Blob; version kiểm soát chỉnh sửa đồng thời.
- Replicas, anti-affinity, NSG, ACR, AGIC, DNS, Key Vault, pipeline, ArgoCD và quyền truy cập là phần tiếp theo của lab, chưa được ứng dụng này triển khai.

### Dọn ảnh cũ

Khi thay/xóa ảnh hoặc xóa sản phẩm, database ghi yêu cầu xóa blob vào `blob_deletions` cùng transaction. Backend thử dọn sau request. Nếu Storage tạm lỗi, entry vẫn còn để chạy lại:

```powershell
docker compose exec backend python -m app.cleanup
```

Trên AKS, có thể dùng CronJob chạy lệnh này bằng cùng image và identity. Job dọn tối đa 1.000 entry mỗi lượt. PostgreSQL và Blob không có transaction chung: một tiến trình bị dừng đột ngột sau upload nhưng trước DB commit vẫn có thể để lại blob mồ côi. Bản lab chưa có tác vụ đối soát định kỳ toàn bộ blob; cần bổ sung nếu vận hành lâu dài.

## Kiểm thử tự động

Trong thư mục `backend`, dùng Python 3.13:

```powershell
python -m venv .venv
.\.venv\Scripts\python.exe -m pip install -r requirements-dev.txt
.\.venv\Scripts\python.exe -m pytest tests -q
```

Tests dùng SQLite tạm và mock Blob để kiểm tra logic nhanh; không thay PostgreSQL/Blob trong ứng dụng thật. Phải kiểm tra thêm qua Compose/PostgreSQL và Azure sau khi triển khai.

Kiểm thử xuyên suốt một instance đang chạy (tạo rồi tự xóa **chỉ sản phẩm test của nó**):

```powershell
python scripts/smoke_test.py --url http://localhost:8080
```

Script chỉ dùng thư viện chuẩn Python. Kiểm tra health, CRUD, giá decimal, stale update, upload/download ảnh và từ chối file giả. Xem `VERIFICATION.md` để biết những bước thực sự đã được chạy trong phiên tạo source.

## Dữ liệu và quyền sở hữu

Không có seed tự động, secret Azure hoặc credential cloud trong source. `.env` được bỏ qua bởi Git. Source này nằm trong `app/` của repo; Terraform và GitOps ở ngoài thư mục này vẫn do bạn tiếp tục thực hành.
