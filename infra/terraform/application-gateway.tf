resource "azurerm_public_ip" "appgw" {
  name                = "pip-appgw-azurelab-dev"
  location            = azurerm_resource_group.lab.location
  resource_group_name = azurerm_resource_group.lab.name
  allocation_method   = "Static"
  sku                 = "Standard"
  domain_name_label   = "azurelab-${local.name_suffix}"
  tags                = azurerm_resource_group.lab.tags
}

resource "azurerm_application_gateway" "main" {
  name                = "agw-azurelab-dev"
  location            = azurerm_resource_group.lab.location
  resource_group_name = azurerm_resource_group.lab.name
  tags                = azurerm_resource_group.lab.tags

  sku {
    name     = "Standard_v2"
    tier     = "Standard_v2"
    capacity = 1
  }

  gateway_ip_configuration {
    name      = "gateway-ip"
    subnet_id = azurerm_subnet.appgw.id
  }

  frontend_ip_configuration {
    name                 = "public-frontend"
    public_ip_address_id = azurerm_public_ip.appgw.id
  }

  frontend_port {
    name = "http"
    port = 80
  }

  backend_address_pool { name = "bootstrap-pool" }

  backend_http_settings {
    name                  = "bootstrap-settings"
    cookie_based_affinity = "Disabled"
    port                  = 8080
    protocol              = "Http"
    request_timeout       = 60
  }

  http_listener {
    name                           = "bootstrap-listener"
    frontend_ip_configuration_name = "public-frontend"
    frontend_port_name             = "http"
    protocol                       = "Http"
  }

  request_routing_rule {
    name                       = "bootstrap-rule"
    rule_type                  = "Basic"
    http_listener_name         = "bootstrap-listener"
    backend_address_pool_name  = "bootstrap-pool"
    backend_http_settings_name = "bootstrap-settings"
    priority                   = 100
  }

  # AGIC owns application routes after bootstrap. Terraform owns the gateway itself.
  lifecycle {
    ignore_changes = [
      backend_address_pool, backend_http_settings, http_listener,
      request_routing_rule, url_path_map, probe, redirect_configuration,
      frontend_port, ssl_certificate
    ]
  }
}

resource "azurerm_role_assignment" "agic_gateway" {
  scope                = azurerm_application_gateway.main.id
  role_definition_name = "Contributor"
  principal_id         = azurerm_kubernetes_cluster.main.ingress_application_gateway[0].ingress_application_gateway_identity[0].object_id
}

resource "azurerm_role_assignment" "agic_reader" {
  scope                = azurerm_resource_group.lab.id
  role_definition_name = "Reader"
  principal_id         = azurerm_kubernetes_cluster.main.ingress_application_gateway[0].ingress_application_gateway_identity[0].object_id
}

resource "azurerm_role_assignment" "agic_subnet" {
  scope                = azurerm_subnet.appgw.id
  role_definition_name = "Network Contributor"
  principal_id         = azurerm_kubernetes_cluster.main.ingress_application_gateway[0].ingress_application_gateway_identity[0].object_id
}

output "application_url" {
  value = "http://${azurerm_public_ip.appgw.fqdn}"
}

output "application_public_ip" {
  value = azurerm_public_ip.appgw.ip_address
}
