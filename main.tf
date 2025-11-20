# --- Data: current client config (required for subscription_id) ---
data "azurerm_client_config" "current" {}

# --- Resource Group ---
resource "azurerm_resource_group" "rg" {
  name     = var.rg_name
  location = var.location
}

# --- Storage Account ---
resource "azurerm_storage_account" "sa" {
  name                     = "examplestoraccount"  # must be lowercase & globally unique
  resource_group_name      = azurerm_resource_group.rg.name
  location                 = azurerm_resource_group.rg.location
  account_tier             = "Standard"
  account_replication_type = "LRS"

  tags = {
    environment = "staging"
  }
}

# Optional container #1 (uses storage_account_id)
resource "azurerm_storage_container" "sa" {
  name                  = "vhds"
  storage_account_id    = azurerm_storage_account.sa.id
  container_access_type = "private"
}

# Optional container #2 (uses storage_account_name)
# Keep only one of these if you don't need both.

# --- API Connection: Azure Blob using Managed Identity ---
resource "azapi_resource" "blob_connection" {
  type      = "Microsoft.Web/connections@2016-06-01"
  name      = var.blob_connection_name

  # Required: connections are under the resource group
  parent_id = azurerm_resource_group.rg.id

  location  = azurerm_resource_group.rg.location

  body = jsonencode({
    properties = {
      displayName = var.blob_connection_display_name
      api = {
        id = "/subscriptions/${data.azurerm_client_config.current.subscription_id}/providers/Microsoft.Web/locations/${azurerm_resource_group.rg.location}/managedApis/azureblob"
      }
      # Correct schema: plain key/value pairs (no { value = ... })
      parameterValues = {
        accountName        = azurerm_storage_account.sa.name
        authenticationType = "ManagedServiceIdentity"
        # resourceUri = "https://storage.azure.com/" # optional in some tenants
      }
    }
  })

  depends_on = [azurerm_storage_account.sa]
}

# --- Logic App (Consumption) with System Assigned Identity ---
resource "azapi_resource" "workflow" {
  type      = "Microsoft.Logic/workflows@2019-05-01"
  name      = var.logic_app_name
  parent_id = azurerm_resource_group.rg.id
  location  = azurerm_resource_group.rg.location

  body = jsonencode({
    identity = {
      type = "SystemAssigned"
    }
    properties = {
      state      = "Enabled"
      definition = jsondecode(file("${path.module}/workflow-definition.json"))
      parameters = {
        "$connections" = {
          value = {
            azureblob = {
              id             = "/subscriptions/${data.azurerm_client_config.current.subscription_id}/providers/Microsoft.Web/locations/${azurerm_resource_group.rg.location}/managedApis/azureblob"
              connectionId   = azapi_resource.blob_connection.id
              connectionName = var.blob_connection_name
              connectionProperties = {
                authentication = { type = "ManagedServiceIdentity" }
              }
            }
          }
        }
      }
    }
  })

  depends_on = [azapi_resource.blob_connection]
}

# --- (Recommended) Role assignment for the Logic App MSI on the Storage Account ---
resource "azurerm_role_assignment" "la_blob_data_contributor" {
  scope                = azurerm_storage_account.sa.id
  role_definition_name = "Storage Blob Data Contributor"
  principal_id         = jsondecode(azapi_resource.workflow.output).identity.principalId

  depends_on = [azapi_resource.workflow]
}
