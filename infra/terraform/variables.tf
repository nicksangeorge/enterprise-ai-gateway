variable "subscription_id" {
  description = "Azure subscription ID"
  type        = string
}

variable "resource_group_name" {
  description = "Name of the resource group"
  type        = string
  default     = "rg-ai-gateway-demo"
}

variable "location_primary" {
  description = "Primary Azure region for APIM and Foundry"
  type        = string
  default     = "eastus2"
}

variable "location_secondary" {
  description = "Secondary Azure region for Foundry failover"
  type        = string
  default     = "swedencentral"
}

variable "prefix" {
  description = "Resource name prefix"
  type        = string
  default     = "aigw"
}

variable "tags" {
  description = "Tags applied to all resources"
  type        = map(string)
  default = {
    project     = "ai-gateway-demo"
    environment = "demo"
    owner       = "platform-team"
  }
}

variable "apim_name" {
  description = "APIM instance name (must be globally unique DNS name). If null, generated from prefix + random suffix."
  type        = string
  default     = null
}

variable "use_random_suffix" {
  description = "Append a random 4-char suffix to resource names to avoid collisions"
  type        = bool
  default     = true
}

variable "api_center_location" {
  description = "Azure region for API Center (not available in all regions — eastus works)"
  type        = string
  default     = "eastus"
}
