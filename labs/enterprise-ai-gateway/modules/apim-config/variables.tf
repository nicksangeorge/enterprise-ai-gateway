variable "resource_group_name" {
  type = string
}

variable "apim_name" {
  type = string
}

variable "apim_id" {
  type = string
}

variable "foundry_primary_endpoint" {
  description = "Foundry East US 2 endpoint URL"
  type        = string
}

variable "foundry_secondary_endpoint" {
  description = "Foundry Sweden Central endpoint URL"
  type        = string
}

variable "foundry_primary_id" {
  description = "Foundry East US 2 resource ID"
  type        = string
}

variable "foundry_secondary_id" {
  description = "Foundry Sweden Central resource ID"
  type        = string
}

variable "user_assigned_identity_id" {
  type = string
}

variable "apim_system_identity_principal" {
  description = "APIM system-assigned managed identity principal ID"
  type        = string
}

variable "prefix" {
  type = string
}

variable "tags" {
  type    = map(string)
  default = {}
}
