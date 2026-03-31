resource "azurerm_resource_group" "main" {
  name     = var.resource_group_name
  location = var.location_primary
  tags     = var.tags
}

resource "random_string" "suffix" {
  count   = var.use_random_suffix ? 1 : 0
  length  = 4
  special = false
  upper   = false
}

locals {
  suffix    = var.use_random_suffix ? random_string.suffix[0].result : ""
  apim_name = var.apim_name != null ? var.apim_name : "${var.prefix}-apim-${local.suffix}"
  # Foundry suffixes include region + random to avoid soft-delete name collisions
  foundry_suffix_eus2 = var.use_random_suffix ? "eus2-${local.suffix}" : "eus2"
  foundry_suffix_swc  = var.use_random_suffix ? "swc-${local.suffix}" : "swc"
}

# Phase 1: Identity
module "identity" {
  source              = "./modules/identity"
  resource_group_name = azurerm_resource_group.main.name
  location            = azurerm_resource_group.main.location
  prefix              = var.prefix
  tags                = var.tags
}

# Phase 1: Monitoring
module "monitoring" {
  source              = "./modules/monitoring"
  resource_group_name = azurerm_resource_group.main.name
  location            = azurerm_resource_group.main.location
  prefix              = var.prefix
  tags                = var.tags
}

# Phase 1: Foundry - East US 2 (primary)
module "foundry_primary" {
  source                            = "./modules/foundry"
  resource_group_name               = azurerm_resource_group.main.name
  location                          = var.location_primary
  prefix                            = var.prefix
  suffix                            = local.foundry_suffix_eus2
  identity_id                       = module.identity.user_assigned_identity_id
  identity_principal_id             = module.identity.user_assigned_identity_principal_id
  apim_system_identity_principal_id = module.apim.system_assigned_identity_principal_id
  tags                              = var.tags
}

# Phase 1: Foundry - Sweden Central (failover)
module "foundry_secondary" {
  source                            = "./modules/foundry"
  resource_group_name               = azurerm_resource_group.main.name
  location                          = var.location_secondary
  prefix                            = var.prefix
  suffix                            = local.foundry_suffix_swc
  identity_id                       = module.identity.user_assigned_identity_id
  identity_principal_id             = module.identity.user_assigned_identity_principal_id
  apim_system_identity_principal_id = module.apim.system_assigned_identity_principal_id
  tags                              = var.tags
}

# Phase 1: APIM
module "apim" {
  source                     = "./modules/apim"
  resource_group_name        = azurerm_resource_group.main.name
  location                   = azurerm_resource_group.main.location
  apim_name                  = local.apim_name
  prefix                     = var.prefix
  user_assigned_identity_id  = module.identity.user_assigned_identity_id
  log_analytics_workspace_id = module.monitoring.log_analytics_workspace_id
  app_insights_id            = module.monitoring.app_insights_id
  app_insights_key           = module.monitoring.app_insights_instrumentation_key
  tags                       = var.tags
}

# Phase 2: APIM Configuration (backends, pool, products, subscriptions)
module "apim_config" {
  source                         = "./modules/apim-config"
  resource_group_name            = azurerm_resource_group.main.name
  apim_name                      = module.apim.apim_name
  apim_id                        = module.apim.apim_id
  foundry_primary_endpoint       = module.foundry_primary.endpoint
  foundry_secondary_endpoint     = module.foundry_secondary.endpoint
  foundry_primary_id             = module.foundry_primary.account_id
  foundry_secondary_id           = module.foundry_secondary.account_id
  user_assigned_identity_id      = module.identity.user_assigned_identity_id
  apim_system_identity_principal = module.apim.system_assigned_identity_principal_id
  prefix                         = var.prefix
  tags                           = var.tags
  enable_mcp_demo                = var.enable_mcp_demo
  mcp_server_url                 = var.mcp_server_url
}

# Phase 3: API Center (unified tool discovery catalog)
# API Center isn't available in all regions — use api_center_location variable
module "api_center" {
  source              = "./modules/api-center"
  resource_group_name = azurerm_resource_group.main.name
  location            = var.api_center_location
  prefix              = var.prefix
  suffix              = local.suffix
  apim_id             = module.apim.apim_id
  tags                = var.tags
}
