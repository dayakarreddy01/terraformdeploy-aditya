terraform {
  required_version = ">= 1.4.0"
  required_providers {
    azurerm = { source = "hashicorp/azurerm", version = ">= 3.100" }
    azapi   = { source = "azure/azapi",     version = ">= 2.0" }
  }
}

provider "azurerm" { 

features {} 

}

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
#    IMPORTANT: use AzAPI to send the exact payload the portal uses
#    parameterValueSet -> name: managedIdentityAuth (+ required values for the connector)
resource "azapi_resource" "blob_connection" {
  type      = "Microsoft.Web/connections@2016-06-01"
  name      = var.blob_connection_name
  parent_id = azurerm_resource_group.rg.id
  location  = azurerm_resource_group.rg.location

  body = jsonencode({
    properties = {
      displayName = var.blob_connection_display_name
      api = {
        id = "/subscriptions/${data.azurerm_client_config.current.subscription_id}" +
             "/providers/Microsoft.Web/locations/${azurerm_resource_group.rg.location}/managedApis/azureblob"
      }
      # For Azure Blob, pass the storage account name as a value in the managedIdentityAuth set
      # (Connectors differ; some require additional values such as namespaceEndpoint for Service Bus.)
      parameterValueSet = {
        name   = "managedIdentityAuth"
        values = {
          accountName = { value = azurerm_storage_account.sa.name }
        }
      }
    }
  })
}

# 4) Logic App (Consumption) with system-assigned managed identity
resource "azurerm_logic_app_workflow" "la" {
  name                = var.logic_app_name
  resource_group_name = azurerm_resource_group.rg.name
  location            = azurerm_resource_group.rg.location
  enabled             = true

  identity { type = "SystemAssigned" }

  # declare the $connections parameter schema
  workflow_parameters = {
    "$connections" = jsonencode({
      defaultValue = {}
      type         = "Object"
    })
  }

  # provide the values including authentication for the connection
  parameters = {
    "$connections" = jsonencode({
      azureblob = {
        id             = "/subscriptions/${data.azurerm_client_config.current.subscription_id}" +
                         "/providers/Microsoft.Web/locations/${azurerm_resource_group.rg.location}/managedApis/azureblob"
        connectionId   = azapi_resource.blob_connection.id
        connectionName = var.blob_connection_name
        connectionProperties = {
          authentication = {
            # THIS IS CRITICAL: tells the workflow to use MI when calling the connection
            type = "ManagedServiceIdentity"
          }
        }
      }
    })
  }

  # your workflow definition (Consumption schema 2016-06-01)
  # keep it minimal at first; add actions that reference the connection later
  definition = file("${path.module}/workflow-definition.json")

  depends_on = [azapi_resource.blob_connection]
}

# 5) RBAC: grant the Logic App’s identity access to the target service
resource "azurerm_role_assignment" "blob_data_contributor" {
  scope                = azurerm_storage_account.sa.id
  role_definition_name = "Storage Blob Data Contributor"
  principal_id         = azurerm_logic_app_workflow.la.identity[0].principal_id
