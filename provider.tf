terraform {
  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 3.0"
    }

    azapi = {
      source  = "Azure/azapi"   # ✅ FIX HERE
      version = "~> 1.5"        # or latest
    }
  }
}
