output "user_assigned_identity_id" {
  value = azurerm_user_assigned_identity.apim.id
}

output "user_assigned_identity_principal_id" {
  value = azurerm_user_assigned_identity.apim.principal_id
}

output "user_assigned_identity_client_id" {
  value = azurerm_user_assigned_identity.apim.client_id
}
