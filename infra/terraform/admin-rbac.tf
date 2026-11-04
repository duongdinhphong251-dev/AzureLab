resource "azurerm_role_assignment" "admin_acr" {
  scope                = azurerm_container_registry.main.id
  role_definition_name = "AcrPush"
  principal_id         = azurerm_linux_virtual_machine.admin.identity[0].principal_id
}

resource "azurerm_role_assignment" "admin_keyvault" {
  scope                = azurerm_key_vault.main.id
  role_definition_name = "Key Vault Secrets Officer"
  principal_id         = azurerm_linux_virtual_machine.admin.identity[0].principal_id
}

resource "azurerm_role_assignment" "admin_blob" {
  scope                = azurerm_storage_account.images.id
  role_definition_name = "Storage Blob Data Contributor"
  principal_id         = azurerm_linux_virtual_machine.admin.identity[0].principal_id
}
resource "azurerm_role_assignment" "admin_aks" {
  scope                = azurerm_kubernetes_cluster.main.id
  role_definition_name = "Azure Kubernetes Service Cluster Admin Role"
  principal_id         = azurerm_linux_virtual_machine.admin.identity[0].principal_id
}
