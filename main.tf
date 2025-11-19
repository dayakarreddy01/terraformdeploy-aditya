terraform {
  required_version = ">= 1.4.0"
  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = ">= 3.100"
    }
    azapi = {
      source  = "azure/azapi"
      version = ">= 2.0"
    }
  }
}

provider "azurerm" {
  features {}
}

provider "azapi" {}

data "azurerm_client_config" "current" {}

# 1) Resource Group
resource "azurerm_resource_group" "rg" {
  name     = var.rg_name
  location = var.location
}

# 2) Example target resource: Storage account + container
resource "azurerm_storage_account" "sa" {
  name                     = var.storage_account_name
  resource_group_name      = azurerm_resource_group.rg.name
  location                 = azurerm_resource_group.rg.location
  account_tier             = "Standard"
  account_replication_type = "LRS"
  min_tls_version          = "TLS1_2"
}

resource "azurerm_storage_container" "cont" {
  name                  = var.storage_container_name
  storage_account_name  = azurerm_storage_account.sa.name
  container_access_type = "private"
}

# 3) API connection (Azure Blob) configured for Managed Identity
#    IMPORTANT: use AzAPI to send the same shape the portal uses
#    parameterValueSet -> name: managedIdentityAuth (+ required values for the connector)
resource "azapi_resource" "blob_connection" {
  type      = "Microsoft.Web/connections@2016-06-01"
  name      = var.blob_connection_name
  parent_id = azurerm_resource_group.rg.id
  location  = azurerm_resource_group.rg.location

  body = jsonencode({
    properties = {
      displayName = var.blob_connection_display_name
