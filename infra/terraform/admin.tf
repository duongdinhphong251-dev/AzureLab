resource "azurerm_subnet" "admin" {
  name                 = "snet-admin"
  resource_group_name  = azurerm_resource_group.lab.name
  virtual_network_name = azurerm_virtual_network.main.name
  address_prefixes     = ["10.20.10.0/24"]
}

resource "azurerm_public_ip" "admin_nat" {
  name                = "pip-admin-nat"
  location            = azurerm_resource_group.lab.location
  resource_group_name = azurerm_resource_group.lab.name

  allocation_method = "Static"
  sku               = "Standard"

  tags = azurerm_resource_group.lab.tags
}

resource "azurerm_nat_gateway" "admin" {
  name                = "nat-admin"
  location            = azurerm_resource_group.lab.location
  resource_group_name = azurerm_resource_group.lab.name

  sku_name = "Standard"

  tags = azurerm_resource_group.lab.tags
}
resource "azurerm_nat_gateway_public_ip_association" "admin" {
  nat_gateway_id       = azurerm_nat_gateway.admin.id
  public_ip_address_id = azurerm_public_ip.admin_nat.id
}
resource "azurerm_subnet_nat_gateway_association" "admin" {
  subnet_id      = azurerm_subnet.admin.id
  nat_gateway_id = azurerm_nat_gateway.admin.id
}

resource "azurerm_network_security_group" "admin" {
  name                = "nsg-admin"
  location            = azurerm_resource_group.lab.location
  resource_group_name = azurerm_resource_group.lab.name

  security_rule {
    name                       = "Deny-All-Inbound"
    priority                   = 100
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

resource "azurerm_subnet_network_security_group_association" "admin" {
  subnet_id                 = azurerm_subnet.admin.id
  network_security_group_id = azurerm_network_security_group.admin.id
}

# Card mạng của VM: chỉ có private IP.
resource "azurerm_network_interface" "admin" {
  name                = "nic-admin"
  location            = azurerm_resource_group.lab.location
  resource_group_name = azurerm_resource_group.lab.name

  ip_configuration {
    name                          = "internal"
    subnet_id                     = azurerm_subnet.admin.id
    private_ip_address_allocation = "Dynamic"
  }

  tags = azurerm_resource_group.lab.tags
}

resource "azurerm_linux_virtual_machine" "admin" {
  name                = "vm-admin-azurelab"
  location            = azurerm_resource_group.lab.location
  resource_group_name = azurerm_resource_group.lab.name

  size           = "Standard_B2s_v2"
  admin_username = "azureadmin"

  disable_password_authentication = true
  secure_boot_enabled             = true
  vtpm_enabled                    = true

  network_interface_ids = [
    azurerm_network_interface.admin.id
  ]

  admin_ssh_key {
    username   = "azureadmin"
    public_key = file(pathexpand("~/.ssh/azurelab_admin.pub"))
  }

  os_disk {
    caching              = "ReadWrite"
    storage_account_type = "StandardSSD_LRS"
    disk_size_gb         = 64
  }

  source_image_reference {
    publisher = "Canonical"
    offer     = "ubuntu-24_04-lts"
    sku       = "server"
    version   = "latest"
  }

  identity {
    type = "SystemAssigned"
  }

  tags = azurerm_resource_group.lab.tags

  depends_on = [
    azurerm_nat_gateway_public_ip_association.admin,
    azurerm_subnet_nat_gateway_association.admin,
    azurerm_subnet_network_security_group_association.admin
  ]
}