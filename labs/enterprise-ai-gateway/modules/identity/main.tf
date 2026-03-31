resource "azurerm_user_assigned_identity" "apim" {
  name                = "${var.prefix}-identity"
  resource_group_name = var.resource_group_name
  location            = var.location
  tags                = var.tags
}
