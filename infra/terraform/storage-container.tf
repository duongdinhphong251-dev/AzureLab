resource "azurerm_storage_container" "images" {
  name                  = "product-images"
  storage_account_id    = azurerm_storage_account.images.id
  container_access_type = "private"
}
