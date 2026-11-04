# AzureLab

CRUD quản lý sản phẩm với frontend HTML/CSS/JavaScript và backend FastAPI. PostgreSQL Flexible Server lưu dữ liệu; Azure Blob Storage lưu ảnh. Source ứng dụng nằm trong `app/`.

## Triển khai Azure

- Application entry point: `http://azurelab-b436d920.koreacentral.cloudapp.azure.com`
- API documentation: `/api/docs`
- IaC: `infra/terraform/`
- GitOps: `gitops/app/`, ArgoCD Application: `gitops/application.yaml`
- Hướng dẫn kiến trúc, cập nhật và giới hạn: [docs/DEPLOYMENT.md](docs/DEPLOYMENT.md)
- Chạy local và API contract: [app/README.md](app/README.md)

## Thành phần

- AKS private, hai worker node; frontend/backend mỗi loại hai replica phân bố khác node.
- Application Gateway + AGIC cung cấp entry point public duy nhất cho ứng dụng.
- ACR Premium, Key Vault và Blob dùng Private Endpoint, public network access tắt.
- PostgreSQL dùng delegated subnet và Private DNS, không public access.
- Workload Identity + Key Vault CSI cung cấp credential cho backend; không lưu mật khẩu trong Git.
- ArgoCD quản lý triển khai từ Git. Build/push image thủ công trên VM private, không dùng GitHub Actions.

## Kiểm thử

Kết quả nghiệm thu Azure: [docs/VERIFICATION.md](docs/VERIFICATION.md). ArgoCD đã Synced/Healthy; CRUD và ảnh đã kiểm thử thành công qua Application Gateway.

Smoke test có trong `app/scripts/smoke_test.py`, kiểm tra health/readiness, CRUD, tìm kiếm, stale update, upload/download và từ chối file giả. Dữ liệu kiểm thử được tạo rồi xóa bởi script.

```powershell
python app/scripts/smoke_test.py --url http://azurelab-b436d920.koreacentral.cloudapp.azure.com
```

## Phạm vi bản lab

Entry point hiện dùng HTTP, chưa có HTTPS với chứng chỉ được trình duyệt tin cậy. Ứng dụng chưa có đăng nhập/phân quyền người dùng. Bonus HA/DR toàn bộ data services chưa triển khai; xem chi tiết trong tài liệu vận hành.
