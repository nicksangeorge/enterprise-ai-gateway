terraform {
  required_providers {
    azapi = {
      source = "azure/azapi"
    }
  }
}

# --- Backends (azapi — supports MI credentials + circuit breakers) ---
# Foundry endpoints typically end with "/" — trimsuffix ensures clean URL construction

resource "azapi_resource" "backend_primary" {
  type      = "Microsoft.ApiManagement/service/backends@2024-05-01"
  name      = "${var.prefix}-foundry-eus2"
  parent_id = var.apim_id

  schema_validation_enabled = false

  body = {
    properties = {
      description = "Foundry East US 2 — primary (priority 1)"
      protocol    = "http"
      url         = "${trimsuffix(var.foundry_primary_endpoint, "/")}/openai"

      credentials = {
        managedIdentity = {
          resource = "https://cognitiveservices.azure.com/"
        }
      }

      tls = {
        validateCertificateChain = true
        validateCertificateName  = true
      }

      circuitBreaker = {
        rules = [
          {
            name = "foundry-breaker"
            failureCondition = {
              count    = 3
              interval = "PT10S"
              statusCodeRanges = [
                { min = 429, max = 429 },
                { min = 500, max = 503 }
              ]
            }
            tripDuration     = "PT30S"
            acceptRetryAfter = true
          }
        ]
      }
    }
  }
}

resource "azapi_resource" "backend_secondary" {
  type      = "Microsoft.ApiManagement/service/backends@2024-05-01"
  name      = "${var.prefix}-foundry-swc"
  parent_id = var.apim_id

  schema_validation_enabled = false

  body = {
    properties = {
      description = "Foundry Sweden Central — failover (priority 2)"
      protocol    = "http"
      url         = "${trimsuffix(var.foundry_secondary_endpoint, "/")}/openai"

      credentials = {
        managedIdentity = {
          resource = "https://cognitiveservices.azure.com/"
        }
      }

      tls = {
        validateCertificateChain = true
        validateCertificateName  = true
      }

      circuitBreaker = {
        rules = [
          {
            name = "foundry-breaker"
            failureCondition = {
              count    = 3
              interval = "PT10S"
              statusCodeRanges = [
                { min = 429, max = 429 },
                { min = 500, max = 503 }
              ]
            }
            tripDuration     = "PT30S"
            acceptRetryAfter = true
          }
        ]
      }
    }
  }
}

# --- Backend Pool (priority-based routing: EUS2 primary, SWC failover) ---

resource "azapi_resource" "foundry_pool" {
  type      = "Microsoft.ApiManagement/service/backends@2024-05-01"
  name      = "foundry-pool"
  parent_id = var.apim_id

  schema_validation_enabled = false

  body = {
    properties = {
      description = "Priority-based pool: EUS2 primary, SWC failover"
      type        = "Pool"
      pool = {
        services = [
          {
            id       = azapi_resource.backend_primary.id
            priority = 1
            weight   = 1
          },
          {
            id       = azapi_resource.backend_secondary.id
            priority = 2
            weight   = 1
          }
        ]
      }
    }
  }

  depends_on = [
    azapi_resource.backend_primary,
    azapi_resource.backend_secondary,
  ]
}

# --- Products (one per team, each with different quota policies) ---

resource "azurerm_api_management_product" "alpha" {
  product_id            = "team-alpha"
  api_management_name   = var.apim_name
  resource_group_name   = var.resource_group_name
  display_name          = "Team Alpha - Product Engineering"
  description           = "Production workloads. 50K TPM. Priority routing."
  subscription_required = true
  approval_required     = false
  published             = true
}

resource "azurerm_api_management_product" "beta" {
  product_id            = "team-beta"
  api_management_name   = var.apim_name
  resource_group_name   = var.resource_group_name
  display_name          = "Team Beta - Customer Support AI"
  description           = "Internal support tools. 20K TPM. Cost-optimized routing."
  subscription_required = true
  approval_required     = false
  published             = true
}

resource "azurerm_api_management_product" "gamma" {
  product_id            = "team-gamma"
  api_management_name   = var.apim_name
  resource_group_name   = var.resource_group_name
  display_name          = "Team Gamma - Innovation Lab"
  description           = "R&D and experimentation. 5K TPM. Multi-provider models."
  subscription_required = true
  approval_required     = false
  published             = true
}

# --- Subscriptions ---

resource "azurerm_api_management_subscription" "alpha" {
  api_management_name = var.apim_name
  resource_group_name = var.resource_group_name
  product_id          = azurerm_api_management_product.alpha.id
  display_name        = "Team Alpha Subscription"
  state               = "active"
}

resource "azurerm_api_management_subscription" "beta" {
  api_management_name = var.apim_name
  resource_group_name = var.resource_group_name
  product_id          = azurerm_api_management_product.beta.id
  display_name        = "Team Beta Subscription"
  state               = "active"
}

resource "azurerm_api_management_subscription" "gamma" {
  api_management_name = var.apim_name
  resource_group_name = var.resource_group_name
  product_id          = azurerm_api_management_product.gamma.id
  display_name        = "Team Gamma Subscription"
  state               = "active"
}

# --- Product Policies (rate-limit-by-key as bootstrap) ---
# These get upgraded to llm-token-limit by the post-deploy script
# after the Foundry API is imported via portal (which enables llm-* policies).

resource "azurerm_api_management_product_policy" "alpha" {
  product_id          = azurerm_api_management_product.alpha.product_id
  api_management_name = var.apim_name
  resource_group_name = var.resource_group_name
  xml_content         = file("${path.module}/policies/product-alpha.xml")
}

resource "azurerm_api_management_product_policy" "beta" {
  product_id          = azurerm_api_management_product.beta.product_id
  api_management_name = var.apim_name
  resource_group_name = var.resource_group_name
  xml_content         = file("${path.module}/policies/product-beta.xml")
}

resource "azurerm_api_management_product_policy" "gamma" {
  product_id          = azurerm_api_management_product.gamma.product_id
  api_management_name = var.apim_name
  resource_group_name = var.resource_group_name
  xml_content         = file("${path.module}/policies/product-gamma.xml")
}
