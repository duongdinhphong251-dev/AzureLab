output "acr_name" {
  description = "Tên Azure Container Registry"
  value       = azurerm_container_registry.main.name
}

output "acr_login_server" {
  description = "Địa chỉ dùng trong tên container image"
  value       = azurerm_container_registry.main.login_server
}

output "aks_name" {
  description = "Tên AKS cluster"
  value       = azurerm_kubernetes_cluster.main.name
}

output "key_vault_name" {
  value = azurerm_key_vault.main.name
}

output "key_vault_uri" {
  value = azurerm_key_vault.main.vault_uri
}

output "storage_account_name" {
  value = azurerm_storage_account.images.name
}

output "blob_service_url" {
  value = azurerm_storage_account.images.primary_blob_endpoint
}

output "admin_vm_name" {
  value = azurerm_linux_virtual_machine.admin.name
}

output "admin_vm_private_ip" {
  value = azurerm_network_interface.admin.private_ip_address
}

output "backend_identity_client_id" {
  description = "Client ID để cấu hình ServiceAccount backend"
  value       = azurerm_user_assigned_identity.backend.client_id
}

output "azure_tenant_id" {
  description = "Tenant ID để cấu hình tích hợp Key Vault"
  value       = data.azurerm_client_config.current.tenant_id
}

output "postgres_server_name" {
  value = azurerm_postgresql_flexible_server.main.name
}

output "postgres_fqdn" {
  value = azurerm_postgresql_flexible_server.main.fqdn
}

output "postgres_database_name" {
  value = azurerm_postgresql_flexible_server_database.app.name
}