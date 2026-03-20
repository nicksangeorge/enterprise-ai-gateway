output "team_alpha_key" {
  value     = azurerm_api_management_subscription.alpha.primary_key
  sensitive = true
}

output "team_beta_key" {
  value     = azurerm_api_management_subscription.beta.primary_key
  sensitive = true
}

output "team_gamma_key" {
  value     = azurerm_api_management_subscription.gamma.primary_key
  sensitive = true
}

output "backend_pool_name" {
  value = azapi_resource.foundry_pool.name
}

output "backend_primary_id" {
  value = azapi_resource.backend_primary.id
}

output "backend_secondary_id" {
  value = azapi_resource.backend_secondary.id
}
