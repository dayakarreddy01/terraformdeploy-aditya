terraform {
  required_version = ">= 1.4.0"

 required_providers {
  azurerm = { source = "hashicorp/azurerm", version = "~> 3.100" }
  azapi   = { source = "azure/azapi",    version = "~> 1.12" } # or "~> 2.0" if tested


provider "azurerm" {
  features {}
}

