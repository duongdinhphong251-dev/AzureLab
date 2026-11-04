terraform {
  required_providers { // khai bao provider
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 4.0" //lay version tu 4.0
    }
  }
}

provider "azurerm" {
  features {
    storage {
      data_plane_available = false
    }
  }

  storage_use_azuread = true
}