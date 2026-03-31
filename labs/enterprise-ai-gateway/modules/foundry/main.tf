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

resource "azurerm_cognitive_account" "foundry" {
  name                       = "${var.prefix}-foundry-${var.suffix}"
  resource_group_name        = var.resource_group_name
  location                   = var.location
  kind                       = "AIServices"
  sku_name                   = "S0"
  custom_subdomain_name      = "${var.prefix}-foundry-${var.suffix}"
  project_management_enabled = true

  identity {
    type = "SystemAssigned"
  }

  tags = var.tags
}

# Default project — required for Foundry portal experiences (model catalog, agents, etc.)
resource "azurerm_cognitive_account_project" "default" {
  name                 = "${var.prefix}-project-${var.suffix}"
  cognitive_account_id = azurerm_cognitive_account.foundry.id
  location             = var.location

  identity {
    type = "SystemAssigned"
  }

  tags = var.tags
}

# Grant the APIM user-assigned managed identity access to this Foundry resource
resource "azurerm_role_assignment" "apim_cognitive_user" {
  scope                = azurerm_cognitive_account.foundry.id
  role_definition_name = "Cognitive Services OpenAI User"
  principal_id         = var.identity_principal_id
}

# Grant the APIM system-assigned identity access (used by portal-imported Foundry API)
resource "azurerm_role_assignment" "apim_system_cognitive_user" {
  scope                = azurerm_cognitive_account.foundry.id
  role_definition_name = "Cognitive Services OpenAI User"
  principal_id         = var.apim_system_identity_principal_id
}

# Model Router — intelligent routing across 20+ underlying models
resource "azurerm_cognitive_deployment" "model_router" {
  name                 = "model-router"
  cognitive_account_id = azurerm_cognitive_account.foundry.id

  model {
    format  = "OpenAI"
    name    = "model-router"
    version = "2025-11-18"
  }

  sku {
    name     = "GlobalStandard"
    capacity = 30
  }
}

# GPT-5.1 — current-gen reasoning model for production use
# depends_on model_router to avoid concurrent deployment conflicts on the same account
resource "azurerm_cognitive_deployment" "gpt_51" {
  name                 = "gpt-51"
  cognitive_account_id = azurerm_cognitive_account.foundry.id

  model {
    format  = "OpenAI"
    name    = "gpt-5.1"
    version = "2025-11-13"
  }

  sku {
    name     = "GlobalStandard"
    capacity = 30
  }

  depends_on = [azurerm_cognitive_deployment.model_router]
}

# Kimi-K2.5 (Moonshot AI) — multi-provider story
# Can't be deployed via Terraform: azurerm_cognitive_deployment only supports
# format="OpenAI", and the azapi format string for Moonshot AI models isn't
# documented. Kimi-K2.5 IS in the Foundry model catalog (confirmed Feb 2026).
#
# Deploy manually via the Foundry portal:
# 1. Go to ai.azure.com > Model catalog > search "Kimi-K2.5"
# 2. Select Deploy > Global Standard
# 3. Deploy to both aigw-foundry-eus2 and aigw-foundry-swc accounts
# 4. Use deployment name "kimi-k25" to match the demo scripts
