variable "resource_group_name" {
  type = string
}

variable "location" {
  type = string
}

variable "prefix" {
  type = string
}

variable "apim_id" {
  description = "APIM instance ID to link for sync"
  type        = string
}

variable "suffix" {
  description = "Random suffix for globally unique naming"
  type        = string
  default     = ""
}

variable "tags" {
  type    = map(string)
  default = {}
}
