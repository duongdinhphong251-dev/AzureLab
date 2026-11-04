# Kiểm thử ứng dụng

## Local

- 13 unit tests backend sử dụng SQLite tạm và Blob giả lập đã pass.
- Kiểm tra cú pháp JavaScript thành công.
- Docker Compose build frontend/backend, chạy migration PostgreSQL 17 và kiểm tra readiness với Azurite 3.35.0 thành công.
- Smoke test qua Nginx đã pass: health/readiness, CRUD, tìm kiếm, kiểm tra xung đột phiên bản, upload/download và từ chối file giả.
- Đã kiểm tra thêm/sửa sản phẩm trên giao diện local; thống kê và trạng thái tồn kho cập nhật đúng.

## Azure

Ứng dụng đã được triển khai lên AKS và kiểm thử với PostgreSQL Flexible Server, Key Vault và Azure Blob Storage. Kết quả chi tiết: [docs/VERIFICATION.md](../docs/VERIFICATION.md).

## Giới hạn

Chưa kiểm thử tải lớn hoặc phục hồi sự cố zone/region. Ứng dụng chưa có đăng nhập/phân quyền người dùng. Ảnh được kiểm tra và mã hóa lại trước khi lưu.
