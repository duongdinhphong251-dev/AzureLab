resource "azurerm_network_security_group" "db" {
  name                = "nsg-db"
  location            = azurerm_resource_group.lab.location
  resource_group_name = azurerm_resource_group.lab.name

  security_rule { // quy tắc lọc kết nối 
    name                       = "Allow-PostgreSQL"
    priority                   = 100
    direction                  = "Inbound" // kết nối đi vào 
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"    // *: bất kì giá trị nào 
    destination_port_range     = "5432" // cổng dịch vụ đích 
    destination_address_prefix = azurerm_subnet.db.address_prefixes[0]

    source_address_prefixes = [               // dải IP nguồn cho phép
      azurerm_subnet.aks.address_prefixes[0], // lấy phần tử đầu tiên 
      azurerm_subnet.db.address_prefixes[0],
      azurerm_subnet.admin.address_prefixes[0]
    ]
  }
  security_rule {
    name                       = "Deny-other-Inbound"
    priority                   = 200
    direction                  = "Inbound"
    access                     = "Deny"
    protocol                   = "*"
    source_port_range          = "*"
    destination_port_range     = "*"
    source_address_prefix      = "*"
    destination_address_prefix = "*"
  }

  tags = azurerm_resource_group.lab.tags
}

resource "azurerm_subnet_network_security_group_association" "db" {
  subnet_id                 = azurerm_subnet.db.id
  network_security_group_id = azurerm_network_security_group.db.id
}