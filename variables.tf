variable "rg_name" {
  type    = string
  default = "New_LA"
}

variable "location" {
  type    = string
  default = "East US"
}

variable "logic_app_name" {
  type    = string
  default = "New_LA" # Legal for Logic Apps Consumption
}

variable "storage_account_name" {
  type    = string
  default = "mynewstoragestr123" # must be lowercase, 3–24 chars, globally unique
}

variable "storage_container_name" {
  type    = string
  default = "demonewconnect"
}

variable "blob_connection_name" {
  type    = string
  default = "Newconnection"
}

variable "blob_connection_display_name" {
  type    = string
  default = "newconnection"
}

 //You don't need subscription_id if using data.azurerm_client_config.current.
variable "subscription_id" {
  type    = string
  default = "b26b0c24-15bd-4527-bf7b-970aab26312b"
}
