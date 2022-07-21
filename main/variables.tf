#############################################################################
# VARIABLES
#############################################################################

variable "location" {
  type    = string
  default = "eastus"
}

variable "naming_prefix" {
  type    = string
  default = "adolabs"
}

variable "resource_group_name" {
  type        = string
  description = "RG name in Azure"
  default = "adolabs_aks_rg"
}

variable "cluster_name" {
  type        = string
  description = "AKS name in Azure"
  default = "adolabs-cluster"
}

variable "kubernetes_version" {
  type        = string
  description = "Kubernetes version"
  default = "1.23"
}

variable "system_node_count" {
  type        = number
  description = "Number of AKS worker nodes"
  default = "2"
}

variable "acr_name" {
  type        = string
  description = "ACR name"
  default = "adolabsacr"
}

variable "github_repository" {
  type    = string
  default = "ado-labs-github-actions"
}