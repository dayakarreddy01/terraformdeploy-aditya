terraform {
  required_version = ">= 1.5.0"
  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 3.111"
    }
    azapi = {
      source  = "azure/azapi"
      version = "~> 1.13"
    }
  }
}

provider "azurerm" {
  features {}
}

provider "azapi" {}

# -------------------------------------------------------
# Load external parameters.json
# -------------------------------------------------------
locals {
  params = jsondecode(file("${path.module}/parameters.json"))
}

data "azurerm_client_config" "current" {}

# -------------------------------------------------------
# Resource Group
# -------------------------------------------------------
resource "azurerm_resource_group" "rg" {
  name     = local.params.resourceGroupName
  location = local.params.location
}

# -------------------------------------------------------
# Storage Account (Blob) - the target resource
# -------------------------------------------------------
resource "azurerm_storage_account" "stg" {
  name                     = local.params.storageAccountName
  resource_group_name      = azurerm_resource_group.rg.name
  location                 = azurerm_resource_group.rg.location
  account_tier             = "Standard"
  account_replication_type = "LRS"
  min_tls_version          = "TLS1_2"
}

# -------------------------------------------------------
# Logic App (Consumption) using ONLY User-Assigned MSI
# -------------------------------------------------------
resource "azurerm_logic_app_workflow" "la" {
  name                = local.params.logicAppName
  resource_group_name = azurerm_resource_group.rg.name
  location            = azurerm_resource_group.rg.location

  identity {
    type         = "UserAssigned"
    identity_ids = [local.params.userAssignedIdentityResourceId]
  }

  # Minimal workflow definition with Request trigger and Blob action
  definition = jsonencode({
    "$schema"        = "https://schema.management.azure.com/schemas/2016-06-01/workflowdefinition.json#"
    "contentVersion" = "1.0.0.0"
    "parameters"     = {
      "storageAccountName" = { "type" = "string" }
      "$connections"       = { "type" = "Object" }
    }
    "triggers" = {
      "manual" = {
        "type"   = "Request",
        "kind"   = "Http",
        "inputs" = { "method" = "GET" }
      }
    }
    "actions" = {
      "List_Containers" = {
        "type"   = "ApiConnection",
        "inputs" = {
          "host"  = { "connection" = { "name" = "@parameters('$connections')['azureblob']['connectionId']" } }
          "path"  = "/v2/storageAccounts/@{encodeURIComponent(parameters('storageAccountName'))}/blobServices/default/containers"
          "method"= "GET"
        }
        "runAfter" = {}
      }
    }
    "outputs" = {}
  })

  parameters = {
    "storageAccountName" = azurerm_storage_account.stg.name

    # Wire the API connection and assert MSI+UAMI
    "$connections" = jsonencode({
      value = {
        azureblob = {
          connectionId   = azapi_resource.blob_connection.id
          connectionName = local.params.blobConnectionName
          id             = "/subscriptions/${data.azurerm_client_config.current.subscription_id}/providers/Microsoft.Web/locations/${local.params.location}/managedApis/azureblob"
          connectionProperties = {
            authentication = {
              type     = "ManagedServiceIdentity"
              identity = local.params.userAssignedIdentityResourceId
            }
          }
        }
      }
    })
  }

  depends_on = [azapi_resource.blob_connection]
}

# -------------------------------------------------------
# RBAC: grant the UAMI principal data-plane access on Storage
# -------------------------------------------------------
# Resolve UAMI principal (object) ID via ARM reference
data "azapi_resource" "uami" {
  type      = "Microsoft.ManagedIdentity/userAssignedIdentities@2025-01-31-preview"
  name      = split("/", local.params.userAssignedIdentityResourceId)[length(split("/", local.params.userAssignedIdentityResourceId)) - 1]
  parent_id = join("/", slice(split("/", local.params.userAssignedIdentityResourceId), 0, 8))
}

resource "azurerm_role_assignment" "blob_contributor" {
  scope                = azurerm_storage_account.stg.id
  role_definition_name = "Storage Blob Data Contributor"
  principal_id         = data.azapi_resource.uami.output.identity.principalId
}

# -------------------------------------------------------
# API Connection (Consumption) for Azure Blob using MSI
# -------------------------------------------------------
resource "azapi_resource" "blob_connection" {
  type      = "Microsoft.Web/connections@2016-06-01"
  name      = local.params.blobConnectionName
  location  = azurerm_resource_group.rg.location
  parent_id = azurerm_resource_group.rg.id

  body = jsonencode({
    kind       = "V1"
    properties = {
      displayName = local.params.blobConnectionName
      api = {
        id = "/subscriptions/${data.azurerm_client_config.current.subscription_id}/providers/Microsoft.Web/locations/${local.params.location}/managedApis/azureblob"
      }
      # MSI variant uses parameterValueSet with the well-known set name
      parameterValueSet = {
        name   = "managedIdentityAuth"
        values = {
          # Azure Blob MSI generally needs no extra values in this set.
          # (Service Bus would require namespaceEndpoint here.)
        }
      }
    }
  })

  # Ensure RBAC is in place before the connection is created
  depends_on = [azurerm_role_assignment.blob_contributor]
}

# -------------------------------------------------------
# Optional: Connection Access Policy for the Logic App principal
# -------------------------------------------------------
resource "azapi_resource" "blob_connection_access_policy" {
  type      = "Microsoft.Web/connections/accessPolicies@2016-06-01"
  name      = azurerm_logic_app_workflow.la.identity[0].principal_id
  location  = azurerm_resource_group.rg.location
  parent_id = azapi_resource.blob_connection.id

  body = jsonencode({
    properties = {
      principal = {
        type     = "ActiveDirectory"
        identity = {
          objectId = azurerm_logic_app_workflow.la.identity[0].principal_id
          tenantId = data.azurerm_client_config.current.tenant_id
        }
      }
    }
  })

  depends_on = [azapi_resource.blob_connection]
}
``
