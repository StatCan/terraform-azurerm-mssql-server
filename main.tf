resource "azurerm_mssql_server" "mssql" {
  name                = var.name
  location            = var.location
  resource_group_name = var.resource_group_name

  administrator_login          = var.administrator_login
  administrator_login_password = length(data.azurerm_key_vault_secret.sqlhstsvc) > 0 ? data.azurerm_key_vault_secret.sqlhstsvc[0].value : var.administrator_login_password

  version = var.mssql_version

  minimum_tls_version = var.ssl_minimal_tls_version_enforced

  connection_policy = var.connection_policy

  azuread_administrator {
    login_username = var.active_directory_administrator_login_username
    object_id      = var.active_directory_administrator_object_id
    tenant_id      = var.active_directory_administrator_tenant_id
  }

  identity {
    type = "SystemAssigned"
  }

  lifecycle {
    ignore_changes = [
      tags
    ]
  }
}


resource "azurerm_mssql_firewall_rule" "AllowAzure" {
  name             = "AllowAzureInternal"
  server_id        = azurerm_mssql_server.mssql.id
  start_ip_address = "0.0.0.0"
  end_ip_address   = "0.0.0.0"
}


resource "azurerm_mssql_firewall_rule" "mssql" {
  count = length(var.firewall_rules)

  name             = azurerm_mssql_server.mssql.name
  server_id        = azurerm_mssql_server.mssql.id
  start_ip_address = var.firewall_rules[count.index]
  end_ip_address   = var.firewall_rules[count.index]
}

resource "azurerm_mssql_virtual_network_rule" "this" {
  for_each = toset(var.subnets)

  name      = split("/", each.value)[10]
  server_id = azurerm_mssql_server.mssql.id
  subnet_id = each.value
}

resource "azurerm_role_assignment" "this" {
  count = var.express_va_enabled == true ? 0 : 1

  description          = "${azurerm_mssql_server.mssql.name}-ra"
  scope                = data.azurerm_storage_account.storageaccountinfo[0].id
  role_definition_name = "Storage Blob Data Contributor"
  principal_id         = azurerm_mssql_server.mssql.identity.0.principal_id

  depends_on = [
    azurerm_mssql_server.mssql,
    azurerm_mssql_firewall_rule.mssql
  ]
}

resource "azurerm_role_assignment" "mi" {
  count                = var.primary_mi_id == null ? 0 : (var.express_va_enabled == true ? 1 : 0)
  description          = "${azurerm_mssql_server.mssql.name}-ura"
  scope                = data.azurerm_storage_account.storageaccountinfo[0].id
  role_definition_name = "Storage Blob Data Contributor"
  principal_id         = var.primary_mi_id

  depends_on = [
    azurerm_mssql_server.mssql,
    azurerm_mssql_firewall_rule.mssql
  ]
}


resource "azurerm_mssql_server_security_alert_policy" "this" {
  count = var.express_va_enabled == true ? 0 : 1

  server_name         = azurerm_mssql_server.mssql.name
  resource_group_name = var.resource_group_name

  storage_endpoint           = var.kv_enable ? null : azurerm_storage_account.this[0].primary_blob_endpoint
  storage_account_access_key = var.kv_enable ? null : azurerm_storage_account.this[0].primary_access_key

  state          = "Enabled"
  retention_days = var.retention_days

  email_addresses = var.emails

  depends_on = [
    azurerm_role_assignment.this,
    azurerm_role_assignment.mi
  ]
}

resource "azurerm_mssql_server_extended_auditing_policy" "this" {
  count = var.express_va_enabled == true ? 0 : 1

  server_id = azurerm_mssql_server.mssql.id

  storage_endpoint           = var.kv_enable ? data.azurerm_storage_account.storageaccountinfo[0].primary_blob_endpoint : azurerm_storage_account.this[0].primary_blob_endpoint
  storage_account_access_key = var.kv_enable ? null : azurerm_storage_account.this[0].primary_access_key

  retention_in_days      = var.retention_days
  log_monitoring_enabled = true

  depends_on = [
    azurerm_role_assignment.this,
    azurerm_role_assignment.mi,
    azurerm_mssql_server_security_alert_policy.this
  ]
}
resource "azurerm_mssql_server_vulnerability_assessment" "this" {
  count = var.express_va_enabled == true ? 0 : 1

  server_security_alert_policy_id = azurerm_mssql_server_security_alert_policy.this[0].id

  storage_container_path     = var.kv_enable ? "${data.azurerm_storage_account.storageaccountinfo[0].primary_blob_endpoint}vulnerability-assessment/" : "${azurerm_storage_account.this[0].primary_blob_endpoint}${azurerm_storage_container.this[0].name}/"
  storage_account_access_key = var.kv_enable ? null : azurerm_storage_account.this[0].primary_access_key

  recurring_scans {
    enabled                   = true
    email_subscription_admins = true
    emails                    = var.emails
  }

  depends_on = [
    azurerm_role_assignment.this,
    azurerm_role_assignment.mi,
    azurerm_mssql_server_security_alert_policy.this
  ]

}

resource "azurerm_private_endpoint" "this" {
  for_each = var.private_endpoints

  name                = each.key
  location            = var.location
  resource_group_name = var.resource_group_name
  subnet_id           = lookup(each.value, "subnet_id", "")

  private_service_connection {
    name                           = "${each.key}-privateserviceconnection"
    private_connection_resource_id = azurerm_mssql_server.mssql.id
    is_manual_connection           = false
    subresource_names              = ["sqlServer"]
  }

  private_dns_zone_group {
    name                 = "default"
    private_dns_zone_ids = lookup(each.value, "private_dns_zone_ids", [])
  }

  depends_on = [
    azurerm_mssql_server.mssql
  ]

}