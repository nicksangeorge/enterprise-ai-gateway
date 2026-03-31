output "apim_id" {
  value = azurerm_api_management.main.id
}

output "apim_name" {
  value = azurerm_api_management.main.name
}

output "gateway_url" {
  value = azurerm_api_management.main.gateway_url
}

output "system_assigned_identity_principal_id" {
  value = azurerm_api_management.main.identity[0].principal_id
}
