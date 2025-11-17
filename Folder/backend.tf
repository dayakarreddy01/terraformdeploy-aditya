
terraform {
  backend "azurerm" {}
  required_providers {
    azurerm = { source = "hashicorp/azurerm", version = "~> 3.111" }
    azapi  = { source = "azure/azapi",       version = "~> 1.13"  }
  }
}
provider "azurerm" { features {} }
