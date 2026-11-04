resource "azurerm_postgresql_flexible_server" "main" {
  name                = "psql-azurelab-${local.name_suffix}"
  location            = azurerm_resource_group.lab.location
  resource_group_name = azurerm_resource_group.lab.name

  version  = "17"
  sku_name = "B_Standard_B1ms"

  storage_mb = 32768

  administrator_login               = "labadmin"
  administrator_password_wo         = var.postgres_admin_password
  administrator_password_wo_version = 1

  delegated_subnet_id = azurerm_subnet.db.id
  private_dns_zone_id = azurerm_private_dns_zone.db.id

  public_network_access_enabled = false

  backup_retention_days        = 7
  geo_redundant_backup_enabled = false

  tags = azurerm_resource_group.lab.tags

  depends_on = [
    azurerm_private_dns_zone_virtual_network_link.db,
    azurerm_subnet_network_security_group_association.db
  ]
}

resource "azurerm_postgresql_flexible_server_database" "app" {
  name      = "azurelab"
  server_id = azurerm_postgresql_flexible_server.main.id

  charset   = "UTF8"
  collation = "en_US.utf8"
}