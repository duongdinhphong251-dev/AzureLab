resource "azurerm_virtual_network" "main" {
  name                = "vnet-azurelab-dev"
  location            = azurerm_resource_group.lab.location
  resource_group_name = azurerm_resource_group.lab.name
  address_space       = ["10.20.0.0/16"]

  tags = azurerm_resource_group.lab.tags
}

resource "azurerm_subnet" "appgw" {
  name                 = "snet-appgw"
  resource_group_name  = azurerm_resource_group.lab.name
  virtual_network_name = azurerm_virtual_network.main.name
  address_prefixes     = ["10.20.0.0/24"]
}

resource "azurerm_subnet" "aks" {
  name                 = "snet_aks"
  resource_group_name  = azurerm_resource_group.lab.name
  virtual_network_name = azurerm_virtual_network.main.name
  address_prefixes     = ["10.20.4.0/22"]
}

resource "azurerm_subnet" "pe" {
  name                 = "snet_pe"
  resource_group_name  = azurerm_resource_group.lab.name
  virtual_network_name = azurerm_virtual_network.main.name
  address_prefixes     = ["10.20.8.0/24"]

  private_endpoint_network_policies = "NetworkSecurityGroupEnabled" // cho phép Nsg áp dụng lên PE 
}

resource "azurerm_subnet" "db" {
  name                 = "snet_db"
  resource_group_name  = azurerm_resource_group.lab.name
  virtual_network_name = azurerm_virtual_network.main.name
  address_prefixes     = ["10.20.9.0/24"]
  service_endpoints    = ["Microsoft.Storage"]

  delegation { // giao snet cho 1 dich vu azure sử dụng 
    name = "postgresql-delegation"

    service_delegation {
      name = "Microsoft.DBforPostgreSQL/flexibleServers" // tên định danh của azure

      actions = ["Microsoft.Network/virtualNetworks/subnets/join/action"] // cho phép thực hiện thao tác 
    }
  }
}