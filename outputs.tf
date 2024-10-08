output "id" {
  value = azurerm_mssql_server.mssql.id
}

output "name" {
  value = azurerm_mssql_server.mssql.name
}

output "identity_tenant_id" {
  value = azurerm_mssql_server.mssql.identity[0].tenant_id
}

output "identity_object_id" {
  value = azurerm_mssql_server.mssql.identity[0].principal_id
}

output "sa_primary_blob_endpoint" {
  value = var.express_va_enabled == false ? azurerm_mssql_server_extended_auditing_policy.this[0].storage_endpoint : null
}

output "sa_primary_access_key" {
  value = var.kv_enable ? null : azurerm_mssql_server_extended_auditing_policy.this[0].storage_account_access_key
}

output "assessment_id" {
  value = var.express_va_enabled == false ? azurerm_mssql_server_vulnerability_assessment.this[0].id : null
}

output "firewall" {
  value = azurerm_mssql_firewall_rule.mssql
}
