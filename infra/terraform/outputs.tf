output "resource_group_name" {
  value = azurerm_resource_group.main.name
}

output "apim_gateway_url" {
  value = module.apim.gateway_url
}

output "apim_name" {
  value = module.apim.apim_name
}

output "foundry_primary_endpoint" {
  value = module.foundry_primary.endpoint
}

output "foundry_secondary_endpoint" {
  value = module.foundry_secondary.endpoint
}

output "app_insights_connection_string" {
  value     = module.monitoring.app_insights_connection_string
  sensitive = true
}

output "team_alpha_subscription_key" {
  value     = module.apim_config.team_alpha_key
  sensitive = true
}

output "team_beta_subscription_key" {
  value     = module.apim_config.team_beta_key
  sensitive = true
}

output "team_gamma_subscription_key" {
  value     = module.apim_config.team_gamma_key
  sensitive = true
}

output "backend_pool_name" {
  value = module.apim_config.backend_pool_name
}

output "mcp_demo_subscription_key" {
  value     = try(module.apim_config.mcp_demo_subscription_key, null)
  sensitive = true
}
