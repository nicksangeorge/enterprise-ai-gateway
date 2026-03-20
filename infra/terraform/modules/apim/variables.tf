variable "resource_group_name" {
  type = string
}

variable "location" {
  type = string
}

variable "prefix" {
  type = string
}

variable "user_assigned_identity_id" {
  description = "User-assigned managed identity for Foundry backend auth"
  type        = string
}

variable "log_analytics_workspace_id" {
  description = "Log Analytics workspace for diagnostic logs"
  type        = string
}

variable "app_insights_id" {
  description = "Application Insights resource ID"
  type        = string
}

variable "app_insights_key" {
  description = "Application Insights instrumentation key"
  type        = string
  sensitive   = true
}

variable "tags" {
  type    = map(string)
  default = {}
}

variable "apim_name" {
  description = "Explicit APIM instance name (globally unique)"
  type        = string
}
