variable "resource_group_name" {
  type = string
}

variable "location" {
  type = string
}

variable "prefix" {
  type = string
}

variable "suffix" {
  description = "Region suffix for naming (e.g., eus2, swc)"
  type        = string
}

variable "identity_id" {
  description = "User-assigned managed identity resource ID"
  type        = string
}

variable "identity_principal_id" {
  description = "User-assigned managed identity principal ID for RBAC"
  type        = string
}

variable "tags" {
  type    = map(string)
  default = {}
}

variable "apim_system_identity_principal_id" {
  description = "APIM system-assigned identity principal ID for RBAC"
  type        = string
}
