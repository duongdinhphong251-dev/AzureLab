resource "azurerm_user_assigned_identity" "aks" {
  name                = "id-aks-azurelab-dev"
  location            = azurerm_resource_group.lab.location
  resource_group_name = azurerm_resource_group.lab.name

  tags = azurerm_resource_group.lab.tags
}

resource "azurerm_role_assignment" "aks_network" {
  scope                = azurerm_virtual_network.main.id                 // lm ở đâu
  role_definition_name = "Network Contributor"                           // đc làm j 
  principal_id         = azurerm_user_assigned_identity.aks.principal_id //ai đc cấp quyền
}

resource "azurerm_kubernetes_cluster" "main" {
  name                = "aks-azurelab-dev"
  location            = azurerm_resource_group.lab.location
  resource_group_name = azurerm_resource_group.lab.name
  dns_prefix          = "aks-azurelab-dev"

  sku_tier = "Free"

  private_cluster_enabled             = true
  private_cluster_public_fqdn_enabled = false // ko tạo thêm DNS cho APi private đó 
  private_dns_zone_id                 = "System"

  role_based_access_control_enabled = true

  oidc_issuer_enabled       = true
  workload_identity_enabled = true

  default_node_pool {
    name           = "system"
    vm_size        = "Standard_D2s_v4"
    node_count     = 2
    vnet_subnet_id = azurerm_subnet.aks.id

    os_disk_size_gb = 64
    max_pods        = 30

    upgrade_settings {
      drain_timeout_in_minutes      = 0
      max_surge                     = "10%"
      node_soak_duration_in_minutes = 0
    }
  }

  identity {
    type = "UserAssigned"

    identity_ids = [
      azurerm_user_assigned_identity.aks.id
    ]
  }

  network_profile {
    network_plugin    = "azure"
    load_balancer_sku = "standard"
    outbound_type     = "loadBalancer"

    service_cidr   = "10.30.0.0/16"
    dns_service_ip = "10.30.0.10"
  }

  ingress_application_gateway {
    gateway_id = azurerm_application_gateway.main.id
  }
  key_vault_secrets_provider {
    secret_rotation_enabled = true
  }

  tags = azurerm_resource_group.lab.tags

  depends_on = [
    azurerm_role_assignment.aks_network
  ]
}