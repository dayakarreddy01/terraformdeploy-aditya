terraform {
  required_version = ">= 1.4.0"
  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = ">= 3.100.0"
    }
    azapi = {
      source  = "azure/azapi" # <-- correct namespace
      version = ">= 2.0.0"
    }
  }
}
