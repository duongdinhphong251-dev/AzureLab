# Kết quả kiểm thử

Ngày hoàn tất kiểm thử Docker: 03/11/2026.

## Đã kiểm tra

- 13 unit tests backend đã pass ở phiên tạo source (SQLite tạm và Blob giả lập).
- JavaScript: `node --check frontend/src/app.js` thành công.
- Docker Compose build thành công image frontend Nginx và backend Python 3.13.
- PostgreSQL 17 trong Docker: migration Alembic thành công, database healthy.
- Azurite 3.35.0 trong Docker: backend readiness healthy.
- Smoke test qua `http://127.0.0.1:8080` (Nginx → backend → PostgreSQL/Azurite) đã pass: health, readiness, create/read/search, update, stale update 409, upload/download ảnh, từ chối file giả, delete.
- Phiên trước đã kiểm tra thêm/sửa sản phẩm trong trình duyệt với PostgreSQL thật và Azurite; thống kê và trạng thái tồn kho cập nhật đúng.

## Chưa kiểm tra trên Azure

- Kết nối thực tế tới PostgreSQL Flexible Server, Key Vault CSI và Blob bằng Workload Identity.
- ACR push/pull, AGIC, ArgoCD, HTTPS và hai replica phân bố trên hai node.
- Tải lớn, HA/DR và phục hồi sự cố region.

Các mục này thuộc triển khai hạ tầng/GitOps ở checkpoint1. Docker Compose chỉ là môi trường local; không phải cấu hình triển khai AKS.

Ứng dụng chưa có đăng nhập/phân quyền người dùng. Ảnh được kiểm tra và mã hóa lại, không bảo đảm giữ nguyên byte file gốc.
