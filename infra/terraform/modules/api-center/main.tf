# API Center — unified tool and API discovery catalog
# Standard plan is free when linked to APIM Standard or Premium
# azurerm doesn't support API Center natively, so we use azapi

terraform {
  required_providers {
    azapi = {
      source = "azure/azapi"
    }
    azurerm = {
      source = "hashicorp/azurerm"
    }
  }
}

data "azurerm_subscription" "current" {}

resource "azapi_resource" "api_center" {
  type      = "Microsoft.ApiCenter/services@2024-06-01-preview"
  name      = var.suffix != "" ? "${var.prefix}-apicenter-${var.suffix}" : "${var.prefix}-apicenter"
  parent_id = "/subscriptions/${data.azurerm_subscription.current.subscription_id}/resourceGroups/${var.resource_group_name}"
  location  = var.location
  tags      = var.tags

  body = {
    properties = {}
  }
}

# NOTE: The APIM-to-API-Center sync link and API/MCP registration
# are configured in the Azure portal after deployment:
# API Center > Environments > Add environment > Link to APIM instance
# This enables automatic sync of APIs, MCP servers, and metadata.
