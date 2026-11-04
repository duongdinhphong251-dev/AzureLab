# AzureLab — kết quả nghiệm thu phần bắt buộc

Ngày kiểm thử: 04/11/2026.

Entry point: http://azurelab-b436d920.koreacentral.cloudapp.azure.com

## Kiểm thử từ internet qua Application Gateway

```text
PASS: health and readiness
PASS: create, read and search
PASS: update and stale-write protection
PASS: upload/download and invalid-image rejection
PASS: delete
```

Trang `/`, `/styles.css` và `/app.js` đều trả HTTP 200 với Content-Type phù hợp. Kiểm tra tự động này không thay thế việc duyệt giao diện thủ công trên Azure; công cụ browser trong phiên bàn giao không khởi tạo được. Giao diện cùng image đã được kiểm tra thêm/sửa ở phiên local trước.

Smoke test tạo dữ liệu riêng rồi xóa dữ liệu test. Dữ liệu sản phẩm lưu ở PostgreSQL Flexible Server thật; file ảnh lưu ở Azure Blob thật, không dùng Azurite trong AKS.

## AKS, replica và GitOps

- Hai worker node `Ready`.
- Backend: hai Pod `Ready`, mỗi Pod trên một node khác nhau.
- Frontend: hai Pod `Ready`, mỗi Pod trên một node khác nhau.
- Hai Service ứng dụng đều `ClusterIP`, không có external IP.
- Migration thành công qua ArgoCD Sync hook.
- ArgoCD Application `azurelab`: `Synced Healthy`.
- AGIC deployment: `1/1 Ready`.
- Ingress `azurelab`: `20.214.165.181`.

Backend và frontend dùng tag `0c0b974d92d4` trong ACR private. Manifest có required Pod anti-affinity theo hostname.

## Bảo vệ dữ liệu và private networking

- AKS API private; không bật public FQDN.
- VM quản trị không có public IP.
- ACR, Key Vault, Storage và PostgreSQL đều tắt public network access.
- Storage tắt Shared Key và anonymous Blob access.
- Container `product-images` private.
- Key Vault CSI mount secret vào Pod; backend sử dụng Workload Identity.
- PostgreSQL kết nối TLS `verify-full`, tài khoản app `azurelab_app`.
- Private DNS và Private Endpoint đã kiểm tra từ VM.

## Terraform

```text
No changes. Your infrastructure matches the configuration.
PLAN_EXIT_CODE=0
```

Đã đồng bộ zone PostgreSQL và service endpoint được Azure tạo; Terraform bỏ qua đúng hai tag quản lý của AGIC và cấu hình định tuyến mà AGIC sở hữu. Không áp dụng plan thay đổi mật khẩu trong kiểm tra drift.

## Giới hạn còn lại

- Entry point dùng HTTP; chưa có HTTPS với chứng chỉ được trình duyệt tin cậy.
- Ứng dụng chưa có đăng nhập/phân quyền người dùng.
- Chưa triển khai bonus HA/DR toàn bộ data services, chưa kiểm thử sự cố zone/region.
- Hai node đang dùng hết quota DSv4; cấu hình nâng cấp node AKS cần được điều chỉnh hoặc tăng quota trước khi nâng cấp cluster. Rolling update ứng dụng đã cấu hình không cần node mới.
