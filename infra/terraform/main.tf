resource "azurerm_resource_group" "lab" {
  name     = "rg-azurelab-dev"
  location = "koreacentral"

  tags = {
    project     = "azurelab"
    environment = "dev"
  }
}