resource "azurerm_user_assigned_identity" "backend" {
  name                = "id-backend-azurelab-dev"
  location            = azurerm_resource_group.lab.location
  resource_group_name = azurerm_resource_group.lab.name

  tags = azurerm_resource_group.lab.tags
}

resource "azurerm_federated_identity_credential" "backend" {
  name                      = "fic-backend"
  user_assigned_identity_id = azurerm_user_assigned_identity.backend.id

  issuer   = azurerm_kubernetes_cluster.main.oidc_issuer_url
  subject  = "system:serviceaccount:azurelab:backend"
  audience = ["api://AzureADTokenExchange"]
}


resource "azurerm_role_assignment" "backend_keyvault" {
  scope                = azurerm_key_vault.main.id
  role_definition_name = "Key Vault Secrets User"
  principal_id         = azurerm_user_assigned_identity.backend.principal_id
}

resource "azurerm_role_assignment" "backend_blob" {
  scope                = azurerm_storage_account.images.id
  role_definition_name = "Storage Blob Data Contributor"
  principal_id         = azurerm_user_assigned_identity.backend.principal_id
}

