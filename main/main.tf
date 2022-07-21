##################################################################################
# LOCALS
##################################################################################


locals {
  resource_group_name = "${var.naming_prefix}-${random_integer.name_suffix.result}"
  cluster_name = "${var.naming_prefix}-${random_integer.name_suffix.result}"
  acr_name = "${var.naming_prefix}${random_integer.name_suffix.result}"
  service_principal_name = "${var.naming_prefix}-${random_integer.name_suffix.result}"
}

resource "random_integer" "name_suffix" {
  min = 10000
  max = 99999
}



##################################################################################
# AKS
##################################################################################

data "azurerm_subscription" "current" {}

data "azuread_client_config" "current" {}

resource "azurerm_resource_group" "aks" {
  name     = local.resource_group_name
  location = var.location
}

resource "azuread_application" "role_acrpull" {
  display_name = local.service_principal_name
  owners = [ data.azuread_client_config.current.object_id ]
}

resource "azuread_service_principal" "role_acrpull" {
  application_id = azuread_application.role_acrpull.application_id
  owners = [ data.azuread_client_config.current.object_id ]
}

resource "azuread_service_principal_password" "role_acrpull" {
  service_principal_id = azuread_service_principal.role_acrpull.object_id
}
resource "azurerm_role_assignment" "role_acrpull" {
  scope                = data.azurerm_subscription.current.id
  role_definition_name = "Contributor"
  principal_id         = azuread_service_principal.role_acrpull.id
}

resource "azurerm_container_registry" "acr" {
  name                = local.acr_name
  location            = azurerm_resource_group.aks.location
  resource_group_name = azurerm_resource_group.aks.name
  sku                 = "Standard"
  admin_enabled       = false
}

resource "azurerm_kubernetes_cluster" "aks" {
  name                = local.cluster_name
  kubernetes_version  = var.kubernetes_version
  location            = azurerm_resource_group.aks.location
  resource_group_name = azurerm_resource_group.aks.name
  dns_prefix          = local.cluster_name

  default_node_pool {
    name                = "system"
    node_count          = var.system_node_count
    vm_size             = "Standard_DS2_v2"
    type                = "VirtualMachineScaleSets"
    availability_zones  = [1, 2, 3]
    enable_auto_scaling = false
  }

  identity {
    type = "SystemAssigned"
  }

  network_profile {
    load_balancer_sku = "Standard"
    network_plugin    = "kubenet" 
  }
}

## GitHub secrets

resource "github_actions_secret" "actions_secret_for_aks" {
  for_each = {
    RESOURCE_GROUP      = azurerm_resource_group.aks.resource_group_name
    ARM_CLIENT_ID       = azuread_service_principal.role_acrpull.application_id
    ARM_CLIENT_SECRET   = azuread_service_principal_password.role_acrpull.value
    ARM_SUBSCRIPTION_ID = data.azurerm_subscription.current.subscription_id
    ARM_TENANT_ID       = data.azuread_client_config.current.tenant_id
  }

  repository      = var.github_repository
  secret_name     = each.key
  plaintext_value = each.value
}