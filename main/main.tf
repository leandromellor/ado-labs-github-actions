##################################################################################
# LOCALS
##################################################################################


locals {
  resource_group_name = "${var.naming_prefix}-${random_integer.name_suffix.result}"
  cluster_name = "${var.naming_prefix}-${random_integer.name_suffix.result}"
  acr_name = "${var.naming_prefix}${random_integer.name_suffix.result}"
  service_principal_name = "${var.naming_prefix}-${random_integer.name_suffix.result}"
  storage_account_name   = "${lower(var.naming_prefix)}${random_integer.sa_numaks.result}"
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

data "azuread_application_published_app_ids" "current" {}

resource "azuread_service_principal" "role_acrpull" {
  application_id = data.azuread_application_published_app_ids.current.result.MicrosoftGraph
  use_existing   = true
  owners = [ data.azuread_client_config.current.object_id ]
}

resource "azuread_application" "role_acrpull" {
  display_name = local.service_principal_name
  owners = [ data.azuread_client_config.current.object_id ]

  required_resource_access {
    resource_app_id = data.azuread_application_published_app_ids.current.result.MicrosoftGraph

    resource_access {
      id   = azuread_service_principal.role_acrpull.app_role_ids["User.Read.All"]
      type = "Role"
    }

    resource_access {
      id   = azuread_service_principal.role_acrpull.oauth2_permission_scope_ids["User.ReadWrite"]
      type = "Scope"
    }
  }
}

resource "azuread_service_principal" "principal" {
  application_id = azuread_application.principal.application_id
}

resource "azurerm_role_assignment" "role_acrpull" {
  app_id         = azuread_service_principal.role_acrpull.app_role_ids["User.Read.All"]
  principal_id = azuread_service_principal.principal.id
  resource_id  = azuread_service_principal.role_acrpull.id
  scope                = data.azurerm_subscription.current.id
  role_definition_name = "Contributor"
}

resource "azurerm_resource_group" "aks" {
  name     = local.resource_group_name
  location = var.location
}

resource "azuread_service_principal_password" "role_acrpull" {
  service_principal_id = azuread_service_principal.role_acrpull.object_id
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

##################################################################################
# SA
##################################################################################

resource "random_integer" "sa_numaks" {
  min = 10000
  max = 99999
}

resource "azurerm_resource_group" "setupaks" {
  name     = local.resource_group_name
  location = var.location
}

resource "azurerm_storage_account" "saaks" {
  name                     = local.storage_account_name
  resource_group_name      = azurerm_resource_group.setupaks.name
  location                 = var.location
  account_tier             = "Standard"
  account_replication_type = "LRS"

}

resource "azurerm_storage_container" "ctaks" {
  name                 = "terraform-state"
  storage_account_name = azurerm_storage_account.saaks.name

}

## GitHub secrets

resource "github_actions_secret" "actions_secret_for_aks" {
  for_each = {
    STORAGE_ACCOUNT     = azurerm_storage_account.saaks.name
    RESOURCE_GROUP      = azurerm_resource_group.aks.name
    CONTAINER_NAME      = azurerm_storage_container.ctaks.name
    ARM_CLIENT_ID       = azuread_service_principal.role_acrpull.application_id
    ARM_CLIENT_SECRET   = azuread_service_principal_password.role_acrpull.value
    ARM_SUBSCRIPTION_ID = data.azurerm_subscription.current.subscription_id
    ARM_TENANT_ID       = data.azuread_client_config.current.tenant_id
  }

  repository      = var.github_repository
  secret_name     = each.key
  plaintext_value = each.value
}