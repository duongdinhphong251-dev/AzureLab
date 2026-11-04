variable "postgres_admin_password" {
  description = "Mật khẩu quản trị PostgreSQL"
  type        = string

  sensitive = true // che giá trị 
  ephemeral = true // ko lưu vô plan
}