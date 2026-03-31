resource "azurerm_api_management" "main" {
  name                = var.apim_name
  resource_group_name = var.resource_group_name
  location            = var.location
  publisher_name      = "AI Gateway Demo"
  publisher_email     = "admin@contoso.com"
  sku_name            = "StandardV2_1"

  identity {
    type         = "SystemAssigned, UserAssigned"
    identity_ids = [var.user_assigned_identity_id]
  }

  tags = var.tags
}

# Application Insights logger for token metrics
resource "azurerm_api_management_logger" "app_insights" {
  name                = "app-insights-logger"
  api_management_name = azurerm_api_management.main.name
  resource_group_name = var.resource_group_name
  resource_id         = var.app_insights_id

  application_insights {
    instrumentation_key = var.app_insights_key
  }
}

# Diagnostic setting: Dedicated mode sends logs to resource-specific tables
# (ApiManagementGatewayLogs, ApiManagementGatewayLlmLog) instead of generic AzureDiagnostics
resource "azurerm_monitor_diagnostic_setting" "apim_logs" {
  name                           = "apim-all-logs"
  target_resource_id             = azurerm_api_management.main.id
  log_analytics_workspace_id     = var.log_analytics_workspace_id
  log_analytics_destination_type = "Dedicated"

  enabled_log { category = "GatewayLogs" }
  enabled_log { category = "GatewayLlmLogs" }

  enabled_metric { category = "AllMetrics" }
}
