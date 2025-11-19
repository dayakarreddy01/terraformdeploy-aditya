terraform {
  backend "azurerm" {
    use_oidc             = true                                    # Can also be set via `ARM_USE_OIDC` environment variable.
    use_azuread_auth     = true                                    # Can also be set via `ARM_USE_AZUREAD` environment variable.
    tenant_id            = "16b3c013-d300-468d-ac64-7eda0820b6d3"  # Can also be set via `ARM_TENANT_ID` environment variable.
    client_id            = "0a869235-5b2e-44bb-8f7d-199a6b84d823"  # Can also be set via `ARM_CLIENT_ID` environment variable.
    storage_account_name = "demonewtestgroupb2e7"                              # Can be passed via `-backend-config=`"storage_account_name=<storage account name>"` in the `init` command.
    container_name       = "demonew"                               # Can be passed via `-backend-config=`"container_name=<container name>"` in the `init` command.
    key                  = "prod.terraform.tfstate"                # Can be passed via `-backend-config=`"key=<blob key name>"` in the `init` command.
  }
}
